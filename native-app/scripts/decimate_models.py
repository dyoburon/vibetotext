#!/usr/bin/env python3
"""Decimate all GLB models to ~10% of their original vertex count.

Preserves PBR materials through decimation (the original version
stripped materials, leaving everything gray).
"""

import sys
from pathlib import Path

import trimesh

MODELS_DIR = Path(__file__).parent.parent / "Sources" / "DontAngerTheAI" / "Web" / "models"
TARGET_RATIO = 0.80  # Keep 80% of faces
MIN_FACES_TO_DECIMATE = 100  # Skip meshes already this low-poly


def _preserve_material(original, simplified):
    """Copy the material from the original mesh onto the simplified one."""
    vis = original.visual
    if hasattr(vis, 'material') and vis.material is not None:
        simplified.visual = trimesh.visual.TextureVisuals(material=vis.material)
    elif hasattr(vis, 'face_colors') and len(vis.face_colors) > 0:
        # Vertex/face color visual — apply the dominant color uniformly
        from collections import Counter
        mode_color = Counter(map(tuple, vis.face_colors)).most_common(1)[0][0]
        simplified.visual.face_colors = [mode_color] * len(simplified.faces)


def decimate_glb(filepath: Path):
    """Load a GLB, decimate all meshes to TARGET_RATIO, save in-place."""
    print(f"\n{'='*60}")
    print(f"Processing: {filepath.name}")

    scene = trimesh.load(str(filepath), force='scene')

    if not isinstance(scene, trimesh.Scene):
        mesh = scene
        orig_faces = len(mesh.faces)
        orig_verts = len(mesh.vertices)
        if orig_faces <= MIN_FACES_TO_DECIMATE:
            print(f"  Already low-poly ({orig_faces} faces), skipping")
            return
        target_faces = max(int(orig_faces * TARGET_RATIO), MIN_FACES_TO_DECIMATE)
        simplified = mesh.simplify_quadric_decimation(face_count=target_faces)
        _preserve_material(mesh, simplified)
        print(f"  {orig_verts:,}v/{orig_faces:,}f -> {len(simplified.vertices):,}v/{len(simplified.faces):,}f")
        simplified.export(str(filepath))
        return

    total_orig_verts = 0
    total_orig_faces = 0
    total_new_verts = 0
    total_new_faces = 0

    new_geometry = {}
    for name, geom in scene.geometry.items():
        if not isinstance(geom, trimesh.Trimesh):
            new_geometry[name] = geom
            continue

        orig_faces = len(geom.faces)
        orig_verts = len(geom.vertices)
        total_orig_verts += orig_verts
        total_orig_faces += orig_faces

        if orig_faces <= MIN_FACES_TO_DECIMATE:
            print(f"  {name}: {orig_verts:,}v/{orig_faces:,}f (already low-poly, skip)")
            new_geometry[name] = geom
            total_new_verts += orig_verts
            total_new_faces += orig_faces
            continue

        try:
            target_faces = max(int(orig_faces * TARGET_RATIO), MIN_FACES_TO_DECIMATE)
            simplified = geom.simplify_quadric_decimation(face_count=target_faces)
            _preserve_material(geom, simplified)
            total_new_verts += len(simplified.vertices)
            total_new_faces += len(simplified.faces)
            print(f"  {name}: {orig_verts:,}v/{orig_faces:,}f -> {len(simplified.vertices):,}v/{len(simplified.faces):,}f")
            new_geometry[name] = simplified
        except Exception as e:
            print(f"  {name}: SKIP (error: {e})")
            new_geometry[name] = geom
            total_new_verts += orig_verts
            total_new_faces += orig_faces

    scene.geometry = new_geometry

    orig_size = filepath.stat().st_size
    scene.export(str(filepath))
    new_size = filepath.stat().st_size

    print(f"  TOTAL: {total_orig_verts:,}v/{total_orig_faces:,}f -> {total_new_verts:,}v/{total_new_faces:,}f")
    print(f"  File: {orig_size/1024:.0f} KB -> {new_size/1024:.0f} KB ({new_size/orig_size*100:.1f}%)")


def main():
    glb_files = sorted(MODELS_DIR.glob("*.glb"))
    if not glb_files:
        print(f"No GLB files found in {MODELS_DIR}")
        sys.exit(1)

    print(f"Found {len(glb_files)} GLB files in {MODELS_DIR}")
    print(f"Target: {TARGET_RATIO*100:.0f}% of original faces")
    print(f"Skip threshold: meshes with <= {MIN_FACES_TO_DECIMATE} faces")

    for f in glb_files:
        decimate_glb(f)

    print(f"\n{'='*60}")
    print("Done! All models decimated.")


if __name__ == "__main__":
    main()
