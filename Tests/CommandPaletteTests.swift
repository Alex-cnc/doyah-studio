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
