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
# ── 构建变体：让「日常版」与「开发中的包」同时存在一台机器上 ────────────────────────
#
#   ./Scripts/build-app.sh --no-install                                  # 只出 dist/，不动 ~/Applications
#   ./Scripts/build-app.sh --no-install --label beta1.1-rc1 --variant rc # 出 rc 包（可与装机版同时跑）
#   ./Scripts/build-app.sh --label beta1.1                               # 发正式版（照旧安装）
#
# **为什么 rc 必须有自己的一套身份**（2026-11-06 实测，不是推理）：同一个 `CFBundleIdentifier`
# 的两份 `.app` **根本无法同时运行** —— 装机版在跑时，`open dist/…app` 与 `open -n` 都只是
# 把已有实例调到前台（`ps aux` 里进程数始终为 1）。所以 `--variant rc` 做三件事：
#   ① `CFBundleIdentifier` 追加 `.rc`（系统才认它们是两个 App）；
#   ② 写 `DoyahDataDirectoryName=DoyahStudio-rc`（**数据目录也隔离** —— 否则两版抢同一份
#      `agent.json` / `connections.json` / 审计日志，比覆盖安装更危险：两份进程各写各的）；
#   ③ app 名用 `--label` 那个名字（`dist/DoyahStudio-beta1.1-rc1.app`）。
# rc 包**默认不安装**：它是拿来验具体 bug / 功能的，不进 `~/Applications`（那里只放日常版）。
# 首次启动时 rc 会从日常版目录继承 `agent.json` / `connections.json`（见 Core/DoyahIdentity.swift
# 的 `VariantConfigInheritance`）—— 配置只配一遍，会话与 IM 状态各写各的。
#
# **不带任何参数时行为一字不变**：`beta1.0` / 原包标识 / 原数据目录 / 仍然安装到 `~/Applications`。
#
# 为什么需要架构选项（NFR-ALL-GATE-COMP-005）：默认产物是**单架构 arm64**，
# 实测 `lipo -info` 为 `Non-fat file … arm64` —— 在 Intel 机上**根本起不来**。
# 需求要求"支持 Apple Silicon 与 Intel"，所以构建侧必须能产出 x86_64 / universal。
# Intel 实机与 Rosetta 的启动验证仍需真机（构建通过 ≠ 真机可跑）。
#
# **沙箱口径（2026-09-29 需求提出者拍板「改非沙箱，先验证功能」）**：
# 默认出**非沙箱**包（`App/DoyahStudio-unsandboxed.entitlements`）—— 这是交付口径
# （`Docs/archive/root-20261026/发布计划.md` §1：交付物 = 非沙箱 ad-hoc 包）。沙箱下挡着三件事：终端作业控制
# （⌃C）/ 导入导出起 `pg_dump`·`pg_restore` / SSH 隧道起 `ssh`（SRS R-018 路线③）。
# 沙箱改为**显式开关**（两个 entitlements 文件都留在仓里）：
#   · 上架那天切回 —— **Mac App Store 强制沙箱**，此时 `DOYAH_SANDBOX=1` 即得；
#   · 旧的 `DOYAH_NO_SANDBOX=1` 仍然认（= 今天默认的那一面），只是不再有开关作用。
#
# 产物：dist/DoyahStudio-<发布标签>.app（**发布标签**在下面「发布标签（唯一出处）」一节里定义）
#   · 交付 / 复测**一律用带版本号的那份**；`dist/DoyahStudio.app` 只是指向最新一份的**软链**（方便入口，
#     不作身份来源 —— 身份 = 带版本号的实物自身，派活单 `T-20261002-028`）。
#   · 交付回执：脚本末尾固定打印「产物名 / 目录 / 标签 / 构建时间 / sha256 / 本版包含 / 未含 /
#     验法」+ 一行 `交付: …`（**身份留痕** —— 四项 + 含片/未含/验法，可整行粘进提交信息；
#     基本法第三十五条）。
#
# 说明：ad-hoc 签名 + entitlements 足以在本机运行（网络客户端 + 默认不带 App Sandbox）。
# 如果要分发或使用钥匙串的持久授权，请换用自己的开发者证书签名。
#
# **签名身份（Q53，2026-09-30；★00 2026-10-29 改口径）**：ad-hoc 没有稳定身份 ⇒ **每次重打包都换指纹** ⇒
# macOS「本地网络」授权对不上新包（症状：应用连不上 217 的库，终端 `psql` 却正常），
# 并且钥匙串条目的 ACL 也对不上 ⇒ **每次启动弹「请输入钥匙串密码」**（主人 2026-10-29 当面点出）。
# 有了稳定身份，授权只授一次，之后重打包不再掉。用法：
#   ./Scripts/make-signing-identity.sh                    # 一次性：建自签名身份
#   ./Scripts/make-signing-identity.sh --trust            # 再一次性：让自签根受信任（要管理员密码）
#   DOYAH_CODESIGN_IDENTITY="Developer ID Application: …" ./Scripts/build-app.sh   # 用别的身份
# **找不到身份不再回退 ad-hoc**：直接报错并印修法；确实要接受那个后果才用 `DOYAH_ALLOW_ADHOC=1`。
# 由头：静默回退把「一个治不好的缺陷」伪装成「构建成功」，而症状要等用户下次启动才出现。

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
CONFIGURATION="debug"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SWIFT="${DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
SCRATCH="${ROOT}/.build"
SCRATCH_X86="${ROOT}/.build-x86"
CACHE="${ROOT}/.build-cache"

