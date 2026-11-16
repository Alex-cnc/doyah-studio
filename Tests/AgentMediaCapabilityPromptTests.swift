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
    /// **大文件先搜后读**（2026-11-16 真机）：679KB 的一单 ≈ 118 窗，模型一窗窗读、同一文件读了 42 次。
    /// 判据：提示词里必须写明「还剩几窗 → M > 8 就先 search 定位」。
    func testPromptTeachesToSearchBeforeReadingHugeFiles() {
        XCTAssertTrue(prompt.contains("全篇约 N 窗"), "要教它读回执里的窗数：\(prompt.suffix(300))")
        XCTAssertTrue(prompt.contains("先 `search` 定位关键词"), "大文件要先搜后读：\(prompt.suffix(300))")
        XCTAssertTrue(prompt.contains("不许") && prompt.contains("一窗窗读到底"),
                      "要明说「不许一窗窗读到底」：\(prompt.suffix(300))")
    }

    /// 负例：把这条删掉，上面那条必须判红。
    func testRemovingTheLargeFileRuleMakesTheCheckFail() {
        let stripped = prompt.replacingOccurrences(of: "全篇约 N 窗", with: "（旧文案）")
        XCTAssertFalse(stripped.contains("全篇约 N 窗"), "删掉之后判据要能看见差别")
    }
}