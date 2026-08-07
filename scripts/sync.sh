#!/usr/bin/env bash
# sync.sh — 菜谱数据同步脚本
# 用法：编辑完 Kitchen/Recipes/<菜系>/*.yaml 后，跑这个脚本即可。
#
#   bash scripts/sync.sh         # 默认同步本机分布 + push
#   bash scripts/sync.sh --no-push   # 只生成 JSON 不 push

set -euo pipefail

cd "$(dirname "$0")/.."

PUSH=true
if [ "${1:-}" = "--no-push" ]; then
    PUSH=false
fi

echo "==============================================="
echo "  Step 1: YAML → JSON 重导出"
echo "==============================================="
python3 scripts/yaml_to_json.py
echo ""

echo "==============================================="
echo "  Step 2: Roundtrip 校验"
echo "==============================================="
python3 - <<'PYEOF'
import json, yaml
from pathlib import Path

src = Path("Kitchen/Recipes")
dist = Path("distribution")

bad = 0
total = 0
for jf in sorted(src.rglob("*.json")):
    yf = jf.with_suffix(".yaml")
    if not yf.exists():
        continue
    total += 1
    with open(jf, encoding="utf-8") as f:
        a = json.load(f)
    with open(yf, encoding="utf-8") as f:
        b = yaml.safe_load(f)
    if a != b:
        bad += 1
        print(f"  ❌ {jf.relative_to(src)}: 不匹配")
print(f"  ✅ {total} 个文件比对完成，{bad} 个不匹配")
PYEOF
echo ""

if $PUSH; then
    echo "==============================================="
    echo "  Step 3: 推 GitHub Data"
    echo "==============================================="
    cd distribution
    if ! git diff --quiet; then
        git add -A
        git -c user.name="hengmintao" -c user.email="hengmintao@users.noreply.github.com" \
            commit -m "同步菜谱数据"
        GIT_TERMINAL_PROMPT=0 git push origin main
    else
        echo "  没有改动，跳过 push"
    fi
fi

echo ""
echo "🎉 完成！App 启动会自动拉新数据，或点 ⟳ 手动刷新。"