# ── 参数（2026-11-06：加 `--no-install` / `--label` / `--variant`）──────────────────
# 位置参数仍然只认 `debug` / `release`（历史用法 `./Scripts/build-app.sh release` 不变）；
# **不带参数**时下面三个变量全为空 ⇒ 走原来的那条路，行为与产物路径一字不变。
NO_INSTALL=0
LABEL_OVERRIDE=""
VARIANT=""
usage() {
  cat <<'USAGE'
用法：Scripts/build-app.sh [debug|release] [--no-install] [--label <名字>] [--variant rc]

  --no-install       只出 dist/，**不动** ~/Applications（日常版在用的那份不碰）
  --label <名字>      这一次构建叫什么（进 app 名与 DoyahReleaseLabel），如 beta1.1-rc1
  --variant rc       构建变体：包标识追加 `.rc` + 数据目录改 `DoyahStudio-rc` + app 名用 label
                     （必须同时给 --label；rc 包默认不安装 —— 它不进 ~/Applications）
USAGE
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-install) NO_INSTALL=1; shift ;;
    --label) LABEL_OVERRIDE="${2:-}"; shift 2 ;;
    --label=*) LABEL_OVERRIDE="${1#*=}"; shift ;;
    --variant) VARIANT="${2:-}"; shift 2 ;;
    --variant=*) VARIANT="${1#*=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    debug|release) CONFIGURATION="$1"; shift ;;
    *)
      echo "错误：不认识的参数「$1」" >&2
      usage >&2
      exit 64
      ;;
  esac
done
if [ -z "${LABEL_OVERRIDE}" ] && [ -n "${VARIANT}" ]; then
  echo "错误：--variant ${VARIANT} 必须配 --label（否则会覆盖日常版的同名产物）" >&2
  exit 64
fi

# ── 发布标签（**唯一出处**）──────────────────────────────────────────────────────
# 产物名（`dist/DoyahStudio-<发布标签>.app`）与 Info.plist 的 `DoyahReleaseLabel`**都从这一个值派生**，
# 不许手抄第二份（派活单 `T-20261002-028`；判据 = `Scripts/check-release-version.py`，闭环第 18 项）。
# 口径 = **`<里程碑>.<子号>`**（每个里程碑从 `.0` 起，里程碑内小改 +1）—— 出处 `Docs/archive/root-20261026/发布计划.md` §5 附注。
# 当前 **Beta 1 = 全量功能** ⇒ `beta1.0`（2026-10-21 出包齐套 · 派单 `T-20261021-001`：产物身份与所有 `alpha3.1` 包不同 ⇒ 换里程碑，避免「同标签不同身份」；改前值 = `alpha3.1`）。
RELEASE_LABEL="beta1.0"

# ── 构建戳（**每次构建都不一样**，用来分清新旧）──────────────────────────────────
# 主人 2026-10-30：「这个 beta1.0.app 始终不增长子版本号，我也分不清哪个是新哪个是旧」。
# 发布标签必须稳定（`check-release-version.py` 拿它跟台账比），所以**不动标签**，
# 另存一条随手可读的构建戳：`<提交数>.<sha7> · <时刻>` ⇒ About 页与 Info.plist 都看得到。
# 面向用户的版本号：**从发布标签派生，不许手抄第二份**。
# 主人 2026-10-30：「系统菜单里的关于面板上的版本是 0.3.0，而构建出的 app 却一直是 beta1.0」
# —— 标签是内部里程碑（`beta1.0`），系统「关于」读的是 `CFBundleShortVersionString`，两者必须同源。
# 口径：`beta1.0` → `1.0.0`，`alpha3.1` → `3.1.0`（去掉里程碑前缀，两段补成三段）。
MARKETING_VERSION="$(printf '%s' "${RELEASE_LABEL}" | sed -E 's/^(alpha|beta|rc)//' | awk -F. '{ if (NF>=3) print $1"."$2"."$3; else print $1"."$2".0" }')"
BUILD_COUNT="$(git -C "${ROOT}" rev-list --count HEAD 2>/dev/null || echo 0)"
SHORT_SHA="$(git -C "${ROOT}" rev-parse --short=7 HEAD 2>/dev/null || echo nosha)"
BUILD_STAMP="${BUILD_COUNT}.${SHORT_SHA} · $(date +%m-%d\ %H:%M)"

APP="${ROOT}/dist/DoyahStudio-${RELEASE_LABEL}.app"
LATEST_LINK="${ROOT}/dist/DoyahStudio.app"
DOYAH_ARCH="${DOYAH_ARCH:-}"

# ── 这一次构建的**实际身份**（默认 = 上面那几个派生值，一字不改）────────────────────
# 门禁 `Scripts/check-release-version.py` 钉住三件事，这里刻意都不动：
#   ① `RELEASE_LABEL="…"` 只许**一处**字面量定义（发布标签的唯一定义仍在上面）；
#   ② `MARKETING_VERSION="$(…)"` 那行派生式逐字不动；
#   ③ `APP="${ROOT}/dist/DoyahStudio-${RELEASE_LABEL}.app"` 这行产物名派生式逐字不动。
# 变体构建（`--label` / `--variant`）改写的是**下面这一层的「这一次叫什么」**——
# 也就是「默认值 + 本次覆盖」，而不是给发布标签再开第二处定义。
APPLIED_LABEL="${RELEASE_LABEL}"
APPLIED_MARKETING_VERSION="${MARKETING_VERSION}"
BUNDLE_IDENTIFIER="studio.doyah.DoyahStudio"
VARIANT_KEY=""            # 空 = 日常版（Info.plist **不写** DoyahBuildVariant / DoyahDataDirectoryName）
DATA_DIRECTORY_NAME=""

