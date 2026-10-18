import XCTest
@testable import DoyahCore

/// `FR-AI-25` 信息面三格（上下文窗口 / 缓存命中率 / 价目）的机械判据。
///
/// 要害是**宁缺不假**：认不出窗口就说未知（不许拿个整数凑）、端点没报缓存就不画那一格
/// （不许当 0%）、没填价目就不给钱数（不许自造 `¥0`）。所以每一格都站一对正负例。
final class AgentModelMeterTests: XCTestCase {

    // MARK: - 第一格：上下文窗口

    func testWindowUserOverrideWinsOverCatalog() {
        let pricing = AgentModelPricing(contextWindow: 32_000)
        XCTAssertEqual(AgentModelMeter.window(for: "gpt-4o", pricing: pricing), 32_000,
                       "用户填的是真值源，内置表不许压过它")
    }

    func testWindowFromBuiltInCatalogNames() {
        XCTAssertEqual(AgentModelMeter.window(for: "gpt-4o", pricing: nil), 128_000)
        XCTAssertEqual(AgentModelMeter.window(for: "gpt-4o-mini-2024-07-18", pricing: nil), 128_000,
                       "带日期后缀也要认得出")
        XCTAssertEqual(AgentModelMeter.window(for: "claude-3-7-sonnet-20250219", pricing: nil), 200_000)
    }

    func testWindowFromModelNameSuffix() {
        XCTAssertEqual(AgentModelMeter.window(for: "moonshot-v1-8k", pricing: nil), 8_192,
                       "名字里的 k 按 1024 算（业内命名惯例）")
        XCTAssertEqual(AgentModelMeter.window(for: "my-gateway-128k", pricing: nil), 131_072)
        XCTAssertEqual(AgentModelMeter.window(for: "house-model-1m", pricing: nil), 1_048_576)
    }

    func testWindowUnknownIsNilNotGuessed() {
        XCTAssertNil(AgentModelMeter.window(for: "house-secret-model", pricing: nil),
                     "认不出不许猜一个整数")
        XCTAssertNil(AgentModelMeter.window(for: "", pricing: nil))
    }

    func testWindowIgnoresNonPositiveUserValue() {
        XCTAssertEqual(AgentModelMeter.window(for: "gpt-4o",
                                              pricing: AgentModelPricing(contextWindow: 0)),
                       128_000, "填 0 = 没填，退回内置表")
        XCTAssertNil(AgentModelMeter.window(for: "house-secret-model",
                                            pricing: AgentModelPricing(contextWindow: -5)))
    }

    func testContextPercent() {
        let readings = AgentModelMeter.readings(input: AgentMeterInput(model: "gpt-4o"),
                                                ledger: TokenUsageLedger(),
                                                lastPromptTokens: 12_800)
        XCTAssertEqual(readings.contextUsed, 12_800)
        XCTAssertEqual(readings.contextWindow, 128_000)
        XCTAssertEqual(readings.contextPercent ?? -1, 10, accuracy: 0.0001)
        XCTAssertEqual(AgentModelReadings.percentText(readings.contextPercent ?? 0), "10.0%")
    }

    func testContextPercentNilWhenWindowUnknown() {
        let readings = AgentModelMeter.readings(input: AgentMeterInput(model: "house-secret-model"),
                                                ledger: TokenUsageLedger(),
                                                lastPromptTokens: 900)
        XCTAssertEqual(readings.contextUsed, 900)
        XCTAssertNil(readings.contextWindow)
        XCTAssertNil(readings.contextPercent, "窗口未知就不给百分比（分母是猜的，数就是假的）")
    }

    func testContextPercentNotClampedWhenWindowTooSmall() {
        let readings = AgentModelMeter.readings(
            input: AgentMeterInput(model: "gpt-4o", pricing: AgentModelPricing(contextWindow: 1_000)),
            ledger: TokenUsageLedger(),
            lastPromptTokens: 2_000)
        XCTAssertEqual(readings.contextPercent ?? -1, 200, accuracy: 0.0001,
                       "窗口填小了就要露出 >100% 这个信号，不许夹到 100 骗人")
    }

