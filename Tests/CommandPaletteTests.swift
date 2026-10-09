import XCTest
@testable import DoyahCore

/// 命令面板的匹配与排序（FR-EDIT-25）。
///
/// 面板好不好用几乎全在这层：缩写要能命中、中文要能命中、**顺序要稳定**
/// （用户会记"按两下 ↓ 再回车"这条最省事的路径）。
final class CommandPaletteTests: XCTestCase {

    private let items: [CommandPalette.Item] = [
        .init(id: "newQuery", title: "新建查询", keywords: ["new query", "nq"], category: "查询"),
        .init(id: "execute", title: "执行", keywords: ["execute", "run"], category: "查询"),
        .init(id: "check", title: "语法检查", keywords: ["check", "explain"], category: "查询"),
        .init(id: "format", title: "格式化 SQL", keywords: ["format", "fmt"], category: "查询"),
        .init(id: "exportCSV", title: "导出 CSV", keywords: ["export", "csv"], category: "结果"),
        .init(id: "switchConnection", title: "切换连接", keywords: ["connection", "conn"], category: "连接"),
        .init(id: "openTable", title: "打开表…", keywords: ["open table", "browse"], category: "对象"),
        .init(id: "agentSQL", title: "用自然语言生成 SQL", keywords: ["agent", "nl2sql"], category: "智能体"),
    ]

    private func ids(_ query: String, limit: Int = 50) -> [String] {
        CommandPalette.search(query, in: items, limit: limit).map(\.item.id)
    }

    // MARK: 命中

    /// 空查询返回全部（面板刚打开要能看到有什么可用），且顺序稳定。
    func testEmptyQueryReturnsEverythingInOrder() {
        XCTAssertEqual(ids(""), items.map(\.id))
        XCTAssertEqual(ids("   "), items.map(\.id))
    }

    func testExactTitleComesFirst() {
        XCTAssertEqual(ids("执行").first, "execute")
        XCTAssertEqual(ids("格式化 SQL").first, "format")
    }

    /// 前缀优先于子串：输入「导」时「导出 CSV」应在前。
    func testPrefixBeatsSubstring() {
        let result = ids("导出")
        XCTAssertEqual(result.first, "exportCSV")
    }

    func testChineseSubstringMatches() {
        XCTAssertTrue(ids("语言").contains("agentSQL"), "「语言」应当命中「用自然语言生成 SQL」")
        XCTAssertTrue(ids("检查").contains("check"))
    }

    /// 英文缩写：`nq` → 新建查询（关键词）、`fmt` → 格式化。
    func testAcronymAndKeywordMatching() {
        XCTAssertEqual(ids("nq").first, "newQuery")
        XCTAssertEqual(ids("fmt").first, "format")
        XCTAssertEqual(ids("csv").first, "exportCSV")
    }

    /// 子序列：跳字输入也要有结果（否则用户会觉得"搜不到"）。
    /// 用真实能命中的例子，而不是随手编的字母（我第一版编了 `gsh`，没有任何标题含这三个字符）。
    func testSubsequenceMatching() {
        XCTAssertTrue(ids("格S").contains("format"), "「格」+「S」是「格式化 SQL」的子序列")
        XCTAssertTrue(ids("切连").contains("switchConnection"), "「切」+「连」是「切换连接」的子序列")
        // `格S` 实际命中的是**首字母缩写档**：`格` 是「格式化」的词首、`S` 是 `SQL` 的词首 ——
        // 缩写规则比子序列更贴切，所以先命中它（我第一版期望"子序列档"，又是期望写错）。
        let match = try? XCTUnwrap(CommandPalette.search("格S", in: items).first { $0.item.id == "format" })
        XCTAssertEqual(match?.score, CommandPalette.Score.acronym)
    }

    func testNoMatchReturnsEmpty() {
        XCTAssertTrue(ids("zzzzzz").isEmpty)
    }

    /// 大小写不敏感。
    func testCaseInsensitive() {
        XCTAssertEqual(ids("FMT").first, "format")
        XCTAssertEqual(ids("Csv").first, "exportCSV")
    }

    // MARK: 排序稳定性

