#!/bin/bash
set -euo pipefail

# App Store 式「展示图」（Demo 图）的**唯一渲染入口** —— T-20261001-031 ②（人类主人任务）。
#
# 为什么另起一个入口、不去改 `Scripts/render-design-mock.sh`：
#   样张链路那条判据（`Scripts/check-design-mock-tokens.py`）钉住「样张与产品同源」——
#   脚本里不许有色值字面量、必须编译真令牌。展示图要加标题 / 卖点 / 圆角 / 辉光这些
#   **产品里没有的像素**，混进同一条链路会破坏那条判据。**营销物料与工程证据应分开。**
#
# 但「分开」只分**像素**，不分**色源**：本入口同样把 `platform/macos/Core/DesignTokens.swift` /
# `platform/macos/Core/DesignTheme.swift` 一起 `swiftc` 编译（展示图的底 / 字 / 强调色全部取星空紫值表），
# 而产品窗口那一块**直接贴 `render-design-mock.sh` 刚产出的真样张**。
# ⇒ 展示图里不可能出现产品里没有的颜色，也不会画着旧配色。
#
# 用法：./Scripts/render-store-shot.sh [输出目录]      # 默认 Docs/design/store

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
OUT="${1:-${ROOT}/Docs/design/store}"

mkdir -p "${OUT}"
# 样张先渲染到临时目录（**不进** Docs/design/store：那一份只放封面图，17 张历史样张不入库）
TMP="$(mktemp -d "${ROOT}/.build/store-shot-samples-XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT

echo "① 先渲染真样张（展示图贴的就是它）：${TMP}"
SAMPLE_LOG="${TMP}/samples.log"
if "${ROOT}/Scripts/render-design-mock.sh" "${TMP}" > "${SAMPLE_LOG}" 2>&1; then
  echo "   上游样张自检：$(tail -1 "${SAMPLE_LOG}")"
else
  # 上游红不红**不影响本件的结论**（两件分开），但必须**如实转述**、不许吞掉
  echo "   ⚠️ 上游样张自检未过（本件的自检另算，见末尾）：$(tail -1 "${SAMPLE_LOG}")"
fi

# swiftc 只在文件名叫 main.swift 时才允许顶层代码 ⇒ 拷一份改名，不动仓库里的源
BUILD="${ROOT}/.build/store-shot"
mkdir -p "${BUILD}"
cp "${ROOT}/Scripts/render-store-shot.swift" "${BUILD}/main.swift"

echo "② 编译展示图渲染器（与 Core 令牌一起编：营销物料也不许自己编配色）"
xcrun swiftc -O -o "${BUILD}/store-shot" \
  "${BUILD}/main.swift" \
  "${ROOT}/platform/macos/Core/DesignTokens.swift" \
  "${ROOT}/platform/macos/Core/DesignTheme.swift" \
  "${ROOT}/platform/macos/Core/ColorContrast.swift" \
  "${ROOT}/platform/macos/Core/AccentTheme.swift" \
  "${ROOT}/platform/macos/Core/Localization.swift"

echo "③ 渲染深 / 浅各一张到 ${OUT}"
"${BUILD}/store-shot" "${TMP}/样张-深色-星空紫.png" "${TMP}/样张-浅色-星空紫.png" "${OUT}"
