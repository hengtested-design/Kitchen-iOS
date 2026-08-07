#!/usr/bin/env python3
"""Fix the 15 leftover img.zhifure.com URLs in recipe JSON.

zhifure.com CDN went dead, but these are popular dishes (青椒土豆丝, 鱼香肉丝,
宫保鸡丁...). Sogou definitely has good pics for them.

For every recipe with cover starting with img.zhifure.com:
  1. Re-query sogou for that recipe name
  2. If found: update cover → sogou CDN URL, download to /tmp/img-cache
  3. If not found: clear cover (App will fallback to placeholder)
"""

from __future__ import annotations

import json
import importlib.util
import re
import sys
from pathlib import Path

# fetch-images.py has a hyphen; load via importlib
def _load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

HERE = Path(__file__).parent
fetch_images = _load("fetch_images", HERE / "fetch-images.py")
download_from_json = _load("download_from_json", HERE / "download-from-json.py")

RECIPES_DIR = Path("/Users/hengmintao/Desktop/Kitchen/Kitchen/Recipes")
CACHE_DIR = Path("/tmp/img-cache")


def main():
    fixed = 0
    cleared = 0
    skipped = 0

    for jpath in sorted(RECIPES_DIR.rglob("*.json")):
        try:
            d = json.loads(jpath.read_text(encoding="utf-8"))
        except Exception:
            continue
        if not isinstance(d, dict):
            continue
        c = (d.get("cover") or "").strip()
        if "zhifure" not in c:
            continue
        skipped += 1

        cuisine = d.get("cuisine", "?")
        name = d.get("name", "?")
        print(f"\n[{cuisine}] {name} (zhifure → sogou)")

        try:
            results = fetch_images.sogou_search(name)
        except Exception as e:
            print(f"  ! sogou failed: {e}")
            continue
        pick = fetch_images.pick_best(results, min_w=400)
        if not pick:
            print(f"  · no sogou hit — clearing cover")
            d["cover"] = ""
            jpath.write_text(json.dumps(d, ensure_ascii=False, indent=2), encoding="utf-8")
            cleared += 1
            continue

        cdn_url = pick.get("locImageLink") or pick.get("thumbUrl") or pick.get("picUrl") or ""
        if cdn_url:
            d["cover"] = cdn_url
            jpath.write_text(json.dumps(d, ensure_ascii=False, indent=2), encoding="utf-8")
            print(f"  ✓ {pick['width']}×{pick['height']} ({pick['source']}) → {cdn_url[:60]}")
            fixed += 1

        # Also download to cache
        slug = download_from_json.slugify(name)
        dest = CACHE_DIR / cuisine / slug
        saved = fetch_images.download_with_fallback(pick, dest, lambda m: print(m))
        if saved:
            print(f"  → {saved.name} ({saved.stat().st_size // 1024} KB)")
        else:
            print(f"  ! download failed")

    print(f"\n=== Scanned {skipped} zhifure URLs, Fixed {fixed}, cleared {cleared} ===")


if __name__ == "__main__":
    main()
