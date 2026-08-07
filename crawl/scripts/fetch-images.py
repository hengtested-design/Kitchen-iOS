#!/usr/bin/env python3
"""Fetch cover images for recipes from Sogou image search.

Sogou returns a JSON blob via window.__INITIAL_STATE__ with `searchList`,
each item has picUrl (original), thumbUrl (Sogou CDN cached), width/height/size.

Strategy:
  1. Search by Chinese name via pic.sogou.com/pics
  2. Pick first result with width >= 400 and reasonable aspect (0.5..2.0)
  3. Try picUrl first → fallback thumbUrl / locImageLink (Sogou CDN)
  4. Save to /tmp/img-cache/{cuisine}/{slug}.{ext}
  5. Update recipe JSON `cover` field with relative path

Robustness:
  - Lenient SSL (some Chinese CDNs have self-signed certs)
  - Salvage search results if Sogou returns malformed JSON
  - Multi-URL fallback chain for downloads
  - Per-recipe try/except so one failure doesn't stop the whole batch

Usage:
  python3 fetch-images.py --dry-run   # show what would be fetched
  python3 fetch-images.py --limit 5   # only do first 5 recipes
  python3 fetch-images.py             # all empty-cover recipes
"""

from __future__ import annotations

import argparse
import json
import os
import re
import ssl
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Optional

ROOT = Path("/Users/hengmintao/Desktop/Kitchen")
RECIPES_DIR = ROOT / "Kitchen" / "Recipes"
CACHE_DIR = Path("/tmp/img-cache")

UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
)
_SSL_CTX = ssl._create_unverified_context()
VALID_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".gif"}


def _fetch(url: str, headers: Optional[dict] = None, timeout: int = 15, method: str = "GET") -> bytes:
    """Fetch URL. Returns bytes (empty on failure). Lenient SSL."""
    h = {"User-Agent": UA}
    if headers:
        h.update(headers)
    req = urllib.request.Request(url, headers=h, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=_SSL_CTX) as r:
            return r.read()
    except Exception:
        return b""


def _head(url: str) -> Optional[str]:
    """HEAD request → Content-Type or None."""
    try:
        req = urllib.request.Request(
            url, method="HEAD", headers={"User-Agent": UA, "Referer": "https://pic.sogou.com/"}
        )
        with urllib.request.urlopen(req, timeout=8, context=_SSL_CTX) as r:
            return r.headers.get("Content-Type", "")
    except Exception:
        return None


def sogou_search(name: str) -> list[dict]:
    """Hit Sogou image search, return list of normalized items."""
    encoded = urllib.parse.quote(name.encode("gbk"))
    url = f"https://pic.sogou.com/pics?query={encoded}&style=pic"
    html = _fetch(
        url,
        headers={
            "Accept": "text/html",
            "Accept-Language": "zh-CN,zh;q=0.9",
            "Referer": "https://pic.sogou.com/",
        },
    ).decode("utf-8", errors="ignore")
    if not html:
        return []
    m = re.search(r"window\.__INITIAL_STATE__\s*=\s*(\{.+?})\s*;", html, re.DOTALL)
    if not m:
        return []
    blob = m.group(1).replace("\\u002F", "/").replace("\\u003C", "<").replace("\\u003E", ">")
    blob = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", "", blob)
    blob = blob.replace('\\"', '"').replace("\\\\", "\\")
    try:
        data = json.loads(blob)
        items = data.get("searchList", {}).get("searchList") or []
        return [_normalize(it) for it in items if (it.get("width") or 0) > 0 and (it.get("height") or 0) > 0]
    except json.JSONDecodeError:
        return _salvage(blob)


def _salvage(blob: str) -> list[dict]:
    """Crude fallback: pull tuples from raw text if JSON breaks."""
    out = []
    for m in re.finditer(
        r'"picUrl"\s*:\s*"([^"]+)"\s*,\s*"thumbUrl"\s*:\s*"([^"]+)"\s*,[^}]*?"width"\s*:\s*(\d+)\s*,\s*"height"\s*:\s*(\d+)',
        blob,
    ):
        pic, thumb, w, h = m.group(1), m.group(2), int(m.group(3)), int(m.group(4))
        out.append({"picUrl": pic, "thumbUrl": thumb, "locImageLink": thumb,
                    "width": w, "height": h, "size": 0, "source": ""})
    return out


def _normalize(it: dict) -> dict:
    w = it.get("width") or 0
    h = it.get("height") or 0
    return {
        "picUrl": it.get("picUrl"),
        "thumbUrl": it.get("thumbUrl"),
        "locImageLink": it.get("locImageLink"),
        "width": w,
        "height": h,
        "size": it.get("size", 0),
        "source": it.get("ch_site_name", ""),
    }


def pick_best(results: list[dict], min_w: int = 400) -> Optional[dict]:
    """First large-enough image with reasonable aspect ratio."""
    for r in results:
        ratio = r["width"] / r["height"]
        if r["width"] >= min_w and 0.5 <= ratio <= 2.0:
            return r
    return None


