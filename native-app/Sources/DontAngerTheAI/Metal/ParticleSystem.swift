import Metal
import simd

struct ParticleData {
    var orbitalRadius: Float
    var angle: Float
    var angularSpeed: Float
    var brightness: Float
    var size: Float
    var noisePhase: Float
    var colorMix: Float  // frequency-based: 0=rare, 1=common
    var ageFraction: Float  // 0=oldest, 1=newest
    var baseAngle: Float
    var baseRadius: Float
    var clusterID: Float
    var armIndex: Float
}

struct GalaxyUniforms {
    var time: Float = 0
    var globalRotation: Float = 0
    var viewportSize: SIMD2<Float> = .zero
    var zoom: Float = 1.0
    var highlightIndex: Int32 = -1
    var dimFactor: Float = 1.0
    var colorMode: Int32 = 0
    var audioAmplitude: Float = 0
}

final class ParticleSystem {
    let particleCount: Int
    let particleBuffer: MTLBuffer
    var words: [String]
    var wordCounts: [Int]
    var wordIndices: [String: Int]

    static let maxOrbitalRadius: Float = 0.85
    static let minParticleSize: Float = 2.0
    static let maxParticleSize: Float = 14.0
    static let orbitalSpeedFactor: Float = 0.3

    init(device: MTLDevice,
         wordFrequencies: [WordFrequency],
         coOccurrence: [String: [(String, Int)]] = [:],
         entries: [TranscriptionEntry] = []) {
        let freqs = Array(wordFrequencies.prefix(8000))
        self.particleCount = freqs.count
        self.words = freqs.map(\.word)
        self.wordCounts = freqs.map(\.count)
        self.wordIndices = Dictionary(uniqueKeysWithValues: freqs.enumerated().map { ($1.word, $0) })

        let arms = 3
        let twist: Float = 2.8  // full rotations over galaxy radius

        var particles: [ParticleData] = []
        particles.reserveCapacity(particleCount)

        for (i, wf) in freqs.enumerated() {
            let nf = wf.normalizedFrequency

            // Radius from frequency: common words just outside ring, rare at edge
            let minR: Float = 0.52  // just outside the black hole ring
            let r = minR + (Self.maxOrbitalRadius - minR) * pow(1.0 - nf, 0.45)

            // Arm assignment: simple modulo
            let arm = i % arms

            // Spiral angle: arm offset + twist proportional to radius
            let armBase = Float(arm) * (2.0 * .pi / Float(arms))
            let spiralAngle = (r / Self.maxOrbitalRadius) * twist * 2.0 * .pi
            let scatter = (Self.hashFloat(UInt32(i)) - 0.5) * 0.55
            let angle = armBase + spiralAngle + scatter

            let brightness: Float = 0.15 + 0.85 * nf
            let size = Self.minParticleSize + (Self.maxParticleSize - Self.minParticleSize) * nf
            let speed = r > 0.01 ? Self.orbitalSpeedFactor / sqrt(r) : Self.orbitalSpeedFactor * 10
            let noisePhase = Float(i) * 0.37

            particles.append(ParticleData(
                orbitalRadius: r,
                angle: angle,
                angularSpeed: speed,
                brightness: brightness,
                size: size,
                noisePhase: noisePhase,
                colorMix: nf,
                ageFraction: wf.ageFraction,
                baseAngle: angle,
                baseRadius: r,
                clusterID: 0,
                armIndex: Float(arm)
            ))
        }

        let bufferSize = MemoryLayout<ParticleData>.stride * max(particleCount, 1)
        self.particleBuffer = device.makeBuffer(
            bytes: particles,
            length: bufferSize,
            options: .storageModeShared
        )!
    }

    static func hashFloat(_ x: UInt32) -> Float {
        var h = x
        h = ((h >> 16) ^ h) &* 0x45d9f3b
        h = ((h >> 16) ^ h) &* 0x45d9f3b
        h = (h >> 16) ^ h
        return Float(h & 0xFFFF) / 65535.0
    }

    func screenPosition(index: Int, uniforms: GalaxyUniforms) -> SIMD2<Float>? {
        guard index >= 0 && index < particleCount else { return nil }
        let ptr = particleBuffer.contents().bindMemory(to: ParticleData.self, capacity: particleCount)
        let p = ptr[index]
        let totalAngle = p.angle + uniforms.globalRotation
        let x = p.orbitalRadius * cos(totalAngle) * uniforms.zoom
        let y = p.orbitalRadius * sin(totalAngle) * uniforms.zoom
        let vx = (x + 1.0) * 0.5 * uniforms.viewportSize.x
        let vy = (1.0 - y) * 0.5 * uniforms.viewportSize.y
        return SIMD2<Float>(vx, vy)
    }

    func hitTest(screenPoint: SIMD2<Float>, uniforms: GalaxyUniforms, threshold: Float = 20) -> Int? {
        let ptr = particleBuffer.contents().bindMemory(to: ParticleData.self, capacity: particleCount)
        var bestIndex: Int? = nil
        var bestDist: Float = threshold

        for i in 0..<particleCount {
            let p = ptr[i]
            let totalAngle = p.angle + uniforms.globalRotation
            let x = p.orbitalRadius * cos(totalAngle) * uniforms.zoom
            let y = p.orbitalRadius * sin(totalAngle) * uniforms.zoom
            let vx = (x + 1.0) * 0.5 * uniforms.viewportSize.x
            let vy = (1.0 - y) * 0.5 * uniforms.viewportSize.y
            let dx = vx - screenPoint.x
            let dy = vy - screenPoint.y
            let dist = sqrt(dx * dx + dy * dy)
            if dist < bestDist {
                bestDist = dist
                bestIndex = i
            }
        }
        return bestIndex
    }
}