    // MARK: - 第二格：缓存读数（三种端点形状）

    func testUsageParsesOpenAICacheDetails() {
        let usage = LLMUsage.parsed(from: [
            "prompt_tokens": 1_000, "completion_tokens": 50, "total_tokens": 1_050,
            "prompt_tokens_details": ["cached_tokens": 800]
        ])
        XCTAssertEqual(usage.promptTokens, 1_000)
        XCTAssertEqual(usage.cachedPromptTokens, 800)
    }

    func testUsageParsesDeepSeekCacheField() {
        let usage = LLMUsage.parsed(from: [
            "prompt_tokens": 2_000, "completion_tokens": 10, "total_tokens": 2_010,
            "prompt_cache_hit_tokens": 1_500, "prompt_cache_miss_tokens": 500
        ])
        XCTAssertEqual(usage.cachedPromptTokens, 1_500)
    }

    func testUsageParsesAnthropicCacheField() {
        let usage = LLMUsage.parsed(from: [
            "prompt_tokens": 900, "completion_tokens": 30, "cache_read_input_tokens": 600
        ])
        XCTAssertEqual(usage.cachedPromptTokens, 600)
    }

    func testUsageWithoutCacheFieldIsNilNotZero() {
        let usage = LLMUsage.parsed(from: ["prompt_tokens": 100, "completion_tokens": 5, "total_tokens": 105])
        XCTAssertEqual(usage.promptTokens, 100)
        XCTAssertNil(usage.cachedPromptTokens, "没报 ≠ 零命中")
    }

    func testUsageRejectsCacheReadingAbovePrompt() {
        let usage = LLMUsage.parsed(from: [
            "prompt_tokens": 100, "prompt_tokens_details": ["cached_tokens": 300]
        ])
        XCTAssertNil(usage.cachedPromptTokens, "120% 的命中率比不显示更坏")
    }

    func testUsageRejectsNegativeCacheReading() {
        let usage = LLMUsage.parsed(from: [
            "prompt_tokens": 100, "prompt_cache_hit_tokens": -40
        ])
        XCTAssertNil(usage.cachedPromptTokens)
    }

    func testStreamUsageEventCarriesCacheReading() throws {
        var decoder = LLMStreamDecoder()
        let sse = """
        data: {"model":"deepseek-chat","choices":[{"delta":{"content":"hi"}}]}

        data: {"model":"deepseek-chat","choices":[],"usage":{"prompt_tokens":400,"completion_tokens":2,"total_tokens":402,"prompt_cache_hit_tokens":320}}

        data: [DONE]

        """
        var seen: LLMUsage?
        for event in decoder.feed(Data(sse.utf8)) {
            if case .usage(let usage, _) = event { seen = usage }
        }
        XCTAssertEqual(seen?.cachedPromptTokens, 320, "流式这条路必须带出缓存读数（否则界面上那一格永远不出现）")
    }

    // MARK: - 第二格：会话账

    func testLedgerCacheHitPercentNilUntilReported() {
        var ledger = TokenUsageLedger()
        ledger.add(prompt: 1_000, completion: 10)
        XCTAssertNil(ledger.cacheHitPercent, "一次都没报 ⇒ 不画这一格（不是 0%）")
        XCTAssertEqual(ledger.responsesWithCacheReading, 0)
    }

    func testLedgerCacheHitPercentUsesOnlyReportingTurns() {
        var ledger = TokenUsageLedger()
        ledger.add(prompt: 1_000, completion: 10)                        // 没报缓存
        ledger.add(prompt: 1_000, completion: 10, cached: 900)           // 报：900/1000
        ledger.add(prompt: 500, completion: 10, cached: 100)             // 报：100/500
        XCTAssertEqual(ledger.cacheHitPercent ?? -1, 1_000.0 * 100 / 1_500, accuracy: 0.0001,
                       "分母只算报了缓存读数的那些轮次（不然「不知道」被当成零命中）")
        XCTAssertEqual(ledger.promptTokens, 2_500, "总量照旧全算")
        XCTAssertEqual(ledger.cachedPromptTokens, 1_000)
    }