if [ -n "${LABEL_OVERRIDE}" ]; then
  APPLIED_LABEL="${LABEL_OVERRIDE}"
  # 面向用户的版本号仍从标签派生，但**只取开头的数字段**：
  #   `beta1.0` → `1.0` → `1.0.0`（与上面那一行同结果）；
  #   `beta1.1-rc1` → `1.1` → `1.1.0`（`-rc1` 后缀不进版本号 —— 系统「关于」要的是 `x.y.z`）。
  MV_NUMERIC="$(printf '%s' "${APPLIED_LABEL}" | sed -E 's/^(alpha|beta|rc)//' | grep -oE '^[0-9]+(\.[0-9]+)*' || true)"
  if [ -z "${MV_NUMERIC}" ]; then
    echo "错误：--label「${APPLIED_LABEL}」里取不到版本号（期望形如 beta1.1-rc1 / beta1.1）" >&2
    exit 64
  fi
  APPLIED_MARKETING_VERSION="$(printf '%s' "${MV_NUMERIC}" | awk -F. '{ if (NF>=3) print $1"."$2"."$3; else print $1"."$2".0" }')"
  # 产物名跟着这一次的标签走（`dist/DoyahStudio-<本次标签>.app`），并且**不碰**那条软链别名
  # —— 别名是「当前发布标签那一份」的入口，rc 包不许把它指歪（门禁第 18 项会判）。
  APP="${ROOT}/dist/DoyahStudio-${APPLIED_LABEL}.app"
fi

case "${VARIANT}" in
  "")
    ;;
  rc)
    # 包标识加后缀：同一个 id 的第二份 .app **起不来**（只会把已有实例调到前台），
    # 这一个是「两版同时跑」的唯一开关。
    BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER}.rc"
    VARIANT_KEY="rc"
    DATA_DIRECTORY_NAME="DoyahStudio-rc"
    ;;
  *)
    echo "错误：--variant「${VARIANT}」不认识（目前只支持 rc）" >&2
    exit 64
    ;;
esac

if [ -n "${VARIANT_KEY}" ]; then
  echo "==> 构建变体：${VARIANT_KEY}（包标识 ${BUNDLE_IDENTIFIER} · 数据目录 ${DATA_DIRECTORY_NAME} · 标签 ${APPLIED_LABEL} · **不安装到 ~/Applications**）"
fi

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
  # **失败必须当场停**（2026-10-16 实机踩到）：原先这一步的返回码没被检查，
  # 编译红了脚本照样往下走，把 SCRATCH 里**上一次的旧二进制**装进 .app 并打印「完成」——
  # 于是"发出去的包里没有这处改动"，而脚本 rc=0、看日志也像成功。这比崩溃更坏：
  # 崩溃你会知道，静默出旧包则要靠人肉点验才发现。
  if ! "${SWIFT}" build \
    --product DoyahStudioApp \
    --configuration "${CONFIGURATION}" \
    --disable-sandbox \
    --package-path "${ROOT}" \
    --cache-path "${CACHE}" \
    --scratch-path "${scratch}" \
    --manifest-cache local \
    ${arch_args[@]+"${arch_args[@]}"} \
    -Xswiftc -disable-sandbox >&2
  then
    echo "错误：swift build 失败 —— 不再继续打包（否则会把上一次的旧二进制打成一个看似成功的包）" >&2
    exit 1
  fi
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
  # **release 包要去符号**（人类主人 2026-11-07：「108MB 感觉也没多少功能」）。
  # 实测同一份 release 二进制：71MB → `strip -x` 后 35MB，整包 73MB → ≈37MB。
  # debug 包**不 strip**：留着符号才能看崩溃栈（定位问题时用 debug 包）。
  # 必须在下面的 codesign **之前**做 —— strip 改文件就会让签名失效。
  if [ "${CONFIGURATION}" = "release" ]; then
    BEFORE="$(stat -f%z "${APP}/Contents/MacOS/DoyahStudio")"
    strip -x "${APP}/Contents/MacOS/DoyahStudio" 2>/dev/null || true
    AFTER="$(stat -f%z "${APP}/Contents/MacOS/DoyahStudio")"
    echo "==> 已去符号（release）：$((BEFORE/1024/1024))MB → $((AFTER/1024/1024))MB"
  fi
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
    <string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_COUNT}</string>
    <key>DoyahReleaseLabel</key>
    <string>${RELEASE_LABEL}</string>
    <key>DoyahBuildStamp</key>
    <string>${BUILD_STAMP}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 豆丫科技 · Doyah Tech</string>
</dict>
</plist>
PLIST

