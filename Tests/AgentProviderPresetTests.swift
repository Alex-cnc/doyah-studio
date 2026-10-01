import XCTest
@testable import DoyahCore

/// 内置模型服务预设的判据（队列 `L-146` / 内测清单丁3 / FR-AI-01 的配置面）。
///
/// 分两半：
/// · **目录自身的形状**（标识 / 端点 / 清单 / 语言表 / 不许有凭据字段）—— 防「加一条预设时手滑」；
/// · **给界面用的两件行为**（端点匹配、模型下拉内容）—— 界面只许照它们画。
final class AgentProviderPresetTests: XCTestCase {

    // MARK: - 目录形状

    /// 条数下限 + 「自定义」固定在最后（界面靠这个顺序把它排在末位）。
    func testCatalogShapeAndCustomEntryIsLast() {
        XCTAssertGreaterThanOrEqual(AgentProviderCatalog.all.count, 12)
        XCTAssertEqual(AgentProviderCatalog.all.last?.id, AgentProviderCatalog.customID)
        XCTAssertTrue(AgentProviderCatalog.custom.isCustom)
        XCTAssertTrue(AgentProviderCatalog.custom.endpoint.isEmpty, "自定义条目不该有预设端点")
        XCTAssertTrue(AgentProviderCatalog.custom.models.isEmpty, "自定义条目不该有预设模型清单")
        XCTAssertEqual(AgentProviderCatalog.all.filter(\.isCustom).count, 1)
        for preset in AgentProviderCatalog.all where !preset.isCustom {
            XCTAssertFalse(preset.endpoint.isEmpty, "\(preset.id) 缺端点")
        }
    }

    /// 标识唯一且是稳定 slug（它同时被界面 `.tag()` 与匹配逻辑用）。
    func testIdentifiersAreUniqueLowercaseSlugs() {
        var seen = Set<String>()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        for preset in AgentProviderCatalog.all {
            XCTAssertFalse(preset.id.isEmpty)
            XCTAssertNil(preset.id.rangeOfCharacter(from: allowed.inverted), "\(preset.id) 不是 slug")
            XCTAssertTrue(seen.insert(preset.id).inserted, "标识重复：\(preset.id)")
        }
    }

    /// 端点唯一且是合法 http(s) 端点 —— 校验**用产品自己那套**（`AgentConfiguration`），
    /// 不在这里另写一份 URL 形状判断。
    func testEndpointsAreUniqueAndValid() {
        var seen = Set<String>()
        for preset in AgentProviderCatalog.all where !preset.isCustom {
            let configuration = AgentConfiguration(endpoint: preset.endpoint)
            XCTAssertNotNil(configuration.endpointURL, "\(preset.id) 的端点不是合法 http(s) 地址")
            XCTAssertTrue(
                configuration.issues.filter { $0 == .emptyEndpoint || $0 == .invalidEndpoint }.isEmpty,
                "\(preset.id) 的端点过不了配置校验：\(configuration.issues)"
            )
            let normalized = AgentProviderCatalog.normalizedEndpoint(preset.endpoint)
            XCTAssertTrue(seen.insert(normalized).inserted, "端点重复：\(preset.endpoint)")
        }
    }

    /// 模型清单：不许有空串、不许条内重复（空清单合法 —— 本机服务 / 接入点 ID 只能由用户填）。
    func testModelListsAreClean() {
        for preset in AgentProviderCatalog.all {
            var seen = Set<String>()
            for model in preset.models {
                XCTAssertFalse(model.trimmingCharacters(in: .whitespaces).isEmpty, "\(preset.id) 有空模型名")
                XCTAssertTrue(seen.insert(model).inserted, "\(preset.id) 有重复模型名：\(model)")
            }
        }
    }

    /// 每个预设的标签在语言表里**两种语言都非空**（品牌名不硬编码在 Core 里）。
    func testEveryPresetLabelIsInTheLanguageTable() {
        for preset in AgentProviderCatalog.all {
            let entry = LocalizedStrings.table[preset.labelKey]
            XCTAssertNotNil(entry, "\(preset.id) 的标签键没进语言表")
            XCTAssertFalse((entry?[.simplifiedChinese] ?? "").isEmpty, "\(preset.id) 缺中文标签")
            XCTAssertFalse((entry?[.english] ?? "").isEmpty, "\(preset.id) 缺英文标签")
        }
    }

    /// 「本地端点」只有一个定义：预设的 `isLocal` 必须与 `AgentConfiguration.isLocalEndpoint` 同答。
    func testLocalFlagFollowsTheSingleDefinition() {
        for preset in AgentProviderCatalog.all {
            XCTAssertEqual(
                preset.isLocal,
                AgentConfiguration(endpoint: preset.endpoint).isLocalEndpoint,
                "\(preset.id) 的本地判定与配置层不一致"
            )
        }
        XCTAssertTrue(AgentProviderCatalog.preset(id: "ollama")?.isLocal ?? false)
        XCTAssertTrue(AgentProviderCatalog.preset(id: "vllm")?.isLocal ?? false)
        XCTAssertFalse(AgentProviderCatalog.preset(id: "openai")?.isLocal ?? true)
    }

