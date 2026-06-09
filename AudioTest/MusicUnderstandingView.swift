//
//  MusicUnderstandingView.swift
//  AudioTest
//
//  Analyzes the bundled track with Apple's MusicUnderstanding framework and
//  presents the results in a visualizer styled to match the AudioKit Test view.
//  Unlike the AudioKit meters (which react live to playback), MusicUnderstanding
//  performs a single file-based analysis pass over the whole song.
//

import AVFoundation
import MusicUnderstanding
import Observation
import SwiftUI

@available(iOS 27.0, *)
@MainActor
@Observable
final class MusicUnderstandingManager {
    enum Status: Equatable {
        case idle
        case analyzing
        case finished
        case failed(String)
    }

    var status: Status = .idle

    // Rhythm
    var bpm: Float?
    var beatCount: Int = 0
    var barCount: Int = 0

    // Key
    var keyDescription: String?

    // Loudness
    var integratedLUFS: Float?
    var peakDB: Float?
    var loudnessValue: Float = 0

    // Pace
    var averagePace: Double?
    var paceValue: Float = 0

    // Structure
    var sectionCount: Int = 0
    var segmentCount: Int = 0
    var phraseCount: Int = 0

    // Instrument activity (average level across the song, 0...1)
    var vocalActivity: Float = 0
    var drumActivity: Float = 0
    var bassActivity: Float = 0
    var otherActivity: Float = 0

    // Live playback levels, sampled from the analyzed data at the current play head.
    var isPlaying: Bool = false
    var liveLoudnessValue: Float = 0
    var liveLoudnessLUFS: Float?
    var liveVocal: Float = 0
    var liveDrum: Float = 0
    var liveBass: Float = 0
    var liveOther: Float = 0

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var audioPlayer: AVAudioPlayer?
    @ObservationIgnored private var playbackTask: Task<Void, Never>?

    // Time-stamped analysis data (seconds, value) used to drive the live meters.
    @ObservationIgnored private var loudnessSamples: [(time: Double, value: Float)] = []
    @ObservationIgnored private var vocalSamples: [(time: Double, value: Float)] = []
    @ObservationIgnored private var drumSamples: [(time: Double, value: Float)] = []
    @ObservationIgnored private var bassSamples: [(time: Double, value: Float)] = []
    @ObservationIgnored private var otherSamples: [(time: Double, value: Float)] = []

    private let audioURL = Bundle.main.url(
        forResource: "melodic-rampb-soul-394784",
        withExtension: "mp3"
    )

