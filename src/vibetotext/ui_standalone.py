#!/usr/bin/env python3
"""Standalone UI process for the floating sphere indicator."""

import json
import math
import os
import random
import sys
import time

# PyObjC imports
from AppKit import (
    NSApplication, NSApp, NSPanel, NSView, NSColor, NSBezierPath,
    NSBackingStoreBuffered, NSMakeRect, NSFloatingWindowLevel,
    NSWindowStyleMaskBorderless, NSWindowCollectionBehaviorCanJoinAllSpaces,
    NSWindowCollectionBehaviorStationary, NSTimer, NSRunLoop,
    NSDefaultRunLoopMode
)
from Foundation import NSObject
from Quartz import kCGMaximumWindowLevelKey, CGWindowLevelForKey
import objc

IPC_FILE = sys.argv[1] if len(sys.argv) > 1 else "/tmp/vibetotext_ui_ipc.json"


def _generate_sphere(n_lat=9, n_lon=12):
    """Generate wireframe sphere vertices and edges."""
    vertices = []
    edges = []
    phis = []    # latitude angle per vertex
    thetas = []  # longitude angle per vertex

    n_rings = n_lat - 1
    for i in range(1, n_lat):
        phi = math.pi * i / n_lat
        for j in range(n_lon):
            theta = 2 * math.pi * j / n_lon
            x = math.sin(phi) * math.cos(theta)
            y = math.cos(phi)
            z = math.sin(phi) * math.sin(theta)
            vertices.append((x, y, z))
            phis.append(phi)
            thetas.append(theta)

    # Poles
    north = len(vertices)
    vertices.append((0.0, 1.0, 0.0))
    phis.append(0.0)
    thetas.append(0.0)
    south = len(vertices)
    vertices.append((0.0, -1.0, 0.0))
    phis.append(math.pi)
    thetas.append(0.0)

    # Latitude edges
    for i in range(n_rings):
        for j in range(n_lon):
            edges.append((i * n_lon + j, i * n_lon + (j + 1) % n_lon))

    # Longitude edges
    for i in range(n_rings - 1):
        for j in range(n_lon):
            edges.append((i * n_lon + j, (i + 1) * n_lon + j))

    # Pole connections
    for j in range(n_lon):
        edges.append((north, j))
        edges.append((south, (n_rings - 1) * n_lon + j))

    return vertices, edges, phis, thetas


SPHERE_VERTS, SPHERE_EDGES, SPHERE_PHI, SPHERE_THETA = _generate_sphere(
    n_lat=9, n_lon=12
)


