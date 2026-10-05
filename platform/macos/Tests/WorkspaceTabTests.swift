import XCTest
@testable import DoyahCore

/// 工作区页签的规则（FR-EDIT-35 / 36）。
final class WorkspaceTabTests: XCTestCase {

    func testOpeningSameFileReusesTab() {
        var tabs = [WorkspaceTab.home(title: "首页")]
        let first = WorkspaceTabSet.opening(path: "/tmp/a.js", in: tabs, content: "let a = 1")
        tabs = first.tabs
        XCTAssertEqual(tabs.count, 2)

        let second = WorkspaceTabSet.opening(path: "/tmp/a.js", in: tabs, content: "let a = 2")
        XCTAssertEqual(second.tabs.count, 2, "同一个文件不该开第二个页签")
        XCTAssertEqual(second.selected, first.selected)
        XCTAssertEqual(second.tabs[1].content, "let a = 1", "复用已有页签，不覆盖用户正在编辑的内容")
    }

    func testTabTitleIsFileNameAndLanguageIsDetected() {
        let tab = WorkspaceTab.file(path: "/Users/me/项目/query.sql", content: "select 1")
        XCTAssertEqual(tab.title, "query.sql")
        XCTAssertEqual(tab.language, .sql)
        XCTAssertFalse(tab.isHome)
    }

    /// Home 是工作区的落脚点：**关不掉**。
    func testHomeCannotBeClosed() {
        let home = WorkspaceTab.home(title: "首页")
        let file = WorkspaceTab.file(path: "/tmp/a.py", content: "")
        let remaining = WorkspaceTabSet.closing(id: home.id, in: [home, file])
        XCTAssertEqual(remaining.count, 2)
        XCTAssertEqual(WorkspaceTabSet.closing(id: file.id, in: [home, file]).count, 1)
    }

    /// 关闭后选中项落到右边（没有就左边）。
    func testSelectionAfterClosing() {
        let home = WorkspaceTab.home(title: "首页")
        let a = WorkspaceTab.file(path: "/tmp/a.js", content: "")
        let b = WorkspaceTab.file(path: "/tmp/b.js", content: "")
        let tabs = [home, a, b]
        XCTAssertEqual(WorkspaceTabSet.selection(afterClosing: a.id, in: tabs, selected: a.id), b.id)
        XCTAssertEqual(WorkspaceTabSet.selection(afterClosing: b.id, in: tabs, selected: b.id), a.id)
        // 关的不是当前选中项 → 选中项不变
        XCTAssertEqual(WorkspaceTabSet.selection(afterClosing: a.id, in: tabs, selected: b.id), b.id)
    }

    func testDirtyTracksContentNotABoolean() {
        var tab = WorkspaceTab.file(path: "/tmp/a.js", content: "let a = 1")
        XCTAssertFalse(tab.isDirty)
        tab.content = "let a = 2"
        XCTAssertTrue(tab.isDirty)
        tab.markSaved()
        XCTAssertFalse(tab.isDirty)
        tab.content = "let a = 3"
        XCTAssertTrue(tab.isDirty)
        // 手动改回**已保存的那份内容** → 自动不脏。
        // 布尔标记做不到这一条：它一旦置 true，用户把改动撤回去也还是"脏"。
        tab.content = "let a = 2"
        XCTAssertFalse(tab.isDirty)
    }
}

/// Home 的"最近打开"（FR-EDIT-35）。
final class WorkspaceHistoryTests: XCTestCase {

    func testRecordingFileMovesItToFrontAndDeduplicates() {
        var history = WorkspaceHistory()
        history = WorkspaceHistory.recording(file: "/a.js", into: history)
        history = WorkspaceHistory.recording(file: "/b.js", into: history)
        history = WorkspaceHistory.recording(file: "/a.js", into: history)
        XCTAssertEqual(history.files.map(\.path), ["/a.js", "/b.js"])
    }

    func testFileHistoryIsCapped() {
        var history = WorkspaceHistory()
        for index in 0..<(WorkspaceHistory.fileLimit + 5) {
            history = WorkspaceHistory.recording(file: "/file\(index).js", into: history)
        }
        XCTAssertEqual(history.files.count, WorkspaceHistory.fileLimit)
        XCTAssertEqual(history.files.first?.path, "/file\(WorkspaceHistory.fileLimit + 4).js")
    }

