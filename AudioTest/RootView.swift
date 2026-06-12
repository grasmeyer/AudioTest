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

                NavigationLink {
                    PulsingShapesView()
                } label: {
                    Label("Pulsing Shapes", systemImage: "circle.circle")
                }

                NavigationLink {
                    ParticleSystemView()
                } label: {
                    Label("Particle System", systemImage: "sparkles")
                }

                NavigationLink {
                    ShaderSceneView()
                } label: {
                    Label("2D Shader", systemImage: "water.waves")
                }

                NavigationLink {
                    SinebowView()
                } label: {
                    Label("Sinebow", systemImage: "rainbow")
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
