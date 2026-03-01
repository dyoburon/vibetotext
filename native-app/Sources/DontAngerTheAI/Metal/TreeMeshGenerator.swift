import simd

struct TreeVertex {
    var px: Float; var py: Float; var pz: Float
    var nx: Float; var ny: Float; var nz: Float
    var u: Float;  var v: Float
    var branchId: Float
}

struct LeafPoint {
    var px: Float; var py: Float; var pz: Float
    var size: Float
}

final class TreeMeshGenerator {
    var vertices: [TreeVertex] = []
    var indices: [UInt32] = []
    var branchTips: [SIMD3<Float>] = []

    private let vertsPerRing = 8
    private let ringsPerSegment = 4

    func generate(topicCount: Int = 4, seed: Float = 42.0, maxDepth: Int = 4) {
        vertices.removeAll()
        indices.removeAll()
        branchTips.removeAll()

        growBranch(
            from: SIMD3<Float>(0, -1, 0),
            direction: SIMD3<Float>(0, 1, 0),
            length: 1.2,
            radius: 0.12,
            depth: 0,
            maxDepth: maxDepth,
            numChildren: topicCount,
            seed: seed,
            branchId: 0
        )
    }

    private func growBranch(
        from start: SIMD3<Float>,
        direction: SIMD3<Float>,
        length: Float,
        radius: Float,
        depth: Int,
        maxDepth: Int,
        numChildren: Int,
        seed: Float,
        branchId: Float
    ) {
        let end = start + direction * length
        let endRadius = radius * 0.72

        addCylinder(from: start, to: end, startRadius: radius, endRadius: endRadius, branchId: branchId)

        if depth >= maxDepth {
            branchTips.append(end)
            return
        }

        let children = depth == 0 ? max(numChildren, 3) : (depth < 2 ? 3 : 2)
        let childLength = length * 0.65
        let childRadius = endRadius * 0.9

        for i in 0..<children {
            let angle = Float(i) / Float(children) * 2 * .pi + seed * 0.37 + Float(depth) * 1.1
            let spread: Float = 0.35 + Float(depth) * 0.1

            let newDir = spreadDirection(direction, angle: angle, spread: spread)

            growBranch(
                from: end,
                direction: simd_normalize(newDir),
                length: childLength,
                radius: childRadius,
                depth: depth + 1,
                maxDepth: maxDepth,
                numChildren: children,
                seed: seed + Float(i) * 13.7 + Float(depth) * 7.3,
                branchId: Float(i + 1) + branchId * 10
            )
        }
    }

    private func spreadDirection(_ dir: SIMD3<Float>, angle: Float, spread: Float) -> SIMD3<Float> {
        let up: SIMD3<Float> = abs(dir.y) < 0.99
            ? SIMD3<Float>(0, 1, 0)
            : SIMD3<Float>(1, 0, 0)
        let right = simd_normalize(simd_cross(dir, up))
        let forward = simd_normalize(simd_cross(right, dir))

        let sx = sin(spread) * cos(angle)
        let sz = sin(spread) * sin(angle)
        let sy = cos(spread)

        return dir * sy + right * sx + forward * sz
    }

    private func addCylinder(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        startRadius: Float,
        endRadius: Float,
        branchId: Float
    ) {
        let axis = end - start
        let length = simd_length(axis)
        guard length > 0.001 else { return }
        let axisNorm = axis / length

        let up: SIMD3<Float> = abs(axisNorm.y) < 0.99
            ? SIMD3<Float>(0, 1, 0)
            : SIMD3<Float>(1, 0, 0)
        let right = simd_normalize(simd_cross(axisNorm, up))
        let forward = simd_normalize(simd_cross(right, axisNorm))

        let baseIndex = UInt32(vertices.count)

        for ring in 0...ringsPerSegment {
            let t = Float(ring) / Float(ringsPerSegment)
            let center = start + axis * t
            let radius = startRadius + (endRadius - startRadius) * t

            for vi in 0..<vertsPerRing {
                let angle = Float(vi) / Float(vertsPerRing) * 2 * .pi
                let x = cos(angle)
                let z = sin(angle)

                let normal = simd_normalize(right * x + forward * z)
                let position = center + normal * radius
                let uv = SIMD2<Float>(Float(vi) / Float(vertsPerRing), t)

                vertices.append(TreeVertex(
                    px: position.x, py: position.y, pz: position.z,
                    nx: normal.x, ny: normal.y, nz: normal.z,
                    u: uv.x, v: uv.y,
                    branchId: branchId
                ))
            }
        }

        // Triangles connecting rings
        for ring in 0..<ringsPerSegment {
            for vi in 0..<vertsPerRing {
                let nextV = (vi + 1) % vertsPerRing
                let curr = baseIndex + UInt32(ring * vertsPerRing + vi)
                let next = baseIndex + UInt32(ring * vertsPerRing + nextV)
                let above = baseIndex + UInt32((ring + 1) * vertsPerRing + vi)
                let aboveNext = baseIndex + UInt32((ring + 1) * vertsPerRing + nextV)

                indices.append(contentsOf: [curr, above, next])
                indices.append(contentsOf: [next, above, aboveNext])
            }
        }
    }

    // Generate leaf positions scattered around branch tips
    func generateLeaves(count: Int = 500) -> [LeafPoint] {
        guard !branchTips.isEmpty else { return [] }
        var leaves: [LeafPoint] = []
        leaves.reserveCapacity(count)

        for i in 0..<count {
            let tipIndex = i % branchTips.count
            let tip = branchTips[tipIndex]

            let h1 = Self.hashFloat(UInt32(i))
            let h2 = Self.hashFloat(UInt32(i + 7919))
            let h3 = Self.hashFloat(UInt32(i + 15731))

            let offset = SIMD3<Float>(
                (h1 - 0.5) * 0.18,
                (h2 - 0.5) * 0.14,
                (h3 - 0.5) * 0.18
            )

            let size: Float = 5.0 + h1 * 7.0

            leaves.append(LeafPoint(
                px: tip.x + offset.x,
                py: tip.y + offset.y,
                pz: tip.z + offset.z,
                size: size
            ))
        }
        return leaves
    }

    // Generate bloom positions at branch tips (for streak rewards)
    func generateBlooms(count: Int = 30) -> [LeafPoint] {
        guard !branchTips.isEmpty else { return [] }
        var blooms: [LeafPoint] = []

        for i in 0..<min(count, branchTips.count) {
            let tip = branchTips[i]
            let h = Self.hashFloat(UInt32(i + 50000))
            blooms.append(LeafPoint(
                px: tip.x + (h - 0.5) * 0.03,
                py: tip.y + 0.02,
                pz: tip.z + (h - 0.5) * 0.03,
                size: 8.0 + h * 6.0
            ))
        }
        return blooms
    }

    static func hashFloat(_ x: UInt32) -> Float {
        var h = x
        h = ((h >> 16) ^ h) &* 0x45d9f3b
        h = ((h >> 16) ^ h) &* 0x45d9f3b
        h = (h >> 16) ^ h
        return Float(h & 0xFFFF) / 65535.0
    }
}
