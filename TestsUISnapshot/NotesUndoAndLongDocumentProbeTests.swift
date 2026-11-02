import AppKit
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **撤销以段落为粒度 + 万行级文档可用**的机械判据（`FR-NTS-NOTE-FORMAT-001` ②③ · 契约 §15.4）。
///
/// 两种形状都**必须在真 AppKit 对象上判**，所以本文件住在 `TestsUISnapshot`（能 `@testable import DoyahStudioApp`）：
///   · ② 撤销：`allowsUndo = true` 只是把栈接上；「一次 ⌘Z 回退一段」是 `breakUndoCoalescing()` 的
///     行为 —— 只有真 `NotesTextView` + 真 `UndoManager` 才判得了（源树里出现那个方法名什么都不证明）；
///   · ③ 万行：读的是「装进真 `NSTextStorage` 要多久、编辑一个字符要不要整篇重算」，同样只有真对象有读数。
///
/// **不落快照**（不调 `UISnapshot.write` / `LiveHost.capture`）：判的是视图树上的文本与属性，不是像素。
/// **不设 `DOYAH_UI_SNAPSHOT` 门槛**：这两条不需要屏幕，`swift test` 每轮都该真跑 ——
/// 跳过不算通过，所以本文件刻意不 `XCTSkip`。
final class NotesUndoAndLongDocumentProbeTests: XCTestCase {

    // MARK: - 夹具：真 NSTextView + 真 UndoManager

    /// `NSTextView` 的撤销管理员来自 delegate（`NSTextViewDelegate.undoManager(for:)`），
    /// 由这里显式给一个 —— 依赖「窗口替我们造一个」在离屏宿主上不稳定（窗口不一定在响应链上）。
    private final class UndoHost: NSObject, NSTextViewDelegate {
        let manager = UndoManager()

        func undoManager(for view: NSTextView) -> UndoManager? { manager }
    }

    private var host: UndoHost!
    private var textView: NotesTextView!
    private var window: NSWindow!

