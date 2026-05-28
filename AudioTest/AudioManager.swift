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
    @ObservationIgnored private var fftTap: FFTTap?
    @ObservationIgnored private var sampleRate: Float = 44_100

    var bass: Float = 0
    var mid: Float = 0
    var treble: Float = 0
    var isPlaying: Bool = false
    var errorMessage: String?

    private let bufferSize: UInt32 = 4096
    private let smoothing: Float = 0.55

    init() {
        setup()
    }

    private func setup() {
        engine.output = player

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

            let tap = FFTTap(player, bufferSize: bufferSize) { [weak self] fftData in
                MainActor.assumeIsolated {
                    self?.process(fftData: fftData)
                }
            }
            tap.isNormalized = false
            tap.start()
            fftTap = tap
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
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    private func process(fftData: [Float]) {
        guard !fftData.isEmpty else { return }
        let binWidth = sampleRate / Float(bufferSize)
        let binCount = fftData.count

        func amplitude(low: Float, high: Float) -> Float {
            let startBin = max(1, Int(low / binWidth))
            let endBin = min(binCount - 1, Int(high / binWidth))
            guard startBin < endBin else { return 0 }
            var sum: Float = 0
            for i in startBin..<endBin {
                // vDSP_zvmags produces squared magnitudes; sqrt → real magnitude.
                sum += sqrt(max(fftData[i], 0))
            }
            return sum / Float(endBin - startBin)
        }

        // Per-band gain — treble bins carry less energy per bin in music, so they need a boost.
        let bassLevel = min(amplitude(low: 20, high: 250) * 10, 1)
        let midLevel = min(amplitude(low: 250, high: 4_000) * 200, 1)
        let trebleLevel = min(amplitude(low: 4_000, high: 16_000) * 1000, 1)

        bass = bass * smoothing + bassLevel * (1 - smoothing)
        mid = mid * smoothing + midLevel * (1 - smoothing)
        treble = treble * smoothing + trebleLevel * (1 - smoothing)
    }
}
