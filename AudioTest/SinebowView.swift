//
//  SinebowView.swift
//  AudioTest
//
//  Full-screen sinebow scene (adapted from twostraws/Inferno) with a developer
//  test harness. Bass swells the waves, RMS drives speed, and the spectral
//  centroid shifts the color cycle. In portrait the bottom half holds sliders;
//  in landscape the visual takes over the whole screen.
//

import SwiftUI
import Metal

struct SinebowView: View {
    @State private var audio = AudioManager()
    @State private var settings = SinebowSettings()
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

                    SinebowControlsView(settings: settings)
                        .frame(height: geo.size.height * 0.5)
                }
            }
        }
        .background(Color.black)
        .navigationTitle("Sinebow")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isLandscape ? .hidden : .visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .statusBarHidden(isLandscape)
        .ignoresSafeArea(edges: isLandscape ? .all : [])
        .onAppear { audio.start() }
        .onDisappear { audio.stop() }
    }

    @ViewBuilder
    private var visual: some View {
        if isMetalAvailable {
            MetalSinebowView(audio: audio, settings: settings)
        } else {
            ContentUnavailableView(
                "Metal Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("This device can't run the sinebow scene.")
            )
            .foregroundStyle(.white)
        }
    }

    private var isMetalAvailable: Bool {
        MTLCreateSystemDefaultDevice() != nil
    }
}

struct SinebowControlsView: View {
    @Bindable var settings: SinebowSettings

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Sinebow Controls")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Spacer()
                        Button("Reset") { settings.reset() }
                            .font(.subheadline.bold())
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                    }

                    controlGroup("Waves") {
                        ParamSlider(label: "Wave Count", value: $settings.waveCount, range: 1...20)
                        ParamSlider(label: "Strength Base", value: $settings.strengthBase, range: 0...40)
                        ParamSlider(label: "Strength ← Bass", value: $settings.strengthBass, range: 0...60)
                    }

                    controlGroup("Motion") {
                        ParamSlider(label: "Speed Base", value: $settings.speedBase, range: 0...3)
                        ParamSlider(label: "Speed ← RMS", value: $settings.speedRMS, range: 0...6)
                    }

                    controlGroup("Look") {
                        ParamSlider(label: "Thickness", value: $settings.thickness, range: 20...250)
                        ParamSlider(label: "Brightness", value: $settings.brightness, range: 0.2...3)
                        ParamSlider(label: "Hue Offset", value: $settings.hueOffset, range: 0...6.283)
                        ParamSlider(label: "Hue ← Centroid", value: $settings.hueCentroid, range: 0...6.283)
                    }

                    if let url = URL(string: "https://github.com/twostraws/Inferno") {
                        Link("Adapted from twostraws/Inferno", destination: url)
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
        SinebowView()
    }
}
