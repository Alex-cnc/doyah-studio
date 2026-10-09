import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 片 `L116-RESTORE-2`（`FR-EDIT-43` · 队列 `L-116` · 派单 `T-20261009-097` ①）的机器判据：
/// **回填之后，编辑器的插入点与滚动位置真的设回去了**（卡上判据 ②：对**可见范围内**的插入点做几何核对）。
///
/// ## 判什么
///
/// `Core/WorkspaceSession.swift` 的往返 / 夹范围由单测管（`Tests/WorkspaceSessionTests.swift`，
/// 27 例）；这里判的是**单测够不到的那一半**：把落脚点交给真编辑器之后，`NSTextView` 上发生了什么。
///
///   ① 插入点**真的**落在记下的偏移上（不是「恢复了但光标还在 0」）；
///   ② 滚动位置**真的**设回去了（不为 0 的那一档才判得出「设了没」）；
///   ③ 插入点的**几何**：两种量法先**统一到同一个坐标系**再比 ——
///      `firstRect(forCharacterRange:)` 给的是**窗口坐标**（要 `convert(_:from: nil)`），
///      `layoutManager.boundingRect(forGlyphRange:in:)` 给的是**文本容器坐标**
///      （要补**容器原点** `textContainerOrigin`，不是 `textContainerInset`）。
///      不这么换算就会量出一个恒定的大差值，看着像「插入点画偏了」的产品缺陷、
///      其实是探针自己的口径错（见 skill `doyah-projects` 的「几何量必须先把两边统一到同一个坐标系再比」）。
///      **实测读数**：补 `textContainerOrigin`（25.00×8.00）⇒ Δ=(0.00, 0.00)；
///      若误用 `textContainerInset`（25.60×8.00，两者差 0.6pt）⇒ Δ=(0.60, 0.00)。
///      判据写成「差 > 一行才记一次」，改对之后是同坐标系下的 0。
///
/// ## 边界（如实登记）
///
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）：它起**离屏活体宿主**，是取证工具、不进每轮门禁；
/// · **不落快照**（`UISnapshot.write` 一次都不调）：判的是几何读数不是像素，出图只会搅乱
///   「张数 / 组数」那类派生计数（与 `RetroHostProbeTests` / `NotesEditorFormatProbeTests` 同款理由）；
/// · 插入点放在**可见范围内**再量：`allowsNonContiguousLayout` 下文档中部的 `firstRect`
///   会返回零矩形（离屏量不到），所以夹具用 60 行（连续布局）、插入点取可见的那几行；
/// · **量不到时交矩阵不交结论**：读数退化成零矩形时，这条用例只打印矩阵、不把几何那一格判绿。
final class WorkspaceSessionCursorProbeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "会话恢复的几何探针要起离屏活体宿主：DOYAH_UI_SNAPSHOT=1（取证工具，不进每轮门禁）"
        )
    }

    // MARK: - 宿主与夹具

    /// 把真 `CodeEditorView` 装进离屏宿主，并把它接到一份**会话恢复的落脚点**上 ——
    /// 与产品接线同形：`takeCursorPlacement` 取走即没（这里每次宿主新建只挂一次）。
    private struct Harness: View {
        let tabID: UUID
        let text: String
        let placement: WorkspaceTabsModel.CursorPlacement?

        var body: some View {
            CodeEditorView(
                tabID: tabID,
                text: text,
                language: .swift,
                onTextChange: { _ in },
                onSave: {},
                onFormat: {},
                takeCursorPlacement: { id in id == tabID ? placement : nil },
                onCursorPosition: { _, _, _ in }
            )
        }
    }

    /// `n` 行 Swift 文档（末尾带换行）。60 行 ⇒ 连续布局 ⇒ 插入点类读数有意义。
    private static func document(_ lines: Int) -> String {
        (1...lines).map { "let value\($0) = \($0)" }.joined(separator: "\n") + "\n"
    }

    @MainActor
    private func makeEditor(
        text: String,
        caretOffset: Int,
        scrollOffset: Double,
        size: CGSize = CGSize(width: 640, height: 260)
    ) throws -> (host: UISnapshot.LiveHost<Harness>, textView: CodeTextView, scrollView: NSScrollView) {
        let tabID = UUID()
        let placement = WorkspaceTabsModel.CursorPlacement(
            tabID: tabID,
            caretOffset: caretOffset,
            scrollOffset: scrollOffset
        )
        let host = UISnapshot.LiveHost(
            Harness(tabID: tabID, text: text, placement: placement),
            size: size,
            scheme: .light
        )
        host.pump(0.5)

        let textView = try XCTUnwrap(
            UISnapshot.LiveHost<Harness>.findViews(ofType: CodeTextView.self, in: host.hosting).first,
            "工作区编辑器不在宿主视图树里 —— 判据的入口没了"
        )
        let scrollView = try XCTUnwrap(textView.enclosingScrollView, "编辑器没有滚动容器 ⇒ 滚动位置无从谈起")
        return (host, textView, scrollView)
    }

    // MARK: - 判据 ② 插入点 + 滚动位置：真的设回去了，且几何在同一个坐标系下对得上

    @MainActor
    func testRestoredCursorLandsInTheVisibleRangeInOneCoordinateSystem() throws {
        let document = Self.document(60)
        // 可见范围内的一行（离屏宿主高 260pt ≈ 十几行）；**非零**的滚动位置才判得出「设了没」。
        let cases: [(line: Int, scroll: Double)] = [
            (line: 4, scroll: 0),
            (line: 10, scroll: 100),
        ]

        var rows: [String] = []
        for (line, scroll) in cases {
            let caret = try XCTUnwrap(
                CodeLines.range(ofLine: line, in: document),
                "夹具：第 \(line) 行取不到范围"
            ).location
            let (host, textView, scrollView) = try makeEditor(
                text: document,
                caretOffset: caret,
                scrollOffset: scroll
            )
            defer { _ = host }

            XCTAssertEqual(textView.string, document, "编辑器里应当是夹具那段文档")

            // ① 插入点真的设回去了。
            let selected = textView.selectedRange()
            XCTAssertEqual(
                selected.location, caret,
                "插入点没落到记下的偏移上（行 \(line) ⇒ \(caret)），而是 \(selected.location)"
            )
            XCTAssertEqual(selected.length, 0, "会话恢复不选中任何文字（要的是「接着往下写」）")

            // ② 滚动位置真的设回去了（上界由文档高度夹，这里两档都在范围内 ⇒ 应当逐点相等）。
            let scrollY = Double(scrollView.contentView.bounds.origin.y)
            XCTAssertEqual(
                scrollY, scroll, accuracy: 1.0,
                "滚动位置没设回去：期望 \(scroll)、实测 \(scrollY)"
            )

            // ③ 几何核对（同一个坐标系）。
            let caretRange = NSRange(location: caret, length: 0)
            let layoutManager = try XCTUnwrap(textView.layoutManager)
            let container = try XCTUnwrap(textView.textContainer)

            // 量法 A：`firstRect` 给**窗口坐标** ⇒ 换算进编辑器坐标。
            let windowRect = textView.firstRect(forCharacterRange: caretRange, actualRange: nil)
            let inTextView = textView.convert(windowRect, from: nil)
            // 量法 B：`boundingRect` 给**文本容器坐标** ⇒ 补容器原点（`textContainerOrigin`）进编辑器坐标。
            let glyphRange = layoutManager.glyphRange(forCharacterRange: caretRange, actualCharacterRange: nil)
            let containerRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
            let expected = containerRect.offsetBy(
                dx: textView.textContainerOrigin.x,
                dy: textView.textContainerOrigin.y
            )
            let lineHeight = layoutManager.defaultLineHeight(for: textView.font ?? NSFont.systemFont(ofSize: 12))
            let deltaY = abs(inTextView.minY - expected.minY)
            let deltaX = abs(inTextView.minX - expected.minX)

            let visible = scrollView.documentVisibleRect
            rows.append(
                "行 \(line) · 插入点 \(caret) · 滚动 \(scroll)"
                    + " | firstRect(窗口坐标) \(Self.text(windowRect))"
                    + " → 编辑器坐标 \(Self.text(inTextView))"
                    + " | boundingRect(容器坐标) \(Self.text(containerRect))"
                    + " → +容器原点 \(Self.text(expected))"
                    + " | Δ=(\(Self.num(deltaX)), \(Self.num(deltaY))) · 行高 \(Self.num(lineHeight))"
                    + " | 容器原点 \(Self.text(NSRect(origin: textView.textContainerOrigin, size: .zero)))"
                    + " · inset \(Self.num(textView.textContainerInset.width))×\(Self.num(textView.textContainerInset.height))"
                    + " | 可见区 \(Self.text(visible))"
                    + " | 行高>0=\(lineHeight > 0) 非零矩形=\(inTextView.width > 0 || inTextView.height > 0)"
            )

            // 插入点必须在**可见范围内**（判据 ② 的前提；量到可见区外说明夹具挑错了行）。
            XCTAssertTrue(
                visible.minY <= inTextView.minY && inTextView.maxY <= visible.maxY,
                "插入点不在可见范围内（行 \(line)）：插入点 y=\(inTextView.minY) · 可见区 \(visible)"
            )

            // 量法退化（零矩形）时**只交矩阵、不下结论** —— 离屏有可能量不到，那是探针的口径问题，
            // 不是产品缺陷（口径见文件头：中部插入点在非连续布局下会返回零矩形）。
            guard lineHeight > 0, inTextView.height > 0 else {
                print("⚠️ L116-RESTORE-2 几何读数退化（交矩阵不交结论）：\(rows.last ?? "")")
                continue
            }

            // 同一个坐标系下的两个量必须重合；容差取一行（口径：「差 > 一行才记一次」）。
            XCTAssertLessThan(
                deltaY, lineHeight,
                "插入点的纵向几何对不上（同一个坐标系下差 \(deltaY) ≥ 一行 \(lineHeight)）："
                    + "firstRect 与 layoutManager 量的是两个地方"
            )
            XCTAssertLessThan(
                deltaX, lineHeight,
                "插入点的横向几何对不上（同一个坐标系下差 \(deltaX) ≥ 一行 \(lineHeight)）"
            )
        }

        print("📄 L116-RESTORE-2 ② 插入点几何矩阵（两种量法统一坐标系后逐档比对）：")
        for row in rows { print("    · \(row)") }

        UISnapshot.finishManifestIfEnabled()
    }

    /// 没给落脚点（旧快照 / Home 选中）⇒ 编辑器**不许**动光标：它还停在设文本之后的自然落点。
    ///
    /// 这条是「旧快照读取不崩」在编辑器那一侧的对照（Core 那侧由单测 `testLegacySnapshot…` 判）：
    /// 把缺字段当成偏移 `0` ⇒ 一打开就把光标顶到文档开头 —— 那是「恢复了但跳到开头」的假恢复。
    /// 所以这里判的正是**「不是 0」**：`NSTextView` 设完 `string` 之后的自然落点是**文档末尾**。
    @MainActor
    func testEditorLeavesTheCaretAloneWhenNoPlacementIsHandedOver() throws {
        let document = Self.document(60)
        let tabID = UUID()
        let host = UISnapshot.LiveHost(
            Harness(tabID: tabID, text: document, placement: nil),
            size: CGSize(width: 640, height: 260),
            scheme: .light
        )
        host.pump(0.5)

        let textView = try XCTUnwrap(
            UISnapshot.LiveHost<Harness>.findViews(ofType: CodeTextView.self, in: host.hosting).first
        )
        let caret = textView.selectedRange().location
        XCTAssertNotEqual(caret, 0, "没有落脚点时插入点被顶到了文档开头 —— 「缺字段当成 0」那种假恢复")
        XCTAssertEqual(
            caret, document.utf16.count,
            "没有落脚点时插入点应当还在设文本之后的自然落点（文档末尾）"
        )
        XCTAssertEqual(
            Double(textView.enclosingScrollView?.contentView.bounds.origin.y ?? -1), 0, accuracy: 0.5,
            "没有落脚点时滚动位置不该被动过"
        )
        print("📄 L116-RESTORE-2 ② 无落脚点一档：插入点 \(caret)（文档长 \(document.utf16.count)）、未滚")
        UISnapshot.finishManifestIfEnabled()
    }

    // MARK: - 小工具（矩阵里印人看得懂的数）

    private static func num(_ value: CGFloat) -> String { String(format: "%.2f", Double(value)) }
    private static func text(_ rect: NSRect) -> String {
        "(\(num(rect.minX)),\(num(rect.minY)) \(num(rect.width))×\(num(rect.height)))"
    }
}
