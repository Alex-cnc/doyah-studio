import AppKit
import Combine
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **工作区 Markdown 预览的界面面不变量** —— 队列 `L-137` 第三片。
///
/// ## 判的是三件界面层能机器量的事
///
/// ① **只读**：预览里不许有可编辑文本视图。需求已拍板「Markdown 是唯一真相」，
///    预览要是能改字，就立刻多出一个"哪边为准"的问题 —— 而这类问题**编译照过**。
///    判据不只报"没找到"：同一族里带**对照**（真的插一个可编辑 `NSTextView` 进去，
///    量法必须看得见它），否则"零命中"可能只是这套遍历根本看不见东西。
/// ② **跟随滚动落点**：光标行 → 顶层块下标，必须与契约层 `anchor(forSourceLine:)`
///    同解（界面层不许自己数行）。
/// ③ **如实报数**：截断时才有计数，且与 `report` 逐字段相等；没截断就一行不多。
///
/// ## 边界（如实登记）
///
/// · 不验观感（字号 / 间距好不好看）—— 那是快照 + 读图那一族；
/// · `.task(id:)` 在离屏宿主里不会自己转 run loop，所以本轮用一个**有上限的自旋**
///   放它跑完（`settle`）；高度断言留了余量，不拿像素级相等当判据；
/// · 不验链接可点（`L-137` 剩余③ 未落，链接还不可点）。
final class MarkdownPreviewProbeTests: XCTestCase {

    // MARK: 取样文档

    /// 覆盖 GFM 的主要块型（标题 / 段落 / 嵌套列表 / 表格 / 围栏 / 引用 / 分隔线）。
    private let sample = """
    # 标题

    第一段 **粗体** 与 `代码`。

    - 甲
    - 乙
      - 乙一

    | 列 | 值 |
    | --- | ---: |
    | a | 1 |

    ```swift
    let x = 1
    ```

    > 引用

    ---
    """

    // MARK: 装配（全程离屏：不需要窗口、不渲染位图、不需要人在场）

    @MainActor
    private func host<V: View>(_ view: V, width: CGFloat = 720) -> NSHostingController<V> {
        let controller = NSHostingController(rootView: view)
        controller.view.frame = NSRect(x: 0, y: 0, width: width, height: 900)
        controller.view.layoutSubtreeIfNeeded()
        return controller
    }

