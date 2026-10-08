#!/usr/bin/env python3
"""终端多会话（页签）的判据（队列 L-84，闭环第 9 项）。

存在的理由（真现场）
--------------------
需求提出者 2026-09-29 把「底部 terminal 只支持单终端」提为**刚需**，原话：「一个 terminal 在执行
dsh-tui，遇到要执行命令只能去开系统终端，**违背了我这个软件的初衷**」。多会话的坑几乎全在
**顺序与归属**上 —— 新页签插在哪、关掉当前页签谁接管、⌘1…9 落到哪个会话、重命名之后标题怎么
回落、最后一个页签能不能关 —— 而这几件事**不需要真开一个 shell 就能穷举**，所以判据判的是
「这些判断真的在 Core 里、且被单测逐组钉住」，不是「界面上看起来有页签」。

判据（任一不过即失败）
----------------------
A. **Core 模型在位**：`Core/TerminalTabs.swift` 每个 API 锚点在盘上（逐条正则，少一条点名），
   且**六个行为组**（新建 / 关闭 / 切换 / 标题推导 / 关闭确认 / 按键映射）各自的方法一个不少。
B. **Core 不出用户可见文案**：该文件的**代码行**里不许出现中文字面量（R-45：人话走语言表）。
C. **文案键中英都在**：页签那一族键逐个在 `Core/Localization.swift` 的语言表里同时有简中与英文
   （少一个 = 英文界面掉回中文）。
D. **单测逐组钉住**：`Tests/TerminalTabsTests.swift` 里六个行为组的用例锚点必须在，且用例总数
   不低于下限（防「测试文件被掏空」）。
E. **口径锚点**：需求提出者的原话场景（一个页签跑 `dsh-tui`、另一个执行命令）在
   `Docs/发布计划.md` 与队列 `L-84` 行里都在（口径被删 = 判据失去依据）。
F. **㈡ 界面接线在位**（第 82 轮补；**第 96 轮 `L-89` ㈡ ③ 扩**）：这一半在 App 侧
   （`App/TerminalPane.swift` / `App/TerminalTabsModel.swift` / `App/Views/TerminalTabsBar.swift` /
   `App/Views/LowerPaneTabStrip.swift` / `App/Views/LowerPaneView.swift` / `App/Views/TerminalView.swift` /
   `App/TerminalSession.swift`），**逐条对应口径①②④⑤**：
   每页签独立会话对象（不是「一个模型切屏」）、工具条**左侧**的页签头（在 `Spacer` 之前）、
   右侧那排按钮**六个符号一个不少**（清单数的是五个动作：清空日志 / 最大化 / 恢复 / 收起 / 重启 shell；
   第 6 个是折叠态的**展开**箭头 —— 恢复面板的唯一入口）、⌘T ⌘W ⌘1…9/⌘⇧[ ⌘⇧] 的接线点
   （判定仍只有 Core 一处）、双击重命名、关页签的二次确认、会话退出标记与「重启作用在当前页签上」。
   **第 96 轮补两处**：① 「一个不少」现在是**双向**对账 —— 登记过的符号少一个要报，
   **新画一个没登记的**也要报（棘轮 `RIGHT_SIDE_CALL_SITES`：这一行里 `iconButton(` 的调用点数是登记的），
   否则新按钮可以永远不进任何判据；② 工具条那一行抽成了**独立视图**（`LowerPaneTabStrip`），
   锚点随之搬过去 —— 抽出来是为了能**单独离屏渲染**，页面判据（探针四）才拍得到它。
   **另外**：App 侧探针（`TestsUISnapshot/TerminalTabsProbeTests.swift`）**六个用例**的锚点必须在位
   —— 前三个是真开 shell 的独立性与退出 / 确认链路，后三个是**版面**（页签头在左 / 右侧按钮位置不动的
   像素判据）、**按钮齐备**（按面板状态该有的有、不该有的没有）与**落点**（⌘1…9 / ⌘⇧[ ⌘⇧] / 改名
   落到对的会话，且改名不动那条 PTY）。

   **2026-10-08 改层级（人类主人原话：「其 tab 不能开在跟 problems / Output / terminal /
   debug console 平级的位置……而 terminal 页签自己的，也就是在 terminal 页签下再来一个工具条，
   左侧是每个细分 terminal 的 title，右侧是常用的工具按钮……最外层的 tab bar 最右侧就只保留
   最大化、恢复、最小化折叠按钮」）**：`T-1a` 把子终端件移出外层条，`T-1b` 归位 —— 于是本项多了
   **两条新判据**：① **层级断言**（`LAYER_FORBIDDEN`：外层条的**代码行**里不得再出现
   `TerminalTabsBar(` / `TerminalPaneStatus(` / `arrow.clockwise` / `"trash"`，逐件点名）；
   ② 「页签头在左」这条位置判据从 `LowerPaneTabStrip.swift` **搬到** `TerminalSubToolbar.swift`
   （外层条上已经没有页签头了，判据留原地只会永远红）。外层条右侧的符号登记表也随之缩到
   **四个窗口按钮**（3 个调用点）；清空日志归位在 `LowerPaneView.swift` 的问题 / 输出内容顶部
   （锚点 `logPaneToolbar`）。

边界（如实登记）：本判据判的是**接线在位**（文件里有没有这条线、位置对不对），
不等于「界面上点得动」—— 真开 PTY 的行为由 App 侧探针（`TerminalTabsProbeTests`，
`DOYAH_UI_SNAPSHOT=1` 时跑）承担，观感由快照 `terminal-tabs-bar{,-dark}-{zh,en}` 与
`manual-check-terminal-strip-*` 读图 / 像素判据承担，真人点验承担主诉场景（一个页签跑
`dsh-tui`、另一个执行命令，互不干扰）。

判据自己的证据：`--self-test` **13 例**（红 / 绿成对；夹具一律在临时目录；末例核对真仓库
**有盘的十四份**文件逐字节未变）。

⚠️ **已知先红（2026-10-08 实测，非本族引入）**：`Docs/design/开发循环-任务队列.md` **全仓不存在**
（`git log --all` 无此路径）⇒ 例 1（绿路基线）与「口径锚点 2 处」这一条会报红，
`--self-test` 的退出码因此是 1。修它要一份含 `**L-84** … tab 头切换` 的队列文档 ——
`Docs/` 归前门，不在本机组手里。**判据不掩盖这件事**：如实报红，缺文件也不许当通过。

用法：
    python3 Scripts/check-terminal-tabs.py              # 校验（闭环第 9 项）
    python3 Scripts/check-terminal-tabs.py --self-test  # 门禁自己的证据（**13 例**）
"""

