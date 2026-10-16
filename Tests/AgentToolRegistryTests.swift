import XCTest
@testable import DoyahCore

/// `FR-AI-19`（工具注册表 = 唯一出处）的机械判据 —— 验收要点 ② ③ ④。
final class AgentToolRegistryTests: XCTestCase {

    private let registry = AgentToolRegistry.standard

    // MARK: - ② 每条声明字段齐全，且**指纹随 schema 变化而变**

    func testEveryEntryCarriesAllDeclaredFieldsAndAFingerprintThatTracksTheSchema() {
        XCTAssertEqual(registry.definitions.count, 9, "标准表 = MVP 七件（2026-10-16 增 `edit_file`：定点改代码）+ 第二批两件（如实登记，不写成已做）")
        for definition in registry.definitions {
            XCTAssertFalse(definition.name.isEmpty, "name 不许空")
            XCTAssertFalse(definition.summary.isEmpty, "summary 不许空")
            XCTAssertFalse(definition.schemaJSON.isEmpty, "schemaJSON 不许空")
            XCTAssertFalse(definition.fingerprint.isEmpty, "指纹不许空")
            XCTAssertFalse(definition.level.rawValue.isEmpty)
            XCTAssertFalse(definition.approval.rawValue.isEmpty)
            XCTAssertFalse(definition.stage.rawValue.isEmpty)
            XCTAssertTrue(Set(definition.required).isSubset(of: Set(definition.parameters.keys)),
                          "必填必须是参数的子集（\(definition.name)）")
        }

        // schema 是合法 JSON 且形状对
        for definition in registry.definitions {
            let object = try? JSONSerialization.jsonObject(with: Data(definition.schemaJSON.utf8)) as? [String: Any]
            XCTAssertEqual(object?["type"] as? String, "object", "\(definition.name) 的参数 schema 要是对象")
            XCTAssertNotNil(object?["properties"])
        }

        // 指纹：同一条两次调用相同（纯函数，不引随机源）
        let first = registry.definitions[0]
        XCTAssertEqual(first.fingerprint, registry.definition(named: first.name)?.fingerprint)

        // **指纹随 schema 变**：改一个字段（加一个参数）⇒ 指纹必须变
        var mutated = first
        mutated.parameters["extra"] = "string"
        XCTAssertNotEqual(mutated.fingerprint, first.fingerprint, "schema 变了指纹不变 = 指纹没用")

        // 等级或审批策略变了，指纹也要变（同一份声明管等级与审批，不许被绕过）
        var escalated = first
        escalated.approval = .required
        XCTAssertNotEqual(escalated.fingerprint, first.fingerprint)
    }

    // MARK: - ③ 注入模型的 `tools` 与「启用」条目**逐条相等**

    func testInjectedToolsEqualTheEnabledEntriesExactly() {
        let enabled = registry.enabledDefinitions
        XCTAssertEqual(enabled.count, 7, "MVP 七件（第二批两件不启用）—— 含 2026-10-16 增的 `edit_file`")
        XCTAssertEqual(registry.enabledTools.map(\.name), enabled.map(\.name), "一条不多、一条不少，顺序也一致")

        // 与 `LLMRequest` 那条通道接得上：工具名与 schema 原样进 payload
        let tools = registry.enabledTools
        XCTAssertEqual(Set(tools.map(\.name)), Set(["read_file", "list_dir", "search", "query_db", "write_file", "edit_file", "run_command"]))
        let request = LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!, model: "m",
                                 systemPrompt: "s", userPrompt: "u", tools: tools, toolChoice: .automatic, stream: true)
        let body = try? OpenAICompatibleClient.makeBody(request)
        let payload = try? JSONSerialization.jsonObject(with: body ?? Data()) as? [String: Any]
        XCTAssertEqual((payload?["tools"] as? [[String: Any]])?.count, enabled.count, "注入条数 = 启用条数")
    }

    // MARK: - ④ 未登记的工具名不可被调用

    func testUnregisteredNamesAreNotResolvable() {
        XCTAssertNil(registry.definition(named: "delete_everything"))
        XCTAssertFalse(registry.isRegistered("delete_everything"))
        XCTAssertFalse(registry.enabledTools.contains { $0.name == "delete_everything" })
        XCTAssertTrue(registry.isRegistered("read_file"))
    }

    /// 只读的六件里，写 / 执行那两件必须带审批；第二批两件不许悄悄启用（`FR-AI-20` ⑥）。
    func testLevelsApprovalsAndStagesMatchTheContract() {
        for definition in registry.definitions {
            switch definition.level {
            case .readOnly:
                if definition.stage == .mvp, definition.name != "query_db" {
                    XCTAssertEqual(definition.approval, .none, "只读且 MVP ⇒ 直接跑（\(definition.name)）")
                }
            case .writable, .executable:
                XCTAssertEqual(definition.approval, .required, "写 / 执行 ⇒ 逐次要审批（\(definition.name)）")
            }
        }
        XCTAssertEqual(registry.definitions.filter { $0.stage == .secondBatch }.map(\.name), ["read_notes", "fetch_url"])
        XCTAssertTrue(registry.definitions.filter { $0.stage == .secondBatch }.allSatisfy { !$0.enabled },
                      "第二批不许默认启用")
    }
}