    /// 放 SwiftUI 的 `.task(id:)` 跑完：离屏宿主不会自己转 run loop。
    @MainActor
    private func settle(_ controller: NSHostingController<some View>, seconds: TimeInterval = 0.4) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            controller.view.layoutSubtreeIfNeeded()
        }
    }

    /// 递归收集整棵树里的文本视图（对照用例证明它**看得见**真插进去的 `NSTextView`）。
    @MainActor
    private func textViews(in view: NSView) -> [NSTextView] {
        var found: [NSTextView] = []
        if let textView = view as? NSTextView { found.append(textView) }
        for subview in view.subviews {
            found.append(contentsOf: textViews(in: subview))
        }
        return found
    }

    @MainActor
    private func preview(_ text: String) -> MarkdownPreviewView {
        MarkdownPreviewView(text: text, language: .markdown, cursor: MarkdownPreviewCursorModel())
    }

    // MARK: ① 只读

    @MainActor
    func testPreviewHasNoEditableTextSurface() {
        let controller = host(preview(sample))
        settle(controller)
        let editors = textViews(in: controller.view)
        XCTAssertTrue(
            editors.isEmpty,
            "预览里不该有文本视图（只读 = 不引 NSTextView）：实测 \(editors.count) 个，"
                + "可编辑 \(editors.filter(\.isEditable).count) 个"
        )
        XCTAssertEqual(textViews(in: controller.view).filter { $0 is CodeTextView }.count, 0)
    }

    /// **对照（判据必须能判红）**：同一套遍历，插一个真可编辑的 `NSTextView` 进去就得看得见。
    @MainActor
    func testProbeSeesAnEditableTextSurface() {
        let host = host(EditableProbeRepresentable())
        host.view.layoutSubtreeIfNeeded()
        let editors = textViews(in: host.view)
        XCTAssertFalse(editors.isEmpty, "量法看不见真插进去的 NSTextView ⇒ 上面那条的\"零命中\"不算数")
        XCTAssertTrue(editors.contains(where: \.isEditable))
    }

    // MARK: ② 跟随滚动的落点

    func testScrollTargetFollowsTheContractAnchor() {
        let document = MarkdownDocument.parse(sample)
        for line in 1...max(1, document.lineCount) {
            XCTAssertEqual(
                MarkdownPreviewContent.scrollTarget(forSourceLine: line, in: document),
                document.anchor(forSourceLine: line)?.blockIndex,
                "第 \(line) 行：界面层的落点必须与契约层锚点同解（界面不许自己数行）"
            )
        }
        XCTAssertNil(MarkdownPreviewContent.scrollTarget(forSourceLine: 0, in: document))
        XCTAssertNil(MarkdownPreviewContent.scrollTarget(forSourceLine: document.lineCount + 1, in: document))
    }

    // MARK: ③ 如实报数

    func testTruncationCountsOnlyWhenTheReportSaysSo() {
        let clean = MarkdownDocument.parse(sample)
        XCTAssertNil(MarkdownPreviewContent.truncationCounts(clean.report))

        let truncated = MarkdownDocument.parse(
            "# 标题\n\n正文\n更多正文\n",
            limits: MarkdownParseLimits(maxLines: 1, maxBlocks: 1)
        )
        let counts = MarkdownPreviewContent.truncationCounts(truncated.report)
        XCTAssertNotNil(counts, "真截断了就必须报出来（不许静默少画）")
        XCTAssertEqual(counts?.skipped, truncated.report.skippedLineCount)
        XCTAssertEqual(counts?.unparsed, truncated.report.unparsedLineCount)
    }

    // MARK: 光标行（同一行重复上报不许反复发布）

    @MainActor
    func testCursorModelPublishesOnlyOnChange() {
        let model = MarkdownPreviewCursorModel()
        var published: [Int] = []
        let token = model.$line.dropFirst().sink { published.append($0) }
        defer { token.cancel() }

        model.report(line: 1)
        model.report(line: 3)
        model.report(line: 3)
        model.report(line: 0)
        model.report(line: -2)

        XCTAssertEqual(model.line, 3, "越界值必须丢掉（宁可不动，也不猜一个位置）")
        XCTAssertEqual(published, [3], "同一行重复上报不许发布：实测 \(published)")
    }

    // MARK: 内容决定高度（证明真的画出来了，不是一张空底）

    /// 量的**是预览真渲染的那一份**（`MarkdownBlocksView`）——
    /// 预览自身外面套着 `ScrollView`，它按提议高度撑满，量不出内容差异
    /// （第一版判据就是这么判红的：10000.0 不比 10000.0 高）。
    @MainActor
    func testBlocksRenderTallerWithMoreContent() {
        let longDocument = MarkdownDocument.parse(sample + "\n" + sample + "\n" + sample)
        let shortDocument = MarkdownDocument.parse("短")

        let long = host(MarkdownBlocksView(blocks: longDocument.blocks, language: .markdown))
        let short = host(MarkdownBlocksView(blocks: shortDocument.blocks, language: .markdown))
        let longHeight = long.sizeThatFits(in: NSSize(width: 720, height: 10_000)).height
        let shortHeight = short.sizeThatFits(in: NSSize(width: 720, height: 10_000)).height

        XCTAssertGreaterThan(shortHeight, 0)
        XCTAssertGreaterThan(
            longHeight,
            shortHeight,
            "内容多了高度不变 ⇒ 这些块没真画（空底也能过的假绿）：\(shortHeight) → \(longHeight)"
        )
    }

    /// 空文件也画得出来、且**没有编辑面**（空态那一句人话由语言表的键在位保证，
    /// 本判据不做文案断言 —— 文案不是这一层的事）。
    @MainActor
    func testEmptyDocumentStillHosts() {
        let controller = host(preview(""))
        settle(controller)
        XCTAssertTrue(textViews(in: controller.view).isEmpty)
    }
}

/// 对照用：把**真的可编辑** `NSTextView` 插进 SwiftUI 树里（判据的"能判红"那一半）。
private struct EditableProbeRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        textView.isEditable = true
        textView.string = "对照"
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}
