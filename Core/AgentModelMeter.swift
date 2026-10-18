import Foundation

/// 计价币种（价目表的一列，`FR-AI-25` 信息面第三格）。
///
/// **不做汇率换算**：本机没有可信汇率源，编一个汇率比不显示更坏 ——
/// 价目表里写的是哪个币种，读数就用哪个币种的符号。
public enum AgentPriceCurrency: String, Codable, Sendable, Equatable, CaseIterable {
    case cny = "CNY"
    case usd = "USD"

    /// 读数前缀用的符号（是**符号**不是文案，语言表不需要它）。
    public var symbol: String {
        switch self {
        case .cny: return "¥"
        case .usd: return "$"
        }
    }
}

/// 一个模型的**真值源**（`FR-AI-25` 状态块三格：窗口多大 / 缓存读多少 / 每百万 token 多少钱）。
///
/// 为什么要用户填、而不是内置一份「官方价目表」：
/// 价格随时在变，写死一份等于**把过期数字当真值显示**（比不显示更坏）；
/// 自定义网关 / 代理后面那个模型的窗口未必与同名官方模型同尺寸。
/// 内置表只覆盖「尺寸是结构事实、不随价格漂移」的常见家族，**认不出就报未知**。
public struct AgentModelPricing: Codable, Equatable, Sendable {

    /// 上下文窗口（token）。`nil` = 用内置表；内置表也认不出 = 未知（界面显示「窗口未知」）。
    public var contextWindow: Int?
    /// 每百万**输入** token 的价格（缓存未命中那一档）。
    public var inputPerMillion: Double?
    /// 每百万**输出** token 的价格。
    public var outputPerMillion: Double?
    /// 每百万**缓存命中**输入 token 的价格。缺省 = 按输入价算（不假装更便宜）。
    public var cachedInputPerMillion: Double?
    public var currency: AgentPriceCurrency

    public init(contextWindow: Int? = nil,
                inputPerMillion: Double? = nil,
                outputPerMillion: Double? = nil,
                cachedInputPerMillion: Double? = nil,
                currency: AgentPriceCurrency = .cny) {
        self.contextWindow = contextWindow
        self.inputPerMillion = inputPerMillion
        self.outputPerMillion = outputPerMillion
        self.cachedInputPerMillion = cachedInputPerMillion
        self.currency = currency
    }

    /// 一个字都没填（保存时就不往配置里写空壳）。
    public var isEmpty: Bool {
        contextWindow == nil && inputPerMillion == nil
            && outputPerMillion == nil && cachedInputPerMillion == nil
    }

    /// 能不能算钱：**输入与输出两档都得有**。少一档就不给数字 ——
    /// 只算一半再显示出来，等于把一个偏小的数当账单。
    public var canEstimateCost: Bool { inputPerMillion != nil && outputPerMillion != nil }
}

/// 一次性花费估算（金额 + 币种；文本按固定小数位规则给，界面直接用）。
public struct AgentCostEstimate: Equatable, Sendable {

    public var amount: Double
    public var currency: AgentPriceCurrency

    public init(amount: Double, currency: AgentPriceCurrency) {
        self.amount = amount
        self.currency = currency
    }

    /// 读数文本（`≈¥0.0213`）。小数位按量级选：小额多给几位，否则看着永远是 0.00。
    public var text: String { "≈" + currency.symbol + Self.amountText(amount) }

    /// 金额文本（不含符号）。
    ///
    /// 规则（判据逐档钉住）：`<= 0` ⇒ `0`；`< 0.01` ⇒ 4 位；`< 1` ⇒ 3 位；
    /// `< 100` ⇒ 2 位；其余 1 位。
    public static func amountText(_ amount: Double) -> String {
        guard amount > 0 else { return "0" }
        if amount < 0.01 { return String(format: "%.4f", amount) }
        if amount < 1 { return String(format: "%.3f", amount) }
        if amount < 100 { return String(format: "%.2f", amount) }
        return String(format: "%.1f", amount)
    }
}

