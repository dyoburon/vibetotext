let treeShaderSource: String = #"""
#include <metal_stdlib>
using namespace metal;

// ── Simplex 3D noise ──
float3 tmod289(float3 x) { return x - floor(x / 289.0) * 289.0; }
float4 tmod289(float4 x) { return x - floor(x / 289.0) * 289.0; }
float4 tpermute(float4 x) { return tmod289((x * 34.0 + 1.0) * x); }
float4 ttaylorInvSqrt(float4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

float tsnoise(float3 v) {
    const float2 C = float2(1.0/6.0, 1.0/3.0);
    float3 i = floor(v + dot(v, float3(C.y)));
    float3 x0 = v - i + dot(i, float3(C.x));
    float3 g = step(x0.yzx, x0.xyz);
    float3 l = 1.0 - g;
    float3 i1 = min(g, l.zxy);
    float3 i2 = max(g, l.zxy);
    float3 x1 = x0 - i1 + C.x;
    float3 x2 = x0 - i2 + C.y;
    float3 x3 = x0 - 0.5;
    i = tmod289(i);
    float4 p = tpermute(tpermute(tpermute(
        i.z + float4(0, i1.z, i2.z, 1))
        + i.y + float4(0, i1.y, i2.y, 1))
        + i.x + float4(0, i1.x, i2.x, 1));
    float n_ = 0.142857142857;
    float3 ns = n_ * float3(2, 1, 0) - float3(1, 0.5, 0);
    float4 j = p - 49.0 * floor(p * ns.z * ns.z);
    float4 x_ = floor(j * ns.z);
    float4 y_ = floor(j - 7.0 * x_);
    float4 x2_ = x_ * ns.x + ns.y;
    float4 y2_ = y_ * ns.x + ns.y;
    float4 h = 1.0 - abs(x2_) - abs(y2_);
    float4 b0 = float4(x2_.xy, y2_.xy);
    float4 b1 = float4(x2_.zw, y2_.zw);
    float4 s0 = floor(b0) * 2.0 + 1.0;
    float4 s1 = floor(b1) * 2.0 + 1.0;
    float4 sh = -step(h, float4(0.0));
    float4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    float4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
    float3 p0 = float3(a0.xy, h.x);
    float3 p1 = float3(a0.zw, h.y);
    float3 p2 = float3(a1.xy, h.z);
    float3 p3 = float3(a1.zw, h.w);
    float4 norm = ttaylorInvSqrt(float4(dot(p0,p0),dot(p1,p1),dot(p2,p2),dot(p3,p3)));
    p0 *= norm.x; p1 *= norm.y; p2 *= norm.z; p3 *= norm.w;
    float4 m = max(0.6 - float4(dot(x0,x0),dot(x1,x1),dot(x2,x2),dot(x3,x3)), 0.0);
    m = m * m;
    return 42.0 * dot(m * m, float4(dot(p0,x0),dot(p1,x1),dot(p2,x2),dot(p3,x3)));
}

// ── Uniforms ──
struct TreeUniforms {
    float4x4 mvp;
    float time;
    float deltaTime;
    float health;
    float season;
    int streak_tier;
    float growth_progress;
    float word_density;
    float noise_seed;
    float wind_strength;
    float rotation;
    float padding2;
    float padding3;
};

// ── Background ──
struct BGVOut {
    float4 position [[position]];
    float2 uv;
};

vertex BGVOut vertex_tree_bg(uint vid [[vertex_id]]) {
    float2 pos;
    pos.x = (vid == 1) ? 3.0 : -1.0;
    pos.y = (vid == 2) ? 3.0 : -1.0;
    BGVOut out;
    out.position = float4(pos, 0.999, 1.0);
    out.uv = pos * 0.5 + 0.5;
    return out;
}

fragment float4 fragment_tree_bg(BGVOut in [[stage_in]], constant TreeUniforms& u [[buffer(1)]]) {
    float3 top = float3(0.02, 0.02, 0.06);
    float3 mid = float3(0.01, 0.01, 0.02);
    float3 bottom = float3(0.04, 0.03, 0.02);
    float t = in.uv.y;
    float3 col = t > 0.5 ? mix(mid, top, (t - 0.5) * 2.0) : mix(bottom, mid, t * 2.0);
    return float4(col, 1.0);
}

// ── Tree Vertex/Fragment ──
struct TreeVertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float2 uv       [[attribute(2)]];
    float branchId  [[attribute(3)]];
};

