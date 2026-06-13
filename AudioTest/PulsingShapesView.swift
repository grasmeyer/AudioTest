//
//  PulsingShapesView.swift
//  AudioTest
//
//  A reactivity test bench: pulsing bass/mid/treble/RMS circles on black,
//  a full-screen beat flash, plus scrolling spectrogram (top) and waveform
//  (bottom) for "is the analysis even working" monitoring.
//

import SwiftUI

struct PulsingShapesView: View {
    @Environment(AudioManager.self) private var audio

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // Scrolling spectrogram across the top.
                VStack {
                    SpectrogramStrip(columns: audio.spectrogram, bandCount: 48)
                        .frame(height: max(90, geo.size.height * 0.16))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                    Spacer()
                }

                // Pulsing energy circles, centered, additive blend.
                PulsingCircles(
                    bass: audio.bass,
                    mid: audio.mid,
                    treble: audio.treble,
                    minSide: min(geo.size.width, geo.size.height)
                )
                .position(x: geo.size.width / 2, y: geo.size.height / 2)

                // RMS (overall loudness) circle pinned to the top-trailing corner.
                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(
                        width: 24 + CGFloat(audio.amplitude) * 120,
                        height: 24 + CGFloat(audio.amplitude) * 120
                    )
                    .position(x: geo.size.width - 70, y: max(90, geo.size.height * 0.16) + 110)
                    .blendMode(.screen)
                    .animation(.easeOut(duration: 0.06), value: audio.amplitude)

                // Scrolling waveform tape across the bottom.
                VStack {
                    Spacer()
                    WaveformStrip(samples: audio.scrollingWaveform)
                        .frame(height: max(70, geo.size.height * 0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }

            }
        }
        .navigationTitle("Pulsing Shapes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

/// Three overlapping circles (bass/mid/treble) sized by smoothed band energy.
struct PulsingCircles: View {
    let bass: Float
    let mid: Float
    let treble: Float
    let minSide: CGFloat

    var body: some View {
        let offset = minSide * 0.10

        ZStack {
            circle(value: bass, color: .red)
                .offset(x: -offset, y: offset)
            circle(value: mid, color: .green)
                .offset(x: offset, y: offset)
            circle(value: treble, color: .blue)
                .offset(x: 0, y: -offset)
        }
        .compositingGroup()
    }

    private func circle(value: Float, color: Color) -> some View {
        let base = minSide * 0.08
        let span = minSide * 0.34
        return Circle()
            .fill(color)
            .frame(
                width: base + CGFloat(value) * span,
                height: base + CGFloat(value) * span
            )
            .blendMode(.screen)
            .animation(.easeOut(duration: 0.05), value: value)
    }
}

/// Scrolling spectrogram: each history column is a vertical strip, low freq at
/// the bottom, intensity mapped to a heat color.
struct SpectrogramStrip: View {
    let columns: [[Float]]
    let bandCount: Int
    private let maxColumns = 120

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { context, size in
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .color(Color(white: 0.04))
                )
                guard !columns.isEmpty else { return }

                let colWidth = size.width / CGFloat(maxColumns)
                let bandHeight = size.height / CGFloat(bandCount)

                for (colIndex, column) in columns.enumerated() {
                    let x = size.width - CGFloat(columns.count - colIndex) * colWidth
                    for (band, value) in column.enumerated() {
                        let t = Double(max(0, min(1, value)))
                        guard t > 0.01 else { continue }
                        // Low band at bottom, high band at top.
                        let y = size.height - CGFloat(band + 1) * bandHeight
                        let rect = CGRect(x: x, y: y, width: colWidth + 0.5, height: bandHeight + 0.5)
                        context.fill(Path(rect), with: .color(heatColor(t)))
                    }
                }
            }
        }
    }

    private func heatColor(_ t: Double) -> Color {
        // Dark at low intensity, sweeping blue → cyan → green → yellow → red as it rises.
        Color(hue: 0.66 * (1 - t), saturation: 1, brightness: pow(t, 0.45))
    }
}

/// Scrolling waveform tape: recent raw samples drawn as a centered line.
struct WaveformStrip: View {
    let samples: [Float]

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { context, size in
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .color(Color(white: 0.04))
                )
                guard samples.count > 1 else { return }

                let midY = size.height / 2
                let stepX = size.width / CGFloat(samples.count - 1)
                var path = Path()
                for (i, sample) in samples.enumerated() {
                    let x = CGFloat(i) * stepX
                    let clamped = max(-1, min(1, sample))
                    let y = midY - CGFloat(clamped) * (size.height * 0.46)
                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                context.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [.cyan, .mint, .yellow]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: 0)
                    ),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }
}

#Preview {
    NavigationStack {
        PulsingShapesView()
            .environment(AudioManager())
    }
}