from __future__ import annotations

import hashlib
import pathlib
import re
import shutil
import sys
import tempfile

MODEL = "Core/TerminalTabs.swift"
TABLE = "Core/Localization.swift"
TESTS = "Tests/TerminalTabsTests.swift"
PLAN = "Docs/发布计划.md"
QUEUE = "Docs/design/开发循环-任务队列.md"

# F（㈡ 界面接线）：判据要盯的 App 侧文件。
PANE = "App/TerminalPane.swift"
SESSION = "App/TerminalSession.swift"
TABS_MODEL = "App/TerminalTabsModel.swift"
TABS_BAR = "App/Views/TerminalTabsBar.swift"
LOWER_PANE = "App/Views/LowerPaneView.swift"
TERMINAL_VIEW = "App/Views/TerminalView.swift"
# F（㈡ 界面接线 · 第 96 轮）：工具条那一行抽成了**独立视图**（原来长在 LowerPaneView 的 tabStrip 里）——
# 抽出来是为了能**单独离屏渲染**（探针四拿它做版面判据），所以锚点也跟着搬到这里。
STRIP = "App/Views/LowerPaneTabStrip.swift"
# F（㈡ 界面接线 · 2026-10-08 `T-1a`/`T-1b`）：子终端那几件（终端页签条 / 状态小字 / 清空日志 /
# 重启 shell）**不再长在外层页签条上** —— 终端页签条、状态小字、`refusalHint` 归到这一份
# **终端二级工具条**（挂在终端内容顶部），`trash` 归到问题 / 输出两页的内容顶部
# （`LowerPaneView.logPaneToolbar`），重启 shell 归 `T-2` 的四枚动作按钮。
# 「页签头在左侧」这条位置判据随之搬到这里（它现在只能在二级条上成立）。
SUB_TOOLBAR = "App/Views/TerminalSubToolbar.swift"
PROBE = "TestsUISnapshot/TerminalTabsProbeTests.swift"

# A：模型锚点。分六组，与 `FR-EDIT-29` 的判据逐条对应 —— 少一组就等于那条判据悬空。
API_ANCHORS = {
    "新建": ["public mutating func newTab"],
    "关闭": ["public func closeDecision", "public mutating func close(id: Int, force: Bool"],
    "切换": ["public mutating func select(id:", "public mutating func select(numbered",
             "public mutating func selectNext()", "public mutating func selectPrevious()"],
    "标题推导": ["public static func derive(fromExecutablePath", "public static func sanitize(",
                 "public var title: String?", "static let ellipsis"],
    "关闭确认": ["case needsConfirmation", "case canClose", "case lastTab", "case unknownTab",
                 "public var isShellInForeground"],
    "按键映射": ["public enum TerminalTabCommand", "public static func command(",
                 "public mutating func perform(_ command: TerminalTabCommand)"],
}

