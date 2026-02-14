#!/usr/bin/env python3
"""Offline 3D model generator using Tripo 3D API.

Usage:
    python generate_models.py              # Generate all models
    python generate_models.py --only planet house_01  # Generate specific models
    python generate_models.py --list       # List all model definitions
"""

import argparse
import os
import requests
import time
import sys
from pathlib import Path

API_BASE = "https://api.tripo3d.ai/v2/openapi"
API_KEY = os.environ.get("TRIPO_API_KEY", "tsk_XrmdjkpD3LIrm8IxHQlil-zccCW-MEVtJDjBfTv2pYg")
HEADERS = {
    "Content-Type": "application/json",
    "Authorization": f"Bearer {API_KEY}",
}

OUTPUT_DIR = Path(__file__).parent.parent / "Sources" / "WordGalaxy" / "Web" / "models"

POLL_INTERVAL = 5
MAX_POLL_TIME = 180

NEGATIVE = (
    "high poly, realistic, photorealistic, smooth, PBR, 4k texture, "
    "detailed texture, wrinkles, noise, multiple objects, text, watermark"
)
STYLE = (
    ", low poly stylized 3D model, flat shading, geometric facets, "
    "monument valley art style, pastel colors, clean edges, game asset, "
    "centered, single object, solid background"
)

MODELS = [
    {
        "name": "planet",
        "filename": "planet.glb",
        "prompt": (
            "A small cartoon planet sphere with green grass on top and "
            "brown earth rock layers underneath, round sphere shape, "
            "stylized Little Prince planet, tiny trees and flowers on surface"
            + STYLE
        ),
    },
    {
        "name": "house_01",
        "filename": "house_01.glb",
        "prompt": (
            "A small medieval cottage with colorful pastel walls, "
            "pointed triangular roof with tiles, single wooden door, "
            "tiny shuttered windows, stone chimney"
            + STYLE
        ),
    },
    {
        "name": "house_02",
        "filename": "house_02.glb",
        "prompt": (
            "A small two-story townhouse with a sloped red roof, "
            "stone chimney, blue shuttered windows, wooden balcony"
            + STYLE
        ),
    },
    {
        "name": "house_03",
        "filename": "house_03.glb",
        "prompt": (
            "A round hobbit-style house with a grass covered dome roof "
            "and round wooden door, flower garden, stone path"
            + STYLE
        ),
    },
    {
        "name": "house_04",
        "filename": "house_04.glb",
        "prompt": (
            "A small windmill building with four wooden sails, "
            "stone cylindrical base, wooden door, tiny windows"
            + STYLE
        ),
    },
    {
        "name": "villager_01",
        "filename": "villager_01.glb",
        "prompt": (
            "A tiny low-poly farmer character standing upright, "
            "straw hat, overalls, holding a pitchfork, friendly face"
            + STYLE
        ),
    },
    {
        "name": "villager_02",
        "filename": "villager_02.glb",
        "prompt": (
            "A tiny low-poly blacksmith character standing upright, "
            "leather apron, holding a hammer, muscular arms"
            + STYLE
        ),
    },
    {
        "name": "villager_03",
        "filename": "villager_03.glb",
        "prompt": (
            "A tiny low-poly scholar character standing upright, "
            "long robe, holding an open book, round glasses"
            + STYLE
        ),
    },
    {
        "name": "villager_04",
        "filename": "villager_04.glb",
        "prompt": (
            "A tiny low-poly guard character standing upright, "
            "metal helmet, holding a round shield, chainmail armor"
            + STYLE
        ),
    },
    {
        "name": "villager_05",
        "filename": "villager_05.glb",
        "prompt": (
            "A tiny low-poly builder character standing upright, "
            "hard hat, holding a wooden hammer, tool belt"
            + STYLE
        ),
    },
]


def submit_task(prompt: str) -> str:
    body = {
        "type": "text_to_model",
        "prompt": prompt,
        "negative_prompt": NEGATIVE,
    }
    resp = requests.post(f"{API_BASE}/task", headers=HEADERS, json=body)
    resp.raise_for_status()
    data = resp.json()
    if data.get("code") != 0:
        raise RuntimeError(f"API error: {data}")
    return data["data"]["task_id"]


def poll_task(task_id: str) -> dict:
    elapsed = 0
    while elapsed < MAX_POLL_TIME:
        resp = requests.get(f"{API_BASE}/task/{task_id}", headers=HEADERS)
        resp.raise_for_status()
        data = resp.json()["data"]
        status = data["status"]
        print(f"  [{elapsed:3d}s] status={status}")
        if status == "success":
            return data["output"]
        if status == "failed":
            raise RuntimeError(f"Task {task_id} failed: {data}")
        time.sleep(POLL_INTERVAL)
        elapsed += POLL_INTERVAL
    raise TimeoutError(f"Task {task_id} timed out after {MAX_POLL_TIME}s")


def download_model(url: str, filename: str):
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUTPUT_DIR / filename
    resp = requests.get(url)
    resp.raise_for_status()
    path.write_bytes(resp.content)
    size_kb = len(resp.content) / 1024
    print(f"  Saved: {path.name} ({size_kb:.0f} KB)")


def generate_model(model: dict):
    print(f"\n{'='*50}")
    print(f"Generating: {model['name']} -> {model['filename']}")
    print(f"Prompt: {model['prompt'][:80]}...")
    print(f"{'='*50}")

    task_id = submit_task(model["prompt"])
    print(f"  Task ID: {task_id}")

    output = poll_task(task_id)
    model_url = output.get("model") or output.get("pbr_model")
    if not model_url:
        raise RuntimeError(f"No model URL in output: {output}")

    download_model(model_url, model["filename"])


def main():
    parser = argparse.ArgumentParser(description="Generate 3D models via Tripo API")
    parser.add_argument(
        "--only", nargs="+", metavar="NAME",
        help="Generate only specific models by name (e.g. planet house_01)",
    )
    parser.add_argument(
        "--list", action="store_true",
        help="List all model definitions and exit",
    )
    args = parser.parse_args()

    if args.list:
        for m in MODELS:
            exists = (OUTPUT_DIR / m["filename"]).exists()
            status = "EXISTS" if exists else "missing"
            print(f"  {m['name']:15s} -> {m['filename']:20s} [{status}]")
        return

    models = MODELS
    if args.only:
        names = set(args.only)
        models = [m for m in MODELS if m["name"] in names]
        unknown = names - {m["name"] for m in models}
        if unknown:
            print(f"Unknown model names: {unknown}")
            print(f"Available: {[m['name'] for m in MODELS]}")
            sys.exit(1)

    print(f"Will generate {len(models)} model(s)")
    print(f"Output directory: {OUTPUT_DIR}")
    print(f"Estimated credits: ~{len(models) * 30}")

    for model in models:
        try:
            generate_model(model)
        except Exception as e:
            print(f"  FAILED: {e}")
            print("  Continuing with next model...")

    print(f"\nDone! Check {OUTPUT_DIR}")
    existing = list(OUTPUT_DIR.glob("*.glb"))
    print(f"Models on disk: {len(existing)}")
    for f in sorted(existing):
        print(f"  {f.name} ({f.stat().st_size / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
