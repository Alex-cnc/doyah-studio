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
#
# ## 第三批（L-90 ㈡ 第 2 条，第 110 轮）：对象树逐行右键
#
# `TestsUISnapshot/ObjectTreeContextMenuProbeTests.swift` 判清单 §4 `FR-META-14` 那一行
# （「依次右键表 / 视图 / 列 / 服务器 / 数据库 / schema / 函数」）：菜单**内容**与**作用在哪一行**
# 两件事这一轮都搬进了 `App/Views/ObjectTreeContextMenu.swift`（一个静态 `@ViewBuilder` 入口 + 一个纯函数），
# 于是不需要鼠标事件、也不需要任何权限 —— 每类节点渲染一遍、拿「这一遍取到的文案集合」与
# `ObjectTreeActions.isAvailable` 的规则**双向**对账；作用行用产品自己摊平的
# `ObjectTreeRows.visibleRows` 喂 `ObjectTreeMenuTarget.resolve`。
# 老缺陷的回归钉 = 「非服务器那一行**不许**出现服务器菜单项」（点数据库弹服务器菜单那次）。
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
FILTER="TerminalInteractionProbeTests|MultiCursorProbeTests|ObjectTreeContextMenuProbeTests|TitleBarSearchClickProbeTests"
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
    if int(total) < 15:
        failures.append(
            f"只跑了 {total} 条 —— 四批十五条（鼠标上报 / DECCKM / 右键归属 / ⌥⌘D 多光标 /"
            " ⌥⌘↑↓ 加光标 / ⌥ 拖拽列选 / 逐行菜单内容 / 菜单作用行 / 菜单确定性与跟随行 /"
            " 点击地图 / 留白点给键盘 / 清空按钮三态 + 回车接线 / 打字后回车交词 / 修前对照 / 整框源锚点）应当都跑到"
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
print("✓ 十五条都真跑过、都以 passed 收尾、没有跳过")
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
              "TitleBarSearchClickProbeTests"):
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
echo "    本入口判住的十五条："
echo "    · §1 FR-EDIT-29 鼠标上报（真 PTY 上的 SGR 报文：右下角点击列行变大、拖动 32、滚轮 64、⌥ 归本机）"
echo "    · §1 FR-EDIT-29 方向键 DECCKM（?1h 时 ^[OA、复位后 ^[[B）"
echo "    · §1 FR-EDIT-29 右键菜单（五项齐备且指向产品自己的动作、接管 + ⌥ 时按钮码 10 转发）"
echo "    · §3 FR-EDIT-27 ⌥⌘D 选下一处（三处同内容都进选区、打字三处一起改、一次撤销全回退、光标不漂）"
echo "    · §3 FR-EDIT-27 ⌥⌘↑ / ↓ 加光标（第 109 轮修的缺陷：加出来的光标必须真的在；打字 / ⌫ / 回车逐个生效；Esc 收敛）"
echo "    · §3 FR-EDIT-27 ⌥ 拖拽列选（逐行一段、短行夹到行尾、绝不跨换行、一次撤销）"
echo "    · §4 FR-META-14 逐行菜单**内容**（七类节点各一张图；动作项与 Core 的规则双向对账；非服务器行不许出现服务器菜单项）"
echo "    · §4 FR-META-14 菜单作用在**哪一行**（悬停优先 / 盒子空退回选中项 / 表头与无菜单节点 / 都不成立时的空菜单）"
echo "    · §4 FR-META-14 菜单确定性与跟随行（同一行两次逐字节一致、不同行必须画成两个样子）"
echo "    · §1 FR-EDIT-37 标题栏搜索栏点击地图（可见框内 21 点全部落到整框 / 输入框 / 清空按钮；上一轮那版同期必须判红）"
echo "    · §1 FR-EDIT-37 留白点按下把键盘交给输入框（左留白 + 上下留白逐点：第一响应者 = 输入框或它的字段编辑器）"
echo "    · §1 FR-EDIT-37 清空按钮三态（空词隐藏 / 有词显示 / 点它清空并回调）"
echo "    · §1 FR-EDIT-37 打字之后按回车那个词真的交出去（打字不许把 AppKit 的编辑会话收掉 —— 2026-10-02 晚的真缺陷）"
echo "    · §1 FR-EDIT-37 修前对照（装饰参与命中测试的那份框必须判红 —— 这条判据量得出来）"