# D：单测锚点（每条一个行为组；用例总数下限）。
TEST_ANCHORS = {
    "新建": "testNewTabInsertsRightOfActiveAndActivatesIt",
    "关闭": "testCloseActiveTabHandsOverToRightNeighbour",
    "切换": "testSelectNextAndPreviousWrapAround",
    "标题推导": "testDeriveTitleStripsLoginShellDash",
    "关闭确认": "testCloseDecisionNeedsConfirmationForRunningProgram",
    "按键映射": "testCommandAcceptsShiftedBracketsAsWellAsPlainOnes",
}
TEST_FLOOR = 34

# C：页签那一族文案键（㈠ 登记、㈡ 使用）。
KEYS = [
    "terminalTabNew", "terminalTabClose", "terminalTabRename", "terminalTabExited",
    "terminalTabUntitled", "terminalTabCloseConfirmTitle", "terminalTabCloseConfirmMessage",
    "terminalTabCloseConfirmAction", "terminalTabLastTabHint", "terminalTabExitedCode",
    "terminalTabShortcutHint", "terminalTabRenameMessage",
]

# F：㈡ 的界面接线锚点（文件 → 每条口径一个锚点；少一条点名）。
APP_ANCHORS = {
    PANE: [
        ("每页签一个会话对象", "final class TerminalPane"),
        ("退出事件回填给协调器", "var onExitDetected: ((Int32) -> Void)?"),
        ("前台进程查询入口", "func foregroundProcessPath() -> String?"),
    ],
    SESSION: [
        ("问 PTY 谁是前台", "tcgetpgrp("),
        ("拿前台进程的可执行路径", "proc_pidpath("),
    ],
    TABS_MODEL: [
        ("面板级模型", "final class TerminalModel"),
        ("每个页签一条会话（切页签不动它）", "private var panes: [Int: TerminalPane]"),
        ("⌘T 的落点", "func newTab() -> Int"),
        ("关页签先过判定", "func requestClose(id: Int)"),
        ("确认之后真的关（force）", "close(id: id, force: true)"),
        ("双击重命名入口", "func beginRename(id: Int)"),
        ("重启作用在当前页签上", "func restart(id: Int, columns: Int, rows: Int)"),
        ("前台进程名轮询（标题来源）", "func refreshForegroundProcesses()"),
    ],
    TABS_BAR: [
        ("页签头视图在", "struct TerminalTabsBar"),
        ("双击在前、单击在后", ".onTapGesture(count: 2)"),
        ("已退出是写出来的字", "L(.terminalTabExited)"),
        ("最后一个页签的关闭按钮有说法", "L(.terminalTabLastTabHint)"),
    ],
    LOWER_PANE: [
        ("每个页签一个视图身份", ".id(terminal.tabs.activeID)"),
        ("关页签的二次确认挂在面板层", "terminal.pendingCloseTab"),
        ("重命名弹窗", "terminal.renamingTab"),
        ("工具条那一行挂进面板（独立视图）", "LowerPaneTabStrip(tab: tab,"),
        ("终端二级工具条挂进终端内容顶部（独立视图）", "TerminalSubToolbar()"),
        ("清空日志归位到问题 / 输出内容顶部", "logPaneToolbar"),
    ],
    STRIP: [
        ("工具条那一行是独立视图（能单独离屏渲染）", "struct LowerPaneTabStrip"),
        ("右侧那排按钮的唯一画法", "private func iconButton("),
    ],
    SUB_TOOLBAR: [
        ("终端二级工具条是独立视图（能单独离屏渲染）", "struct TerminalSubToolbar"),
        ("细分终端 title 挂在二级条左侧", "TerminalTabsBar(terminal: terminal)"),
        ("当前页签的状态小字在二级条右侧", "TerminalPaneStatus(pane: terminal.activePane)"),
    ],
    TERMINAL_VIEW: [
        ("按键交给 Core 判定", "TerminalTabs.command("),
        ("判出来的动作落到协调器", "tabs?.perform(command)"),
    ],
    PROBE: [
        ("主诉场景：两条独立会话 + 切页签不重启", "func testTwoTabsRunIndependentShellsAndSurviveTabSwitching"),
        ("退出 / 重启 / 先问一句 / 最后一个不许关", "func testExitRestartConfirmationAndLastTabRefusal"),
        ("页签头快照（已退出到像素上）", "func testTabStripSnapshotShowsThreeSessionsAndExitedMark"),
        ("版面：页签头在左 / 右侧按钮位置不动（像素）",
         "func testStripKeepsTabHeadersOnTheLeftAndRightButtonsInPlace"),
        ("右侧按钮按面板状态齐备（该有的有、不该有的没有）",
         "func testRightSideButtonsMatchThePanelState"),
        ("⌘1…9 / ⌘⇧[ ⌘⇧] / 双击改名落到对的会话",
         "func testNumberedSelectionAndRenameLandOnTheRightSession"),
    ],
}

