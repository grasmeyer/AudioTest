//
//  AudioManager.swift
//  AudioTest
//

import AudioKit
import SoundpipeAudioKit
import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class AudioManager {
    @ObservationIgnored private let engine = AudioEngine()
    @ObservationIgnored private let player = AudioPlayer()
    @ObservationIgnored private let waveformMixer: Mixer
    @ObservationIgnored private let mixer: Mixer
    @ObservationIgnored private let pitchMixer: Mixer
    @ObservationIgnored private var fftTap: FFTTap?
    @ObservationIgnored private var amplitudeTap: AmplitudeTap?
    @ObservationIgnored private var pitchTap: PitchTap?
    @ObservationIgnored private var rawDataTap: RawDataTap?
    @ObservationIgnored private var sampleRate: Float = 44_100
    @ObservationIgnored private var previousMagnitudes: [Float] = []
    @ObservationIgnored private var fluxBaseline: Float = 0

    var bass: Float = 0
    var mid: Float = 0
    var treble: Float = 0
    var amplitude: Float = 0
    var leftAmplitude: Float = 0
    var rightAmplitude: Float = 0
    var pitchValue: Float = 0
    var pitchFrequency: Float = 0
    var brightness: Float = 0
    var centroidHz: Float = 0
    var beatPulse: Float = 0
    var waveform: [Float] = Array(repeating: 0, count: 96)
    var isPlaying: Bool = false
    var errorMessage: String?

    private let bufferSize: UInt32 = 4096
    private let waveformBufferSize: UInt32 = 1024
    private let smoothing: Float = 0.55
    private let pitchSmoothing: Float = 0.7
    private let waveformPoints: Int = 96

    private let pitchMinHz: Float = 80
    private let pitchMaxHz: Float = 1_200
    private let brightnessMinHz: Float = 200
    private let brightnessMaxHz: Float = 6_000

    init() {
        // Each AVAudioNode allows only one tap, so chain Mixers to give every analyzer
        // its own attachment point.
        waveformMixer = Mixer(player)
        mixer = Mixer(waveformMixer)
        pitchMixer = Mixer(mixer)
        setup()
    }

    private func setup() {
        engine.output = pitchMixer

        guard let url = Bundle.main.url(
            forResource: "melodic-rampb-soul-394784",
            withExtension: "mp3"
        ) else {
            errorMessage = "Audio file not found in bundle"
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            try player.load(url: url)
            player.isLooping = true

            try engine.start()

            let format = player.avAudioNode.outputFormat(forBus: 0)
            if format.sampleRate > 0 {
                sampleRate = Float(format.sampleRate)
            }

            let fft = FFTTap(player, bufferSize: bufferSize) { [weak self] fftData in
                MainActor.assumeIsolated {
                    self?.process(fftData: fftData)
                }
            }
            fft.isNormalized = false
            fft.start()
            fftTap = fft

            let raw = RawDataTap(waveformMixer, bufferSize: waveformBufferSize) { [weak self] data in
                MainActor.assumeIsolated {
                    self?.processWaveform(data)
                }
            }
            raw.start()
            rawDataTap = raw

            let amp = AmplitudeTap(
                mixer,
                bufferSize: 1_024,
                stereoMode: .stereo,
                analysisMode: .rms
            ) { [weak self] left, right in
                MainActor.assumeIsolated {
                    self?.processStereoAmplitude(left: left, right: right)
                }
            }
            amp.start()
            amplitudeTap = amp

            let pitch = PitchTap(pitchMixer, bufferSize: bufferSize) { [weak self] pitch, amp in
                MainActor.assumeIsolated {
                    self?.processPitch(pitch: pitch, amplitude: amp)
                }
            }
            pitch.start()
            pitchTap = pitch

            player.play()
            isPlaying = true
        } catch {
            errorMessage = "Audio setup error: \(error.localizedDescription)"
        }
    }

    func togglePlay() {
        if isPlaying {
            player.stop()
            bass = 0
            mid = 0
            treble = 0
            amplitude = 0
            leftAmplitude = 0
            rightAmplitude = 0
            pitchValue = 0
            pitchFrequency = 0
            brightness = 0
            centroidHz = 0
            beatPulse = 0
            waveform = Array(repeating: 0, count: waveformPoints)
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    private func processStereoAmplitude(left: Float, right: Float) {
        let scaledLeft = min(left * 4, 1)
        let scaledRight = min(right * 4, 1)
        leftAmplitude = leftAmplitude * smoothing + scaledLeft * (1 - smoothing)
        rightAmplitude = rightAmplitude * smoothing + scaledRight * (1 - smoothing)
        amplitude = (leftAmplitude + rightAmplitude) / 2
    }

    private func processPitch(pitch: [Float], amplitude: [Float]) {
        guard !pitch.isEmpty else { return }
        let avgPitch = pitch.reduce(0, +) / Float(pitch.count)
        let avgAmp = amplitude.reduce(0, +) / Float(amplitude.count)

        guard avgAmp > 0.01, avgPitch >= pitchMinHz, avgPitch <= pitchMaxHz else { return }

        let logLow = log2(pitchMinHz)
        let logHigh = log2(pitchMaxHz)
        let normalized = (log2(avgPitch) - logLow) / (logHigh - logLow)

        pitchFrequency = pitchFrequency * pitchSmoothing + avgPitch * (1 - pitchSmoothing)
        pitchValue = pitchValue * pitchSmoothing + max(0, min(normalized, 1)) * (1 - pitchSmoothing)
    }

    private func processWaveform(_ data: [Float]) {
        guard !data.isEmpty else { return }
        let step = max(1, data.count / waveformPoints)
        var sampled: [Float] = []
        sampled.reserveCapacity(waveformPoints)
        for i in 0..<waveformPoints {
            let idx = min(i * step, data.count - 1)
            sampled.append(data[idx])
        }
        waveform = sampled
    }

    private func process(fftData: [Float]) {
        guard !fftData.isEmpty else { return }
        let binWidth = sampleRate / Float(bufferSize)
        let binCount = fftData.count

        func amplitudeAvg(low: Float, high: Float) -> Float {
            let startBin = max(1, Int(low / binWidth))
            let endBin = min(binCount - 1, Int(high / binWidth))
            guard startBin < endBin else { return 0 }
            var sum: Float = 0
            for i in startBin..<endBin {
                sum += sqrt(max(fftData[i], 0))
            }
            return sum / Float(endBin - startBin)
        }

        let bassLevel = min(amplitudeAvg(low: 20, high: 250) * 60, 1)
        let midLevel = min(amplitudeAvg(low: 250, high: 4_000) * 90, 1)
        let trebleLevel = min(amplitudeAvg(low: 4_000, high: 16_000) * 180, 1)

        bass = bass * smoothing + bassLevel * (1 - smoothing)
        mid = mid * smoothing + midLevel * (1 - smoothing)
        treble = treble * smoothing + trebleLevel * (1 - smoothing)

        // Spectral centroid — magnitude-weighted average frequency, "brightness".
        var weighted: Float = 0
        var total: Float = 0
        for i in 1..<binCount {
            let mag = sqrt(max(fftData[i], 0))
            weighted += Float(i) * binWidth * mag
            total += mag
        }
        if total > 0 {
            let centroid = weighted / total
            centroidHz = centroidHz * smoothing + centroid * (1 - smoothing)
            let logLow = log2(brightnessMinHz)
            let logHigh = log2(brightnessMaxHz)
            let normalized = (log2(max(centroid, brightnessMinHz)) - logLow) / (logHigh - logLow)
            brightness = brightness * smoothing + max(0, min(normalized, 1)) * (1 - smoothing)
        }

        // Spectral flux — frame-to-frame positive energy increase in the rhythm range.
        // Used as a simple onset / beat detector.
        let fluxLow = max(1, Int(50 / binWidth))
        let fluxHigh = min(binCount - 1, Int(500 / binWidth))
        var flux: Float = 0
        if previousMagnitudes.count == binCount && fluxLow < fluxHigh {
            for i in fluxLow...fluxHigh {
                let cur = sqrt(max(fftData[i], 0))
                let prev = sqrt(max(previousMagnitudes[i], 0))
                flux += max(0, cur - prev)
            }
        }
        previousMagnitudes = fftData

        // Adaptive threshold: spike must exceed running baseline by a margin.
        let triggerRatio: Float = 1.6
        beatPulse = max(beatPulse * 0.78, 0)
        if fluxBaseline > 0, flux > fluxBaseline * triggerRatio {
            beatPulse = 1
        }
        fluxBaseline = fluxBaseline * 0.92 + flux * 0.08
    }
}