    /// 同分时按标题再按 id 排序 —— 不能依赖数组顺序（那是实现细节，用户看到的是"每次不一样"）。
    func testOrderIsStableForEqualScores() {
        let sameScore: [CommandPalette.Item] = [
            .init(id: "b", title: "导出 B"),
            .init(id: "a", title: "导出 A"),
            .init(id: "c", title: "导出 A"),
        ]
        XCTAssertEqual(CommandPalette.search("导出", in: sameScore).map(\.item.id), ["a", "c", "b"])

        // 打乱输入顺序，结果仍然一致
        XCTAssertEqual(CommandPalette.search("导出", in: sameScore.reversed()).map(\.item.id), ["a", "c", "b"])
    }

    func testScoreOrderingAcrossKinds() {
        let query = "格式"
        let match = CommandPalette.search(query, in: items).first
        XCTAssertEqual(match?.item.id, "format")
        // 「格式化 SQL」以「格式」**开头** → 前缀档（比子串更高）。我第一版写成"子串档"，
        // 是期望写错了 —— 实现给的档位更准。
        XCTAssertEqual(match?.score, CommandPalette.Score.prefix)
    }

    func testLimitIsRespected() {
        XCTAssertEqual(CommandPalette.search("", in: items, limit: 3).count, 3)
        XCTAssertEqual(CommandPalette.search("查询", in: items, limit: 1).count, 1)
    }

    // MARK: 高亮

    /// 高亮位置要能对上（界面据此加粗）：子串命中是连续区间。
    func testHighlightPositionsForSubstring() throws {
        let match = try XCTUnwrap(CommandPalette.search("格式", in: items).first { $0.item.id == "format" })
        XCTAssertEqual(match.highlighted, [0, 1], "「格式化 SQL」的前两个字符")

        let acronym = try XCTUnwrap(CommandPalette.search("fmt", in: items).first { $0.item.id == "format" })
        XCTAssertEqual(acronym.highlighted, [], "关键词命中时标题没有可高亮的位置")
    }

    /// 面板上要按需求列出的那几类命令**都能被搜到** —— 这是需求覆盖度的可测形式。
    func testRequiredCommandsAreReachable() {
        for (query, expected) in [
            ("新建查询", "newQuery"), ("执行", "execute"), ("检查", "check"),
            ("格式化", "format"), ("导出", "exportCSV"), ("切换连接", "switchConnection"), ("打开表", "openTable"),
        ] {
            XCTAssertEqual(ids(query).first, expected, "「\(query)」应当命中 \(expected)")
        }
    }
}

/// **面板的搜索范围**（队列 `L-170`，需求提出者 2026-10-03 定案）：
/// 只有两类 —— **当前工作区里的文件** + **Doyah Studio 自带的命令**。
///
/// 判据三层（照「用户可见的小行为也要判据」那套写法）：
///  ① **项的身份证**：工作区文件项的 id 形状只有一处（`CommandPalette.FileID`），
///     正反解析成对；命令项默认 `scope = .command`（老调用点不受影响）。
///  ② **分组规则**：空组不出标题；两组都在时按「最强命中更硬的那组在前」；
///     同分 ⇒ 命令在前（确定性 —— 不随数组顺序摇）。
///  ③ **接线（源锚点）**：面板真的把工作区文件名交给引擎（`WorkspaceSearch.findFileNames`）、
///     真的按 `scope` 分派（文件 → `openFile(at:line:)`），且**没有**去搜范围外的东西
///     （对象树 / 笔记 / 内容检索）。
final class CommandPaletteWorkspaceScopeTests: XCTestCase {

    private func item(_ id: String, _ title: String, keywords: [String] = []) -> CommandPalette.Item {
        CommandPalette.Item(id: id, title: title, keywords: keywords)
    }

    private func match(_ item: CommandPalette.Item, score: Int) -> CommandPalette.Match {
        CommandPalette.Match(item: item, score: score, highlighted: [])
    }

    // MARK: ① 项的身份证

    func testFileIDRoundTripsAndRejectsOtherIDs() {
        let id = CommandPalette.FileID.make(relativePath: "App/Views/MainWindow.swift")
        XCTAssertEqual(id, "file:App/Views/MainWindow.swift")
        XCTAssertEqual(CommandPalette.FileID.relativePath(from: id), "App/Views/MainWindow.swift")
        XCTAssertTrue(CommandPalette.FileID.isFile(id))

        // 命令 id 不是文件项；空路径也不是。
        XCTAssertNil(CommandPalette.FileID.relativePath(from: "format"))
        XCTAssertFalse(CommandPalette.FileID.isFile("format"))
        XCTAssertNil(CommandPalette.FileID.relativePath(from: CommandPalette.FileID.prefix))
    }

