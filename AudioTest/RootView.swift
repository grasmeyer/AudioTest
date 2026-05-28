//
//  RootView.swift
//  AudioTest
//

import SwiftUI

struct RootView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    ContentView()
                } label: {
                    Label("Audio Meters", systemImage: "waveform")
                }
            }
            .navigationTitle("AudioTest")
        }
    }
}

#Preview {
    RootView()
}