/// token 数的短写法（`12.3k` / `1.0M`）——状态块那一行很窄，放不下 6 位整数。
public enum AgentTokenShort {

    public static func text(_ tokens: Int) -> String {
        let value = max(0, tokens)
        if value < 1_000 { return "\(value)" }
        if value < 1_000_000 {
            let k = Double(value) / 1_000
            // 100k 以下给一位小数（`12.3k`），再往上取整（`150k`）—— 状态行很窄，
            // 多一位小数会把后面两格挤掉。
            return String(format: k < 100 ? "%.1f" : "%.0f", k) + "k"
        }
        let m = Double(value) / 1_000_000
        return String(format: m < 10 ? "%.1f" : "%.0f", m) + "M"
    }
}

/// 已知模型的**窗口**内置表。
///
/// 只收「尺寸是结构事实、几乎不随价格漂移」的常见家族；**认不出返回 `nil`**，
/// 由界面如实显示「窗口未知」，用户可在设置里补一个数（`AgentModelPricing.contextWindow`）。
/// 刻意**不内置价格**：价格随版本变，内置一份就是把过期数字当真值。
public enum AgentModelWindowCatalog {

    /// 家族名（小写，按包含匹配；**长串优先** —— `gpt-4o-mini` 不能被 `gpt-4o` 抢先）。
    private static let families: [(key: String, window: Int)] = [
        ("gpt-4.1", 1_047_576),
        ("gpt-4o", 128_000),
        ("o1", 200_000),
        ("o3", 200_000),
        ("claude", 200_000),
        ("deepseek-chat", 64_000),
        ("deepseek-reasoner", 64_000),
        ("glm-4", 128_000),
        ("qwen-long", 10_000_000),
        ("gemini-1.5-pro", 2_097_152),
        ("gemini-1.5-flash", 1_048_576),
        ("gemini-2.0-flash", 1_048_576),
        ("llama-3", 128_000),
        ("llama3", 128_000),
        ("mistral-large", 131_072),
        ("mistral-small", 131_072),
        ("grok-2", 131_072)
    ]

    /// 名字里自带的窗口尺寸（`moonshot-v1-8k` / `qwen-128k` / `xxx-1m`）——
    /// 这类名字本身就是尺寸，不需要查表。`k` 按 1024 算（业内命名惯例），`m` 按 1_048_576。
    public static func window(for model: String) -> Int? {
        let name = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty else { return nil }
        for family in families.sorted(by: { $0.key.count > $1.key.count }) where name.contains(family.key) {
            return family.window
        }
        return windowFromNameSuffix(name)
    }

    private static func windowFromNameSuffix(_ name: String) -> Int? {
        let tail = name.split(separator: "-").last.map(String.init) ?? name
        guard tail.count >= 2, let unit = tail.last, unit == "k" || unit == "m" else { return nil }
        let digits = tail.dropLast()
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let value = Int(digits), value > 0 else { return nil }
        return unit == "k" ? value * 1_024 : value * 1_048_576
    }
}

/// 状态块三格的读数。**每一格都可能缺**：缺就不画，不补 0、不猜。
public struct AgentModelReadings: Equatable, Sendable {

    /// 上下文占用 = 上一次请求的输入 token（端点自己报的那个数）。
    public var contextUsed: Int?
    /// 上下文窗口（用户填的优先，其次内置表）；`nil` = 未知。
    public var contextWindow: Int?
    /// 占用百分比。**不夹到 100**：窗口填小了就会 > 100，那正是要让人看见的信号。
    public var contextPercent: Double?
    /// 缓存命中率（0…100）。`nil` = 端点没报过缓存读数（**不当 0%**）。
    public var cacheHitPercent: Double?
    /// 本会话估算花费。`nil` = 没配价目（不自造一个 `¥0`）。
    public var estimatedCost: AgentCostEstimate?
    /// 有轮次没报缓存读数 ⇒ 那些 token 按全价算，估出来的是**上限**。
    public var costIsUpperBound: Bool