    func testWorkspaceHistoryIsSeparateFromFiles() {
        var history = WorkspaceHistory()
        history = WorkspaceHistory.recording(workspace: "/Users/me/project", into: history)
        XCTAssertEqual(history.workspaces.count, 1)
        XCTAssertTrue(history.files.isEmpty)
    }

    func testEmptyPathIsIgnored() {
        var history = WorkspaceHistory()
        history = WorkspaceHistory.recording(file: "   ", into: history)
        history = WorkspaceHistory.recording(workspace: "", into: history)
        XCTAssertTrue(history.files.isEmpty)
        XCTAssertTrue(history.workspaces.isEmpty)
    }

    func testRemovingEntries() {
        var history = WorkspaceHistory()
        history = WorkspaceHistory.recording(file: "/a.js", into: history)
        history = WorkspaceHistory.recording(file: "/b.js", into: history)
        history = WorkspaceHistory.removing(file: "/a.js", from: history)
        XCTAssertEqual(history.files.map(\.path), ["/b.js"])
    }

    /// 只记路径与时间 —— **不存文件内容**（否则这份历史会变成代码库的副本）。
    func testHistoryRoundTripsThroughJSONWithoutContent() throws {
        var history = WorkspaceHistory()
        history = WorkspaceHistory.recording(file: "/Users/me/project/index.ts", at: Date(timeIntervalSince1970: 1_700_000_000), into: history)
        let data = try JSONEncoder().encode(history)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("content"))
        let decoded = try JSONDecoder().decode(WorkspaceHistory.self, from: data)
        XCTAssertEqual(decoded, history)
        XCTAssertEqual(decoded.files.first?.displayName, "index.ts")
    }
}

/// Home 页签标题的约定（`L-108`；`FR-EDIT-35` 口径补充）。
///
/// 规矩：**Core 不许出现展示文案** —— 标题一律由调用点从语言表取。
/// 之前 `Core/WorkspaceTab.swift` 写死 `"Home"`，中文界面也是 Home。
final class WorkspaceHomeTitleTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    /// 标题由调用点给（Core 不猜）。
    func testTitleComesFromCaller() {
        let home = WorkspaceTab.home(title: "首页")
        XCTAssertEqual(home.title, "首页")
        XCTAssertTrue(home.isHome)
        XCTAssertEqual(home.language, .plainText)
    }

    /// 语言表两栏都有（中文「首页」/ 英文 `Home`）。
    func testLanguageTableHasBothLanguages() {
        XCTAssertEqual(LocalizedStrings.text(.workspaceTabHome, language: .simplifiedChinese), "首页")
        XCTAssertEqual(LocalizedStrings.text(.workspaceTabHome, language: .english), "Home")
    }

    /// 源锚点一：Core 里不再有写死的展示文案。
    ///
    /// 只看**代码行**（跳过 `//` 注释与文档段）—— 注释里会引用这个坏例子（`"Home"`），
    /// 拿整份文件搜子串会把自己的说明文字当成命中（这条判据初版就是这么误报的）。
    func testCoreDoesNotHardcodeDisplayTitle() throws {
        let code = try source("Core/WorkspaceTab.swift")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") }
            .joined(separator: "\n")
        guard !code.contains("\"Home\"") else {
            return XCTFail("Core 里又出现了写死的展示文案 —— 标题必须由调用点从语言表取")
        }
    }

    /// 源锚点二：宿主装配侧确实从语言表取名。
    func testAppFeedsLocalizedTitle() throws {
        let text = try source("App/WorkspaceTabsModel.swift")
        guard text.contains(".home(title: L(.workspaceTabHome))") else {
            return XCTFail("Home 页签标题没有走语言表 —— 锚点变了请更新这条判据，不要删掉它")
        }
    }
    /// 源锚点三（内测清单 `#8`）：**渲染点**也要取语言表。
    ///
    /// 模型只建一次，而切语言时根视图按 `.id(language)` 重建 —— 标题若只在**建模那一刻**算一次，
    /// 运行期切语言不会重算（实测：切英文后页签仍写「首页」，切回中文同理）。
    func testTabStripReadsHomeTitleFromLanguageTableAtRenderTime() throws {
        let text = try source("App/Views/WorkspaceTabStrip.swift")
        guard text.contains("tab.isHome ? L(.workspaceTabHome) : tab.title") else {
            return XCTFail("页签条没有在渲染时取 Home 标题 —— 切语言会停在建模那次的语言上")
        }
        guard !text.contains("Text(tab.title)") else {
            return XCTFail("页签条又把标题直接写成 `Text(tab.title)` 了（Home 会不跟着语言变）")
        }
    }
}
