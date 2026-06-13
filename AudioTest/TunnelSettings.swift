//
//  TunnelSettings.swift
//  AudioTest
//
//  Live-tunable parameters for the box-tunnel test harness. The renderer reads
//  these every frame, so slider changes take effect immediately.
//

import Observation

@MainActor
@Observable
final class TunnelSettings {
    // Flythrough.
    var speedBase: Float = 0.8     // baseline forward speed
    var speedRMS: Float = 3.0      // added forward speed per unit RMS

    // Rotation.
    var rotBase: Float = 0.5       // baseline box rotation speed
    var rotBass: Float = 1.5       // added rotation speed per unit bass

    // Boxes.
    var boxSize: Float = 0.1       // box half-size
    var boxBeat: Float = 0.05      // box growth on beat pulse

    // Camera.
    var sway: Float = 1.0          // side-to-side sway amount

    // Color.
    var hueOffset: Float = 0.0     // manual palette phase
    var hueCentroid: Float = 0.5   // how much the spectral centroid shifts the palette
    var brightness: Float = 1.0

    func reset() {
        speedBase = 0.8
        speedRMS = 3.0
        rotBase = 0.5
        rotBass = 1.5
        boxSize = 0.1
        boxBeat = 0.05
        sway = 1.0
        hueOffset = 0.0
        hueCentroid = 0.5
        brightness = 1.0
    }
}