def download_to(url: str, dest: Path) -> Optional[Path]:
    """Download single image. Tries URL directly (already tries SSL-lenient).

    Returns the saved path on success, None on failure.
    """
    if dest.suffix.lower() in VALID_EXTS and dest.exists() and dest.stat().st_size > 1024:
        return dest
    dest.parent.mkdir(parents=True, exist_ok=True)
    data = _fetch(
        url,
        headers={"Accept": "image/*,*/*;q=0.8", "Referer": "https://pic.sogou.com/"},
        timeout=20,
    )
    if len(data) < 1024:
        return None
    ctype = _head(url) or ""
    ext = ".jpg"
    if "png" in ctype:
        ext = ".png"
    elif "webp" in ctype:
        ext = ".webp"
    elif "gif" in ctype:
        ext = ".gif"
    if dest.suffix.lower() not in VALID_EXTS:
        dest = dest.with_suffix(ext)
    dest.write_bytes(data)
    return dest


def download_with_fallback(pick: dict, dest: Path, log) -> Optional[Path]:
    """Try picUrl → thumbUrl → locImageLink."""
    candidates = []
    for k in ("picUrl", "thumbUrl", "locImageLink"):
        v = pick.get(k)
        if v and v not in candidates:
            candidates.append(v)
    for idx, url in enumerate(candidates):
        saved = download_to(url, dest)
        if saved:
            if idx > 0:
                log(f"     used fallback #{idx+1}")
            return saved
    return None


def iter_recipes(only_missing: bool = True):
    """Yield (json_path, recipe_dict) for all recipes."""
    for cuisine_dir in sorted(RECIPES_DIR.iterdir()):
        if not cuisine_dir.is_dir():
            continue
        for jpath in sorted(cuisine_dir.glob("*.json")):
            try:
                d = json.loads(jpath.read_text(encoding="utf-8"))
            except Exception:
                continue
            if only_missing:
                c = (d.get("cover") or "").strip()
                # Skip if cover is a remote URL (already done)
                if c and c.startswith(("http://", "https://")):
                    continue
                # Skip if cover looks like a stale relative path from previous run
                if c and "img-cache/" in c:
                    pass  # treat as missing — re-fetch
                elif c:
                    continue  # some other non-empty value, leave it
            yield jpath, d


def slugify(name: str) -> str:
    """Make a filename-safe slug from Chinese name."""
    s = re.sub(r"[\\/:*?\"<>|]+", "_", name).strip()
    return s[:80] or "unnamed"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="Max recipes (0 = all)")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    recipes = list(iter_recipes(only_missing=True))
    if args.limit:
        recipes = recipes[: args.limit]
    total = len(recipes)
    print(f"Total recipes to enrich: {total}")
    CACHE_DIR.mkdir(parents=True, exist_ok=True)

    success = 0
    fail = 0
    no_results = []
    download_fails = []

    for i, (jpath, d) in enumerate(recipes, 1):
        name = d.get("name", "?")
        cuisine = d.get("cuisine", "?")
        slug = slugify(name)
        print(f"\n[{i}/{total}] {cuisine} · {name}")

        try:
            results = sogou_search(name)
        except Exception as e:
            print(f"  ! sogou failed: {e}")
            fail += 1
            time.sleep(1.0)
            continue

        if not results:
            print(f"  · no results from sogou")
            no_results.append(name)
            fail += 1
            time.sleep(0.6)
            continue

        pick = pick_best(results)
        if pick is None:
            print(f"  · no image meets width/aspect criteria ({len(results)} results)")
            fail += 1
            time.sleep(0.6)
            continue

        print(f"  ✓ {pick['width']}×{pick['height']} ({pick['source']})")

        if args.dry_run:
            success += 1
            continue

        dest_dir = CACHE_DIR / cuisine
        saved = download_with_fallback(pick, dest_dir / slug, lambda m: print(m))
        if saved:
            # JSON cover = Sogou CDN URL (stable, no local path dep)
            # We still keep the local cache for offline preview / fallback.
            cdn_url = pick.get("locImageLink") or pick.get("thumbUrl") or pick.get("picUrl") or ""
            d["cover"] = cdn_url
            d["_coverLocal"] = str(saved)  # internal: where we cached it locally
            jpath.write_text(json.dumps(d, ensure_ascii=False, indent=2), encoding="utf-8")
            print(f"  → saved {saved.name} ({saved.stat().st_size // 1024} KB), cover = {cdn_url}")
            success += 1
        else:
            download_fails.append(name)
            fail += 1

        time.sleep(1.0)

    print(f"\n=== Done: {success}/{total} ok, {fail} fail ===")
    if no_results:
        print(f"  · no-results: {len(no_results)} → {no_results[:5]}{'...' if len(no_results)>5 else ''}")
    if download_fails:
        print(f"  · download-fails: {len(download_fails)} → {download_fails[:5]}{'...' if len(download_fails)>5 else ''}")


if __name__ == "__main__":
    main()
