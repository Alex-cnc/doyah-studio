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
# （右键「不按 ⌥」那一面**不派发事件**）写在那个文件的头注释里。
#
# ## 第二批（L-90 ㈡ 第 1 条，第 109 轮）：多光标与列编辑
#
# `TestsUISnapshot/MultiCursorProbeTests.swift` 判清单 §3 `FR-EDIT-27` 那一行的**行为面**
# （「⌥ 拖拽列选；⌥⌘D 选下一处；⌥⌘↑ / ↓ 加光标；多光标下打字与 ⌫」＋验收面「一次撤销能全回退、
# 光标位置不漂」）：真 `SQLEditorView` 进活宿主、从视图树里取出真 `SQLTextView`，
# 合成的 `NSEvent`（⌥⌘D / ⌥⌘↑↓ / ⌥ 拖拽）直接交给它的方法；「界面上有几个光标」
# 读 `SQLTextView.multiSelection`。三条用例各出一张图。
#
# **本轮在这条路上抓出一个真缺陷并修掉**：`NSTextView` **只收得下第一个零长度选区**
# （实测 macOS 27：设 `[{4,0},{30,0}]` 读回来 `[{4,0}]`；非零长度的多选区则原样收下）
# ⇒ `⌥⌘↑` / `⌥⌘↓` **加光标在真机上一直是静默失效的**（`selectedRanges` 恒为一条 ⇒
# 打字 / 退格的多光标分支、`drawInsertionPoint` 画次光标那段都是死代码），
# 而判 Core 的 `MultiCursorTests` 21 项照样全绿。修法：零长度那些由视图自己记
# （`rememberedCarets`），选区集合取「AppKit 收下的 + 自己记的」两份并集。
# 下面那两条源锚点盯的就是这个修法别再退回去。

ROOT="$(cd "$(dirname "${0}")/.." && pwd -P)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SWIFT="${DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
SCRATCH="${ROOT}/.build"
CACHE="${ROOT}/.build-cache"
OUT="${SCRATCH}/ui-interactions"
FILTER="TerminalInteractionProbeTests|MultiCursorProbeTests"
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
    if int(total) < 6:
        failures.append(
            f"只跑了 {total} 条 —— 两批六条（鼠标上报 / DECCKM / 右键归属 / ⌥⌘D 多光标 /"
            " ⌥⌘↑↓ 加光标 / ⌥ 拖拽列选）应当都跑到"
        )

expected = [
    "testMouseReportingForwardsToTheProgramAndOptionKeepsItLocal",
    "testCursorKeyBytesFollowDECCKMOnARealProgram",
    "testRightClickMenuStaysLocalAndOnlyOptionForwardsIt",
    "testOptionCommandDTypesInEveryOccurrenceAndOneUndoRevertsAll",
    "testOptionArrowMultipliesCaretsAndEditingHitsEveryCaret",
    "testOptionDragSelectsAColumnAcrossLinesWithoutCrossingThem",
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
print("✓ 六条都真跑过、都以 passed 收尾、没有跳过")
PY

echo
echo "==> 源锚点：判据盯的必须是产品那条线"
python3 - "${ROOT}" <<'PY'
import os
import sys

root = sys.argv[1]
anchors = {
    "App/Views/SQLEditorView.swift": (
        ("private var rememberedCarets: [NSRange] = []",
         "视图不再自己记住 AppKit 收不下的裸光标（⌥⌘↑↓ 加光标会静默失效）"),
        ("selectedRanges.map(\\.rangeValue) + rememberedCarets,",
         "选区集合不再并上自己记的裸光标"),
        ("guard rangeValues.count > 1, !text.isEmpty else {",
         "多光标打字不再看那份含裸光标的集合"),
        ("if event.keyCode == 53, rangeValues.count > 1 {",
         "Esc 收敛不再看那份含裸光标的集合"),
        ("if !isApplyingMultiSelection { rememberedCarets = [] }",
         "用户自己动光标时不再作废裸光标（会退回「看着一个光标、打字却在两处」）"),
    ),
    "Core/MultiCursor.swift": (
        ("let end = range.location + min(maxColumn + 1, contentLength)",
         "列选不再夹到行尾（短行会被拽过换行）"),
    ),
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

for probe in ("TerminalInteractionProbeTests", "MultiCursorProbeTests"):
    if not os.path.exists(os.path.join(root, f"TestsUISnapshot/{probe}.swift")):
        failures.append(f"TestsUISnapshot/{probe}.swift 不在盘上")

if failures:
    for item in failures:
        print(f"✗ {item}")
    sys.exit(1)
print("✓ 源锚点都在：路由判定在 Core、视图真的问过它、字节从 TerminalInput 出去、裸光标由视图自己记")
PY

echo
echo "==> 完成：证据日志在 ${OUT}/"
echo "    本入口判住的六条："
echo "    · §1 FR-EDIT-29 鼠标上报（真 PTY 上的 SGR 报文：右下角点击列行变大、拖动 32、滚轮 64、⌥ 归本机）"
echo "    · §1 FR-EDIT-29 方向键 DECCKM（?1h 时 ^[OA、复位后 ^[[B）"
echo "    · §1 FR-EDIT-29 右键菜单（五项齐备且指向产品自己的动作、接管 + ⌥ 时按钮码 10 转发）"
echo "    · §3 FR-EDIT-27 ⌥⌘D 选下一处（三处同内容都进选区、打字三处一起改、一次撤销全回退、光标不漂）"
echo "    · §3 FR-EDIT-27 ⌥⌘↑ / ↓ 加光标（本轮修的缺陷：加出来的光标必须真的在；打字 / ⌫ / 回车逐个生效；Esc 收敛）"
echo "    · §3 FR-EDIT-27 ⌥ 拖拽列选（逐行一段、短行夹到行尾、绝不跨换行、一次撤销）"
