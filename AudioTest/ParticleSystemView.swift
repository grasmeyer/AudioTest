//
//  ParticleSystemView.swift
//  AudioTest
//
//  Audio-reactive GPU particle system with a developer test harness. The top
//  half shows the live Metal particle visual; the bottom half holds sliders to
//  tune the emitter's appearance in real time.
//

import SwiftUI
import Metal

struct ParticleSystemView: View {
    @Environment(AudioManager.self) private var audio
    @State private var settings = ParticleSettings()
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    // On iPhone, landscape collapses the vertical size class to compact.
    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        GeometryReader { geo in
            if isLandscape {
                // Landscape: the visual takes over the whole screen and fills its width.
                ZStack {
                    Color.black
                    visual(aspectFill: true)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .ignoresSafeArea()
            } else {
                // Portrait: top-half visual, bottom-half control harness.
                VStack(spacing: 0) {
                    ZStack {
                        Color.black
                        visual(aspectFill: false)
                    }
                    .frame(height: geo.size.height * 0.5)
                    .clipped()

                    ParticleControlsView(settings: settings)
                        .frame(height: geo.size.height * 0.5)
                }
            }
        }
        .background(Color.black)
        .navigationTitle("Particle System")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isLandscape ? .hidden : .visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .statusBarHidden(isLandscape)
        .ignoresSafeArea(edges: isLandscape ? .all : [])
    }

    @ViewBuilder
    private func visual(aspectFill: Bool) -> some View {
        if isMetalAvailable {
            MetalParticleView(audio: audio, settings: settings, aspectFill: aspectFill)
        } else {
            ContentUnavailableView(
                "Metal Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("This device can't run the particle system.")
            )
            .foregroundStyle(.white)
        }
    }

    private var isMetalAvailable: Bool {
        MTLCreateSystemDefaultDevice() != nil
    }
}

struct ParticleControlsView: View {
    @Bindable var settings: ParticleSettings

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Emitter Controls")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Spacer()
                        Button("Reset") { settings.reset() }
                            .font(.subheadline.bold())
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                    }

                    controlGroup("Curl Field") {
                        ParamSlider(label: "Field Base", value: $settings.fieldBase, range: 0...0.4)
                        ParamSlider(label: "Field ← Bass", value: $settings.fieldBass, range: 0...1)
                        ParamSlider(label: "Inertia", value: $settings.inertia, range: 0.02...1)
                    }

                    controlGroup("Emission") {
                        ParamSlider(label: "Emission Base", value: $settings.emissionBase, range: 0...0.2)
                        ParamSlider(label: "Emission ← Beat", value: $settings.emissionBeat, range: 0...1)
                        ParamSlider(label: "Spawn Radius", value: $settings.spawnRadius, range: 0...1.2)
                        ParamSlider(label: "Initial Speed", value: $settings.initialSpeed, range: 0...1.5)
                        ParamSlider(label: "Life Decay", value: $settings.lifeDecay, range: 0.05...1.5)
                    }

                    controlGroup("Appearance") {
                        ParamSlider(label: "Point Size", value: $settings.pointSize, range: 0.5...8)
                        ParamSlider(label: "Speed → Size", value: $settings.speedToSize, range: 0...30)
                        ParamSlider(label: "Hue Shift", value: $settings.hueShift, range: 0...1)
                        ParamSlider(label: "Saturation", value: $settings.saturation, range: 0...1)
                        ParamSlider(label: "Brightness", value: $settings.brightnessBoost, range: 0.2...3)
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

struct ParamSlider: View {
    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                Spacer()
                Text(String(format: "%.3f", value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
            }
            Slider(value: $value, in: range)
                .tint(.cyan)
        }
    }
}

#Preview {
    NavigationStack {
        ParticleSystemView()
            .environment(AudioManager())
    }
}
