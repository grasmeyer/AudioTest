//
//  ShaderRenderer.swift
//  AudioTest
//
//  Metal renderer for the full-screen domain-warp shader scene, plus a SwiftUI
//  UIViewRepresentable wrapper around MTKView.
//

import MetalKit
import SwiftUI
import simd
import QuartzCore

// Must match the layout of `ShaderUniforms` in DomainWarpShader.metal.
struct ShaderUniforms {
    var time: Float
    var warp: Float
    var palette: Float
    var scroll: Float
    var zoom: Float
    var contrast: Float
    var brightness: Float
    var resolution: SIMD2<Float>
}

final class ShaderRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let audio: AudioManager
    private let settings: ShaderSettings

    private var time: Float = 0
    private var scrollPhase: Float = 0
    private var lastTimestamp: CFTimeInterval = CACurrentMediaTime()
    private var resolution = SIMD2<Float>(1, 1)

    // Smoothed audio values so the scene drifts rather than jitters.
    private var warpSmoothed: Float = 0
    private var paletteSmoothed: Float = 0

    init?(audio: AudioManager, settings: ShaderSettings) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertexFn = library.makeFunction(name: "fullscreenVertex"),
              let fragmentFn = library.makeFunction(name: "domainWarpFragment")
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
            print("Domain-warp pipeline error: \(error)")
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
        time += dt

        // Audio → parameters. Bass warps, centroid shifts palette, RMS scrolls.
        let bass = audio.bass
        let rms = audio.amplitude
        let centroid = audio.brightness

        warpSmoothed = warpSmoothed * 0.9 + bass * 0.1
        paletteSmoothed = paletteSmoothed * 0.95 + centroid * 0.05
        scrollPhase += dt * (settings.scrollBase + rms * settings.scrollRMS)

        var uniforms = ShaderUniforms(
            time: time,
            warp: settings.warpBase + warpSmoothed * settings.warpBass,
            palette: paletteSmoothed * settings.paletteCentroid + settings.paletteOffset,
            scroll: scrollPhase,
            zoom: settings.zoom,
            contrast: settings.contrast,
            brightness: settings.brightness,
            resolution: resolution
        )

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) {
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

struct MetalShaderView: UIViewRepresentable {
    var audio: AudioManager
    var settings: ShaderSettings

    func makeCoordinator() -> ShaderRenderer? {
        ShaderRenderer(audio: audio, settings: settings)
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
