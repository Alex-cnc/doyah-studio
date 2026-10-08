import XCTest
@testable import DoyahCore

/// 终端多会话（页签）的 **Core 纯逻辑**单测 —— 队列 `L-84` ㈠ / 开发循环第 81 轮。
///
/// 这个文件钉的就是 `FR-EDIT-29` 判据里点名的五件事：**新建 / 关闭 / 切换 / 标题推导 /
/// 关闭确认判定** —— 一件一组。为什么能在不真开 shell 的情况下钉住：多会话的坑几乎全在
/// **顺序与归属**上（新页签插哪、关掉当前页签谁接管、⌘1…9 落到哪个、重命名后标题怎么回落、
/// 最后一个能不能关），这些在 `TerminalTabs` 里是纯值逻辑，可以穷举。
///
/// 边界（如实说）：真开 PTY、前台进程名怎么查、界面怎么画，**不在这个文件里** ——
/// 那三样分别由 App 侧接线（㈡）与真人点验（主诉场景：一个页签跑 `dsh-tui`、另一个执行命令）承担。
final class TerminalTabsTests: XCTestCase {

    private let shell = "/bin/zsh"

    // MARK: - 标题推导与清洗

    func testDeriveTitleTakesLastPathComponent() {
        XCTAssertEqual(TerminalTabTitle.derive(fromExecutablePath: "/usr/local/bin/dsh-tui"), "dsh-tui")
        XCTAssertEqual(TerminalTabTitle.derive(fromExecutablePath: "/bin/zsh"), "zsh")
        XCTAssertEqual(TerminalTabTitle.derive(fromExecutablePath: "psql"), "psql")
    }

    func testDeriveTitleStripsLoginShellDash() {
        XCTAssertEqual(TerminalTabTitle.derive(fromExecutablePath: "-zsh"), "zsh")
        XCTAssertEqual(TerminalTabTitle.derive(fromExecutablePath: "/bin/-bash"), "bash")
    }

    func testDeriveTitleRefusesUnusableNames() {
        // 认不出就**没有标题**（nil），由界面用语言表里的兜底词 —— 不许拿路径硬凑一个像名字的东西。
        XCTAssertNil(TerminalTabTitle.derive(fromExecutablePath: nil))
        XCTAssertNil(TerminalTabTitle.derive(fromExecutablePath: ""))
        XCTAssertNil(TerminalTabTitle.derive(fromExecutablePath: "/"))
        XCTAssertNil(TerminalTabTitle.derive(fromExecutablePath: "-"))
        XCTAssertNil(TerminalTabTitle.derive(fromExecutablePath: "   "))
    }

    func testSanitizeCollapsesWhitespaceAndDropsControlCharacters() {
        XCTAssertEqual(TerminalTabTitle.sanitize("  dsh\ttui \n"), "dsh tui")
        XCTAssertEqual(TerminalTabTitle.sanitize("a\u{1b}b"), "ab")
        XCTAssertEqual(TerminalTabTitle.sanitize("a\u{7}b"), "ab")
        XCTAssertEqual(TerminalTabTitle.sanitize("\n\t  "), nil)
    }

    func testSanitizeTruncatesLongTitles() throws {
        let long = String(repeating: "x", count: 60)
        let cleaned = try XCTUnwrap(TerminalTabTitle.sanitize(long))
        XCTAssertEqual(cleaned.count, TerminalTabTitle.maxLength)
        XCTAssertTrue(cleaned.hasSuffix("…"))
        // 正好等于上限的标题**不截断**（边界不许提前砍）。
        let exact = String(repeating: "y", count: TerminalTabTitle.maxLength)
        XCTAssertEqual(TerminalTabTitle.sanitize(exact), exact)
    }
}

extension TerminalTabsTests {

    // MARK: - 首建（= 现状）

    func testInitialTabsMatchSingleTerminalBehaviour() {
        // 口径⑥：首个页签 = 现状（打开面板就是一个 zsh），行为不变。
        let tabs = TerminalTabs(shellPath: shell)
        XCTAssertEqual(tabs.count, 1)
        XCTAssertEqual(tabs.ids, [1])
        XCTAssertEqual(tabs.activeTab.id, 1)
        XCTAssertEqual(tabs.activeTab.title, "zsh")
        XCTAssertEqual(tabs.activeTab.state, .live)
        XCTAssertFalse(tabs.activeTab.isRenamed)
    }

    // MARK: - 新建

