//
//  AudioManager.swift
//  AudioTest
//

import AudioKit
import SoundpipeAudioKit
import AVFoundation
import Foundation
import MediaPlayer
import Observation

@MainActor
@Observable
final class AudioManager {
    // Which engine is currently driving playback.
    enum Source { case engine, system }

    @ObservationIgnored private let engine = AudioEngine()
    @ObservationIgnored private let player = AudioPlayer()
    @ObservationIgnored private let systemPlayer = MPMusicPlayerController.applicationMusicPlayer
    @ObservationIgnored private var source: Source = .engine
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
    // Log-binned magnitude spectrum (current column), 0...1 per band.
    var spectrum: [Float] = Array(repeating: 0, count: 48)
    // Rolling history of spectrum columns for the scrolling spectrogram (oldest first).
    var spectrogram: [[Float]] = []
    // Rolling buffer of recent raw samples for the scrolling waveform tape.
    var scrollingWaveform: [Float] = []
    var isPlaying: Bool = false
    var errorMessage: String?
    // Title of the current track shown in the Music tab.
    var nowPlayingTitle: String = "Default Song"
    // False when the current track plays through the system music player
    // (DRM Apple Music streaming), which AudioKit cannot tap — visuals stay idle.
    var isReactive: Bool = true

    private let bufferSize: UInt32 = 4096
    private let waveformBufferSize: UInt32 = 1024
    private let smoothing: Float = 0.55
    private let pitchSmoothing: Float = 0.7
    private let waveformPoints: Int = 96

    private let spectrumBands: Int = 48
    private let spectrumMinHz: Float = 30
    private let spectrumMaxHz: Float = 16_000
    private let spectrogramColumns: Int = 120
    private let scrollingWaveformSamples: Int = 900

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
        } catch {
            errorMessage = "Audio setup error: \(error.localizedDescription)"
        }
    }

    func start() {
        guard !isPlaying else { return }
        switch source {
        case .engine: player.play()
        case .system: systemPlayer.play()
        }
        isPlaying = true
    }

    func stop() {
        guard isPlaying else { return }
        switch source {
        case .engine: player.stop()
        case .system: systemPlayer.pause()
        }
        clearAnalysis()
        isPlaying = false
    }

    func togglePlay() {
        if isPlaying {
            stop()
        } else {
            start()
        }
    }

    /// Play a song chosen from the Apple Music / library picker. If the item has
    /// accessible audio (downloaded/local/non-DRM), it plays through AudioKit so
    /// the visualizers react; otherwise it falls back to the system music player.
    func play(mediaItem item: MPMediaItem) {
        nowPlayingTitle = item.title ?? "Unknown Track"

        // Stop whatever is currently playing on either engine.
        player.stop()
        systemPlayer.stop()
        clearAnalysis()

        if let url = item.assetURL {
            do {
                try player.load(url: url)
                player.isLooping = false
                player.play()
                source = .engine
                isReactive = true
                isPlaying = true
            } catch {
                errorMessage = "Couldn't load track: \(error.localizedDescription)"
                isPlaying = false
            }
        } else {
            // DRM-protected Apple Music stream: no audio taps available.
            systemPlayer.setQueue(with: MPMediaItemCollection(items: [item]))
            systemPlayer.play()
            source = .system
            isReactive = false
            isPlaying = true
        }
    }

    private func clearAnalysis() {
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
        spectrum = Array(repeating: 0, count: spectrumBands)
        spectrogram = []
        scrollingWaveform = []
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

        // Append this block to the scrolling-waveform tape and trim to the window.
        var tape = scrollingWaveform
        tape.append(contentsOf: sampled)
        if tape.count > scrollingWaveformSamples {
            tape.removeFirst(tape.count - scrollingWaveformSamples)
        }
        scrollingWaveform = tape
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

        // Log-binned spectrum for the spectrogram / debug views.
        let logMin = log2(spectrumMinHz)
        let logMax = log2(spectrumMaxHz)
        var column = spectrum
        for b in 0..<spectrumBands {
            let f0 = pow(2, logMin + (logMax - logMin) * Float(b) / Float(spectrumBands))
            let f1 = pow(2, logMin + (logMax - logMin) * Float(b + 1) / Float(spectrumBands))
            let startBin = max(1, Int(f0 / binWidth))
            let endBin = min(binCount - 1, max(startBin + 1, Int(f1 / binWidth)))
            var sum: Float = 0
            for i in startBin..<endBin {
                sum += sqrt(max(fftData[i], 0))
            }
            let avg = sum / Float(endBin - startBin)
            // Higher bands carry less energy per bin, so ramp the gain with frequency.
            let gain = 40 + 150 * Float(b) / Float(spectrumBands)
            let level = min(avg * gain, 1)
            // Lighter smoothing than the bands so the spectrogram stays responsive.
            column[b] = column[b] * 0.4 + level * 0.6
        }
        spectrum = column

        var history = spectrogram
        history.append(column)
        if history.count > spectrogramColumns {
            history.removeFirst(history.count - spectrogramColumns)
        }
        spectrogram = history

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
