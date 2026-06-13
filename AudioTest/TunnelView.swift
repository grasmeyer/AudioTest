//
//  TunnelView.swift
//  AudioTest
//
//  Full-screen box-tunnel scene (ported from James Porter's raymarching gist)
//  with a developer test harness. RMS drives the flythrough, bass spins the
//  boxes, beats pulse box size, and the spectral centroid shifts the palette.
//  Portrait shows the visual up top with sliders below; landscape goes
//  full-screen.
//

import SwiftUI
import Metal

struct TunnelView: View {
    @Environment(AudioManager.self) private var audio
    @State private var settings = TunnelSettings()
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        GeometryReader { geo in
            if isLandscape {
                ZStack {
                    Color.black
                    visual
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .ignoresSafeArea()
            } else {
                VStack(spacing: 0) {
                    ZStack {
                        Color.black
                        visual
                    }
                    .frame(height: geo.size.height * 0.5)
                    .clipped()

                    TunnelControlsView(settings: settings)
                        .frame(height: geo.size.height * 0.5)
                }
            }
        }
        .background(Color.black)
        .navigationTitle("Box Tunnel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isLandscape ? .hidden : .visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .statusBarHidden(isLandscape)
        .ignoresSafeArea(edges: isLandscape ? .all : [])
    }

    @ViewBuilder
    private var visual: some View {
        if isMetalAvailable {
            MetalTunnelView(audio: audio, settings: settings)
        } else {
            ContentUnavailableView(
                "Metal Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("This device can't run the tunnel scene.")
            )
            .foregroundStyle(.white)
        }
    }

    private var isMetalAvailable: Bool {
        MTLCreateSystemDefaultDevice() != nil
    }
}

struct TunnelControlsView: View {
    @Bindable var settings: TunnelSettings

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Tunnel Controls")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Spacer()
                        Button("Reset") { settings.reset() }
                            .font(.subheadline.bold())
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                    }

                    controlGroup("Flythrough") {
                        ParamSlider(label: "Speed Base", value: $settings.speedBase, range: 0...3)
                        ParamSlider(label: "Speed ← RMS", value: $settings.speedRMS, range: 0...6)
                    }

                    controlGroup("Rotation") {
                        ParamSlider(label: "Rotation Base", value: $settings.rotBase, range: 0...2)
                        ParamSlider(label: "Rotation ← Bass", value: $settings.rotBass, range: 0...4)
                    }

                    controlGroup("Boxes") {
                        ParamSlider(label: "Box Size", value: $settings.boxSize, range: 0.03...0.3)
                        ParamSlider(label: "Size ← Beat", value: $settings.boxBeat, range: 0...0.2)
                        ParamSlider(label: "Camera Sway", value: $settings.sway, range: 0...2)
                    }

                    controlGroup("Color") {
                        ParamSlider(label: "Hue Offset", value: $settings.hueOffset, range: 0...1)
                        ParamSlider(label: "Hue ← Centroid", value: $settings.hueCentroid, range: 0...1)
                        ParamSlider(label: "Brightness", value: $settings.brightness, range: 0.2...2)
                    }

                    if let url = URL(string: "https://gist.github.com/jamesporter/1b33558b3fc2771b45630ba7e0ba5122") {
                        Link("Ported from James Porter's gist", destination: url)
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
    }

    private func controlGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.5))
            content()
        }
    }
}

#Preview {
    NavigationStack {
        TunnelView()
            .environment(AudioManager())
    }
}
