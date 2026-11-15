import XCTest
@testable import DoyahCore

/// 判据：`T-3.25-19`（IM 回话语言跟用户说的语言，不随界面语言）——
/// 见 `Docs/Doyah产品详细设计说明书-macOS.md` §3.25.1「回话语言」一行。
final class AgentIMUserLanguageTests: XCTestCase {

    func testChineseIsLearnedFromAnyChineseSentence() {
        XCTAssertEqual(AgentIMUserLanguage.infer(from: "现在能跑吗？"), .simplifiedChinese)
        XCTAssertEqual(AgentIMUserLanguage.infer(from: "ok 收到 好的"), .simplifiedChinese, "混写有汉字就算中文")
    }

    func testLatinOnlyIsEnglish() {
        XCTAssertEqual(AgentIMUserLanguage.infer(from: "/status"), .english)
    }

    func testDigitsAndEmojiTeachNothing() {
        XCTAssertNil(AgentIMUserLanguage.infer(from: "12345"))
        XCTAssertNil(AgentIMUserLanguage.infer(from: "🙂👍"))
        var memory = AgentIMUserLanguage(language: .simplifiedChinese)
        XCTAssertFalse(memory.learn(from: "🙂"), "学不出就别学")
        XCTAssertEqual(memory.language, .simplifiedChinese, "不许拿表情覆盖已学到的语言")
    }

    func testFallbackIsUsedOnlyBeforeAnythingWasLearned() {
        XCTAssertEqual(AgentIMUserLanguage().resolved(fallback: .english), .english)
        var memory = AgentIMUserLanguage()
        memory.learn(from: "你好")
        XCTAssertEqual(memory.resolved(fallback: .english), .simplifiedChinese)
    }

    func testRoundTripsThroughDiskWithOwnerOnlyPermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ul-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("user-language.json")
        var memory = AgentIMUserLanguage()
        memory.learn(from: "继续")
        memory.save(to: url)
        let loaded = try XCTUnwrap(AgentIMUserLanguage.load(from: url))
        XCTAssertEqual(loaded.language, .simplifiedChinese)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600, "落盘要 0600")
        try? FileManager.default.removeItem(at: directory)
    }
}