    func testNewTabInsertsRightOfActiveAndActivatesIt() {
        var tabs = TerminalTabs(shellPath: shell)
        _ = tabs.newTab()
        _ = tabs.newTab()
        // 连开两个：插在当前页签右侧（不是飞到最右边），并且新页签就是当前页签。
        XCTAssertEqual(tabs.ids, [1, 2, 3])
        XCTAssertEqual(tabs.activeID, 3)

        _ = tabs.select(id: 1)
        _ = tabs.newTab()
        XCTAssertEqual(tabs.ids, [1, 4, 2, 3])
        XCTAssertEqual(tabs.activeID, 4)
    }

    func testTabIdentifiersKeepGrowingAfterClose() {
        // 关掉中间的页签不重号 —— 重号会让「切到第 3 个」指到另一个会话。
        var tabs = TerminalTabs(shellPath: shell)
        let second = tabs.newTab()
        let third = tabs.newTab()
        _ = tabs.select(id: second)
        _ = tabs.close(id: second)
        let fourth = tabs.newTab()
        XCTAssertEqual([second, third, fourth], [2, 3, 4])
        XCTAssertEqual(tabs.ids, [1, 3, 4])
    }

    func testNewTabInheritsShellWhenNotGiven() {
        var tabs = TerminalTabs(shellPath: "/bin/bash")
        _ = tabs.newTab(shellPath: "/usr/local/bin/dsh-tui")
        _ = tabs.newTab()
        XCTAssertEqual(tabs.tab(id: 2)?.shellPath, "/usr/local/bin/dsh-tui")
        XCTAssertEqual(tabs.tab(id: 3)?.shellPath, "/usr/local/bin/dsh-tui")
    }

    // MARK: - 切换

    func testSelectByIdRejectsUnknownIdentifier() {
        var tabs = TerminalTabs(shellPath: shell)
        XCTAssertFalse(tabs.select(id: 99))
        XCTAssertEqual(tabs.activeID, 1)
    }

    func testSelectNumberedIsOneBasedAndRejectsOutOfRange() {
        var tabs = TerminalTabs(shellPath: shell)
        _ = tabs.newTab()
        _ = tabs.newTab()
        XCTAssertTrue(tabs.select(numbered: 1))
        XCTAssertEqual(tabs.activeID, 1)
        XCTAssertTrue(tabs.select(numbered: 3))
        XCTAssertEqual(tabs.activeID, tabs.ids[2])
        // 越界不动（不是环绕：按错了不该跳到一个你没想到的会话）。
        XCTAssertFalse(tabs.select(numbered: 4))
        XCTAssertFalse(tabs.select(numbered: 0))
        XCTAssertEqual(tabs.activeID, tabs.ids[2])
    }

    func testSelectNextAndPreviousWrapAround() {
        var tabs = TerminalTabs(shellPath: shell)
        _ = tabs.newTab()
        _ = tabs.newTab()
        _ = tabs.select(numbered: 1)
        XCTAssertTrue(tabs.selectPrevious())
        XCTAssertEqual(tabs.activeIndex, 2)
        XCTAssertTrue(tabs.selectNext())
        XCTAssertEqual(tabs.activeIndex, 0)
        XCTAssertTrue(tabs.selectNext())
        XCTAssertEqual(tabs.activeIndex, 1)
    }

    func testSelectNextIsNoOpWithSingleTab() {
        var tabs = TerminalTabs(shellPath: shell)
        XCTAssertFalse(tabs.selectNext())
        XCTAssertFalse(tabs.selectPrevious())
        XCTAssertEqual(tabs.activeID, 1)
    }
}

extension TerminalTabsTests {

    // MARK: - 重命名

    func testRenameWinsOverForegroundProcess() {
        var tabs = TerminalTabs(shellPath: shell)
        let tab = tabs.newTab(foregroundProcess: "/usr/local/bin/dsh-tui")
        XCTAssertEqual(tabs.tab(id: tab)?.title, "dsh-tui")
        XCTAssertTrue(tabs.rename(id: tab, to: "  会话甲 "))
        XCTAssertEqual(tabs.tab(id: tab)?.title, "会话甲")
        XCTAssertTrue(tabs.tab(id: tab)?.isRenamed == true)
    }

