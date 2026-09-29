#!/bin/bash
set -euo pipefail

# 「界面点验自动化」的入口（队列 `L-90` —— 「App 内探针 + 自渲染快照」路线，**零权限**）。
#
#   ./Scripts/verify-ui-interactions.sh                     # 跑全部交互探针
#   ./Scripts/verify-ui-interactions.sh --filter 用例片段    # 只跑一部分
#
# ## 与 `run-manual-verification-probes.sh` 的分工
#
# 那份把「待人工验收清单」的 B 类（13 条：快照 / 探针可代劳）机器化，跑**两遍**（其中一条判据要靠
# 「沙箱标记」那一面）。这一份是清单 §0.2 的 D 类（5 条：真实鼠标 / 键盘事件）改走「自己点自己」
# 之后的入口 —— 判据与进程环境无关，所以**只跑一遍**，但末尾两件事一件不少：
#
#   · **核对跑了几条、有没有跳过**（跳过 ≠ 通过：`XCTSkip` 会让「三条全过」变成零证据）；
#   · **源锚点**（判据盯的必须是产品那条线：路由判定在 Core、视图真的问过它、字节真的从
#     `TerminalInput` 那两个出口出去 —— 判据与产品脱钩的话，绿也是白绿）。
#
# ## 本批（㈠）：终端交互三面
#
# `TestsUISnapshot/TerminalInteractionProbeTests.swift` 判清单 §1 那三行的**行为面**：
#   ① `FR-EDIT-29` 鼠标上报 —— 按下 / 拖动 / 滚轮在**程序接管鼠标**时真的转发（SGR 报文出现在
#      「前台程序的字节出口」上），按住 ⌥ 拖动必须归本机（出现选区、报文不再增加）；
#   ② `FR-EDIT-29` 方向键（DECCKM）—— `?1h` 置位时 ↑ 走 SS3、复位后走 CSI；
#   ③ `FR-EDIT-29` 右键菜单 —— 程序接管鼠标时菜单仍归本机（五项齐备且指向产品自己的动作），
#      只有「接管 + ⌥」才转发给程序。
# 判字节出口是**真 PTY**（终端里跑 `cat -v`，把收到的字节按可见形式打回屏幕）。两条边界
# （右键「不按 ⌥」那一面**不派发事件**；快照与「多光标 / 对象树逐行右键」两条留到 ㈡）
# 写在那个文件的头注释里。

ROOT="$(cd "$(dirname "${0}")/.." && pwd -P)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SWIFT="${DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
SCRATCH="${ROOT}/.build"
CACHE="${ROOT}/.build-cache"
OUT="${SCRATCH}/ui-interactions"
FILTER="TerminalInteractionProbeTests"
while [ $# -gt 0 ]; do
    case "${1}" in
        --filter) FILTER="${2:-}"; shift 2 ;;
        *) echo "未知参数：${1}（支持 --filter <片段>）"; exit 2 ;;
    esac
done

export DEVELOPER_DIR
export CLANG_MODULE_CACHE_PATH="${SCRATCH}/clang-module-cache"
export SWIFT_MODULE_CACHE_PATH="${SCRATCH}/swift-module-cache"
export DOYAH_UI_SNAPSHOT=1

# 与用户真实数据解耦：笔记 / 外发日志指到每轮清空的临时目录
# （探针真开 shell，但不该往真实数据家里写一个字节）。
PROBE_DATA="${SCRATCH}/ui-interaction-data"
rm -rf "${PROBE_DATA}"
mkdir -p "${PROBE_DATA}/notes" "${PROBE_DATA}/egress"
export DOYAH_NOTES_DIR="${PROBE_DATA}/notes"
export DOYAH_EGRESS_LOG_DIR="${PROBE_DATA}/egress"

mkdir -p "${CACHE}" "${SCRATCH}" "${CLANG_MODULE_CACHE_PATH}" "${SWIFT_MODULE_CACHE_PATH}" "${OUT}"
cd "${ROOT}"

LOG="${OUT}/run-$(date +%Y%m%d-%H%M%S).log"
echo "==> 跑交互探针（${FILTER}）—— 证据日志 ${LOG}"
set +e
"${SWIFT}" test \
    --disable-sandbox \
    --package-path . \
    --cache-path "${CACHE}" \
    --scratch-path "${SCRATCH}" \
    --manifest-cache local \
    -Xswiftc -disable-sandbox \
    --filter "${FILTER}" 2>&1 | tee "${LOG}"
STATUS="${PIPESTATUS[0]}"
set -e
if [ "${STATUS}" -ne 0 ]; then
    echo "✗ swift test 退出码 ${STATUS}（完整日志 ${LOG}）"
    exit "${STATUS}"
