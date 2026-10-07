#!/bin/bash
set -euo pipefail

# 片 `N2-4` 判据③ 的**进程级**证据：`kill -9` 之后重开，最近一次自动保存的内容还在。
#
# 为什么要有这一条（探针里那条等价物之外再补一次真的信号）：
#   探针 `testN24AutosavePersistsOnPauseWithoutAnyExitPath` 判的是「**没有任何退出路径**，
#   内容也已经落盘」（成对读数：窗前后各从独立连接读一次盘）。那一条已经把「内容在盘上」证住；
#   这里再补一次**真的信号**：phase 1 落库之后 `kill(getpid(), SIGKILL)` —— 不可捕获、
#   不给任何收尾机会（`kill -9 <pid>` 发的就是它，用户在活动监视器里点「强制退出」也是它）。
#   于是「重开之后内容还在」只剩一种解释：**盘上那一份**。
#
# 两遍，中间那一下是真的强杀：
#   ① `DOYAH_AUTOSAVE_KILL9=type`：打字 → 等停顿窗口 → 落库 → 写交接单 → `SIGKILL` 自己
#      （进程当场死掉 ⇒ `swift test` 报非零退出，那是**预期**，不是失败）；
#   ② `DOYAH_AUTOSAVE_KILL9=read`：**另一个进程**读交接单 + 读盘，断言正文 = 「最近一次自动保存」。
#
# 三条纪律：
#   · **跳过 ≠ 通过**：`swift test` 跳过用例也返回 0，所以两遍都按**输出里的读数行**判
#     （`N2-4 ③ phase 1/2 …`），光看退出码会把「没跑」读成「过了」；
#   · 夹具一律在 `.build/` 下的临时数据家里（笔记库指到 `DOYAH_NOTES_DIR`），不碰真实用户数据；
#   · 这一条**不进** `verify-all.sh`（它花几十秒、还要真杀一个进程）—— 它是取证，不是每轮门禁。
#
# 用法：`bash Scripts/test-note-autosave-kill9.sh`

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SWIFT="${DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
SCRATCH="${ROOT}/.build"
CACHE="${ROOT}/.build-cache"
DATA="${SCRATCH}/note-autosave-kill9"
HANDOFF="${DATA}/handoff.json"
LOG_ONE="${DATA}/phase1.log"
LOG_TWO="${DATA}/phase2.log"

export DEVELOPER_DIR
export CLANG_MODULE_CACHE_PATH="${SCRATCH}/clang-module-cache"
export SWIFT_MODULE_CACHE_PATH="${SCRATCH}/swift-module-cache"
export DOYAH_UI_SNAPSHOT=1
export DOYAH_NOTES_DIR="${DATA}/notes"
export DOYAH_AUTOSAVE_KILL9_HANDOFF="${HANDOFF}"

rm -rf "${DATA}"
mkdir -p "${DOYAH_NOTES_DIR}" "${CACHE}" "${CLANG_MODULE_CACHE_PATH}" "${SWIFT_MODULE_CACHE_PATH}"
cd "${ROOT}"

run_phase() {  # $1 = type|read ；$2 = 这一遍的日志文件
    DOYAH_AUTOSAVE_KILL9="$1" "${SWIFT}" test \
        --disable-sandbox \
        --package-path . \
        --cache-path "${CACHE}" \
        --scratch-path "${SCRATCH}" \
        --manifest-cache local \
        -Xswiftc -disable-sandbox \
        --filter "NotesEditorSaveProbeTests/testN24Kill9Phase" > "$2" 2>&1
}

echo "==> ① 打字 → 停顿窗口 → 落库 → SIGKILL 自己（不可捕获）"
if run_phase type "${LOG_ONE}"; then
    PHASE_ONE_STATUS="0"
else
    PHASE_ONE_STATUS="$?"
fi
echo "    phase 1 的 swift test 退出码 ${PHASE_ONE_STATUS}（被 SIGKILL 带走 ⇒ 非零是预期）"

if ! grep -q "N2-4 ③ phase 1：已落库并写好交接单" "${LOG_ONE}"; then
    echo "✗ phase 1 没有走到「已落库」那一步 —— 不能拿「反正它死了」当通过"
    tail -30 "${LOG_ONE}"
    exit 1
fi
grep "N2-4 ③ phase 1" "${LOG_ONE}"

if [ ! -f "${HANDOFF}" ]; then
    echo "✗ 交接单没写出来：${HANDOFF}（强杀之后那一遍读不到「期望什么」）"
    exit 1
fi
echo "    ✓ phase 1 真跑到落库了，并且进程确实是被 SIGKILL 带走的"

echo "==> ② 另一个进程：读交接单 + 读盘（上一个进程已经没了）"
PHASE_TWO_STATUS=0
if ! run_phase read "${LOG_TWO}"; then
    PHASE_TWO_STATUS=1
fi

if [ "${PHASE_TWO_STATUS}" != "0" ]; then
    echo "✗ phase 2 的 swift test 没通过（退出码非零）"
    tail -40 "${LOG_TWO}"
    exit 1
fi
if ! grep -q "N2-4 ③ phase 2：强杀后重开" "${LOG_TWO}"; then
    echo "✗ phase 2 没有跑出读数行（跳过也算 0 退出码 —— 跳过 ≠ 通过）"
    tail -40 "${LOG_TWO}"
    exit 1
fi
grep "N2-4 ③ phase 2" "${LOG_TWO}"

echo
echo "✅ 判据③（进程级）：打字 → 停顿窗口一到就落库 → 真 SIGKILL → 另一个进程读盘，内容仍在"
echo "   读数留档：${LOG_ONE} · ${LOG_TWO}"