    override func setUpWithError() throws {
        host = UndoHost()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 320),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        textView = NotesTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 320))
        textView.allowsUndo = true
        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.delegate = host
        window.contentView = textView
        window.makeKeyAndOrderFront(nil)
        XCTAssertNotNil(textView.undoManager, "前提：撤销管理员接上了（否则后面判的是空气）")
    }

    override func tearDownWithError() throws {
        window?.orderOut(nil)
        window = nil
        textView = nil
        host = nil
    }

    /// 敲一段（多次 `insertText`，模拟连续输入 —— 只调一次是判不出「合并」的）。
    ///
    /// **每个字之间让一次运行循环**：真敲键盘时每个字都是一次独立事件、AppKit 在两次事件之间
    /// 关闭上一次的撤销组；在同一个测试 tick 里连调 `insertText` 等于把整段塞进同一组，
    /// 判出来的「一次撤销退多少」就不是用户看到的那件事（第一版正是这样：一次撤销清空整篇）。
    private func type(_ text: String) {
        for character in text {
            textView.insertText(String(character), replacementRange: textView.selectedRange())
            settle()
        }
    }

    /// 让一次运行循环：AppKit 在两次事件之间关闭上一次的撤销组（见 `type` 的注释）。
    private func settle() {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.002))
    }

    /// 按一次回车（真按键也是独立一次事件 ⇒ 之后同样让一次运行循环）。
    private func pressReturn() {
        textView.insertNewline(nil)
        settle()
    }

    // MARK: - ② 撤销以段落为粒度

    /// **一次撤销回退一个段落**（契约 §15.4「一次撤销回退一个编辑事务（一段输入或一次格式操作）」）。
    ///
    /// 反例形状（本片修掉的那一档）：不调 `breakUndoCoalescing()`，AppKit 把「第一段 + 回车 + 第二段」
    /// 合并成一步 ⇒ 一次 ⌘Z 整篇消失（实测：撤销后正文为空）。
    func testOneUndoRemovesExactlyTheLastParagraph() {
        type("第一段")
        pressReturn()
        type("第二段")
        type("接着写")

        XCTAssertEqual(textView.string, "第一段\n第二段接着写")

        textView.undoManager?.undo()

        // 一次撤销 = 回到「第二段还没写」的那一刻：第一段原样在，第二段那两截一起退掉。
        XCTAssertEqual(textView.string, "第一段\n", "一次撤销应当收掉最后一段，而不是整篇")
        XCTAssertFalse(textView.string.contains("第二段"), "第二段该退掉")
        XCTAssertTrue(textView.string.contains("第一段"), "前面那一段必须留着（整篇回退就是这一条判红）")

        // 再撤一次 ⇒ 连回车一起退（段落边界本身也是一个编辑事务）。
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "第一段")
    }

    /// **格式操作自成一步**：写字之后加粗，撤销一次只退加粗，字还在。
    func testUndoAfterAFormatCommandKeepsTheText() {
        type("加粗我")
        settle()
        textView.setSelectedRange(NSRange(location: 0, length: 3))
        settle()
        textView.apply(.bold)
        settle()

        let bolded = textView.textStorage?.attribute(
            .doyahBold, at: 0, effectiveRange: nil
        ) as? Bool ?? false
        XCTAssertTrue(bolded, "前提：加粗真的落到了属性上")

        textView.undoManager?.undo()

        XCTAssertEqual(textView.string, "加粗我", "撤销格式不许把文字一起带走")
        let stillBold = textView.textStorage?.attribute(.doyahBold, at: 0, effectiveRange: nil) as? Bool ?? false
        XCTAssertFalse(stillBold, "加粗这一步该退掉")
    }

    // MARK: - ③ 万行级文档

    /// 一万行：装进真 `NSTextStorage` 要在预算内，且编辑一个字符**不该整篇重来**。
    ///
    /// 读数口径（本机 2026-11-02 实测，`swift test --filter …` 真跑）：
    ///   · 解析 + 造属性串 + 装进文本存储 = **35.4 ms**（一万行）；
    ///   · 敲一个字符后「取 span 树 + 投影回 Markdown」= **48.8 ms**。
    /// 阈值定 **1 000 ms**（实测的二十来倍）：它的用处不是量「快不快」，而是抓**量级变了** ——
    /// 任何一个环节退化成按行重复全篇扫描（O(n²)），一万行就是几十秒，这一条当场红。
    func testATenThousandLineDocumentOpensAndStaysEditable() throws {
        let lines = (1 ... 10_000).map { "第\($0)行：这一行用来量长文档的打开与编辑。" }
        let text = lines.joined(separator: "\n")

        let openStart = Date()
        let spans = NoteBodyProjection.parseInline(text)
        let attributed = NoteRichAttributes.attributed(
            from: spans,
            font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        )
        textView.textStorage?.setAttributedString(attributed)
        let openMilliseconds = Date().timeIntervalSince(openStart) * 1000

        let lineCount = textView.string.components(separatedBy: "\n").count
        XCTAssertEqual(lineCount, 10_000, "一万行要一字不少地装进来（不是截断到某一页）")
        XCTAssertLessThan(openMilliseconds, 1_000, "一万行打开耗时 \(openMilliseconds) ms，超出预算（实测 35.4 ms）")

        // 首行的属性快照：编辑尾部之后它必须原样还在（整篇重排会把它们重建一遍）。
        let headAttributes = textView.textStorage?.attributes(at: 0, effectiveRange: nil) ?? [:]
        let headFont = headAttributes[.font] as? NSFont

        let editStart = Date()
        let tail = textView.string.utf16.count
        textView.setSelectedRange(NSRange(location: tail, length: 0))
        type("结")
        // 编辑之后那一次「属性 → span 树 → Markdown 投影」就是每敲一个字的真实代价。
        let editedSpans = NoteRichAttributes.spans(from: textView.textStorage ?? NSAttributedString())
        let markdown = NoteBodyProjection.markdown(from: editedSpans)
        let editMilliseconds = Date().timeIntervalSince(editStart) * 1000

        XCTAssertTrue(textView.string.hasSuffix("结"), "字要真敲进去")
        XCTAssertTrue(markdown.contains("第1行"), "投影里要保留首行（投影不是只算尾巴）")
        XCTAssertLessThan(editMilliseconds, 1_000, "敲一个字后重算耗时 \(editMilliseconds) ms，超出预算（实测 48.8 ms）")

        let headFontAfter = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(headFontAfter, headFont, "编辑尾部不该动首行的字形（动了就是整篇重排）")
    }
}
