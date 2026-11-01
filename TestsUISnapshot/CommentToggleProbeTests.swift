import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 注释切换（`FR-STD-WS-EDIT-008` · ⌘/）的 **App 内按键探针**。
///
/// ## 为什么要有它
///
/// Core 侧 `Tests/CodeCommentToggleTests` 判的是 `CodeCommentToggling.plan` 这个纯函数 ——
/// 它全绿照样拦不住「⌘/ 根本没走到这个函数」（视图没接、掩码判错、键被上层吃掉）。
/// 本仓已经栽过两次同形状的坑（⌘L 那条掩码里混进 `.capsLock`、多光标零长度选区），
/// 所以这里**只判按键到正文**：真 `CodeEditorView` 装进 `UISnapshot.LiveHost`，
/// 拿到真 `CodeTextView`，打一个真 ⌘/，断言 `string` / 选区。
///
/// ## 判什么（每条都是行为面）
///
/// ① 加注释：光标所在行前面出现**这门语言登记的**行注释符 + 一个空格；
/// ② **注释符只从语言表来**：同一个按键在 SQL / Swift / Python 上得到三种不同的符号，
///    而且每次都与 `CodeLanguageRegistry.definition(of:).syntax.comments` 里那一项**逐字相等** ——
///    视图自己写死一个 `//` 就必然在这三条里红一条；
/// ③ 缩进保持：注释符插在缩进**之后**，不是绝对行首；
/// ④ 空行不动：多行选区里那一行空行不许被写成 `-- `（只留空白 / 空行仍然是空行）；
/// ⑤ 再按一次取消：注释符**连同它后面那一个空格**一起去掉（不然来回切会一点点往右挪）；
/// ⑥ 没登记行注释符的语言（今天 = Markdown / HTML / CSS / JSON）：⌘/ **不吞**，正文一字不动。
///
/// ## 判红自证（红 → 逐字节还原 → 绿）
///
/// 把 `Core/CodeCommentToggle.swift` 的
/// `guard let token = syntax.comments.first(where: { $0.isLine })?.open, !token.isEmpty else { return nil }`
/// 临时改成 `let token = "//"`（＝核心自己写死注释符）：
/// 红 —— 本族 **6 条全红**：SQL 那几条得到 `// select 1;`、Swift 之外的语言全部用了 `//`、
/// Markdown（登记表里没有行注释符）变成「被吞了且写入了 `// `」。
/// 用 `git checkout -- Core/CodeCommentToggle.swift` 逐字节还原后同一批用例转绿。
///
/// 跑法：`env DOYAH_UI_SNAPSHOT=1 swift test --filter CommentToggleProbeTests`
final class CommentToggleProbeTests: XCTestCase {

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
        XCTAssertEqual(textView.string, text, "编辑器里应当是夹具那段文本")
        XCTAssertTrue(host.window.makeFirstResponder(textView), "编辑器拿不到第一响应者")
        return (host, textView)
    }

    /// 这门语言**登记表里**的行注释符（判据的期望值从这里取，不从被测量自己取）。
    private func registryLineToken(_ language: TextLanguage) throws -> String {
        let syntax = CodeLanguageRegistry.definition(of: language).syntax
        return try XCTUnwrap(
            syntax.comments.first(where: { $0.isLine })?.open,
            "语言表里 \(language.rawValue) 没有登记行注释符 —— 夹具选错了语言"
        )
    }

    private func commandSlash(windowNumber: Int) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: "/",
            charactersIgnoringModifiers: "/",
            isARepeat: false,
            keyCode: 44
        )!
    }

    // MARK: - ① 加注释：光标那一行

    @MainActor
    func testCommandSlashCommentsCaretLine() throws {
        let text = "select 1;\nfrom x;\n"
        let token = try registryLineToken(.sql)
        let (host, tv) = try makeEditor(text: text, language: .sql)
        tv.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertTrue(tv.performKeyEquivalent(with: commandSlash(windowNumber: host.window.windowNumber)),
                      "⌘/ 没被编辑器接住（需求 ① 的入口是空的那一类静默失效）")
        XCTAssertEqual(tv.string, "\(token) select 1;\nfrom x;\n",
                       "光标那一行没被注释 / 注释到了别的行")
        XCTAssertEqual(tv.selectedRange().location, token.count + 1,
                       "光标应当跟着行首插进去的「注释符 + 空格」右移，仍停在原来那个字前面")
    }

    // MARK: - ② 注释符只从语言表来（三种语言 = 三个不同的符号）

    @MainActor
    func testTokenComesFromRegistryForSwiftAndPython() throws {
        // 同一条按键、同一个入口，三种语言三种符号 ⇒ 符号不可能来自视图里的字面量。
        let cases: [(TextLanguage, String, String)] = [
            (.swift, "let a = 1\n", "let a = 1"),
            (.python, "x = 1\n", "x = 1"),
        ]
        for (language, text, line) in cases {
            let token = try registryLineToken(language)
            let (host, tv) = try makeEditor(text: text, language: language)
            tv.setSelectedRange(NSRange(location: 0, length: 0))
            XCTAssertTrue(tv.performKeyEquivalent(with: commandSlash(windowNumber: host.window.windowNumber)),
                          "\(language.rawValue)：⌘/ 没被接住")
            XCTAssertEqual(tv.string, "\(token) \(line)\n",
                           "\(language.rawValue)：注释符与语言登记表给的不一致"
                           + "（期望「\(token) 」，实际正文「\(tv.string)」）")
        }
    }

    // MARK: - ③ 缩进保持

    @MainActor
    func testIndentedLineKeepsItsIndent() throws {
        let text = "    select 1;\n"
        let token = try registryLineToken(.sql)
        let (host, tv) = try makeEditor(text: text, language: .sql)
        tv.setSelectedRange(NSRange(location: 6, length: 0))

        XCTAssertTrue(tv.performKeyEquivalent(with: commandSlash(windowNumber: host.window.windowNumber)))
        XCTAssertEqual(tv.string, "    \(token) select 1;\n",
                       "注释符插到了绝对行首，把缩进顶掉了")
        XCTAssertEqual(tv.selectedRange().location, 9,
                       "缩进 + 注释符 + 空格一共让光标右移了 \(tv.selectedRange().location - 6) 格（期望 3）")
    }

    // MARK: - ④ 空行不动（多行选区逐行处理）

    @MainActor
    func testBlankLineIsSkippedInsideMultiLineSelection() throws {
        let text = "a;\n\nb;\n"
        let token = try registryLineToken(.sql)
        let (host, tv) = try makeEditor(text: text, language: .sql)
        tv.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))

        XCTAssertTrue(tv.performKeyEquivalent(with: commandSlash(windowNumber: host.window.windowNumber)))
        XCTAssertEqual(tv.string, "\(token) a;\n\n\(token) b;\n",
                       "多行选区没有逐行加注释，或者把空行也写成了注释行"
                       + "（空行写 `\(token) ` 之后，再取消注释就回不到空行了）")
    }

    // MARK: - ⑤ 再按一次取消：连那个空格一起去掉

    @MainActor
    func testSecondPressRemovesTokenAndOneSpace() throws {
        let token = try registryLineToken(.sql)
        let commented = "\(token) select 1;\n"
        let (host, tv) = try makeEditor(text: commented, language: .sql)
        tv.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertTrue(tv.performKeyEquivalent(with: commandSlash(windowNumber: host.window.windowNumber)))
        XCTAssertEqual(tv.string, "select 1;\n",
                       "取消注释时没有把注释符后面的那一个空格一起去掉"
                       + "（来回切一次就多一个空格，正文会一点点往右挪）")
    }

    // MARK: - ⑥ 没登记行注释符的语言：不吞键、不动正文

    @MainActor
    func testMarkdownHandsCommandSlashBack() throws {
        // Markdown 在语言登记表里只有块注释（`<!-- -->`）或压根没有行注释符 ⇒ 核心侧返回 nil。
        // 期望值从登记表现取：将来真要给它登记一个行注释符，这条会按新口径自动改判。
        let text = "# 标题\n正文\n"
        let registered = CodeLanguageRegistry.definition(of: .markdown).syntax
            .comments.first(where: { $0.isLine })?.open
        let (host, tv) = try makeEditor(text: text, language: .markdown)
        tv.setSelectedRange(NSRange(location: 0, length: 0))

        let handled = tv.performKeyEquivalent(with: commandSlash(windowNumber: host.window.windowNumber))
        if let registered {
            XCTAssertTrue(handled, "Markdown 登记了行注释符「\(registered)」却没接住 ⌘/")
            XCTAssertEqual(tv.string, "\(registered) # 标题\n正文\n")
        } else {
            XCTAssertFalse(handled, "Markdown 没有行注释符，⌘/ 不该被吞（吞掉 = 用户按了没反应）")
            XCTAssertEqual(tv.string, text, "没有行注释符的语言，正文一个字都不许动")
        }
    }
}
