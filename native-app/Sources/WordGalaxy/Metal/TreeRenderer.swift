import MetalKit
import simd

struct TreeUniforms {
    var mvp: float4x4 = .init(1)
    var time: Float = 0
    var deltaTime: Float = 0
    var health: Float = 0.85
    var season: Float = 0.8
    var streak_tier: Int32 = 2
    var growth_progress: Float = 1.0
    var word_density: Float = 0.6
    var noise_seed: Float = 42.0
    var wind_strength: Float = 0.05
    var rotation: Float = 0
    var padding2: Float = 0
    var padding3: Float = 0
}

final class TreeRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue

    // Pipelines
    let bgPipeline: MTLRenderPipelineState
    let treePipeline: MTLRenderPipelineState
    let leafPipeline: MTLRenderPipelineState
    let bloomPipeline: MTLRenderPipelineState
    let depthStateWrite: MTLDepthStencilState
    let depthStateRead: MTLDepthStencilState
    let depthStateNone: MTLDepthStencilState

    // Buffers
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    let leafBuffer: MTLBuffer
    let bloomBuffer: MTLBuffer
    let indexCount: Int
    let leafCount: Int
    let bloomCount: Int

    var uniforms = TreeUniforms()
    var lastFrameTime: CFAbsoluteTime = 0
    var cameraRotation: Float = 0
    var frameCount = 0

    init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue

        // Debug log helper
        func dbg(_ msg: String) {
            let path = "/tmp/tree_renderer_debug.log"
            let line = msg + "\n"
            if let fh = FileHandle(forWritingAtPath: path) {
                fh.seekToEndOfFile()
                fh.write(line.data(using: .utf8)!)
                fh.closeFile()
            } else {
                FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
            }
        }

        // Compile shaders
        dbg("init started, compiling shaders...")
        let options = MTLCompileOptions()
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: treeShaderSource, options: options)
            dbg("shaders compiled OK")
        } catch {
            dbg("SHADER ERROR: \(error)")
            return nil
        }

        // ── Background pipeline ──
        guard let bgVert = library.makeFunction(name: "vertex_tree_bg"),
              let bgFrag = library.makeFunction(name: "fragment_tree_bg") else {
            print("Failed to find background functions"); return nil
        }
        let bgDesc = MTLRenderPipelineDescriptor()
        bgDesc.vertexFunction = bgVert
        bgDesc.fragmentFunction = bgFrag
        bgDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        bgDesc.depthAttachmentPixelFormat = .depth32Float
        guard let bgPS = try? device.makeRenderPipelineState(descriptor: bgDesc) else {
            print("Failed to create bg pipeline"); return nil
        }
        self.bgPipeline = bgPS

        // ── Tree pipeline (with vertex descriptor) ──
        let vd = MTLVertexDescriptor()
        // position: float3
        vd.attributes[0].format = .float3
        vd.attributes[0].offset = 0
        vd.attributes[0].bufferIndex = 0
        // normal: float3
        vd.attributes[1].format = .float3
        vd.attributes[1].offset = 12
        vd.attributes[1].bufferIndex = 0
        // uv: float2
        vd.attributes[2].format = .float2
        vd.attributes[2].offset = 24
        vd.attributes[2].bufferIndex = 0
        // branchId: float
        vd.attributes[3].format = .float
        vd.attributes[3].offset = 32
        vd.attributes[3].bufferIndex = 0
        // stride
        vd.layouts[0].stride = 36
        vd.layouts[0].stepRate = 1
        vd.layouts[0].stepFunction = .perVertex

        guard let treeVert = library.makeFunction(name: "vertex_tree"),
              let treeFrag = library.makeFunction(name: "fragment_tree") else {
            print("Failed to find tree functions"); return nil
        }
        let treeDesc = MTLRenderPipelineDescriptor()
        treeDesc.vertexFunction = treeVert
        treeDesc.fragmentFunction = treeFrag
        treeDesc.vertexDescriptor = vd
        treeDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        treeDesc.depthAttachmentPixelFormat = .depth32Float
        guard let treePS = try? device.makeRenderPipelineState(descriptor: treeDesc) else {
            print("Failed to create tree pipeline"); return nil
        }
        self.treePipeline = treePS

        // ── Leaf pipeline (point sprites, additive blend) ──
        guard let leafVert = library.makeFunction(name: "vertex_leaf"),
              let leafFrag = library.makeFunction(name: "fragment_leaf") else {
            print("Failed to find leaf functions"); return nil
        }
        let leafDesc = MTLRenderPipelineDescriptor()
        leafDesc.vertexFunction = leafVert
        leafDesc.fragmentFunction = leafFrag
        leafDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        leafDesc.colorAttachments[0].isBlendingEnabled = true
        leafDesc.colorAttachments[0].sourceRGBBlendFactor = .one
        leafDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        leafDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        leafDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        leafDesc.depthAttachmentPixelFormat = .depth32Float
        guard let leafPS = try? device.makeRenderPipelineState(descriptor: leafDesc) else {
            print("Failed to create leaf pipeline"); return nil
        }
        self.leafPipeline = leafPS

        // ── Bloom pipeline (additive glow) ──
        guard let bloomVert = library.makeFunction(name: "vertex_bloom"),
              let bloomFrag = library.makeFunction(name: "fragment_bloom") else {
            print("Failed to find bloom functions"); return nil
        }
        let bloomDesc = MTLRenderPipelineDescriptor()
        bloomDesc.vertexFunction = bloomVert
        bloomDesc.fragmentFunction = bloomFrag
        bloomDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        bloomDesc.colorAttachments[0].isBlendingEnabled = true
        bloomDesc.colorAttachments[0].sourceRGBBlendFactor = .one
        bloomDesc.colorAttachments[0].destinationRGBBlendFactor = .one
        bloomDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        bloomDesc.colorAttachments[0].destinationAlphaBlendFactor = .one
        bloomDesc.depthAttachmentPixelFormat = .depth32Float
        guard let bloomPS = try? device.makeRenderPipelineState(descriptor: bloomDesc) else {
            print("Failed to create bloom pipeline"); return nil
        }
        self.bloomPipeline = bloomPS

        // ── Depth stencil states ──
        let dsWrite = MTLDepthStencilDescriptor()
        dsWrite.depthCompareFunction = .less
        dsWrite.isDepthWriteEnabled = true
        self.depthStateWrite = device.makeDepthStencilState(descriptor: dsWrite)!

        let dsRead = MTLDepthStencilDescriptor()
        dsRead.depthCompareFunction = .less
        dsRead.isDepthWriteEnabled = false
        self.depthStateRead = device.makeDepthStencilState(descriptor: dsRead)!

        let dsNone = MTLDepthStencilDescriptor()
        dsNone.depthCompareFunction = .always
        dsNone.isDepthWriteEnabled = false
        self.depthStateNone = device.makeDepthStencilState(descriptor: dsNone)!

        // ── Generate mesh ──
        let meshGen = TreeMeshGenerator()
        meshGen.generate(topicCount: 4, seed: 42.0, maxDepth: 4)

        let leaves = meshGen.generateLeaves(count: 600)
        let blooms = meshGen.generateBlooms(count: 25)

        self.indexCount = meshGen.indices.count
        self.leafCount = leaves.count
        self.bloomCount = blooms.count

        dbg("vertices: \(meshGen.vertices.count), indices: \(meshGen.indices.count), tips: \(meshGen.branchTips.count), leaves: \(leaves.count), blooms: \(blooms.count)")
        dbg("vertex stride: \(MemoryLayout<TreeVertex>.stride), leaf stride: \(MemoryLayout<LeafPoint>.stride)")
        if let first = meshGen.vertices.first {
            dbg("first vertex: pos=(\(first.px), \(first.py), \(first.pz))")
        }
        if let tip = meshGen.branchTips.first {
            dbg("first tip: (\(tip.x), \(tip.y), \(tip.z))")
        }

        let vbSize = MemoryLayout<TreeVertex>.stride * max(meshGen.vertices.count, 1)
        self.vertexBuffer = device.makeBuffer(bytes: meshGen.vertices, length: vbSize, options: .storageModeShared)!

        let ibSize = MemoryLayout<UInt32>.stride * max(meshGen.indices.count, 1)
        self.indexBuffer = device.makeBuffer(bytes: meshGen.indices, length: ibSize, options: .storageModeShared)!

        let lfSize = MemoryLayout<LeafPoint>.stride * max(leaves.count, 1)
        self.leafBuffer = device.makeBuffer(bytes: leaves, length: lfSize, options: .storageModeShared)!

        let blSize = MemoryLayout<LeafPoint>.stride * max(blooms.count, 1)
        self.bloomBuffer = device.makeBuffer(bytes: blooms, length: blSize, options: .storageModeShared)!

        super.init()
        self.lastFrameTime = CFAbsoluteTimeGetCurrent()
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor else { return }

        let now = CFAbsoluteTimeGetCurrent()
        var dt = Float(now - lastFrameTime)
        lastFrameTime = now
        dt = min(dt, 0.05)

        uniforms.time += dt
        uniforms.deltaTime = dt
        cameraRotation += dt * 0.015
        frameCount += 1
        if frameCount == 1 || frameCount == 60 {
            print("[TreeRenderer] draw frame \(frameCount), indexCount=\(indexCount), leafCount=\(leafCount)")
            print("[TreeRenderer] mvp[0][0]=\(uniforms.mvp[0][0]), drawableSize=\(view.drawableSize)")
        }

        // Build MVP
        let aspect = Float(view.drawableSize.width / view.drawableSize.height)
        uniforms.mvp = makeMVP(aspect: aspect, rotation: cameraRotation)
        uniforms.rotation = cameraRotation

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.depthAttachment.clearDepth = 1.0
        rpd.depthAttachment.loadAction = .clear
        rpd.depthAttachment.storeAction = .dontCare

        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return }

        // 1) Background
        enc.setDepthStencilState(depthStateNone)
        enc.setRenderPipelineState(bgPipeline)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<TreeUniforms>.stride, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        // 2) Tree (opaque, depth write)
        enc.setDepthStencilState(depthStateWrite)
        enc.setRenderPipelineState(treePipeline)
        enc.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        enc.setVertexBytes(&uniforms, length: MemoryLayout<TreeUniforms>.stride, index: 1)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<TreeUniforms>.stride, index: 1)
        enc.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indexCount,
            indexType: .uint32,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0
        )

        // 3) Leaves (alpha blend, depth read only)
        enc.setDepthStencilState(depthStateRead)
        enc.setRenderPipelineState(leafPipeline)
        enc.setVertexBuffer(leafBuffer, offset: 0, index: 0)
        enc.setVertexBytes(&uniforms, length: MemoryLayout<TreeUniforms>.stride, index: 1)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<TreeUniforms>.stride, index: 1)
        enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: leafCount)

        // 4) Blooms (additive glow)
        if uniforms.streak_tier > 0 {
            enc.setRenderPipelineState(bloomPipeline)
            enc.setVertexBuffer(bloomBuffer, offset: 0, index: 0)
            enc.setVertexBytes(&uniforms, length: MemoryLayout<TreeUniforms>.stride, index: 1)
            enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: bloomCount)
        }

        enc.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Camera

    private func makeMVP(aspect: Float, rotation: Float) -> float4x4 {
        let proj = perspectiveMatrix(fovY: .pi / 3.5, aspect: aspect, near: 0.1, far: 100)
        let eye = SIMD3<Float>(
            sin(rotation) * 5.0,
            1.0,
            cos(rotation) * 5.0
        )
        let view = lookAtMatrix(eye: eye, center: SIMD3<Float>(0, 0.5, 0), up: SIMD3<Float>(0, 1, 0))
        return proj * view
    }

    private func perspectiveMatrix(fovY: Float, aspect: Float, near: Float, far: Float) -> float4x4 {
        let y = 1 / tan(fovY * 0.5)
        let x = y / aspect
        let z = far / (near - far)
        return float4x4(columns: (
            SIMD4<Float>(x, 0, 0, 0),
            SIMD4<Float>(0, y, 0, 0),
            SIMD4<Float>(0, 0, z, -1),
            SIMD4<Float>(0, 0, z * near, 0)
        ))
    }

    private func lookAtMatrix(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> float4x4 {
        let f = simd_normalize(center - eye)
        let s = simd_normalize(simd_cross(f, up))
        let u = simd_cross(s, f)
        return float4x4(columns: (
            SIMD4<Float>(s.x, u.x, -f.x, 0),
            SIMD4<Float>(s.y, u.y, -f.y, 0),
            SIMD4<Float>(s.z, u.z, -f.z, 0),
            SIMD4<Float>(-simd_dot(s, eye), -simd_dot(u, eye), simd_dot(f, eye), 1)
        ))
    }
}