    public init(contextUsed: Int? = nil, contextWindow: Int? = nil, contextPercent: Double? = nil,
                cacheHitPercent: Double? = nil, estimatedCost: AgentCostEstimate? = nil,
                costIsUpperBound: Bool = false) {
        self.contextUsed = contextUsed
        self.contextWindow = contextWindow
        self.contextPercent = contextPercent
        self.cacheHitPercent = cacheHitPercent
        self.estimatedCost = estimatedCost
        self.costIsUpperBound = costIsUpperBound
    }

    public var hasContextCell: Bool { contextUsed != nil }
    public var hasCacheCell: Bool { cacheHitPercent != nil }
    public var hasCostCell: Bool { estimatedCost != nil }

    /// 百分比文本（一位小数）。判据钉住格式，免得界面各处自己 `String(format:)` 出两种口径。
    public static func percentText(_ value: Double) -> String {
        String(format: "%.1f", value) + "%"
    }
}

/// 宿主交给界面的**当前档真值源**（模型名 + 价目）。
public struct AgentMeterInput: Equatable, Sendable {

    public var model: String
    public var pricing: AgentModelPricing?

    public init(model: String = "", pricing: AgentModelPricing? = nil) {
        self.model = model
        self.pricing = pricing
    }
}

/// 三格读数的**唯一换算处**：窗口解析、占比、缓存命中率、花费估算都在这里，
/// 界面只负责画 —— 于是「同一份用量在两处算出两个数」不可能发生。
public enum AgentModelMeter {

    /// 上下文窗口：用户填的有效值优先，其次内置表，最后**如实未知**。
    public static func window(for model: String, pricing: AgentModelPricing?) -> Int? {
        if let explicit = pricing?.contextWindow, explicit > 0 { return explicit }
        return AgentModelWindowCatalog.window(for: model)
    }

    public static func readings(input: AgentMeterInput,
                               ledger: TokenUsageLedger,
                               lastPromptTokens: Int?) -> AgentModelReadings {
        var readings = AgentModelReadings()
        readings.contextUsed = lastPromptTokens
        readings.contextWindow = window(for: input.model, pricing: input.pricing)
        if let used = lastPromptTokens, let window = readings.contextWindow, window > 0 {
            readings.contextPercent = Double(used) * 100 / Double(window)
        }
        readings.cacheHitPercent = ledger.cacheHitPercent
        readings.estimatedCost = cost(pricing: input.pricing,
                                      promptTokens: ledger.promptTokens,
                                      completionTokens: ledger.completionTokens,
                                      cachedPromptTokens: ledger.cachedPromptTokens,
                                      requests: ledger.requests)
        readings.costIsUpperBound = ledger.requests > ledger.responsesWithCacheReading
        return readings
    }

    /// 花费估算。**缺档就给 `nil`**（不把半个价目算出来的数当账单）。
    static func cost(pricing: AgentModelPricing?,
                     promptTokens: Int,
                     completionTokens: Int,
                     cachedPromptTokens: Int,
                     requests: Int) -> AgentCostEstimate? {
        guard requests > 0,
              let pricing, pricing.canEstimateCost,
              let inputPrice = pricing.inputPerMillion,
              let outputPrice = pricing.outputPerMillion else { return nil }
        let cached = min(max(0, cachedPromptTokens), max(0, promptTokens))
        let freshInput = max(0, promptTokens - cached)
        // 缓存价没填 ⇒ 按输入价算（宁可高估，也不许凭空给个更便宜的价）。
        let cachePrice = pricing.cachedInputPerMillion ?? inputPrice
        let amount = Double(freshInput) / 1_000_000 * inputPrice
            + Double(cached) / 1_000_000 * cachePrice
            + Double(max(0, completionTokens)) / 1_000_000 * outputPrice
        return AgentCostEstimate(amount: amount, currency: pricing.currency)
    }
}