# F：外层页签条右侧那排按钮（口径①：右侧按钮一概不动）—— 少一个就是「顺手把它挪了」。
#
# **第 96 轮（`L-89` ㈡ ③）**补齐了「五个动作按钮」的完整口径 + 反向对账；**2026-10-08
# （人类主人原话 + `T-1a`/`T-1b`）那一排**缩小到只剩窗口按钮**：人类主人要求「最外层的 tab bar
# 最右侧就只保留最大化、恢复、最小化折叠按钮」⇒ 清空日志 / 重启 shell 随 `T-1a` 移出，
# `T-1b` 已把它们归位（清空日志 → 问题 / 输出内容顶部；重启 shell → `T-2` 的四枚动作按钮，
# 那一侧至今**一个按钮都还没有**，等 `T-2` 落地时再补它的登记表与反向对账棘轮）。
#   · 折叠态那枚**向上展开**箭头仍登记 —— 它是「把面板恢复出来」的唯一入口。
#   · 「一个不少」要**两个方向都判**才成立：少了要报（正向），**多画一个没登记的**也要报（反向）。
#     反向靠 `RIGHT_SIDE_CALL_SITES` 的棘轮：这一行里 `iconButton(` 的调用点数是登记的。
RIGHT_SIDE_BUTTONS = ["rectangle.compress.vertical", "rectangle.expand.vertical",
                      "chevron.down", "chevron.up"]

# 反向对账的棘轮：`App/Views/LowerPaneTabStrip.swift` 里 `iconButton(` 的**调用点**数。
# 4 个符号由 3 个调用点画出（最大化 / 恢复是同一个调用点上的三目表达式，展开箭头在折叠那一支）。
# 新增按钮必须**同时**改这里与登记表 —— 只改一处就判红（这正是「同一件事有两份手抄清单就有两个出口」的解药）。
RIGHT_SIDE_CALL_SITES = 3

# F：**层级断言**（2026-10-08 人类主人原话：「其 tab 不能开在跟 problems / Output / terminal /
# debug console 平级的位置」）—— 外层页签条上**不得再出现**的子终端符号。它们各归其位：
# 页签条 / 状态小字在终端二级条，清空日志在问题·输出内容顶部，重启 shell 归 `T-2` 的四枚按钮。
# 只判「登记过的符号在不在」是不够的：子终端件**长回外层条**这条判据必须独立存在，否则
# 「平级」这件人类主人明确否掉的事可以悄悄回来。
LAYER_FORBIDDEN = [
    ("TerminalTabsBar(", "终端页签条"),
    ("TerminalPaneStatus(", "状态小字「已停止 / 出错」"),
    ("arrow.clockwise", "重启 shell"),
    ('"trash"', "清空日志"),
]

# E：口径锚点（需求提出者的原话场景 —— 判据的立足点）。
PLAN_ANCHOR = r"一个页签跑\s*`?dsh-tui`?[^\n]{0,60}另一个页签执行命令"
QUEUE_ANCHOR = r"\*\*L-84\*\*[^\n]{0,400}tab 头切换"

HAN = re.compile(r"[\u4e00-\u9fff]")
STRING_LITERAL = re.compile(r'"([^"\\]*(?:\\.[^"\\]*)*)"')


class Issue:
    def __init__(self, where: str, reason: str) -> None:
        self.where = where
        self.reason = reason

    def __str__(self) -> str:  # pragma: no cover - 只为打印
        return f"❌ {self.where}：{self.reason}"


def _read(root: pathlib.Path, relative: str) -> str:
    path = root / relative
    return path.read_text(encoding="utf-8") if path.is_file() else ""


def code_lines(text: str) -> list[tuple[int, str]]:
    """只留代码行（`//` 注释不算 —— 注释里必然有中文）。"""
    return [(number, line) for number, line in enumerate(text.splitlines(), 1)
            if not line.strip().startswith("//")]


def check_model(root: pathlib.Path) -> tuple[list[Issue], int]:
    """A + B：模型 API 锚点 + 「Core 不出用户可见文案」。"""
    issues: list[Issue] = []
    model = _read(root, MODEL)
    if not model.strip():
        return [Issue(MODEL, "模型文件不在盘上（判据取不到输入，不许当通过）")], 0
    sites = 0
    for group, anchors in API_ANCHORS.items():
        for anchor in anchors:
            if anchor not in model:
                issues.append(Issue(f"{MODEL}[{group}]", f"缺 API 锚点 `{anchor}`"))
            else:
                sites += 1
    for number, line in code_lines(model):
        for literal in STRING_LITERAL.findall(line):
            if HAN.search(literal):
                issues.append(Issue(
                    f"{MODEL}:{number}",
                    f"代码行里有中文字面量「{literal}」—— Core 只出逻辑，人话走语言表（R-45）",
                ))
                break
    return issues, sites