class SphereView(NSView):
    """Custom view that draws a rotating wireframe sphere with deformations."""

    def initWithFrame_(self, frame):
        self = objc.super(SphereView, self).initWithFrame_(frame)
        if self:
            self.levels = [0.0] * 25
            self.recording = False
            self.rotation_angle = 0.0
            self.smooth_amp = 0.0
            self.dot_amp = 0.0
            self.t0 = time.time()
        return self

    def setLevels_recording_(self, levels, recording):
        self.levels = list(levels)
        self.recording = recording

    def drawRect_(self, rect):
        w = rect.size.width
        h = rect.size.height
        cx, cy = w / 2, h / 2
        size = min(w, h)
        t = time.time() - self.t0

        # --- Background: dark circle ---
        NSColor.colorWithCalibratedRed_green_blue_alpha_(0.0, 0.0, 0.0, 0.88).set()
        bg_r = size / 2
        NSBezierPath.bezierPathWithOvalInRect_(
            NSMakeRect(cx - bg_r, cy - bg_r, bg_r * 2, bg_r * 2)
        ).fill()

        # --- Rotation ---
        self.rotation_angle += 0.012

        # --- Audio amplitude ---
        raw = sum(self.levels) / len(self.levels) if self.levels else 0.0
        if not self.recording:
            raw = 0.0
        self.smooth_amp = self.smooth_amp * 0.6 + raw * 0.4
        self.dot_amp = self.dot_amp * 0.82 + raw * 0.18

        # --- Sphere radius (more dramatic pulse) ---
        base_r = size * 0.25
        pulse = size * 0.22
        if self.recording:
            radius = base_r + pulse * self.smooth_amp
        else:
            radius = base_r * 0.65

        # --- Deform + Rotate vertices ---
        angle_y = self.rotation_angle
        tilt_x = 0.4
        cy_rot = math.cos(angle_y)
        sy_rot = math.sin(angle_y)
        cx_rot = math.cos(tilt_x)
        sx_rot = math.sin(tilt_x)

        amp = self.smooth_amp if self.recording else 0.0
        # Deformation intensity ramps with audio
        deform_i = 0.06 + amp * 0.28

        # Smoothly blend 3 deformation patterns using phase-offset sine weights
        w1 = (math.sin(t * 0.25) + 1) / 2
        w2 = (math.sin(t * 0.25 + 2.094) + 1) / 2
        w3 = (math.sin(t * 0.25 + 4.189) + 1) / 2
        wt = w1 + w2 + w3
        w1 /= wt
        w2 /= wt
        w3 /= wt

        projected = []
        for idx in range(len(SPHERE_VERTS)):
            vx, vy, vz = SPHERE_VERTS[idx]
            phi = SPHERE_PHI[idx]
            theta = SPHERE_THETA[idx]

            # Three deformation patterns (radial displacement)
            d1 = math.sin(phi * 4 + t * 1.2) * math.sin(theta * 3 + t * 0.8)
            d2 = math.sin(phi * 3 - t * 0.9) * math.cos(theta * 5 + t * 1.1)
            d3 = (math.sin(phi * 6 + theta * 2 + t * 0.7)
                  * math.cos(phi * 2 - t * 1.3))
            disp = 1.0 + (d1 * w1 + d2 * w2 + d3 * w3) * deform_i

            dx, dy, dz = vx * disp, vy * disp, vz * disp

            # Y-axis rotation
            rx = dx * cy_rot + dz * sy_rot
            rz = -dx * sy_rot + dz * cy_rot
            # X-axis tilt
            ry = dy * cx_rot - rz * sx_rot
            rz2 = dy * sx_rot + rz * cx_rot
            # Project
            projected.append((cx + rx * radius, cy + ry * radius, rz2))

        # --- TV flicker ---
        if self.recording:
            flicker = 0.78 + random.random() * 0.22
            if random.random() < 0.05:
                flicker *= 0.4
        else:
            flicker = 0.85 + random.random() * 0.15

        # --- Colors ---
        if self.recording:
            sr, sg, sb = 0xD5 / 255, 0x59 / 255, 0x83 / 255
        else:
            sr, sg, sb = 63 / 255, 63 / 255, 70 / 255

        # --- Subtle inner fill (purple tint like reference) ---
        if self.recording:
            fill_r = radius * 0.95
            NSColor.colorWithCalibratedRed_green_blue_alpha_(
                0x3B / 255, 0x1A / 255, 0x45 / 255, 0.15 * flicker
            ).set()
            NSBezierPath.bezierPathWithOvalInRect_(
                NSMakeRect(cx - fill_r, cy - fill_r, fill_r * 2, fill_r * 2)
            ).fill()

        # --- Draw edges: glow pass (thick, low opacity) ---
        for i1, i2 in SPHERE_EDGES:
            p1 = projected[i1]
            p2 = projected[i2]
            avg_z = (p1[2] + p2[2]) / 2
            depth_a = 0.08 + 0.92 * ((avg_z + 1) / 2)
            alpha = depth_a * flicker * 0.25

            NSColor.colorWithCalibratedRed_green_blue_alpha_(
                sr, sg, sb, alpha
            ).set()
            edge = NSBezierPath.bezierPath()
            edge.moveToPoint_((p1[0], p1[1]))
            edge.lineToPoint_((p2[0], p2[1]))
            edge.setLineWidth_(3.5 if self.recording else 1.5)
            edge.stroke()

        # --- Draw edges: sharp pass ---
        for i1, i2 in SPHERE_EDGES:
            p1 = projected[i1]
            p2 = projected[i2]
            avg_z = (p1[2] + p2[2]) / 2
            depth_a = 0.12 + 0.88 * ((avg_z + 1) / 2)
            alpha = depth_a * flicker

            NSColor.colorWithCalibratedRed_green_blue_alpha_(
                sr, sg, sb, alpha
            ).set()
            edge = NSBezierPath.bezierPath()
            edge.moveToPoint_((p1[0], p1[1]))
            edge.lineToPoint_((p2[0], p2[1]))
            edge.setLineWidth_(1.0 if self.recording else 0.5)
            edge.stroke()

        # --- Vertex glow dots (intersection highlights) ---
        if self.recording:
            for p in projected:
                z_norm = (p[2] + 1) / 2
                if z_norm < 0.25:
                    continue
                dot_a = z_norm * flicker * 0.55
                dot_sz = 1.2 + z_norm * 1.8
                # Brighter than edge color
                NSColor.colorWithCalibratedRed_green_blue_alpha_(
                    min(1.0, sr * 1.4),
                    min(1.0, sg * 1.4),
                    min(1.0, sb * 1.4),
                    dot_a
                ).set()
                NSBezierPath.bezierPathWithOvalInRect_(
                    NSMakeRect(p[0] - dot_sz / 2, p[1] - dot_sz / 2,
                               dot_sz, dot_sz)
                ).fill()

        # --- Center dot ---
        dot_min = size * 0.02
        dot_max = size * 0.065
        if self.recording:
            dot_r = dot_min + (dot_max - dot_min) * self.dot_amp
            dot_a = 0.85 + 0.15 * flicker
        else:
            dot_r = dot_min
            dot_a = 0.5

        # Center dot glow
        if self.recording:
            glow_r = dot_r * 2.8
            NSColor.colorWithCalibratedRed_green_blue_alpha_(
                0xE4 / 255, 0xE4 / 255, 0xE7 / 255, dot_a * 0.2
            ).set()
            NSBezierPath.bezierPathWithOvalInRect_(
                NSMakeRect(cx - glow_r, cy - glow_r, glow_r * 2, glow_r * 2)
            ).fill()

        NSColor.colorWithCalibratedRed_green_blue_alpha_(
            0xE4 / 255, 0xE4 / 255, 0xE7 / 255, dot_a
        ).set()
        NSBezierPath.bezierPathWithOvalInRect_(
            NSMakeRect(cx - dot_r, cy - dot_r, dot_r * 2, dot_r * 2)
        ).fill()


