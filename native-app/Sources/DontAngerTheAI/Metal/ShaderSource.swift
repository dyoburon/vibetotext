let metalShaderSource: String = #"""
#include <metal_stdlib>
using namespace metal;

// ── Noise (replaces iChannel0 texture) ──
float hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + float2(1, 0)), f.x),
               mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), f.x), f.y);
}

// ── Data structures ──
struct Particle {
    float orbitalRadius;
    float angle;
    float angularSpeed;
    float brightness;
    float size;
    float noisePhase;
    float colorMix;
    float ageFraction;
    float baseAngle;
    float baseRadius;
    float clusterID;
    float armIndex;
};

struct Uniforms {
    float time;
    float globalRotation;
    float2 viewportSize;
    float zoom;
    int highlightIndex;
    float dimFactor;
    int colorMode;
    float audioAmplitude;
};

// ── Compute: update particle orbits with spring-back ──
kernel void updateParticles(
    device Particle* particles [[buffer(0)]],
    constant Uniforms& u [[buffer(1)]],
    constant float& deltaTime [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    device Particle& p = particles[id];
    p.angle += p.angularSpeed * deltaTime;

    // Spring-back toward base angle
    float diff = p.baseAngle - p.angle;
    diff = diff - round(diff / (2.0 * M_PI_F)) * 2.0 * M_PI_F;
    p.angle += diff * 0.3 * deltaTime;

    // Spring-back toward base radius
    p.orbitalRadius += (p.baseRadius - p.orbitalRadius) * 0.3 * deltaTime;
}

// ── Procedural galaxy background ──
struct BGVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex BGVertexOut vertexBackground(uint vid [[vertex_id]]) {
    float2 pos;
    pos.x = (vid == 1) ? 3.0 : -1.0;
    pos.y = (vid == 2) ? 3.0 : -1.0;
    BGVertexOut out;
    out.position = float4(pos, 0.0, 1.0);
    out.uv = pos;
    return out;
}

fragment float4 fragmentBackground(
    BGVertexOut in [[stage_in]],
    constant Uniforms& u [[buffer(1)]],
    constant float* audioLevels [[buffer(2)]]
) {
    float2 r = u.viewportSize;
    float2 FC = (in.uv * 0.5 + 0.5) * r;

    float2 p = (FC.xy * 2.0 - r) / r.y / u.zoom;

    // Rotate with galaxy
    float c = cos(u.globalRotation);
    float s = sin(u.globalRotation);
    p = float2(p.x * c - p.y * s, p.x * s + p.y * c);

    // Angle around the ring (0 to 1)
    float angle = atan2(p.y, p.x); // -pi to pi
    float t = (angle + M_PI_F) / (2.0 * M_PI_F); // 0 to 1

    // Map angle to frequency band with smooth cubic interpolation
    float bandPos = t * 24.0; // 25 bands (0-24)
    int bandLow = int(floor(bandPos)) % 25;
    int bandHigh = (bandLow + 1) % 25;
    float frac = fract(bandPos);
    // Smoothstep for smoother transitions between bands
    frac = frac * frac * (3.0 - 2.0 * frac);
    float bandLevel = mix(audioLevels[bandLow], audioLevels[bandHigh], frac);

    // Ring radius: base pulse + per-band waveform deformation
    float amp = u.audioAmplitude;
    float pulse = 0.5
        + 0.015 * sin(u.time * 0.8)
        + 0.008 * sin(u.time * 1.7)
        + bandLevel * 0.12;
    float v = length(p) - pulse;
    float edge = max(v, -v / 0.1);

    // Glow intensity: brighter when speaking
    float glow = 0.03 + amp * 0.04;

    float4 o = tanh(glow * float4(2.0, 1.0, 1.0 + p.x, 1.0 + p.y)
        / (0.05 + edge)
        / (0.1 + abs(p.x - p.y)));

    return float4(o.rgb, 1.0);
}

// ── Vertex: point sprites ──
struct VertexOut {
    float4 position [[position]];
    float  pointSize [[point_size]];
    float  brightness;
    float  colorMix;
    float  ageFraction;
    float  isHighlighted;
};

vertex VertexOut vertexParticle(
    device const Particle* particles [[buffer(0)]],
    constant Uniforms& u [[buffer(1)]],
    uint vid [[vertex_id]]
) {
    device const Particle& p = particles[vid];
    float totalAngle = p.angle + u.globalRotation;
    float x = p.orbitalRadius * cos(totalAngle);
    float y = p.orbitalRadius * sin(totalAngle);
    float2 ndc = float2(x, y) * u.zoom;

    bool highlighted = (int(vid) == u.highlightIndex);
    float sizeBoost = highlighted ? 3.0 : 1.0;

    VertexOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.pointSize = p.size * u.zoom * sizeBoost;
    out.brightness = p.brightness;
    out.colorMix = p.colorMix;
    out.ageFraction = p.ageFraction;
    out.isHighlighted = highlighted ? 1.0 : 0.0;
    return out;
}

fragment float4 fragmentParticle(
    VertexOut in [[stage_in]],
    float2 pointCoord [[point_coord]],
    constant Uniforms& u [[buffer(1)]]
) {
    float dist = length(pointCoord - float2(0.5)) * 2.0;
    float alpha = smoothstep(1.0, 0.0, dist);
    alpha *= alpha;

    float3 color;
    if (u.colorMode == 1) {
        float3 oldColor = float3(0.2, 0.8, 0.9);
        float3 newColor = float3(0.95, 0.3, 0.6);
        color = mix(oldColor, newColor, in.ageFraction);
    } else {
        float3 amber = float3(0.984, 0.749, 0.141);
        float3 coolGray = float3(0.443, 0.443, 0.475);
        color = mix(coolGray, amber, in.colorMix);
    }

    if (in.isHighlighted > 0.5) {
        float ring = smoothstep(0.35, 0.45, dist) * smoothstep(0.55, 0.45, dist);
        color = mix(color, float3(1.0), ring * 0.8);
        alpha = max(alpha, ring * 0.6);
    }

    float dim = (in.isHighlighted > 0.5) ? 1.0 : u.dimFactor;
    float finalAlpha = alpha * in.brightness * dim;
    return float4(color * finalAlpha, finalAlpha);
}
"""#
