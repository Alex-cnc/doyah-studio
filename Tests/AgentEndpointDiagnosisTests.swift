import XCTest
@testable import DoyahCore

/// 端点判定三档（`NFR-ALL-GATE-AI-006` ①②③）。
///
/// 为什么单开一族：本条需求过去只有一枚 `isLocalEndpoint: Bool`，
/// 于是「远端要 Key」与「地址根本不对」被判成同一件事 —— 判据没法判，
/// 人也被引到错误的方向（去补一把 Key）。这里把三档与五种不可用原因逐条钉住。
final class AgentEndpointDiagnosisTests: XCTestCase {

    // MARK: - ① 本地端点：免 Key

    /// 需求列的四类地址（localhost / *.local / 私网 / ::1）都要判成本地且免 Key。
    func testLocalAddressesNeedNoAPIKey() {
        let locals = [
            "http://localhost:11434/v1",
            "http://localhost",
            "http://ollama.local:11434/v1",
            "http://macbook.local/v1",
            "http://127.0.0.1:11434/v1",
            "http://127.9.9.9/v1",
            "http://10.0.0.7/v1",
            "http://192.168.1.50:8000/v1",
            "http://172.16.3.4/v1",
            "http://172.31.255.254/v1",
            "http://169.254.10.10/v1",
            "http://[::1]:8080/v1",
            "http://[fd00::1]:8080/v1",
            "http://[fe80::1]:8080/v1"
        ]
        for endpoint in locals {
            let diagnosis = AgentEndpointDiagnosis(endpoint: endpoint)
            XCTAssertTrue(diagnosis.isUsable, "\(endpoint) 应当是可用端点")
            XCTAssertTrue(diagnosis.isLocal, "\(endpoint) 应当判为本地")
            XCTAssertFalse(diagnosis.isRemote, "\(endpoint) 不应判为远端")
            XCTAssertFalse(diagnosis.requiresAPIKey, "\(endpoint) 免 API Key")
            XCTAssertNil(diagnosis.problem, "\(endpoint) 不该带「不可用」原因")
            XCTAssertEqual(
                diagnosis.summary(language: .simplifiedChinese),
                "本地端点（免 API Key）· \(diagnosis.host ?? "")"
            )
        }
    }

    /// 首尾空白不算「地址的一部分」。
    func testWhitespaceIsTrimmedBeforeJudging() {
        let diagnosis = AgentEndpointDiagnosis(endpoint: "  http://127.0.0.1:11434/v1  ")
        XCTAssertTrue(diagnosis.isLocal)
        XCTAssertEqual(diagnosis.host, "127.0.0.1")
    }

    // MARK: - ② 远端端点：走同一套兼容接口，需要 Key

    /// 公网地址判远端；地址表边界（172.32 / 192.169 / 11.x）不许被误判成本地。
    func testRemoteAddressesRequireAPIKey() {
        let remotes = [
            "https://api.example.com/v1",
            "https://8.8.8.8/v1",
            "http://172.32.0.1/v1",
            "http://192.169.1.1/v1",
            "http://11.0.0.1/v1",
            "https://api.openai.com/v1"
        ]
        for endpoint in remotes {
            let diagnosis = AgentEndpointDiagnosis(endpoint: endpoint)
            XCTAssertTrue(diagnosis.isRemote, "\(endpoint) 应当判为远端")
            XCTAssertFalse(diagnosis.isLocal, "\(endpoint) 不应判为本地")
            XCTAssertTrue(diagnosis.requiresAPIKey, "\(endpoint) 需要 API Key")
            XCTAssertTrue(
                diagnosis.summary(language: .simplifiedChinese).hasPrefix("远端端点（需 API Key）"),
                "\(endpoint) 的结论行应当说清「远端需 Key」"
            )
        }
    }

    /// 远端端点走的是**同一套** OpenAI 兼容请求：路径固定补成 `chat/completions`
    /// （`NFR-ALL-GATE-AI-006` ②「远端走标准兼容接口」的那一半）。
    ///
    /// 请求头 / 请求体那一半**不在这里重复造**：`Tests/AgentSQLGeneratorTests` 与
    /// `Tests/LLMStreamingAuthTests` 已经按 `OpenAICompatibleClient.makeURLRequest` 逐项钉过
    /// （`Authorization: Bearer` 只进头、不进体）。这一族只判「判定」这一层，不重测别处的判据。
    func testRemoteEndpointUsesStandardChatCompletionsPath() throws {
        let remote = AgentEndpointDiagnosis(endpoint: "https://api.example.com/v1")
        XCTAssertTrue(remote.isRemote)

        let endpoint = try XCTUnwrap(URL(string: "https://api.example.com/v1"))
        XCTAssertEqual(
            OpenAICompatibleClient.chatCompletionsURL(from: endpoint).absoluteString,
            "https://api.example.com/v1/chat/completions"
        )
        // 本地端点走的是**同一个**拼法：不是另开一套「本地专用」协议。
        let local = try XCTUnwrap(URL(string: "http://127.0.0.1:11434/v1"))
        XCTAssertEqual(
            OpenAICompatibleClient.chatCompletionsURL(from: local).absoluteString,
            "http://127.0.0.1:11434/v1/chat/completions"
        )
    }