    func testRenameAllowsDuplicatesAndEmptyClearsIt() {
        var tabs = TerminalTabs(shellPath: shell)
        let second = tabs.newTab(foregroundProcess: "/usr/bin/psql")
        XCTAssertTrue(tabs.rename(id: 1, to: "psql"))
        // 重名允许：两个 psql 会话是两件事，硬去重只会让用户没法叫出自己想叫的名字。
        XCTAssertEqual(tabs.tab(id: 1)?.title, "psql")
        XCTAssertEqual(tabs.tab(id: second)?.title, "psql")
        // 空 / 全空白 = 清除重命名，标题回落到前台进程名。
        XCTAssertTrue(tabs.rename(id: 1, to: "   "))
        XCTAssertEqual(tabs.tab(id: 1)?.title, "zsh")
        XCTAssertFalse(tabs.tab(id: 1)?.isRenamed == true)
    }

    func testRenameSanitizesAndRejectsUnknownTab() {
        var tabs = TerminalTabs(shellPath: shell)
        _ = tabs.rename(id: 1, to: "a\n\tb")
        XCTAssertEqual(tabs.tab(id: 1)?.title, "a b")
        XCTAssertFalse(tabs.rename(id: 42, to: "x"))
        XCTAssertFalse(tabs.setForegroundProcess("/bin/bash", for: 42))
    }

    func testForegroundProcessDrivesTitleUntilRenamed() {
        var tabs = TerminalTabs(shellPath: shell)
        // 前台跑起来一个 dsh-tui：标题跟着变（用户没起名字时）。
        XCTAssertTrue(tabs.setForegroundProcess("/usr/local/bin/dsh-tui", for: 1))
        XCTAssertEqual(tabs.activeTab.title, "dsh-tui")
        // 前台程序退出、回到 shell：标题回到 shell 名。
        XCTAssertTrue(tabs.setForegroundProcess("/bin/zsh", for: 1))
        XCTAssertEqual(tabs.activeTab.title, "zsh")
        // 用户起过名字之后，前台进程再变也不动标题。
        _ = tabs.rename(id: 1, to: "日志")
        XCTAssertTrue(tabs.setForegroundProcess("/usr/bin/psql", for: 1))
        XCTAssertEqual(tabs.activeTab.title, "日志")
    }

    // MARK: - 状态（退出 / 重启）

    func testExitedAndRestartedState() throws {
        var tabs = TerminalTabs(shellPath: shell)
        XCTAssertTrue(tabs.markExited(id: 1, code: 1))
        let exited = try XCTUnwrap(tabs.tab(id: 1))
        XCTAssertTrue(exited.isExited)
        XCTAssertEqual(exited.state, .exited(code: 1))
        // 重启 = 同一个页签换一条命：id 与名字都留着。
        XCTAssertTrue(tabs.markLive(id: 1))
        XCTAssertFalse(tabs.activeTab.isExited)
        XCTAssertEqual(tabs.activeTab.state, .live)
        XCTAssertEqual(tabs.activeTab.id, 1)
        XCTAssertFalse(tabs.markExited(id: 9, code: 0))
    }
}

extension TerminalTabsTests {

    // MARK: - 关闭确认判定

    func testCloseDecisionForShellItselfIsDirect() {
        var tabs = TerminalTabs(shellPath: shell)
        _ = tabs.newTab()
        // 前台就是 shell（或还没查到前台进程）：直接关，不弹确认。
        XCTAssertEqual(tabs.closeDecision(for: 1), .canClose)
        XCTAssertTrue(tabs.setForegroundProcess("/bin/zsh", for: 1))
        XCTAssertEqual(tabs.closeDecision(for: 1), .canClose)
    }

    func testCloseDecisionNeedsConfirmationForRunningProgram() {
        var tabs = TerminalTabs(shellPath: shell)
        let second = tabs.newTab(foregroundProcess: "/usr/local/bin/dsh-tui")
        XCTAssertEqual(tabs.closeDecision(for: second), .needsConfirmation)
        // 主诉场景：一个页签跑 dsh-tui、另一个是 shell —— 前者的关闭要问一句，后者不用。
        XCTAssertEqual(tabs.closeDecision(for: 1), .canClose)
        // 界面不许绕过判定直接关（判据在集合里，不在视图里）。
        XCTAssertFalse(tabs.close(id: second))
        XCTAssertEqual(tabs.count, 2)
    }

    func testCloseDecisionForExitedSessionIsDirect() {
        // 会话已退出：里面没有东西可丢，前台进程名还没被清掉也直接关。
        var tabs = TerminalTabs(shellPath: shell)
        let second = tabs.newTab(foregroundProcess: "/usr/local/bin/dsh-tui")
        _ = tabs.markExited(id: second, code: 0)
        XCTAssertEqual(tabs.closeDecision(for: second), .canClose)
    }

