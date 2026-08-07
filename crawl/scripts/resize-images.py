#!/usr/bin/env python3
"""Compress /tmp/img-cache images for iOS bundle inclusion.

Steps:
  - Read each image from /tmp/img-cache/{cuisine}/{slug}.{ext}
  - Resize to max 800px wide (preserving aspect ratio)
  - Convert to JPEG quality 80 (best size/quality trade for thumbnails)
  - Save to target dir, also update recipe JSON cover path

Target formats:
  - Single-image set: /Users/hengmintao/Desktop/Kitchen/Kitchen/Resources/images/{cuisine}/{slug}.jpg
  - The App can later read via Bundle.main.url(forResource:withExtension:)

Usage:
  python3 resize-images.py --limit 10
  python3 resize-images.py
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image

CACHE_DIR = Path("/tmp/img-cache")
TARGET_DIR = Path("/Users/hengmintao/Desktop/Kitchen/Kitchen/Resources/images")
RECIPES_DIR = Path("/Users/hengmintao/Desktop/Kitchen/Kitchen/Recipes")

MAX_W = 800
QUALITY = 80


def resize_one(src: Path, dest: Path) -> tuple[int, int]:
    """Resize src image to dest. Returns (src_size, dest_size) in bytes."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(src) as im:
        # Normalize orientation
        try:
            from PIL import ImageOps
            im = ImageOps.exif_transpose(im)
        except Exception:
            pass
        # Resize
        if im.width > MAX_W:
            ratio = MAX_W / im.width
            new_h = int(im.height * ratio)
            im = im.resize((MAX_W, new_h), Image.LANCZOS)
        # Always save as JPEG
        if im.mode != "RGB":
            im = im.convert("RGB")
        src_size = src.stat().st_size
        im.save(dest, "JPEG", quality=QUALITY, optimize=True, progressive=True)
        dest_size = dest.stat().st_size
    return src_size, dest_size


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    if not CACHE_DIR.exists():
        print(f"No cache dir at {CACHE_DIR}; run fetch-images.py first.")
        sys.exit(1)

    TARGET_DIR.mkdir(parents=True, exist_ok=True)

    files = sorted([p for p in CACHE_DIR.rglob("*") if p.is_file()])
    if args.limit:
        files = files[: args.limit]

    print(f"Compressing {len(files)} images → {TARGET_DIR}")
    total_src = 0
    total_dest = 0
    ok = 0
    fail = 0

    for i, src in enumerate(files, 1):
        rel = src.relative_to(CACHE_DIR)
        # rel = "{cuisine}/{slug}.{ext}"  →  "{cuisine}/{slug}.jpg"
        cuisine = rel.parts[0]
        stem = rel.stem
        dest = TARGET_DIR / cuisine / f"{stem}.jpg"

        try:
            src_size, dest_size = resize_one(src, dest)
            total_src += src_size
            total_dest += dest_size
            print(f"  [{i}/{len(files)}] {rel}: {src_size//1024}KB → {dest_size//1024}KB "
                  f"({100 * dest_size // src_size}%)")
            ok += 1
        except Exception as e:
            print(f"  [{i}/{len(files)}] {rel}: FAIL {e}")
            fail += 1

    print(f"\n=== {ok} ok, {fail} fail ===")
    print(f"  total: {total_src//1024//1024} MB → {total_dest//1024//1024} MB "
          f"({100 * total_dest // max(total_src, 1)}%)")

    # Update JSON cover paths from img-cache/* → images/* (relative to project)
    print("\nUpdating JSON cover paths ...")
    updated = 0
    for jpath in RECIPES_DIR.rglob("*.json"):
        try:
            d = json.loads(jpath.read_text(encoding="utf-8"))
        except Exception:
            continue
        c = d.get("cover", "").strip()
        if not c:
            continue
        # Old: img-cache/{cuisine}/{stem}.{ext}
        if c.startswith("img-cache/"):
            rest = c[len("img-cache/"):]  # "{cuisine}/{stem}.{ext}"
            new = f"images/{Path(rest).stem}.jpg" if "/" in rest else f"images/{Path(rest).stem}.jpg"
            # if rest had a cuisine folder, collapse since target dir is flat per-cuisine
            # actually keep {cuisine}/{stem}.jpg
            cuisine = rest.split("/")[0]
            stem = Path(rest).stem
            new = f"images/{cuisine}/{stem}.jpg"
            d["cover"] = new
            jpath.write_text(json.dumps(d, ensure_ascii=False, indent=2), encoding="utf-8")
            updated += 1
    print(f"  updated {updated} JSON cover paths")


if __name__ == "__main__":
    main()
