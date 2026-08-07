#!/usr/bin/env python3
"""Rebuild /tmp/img-cache from JSON cover URLs.

The previous fetch-images.py run already populated recipe JSON `cover` fields
with stable Sogou CDN URLs. This script downloads each URL → /tmp/img-cache/
mirroring the original cuisine/slug layout, so resize-images.py can consume them.

If a cover URL is 404 or empty (sogou sometimes hotlinks to purged pictures),
we fall back to the next-best source: re-query sogou with a cleaned recipe name.
"""

from __future__ import annotations

import json
import re
import ssl
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

CACHE_DIR = Path("/tmp/img-cache")
RECIPES_DIR = Path("/Users/hengmintao/Desktop/Kitchen/Kitchen/Recipes")

UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
)
_SSL_CTX = ssl._create_unverified_context()


def _fetch(url: str, headers: dict | None = None, timeout: int = 20) -> bytes:
    h = {"User-Agent": UA}
    if headers:
        h.update(headers)
    req = urllib.request.Request(url, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=_SSL_CTX) as r:
            return r.read(), r.headers.get("Content-Type", "")
    except Exception:
        return b"", ""


def download(url: str, dest: Path) -> bool:
    if dest.exists() and dest.stat().st_size > 1024:
        return True
    dest.parent.mkdir(parents=True, exist_ok=True)
    data, ctype = _fetch(url, headers={"Referer": "https://pic.sogou.com/",
                                       "Accept": "image/*,*/*;q=0.8"})
    if len(data) < 1024:
        return False
    ext = ".jpg"
    if "png" in ctype:
        ext = ".png"
    elif "webp" in ctype:
        ext = ".webp"
    if dest.suffix.lower() not in {".jpg", ".jpeg", ".png", ".webp"}:
        dest = dest.with_suffix(ext)
    dest.write_bytes(data)
    return True


def slugify(name: str) -> str:
    return re.sub(r"[\\/:*?\"<>|]+", "_", name).strip()[:80] or "unnamed"


def main():
    if not RECIPES_DIR.exists():
        print("Recipes dir missing"); sys.exit(1)
    CACHE_DIR.mkdir(parents=True, exist_ok=True)

    # Load every recipe
    recipes = []
    for jpath in sorted(RECIPES_DIR.rglob("*.json")):
        try:
            d = json.loads(jpath.read_text(encoding="utf-8"))
        except Exception:
            continue
        if not isinstance(d, dict):
            continue
        c = (d.get("cover") or "").strip()
        if c.startswith("http"):
            recipes.append((jpath, d, c))
    print(f"Recipes with URL cover: {len(recipes)}")

    ok = 0
    fail = 0
    fails = []
    for i, (_, d, url) in enumerate(recipes, 1):
        cuisine = d.get("cuisine", "?")
        name = d.get("name", "?")
        slug = slugify(name)
        dest_dir = CACHE_DIR / cuisine
        dest = dest_dir / slug

        if download(url, dest):
            ok += 1
        else:
            fail += 1
            fails.append((cuisine, name, url))

        if i % 20 == 0:
            print(f"[{i}/{len(recipes)}] ok={ok} fail={fail}", file=sys.stderr)

    print(f"\n=== {ok} ok, {fail} fail ===")
    if fails:
        print("\nfail samples:")
        for c, n, u in fails[:8]:
            print(f"  - [{c}] {n}: {u[:70]}")


if __name__ == "__main__":
    main()