# 变体构建：**写盘之后**再把这三样改成本次的身份（默认路径一个字都不动 —— 模板里那两个键
# 就是发布标签的默认值，门禁逐字钉着它们只许一处）。
# 为什么不用 heredoc 变量：`DoyahReleaseLabel` / `CFBundleShortVersionString` 在模板里
# 必须逐字是 `${RELEASE_LABEL}` / `${MARKETING_VERSION}`（`Scripts/check-release-version.py`
# 的 B1/B4 两族判据），而 rc 的标签是「这一次」的覆盖值、不是发布标签的第二处定义。
# **只要这一次的身份与默认值不同就要写**（`--label beta1.0.1` 只换标签、不带 --variant，
# 原来的条件 `[ -n "${VARIANT_KEY}" ]` 会跳过写盘 ⇒ 产物仍是 beta1.0/1.0.0，
# 而下面的自检按期望值判 ⇒ 直接失败。2026-11-06 报「beta1.0.1 打不出来」就是这条）。
if [ -n "${VARIANT_KEY}" ] || [ -n "${LABEL_OVERRIDE}" ]; then
  PLIST_ARGS=(
    -c "Set :DoyahReleaseLabel ${APPLIED_LABEL}"
    -c "Set :CFBundleShortVersionString ${APPLIED_MARKETING_VERSION}"
  )
  if [ -n "${VARIANT_KEY}" ]; then
    PLIST_ARGS+=(
      -c "Set :CFBundleIdentifier ${BUNDLE_IDENTIFIER}"
      -c "Add :DoyahBuildVariant string ${VARIANT_KEY}"
      -c "Add :DoyahDataDirectoryName string ${DATA_DIRECTORY_NAME}"
    )
  fi
  /usr/libexec/PlistBuddy "${PLIST_ARGS[@]}" "${APP}/Contents/Info.plist"
  echo "==> 身份已写入 Info.plist（${APPLIED_LABEL} / ${APPLIED_MARKETING_VERSION}${VARIANT_KEY:+ / ${BUNDLE_IDENTIFIER} · ${DATA_DIRECTORY_NAME}}）"
fi

# 版本身份**写盘后立刻读回来核**（2026-11-03）。
# 为什么在构建脚本里也要判一次：`check-release-version.py` 只能判「模板与台账」——
# 它判不到**这一次构建**真写进了什么；而构建号是 `git rev-list --count HEAD` 的派生值，
# 每次提交都变，台账里根本存不住一个字面量去逐字比。所以「写进包里的三个值 == 这次算出来的三个值」
# 这一步只能在构建那一刻自证；读回不一致就直接失败（不出一个身份不对的包）。
# 2026-11-06：比对基准从「发布标签」换成「**这一次**的标签」（默认路径下两者 **逐字相同**）。
for PAIR in "CFBundleShortVersionString:${APPLIED_MARKETING_VERSION}" \
            "CFBundleVersion:${BUILD_COUNT}" \
            "DoyahReleaseLabel:${APPLIED_LABEL}"; do
  PLIST_KEY="${PAIR%%:*}"
  PLIST_WANT="${PAIR#*:}"
  PLIST_GOT="$(/usr/libexec/PlistBuddy -c "Print :${PLIST_KEY}" "${APP}/Contents/Info.plist" 2>/dev/null || echo '<读不到>')"
  if [ "${PLIST_GOT}" != "${PLIST_WANT}" ]; then
    echo "错误：产物 Info.plist 的 ${PLIST_KEY} 读回 = ${PLIST_GOT}，期望 ${PLIST_WANT}" >&2
    exit 1
  fi
done

# 变体构建再多核两样：包标识与数据目录必须真的进了包（否则两版要么起不来、要么抢同一份数据）。
if [ -n "${VARIANT_KEY}" ]; then
  for PAIR in "CFBundleIdentifier:${BUNDLE_IDENTIFIER}" \
              "DoyahBuildVariant:${VARIANT_KEY}" \
              "DoyahDataDirectoryName:${DATA_DIRECTORY_NAME}"; do
    PLIST_KEY="${PAIR%%:*}"
    PLIST_WANT="${PAIR#*:}"
    PLIST_GOT="$(/usr/libexec/PlistBuddy -c "Print :${PLIST_KEY}" "${APP}/Contents/Info.plist" 2>/dev/null || echo '<读不到>')"
    if [ "${PLIST_GOT}" != "${PLIST_WANT}" ]; then
      echo "错误：变体产物 Info.plist 的 ${PLIST_KEY} 读回 = ${PLIST_GOT}，期望 ${PLIST_WANT}" >&2
      exit 1
    fi
  done
fi

# 应用图标（法斗 Doyah）：App/Resources/AppIcon.icns。
# 用 sips/iconutil 校验过含全部 10 个尺寸；缺了它 Dock 与访达里就是白纸图标。
ICON="${ROOT}/App/Resources/AppIcon.icns"
if [ -f "${ICON}" ]; then
  cp "${ICON}" "${APP}/Contents/Resources/AppIcon.icns"
else
  echo "警告：缺少 ${ICON}，应用将没有图标（可用 Scripts/make-app-icon.swift 重新生成）"
fi

