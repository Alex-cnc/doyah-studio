#!/bin/bash
set -euo pipefail

# 不依赖 Xcode GUI：用 SwiftPM 编译 App 源码，然后组装成 .app 包并做 ad-hoc 签名。
#
#   ./Scripts/build-app.sh            # Debug（默认 **非沙箱**）
#   ./Scripts/build-app.sh release    # Release
#
#   DOYAH_ARCH=x86_64 ./Scripts/build-app.sh    # 单架构 Intel
#   DOYAH_ARCH=universal ./Scripts/build-app.sh # 通用二进制（arm64 + x86_64）
#
#   DOYAH_SANDBOX=1 ./Scripts/build-app.sh      # 带 App 沙箱（**上架那一天才用**）
#
# 为什么需要架构选项（NFR-COMP-02）：默认产物是**单架构 arm64**，
# 实测 `lipo -info` 为 `Non-fat file … arm64` —— 在 Intel 机上**根本起不来**。
# 需求要求"支持 Apple Silicon 与 Intel"，所以构建侧必须能产出 x86_64 / universal。
# Intel 实机与 Rosetta 的启动验证仍需真机（构建通过 ≠ 真机可跑）。
#
# **沙箱口径（2026-09-29 需求提出者拍板「改非沙箱，先验证功能」）**：
# 默认出**非沙箱**包（`App/DoyahStudio-unsandboxed.entitlements`）—— 这是交付口径
# （`Docs/发布计划.md` §1：交付物 = 非沙箱 ad-hoc 包）。沙箱下挡着三件事：终端作业控制
# （⌃C）/ 导入导出起 `pg_dump`·`pg_restore` / SSH 隧道起 `ssh`（SRS R-18 路线③）。
# 沙箱改为**显式开关**（两个 entitlements 文件都留在仓里）：
#   · 上架那天切回 —— **Mac App Store 强制沙箱**，此时 `DOYAH_SANDBOX=1` 即得；
#   · 旧的 `DOYAH_NO_SANDBOX=1` 仍然认（= 今天默认的那一面），只是不再有开关作用。
#
# 产物：dist/DoyahStudio.app
#
# 说明：ad-hoc 签名 + entitlements 足以在本机运行（网络客户端 + 默认不带 App Sandbox）。
# 如果要分发或使用钥匙串的持久授权，请换用自己的开发者证书签名。

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
CONFIGURATION="${1:-debug}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SWIFT="${DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
SCRATCH="${ROOT}/.build"
SCRATCH_X86="${ROOT}/.build-x86"
CACHE="${ROOT}/.build-cache"
APP="${ROOT}/dist/DoyahStudio.app"
DOYAH_ARCH="${DOYAH_ARCH:-}"

export DEVELOPER_DIR
export CLANG_MODULE_CACHE_PATH="${SCRATCH}/clang-module-cache"
export SWIFT_MODULE_CACHE_PATH="${SCRATCH}/swift-module-cache"
mkdir -p "${SCRATCH}" "${CACHE}" "${CLANG_MODULE_CACHE_PATH}" "${SWIFT_MODULE_CACHE_PATH}"

# 独立 scratch 需要自己那份依赖检出。沙箱里没有网络，让 SwiftPM 现拉会**卡死**
# （实测：新 scratch 里 checkouts 一直是空的）。所以从主 scratch 复制一份检出。
seed_scratch() {
  local scratch="$1"
  if [ -d "${scratch}/checkouts" ] && [ -n "$(ls -A "${scratch}/checkouts" 2>/dev/null)" ]; then
    return
  fi
  if [ -d "${SCRATCH}/checkouts" ]; then
    mkdir -p "${scratch}"
    cp -R "${SCRATCH}/checkouts" "${scratch}/" 2>/dev/null || true
    cp -R "${SCRATCH}/repositories" "${scratch}/" 2>/dev/null || true
  fi
}

# 编译并回显可执行文件路径。`$2` 为空表示本机原生架构（保持历史行为）。
#
# 注意 `${arch_args[@]+…}` 这个写法：macOS 自带的是 bash 3.2，在 `set -u` 下
# 展开**空数组**会报 `unbound variable` —— 原生架构那条路径正是空数组（踩过一次）。
build_product() {
  local scratch="$1" arch="$2"
  seed_scratch "${scratch}"
  local arch_args=()
  if [ -n "${arch}" ]; then arch_args=(--arch "${arch}"); fi
  echo "==> 编译 DoyahStudioApp (${CONFIGURATION}${arch:+, ${arch}})" >&2
  "${SWIFT}" build \
    --product DoyahStudioApp \
    --configuration "${CONFIGURATION}" \
    --disable-sandbox \
    --package-path "${ROOT}" \
    --cache-path "${CACHE}" \
    --scratch-path "${scratch}" \
    --manifest-cache local \
    ${arch_args[@]+"${arch_args[@]}"} \
    -Xswiftc -disable-sandbox >&2
  local bin_dir
  bin_dir="$("${SWIFT}" build \
    --configuration "${CONFIGURATION}" \
    --disable-sandbox \
    --package-path "${ROOT}" \
    --cache-path "${CACHE}" \
    --scratch-path "${scratch}" \
    --manifest-cache local \
    ${arch_args[@]+"${arch_args[@]}"} \
    --show-bin-path)"
  echo "${bin_dir}/DoyahStudioApp"
}

BIN=""
BIN_X86=""
case "${DOYAH_ARCH}" in
  ""|"$(uname -m)")
    BIN="$(build_product "${SCRATCH}" "")"
    ;;
  arm64|x86_64)
    if [ "${DOYAH_ARCH}" = "x86_64" ]; then
      BIN="$(build_product "${SCRATCH_X86}" "x86_64")"
    else
      BIN="$(build_product "${SCRATCH}" "arm64")"
    fi
    ;;
  universal)
    BIN="$(build_product "${SCRATCH}" "arm64")"
    BIN_X86="$(build_product "${SCRATCH_X86}" "x86_64")"
    ;;
  *)
    echo "未知 DOYAH_ARCH：${DOYAH_ARCH}（可用：arm64 / x86_64 / universal）"
    exit 64
    ;;
