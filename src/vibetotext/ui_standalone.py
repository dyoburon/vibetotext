#!/usr/bin/env python3
"""Standalone UI process - Metal wireframe sphere with bloom."""

import json
import math
import os
import random
import struct
import sys
import time

from AppKit import (
    NSApplication, NSApp, NSPanel, NSView, NSColor,
    NSBackingStoreBuffered, NSMakeRect,
    NSWindowStyleMaskBorderless, NSWindowCollectionBehaviorCanJoinAllSpaces,
    NSWindowCollectionBehaviorStationary, NSTimer,
)
from Foundation import NSObject
from Quartz import kCGMaximumWindowLevelKey, CGWindowLevelForKey, CAMetalLayer
import Metal
import objc

IPC_FILE = sys.argv[1] if len(sys.argv) > 1 else "/tmp/vibetotext_ui_ipc.json"

# ─── Metal Shading Language source ───────────────────────────────────────────

MSL_SOURCE = """
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

    SphereVOut out;
    out.position = u.mvp * float4(disp, 1.0);
    out.bary = in.bary;
    out.worldPos = in.position;

    float3 viewDir = normalize(float3(0, 0, 1));
    out.ndotv = abs(dot(normalize(in.normal), viewDir));
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
    opacity = pow(opacity, 3.0) * 0.17 + 0.01;

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
"""

# ─── Mesh generation ─────────────────────────────────────────────────────────

def generate_sphere_mesh(n_lat=20, n_lon=30):
    """UV sphere with barycentric coords for wireframe rendering.
    Returns (vertex_bytes, num_vertices).
    Vertex layout: position(3f) + normal(3f) + barycentric(3f) = 36 bytes.
    """
    # Generate grid positions (normals = positions for unit sphere)
    grid = []
    for i in range(n_lat + 1):
        phi = math.pi * i / n_lat
        row = []
        for j in range(n_lon + 1):
            theta = 2 * math.pi * j / n_lon
            x = math.sin(phi) * math.cos(theta)
            y = math.cos(phi)
            z = math.sin(phi) * math.sin(theta)
            row.append((x, y, z))
        grid.append(row)

    bary = ((1, 0, 0), (0, 1, 0), (0, 0, 1))
    data = bytearray()
    num_verts = 0

    for i in range(n_lat):
        for j in range(n_lon):
            p00 = grid[i][j]
            p10 = grid[i][j + 1]
            p01 = grid[i + 1][j]
            p11 = grid[i + 1][j + 1]

            # Triangle 1: p00, p10, p01
            for k, p in enumerate((p00, p10, p01)):
                b = bary[k]
                data.extend(struct.pack('9f',
                    p[0], p[1], p[2], p[0], p[1], p[2], b[0], b[1], b[2]))

            # Triangle 2: p10, p11, p01
            for k, p in enumerate((p10, p11, p01)):
                b = bary[k]
                data.extend(struct.pack('9f',
                    p[0], p[1], p[2], p[0], p[1], p[2], b[0], b[1], b[2]))

            num_verts += 6

    return bytes(data), num_verts


# ─── Matrix math ─────────────────────────────────────────────────────────────

def mat4_identity():
    return [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]

def mat4_perspective(fov, aspect, near, far):
    f = 1.0 / math.tan(fov / 2)
    nf = near - far
    return [
        f/aspect, 0, 0, 0,
        0, f, 0, 0,
        0, 0, (far+near)/nf, -1,
        0, 0, (2*far*near)/nf, 0,
    ]

def mat4_rotate_y(angle):
    c, s = math.cos(angle), math.sin(angle)
    return [c,0,s,0, 0,1,0,0, -s,0,c,0, 0,0,0,1]

def mat4_rotate_x(angle):
    c, s = math.cos(angle), math.sin(angle)
    return [1,0,0,0, 0,c,-s,0, 0,s,c,0, 0,0,0,1]

def mat4_translate(x, y, z):
    return [1,0,0,0, 0,1,0,0, 0,0,1,0, x,y,z,1]

def mat4_mul(a, b):
    """Multiply two 4x4 column-major matrices."""
    r = [0.0] * 16
    for col in range(4):
        for row in range(4):
            s = 0.0
            for k in range(4):
                s += a[k * 4 + row] * b[col * 4 + k]
            r[col * 4 + row] = s
    return r