    func testCloseDecisionRefusesLastTabAndUnknownTab() {
        let tabs = TerminalTabs(shellPath: shell)
        XCTAssertEqual(tabs.closeDecision(for: 1), .refuse(.lastTab))
        XCTAssertEqual(tabs.closeDecision(for: 7), .refuse(.unknownTab))
    }

    // MARK: - 关闭后的归属

    func testCloseActiveTabHandsOverToRightNeighbour() {
        var tabs = TerminalTabs(shellPath: shell)
        _ = tabs.newTab()
        let third = tabs.newTab()
        _ = tabs.select(id: 2)
        XCTAssertTrue(tabs.close(id: 2))
        XCTAssertEqual(tabs.ids, [1, third])
        XCTAssertEqual(tabs.activeID, third)   // 右邻居接管
    }

    func testCloseActiveLastTabHandsOverToLeftNeighbour() {
        var tabs = TerminalTabs(shellPath: shell)
        let second = tabs.newTab()
        _ = tabs.newTab()
        XCTAssertEqual(tabs.activeID, 3)
        XCTAssertTrue(tabs.close(id: 3))
        XCTAssertEqual(tabs.ids, [1, second])
        XCTAssertEqual(tabs.activeID, second)  // 没有右邻居 → 左邻居接管
    }

    func testCloseInactiveTabKeepsActiveTab() {
        var tabs = TerminalTabs(shellPath: shell)
        _ = tabs.newTab()
        let second = tabs.newTab()
        _ = tabs.select(id: 2)
        XCTAssertTrue(tabs.close(id: 1))
        XCTAssertEqual(tabs.ids, [2, second])
        XCTAssertEqual(tabs.activeID, 2)
    }

    func testCloseLastRemainingTabIsRefusedAndChangesNothing() {
        var tabs = TerminalTabs(shellPath: shell)
        let before = tabs
        XCTAssertFalse(tabs.close(id: 1))
        XCTAssertEqual(tabs, before)
        // 想收起终端有专门的入口（收起面板），关页签的语义是销毁会话。
        XCTAssertEqual(tabs.count, 1)
    }

    func testCloseAfterConfirmationActuallyCloses() {
        var tabs = TerminalTabs(shellPath: shell)
        _ = tabs.newTab(foregroundProcess: "/usr/local/bin/psql")
        let id = tabs.activeID
        // 没确认：一个字节都不动
        XCTAssertFalse(tabs.close(id: id))
        XCTAssertNotNil(tabs.tab(id: id))
        // 确认过：**真的关** —— 这一条是「点了『关闭页签』却没反应」那个坑的回归钉
        // （第 82 轮 App 侧探针先撞上它：`confirmClose()` 再走一次判定被挡回来）。
        XCTAssertTrue(tabs.close(id: id, force: true))
        XCTAssertNil(tabs.tab(id: id))
        XCTAssertEqual(tabs.count, 1)
    }

    func testCloseForceStillRefusesTheLastTab() {
        var tabs = TerminalTabs(shellPath: shell)
        // 唯一一个页签、前台还挂着程序：**确认过也关不掉**（关掉它面板就成了空壳，
        // 「收起终端」另有入口）。force 不是万能钥匙。
        _ = tabs.setForegroundProcess("/usr/local/bin/psql", for: 1)
        let before = tabs
        XCTAssertFalse(tabs.close(id: 1, force: true))
        XCTAssertEqual(tabs, before)
    }

    // MARK: - 按键 → 动作（㈡ 的界面把这一套判定当唯一入口）

    func testCommandNewAndCloseTabs() {
        XCTAssertEqual(TerminalTabs.command(key: "t", command: true, shift: false), .newTab)
        XCTAssertEqual(TerminalTabs.command(key: "w", command: true, shift: false), .closeTab)
    }

    func testCommandAcceptsShiftedBracketsAsWellAsPlainOnes() {
        // **真坑**：`charactersIgnoringModifiers` 会把 ⇧ 一起作用到字符上 —— 美式键盘上
        // ⇧⌘[ 拿到的是 `{`。只认 `[` 的话「上一个页签」这个键**永远不会触发**，
        // 而症状看起来像「快捷键没生效」，极难归因。
        XCTAssertEqual(TerminalTabs.command(key: "[", command: true, shift: true), .previousTab)
        XCTAssertEqual(TerminalTabs.command(key: "{", command: true, shift: true), .previousTab)
        XCTAssertEqual(TerminalTabs.command(key: "]", command: true, shift: true), .nextTab)
        XCTAssertEqual(TerminalTabs.command(key: "}", command: true, shift: true), .nextTab)
    }

