import XCTest
@testable import DoyahCore

/// 灵魂固定层（`FR-AI-34`）的判据：**L0 在前不许被覆盖** · **缺了如实报** · **含密钥形态一律拒**。
///
/// 由头：人类主人 2026-10-17 定「L0 = Agent 的通用角色（纸面描述）+ 配套准则；L1 = 工作区领域角色」。
final class AgentSoulTests: XCTestCase {

    private let coreBody = """
    # L0
    我是一个有判断力的执行者，是人类最忠诚的伙伴。
    我不吹、不瞒、不推、不越。
    """

    private let roleBody = """
    # 开发角色
    判据跑了才算完成；未执行 ≠ 通过。
    """

    /// ① 组装顺序写死：L0 在前、L1 在后，且顶部有"以本层为准"的声明。
    func testComposePutsCoreFirstAndDeclaresPrecedence() {
        let composition = AgentSoul.compose(
            core: AgentSoul.inspect(coreBody, kind: .core, path: "L0.md"),
            role: AgentSoul.inspect(roleBody, kind: .role, path: "role.md"))
        XCTAssertTrue(composition.isComplete, "两件齐 ⇒ 无缺陷：\(composition.problems)")
        let coreRange = composition.section.range(of: "我是一个有判断力的执行者")
        let roleRange = composition.section.range(of: "判据跑了才算完成")
        XCTAssertNotNil(coreRange)
        XCTAssertNotNil(roleRange)
        XCTAssertLessThan(coreRange!.lowerBound, roleRange!.lowerBound, "L0 必须排在 L1 之前")
        XCTAssertTrue(composition.section.contains("以本层为准"), "固定层必须声明优先级")
    }

    /// ② L1 未设定 ⇒ **如实写进提示词**，且明说"不套用其他工作区的角色灵魂"。
    func testMissingRoleIsReportedNotSilentlyBorrowed() {
        let composition = AgentSoul.compose(
            core: AgentSoul.inspect(coreBody, kind: .core, path: "L0.md"),
            role: AgentSoul.inspect(nil, kind: .role, path: ".doyah/soul-role.md"))
        XCTAssertFalse(composition.isComplete)
        XCTAssertNil(composition.role)
        XCTAssertTrue(composition.section.contains("尚未设定角色灵魂"))
        XCTAssertTrue(composition.section.contains("不套用其他工作区的角色灵魂"))
        XCTAssertEqual(composition.problems.count, 1)
    }

    /// ③ L0 缺失 ⇒ 标记为**缺陷**（不是"就当没有灵魂"），且提示按最保守方式行事。
    func testMissingCoreIsMarkedAsDefect() {
        let composition = AgentSoul.compose(
            core: AgentSoul.inspect("   \n\n", kind: .core, path: "soul-L0.md"),
            role: AgentSoul.inspect(roleBody, kind: .role, path: "role.md"))
        XCTAssertNil(composition.core)
        XCTAssertTrue(composition.problems.contains { $0.hasPrefix("L0 缺失") })
        XCTAssertTrue(composition.section.contains("这是缺陷"))
        XCTAssertTrue(composition.section.contains("最保守"))
    }

    /// ④ 灵魂里出现密钥形态 ⇒ **拒绝载入**（它会进每次请求的上下文，不能放行）。
    func testSecretLookingSoulIsRejected() {
        let leaky = """
        # 角色
        调用时带 api_key=abcd1234 就行。
        """
        let result = AgentSoul.inspect(leaky, kind: .role, path: "role.md")
        XCTAssertNil(result.layer, "含密钥形态必须拒绝")
        guard case .rejected(let rejection)? = result.problem.map({ _ in result }) else {
            return XCTFail("应被拒绝")
        }
        if case .carriesSecretForm(_, let marker) = rejection {
            XCTAssertEqual(marker, "api_key")
        } else {
            XCTFail("拒绝原因应是密钥形态，实际：\(rejection)")
        }
    }

    /// ⑤ 正常谈论"api_key 这个概念"（没有赋值）不算泄漏 —— 不许误杀。
    func testMentioningTheWordWithoutAssignmentIsNotASecretForm() {
        let harmless = """
        # 角色
        密钥只进钥匙串；配置文件里不写 api_key 字段。
        """
        XCTAssertNotNil(AgentSoul.inspect(harmless, kind: .role, path: "role.md").layer,
                        "只是提到概念、没有赋值形态，不该被拒")
    }

    /// ⑥ 一级标题由组装器统一给：层文本里的 `# ` 标题被剥掉（免得两个标题打架）。
    func testTopLevelHeadingIsStrippedFromLayerText() {
        let layer = AgentSoul.inspect(coreBody, kind: .core, path: "L0.md").layer
        XCTAssertNotNil(layer)
        XCTAssertFalse(layer!.text.hasPrefix("# "), "层正文不该以一级标题开头")
        XCTAssertTrue(layer!.text.contains("人类最忠诚的伙伴"))
    }
}