    /// 本地端点**不要求** Key（判定的那一层）；真 HTTP 上「请求里确实没有 Authorization」
    /// 由 `Scripts/test-endpoint-modes.sh` 第 4 节在假端点侧核对（服务端看得见的那一面，
    /// 比在这里看客户端自己拼的请求更硬）。
    func testLocalEndpointNeedsNoKeyInConfiguration() {
        let configuration = AgentConfiguration(
            isEnabled: true,
            endpoint: "http://127.0.0.1:11434/v1",
            model: "qwen2.5:7b"
        )
        XCTAssertTrue(
            AgentGate.decide(configuration: configuration, apiKey: nil).isAllowed,
            "本地端点没有 Key 也应当放行（免 Key 不是「随便填个空串」）"
        )
    }

    // MARK: - ③ 判不了：给出可读原因（五种形状各一句）

    /// 五种不可用形状：各自的原因不同，且**都不是**「远端，需要 API Key」。
    func testUnusableEndpointsGiveDistinctReadableReasons() {
        let cases: [(String, AgentEndpointProblem)] = [
            ("", .empty),
            ("   ", .empty),
            ("localhost:11434/v1", .missingScheme),
            ("127.0.0.1:11434/v1", .missingScheme),
            ("ftp://127.0.0.1:11434/v1", .unsupportedScheme),
            ("postgres://db.local:5432/app", .unsupportedScheme),
            ("http://", .missingHost),
            ("https://", .missingHost),
            ("http:///v1", .missingHost)
        ]
        for (endpoint, expected) in cases {
            let diagnosis = AgentEndpointDiagnosis(endpoint: endpoint)
            XCTAssertEqual(diagnosis.problem, expected, "「\(endpoint)」应当判为 \(expected)")
            XCTAssertFalse(diagnosis.isUsable, "「\(endpoint)」不可用")
            XCTAssertFalse(diagnosis.requiresAPIKey, "不可用的端点不该被说成「需要 API Key」")
            XCTAssertNil(diagnosis.host)
            let reason = diagnosis.problemMessage(language: .simplifiedChinese) ?? ""
            XCTAssertFalse(reason.isEmpty, "「\(endpoint)」必须给出原因")
            XCTAssertTrue(
                diagnosis.summary(language: .simplifiedChinese).hasPrefix("端点不可用："),
                "「\(endpoint)」的结论行应当说「不可用」而不是「需要 Key」"
            )
        }
    }

    /// 协议不支持时，原因里要带上**当前那个协议名**（只说「不支持 http(s)」等于没说哪里不对）。
    func testUnsupportedSchemeReasonNamesTheScheme() {
        let diagnosis = AgentEndpointDiagnosis(endpoint: "mysql://db.local/app")
        XCTAssertEqual(diagnosis.problem, .unsupportedScheme)
        XCTAssertEqual(diagnosis.scheme, "mysql")
        let reason = diagnosis.problemMessage(language: .simplifiedChinese) ?? ""
        XCTAssertTrue(reason.contains("mysql"), "原因里应当出现 mysql：\(reason)")
    }

    /// 五种原因互不相同、两种语言都在（界面切英文时那一行不许空）。
    func testEveryProblemHasBothLanguages() {
        let chinese = Set(AgentEndpointProblem.allCases.map { $0.message(language: .simplifiedChinese) })
        XCTAssertEqual(chinese.count, AgentEndpointProblem.allCases.count, "中文原因不许重复")
        for problem in AgentEndpointProblem.allCases {
            XCTAssertFalse(problem.message(language: .english).isEmpty, "\(problem) 缺英文")
        }
    }

    // MARK: - 配置面：三档与「需不需要 Key」「问题清单」一致

    /// `AgentConfiguration` 的口径必须来自同一处：不可用 ⇒ 有问题项；本地 ⇒ 无问题且免 Key。
    func testConfigurationAgreesWithDiagnosis() {
        let local = AgentConfiguration(endpoint: "http://127.0.0.1:11434/v1", model: "qwen2.5:7b")
        XCTAssertTrue(local.isLocalEndpoint)
        XCTAssertFalse(local.requiresAPIKey)
        XCTAssertTrue(local.isComplete)

        let remote = AgentConfiguration(endpoint: "https://api.example.com/v1", model: "gpt-4o-mini")
        XCTAssertFalse(remote.isLocalEndpoint)
        XCTAssertTrue(remote.requiresAPIKey)
        XCTAssertTrue(remote.isComplete)

        let broken = AgentConfiguration(endpoint: "localhost:11434/v1", model: "qwen2.5:7b")
        XCTAssertFalse(broken.isLocalEndpoint)
        XCTAssertFalse(broken.requiresAPIKey, "地址不可用 ≠ 缺 Key")
        XCTAssertTrue(broken.issues.contains(.invalidEndpoint))

        let empty = AgentConfiguration(endpoint: "", model: "qwen2.5:7b")
        XCTAssertEqual(empty.endpointDiagnosis.problem, .empty)
        XCTAssertTrue(empty.issues.contains(.emptyEndpoint))
    }

    /// 提供商预设里的两个本地预设（Ollama / vLLM）判本地且免 Key ——
    /// 「预设表自己再判一遍」是最容易漂的那种重复（`AgentProviderPreset.isLocal` 只转发）。
    func testProviderPresetsForLocalServersAreLocal() {
        let locals = AgentProviderCatalog.all.filter { $0.id == "ollama" || $0.id == "vllm" }
        XCTAssertEqual(locals.count, 2, "Ollama / vLLM 两个预设应当在册")
        for preset in locals {
            XCTAssertTrue(preset.isLocal, "\(preset.id) 应当判为本地")
            XCTAssertFalse(
                AgentEndpointDiagnosis(endpoint: preset.endpoint).requiresAPIKey,
                "\(preset.id) 免 API Key"
            )
        }
    }
}