# 壁纸皮肤的两张照片（2026-10-16）：`Core/WallpaperSkin.swift` 的值表按**资源名**取图
# （`NSImage(named: "wallpaper-city-lake")` ⇒ 找的就是包内 `Contents/Resources/<名>.jpg`）。
# **这一格必须点名拷贝**：SwiftPM 侧 `Package.swift` 把 `Resources` 整目录 exclude 掉了
# （注释原话「Resources 由 Scripts/build-app.sh 装进 .app；SwiftPM 不处理 .icns/.png」）——
# 所以"把图放进 App/Resources"**不等于**它会进包。2026-10-16 实测踩过：改了资源名没跟这一格，
# 打出来的包里一张壁纸都没有，而 App 侧有兜底（取不到图就退回主题纯色）**不会崩**，
# 只是"功能静默消失"——正是那种只靠人工点验才看得见、判据全绿也拦不住的漏。
# 因此这里**数一遍**：盘上有几张就必须进包几张；一张都没有 ⇒ 直接报错退出（不许静默出一个没壁纸的包）。
# 灵魂 L0（2026-10-17）：`Core/AgentSoul.swift` 按**文件名**从包内 `Contents/Resources/soul-L0.md` 读；
# 与壁纸同理 —— 放盘上不等于进包（`Resources` 整目录被 SwiftPM exclude），**这里点名拷贝**，缺了直接报错。
SOUL="${ROOT}/App/Resources/soul-L0.md"
if [ ! -f "${SOUL}" ]; then echo "❌ 灵魂文件缺失：${SOUL}（App 会如实报 L0 未载入，但不许就这么出包）" >&2; exit 1; fi
cp "${SOUL}" "${APP}/Contents/Resources/soul-L0.md"
WALLPAPERS=$(ls "${ROOT}"/App/Resources/wallpaper-*.jpg 2>/dev/null || true)
if [ -z "${WALLPAPERS}" ]; then
  echo "错误：${ROOT}/App/Resources 里没有 wallpaper-*.jpg —— 壁纸皮肤会静默失效（值表见 Core/WallpaperSkin.swift）" >&2
  exit 1
fi
echo "==> 附带壁纸（App/Resources/wallpaper-*.jpg ⇒ Contents/Resources/）"
for WALLPAPER in ${WALLPAPERS}; do
  cp "${WALLPAPER}" "${APP}/Contents/Resources/"
  echo "    $(basename "${WALLPAPER}")"
done

# 第三方许可声明随产品分发（审核与合规都要能随包拿到）
echo "==> 附带第三方许可声明"
cp "${ROOT}/THIRD-PARTY-NOTICES.md" "${APP}/Contents/Resources/THIRD-PARTY-NOTICES.md"

# ---- 随包命令行工具（2026-11-07 主人拍板：ripgrep 进包）------------------------------
# `App/Resources/tools/` 里的 `rg`（ripgrep 15.2.0，仅 macOS arm64）是智能体 `search` 工具的
# **首选执行器**：`Core/AgentRipgrep.swift` 按 `Bundle.main.resourceURL/tools/rg` 找它。
# 与壁纸 / 灵魂 L0 同一条坑：SwiftPM 把 `Resources` 整目录 exclude 掉 ⇒ **放盘上不等于进包**，
# 这里点名拷贝。缺了**不报错**（App 会回落到 `WorkspaceSearch` 的 Swift 实现，功能不消失），
# 但必须把「这次没带工具」打印出来 —— 静默少一个工具 = 悄悄退回 1.4 秒一次的慢路径。
TOOLS_SRC="${ROOT}/App/Resources/tools"
if [ -d "${TOOLS_SRC}" ]; then
  echo "==> 随包命令行工具（App/Resources/tools/ ⇒ Contents/Resources/tools/）"
  mkdir -p "${APP}/Contents/Resources/tools"
  cp -R "${TOOLS_SRC}/." "${APP}/Contents/Resources/tools/"
  chmod 755 "${APP}/Contents/Resources/tools/rg" 2>/dev/null || true
  # **嵌套可执行文件必须自己签一次**（ad-hoc，与主二进制同一套口径）：外层 `codesign` 只盖
  # bundle 的封装，不替嵌套的 Mach-O 签；不签的话启动子进程会被 Gatekeeper / 公证判成
  # 「未签名嵌套代码」。签完当场 `codesign -v` 验 —— 验不过就**不出包**（出一个起不来的
  # 工具比没有这个工具更坏：它会以「rg 不可用」的形式静默退回慢路径）。
  for TOOL in "${APP}/Contents/Resources/tools/"*; do
    [ -f "${TOOL}" ] || continue
    file "${TOOL}" | grep -q "Mach-O" || continue
    codesign --force --sign - --timestamp=none "${TOOL}" >/dev/null 2>&1 || {
      echo "❌ 随包工具签名失败：$(basename "${TOOL}")" >&2; exit 1; }
    if ! codesign -v "${TOOL}" >/dev/null 2>&1; then
      echo "❌ 随包工具验签不过：$(basename "${TOOL}")（codesign -v 非 0）" >&2
      exit 1
    fi
    echo "    $(basename "${TOOL}")：$(file -b "${TOOL}" | cut -d, -f1) · $(codesign -dv "${TOOL}" 2>&1 | grep -E '^Signature=' | head -1) · codesign -v OK"
  done
  if [ -x "${APP}/Contents/Resources/tools/rg" ]; then
    echo "    $("${APP}/Contents/Resources/tools/rg" --version | head -1)（search 首选执行器）"
  fi
  # 本仓只随包 arm64 一份：Intel / universal 包里它会 EBADARCH ⇒ 如实提示回落，不静默。
  if [ -n "${BIN_X86}" ] || [ "${DOYAH_ARCH:-}" = "x86_64" ]; then
    echo "    注意：本包是 Intel / 通用包，而 tools/rg 只有 arm64 —— Intel 机上 search 会回落 Swift 实现"
  fi
