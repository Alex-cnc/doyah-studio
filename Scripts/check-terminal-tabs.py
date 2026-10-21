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
   且**七个行为组**（新建 / 关闭 / 切换 / 标题推导 / 关闭确认 / 按键映射 /
   一键启动与重启）各自的方法一个不少。
B. **Core 不出用户可见文案**：该文件的**代码行**里不许出现中文字面量（NFR-ALL-GATE-RISK-037：人话走语言表）。
C. **文案键中英都在**：页签那一族键逐个在 `Core/Localization.swift` 的语言表里同时有简中与英文
   （少一个 = 英文界面掉回中文）。
D. **单测逐组钉住**：`Tests/TerminalTabsTests.swift` 里七个行为组的用例锚点必须在，且用例总数
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

   **`T-2` 片（2026-10-08，人类主人原话的下半句：「右侧是常用的工具按钮，比如**一键启动
   dsh-tui、Hermes，清除终端会话窗口内容，重启终端**等操作」）**：二级条右侧那四枚的判据分三层 ——
   ① **语义在 Core**：一键启动的两个预设（`TerminalLaunchCommand`：要敲的命令 + 新页签的名字）
      与「重启要不要先问一句」（`restartDecision`）各有锚点（A 组的第七组，另配单测组）；
   ② **四枚成对存在**（`SUB_TOOLBAR_ACTIONS`）：逐枚判 `accessibilityIdentifier` 与**同一枚按钮
      那一块**里的 `.help(` —— 四枚都是**图标按钮**（禁文字按钮），提示是用户唯一读得到的解释；
      外加**反向对账棘轮**（二级条里画了几枚必须等于登记表长度，多画一枚就判红）；
   ③ **行为读数**在另一份探针（`TestsUISnapshot/TerminalSubToolbarProbeTests.swift`）：
      一键启动起一条真会话（前台换人 + 有回显）/ 清屏只擦缓冲（行数归零、pid 不变）/
      重启先问一句再换 pid / 二级条左半变·右四分之一逐像素不变。

边界（如实登记）：本判据判的是**接线在位**（文件里有没有这条线、位置对不对），
不等于「界面上点得动」—— 真开 PTY 的行为由 App 侧探针（`TerminalTabsProbeTests`，
`DOYAH_UI_SNAPSHOT=1` 时跑）承担，观感由快照 `terminal-tabs-bar{,-dark}-{zh,en}` 与
`manual-check-terminal-strip-*` 读图 / 像素判据承担，真人点验承担主诉场景（一个页签跑
`dsh-tui`、另一个执行命令，互不干扰）。

判据自己的证据：`--self-test` **25 例**（红 / 绿成对；夹具一律在临时目录；末例核对真仓库
**有盘的十七份**文件逐字节未变）。

**2026-10-13 修（合册 `T-20261013-027` · 原单 `T-20261010-065` · 样本 68）**：① 注释不再当代码
—— 判定物一律先**剥注释**（`strip_comments`，字符串感知、等长替换 ⇒ 行号与列位都不动）；
② 位置判据改判**非注释上下文**里的出现；③ 反向棘轮改判剥注释后的**调用点**与**画法形状**
（二级条数 `Button {` 块数 —— 标识符换个前缀就绕不过去了）；④ Core 的「不出人话」认
`"\\u{7EC8}\\u{7AEF}"` 这类**转义**写法；⑤ 行尾 `//` 与 `/*…*/` 里的中文 / 被禁符号不再误伤；
⑥ **判定面与 `Package.swift` 现读对账**（面内未登记件承载子终端件 ⇒ 判红并点名）；
⑦ `TEST_FLOOR` 收到实测（42）并新增「用例函数体非空 + 断言下限」。未知参数一律 `rc=2`
（旧实现把 `--bogus` 吞掉照跑）。

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
import json
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
# F（`T-2` 片 · 2026-10-08）：二级条那四枚的**行为**由另一份探针承担 —— 它们真开 shell
# （一键启动起一条真会话、清屏读缓冲行数、重启读 pid），所以与快照同一条纪律：
# 取证才跑（`DOYAH_UI_SNAPSHOT=1`），用例锚点必须在位（判据塌了这一条就悬空）。
SUB_PROBE = "TestsUISnapshot/TerminalSubToolbarProbeTests.swift"

# A：模型锚点。分七组，与 `FR-STD-WS-TOOL-001` 的判据逐条对应 —— 少一组就等于那条判据悬空。
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
    # T-2 片（2026-10-08）：二级条右侧那四枚的**语义**也在 Core —— 一键启动的两个预设
    # （要敲的命令 + 新页签的名字）与「重启要不要先问一句」的判定。放在这里而不是视图里的
    # 理由写在 `TerminalLaunchCommand` 的注释里：三处各写一遍就会漂移。
    "一键启动与重启": ["public enum TerminalLaunchCommand", "public func restartDecision(for id: Int)"],
}