# ─── Metal renderer ──────────────────────────────────────────────────────────

class MetalRenderer:
    def __init__(self):
        self.device = Metal.MTLCreateSystemDefaultDevice()
        self.cmd_queue = self.device.newCommandQueue()

        # Compile all shaders
        lib, err = self.device.newLibraryWithSource_options_error_(
            MSL_SOURCE, None, None
        )
        if err:
            print(f"Shader compile error: {err}", file=sys.stderr)
            sys.exit(1)

        self.fn_v_sphere = lib.newFunctionWithName_("vertex_sphere")
        self.fn_f_sphere = lib.newFunctionWithName_("fragment_sphere")
        self.fn_v_quad = lib.newFunctionWithName_("vertex_quad")
        self.fn_f_blur_h = lib.newFunctionWithName_("fragment_blur_h")
        self.fn_f_blur_v = lib.newFunctionWithName_("fragment_blur_v")
        self.fn_f_composite = lib.newFunctionWithName_("fragment_composite")

        # Sphere mesh
        mesh_data, self.num_verts = generate_sphere_mesh(16, 24)
        self.vertex_buf = self.device.newBufferWithBytes_length_options_(
            mesh_data, len(mesh_data), 0  # MTLResourceStorageModeShared
        )

        # Uniform buffer placeholder (recreated each frame)
        self.uniform_buf = None

        # Vertex descriptor for sphere
        vd = Metal.MTLVertexDescriptor.vertexDescriptor()
        # position float3
        vd.attributes().objectAtIndexedSubscript_(0).setFormat_(30)  # Float3
        vd.attributes().objectAtIndexedSubscript_(0).setOffset_(0)
        vd.attributes().objectAtIndexedSubscript_(0).setBufferIndex_(0)
        # normal float3
        vd.attributes().objectAtIndexedSubscript_(1).setFormat_(30)
        vd.attributes().objectAtIndexedSubscript_(1).setOffset_(12)
        vd.attributes().objectAtIndexedSubscript_(1).setBufferIndex_(0)
        # barycentric float3
        vd.attributes().objectAtIndexedSubscript_(2).setFormat_(30)
        vd.attributes().objectAtIndexedSubscript_(2).setOffset_(24)
        vd.attributes().objectAtIndexedSubscript_(2).setBufferIndex_(0)
        # stride
        vd.layouts().objectAtIndexedSubscript_(0).setStride_(36)

        # ── Sphere pipeline (renders to offscreen HDR texture) ──
        pd = Metal.MTLRenderPipelineDescriptor.alloc().init()
        pd.setVertexFunction_(self.fn_v_sphere)
        pd.setFragmentFunction_(self.fn_f_sphere)
        pd.setVertexDescriptor_(vd)
        ca = pd.colorAttachments().objectAtIndexedSubscript_(0)
        ca.setPixelFormat_(115)  # RGBA16Float
        ca.setBlendingEnabled_(True)
        # Premultiplied alpha: src=One(1), dst=OneMinusSourceAlpha(5)
        ca.setSourceRGBBlendFactor_(1)
        ca.setDestinationRGBBlendFactor_(5)
        ca.setSourceAlphaBlendFactor_(1)
        ca.setDestinationAlphaBlendFactor_(5)
        self.pipe_sphere, err = self.device.newRenderPipelineStateWithDescriptor_error_(pd, None)
        if err:
            print(f"Sphere pipeline error: {err}", file=sys.stderr)

        # ── Bloom blur pipelines (read texture, write texture) ──
        for name, fn, attr in [
            ("pipe_blur_h", self.fn_f_blur_h, 115),
            ("pipe_blur_v", self.fn_f_blur_v, 115),
        ]:
            pd2 = Metal.MTLRenderPipelineDescriptor.alloc().init()
            pd2.setVertexFunction_(self.fn_v_quad)
            pd2.setFragmentFunction_(fn)
            ca2 = pd2.colorAttachments().objectAtIndexedSubscript_(0)
            ca2.setPixelFormat_(attr)
            ps, err = self.device.newRenderPipelineStateWithDescriptor_error_(pd2, None)
            if err:
                print(f"{name} error: {err}", file=sys.stderr)
            setattr(self, name, ps)

        # ── Composite pipeline (to screen BGRA8) ──
        pd3 = Metal.MTLRenderPipelineDescriptor.alloc().init()
        pd3.setVertexFunction_(self.fn_v_quad)
        pd3.setFragmentFunction_(self.fn_f_composite)
        ca3 = pd3.colorAttachments().objectAtIndexedSubscript_(0)
        ca3.setPixelFormat_(80)  # BGRA8Unorm
        # Composite writes final premultiplied color, no blending needed
        ca3.setBlendingEnabled_(False)
        self.pipe_composite, err = self.device.newRenderPipelineStateWithDescriptor_error_(pd3, None)
        if err:
            print(f"Composite pipeline error: {err}", file=sys.stderr)

        # Offscreen textures (created on first render / resize)
        self.tex_main = None
        self.tex_blur_h = None
        self.tex_blur_v = None
        self.tex_w = 0
        self.tex_h = 0

        # Animation state
        self.t0 = time.time()
        self.rotation = 0.0
        self.smooth_amp = 0.0
        self.noise_seed_x = 0.0
        self.noise_seed_y = 0.0

    def _ensure_textures(self, w, h):
        """Create offscreen textures if size changed."""
        if w == self.tex_w and h == self.tex_h and self.tex_main is not None:
            return
        self.tex_w, self.tex_h = w, h
        for attr_name in ("tex_main", "tex_blur_h", "tex_blur_v"):
            td = Metal.MTLTextureDescriptor.texture2DDescriptorWithPixelFormat_width_height_mipmapped_(
                115, w, h, False  # RGBA16Float
            )
            td.setUsage_(0x05)  # renderTarget | shaderRead
            td.setStorageMode_(2)  # private (GPU only)
            setattr(self, attr_name, self.device.newTextureWithDescriptor_(td))

    def render(self, layer, levels, recording):
        drawable = layer.nextDrawable()
        if drawable is None:
            return

        tex = drawable.texture()
        w, h = tex.width(), tex.height()
        if w == 0 or h == 0:
            return

        self._ensure_textures(w, h)

        # Update uniforms
        t = time.time() - self.t0
        self.rotation += 0.006

        raw_amp = sum(levels) / len(levels) if levels and recording else 0.0
        self.smooth_amp = self.smooth_amp * 0.7 + raw_amp * 0.3
        amp = self.smooth_amp if recording else 0.0

        # MVP matrix
        proj = mat4_perspective(math.radians(45), 1.0, 0.1, 100.0)
        view = mat4_translate(0, 0, -3.2)
        model = mat4_mul(mat4_rotate_x(0.4), mat4_rotate_y(self.rotation))
        mvp = mat4_mul(proj, mat4_mul(view, model))

        # Pack uniforms: 16 floats (mvp) + time + amplitude + 2 seed
        uniform_data = struct.pack('16f4f', *mvp, t, amp, self.noise_seed_x, self.noise_seed_y)
        self.uniform_buf = self.device.newBufferWithBytes_length_options_(
            uniform_data, len(uniform_data), 0
        )

        cmd = self.cmd_queue.commandBuffer()

        # ── Pass 1: Render sphere to offscreen texture ──
        rpd = Metal.MTLRenderPassDescriptor.renderPassDescriptor()
        ca = rpd.colorAttachments().objectAtIndexedSubscript_(0)
        ca.setTexture_(self.tex_main)
        ca.setLoadAction_(2)   # clear
        ca.setClearColor_((0, 0, 0, 0))
        ca.setStoreAction_(1)  # store

        enc = cmd.renderCommandEncoderWithDescriptor_(rpd)
        enc.setRenderPipelineState_(self.pipe_sphere)
        enc.setVertexBuffer_offset_atIndex_(self.vertex_buf, 0, 0)
        enc.setVertexBuffer_offset_atIndex_(self.uniform_buf, 0, 1)
        enc.setFragmentBuffer_offset_atIndex_(self.uniform_buf, 0, 1)
        enc.drawPrimitives_vertexStart_vertexCount_(3, 0, self.num_verts)  # triangle
        enc.endEncoding()

        # ── Pass 2: Horizontal blur ──
        rpd2 = Metal.MTLRenderPassDescriptor.renderPassDescriptor()
        ca2 = rpd2.colorAttachments().objectAtIndexedSubscript_(0)
        ca2.setTexture_(self.tex_blur_h)
        ca2.setLoadAction_(2)
        ca2.setClearColor_((0, 0, 0, 0))
        ca2.setStoreAction_(1)

        enc2 = cmd.renderCommandEncoderWithDescriptor_(rpd2)
        enc2.setRenderPipelineState_(self.pipe_blur_h)
        enc2.setFragmentTexture_atIndex_(self.tex_main, 0)
        enc2.drawPrimitives_vertexStart_vertexCount_(4, 0, 4)  # triangleStrip
        enc2.endEncoding()

        # ── Pass 3: Vertical blur ──
        rpd3 = Metal.MTLRenderPassDescriptor.renderPassDescriptor()
        ca3 = rpd3.colorAttachments().objectAtIndexedSubscript_(0)
        ca3.setTexture_(self.tex_blur_v)
        ca3.setLoadAction_(2)
        ca3.setClearColor_((0, 0, 0, 0))
        ca3.setStoreAction_(1)

        enc3 = cmd.renderCommandEncoderWithDescriptor_(rpd3)
        enc3.setRenderPipelineState_(self.pipe_blur_v)
        enc3.setFragmentTexture_atIndex_(self.tex_blur_h, 0)
        enc3.drawPrimitives_vertexStart_vertexCount_(4, 0, 4)
        enc3.endEncoding()

        # ── Pass 4: Composite to screen drawable ──
        rpd4 = Metal.MTLRenderPassDescriptor.renderPassDescriptor()
        ca4 = rpd4.colorAttachments().objectAtIndexedSubscript_(0)
        ca4.setTexture_(tex)
        ca4.setLoadAction_(2)
        ca4.setClearColor_((0, 0, 0, 0))
        ca4.setStoreAction_(1)

        enc4 = cmd.renderCommandEncoderWithDescriptor_(rpd4)
        enc4.setRenderPipelineState_(self.pipe_composite)
        enc4.setFragmentBuffer_offset_atIndex_(self.uniform_buf, 0, 0)
        enc4.setFragmentTexture_atIndex_(self.tex_main, 0)
        enc4.setFragmentTexture_atIndex_(self.tex_blur_v, 1)
        enc4.drawPrimitives_vertexStart_vertexCount_(4, 0, 4)
        enc4.endEncoding()

        cmd.presentDrawable_(drawable)
        cmd.commit()


