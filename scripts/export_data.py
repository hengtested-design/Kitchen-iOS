#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
export_data.py
==============
把 Kitchen/Recipes/ 下的菜谱 JSON 打成"发布版"目录，
准备推送到 GitHub，供 iOS App 远程拉取。

输出目录：./distribution/
  - <菜系>.json   每个菜系一个文件
  - manifest.json 版本号+文件清单
  - README.md     给 GitHub 仓库看的说明

用法：
  python3 scripts/export_data.py
"""

import json
from pathlib import Path
from datetime import datetime

SRC = Path(__file__).resolve().parent.parent / "Kitchen" / "Recipes"
DIST = Path(__file__).resolve().parent.parent / "distribution"


def main():
    DIST.mkdir(exist_ok=True)

    # 清空老文件
    for p in DIST.iterdir():
        if p.is_file():
            p.unlink()

    # 按菜系分组
    cuisines = {}
    total = 0
    zero_cal = 0
    for f in sorted(SRC.rglob("*.json")):
        with open(f, encoding="utf-8") as fh:
            d = json.load(fh)
        cuisine = d.get("cuisine", "其他")
        cuisines.setdefault(cuisine, []).append(d)
        total += 1
        if d.get("calories", -1) <= 0:
            zero_cal += 1

    # 输出每个菜系 JSON
    for cuisine, recipes in cuisines.items():
        out = DIST / f"{cuisine}.json"
        with open(out, "w", encoding="utf-8") as fh:
            json.dump(recipes, fh, ensure_ascii=False, indent=2)
        print(f"  ✓ {out.name:>12s}  {len(recipes):>3d} 道菜")

    # manifest.json
    manifest = {
        "schema_version": "1.0",
        "data_version": datetime.now().strftime("%Y%m%d.%H%M"),
        "updated_at": datetime.now().isoformat(timespec="seconds"),
        "total": total,
        "cuisines": sorted(cuisines.keys()),
        "files": {c: f"{c}.json" for c in sorted(cuisines.keys())},
        "source_attribution": "CookBook-KG (https://github.com/ngl567/CookBook-KG) + manual curation",
    }
    with open(DIST / "manifest.json", "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, ensure_ascii=False, indent=2)
    print("  ✓ manifest.json")

    # README.md
    lines = [
        "# Kitchen-Data", "",
        "iOS App **Kitchen** 的菜谱数据源（远程托管）。", "",
        "由 [jsDelivr CDN](https://www.jsdelivr.com) 加速，iOS App 启动时远程拉取。", "",
        "## 文件", "",
        "- **manifest.json** — 版本号、菜系列表、文件清单",
        "- **<菜系>.json** — 每个菜系一个文件", "",
        f"## 当前 {total} 道菜，卡路里为 0 的还有 {zero_cal} 道",
        "",
        "| 菜系 | 道数 |",
        "|---|---|",
    ]
    for c in sorted(cuisines.keys()):
        lines.append(f"| {c} | {len(cuisines[c])} |")
    lines += [
        "",
        "## 数据来源", "",
        "- 基础: [CookBook-KG](https://github.com/ngl567/CookBook-KG)（中式菜谱知识图谱）",
        "- 手工精选: 15 道（带原始热量）",
        f"- 填充: {total - 15} 道（`scripts/fill_calories.py` 自动估算）",
        "",
        "## 更新流程", "",
        "1. 改数据（本地）",
        "2. `python3 scripts/fill_calories.py --apply`（重算卡路里）",
        "3. `python3 scripts/export_data.py`（打包）",
        "4. `git add . && git commit && git push`",
        "",
        "iOS App 下次启动自动拉到新数据，无需升级 ipa。",
    ]
    with open(DIST / "README.md", "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))
    print("  ✓ README.md")

    print()
    print(f"📊 {total} 道菜 · {sum(p.stat().st_size for p in DIST.glob('*.json')) // 1024} KB")
    if zero_cal > 0:
        print(f"⚠️  还有 {zero_cal} 道菜卡路里为 0，需要先跑 fill_calories.py --apply")
    else:
        print("✅ 卡路里 100% 已填")


if __name__ == "__main__":
    main()
