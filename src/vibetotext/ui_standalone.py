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

_shader_path = os.path.join(os.path.dirname(__file__), "sphere.metal")
with open(_shader_path, "r") as _f:
    MSL_SOURCE = _f.read()

# ─── Mesh generation ─────────────────────────────────────────────────────────

def generate_sphere_mesh(n_lat=48, n_lon=64):
    """UV sphere with barycentric coords for panelized edge rendering.
    Returns (vertex_bytes, num_vertices).
    Vertex layout: position(3f) + normal(3f) + barycentric(3f) = 36 bytes.
    """
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

            for k, p in enumerate((p00, p10, p01)):
                b = bary[k]
                data.extend(struct.pack('9f',
                    p[0], p[1], p[2], p[0], p[1], p[2], b[0], b[1], b[2]))
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
        mesh_data, self.num_verts = generate_sphere_mesh()
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
        self.smooth_amp = self.smooth_amp * 0.5 + raw_amp * 0.5
        amp = self.smooth_amp if recording else 0.0

        # MVP matrix
        proj = mat4_perspective(math.radians(45), 1.0, 0.1, 100.0)
        view = mat4_translate(0, 0, -3.8)
        model = mat4_mul(mat4_rotate_x(0.4), mat4_rotate_y(self.rotation))
        mvp = mat4_mul(proj, mat4_mul(view, model))

        # Pack uniforms: 16 floats (mvp) + time + amplitude + 2 seed + rotationY
        uniform_data = struct.pack('16f5f', *mvp, t, amp, self.noise_seed_x, self.noise_seed_y, self.rotation)
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

                self.target_scale = 6.1 if self.recording else 1.0

                scale_diff = self.target_scale - self.current_scale
                if abs(scale_diff) > 0.01:
                    self.scale_velocity = (
                        self.scale_velocity * 0.7 + scale_diff * 0.15
                    )
                    self.current_scale += self.scale_velocity
                    self.current_scale = max(1.0, min(6.1, self.current_scale))

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
