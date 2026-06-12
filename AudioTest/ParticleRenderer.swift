//
//  ParticleRenderer.swift
//  AudioTest
//
//  Metal renderer for the audio-reactive GPU particle system, plus a
//  SwiftUI UIViewRepresentable wrapper around MTKView.
//

import MetalKit
import SwiftUI
import simd
import QuartzCore

// Must match the layout of `Particle` in ParticleSystem.metal.
struct Particle {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var life: Float
    var seed: Float
}

// Must match the layout of `ParticleUniforms` in ParticleSystem.metal.
struct ParticleUniforms {
    var emitterX: Float
    var emitterY: Float
    var deltaTime: Float
    var time: Float
    var fieldStrength: Float
    var emissionRate: Float
    var hue: Float
    var hueShift: Float
    var saturation: Float
    var brightnessBoost: Float
    var spawnRadius: Float
    var initialSpeed: Float
    var inertia: Float
    var lifeDecay: Float
    var pointSize: Float
    var speedToSize: Float
    var scaleX: Float
    var scaleY: Float
    var particleCount: UInt32
    var frameSeed: UInt32
}

final class ParticleRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let computePipeline: MTLComputePipelineState
    private let renderPipeline: MTLRenderPipelineState
    private let particleBuffer: MTLBuffer

    private let particleCount: Int
    private let audio: AudioManager
    private let settings: ParticleSettings
    private let aspectFill: Bool

    private var time: Float = 0
    private var frameSeed: UInt32 = 0
    private var lastTimestamp: CFTimeInterval = CACurrentMediaTime()
    private var scaleX: Float = 1
    private var scaleY: Float = 1

    init?(audio: AudioManager, settings: ParticleSettings, aspectFill: Bool = false, particleCount: Int = 130_000) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let updateFn = library.makeFunction(name: "updateParticles"),
              let vertexFn = library.makeFunction(name: "particleVertex"),
              let fragmentFn = library.makeFunction(name: "particleFragment")
        else {
            return nil
        }

        self.device = device
        self.commandQueue = queue
        self.audio = audio
        self.settings = settings
        self.aspectFill = aspectFill
        self.particleCount = particleCount

        do {
            computePipeline = try device.makeComputePipelineState(function: updateFn)
        } catch {
            print("Particle compute pipeline error: \(error)")
            return nil
        }

        let rpld = MTLRenderPipelineDescriptor()
        rpld.vertexFunction = vertexFn
        rpld.fragmentFunction = fragmentFn
        let color = rpld.colorAttachments[0]!
        color.pixelFormat = .bgra8Unorm
        color.isBlendingEnabled = true
        color.rgbBlendOperation = .add
        color.alphaBlendOperation = .add
        color.sourceRGBBlendFactor = .sourceAlpha
        color.sourceAlphaBlendFactor = .sourceAlpha
        color.destinationRGBBlendFactor = .one
        color.destinationAlphaBlendFactor = .one

        do {
            renderPipeline = try device.makeRenderPipelineState(descriptor: rpld)
        } catch {
            print("Particle render pipeline error: \(error)")
            return nil
        }

        let length = MemoryLayout<Particle>.stride * particleCount
        guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
            return nil
        }
        particleBuffer = buffer

        super.init()
        seedParticles()
    }

    private func seedParticles() {
        let ptr = particleBuffer.contents().bindMemory(to: Particle.self, capacity: particleCount)
        for i in 0..<particleCount {
            // Stagger initial life so particles don't all respawn on the same frame,
            // and spread the starting positions across the whole screen.
            let r0 = Float.random(in: 0...1)
            let r1 = Float.random(in: 0...1)
            ptr[i] = Particle(
                position: SIMD2<Float>(Float.random(in: -0.95...0.95),
                                       Float.random(in: -0.95...0.95)),
                velocity: SIMD2<Float>(repeating: 0),
                life: r0,
                seed: r1
            )
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let w = Float(size.width)
        let h = Float(size.height)
        guard w > 0, h > 0 else { return }
        if aspectFill {
            // Cover the view with the square simulation, keeping it undistorted:
            // fill the larger dimension and let the smaller one overflow off-screen.
            if w >= h {
                scaleX = 1
                scaleY = w / h
            } else {
                scaleX = h / w
                scaleY = 1
            }
        } else {
            // Fit the square simulation region into the view, centered.
            let m = min(w, h)
            scaleX = m / w
            scaleY = m / h
        }
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
        if dt > 0.05 { dt = 0.05 } // clamp after stalls
        if dt < 0 { dt = 0 }
        time += dt
        frameSeed &+= 1

        // Audio-driven parameters, combined with the live test-harness settings.
        let bass = audio.bass
        let beat = audio.beatPulse
        let hue = audio.brightness // normalized spectral centroid

        var uniforms = ParticleUniforms(
            emitterX: 0,
            emitterY: 0,
            deltaTime: dt,
            time: time,
            fieldStrength: settings.fieldBase + bass * settings.fieldBass,
            emissionRate: settings.emissionBase + beat * settings.emissionBeat,
            hue: hue,
            hueShift: settings.hueShift,
            saturation: settings.saturation,
            brightnessBoost: settings.brightnessBoost,
            spawnRadius: settings.spawnRadius,
            initialSpeed: settings.initialSpeed,
            inertia: settings.inertia,
            lifeDecay: settings.lifeDecay,
            pointSize: settings.pointSize,
            speedToSize: settings.speedToSize,
            scaleX: scaleX,
            scaleY: scaleY,
            particleCount: UInt32(particleCount),
            frameSeed: frameSeed
        )
        let uniformsLength = MemoryLayout<ParticleUniforms>.stride

        // Compute pass: advance the simulation.
        if let compute = commandBuffer.makeComputeCommandEncoder() {
            compute.setComputePipelineState(computePipeline)
            compute.setBuffer(particleBuffer, offset: 0, index: 0)
            compute.setBytes(&uniforms, length: uniformsLength, index: 1)
            let threadWidth = computePipeline.threadExecutionWidth
            let threadsPerGroup = MTLSize(width: threadWidth, height: 1, depth: 1)
            let groups = MTLSize(
                width: (particleCount + threadWidth - 1) / threadWidth,
                height: 1,
                depth: 1
            )
            compute.dispatchThreadgroups(groups, threadsPerThreadgroup: threadsPerGroup)
            compute.endEncoding()
        }

        // Render pass: draw particles as additive points on black.
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        if let render = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) {
            render.setRenderPipelineState(renderPipeline)
            render.setVertexBuffer(particleBuffer, offset: 0, index: 0)
            render.setVertexBytes(&uniforms, length: uniformsLength, index: 1)
            render.drawPrimitives(type: .point, vertexStart: 0, vertexCount: particleCount)
            render.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

struct MetalParticleView: UIViewRepresentable {
    var audio: AudioManager
    var settings: ParticleSettings
    var aspectFill: Bool = false

    func makeCoordinator() -> ParticleRenderer? {
        ParticleRenderer(audio: audio, settings: settings, aspectFill: aspectFill)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.isOpaque = true
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
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