class AppDelegate(NSObject):
    def init(self):
        self = objc.super(AppDelegate, self).init()
        if self:
            self.levels = [0.0] * 25
            self.recording = False
            self.panel = None
            self.sphere_view = None
            # Bigger base for more dramatic scale-up
            self.base_width = 44
            self.base_height = 44
            self.current_scale = 1.0
            self.target_scale = 1.0
            self.scale_velocity = 0.0
            self.anchor_right = 0
            self.anchor_bottom = 0
        return self

    def applicationDidFinishLaunching_(self, notification):
        width = self.base_width
        height = self.base_height

        self.panel = NSPanel.alloc().initWithContentRect_styleMask_backing_defer_(
            NSMakeRect(100, 100, width, height),
            NSWindowStyleMaskBorderless,
            NSBackingStoreBuffered,
            False
        )

        self.panel.setLevel_(CGWindowLevelForKey(kCGMaximumWindowLevelKey))
        self.panel.setFloatingPanel_(True)
        self.panel.setHidesOnDeactivate_(False)
        self.panel.setCanHide_(False)

        self.panel.setCollectionBehavior_(
            NSWindowCollectionBehaviorCanJoinAllSpaces |
            NSWindowCollectionBehaviorStationary
        )

        self.panel.setOpaque_(False)
        self.panel.setBackgroundColor_(NSColor.clearColor())

        self.sphere_view = SphereView.alloc().initWithFrame_(
            NSMakeRect(0, 0, width, height)
        )
        self.panel.setContentView_(self.sphere_view)
        self.panel.orderFrontRegardless()

        self.timer = NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
            0.033, self, "update:", None, True
        )

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

                # Reposition when recording starts
                if self.recording and not was_recording:
                    screen_x = data.get("screen_x", 0)
                    screen_y = data.get("screen_y", 0)
                    screen_w = data.get("screen_w", 1920)
                    self.current_scale = 1.0
                    self.target_scale = 1.0
                    self.scale_velocity = 0.0
                    width = self.base_width
                    height = self.base_height
                    right_edge_x = screen_x + int(screen_w * 0.74)
                    new_x = right_edge_x - width
                    new_y = screen_y + 20
                    self.anchor_right = right_edge_x
                    self.anchor_bottom = new_y

                    self.panel.setFrame_display_(
                        NSMakeRect(new_x, new_y, width, height), True
                    )
                    self.panel.orderFrontRegardless()

                if "levels" in data and self.recording:
                    self.levels = list(data["levels"])
                elif not self.recording:
                    self.levels = [0.0] * 25

                if self.recording:
                    self.target_scale = 3.8
                else:
                    self.target_scale = 1.0

                # Spring animation
                scale_diff = self.target_scale - self.current_scale
                if abs(scale_diff) > 0.01:
                    spring_strength = 0.15
                    damping = 0.7
                    self.scale_velocity = (self.scale_velocity * damping
                                           + scale_diff * spring_strength)
                    self.current_scale += self.scale_velocity
                    self.current_scale = max(1.0, min(3.8, self.current_scale))

                    new_width = int(self.base_width * self.current_scale)
                    new_height = int(self.base_height * self.current_scale)
                    new_x = self.anchor_right - new_width
                    new_y = self.anchor_bottom

                    self.panel.setFrame_display_(
                        NSMakeRect(new_x, new_y, new_width, new_height), True
                    )
                    self.sphere_view.setFrame_(
                        NSMakeRect(0, 0, new_width, new_height)
                    )
                elif (abs(scale_diff) <= 0.01
                      and abs(self.scale_velocity) > 0.001):
                    self.scale_velocity *= 0.5
                    if abs(self.scale_velocity) < 0.001:
                        self.scale_velocity = 0
                        self.current_scale = self.target_scale

                self.sphere_view.setLevels_recording_(
                    list(self.levels), self.recording
                )
        except Exception:
            pass

        # Always trigger redraw so sphere rotates even when idle
        if self.sphere_view:
            self.sphere_view.setNeedsDisplay_(True)


def main():
    app = NSApplication.sharedApplication()
    delegate = AppDelegate.alloc().init()
    app.setDelegate_(delegate)
    app.setActivationPolicy_(2)  # NSApplicationActivationPolicyAccessory
    app.run()


if __name__ == "__main__":
    main()
