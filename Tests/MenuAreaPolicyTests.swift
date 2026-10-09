import XCTest
@testable import DoyahCore

/// 菜单显示与活动栏联动的判据（2026-10-02 需求提出者口径）。
///
/// 需求原话：「**菜单显示应该与活动栏当前的选择相关联**，比如用户选了数据库才会有 file 菜单里的
/// 新建查询。现在不关联，导致新建了一个查询，界面还是停留在 workspace」。
///
/// 两层分开判，因为它们是两件不同的事：
///   ① **显示**：`MenuAreaPolicy` 的映射（纯函数，本文件的 ①②）；
///   ② **动作**：命令执行时先切区（源锚点，本文件的 ④）——
///      只做①不做②，快捷键 / 命令面板那条路仍会「建在看不见的地方」。
final class MenuAreaPolicyTests: XCTestCase {

    // MARK: - ① 映射

    func testOwnerOfAreaBoundItems() {
        XCTAssertEqual(MenuAreaPolicy.owner(of: .menuNewQuery), .database)
        XCTAssertEqual(MenuAreaPolicy.owner(of: .menuNewBrowserTab), .workspace)
        XCTAssertEqual(MenuAreaPolicy.owner(of: .menuNotes), .notes)
    }

    /// 表外的命令**不属于任何区**（漏登记的后果是「到处都显示」= 回到改动前的行为，
    /// 而不是「被藏起来找不到」——这条是刻意选的，见 `MenuAreaPolicy` 的注释）。
    func testUnregisteredItemsStayVisibleEverywhere() {
        let appLevel: [LKey] = [.menuAppearance, .menuLanguage, .menuRelaunchApp, .menuAboutLicense, .lowerPaneToggle]
        for key in appLevel {
            XCTAssertNil(MenuAreaPolicy.owner(of: key), "\(key) 不该被登记成某个区专属")
            for area in ActivityBarItem.allCases {
                XCTAssertTrue(MenuAreaPolicy.isVisible(key: key, in: area), "\(key) 在 \(area.rawValue) 下也应可见")
            }
        }
    }

    func testVisibilityMatrix() {
        // 只有**它自己那个区**看得见（这就是需求原话举的那一例）。
        XCTAssertTrue(MenuAreaPolicy.isVisible(key: .menuNewQuery, in: .database))
        XCTAssertFalse(MenuAreaPolicy.isVisible(key: .menuNewQuery, in: .workspace))
        XCTAssertFalse(MenuAreaPolicy.isVisible(key: .menuNewQuery, in: .notes))
        XCTAssertTrue(MenuAreaPolicy.isVisible(key: .menuNewBrowserTab, in: .workspace))
        XCTAssertFalse(MenuAreaPolicy.isVisible(key: .menuNewBrowserTab, in: .database))
        XCTAssertTrue(MenuAreaPolicy.isVisible(key: .menuNotes, in: .notes))
        XCTAssertFalse(MenuAreaPolicy.isVisible(key: .menuNotes, in: .workspace))
    }

    /// 每个区至少有一条登记项 —— 否则「联动」在某一个区是空转（改了看不出来）。
    ///
    /// **登记在案的豁免**（片 `M7-HOST` · 派单 `T-20261009-080`）：周报（Retro）区本片只落
    /// 「活动栏入口 + 只读阅读器」，**还没有自己的区专属菜单命令** ⇒ 这里对它是空集。
    /// 豁免**必须登记在案**，两个方向都判：新加的区忘了给菜单命令 ⇒ 红；
    /// 已经给了菜单命令却忘了销豁免 ⇒ 也红（陈旧）。
    private static let areasWithoutMenuCommands: Set<ActivityBarItem> = [.retro]

    func testEveryAreaHasAtLeastOneBoundItem() {
        for area in ActivityBarItem.allCases {
            let bound = MenuAreaPolicy.registeredKeys.filter { MenuAreaPolicy.owner(of: $0) == area }
            if bound.isEmpty {
                XCTAssertTrue(
                    Self.areasWithoutMenuCommands.contains(area),
                    "\(area.rawValue) 区没有任何登记项 ⇒ 这条联动在它上面是空转"
                        + "（新加的区若确实还没有区专属菜单命令，把它登记进 `areasWithoutMenuCommands` 并写明理由）"
                )
            } else {
                XCTAssertFalse(
                    Self.areasWithoutMenuCommands.contains(area),
                    "\(area.rawValue) 已经有登记项了 ⇒ 豁免条目陈旧，请从 `areasWithoutMenuCommands` 删掉它"
                )
            }
        }
    }