    func testCommandSelectsNumberedTabsOneThroughNine() {
        XCTAssertEqual(TerminalTabs.command(key: "1", command: true, shift: false), .selectTab(number: 1))
        XCTAssertEqual(TerminalTabs.command(key: "9", command: true, shift: false), .selectTab(number: 9))
        // ⌘0 不动（不是「第 10 个」），方向键一类的字符也认不出来。
        XCTAssertNil(TerminalTabs.command(key: "0", command: true, shift: false))
        XCTAssertNil(TerminalTabs.command(key: "\u{F701}", command: true, shift: false))
    }

    func testCommandRefusesOptionControlAndShiftedLetters() {
        // ⌥ / ⌃ 参与就不认：⌥ 是终端里「把鼠标还给本机」那一族，⌃W 要**原样发给 shell** 删词。
        XCTAssertNil(TerminalTabs.command(key: "t", command: true, shift: false, option: true))
        XCTAssertNil(TerminalTabs.command(key: "w", command: true, shift: false, control: true))
        // 没按 ⌘ 的普通字母不是页签动作。
        XCTAssertNil(TerminalTabs.command(key: "t", command: false, shift: false))
        XCTAssertNil(TerminalTabs.command(key: "w", command: false, shift: false))
        // ⇧ + 其它键不许被页签偷走（⇧⌘T 已经归「数据任务」）。
        XCTAssertNil(TerminalTabs.command(key: "t", command: true, shift: true))
        XCTAssertNil(TerminalTabs.command(key: "w", command: true, shift: true))
        XCTAssertNil(TerminalTabs.command(key: "1", command: true, shift: true))
    }

    func testPerformNewTabInsertsRightOfActive() {
        var tabs = TerminalTabs(shellPath: shell)
        _ = tabs.newTab()
        _ = tabs.select(numbered: 1)
        XCTAssertTrue(tabs.perform(.newTab))
        // 新页签插在**当前**（第 1 个）右侧 —— 与 Core 的 `newTab()` 同一口径。
        XCTAssertEqual(tabs.ids, [1, 3, 2])
        XCTAssertEqual(tabs.activeID, 3)
    }

    func testPerformCloseTabRefusesTheLastOne() {
        var tabs = TerminalTabs(shellPath: shell)
        XCTAssertFalse(tabs.perform(.closeTab))
        XCTAssertEqual(tabs.count, 1)
    }

    func testPerformCloseTabWaitsForConfirmationWhenProgramIsRunning() {
        var tabs = TerminalTabs(shellPath: shell)
        _ = tabs.newTab(foregroundProcess: "/usr/local/bin/psql")
        XCTAssertEqual(tabs.closeDecision(for: tabs.activeID), .needsConfirmation)
        let before = tabs
        // `perform` **只做判定已经允许的那一步**：要确认的关闭它什么都不做（问一句是界面的事）。
        XCTAssertFalse(tabs.perform(.closeTab))
        XCTAssertEqual(tabs, before)
    }

    func testPerformSelectTabOutOfRangeChangesNothing() {
        var tabs = TerminalTabs(shellPath: shell)
        _ = tabs.newTab()
        let before = tabs
        XCTAssertFalse(tabs.perform(.selectTab(number: 5)))
        XCTAssertEqual(tabs, before)
        XCTAssertTrue(tabs.perform(.selectTab(number: 1)))
        XCTAssertEqual(tabs.activeID, 1)
    }

    func testPerformNextAndPreviousWrapAround() {
        var tabs = TerminalTabs(shellPath: shell)
        _ = tabs.newTab()
        _ = tabs.newTab()
        XCTAssertEqual(tabs.ids, [1, 2, 3])
        XCTAssertTrue(tabs.perform(.nextTab))
        XCTAssertEqual(tabs.activeID, 1)          // 3 → 环绕到 1
        XCTAssertTrue(tabs.perform(.previousTab))
        XCTAssertEqual(tabs.activeID, 3)          // 1 → 环绕到 3
    }

    // MARK: - 值语义

    func testTabsValueSemanticsKeepCopiesIndependent() {
        var original = TerminalTabs(shellPath: shell)
        _ = original.newTab()
        var copy = original
        _ = copy.newTab(shellPath: "/bin/bash")
        XCTAssertEqual(original.count, 2)
        XCTAssertEqual(copy.count, 3)
        XCTAssertEqual(original.ids, [1, 2])
        XCTAssertEqual(copy.ids, [1, 2, 3])
        XCTAssertNotEqual(original, copy)
    }