def _entry_body(text: str, key: str) -> str | None:
    """取出 `.key:` 后面那个数组字面量的内容（**按括号配对走、字符串里的括号不算**）。

    为什么要自己配一遍括号：语言表里有些文案**本身带方括号** —— 页签快捷键那一句就写着
    `⌘⇧[ / ⌘⇧]`。原来用非贪婪的 `\\[(.*?)\\]` 去切，会在文案里的 `]` 上提前收尾，
    于是英文译文「看不见」⇒ 判据报一条**假红**（第 82 轮实测：`.terminalTabShortcutHint`，
    它明明中英都在）。判据自己出错比漏判更糟 —— 所以这里改成能处理字符串字面量的扫描。
    """
    marker = "." + key + ":"
    start = text.find(marker)
    if start < 0:
        return None
    index = text.find("[", start + len(marker))
    if index < 0:
        return None
    depth = 0
    in_string = False
    escaped = False
    for position in range(index, len(text)):
        character = text[position]
        if in_string:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
            continue
        if character == '"':
            in_string = True
        elif character == "[":
            depth += 1
        elif character == "]":
            depth -= 1
            if depth == 0:
                return text[index + 1:position]
    return None


def check_keys(root: pathlib.Path) -> tuple[list[Issue], int]:
    """C：页签那一族键在语言表里中英都在。"""
    issues: list[Issue] = []
    table = _read(root, TABLE)
    if not table.strip():
        return [Issue(TABLE, "语言表不在盘上")], 0
    complete = 0
    for key in KEYS:
        body = _entry_body(table, key)
        if body is None:
            issues.append(Issue(TABLE, f"语言表里没有 `.{key}`"))
            continue
        missing = [name for name, token in (("简中", ".simplifiedChinese"), ("英文", ".english"))
                   if token not in body]
        if missing:
            issues.append(Issue(f"{TABLE}::.{key}", f"缺{'/'.join(missing)}译文（英文界面会掉回中文）"))
        else:
            complete += 1
    return issues, complete


def check_tests(root: pathlib.Path) -> tuple[list[Issue], int]:
    """D：六个行为组各自的用例锚点 + 用例总数下限。"""
    issues: list[Issue] = []
    tests = _read(root, TESTS)
    if not tests.strip():
        return [Issue(TESTS, "单测文件不在盘上（判据取不到输入，不许当通过）")], 0
    for group, anchor in TEST_ANCHORS.items():
        if anchor not in tests:
            issues.append(Issue(f"{TESTS}[{group}]", f"缺用例锚点 `{anchor}`（这一组的判据悬空了）"))
    count = len(re.findall(r"func test", tests))
    if count < TEST_FLOOR:
        issues.append(Issue(TESTS, f"用例只有 {count} 个、下限 {TEST_FLOOR} —— 测试被掏空了"))
    return issues, count


