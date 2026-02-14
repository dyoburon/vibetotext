import MetalKit
import simd

final class GalaxyRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let computePipeline: MTLComputePipelineState
    let renderPipeline: MTLRenderPipelineState
    let backgroundPipeline: MTLRenderPipelineState

    var particleSystem: ParticleSystem?
    var uniforms = GalaxyUniforms()
    var lastFrameTime: CFAbsoluteTime = 0
    var zoom: Float = 1.0
    var highlightIndex: Int32 = -1
    var dimFactor: Float = 1.0
    var colorMode: Int32 = 0
    var audioLevels: [Float] = Array(repeating: 0, count: 32)
    var audioAmplitude: Float = 0

    init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue

        let options = MTLCompileOptions()
        guard let library = try? device.makeLibrary(source: metalShaderSource, options: options) else {
            print("Failed to compile Metal shaders")
            return nil
        }

        // Compute pipeline
        guard let updateFunc = library.makeFunction(name: "updateParticles"),
              let computePS = try? device.makeComputePipelineState(function: updateFunc) else {
            print("Failed to create compute pipeline")
            return nil
        }
        self.computePipeline = computePS

        // Background pipeline (full-screen procedural galaxy)
        guard let bgVertex = library.makeFunction(name: "vertexBackground"),
              let bgFragment = library.makeFunction(name: "fragmentBackground") else {
            print("Failed to find background shader functions")
            return nil
        }

        let bgRPD = MTLRenderPipelineDescriptor()
        bgRPD.vertexFunction = bgVertex
        bgRPD.fragmentFunction = bgFragment
        bgRPD.colorAttachments[0].pixelFormat = .bgra8Unorm
        bgRPD.colorAttachments[0].isBlendingEnabled = false

        guard let bgPS = try? device.makeRenderPipelineState(descriptor: bgRPD) else {
            print("Failed to create background pipeline")
            return nil
        }
        self.backgroundPipeline = bgPS

        // Particle pipeline
        guard let vertexFunc = library.makeFunction(name: "vertexParticle"),
              let fragmentFunc = library.makeFunction(name: "fragmentParticle") else {
            print("Failed to find shader functions")
            return nil
        }

        let rpd = MTLRenderPipelineDescriptor()
        rpd.vertexFunction = vertexFunc
        rpd.fragmentFunction = fragmentFunc
        rpd.colorAttachments[0].pixelFormat = .bgra8Unorm
        rpd.colorAttachments[0].isBlendingEnabled = true
        rpd.colorAttachments[0].sourceRGBBlendFactor = .one
        rpd.colorAttachments[0].destinationRGBBlendFactor = .one
        rpd.colorAttachments[0].sourceAlphaBlendFactor = .one
        rpd.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        guard let renderPS = try? device.makeRenderPipelineState(descriptor: rpd) else {
            print("Failed to create render pipeline")
            return nil
        }
        self.renderPipeline = renderPS

        super.init()
        self.lastFrameTime = CFAbsoluteTimeGetCurrent()
    }

    func loadParticles(
        wordFrequencies: [WordFrequency],
        coOccurrence: [String: [(String, Int)]] = [:],
        entries: [TranscriptionEntry] = []
    ) {
        guard !wordFrequencies.isEmpty else { return }
        self.particleSystem = ParticleSystem(
            device: device,
            wordFrequencies: wordFrequencies,
            coOccurrence: coOccurrence,
            entries: entries
        )
    }

    func hitTest(at point: SIMD2<Float>) -> Int? {
        particleSystem?.hitTest(screenPoint: point, uniforms: uniforms)
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        uniforms.viewportSize = SIMD2<Float>(Float(size.width), Float(size.height))
    }

    func draw(in view: MTKView) {
        guard let particleSystem, particleSystem.particleCount > 0 else { return }
        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor else { return }

        let now = CFAbsoluteTimeGetCurrent()
        var deltaTime = Float(now - lastFrameTime)
        lastFrameTime = now
        deltaTime = min(deltaTime, 0.05)

        uniforms.time += deltaTime
        uniforms.globalRotation += 0.02 * deltaTime
        uniforms.zoom = zoom
        uniforms.highlightIndex = highlightIndex
        uniforms.dimFactor = dimFactor
        uniforms.colorMode = colorMode
        uniforms.audioAmplitude = audioAmplitude

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        // Compute pass
        if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
            computeEncoder.setComputePipelineState(computePipeline)
            computeEncoder.setBuffer(particleSystem.particleBuffer, offset: 0, index: 0)
            computeEncoder.setBytes(&uniforms, length: MemoryLayout<GalaxyUniforms>.stride, index: 1)
            computeEncoder.setBytes(&deltaTime, length: MemoryLayout<Float>.stride, index: 2)

            let threadCount = particleSystem.particleCount
            let threadgroupSize = min(computePipeline.maxTotalThreadsPerThreadgroup, 256)
            computeEncoder.dispatchThreads(
                MTLSize(width: threadCount, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: threadgroupSize, height: 1, depth: 1)
            )
            computeEncoder.endEncoding()
        }

        // Render pass
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store

        if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) {
            // 1) Background: procedural galaxy nebula
            renderEncoder.setRenderPipelineState(backgroundPipeline)
            renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<GalaxyUniforms>.stride, index: 1)
            renderEncoder.setFragmentBytes(&audioLevels, length: MemoryLayout<Float>.stride * 32, index: 2)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

            // 2) Particles on top
            renderEncoder.setRenderPipelineState(renderPipeline)
            renderEncoder.setVertexBuffer(particleSystem.particleBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<GalaxyUniforms>.stride, index: 1)
            renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<GalaxyUniforms>.stride, index: 1)
            renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: particleSystem.particleCount)
            renderEncoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