# D：单测锚点（每条一个行为组；用例总数下限）。
TEST_ANCHORS = {
    "新建": "testNewTabInsertsRightOfActiveAndActivatesIt",
    "关闭": "testCloseActiveTabHandsOverToRightNeighbour",
    "切换": "testSelectNextAndPreviousWrapAround",
    "标题推导": "testDeriveTitleStripsLoginShellDash",
    "关闭确认": "testCloseDecisionNeedsConfirmationForRunningProgram",
    "按键映射": "testCommandAcceptsShiftedBracketsAsWellAsPlainOnes",
    # T-2 片：一键启动的名字优先序（预设名 ＞ 前台进程名，用户重命名仍优先）+ 重启要不要问。
    "一键启动与重启": "testLaunchTitleWinsOverForegroundProcessButNotOverRename",
}
TEST_FLOOR = 42

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
        # F（T-2 片 · 2026-10-08）：右侧四枚动作各自的**落点**（点击交给协调器）。
        ("一键启动 dsh-tui 的落点", "terminal.launchTab(.dshTUI)"),
        ("一键启动 Hermes 的落点", "terminal.launchTab(.hermes)"),
        ("清除会话窗口内容的落点", "terminal.clearActiveBuffer()"),
        ("重启终端的落点（先问一句）", "terminal.requestRestart()"),
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
    # F（`T-2` 片）：二级条右侧那四枚的**行为**读数（真开 shell / 真读 pid / 真读缓冲行数）。
    SUB_PROBE: [
        ("一键启动真的起了一条会话（前台换人 + 有回显）",
         "func testLaunchButtonsStartRealSessionsAndNameTheirTabs"),
        ("清屏只擦缓冲、不杀进程（缓冲行数归零 / pid 不变）",
         "func testClearBufferWipesTheScreenButKeepsTheSession"),
        ("重启先问一句、确认之后 pid 换人",
         "func testRestartAsksFirstThenChangesTheProcessIdentifier"),
        ("二级条版面：title 在左 / 四枚在右（像素 + 左/右各一张）",
         "func testSubToolbarKeepsTitlesOnTheLeftAndFourButtonsInPlace"),
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

# F：终端二级工具条的**右侧那四枚常用动作**（`T-2` 片 · 2026-10-08 人类主人原话：「右侧是常用的
# 工具按钮，比如一键启动 dsh-tui、Hermes，清除终端会话窗口内容，重启终端等操作」）。
#
# 判据就是交付面里写死的那一条：**每个 `accessibilityIdentifier` 与**同一枚按钮那一块里的
# `.help(` 成对存在（4/4）**。为什么必须成对：这四枚是**图标按钮**（口径：不许文字按钮）——
# 提示（`.help`）与无障碍标签是用户**唯一**读得到的解释；少一个，界面上就多一枚
# 「没人知道按下去会发生什么」的图标。少 `.help(` 不影响编译、不影响观感，只有这条判据看着它。
SUB_TOOLBAR_ACTIONS = [
    ("terminal-launch-dsh-tui", "一键启动 dsh-tui"),
    ("terminal-launch-hermes", "一键启动 Hermes"),
    ("terminal-clear-buffer", "清除终端会话窗口内容"),
    ("terminal-restart", "重启终端"),
]

# 反向对账的棘轮（与 `RIGHT_SIDE_CALL_SITES` 同一个形状，数在 `check_app` 里）：二级条里
# `accessibilityIdentifier("terminal-…")` 的**枚数**必须正好等于登记表长度 ——
# 新画一枚没登记的按钮（例如第 5 枚）只改这一处就判红。

# E：口径锚点（需求提出者的原话场景 —— 判据的立足点）。
PLAN_ANCHOR = r"一个页签跑\s*`?dsh-tui`?[^\n]{0,60}另一个页签执行命令"
QUEUE_ANCHOR = r"\*\*L-84\*\*[^\n]{0,400}tab 头切换"

HAN = re.compile(r"[\u4e00-\u9fff]")
STRING_LITERAL = re.compile(r'"([^"\\]*(?:\\.[^"\\]*)*)"')


# ㈠（2026-10-13 · 合册 T-20261013-027 · 原单 T-20261010-065 · 样本 68）：**注释不是代码**。
# 旧实现有一整族「注释充数」的假绿 —— `if anchor in text` 认的是**原文子串**，于是
# 「把那一行注释掉」与「那一行在位」读数逐字相同（现场：API 锚点 / `iconButton(` 调用 /
# `.help(` / 语言表整条 / 单测用例锚点，五处一个长相）。修法 = 判定物一律先在**剥了注释**的
# 文本上取，且替换**等长**（行号与列位都不动 —— 位置判据要比 `find()` 的下标，不等长就全错）。
# 字符串字面量**按原样保留**：判定物里有一半是字符串里的记号（`"trash"` / `"terminal-…"`）。
UNICODE_ESCAPE = re.compile(r"\\u\{([0-9A-Fa-f]{1,6})\}")


def strip_comments(text: str) -> str:
    """把注释抹成**等长空格**（字符串感知、支持块注释嵌套）。

    为什么自己扫而不是上正则：Swift 里 `"// 不是注释"` 是字符串、`/* /* 嵌套 */ */` 合法，
    一行正则两面都会判错。等长替换的额外好处是**下标可比** —— 位置判据（页签头在 `Spacer`
    之前）拿到的偏移量与原文件一一对应。
    """
    out: list[str] = []
    index = 0
    length = len(text)
    in_line = False
    depth = 0
    in_string = False
    escaped = False
    while index < length:
        char = text[index]
        following = text[index + 1] if index + 1 < length else ""
        if in_line:
            out.append("\n" if char == "\n" else " ")
            in_line = char != "\n"
        elif depth > 0:
            if char == "*" and following == "/":
                depth -= 1
                out.append("  ")
                index += 2
                continue
            if char == "/" and following == "*":
                depth += 1
                out.append("  ")
                index += 2
                continue
            out.append("\n" if char == "\n" else " ")
        elif in_string:
            out.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
        elif char == '"':
            in_string = True
            out.append(char)
        elif char == "/" and following == "/":
            in_line = True
            out.append("  ")
            index += 2
            continue
        elif char == "/" and following == "*":
            depth = 1
            out.append("  ")
            index += 2
            continue
        else:
            out.append(char)
        index += 1
    return "".join(out)


def visible_han(literal: str) -> bool:
    """字面量里有没有中文 —— **转义也算**（㈣）。

    第 82 轮现场（样本 68 · P2）：`"\\u{7EC8}\\u{7AEF}"` 与 `"终端"` 是同一句话，
    而旧实现只认源码里的 U+4E00–9FFF 字面字符 ⇒ 转义写法**整条绕过**「Core 不出人话」。
    """
    if HAN.search(literal):
        return True
    for code in UNICODE_ESCAPE.findall(literal):
        if HAN.search(chr(int(code, 16))):
            return True
    return False


# ㈥（2026-10-13 · 合册 T-20261013-027 · 原单 T-20261010-065）：**判定面与 `Package.swift` 对账**。
#
# 旧实现的面 = **15 个写死路径**，与包清单**无对账** —— 现场（样本 68 · P4c/P4d）：新建
# `App/Views/Extra68.swift` 里写 `TerminalTabsBar(terminal:)`（子终端件）、或在
# `Core/Extra68Core.swift` 里写「终端」，判据读数与基线**逐字相同**（一声不响）。
# 面 = 包清单**现读**的 target 源码目录；登记的判定件必须在面内；面内**未登记**的文件不许
# 承载子终端件（每个符号的家写在 `CARRIER_OWNERS` 里）；面内文件数按**棘轮**（只许涨）。
PACKAGE = "Package.swift"
FACE_TARGETS = ["DoyahCore", "DoyahStudioApp", "DoyahCoreTests", "DoyahUISnapshotTests"]
# 面内 `.swift` 文件数的**下限**（2026-10-13 现读值；棘轮：只许涨不许跌 —— 缩面才是攻击面，
# 新增 `.swift` 是正常开发）。降这个数要同时改这里与提交信息里的理由。
FACE_FILE_FLOOR = {
    "Core": 214, "Plugins/Notes/Sources": 21, "App": 119,
    "Plugins/Notes/Views": 3, "Tests": 218, "TestsUISnapshot": 45,
}
# 「子终端件」的**家**：符号 → 允许承载它的文件（新文件不在名单里 ⇒ 判红并点名）。
# 这份名单**穷举过**（2026-10-13 现读；`TestsUISnapshot/QueryHistoryPaneProbeTests.swift` 那一处
# 是它为了拍「历史」段整块面板而真用到 `LowerPaneTabStrip` —— 是正当用法，登记在此）。
CARRIER_OWNERS = {
    "TerminalTabsBar(": [SUB_TOOLBAR],
    "TerminalPaneStatus(": [SUB_TOOLBAR],
    "LowerPaneTabStrip(": [LOWER_PANE, "TestsUISnapshot/QueryHistoryPaneProbeTests.swift"],
    "TerminalSubToolbar(": [LOWER_PANE],
    "TerminalLaunchCommand": [MODEL],
    "TerminalTabCommand": [MODEL],
    "restartDecision": [MODEL],
}
# NFR-ALL-GATE-RISK-037 的**先红基线**（面内未登记件的「Core 不出人话」那一面）：本仓 Core 目录现读 **67 / 214 份**
# 文件都有中文字面量 —— 那是 NFR-ALL-GATE-RISK-037 的**全局收口**（别单的活）。判据的做法不是放宽面，而是**把债记下来**：
# 台账里那份名单 = 允许仍然写中文的**历史件**；名单**双向判** —— 不在名单里而写了中文 ⇒ 判红
# （新件不许再添债）；在名单里却**不再**写中文 ⇒ 也判红（死豁免，防抄名单混过去）。
HAN_LEDGER = "Scripts/terminal-tabs-han-baseline.json"
# 判定面登记件（面内枚举时的「已登记」集合）—— `PLAN` / `QUEUE` 是 Docs 口径件、不在面内。
FACE_REGISTERED = [MODEL, TABLE, TESTS, PANE, SESSION, TABS_MODEL, TABS_BAR, LOWER_PANE,
                   STRIP, SUB_TOOLBAR, TERMINAL_VIEW, PROBE, SUB_PROBE]
# 二级条「右侧四枚」的**反向对账（画法形状）**：那一份文件里 `Button {` 的块数 = 登记枚数。
# 为什么数「块数」而不是数标识符前缀：现场（样本 68 · P8）—— 新画的第 5 枚只要把标识符写成
# `"terminal5-extra"`（不以 `terminal-` 开头），前缀计数就永远看不见它。
SUB_TOOLBAR_DRAWN_SHAPES = 4


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
    """只留代码行 —— **注释整条剥掉**（不只行首 `//`）。

    2026-10-13（合册 `T-20261013-027` · 原单 `T-20261010-065` · 样本 68 ㈤）：旧实现只丢
    「以 `//` 开头」的行 ⇒ ① **行尾注释**里的中文串被当成代码里的字面量（假阳）；②
    `/* arrow.clockwise 已随 T-1a 搬走 */` 这种**路标块注释**在层级断言里被当成真写了该符号
    （假阳）—— 而搬走时要留的正是这种路标。剥注释是按 Swift 的真语法走（字符串感知、等长替换），
    字符串字面量本身**保留**：判定物里有一半是字符串里的记号（`"trash"` / `"terminal-…"`）。
    """
    return [(number, line) for number, line in enumerate(strip_comments(text).splitlines(), 1)]


def check_model(root: pathlib.Path) -> tuple[list[Issue], int]:
    """A + B：模型 API 锚点 + 「Core 不出用户可见文案」。"""
    issues: list[Issue] = []
    model = _read(root, MODEL)
    if not model.strip():
        return [Issue(MODEL, "模型文件不在盘上（判据取不到输入，不许当通过）")], 0
    sites = 0
    code = strip_comments(model)
    for group, anchors in API_ANCHORS.items():
        for anchor in anchors:
            if anchor not in code:
                issues.append(Issue(f"{MODEL}[{group}]", f"缺 API 锚点 `{anchor}`"))
            else:
                sites += 1
    for number, line in code_lines(model):
        for literal in STRING_LITERAL.findall(line):
            if visible_han(literal):
                issues.append(Issue(
                    f"{MODEL}:{number}",
                    f"代码行里有中文字面量「{literal}」—— Core 只出逻辑，人话走语言表（NFR-ALL-GATE-RISK-037）",
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
    table_code = strip_comments(table)
    for key in KEYS:
        body = _entry_body(table_code, key)
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
    code = strip_comments(tests)
    for group, anchor in TEST_ANCHORS.items():
        if anchor not in code:
            issues.append(Issue(f"{TESTS}[{group}]", f"缺用例锚点 `{anchor}`（这一组的判据悬空了）"))
    count = len(re.findall(r"func test", code))
    if count < TEST_FLOOR:
        issues.append(Issue(TESTS, f"用例只有 {count} 个、下限 {TEST_FLOOR} —— 测试被掏空了"))
    # ⑧（2026-10-13）：锚点在位 ≠ 用例还在干活 —— 逐个行为组看**函数体**：
    # 空体（锚点还在、断言没了）或一条断言都没有（`#expect` / `XCTAssert` 全无），都判红。
    for group, anchor in TEST_ANCHORS.items():
        body = _function_body(code, anchor)
        if body is None:
            continue
        if not body.strip():
            issues.append(Issue(
                f"{TESTS}[{group}]", f"用例 `{anchor}` 的函数体是空的 —— 锚点还在、断言没了"))
        elif not re.search(r"#expect\(|XCTAssert", body):
            issues.append(Issue(
                f"{TESTS}[{group}]", f"用例 `{anchor}` 里一条断言都没有 —— 锚点还在、它什么都不验"))
    return issues, count




def _han_ledger(root: pathlib.Path) -> set[str] | None:
    """NFR-ALL-GATE-RISK-037 先红基线台账里的文件名集合（读不到 / 读不动 ⇒ `None` = 判红，不当通过）。"""
    text = _read(root, HAN_LEDGER)
    if not text.strip():
        return None
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        return None
    return {str(item) for item in data.get("coreFilesWithChineseLiterals", [])}


def _blocks(text: str, opener: str) -> list[str]:
    """取 `opener` 起的那一整段（**按括号配对走、字符串里的括号不算**）。"""
    found: list[str] = []
    index = 0
    while True:
        at = text.find(opener, index)
        if at < 0:
            return found
        index = at + len(opener)
        depth = 0
        in_string = False
        escaped = False
        for position in range(at + len(opener) - 1, len(text)):
            char = text[position]
            if in_string:
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == '"':
                    in_string = False
                continue
            if char == '"':
                in_string = True
            elif char in "([":
                depth += 1
            elif char in ")]":
                depth -= 1
                if depth == 0:
                    found.append(text[at:position + 1])
                    index = position + 1
                    break
        else:
            return found


def package_targets(root: pathlib.Path) -> dict[str, list[str]] | None:
    """包清单**现读**每个 target 的源码目录（面 = 声明面，不是判据手抄的清单）。"""
    text = _read(root, PACKAGE)
    if not text.strip():
        return None
    code = strip_comments(text)
    targets: dict[str, list[str]] = {}
    for opener in (".target(", ".executableTarget(", ".testTarget("):
        for block in _blocks(code, opener):
            name = re.search(r'name:\s*"([^"]+)"', block)
            if not name:
                continue
            base = re.search(r'path:\s*"([^"]+)"', block)
            sources = re.search(r"sources:\s*\[([^\]]*)\]", block)
            prefix = "" if base is None or base.group(1) == "." else base.group(1) + "/"
            if sources:
                dirs = [prefix + item.strip().strip('"')
                        for item in sources.group(1).split(",") if item.strip()]
            elif base is not None and base.group(1) != ".":
                dirs = [base.group(1)]
            else:
                dirs = [name.group(1)]
            targets.setdefault(name.group(1), []).extend(dirs)
    return targets


def face_dirs(targets: dict[str, list[str]]) -> list[str]:
    dirs: list[str] = []
    for name in FACE_TARGETS:
        for directory in targets.get(name, []):
            if directory not in dirs:
                dirs.append(directory)
    return dirs


def check_face(root: pathlib.Path, strict: bool = True) -> tuple[list[Issue], int]:
    """㈥：面（包清单现读的 target 源码目录）+ 面内未登记件不许承载子终端件。

    `strict=False` 只在自检夹具上跑（夹具是**修剪过的树**：面目录不全、文件数远低于下限）——
    只跳过「面目录必须在盘 / 文件数下限」这两条，**承载件与语义字面量那两条照跑**
    （新补的负例全靠它们）。
    """
    issues: list[Issue] = []
    sites = 0
    targets = package_targets(root)
    if targets is None:
        return [Issue(PACKAGE, "包清单不在盘上 —— 面对账取不到输入，不许当通过")], 0
    for name in FACE_TARGETS:
        if name not in targets:
            issues.append(Issue(PACKAGE, f"面里点名的 target 在包清单里找不到：`{name}`"))
        else:
            sites += 1
    dirs = face_dirs(targets)
    han_ledger = _han_ledger(root)
    hit_legacy: set[str] = set()
    for relative in FACE_REGISTERED:
        if not any(relative.startswith(directory + "/") for directory in dirs):
            issues.append(Issue(
                relative, f"登记的判定件落在**面外**（面 = {dirs}）—— 面与清单两边都得改"))
        else:
            sites += 1
    for directory in dirs:
        path = root / directory
        if not path.is_dir():
            if strict:
                issues.append(Issue(directory, "面目录不在盘上 —— 面被削了（包清单还声明着它）"))
            continue
        count = len(list(path.rglob("*.swift")))
        floor = FACE_FILE_FLOOR.get(directory)
        if floor is None:
            issues.append(Issue(
                directory, "这个面目录没在 `FACE_FILE_FLOOR` 里登记下限 —— 新面要连下限一起登记"))
        elif count < floor:
            issues.append(Issue(
                directory, f"面内 `.swift` 只剩 {count} 份（台账下限 {floor}）—— 面被削了"))
        sites += 1
        for file in sorted(path.rglob("*.swift")):
            relative = file.relative_to(root).as_posix()
            if relative in FACE_REGISTERED:
                continue
            code = strip_comments(file.read_text(encoding="utf-8", errors="ignore"))
            carried = [symbol for symbol in CARRIER_OWNERS
                       if symbol in code and relative not in CARRIER_OWNERS[symbol]]
            if carried:
                issues.append(Issue(
                    relative,
                    f"面内**未登记**的文件承载子终端件 `{carried[0]}`（它的家是 "
                    f"{CARRIER_OWNERS[carried[0]]}）—— 新件要么登记进判定面，要么别长在这儿"
                ))
            elif directory == "Core" or directory.startswith("Core/") \
                    or directory == "Plugins/Notes/Sources":
                # NFR-ALL-GATE-RISK-037：Core target 的代码行里不许有中文字面量（**转义写法也算**，见 `visible_han`）。
                # 不在先红基线名单里 ⇒ 判红；在名单里 ⇒ 记一笔（下面判「死豁免」）。
                found = [literal for literal in STRING_LITERAL.findall(code)
                         if visible_han(literal)]
                if found and (han_ledger is None or relative not in han_ledger):
                    issues.append(Issue(
                        relative,
                        f"面内未登记的件里出现中文字面量「{found[0]}」—— Core 只出逻辑、人话走语言表"
                        f"（NFR-ALL-GATE-RISK-037）；确有理由就登记进 `{HAN_LEDGER}` 的先红基线（连着理由一起）"
                    ))
                elif found:
                    hit_legacy.add(relative)
    if han_ledger is None:
        issues.append(Issue(HAN_LEDGER, "NFR-ALL-GATE-RISK-037 先红基线不在盘上 —— 这一面取不到输入，不许当通过"))
    else:
        sites += 1
        for relative in sorted(han_ledger):
            if relative in hit_legacy:
                continue
            # 只在「文件还在盘上」时判死豁免：夹具是修剪过的树，不在盘上的条目不算账。
            if (root / relative).is_file():
                issues.append(Issue(
                    HAN_LEDGER,
                    f"死豁免：`{relative}` 不再写中文字面量了 —— 从先红基线里删掉它（名单不许积灰）"))
    return issues, sites


def _function_body(code: str, name: str) -> str | None:
    """取 `func <name>(` 的函数体（**按花括号配对走、字符串里的花括号不算**）。"""
    at = code.find("func " + name + "(")
    if at < 0:
        return None
    brace = code.find("{", at)
    if brace < 0:
        return None
    depth = 0
    in_string = False
    escaped = False
    for position in range(brace, len(code)):
        char = code[position]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return code[brace + 1:position]
    return None


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
        code = strip_comments(text)
        for label, anchor in anchors:
            if anchor in code:
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
    # ㈡（2026-10-13 · 样本 68 · P9）：位置判据比的是**非注释上下文**里的下标。
    # 现场：把真页签头挪到 `Spacer(minLength: 8)` 之后、再在 Spacer 之前留一行**注释**写着同一串
    # ⇒ 旧实现（`sub.find(...)` 在原文上找）读到的是那行注释，读数与基线**逐字相同**。
    # `strip_comments` 是**等长**替换 ⇒ 剥注释后的下标与原文件一一对应，比对仍然成立。
    sub_code = strip_comments(sub)
    bar = sub_code.find("TerminalTabsBar(terminal: terminal)")
    spacer = sub_code.find("Spacer(minLength: 8)")
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
    strip_code = strip_comments(strip)
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
        if symbol not in strip_code:
            issues.append(Issue(
                f"{STRIP}[口径①右侧按钮不动]",
                f"右侧按钮 `{symbol}` 不见了 —— 口径①明说「右侧现有按钮一律不动」",
            ))
        else:
            sites += 1

    # 反向对账（第 96 轮补）：这一行里画按钮的**调用点**数必须等于登记值 + 1（定义那一处）。
    # 只判「登记过的符号在不在」是不够的 —— 新画一个没登记的按钮，正向那条一条都不会响。
    call_sites = strip_code.count("iconButton(")
    expected_call_sites = RIGHT_SIDE_CALL_SITES + 1
    if call_sites != expected_call_sites:
        issues.append(Issue(
            f"{STRIP}[口径①右侧按钮一个不少]",
            f"`iconButton(` 出现 {call_sites} 处，登记的是 {RIGHT_SIDE_CALL_SITES} 个调用点 + 1 处定义"
            f"（= {expected_call_sites}）—— 多画了没登记的按钮，还是绕开这个画法自己拼了一个？"
        ))
    else:
        sites += 1

    # F（`T-2` 片 · 2026-10-08）：二级条**右侧那四枚** —— 每个 `accessibilityIdentifier`
    # 必须与**同一枚按钮那一块**里的 `.help(` 成对（判据② 4/4）。
    #
    # 「同一枚那一块」= 从这一枚**往前最近一个** `Button {` 起、到**往后最近一个** `Button {` 为止。
    # 用字窗（±N 字符）判是行不通的：四枚挨着排，窗口一大就会把隔壁那枚的 `.help(` 算进来 ——
    # 那是**假绿**（隔壁有提示、这一枚没有，判据照样过）。
    for identifier, note in SUB_TOOLBAR_ACTIONS:
        marker = f'accessibilityIdentifier("{identifier}")'
        at = sub_code.find(marker)
        if at < 0:
            issues.append(Issue(
                f"{SUB_TOOLBAR}[右侧四枚]",
                f"{note} 那枚不见了：缺 `{marker}`（人类主人原话点名了它）",
            ))
            continue
        start = sub_code.rfind("Button {", 0, at)
        next_button = sub_code.find("Button {", at)
        block = sub_code[start if start >= 0 else 0: next_button if next_button >= 0 else len(sub_code)]
        if ".help(" not in block:
            issues.append(Issue(
                f"{SUB_TOOLBAR}[右侧四枚]",
                f"{note} 那枚没有 `.help(` 提示 —— 图标按钮没有提示，用户只能猜它干什么",
            ))
        else:
            sites += 1

    # 反向对账（`T-2` 片 · ㈢ 2026-10-13 改判**画法形状**）：二级条里画的**枚数**必须等于登记值。
    # 旧实现数的是标识符**前缀**（`accessibilityIdentifier("terminal-`）—— 现场（样本 68 · P8）：
    # 新画的第 5 枚只要把标识符写成 `"terminal5-extra"`（不以 `terminal-` 开头），前缀计数就
    # 永远看不见它（读数与基线逐字同）。改判两样都数：`Button {` 的**块数** 与
    # `accessibilityIdentifier(` 的**出现数**，两者都 == `SUB_TOOLBAR_DRAWN_SHAPES`。
    drawn_shapes = len(re.findall(r"\bButton\s*\{", sub_code))
    drawn_ids = sub_code.count("accessibilityIdentifier(")
    if drawn_shapes != SUB_TOOLBAR_DRAWN_SHAPES or drawn_ids != SUB_TOOLBAR_DRAWN_SHAPES:
        issues.append(Issue(
            f"{SUB_TOOLBAR}[右侧四枚·反向对账]",
            f"二级条里画了 {drawn_shapes} 枚按钮（`accessibilityIdentifier` {drawn_ids} 处），"
            f"登记的是 {SUB_TOOLBAR_DRAWN_SHAPES} 枚"
            f"—— 多画了没登记的按钮，还是把登记过的那枚删了？（两边都得改）",
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


def run(root: pathlib.Path, strict_face: bool = True) -> tuple[list[Issue], dict[str, int]]:
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

    # ㈥：面 —— 与 `Package.swift` 现读的 target 源码目录对账（`strict_face=False` 只在自检夹具上）。
    face_issues, face_sites = check_face(root, strict=strict_face)
    issues += face_issues
    stats["faceSites"] = face_sites

    doc_issues, doc_hits, doc_expected = check_docs(root)
    issues += doc_issues
    stats["docHits"] = doc_hits
    stats["docExpected"] = doc_expected

    # G：空跑防护 —— 「判据自己失效」比「发现不了」更危险。
    expected_api = sum(len(group) for group in API_ANCHORS.values())
    expected_app = (sum(len(anchors) for anchors in APP_ANCHORS.values())
                    + len(RIGHT_SIDE_BUTTONS) + len(LAYER_FORBIDDEN) + 2
                    # `T-2` 片：二级条右侧四枚（逐枚成对）+ 它们的反向对账棘轮。
                    + len(SUB_TOOLBAR_ACTIONS) + 1)
    if stats["apiSites"] < expected_api:
        issues.append(Issue("空跑防护", f"API 锚点只命中 {stats['apiSites']}/{expected_api} 处"))
    if stats["appSites"] < expected_app:
        issues.append(Issue("空跑防护", f"界面接线锚点只命中 {stats['appSites']}/{expected_app} 处"))
    if stats["keys"] < len(KEYS):
        issues.append(Issue("空跑防护", f"文案键只有 {stats['keys']}/{len(KEYS)} 个中英齐"))
    if stats["docHits"] < stats["docExpected"]:
        issues.append(Issue("空跑防护", f"口径锚点只命中 {stats['docHits']}/{stats['docExpected']} 处"))
    expected_face = len(FACE_REGISTERED) + len(FACE_TARGETS) + len(FACE_FILE_FLOOR) + 1
    if strict_face and stats["faceSites"] < expected_face:
        issues.append(Issue("空跑防护", f"面对账只命中 {stats['faceSites']}/{expected_face} 处"))
    return issues, stats


FIXTURE_FILES = [MODEL, TABLE, TESTS, PLAN, QUEUE, PACKAGE, HAN_LEDGER,
                 PANE, SESSION, TABS_MODEL, TABS_BAR, LOWER_PANE, STRIP, SUB_TOOLBAR,
                 TERMINAL_VIEW, PROBE, SUB_PROBE]


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
    """把判据盯着的十七份文件原样拷进临时目录（**只在副本上写坏**）。

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
    # 本机台账不在盘上（干净克隆 / 并行工作树 / 另一平台）⇒ 本族自检**如实跳过 + 高声提示**、
    # 退出 0（口径出处 = `AGENT-SPEC.md` §9 第 147 条 ④）：夹具里那十七份文件含**队列台账**
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
    issues, _ = run(with_fixture, strict_face=False)
    record(any("select(numbered" in str(issue) for issue in issues),
           "例 2（A）API 锚点被拿掉 ⇒ 报红并点名", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 3（B · 红路）：Core 代码行里塞一句中文字面量 ⇒ 报红。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / MODEL, "public enum TerminalTabTitle {", 'public enum TerminalTabTitle {\n    static let bad = "终端"')
    issues, _ = run(with_fixture, strict_face=False)
    record(any("中文字面量" in str(issue) for issue in issues),
           "例 3（B）Core 代码行出现中文字面量 ⇒ 报红", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 4（C · 红路）：语言表里删掉英文译文 ⇒ 报红（英文界面会掉回中文）。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / TABLE, '.terminalTabExited: [.simplifiedChinese: "已退出", .english: "Exited"]',
             '.terminalTabExited: [.simplifiedChinese: "已退出"]')
    issues, _ = run(with_fixture, strict_face=False)
    record(any("缺英文" in str(issue) for issue in issues),
           "例 4（C）语言表缺英文译文 ⇒ 报红", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 5（D · 红路）：单测里一个行为组的锚点被改名 ⇒ 报红。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / TESTS, "func testDeriveTitleStripsLoginShellDash", "func testTitleDerivation")
    issues, _ = run(with_fixture, strict_face=False)
    record(any("testDeriveTitleStripsLoginShellDash" in str(issue) for issue in issues),
           "例 5（D）行为组的用例锚点被改名 ⇒ 报红", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 6（E · 红路）：口径被删（队列 L-84 行里的需求原话被改写）⇒ 报红。
    # 队列文档目前**不在盘上**（先红，见文件头）—— 那就不假装跑得动：如实记一条红并说明原因，
    # 而不是让 traceback 把后面 7 个例子全带走。
    with_fixture = _fixture(root)
    if (with_fixture / QUEUE).is_file():
        _rewrite(with_fixture / QUEUE, "tab 头切换", "页签切换")
        issues, _ = run(with_fixture, strict_face=False)
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
    issues, _ = run(with_fixture, strict_face=False)
    record(moved and any("口径①左侧" in str(issue) for issue in issues),
           "例 7（F）页签头被挪到 Spacer 之后 ⇒ 报红", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 8（F · 红路）：右侧那个「收起」按钮被顺手换掉 ⇒ 报红（口径①：右侧按钮不动）。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / STRIP, 'iconButton("chevron.down"', 'iconButton("chevron.forward"')
    issues, _ = run(with_fixture, strict_face=False)
    record(any("右侧按钮" in str(issue) for issue in issues),
           "例 8（F）右侧按钮被挪走 ⇒ 报红", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 9（F · 红路）：协调器里「确认之后真的关」那条线被删 ⇒ 报红
    # （这正是第 82 轮探针先撞上的坑：确认了却关不掉）。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / TABS_MODEL, "close(id: id, force: true)", "close(id: id)")
    issues, _ = run(with_fixture, strict_face=False)
    record(any("force" in str(issue) for issue in issues),
           "例 9（F）「确认之后真的关」被删 ⇒ 报红", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 10（F · 红路）：App 侧探针的主诉场景用例被改名 ⇒ 报红（证据链断）。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / PROBE, "func testTwoTabsRunIndependentShellsAndSurviveTabSwitching",
             "func testTwoTabs")
    issues, _ = run(with_fixture, strict_face=False)
    record(any("主诉场景" in str(issue) for issue in issues),
           "例 10（F）探针的主诉场景用例锚点被改名 ⇒ 报红", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 11（F · 红路）：界面自己判定按键（不再交给 Core）⇒ 报红。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / TERMINAL_VIEW, "TerminalTabs.command(", "Self.tabCommandIgnoringCore(")
    issues, _ = run(with_fixture, strict_face=False)
    record(any("Core 判定" in str(issue) for issue in issues),
           "例 11（F）按键判定离开 Core ⇒ 报红", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 12（F · 红路）：**多画一个没登记的按钮**（反向对账）⇒ 报红。
    # 这一条才是"一个不少"的另一半：正向只认登记过的符号在不在，新画的按钮它一条都不响。
    # **`T-2` 片扩**：这一例现在同时写坏**三处**、三条红都要看到 ——
    #   ① 外层条多画一枚（`iconButton("star")`）；
    #   ② 终端二级条多画一枚（`accessibilityIdentifier("terminal-extra-bonus")`）；
    #   ③ 二级条某一枚**丢了 `.help(`**（图标按钮没有提示 = 用户只能猜）。
    # 为什么不拆成两例：这三处是**同一条判据族**（「右侧几枚 + 每枚有提示」）的不同写坏方式，
    # 而拆例会改本脚本的自测例数（13）—— 那个数在 `Scripts/self-test-counts.json` /
    # `verify-all.sh` / `AGENT-SPEC.md` 三处登记着，改它要同时动三份文档。分开判的成本大于收益，
    # 但三条红**逐一断言**：任何一条不被抓出来，这一例就红（合并的代价被这一句补上）。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / STRIP, "            Spacer(minLength: 8)\n",
             "            Spacer(minLength: 8)\n"
             "            iconButton(\"star\", help: L(.lowerPaneHide)) { }\n")
    _rewrite(with_fixture / SUB_TOOLBAR,
             '            .accessibilityIdentifier("terminal-restart")\n',
             '            .accessibilityIdentifier("terminal-restart")\n'
             '            .accessibilityIdentifier("terminal-extra-bonus")\n')
    _rewrite(with_fixture / SUB_TOOLBAR, "            .help(L(.terminalClearBuffer))\n", "")
    issues, _ = run(with_fixture, strict_face=False)
    texts = [str(issue) for issue in issues]
    record(
        any("一个不少" in text for text in texts)
        and any("右侧四枚·反向对账" in text for text in texts)
        and any("没有 `.help(` 提示" in text for text in texts),
        "例 12（F）多画没登记的按钮（外层条 / 二级条各一处）+ 二级条某一枚丢提示 ⇒ 三条红",
        "；".join(texts[:3])
    )
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 13（㈠ A · 红路）：API 锚点被**注释掉**（不是删掉）⇒ 报红并点名。
    # 这是样本 68 的第一个现场：旧实现 `anchor in text` 认的是原文子串 ⇒ 读数与基线**逐字相同**。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / MODEL, "public mutating func select(numbered",
             "// public mutating func select(numbered")
    issues, _ = run(with_fixture, strict_face=False)
    record(any("select(numbered" in str(issue) for issue in issues),
           "例 13（㈠ A）API 锚点被注释掉 ⇒ 报红并点名", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 14（㈠ F · 红路）：真 `iconButton(` 调用被**注释掉** ⇒ 反向对账棘轮报红（旧实现数子串）。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / STRIP, 'iconButton("chevron.down", help: L(.lowerPaneHide)) {',
             '// iconButton("chevron.down", help: L(.lowerPaneHide)) {')
    issues, _ = run(with_fixture, strict_face=False)
    record(any("一个不少" in str(issue) for issue in issues),
           "例 14（㈠ F）右侧按钮的调用点被注释掉 ⇒ 棘轮报红", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 15（㈠ F · 红路）：图标按钮的 `.help(` 被注释掉 ⇒ 报红（注释不是提示）。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / SUB_TOOLBAR, "            .help(L(.terminalClearBuffer))",
             "            // .help(L(.terminalClearBuffer))")
    issues, _ = run(with_fixture, strict_face=False)
    record(any("没有 `.help(` 提示" in str(issue) for issue in issues),
           "例 15（㈠ F）`.help(` 被注释掉 ⇒ 报红", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 16（㈠ D · 红路）：行为组的用例锚点被**注释掉** ⇒ 报红（旧实现 D 组同样只认子串）。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / TESTS, "func testDeriveTitleStripsLoginShellDash",
             "// func testDeriveTitleStripsLoginShellDash")
    issues, _ = run(with_fixture, strict_face=False)
    record(any("testDeriveTitleStripsLoginShellDash" in str(issue) for issue in issues),
           "例 16（㈠ D）用例锚点被注释掉 ⇒ 报红", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 17（㈠ C · 红路）：语言表里整条**注释掉** ⇒ 报红（英文界面已掉回中文，读数不再逐字同）。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / TABLE,
             '.terminalTabExited: [.simplifiedChinese: "已退出", .english: "Exited"]',
             '// .terminalTabExited（整条注释掉）')
    issues, _ = run(with_fixture, strict_face=False)
    record(any("语言表里没有 `.terminalTabExited`" in str(issue) for issue in issues),
           "例 17（㈠ C）语言表整条被注释掉 ⇒ 报红", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 18（㈡ 位置 · 红路）：真页签头挪到 `Spacer(minLength: 8)` **之后**，并在 Spacer 之前
    # **留一行注释**写着同一串 —— 旧实现读到的是那行注释（读数与基线逐字同）⇒ 现在必须报红。
    with_fixture = _fixture(root)
    bar_line = "            TerminalTabsBar(terminal: terminal)\n"
    spacer_line = "            Spacer(minLength: 8)\n"
    moved = _rewrite(with_fixture / SUB_TOOLBAR, bar_line,
                     "            // 已挪走：TerminalTabsBar(terminal: terminal)\n")
    moved = moved and _rewrite(with_fixture / SUB_TOOLBAR, spacer_line, spacer_line + bar_line)
    issues, _ = run(with_fixture, strict_face=False)
    record(moved and any("口径①左侧" in str(issue) for issue in issues),
           "例 18（㈡ 位置）挪走之后靠一行注释冒充原位 ⇒ 仍报红",
           "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 19（㈢ 反向棘轮 · 红路）：二级条多画第 5 枚、且标识符**不以 `terminal-` 开头**
    # ⇒ 报红（旧实现数的是前缀，这一枚它永远看不见 —— 样本 68 · P8 的现场）。
    with_fixture = _fixture(root)
    extra = ('            Button {\n                terminal.clearActiveBuffer()\n'
             '            } label: {\n                Image(systemName: "star")\n            }\n'
             '            .accessibilityIdentifier("terminal5-extra")\n')
    _rewrite(with_fixture / SUB_TOOLBAR, '            .accessibilityIdentifier("terminal-restart")\n',
             '            .accessibilityIdentifier("terminal-restart")\n' + extra)
    issues, _ = run(with_fixture, strict_face=False)
    record(any("右侧四枚·反向对账" in str(issue) for issue in issues),
           "例 19（㈢）第 5 枚按钮的标识符不以前缀开头 ⇒ 仍报红", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 20（㈣ · 红路）：Core 里写 `"\u{7EC8}\u{7AEF}"`（转义的中文）⇒ 报红。
    # 旧实现只认源码里的 U+4E00–9FFF 字面字符 ⇒ 同一句话换个写法就整条绕过「Core 不出人话」。
    with_fixture = _fixture(root)
    escaped = '    static let bad = "' + r'\u{7EC8}\u{7AEF}' + '"\n'
    _rewrite(with_fixture / MODEL, "public enum TerminalTabTitle {",
             "public enum TerminalTabTitle {\n" + escaped)
    issues, _ = run(with_fixture, strict_face=False)
    record(any("中文字面量" in str(issue) for issue in issues),
           "例 20（㈣）转义写法的中文 ⇒ 报红", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 21（㈤ 对手臂 · 绿路）：**行尾注释**里写中文 ⇒ 不再误伤（旧实现把注释里的引号串当字面量）。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / MODEL, "public enum TerminalTabTitle {",
             "public enum TerminalTabTitle { // 终端页签的标题")
    issues, _ = run(with_fixture, strict_face=False)
    record(not any("中文字面量" in str(issue) for issue in issues),
           "例 21（㈤）行尾注释里的中文 ⇒ 不报红（同一串真写成代码时见例 3）",
           "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 22（㈤ 对手臂 · 绿路）：**块注释**里写被禁符号 `arrow.clockwise`（搬走时要留的路标）
    # ⇒ 不再误伤层级断言；同处真写代码时见例 12 那一族（外层条上写就报红）。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / STRIP, "struct LowerPaneTabStrip",
             "/* arrow.clockwise 已随 T-1a 搬走 */\nstruct LowerPaneTabStrip")
    issues, _ = run(with_fixture, strict_face=False)
    record(not any("层级" in str(issue) for issue in issues),
           "例 22（㈤）块注释里的被禁符号 ⇒ 不报红（路标注释是正常的）",
           "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 23（㈥ 面 · 红路）：**面内新文件**承载子终端件（`App/Views/Extra68.swift` 里画
    # `TerminalTabsBar(terminal:)`）⇒ 报红并点名（旧实现面是 15 个写死路径，这一件它看不见）。
    with_fixture = _fixture(root)
    extra_view = with_fixture / "App/Views/Extra68.swift"
    extra_view.write_text('struct Extra68: View {\n'
                          '    var body: some View { TerminalTabsBar(terminal: terminal) }\n'
                          '}\n', encoding="utf-8")
    issues, _ = run(with_fixture, strict_face=False)
    record(any("Extra68.swift" in str(issue) and "承载子终端件" in str(issue) for issue in issues),
           "例 23（㈥）面内未登记的新件承载子终端件 ⇒ 报红并点名",
           "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 24（㈥ 面 · 红路 · 两臂）：① **面内新的 Core 件**里写中文字面量 ⇒ 报红（旧实现只读写死的
    # 那一份模型 —— 新建 Core 件写「终端」它一声不响）；② **死豁免**：先红基线名单点着的件
    # 不再写中文 ⇒ 也报红（名单不许积灰）。
    with_fixture = _fixture(root)
    (with_fixture / "Core/Extra68Core.swift").write_text('let bad68 = "终端"\n', encoding="utf-8")
    issues, _ = run(with_fixture, strict_face=False)
    texts = [str(issue) for issue in issues]
    first = any("Extra68Core.swift" in text and "中文字面量" in text for text in texts)
    shutil.rmtree(with_fixture, ignore_errors=True)

    with_fixture = _fixture(root)
    listed = json.loads((with_fixture / HAN_LEDGER).read_text(encoding="utf-8"))
    stale = listed.get("coreFilesWithChineseLiterals", [])
    if stale:
        (with_fixture / stale[0]).write_text("let clean68 = 1\n", encoding="utf-8")
        issues, _ = run(with_fixture, strict_face=False)
        texts = [str(issue) for issue in issues]
    record(first and any("死豁免" in text for text in texts),
           "例 24（㈥）面内新 Core 件写中文 ⇒ 报红；先红基线里的件不再写中文 ⇒ 死豁免报红",
           "；".join(texts[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 25（反过来核一遍）：所有写坏都发生在副本上 —— 真仓库（有盘的）十七份文件必须逐字节未变。
    after = _digests(root)
    record(before == after, "例 25 真仓库（有盘的十七份）文件逐字节未变",
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
    index = 1  # argv[0] 是脚本自己的路径
    while index < len(argv):
        item = argv[index]
        if item == "--root":
            if index + 1 >= len(argv):
                print("❌ `--root` 后面少了一个路径")
                return 2
            index += 2
            continue
        if item == "--self-test":
            index += 1
            continue
        print(f"❌ 未知参数 `{item}` —— 判据不接受它（旧实现吞掉照跑，读数就是假的）")
        return 2
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
