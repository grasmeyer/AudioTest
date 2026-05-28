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
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.04, blue: 0.10),
                    Color(
                        red: 0.10 + Double(audio.bass) * 0.35,
                        green: 0.05 + Double(audio.mid) * 0.20,
                        blue: 0.18 + Double(audio.treble) * 0.30
                    )
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeOut(duration: 0.15), value: audio.bass)

            VStack(spacing: 24) {
                Text("Audio Visualizer")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .padding(.top, 20)

                if let error = audio.errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                VStack(spacing: 16) {
                    FrequencyBar(label: "Bass", value: audio.bass, color: .pink)
                    FrequencyBar(label: "Mid", value: audio.mid, color: .mint)
                    FrequencyBar(label: "Treble", value: audio.treble, color: .cyan)
                    FrequencyBar(label: "Volume (RMS)", value: audio.amplitude, color: .yellow)
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

                Spacer()

                Button(action: audio.togglePlay) {
                    HStack(spacing: 12) {
                        Image(systemName: audio.isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 28, weight: .bold))
                        Text(audio.isPlaying ? "Stop" : "Play")
                            .font(.title2.bold())
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        Capsule()
                            .fill(audio.isPlaying ? Color.red.opacity(0.8) : Color.green.opacity(0.8))
                            .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 1.5))
                    )
                    .shadow(color: (audio.isPlaying ? Color.red : Color.green).opacity(0.5), radius: 14)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
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
            .frame(height: 32)
        }
    }
}

#Preview {
    ContentView()
}
