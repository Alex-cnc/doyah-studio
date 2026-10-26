import XCTest
@testable import DoyahCore

/// 计划 P4 工具面判据：编辑（按块改、给差异、不整篇重写）· 摄取（可点来源、能力如实）·
/// 模型（多档 + 预填）· 媒体（转写可回看、可中断）· 系统（每步可见、委派标来源）。
final class AgentToolFaceTests: XCTestCase {

    // MARK: 编辑

    func testAnchorReplaceProducesDiff() throws {
        let text = "line1\nline2\nline3"
        let result = try AgentBlockEditor.replaceAnchor(in: text, anchor: "line2", with: "LINE-TWO").get()
        XCTAssertEqual(result.updated, "line1\nLINE-TWO\nline3")
        XCTAssertEqual(result.diff, ["-line2", "+LINE-TWO"])
        XCTAssertEqual(result.changedLines, 2)
    }

    func testAnchorMustBeUnique() {
        let text = "a\nb\na"
        XCTAssertEqual(AgentBlockEditor.replaceAnchor(in: text, anchor: "a", with: "x"),
                       .failure(.anchorNotUnique(count: 2)))
        XCTAssertEqual(AgentBlockEditor.replaceAnchor(in: text, anchor: "zzz", with: "x"),
                       .failure(.anchorNotFound))
    }

    func testLineRangeReplace() throws {
        let text = "1\n2\n3\n4"
        let result = try AgentBlockEditor.replaceLines(in: text, range: 2...3, with: ["two", "three"]).get()
        XCTAssertEqual(result.updated, "1\ntwo\nthree\n4")
    }

    func testLineRangeOutOfBounds() {
        XCTAssertEqual(AgentBlockEditor.replaceLines(in: "1\n2", range: 2...5, with: ["x"]),
                       .failure(.rangeOutOfBounds(requested: 2...5, lines: 2)))
    }

    func testWholeFileRewriteIsRefusedByDefault() {
        XCTAssertEqual(AgentBlockEditor.rewrite(in: "a", with: "b", wholeFile: false),
                       .failure(.wholeFileRewriteNotAllowed))
        XCTAssertNoThrow(try AgentBlockEditor.rewrite(in: "a", with: "b", wholeFile: true).get())
    }

    // MARK: 摄取

    func testOnlyTextFormatsAreAvailable() {
        guard case .chunks = AgentIngestion.capability(for: .markdown) else {
            return XCTFail("markdown 应当可读")
        }
        XCTAssertEqual(AgentIngestion.capability(for: .pdf), .unavailable(.parserUnavailable(format: "pdf")))
        XCTAssertEqual(AgentIngestion.capability(for: .image), .unavailable(.visionUnavailable),
                       "视觉不可用必须明说")
    }

    func testKindDetection() {
        XCTAssertEqual(AgentIngestion.kind(ofFileNamed: "a.MD"), .markdown)
        XCTAssertEqual(AgentIngestion.kind(ofFileNamed: "a.xlsx"), .excel)
        XCTAssertEqual(AgentIngestion.kind(ofFileNamed: "a.png"), .image)
        XCTAssertNil(AgentIngestion.kind(ofFileNamed: "a.bin"))
    }

    func testChunksCarryClickableSource() {
        let text = (1...10).map { "line \($0)" }.joined(separator: "\n")
        let chunks = AgentIngestion.chunk(text: text, uri: "file:///a.md", maxChunkCharacters: 20)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(chunks.first?.source.link, "file:///a.md:1")
        XCTAssertTrue(chunks.allSatisfy { $0.source.uri == "file:///a.md" })
    }