    // MARK: - ② 表与菜单键表不许脱钩

    /// 登记进联动的键**必须是菜单键表里的键**：`MainMenuLocalizer` 是按**标题**反查键的
    /// （`MenuLocalization.key(forTitle:)` 只在 `menuKeys + systemMenuTitles` 里找）——
    /// 键不在那张表里，反查就永远认不出来 ⇒ 联动**静默失效**（页面上看不出任何异常）。
    func testRegisteredKeysAreMenuKeys() {
        for key in MenuAreaPolicy.registeredKeys {
            XCTAssertNotNil(MenuLocalization.key(forTitle: LocalizedStrings.text(key, language: .simplifiedChinese)),
                            "中文标题反查不到键 \(key) —— 联动会静默失效")
            XCTAssertTrue(MenuLocalization.menuKeys.contains(key), "\(key) 不在 MenuLocalization.menuKeys 里")
        }
    }

    /// 键**不许撞标题**：两个键的标题相同 ⇒ 反查会认成先出现的那个，联动就作用在错的项上。
    func testBoundKeysHaveDistinctTitles() {
        for language in AppLanguage.allCases {
            let titles = MenuAreaPolicy.registeredKeys.map { LocalizedStrings.text($0, language: language) }
            XCTAssertEqual(Set(titles).count, titles.count, "\(language.rawValue) 下登记键的标题有重复")
        }
    }

    // MARK: - ③ 通知名（两端的唯一接口）

    func testActivityChangeNotificationName() {
        XCTAssertEqual(Notification.Name.doyahActivityItemChanged.rawValue, "doyah.activityItemChanged")
    }

    // MARK: - ④ 接线（源锚点：动作那一半真的做了）

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    /// 取 `anchor` 起、**配对花括号**圈住的那一段（即锚点所在函数的函数体 / 闭包体）。
    ///
    /// 为什么不再用「锚点 + 固定 N 个字符」：那是**魔数窗口** —— 函数里插几行就会把要找的语句
    /// 挤出窗口，判据**假红**、且与源码对错无关（HIST-2 在 `selectActivityItem` 里插了 3 行
    /// 注释与 `syncLowerPaneTabWithSegment()` 调用，就把 900 的窗口挤爆了）。
    /// 改成跟着函数体走：锚点后的第一个 `{` 起、到与它配对的 `}` 为止 —— 函数里增删多少行都不影响，
    /// 判据只随「那句还在不在这个函数里」变化。
    private func functionBody(in source: String, from anchor: String) -> Substring? {
        guard let anchorRange = source.range(of: anchor),
              let openBrace = source[anchorRange.lowerBound...].firstIndex(of: "{"),
              let body = balancedBlock(in: source, from: openBrace) else { return nil }
        return body
    }