fi

echo
echo "==> 核对：跑了几条、有没有跳过（跳过 ≠ 通过）"
python3 - "${LOG}" <<'PY'
import re
import sys

log = open(sys.argv[1], encoding="utf-8", errors="replace").read()
failures = []

executed = re.findall(r"Executed (\d+) tests?, with (\d+) failures? \((\d+) unexpected\)", log)
if not executed:
    failures.append(
        "日志里没有 \"Executed N tests\" —— 探针根本没跑（检查 --filter / DOYAH_UI_SNAPSHOT）"
    )
else:
    # 一个 xctest 进程里会打好几个套件（本套件 + 过滤后剩 0 条的空套件）⇒ 取**条数最多**那条汇总，
    # 否则会被后面那些 0 条的空套件盖掉（本次实测第一版就是这么假红的）。
    total, failed, unexpected = max(executed, key=lambda row: int(row[0]))
    if int(failed) or int(unexpected):
        failures.append(f"汇总非零失败：{failed} 失败 / {unexpected} 意外")
    if int(total) < 3:
        failures.append(
            f"只跑了 {total} 条 —— 本批三条（鼠标上报 / DECCKM / 右键归属）应当都跑到"
        )

expected = [
    "testMouseReportingForwardsToTheProgramAndOptionKeepsItLocal",
    "testCursorKeyBytesFollowDECCKMOnARealProgram",
    "testRightClickMenuStaysLocalAndOnlyOptionForwardsIt",
]
for name in expected:
    if name not in log:
        failures.append(f"日志里没有 {name}")
    elif not re.search(rf"Test Case '[^']*{re.escape(name)}\]' passed", log):
        failures.append(f"{name} 没有以 passed 收尾（跳过 / 失败都会走到这里）")

if "skipped" in log:
    failures.append("日志里出现 skipped —— 探针被跳过了，那不是通过")

if failures:
    for item in failures:
        print(f"✗ {item}")
    sys.exit(1)
print("✓ 三条都真跑过、都以 passed 收尾、没有跳过")
PY

echo
echo "==> 源锚点：判据盯的必须是产品那条线"
python3 - "${ROOT}" <<'PY'
import os
import sys

root = sys.argv[1]
anchors = {
    "App/Views/TerminalView.swift": (
        ("TerminalInput.route(", "视图不再问 Core 的归属判定（拖动 / 滚轮那条线）"),
        ("TerminalInput.rightClickRoute(", "视图不再问 Core 的右键归属判定"),
        ("guard forwardsRightClick(event) else { return super.rightMouseDown(with: event) }",
         "右键「归本机」那一支不再走 AppKit 的弹菜单（菜单会永远不出现）"),
        ("if isReportingMouse(event) {", "鼠标事件不再先判归属再分发"),
        ("applicationCursorKeys: model.screen.isApplicationCursorKeysEnabled",
         "方向键不再带上 DECCKM（vim / less 分不出两种键序）"),
        ("TerminalInput.mouseReport(", "鼠标上报字节不再经唯一出口"),
        ("TerminalInput.shouldReport(", "鼠标上报不再按模式过滤"),
    ),
}

failures = []
for relative, needles in anchors.items():
    path = os.path.join(root, relative)
    if not os.path.exists(path):
        failures.append(f"{relative} 不在盘上")
        continue
    text = open(path, encoding="utf-8").read()
    for needle, why in needles:
        if needle not in text:
            failures.append(f"{relative} 里「{needle}」不见了：{why}")

if not os.path.exists(os.path.join(root, "TestsUISnapshot/TerminalInteractionProbeTests.swift")):
    failures.append("TestsUISnapshot/TerminalInteractionProbeTests.swift 不在盘上")

if failures:
    for item in failures:
        print(f"✗ {item}")
    sys.exit(1)
print("✓ 七个源锚点都在：路由判定在 Core、视图真的问过它、字节从 TerminalInput 出去")
PY

echo
echo "==> 完成：证据日志在 ${OUT}/"
echo "    本批（L-90 ㈠）判住的三条："
echo "    · §1 FR-EDIT-29 鼠标上报（真 PTY 上的 SGR 报文：右下角点击列行变大、拖动 32、滚轮 64、⌥ 归本机）"
echo "    · §1 FR-EDIT-29 方向键 DECCKM（?1h 时 ^[OA、复位后 ^[[B）"
echo "    · §1 FR-EDIT-29 右键菜单（五项齐备且指向产品自己的动作、接管 + ⌥ 时按钮码 10 转发）"
