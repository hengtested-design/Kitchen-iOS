#!/usr/bin/env python3
"""
probe_image_status.py — 进程 A: 轻量扫描器
=============================================
扫描所有菜谱 JSON, 给每道菜打标签:
  - has_image: 1 (cover 字段非空 + 是合法 URL) / 0 (空 / 非法)
  - source: chuimg / sogou / zifangsk / unknown / none
  - cache_hit: 1 (本地 /tmp/img-cache 有缓存) / 0
  - needs_fetch: 1 (has_image=0 且 cache_hit=0) / 0

输出:
  - Kitchen/image_status.json: 全量状态
  - Kitchen/image_status.diff.json: 与上一次对比 (新增/修改/删除)

不修改原菜谱 JSON — 只读取 + 写状态文件。

设计意图 (老板的"双进程"思路):
  进程 A (这个): 扫 + 标 + diff — CPU 密集, 毫秒级
  进程 B (fetch-images.py): 爬图 — IO 密集, 慢

两个进程可同时跑:
  - A 输出 needs_fetch=1 的清单
  - B 只针对 needs_fetch=1 爬图
  - B 完成后, A 再跑一次 → diff 自动验证"图片是否跟上菜谱"
"""
import json
import sys
import os
import re
from pathlib import Path
from datetime import datetime
from collections import defaultdict

ROOT = Path("/Users/hengmintao/Desktop/Kitchen")
RECIPES_DIR = ROOT / "Kitchen" / "Recipes"
CACHE_DIR = Path("/tmp/img-cache")
STATUS_FILE = ROOT / "Kitchen" / "image_status.json"
DIFF_FILE = ROOT / "Kitchen" / "image_status.diff.json"

VALID_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".gif"}
URL_HOST_PATTERNS = {
    "chuimg": re.compile(r"s\.chuimg\.com"),
    "sogou":  re.compile(r"sogoucdn\.com"),
    "zifangsk": re.compile(r"img\.zifangsk\.com"),
}


def classify_source(cover: str) -> str:
    """根据 host 分类图片源."""
    if not cover:
        return "none"
    for name, pat in URL_HOST_PATTERNS.items():
        if pat.search(cover):
            return name
    return "unknown"


def has_local_cache(cuisine: str, slug: str) -> bool:
    """检查 /tmp/img-cache/<cuisine>/<slug>.<ext> 是否有图片."""
    cache_dir = CACHE_DIR / cuisine
    if not cache_dir.exists():
        return False
    for ext in VALID_EXTS:
        if (cache_dir / f"{slug}{ext}").exists():
            return True
    return False


def slugify(name: str) -> str:
    """与 fetch-images.py 保持一致的命名规则."""
    s = re.sub(r"[\\/:*?\"<>|]+", "_", name).strip()
    return s[:80] or "unnamed"


def scan_recipes():
    """扫所有菜谱, 返回 status list."""
    status = []
    for cuisine_dir in sorted(RECIPES_DIR.iterdir()):
        if not cuisine_dir.is_dir():
            continue
        cuisine = cuisine_dir.name
        for jpath in sorted(cuisine_dir.glob("*.json")):
            try:
                d = json.loads(jpath.read_text(encoding="utf-8"))
            except Exception:
                continue
            name = d.get("name", "?")
            cover = (d.get("cover") or "").strip()
            slug = slugify(name)

            # 判定 has_image: cover 是 http URL 且长度合理
            has_image = 1 if (cover.startswith(("http://", "https://")) and len(cover) > 20) else 0
            source = classify_source(cover) if has_image else "none"
            cache_hit = 1 if has_local_cache(cuisine, slug) else 0
            # needs_fetch: has_image=0 且本地无缓存
            needs_fetch = 0 if (has_image or cache_hit) else 1

            status.append({
                "path": str(jpath.relative_to(ROOT)),
                "cuisine": cuisine,
                "name": name,
                "slug": slug,
                "cover": cover[:120] if cover else "",
                "source": source,
                "has_image": has_image,
                "cache_hit": cache_hit,
                "needs_fetch": needs_fetch,
            })
    return status


