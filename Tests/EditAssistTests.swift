import XCTest
@testable import DoyahCore

/// 编辑区 AI 辅助的判定层（`FR-STD-WS-AI-001`）。
///
/// 判四件事：**数据边界**（默认只发选中 / 读数与真发出去的一致）、**闸门**（端点 / 模型 /
/// 本机能力 / 没东西可发，全在发请求之前判）、**请求组装**（发出去的就是显示出来的那段）、
/// **结果解析**（rewrite 换选区、complete 在光标处插入、explain 只出文字，且剥代码围栏）。
final class EditAssistTests: XCTestCase {

    private let file = """
    func total(_ items: [Int]) -> Int {
        var sum = 0
        for item in items { sum += item }
        return sum
    }
    """

    private func context(selection: NSRange = NSRange(location: 0, length: 0),
                         instruction: String = "",
                         boundary: EditAssist.Boundary = .default,
                         text: String? = nil) -> EditAssist.Context {
        EditAssist.Context(fileName: "Sum.swift", language: TextLanguage.detect(path: "Sum.swift"),
                           fileText: text ?? file, selection: selection,
                           instruction: instruction, boundary: boundary)
    }

    // MARK: - 数据边界（契约 ③）

    func testDefaultBoundaryIsConservative() {
        XCTAssertEqual(EditAssist.Boundary.default, .selection,
                       "默认必须只发选中片段；默认整个文件就是「默认不保守」")
        XCTAssertEqual(EditAssist.Context(fileName: "a.swift", language: .plainText,
                                          fileText: "x", selection: NSRange(location: 0, length: 1)).boundary,
                       .selection)
    }

    func testOutboundIsTheSelectionWhenThereIsOne() {
        let text = "abcdef"
        let context = context(selection: NSRange(location: 2, length: 3), text: text)
        XCTAssertEqual(context.outbound, "cde", "选中了就必须只发选中的那段")
        XCTAssertEqual(context.selectedText, "cde")
    }

    func testOutboundFallsBackToWholeFileWithoutSelection() {
        let context = context(text: "abc")
        XCTAssertEqual(context.outbound, "abc",
                       "没选中又不能发空 ⇒ 退回整篇；这条与「默认只发选中」不冲突，只是没有选中时")
    }

    func testFileBoundarySendsWholeFile() {
        let context = context(selection: NSRange(location: 0, length: 3), boundary: .file, text: "abcdef")
        XCTAssertEqual(context.outbound, "abcdef")
        XCTAssertEqual(context.outboundSummary.scope, .file)
        XCTAssertEqual(context.outboundSummary.textLength, 6)
    }

    func testOutboundSummaryCountsLines() {
        let context = context(boundary: .file, text: "a\nb\nc")
        XCTAssertEqual(context.outboundSummary.lineCount, 3)
        XCTAssertEqual(context.outboundSummary.displayArguments.count, 2)
    }

    func testOutboundSummaryMatchesWhatIsSent() {
        let context = context(selection: NSRange(location: 0, length: 3), text: "abcdef")
        // 「显示多少」与「真发多少」是同一份计算 —— 分开算迟早对不上。
        XCTAssertEqual(context.outboundSummary.textLength, (context.outbound as NSString).length)
    }

    // MARK: - 闸门（契约 ② ④，全在发请求之前）

    func testGateRefusesWithoutContent() {
        let empty = context(text: "")
        XCTAssertEqual(EditAssist.gate(action: .explain, context: empty, endpoint: "http://x", model: "m"),
                       .nothingToSend)
    }

    func testGateRefusesRewriteWithoutInstruction() {
        XCTAssertEqual(EditAssist.gate(action: .rewrite, context: context(), endpoint: "http://x", model: "m"),
                       .missingInstruction)
    }

    func testGateRefusesMissingEndpointBeforeNetwork() {
        XCTAssertEqual(EditAssist.gate(action: .explain, context: context(), endpoint: "", model: "m"),
                       .endpointNotConfigured)
    }

    func testGateRefusesMissingModelAfterEndpoint() {
        XCTAssertEqual(EditAssist.gate(action: .explain, context: context(), endpoint: "http://x", model: "  "),
                       .modelNotConfigured)
    }

    func testGateRefusesCompletionBecauseLocalCapabilityExists() {
        // 契约 ④：补全在本机有词法 / SQL / 路径三路灰字，不该走模型。
        XCTAssertEqual(EditAssist.gate(action: .complete, context: context(), endpoint: "http://x", model: "m"),
                       .localCapabilityExists(.editAssistLocalAlternativeCompletion))
        XCTAssertNil(EditAssist.Action.explain.localOnlyAlternative)
        XCTAssertNil(EditAssist.Action.rewrite.localOnlyAlternative)
        XCTAssertNil(EditAssist.Action.fixError.localOnlyAlternative)
    }

    func testGatePassesForConfiguredExplain() {
        XCTAssertNil(EditAssist.gate(action: .explain, context: context(), endpoint: "http://x", model: "m"))
    }

    // MARK: - 请求组装