def check_app(root: pathlib.Path) -> tuple[list[Issue], int]:
    """F：㈡ 的界面接线。

    除了逐文件锚点，还判两条**位置/口径**（光有锚点挡不住「挂在右边」或「顺手挪走按钮」）：
    · 页签头必须在工具条的 `Spacer(minLength: 8)` **之前**（口径①「左侧」）；
    · 右侧那排按钮（最大化 / 恢复 / 收起 / 重启 shell）**一个都不能少**。
    """
    issues: list[Issue] = []
    sites = 0
    for relative, anchors in APP_ANCHORS.items():
        text = _read(root, relative)
        if not text.strip():
            issues.append(Issue(relative, "文件不在盘上（判据取不到输入，不许当通过）"))
            continue
        for label, anchor in anchors:
            if anchor in text:
                sites += 1
            else:
                issues.append(Issue(f"{relative}[{label}]", f"缺接线锚点 `{anchor}`"))

    strip = _read(root, STRIP)
    if not strip.strip():
        issues.append(Issue(STRIP, "文件不在盘上（判据取不到输入，不许当通过）"))
        return issues, sites

    # 位置判据（口径①「页签头在左侧」）：**2026-10-08 起它只能在终端二级条上成立** ——
    # 外层页签条上已经没有页签头了（子终端件整体移出，见 `T-1a`/`T-1b`）。
    sub = _read(root, SUB_TOOLBAR)
    if not sub.strip():
        issues.append(Issue(SUB_TOOLBAR, "文件不在盘上（判据取不到输入，不许当通过）"))
        return issues, sites
    bar = sub.find("TerminalTabsBar(terminal: terminal)")
    spacer = sub.find("Spacer(minLength: 8)")
    if bar < 0 or spacer < 0:
        issues.append(Issue(
            f"{SUB_TOOLBAR}[口径①左侧]",
            "取不到「页签头」或 `Spacer(minLength: 8)` —— 位置判据悬空了（两者都得在这份文件里）"
        ))
    elif bar > spacer:
        issues.append(Issue(
            f"{SUB_TOOLBAR}[口径①左侧]",
            "页签头画在了 `Spacer(minLength: 8)` **之后** —— 那是右侧（口径①写死「左侧」）"
        ))
    else:
        sites += 1

    # **层级断言**（2026-10-08 人类主人原话）：外层页签条上不得再出现子终端项。
    # 只看**代码行**（注释里提到这些名字是正常的 —— 路标注释正是搬走时要留的）。
    strip_code = "\n".join(line for _, line in code_lines(strip))
    for symbol, note in LAYER_FORBIDDEN:
        if symbol in strip_code:
            issues.append(Issue(
                f"{STRIP}[层级]",
                f"外层页签条上又出现了子终端项 `{symbol}`（{note}）—— 它属于终端二级条"
                f"（{SUB_TOOLBAR}）或问题 / 输出内容顶部，**不属于这一行**"
            ))
        else:
            sites += 1

    for symbol in RIGHT_SIDE_BUTTONS:
        if symbol not in strip:
            issues.append(Issue(
                f"{STRIP}[口径①右侧按钮不动]",
                f"右侧按钮 `{symbol}` 不见了 —— 口径①明说「右侧现有按钮一律不动」",
            ))
        else:
            sites += 1

    # 反向对账（第 96 轮补）：这一行里画按钮的**调用点**数必须等于登记值 + 1（定义那一处）。
    # 只判「登记过的符号在不在」是不够的 —— 新画一个没登记的按钮，正向那条一条都不会响。
    call_sites = strip.count("iconButton(")
    expected_call_sites = RIGHT_SIDE_CALL_SITES + 1
    if call_sites != expected_call_sites:
        issues.append(Issue(
            f"{STRIP}[口径①右侧按钮一个不少]",
            f"`iconButton(` 出现 {call_sites} 处，登记的是 {RIGHT_SIDE_CALL_SITES} 个调用点 + 1 处定义"
            f"（= {expected_call_sites}）—— 多画了没登记的按钮，还是绕开这个画法自己拼了一个？"
        ))
    else:
        sites += 1
    return issues, sites


def check_docs(root: pathlib.Path) -> tuple[list[Issue], int]:
    """E：口径锚点（需求提出者的原话场景 —— 判据的立足点）。"""
    issues: list[Issue] = []
    hits = 0
    for relative, pattern, note in (
        (PLAN, PLAN_ANCHOR, "发布计划的验收场景表"),
        (QUEUE, QUEUE_ANCHOR, "队列 L-84 行的需求原话"),
    ):
        text = _read(root, relative)
        if not text.strip():
            issues.append(Issue(relative, "文档不在盘上"))
            continue
        if re.search(pattern, text):
            hits += 1
        else:
            issues.append(Issue(relative, f"{note}里的口径被删了（判据失去立足点）"))
    return issues, hits


def run(root: pathlib.Path) -> tuple[list[Issue], dict[str, int]]:
    issues: list[Issue] = []
    stats: dict[str, int] = {}

    model_issues, api_sites = check_model(root)
    issues += model_issues
    stats["apiSites"] = api_sites

    key_issues, complete_keys = check_keys(root)
    issues += key_issues
    stats["keys"] = complete_keys

    test_issues, tests = check_tests(root)
    issues += test_issues
    stats["tests"] = tests

    app_issues, app_sites = check_app(root)
    issues += app_issues
    stats["appSites"] = app_sites

    doc_issues, doc_hits = check_docs(root)
    issues += doc_issues
    stats["docHits"] = doc_hits

    # G：空跑防护 —— 「判据自己失效」比「发现不了」更危险。
    expected_api = sum(len(group) for group in API_ANCHORS.values())
    expected_app = (sum(len(anchors) for anchors in APP_ANCHORS.values())
                    + len(RIGHT_SIDE_BUTTONS) + len(LAYER_FORBIDDEN) + 2)
    if stats["apiSites"] < expected_api:
        issues.append(Issue("空跑防护", f"API 锚点只命中 {stats['apiSites']}/{expected_api} 处"))
    if stats["appSites"] < expected_app:
        issues.append(Issue("空跑防护", f"界面接线锚点只命中 {stats['appSites']}/{expected_app} 处"))
    if stats["keys"] < len(KEYS):
        issues.append(Issue("空跑防护", f"文案键只有 {stats['keys']}/{len(KEYS)} 个中英齐"))
    if stats["docHits"] < 2:
        issues.append(Issue("空跑防护", f"口径锚点只命中 {stats['docHits']}/2 处"))
    return issues, stats


