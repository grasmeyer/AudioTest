//
//  MusicTabView.swift
//  AudioTest
//
//  The Music tab: a single Play/Stop button that plays the default song.
//

import SwiftUI
import MediaPlayer

struct MusicTabView: View {
    @Environment(AudioManager.self) private var audio
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.05, blue: 0.12), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 24) {
                    Image(systemName: "music.note")
                        .font(.system(size: 64))
                        .foregroundStyle(.white.opacity(0.85))

                    VStack(spacing: 4) {
                        Text(audio.nowPlayingTitle)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        if !audio.isReactive {
                            Text("Streaming — visuals won't react")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal)

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

                    Button(action: requestPickerAccess) {
                        HStack(spacing: 8) {
                            Image(systemName: "music.note.list")
                            Text("Apple Music")
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: 240)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(Color.pink.opacity(0.55))
                                .overlay(Capsule().stroke(.white.opacity(0.4), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)

                    if #available(iOS 27.0, *) {
                        NavigationLink {
                            MusicUnderstandingView()
                                .toolbar(.hidden, for: .tabBar)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "waveform.badge.magnifyingglass")
                                Text("Music Understanding")
                            }
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .frame(maxWidth: 240)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .fill(.white.opacity(0.12))
                                    .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 1))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Music")
            .sheet(isPresented: $showPicker) {
                MusicPicker(isPresented: $showPicker) { item in
                    audio.play(mediaItem: item)
                }
                .ignoresSafeArea()
            }
        }
    }

    // Apple Music / library access needs authorization before the picker can
    // show the user's songs.
    private func requestPickerAccess() {
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized:
            showPicker = true
        case .notDetermined:
            MPMediaLibrary.requestAuthorization { status in
                Task { @MainActor in
                    if status == .authorized {
                        showPicker = true
                    } else {
                        audio.errorMessage = "Apple Music access was not granted."
                    }
                }
            }
        default:
            audio.errorMessage = "Enable Media & Apple Music access in Settings to pick a song."
        }
    }
}

#Preview {
    MusicTabView()
        .environment(AudioManager())
}
