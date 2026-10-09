#!/bin/bash
set -euo pipefail

# 编译并测试 DoyahCore（包含 PostgresNIO 驱动）。
#
# 该脚本使用 SwiftPM CLI，不依赖 Xcode GUI；
# 适合在没有数据库服务器时，先验证驱动编译与单元测试。

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SWIFT="${DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
SCRATCH="${ROOT}/.build"
CACHE="${ROOT}/.build-cache"

export DEVELOPER_DIR
export CLANG_MODULE_CACHE_PATH="${SCRATCH}/clang-module-cache"
export SWIFT_MODULE_CACHE_PATH="${SCRATCH}/swift-module-cache"
mkdir -p "${SCRATCH}" "${CACHE}" "${CLANG_MODULE_CACHE_PATH}" "${SWIFT_MODULE_CACHE_PATH}"

# 证据面（T-20261009-095 ②）：凡跑 swift test / xcodebuild 的证据必须能复现「用的哪套工具链」
# ⇒ 每次跑都把这行打进输出；`DEVELOPER_DIR` 仍可被外部显式覆盖（本机制不锁死取值）。
echo "ℹ️ 工具链证据: DEVELOPER_DIR=${DEVELOPER_DIR} · $("${DEVELOPER_DIR}/usr/bin/xcodebuild" -version 2>/dev/null | tr '\n' ' ')"

# 「文档里的数字」台账（Scripts/doc-numbers.json）的 core-tests 那一项，证据落在下面两个文件里：
TEST_LOG="${SCRATCH}/core-test.log"
COUNT_FILE="${SCRATCH}/core-test-count.txt"

cd "${ROOT}"

"${SWIFT}" package \
  --disable-sandbox \
  --package-path . \
  --cache-path "${CACHE}" \
  --scratch-path "${SCRATCH}" \
  --manifest-cache local \
  resolve

set +e   # 这一段要自己收 swift 的退出码（PIPESTATUS），别让 set -e 抢在前头中止
"${SWIFT}" test \
  --disable-sandbox \
  --package-path . \
  --cache-path "${CACHE}" \
  --scratch-path "${SCRATCH}" \
  --manifest-cache local \
  -Xswiftc -disable-sandbox 2>&1 | tee "${TEST_LOG}"
STATUS="${PIPESTATUS[0]}"
set -e

# 单测数是「文档里的数字」台账（Scripts/doc-numbers.json）里的 core-tests 那一项 ——
# 它只认**同一次运行**跑出来的数，不认人的记忆、也不认上一轮的日志。
# 纪律：解析不到就**删掉计数文件**（宁可让判据如实报「跳过」，也不许留一个陈旧值冒充现状）。
COUNT="$(grep -Eo 'Executed [0-9][0-9]* tests?' "${TEST_LOG}" | tail -1 | grep -Eo '[0-9][0-9]*' || true)"
if [ -n "${COUNT}" ]; then
  printf '%s tests\n' "${COUNT}" > "${COUNT_FILE}"
  echo "ℹ️ Core 单测 ${COUNT} 项（已写入 ${COUNT_FILE}，供 Scripts/check-doc-numbers.py 对账）"
else
  rm -f "${COUNT_FILE}"
  echo "⚠️ 解析不出单测数（${TEST_LOG} 里没有「Executed N tests」这一行）—— 已删掉 ${COUNT_FILE}，判据会如实报「跳过」"
fi

exit "${STATUS}"
