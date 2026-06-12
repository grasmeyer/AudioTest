//
//  SinebowSettings.swift
//  AudioTest
//
//  Live-tunable parameters for the sinebow test harness. The renderer reads
//  these every frame, so slider changes take effect immediately.
//

import Observation

@MainActor
@Observable
final class SinebowSettings {
    // Waves.
    var waveCount: Float = 8        // number of stacked waves
    var strengthBase: Float = 15    // baseline wave displacement
    var strengthBass: Float = 25    // added displacement per unit bass

    // Motion.
    var speedBase: Float = 0.8      // baseline animation speed
    var speedRMS: Float = 3.0       // added speed per unit RMS

    // Look.
    var thickness: Float = 100      // band thinness (larger = thinner/brighter)
    var brightness: Float = 1.0
    var hueOffset: Float = 0.0      // manual color-cycle phase
    var hueCentroid: Float = 3.0    // how much the spectral centroid shifts color

    func reset() {
        waveCount = 8
        strengthBase = 15
        strengthBass = 25
        speedBase = 0.8
        speedRMS = 3.0
        thickness = 100
        brightness = 1.0
        hueOffset = 0.0
        hueCentroid = 3.0
    }
}