    func testRequestCarriesOnlyTheBoundedContent() {
        let text = "SECRET-TOP\nvisible"
        let context = context(selection: NSRange(location: 11, length: 7), text: text)
        let request = EditAssist.request(action: .explain, context: context)
        XCTAssertNotNil(request)
        XCTAssertTrue(request!.userPrompt.contains("visible"))
        XCTAssertFalse(request!.userPrompt.contains("SECRET-TOP"),
                       "选中的那段之外的内容一个字都不许进请求（契约 ③）")
    }

    func testRequestNamesTheFileAndLanguage() {
        let request = EditAssist.request(action: .explain, context: context())
        XCTAssertTrue(request!.userPrompt.contains("Sum.swift"))
        XCTAssertTrue(request!.systemPrompt.contains("不会被执行"))
    }

    func testRequestRequiresInstructionForRewrite() {
        XCTAssertNil(EditAssist.request(action: .rewrite, context: context()),
                     "改写没有要求 ⇒ 不组装请求（不许让模型自己猜要改成什么样）")
        let withInstruction = EditAssist.Context(fileName: "Sum.swift", language: .plainText,
                                                 fileText: file, selection: NSRange(location: 0, length: 0),
                                                 instruction: "改成递归")
        XCTAssertTrue(EditAssist.request(action: .rewrite, context: withInstruction)!.userPrompt.contains("改成递归"))
    }

    func testRequestCodeFenceUsesRegisteredLanguage() {
        let request = EditAssist.request(action: .explain, context: context())!
        XCTAssertTrue(request.userPrompt.contains("```swift"), "围栏标记要从语言登记表派生，不另写一份别名")
    }

    // MARK: - 结果解析

    func testAnswerKeepsTextAndStripsFence() {
        let result = EditAssist.result(from: "```swift\n这段代码求和。\n```", action: .explain, context: context())
        XCTAssertEqual(result, .answer("这段代码求和。"))
    }

    func testRewriteProposalReplacesTheSelection() {
        let text = "let a = 1"
        let context = context(selection: NSRange(location: 8, length: 1), text: text)
        guard case .proposal(let proposal)? = EditAssist.result(from: "```swift\n2\n```", action: .rewrite,
                                                                context: context) else {
            return XCTFail("改写必须产出可应用的提案")
        }
        XCTAssertEqual(proposal.range, NSRange(location: 8, length: 1))
        XCTAssertEqual(proposal.replacement, "2")
        XCTAssertEqual(proposal.applying(to: text), "let a = 2")
        XCTAssertEqual(proposal.summary.added, 1)
        XCTAssertEqual(proposal.summary.removed, 1)
    }

    func testCompleteInsertsAtCaretInsteadOfReplacing() {
        let text = "func f() {\n"
        let context = context(selection: NSRange(location: 11, length: 0), text: text)
        guard case .proposal(let proposal)? = EditAssist.result(from: "    return\n}", action: .complete,
                                                                context: context) else {
            return XCTFail("补全必须产出提案")
        }
        XCTAssertEqual(proposal.range, NSRange(location: 11, length: 0),
                       "补全是往后接，不是把已有代码换掉")
        XCTAssertEqual(proposal.applying(to: text), "func f() {\n    return\n}")
    }

    func testEmptyResponseIsNotAProposal() {
        XCTAssertNil(EditAssist.result(from: "   \n", action: .complete, context: context()))
        XCTAssertNil(EditAssist.result(from: "```\n```", action: .rewrite, context: context(instruction: "x")))
    }

    func testOnlyWritingActionsWriteBack() {
        XCTAssertTrue(EditAssist.Action.rewrite.writesBack)
        XCTAssertTrue(EditAssist.Action.complete.writesBack)
        XCTAssertFalse(EditAssist.Action.explain.writesBack)
        XCTAssertFalse(EditAssist.Action.fixError.writesBack)
    }

    // MARK: - 撤销动作名（应用之后编辑菜单那一行读它）

    func testAssistHasItsOwnUndoStep() {
        XCTAssertEqual(UndoEditKind.assist.actionNameKey, .undoActionAssist)
        XCTAssertTrue(UndoEditKind.assist.isAtomic, "应用 AI 产出是一次动作 = 一个撤销步")
    }

    // MARK: - 语言表（中英齐）

    func testEveryActionAndBoundaryIsLocalized() {
        for action in EditAssist.Action.allCases {
            XCTAssertFalse(LocalizedStrings.englishText(action.titleKey).isEmpty, "\(action) 缺英文")
        }
        for boundary in EditAssist.Boundary.allCases {
            XCTAssertFalse(LocalizedStrings.englishText(boundary.titleKey).isEmpty)
        }
        for refusal in [EditAssist.Refusal.nothingToSend, .missingInstruction, .endpointNotConfigured,
                        .modelNotConfigured, .emptyResponse] {
            XCTAssertFalse(LocalizedStrings.defaultText(refusal.messageKey).isEmpty)
        }
        XCTAssertTrue(LocalizedStrings.englishText(.editAssistRefusedEndpoint).contains("not configured"))
    }
}
