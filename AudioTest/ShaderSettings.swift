//
//  ShaderSettings.swift
//  AudioTest
//
//  Live-tunable parameters for the 2D domain-warp shader test harness. The
//  renderer reads these every frame, so slider changes take effect immediately.
//

import Observation

@MainActor
@Observable
final class ShaderSettings {
    // Domain warp.
    var warpBase: Float = 0.5      // baseline warp amount
    var warpBass: Float = 2.5      // added warp per unit bass

    // Scroll / flow.
    var scrollBase: Float = 0.08   // baseline scroll speed
    var scrollRMS: Float = 0.7     // added scroll speed per unit RMS

    // Color.
    var paletteOffset: Float = 0.0    // manual palette phase offset
    var paletteCentroid: Float = 1.0  // how much the spectral centroid shifts the palette

    // Framing / look.
    var zoom: Float = 2.2          // spatial scale of the field
    var contrast: Float = 1.0      // contrast curve strength
    var brightness: Float = 1.0    // overall brightness

    func reset() {
        warpBase = 0.5
        warpBass = 2.5
        scrollBase = 0.08
        scrollRMS = 0.7
        paletteOffset = 0.0
        paletteCentroid = 1.0
        zoom = 2.2
        contrast = 1.0
        brightness = 1.0
    }
}
