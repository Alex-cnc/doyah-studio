#!/bin/bash
set -euo pipefail

# 外观样张的唯一渲染入口（队列 L-79 ㈡）。
#
# 为什么要有这个入口：`Scripts/design-mock.swift` 原先**自带一份调色板**，于是方案 D 换值之后
# 样张与产品不再同源（拿它出的图去逐屏复查，看的是另一套配色）。现在样张**编译期接真令牌**：
# 本入口把 design-mock.swift 当 `main.swift`，与 `Core/DesignTokens.swift`
# （+ `AccentTheme.swift` / `ColorContrast.swift` / `Localization.swift`）一起 swiftc 编译再运行。
#
#   · 令牌换值 → 样张自动跟着换（不需要改渲染脚本）；
#   · `Scripts/check-design-mock-tokens.py`（闭环第 6 项）钉住这条接线：渲染脚本里不许有色值字面量、
#     本入口必须真的把 `Core/DesignTokens.swift` **与 `Core/DesignTheme.swift`** 编进来、
#     深色样张必须量得出方案 D 的蓝调。
#
# 2026-09-29（L-80 ㈠）：值表按**主题**分组后落到 `Core/DesignTheme.swift`（角色语义仍在
# `Core/DesignTokens.swift`）⇒ 两份都要编进来，缺一份就是"样张回到自带调色板"。
#
# 用法：./Scripts/render-design-mock.sh [输出目录]      # 默认 Docs/design
#       ./Scripts/render-design-mock.sh /tmp/out       # 自检 / 门禁用临时目录

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
OUT="${1:-${ROOT}/Docs/design}"

BUILD="${ROOT}/.build/design-mock"
mkdir -p "${BUILD}"
# swiftc 只在文件名叫 main.swift 时才允许顶层代码 ⇒ 拷一份改名，不动仓库里的源。
cp "${ROOT}/Scripts/design-mock.swift" "${BUILD}/main.swift"

xcrun swiftc -O -o "${BUILD}/design-mock" \
  "${BUILD}/main.swift" \
  "${ROOT}/Core/DesignTokens.swift" \
  "${ROOT}/Core/DesignTheme.swift" \
  "${ROOT}/Core/ColorContrast.swift" \
  "${ROOT}/Core/AccentTheme.swift" \
  "${ROOT}/Core/Localization.swift"

"${BUILD}/design-mock" "${OUT}"
