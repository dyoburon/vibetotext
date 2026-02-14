import MetalKit
import simd
import Foundation

// Same uniform layout as ui_standalone.py: 16 floats (mvp) + time + amplitude + 2 seeds
struct SphereUniforms {
    var mvp: simd_float4x4
    var time: Float
    var amplitude: Float
    var noiseSeedX: Float
    var noiseSeedY: Float
}

final class SpherePreviewRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let spherePipeline: MTLRenderPipelineState
    let blurHPipeline: MTLRenderPipelineState
    let blurVPipeline: MTLRenderPipelineState
    let compositePipeline: MTLRenderPipelineState
    let vertexBuffer: MTLBuffer
    let numVertices: Int

    var texMain: MTLTexture?
    var texBlurH: MTLTexture?
    var texBlurV: MTLTexture?
    var texW: Int = 0
    var texH: Int = 0

    var startTime: CFAbsoluteTime
    var rotation: Float = 0
    var smoothAmp: Float = 0

    init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        self.startTime = CFAbsoluteTimeGetCurrent()

        // Read sphere.metal source from vibetotext
        let shaderPath = NSString(string: "~/Desktop/projects/vibetotext/src/vibetotext/sphere.metal").expandingTildeInPath
        guard let shaderSource = try? String(contentsOfFile: shaderPath, encoding: .utf8) else {
            print("Failed to read sphere.metal")
            return nil
        }

        let options = MTLCompileOptions()
        guard let library = try? device.makeLibrary(source: shaderSource, options: options) else {
            print("Failed to compile sphere shaders")
            return nil
        }

        // Sphere mesh (48 lat x 64 lon, same as ui_standalone.py)
        let (meshData, vertCount) = SpherePreviewRenderer.generateSphereMesh(nLat: 48, nLon: 64)
        self.numVertices = vertCount
        self.vertexBuffer = device.makeBuffer(bytes: meshData, length: meshData.count, options: .storageModeShared)!

        // Vertex descriptor: position(3f) + normal(3f) + bary(3f) = 36 bytes
        let vd = MTLVertexDescriptor()
        vd.attributes[0].format = .float3; vd.attributes[0].offset = 0; vd.attributes[0].bufferIndex = 0
        vd.attributes[1].format = .float3; vd.attributes[1].offset = 12; vd.attributes[1].bufferIndex = 0
        vd.attributes[2].format = .float3; vd.attributes[2].offset = 24; vd.attributes[2].bufferIndex = 0
        vd.layouts[0].stride = 36

        // Sphere pipeline -> RGBA16Float offscreen
        let sphereDesc = MTLRenderPipelineDescriptor()
        sphereDesc.vertexFunction = library.makeFunction(name: "vertex_sphere")
        sphereDesc.fragmentFunction = library.makeFunction(name: "fragment_sphere")
        sphereDesc.vertexDescriptor = vd
        sphereDesc.colorAttachments[0].pixelFormat = .rgba16Float
        sphereDesc.colorAttachments[0].isBlendingEnabled = true
        sphereDesc.colorAttachments[0].sourceRGBBlendFactor = .one
        sphereDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        sphereDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        sphereDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let sps = try? device.makeRenderPipelineState(descriptor: sphereDesc) else { return nil }
        self.spherePipeline = sps

        // Blur H pipeline
        let blurHDesc = MTLRenderPipelineDescriptor()
        blurHDesc.vertexFunction = library.makeFunction(name: "vertex_quad")
        blurHDesc.fragmentFunction = library.makeFunction(name: "fragment_blur_h")
        blurHDesc.colorAttachments[0].pixelFormat = .rgba16Float
        guard let bhps = try? device.makeRenderPipelineState(descriptor: blurHDesc) else { return nil }
        self.blurHPipeline = bhps

        // Blur V pipeline
        let blurVDesc = MTLRenderPipelineDescriptor()
        blurVDesc.vertexFunction = library.makeFunction(name: "vertex_quad")
        blurVDesc.fragmentFunction = library.makeFunction(name: "fragment_blur_v")
        blurVDesc.colorAttachments[0].pixelFormat = .rgba16Float
        guard let bvps = try? device.makeRenderPipelineState(descriptor: blurVDesc) else { return nil }
        self.blurVPipeline = bvps

        // Composite pipeline -> BGRA8
        let compDesc = MTLRenderPipelineDescriptor()
        compDesc.vertexFunction = library.makeFunction(name: "vertex_quad")
        compDesc.fragmentFunction = library.makeFunction(name: "fragment_composite")
        compDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        compDesc.colorAttachments[0].isBlendingEnabled = false
        guard let cps = try? device.makeRenderPipelineState(descriptor: compDesc) else { return nil }
        self.compositePipeline = cps

        super.init()
    }

    // MARK: - Mesh generation (matches ui_standalone.py)

    static func generateSphereMesh(nLat: Int, nLon: Int) -> ([UInt8], Int) {
        var data = [Float]()
        var numVerts = 0
        let bary: [[Float]] = [[1,0,0], [0,1,0], [0,0,1]]

        var grid = [[(Float, Float, Float)]]()
        for i in 0...nLat {
            let phi = Float.pi * Float(i) / Float(nLat)
            var row = [(Float, Float, Float)]()
            for j in 0...nLon {
                let theta = 2.0 * Float.pi * Float(j) / Float(nLon)
                let x = sin(phi) * cos(theta)
                let y = cos(phi)
                let z = sin(phi) * sin(theta)
                row.append((x, y, z))
            }
            grid.append(row)
        }

        for i in 0..<nLat {
            for j in 0..<nLon {
                let p00 = grid[i][j], p10 = grid[i][j+1], p01 = grid[i+1][j], p11 = grid[i+1][j+1]
                for (k, p) in [p00, p10, p01].enumerated() {
                    let b = bary[k]
                    data.append(contentsOf: [p.0, p.1, p.2, p.0, p.1, p.2, b[0], b[1], b[2]])
                }
                for (k, p) in [p10, p11, p01].enumerated() {
                    let b = bary[k]
                    data.append(contentsOf: [p.0, p.1, p.2, p.0, p.1, p.2, b[0], b[1], b[2]])
                }
                numVerts += 6
            }
        }

        let bytes = data.withUnsafeBufferPointer { ptr in
            Array(UnsafeBufferPointer(start: ptr.baseAddress!.withMemoryRebound(to: UInt8.self, capacity: data.count * 4) { $0 },
                                      count: data.count * 4))
        }
        return (bytes, numVerts)
    }

    // MARK: - Textures

    func ensureTextures(w: Int, h: Int) {
        guard w != texW || h != texH || texMain == nil else { return }
        texW = w; texH = h
        for name in ["texMain", "texBlurH", "texBlurV"] {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
            desc.usage = [.renderTarget, .shaderRead]
            desc.storageMode = .private
            let tex = device.makeTexture(descriptor: desc)!
            switch name {
            case "texMain": texMain = tex
            case "texBlurH": texBlurH = tex
            case "texBlurV": texBlurV = tex
            default: break
            }
        }
    }

    // MARK: - Matrix helpers

    static func perspective(fov: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let f = 1.0 / tan(fov / 2.0)
        let nf = near - far
        return simd_float4x4(columns: (
            SIMD4(f / aspect, 0, 0, 0),
            SIMD4(0, f, 0, 0),
            SIMD4(0, 0, (far + near) / nf, -1),
            SIMD4(0, 0, (2 * far * near) / nf, 0)
        ))
    }

    static func translate(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(x, y, z, 1)
        return m
    }

    static func rotateY(_ angle: Float) -> simd_float4x4 {
        let c = cos(angle), s = sin(angle)
        return simd_float4x4(columns: (
            SIMD4(c, 0, s, 0), SIMD4(0, 1, 0, 0), SIMD4(-s, 0, c, 0), SIMD4(0, 0, 0, 1)
        ))
    }

    static func rotateX(_ angle: Float) -> simd_float4x4 {
        let c = cos(angle), s = sin(angle)
        return simd_float4x4(columns: (
            SIMD4(1, 0, 0, 0), SIMD4(0, c, -s, 0), SIMD4(0, s, c, 0), SIMD4(0, 0, 0, 1)
        ))
    }

    // MARK: - Draw

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable else { return }
        let tex = drawable.texture
        let w = tex.width, h = tex.height
        guard w > 0, h > 0 else { return }
        ensureTextures(w: w, h: h)

        let t = Float(CFAbsoluteTimeGetCurrent() - startTime)
        rotation += 0.006

        // Simulate pulsing audio
        let fakeAmp = (sin(t * 2.0) * 0.5 + 0.5) * 0.5
        smoothAmp = smoothAmp * 0.5 + fakeAmp * 0.5

        let proj = Self.perspective(fov: Float.pi / 4, aspect: 1.0, near: 0.1, far: 100)
        let view_ = Self.translate(0, 0, -3.2)
        let model = Self.rotateX(0.4) * Self.rotateY(rotation)
        let mvp = proj * view_ * model

        var uniforms = SphereUniforms(mvp: mvp, time: t, amplitude: smoothAmp, noiseSeedX: 0, noiseSeedY: 0)

        guard let cmd = commandQueue.makeCommandBuffer() else { return }

        // Pass 1: Sphere -> offscreen
        let rpd1 = MTLRenderPassDescriptor()
        rpd1.colorAttachments[0].texture = texMain
        rpd1.colorAttachments[0].loadAction = .clear
        rpd1.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        rpd1.colorAttachments[0].storeAction = .store
        if let enc = cmd.makeRenderCommandEncoder(descriptor: rpd1) {
            enc.setRenderPipelineState(spherePipeline)
            enc.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            enc.setVertexBytes(&uniforms, length: MemoryLayout<SphereUniforms>.stride, index: 1)
            enc.setFragmentBytes(&uniforms, length: MemoryLayout<SphereUniforms>.stride, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: numVertices)
            enc.endEncoding()
        }

        // Pass 2: Blur H
        let rpd2 = MTLRenderPassDescriptor()
        rpd2.colorAttachments[0].texture = texBlurH
        rpd2.colorAttachments[0].loadAction = .clear
        rpd2.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        rpd2.colorAttachments[0].storeAction = .store
        if let enc = cmd.makeRenderCommandEncoder(descriptor: rpd2) {
            enc.setRenderPipelineState(blurHPipeline)
            enc.setFragmentTexture(texMain, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            enc.endEncoding()
        }

        // Pass 3: Blur V
        let rpd3 = MTLRenderPassDescriptor()
        rpd3.colorAttachments[0].texture = texBlurV
        rpd3.colorAttachments[0].loadAction = .clear
        rpd3.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        rpd3.colorAttachments[0].storeAction = .store
        if let enc = cmd.makeRenderCommandEncoder(descriptor: rpd3) {
            enc.setRenderPipelineState(blurVPipeline)
            enc.setFragmentTexture(texBlurH, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            enc.endEncoding()
        }

        // Pass 4: Composite -> screen
        let rpd4 = MTLRenderPassDescriptor()
        rpd4.colorAttachments[0].texture = tex
        rpd4.colorAttachments[0].loadAction = .clear
        rpd4.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd4.colorAttachments[0].storeAction = .store
        if let enc = cmd.makeRenderCommandEncoder(descriptor: rpd4) {
            enc.setRenderPipelineState(compositePipeline)
            enc.setFragmentBytes(&uniforms, length: MemoryLayout<SphereUniforms>.stride, index: 0)
            enc.setFragmentTexture(texMain, index: 0)
            enc.setFragmentTexture(texBlurV, index: 1)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            enc.endEncoding()
        }

        cmd.present(drawable)
        cmd.commit()
    }
}
