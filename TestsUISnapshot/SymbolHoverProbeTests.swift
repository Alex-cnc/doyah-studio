import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **悬停文档与跳转到定义（词法级）**（`FR-STD-WS-NAV-006`）—— 需求 E 的 App 内行为探针。
///
/// ## 判的是「真编辑器 + 真鼠标位置 + 真按键修饰键」
///
/// 解析的判定（`SymbolIndex.lookup`）已由 `Tests/SymbolOutlineTests` 判过；`SymbolHover.swift`
/// 里那句话的组装与 ⌘ 点击的落实则是**界面层**，纯逻辑判据一个字都看不见。这里把真
/// `CodeEditorView` 装进离屏活宿主，从视图树里取出那枚真 `CodeTextView`，然后：
///
///   · **坐标是量出来的**：`firstRect(forCharacterRange:)` → 窗口坐标 → 文本视图坐标，
///     再用产品自己那条 `characterIndexForInsertion(at:)` 反查，确认这个点真的落在那个标识符上；
///   · **悬停**走 `NSViewToolTipOwner` 那一格（`view(_:stringForToolTip:point:userData:)`，
///     系统弹出 tooltip 时调的正是它）；
///   · **⌘ 点击**造一枚带 `.command` 的真 `NSEvent` 投给 `mouseDown`（`CodeTextView` 里那条分支）；
///   · **滚到可见**用几何量：跳转前定义那一行**不在** `visibleRect` 里，跳转后必须在。
///
/// ## 边界（如实登记）
///
/// · 字符串 / 注释里的同名**不弹**：判的是 tooltip **文案为空**且 `revealDefinition(at:)` 回 `false`。
///   这里刻意**不**投 mouseDown：未命中时 `CodeTextView` 会把点击交还系统（`super.mouseDown`），
///   而 `NSTextView` 在离屏宿主里会进模态跟踪环等 mouseUp（本机实测：整支测试挂死）——
///   那是「没命中就该交还」的正确行为，不是缺陷，所以换一个入口判同一条结论。
/// · 观感（tooltip 的字体 / 停留时长 / 出现位置）不在本判据内。
final class SymbolHoverProbeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏活体宿主要显式打开：DOYAH_UI_SNAPSHOT=1（取证工具，不进每轮门禁）"
        )
    }

    // MARK: - 取样文档

    /// 调用在**第一行**（可见），定义在**一百多行之后**（离屏）——
    /// 「跳过去之后滚到可见」只有在定义本来不可见时才判得出来。
    private let farAway = SymbolHoverSamples.farAway
    /// 字符串里有一个同名标识符，文件里另有一份真定义。
    private let stringShadow = SymbolHoverSamples.stringShadow
    /// 本文件里**没有**它的定义。
    private let undeclared = SymbolHoverSamples.undeclared

    // MARK: - 装配

    @MainActor
    private func makeEditor(text: String) throws -> (host: UISnapshot.LiveHost<AnyView>, textView: CodeTextView) {
        let host = UISnapshot.LiveHost(
            AnyView(
                CodeEditorView(
                    tabID: UUID(), text: text, language: .swift,
                    onTextChange: { _ in }, onSave: {}, onFormat: {}
                )
            ),
            size: CGSize(width: 640, height: 300)
        )
        host.pump(0.6)
        let textView = try XCTUnwrap(
            UISnapshot.LiveHost<Never>.findViews(ofType: CodeTextView.self, in: host.hosting).first,
            "真编辑器不在宿主视图树里 —— 判据的入口没了"
        )
        XCTAssertEqual(textView.string, text, "编辑器里的正文与夹具不一致")
        XCTAssertEqual(textView.symbolLanguage, .swift, "编辑器没按 Swift 建符号表")
        textView.layoutManager?.ensureLayout(for: try XCTUnwrap(textView.textContainer))
        return (host, textView)
    }

    /// 某个字符下标处**那一点**（文本视图坐标）。量法：字符矩形 → 屏幕 → 窗口 → 视图。
    @MainActor
    private func point(atCharacter index: Int, in textView: CodeTextView, window: NSWindow) throws -> NSPoint {
        let screenRect = textView.firstRect(
            forCharacterRange: NSRange(location: index, length: 1), actualRange: nil
        )
        XCTAssertGreaterThan(
            screenRect.width, 0,
            "第 \(index) 个字符量不出矩形 ⇒ 它不在已排版的可见范围里（判据的坐标没有来源）"
        )
        let windowRect = window.convertFromScreen(screenRect)
        let local = textView.convert(windowRect, from: nil)
        return NSPoint(x: local.midX, y: local.midY)
    }

    private func tooltip(_ textView: CodeTextView, at point: NSPoint) -> String {
        textView.view(textView, stringForToolTip: 0, point: point, userData: nil)
    }

    // MARK: - ① 一句话说明：名字 · 类型 · 行 N · ⌘ 点击跳到定义

    @MainActor
    func testHoverSentenceNamesTheSymbolItsKindItsLineAndHowToJump() throws {
        let (host, textView) = try makeEditor(text: farAway)
        let callIndex = try XCTUnwrap(SymbolHoverSamples.indexOfCall(in: farAway))
        let point = try point(atCharacter: callIndex, in: textView, window: host.window)

        // 这个点真的落在那个标识符上（产品自己那条映射）。
        let landed = textView.characterIndexForInsertion(at: point)
        let nameRange = (farAway as NSString).range(of: "target")
        XCTAssertTrue(
            NSLocationInRange(landed, nameRange)
                || NSLocationInRange(landed - 1, nameRange)
                || NSLocationInRange(landed + 1, nameRange),
            "量出来的点反查回第 \(landed) 个字符，不在 `target` 那段 \(NSStringFromRange(nameRange)) 里"
        )

        let hover = try XCTUnwrap(
            SymbolIndex.lookup(in: farAway, language: .swift, at: callIndex).hover,
            "调用处的 `target` 本该解析到定义"
        )
        let expected = [
            hover.name,
            L(.symbolKindFunction),
            "\(L(.symbolLineLabel)) \(hover.definitionLine)",
            L(.symbolGoToDefinitionHint),
        ].joined(separator: " · ")

        let text = tooltip(textView, at: point)
        XCTAssertEqual(text, expected, "悬停那句话与「名字 · 类型 · 行 N · 怎么跳」不对")
        XCTAssertTrue(text.hasPrefix("target · function · "), "句子开头不是「名字 · 类型」：\(text)")
        XCTAssertTrue(text.hasSuffix(L(.symbolGoToDefinitionHint)), "句子末尾没有「⌘ 点击跳到定义」")
        XCTAssertGreaterThan(hover.definitionLine, 100, "夹具里的定义不该在可见区（否则滚动那一条判不出来）")
    }

    /// 光标不在标识符上（空白处）：**不弹**（那不是错误，弹一个框只会打扰）。
    @MainActor
    func testBlankAreaDoesNotPopAnything() throws {
        let (host, textView) = try makeEditor(text: undeclared)
        // 第 1 行最后一个字符（`let a = 1` 的 `1`）右侧的空白处：同一个 y，横轴推到文字之外。
        let lineEnd = (undeclared as NSString).range(of: "\n").location
        var point = try point(atCharacter: lineEnd - 1, in: textView, window: host.window)
        point.x += 240
        XCTAssertEqual(
            tooltip(textView, at: point), "",
            "空白处也弹了一句说明 —— 用户只是把鼠标放在那里"
        )
    }

    // MARK: - ② ⌘ 点击：光标落到定义处，并滚到可见

    @MainActor
    func testCommandClickJumpsToTheDefinitionAndScrollsItIntoView() throws {
        let (host, textView) = try makeEditor(text: farAway)
        let callIndex = try XCTUnwrap(SymbolHoverSamples.indexOfCall(in: farAway))
        let hover = try XCTUnwrap(SymbolIndex.lookup(in: farAway, language: .swift, at: callIndex).hover)
        let point = try point(atCharacter: callIndex, in: textView, window: host.window)

        // 跳转之前：定义那一行**不在**可见区（否则「滚到可见」这条判据什么也没判）。
        let definitionRect = try boundingRect(of: hover.definition, in: textView)
        XCTAssertFalse(
            textView.visibleRect.intersects(definitionRect),
            "定义在跳转之前就已经可见（\(definitionRect) 落在 \(textView.visibleRect)）⇒ 滚动判不出来"
        )
        XCTAssertNotEqual(textView.selectedRange(), hover.definition, "起手光标就在定义上 ⇒ 跳转判不出来")

        // 先确认这个点真的解析出符号：`CodeTextView.mouseDown` 在 **没命中** 时会把事件交还系统
        // （`super.mouseDown`），而 `NSTextView` 在离屏宿主里会进模态跟踪环等 mouseUp
        // （本机实测：整支测试挂死）—— 那是正确行为，不是缺陷，所以这里先挡住，避免判据变成挂死。
        guard textView.symbolLookup(at: point).hover != nil else {
            return XCTFail("量出来的点没解析出符号（第 \(textView.characterIndexForInsertion(at: point)) 个字符）"
                + " ⇒ 这一条判据的输入没了")
        }

        let click = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: textView.convert(point, to: nil),
                modifierFlags: [.command], timestamp: 0,
                windowNumber: host.window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1
            ),
            "`NSEvent.mouseEvent` 没造出来 ⇒ 这一条判据的输入没了"
        )
        textView.mouseDown(with: click)
        host.pump(0.3)

        XCTAssertEqual(
            textView.selectedRange(), hover.definition,
            "⌘ 点击之后光标在 \(textView.selectedRange())，不在定义那一段 \(hover.definition)"
        )
        XCTAssertTrue(
            textView.visibleRect.intersects(try boundingRect(of: hover.definition, in: textView)),
            "光标落到定义上了，但定义那一行没滚进可见区（用户看不见自己跳到了哪）"
        )
    }

    /// 某个字符范围的矩形（**文本视图坐标**；不依赖可见性 —— `firstRect` 对离屏行返回零矩形）。
    @MainActor
    private func boundingRect(of range: NSRange, in textView: CodeTextView) throws -> NSRect {
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let container = try XCTUnwrap(textView.textContainer)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y
        return rect
    }

    // MARK: - ③ 字符串里的同名不弹

    @MainActor
    func testSameNameInsideAStringIsNotASymbol() throws {
        let (host, textView) = try makeEditor(text: stringShadow)
        let insideString = try XCTUnwrap(SymbolHoverSamples.indexOfStringLiteral(in: stringShadow))
        let point = try point(atCharacter: insideString, in: textView, window: host.window)

        // 这个点确实落在字符串里（不是别的地方）。
        let landed = textView.characterIndexForInsertion(at: point)
        XCTAssertEqual(
            SymbolIndex.lookup(in: stringShadow, language: .swift, at: landed).miss, .protectedRegion,
            "量出来的点没有落在字符串里（第 \(landed) 个字符）⇒ 这一条判的不是它"
        )

        XCTAssertEqual(
            tooltip(textView, at: point), "",
            "字符串里的同名也弹了说明 —— 那不是符号，指过去等于给一个假定义"
        )
        let before = textView.selectedRange()
        XCTAssertFalse(
            textView.revealDefinition(at: point),
            "字符串里的同名也能「跳转」⇒ 用户会被带到一份不相干的定义上"
        )
        XCTAssertEqual(textView.selectedRange(), before, "没跳转却动了光标")
    }

    // MARK: - ④ 本文件里没有它的定义：明说没有，不指到别处

    @MainActor
    func testUndeclaredIdentifierSaysSoInsteadOfPointingElsewhere() throws {
        let (host, textView) = try makeEditor(text: undeclared)
        let index = try XCTUnwrap(SymbolHoverSamples.indexOfMissing(in: undeclared))
        let point = try point(atCharacter: index, in: textView, window: host.window)

        let landed = textView.characterIndexForInsertion(at: point)
        XCTAssertEqual(
            SymbolIndex.lookup(in: undeclared, language: .swift, at: landed).miss, .notDeclaredInFile,
            "量出来的点没有落在那个「本文件里没有定义」的标识符上（第 \(landed) 个字符）"
        )

        let text = tooltip(textView, at: point)
        XCTAssertEqual(text, L(.symbolNoDefinitionInFile), "查不到时说的不是「本文件里没有它的定义」")
        XCTAssertFalse(
            text.contains(L(.symbolLineLabel)),
            "查不到却给了一个位置（`line …`）—— 用户会以为跳得过去：\(text)"
        )
        XCTAssertFalse(
            text.contains(L(.symbolGoToDefinitionHint)),
            "查不到却给了「⌘ 点击跳到定义」—— 那是假承诺：\(text)"
        )
        XCTAssertFalse(
            textView.revealDefinition(at: point),
            "查不到却「跳」了（跳到最近似的那一条 = 猜）"
        )
    }
}

