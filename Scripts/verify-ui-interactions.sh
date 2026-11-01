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
#   ① `FR-STD-WS-TOOL-001` 鼠标上报 —— 按下 / 拖动 / 滚轮在**程序接管鼠标**时真的转发（SGR 报文出现在
#      「前台程序的字节出口」上），按住 ⌥ 拖动必须归本机（出现选区、报文不再增加）；
#   ② `FR-STD-WS-TOOL-001` 方向键（DECCKM）—— `?1h` 置位时 ↑ 走 SS3、复位后走 CSI；
#   ③ `FR-STD-WS-TOOL-001` 右键菜单 —— 程序接管鼠标时菜单仍归本机（五项齐备且指向产品自己的动作），
#      只有「接管 + ⌥」才转发给程序。
# 判字节出口是**真 PTY**（终端里跑 `cat -v`，把收到的字节按可见形式打回屏幕）。两条边界
# （右键「不按 ⌥」那一面**不派发事件**）写在那个文件的头注释里。
#
# ## 第二批（L-90 ㈡ 第 1 条，第 109 轮）：多光标与列编辑
#
# `TestsUISnapshot/MultiCursorProbeTests.swift` 判清单 §3 `FR-STD-WS-EDIT-016` 那一行的**行为面**
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
#
# ## 第三批（L-90 ㈡ 第 2 条，第 110 轮）：对象树逐行右键
#
# `TestsUISnapshot/ObjectTreeContextMenuProbeTests.swift` 判清单 §4 `FR-STD-DB-META-012` 那一行
# （「依次右键表 / 视图 / 列 / 服务器 / 数据库 / schema / 函数」）：菜单**内容**与**作用在哪一行**
# 两件事这一轮都搬进了 `App/Views/ObjectTreeContextMenu.swift`（一个静态 `@ViewBuilder` 入口 + 一个纯函数），
# 于是不需要鼠标事件、也不需要任何权限 —— 每类节点渲染一遍、拿「这一遍取到的文案集合」与
# `ObjectTreeActions.isAvailable` 的规则**双向**对账；作用行用产品自己摊平的
# `ObjectTreeRows.visibleRows` 喂 `ObjectTreeMenuTarget.resolve`。
# 老缺陷的回归钉 = 「非服务器那一行**不许**出现服务器菜单项」（点数据库弹服务器菜单那次）。
#
# ## 第五批（v0.3.0 数据库运维面·第一跳）：`FR-STD-DB-RES-006` 复制为多格式
#
# `TestsUISnapshot/ResultCopyProbeTests.swift` 判这一行的**交付面**（台账备注原文是
# 「界面粘贴待人工点验」）：挂真 `ResultGrid` 进离屏真窗口 → 取出真 `NSTableView` →
# 用**产品自己那份右键菜单**（`tableView.menu`）里的菜单项 → 按菜单项自己的
# `action` / `target` 派发 → 读 `NSPasteboard.general` 里真实的字符串。七条：
#   ① 四档格式都在「复制为…」子菜单里、每档都能真的写进系统剪贴板且带表头 / 只含选中的行；
#   ② 默认 ⌘C = TSV，逐字节与需求口径一致（值里的制表符 / 换行被换成空格，不撑破行）；
#   ③ 转义：Markdown 的 `|` 与换行（`<br>`）、CSV 含换行字段加引号；
#   ④ INSERT 指向**正在浏览的那张表**（`public.orders`），没有来源表时落占位表名；
#   ⑤ 负例：没有选中行时剪贴板一个字节都不动；
#   ⑥ 只进剪贴板、不落文件（剪贴板类型里没有 `public.file-url`）。
# **证不住**：把这段文本粘进 Excel / 飞书之后长什么样（外部软件行为，与 `DB-RES-014` 同边界）。
# 反例三段（默认格式改成 markdown / INSERT 不带来源表 / 菜单少放一档格式）各判红后逐字节还原。
#
# ## 第六批（v0.3.0 数据库运维面·第二跳）：`FR-STD-DB-RES-007` 客户端排序
#
# `TestsUISnapshot/ResultSortProbeTests.swift` 判这一行的**交付面**（台账备注原文是
# 「界面点击待人工点验」）：挂真 `ResultTableView`（生产里自己持有 `ResultGridState` 的那个视图）
# 进离屏真窗口 → 取出真 `NSTableView` → 取**真表头**（`tableView.headerView`）→ 用那一列的
# 中间点造 `NSEvent`，把 `mouseUp` 投进 `NSApplication` 的事件队列，再把 `mouseDown` **直接交给
# 表头自己的 `mouseDown(with:)`** —— 用户点一下走的就是这条 AppKit 路径（跟踪循环、指示器、
# `sortDescriptorsDidChange` 都在里面）。判据读**表格里真的显示成什么**（逐行取
# `NSTableCellView.textField.stringValue`）+ 表头指示器（`tableView.sortDescriptors`）。六条：
#   ① 每列都带排序原型（没有它 AppKit 不画指示器、也不派发变化，点上去等于点死木头），
#      且点这一列的中点命中的就是这一列（点 A 排 B 的那种错行）；
#   ② 升 → 降 → 取消三档，取消后回到服务端顺序、指示器清空，且点表头不改列宽；
#   ③ 数值按数值比（`9` 排在 `10` 前）、**NULL 在两种方向下都留在末尾**（早期实现按方向取反、
#      降序时 NULL 跑到最前的那次事故的回归钉）；
#   ④ Shift 点第二列 = 追加次要键，主键不丢；
#   ⑤ Shift 再点同一个次要键先翻方向、第三下只删这一键（主键留着）；
#   ⑥ 负例：点表头**空白处**什么都不发生（不许凭空清掉排序）。
# **证不住**：真鼠标在真屏幕上的手感（双击节奏、拖几像素才算拖列）—— 输入设备行为，不在本行验收要点里。
# 反例三段（派发退回 `sortDescriptors.first` / 让 NULL 跟着方向翻 / 显示变更退回「首末行摘要」）
# 各判红后逐字节还原。
#
# **本批在这条路上抓出两个真缺陷并修掉**（不是只补判据）：
#   · Shift 加次要键时派发读 `tableView.sortDescriptors.first`，而 AppKit 把新列**追加**在后面
#     ⇒ 第一个仍是被点的老主键，多列排序永远加不上新列（`SortableHeaderView` 改为自己记
#     「点的是哪一列、有没有按 Shift」，一次点击只派发一档）；
#   · 表格「显示内容变了没有」原先用「行数 + 首行 + 末行」摘要判 —— 取消排序回到服务端顺序时
#     末行往往与降序那份的末行相同 ⇒ 摘要不变 ⇒ 不重载 ⇒ 界面上还留着旧的排序结果
#     （现改为逐行比对 `lastDisplayedRows`）。
#
# ## 第七批（v0.3.0 数据库运维面·第三跳）：`FR-STD-DB-RES-008` 客户端筛选
#
# `TestsUISnapshot/ResultFilterProbeTests.swift` 判这一行的**交付面**（台账备注原文是
# 「界面点击待人工点验」）：挂真 `ResultTableView` 进离屏真窗口 → 取真 `NSTableView` 与条上的
# 真控件 → 按钮用 `performClick(nil)`、换列 / 换运算符用 `NSPopUpButton.selectItem + sendAction`
# （与手选同一条 action 路径）、打字走**字段编辑器**（`makeFirstResponder` →
# `currentEditor().insertText`，与手打同一条路）。判据读**表格里真的显示成哪几行**。六条：
#   ① 死路回归钉：**没做过任何客户端操作**时条也在场、「+」点得动，而且加出来的（还没填值的）
#      条件**不参与筛选**（一行不少）；
#   ② 换列：条件看的是哪一列，表格跟着变（换到 id 列 ⇒ 0 行，换回 note ⇒ 3 行）；
#   ③ 换运算符：包含 / 不包含 / 为空 三档都改到显示的行，「为空」同时命中 NULL 与空串，
#      并把值输入框收掉（它不需要值）；
#   ④ 打字：逐字打进输入框，表格**当场**跟着筛，且编辑会话一直在（`currentEditor()` 不丢 ——
#      `TitleBarSearchField` 那次「字只进得去一个」的同一类风险）；
#   ⑤ 大小写开关：同一份数据按一下命中的行就变（`beta/BETA/gamma` ⇒ 只剩 `BETA`）；
#   ⑥ 多条件 AND + 删单条条件 + 删光之后条还在、还能再加（入口不许跟着条件一起消失）。
# **证不住**：真鼠标点开菜单的弹出动画与拖选文本（输入设备行为）；条右侧「清空全部条件 /
# 生成 WHERE」两颗仍是 SwiftUI `.plain` 按钮（`ToolbarIconButton` 不落成 `NSButton`，量不到点击）。
# 反例四段（条退回 `isClientViewActive` 才渲染 / 待填条件照旧参与筛选 / 列弹出按钮退回 SwiftUI
# `Menu` / WHERE 不丢待填条件）各判红后逐字节还原。
#
# **本批在这条路上抓出两个真缺陷并修掉**（不是只补判据）：
#   · 筛选条只在 `isClientViewActive` 时渲染，而唯一的「+ 加条件」入口就在条里 ⇒ 没排过序的用户
#     永远加不了第一个筛选条件（与 2026-09-23 分页条死路同一个形状）；
#   · 点「+」当场把整张表清空：新条件默认 `contains ""`，而 Foundation 里 `"abc".contains("") == false`
#     ⇒ 一条还没填值的条件筛掉了所有行。现按 `ResultFilter.isPending` 跳过，也进不了生成的 WHERE。
#
# **源锚点归位（开发循环第 113 轮，队列 `L-103`）**：2026-09-29 23:25–23:36 那个会话把行渲染搬进
# `ObjectTreeRowContent.swift`、把右键改由**行的 AppKit 捕获器**自己给出（`ObjectTreeRightClick.swift`
# → `ObjectTreeAppKitMenu.build(object: row.object…)`），附录里原先钉的三条（`.contextMenu {` /
# `ObjectTreeMenuTarget.resolve(` / `ObjectTreeContextMenu.items(` 在 `ObjectTreeView.swift` 里）
# 跟着失效 ⇒ 本入口**九条探针全绿却在源锚点那一步 exit 1**。归位后盯的是**同一件事的新形状**：
# 每一行有自己的捕获器、菜单由这一行现建、目标就是 `row.object`（「不许退回整树一份 + 悬停解析」
# 那半由两份 Swift 判据的 `XCTAssertFalse` 钉住，不在这里重复）。