    func testSearchReturnsOnlyHitsWithSource() {
        let chunks = [
            AgentIngestedChunk(text: "alpha", source: AgentSourceRef(uri: "file:///a", line: 3)),
            AgentIngestedChunk(text: "beta", source: AgentSourceRef(uri: "file:///a", line: 9)),
        ]
        let hits = AgentIngestion.search("ALPHA", in: chunks)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.source.link, "file:///a:3")
        XCTAssertTrue(AgentIngestion.search("", in: chunks).isEmpty)
    }

    // MARK: 模型

    func testThreeTiersAndPrefill() throws {
        let catalog = AgentModelCatalog.standard
        XCTAssertEqual(catalog.presets.count, 3)
        let deep = try catalog.prefilled(tier: .deep, endpoint: "https://proxy.local/v1", model: "m2")
        XCTAssertEqual(deep.endpoint, "https://proxy.local/v1")
        XCTAssertEqual(deep.model, "m2")
        XCTAssertEqual(deep.contextLimit, 1_000_000, "换端点不许改掉档位上限")
    }

    func testPrefillValidation() {
        let catalog = AgentModelCatalog.standard
        XCTAssertThrowsError(try catalog.prefilled(tier: .fast, endpoint: "http://insecure", model: nil)) { error in
            XCTAssertEqual(error as? AgentModelPresetError, .endpointNotHTTPS("http://insecure"))
        }
        XCTAssertThrowsError(try catalog.prefilled(tier: .fast, endpoint: "https://x", model: "  ")) { error in
            XCTAssertEqual(error as? AgentModelPresetError, .missingModel)
        }
    }

    // MARK: 媒体

    func testTranscriptSurvivesInterruption() throws {
        var session = AgentVoiceSession()
        try session.startRecording()
        try session.appendTranscript("前半句，")
        try session.appendTranscript("后半句。")
        session.cancel()
        XCTAssertEqual(session.state, .cancelled)
        XCTAssertTrue(session.interrupted)
        XCTAssertEqual(session.transcript, "前半句，\n后半句。", "中断不许丢已转写内容")
    }

    func testFinishRequiresContent() throws {
        var session = AgentVoiceSession()
        try session.startRecording()
        XCTAssertThrowsError(try session.finish()) { error in
            XCTAssertEqual(error as? AgentVoiceError, .emptyTranscript)
        }
        try session.appendTranscript("hello")
        XCTAssertEqual(try session.finish(), "hello")
        XCTAssertTrue(session.isReady)
    }

    func testSpeechRequestValidation() {
        XCTAssertThrowsError(try AgentSpeechRequest(text: "  ").validated()) { error in
            XCTAssertEqual(error as? AgentSpeechRequest.Validation, .emptyText)
        }
        XCTAssertThrowsError(try AgentSpeechRequest(text: String(repeating: "a", count: 20)).validated(limit: 10)) { error in
            XCTAssertEqual(error as? AgentSpeechRequest.Validation, .tooLong(characters: 20, limit: 10))
        }
        XCTAssertEqual(try AgentSpeechRequest(text: " hi ").validated().text, "hi")
    }

    // MARK: 系统（可见 + 委派标来源）

    func testDelegationTagsOrigin() {
        var ledger = AgentSubtaskLedger()
        ledger.delegate(id: "S1", goal: "核对文档", atStep: 3)
        ledger.appendStep(subtaskID: "S1", kind: .tool, label: "grep")
        ledger.appendStep(subtaskID: "S1", kind: .file, label: "Docs/a.md")
        XCTAssertEqual(ledger.delegations.first?.origin, .subtask(id: "S1", delegatedAtStep: 3))
        XCTAssertEqual(ledger.delegations.first?.steps.records.count, 2)
        XCTAssertEqual(ledger.allStepsGrouped().count, 1)
    }

    func testUIActionLineShowsSource() {
        let main = AgentUIAction(action: "click", target: "File>Save")
        XCTAssertEqual(main.displayLine, "[main] click:File>Save")
        let sub = AgentUIAction(action: "click", target: "File>Save",
                                origin: .subtask(id: "S7", delegatedAtStep: 12))
        XCTAssertEqual(sub.displayLine, "[subtask S7 @12] click:File>Save")
    }

    func testUnknownSubtaskOriginIsNil() {
        var ledger = AgentSubtaskLedger()
        ledger.delegate(id: "S1", goal: "g", atStep: 1)
        ledger.appendStep(subtaskID: "S1", kind: .tool, label: "grep")
        XCTAssertNotNil(ledger.origin(ofStep: 1, inSubtask: "S1"))
        XCTAssertNil(ledger.origin(ofStep: 9, inSubtask: "S1"))
        XCTAssertNil(ledger.origin(ofStep: 1, inSubtask: "nope"))
    }
}
