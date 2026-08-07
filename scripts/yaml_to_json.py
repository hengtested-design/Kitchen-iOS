#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
yaml_to_json.py
===============
把 YAML 源文件 转回 JSON（保留原字段顺序，输出到 distribution/）。

用法：
  python3 scripts/yaml_to_json.py

输出文件（按字段顺序对齐）：
  distribution/
    ├── manifest.json
    └── <菜系>.json
"""

import json
import yaml
import os
from pathlib import Path
from collections import OrderedDict
from datetime import datetime

SRC = Path(__file__).resolve().parent.parent / "Kitchen" / "Recipes"
DIST = Path(__file__).resolve().parent.parent / "distribution"


def main():
    yaml_files = sorted(SRC.rglob("*.yaml"))
    if not yaml_files:
        print("❌ No YAML files found")
        return

    DIST.mkdir(exist_ok=True)
    for p in DIST.iterdir():
        if p.is_file() and p.suffix == ".json":
            p.unlink()

    cuisines = {}
    total_recipes = 0
    zero_cal = 0
    for f in yaml_files:
        with open(f, encoding="utf-8") as fh:
            d = yaml.safe_load(fh)
        # 让字段保持原顺序（PyYAML 用 OrderedDict）
        if not isinstance(d, dict):
            continue
        cuisine = d.get("cuisine", "其他")
        cuisines.setdefault(cuisine, []).append(d)
        total_recipes += 1
        if d.get("calories", -1) <= 0:
            zero_cal += 1

    for cuisine, recipes in cuisines.items():
        out = DIST / f"{cuisine}.json"
        with open(out, "w", encoding="utf-8") as fh:
            json.dump(recipes, fh, ensure_ascii=False, indent=2)
        print(f"  ✓ {out.name:>12}  {len(recipes):>3d} 道菜")

    manifest = {
        "schema_version": "1.0",
        "data_version": datetime.now().strftime("%Y%m%d.%H%M"),
        "updated_at": datetime.now().isoformat(timespec="seconds"),
        "total": total_recipes,
        "cuisines": sorted(cuisines.keys()),
        "files": {c: f"{c}.json" for c in sorted(cuisines.keys())},
        "source_attribution": "CookBook-KG + 手工精选 + YAML 源格式",
    }
    with open(DIST / "manifest.json", "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, ensure_ascii=False, indent=2)
    print(f"  ✓ manifest.json")

    print()
    print(f"📊 {total_recipes} 道菜 · JSON {sum(p.stat().st_size for p in DIST.glob('*.json')) // 1024} KB · YAML 源 {sum(p.stat().st_size for p in yaml_files) // 1024} KB")
    if zero_cal > 0:
        print(f"⚠️  {zero_cal} 道菜卡路里为 0")


if __name__ == "__main__":
    main()
