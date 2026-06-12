//
//  RaymarchSettings.swift
//  AudioTest
//
//  Live-tunable parameters for the raymarching test harness. The renderer reads
//  these every frame, so slider changes take effect immediately.
//

import Observation

@MainActor
@Observable
final class RaymarchSettings {
    // Camera.
    var camDistance: Float = 4.0   // distance from the sphere
    var fov: Float = 1.0           // field-of-view scale

    // Object.
    var sphereRadius: Float = 1.0

    // Audio reactivity.
    var shakeAmount: Float = 0.6   // camera shake per unit bass hit
    var bloomBase: Float = 0.3     // baseline glow intensity
    var bloomRMS: Float = 1.5      // added glow per unit RMS

    // Color.
    var hueOffset: Float = 0.0     // manual palette offset
    var hueCentroid: Float = 1.0   // how much the spectral centroid tints the scene
    var brightness: Float = 1.0

    func reset() {
        camDistance = 4.0
        fov = 1.0
        sphereRadius = 1.0
        shakeAmount = 0.6
        bloomBase = 0.3
        bloomRMS = 1.5
        hueOffset = 0.0
        hueCentroid = 1.0
        brightness = 1.0
    }
}