    /// 预设里**不许**出现凭据类字段 —— 这是结构性的（密钥只进钥匙串），不是纪律性的。
    ///
    /// 上面那条 `XCTAssertEqual(labels, [...])` 才是硬保证（字段集合被钉死）；
    /// 这一条是在字段名这一层再拦一次。`labelKey` 自己含 "key"，按名字放行。
    func testPresetCarriesNoCredentialFields() {
        let labels = Mirror(reflecting: AgentProviderCatalog.all[0]).children.compactMap(\.label).map { $0.lowercased() }
        XCTAssertEqual(labels, ["id", "labelkey", "endpoint", "models"])
        for label in labels where label != "labelkey" {
            XCTAssertFalse(
                label.contains("apikey") || label.contains("secret")
                    || label.contains("token") || label.contains("password"),
                "预设多了一个凭据类字段：\(label)"
            )
        }
    }

    // MARK: - 端点匹配（重开面板时恢复选中）

    func testLookupById() {
        XCTAssertEqual(AgentProviderCatalog.preset(id: "deepseek")?.endpoint, "https://api.deepseek.com/v1")
        XCTAssertNil(AgentProviderCatalog.preset(id: "不存在的厂商"))
        XCTAssertTrue(AgentProviderCatalog.preset(id: AgentProviderCatalog.customID)?.isCustom ?? false)
    }

    /// 匹配要宽容：用户手抄常带首尾空白 / 结尾斜杠 / 大写。
    func testEndpointMatchingIsForgiving() {
        let raws = [
            "  https://api.openai.com/v1  ",
            "https://api.openai.com/v1/",
            "HTTPS://API.OPENAI.COM/v1",
            "https://api.openai.com/v1///"
        ]
        for raw in raws {
            XCTAssertEqual(AgentProviderCatalog.preset(matchingEndpoint: raw)?.id, "openai", raw)
        }
    }

    /// 宽容只到「归一化」为止：少一段路径 / 换端口 / 空串都认不出来（不许猜）。
    func testEndpointMatchingIsExactBeyondNormalization() {
        XCTAssertNil(AgentProviderCatalog.preset(matchingEndpoint: "https://api.openai.com"))
        XCTAssertNil(AgentProviderCatalog.preset(matchingEndpoint: "https://api.openai.com/v1beta"))
        XCTAssertNil(AgentProviderCatalog.preset(matchingEndpoint: "http://192.168.1.9:8000/v1"))
        XCTAssertNil(AgentProviderCatalog.preset(matchingEndpoint: ""))
        XCTAssertNil(AgentProviderCatalog.preset(matchingEndpoint: "   "))
    }

    func testUnknownEndpointResolvesToCustom() {
        XCTAssertTrue(AgentProviderCatalog.resolved(endpoint: "http://10.0.0.5:8080/v1").isCustom)
        XCTAssertTrue(AgentProviderCatalog.resolved(endpoint: "").isCustom)
        XCTAssertEqual(AgentProviderCatalog.resolved(endpoint: "https://api.deepseek.com/v1").id, "deepseek")
    }

    /// 归一化**只影响比较**：不进用户配置、也不改任何东西（顺带钉住退化输入）。
    func testNormalizationIsPureAndDegenerateInputsAreSafe() {
        let configuration = AgentConfiguration(endpoint: "https://api.openai.com/v1/")
        XCTAssertEqual(AgentProviderCatalog.resolved(endpoint: configuration.endpoint).id, "openai")
        XCTAssertEqual(configuration.endpoint, "https://api.openai.com/v1/", "归一化不许回写用户配置")
        XCTAssertEqual(AgentProviderCatalog.normalizedEndpoint(""), "")
        XCTAssertEqual(AgentProviderCatalog.normalizedEndpoint("/"), "")
        XCTAssertEqual(AgentProviderCatalog.normalizedEndpoint("  https://A/B//  "), "https://a/b")
    }

    // MARK: - 模型下拉（界面照这个画）

    func testModelOptionsKeepPresetOrderAndAppendTheTypedModel() {
        let openai = AgentProviderCatalog.preset(id: "openai")!
        XCTAssertEqual(openai.modelOptions(currentModel: ""), openai.models)
        XCTAssertEqual(openai.modelOptions(currentModel: "gpt-4o"), openai.models)
        XCTAssertEqual(openai.modelOptions(currentModel: "my-gateway-model"), openai.models + ["my-gateway-model"])
    }

    func testModelOptionsTrimAndIgnoreBlank() {
        let deepseek = AgentProviderCatalog.preset(id: "deepseek")!
        XCTAssertEqual(deepseek.modelOptions(currentModel: "   "), deepseek.models)
        XCTAssertEqual(deepseek.modelOptions(currentModel: "  deepseek-chat  "), deepseek.models)
        XCTAssertEqual(deepseek.modelOptions(currentModel: "  my-model  "), deepseek.models + ["my-model"])
    }

    /// 没有预设清单的预设（火山方舟的接入点 ID / vLLM 已加载的模型）：下拉里**只剩**用户填的那一个。
    func testModelOptionsForPresetsWithoutAList() {
        let vllm = AgentProviderCatalog.preset(id: "vllm")!
        XCTAssertTrue(vllm.models.isEmpty)
        XCTAssertEqual(vllm.modelOptions(currentModel: "Qwen2.5-7B-Instruct"), ["Qwen2.5-7B-Instruct"])
        XCTAssertEqual(vllm.modelOptions(currentModel: ""), [])
    }
}