// MARK: - 取样文档

/// 三份夹具（放在文件级 `enum` 里，好让「下标在哪」与「正文长什么样」写在同一处）。
enum SymbolHoverSamples {

    /// 第一行调用，定义在一百多行之后（离屏）。
    static let farAway: String = {
        var text = "target()\n"
        for index in 0..<130 { text += "let filler\(index) = \(index)\n" }
        text += "func target() -> Int { return 1 }\n"
        return text
    }()

    /// 字符串里有一个同名；文件里另有一份真定义。
    static let stringShadow = "let s = \"target\"\nfunc target() -> Int { return 1 }\n"

    /// 本文件里没有它的定义。
    static let undeclared = "let a = 1\nprint(missingThing)\n"

    /// `target()` 那处调用里 `target` 的首字符（第一行行首）。
    static func indexOfCall(in text: String) -> Int? {
        guard text.hasPrefix("target()") else { return nil }
        return 0
    }

    /// 字符串字面量里 `target` 的首字符。
    static func indexOfStringLiteral(in text: String) -> Int? {
        let ns = text as NSString
        let range = ns.range(of: "\"target\"")
        guard range.location != NSNotFound else { return nil }
        return range.location + 1
    }

    /// `missingThing` 的首字符。
    static func indexOfMissing(in text: String) -> Int? {
        let range = (text as NSString).range(of: "missingThing")
        return range.location == NSNotFound ? nil : range.location
    }
}