else
  echo "警告：缺少 ${TOOLS_SRC}（本次包内没有 rg；search 走 Swift 实现，慢 30–50 倍）"
fi

# 插件面随包发（概设 §7 · §8 判据⑤「产物含插件目录与清单」）：清单与资源进
# `Contents/Resources/Plugins/`，**源码（`*.swift`）不进包** —— 与 `project.yml` 里
# 那条资源登记同口径（源码由各自 target 收）。装配器读的就是这个位置：
# `PluginManifestLoader.defaultPluginsDirectory()` = `Bundle.main.url(forResource: "Plugins", …)`
# ⇒ 包内缺它，交付物里 `PluginRegistry` 恒空（而门禁第 10 项只判源码形状，看不见这一格）。
# shared-surface：交付打包面补「插件目录与清单进包」（概设 §8 判据⑤）—— 只加一段拷贝，既有步骤一字不动
PLUGINS_SRC="${ROOT}/Plugins"
if [ -d "${PLUGINS_SRC}" ]; then
  echo "==> 附带插件目录与清单（Plugins/ ⇒ Contents/Resources/Plugins/）"
  cp -R "${PLUGINS_SRC}" "${APP}/Contents/Resources/Plugins"
  find "${APP}/Contents/Resources/Plugins" -name '*.swift' -delete
  find "${APP}/Contents/Resources/Plugins" -type d -empty -delete
  find "${APP}/Contents/Resources/Plugins" -name 'plugin.json' -print | sed 's|^|    |'
else
  echo "警告：缺少 ${PLUGINS_SRC}（本次包内没有插件目录）"
fi

# ---- App 沙箱：默认**不带**；带了才是沙箱（上架那一天） ----
# 交付口径 = 非沙箱包（见文件头与 Docs/archive/root-20261026/发布计划.md §1）。沙箱路径**不许删** ——
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

# ---- 签名身份（★00：主人 2026-10-29「每次启动都要输入密码」）----
#
# 口径（改过，旧的作废）：**身份不存在 / 签不动 ⇒ 报错退出，不再静默回退 ad-hoc**。
# 为什么：ad-hoc 没有证书 ⇒ 每次重打包都换一个「应用」身份 ⇒ 钥匙串条目的 ACL 永远对不上
# ⇒ 每次启动弹「请输入钥匙串密码」。回退不是「构建更宽容」，是把一个治不好的缺陷伪装成构建成功。
# 明确要接受这个后果时才用 `DOYAH_ALLOW_ADHOC=1`（会打一整段警告）。
#
# **判存在性仍然不用 `security find-identity -v`** —— 它只列「被信任的」身份，自签名证书
# 未信任时实测恒报 `0 valid identities found`，会把装好的身份误判成没有。
# 判据是**真签一次**（签一个临时二进制，走的就是后面要走的那条路）。
# 扫码桥（`FR-AGT-LINK-CHAN-003`）：打进包里的 Resources，安装后也能用（不依赖仓库路径）。
if [[ -f "Scripts/qq-qr-bridge.mjs" ]]; then
  cp "Scripts/qq-qr-bridge.mjs" "${APP}/Contents/Resources/qq-qr-bridge.mjs"
fi

# 身份名**不要写死**：机器上可能早有一个（本机现存 `Doyah Local Dev`），
# 名字对不上就会一路掉回 ad-hoc —— 那正是「每装一版 keychain 又弹一次」的根因。
# 取值顺序：环境变量 → 已存在的两个常见名 → 缺省名（没有就由下面的真签试探决定是否 ad-hoc）。
if [ -n "${DOYAH_CODESIGN_IDENTITY:-}" ]; then
  IDENTITY="${DOYAH_CODESIGN_IDENTITY}"
elif security find-certificate -c "Doyah Local Dev" "${HOME}/Library/Keychains/login.keychain-db" >/dev/null 2>&1; then
  IDENTITY="Doyah Local Dev"
else
  IDENTITY="DoyahStudio Local Dev"
fi
SIGN_LOG="$(mktemp)"
PROBE_DIR="$(mktemp -d)"
cp /usr/bin/true "${PROBE_DIR}/signtest"
IDENTITY_USABLE=0
if codesign --force --sign "${IDENTITY}" --timestamp=none "${PROBE_DIR}/signtest" >"${SIGN_LOG}" 2>&1; then
  IDENTITY_USABLE=1
fi
rm -rf "${PROBE_DIR}"

if [ "${IDENTITY_USABLE}" != "1" ]; then
  if [ "${DOYAH_ALLOW_ADHOC:-0}" = "1" ]; then
    echo "⚠ 身份「${IDENTITY}」用不了，但 DOYAH_ALLOW_ADHOC=1 ⇒ 按要求回退 ad-hoc："
    sed 's/^/    /' "${SIGN_LOG}" | head -3
    echo "    后果（接受才该用这个开关）：每次重打包换指纹 ⇒「本地网络」授权对不上、"
    echo "    钥匙串条目的 ACL 也对不上 ⇒ **每次启动都会弹钥匙串密码**。"
    codesign --force --sign - \
      --entitlements "${ENTITLEMENTS}" --timestamp=none "${APP}" 2>&1 | tail -3
    rm -f "${SIGN_LOG}"
  else
    echo "❌ 签名身份「${IDENTITY}」用不了 —— **不再静默回退 ad-hoc**（那会让每次启动都弹钥匙串密码）。"
    sed 's/^/    /' "${SIGN_LOG}" | head -5
    echo "    修法（任选其一）："
    echo "      1) ./Scripts/make-signing-identity.sh        # 建一次身份，再跑一次它印的信任步骤"
    echo "      2) DOYAH_CODESIGN_IDENTITY=\"Developer ID Application: …\" ./Scripts/build-app.sh"
    echo "      3) DOYAH_ALLOW_ADHOC=1 ./Scripts/build-app.sh # 明确接受上面那段后果"
    rm -f "${SIGN_LOG}"
    exit 1
  fi
