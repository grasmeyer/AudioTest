//
//  RaymarchView.swift
//  AudioTest
//
//  Full-screen raymarched scene (an SDF sphere in a procedural sky) with a
//  developer test harness. Bass hits shake the camera, RMS drives the bloom,
//  and the spectral centroid tints the palette. Portrait shows the visual up
//  top with sliders below; landscape goes full-screen.
//

import SwiftUI
import Metal

struct RaymarchView: View {
    @Environment(AudioManager.self) private var audio
    @State private var settings = RaymarchSettings()
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

                    RaymarchControlsView(settings: settings)
                        .frame(height: geo.size.height * 0.5)
                }
            }
        }
        .background(Color.black)
        .navigationTitle("Raymarching")
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
            MetalRaymarchView(audio: audio, settings: settings)
        } else {
            ContentUnavailableView(
                "Metal Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("This device can't run the raymarched scene.")
            )
            .foregroundStyle(.white)
        }
    }

    private var isMetalAvailable: Bool {
        MTLCreateSystemDefaultDevice() != nil
    }
}

struct RaymarchControlsView: View {
    @Bindable var settings: RaymarchSettings

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Raymarch Controls")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Spacer()
                        Button("Reset") { settings.reset() }
                            .font(.subheadline.bold())
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                    }

                    controlGroup("Camera") {
                        ParamSlider(label: "Distance", value: $settings.camDistance, range: 2...10)
                        ParamSlider(label: "Field of View", value: $settings.fov, range: 0.4...2.0)
                    }

                    controlGroup("Object") {
                        ParamSlider(label: "Sphere Radius", value: $settings.sphereRadius, range: 0.3...2.5)
                    }

                    controlGroup("Audio Reactivity") {
                        ParamSlider(label: "Shake ← Bass", value: $settings.shakeAmount, range: 0...1.5)
                        ParamSlider(label: "Bloom Base", value: $settings.bloomBase, range: 0...2)
                        ParamSlider(label: "Bloom ← RMS", value: $settings.bloomRMS, range: 0...3)
                    }

                    controlGroup("Color") {
                        ParamSlider(label: "Hue Offset", value: $settings.hueOffset, range: 0...1)
                        ParamSlider(label: "Hue ← Centroid", value: $settings.hueCentroid, range: 0...1)
                        ParamSlider(label: "Brightness", value: $settings.brightness, range: 0.2...2)
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
        RaymarchView()
            .environment(AudioManager())
    }
}