# ─── Metal-backed NSView ─────────────────────────────────────────────────────

class MetalSphereView(NSView):

    def initWithFrame_renderer_(self, frame, renderer):
        self = objc.super(MetalSphereView, self).initWithFrame_(frame)
        if self:
            self.renderer = renderer
            self.levels = [0.0] * 25
            self.recording = False

            # Layer-hosting view: set layer BEFORE wantsLayer
            self._metalLayer = CAMetalLayer.layer()
            self._metalLayer.setDevice_(renderer.device)
            self._metalLayer.setPixelFormat_(80)  # BGRA8Unorm
            self._metalLayer.setFramebufferOnly_(False)
            self._metalLayer.setOpaque_(False)
            self._metalLayer.setContentsScale_(2.0)
            w, h = frame.size.width, frame.size.height
            self._metalLayer.setDrawableSize_((w * 2.0, h * 2.0))
            self.setLayer_(self._metalLayer)
            self.setWantsLayer_(True)
        return self

    def setLevels_recording_(self, levels, recording):
        self.levels = list(levels)
        self.recording = recording

    def setFrameSize_(self, size):
        objc.super(MetalSphereView, self).setFrameSize_(size)
        scale = (self.window().backingScaleFactor() if self.window() else 2.0)
        self._metalLayer.setContentsScale_(scale)
        self._metalLayer.setDrawableSize_((size.width * scale, size.height * scale))

    def draw(self):
        self.renderer.render(self._metalLayer, self.levels, self.recording)


