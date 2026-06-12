//
//  ParticleSettings.swift
//  AudioTest
//
//  Live-tunable parameters for the particle system test harness. The renderer
//  reads these every frame, so slider changes take effect immediately.
//

import Observation

@MainActor
@Observable
final class ParticleSettings {
    // Curl-noise field.
    var fieldBase: Float = 0.07        // baseline flow speed
    var fieldBass: Float = 0.33        // added field strength per unit bass
    var inertia: Float = 0.20          // how fast velocity follows the field

    // Emission.
    var emissionBase: Float = 0.015    // baseline respawn probability
    var emissionBeat: Float = 0.55     // added emission per unit beat pulse
    var spawnRadius: Float = 0.55      // emission disc radius
    var initialSpeed: Float = 0.40     // outward burst speed at spawn
    var lifeDecay: Float = 0.30        // how quickly particles age out

    // Appearance.
    var pointSize: Float = 1.5         // base point size
    var speedToSize: Float = 10.0      // extra size per unit speed
    var hueShift: Float = 0.0          // offset added to the centroid hue
    var saturation: Float = 0.85
    var brightnessBoost: Float = 1.0

    func reset() {
        fieldBase = 0.07
        fieldBass = 0.33
        inertia = 0.20
        emissionBase = 0.015
        emissionBeat = 0.55
        spawnRadius = 0.55
        initialSpeed = 0.40
        lifeDecay = 0.30
        pointSize = 1.5
        speedToSize = 10.0
        hueShift = 0.0
        saturation = 0.85
        brightnessBoost = 1.0
    }
}
