//
//  MusicTabView.swift
//  AudioTest
//
//  The Music tab: a single Play/Stop button that plays the default song.
//

import SwiftUI

struct MusicTabView: View {
    @State private var audio = AudioManager()

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.05, blue: 0.12), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 28) {
                    Image(systemName: "music.note")
                        .font(.system(size: 64))
                        .foregroundStyle(.white.opacity(0.85))

                    if let error = audio.errorMessage {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Button(action: audio.togglePlay) {
                        HStack(spacing: 12) {
                            Image(systemName: audio.isPlaying ? "stop.fill" : "play.fill")
                                .font(.system(size: 24, weight: .bold))
                            Text(audio.isPlaying ? "Stop" : "Play")
                                .font(.title3.bold())
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: 240)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(audio.isPlaying ? Color.red.opacity(0.8) : Color.green.opacity(0.8))
                                .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 1.5))
                        )
                        .shadow(color: (audio.isPlaying ? Color.red : Color.green).opacity(0.5), radius: 14)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .navigationTitle("Music")
        }
    }
}

#Preview {
    MusicTabView()
}