FIXTURE_FILES = [MODEL, TABLE, TESTS, PLAN, QUEUE,
                 PANE, SESSION, TABS_MODEL, TABS_BAR, LOWER_PANE, STRIP, SUB_TOOLBAR,
                 TERMINAL_VIEW, PROBE]


def _digests(root: pathlib.Path) -> dict[str, str]:
    """盘上**真有的**那几份的摘要。

    **缺文件不在这里算账**：`Docs/design/开发循环-任务队列.md` 目前全仓不存在（**先红**，归前门），
    而本函数在例 1 之前就会跑 —— 让它因为「一份文件不在盘上」直接 traceback，等于整族自测
    **一个例子都跑不了**（连红在哪都看不见）。缺文件由 `check_docs` 如实报红；这里只对盘上有的
    做逐字节对账。
    """
    return {relative: hashlib.sha256((root / relative).read_bytes()).hexdigest()
            for relative in FIXTURE_FILES if (root / relative).is_file()}


def _fixture(base: pathlib.Path) -> pathlib.Path:
    """把判据盯着的十四份文件原样拷进临时目录（**只在副本上写坏**）。

    盘上没有的那几份跳过（同 `_digests` 的理由：缺文件由 `check_docs` 报红，不该让自测连跑都跑不起来）。
    """
    temp = pathlib.Path(tempfile.mkdtemp(prefix="terminal-tabs-selftest-"))
    for relative in FIXTURE_FILES:
        if not (base / relative).is_file():
            continue
        target = temp / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(base / relative, target)
    return temp


def _rewrite(path: pathlib.Path, old: str, new: str) -> bool:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        return False
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    return True


