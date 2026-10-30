#!/bin/sh
#
# 安装提交钩子（**三仓通用**：DoyahNotes / Doyah Retro / Doyah Studio）
# 在**本仓根目录**执行：
#
#   bash tools/hooks/install.sh        # DoyahNotes / Doyah Retro（钩子在 tools/hooks/）
#   bash Scripts/hooks/install.sh      # Doyah Studio（钩子在 Scripts/hooks/）
#
# 装好后每次 git commit 都会先跑本仓的检查：
#   · DoyahNotes      → node tools/logic-check/run.mjs（五层回归）
#   · Retro / Studio  → check-exclusive-sections.py --mine windows --base origin/master（越界门禁）
set -e

HOOKS="$(git rev-parse --git-path hooks)"
SRC="$(dirname "$0")/pre-commit"

[ -f "$SRC" ] || { echo "找不到 $SRC（请在本仓根目录执行）"; exit 2; }

mkdir -p "$HOOKS"
cp "$SRC" "$HOOKS/pre-commit"
chmod +x "$HOOKS/pre-commit"
echo "已安装：$HOOKS/pre-commit"
echo "验证：git commit 前会先跑本仓检查（五层回归 / 越界门禁）；临时绕过用 git commit --no-verify"
