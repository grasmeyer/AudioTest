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
                    Label("AudioKit Test", systemImage: "waveform")
                }

                if #available(iOS 27.0, *) {
                    NavigationLink {
                        MusicUnderstandingView()
                    } label: {
                        Label("MusicUnderstanding Test", systemImage: "waveform.badge.magnifyingglass")
                    }
                }
            }
            .navigationTitle("TrippyBeats")
        }
    }
}

#Preview {
    RootView()
}
