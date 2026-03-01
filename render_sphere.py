#!/usr/bin/env python3
"""Render the vibetotext sphere shader to a 512x512 PNG."""

import math
import os
import struct
import sys

# Must set up Metal before importing AppKit in some contexts
from Foundation import NSObject
from AppKit import NSApplication, NSBitmapImageRep, NSPNGFileType
from Quartz import CAMetalLayer
import Metal

SIZE = 512

# ─── Load shader ─────────────────────────────────────────────────────────────

_shader_path = os.path.join(os.path.dirname(__file__), "src", "vibetotext", "sphere.metal")
with open(_shader_path, "r") as f:
    MSL_SOURCE = f.read()

# ─── Mesh generation (same as ui_standalone.py) ─────────────────────────────

def generate_sphere_mesh(n_lat=48, n_lon=64):
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
                data.extend(struct.pack('9f', p[0], p[1], p[2], p[0], p[1], p[2], b[0], b[1], b[2]))
            for k, p in enumerate((p10, p11, p01)):
                b = bary[k]
                data.extend(struct.pack('9f', p[0], p[1], p[2], p[0], p[1], p[2], b[0], b[1], b[2]))
            num_verts += 6
    return bytes(data), num_verts

# ─── Matrix math ─────────────────────────────────────────────────────────────

def mat4_perspective(fov, aspect, near, far):
    f = 1.0 / math.tan(fov / 2)
    nf = near - far
    return [f/aspect, 0, 0, 0, 0, f, 0, 0, 0, 0, (far+near)/nf, -1, 0, 0, (2*far*near)/nf, 0]

def mat4_rotate_y(angle):
    c, s = math.cos(angle), math.sin(angle)
    return [c, 0, s, 0, 0, 1, 0, 0, -s, 0, c, 0, 0, 0, 0, 1]

def mat4_rotate_x(angle):
    c, s = math.cos(angle), math.sin(angle)
    return [1, 0, 0, 0, 0, c, -s, 0, 0, s, c, 0, 0, 0, 0, 1]

def mat4_translate(x, y, z):
    return [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, y, z, 1]

def mat4_mul(a, b):
    r = [0.0] * 16
    for col in range(4):
        for row in range(4):
            s = 0.0
            for k in range(4):
                s += a[k * 4 + row] * b[col * 4 + k]
            r[col * 4 + row] = s
    return r

# ─── Render ──────────────────────────────────────────────────────────────────

