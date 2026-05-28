//
//  AudioManager.swift
//  AudioTest
//

import AudioKit
import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class AudioManager {
    @ObservationIgnored private let engine = AudioEngine()
    @ObservationIgnored private let player = AudioPlayer()
    @ObservationIgnored private let mixer: Mixer
    @ObservationIgnored private var fftTap: FFTTap?
    @ObservationIgnored private var amplitudeTap: AmplitudeTap?
    @ObservationIgnored private var sampleRate: Float = 44_100

    var bass: Float = 0
    var mid: Float = 0
    var treble: Float = 0
    var amplitude: Float = 0
    var pitchValue: Float = 0
    var pitchFrequency: Float = 0
    var isPlaying: Bool = false
    var errorMessage: String?

    private let bufferSize: UInt32 = 4096
    private let smoothing: Float = 0.55
    private let pitchSmoothing: Float = 0.7

    private let pitchMinHz: Float = 80
    private let pitchMaxHz: Float = 1_200

    init() {
        mixer = Mixer(player)
        setup()
    }

    private func setup() {
        engine.output = mixer

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

            // Install AmplitudeTap on the mixer (not the player) — AVAudioNode only allows
            // one tap per node, and FFTTap is already on the player.
            let amp = AmplitudeTap(
                mixer,
                bufferSize: 1_024,
                stereoMode: .center,
                analysisMode: .rms
            ) { [weak self] value in
                MainActor.assumeIsolated {
                    self?.processAmplitude(value)
                }
            }
            amp.start()
            amplitudeTap = amp

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
            pitchValue = 0
            pitchFrequency = 0
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    private func processAmplitude(_ rms: Float) {
        // RMS for music sits around 0.05–0.3; scale to fill the bar.
        let scaled = min(rms * 4, 1)
        amplitude = amplitude * smoothing + scaled * (1 - smoothing)
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

        // Fundamental-pitch estimate: peak bin in the musical range.
        let pitchLow = max(1, Int(pitchMinHz / binWidth))
        let pitchHigh = min(binCount - 1, Int(pitchMaxHz / binWidth))
        if pitchLow < pitchHigh {
            var peakBin = pitchLow
            var peakValue: Float = 0
            for i in pitchLow...pitchHigh where fftData[i] > peakValue {
                peakValue = fftData[i]
                peakBin = i
            }
            // Only update when there's meaningful energy — otherwise the value jitters from noise.
            if peakValue > 0.000005 {
                let detected = Float(peakBin) * binWidth
                let logLow = log2(pitchMinHz)
                let logHigh = log2(pitchMaxHz)
                let normalized = (log2(detected) - logLow) / (logHigh - logLow)
                pitchFrequency = pitchFrequency * pitchSmoothing + detected * (1 - pitchSmoothing)
                pitchValue = pitchValue * pitchSmoothing + max(0, min(normalized, 1)) * (1 - pitchSmoothing)
            }
        }
    }
}
