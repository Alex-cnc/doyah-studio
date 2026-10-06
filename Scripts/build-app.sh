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
# 默认出**非沙箱**包（`platform/macos/App/DoyahStudio-unsandboxed.entitlements`）—— 这是交付口径
# （`Docs/发布计划.md` §1：交付物 = 非沙箱 ad-hoc 包）。沙箱下挡着三件事：终端作业控制
# （⌃C）/ 导入导出起 `pg_dump`·`pg_restore` / SSH 隧道起 `ssh`（SRS R-18 路线③）。
# 沙箱改为**显式开关**（两个 entitlements 文件都留在仓里）：
#   · 上架那天切回 —— **Mac App Store 强制沙箱**，此时 `DOYAH_SANDBOX=1` 即得；
#   · 旧的 `DOYAH_NO_SANDBOX=1` 仍然认（= 今天默认的那一面），只是不再有开关作用。
#
# 产物：dist/DoyahStudio-<发布标签>.app（**发布标签**在下面「发布标签（唯一出处）」一节里定义）
#   · 交付 / 复测**一律用带版本号的那份**；`dist/DoyahStudio.app` 只是指向最新一份的**软链**（方便入口，
#     不作身份来源 —— 身份 = 带版本号的实物自身，派活单 `T-20261002-028`）。
#   · 交付回执：脚本末尾固定打印「产物名 / 构建时间 / sha256 前 8 位 / 本版包含哪些修复」。
#
# 说明：ad-hoc 签名 + entitlements 足以在本机运行（网络客户端 + 默认不带 App Sandbox）。
# 如果要分发或使用钥匙串的持久授权，请换用自己的开发者证书签名。
#
# **签名身份（Q53，2026-09-30）**：ad-hoc 没有稳定身份 ⇒ **每次重打包都换指纹** ⇒
# macOS「本地网络」授权对不上新包（症状：应用连不上 217 的库，终端 `psql` 却正常）。
# 有了稳定身份，授权只授一次，之后重打包不再掉。用法：
#   ./Scripts/make-signing-identity.sh                    # 一次性：建自签名身份（要输一次钥匙串密码）
#   DOYAH_CODESIGN_IDENTITY="Developer ID Application: …" ./Scripts/build-app.sh   # 用别的身份
# 找不到身份时**回退 ad-hoc**（构建不因此中断），并在终端写明后果。

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
# 源码根（SwiftPM 包根）—— 目录统一 platform/<平台>/ 之后不再等于仓根；跑 swift 一律显式给 --package-path。
PACKAGE_ROOT="${ROOT}/platform/macos"
CONFIGURATION="${1:-debug}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SWIFT="${DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
SCRATCH="${ROOT}/.build"
SCRATCH_X86="${ROOT}/.build-x86"
CACHE="${ROOT}/.build-cache"

# ── 发布标签（**唯一出处**）──────────────────────────────────────────────────────
# 产物名（`dist/DoyahStudio-<发布标签>.app`）与 Info.plist 的 `DoyahReleaseLabel`**都从这一个值派生**，
# 不许手抄第二份（派活单 `T-20261002-028`；判据 = `Scripts/check-release-version.py`，闭环第 18 项）。
# 口径 = **`<里程碑>.<子号>`**（每个里程碑从 `.0` 起，里程碑内小改 +1）—— 出处 `Docs/发布计划.md` §5 附注。
# 当前 **Alpha 2 = Workspace** ⇒ `alpha2.0`。
RELEASE_LABEL="alpha2.0"

APP="${ROOT}/dist/DoyahStudio-${RELEASE_LABEL}.app"
LATEST_LINK="${ROOT}/dist/DoyahStudio.app"
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
    --package-path "${PACKAGE_ROOT}" \
    --cache-path "${CACHE}" \
    --scratch-path "${scratch}" \
    --manifest-cache local \
    ${arch_args[@]+"${arch_args[@]}"} \
    -Xswiftc -disable-sandbox >&2
  local bin_dir
  bin_dir="$("${SWIFT}" build \
    --configuration "${CONFIGURATION}" \
    --disable-sandbox \
    --package-path "${PACKAGE_ROOT}" \
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

cat > "${APP}/Contents/Info.plist" <<PLIST
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
    <key>DoyahReleaseLabel</key>
    <string>${RELEASE_LABEL}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# 应用图标（法斗 Doyah）：platform/macos/App/Resources/AppIcon.icns。
# 用 sips/iconutil 校验过含全部 10 个尺寸；缺了它 Dock 与访达里就是白纸图标。
ICON="${ROOT}/platform/macos/App/Resources/AppIcon.icns"
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
  ENTITLEMENTS="${ROOT}/platform/macos/App/DoyahStudio.entitlements"
  echo "==> 本次为**沙箱**构建（上架那天才用：终端 ⌃C / pg_dump·pg_restore / ssh 三件不可用）"
else
  ENTITLEMENTS="${ROOT}/platform/macos/App/DoyahStudio-unsandboxed.entitlements"
  echo "==> 本次为**非沙箱**构建（默认 · 交付口径）"
  if [ "${DOYAH_NO_SANDBOX:-0}" = "1" ]; then
    echo "    注意：DOYAH_NO_SANDBOX 已废弃 —— 不带任何开关时默认就是非沙箱，这一条不再需要"
  fi
fi

# Q53：优先用稳定身份签名。有身份 ⇒ 指纹稳定 ⇒ 本地网络授权不会随重打包失效；
# 没有 ⇒ 回退 ad-hoc（与改动前行为一致），只在终端说明后果，不让构建失败。
#
# **不用 `security find-identity` 判存在性** —— 它只列「被信任的」身份，自签名证书
# 未信任时实测恒报 `0 valid identities found`，会把装好的身份误判成没有。
# 判据改成**真签一次**：签得成就算有，签不成再回退 ad-hoc（失败信息原样打出来）。
IDENTITY="${DOYAH_CODESIGN_IDENTITY:-DoyahStudio Local Dev}"
SIGN_LOG="$(mktemp)"
if codesign --force --sign "${IDENTITY}" \
  --entitlements "${ENTITLEMENTS}" --timestamp=none "${APP}" >"${SIGN_LOG}" 2>&1; then
  echo "==> 签名：${IDENTITY}（指纹稳定 ⇒「本地网络」授权不会随重打包失效）"
else
  echo "==> 身份「${IDENTITY}」用不了 ⇒ 回退 ad-hoc"
  sed 's/^/    /' "${SIGN_LOG}" | head -3
  echo "    重打包会换指纹，macOS「本地网络」授权可能对不上新包（应用连不上 217、终端却正常）。"
  echo "    先跑一次：./Scripts/make-signing-identity.sh"
  codesign --force --sign - \
    --entitlements "${ENTITLEMENTS}" --timestamp=none "${APP}" 2>&1 | tail -3
fi
rm -f "${SIGN_LOG}"
echo "    结果：$(codesign -dv "${APP}" 2>&1 | grep -E 'Signature=|Identifier=' | tr '\n' ' ')"

# ---- 别名：不带版本号的 `dist/DoyahStudio.app` 只作**方便入口**（派活单 `T-20261002-028`）----
# 身份 = **带版本号的实物**（`DoyahStudio-${RELEASE_LABEL}.app` 自身）；别名只是一个软链，
# 方便工具与习惯路径（`Scripts/check-menu-language.py` 等）继续能用。
# 历史上那个**真目录**（不带版本号）**不删** —— 挪进 `dist/历史/` 留档（交付面文档写明以带版本号的实物为准）。
if [ -e "${LATEST_LINK}" ] && [ ! -L "${LATEST_LINK}" ]; then
  mkdir -p "${ROOT}/dist/历史"
  LEGACY_NAME="DoyahStudio-遗留-$(date +%Y%m%dT%H%M%S).app"
  echo "==> ${LATEST_LINK} 是旧的真目录（不带版本号）⇒ 挪到 dist/历史/${LEGACY_NAME} 留档"
  mv "${LATEST_LINK}" "${ROOT}/dist/历史/${LEGACY_NAME}"
fi
ln -sfn "$(basename "${APP}")" "${LATEST_LINK}"
echo "==> 别名：dist/DoyahStudio.app -> $(readlink "${LATEST_LINK}")（身份以带版本号的实物为准）"

# ---- 交付回执（固定四项：产物名 / 构建时间 / sha256 前 8 位 / 本版包含哪些修复）----
# 人类主人据此回答「我手上这份是不是最新的」。**历史包只增不删**：每个发布标签一个独立目录，
# 重建只覆盖**同名**的那一个 ⇒ 保留最近 ≥3 个历史包是结构保证，不靠额外的清理步骤。
BIN_FILE="${APP}/Contents/MacOS/DoyahStudio"
NOTES_FILE="${ROOT}/dist/发布说明-${RELEASE_LABEL}.md"
echo ""
echo "==== 交付回执 ===="
echo "产物名：$(basename "${APP}")"
echo "构建时间：$(date +%Y-%m-%dT%H:%M:%S%z)（UTC $(date -u +%Y-%m-%dT%H:%M:%SZ)）"
echo "sha256（前 8 位）：$(shasum -a 256 "${BIN_FILE}" | cut -c1-8)（二进制 ${BIN_FILE##*/} · $(stat -f %z "${BIN_FILE}") 字节）"
if [ -f "${NOTES_FILE}" ]; then
  # 第一行**自带**前缀也认（剥掉一个，免得打印成「本版包含：本版包含：…」）
  NOTES_LINE="$(head -1 "${NOTES_FILE}")"
  NOTES_LINE="${NOTES_LINE#本版包含：}"
  echo "本版包含：${NOTES_LINE}"
else
  echo "本版包含：（未登记 —— 在 dist/发布说明-${RELEASE_LABEL}.md 的第一行写一句，或从交付面文档取）"
fi
echo "目录里的历史包：$(ls -d "${ROOT}"/dist/DoyahStudio-*.app 2>/dev/null | wc -l | tr -d ' ') 个（含本次）"
echo "=================="
echo ""
echo "完成：${APP}"
echo "运行：open \"${APP}\""