# ─── App delegate (same window management as before) ─────────────────────────

class AppDelegate(NSObject):
    def init(self):
        self = objc.super(AppDelegate, self).init()
        if self:
            self.levels = [0.0] * 25
            self.recording = False
            self.panel = None
            self.sphere_view = None
            self.renderer = None
            self.base_width = 44
            self.base_height = 44
            self.current_scale = 1.0
            self.target_scale = 1.0
            self.scale_velocity = 0.0
            self.anchor_right = 0
            self.anchor_bottom = 0
        return self

    def applicationDidFinishLaunching_(self, notification):
        self.renderer = MetalRenderer()

        width = self.base_width
        height = self.base_height

        self.panel = NSPanel.alloc().initWithContentRect_styleMask_backing_defer_(
            NSMakeRect(100, 100, width, height),
            NSWindowStyleMaskBorderless,
            NSBackingStoreBuffered,
            False,
        )
        self.panel.setLevel_(CGWindowLevelForKey(kCGMaximumWindowLevelKey))
        self.panel.setFloatingPanel_(True)
        self.panel.setHidesOnDeactivate_(False)
        self.panel.setCanHide_(False)
        self.panel.setCollectionBehavior_(
            NSWindowCollectionBehaviorCanJoinAllSpaces
            | NSWindowCollectionBehaviorStationary
        )
        self.panel.setOpaque_(False)
        self.panel.setBackgroundColor_(NSColor.clearColor())

        self.sphere_view = MetalSphereView.alloc().initWithFrame_renderer_(
            NSMakeRect(0, 0, width, height), self.renderer
        )
        self.panel.setContentView_(self.sphere_view)
        self.panel.orderFrontRegardless()

        self.timer = NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
            0.016, self, "update:", None, True  # ~60fps for Metal
        )

        # Press 'R' to randomize noise pattern
        from AppKit import NSEvent, NSKeyDownMask
        def key_handler(event):
            if event.characters() and event.characters().lower() == 'r':
                self.renderer.noise_seed_x = random.uniform(-100, 100)
                self.renderer.noise_seed_y = random.uniform(-100, 100)
                print(f"Noise randomized: ({self.renderer.noise_seed_x:.1f}, {self.renderer.noise_seed_y:.1f})", file=sys.stderr)
            return event
        NSEvent.addLocalMonitorForEventsMatchingMask_handler_(NSKeyDownMask, key_handler)

    def update_(self, timer):
        try:
            if os.path.exists(IPC_FILE):
                with open(IPC_FILE, "r") as f:
                    data = json.load(f)

                if data.get("stop"):
                    NSApp.terminate_(None)
                    return

                was_recording = self.recording
                self.recording = data.get("recording", False)

                if self.recording and not was_recording:
                    screen_x = data.get("screen_x", 0)
                    screen_y = data.get("screen_y", 0)
                    screen_w = data.get("screen_w", 1920)
                    self.current_scale = 1.0
                    self.target_scale = 1.0
                    self.scale_velocity = 0.0
                    w = self.base_width
                    h = self.base_height
                    right_edge_x = screen_x + int(screen_w * 0.74)
                    self.anchor_right = right_edge_x
                    self.anchor_bottom = screen_y + 20

                    self.panel.setFrame_display_(
                        NSMakeRect(right_edge_x - w, self.anchor_bottom, w, h),
                        True,
                    )
                    self.panel.orderFrontRegardless()

                if "levels" in data and self.recording:
                    self.levels = list(data["levels"])
                elif not self.recording:
                    self.levels = [0.0] * 25

                self.target_scale = 3.8 if self.recording else 1.0

                scale_diff = self.target_scale - self.current_scale
                if abs(scale_diff) > 0.01:
                    self.scale_velocity = (
                        self.scale_velocity * 0.7 + scale_diff * 0.15
                    )
                    self.current_scale += self.scale_velocity
                    self.current_scale = max(1.0, min(3.8, self.current_scale))

                    nw = int(self.base_width * self.current_scale)
                    nh = int(self.base_height * self.current_scale)
                    nx = self.anchor_right - nw

                    self.panel.setFrame_display_(
                        NSMakeRect(nx, self.anchor_bottom, nw, nh), True
                    )
                    self.sphere_view.setFrameSize_((nw, nh))
                elif abs(scale_diff) <= 0.01 and abs(self.scale_velocity) > 0.001:
                    self.scale_velocity *= 0.5
                    if abs(self.scale_velocity) < 0.001:
                        self.scale_velocity = 0
                        self.current_scale = self.target_scale

                self.sphere_view.setLevels_recording_(
                    list(self.levels), self.recording
                )
        except Exception:
            pass

        # Always render (rotation + bloom even when idle)
        if self.sphere_view:
            self.sphere_view.draw()


def main():
    app = NSApplication.sharedApplication()
    delegate = AppDelegate.alloc().init()
    app.setDelegate_(delegate)
    app.setActivationPolicy_(2)
    app.run()


if __name__ == "__main__":
    main()