    // MARK: - 一键启动的两个预设（终端二级条右侧那两枚按钮，2026-10-08）

    /// 预设本身就是**两条事实**：敲进 shell 的那一行、以及新页签的名字。
    /// 两者都是字面量，所以能在这里逐字钉死 —— 这也是把它们放进 Core 的理由
    /// （三处各写一遍的话，改了一处另外两处照样绿）。
    func testLaunchPresetsCarryCommandLineAndTabTitle() {
        XCTAssertEqual(TerminalLaunchCommand.allCases.map(\.rawValue), ["dsh-tui", "hermes"])
        XCTAssertEqual(TerminalLaunchCommand.dshTUI.inputLine, "dsh-tui\n")
        XCTAssertEqual(TerminalLaunchCommand.hermes.inputLine, "hermes\n")
        XCTAssertEqual(TerminalLaunchCommand.dshTUI.tabTitle, "dsh-tui")
        XCTAssertEqual(TerminalLaunchCommand.hermes.tabTitle, "hermes")
    }

    /// 一键启动的页签名：**预设名直接给**，不被前台进程名盖掉（实测那一条是 `node`），
    /// 但**用户改名仍然优先** —— 它是他自己起的名字。
    func testLaunchTitleWinsOverForegroundProcessButNotOverRename() {
        var tabs = TerminalTabs(shellPath: shell)
        let id = tabs.newTab(launchTitle: TerminalLaunchCommand.dshTUI.tabTitle)

        XCTAssertEqual(tabs.tab(id: id)?.title, "dsh-tui", "新页签没带上预设名")
        XCTAssertEqual(tabs.tab(id: id)?.isRenamed, false, "预设名不是用户重命名")

        // 前台进程名回填（解释器启动器实测给的是 node）也不许盖掉预设名。
        _ = tabs.setForegroundProcess("/opt/homebrew/Cellar/node/26.8.2/bin/node", for: id)
        XCTAssertEqual(tabs.tab(id: id)?.title, "dsh-tui", "前台进程名把预设名盖掉了")

        // 用户改名优先。
        _ = tabs.rename(id: id, to: "我的鲸鱼")
        XCTAssertEqual(tabs.tab(id: id)?.title, "我的鲸鱼")

        // 清掉重命名 ⇒ 回落到**预设名**，而不是 `node`。
        _ = tabs.rename(id: id, to: "   ")
        XCTAssertEqual(tabs.tab(id: id)?.title, "dsh-tui")
    }

    /// 普通新页签（`⌘T` / 页签条上的 `+`）口径**一字未改**：没有预设名，仍按前台进程名走。
    func testPlainNewTabStillDerivesTitleFromForegroundProcess() {
        var tabs = TerminalTabs(shellPath: shell)
        let id = tabs.newTab()
        XCTAssertNil(tabs.tab(id: id)?.launchTitle)
        XCTAssertEqual(tabs.tab(id: id)?.title, "zsh", "没有预设名时回落到 shell 名")
        _ = tabs.setForegroundProcess("/usr/local/bin/psql", for: id)
        XCTAssertEqual(tabs.tab(id: id)?.title, "psql", "前台进程名应当驱动标题")
    }

    // MARK: - 重启确认（「重启终端」那枚按钮的判定）

    /// 会话在跑 ⇒ 重启**先问一句**（要 SIGHUP 整条进程组，里面有程序一起结束）；
    /// 会话已经退出 ⇒ 直接重启（没有东西可丢）；页签不在 ⇒ 直接重启（上面没人在跑）。
    func testRestartDecisionAsksWhileLiveAndNotAfterExit() {
        var tabs = TerminalTabs(shellPath: shell)
        let id = tabs.activeID
        XCTAssertEqual(tabs.restartDecision(for: id), .needsConfirmation)

        _ = tabs.markExited(id: id, code: 0)
        XCTAssertEqual(tabs.restartDecision(for: id), .canRestart)

        // 重启之后又回到「在跑」⇒ 又该问了（`markLive` 是重启那条链上的回填）。
        _ = tabs.markLive(id: id)
        XCTAssertEqual(tabs.restartDecision(for: id), .needsConfirmation)

        XCTAssertEqual(tabs.restartDecision(for: 999), .canRestart, "不存在的页签 = 上面没人在跑")
    }
}