def self_test(root: pathlib.Path) -> int:
    results: list[tuple[bool, str, str]] = []

    def record(ok: bool, label: str, detail: str = "") -> None:
        results.append((ok, label, detail))

    before = _digests(root)

    # 例 1（绿路 · 基线）：真仓库现在必须是通过的 —— 连绿路都不绿，下面几条谈不上有意义。
    issues, _ = run(root)
    record(not issues, "例 1（绿路基线）真仓库判据通过",
           "；".join(str(issue) for issue in issues[:3]))

    # 例 2（A · 红路）：拿掉一个 API 锚点 ⇒ 点名报红。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / MODEL, "public mutating func select(numbered", "public mutating func selectNumbered")
    issues, _ = run(with_fixture)
    record(any("select(numbered" in str(issue) for issue in issues),
           "例 2（A）API 锚点被拿掉 ⇒ 报红并点名", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 3（B · 红路）：Core 代码行里塞一句中文字面量 ⇒ 报红。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / MODEL, "public enum TerminalTabTitle {", 'public enum TerminalTabTitle {\n    static let bad = "终端"')
    issues, _ = run(with_fixture)
    record(any("中文字面量" in str(issue) for issue in issues),
           "例 3（B）Core 代码行出现中文字面量 ⇒ 报红", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 4（C · 红路）：语言表里删掉英文译文 ⇒ 报红（英文界面会掉回中文）。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / TABLE, '.terminalTabExited: [.simplifiedChinese: "已退出", .english: "Exited"]',
             '.terminalTabExited: [.simplifiedChinese: "已退出"]')
    issues, _ = run(with_fixture)
    record(any("缺英文" in str(issue) for issue in issues),
           "例 4（C）语言表缺英文译文 ⇒ 报红", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 5（D · 红路）：单测里一个行为组的锚点被改名 ⇒ 报红。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / TESTS, "func testDeriveTitleStripsLoginShellDash", "func testTitleDerivation")
    issues, _ = run(with_fixture)
    record(any("testDeriveTitleStripsLoginShellDash" in str(issue) for issue in issues),
           "例 5（D）行为组的用例锚点被改名 ⇒ 报红", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 6（E · 红路）：口径被删（队列 L-84 行里的需求原话被改写）⇒ 报红。
    # 队列文档目前**不在盘上**（先红，见文件头）—— 那就不假装跑得动：如实记一条红并说明原因，
    # 而不是让 traceback 把后面 7 个例子全带走。
    with_fixture = _fixture(root)
    if (with_fixture / QUEUE).is_file():
        _rewrite(with_fixture / QUEUE, "tab 头切换", "页签切换")
        issues, _ = run(with_fixture)
        record(any("口径被删" in str(issue) for issue in issues),
               "例 6（E）队列里的需求原话被改写 ⇒ 报红", "；".join(str(issue) for issue in issues[:3]))
    else:
        record(False, "例 6（E）队列里的需求原话被改写 ⇒ 报红",
               f"`{QUEUE}` 不在盘上（该文档全仓不存在）—— 这一例跑不动，不算通过")
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 7（F · 红路）：把页签头挪到 `Spacer` **之后** —— 那它就落在二级条右侧了（口径①说左侧）。
    with_fixture = _fixture(root)
    bar_line = "            TerminalTabsBar(terminal: terminal)\n"
    spacer_line = "            Spacer(minLength: 8)\n"
    moved = _rewrite(with_fixture / SUB_TOOLBAR, bar_line, "")
    moved = moved and _rewrite(with_fixture / SUB_TOOLBAR, spacer_line, spacer_line + bar_line)
    issues, _ = run(with_fixture)
    record(moved and any("口径①左侧" in str(issue) for issue in issues),
           "例 7（F）页签头被挪到 Spacer 之后 ⇒ 报红", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 8（F · 红路）：右侧那个「收起」按钮被顺手换掉 ⇒ 报红（口径①：右侧按钮不动）。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / STRIP, 'iconButton("chevron.down"', 'iconButton("chevron.forward"')
    issues, _ = run(with_fixture)
    record(any("右侧按钮" in str(issue) for issue in issues),
           "例 8（F）右侧按钮被挪走 ⇒ 报红", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 9（F · 红路）：协调器里「确认之后真的关」那条线被删 ⇒ 报红
    # （这正是第 82 轮探针先撞上的坑：确认了却关不掉）。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / TABS_MODEL, "close(id: id, force: true)", "close(id: id)")
    issues, _ = run(with_fixture)
    record(any("force" in str(issue) for issue in issues),
           "例 9（F）「确认之后真的关」被删 ⇒ 报红", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 10（F · 红路）：App 侧探针的主诉场景用例被改名 ⇒ 报红（证据链断）。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / PROBE, "func testTwoTabsRunIndependentShellsAndSurviveTabSwitching",
             "func testTwoTabs")
    issues, _ = run(with_fixture)
    record(any("主诉场景" in str(issue) for issue in issues),
           "例 10（F）探针的主诉场景用例锚点被改名 ⇒ 报红", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 11（F · 红路）：界面自己判定按键（不再交给 Core）⇒ 报红。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / TERMINAL_VIEW, "TerminalTabs.command(", "Self.tabCommandIgnoringCore(")
    issues, _ = run(with_fixture)
    record(any("Core 判定" in str(issue) for issue in issues),
           "例 11（F）按键判定离开 Core ⇒ 报红", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 12（F · 红路）：**多画一个没登记的按钮**（反向对账）⇒ 报红。
    # 这一条才是"一个不少"的另一半：正向只认登记过的符号在不在，新画的按钮它一条都不响。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / STRIP, "            Spacer(minLength: 8)\n",
             "            Spacer(minLength: 8)\n"
             "            iconButton(\"star\", help: L(.lowerPaneHide)) { }\n")
    issues, _ = run(with_fixture)
    record(any("一个不少" in str(issue) for issue in issues),
           "例 12（F）多画一个没登记的按钮 ⇒ 报红", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 13（反过来核一遍）：所有写坏都发生在副本上 —— 真仓库十三份文件必须逐字节未变。
    after = _digests(root)
    record(before == after, "例 13 真仓库（有盘的十四份）文件逐字节未变",
           "；".join(f"{name} 变了" for name in after if before[name] != after[name]))

    for ok, label, detail in results:
        print(f"{'✅' if ok else '❌'} {label}" + (f" —— {detail}" if detail and not ok else ""))
    failed = [label for ok, label, _ in results if not ok]
    if failed:
        print(f"❌ 自测失败：{len(failed)}/{len(results)} 例（{failed[0]} …）")
        return 1
    print(f"自测通过（{len(results)} 例）")
    return 0


def main(argv: list[str]) -> int:
    root = pathlib.Path(__file__).resolve().parent.parent
    if "--root" in argv:
        root = pathlib.Path(argv[argv.index("--root") + 1]).resolve()
    if "--self-test" in argv:
        return self_test(root)

    issues, stats = run(root)
    if issues:
        for issue in issues:
            print(issue)
        print(f"❌ 终端多会话（页签）判据不通过：{len(issues)} 条")
        return 1
    print(
        "✅ 终端多会话（页签）判据通过："
        f"Core API 锚点 {stats['apiSites']} 处 / 界面接线锚点 {stats['appSites']} 处"
        f" / 文案键 {stats['keys']} 个（中英齐）"
        f" / 单测 {stats['tests']} 例 / 口径锚点 {stats['docHits']} 处"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
