#!/bin/bash
set -euo pipefail

# 取源：从 sqlite.org 拿**指定版本**的 amalgamation，校验归档哈希，带进 Vendor/sqlite3/。
#
# 为什么要有这个脚本（而不是"我记得下载过"）：
#   三端（macOS / Windows / Linux）编的是同一份 sqlite3.c，所以"哪一份"必须是可复现的事实。
#   台账 `Scripts/vendored-sqlite.json` 记着版本号、归档 SHA-256、各文件 SHA-256 与 SOURCE_ID，
#   门禁 `Scripts/check-vendored-sqlite.py` 拿它逐字节对账 —— 本脚本负责把那本台账**重新算得出来**。
#
# 用法：
#   ./Scripts/vendor-sqlite3.sh                      # 取台账里记着的那个版本（默认行为）
#   ./Scripts/vendor-sqlite3.sh --version 3530500    # 换成另一个版本号（会提示台账要更新）
#   ./Scripts/vendor-sqlite3.sh --check-sums         # 只下载校验，不往 Vendor/ 里写
#
# 注意：脚本**不**自己改台账 —— 换版本是一次有意识的决定，得有人把哈希抄进
# `Scripts/vendored-sqlite.json` 并跑门禁（脚本会把该抄的东西打印出来）。

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
LEDGER="${ROOT}/Scripts/vendored-sqlite.json"
TARGET_DIR="${ROOT}/Vendor/sqlite3"
CACHE_DIR="${DOYAH_SQLITE_CACHE:-${TMPDIR:-/tmp}/doyah-sqlite-vendor}"

VERSION=""
CHECK_ONLY=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="${2:-}"; shift 2 ;;
        --check-sums) CHECK_ONLY=1; shift ;;
        -h|--help) sed -n '3,20p' "$0"; exit 0 ;;
        *) echo "未知参数：$1" >&2; exit 2 ;;
    esac
done

if [[ -z "${VERSION}" ]]; then
    VERSION="$(python3 - "${LEDGER}" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle)["versionNumber"])
PY
)"
fi

YEAR="${VERSION:0:4}"
ZIP_NAME="sqlite-amalgamation-${VERSION}.zip"
URL="https://sqlite.org/${YEAR}/${ZIP_NAME}"
DIR_NAME="sqlite-amalgamation-${VERSION}"
ARCHIVE="${CACHE_DIR}/${ZIP_NAME}"

mkdir -p "${CACHE_DIR}"
echo "==> 取源：${URL}"
if [[ ! -s "${ARCHIVE}" ]]; then
    # 网络慢的时候会断在中途，所以允许续传（sqlite.org 支持 Range）。
    curl -sSL --max-time 900 -C - -o "${ARCHIVE}" "${URL}"
fi
echo "==> 归档 SHA-256"
shasum -a 256 "${ARCHIVE}"

EXPECTED_ARCHIVE="$(python3 - "${LEDGER}" "${VERSION}" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    ledger = json.load(handle)
print(ledger["archiveSHA256"] if str(ledger["versionNumber"]) == sys.argv[2] else "")
PY
)"
ACTUAL_ARCHIVE="$(shasum -a 256 "${ARCHIVE}" | awk '{print $1}')"
if [[ -n "${EXPECTED_ARCHIVE}" && "${EXPECTED_ARCHIVE}" != "${ACTUAL_ARCHIVE}" ]]; then
    echo "❌ 归档哈希与台账不一致：" >&2
    echo "   台账：${EXPECTED_ARCHIVE}" >&2
    echo "   实际：${ACTUAL_ARCHIVE}" >&2
    echo "   （同名归档换了内容 —— sqlite.org 的归档是稳定的，先查是不是代理缓存给了别的文件）" >&2
    exit 1
fi

WORK="${CACHE_DIR}/${DIR_NAME}"
if [[ ! -f "${WORK}/sqlite3.c" ]]; then
    unzip -o -q "${ARCHIVE}" -d "${CACHE_DIR}"
fi

echo "==> 版本自证（从头文件里读，不信文件名）"
grep -m1 -E '^#define SQLITE_VERSION ' "${WORK}/sqlite3.h"
grep -m1 -E '^#define SQLITE_VERSION_NUMBER ' "${WORK}/sqlite3.h"
grep -m1 -E '^#define SQLITE_SOURCE_ID ' "${WORK}/sqlite3.h"

echo "==> 交付文件 SHA-256（台账里要抄的就是这两个 + 归档那一个）"
shasum -a 256 "${WORK}/sqlite3.c" "${WORK}/sqlite3.h"

if [[ "${CHECK_ONLY}" == "1" ]]; then
    echo "==> --check-sums：只校验，不写 Vendor/"
    exit 0
fi

mkdir -p "${TARGET_DIR}"
cp "${WORK}/sqlite3.c" "${WORK}/sqlite3.h" "${TARGET_DIR}/"
echo "==> 已写入 ${TARGET_DIR}（只带编译需要的两个文件：shell.c 与 sqlite3ext.h 不带，理由见 PROVENANCE.md）"
echo "==> 下一步：把上面的版本号 / 归档哈希 / 两个文件哈希 / SOURCE_ID 抄进 Scripts/vendored-sqlite.json，"
echo "          然后跑 python3 Scripts/check-vendored-sqlite.py 与 ./Scripts/verify-all.sh"
