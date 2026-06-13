//
//  TunnelRenderer.swift
//  AudioTest
//
//  Metal renderer for the full-screen box-tunnel scene, plus a SwiftUI
//  UIViewRepresentable wrapper around MTKView.
//

import MetalKit
import SwiftUI
import simd
import QuartzCore

// Must match the layout of `TunnelUniforms` in TunnelShader.metal.
struct TunnelUniforms {
    var time: Float
    var travel: Float
    var rotPhase: Float
    var boxSize: Float
    var hue: Float
    var sway: Float
    var brightness: Float
    var resolution: SIMD2<Float>
}

final class TunnelRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let audio: AudioManager
    private let settings: TunnelSettings

    private var time: Float = 0
    private var travel: Float = 0
    private var rotPhase: Float = 0
    private var lastTimestamp: CFTimeInterval = CACurrentMediaTime()
    private var resolution = SIMD2<Float>(1, 1)

    private var bassSmoothed: Float = 0
    private var centroidSmoothed: Float = 0

    init?(audio: AudioManager, settings: TunnelSettings) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertexFn = library.makeFunction(name: "tunnelVertex"),
              let fragmentFn = library.makeFunction(name: "tunnelFragment")
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
            print("Tunnel pipeline error: \(error)")
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

        // Audio → parameters. RMS speeds the flythrough, bass spins the boxes,
        // beats pulse box size, and the spectral centroid shifts the palette.
        let bass = audio.bass
        let rms = audio.amplitude
        let beat = audio.beatPulse
        let centroid = audio.brightness

        bassSmoothed = bassSmoothed * 0.85 + bass * 0.15
        centroidSmoothed = centroidSmoothed * 0.95 + centroid * 0.05

        travel += dt * (settings.speedBase + rms * settings.speedRMS)
        rotPhase += dt * (settings.rotBase + bassSmoothed * settings.rotBass)

        var uniforms = TunnelUniforms(
            time: time,
            travel: travel,
            rotPhase: rotPhase,
            boxSize: settings.boxSize + beat * settings.boxBeat,
            hue: settings.hueOffset + centroidSmoothed * settings.hueCentroid,
            sway: settings.sway,
            brightness: settings.brightness,
            resolution: resolution
        )

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) {
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<TunnelUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

struct MetalTunnelView: UIViewRepresentable {
    var audio: AudioManager
    var settings: TunnelSettings

    func makeCoordinator() -> TunnelRenderer? {
        TunnelRenderer(audio: audio, settings: settings)
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
