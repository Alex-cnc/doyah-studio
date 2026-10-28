import XCTest
@testable import DoyahCore

/// `FR-STD-WS-NAV-006` 的**源树判据**：两个编辑面共用同一份接线，且「查不到」有话说得出来。
///
/// Core 侧（`SymbolIndex`）全绿只说明「算得对」。这条需求最容易悄悄坏掉的三处都在接线面上：
/// 1. 只有一个编辑器接上了（代码文件里悬停有说明、SQL 里没有）—— 用户看到的是「同一个功能两个样」；
/// 2. 某个编辑器**自己再写一份解析**（直接调 `SymbolIndex.lookup`）—— 两份判定迟早分家；
/// 3. 「查不到」的文案没进语言表 —— 界面只能拿键名当句子，等于明说查不到这件事变成了乱码。
final class SymbolHoverSourceTests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func text(_ relative: String) throws -> String {
        let url = root.appendingPathComponent(relative)
        let body = try String(contentsOf: url, encoding: .utf8)
        XCTAssertGreaterThan(body.count, 1000, "\(relative) 读到的内容太短，扫描面可疑")
        return body
    }

    /// 工作区编辑器按当前页签语言、数据库侧固定 SQL —— 两者都走 `SymbolHoverHost`。
    func testBothEditorsConformToTheSameHost() throws {
        let code = try text("App/Views/CodeEditorView.swift")
        XCTAssertTrue(code.contains("extension CodeTextView: SymbolHoverHost"),
                      "工作区编辑器没有接上悬停/跳定义那套（两个编辑面会一个有一个没有）")
        XCTAssertTrue(code.contains("var symbolLanguage: TextLanguage { completionLanguage }"),
                      "工作区的符号语言必须是**页签的语言**（另立字段会与着色/补全分家）")

        let sql = try text("App/Views/SQLEditorView.swift")
        XCTAssertTrue(sql.contains("extension SQLTextView: SymbolHoverHost"),
                      "数据库侧编辑器没有接上同一套")
        XCTAssertTrue(sql.contains("var symbolLanguage: TextLanguage { .sql }"),
                      "数据库侧固定按 SQL 建符号表")
    }

    /// 悬停与跳转各只有一个入口，且**两个编辑器都调它**。
    func testHoverAndJumpUseTheSharedImplementation() throws {
        let shared = try text("App/Views/SymbolHover.swift")
        XCTAssertTrue(shared.contains("SymbolIndex.lookup(in: string, language: symbolLanguage, at: index)"),
                      "解析的唯一落点是 `SymbolHover.swift` 里的 `symbolLookup(atCharacterIndex:)`")
        XCTAssertTrue(shared.contains("func symbolToolTipText(at point: NSPoint) -> String?"))
        XCTAssertTrue(shared.contains("func revealDefinition(at point: NSPoint) -> Bool"))

        for (file, label) in [("App/Views/CodeEditorView.swift", "工作区编辑器"),
                              ("App/Views/SQLEditorView.swift", "SQL 编辑器")] {
            let body = try text(file)
            XCTAssertTrue(body.contains("symbolToolTipText(at: point)"),
                          "\(label) 的 tooltip 必须转发到共享实现（自己拼一份就分家了）")
            XCTAssertTrue(body.contains("revealDefinition(at:"),
                          "\(label) 的 ⌘ 点击必须走共享的 `revealDefinition(at:)`")
            XCTAssertFalse(body.contains("SymbolIndex.lookup"),
                           "\(label) 里不许自己再解析一次符号（唯一落点在 `SymbolHover.swift`）")
        }
    }

    /// ⌘ 点击是**不吞无结果**的：查不到要把这次点击交还系统（否则一次普通 ⌘ 点击变成「什么都没发生」）。
    func testCommandClickFallsThroughWhenNothingIsFound() throws {
        for file in ["App/Views/CodeEditorView.swift", "App/Views/SQLEditorView.swift"] {
            let body = try text(file)
            XCTAssertTrue(body.contains("event.modifierFlags.contains(.command)"),
                          "\(file) 没有认 ⌘ 修饰键 ⇒ 跳定义没有入口")
            XCTAssertTrue(body.contains("revealDefinition(at: point)") || body.contains("revealDefinition(at: convert(event.locationInWindow"),
                          "\(file) 的 ⌘ 分支没有落到 `revealDefinition`")
        }
    }

    /// 「查不到就明说查不到」（需求 ④）：三档理由都要有中英两种句子，界面才说得出口。
    func testMissReasonsHaveWordingInBothLanguages() throws {
        let localization = try text("Core/Localization.swift")
        for key in [".symbolNoDefinitionInFile", ".symbolNoSymbolsForLanguage"] {
            let chinese = LocalizedStrings.text(LKey(rawValue: String(key.dropFirst()))!, language: .simplifiedChinese)
            let english = LocalizedStrings.text(LKey(rawValue: String(key.dropFirst()))!, language: .english)
            XCTAssertFalse(chinese.isEmpty, "\(key) 中文句子为空")
            XCTAssertFalse(english.isEmpty, "\(key) 英文句子为空")
            XCTAssertNotEqual(chinese, english, "\(key) 中英不能同文")
            XCTAssertTrue(localization.contains(key), "语言表里找不到 \(key)")
        }
        // 六档符号类别的词也必须在表里（悬停那一句话靠它组成）。
        for key in ["symbolKindFunction", "symbolKindType", "symbolKindVariable",
                    "symbolKindTable", "symbolKindAlias", "symbolKindColumn"] {
            XCTAssertTrue(localization.contains(".\(key):"),
                          "语言表里缺 \(key) ⇒ 悬停句子里会出现键名")
        }
    }
}
