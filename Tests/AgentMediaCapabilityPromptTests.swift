import XCTest
@testable import DoyahCore

/// 判据：`T-3.25-21`（提示词必须告诉模型怎么发文件）——
/// 通道侧早就能发（`MEDIA:` 标签 → 上传换 `file_info` → `msg_type=7`），
/// 但提示词里没写，模型就回「我发不出图片」（2026-11-16 真机原话）。
/// 能力在、没人告诉它 = 用不出来；这条判的是**提示词里到底有没有那两个词**。
final class AgentMediaCapabilityPromptTests: XCTestCase {

    private var prompt: String {
        AgentSystemPrompt.base(model: "qwen-test", endpoint: "http://127.0.0.1:11434/v1")
    }

    func testPromptTeachesTheMediaTag() {
        XCTAssertTrue(prompt.contains("MEDIA:/"), "必须出现 `MEDIA:/绝对路径` 的写法，否则模型无从得知：\n\(prompt)")
        XCTAssertTrue(prompt.contains("【发文件到聊天】"), "要有一段显式标题，别埋在长段落里")
    }

    func testPromptForbidsFabricatedPathsAndFakeScreenshotClaims() {
        XCTAssertTrue(prompt.contains("真实存在"), "必须写明只发磁盘上真实存在的路径")
        XCTAssertTrue(prompt.contains("没有") && prompt.contains("截图"),
                      "必须明确「没有截图能力」，否则它会承诺截图然后什么也不发")
    }

    /// 负例：把这条规矩删掉，判据必须变红（证明它是有效判据而不是恒真）。
    func testRemovingTheRuleActuallyMakesTheCheckFail() {
        let stripped = prompt.replacingOccurrences(of: "MEDIA:/绝对路径", with: "")
        XCTAssertFalse(stripped.contains("MEDIA:/"), "删掉写法后就不该再命中 —— 否则这条判据是恒真的废判据")
    }
}
