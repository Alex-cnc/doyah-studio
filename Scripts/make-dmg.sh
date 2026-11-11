#!/usr/bin/env bash
# 打发布 dmg（beta 通道）。
#
# 用法：
#   bash Scripts/make-dmg.sh                     # 用 ~/Applications 里已装的包
#   bash Scripts/make-dmg.sh <App.app>           # 指定 .app
#
# 产物：dist/DoyahStudio-<label>-<sha8>.dmg
#
# 说明（重要）：
# shared-surface：2026-11-10 红#6 收口 —— 两侧共用出包脚本；L85 裸写 `$KEEP_APP（` 在 bash 3.2 会当变量名吞掉 ⇒ 改 `${KEEP_APP}`
#   本脚本**不签名、不公证**。自家/团队内部安装没问题；发给外部用户时 macOS
#   Gatekeeper 会提示「来自身份不明的开发者」，需要右键 →「打开」，或执行
#   `xattr -dr com.apple.quarantine "/Applications/Doyah Studio.app"`。
#   要「双击即开」必须用 Developer ID 签名 + notarytool 公证（需 Apple 开发者账号）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$HOME/Applications/DoyahStudio-beta1.0.app}"
[ -d "$APP" ] || { echo "✗ 找不到 .app：$APP"; exit 2; }

PLIST="$APP/Contents/Info.plist"
LABEL="$(/usr/libexec/PlistBuddy -c 'Print :DoyahReleaseLabel' "$PLIST" 2>/dev/null || echo unknown)"
SHORTVER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null || echo 0)"
BIN="$APP/Contents/MacOS/DoyahStudio"
SHA8="$(shasum -a 256 "$BIN" | cut -c1-8)"

NAME="DoyahStudio-${LABEL}"
STAGE="$(mktemp -d)"
DMG="$ROOT/dist/${NAME}-${SHA8}.dmg"

cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

echo "== 打 dmg =="
echo "  源包   : $APP"
echo "  版本   : $LABEL / $SHORTVER"
echo "  二进制 : $SHA8"
echo "  产物   : $DMG"

# 舞台：.app + /Applications 软链（拖拽安装的标准布局）
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -quiet -volname "Doyah Studio ${LABEL}" \
  -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"

# 自检：真挂载一次，确认 .app 与软链都在
MP="$(mktemp -d)"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MP" "$DMG"
ok=1
[ -d "$MP/$(basename "$APP")" ] || { echo "✗ 挂载后看不到 .app"; ok=0; }
[ -L "$MP/Applications" ] || { echo "✗ 挂载后看不到 /Applications 软链"; ok=0; }
HAS_BIN=$([ -x "$MP/$(basename "$APP")/Contents/MacOS/DoyahStudio" ] && echo yes || echo no)
hdiutil detach -quiet "$MP"
rmdir "$MP" 2>/dev/null || true

SIZE="$(du -h "$DMG" | awk '{print $1}')"
DSHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo
echo "== 自检 =="
echo "  挂载后可执行 : $HAS_BIN"
echo "  dmg 大小     : $SIZE"
echo "  dmg sha256   : $DSHA"
if [ "$ok" = 1 ] && [ "$HAS_BIN" = yes ]; then
  echo "  ✅ 通过"

else
  echo "  ❌ 失败（挂载内容不完整）"
  exit 3
fi

# ---- 保留策略（主人 2026-11-08 令：「出一个新版旧版就可以删除了」）----
# 打成功之后，dist/ 里只留这一版：旧 dmg 与旧 .app 全部删除。
# 为什么放在打成功之后：中断/失败时不能把上一版也删掉，否则手上一个可装包都不剩。
KEEP_APP="$(basename "$APP")"
for d in "$ROOT"/dist/*.dmg; do
  [ -e "$d" ] || continue
  [ "$(basename "$d")" = "$(basename "$DMG")" ] || { rm -f "$d"; echo "  清掉旧 dmg: $(basename "$d")"; }
done
for a in "$ROOT"/dist/*.app; do
  [ -e "$a" ] || continue
  [ "$(basename "$a")" = "$KEEP_APP" ] || { rm -rf "$a"; echo "  清掉旧包: $(basename "$a")"; }
done
echo "  保留策略 : dist/ 只留 $(basename "$DMG") + ${KEEP_APP}（旧版已删）"
echo
echo "未签名/未公证：外部用户首次打开需右键 →「打开」，或"
echo "  xattr -dr com.apple.quarantine \"/Applications/$(basename "$APP" .app).app\""
