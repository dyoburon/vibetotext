#include <metal_stdlib>
using namespace metal;

// ── Simplex 3D noise (Stefan Gustavson) ──
float3 mod289(float3 x) { return x - floor(x / 289.0) * 289.0; }
float4 mod289(float4 x) { return x - floor(x / 289.0) * 289.0; }
float4 permute(float4 x) { return mod289((x * 34.0 + 1.0) * x); }
float4 taylorInvSqrt(float4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

float snoise(float3 v) {
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
    i = mod289(i);
    float4 p = permute(permute(permute(
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
    float4 norm = taylorInvSqrt(float4(dot(p0,p0),dot(p1,p1),dot(p2,p2),dot(p3,p3)));
    p0 *= norm.x; p1 *= norm.y; p2 *= norm.z; p3 *= norm.w;
    float4 m = max(0.6 - float4(dot(x0,x0),dot(x1,x1),dot(x2,x2),dot(x3,x3)), 0.0);
    m = m * m;
    return 42.0 * dot(m * m, float4(dot(p0,x0),dot(p1,x1),dot(p2,x2),dot(p3,x3)));
}

// ── Uniforms ──
struct Uniforms {
    float4x4 mvp;
    float time;
    float amplitude;
    float noiseSeedX;
    float noiseSeedY;
};

// ── Sphere vertex/fragment ──
struct SphereVIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float3 bary     [[attribute(2)]];
};

struct SphereVOut {
    float4 position [[position]];
    float3 bary;
    float  ndotv;
    float3 worldPos;
};

vertex SphereVOut vertex_sphere(SphereVIn in [[stage_in]],
                                constant Uniforms& u [[buffer(1)]]) {
    // Expand sphere slightly with voice
    float scale = 1.0 + u.amplitude * 0.15;
    float3 disp = in.position * scale;

    // Subtle tangential displacement — dots drift along the surface
    float displacement_amp = 0.00000005;
    float speed = 0.1;
    float noise_scale = 5.0;
    float3 p = in.position * noise_scale;
    float t = u.time * speed;

    float dx = snoise(p + float3(t, 0.0, 0.0));
    float dy = snoise(p + float3(0.0, t, 0.0));
    float dz = snoise(p + float3(0.0, 0.0, t));

    float3 tang_disp = float3(dx, dy, dz) * displacement_amp;

    // Project to tangential (perpendicular to normal)
    float3 normal = normalize(in.normal);
    tang_disp -= dot(tang_disp, normal) * normal;

    // Apply and renormalize to keep on sphere
    disp += tang_disp;
    disp = normalize(disp) * scale;

    float3 new_normal = normalize(disp);
    float3 viewDir = normalize(float3(0, 0, 1));

    SphereVOut out;
    out.position = u.mvp * float4(disp, 1.0);
    out.bary = in.bary;
    out.worldPos = disp / scale;
    out.ndotv = abs(dot(new_normal, viewDir));
    return out;
}

fragment float4 fragment_sphere(SphereVOut in [[stage_in]],
                                constant Uniforms& u [[buffer(1)]]) {
    // 4 stacked noise layers at different scales + orientations
    float3 seed = float3(u.noiseSeedX, u.noiseSeedY, u.noiseSeedX + u.noiseSeedY);
    float3 p = in.worldPos;
    float t = u.time;

    float n1 = snoise(p * 0.8 + seed + float3(t * 0.02, t * 0.015, t * -0.018));
    float n2 = snoise(p * 1.5 + seed * 1.3 + float3(t * -0.015, t * 0.02, t * 0.01));
    float n3 = snoise(p * 2.8 + seed * 0.7 + float3(t * 0.01, t * -0.012, t * 0.02));
    float n4 = snoise(p * 4.5 + seed * 2.1 + float3(t * -0.008, t * 0.01, t * -0.015));

    // Combine: large shapes + medium detail + fine detail
    float mask = n1 * 0.45 + n2 * 0.3 + n3 * 0.15 + n4 * 0.1;

    // Continuous opacity — no hard edges, just bright and ghost regions
    float opacity = smoothstep(-0.4, 0.3, -mask);
    // Power curve pushes most values toward the dim end
    opacity = pow(opacity, 3.0) * 0.35 + 0.03;

    // Dots at triangle vertices — bright where barycentric coord is near 1.0
    float dotSize = 0.82;
    float dotGlow = 0.6;
    float maxBary = max(max(in.bary.x, in.bary.y), in.bary.z);
    float dot = smoothstep(dotSize, 1.0, maxBary);
    float glow = smoothstep(dotGlow, 1.0, maxBary) * 0.3;
    float fresnel = pow(1.0 - in.ndotv, 2.5) * 0.2;

    float3 col = float3(0.835, 0.349, 0.514);  // #D55983
    float a = (dot + glow + fresnel) * opacity;
    return float4(col * a, a);
}

// ── Fullscreen quad (for bloom passes) ──
struct QuadVOut {
    float4 position [[position]];
    float2 uv;
};

vertex QuadVOut vertex_quad(uint vid [[vertex_id]]) {
    float2 pos[4] = {float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1)};
    float2 uv[4]  = {float2(0,1),   float2(1,1),  float2(0,0),  float2(1,0)};
    QuadVOut out;
    out.position = float4(pos[vid], 0, 1);
    out.uv = uv[vid];
    return out;
}

fragment float4 fragment_blur_h(QuadVOut in [[stage_in]],
                                texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 texel = 1.0 / float2(tex.get_width(), tex.get_height());
    float weights[5] = {0.227027, 0.194596, 0.121622, 0.054054, 0.016216};
    float4 result = tex.sample(s, in.uv) * weights[0];
    for (int i = 1; i < 5; i++) {
        result += tex.sample(s, in.uv + float2(texel.x * i, 0)) * weights[i];
        result += tex.sample(s, in.uv - float2(texel.x * i, 0)) * weights[i];
    }
    return result;
}

fragment float4 fragment_blur_v(QuadVOut in [[stage_in]],
                                texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 texel = 1.0 / float2(tex.get_width(), tex.get_height());
    float weights[5] = {0.227027, 0.194596, 0.121622, 0.054054, 0.016216};
    float4 result = tex.sample(s, in.uv) * weights[0];
    for (int i = 1; i < 5; i++) {
        result += tex.sample(s, in.uv + float2(0, texel.y * i)) * weights[i];
        result += tex.sample(s, in.uv - float2(0, texel.y * i)) * weights[i];
    }
    return result;
}

fragment float4 fragment_composite(QuadVOut in [[stage_in]],
                                   texture2d<float> mainTex [[texture(0)]],
                                   texture2d<float> bloomTex [[texture(1)]],
                                   constant Uniforms& u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 main_c = mainTex.sample(s, in.uv);
    float4 bloom_c = bloomTex.sample(s, in.uv);

    // Dark background circle
    float2 center = float2(0.5, 0.5);
    float dist = length(in.uv - center);
    float bg_circle = 1.0 - smoothstep(0.42, 0.48, dist);
    float bg_a = bg_circle * 0.88;
    float3 bg_col = float3(0.0, 0.0, 0.0);

    // Center dot: grows + shifts color with voice
    float amp = clamp(u.amplitude * 2.0, 0.0, 1.0);
    float coreSize = 0.06 + amp * 0.08;
    float glowSize = coreSize + 0.08 + amp * 0.06;
    float dot_core = 1.0 - smoothstep(0.0, coreSize, dist);
    float dot_glow = (1.0 - smoothstep(coreSize, glowSize, dist)) * 0.3;
    float dot_a = dot_core + dot_glow;
    float3 idle_col = float3(0.894, 0.894, 0.906);   // #E4E4E7
    float3 voice_col = float3(0.220, 0.576, 0.906);  // #3893E7
    float3 dot_col = mix(idle_col, voice_col, amp);

    // Composite: bg circle + sphere + bloom + center dot
    float4 result = float4(bg_col * bg_a, bg_a);
    result.rgb = result.rgb * (1.0 - main_c.a) + main_c.rgb;
    result.a = max(result.a, main_c.a);
    result.rgb += bloom_c.rgb * 1.8;
    result.a = max(result.a, bloom_c.a * 1.8);
    result.rgb += dot_col * dot_a;
    result.a = max(result.a, dot_a);
    return result;
}
