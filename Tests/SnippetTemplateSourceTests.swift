import XCTest
@testable import DoyahCore

/// `FR-STD-WS-NAV-005` 的**源树判据**：片段表与语言表同源、Tab 的次序写死、会话状态住在编辑器上。
///
/// ## 为什么要有这一条
///
/// Core 侧（`SnippetParser` / `SnippetEngine` / `SnippetSession`）全绿只说明「算得对」。
/// 这条需求最容易悄悄坏掉的三处都在接线面上：
/// 1. 视图里**自己拼一份骨架** —— 于是语言表改一行、界面纹丝不动（「与语言表同源」当场不成立）；
/// 2. `insertTab` 的**次序被调乱** —— 把片段排在灰字前面，则「补全整个词」永远轮不到，
///    而功能看起来「能用」（这是最典型的假绿：两条路都通，只是通错了顺序）；
/// 3. 会话状态搬进 SwiftUI 的 `@State` —— 视图树一重建（切页签 / 主题）会话就丢，
///    用户按 Tab 时人已经在骨架外面。
final class SnippetTemplateSourceTests: XCTestCase {

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

    /// 骨架住语言表：登记在 `snippets` 单列表里，并由 `all` 合成进每条定义。
    func testSnippetTableLivesInLanguageRegistry() throws {
        let body = try text("Core/CodeLanguageDefinitions.swift")
        for anchor in [
            "private static let snippets: [String: [SnippetTemplate]]",
            "public let snippets: [SnippetTemplate]",
            ".withSnippets(snippets[$0.language.rawValue] ?? [])",
            "func withSnippets(",
            "SnippetTemplate("
        ] {
            XCTAssertTrue(body.contains(anchor), "语言表里缺少片段表的锚点：\(anchor)")
        }
        // 表里至少 sql / markdown 两族（需求 ① 点名的两个例子）。
        XCTAssertTrue(body.contains("\"sql\": ["), "语言表里没有 sql 片段")
        XCTAssertTrue(body.contains("\"markdown\": ["), "语言表里没有 markdown 片段")
    }

    /// 两个编辑器的 Tab 次序：会话 → 灰字 → 片段 → 缩进（次序就是口径）。
    func testBothEditorsOrderTabAsSessionGhostSnippetIndent() throws {
        for relative in ["App/Views/CodeEditorView.swift", "App/Views/SQLEditorView.swift"] {
            let body = try text(relative)
            guard let start = body.range(of: "override func insertTab") else {
                XCTFail("\(relative) 里没有 insertTab")
                continue
            }
            let slice = String(body[start.lowerBound...].prefix(800))
            // 灰字那一步在两个编辑器上的落点不同（工作区走 `acceptGhost()`，
            // SQL 编辑器直接问 `ghostOverlay`）—— 判的是**次序**，不是那一句的写法。
            let anchors = [
                "advanceSnippetStop()",
                relative.contains("SQL") ? "ghostOverlay.accept()" : "acceptGhost()",
                "expandSnippetTrigger()"
            ]
            var positions: [Int] = []
            for anchor in anchors {
                guard let range = slice.range(of: anchor) else {
                    XCTFail("\(relative) 的 insertTab 里缺少：\(anchor)")
                    continue
                }
                positions.append(slice.distance(from: slice.startIndex, to: range.lowerBound))
            }
            XCTAssertEqual(positions.count, anchors.count, "\(relative)：Tab 的分支不全")
            if positions.count == anchors.count {
                XCTAssertEqual(positions, positions.sorted(),
                               "\(relative)：Tab 的次序必须是 会话 → 灰字 → 片段")
            }
            // 缩进是最后一档（不吞正常输入）。
            XCTAssertTrue(slice.contains("insertIndentUnit()") || slice.contains("super.insertTab(sender)"),
                          "\(relative)：没有把「都不成立才缩进」写出来")
        }
    }

    /// 视图只取语言表里的片段表，**不带骨架字面量**（反向判据：抄一份骨架到视图里即红）。
    func testViewsNeverCarrySkeletonText() throws {
        for relative in ["App/Views/CodeEditorView.swift", "App/Views/SQLEditorView.swift"] {
            let body = try text(relative)
            XCTAssertTrue(body.contains("SnippetCatalog.templates(for:"),
                          "\(relative) 没有从语言表取片段表")
            for literal in ["FROM ${", "INSERT INTO ${", "| --- | ${", "def ${"] {
                XCTAssertFalse(body.contains(literal),
                               "\(relative) 自己抄了骨架字面量：\(literal)")
            }
        }
    }

    /// 会话状态住在编辑器上（`var snippetSession`），不是 SwiftUI 的 `@State`。
    func testSessionStateLivesOnTheTextView() throws {
        for relative in ["App/Views/CodeEditorView.swift", "App/Views/SQLEditorView.swift"] {
            let body = try text(relative)
            XCTAssertTrue(body.contains("var snippetSession: SnippetSession?"),
                          "\(relative) 没有把片段会话挂在编辑器上")
            XCTAssertFalse(body.contains("@State private var snippetSession"),
                           "\(relative) 把会话放进了 @State（视图树一重建就丢）")
            XCTAssertTrue(body.contains("if snippetSession?.noteEdit(range: range, replacementLength: newLength) == false"),
                          "\(relative) 没有把编辑回报给会话（落点会错位）")
        }
    }

    /// 掩码只有一份：片段与折叠都取 `CodeLexer.protectedSpans`，谁也不许自带引号识别。
    func testProtectedSpansHasOneOwner() throws {
        let snippet = try text("Core/SnippetTemplate.swift")
        XCTAssertTrue(snippet.contains("CodeLexer.protectedSpans(in: text, language: language)"),
                      "片段没走词法掩码（会在字符串 / 注释里粘骨架）")
        let folding = try text("Core/CodeFolding.swift")
        XCTAssertTrue(folding.contains("CodeLexer.protectedSpans(in: text, language: language)"),
                      "折叠的掩码没有转发到同一份实现")
        let lexer = try text("Core/CodeLexer.swift")
        XCTAssertTrue(lexer.contains("public static func protectedSpans("),
                      "词法器里没有这份唯一实现")
    }
}
