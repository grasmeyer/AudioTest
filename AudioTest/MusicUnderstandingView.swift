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

    @ObservationIgnored private var task: Task<Void, Never>?

    func analyze() {
        guard status != .analyzing else { return }

        guard let url = Bundle.main.url(
            forResource: "melodic-rampb-soul-394784",
            withExtension: "mp3"
        ) else {
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

                Button(action: runAnalysis) {
                    HStack(spacing: 12) {
                        Image(systemName: analyzer.status == .analyzing ? "hourglass" : "waveform.badge.magnifyingglass")
                            .font(.system(size: 24, weight: .bold))
                        Text(buttonTitle)
                            .font(.title3.bold())
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(Color.purple.opacity(0.8))
                            .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 1.5))
                    )
                    .shadow(color: Color.purple.opacity(0.5), radius: 14)
                }
                .buttonStyle(.plain)
                .disabled(analyzer.status == .analyzing)
                .opacity(analyzer.status == .analyzing ? 0.6 : 1)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
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
                    label: "Loudness",
                    value: analyzer.loudnessValue,
                    color: .yellow,
                    trailingText: analyzer.integratedLUFS.map { String(format: "%.1f LUFS", $0) }
                )
                FrequencyBar(
                    label: "Pace (energy)",
                    value: analyzer.paceValue,
                    color: .orange,
                    trailingText: analyzer.averagePace.map { String(format: "%.0f epm", $0) }
                )

                Text("Instrument Activity")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)

                FrequencyBar(label: "Vocals", value: analyzer.vocalActivity, color: .purple)
                FrequencyBar(label: "Drums", value: analyzer.drumActivity, color: .red)
                FrequencyBar(label: "Bass", value: analyzer.bassActivity, color: .blue)
                FrequencyBar(label: "Other", value: analyzer.otherActivity, color: .green)
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