else
  codesign --force --sign "${IDENTITY}" \
    --entitlements "${ENTITLEMENTS}" --timestamp=none "${APP}" >"${SIGN_LOG}" 2>&1 || {
      echo "❌ 签名失败（身份能签临时文件、签不了这个 .app）："
      sed 's/^/    /' "${SIGN_LOG}" | head -5
      rm -f "${SIGN_LOG}"
      exit 1
    }
  rm -f "${SIGN_LOG}"
  # 受信任与否**单独报**：它不影响指纹稳定（那只取决于证书本身），影响的是
  # 「点过一次『始终允许』能不能记住」与「本地网络」授权 —— 所以是警告，不是构建失败。
  if security find-identity -v -p codesigning 2>/dev/null | grep -qF "${IDENTITY}"; then
    echo "==> 签名：${IDENTITY}（已受信任 · 指纹稳定 ⇒「本地网络」与钥匙串授权都只授一次）"
  else
    echo "==> 签名：${IDENTITY}（**证书未受信任** ⇒ 指纹虽稳定，但「始终允许」可能记不住）"
    echo "    修法（要管理员密码，跑一次即可）："
    echo "      ./Scripts/make-signing-identity.sh --trust"
  fi
fi
echo "    结果：$(codesign -dv "${APP}" 2>&1 | grep -E 'Signature=|Identifier=' | tr '\n' ' ')"
# 随包工具（`Contents/Resources/tools/rg`）在**外层签完之后**再验一次：外层签名把整棵
# `Resources` 封进了 CodeResources，任何一步改动都会让它失配 —— 这一格就是那个读数的出处。
if [ -f "${APP}/Contents/Resources/tools/rg" ]; then
  codesign -v "${APP}/Contents/Resources/tools/rg" && echo "==> 随包工具验签：Contents/Resources/tools/rg OK（ad-hoc）"
fi

# ---- 别名：不带版本号的 `dist/DoyahStudio.app` 只作**方便入口**（派活单 `T-20261002-028`）----
# 身份 = **带版本号的实物**（`DoyahStudio-${RELEASE_LABEL}.app` 自身）；别名只是一个软链，
# 方便工具与习惯路径（`Scripts/check-menu-language.py` 等）继续能用。
# 历史上那个**真目录**（不带版本号）**不删** —— 挪进 `dist/历史/` 留档（交付面文档写明以带版本号的实物为准）。
if [ -n "${VARIANT_KEY}" ]; then
  # 变体包**不许**动别名：别名是「当前发布标签那一份」的入口（门禁第 18 项逐字判它指向
  # `DoyahStudio-<发布标签>.app`）。rc 只是在 dist/ 里多放一份，不动任何既有身份。
  echo "==> 变体构建：不改 dist/DoyahStudio.app 别名（它仍指向日常版那一份）"
else
  if [ -e "${LATEST_LINK}" ] && [ ! -L "${LATEST_LINK}" ]; then
    mkdir -p "${ROOT}/dist/历史"
    LEGACY_NAME="DoyahStudio-遗留-$(date +%Y%m%dT%H%M%S).app"
    echo "==> ${LATEST_LINK} 是旧的真目录（不带版本号）⇒ 挪到 dist/历史/${LEGACY_NAME} 留档"
    mv "${LATEST_LINK}" "${ROOT}/dist/历史/${LEGACY_NAME}"
  fi
  ln -sfn "$(basename "${APP}")" "${LATEST_LINK}"
  echo "==> 别名：dist/DoyahStudio.app -> $(readlink "${LATEST_LINK}")（身份以带版本号的实物为准）"
fi

# ---- 交付回执（身份留痕：四项 = 目录 / 标签 / sha256 / 构建时刻；三项 = 含片 / 未含 / 验法）----
# 人类主人据此回答「我手上这份是不是最新的」。**历史包只增不删**：每个发布标签一个独立目录，
# 重建只覆盖**同名**的那一个 ⇒ 保留最近 ≥3 个历史包是结构保证，不靠额外的清理步骤。
BIN_FILE="${APP}/Contents/MacOS/DoyahStudio"
NOTES_FILE="${ROOT}/dist/发布说明-${APPLIED_LABEL}.md"
BUILD_TIME="$(date +%Y-%m-%dT%H:%M:%S%z)"
BIN_SHA="$(shasum -a 256 "${BIN_FILE}" | cut -d' ' -f1)"
echo ""
echo "==== 交付回执 ===="
echo "产物名：$(basename "${APP}")"
echo "目录：${APP}"
echo "标签：${APPLIED_LABEL}"
echo "构建时间：${BUILD_TIME}（UTC $(date -u +%Y-%m-%dT%H:%M:%SZ)）"
echo "sha256（前 8 位）：$(shasum -a 256 "${BIN_FILE}" | cut -c1-8)（二进制 ${BIN_FILE##*/} · $(stat -f %z "${BIN_FILE}") 字节）"
# 「本版包含」= 发布说明里**以 `本版包含：` 开头的那一行**（该行自带前缀也认，剥掉一个，
# 免得打印成「本版包含：本版包含：…」）。**不再取文件第一行** —— 本文件的头一行常常是标题
# （`# …发布说明…`），取它会把标题当成「本版包含」印出来（alpha3.1 实测踩到）。
if [ -f "${NOTES_FILE}" ]; then
  NOTES_LINE="$(grep -m1 -E '^\*{0,2}本版包含\*{0,2}[：:]' "${NOTES_FILE}" | sed -e 's/^\*\*本版包含\*\*[：:]//' -e 's/^本版包含[：:]//')"
  [ -n "${NOTES_LINE}" ] || NOTES_LINE="（未登记 —— 在 dist/发布说明-${APPLIED_LABEL}.md 里写一行「本版包含：…」）"
  echo "本版包含：${NOTES_LINE}"