def load_prev_status():
    """读上一次的状态文件 — 用于 diff."""
    if not STATUS_FILE.exists():
        return None
    try:
        return json.loads(STATUS_FILE.read_text(encoding="utf-8"))
    except Exception:
        return None


def diff_status(old, new):
    """对比新旧 status, 找出 changed/added/removed."""
    if old is None:
        return {"added": new, "removed": [], "changed": []}

    old_by_path = {r["path"]: r for r in old["recipes"]}
    new_by_path = {r["path"]: r for r in new}

    added = [n for r, n in new_by_path.items() if r not in old_by_path]
    removed = [old_by_path[r] for r in old_by_path if r not in new_by_path]
    changed = []
    for path, new_r in new_by_path.items():
        if path in old_by_path:
            old_r = old_by_path[path]
            if old_r["has_image"] != new_r["has_image"] or old_r["cache_hit"] != new_r["cache_hit"] or old_r["cover"] != new_r["cover"]:
                changed.append({
                    "path": path,
                    "name": new_r["name"],
                    "before": {k: old_r[k] for k in ("has_image", "cache_hit", "source", "cover")},
                    "after": {k: new_r[k] for k in ("has_image", "cache_hit", "source", "cover")},
                })

    return {"added": added, "removed": removed, "changed": changed}


def main():
    print("🔍 扫描菜谱状态...")
    recipes = scan_recipes()

    total = len(recipes)
    with_image = sum(1 for r in recipes if r["has_image"] == 1)
    no_image = sum(1 for r in recipes if r["has_image"] == 0)
    cached = sum(1 for r in recipes if r["cache_hit"] == 1)
    needs_fetch = sum(1 for r in recipes if r["needs_fetch"] == 1)

    print(f"📊 total: {total}")
    print(f"   ✅ with_image: {with_image} ({with_image/total*100:.1f}%)")
    print(f"   ❌ no_image:   {no_image} ({no_image/total*100:.1f}%)")
    print(f"   💾 cached:     {cached}")
    print(f"   🔄 needs_fetch: {needs_fetch}")

    # 按 source 分布
    by_source = defaultdict(int)
    for r in recipes:
        if r["has_image"]:
            by_source[r["source"]] += 1
    print(f"   📦 sources: {dict(by_source)}")

    # 与上次对比
    old = load_prev_status()
    diff = diff_status(old, recipes)

    new_payload = {
        "scanned_at": datetime.now().isoformat(),
        "total": total,
        "summary": {
            "with_image": with_image,
            "no_image": no_image,
            "cached": cached,
            "needs_fetch": needs_fetch,
            "by_source": dict(by_source),
        },
        "recipes": recipes,
    }

    STATUS_FILE.write_text(
        json.dumps(new_payload, ensure_ascii=False, indent=2),
        encoding="utf-8"
    )
    DIFF_FILE.write_text(
        json.dumps({
            "scanned_at": datetime.now().isoformat(),
            "added_count": len(diff["added"]),
            "removed_count": len(diff["removed"]),
            "changed_count": len(diff["changed"]),
            "added": diff["added"][:20],
            "removed": diff["removed"][:20],
            "changed": diff["changed"][:30],
        }, ensure_ascii=False, indent=2),
        encoding="utf-8"
    )

    print(f"\n📝 status → {STATUS_FILE.relative_to(ROOT)}")
    print(f"📝 diff   → {DIFF_FILE.relative_to(ROOT)}")
    if diff["changed"]:
        print(f"\n🔄 这次扫描相比上次有 {len(diff['changed'])} 道菜状态变化:")
        for c in diff["changed"][:10]:
            b = c["before"]
            a = c["after"]
            arrow = "🎉 获得图片" if (b["has_image"] == 0 and a["has_image"] == 1) else \
                    "🗑️  失去图片" if (b["has_image"] == 1 and a["has_image"] == 0) else \
                    "✏️  改了图"
            print(f"  {arrow}: {c['name']} (has_image: {b['has_image']}→{a['has_image']})")


if __name__ == "__main__":
    main()