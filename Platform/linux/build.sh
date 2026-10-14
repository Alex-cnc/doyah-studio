#!/usr/bin/env bash
# Linux 端构建入口 —— Doyah Studio 全量 PC 端第三端（归 babyhippo）
#
# 派单：T-20261014-016（人类主人 2026-10-14 令「Doyah Studio 全量 PC 端还要补一个 Linux 平台，小河马负责的」）
# 平台设计层：Docs/概要设计.md §8.6 契约 → Linux 实现 [独占:linux]
#
# 用法：
#   Platform/linux/build.sh --deps   # 依赖探测（只读；缺项逐条点名）
#   Platform/linux/build.sh          # 构建 + 打包（.deb / .AppImage），收尾打印交付物身份四项
#
# 退出码：
#   0 = 完成
#   1 = 依赖缺失（--deps 的判定）
#   2 = 非 Linux 宿主机（如实拒绝 —— 本入口不在别处假装能构建）
#   3 = 应用骨架未落地（src-tauri/ 不在盘上；属「骨架落地片」，不是本脚本的故障）
#   4 = 同源前端缺失（同源面 Platform/windows/App 不在盘上 ⇒ 前端同源前提不成立）
#
# **前端同源**（§8.6.1 前端复用边界）：本端**不另存一份前端** —— 界面 = Windows 侧那一套
#   `Platform/windows/App/`（`src-tauri/tauri.conf.json` 的 `frontendDist` / `devUrl` 指过去）。
#   装配 = 在同源目录里装依赖（**npm**：同源面有 `package-lock.json`，这是实体前端的包管理器；
#   设计层 §8.6.1 原写的 `pnpm` 与实体不符 ⇒ 骨架片按实体前端收口为 npm 并登记，见 README）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$HERE/src-tauri"
FRONT_DIR="$HERE/../windows/App"

say() { printf '%s\n' "$*"; }

# ---------- 依赖探测 ----------
DEPS_MISSING=0
probe_cmd() { # probe_cmd <命令> <说明>
  if command -v "$1" >/dev/null 2>&1; then
    printf '  ok   %-14s %s\n' "$1" "$2"
  else
    printf '  MISS %-14s %s\n' "$1" "$2"
    DEPS_MISSING=$((DEPS_MISSING + 1))
  fi
}
probe_pc() { # probe_pc <pkg-config 模块> <说明>
  if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists "$1" 2>/dev/null; then
    printf '  ok   %-14s %s\n' "$1" "$2"
  else
    printf '  MISS %-14s %s\n' "$1" "$2"
    DEPS_MISSING=$((DEPS_MISSING + 1))
  fi
}

deps_report() {
  say "== Linux 端依赖探测 =="
  say "宿主：$(uname -s) $(uname -m)"
  probe_cmd cargo "Rust 工具链（Tauri 2 需 Rust >= 1.77）"
  probe_cmd node  "Node >= 20（前端）"
  probe_cmd npm   "npm（同源前端的包管理器 —— 同源面里是 package-lock.json）"
  probe_pc webkit2gtk-4.1 "系统 WebView（Tauri Linux 承载面）"
  probe_pc gtk+-3.0       "GTK3（Tauri Linux 前置）"
  probe_pc libayatana-appindicator3-0.1 "托盘指示器（可选；缺则不打托盘）"
  if [ "$DEPS_MISSING" -eq 0 ]; then
    say "== 依赖齐 =="
    return 0
  fi
  say "== 缺 $DEPS_MISSING 项；Debian / Ubuntu 参考：sudo apt install libwebkit2gtk-4.1-dev libgtk-3-dev libayatana-appindicator3-dev librsvg2-dev =="
  return 1
}

build_and_package() {
  if [ "$(uname -s)" != "Linux" ]; then
    say "== 本机不是 Linux 宿主（$(uname -s)）⇒ 如实拒绝构建，不当绿 =="
    say "   本入口只收 Linux 宿主；非 Linux 上请用对应端的入口（macOS: Scripts/build-app.sh / Windows: Platform/windows/Tools/verify-all.ps1）。"
    return 2
  fi
  if [ ! -d "$APP_DIR" ]; then
    say "== 应用骨架未落地：$APP_DIR 不在盘上 =="
    say "   属「骨架落地片」（应用工程 + 前端装配），落地后本命令直接可跑；见 platform/linux/README.md。"
    return 3
  fi
  if [ ! -f "$FRONT_DIR/package.json" ]; then
    say "== 同源前端缺失：$FRONT_DIR/package.json 不在盘上 =="
    say "   本端前端**不另存一份**（§8.6.1）：界面 = Windows 侧 App/ ⇒ 同源面不在盘上就无法装配。"
    return 4
  fi
  if [ ! -d "$FRONT_DIR/node_modules" ]; then
    say "== 同源前端依赖未装 ⇒ npm ci（workdir=$FRONT_DIR）=="
    ( cd "$FRONT_DIR" && npm ci )
  else
    say "== 同源前端依赖已在盘上（$FRONT_DIR/node_modules）⇒ 跳过 npm ci =="
  fi
  say "== 前端构建由 tauri 的 beforeBuildCommand 在同源目录里跑（见 src-tauri/tauri.conf.json）=="
  ( cd "$APP_DIR" && cargo tauri build )
  local out="$APP_DIR/target/release/bundle"
  say "== 交付物身份四项（目录 / 标签 / sha256 / 构建时刻）=="
  local f
  for f in "$out"/deb/*.deb "$out"/appimage/*.AppImage; do
    [ -f "$f" ] || continue
    printf '  目录=%s\n  标签=%s\n  sha256=%s\n  构建时刻=%s\n' \
      "$(dirname "$f")" "$(basename "$f")" "$(sha256sum "$f" | cut -d' ' -f1)" "$(date -Iseconds)"
  done
  say "== 本端判据（骨架 / 领域层边界 / 前端同源）：python3 Platform/linux/Tools/check-linux-skeleton.py =="
  return 0
}

case "${1:-}" in
  -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
  --deps) deps_report; exit $? ;;
  "") deps_report || say "（依赖缺项不中止构建尝试；构建阶段会如实报错）" ; build_and_package; exit $? ;;
  *) say "未知参数：$1（用 --deps 或直接跑）"; exit 4 ;;
esac