else
  # `set -euo pipefail` 下 `NOTES_LINE` 必须有值 —— 这条分支此前没赋值，
  # 而收尾那行 `含片=${NOTES_LINE}` 会以 `unbound variable` 让整脚本退出 1
  # （实测 2026-10-13：本机克隆的 dist/ 里没有发布说明文件 ⇒ 必炸，且炸在**打包成功之后**，
  #  看着像打包失败）。口径与 `NOTES_EXCLUDED` 那条一致：**缺了就如实写未登记，不猜**。
  NOTES_LINE="（未登记 —— 在 dist/发布说明-${APPLIED_LABEL}.md 里写一行「本版包含：…」，或从交付面文档取）"
  echo "本版包含：${NOTES_LINE}"
fi
# 「未含」= 同一个发布说明里以 `未含：` 开头的那一行；缺了就**如实写未登记**，不猜。
NOTES_EXCLUDED=""
if [ -f "${NOTES_FILE}" ]; then
  NOTES_EXCLUDED="$(grep -m1 -E '^\*{0,2}未含\*{0,2}[：:]' "${NOTES_FILE}" | sed -e 's/^\*\*未含\*\*[：:]//' -e 's/^未含[：:]//')"
fi
[ -n "${NOTES_EXCLUDED}" ] || NOTES_EXCLUDED="（未登记 —— 在 dist/发布说明-${APPLIED_LABEL}.md 里写一行「未含：…」）"
echo "未含：${NOTES_EXCLUDED}"
echo "验法：shasum -a 256 \"${APP}/Contents/MacOS/DoyahStudio\" ｜ /usr/libexec/PlistBuddy -c 'Print :DoyahReleaseLabel' \"${APP}/Contents/Info.plist\""
# **交付身份留痕**（基本法第三十五条 · 人类主人 2026-10-11 裁）：四项（目录 / 标签 / sha256 /
# 构建时刻）+ 三项（含哪些片 / 未含 / 怎么验），一行可**整行粘进提交信息**（载体 (a)）。
# 卡面 `done` 与「分支已合」都**不算**身份留痕；`sha256` 是**全量**，与 `Contents/MacOS/` 下
# 那份二进制逐字节对得上（《交付物身份留痕》判据将来由脚本核）。
echo "交付: 目录=${APP} 标签=${APPLIED_LABEL} sha256=${BIN_SHA} 构建时刻=${BUILD_TIME} 含片=${NOTES_LINE} 未含=${NOTES_EXCLUDED} 验法=shasum -a 256 <目录>/Contents/MacOS/DoyahStudio + PlistBuddy Print :DoyahReleaseLabel"
echo "目录里的历史包：$(ls -d "${ROOT}"/dist/DoyahStudio-*.app 2>/dev/null | wc -l | tr -d ' ') 个（含本次）"
echo "=================="
echo ""
echo "完成：${APP}"
# **装到人真的会点开的地方**（主人 2026-10-30：「QQ 扫码配置也没有」—— 包只进 dist，
# `~/Applications` 停在三天前，于是新功能一次都没被看见）。默认自动安装，可用
# `DOYAH_SKIP_INSTALL=1` 只打包。
#
# 2026-11-06 加两条**不安装**的路（都是「日常版正在被用着，别把它换掉」）：
#   · `--no-install`：只出 dist/，**不碰** `~/Applications`（本脚本对它零写操作）；
#   · 变体构建（`--variant rc`）：rc 是拿来验 bug 的，**永远不装**（不给开关 —— 装进
#     `~/Applications` 就等于把主人的日常工具换成一个还没验过的包）。
if [ "${NO_INSTALL}" = "1" ] || [ -n "${VARIANT_KEY}" ]; then
  if [ -n "${VARIANT_KEY}" ]; then
    echo "（变体构建 ${VARIANT_KEY}：只出 dist/，未安装到 ~/Applications —— 那里只放日常版）"
  else
    echo "（--no-install：只打包，未安装到 ~/Applications）"
  fi
elif [[ "${DOYAH_SKIP_INSTALL:-0}" != "1" ]]; then
  bash "${ROOT}/Scripts/install-app.sh" "$(basename "${APP}")" || echo "⚠️ 已打包装好 dist，但安装到 ~/Applications 失败（见上面的原因）"
else
  echo "（DOYAH_SKIP_INSTALL=1：只打包，未安装到 ~/Applications）"
fi
echo "运行：open \"${APP}\""