def main():
    # Parse optional args
    t_val = float(sys.argv[1]) if len(sys.argv) > 1 else 2.5       # time
    amp_val = float(sys.argv[2]) if len(sys.argv) > 2 else 0.35    # amplitude (0=idle, ~0.3-0.5=speaking)
    rot_val = float(sys.argv[3]) if len(sys.argv) > 3 else 0.8     # rotation angle

    device = Metal.MTLCreateSystemDefaultDevice()
    cmd_queue = device.newCommandQueue()

    # Compile shaders
    lib, err = device.newLibraryWithSource_options_error_(MSL_SOURCE, None, None)
    if err:
        print(f"Shader error: {err}", file=sys.stderr)
        sys.exit(1)

    # Mesh
    mesh_data, num_verts = generate_sphere_mesh()
    vertex_buf = device.newBufferWithBytes_length_options_(mesh_data, len(mesh_data), 0)

    # Vertex descriptor
    vd = Metal.MTLVertexDescriptor.vertexDescriptor()
    vd.attributes().objectAtIndexedSubscript_(0).setFormat_(30)  # Float3
    vd.attributes().objectAtIndexedSubscript_(0).setOffset_(0)
    vd.attributes().objectAtIndexedSubscript_(0).setBufferIndex_(0)
    vd.attributes().objectAtIndexedSubscript_(1).setFormat_(30)
    vd.attributes().objectAtIndexedSubscript_(1).setOffset_(12)
    vd.attributes().objectAtIndexedSubscript_(1).setBufferIndex_(0)
    vd.attributes().objectAtIndexedSubscript_(2).setFormat_(30)
    vd.attributes().objectAtIndexedSubscript_(2).setOffset_(24)
    vd.attributes().objectAtIndexedSubscript_(2).setBufferIndex_(0)
    vd.layouts().objectAtIndexedSubscript_(0).setStride_(36)

    # ── Pipelines ──

    # Sphere pipeline → RGBA16Float
    pd = Metal.MTLRenderPipelineDescriptor.alloc().init()
    pd.setVertexFunction_(lib.newFunctionWithName_("vertex_sphere"))
    pd.setFragmentFunction_(lib.newFunctionWithName_("fragment_sphere"))
    pd.setVertexDescriptor_(vd)
    ca = pd.colorAttachments().objectAtIndexedSubscript_(0)
    ca.setPixelFormat_(115)  # RGBA16Float
    ca.setBlendingEnabled_(True)
    ca.setSourceRGBBlendFactor_(1)
    ca.setDestinationRGBBlendFactor_(5)
    ca.setSourceAlphaBlendFactor_(1)
    ca.setDestinationAlphaBlendFactor_(5)
    pipe_sphere, err = device.newRenderPipelineStateWithDescriptor_error_(pd, None)

    # Blur H
    pd2 = Metal.MTLRenderPipelineDescriptor.alloc().init()
    pd2.setVertexFunction_(lib.newFunctionWithName_("vertex_quad"))
    pd2.setFragmentFunction_(lib.newFunctionWithName_("fragment_blur_h"))
    pd2.colorAttachments().objectAtIndexedSubscript_(0).setPixelFormat_(115)
    pipe_blur_h, _ = device.newRenderPipelineStateWithDescriptor_error_(pd2, None)

    # Blur V
    pd3 = Metal.MTLRenderPipelineDescriptor.alloc().init()
    pd3.setVertexFunction_(lib.newFunctionWithName_("vertex_quad"))
    pd3.setFragmentFunction_(lib.newFunctionWithName_("fragment_blur_v"))
    pd3.colorAttachments().objectAtIndexedSubscript_(0).setPixelFormat_(115)
    pipe_blur_v, _ = device.newRenderPipelineStateWithDescriptor_error_(pd3, None)

    # Composite → BGRA8
    pd4 = Metal.MTLRenderPipelineDescriptor.alloc().init()
    pd4.setVertexFunction_(lib.newFunctionWithName_("vertex_quad"))
    pd4.setFragmentFunction_(lib.newFunctionWithName_("fragment_composite"))
    ca4 = pd4.colorAttachments().objectAtIndexedSubscript_(0)
    ca4.setPixelFormat_(80)  # BGRA8Unorm
    ca4.setBlendingEnabled_(False)
    pipe_composite, _ = device.newRenderPipelineStateWithDescriptor_error_(pd4, None)

    # ── Textures ──
    def make_tex(fmt, storage_mode=2):
        td = Metal.MTLTextureDescriptor.texture2DDescriptorWithPixelFormat_width_height_mipmapped_(
            fmt, SIZE, SIZE, False
        )
        td.setUsage_(0x05)  # renderTarget | shaderRead
        td.setStorageMode_(storage_mode)
        return device.newTextureWithDescriptor_(td)

    tex_main = make_tex(115)    # RGBA16Float, private
    tex_blur_h = make_tex(115)
    tex_blur_v = make_tex(115)
    tex_output = make_tex(80)   # BGRA8, private

    # Readback buffer (shared memory for CPU access)
    bytes_per_row = SIZE * 4
    readback_buf = device.newBufferWithLength_options_(bytes_per_row * SIZE, 0)  # shared

    # ── Uniforms ──
    proj = mat4_perspective(math.radians(45), 1.0, 0.1, 100.0)
    view = mat4_translate(0, 0, -3.8)
    model = mat4_mul(mat4_rotate_x(0.4), mat4_rotate_y(rot_val))
    mvp = mat4_mul(proj, mat4_mul(view, model))
    uniform_data = struct.pack('16f5f', *mvp, t_val, amp_val, 0.0, 0.0, rot_val)
    uniform_buf = device.newBufferWithBytes_length_options_(uniform_data, len(uniform_data), 0)

    # ── Render ──
    cmd = cmd_queue.commandBuffer()

    # Pass 1: Sphere
    rpd = Metal.MTLRenderPassDescriptor.renderPassDescriptor()
    c = rpd.colorAttachments().objectAtIndexedSubscript_(0)
    c.setTexture_(tex_main)
    c.setLoadAction_(2)
    c.setClearColor_((0, 0, 0, 0))
    c.setStoreAction_(1)
    enc = cmd.renderCommandEncoderWithDescriptor_(rpd)
    enc.setRenderPipelineState_(pipe_sphere)
    enc.setVertexBuffer_offset_atIndex_(vertex_buf, 0, 0)
    enc.setVertexBuffer_offset_atIndex_(uniform_buf, 0, 1)
    enc.setFragmentBuffer_offset_atIndex_(uniform_buf, 0, 1)
    enc.drawPrimitives_vertexStart_vertexCount_(3, 0, num_verts)
    enc.endEncoding()

    # Pass 2: Blur H
    rpd2 = Metal.MTLRenderPassDescriptor.renderPassDescriptor()
    c2 = rpd2.colorAttachments().objectAtIndexedSubscript_(0)
    c2.setTexture_(tex_blur_h)
    c2.setLoadAction_(2)
    c2.setClearColor_((0, 0, 0, 0))
    c2.setStoreAction_(1)
    enc2 = cmd.renderCommandEncoderWithDescriptor_(rpd2)
    enc2.setRenderPipelineState_(pipe_blur_h)
    enc2.setFragmentTexture_atIndex_(tex_main, 0)
    enc2.drawPrimitives_vertexStart_vertexCount_(4, 0, 4)
    enc2.endEncoding()

    # Pass 3: Blur V
    rpd3 = Metal.MTLRenderPassDescriptor.renderPassDescriptor()
    c3 = rpd3.colorAttachments().objectAtIndexedSubscript_(0)
    c3.setTexture_(tex_blur_v)
    c3.setLoadAction_(2)
    c3.setClearColor_((0, 0, 0, 0))
    c3.setStoreAction_(1)
    enc3 = cmd.renderCommandEncoderWithDescriptor_(rpd3)
    enc3.setRenderPipelineState_(pipe_blur_v)
    enc3.setFragmentTexture_atIndex_(tex_blur_h, 0)
    enc3.drawPrimitives_vertexStart_vertexCount_(4, 0, 4)
    enc3.endEncoding()

    # Pass 4: Composite
    rpd4 = Metal.MTLRenderPassDescriptor.renderPassDescriptor()
    c4 = rpd4.colorAttachments().objectAtIndexedSubscript_(0)
    c4.setTexture_(tex_output)
    c4.setLoadAction_(2)
    c4.setClearColor_((0, 0, 0, 0))
    c4.setStoreAction_(1)
    enc4 = cmd.renderCommandEncoderWithDescriptor_(rpd4)
    enc4.setRenderPipelineState_(pipe_composite)
    enc4.setFragmentBuffer_offset_atIndex_(uniform_buf, 0, 0)
    enc4.setFragmentTexture_atIndex_(tex_main, 0)
    enc4.setFragmentTexture_atIndex_(tex_blur_v, 1)
    enc4.drawPrimitives_vertexStart_vertexCount_(4, 0, 4)
    enc4.endEncoding()

    # Blit from private output texture to shared buffer
    blit = cmd.blitCommandEncoder()
    blit.copyFromTexture_sourceSlice_sourceLevel_sourceOrigin_sourceSize_toBuffer_destinationOffset_destinationBytesPerRow_destinationBytesPerImage_(
        tex_output, 0, 0, (0, 0, 0), (SIZE, SIZE, 1),
        readback_buf, 0, bytes_per_row, bytes_per_row * SIZE
    )
    blit.endEncoding()

    cmd.commit()
    cmd.waitUntilCompleted()

    # Read pixels from buffer via objc.varlist
    import objc as _objc
    ptr = readback_buf.contents()
    total_bytes = bytes_per_row * SIZE
    buf = bytearray(ptr.as_buffer(total_bytes))

    # BGRA → RGBA
    for i in range(0, len(buf), 4):
        buf[i], buf[i+2] = buf[i+2], buf[i]

    # Save as PNG using NSBitmapImageRep
    # bitmapDataPlanes requires a 5-element tuple (one per plane, rest None)
    rep = NSBitmapImageRep.alloc().initWithBitmapDataPlanes_pixelsWide_pixelsHigh_bitsPerSample_samplesPerPixel_hasAlpha_isPlanar_colorSpaceName_bytesPerRow_bitsPerPixel_(
        (bytes(buf), None, None, None, None), SIZE, SIZE, 8, 4, True, False, "NSCalibratedRGBColorSpace", bytes_per_row, 32
    )
    png_data = rep.representationUsingType_properties_(NSPNGFileType, None)
    out_path = os.path.expanduser("~/Desktop/vibecoding_sphere.png")
    png_data.writeToFile_atomically_(out_path, True)
    print(f"Saved to {out_path}")


if __name__ == "__main__":
    main()