    func testLedgerRejectsBadCacheValues() {
        var ledger = TokenUsageLedger()
        ledger.add(prompt: 100, completion: 1, cached: 200)   // 坏值：大于输入
        ledger.add(prompt: 100, completion: 1, cached: -3)    // 坏值：负数
        ledger.add(prompt: nil, completion: nil, cached: 50)  // 没有输入 token，比不了
        XCTAssertEqual(ledger.responsesWithCacheReading, 0)
        XCTAssertNil(ledger.cacheHitPercent)
    }

    func testLedgerKeepsLegacyMissingUsageAccounting() {
        var ledger = TokenUsageLedger()
        XCTAssertFalse(ledger.add(prompt: 100, completion: 20))
        XCTAssertTrue(ledger.add(prompt: nil, completion: nil))
        XCTAssertEqual(ledger.requests, 2)
        XCTAssertEqual(ledger.responsesWithoutUsage, 1)
        XCTAssertEqual(ledger.totalTokens, 120, "缺值不当 0 累加（老口径一字未变）")
    }

    // MARK: - 第三格：花费估算

    func testCostBillsFreshCachedAndOutputSeparately() {
        let pricing = AgentModelPricing(inputPerMillion: 2, outputPerMillion: 8,
                                        cachedInputPerMillion: 0.5, currency: .cny)
        var ledger = TokenUsageLedger()
        ledger.add(prompt: 1_000_000, completion: 100_000, cached: 400_000)
        let estimate = AgentModelMeter.cost(pricing: pricing,
                                            promptTokens: ledger.promptTokens,
                                            completionTokens: ledger.completionTokens,
                                            cachedPromptTokens: ledger.cachedPromptTokens,
                                            requests: ledger.requests)
        // 600k 全价 + 400k 缓存价 + 100k 输出
        let expected = 0.6 * 2 + 0.4 * 0.5 + 0.1 * 8
        XCTAssertEqual(estimate?.amount ?? -1, expected, accuracy: 0.000001)
        XCTAssertEqual(estimate?.text, "≈¥2.20")
    }

    func testCostUsesInputPriceWhenCachedPriceMissing() {
        let pricing = AgentModelPricing(inputPerMillion: 1, outputPerMillion: 1, currency: .usd)
        let estimate = AgentModelMeter.cost(pricing: pricing, promptTokens: 1_000_000,
                                            completionTokens: 0, cachedPromptTokens: 500_000,
                                            requests: 1)
        XCTAssertEqual(estimate?.amount ?? -1, 1, accuracy: 0.000001,
                       "缓存价没填就按全价算（宁可高估，不许凭空更便宜）")
        XCTAssertEqual(estimate?.currency, .usd)
        XCTAssertEqual(estimate?.text, "≈$1.00")
    }

    func testCostNilWithoutPrices() {
        let estimate = AgentModelMeter.cost(pricing: AgentModelPricing(contextWindow: 128_000),
                                            promptTokens: 1_000, completionTokens: 10,
                                            cachedPromptTokens: 0, requests: 1)
        XCTAssertNil(estimate, "只有窗口没有价目 ⇒ 不给钱数（不自造 ¥0）")
    }

    func testCostNilWithOnlyOnePrice() {
        let estimate = AgentModelMeter.cost(pricing: AgentModelPricing(inputPerMillion: 3),
                                            promptTokens: 1_000, completionTokens: 10,
                                            cachedPromptTokens: 0, requests: 1)
        XCTAssertNil(estimate, "只填一档 = 算一半，那个数比不显示更坏")
    }

    func testCostNilBeforeAnyRequest() {
        let estimate = AgentModelMeter.cost(
            pricing: AgentModelPricing(inputPerMillion: 1, outputPerMillion: 1),
            promptTokens: 0, completionTokens: 0, cachedPromptTokens: 0, requests: 0)
        XCTAssertNil(estimate, "没跑过就没有花费（不是 0 元）")
    }