esac

if [ ! -x "${BIN}" ]; then
  echo "未找到可执行文件：${BIN}"
  exit 1
fi

echo "==> 组装 ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
if [ -n "${BIN_X86}" ]; then
  echo "==> lipo 合成通用二进制（arm64 + x86_64）"
  lipo -create -output "${APP}/Contents/MacOS/DoyahStudio" "${BIN}" "${BIN_X86}"
else
  cp "${BIN}" "${APP}/Contents/MacOS/DoyahStudio"
fi
echo "==> 架构：$(lipo -info "${APP}/Contents/MacOS/DoyahStudio" 2>&1 | sed 's/^.*: //')"

cat > "${APP}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh-Hans</string>
    </array>
    <key>CFBundleExecutable</key>
    <string>DoyahStudio</string>
    <key>CFBundleIdentifier</key>
    <string>studio.doyah.DoyahStudio</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleName</key>
    <string>Doyah Studio</string>
    <key>CFBundleDisplayName</key>
    <string>Doyah Studio</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# 应用图标（法斗 Doyah）：App/Resources/AppIcon.icns。
# 用 sips/iconutil 校验过含全部 10 个尺寸；缺了它 Dock 与访达里就是白纸图标。
ICON="${ROOT}/App/Resources/AppIcon.icns"
if [ -f "${ICON}" ]; then
  cp "${ICON}" "${APP}/Contents/Resources/AppIcon.icns"
else
  echo "警告：缺少 ${ICON}，应用将没有图标（可用 Scripts/make-app-icon.swift 重新生成）"
fi

# 第三方许可声明随产品分发（审核与合规都要能随包拿到）
echo "==> 附带第三方许可声明"
cp "${ROOT}/THIRD-PARTY-NOTICES.md" "${APP}/Contents/Resources/THIRD-PARTY-NOTICES.md"

# ---- App 沙箱：默认**不带**；带了才是沙箱（上架那一天） ----
# 交付口径 = 非沙箱包（见文件头与 Docs/发布计划.md §1）。沙箱路径**不许删** ——
# 上架那天 `DOYAH_SANDBOX=1` 即可切回，两个 entitlements 文件都在仓里。
if [ "${DOYAH_SANDBOX:-0}" = "1" ]; then
  ENTITLEMENTS="${ROOT}/App/DoyahStudio.entitlements"
  echo "==> 本次为**沙箱**构建（上架那天才用：终端 ⌃C / pg_dump·pg_restore / ssh 三件不可用）"
else
  ENTITLEMENTS="${ROOT}/App/DoyahStudio-unsandboxed.entitlements"
  echo "==> 本次为**非沙箱**构建（默认 · 交付口径）"
  if [ "${DOYAH_NO_SANDBOX:-0}" = "1" ]; then
    echo "    注意：DOYAH_NO_SANDBOX 已废弃 —— 不带任何开关时默认就是非沙箱，这一条不再需要"
  fi
fi

echo "==> ad-hoc 签名"
codesign --force --sign - \
  --entitlements "${ENTITLEMENTS}" \
  --timestamp=none \
  "${APP}" 2>&1 | tail -3

echo ""
echo "完成：${APP}"
echo "运行：open \"${APP}\""
