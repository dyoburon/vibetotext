#!/usr/bin/env python3
"""Compute vertex normals for a GLB model that's missing them (e.g. from Trellis)."""

import sys
import trimesh

if len(sys.argv) < 2:
    print("Usage: compute-normals.py <input.glb> [output.glb]")
    sys.exit(1)

input_path = sys.argv[1]
output_path = sys.argv[2] if len(sys.argv) > 2 else input_path

scene = trimesh.load(input_path)

if isinstance(scene, trimesh.Scene):
    for name, geo in scene.geometry.items():
        if isinstance(geo, trimesh.Trimesh):
            has_normals = geo.vertex_normals is not None and len(geo.vertex_normals) > 0
            print(f"  {name}: {len(geo.vertices)} verts, {len(geo.faces)} faces, normals={'yes' if has_normals else 'NO'}")
            # Force recompute from faces
            geo.vertex_normals
            print(f"    -> normals computed: {geo.vertex_normals.shape}")
elif isinstance(scene, trimesh.Trimesh):
    print(f"  mesh: {len(scene.vertices)} verts, {len(scene.faces)} faces")
    scene.vertex_normals
    print(f"    -> normals computed: {scene.vertex_normals.shape}")

scene.export(output_path)
print(f"Saved to {output_path}")
