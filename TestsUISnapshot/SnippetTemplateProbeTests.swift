import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 片段模板（`FR-STD-WS-NAV-005`）的 **App 内按键探针**。
///
/// ## 为什么要有它
///
/// 这一条的验收口径全在「按了之后正文变成什么」上：打触发器 → Tab 展开骨架 → 再按 Tab
/// 依次跳占位符 → 最后一格之后 Tab 回到缩进；以及在字符串 / 注释里、或带尾巴的词（`selects`）
/// 上**不许**展开。`Core/SnippetTemplate.swift` 的单测判得到 `SnippetEngine` 的纯函数，
/// 但判不到「编辑器有没有把这个键送到那一支」（`insertTab` 的第一顺位就是片段会话），
/// 也判不到「骨架到底是不是语言表里那一段」。所以这里全部打在真 `CodeTextView` 上。
///
/// ## 判什么（每条都是行为面）
///
/// ① 打 `select` 再按 Tab ⇒ 正文换成**语言登记表里那一条**解开的骨架，且光标停在第一个
///    占位符上（默认文字被选中 —— 接着打字就是替换它）；
/// ② 每按一次 Tab 依次跳到下一格；跳完最后一格再按 Tab ⇒ **回到正常缩进**（会话结束）；
/// ③ 在 SQL 字符串里 / 注释行里打触发器再按 Tab ⇒ **不展开**（只按普通 Tab 缩进）；
/// ④ 带尾巴的词（`selects`）⇒ 不展开；
/// ⑤ 大写也认：片段表只登记一行小写，打 `TABLE`（Markdown 的 `table`）同样展开
///    —— 触发词匹配不区分大小写。**SQL 的 `SELECT` 例外**：它同时命中行内灰字那条
///    `SELECT * FROM ` 补全片段，而 Tab 的次序是「灰字 → 片段」，于是被灰字先吃掉
///    （既有先后，已按「发现但未修」登记，不在本族断言）；
/// ⑥ 片段表与语言表同源：`table` 在 Markdown 有、`select` 只在 SQL 有 —— 同一串键在两个语言里
///    结论不同，且期望骨架是**从登记表现解析**出来的（视图写死一段骨架必然对不上）。
///
/// ## 判红自证（红 → 逐字节还原 → 绿）
///
/// 把 `App/Views/CodeEditorView.swift` 的 `insertTab` 里 `if expandSnippetTrigger() { return }`
/// 那一行临时删掉（＝Tab 不再走片段那一支）：
/// 红 —— ①②⑤⑥ 四条全部红（正文里没有骨架、`select` 原样留着）；
/// 用 `git checkout -- App/Views/CodeEditorView.swift` 逐字节还原后同一批用例转绿。
///
/// 跑法：`env DOYAH_UI_SNAPSHOT=1 swift test --filter SnippetTemplateProbeTests`
final class SnippetTemplateProbeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏活体宿主要显式打开：DOYAH_UI_SNAPSHOT=1（取证工具，不进每轮门禁）"
        )
    }

    private struct Harness: View {
        let tabID = UUID()
        let text: String
        let language: TextLanguage
        var body: some View {
            CodeEditorView(
                tabID: tabID,
                text: text,
                language: language,
                onTextChange: { _ in },
                onSave: {},
                onFormat: {}
            )
        }
    }

    @MainActor
    private func makeEditor(
        text: String,
        language: TextLanguage
    ) throws -> (host: UISnapshot.LiveHost<Harness>, textView: CodeTextView) {
        let host = UISnapshot.LiveHost(Harness(text: text, language: language),
                                       size: CGSize(width: 640, height: 240))
        host.pump(0.5)
        let textView = try XCTUnwrap(
            UISnapshot.LiveHost<Harness>.findViews(ofType: CodeTextView.self, in: host.hosting).first,
            "真编辑器不在宿主视图树里 —— 这条判据的入口没了"
        )
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        XCTAssertTrue(host.window.makeFirstResponder(textView), "编辑器拿不到第一响应者")
        return (host, textView)
    }

    private func tabKey(windowNumber: Int) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            isARepeat: false,
            keyCode: 48
        )!
    }

    /// 一个字符一个字符地打（走用户真正那条 `insertText(_:replacementRange: NSNotFound)`）。
    @MainActor
    private func type(_ text: String, into tv: CodeTextView) {
        for character in text {
            tv.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
        }
    }

    @MainActor
    private func pressTab(_ host: UISnapshot.LiveHost<Harness>, on tv: CodeTextView) {
        tv.interpretKeyEvents([tabKey(windowNumber: host.window.windowNumber)])
        host.pump(0.05)
    }

    /// 语言登记表里那条片段解开之后的样子（期望值从这里取，不从被测量自己取）。
    private func registered(_ trigger: String, for language: TextLanguage) throws -> SnippetBody {
        let templates = CodeLanguageRegistry.definition(of: language).snippets
        let template = try XCTUnwrap(
            templates.first { $0.trigger.lowercased() == trigger.lowercased() },
            "语言表里 \(language.rawValue) 没有登记「\(trigger)」这条片段 —— 夹具选错了语言"
        )
        return SnippetParser.parse(template.body)
    }

    // MARK: - ① 展开 + 停在第一个占位符

    @MainActor
    func testTypingTriggerThenTabExpandsSkeleton() throws {
        let expected = try registered("select", for: .sql)
        let (host, tv) = try makeEditor(text: "", language: .sql)
        type("select", into: tv)
        XCTAssertEqual(tv.string, "select", "前置：触发器应当已经打进正文")

        pressTab(host, on: tv)

        XCTAssertEqual(tv.string, expected.text,
                       "按 Tab 没把触发器换成语言表里那段骨架"
                       + "（实际正文：\(tv.string.debugDescription)）")
        let firstStop = try XCTUnwrap(expected.stops.first, "`select` 骨架里没有占位符")
        XCTAssertEqual(tv.selectedRange(), firstStop.range,
                       "展开后光标没停在第一个占位符上（默认文字应当被选中，接着打字就是替换它）")
    }

    // MARK: - ② 依次跳格，跳完回到缩进

    @MainActor
    func testTabWalksEveryPlaceholderThenReturnsToIndent() throws {
        let expected = try registered("select", for: .sql)
        let indentUnit = IndentProfile.fallback.unit
        XCTAssertGreaterThanOrEqual(expected.stops.count, 3, "`select` 骨架的占位符少于三个，夹具不再代表性")
        let (host, tv) = try makeEditor(text: "", language: .sql)
        type("select", into: tv)
        pressTab(host, on: tv)

        for (offset, stop) in expected.stops.enumerated().dropFirst() {
            pressTab(host, on: tv)
            XCTAssertEqual(tv.selectedRange(), stop.range,
                           "第 \(offset + 1) 次 Tab 没停在第 \(offset + 1) 个占位符上"
                           + "（跳到的是第 \(tv.selectedRange().location) 个字符处）")
            XCTAssertEqual(tv.string, expected.text, "跳格过程中正文不该被改（只在占位符之间移动）")
        }

        // 最后一格之后再按 Tab：收尾（光标落到骨架末尾），再下一次 Tab 回到缩进。
        pressTab(host, on: tv)
        XCTAssertEqual(tv.selectedRange().length, 0, "最后一格之后应当收起选区、只留光标")
        let afterFinish = tv.string
        pressTab(host, on: tv)
        XCTAssertEqual(tv.string, afterFinish + indentUnit,
                       "片段跳完之后 Tab 没有回到正常缩进（多吞了一个按键，用户会觉得 Tab 坏了）")
    }

    // MARK: - ③ 字符串 / 注释里不展开

    @MainActor
    func testTriggerInsideStringDoesNotExpand() throws {
        let text = "SELECT name FROM t WHERE name = 'select"
        let (host, tv) = try makeEditor(text: text, language: .sql)
        let before = tv.string

        pressTab(host, on: tv)

        XCTAssertFalse(tv.string.contains("FROM table"),
                       "在字符串里打触发器也展开了骨架 —— 会把一整段 SQL 粘进引号中间")
        XCTAssertEqual(tv.string, before + IndentProfile.fallback.unit,
                       "字符串里按 Tab 应当只是普通缩进")
    }

    @MainActor
    func testTriggerInsideCommentDoesNotExpand() throws {
        let text = "-- select"
        let (host, tv) = try makeEditor(text: text, language: .sql)
        let before = tv.string

        pressTab(host, on: tv)

        XCTAssertFalse(tv.string.contains("FROM table"), "在注释行里打触发器也展开了骨架")
        XCTAssertEqual(tv.string, before + IndentProfile.fallback.unit, "注释行里按 Tab 应当只是普通缩进")
    }

    // MARK: - ④ 带尾巴的词不展开

    @MainActor
    func testWordWithTailDoesNotExpand() throws {
        let text = "selects"
        let (host, tv) = try makeEditor(text: text, language: .sql)

        pressTab(host, on: tv)

        XCTAssertEqual(tv.string, text + IndentProfile.fallback.unit,
                       "`selects` 这种带尾巴的词被当成触发器展开了（前缀匹配写宽了）")
    }

    // MARK: - ⑤ 大写也认（片段表只登记一行小写）
    //
    // 这里用 Markdown 的 `table` 而不是 SQL 的 `select`：SQL 的 `SELECT` 同时命中**行内灰字**里
    // 那条 `SELECT * FROM ` 候选（补全片段），而 Tab 的次序是「灰字 → 片段」（见 `insertTab` 注释），
    // 于是大写 SQL 触发器会先被灰字吃掉 —— 这是两条能力的既有先后，不是片段表大小写的事。
    // 报告里已按「发现但未修」登记该冲突；本用例只判「触发词匹配不区分大小写」这一档。

    @MainActor
    func testUppercaseTriggerExpandsToo() throws {
        let expected = try registered("table", for: .markdown)
        let (host, tv) = try makeEditor(text: "", language: .markdown)
        type("TABLE", into: tv)

        pressTab(host, on: tv)

        XCTAssertEqual(tv.string, expected.text,
                       "片段表只登记了一行小写 `table`，打大写就匹配不上（关键字习惯大写的人按 Tab 没反应）")
    }

    // MARK: - ⑥ 片段表与语言表同源（同一串键在两个语言里结论不同）

    @MainActor
    func testSnippetTableIsPerLanguage() throws {
        let markdownExpected = try registered("table", for: .markdown)
        let (mdHost, mdView) = try makeEditor(text: "", language: .markdown)
        type("table", into: mdView)
        pressTab(mdHost, on: mdView)
        XCTAssertEqual(mdView.string, markdownExpected.text,
                       "Markdown 的 `table` 片段没展开（片段表没按语言取）")

        // `select` 是 SQL 的片段，Markdown 表里没有 ⇒ 只缩进，不许冒出 SQL 骨架。
        let (sqlHost, sqlView) = try makeEditor(text: "", language: .markdown)
        type("select", into: sqlView)
        pressTab(sqlHost, on: sqlView)
        XCTAssertEqual(sqlView.string, "select" + IndentProfile.fallback.unit,
                       "Markdown 里按 Tab 展开了 SQL 的骨架 —— 片段表没跟语言走")
    }
}