    /// 从 `openBrace` 起，返回与它配对的 `}` **之前**的整段（含首尾花括号）。
    private func balancedBlock(in source: String, from openBrace: String.Index) -> Substring? {
        var depth = 0
        var index = openBrace
        while index < source.endIndex {
            switch source[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return source[openBrace...index] }
            default: break
            }
            index = source.index(after: index)
        }
        return nil
    }

    /// 新建查询 = 先切到数据库区再建页签。**只做菜单显示联动是不够的**：快捷键 ⌘T 与命令面板
    /// 不经过菜单项，页签仍会建在看不见的区里。
    func testNewQuerySwitchesToDatabaseArea() throws {
        let state = try source("App/AppState.swift")
        guard let body = functionBody(in: state, from: "func newQueryTab() {") else {
            return XCTFail("`newQueryTab()` 不在了 —— 锚点变了就更新这条判据，不要删掉它")
        }
        XCTAssertTrue(body.contains("selectActivityItem(.database)"),
                      "`newQueryTab()` 没有先切到数据库区 —— 在工作区里点「新建查询」会建在看不见的地方")
    }

    /// 换区必须广播（菜单层不持有 `AppState`，这是两端之间唯一的接口）。
    func testSelectionPostsActivityChange() throws {
        let state = try source("App/AppState.swift")
        guard let body = functionBody(in: state, from: "func selectActivityItem(") else {
            return XCTFail("`selectActivityItem(_:)` 不在了 —— 它是选中区的唯一写入口，别改名")
        }
        XCTAssertTrue(body.contains("NotificationCenter.default.post(name: .doyahActivityItemChanged"),
                      "换区没有广播 ⇒ 菜单显示不会跟着变")
    }

    /// 菜单层真的按区改 `isHidden`，而且**不是**用 SwiftUI 条件菜单项（叶子项不重建 ⇒ 条件不生效）。
    func testMenuLayerHidesItemsByArea() throws {
        let localizer = try source("App/MainMenuLocalizer.swift")
        XCTAssertTrue(localizer.contains("static func syncAreaVisibility("), "缺按区对齐显示的入口")
        XCTAssertTrue(localizer.contains("item.isHidden = shouldHide"), "没有真的改菜单项的显示")
        XCTAssertTrue(localizer.contains("MenuLocalization.key(forTitle: item.title)"),
                      "没有按标题反查键 ⇒ 认不出登记过的项")
        XCTAssertTrue(localizer.contains("MenuAreaPolicy.owner(of: key) != nil"),
                      "没有只碰登记过的键 ⇒ 系统菜单与未登记项可能被误藏")
        XCTAssertTrue(localizer.contains("forName: .doyahActivityItemChanged"), "没有订阅换区广播")
        // 菜单被 SwiftUI 重建后 `isHidden` 会回到初值 ⇒ `apply`（语言自愈那条路）里也要对齐一次。
        XCTAssertTrue(localizer.contains("applyVisibility(mainMenu, area: lastKnownArea)"),
                      "菜单重建后没有重新对齐显示")
    }

    /// **启动就按当前呈现的功能决定菜单项**（2026-10-02 需求提出者原话：「应用启动时就该检查当前默认
    /// 呈现的是那个功能，来决定菜单项」）。菜单层不持有 `AppState` ⇒ 由窗口把权威值喂给它，
    /// 并且不依赖「观察者装好了没 / 菜单建好了没」的先后。
    func testWindowFeedsCurrentAreaAtLaunch() throws {
        let window = try source("App/Views/MainWindow.swift")
        XCTAssertTrue(window.contains("MainMenuLocalizer.syncAreaVisibility(appState.selectedActivityItem)"),
                      "启动时没有把当前活动栏项喂给菜单层 ⇒ 首屏菜单项与默认呈现的功能不一致")
        XCTAssertTrue(window.contains(".onChange(of: appState.selectedActivityItem)"),
                      "换区后没有从窗口这条线再同步一次（广播那条路之外的兜底）")
    }

    /// 反查键是按**标题**认的 ⇒ 标题改完要再对齐一次，否则「启动那一刻标题还没本地化」会漏掉项。
    func testApplyRechecksVisibilityAfterRetitle() throws {
        let localizer = try source("App/MainMenuLocalizer.swift")
        guard let body = functionBody(in: localizer, from: "private static func apply(_ language: AppLanguage) {") else {
            return XCTFail("`apply(_:)` 不在了 —— 锚点变了就更新这条判据")
        }
        guard let retitle = body.range(of: "let changed = retitle(mainMenu, to: language)") else {
            return XCTFail("`retitle` 那一步不在了 —— 锚点变了就更新这条判据")
        }
        let after = body[retitle.upperBound...]
        XCTAssertTrue(after.contains("applyVisibility(mainMenu, area: lastKnownArea)"),
                      "改完标题没有重新对齐显示 —— 标题还没本地化的那一刻会认不出登记过的项")
    }

    /// 浏览器页签长在工作区（队列 `L-149`）⇒ 点菜单建页签前先切区，与「新建查询」同一口径。
    func testNewBrowserTabSwitchesToWorkspaceArea() throws {
        let commands = try source("App/DoyahStudioCommands.swift")
        guard let body = functionBody(in: commands, from: "Button(L(.menuNewBrowserTab))"),
              let openTab = body.range(of: "workspaceBrowser.openBrowserTab()") else {
            return XCTFail("浏览器页签那枚菜单项不在了 —— 锚点变了就更新这条判据")
        }
        let before = body[body.startIndex..<openTab.lowerBound]
        XCTAssertTrue(before.contains("selectActivityItem(.workspace)"),
                      "新建浏览器页签没有先切到工作区 —— 页签会建在看不见的区里")
    }
}
