//
//  RaymarchRenderer.swift
//  AudioTest
//
//  Metal renderer for the full-screen raymarched scene, plus a SwiftUI
//  UIViewRepresentable wrapper around MTKView.
//

import MetalKit
import SwiftUI
import simd
import QuartzCore

// Must match the layout of `RaymarchUniforms` in RaymarchShader.metal.
struct RaymarchUniforms {
    var time: Float
    var shake: Float
    var bloom: Float
    var camDistance: Float
    var fov: Float
    var sphereRadius: Float
    var hue: Float
    var brightness: Float
    var resolution: SIMD2<Float>
}

final class RaymarchRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let audio: AudioManager
    private let settings: RaymarchSettings

    private var time: Float = 0
    private var lastTimestamp: CFTimeInterval = CACurrentMediaTime()
    private var resolution = SIMD2<Float>(1, 1)

    private var rmsSmoothed: Float = 0
    private var centroidSmoothed: Float = 0

    init?(audio: AudioManager, settings: RaymarchSettings) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertexFn = library.makeFunction(name: "raymarchVertex"),
              let fragmentFn = library.makeFunction(name: "raymarchFragment")
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
            print("Raymarch pipeline error: \(error)")
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

        // Audio → parameters. Beat onsets (bass hits) shake the camera, RMS
        // drives the bloom, and the spectral centroid tints the palette.
        let beat = audio.beatPulse
        let rms = audio.amplitude
        let centroid = audio.brightness

        rmsSmoothed = rmsSmoothed * 0.85 + rms * 0.15
        centroidSmoothed = centroidSmoothed * 0.95 + centroid * 0.05

        var uniforms = RaymarchUniforms(
            time: time,
            shake: beat * settings.shakeAmount,
            bloom: settings.bloomBase + rmsSmoothed * settings.bloomRMS,
            camDistance: settings.camDistance,
            fov: settings.fov,
            sphereRadius: settings.sphereRadius,
            hue: settings.hueOffset + centroidSmoothed * settings.hueCentroid,
            brightness: settings.brightness,
            resolution: resolution
        )

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) {
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<RaymarchUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

struct MetalRaymarchView: UIViewRepresentable {
    var audio: AudioManager
    var settings: RaymarchSettings

    func makeCoordinator() -> RaymarchRenderer? {
        RaymarchRenderer(audio: audio, settings: settings)
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
