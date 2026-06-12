//
//  SinebowRenderer.swift
//  AudioTest
//
//  Metal renderer for the full-screen sinebow scene, plus a SwiftUI
//  UIViewRepresentable wrapper around MTKView.
//

import MetalKit
import SwiftUI
import simd
import QuartzCore

// Must match the layout of `SinebowUniforms` in SinebowShader.metal.
struct SinebowUniforms {
    var time: Float
    var waveCount: Float
    var strength: Float
    var thickness: Float
    var brightness: Float
    var hueShift: Float
    var resolution: SIMD2<Float>
}

final class SinebowRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let audio: AudioManager
    private let settings: SinebowSettings

    private var phase: Float = 0
    private var lastTimestamp: CFTimeInterval = CACurrentMediaTime()
    private var resolution = SIMD2<Float>(1, 1)

    private var bassSmoothed: Float = 0
    private var centroidSmoothed: Float = 0

    init?(audio: AudioManager, settings: SinebowSettings) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertexFn = library.makeFunction(name: "sinebowVertex"),
              let fragmentFn = library.makeFunction(name: "sinebowFragment")
        else {
            return nil
        }

        self.device = device
        self.commandQueue = queue
        self.audio = audio
        self.settings = settings

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("Sinebow pipeline error: \(error)")
            return nil
        }

        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        resolution = SIMD2<Float>(Float(size.width), Float(size.height))
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return
        }

        let now = CACurrentMediaTime()
        var dt = Float(now - lastTimestamp)
        lastTimestamp = now
        if dt > 0.05 { dt = 0.05 }
        if dt < 0 { dt = 0 }

        // Audio → parameters. Bass swells the waves, RMS speeds the motion,
        // and the spectral centroid shifts the color cycle.
        let bass = audio.bass
        let rms = audio.amplitude
        let centroid = audio.brightness

        bassSmoothed = bassSmoothed * 0.85 + bass * 0.15
        centroidSmoothed = centroidSmoothed * 0.95 + centroid * 0.05
        phase += dt * (settings.speedBase + rms * settings.speedRMS)

        var uniforms = SinebowUniforms(
            time: phase,
            waveCount: settings.waveCount,
            strength: settings.strengthBase + bassSmoothed * settings.strengthBass,
            thickness: settings.thickness,
            brightness: settings.brightness,
            hueShift: settings.hueOffset + centroidSmoothed * settings.hueCentroid,
            resolution: resolution
        )

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) {
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SinebowUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

struct MetalSinebowView: UIViewRepresentable {
    var audio: AudioManager
    var settings: SinebowSettings

    func makeCoordinator() -> SinebowRenderer? {
        SinebowRenderer(audio: audio, settings: settings)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.isOpaque = true
        view.isPaused = false
        view.enableSetNeedsDisplay = false

        if let renderer = context.coordinator {
            view.device = renderer.device
            view.delegate = renderer
            renderer.mtkView(view, drawableSizeWillChange: view.drawableSize)
        }
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}