    func testCostMarksUpperBoundWhenSomeTurnsLackedCacheReading() {
        var ledger = TokenUsageLedger()
        ledger.add(prompt: 1_000, completion: 10, cached: 400)
        var readings = AgentModelMeter.readings(
            input: AgentMeterInput(model: "gpt-4o",
                                   pricing: AgentModelPricing(inputPerMillion: 1, outputPerMillion: 1)),
            ledger: ledger, lastPromptTokens: 1_000)
        XCTAssertFalse(readings.costIsUpperBound, "每一轮都报了缓存 ⇒ 不是上限")

        ledger.add(prompt: 2_000, completion: 10)   // 这一轮没报
        readings = AgentModelMeter.readings(
            input: AgentMeterInput(model: "gpt-4o",
                                   pricing: AgentModelPricing(inputPerMillion: 1, outputPerMillion: 1)),
            ledger: ledger, lastPromptTokens: 2_000)
        XCTAssertTrue(readings.costIsUpperBound, "有轮次没报缓存 ⇒ 估出来的是上限，界面要说清楚")
        XCTAssertTrue(readings.hasContextCell && readings.hasCacheCell && readings.hasCostCell)
    }

    // MARK: - 读数文本

    func testTokenShortFormatting() {
        XCTAssertEqual(AgentTokenShort.text(0), "0")
        XCTAssertEqual(AgentTokenShort.text(999), "999")
        XCTAssertEqual(AgentTokenShort.text(12_345), "12.3k")
        XCTAssertEqual(AgentTokenShort.text(150_000), "150k")
        XCTAssertEqual(AgentTokenShort.text(1_048_576), "1.0M")
    }

    func testCostAmountTextBands() {
        XCTAssertEqual(AgentCostEstimate.amountText(0), "0")
        XCTAssertEqual(AgentCostEstimate.amountText(0.0042), "0.0042")
        XCTAssertEqual(AgentCostEstimate.amountText(0.0213), "0.021")
        XCTAssertEqual(AgentCostEstimate.amountText(2.0), "2.00")
        XCTAssertEqual(AgentCostEstimate.amountText(1234.5), "1234.5")
    }

    // MARK: - 配置面（真值源要存得住、老配置要读得回）

    func testPricingRoundTripsThroughConfigurationFile() throws {
        var configuration = AgentConfiguration(isEnabled: true, endpoint: "https://api.example.com/v1",
                                               model: "gpt-4o")
        var profile = try XCTUnwrap(configuration.activeProfile)
        profile.pricing = AgentModelPricing(contextWindow: 64_000, inputPerMillion: 1.5,
                                            outputPerMillion: 6, cachedInputPerMillion: 0.3,
                                            currency: .usd)
        configuration.updateProfile(profile)

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(AgentConfiguration.self, from: data)
        XCTAssertEqual(decoded.activeProfile?.pricing, profile.pricing,
                       "存一次读一次不许丢（否则用户填了价目、重启就没了）")
    }

    func testScopeModePersistsThroughConfigurationFile() throws {
        var configuration = AgentConfiguration(isEnabled: true, endpoint: "https://api.example.com/v1",
                                               model: "gpt-4o")
        configuration.scopeMode = .askEachAction
        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(AgentConfiguration.self, from: data)
        XCTAssertEqual(decoded.scopeMode, .askEachAction,
                       "「每个动作都问」存一次就得还是它（从前编码不写这一格 ⇒ 开关点了不生效）")
    }

    func testOldConfigurationWithoutPricingDecodesAsNil() throws {
        let legacy = """
        {"isEnabled":false,"profiles":[{"id":"default","name":"default","endpoint":"https://api.example.com/v1","model":"gpt-4o","timeoutSeconds":60,"secretKey":"agent.api-key"}],"activeProfileID":"default","scopeMode":"taskScope"}
        """
        let decoded = try JSONDecoder().decode(AgentConfiguration.self, from: Data(legacy.utf8))
        XCTAssertNil(decoded.activeProfile?.pricing, "老文件没有这一格 ⇒ 读成 nil，不触发迁移")
        XCTAssertEqual(decoded.model, "gpt-4o", "既有字段一个都没被这份新字段带歪")
    }
}