    func testScopeDefaultsToCommand() {
        XCTAssertEqual(item("format", "格式化 SQL").scope, .command)
        let fileItem = CommandPalette.Item(
            id: CommandPalette.FileID.make(relativePath: "README.md"),
            title: "README.md",
            scope: .workspaceFile
        )
        XCTAssertEqual(fileItem.scope, .workspaceFile)
    }

    // MARK: ② 分组规则

    func testEmptyGroupsProduceNoHeader() {
        XCTAssertTrue(CommandPalette.grouped(commands: [], files: []).isEmpty)

        let commands = [match(item("format", "格式化 SQL"), score: 800)]
        XCTAssertEqual(CommandPalette.grouped(commands: commands, files: []).map(\.kind), [.commands])

        let files = [match(item("file:README.md", "README.md"), score: 1000)]
        XCTAssertEqual(CommandPalette.grouped(commands: [], files: files).map(\.kind), [.workspaceFiles])
    }

    func testHarderHitWinsTheTopGroup() {
        let commands = [match(item("format", "格式化 SQL"), score: CommandPalette.Score.substring)]
        let files = [match(item("file:README.md", "README.md"), score: CommandPalette.Score.exact)]
        XCTAssertEqual(
            CommandPalette.grouped(commands: commands, files: files).map(\.kind),
            [.workspaceFiles, .commands],
            "文件名全等命中（1000）比命令的子串命中（600）硬 ⇒ 文件组在前"
        )
    }

    func testTieGoesToCommands() {
        let commands = [match(item("format", "格式化 SQL"), score: CommandPalette.Score.prefix)]
        let files = [match(item("file:格式化.md", "格式化.md"), score: CommandPalette.Score.prefix)]
        XCTAssertEqual(
            CommandPalette.grouped(commands: commands, files: files).map(\.kind),
            [.commands, .workspaceFiles],
            "同分时命令在前 —— 面板的主用途不变，规则也得有确定答案"
        )
    }

    /// 组内顺序**一个字不改**（成员与顺序的唯一出处是各自的引擎）。
    func testInnerOrderIsUntouched() {
        let commands = [
            match(item("b", "导出 B"), score: 600),
            match(item("a", "导出 A"), score: 600),
        ]
        let files = [
            match(item("file:src/a.md", "a.md"), score: 300),
            match(item("file:docs/b.md", "b.md"), score: 300),
        ]
        let groups = CommandPalette.grouped(commands: commands, files: files)
        XCTAssertEqual(groups.first(where: { $0.kind == .commands })?.matches.map(\.item.id), ["b", "a"])
        XCTAssertEqual(groups.first(where: { $0.kind == .workspaceFiles })?.matches.map(\.item.id),
                       ["file:src/a.md", "file:docs/b.md"])
    }

    /// 端到端：命令与文件同时命中时，走的是**同一个档位比较**（不是写死的组序）。
    func testRealisticQueryPairs() {
        let items: [CommandPalette.Item] = [
            .init(id: "format", title: "格式化 SQL", keywords: ["format", "fmt"]),
        ]
        let fileItems: [CommandPalette.Item] = [
            .init(id: CommandPalette.FileID.make(relativePath: "笔记/格式化.md"), title: "格式化.md",
                  keywords: ["笔记/格式化.md"], scope: .workspaceFile),
            .init(id: CommandPalette.FileID.make(relativePath: "db/SQL.md"), title: "SQL.md",
                  keywords: ["db/SQL.md"], scope: .workspaceFile),
        ]

        // 敲命令名 ⇒ 命令组在前（「格式化 SQL」与「格式化.md」都是**前缀档** ⇒ 同分 ⇒ 命令在前）。
        let tied = CommandPalette.grouped(
            commands: CommandPalette.search("格式", in: items),
            files: CommandPalette.search("格式", in: fileItems)
        )
        XCTAssertEqual(tied.map(\.kind), [.commands, .workspaceFiles])

        // 敲文件名 ⇒ 文件组在前：「SQL.md」是**前缀档**（800），命令那条只到**词首档**（700）。
        let fileFirst = CommandPalette.grouped(
            commands: CommandPalette.search("sql", in: items),
            files: CommandPalette.search("sql", in: fileItems)
        )
        XCTAssertEqual(fileFirst.map(\.kind), [.workspaceFiles, .commands])
    }
}