    func analyze() {
        guard status != .analyzing else { return }

        guard let url = audioURL else {
            status = .failed("Audio file not found in bundle")
            return
        }

        status = .analyzing
        task = Task { [weak self] in
            do {
                let asset = AVURLAsset(url: url)
                let session = try await MusicUnderstandingSession(asset: asset)
                let result = try await session.analyze()
                guard !Task.isCancelled else { return }
                self?.apply(result)
                self?.status = .finished
            } catch is CancellationError {
                // Ignore cancellation triggered by leaving the view.
            } catch {
                self?.status = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        stopPlayback()
    }

    // MARK: - Playback

    func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    func startPlayback() {
        guard status == .finished, let url = audioURL else { return }
        do {
            if audioPlayer == nil {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
                let player = try AVAudioPlayer(contentsOf: url)
                player.numberOfLoops = -1
                player.prepareToPlay()
                audioPlayer = player
            }
            audioPlayer?.play()
            isPlaying = true
            startLiveUpdates()
        } catch {
            status = .failed("Playback error: \(error.localizedDescription)")
        }
    }

    func stopPlayback() {
        audioPlayer?.pause()
        audioPlayer?.currentTime = 0
        isPlaying = false
        playbackTask?.cancel()
        playbackTask = nil
        liveLoudnessValue = 0
        liveLoudnessLUFS = nil
        liveVocal = 0
        liveDrum = 0
        liveBass = 0
        liveOther = 0
    }

    private func startLiveUpdates() {
        playbackTask?.cancel()
        playbackTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let player = self.audioPlayer, player.isPlaying else { break }
                self.updateLiveValues(at: player.currentTime)
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func updateLiveValues(at time: Double) {
        if let lufs = Self.value(in: loudnessSamples, at: time) {
            liveLoudnessLUFS = lufs
            liveLoudnessValue = Self.normalize(lufs, min: -40, max: 0)
        }
        liveVocal = Self.value(in: vocalSamples, at: time) ?? 0
        liveDrum = Self.value(in: drumSamples, at: time) ?? 0
        liveBass = Self.value(in: bassSamples, at: time) ?? 0
        liveOther = Self.value(in: otherSamples, at: time) ?? 0
    }

    /// Returns the value of the most recent sample at or before `time` (samples are sorted by time).
    private static func value(in samples: [(time: Double, value: Float)], at time: Double) -> Float? {
        guard !samples.isEmpty else { return nil }
        var low = 0
        var high = samples.count - 1
        var index = 0
        while low <= high {
            let mid = (low + high) / 2
            if samples[mid].time <= time {
                index = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return samples[index].value
    }

    private func apply(_ result: MusicUnderstandingSession.SessionResult) {
        if let rhythm = result.rhythm {
            bpm = rhythm.beatsPerMinute
            beatCount = rhythm.beats.count
            barCount = rhythm.bars.count
        }

        if let key = result.key, let first = key.ranges.first {
            let signature = first.value
            keyDescription = "\(Self.prettify(signature.tonic)) \(Self.prettify(signature.mode))"
        }

        if let loudness = result.loudness {
            integratedLUFS = loudness.integrated.value
            peakDB = loudness.peak.value
            // LUFS is negative; map a typical -40...0 range onto 0...1 for the bar.
            loudnessValue = Self.normalize(loudness.integrated.value, min: -40, max: 0)
            // Momentary loudness drives the live meter during playback.
            loudnessSamples = loudness.momentary.map { (CMTimeGetSeconds($0.time), $0.value) }
        }

        if let pace = result.pace, !pace.ranges.isEmpty {
            let values = pace.ranges.map { $0.value }
            let average = values.reduce(0, +) / Double(values.count)
            averagePace = average
            // Normalize each section against the song's own peak energy.
            if let maximum = values.max(), maximum > 0 {
                paceValue = Float(average / maximum)
            }
        }

        if let structure = result.structure {
            sectionCount = structure.sections.count
            segmentCount = structure.segments.count
            phraseCount = structure.phrases.count
        }

        if let instruments = result.instrumentActivity {
            vocalActivity = Self.averageActivity(instruments, .vocal)
            drumActivity = Self.averageActivity(instruments, .drum)
            bassActivity = Self.averageActivity(instruments, .bass)
            otherActivity = Self.averageActivity(instruments, .other)
            // Per-instrument activity over time drives the live meters during playback.
            vocalSamples = Self.timedSamples(instruments, .vocal)
            drumSamples = Self.timedSamples(instruments, .drum)
            bassSamples = Self.timedSamples(instruments, .bass)
            otherSamples = Self.timedSamples(instruments, .other)
        }
    }

    private static func averageActivity(
        _ result: InstrumentActivityResult,
        _ instrument: InstrumentActivityResult.Instrument
    ) -> Float {
        guard let samples = result.activity[instrument], !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float(0)) { $0 + $1.value }
        return min(max(sum / Float(samples.count), 0), 1)
    }

    private static func timedSamples(
        _ result: InstrumentActivityResult,
        _ instrument: InstrumentActivityResult.Instrument
    ) -> [(time: Double, value: Float)] {
        (result.activity[instrument] ?? []).map { (CMTimeGetSeconds($0.time), $0.value) }
    }

    private static func normalize(_ value: Float, min lower: Float, max upper: Float) -> Float {
        guard upper > lower else { return 0 }
        return Swift.min(Swift.max((value - lower) / (upper - lower), 0), 1)
    }

    /// Turns an enum case label (e.g. "cSharp", "major") into display text ("C Sharp", "Major").
    private static func prettify<T>(_ value: T) -> String {
        let raw = String(describing: value)
        var words: [String] = []
        var current = ""
        for character in raw {
            if character.isUppercase, !current.isEmpty {
                words.append(current)
                current = String(character)
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

@available(iOS 27.0, *)
struct MusicUnderstandingView: View {
    @State private var analyzer = MusicUnderstandingManager()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.04, blue: 0.10),
                    Color(red: 0.12, green: 0.06, blue: 0.20)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Text("Music Understanding")
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .padding(.top, 12)

                switch analyzer.status {
                case .idle:
                    placeholder(
                        icon: "waveform.and.magnifyingglass",
                        message: "Run an offline analysis of the bundled track using Apple's MusicUnderstanding framework."
                    )
                case .analyzing:
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                        Text("Analyzing track…")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .frame(maxHeight: .infinity)
                case .failed(let message):
                    placeholder(icon: "exclamationmark.triangle.fill", message: message, tint: .red)
                case .finished:
                    results
                }

                Spacer(minLength: 0)

                if analyzer.status == .finished {
                    Button(action: analyzer.togglePlayback) {
                        capsuleLabel(
                            icon: analyzer.isPlaying ? "stop.fill" : "play.fill",
                            title: analyzer.isPlaying ? "Stop" : "Play",
                            color: analyzer.isPlaying ? .red : .green
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)

                    Button(action: runAnalysis) {
                        Text("Re-Analyze")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 12)
                } else {
                    Button(action: runAnalysis) {
                        capsuleLabel(
                            icon: analyzer.status == .analyzing ? "hourglass" : "waveform.badge.magnifyingglass",
                            title: buttonTitle,
                            color: .purple
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(analyzer.status == .analyzing)
                    .opacity(analyzer.status == .analyzing ? 0.6 : 1)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                }
            }
        }
        .navigationTitle("Music Understanding")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            if analyzer.status == .idle { analyzer.analyze() }
        }
        .onDisappear { analyzer.cancel() }
    }

    private var buttonTitle: String {
        switch analyzer.status {
        case .analyzing: return "Analyzing…"
        case .finished, .failed: return "Re-Analyze"
        case .idle: return "Analyze"
        }
    }

    private func runAnalysis() {
        analyzer.cancel()
        analyzer.status = .idle
        analyzer.analyze()
    }

    private func capsuleLabel(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .bold))
            Text(title)
                .font(.title3.bold())
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            Capsule()
                .fill(color.opacity(0.8))
                .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 1.5))
        )
        .shadow(color: color.opacity(0.5), radius: 14)
    }

    private func placeholder(icon: String, message: String, tint: Color = .white) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(tint.opacity(0.8))
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 32)
        }
        .frame(maxHeight: .infinity)
    }

    private var results: some View {
        ScrollView {
            VStack(spacing: 14) {
                InfoRow(
                    label: "Tempo",
                    value: analyzer.bpm.map { String(format: "%.0f BPM", $0) } ?? "—",
                    color: .pink
                )
                InfoRow(label: "Key", value: analyzer.keyDescription ?? "—", color: .mint)
                InfoRow(label: "Beats / Bars", value: "\(analyzer.beatCount) / \(analyzer.barCount)", color: .cyan)
                InfoRow(
                    label: "Structure (Sec/Seg/Phr)",
                    value: "\(analyzer.sectionCount) / \(analyzer.segmentCount) / \(analyzer.phraseCount)",
                    color: .teal
                )

                FrequencyBar(
                    label: analyzer.isPlaying ? "Loudness (live)" : "Loudness (integrated)",
                    value: analyzer.isPlaying ? analyzer.liveLoudnessValue : analyzer.loudnessValue,
                    color: .yellow,
                    trailingText: (analyzer.isPlaying ? analyzer.liveLoudnessLUFS : analyzer.integratedLUFS)
                        .map { String(format: "%.1f LUFS", $0) }
                )
                FrequencyBar(
                    label: "Pace (energy)",
                    value: analyzer.paceValue,
                    color: .orange,
                    trailingText: analyzer.averagePace.map { String(format: "%.0f epm", $0) }
                )

                Text(analyzer.isPlaying ? "Instrument Activity (live)" : "Instrument Activity (avg)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)

                FrequencyBar(label: "Vocals", value: analyzer.isPlaying ? analyzer.liveVocal : analyzer.vocalActivity, color: .purple)
                FrequencyBar(label: "Drums", value: analyzer.isPlaying ? analyzer.liveDrum : analyzer.drumActivity, color: .red)
                FrequencyBar(label: "Bass", value: analyzer.isPlaying ? analyzer.liveBass : analyzer.bassActivity, color: .blue)
                FrequencyBar(label: "Other", value: analyzer.isPlaying ? analyzer.liveOther : analyzer.otherActivity, color: .green)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Circle()
                .fill(color.gradient)
                .frame(width: 10, height: 10)
                .shadow(color: color.opacity(0.8), radius: 6)
            Text(label)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
            Spacer()
            Text(value)
                .font(.callout.monospacedDigit().bold())
                .foregroundStyle(.white)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.06))
        )
    }
}

#Preview {
    if #available(iOS 27.0, *) {
        NavigationStack {
            MusicUnderstandingView()
        }
    } else {
        Text("Requires iOS 27")
    }
}
