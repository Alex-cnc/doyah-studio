#!/usr/bin/env bash
# 生成「Linux 侧离线交接包」—— 三书快照 + 验收自检清单，供需求提出者手工带到公司环境。
#
# 背景（2026-09-27 需求提出者）：公司电脑上不配置个人 GitHub 凭据、也不自动拉取，
# 三书靠**手工搬运**。故本脚本产出单个 zip，拷走即用，不需要账号与网络。
#
# 用法：./Scripts/export-linux-handoff.sh            # 输出到 dist/linux-handoff-YYYYMMDD.zip
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTES="${DOYAH_NOTES_DIR:-$HOME/.dsh/projects/DoyahNotes}"
STAMP="$(date +%Y%m%d)"
OUT="$ROOT/dist/linux-handoff-$STAMP"
ZIP="$ROOT/dist/linux-handoff-$STAMP.zip"

rm -rf "$OUT"; mkdir -p "$OUT/Studio" "$OUT/Notes"

# 1) 说明页与自检清单（模板在 Scripts/linux-handoff/）
cp "$ROOT/Scripts/linux-handoff/读我-先读这个.md" "$OUT/读我-先读这个.md"
cp "$ROOT/Scripts/linux-handoff/自检清单.md"       "$OUT/自检清单.md"

# 2) Studio 侧：三书 + 平台实现状态
for f in 产品能力规划说明书.md 需求规范书.md 概要设计.md 平台实现状态.json; do
  [ -f "$ROOT/Docs/$f" ] && cp "$ROOT/Docs/$f" "$OUT/Studio/$f" || echo "  ⚠ 缺 Docs/$f"
done

# 3) Notes 侧：三书 + 核心契约 + 范围纪律
if [ -d "$NOTES" ]; then
  for f in 产品能力规划说明书.md 需求规范书.md 概要设计.md 核心契约.md; do
    [ -f "$NOTES/Docs/$f" ] && cp "$NOTES/Docs/$f" "$OUT/Notes/$f" || echo "  ⚠ 缺 Notes/Docs/$f"
  done
  [ -f "$NOTES/AGENT-SPEC.md" ] && cp "$NOTES/AGENT-SPEC.md" "$OUT/Notes/AGENT-SPEC.md"
  # 契约检查脚本（若在，便于对方自检 C1~C13；不要求，纯参考）
  mkdir -p "$OUT/Notes/tools"
  for s in contract-check.py docs-check.py; do
    [ -f "$NOTES/tools/logic-check/$s" ] && cp "$NOTES/tools/logic-check/$s" "$OUT/Notes/tools/" || true
  done
else
  echo "  ⚠ 未找到 Notes 仓（${NOTES}）；只打包 Studio 侧。可用 DOYAH_NOTES_DIR=... 指定"
fi

# 4) 快照信息（版本号 + 提交 SHA + 生成时间）—— 便于对方确认拿到的是哪一版
{
  echo "生成时间：$(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "Studio 仓提交：$(cd "$ROOT" && git rev-parse --short HEAD 2>/dev/null || echo '未知')"
  [ -d "$NOTES" ] && echo "Notes 仓提交：$(cd "$NOTES" && git rev-parse --short HEAD 2>/dev/null || echo '未知')"
  echo
  echo "三书最新版本（取变更记录最大值，用于确认拿到的是哪一版）："
  # 版本号取「文档内所有 **vX.Y** 的最大值」（变更记录行顺序不一定严格倒序，取最大值最稳）
  newest() { grep -oE '\*\*v[0-9]+\.[0-9]+\*\*' "$1" 2>/dev/null | tr -d '*' | sort -t. -k1,1n -k2,2n | tail -1; }
  for f in "$ROOT/Docs/产品能力规划说明书.md" "$ROOT/Docs/需求规范书.md" "$ROOT/Docs/概要设计.md"; do
    [ -f "$f" ] && printf '  %s → %s\n' "$(basename "$f")" "$(newest "$f")"
  done
  for f in "$NOTES/Docs/产品能力规划说明书.md" "$NOTES/Docs/需求规范书.md" "$NOTES/Docs/概要设计.md"; do
    [ -f "$f" ] && printf '  %s（Notes）→ %s\n' "$(basename "$f")" "$(newest "$f")"
  done
  echo
  echo "口径：三书继续出（Linux 需求与契约由家族侧维护）；Linux 端由本包使用方实现；"
  echo "      契约层（概要设计无 [独占:*] 标记的节）不可改；Retro 与 Linux 无关。"
} > "$OUT/快照信息.txt"

( cd "$ROOT/dist" && zip -qr "$(basename "$ZIP")" "$(basename "$OUT")" )
echo "✅ 已生成：$ZIP"
( cd "$OUT" && find . -type f | sort | sed 's|^\./|   |' )
du -h "$ZIP" | awk '{print "   包大小：" $1}'