# ## 第四批（`T-20261002-027`，开发循环第 162 轮）：标题栏搜索栏**点击地图**
#
# `TestsUISnapshot/TitleBarSearchClickProbeTests.swift` 判「**看得见的框 = 能点的框**」这条：
# 可见框内的采样点逐点断言命中目标 = 输入框或其接力层（任一点落空 ⇒ 判红）、留白点按下真的把
# 键盘交给同一框里的输入框、清空按钮那一段留给 SwiftUI、以及**同一套量法喂修前那份框必须判红**
# （红/绿成对）。**真因**（第 162 轮量到的）：SwiftUI 画的背景填充与 `strokeBorder` 默认参与命中
# 测试，压在那层接力之上 ⇒ 第 161 轮那层「装上却没接到点击」。宿主是**手工搭的真窗口 + 工具条**
# （与 SwiftUI 工具条项同形），进程内合成事件 ⇒ 零权限。

ROOT="$(cd "$(dirname "${0}")/.." && pwd -P)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SWIFT="${DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
SCRATCH="${ROOT}/.build"
CACHE="${ROOT}/.build-cache"
OUT="${SCRATCH}/ui-interactions"
FILTER="TerminalInteractionProbeTests|MultiCursorProbeTests|ObjectTreeContextMenuProbeTests|TitleBarSearchClickProbeTests|ResultCopyProbeTests|ResultSortProbeTests|ResultFilterProbeTests"
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
# 证据面（T-20261009-095 ②）：回执里的「工具链」必须可复现 ⇒ 每次跑都写进输出（`DEVELOPER_DIR` 仍可外部覆盖）。
echo "ℹ️ 工具链证据: DEVELOPER_DIR=${DEVELOPER_DIR} · $("${DEVELOPER_DIR}/usr/bin/xcodebuild" -version 2>/dev/null | tr '\n' ' ')"
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
    if int(total) < 35:
        failures.append(
            f"只跑了 {total} 条 —— 七批三十五条（鼠标上报 / DECCKM / 右键归属 / ⌥⌘D 多光标 /"
            " ⌥⌘↑↓ 加光标 / ⌥ 拖拽列选 / 逐行菜单内容 / 菜单作用行 / 菜单确定性与跟随行 /"
            " 点击地图 / 留白点给键盘 / 清空按钮三态 + 回车接线 / 打字后回车交词 / 修前对照 / 整框源锚点 /"
            " 复制四档格式与默认 TSV / 排序三档与 NULL / Shift 次要键 / 筛选条默认在场 /"
            " 换列与换运算符 / 逐字打值 / 大小写开关 / 多条件 AND 与删条件）应当都跑到"
        )

expected = [
    "testMouseReportingForwardsToTheProgramAndOptionKeepsItLocal",
    "testCursorKeyBytesFollowDECCKMOnARealProgram",
    "testRightClickMenuStaysLocalAndOnlyOptionForwardsIt",
    "testOptionCommandDTypesInEveryOccurrenceAndOneUndoRevertsAll",
    "testOptionArrowMultipliesCaretsAndEditingHitsEveryCaret",
    "testOptionDragSelectsAColumnAcrossLinesWithoutCrossingThem",
    "testEachRowKindGetsItsOwnMenuNotTheServersMenu",
    "testMenuTargetFollowsTheRowUnderTheMouse",
    "testMenuIsDeterministicAndFollowsTheRow",
    "testEverySamplePointInTheVisibleBoxLandsOnTheBoxOrItsControls",
    "testPaddingClicksHandTheFieldTheKeyboard",
    "testClearButtonShowsWithTextAndClearsIt",
    "testTypedTextThenReturnStillHandsTheWordOut",
    "testLegacySwiftUISearchBoxWouldSwallowThePaddingPoints",
    "testSourceAnchorsKeepTheBoxPureAppKit",
    # 第五批（v0.3.0 数据库运维面第一跳 · FR-STD-DB-RES-006）：复制为多格式
    "testEveryFormatIsOnTheMenuAndReachesTheRealPasteboard",
    "testDefaultCopyIsTSVWithHeaderWithoutAnyEscapingDamage",
    "testEscapingSurvivesTheRealCopyPath",
    "testInsertCopyPointsAtTheTableBeingBrowsed",
    "testInsertCopyWithoutASourceTableSaysPlaceholderInsteadOfGuessing",
    "testEmptySelectionLeavesThePasteboardUntouched",
    "testCopyNeverLeavesAFileOnDisk",
    # 第六批（v0.3.0 数据库运维面第二跳 · FR-STD-DB-RES-007）：客户端排序
    "testEveryHeaderCellIsSortableAndAClickLandsOnItsOwnColumn",
    "testClickingTheHeaderCyclesAscendingDescendingAndBackToServerOrder",
    "testNullsStayAtTheEndInBothDirections",
    "testShiftClickAddsASecondaryKeyWithoutLosingThePrimary",
    "testShiftClickOnTheSecondaryKeyFlipsThenRemovesOnlyThatKey",
    "testClickingTheEmptyHeaderAreaChangesNothing",
    # 第七批（v0.3.0 数据库运维面第三跳 · FR-STD-DB-RES-008）：客户端筛选
    "testBarIsAlwaysPresentAndAddingAWaitingConditionKeepsEveryRow",
    "testTheColumnPopupChangesWhichColumnIsFiltered",
    "testTheOperatorPopupSwitchesContainsNotContainsAndEmptiness",
    "testTypedValueFiltersLiveAndKeepsTheEditingSession",
    "testCaseSensitiveToggleChangesWhichRowsMatch",
    "testMultipleConditionsAreAndedAndRemovingThemRestoresServerOrder",
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
print(f"✓ {total} 条都真跑过（七批）、都以 passed 收尾、没有跳过")
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
    "App/Views/ObjectTreeView.swift": (
        ("@State private var hoverBox = HoverBox()",
         "悬停行不再存进那个**无观察者**的盒子 ⇒ 鼠标停着不动界面会自己闪（2026-09-24 那次）"),
        ("RowMouseCatcher(",
         "每一行不再挂自己的鼠标捕获器 ⇒ 右键与「零等待选中」都会退回旧路"),
        ("makeMenu: {",
         "行里不再现建那一份菜单 ⇒ 会退回「整树一份 + 按列表行解析」那种错行"),
        ("object: row.object",
         "菜单的目标不再是**这一行自己的对象** ⇒ 会退回按悬停 / 上次选中解析"),
        # 反向那半（整树兜底菜单 `menuTargetObject` / `ObjectTreeMenuTarget.resolve(` 不许回来）由
        # `Tests/ObjectTreeRowMenuConventionTests.swift` 与 `Tests/ObjectTreeMenuConventionTests.swift`
        # 的 `XCTAssertFalse` 钉住 —— 这个脚本只支持「在场」形状，别把它写成第二个判据。
    ),
    "App/Views/ObjectTreeContextMenu.swift": (
        ("static func items(",
         "菜单内容不再有唯一入口（判据与界面读的会是两份东西）"),
        ("ObjectTreeActions.isAvailable(.", "菜单项的呈现不再由 Core 的规则决定（视图里会另写一份类型判断）"),
        ("ObjectTreeActions.hasContextMenu(row.object.kind)",
         "「这一行有没有菜单」不再问 Core 的 `menuKinds`"),
    ),
    "TestsUISnapshot/ObjectTreeContextMenuProbeTests.swift": (
        ("VStack(alignment: .leading, spacing: 6) {",
         "快照的容器不再由判据那一侧加 ⇒ 兄弟节点叠成一行，图上看着像「菜单只有一个条目」"),
    ),
    "App/Views/ObjectTreeRows.swift": (
        ("static func visibleRows(", "可见行不再是产品自己摊平出来的那一份（探针拿它当输入）"),
    ),
    "Core/ObjectTreeActions.swift": (
        ("public static let menuKinds: Set<DatabaseObject.Kind> = [",
         "「哪些节点类型该有右键菜单」不再在 Core 里单点定义（漏一个就判不出来了）"),
    ),
    # 第五批（`FR-STD-DB-RES-006`）：探针点的必须是**产品那份菜单与那条写剪贴板的路**。
    # 第六批（`FR-STD-DB-RES-007`）：再加表头点击那条路 —— 同一个文件，**一个键**（重复的键会让
    #   Python 字典静默丢掉先出现的那一份，第五批三条判据就白钉了）。
    "App/Views/ResultGrid.swift": (
        ("for format in ResultClipboard.Format.allCases {",
         "「复制为…」子菜单不再按格式枚举现建 ⇒ 少一档格式用户就点不到，探针也就量成了别的菜单"),
        ("pasteboard.setString(text, forType: .string)",
         "复制不再写系统剪贴板（改成落文件 / 只打日志，用户粘贴到的就是旧内容）"),
        ("tableName: copySourceTable?.name ?? ResultClipboard.placeholderTableName,",
         "复制的 INSERT 不再用来源表名 ⇒ 贴回库里的语句指向 table_name 这张不存在的表"),
        ("final class SortableHeaderView: NSTableHeaderView",
         "表头退回裸 `NSTableHeaderView` ⇒ 认不出「点的是哪一列、有没有按 Shift」，多列排序又会退回读 `sortDescriptors.first`"),
        ("if let header = tableView.headerView as? SortableHeaderView, let click = header.takeClick()",
         "派发不再问表头记下的那一击 ⇒ Shift 加次要键时翻的是老主键（多列排序加不上新列）"),
        ("onClick?(column, clickedAdditively)",
         "表头认得出列号却不派发 ⇒ 表头点击只剩 AppKit 那条随版本飘的路"),
        ("lastDisplayedRows != rows",
         "显示内容变更退回「首末行摘要」判断 ⇒ 取消排序后表格不重载，界面上留着旧顺序"),
    ),
    "App/Views/ResultTableView.swift": (
        ("copySourceTable: sourceTable",
         "结果区不再把来源表交给表格 ⇒ 复制 INSERT 只能落占位表名（而来源表本来就是它手里的事实）"),
        # 第六批（`FR-STD-DB-RES-007`）：表头点击真的接到状态层。
        ("gridState.toggleSort(columnIndex: columnIndex, additive: additive)",
         "表头点击不再交给状态层（排序循环只活在 Core 里，点表头会变成「什么都没发生」）"),
        # 第七批（`FR-STD-DB-RES-008`）：筛选条与「+ 加条件」入口默认在场。
        ("if !result.columns.isEmpty {",
         "筛选条退回 `isClientViewActive` 才渲染 ⇒ 没排过序的用户永远加不了第一个筛选条件（死路）"),
        ("isClientViewActive: gridState.isClientViewActive,",
         "条拿不到「现在有没有客户端操作」⇒ 提示要么不出现、要么一进来就喊"),
    ),
    "App/Views/ResultClientViewBar.swift": (
        ("ResultFilterPopup(",
         "列 / 运算符退回 SwiftUI `Menu`（菜单项要到弹出那一刻才建，离屏探针量不到 ⇒ 换列换运算符又只剩人点）"),
        ("titles: ResultFilterOperator.allCases.map(filterOperatorLabel)",
         "运算符候选不再来自 Core 的 allCases（少一档用户就选不到，判据也量不到这一档）"),
        ("if isClientViewActive {",
         "R-21 提示不按状态判断 ⇒ 条默认在场之后每次查询都喊一句「仅对已加载的行生效」"),
    ),
    "Core/ResultView.swift": (
        ("public var isPending: Bool { op.requiresValue && value.isEmpty }",
         "「还没填值」的概念消失 ⇒ 点「+」那一刻 contains \"\" 会把整张表清空（用户什么都没输入就先丢光行）"),
        ("let effective = filters.filter { !$0.isPending }",
         "筛选不再跳过待填条件 ⇒ 刚加的那条当场筛掉所有行"),
        ("case (true, false):\n                        return descriptor.nullsFirst",
         "NULL 的先后不再只由 nullsFirst 决定 ⇒ 降序时 NULL 会跑到最前面（NULL 位置固定这条就没钉住）"),
    ),
    "App/Views/TitleBarSearchField.swift": (
        ("final class TitleBarSearchBoxView: NSView",
         "整框不再是 AppKit 视图 ⇒ 命中测试又会被 SwiftUI 那层接走，可见框里的留白重新点不动（T-20261002-027 二次复测打回后的结构性换法）"),
        ("final class TitleBarSearchFieldView: NSTextField",
         "输入框不再是自己的 `NSTextField` ⇒ 非活动窗口的第一击（`acceptsFirstMouse`）没处放"),
        ("override func mouseDown(with event: NSEvent)",
         "整框不再自己接留白点击 ⇒ 那几处重新变成「点上去没反应」"),
        ("DOYAH_SEARCHBOX_PROBE",
         "真窗口命中地图探针没了 ⇒ 判据又只能量手工搭的宿主（第 162 轮就是在那里看偏的）"),
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

for probe in ("TerminalInteractionProbeTests", "MultiCursorProbeTests", "ObjectTreeContextMenuProbeTests",
              "TitleBarSearchClickProbeTests", "ResultCopyProbeTests", "ResultSortProbeTests",
              "ResultFilterProbeTests"):
    if not os.path.exists(os.path.join(root, f"TestsUISnapshot/{probe}.swift")):
        failures.append(f"TestsUISnapshot/{probe}.swift 不在盘上")

if failures:
    for item in failures:
        print(f"✗ {item}")
    sys.exit(1)
print("✓ 源锚点都在：路由判定在 Core、视图真的问过它、字节从 TerminalInput 出去、裸光标由视图自己记、"
      "菜单由 Core 的规则决定且悬停行存在无观察者的盒子里")
PY

echo
echo "==> 完成：证据日志在 ${OUT}/"
echo "    本入口判住的十七条："
echo "    · §1 FR-STD-WS-TOOL-001 鼠标上报（真 PTY 上的 SGR 报文：右下角点击列行变大、拖动 32、滚轮 64、⌥ 归本机）"
echo "    · §1 FR-STD-WS-TOOL-001 方向键 DECCKM（?1h 时 ^[OA、复位后 ^[[B）"
echo "    · §1 FR-STD-WS-TOOL-001 右键菜单（五项齐备且指向产品自己的动作、接管 + ⌥ 时按钮码 10 转发）"
echo "    · §3 FR-STD-WS-EDIT-016 ⌥⌘D 选下一处（三处同内容都进选区、打字三处一起改、一次撤销全回退、光标不漂）"
echo "    · §3 FR-STD-WS-EDIT-016 ⌥⌘↑ / ↓ 加光标（第 109 轮修的缺陷：加出来的光标必须真的在；打字 / ⌫ / 回车逐个生效；Esc 收敛）"
echo "    · §3 FR-STD-WS-EDIT-016 ⌥ 拖拽列选（逐行一段、短行夹到行尾、绝不跨换行、一次撤销）"
echo "    · §4 FR-STD-DB-META-012 逐行菜单**内容**（七类节点各一张图；动作项与 Core 的规则双向对账；非服务器行不许出现服务器菜单项）"
echo "    · §4 FR-STD-DB-META-012 菜单作用在**哪一行**（悬停优先 / 盒子空退回选中项 / 表头与无菜单节点 / 都不成立时的空菜单）"
echo "    · §4 FR-STD-DB-META-012 菜单确定性与跟随行（同一行两次逐字节一致、不同行必须画成两个样子）"
echo "    · §1 FR-STD-WS-UI-006 标题栏搜索栏点击地图（可见框内 21 点全部落到整框 / 输入框 / 清空按钮；上一轮那版同期必须判红）"
echo "    · §1 FR-STD-WS-UI-006 留白点按下把键盘交给输入框（左留白 + 上下留白逐点：第一响应者 = 输入框或它的字段编辑器）"
echo "    · §1 FR-STD-WS-UI-006 清空按钮三态（空词隐藏 / 有词显示 / 点它清空并回调）"
echo "    · §1 FR-STD-WS-UI-006 打字之后按回车那个词真的交出去（打字不许把 AppKit 的编辑会话收掉 —— 2026-10-02 晚的真缺陷）"
echo "    · §1 FR-STD-WS-UI-006 修前对照（装饰参与命中测试的那份框必须判红 —— 这条判据量得出来）"
echo "    · §3.4 FR-STD-DB-RES-006 复制为多格式（真视图 + 真菜单 + 真系统剪贴板：四档格式都在菜单里、默认 ⌘C = 带表头 TSV、转义不乱、只复制选中的行、INSERT 指向正在浏览的表、空选中不动剪贴板、不落文件）"
echo "    · §3.4 FR-STD-DB-RES-008 客户端筛选（真控件点击 + 真字段编辑器打字：条默认在场、加条件不丢行、换列换运算符、逐字打值、大小写开关、多条件 AND、删光条件后入口仍在）"
echo "    · §3.4 FR-STD-DB-RES-007 客户端排序（真表头点击 + 真 AppKit 跟踪循环：升 → 降 → 取消三档、数值按数值比、NULL 两种方向都留末尾、Shift 加 / 翻 / 删次要键、点空白处不动、排序不改列宽）"