/// 接线（源锚点）：面板的**范围**与**回车路由**写在哪一行。
///
/// 这一层判的是"两处口径不许漂开"：范围一旦被谁扩回去（或回车路由被改成一律走分派器），
/// 用户看到的就是"搜出来的东西点了没反应"。与 `FR-EDIT-25` 那批"设了标志位没人读"同族。
final class CommandPaletteWorkspaceScopeWiringTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testCatalogBuildsWorkspaceFileItemsWithoutTouchingTheStaticCommandList() throws {
        let text = try source("App/AppCommandCatalog.swift")

        guard text.contains("scope: .workspaceFile") else {
            return XCTFail("目录里没有造过 `scope: .workspaceFile` 的项 —— 面板拿不到工作区文件那一类")
        }
        guard text.contains("CommandPalette.FileID.make(relativePath:") else {
            return XCTFail("文件项的 id 不是走 `CommandPalette.FileID.make` 造的（前缀会有第二份写法）")
        }
        // 静态命令清单里**不许**出现文件项：`Scripts/check-palette-wiring.py` 按 `item(` 数命令，
        // 且要求每条都在分派器里有 case —— 文件是动态的，混进去那条门禁当场报红。
        let listStart = try XCTUnwrap(text.range(of: "static func all()"))
        let listEnd = try XCTUnwrap(text.range(of: "static func shortcutHint", range: listStart.upperBound..<text.endIndex))
        let listBlock = String(text[listStart.upperBound..<listEnd.lowerBound])
        XCTAssertFalse(listBlock.contains("FileID"), "命令清单里混进了工作区文件项")
    }

    func testPaletteRoutesByScopeAndOnlySearchesTheOpenWorkspace() throws {
        let text = try source("App/Views/CommandPaletteView.swift")

        guard text.contains("CommandPalette.grouped(commands:") else {
            return XCTFail("面板没有用 `CommandPalette.grouped` 分组 —— 两类结果会按分值混着排")
        }
        guard text.contains("WorkspaceSearch.findFileNames(in: root, query: needle)") else {
            return XCTFail("工作区文件名没有交给引擎（`WorkspaceSearch.findFileNames`）—— 界面自己写了一套匹配")
        }
        guard text.contains("case .workspaceFile:") , text.contains("openWorkspaceFile(id:") else {
            return XCTFail("回车没有按 `scope` 分开路由 —— 文件项会被丢进命令分派器（点了没反应）")
        }
        guard text.contains("workspaceTabs.openFile(at: url, line: nil)") else {
            return XCTFail("文件项没有真的打开文件（`openFile(at:line:)`）")
        }
        // 范围外的一律不碰（定案：只做工作区文件 + 自带命令）。
        XCTAssertFalse(text.contains("findContents"), "面板不许搜内容（那是 `FR-EDIT-44` 标头搜索框的范围）")
        XCTAssertFalse(text.contains("selectedTreeObject"), "面板不许搜对象树")
        XCTAssertFalse(text.contains("NotesStore"), "面板不许搜笔记")
    }
}


