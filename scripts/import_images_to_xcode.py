#!/usr/bin/env python3
"""
import_images_to_xcode.py
=========================
把 /tmp/img-cache/<菜系>/<slug>.<ext> 里的图片导入 iOS 工程:

  Kitchen/Assets.xcassets/RecipeImages/<菜系>/<slug>.imageset/<slug>.<ext>
  + Contents.json (1x 标识)

这样 AsyncImage 不依赖网络，直接从 bundle 加载图片。

Xcode build phase 会在 build 之前跑 — 确保 bundle 始终有最新图片。
"""
import os
import shutil
import sys
from pathlib import Path

ROOT = Path("/Users/hengmintao/Desktop/Kitchen")
CACHE_DIR = Path("/tmp/img-cache")
ASSETS_DIR = ROOT / "Kitchen" / "Assets.xcassets" / "RecipeImages"

VALID_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".gif"}

CONTENTS_JSON = """{
  "images" : [
    {
      "filename" : "%(filename)s",
      "idiom" : "universal",
      "scale" : "1x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""


def main():
    if not CACHE_DIR.exists():
        print(f"❌ cache dir not found: {CACHE_DIR}")
        sys.exit(1)

    ASSETS_DIR.mkdir(parents=True, exist_ok=True)
    total = 0
    for cuisine_dir in sorted(CACHE_DIR.iterdir()):
        if not cuisine_dir.is_dir():
            continue
        cuisine_name = cuisine_dir.name
        for img in sorted(cuisine_dir.iterdir()):
            if img.suffix.lower() not in VALID_EXTS:
                continue
            slug = img.stem
            imageset_dir = ASSETS_DIR / cuisine_name / f"{slug}.imageset"
            imageset_dir.mkdir(parents=True, exist_ok=True)
            # 复制图片
            target_img = imageset_dir / img.name
            shutil.copy2(img, target_img)
            # Contents.json
            contents = imageset_dir / "Contents.json"
            contents.write_text(CONTENTS_JSON % {"filename": img.name})
            total += 1

    print(f"✅ imported {total} images to {ASSETS_DIR}")


if __name__ == "__main__":
    main()