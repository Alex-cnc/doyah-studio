import XCTest
@testable import DoyahCore

/// 技能库（`FR-AI-26`）：加载校验 + 按需披露。判据逐条对条文那四个机械验收要点。
final class AgentSkillLibraryTests: XCTestCase {

    private func skill(name: String = "查表",
                       applicability: String = "想知道某张表长什么样时",
                       triggers: [String] = ["表结构", "schema"],
                       steps: [AgentSkill.Step] = [.init(tool: "read_file", summary: "读一个工作区文件")],
                       disclosure: String = "只说读了哪个文件，不贴文件内容") -> AgentSkill {
        AgentSkill(name: name, applicability: applicability, triggers: triggers,
                   steps: steps, disclosure: disclosure)
    }

    /// 最日常的那一条：字段给全 + 工具名在注册表里 ⇒ 加载干净。
    func testWellFormedSkillLoadsClean() {
        let result = AgentSkillLibrary.load([skill()])
        XCTAssertTrue(result.isClean, "字段给全、工具名合法 ⇒ 不该有判红：\(result.issues.map(\.text))")
        XCTAssertEqual(result.skills.map(\.name), ["查表"])
    }

    /// ① 字段任一为空 ⇒ 判红**且不放行**（半条技能比没有更坏：模型会以为它可用）。
    func testEveryEmptyFieldIsRejected() {
        let cases: [(String, AgentSkill)] = [
            ("name", skill(name: "")),
            ("适用面", skill(applicability: "   ")),
            ("触发", skill(triggers: [])),
            ("触发（有空项）", skill(triggers: ["ok", " "])),
            ("步骤", skill(steps: [])),
            ("披露面", skill(disclosure: "")),
        ]
        for (label, bad) in cases {
            let result = AgentSkillLibrary.load([bad])
            XCTAssertFalse(result.isClean, "\(label) 为空时必须判红")
            XCTAssertTrue(result.skills.isEmpty, "\(label) 为空时**不许放行**（不静默跳过、也不半放行）")
            XCTAssertFalse(result.issues.isEmpty)
        }
    }

    /// ② 步骤引用的工具名不在注册表里 ⇒ 判红（**不许静默跳过**）。
    func testUnknownToolIsRejected() {
        let bad = skill(steps: [.init(tool: "no_such_tool_xyz", summary: "根本没这个工具")])
        let result = AgentSkillLibrary.load([bad])
        XCTAssertFalse(result.isClean, "引用了不存在的工具必须判红")
        XCTAssertTrue(result.skills.isEmpty, "判红的技能不许进入可用集合")
        if case .unknownTool(let tool)? = result.issues.first?.kind {
            XCTAssertEqual(tool, "no_such_tool_xyz")
        } else {
            XCTFail("应当报 unknownTool")
        }
    }

    /// 重名 ⇒ 判红（第二条不放行，先到的那条留着）。
    func testDuplicateNameIsRejected() {
        let result = AgentSkillLibrary.load([skill(), skill()])
        XCTAssertEqual(result.skills.count, 1, "先到的那条留着")
        XCTAssertTrue(result.issues.contains { if case .duplicateName = $0.kind { return true }; return false })
    }

    /// ④ 负例：**技能库不执行任何工具**（它只说"能做哪几步"）——
    /// 形状判据：本文件里不许出现执行侧的名字（runner / Process / 审批门）。
    func testLibraryNeverExecutesAnything() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Core/AgentSkillLibrary.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        for forbidden in ["AgentCommandRunner", "Process(", "AgentApprovalGate", "prepareWrite", "prepareCommand"] {
            XCTAssertFalse(source.contains(forbidden), "技能库不许碰执行侧（出现了 \(forbidden)）")
        }
        XCTAssertTrue(source.contains("AgentToolRegistry"), "工具名一律问注册表 —— 不在这里另立一份工具清单")
    }

    /// 按需披露：命中触发词才给；大小写不敏感；空提问 ⇒ 一条都不给。
    func testDiscloseIsTriggerBasedAndCaseInsensitive() {
        let skills = [skill(triggers: ["表结构", "schema"])]
        XCTAssertEqual(AgentSkillLibrary.disclose(skills, for: "帮我看看这张表的表结构").count, 1)
        XCTAssertEqual(AgentSkillLibrary.disclose(skills, for: "看下这个 SCHEMA").count, 1, "大小写不敏感")
        XCTAssertTrue(AgentSkillLibrary.disclose(skills, for: "今天天气不错").isEmpty, "没命中就不披露")
        XCTAssertTrue(AgentSkillLibrary.disclose(skills, for: "").isEmpty, "空提问一条都不给")
    }

    /// 披露面之外的东西不写进给模型的那段（这是 `disclosure` 这个字段的意义）。
    func testPromptFragmentCarriesOnlyDisclosure() {
        let fragment = AgentSkillLibrary.promptFragment(for: skill())
        XCTAssertTrue(fragment.contains("查表"), "要带技能名")
        XCTAssertTrue(fragment.contains("read_file"), "要带步骤的工具名（模型据此发起调用）")
        XCTAssertTrue(fragment.contains("披露面"), "要带披露面")
    }
}