/// **窗口标题与标题栏搜索栏**（FR-EDIT-37，2026-09-30 需求提出者）。
///
/// 需求两半：① 主界面标题跟着活动栏走（`Doyah Studio - <视图名>`）；② 标题后面居中放一个搜索栏。
///
/// 判据三层（照「用户可见的小行为也要判据」那套写法）：
///  ① **拼装**：`WindowTitle.text` 是唯一出口，分隔符只在它那里；
///  ② **派生**：每个活动栏项都有中英两份标题名（新增项不许悄悄没有标题）；
///  ③ **接线（源锚点）**：`MainWindow` 真把标题交给 `navigationTitle`、把搜索栏放在工具条**
///     正中**位（`.principal`，宽度由 `TitleBarSearchLayout` 给 —— 队列 `L-141`），
///     并在回车时把词交给**命令面板**（不另做一套搜索）。
final class WindowTitleConventionTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    // MARK: ① 拼装

    func testTitleIsBrandPlusViewName() {
        XCTAssertEqual(WindowTitle.text(brand: "Doyah Studio", suffix: "Database"), "Doyah Studio - Database")
        // 分隔符只有一处出处：两段之间恰好是这个串（换短横 / 改空格都要在这里改）。
        XCTAssertEqual(WindowTitle.separator, " - ")
    }

    // MARK: ② 派生（逐个活动栏项，中英各一份）

    func testEveryActivityItemHasBothLanguageTitles() {
        let expected: [ActivityBarItem: (zh: String, en: String)] = [
            .database: ("数据库", "Database"),
            .workspace: ("工作区", "Workspace"),
            .notes: ("笔记", "Notes"),
            // 周报（Retro · 片 `M7-HOST`）：英文面保留产品名（需求原话那组形状就是 `- Retro`）。
            .retro: ("周报", "Retro"),
        ]
        for item in ActivityBarItem.allCases {
            guard let names = expected[item] else {
                return XCTFail("活动栏项 \(item.rawValue) 没有登记标题名 —— 新项要连标题一起加")
            }
            let zh = WindowTitle.text(
                brand: LocalizedStrings.text(.appBrand, language: .simplifiedChinese),
                suffix: LocalizedStrings.text(item.titleKey, language: .simplifiedChinese)
            )
            let en = WindowTitle.text(
                brand: LocalizedStrings.text(.appBrand, language: .english),
                suffix: LocalizedStrings.text(item.titleKey, language: .english)
            )
            XCTAssertEqual(zh, "Doyah Studio - \(names.zh)")
            // 英文界面正是需求原话给的那组形状（`Doyah Studio - Database` 这种）。
            XCTAssertEqual(en, "Doyah Studio - \(names.en)")
        }
    }

    func testBrandIsNotTranslated() {
        // 品牌名中英同值（产品名不翻译）。改这条要有意识：窗口标题与「关于」那类入口共用它。
        XCTAssertEqual(LocalizedStrings.text(.appBrand, language: .simplifiedChinese), "Doyah Studio")
        XCTAssertEqual(LocalizedStrings.text(.appBrand, language: .english), "Doyah Studio")
        // 搜索栏的占位文案两种语言都得有（空串 = 界面上一个空白的搜索框）。
        XCTAssertFalse(LocalizedStrings.text(.windowSearchPlaceholder, language: .simplifiedChinese).isEmpty)
        XCTAssertFalse(LocalizedStrings.text(.windowSearchPlaceholder, language: .english).isEmpty)
    }

    // MARK: ③ 接线（源锚点）

    func testMainWindowFeedsTitleAndCenteredSearchField() throws {
        let text = try source("App/Views/MainWindow.swift")

        guard text.contains(".navigationTitle(windowTitle)") else {
            return XCTFail("窗口标题没有接到 `navigationTitle` —— 判据锚点变了，请更新这条判据而不是删掉它")
        }
        guard text.contains("private var windowTitle: String"), text.contains("WindowTitle.text(") else {
            return XCTFail("标题不是由 `WindowTitle` 派生的（可能被写死成了另一份名字表）")
        }
        guard text.contains("appState.selectedActivityItem.titleKey") else {
            return XCTFail("标题没有跟着活动栏项走（没有取 `selectedActivityItem.titleKey`）")
        }
        guard text.contains("ToolbarItem(placement: .principal)") else {
            return XCTFail("搜索栏不在工具条的**正中**位（`.principal`）—— 需求要的是「标题后面居中」")
        }
        // 2026-10-01（队列 `L-141` 甲1）：宽度**不再交给系统**（`.searchable(placement: .toolbarPrincipal)`
        // 给的宽度与窗口宽度无关 ⇒ 窄窗口压住标题）—— 改由 `TitleBarSearchLayout` 给，
        // 锚点因此从「系统正中位」变成「自绘正中位 + 策略给宽度」。这条不删，只改判据锚点。
        guard text.contains("TitleBarSearchField(windowWidth:") else {
            return XCTFail("搜索栏没有接上宽度策略（`TitleBarSearchField`）—— 甲1 的修法就是这一步")
        }
        // 回车那一处**随搜索栏一起搬进了 `TitleBarSearchField`**（原标题栏搜索栏是系统件，
        // 现在是自绘件）⇒ 锚点跟着搬，判的是同一件事。
        let field = try source("App/Views/TitleBarSearchField.swift")
        guard field.contains("appState.presentCommandPalette(seed: appState.globalSearchQuery)") else {
            return XCTFail("回车没有把词交给命令面板 —— 搜索栏成了摆设")
        }
    }

    func testPaletteSeedsFromSearchFieldOnce() throws {
        let text = try source("App/Views/CommandPaletteView.swift")
        guard text.contains("appState.commandPaletteSeedQuery"), text.contains("query = seed") else {
            return XCTFail("命令面板没有读标题栏搜索栏带进来的初始查询")
        }
        guard text.contains("appState.commandPaletteSeedQuery = nil") else {
            return XCTFail("种子没有在面板退出时清掉 —— 下一次 ⌘K 会带着上一次的词")
        }
    }
}
