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

边界（如实登记）：本判据判的是**接线在位**（文件里有没有这条线、位置对不对），
不等于「界面上点得动」—— 真开 PTY 的行为由 App 侧探针（`TerminalTabsProbeTests`，
`DOYAH_UI_SNAPSHOT=1` 时跑）承担，观感由快照 `terminal-tabs-bar{,-dark}-{zh,en}` 与
`manual-check-terminal-strip-*` 读图 / 像素判据承担，真人点验承担主诉场景（一个页签跑
`dsh-tui`、另一个执行命令，互不干扰）。

判据自己的证据：`--self-test` **13 例**（红 / 绿成对；夹具一律在临时目录；末例核对真仓库十三份
文件逐字节未变）。

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
    ],
    STRIP: [
        ("工具条那一行是独立视图（能单独离屏渲染）", "struct LowerPaneTabStrip"),
        ("页签头挂进这一行", "TerminalTabsBar(terminal: terminal)"),
        ("右侧那排按钮的唯一画法", "private func iconButton("),
        ("重启按钮指向当前页签", "id: terminal.tabs.activeID"),
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

# F：右侧那排按钮（口径①：右侧按钮一概不动）—— 少一个就是「顺手把它挪了」。
#
# **第 96 轮（`L-89` ㈡ ③）补齐了「五个动作按钮」的完整口径 + 反向对账**：
#   · 清单那一行的人话数的是**五个**（清空日志 / 最大化 / 恢复 / 收起 / 重启 shell）；
#     折叠态那枚**向上展开**箭头是同一位置的第 6 个符号（折叠时才出现）—— 一并登记，
#     否则「折叠态的恢复入口」就成了没人管的按钮。
#   · 「一个不少」要**两个方向都判**才成立：少了要报（正向），**多画一个没登记的**也要报（反向）。
#     反向靠 `RIGHT_SIDE_CALL_SITES` 的棘轮：这一行里 `iconButton(` 的调用点数是登记的。
RIGHT_SIDE_BUTTONS = ["rectangle.compress.vertical", "rectangle.expand.vertical",
                      "chevron.down", "chevron.up", "trash", "arrow.clockwise"]

# 反向对账的棘轮：`App/Views/LowerPaneTabStrip.swift` 里 `iconButton(` 的**调用点**数。
# 6 个符号由 5 个调用点画出（最大化 / 恢复是同一个调用点上的三目表达式，展开箭头在折叠那一支）。
# 新增按钮必须**同时**改这里与登记表 —— 只改一处就判红（这正是「同一件事有两份手抄清单就有两个出口」的解药）。
RIGHT_SIDE_CALL_SITES = 5

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
    bar = strip.find("TerminalTabsBar(terminal: terminal)")
    spacer = strip.find("Spacer(minLength: 8)")
    if bar >= 0 and spacer >= 0 and bar > spacer:
        issues.append(Issue(
            f"{STRIP}[口径①左侧]",
            "页签头画在了 `Spacer(minLength: 8)` **之后** —— 那是工具条右侧（口径①写死「左侧」）"
        ))
    elif bar >= 0 and spacer >= 0:
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


def check_docs(root: pathlib.Path) -> tuple[list[Issue], int, int]:
    """E：口径锚点（需求提出者的原话场景 —— 判据的立足点）。

    返回 `(issues, hits, expected)`：`QUEUE` 是**本机台账**（`.gitignore` 内、只在主开发机上）
    ⇒ 不在盘上时**这一处锚点如实跳过 + 高声提示**、既不算命中也不判红（口径出处 =
    `AGENT-SPEC.md` §9 第 147 条 ④），`expected` 跟着减 —— 否则「干净克隆」会被读成
    「口径被删了」。`PLAN` 是入库件，缺它照旧判红。
    """
    issues: list[Issue] = []
    hits = 0
    expected = 0
    for relative, pattern, note in (
        (PLAN, PLAN_ANCHOR, "发布计划的验收场景表"),
        (QUEUE, QUEUE_ANCHOR, "队列 L-84 行的需求原话"),
    ):
        text = _read(root, relative)
        if not text.strip():
            if relative == QUEUE:
                print(f"⚠ 跳过口径锚点：{relative} 不在盘上（本机台账，只在主开发机上 —— "
                      f"干净克隆 / 并行工作树 / 另一平台；跳过 ≠ 通过）")
                continue
            issues.append(Issue(relative, "文档不在盘上"))
            expected += 1
            continue
        expected += 1
        if re.search(pattern, text):
            hits += 1
        else:
            issues.append(Issue(relative, f"{note}里的口径被删了（判据失去立足点）"))
    return issues, hits, expected


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

    doc_issues, doc_hits, doc_expected = check_docs(root)
    issues += doc_issues
    stats["docHits"] = doc_hits
    stats["docExpected"] = doc_expected

    # G：空跑防护 —— 「判据自己失效」比「发现不了」更危险。
    expected_api = sum(len(group) for group in API_ANCHORS.values())
    expected_app = sum(len(anchors) for anchors in APP_ANCHORS.values()) + len(RIGHT_SIDE_BUTTONS) + 2
    if stats["apiSites"] < expected_api:
        issues.append(Issue("空跑防护", f"API 锚点只命中 {stats['apiSites']}/{expected_api} 处"))
    if stats["appSites"] < expected_app:
        issues.append(Issue("空跑防护", f"界面接线锚点只命中 {stats['appSites']}/{expected_app} 处"))
    if stats["keys"] < len(KEYS):
        issues.append(Issue("空跑防护", f"文案键只有 {stats['keys']}/{len(KEYS)} 个中英齐"))
    if stats["docHits"] < stats["docExpected"]:
        issues.append(Issue("空跑防护", f"口径锚点只命中 {stats['docHits']}/{stats['docExpected']} 处"))
    return issues, stats


FIXTURE_FILES = [MODEL, TABLE, TESTS, PLAN, QUEUE,
                 PANE, SESSION, TABS_MODEL, TABS_BAR, LOWER_PANE, STRIP, TERMINAL_VIEW, PROBE]


def _digests(root: pathlib.Path) -> dict[str, str]:
    return {relative: hashlib.sha256((root / relative).read_bytes()).hexdigest()
            for relative in FIXTURE_FILES}


def _fixture(base: pathlib.Path) -> pathlib.Path:
    """把判据盯着的十三份文件原样拷进临时目录（**只在副本上写坏**）。"""
    temp = pathlib.Path(tempfile.mkdtemp(prefix="terminal-tabs-selftest-"))
    for relative in FIXTURE_FILES:
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
    # 本机台账不在盘上（干净克隆 / 并行工作树 / 另一平台）⇒ 本族自检**如实跳过 + 高声提示**、
    # 退出 0（口径出处 = `AGENT-SPEC.md` §9 第 147 条 ④）：夹具里那十三份文件含**队列台账**
    # （`_fixture` / `_digests` 都要读它），硬跑必崩 —— 而崩在干净克隆上与当轮改动无关。
    if not (root / QUEUE).is_file():
        print("⚠️ 自测需要 %s（本机台账）—— 干净克隆上跳过" % QUEUE)
        return 0

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
    with_fixture = _fixture(root)
    _rewrite(with_fixture / QUEUE, "tab 头切换", "页签切换")
    issues, _ = run(with_fixture)
    record(any("口径被删" in str(issue) for issue in issues),
           "例 6（E）队列里的需求原话被改写 ⇒ 报红", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 7（F · 红路）：把页签头挪到 `Spacer` **之后** —— 那它就落在工具条右侧了（口径①说左侧）。
    with_fixture = _fixture(root)
    bar_line = "                TerminalTabsBar(terminal: terminal)\n"
    spacer_line = "            Spacer(minLength: 8)\n"
    moved = _rewrite(with_fixture / STRIP, bar_line, "")
    moved = moved and _rewrite(with_fixture / STRIP, spacer_line, spacer_line + bar_line)
    issues, _ = run(with_fixture)
    record(moved and any("口径①左侧" in str(issue) for issue in issues),
           "例 7（F）页签头被挪到 Spacer 之后 ⇒ 报红", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 8（F · 红路）：右侧那个「重启 shell」按钮被顺手换掉 ⇒ 报红（口径①：右侧按钮不动）。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / STRIP, 'iconButton("arrow.clockwise"', 'iconButton("arrow.triangle.2.circlepath"')
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
    record(before == after, "例 13 真仓库十三份文件逐字节未变",
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
