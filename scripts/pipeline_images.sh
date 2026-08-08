#!/usr/bin/env bash
# pipeline_images.sh — 老板的"双进程流水线"完整闭环
#
# A 进程: probe_image_status.py  → 扫描 + 标记
# B 进程: fetch-images.py        → 爬图 (异步, IO 密集)
# 后处理: import_images_to_xcode.py → 缓存导入 Xcode bundle
# 验证:   probe_image_status.py  → 重新扫描 + diff 验证
#
# 用法:
#   bash scripts/pipeline_images.sh           # 全流程
#   bash scripts/pipeline_images.sh --skip-fetch  # 只扫 + 验证 (不爬图)

set -euo pipefail
cd "$(dirname "$0")/.."

SKIP_FETCH=false
if [ "${1:-}" = "--skip-fetch" ]; then
    SKIP_FETCH=true
fi

echo "==============================================="
echo "  进程 A: probe_image_status (扫描 + 标记)"
echo "==============================================="
python3 scripts/probe_image_status.py

if [ "$SKIP_FETCH" = "true" ]; then
    echo ""
    echo "⏭️  跳过 fetch (--skip-fetch)"
else
    echo ""
    echo "==============================================="
    echo "  进程 B: fetch-images (爬图, IO 密集)"
    echo "==============================================="
    python3 -u crawl/scripts/fetch-images.py
fi

echo ""
echo "==============================================="
echo "  后处理: import_images_to_xcode (导入 bundle)"
echo "==============================================="
python3 scripts/import_images_to_xcode.py

echo ""
echo "==============================================="
echo "  验证: probe_image_status 二次扫描 + diff"
echo "==============================================="
python3 scripts/probe_image_status.py

echo ""
echo "==============================================="
echo "  ✅ 流水线完成"
echo "  下一步: cd Kitchen && bundle exec xcodebuild ..."
echo "  或直接: open Kitchen.xcodeproj + Cmd+R"
echo "==============================================="