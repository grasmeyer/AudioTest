//
//  ShaderSceneView.swift
//  AudioTest
//
//  Full-screen ShaderToy-style domain-warp scene with a developer test harness.
//  Bass drives the warp amount, the spectral centroid drives the color palette,
//  and RMS drives scroll speed. In portrait, the bottom half holds sliders to
//  tune the look live; in landscape, the visual takes over the whole screen.
//

import SwiftUI
import Metal

struct ShaderSceneView: View {
    @Environment(AudioManager.self) private var audio
    @State private var settings = ShaderSettings()
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    // On iPhone, landscape collapses the vertical size class to compact.
    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        GeometryReader { geo in
            if isLandscape {
                // Landscape: the visual takes over the whole screen.
                ZStack {
                    Color.black
                    visual
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .ignoresSafeArea()
            } else {
                // Portrait: top-half visual, bottom-half control harness.
                VStack(spacing: 0) {
                    ZStack {
                        Color.black
                        visual
                    }
                    .frame(height: geo.size.height * 0.5)
                    .clipped()

                    ShaderControlsView(settings: settings)
                        .frame(height: geo.size.height * 0.5)
                }
            }
        }
        .background(Color.black)
        .navigationTitle("2D Shader")
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
            MetalShaderView(audio: audio, settings: settings)
        } else {
            ContentUnavailableView(
                "Metal Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("This device can't run the shader scene.")
            )
            .foregroundStyle(.white)
        }
    }

    private var isMetalAvailable: Bool {
        MTLCreateSystemDefaultDevice() != nil
    }
}

struct ShaderControlsView: View {
    @Bindable var settings: ShaderSettings

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Shader Controls")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Spacer()
                        Button("Reset") { settings.reset() }
                            .font(.subheadline.bold())
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                    }

                    controlGroup("Domain Warp") {
                        ParamSlider(label: "Warp Base", value: $settings.warpBase, range: 0...3)
                        ParamSlider(label: "Warp ← Bass", value: $settings.warpBass, range: 0...5)
                    }

                    controlGroup("Flow") {
                        ParamSlider(label: "Scroll Base", value: $settings.scrollBase, range: 0...0.5)
                        ParamSlider(label: "Scroll ← RMS", value: $settings.scrollRMS, range: 0...2)
                    }

                    controlGroup("Color") {
                        ParamSlider(label: "Palette Offset", value: $settings.paletteOffset, range: 0...1)
                        ParamSlider(label: "Palette ← Centroid", value: $settings.paletteCentroid, range: 0...1)
                        ParamSlider(label: "Brightness", value: $settings.brightness, range: 0.2...2)
                        ParamSlider(label: "Contrast", value: $settings.contrast, range: 0...2)
                    }

                    controlGroup("Framing") {
                        ParamSlider(label: "Zoom", value: $settings.zoom, range: 0.5...6)
                    }

                    if let url = URL(string: "https://thebookofshaders.com") {
                        Link("The Book of Shaders", destination: url)
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
        ShaderSceneView()
            .environment(AudioManager())
    }
}