struct TreeVOut {
    float4 position [[position]];
    float3 normal;
    float2 uv;
    float3 worldPos;
};

vertex TreeVOut vertex_tree(
    TreeVertexIn in [[stage_in]],
    constant TreeUniforms& u [[buffer(1)]]
) {
    float3 pos = float3(in.position);

    // Growth: squish vertices above the growth line down
    float maxH = -1.0 + u.growth_progress * 3.5;
    if (pos.y > maxH) {
        pos.y = maxH;
    }

    // (wind sway disabled for now)

    TreeVOut out;
    out.position = u.mvp * float4(pos, 1.0);
    out.normal = float3(in.normal);
    out.uv = in.uv;
    out.worldPos = pos;
    return out;
}

fragment float4 fragment_tree(
    TreeVOut in [[stage_in]],
    constant TreeUniforms& u [[buffer(1)]]
) {
    return float4(0.25, 0.15, 0.08, 1.0);
}

// ── Leaves (point sprites) ──
struct LeafData {
    packed_float3 position;
    float size;
};

struct LeafVOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float season;
    float health;
};

vertex LeafVOut vertex_leaf(
    device const LeafData* leaves [[buffer(0)]],
    constant TreeUniforms& u [[buffer(1)]],
    uint vid [[vertex_id]]
) {
    LeafData lf = leaves[vid];
    float3 pos = float3(lf.position);

    // Hide leaves above growth line
    float maxH = -1.0 + u.growth_progress * 3.5;
    if (pos.y > maxH) {
        LeafVOut out;
        out.position = float4(0.0, 0.0, -10.0, 1.0);
        out.pointSize = 0.0;
        out.season = u.season;
        out.health = u.health;
        return out;
    }

    // (leaf sway disabled for now)

    LeafVOut out;
    out.position = u.mvp * float4(pos, 1.0);
    out.pointSize = lf.size * (0.4 + 0.6 * u.health);
    out.season = u.season;
    out.health = u.health;
    return out;
}

fragment float4 fragment_leaf(
    LeafVOut in [[stage_in]],
    float2 pointCoord [[point_coord]]
) {
    float dist = length(pointCoord - 0.5) * 2.0;
    float alpha = smoothstep(1.0, 0.4, dist) * in.health;

    // Seasonal leaf color
    float3 summer_col = float3(0.4, 0.78, 0.28);
    float3 spring_col = float3(0.55, 0.88, 0.4);
    float3 autumn_col = float3(0.9, 0.55, 0.15);
    float3 winter_col = float3(0.5, 0.42, 0.3);

    float3 col;
    if (in.season > 0.66) {
        col = mix(spring_col, summer_col, (in.season - 0.66) * 3.0);
    } else if (in.season > 0.33) {
        col = mix(autumn_col, spring_col, (in.season - 0.33) * 3.0);
    } else {
        col = mix(winter_col, autumn_col, in.season * 3.0);
    }

    return float4(col * alpha, alpha);
}

// ── Bloom particles (streak rewards) ──
vertex LeafVOut vertex_bloom(
    device const LeafData* blooms [[buffer(0)]],
    constant TreeUniforms& u [[buffer(1)]],
    uint vid [[vertex_id]]
) {
    LeafData bl = blooms[vid];
    float3 pos = float3(bl.position);

    // Pulse size
    float pulse = 1.0 + sin(u.time * 2.0 + float(vid) * 0.7) * 0.2;

    // (bloom sway disabled for now)

    LeafVOut out;
    out.position = u.mvp * float4(pos, 1.0);
    out.pointSize = bl.size * pulse * clamp(float(u.streak_tier), 1.0, 4.0);
    out.season = 1.0;
    out.health = 1.0;
    return out;
}

fragment float4 fragment_bloom(
    LeafVOut in [[stage_in]],
    float2 pointCoord [[point_coord]]
) {
    float dist = length(pointCoord - 0.5) * 2.0;
    float alpha = smoothstep(1.0, 0.0, dist);
    alpha = alpha * alpha;

    // Tier 1-2: buds (warm yellow), Tier 3-4: flowers (pink)
    float3 col = float3(1.0, 0.78, 0.88);
    return float4(col * alpha * 1.5, alpha);
}
"""#
