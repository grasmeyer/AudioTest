//
//  ContentView.swift
//  AudioTest
//
//  Created by Joel Grasmeyer on 5/28/26.
//

import SwiftUI

struct ContentView: View {
    @State private var audio = AudioManager()

    var body: some View {
        ZStack {
            // Background reacts to bass/mid/treble and flashes on beat.
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.04, blue: 0.10),
                    Color(
                        red: 0.10 + Double(audio.bass) * 0.35 + Double(audio.beatPulse) * 0.15,
                        green: 0.05 + Double(audio.mid) * 0.20,
                        blue: 0.18 + Double(audio.treble) * 0.30 + Double(audio.beatPulse) * 0.10
                    )
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeOut(duration: 0.15), value: audio.bass)

            // Beat-flash ring overlay.
            RoundedRectangle(cornerRadius: 32)
                .stroke(Color.white.opacity(Double(audio.beatPulse) * 0.55), lineWidth: 6)
                .blur(radius: 4)
                .padding(8)
                .ignoresSafeArea()
                .animation(.easeOut(duration: 0.12), value: audio.beatPulse)

            VStack(spacing: 18) {
                Text("Audio Visualizer")
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .scaleEffect(1 + CGFloat(audio.beatPulse) * 0.06)
                    .shadow(color: .white.opacity(Double(audio.beatPulse) * 0.8), radius: 12)
                    .animation(.easeOut(duration: 0.1), value: audio.beatPulse)
                    .padding(.top, 12)

                if let error = audio.errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                WaveformView(samples: audio.waveform)
                    .frame(height: 70)
                    .padding(.horizontal, 24)

                VStack(spacing: 14) {
                    FrequencyBar(label: "Bass", value: audio.bass, color: .pink)
                    FrequencyBar(label: "Mid", value: audio.mid, color: .mint)
                    FrequencyBar(label: "Treble", value: audio.treble, color: .cyan)
                    FrequencyBar(label: "Brightness", value: audio.brightness, color: .orange,
                                 trailingText: audio.centroidHz > 0
                                    ? String(format: "%.0f Hz", audio.centroidHz)
                                    : nil)
                    FrequencyBar(label: "Volume (RMS)", value: audio.amplitude, color: .yellow)
                    StereoBar(left: audio.leftAmplitude, right: audio.rightAmplitude)
                    FrequencyBar(
                        label: "Pitch",
                        value: audio.pitchValue,
                        color: .purple,
                        trailingText: audio.pitchFrequency > 0
                            ? String(format: "%.0f Hz", audio.pitchFrequency)
                            : nil
                    )
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 0)

                Button(action: audio.togglePlay) {
                    HStack(spacing: 12) {
                        Image(systemName: audio.isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 26, weight: .bold))
                        Text(audio.isPlaying ? "Stop" : "Play")
                            .font(.title3.bold())
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(audio.isPlaying ? Color.red.opacity(0.8) : Color.green.opacity(0.8))
                            .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 1.5))
                    )
                    .shadow(color: (audio.isPlaying ? Color.red : Color.green).opacity(0.5), radius: 14)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
        .navigationTitle("Audio Meters")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { audio.start() }
        .onDisappear { audio.stop() }
    }
}

struct WaveformView: View {
    let samples: [Float]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.06))

                Path { path in
                    guard samples.count > 1 else { return }
                    let width = geo.size.width
                    let height = geo.size.height
                    let midY = height / 2
                    let stepX = width / CGFloat(samples.count - 1)

                    for (i, sample) in samples.enumerated() {
                        let x = CGFloat(i) * stepX
                        let clamped = max(-1, min(1, sample))
                        let y = midY - CGFloat(clamped) * (height * 0.45)
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(
                    LinearGradient(
                        colors: [.cyan, .mint, .yellow],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: .cyan.opacity(0.5), radius: 6)
            }
        }
    }
}

struct StereoBar: View {
    let left: Float
    let right: Float

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Stereo L / R")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Spacer()
                Text(String(format: "%.2f / %.2f", left, right))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
            }

            HStack(spacing: 6) {
                HalfStereoBar(value: left, color: .blue, alignment: .trailing)
                HalfStereoBar(value: right, color: .red, alignment: .leading)
            }
            .frame(height: 32)
        }
    }
}

struct HalfStereoBar: View {
    let value: Float
    let color: Color
    let alignment: HorizontalAlignment

    var body: some View {
        GeometryReader { geo in
            let fill = geo.size.width * CGFloat(min(max(value, 0), 1))
            let leadingAligned = alignment == .leading
            ZStack(alignment: leadingAligned ? .leading : .trailing) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.10))
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.gradient)
                    .frame(width: fill)
                    .shadow(color: color.opacity(0.8), radius: 10)
                    .animation(.easeOut(duration: 0.08), value: value)
            }
        }
    }
}

struct FrequencyBar: View {
    let label: String
    let value: Float
    let color: Color
    var trailingText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Spacer()
                if let trailingText {
                    Text(trailingText)
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(.white)
                    Text(String(format: "%.2f", value))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                } else {
                    Text(String(format: "%.2f", value))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(0.10))

                    RoundedRectangle(cornerRadius: 8)
                        .fill(color.gradient)
                        .frame(width: geo.size.width * CGFloat(min(max(value, 0), 1)))
                        .shadow(color: color.opacity(0.8), radius: 10)
                        .animation(.easeOut(duration: 0.08), value: value)
                }
            }
            .frame(height: 28)
        }
    }
}

#Preview {
    ContentView()
}
