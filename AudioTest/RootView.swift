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
                        .toolbar(.hidden, for: .tabBar)
                } label: {
                    Label("AudioKit Test", systemImage: "waveform")
                }

                NavigationLink {
                    PulsingShapesView()
                        .toolbar(.hidden, for: .tabBar)
                } label: {
                    Label("Pulsing Shapes", systemImage: "circle.circle")
                }

                NavigationLink {
                    ParticleSystemView()
                        .toolbar(.hidden, for: .tabBar)
                } label: {
                    Label("Particle System", systemImage: "sparkles")
                }

                NavigationLink {
                    ShaderSceneView()
                        .toolbar(.hidden, for: .tabBar)
                } label: {
                    Label("2D Shader", systemImage: "water.waves")
                }

                NavigationLink {
                    SinebowView()
                        .toolbar(.hidden, for: .tabBar)
                } label: {
                    Label("Sinebow", systemImage: "rainbow")
                }

                NavigationLink {
                    RaymarchView()
                        .toolbar(.hidden, for: .tabBar)
                } label: {
                    Label("Raymarching", systemImage: "cube.transparent")
                }

                NavigationLink {
                    TunnelView()
                        .toolbar(.hidden, for: .tabBar)
                } label: {
                    Label("Box Tunnel", systemImage: "square.stack.3d.forward.dottedline")
                }

                if #available(iOS 27.0, *) {
                    NavigationLink {
                        MusicUnderstandingView()
                            .toolbar(.hidden, for: .tabBar)
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
