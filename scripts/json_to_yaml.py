#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
json_to_yaml.py
===============
把 `Kitchen/Recipes/<菜系>/<菜系>_<slug>.json` 转成 YAML 格式，
写到  `Kitchen/Recipes/<菜系>/<菜系>_<slug>.yaml`。

YAML 比 JSON 更适合手编辑：
  - 支持注释（#）
  - 支持多行字符串
  - 字面量风格清爽

字段顺序按可读性排：name / cuisine / id / 时间 / 卡路里 / 配料 / 步骤 ...
iOS 端用 Yams 库解析成 Codable。
"""

import json
import yaml
import os
from pathlib import Path

SRC = Path(__file__).resolve().parent.parent / "Kitchen" / "Recipes"
DEST = SRC  # 原地生成 .yaml (与 .json 同目录)


def reorder_for_readability(recipe: dict) -> dict:
    """重排字段顺序，让 YAML 看起来更直观。"""
    order = [
        "id", "name", "cuisine",
        "difficulty", "duration", "calories", "servings",
        "tags", "cover",
        "ingredients", "steps",
        "tips",
    ]
    out = {}
    for k in order:
        if k in recipe:
            out[k] = recipe[k]
    # 保留未在 order 里的字段（防御性）
    for k, v in recipe.items():
        if k not in out:
            out[k] = v
    return out


def convert_one(json_path: Path) -> Path:
    with open(json_path, encoding="utf-8") as f:
        data = json.load(f)

    ordered = reorder_for_readability(data)

    yaml_path = json_path.with_suffix(".yaml")
    with open(yaml_path, "w", encoding="utf-8") as f:
        # allow_unicode: 中文/特殊字符保留
        # sort_keys: False - 我们已经手动排好序
        # default_flow_style: False - block style，可读性好
        # width: 999 - 避免一行被自动换行
        yaml.dump(
            ordered,
            f,
            allow_unicode=True,
            sort_keys=False,
            default_flow_style=False,
            width=999,
        )
    return yaml_path


def main():
    json_files = sorted(SRC.rglob("*.json"))
    if not json_files:
        print("❌ No JSON files found")
        return

    converted = 0
    for fp in json_files:
        rel = fp.relative_to(SRC)
        out = convert_one(fp)
        size_in = fp.stat().st_size
        size_out = out.stat().st_size
        print(f"  ✓ {rel}  {size_in:>6}B → {size_out:>6}B")
        converted += 1

    print()
    print(f"📊 转换完成: {converted} 个文件")
    print(f"   JSON 原总: {sum(p.stat().st_size for p in json_files) // 1024} KB")
    print(f"   YAML 总:  {sum(p.with_suffix('.yaml').stat().st_size for p in json_files) // 1024} KB")


if __name__ == "__main__":
    main()
