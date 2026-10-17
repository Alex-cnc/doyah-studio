import Foundation

/// 一个**模型档**（`FR-AI-32` 模型多档配置与切换）。
///
/// 为什么要有档：一个用户手上通常不止一个模型（本地 Ollama 跑便宜活、云端跑难活；写作一个、代码一个）
/// —— 从前只能配一组 `endpoint` / `model`，换一次就得把上一组**擦掉**。
///
/// **密钥不进这里**：档里只存**钥匙串条目键名**（`secretKey`），密钥本体永远在钥匙串
/// （与 `FR-AI-01` 的「配置里没有 API Key 字段」同一条纪律）。
public struct AgentProfile: Codable, Equatable, Sendable, Identifiable {

    public var id: String
    /// 给人看的名字（界面可直接用；从老单档迁移来的档名是 ASCII 的 `default` —— Core 不写汉字字面量）。
    public var name: String
    /// 提供商预设 id（`AgentProviderPreset`；`nil` = 手工填的）。
    public var presetID: String?
    public var endpoint: String
    public var model: String
    public var timeoutSeconds: TimeInterval
    /// 钥匙串条目键（**只存键名**）。
    public var secretKey: String

    public init(id: String = UUID().uuidString, name: String, presetID: String? = nil,
                endpoint: String = "", model: String = "",
                timeoutSeconds: TimeInterval = AgentConfiguration.defaultTimeoutSeconds,
                secretKey: String? = nil) {
        self.id = id
        self.name = name
        self.presetID = presetID
        self.endpoint = endpoint
        self.model = model
        self.timeoutSeconds = timeoutSeconds
        self.secretKey = secretKey ?? AgentProfile.defaultSecretKey(for: id)
    }

    /// 新建档的钥匙串条目键（**一档一把，互不覆盖**）。
    public static func defaultSecretKey(for id: String) -> String { "agent.api-key.\(id)" }

    /// **从老单档迁移出来的那一档**沿用的旧条目键 —— 保证用户**已经存过的 key 仍读得回来**。
    public static let legacySecretKey = "agent.api-key"
}

/// 智能体接入配置（FR-AI-01）。
///
/// 设计要点：
/// - **安全默认**：`default` 是「总开关关闭 + 端点与模型为空」——装好软件不会自己往外发东西
///   （NFR-SEC-05 默认零外发、AC-AI-01）；
/// - **配置里没有 API Key 字段**：密钥只进系统钥匙串（`AgentKeyStore`），
///   从类型上就杜绝「密钥被写进配置文件 / 日志 / 审计」这一类事故；
/// - 本类型只描述「配了什么」，「能不能发」由 `AgentGate.decide` 判定。
public struct AgentConfiguration: Codable, Equatable, Sendable {

    /// 总开关（FR-AI-01）。关闭时**零外发**，与端点 / 模型 / 密钥是否配好无关。
    public var isEnabled: Bool
    /// **模型档清单**（`FR-AI-32`）：**至少一档**，不许为空（空 = 没有可用的配置）。
    public var profiles: [AgentProfile]
    /// 当前档的 id。指不到（被删 / 老文件里没写）时**退回第一档**（自愈，不留"没有当前档"这种状态）。
    public var activeProfileID: String?

    /// 当前档。
    public var activeProfile: AgentProfile? {
        if let id = activeProfileID, let hit = profiles.first(where: { $0.id == id }) { return hit }
        return profiles.first
    }

    /// OpenAI 兼容端点（**当前档的镜像，只读**）。
    ///
    /// 为什么是计算属性而不是再存一份：**单一真值源** —— 存两份必然漂移（改了档不改镜像、或反过来）。
    /// 全仓没有第二处写这三个字段（写入只经档的增删改 `updateProfile` / `addProfile`）。
    public var endpoint: String { activeProfile?.endpoint ?? "" }
    /// 模型名（当前档的镜像，只读）。
    public var model: String { activeProfile?.model ?? "" }
    /// 单次请求超时（当前档的镜像，只读）。
    public var timeoutSeconds: TimeInterval { activeProfile?.timeoutSeconds ?? Self.defaultTimeoutSeconds }
    /// 成本与配额（NFR-AI-04）。
    public var quota: AgentQuota
    /// 审批 / 护栏策略（FR-AI-09、FR-AI-12）：只读模式与白名单。
    ///
    /// v1.0 默认**只读**（`AgentGuardPolicy.readOnlyDefault`）：智能体发起的写操作 /
    /// DDL 一律被拒（AC-AI-02）。要放开必须显式关闭只读模式，且放开后写操作仍需逐次审批。
    public var guardPolicy: AgentGuardPolicy

    public init(
        isEnabled: Bool = false,
        endpoint: String = "",
        model: String = "",
        timeoutSeconds: TimeInterval = AgentConfiguration.defaultTimeoutSeconds,
        quota: AgentQuota = AgentQuota(),
        guardPolicy: AgentGuardPolicy = .readOnlyDefault,
        profiles: [AgentProfile]? = nil,
        activeProfileID: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.quota = quota
        self.guardPolicy = guardPolicy
        // 老形状（只给端点 / 模型 / 超时）⇒ **包成第一档**，沿用旧条目键（key 不丢）。
        let list = profiles ?? [AgentProfile(id: "default", name: "default",
                                             endpoint: endpoint, model: model,
                                             timeoutSeconds: timeoutSeconds,
                                             secretKey: AgentProfile.legacySecretKey)]
        self.profiles = list.isEmpty
            ? [AgentProfile(id: "default", name: "default", secretKey: AgentProfile.legacySecretKey)]
            : list
        self.activeProfileID = activeProfileID ?? self.profiles.first?.id
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        // 老字段（**只用于解码**：迁移成第一档；新文件不再写它们 —— 免得两个真值源）。
        case endpoint
        case model
        case timeoutSeconds
        case profiles
        case activeProfileID
        case quota
        case guardPolicy
    }

    /// 手写解码只为一件小事：**向后兼容**。
    ///
    /// 老版本的 `agent.json` 里没有 `guardPolicy` 字段，用合成解码会整份配置读不出来，
    /// 用户明明配好的端点 / 模型会被静默丢掉。缺字段时退回只读默认（也就是安全默认）。
    /// 顺带把白名单归一化（剔除 `unknown`，见 `AgentGuardPolicy.sanitized`）。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        // **迁移**：老 `agent.json` 只有一组端点 / 模型 ⇒ 原地变成第 1 档（id `default`），
        // 并**沿用旧条目键** `agent.api-key` —— 用户已存的密钥一个字都不用重填。
        let legacyEndpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? ""
        let legacyModel = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        let legacyTimeout = try container.decodeIfPresent(TimeInterval.self, forKey: .timeoutSeconds)
            ?? AgentConfiguration.defaultTimeoutSeconds
        let decodedProfiles = try container.decodeIfPresent([AgentProfile].self, forKey: .profiles) ?? []
        if decodedProfiles.isEmpty {
            let migrated = AgentProfile(id: "default", name: "default",
                                        endpoint: legacyEndpoint, model: legacyModel,
                                        timeoutSeconds: legacyTimeout,
                                        secretKey: AgentProfile.legacySecretKey)
            self.profiles = [migrated]
            self.activeProfileID = migrated.id
        } else {
            self.profiles = decodedProfiles
            let stored = try container.decodeIfPresent(String.self, forKey: .activeProfileID)
            self.activeProfileID = (stored.flatMap { id in decodedProfiles.contains { $0.id == id } ? id : nil })
                ?? decodedProfiles.first?.id
        }
        self.quota = try container.decodeIfPresent(AgentQuota.self, forKey: .quota) ?? AgentQuota()
        self.guardPolicy = (try container.decodeIfPresent(AgentGuardPolicy.self, forKey: .guardPolicy)
            ?? .readOnlyDefault).sanitized
    }

    /// 手写编码：**只写新形状**（`profiles` + `activeProfileID`），不写老镜像字段 ——
    /// 两个真值源必然漂移（第十二条：不许自己发明口径）。代价如实登记：**老构建读新文件会看到空端点**。
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(profiles, forKey: .profiles)
        try container.encodeIfPresent(activeProfileID, forKey: .activeProfileID)
        try container.encode(quota, forKey: .quota)
        try container.encode(guardPolicy, forKey: .guardPolicy)
    }

    // MARK: - 档的增删改（写入的唯一入口）

    /// 改某一档（改不到就什么都不做 —— **不静默造一个新档**）。
    public mutating func updateProfile(_ profile: AgentProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
    }

    /// 加一档（默认切过去）。
    public mutating func addProfile(_ profile: AgentProfile, makeActive: Bool = true) {
        profiles.append(profile)
        if makeActive { activeProfileID = profile.id }
    }

    /// 删一档。**至少留一档**（删到空 ⇒ 拒绝，返回 `false`）—— 没有档 = 没有可用的配置。
    @discardableResult
    public mutating func removeProfile(id: String) -> Bool {
        guard profiles.count > 1, let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
        profiles.remove(at: index)
        if activeProfileID == id { activeProfileID = profiles.first?.id }
        return true
    }

    /// 切档（切到不存在的档 ⇒ 拒绝）。
    @discardableResult
    public mutating func setActiveProfile(id: String) -> Bool {
        guard profiles.contains(where: { $0.id == id }) else { return false }
        activeProfileID = id
        return true
    }

    /// 默认超时（秒）。
    public static let defaultTimeoutSeconds: TimeInterval = 60
    /// 允许的最大超时（秒）：超过这个值多半是误填，不如直接拒绝。
    public static let maximumTimeoutSeconds: TimeInterval = 600

    /// 安全默认：总开关关闭、端点与模型为空。
    public static let `default` = AgentConfiguration()
}

// MARK: - 校验

/// 配置问题（阻断外发）。
public enum AgentConfigurationIssue: String, Equatable, Sendable, CaseIterable {
    case emptyEndpoint
    case invalidEndpoint
    case emptyModel
    case invalidTimeout
    case invalidQuota

    /// 可读说明，直接给界面用。
    public var message: String {
        switch self {
        case .emptyEndpoint: return "尚未填写模型服务端点。"
        case .invalidEndpoint: return "模型服务端点必须是 http(s) 地址，且包含主机名。"
        case .emptyModel: return "尚未填写模型名。"
        case .invalidTimeout: return "超时必须在 0 秒到 600 秒之间。"
        case .invalidQuota: return "配额上限必须是正整数（留空表示不限）。"
        }
    }
}

/// 配置警告（不阻断外发，但要在界面上提示）。
public enum AgentConfigurationWarning: String, Equatable, Sendable, CaseIterable {
    /// 远端明文 http 端点：密钥会以明文上网。
    case insecureRemoteEndpoint
    /// 只读模式已关闭：智能体可以发起写操作 / DDL（仍须逐次审批）。
    case agentWritesAllowed

    public var message: String {
        switch self {
        case .insecureRemoteEndpoint:
            return "该端点是远端 http 地址，API Key 会以明文传输；建议改用 https。"
        case .agentWritesAllowed:
            return "只读模式已关闭：智能体可以发起写操作 / DDL（每次仍需逐次批准）。"
        }
    }
}

public extension AgentConfiguration {

    /// 端点解析结果；不是合法的 http(s) URL 时为 `nil`。
    var endpointURL: URL? {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty
        else { return nil }
        return url
    }

    /// 去掉首尾空白的模型名；为空时 `nil`。
    var normalizedModel: String? {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 阻断性问题清单；为空即配置完整。
    var issues: [AgentConfigurationIssue] {
        var issues: [AgentConfigurationIssue] = []

        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedEndpoint.isEmpty {
            issues.append(.emptyEndpoint)
        } else if endpointURL == nil {
            issues.append(.invalidEndpoint)
        }

        if normalizedModel == nil {
            issues.append(.emptyModel)
        }

        if !(timeoutSeconds > 0) || timeoutSeconds > Self.maximumTimeoutSeconds {
            issues.append(.invalidTimeout)
        }

        issues.append(contentsOf: quota.issues)
        return issues
    }

    /// 配置是否完整（不含总开关状态）。
    var isComplete: Bool { issues.isEmpty }

    /// 警告清单。
    var warnings: [AgentConfigurationWarning] {
        var warnings: [AgentConfigurationWarning] = []
        if let url = endpointURL,
           url.scheme?.lowercased() == "http",
           !isLocalEndpoint {
            warnings.append(.insecureRemoteEndpoint)
        }
        // 只读模式是 v1.0 的安全默认；关掉它值得在界面上说出来（FR-AI-09）。
        if !guardPolicy.readOnly {
            warnings.append(.agentWritesAllowed)
        }
        return warnings
    }

    /// 实际生效的护栏 / 审批策略（白名单已归一化，`unknown` 不在其中）。
    var effectiveGuardPolicy: AgentGuardPolicy { guardPolicy.sanitized }

    /// 端点是否指向本机 / 局域网（NFR-AI-06 本地模型优先）。
    ///
    /// 覆盖：`localhost`、`*.local`、IPv4 环回 `127/8`、RFC1918 私有段
    /// （`10/8`、`192.168/16`、`172.16/12`）、链路本地 `169.254/16`、
    /// IPv6 环回 `::1` 与唯一本地地址 `fc00::/7` / 链路本地 `fe80::/10`。
    /// 这些地址不会把数据带到公网。
    var isLocalEndpoint: Bool {
        guard let rawHost = endpointURL?.host?.lowercased() else { return false }
        // IPv6 字面量在 URL 里带方括号（`[::1]`），先剥掉再判断。
        let host = rawHost.hasPrefix("[") && rawHost.hasSuffix("]")
            ? String(rawHost.dropFirst().dropLast())
            : rawHost

        if host == "localhost" || host.hasSuffix(".localhost") { return true }
        if host.hasSuffix(".local") { return true }
        if host == "0.0.0.0" { return true }

        // IPv6（含 `::1`、`fc00::/7`、`fe80::/10`）
        if host.contains(":") {
            if host == "::1" { return true }
            if host.hasPrefix("fc") || host.hasPrefix("fd") || host.hasPrefix("fe80") { return true }
        }

        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }
        switch (octets[0], octets[1]) {
        case (127, _): return true                       // 环回
        case (10, _): return true                        // RFC1918
        case (192, 168): return true                     // RFC1918
        case (172, 16...31): return true                 // RFC1918
        case (169, 254): return true                     // 链路本地
        default: return false
        }
    }

    /// 是否需要 API Key：本地端点（Ollama / vLLM 等）不需要。
    var requiresAPIKey: Bool { !isLocalEndpoint }
}

// MARK: - 外发判定

/// 一次外发前的判定结果（FR-AI-01 / AC-AI-01）。
public enum AgentOutboundDecision: Equatable, Sendable {
    /// 允许外发。
    case allowed(endpoint: URL, model: String, warnings: [AgentConfigurationWarning])
    /// 总开关关闭：**一律不外发**。
    case disabled
    /// 配置不完整。
    case misconfigured([AgentConfigurationIssue])
    /// 缺少 API Key。
    case missingAPIKey

    public var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }

    /// 可读说明（拒绝时给界面用）。
    public var message: String {
        switch self {
        case .allowed(_, let model, let warnings):
            if warnings.isEmpty { return "将使用模型 \(model)。" }
            return "将使用模型 \(model)。" + warnings.map(\.message).joined(separator: " ")
        case .disabled:
            return "智能体总开关已关闭，不会向任何模型服务发送数据。"
        case .misconfigured(let issues):
            return issues.map(\.message).joined(separator: " ")
        case .missingAPIKey:
            return "尚未配置该端点的 API Key。"
        }
    }
}

/// 外发闸门（FR-AI-01、NFR-AI-02）。
///
/// **唯一入口**：所有要走模型网络请求的路径都应先问这里，不要在别处自己判断
/// 「开关是否打开」——把判定收在一处，AC-AI-01「关闭总开关后外发流量为 0」
/// 才是可核对的性质，而不是散落各处的 if。
public enum AgentGate {

    /// 判定本次是否可以外发。
    ///
    /// **顺序即语义**：总开关最先判断，关闭时立即返回 `.disabled`，
    /// 后面即使端点 / 模型 / 密钥都齐全也绝不外发。
    public static func decide(
        configuration: AgentConfiguration,
        apiKey: String?
    ) -> AgentOutboundDecision {
        guard configuration.isEnabled else { return .disabled }

        let issues = configuration.issues
        guard issues.isEmpty,
              let endpoint = configuration.endpointURL,
              let model = configuration.normalizedModel
        else {
            return .misconfigured(issues.isEmpty ? [.invalidEndpoint] : issues)
        }

        let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        if configuration.requiresAPIKey, key?.isEmpty ?? true {
            return .missingAPIKey
        }

        return .allowed(endpoint: endpoint, model: model, warnings: configuration.warnings)
    }
}

// MARK: - 配额（NFR-AI-04）

/// 配额配置；`nil` 表示该项不限。
public struct AgentQuota: Codable, Equatable, Sendable {
    /// 单次会话最多调用次数。
    public var maxRequestsPerSession: Int?
    /// 单次请求最多输出 token。
    public var maxOutputTokensPerRequest: Int?
    /// 累计 token 上限。
    public var maxTotalTokens: Int?

    public init(
        maxRequestsPerSession: Int? = nil,
        maxOutputTokensPerRequest: Int? = nil,
        maxTotalTokens: Int? = nil
    ) {
        self.maxRequestsPerSession = maxRequestsPerSession
        self.maxOutputTokensPerRequest = maxOutputTokensPerRequest
        self.maxTotalTokens = maxTotalTokens
    }

    /// 未配置任何上限。
    public var isUnlimited: Bool {
        maxRequestsPerSession == nil && maxOutputTokensPerRequest == nil && maxTotalTokens == nil
    }

    var issues: [AgentConfigurationIssue] {
        var issues: [AgentConfigurationIssue] = []
        for value in [maxRequestsPerSession, maxOutputTokensPerRequest, maxTotalTokens] {
            if let value, value <= 0 { issues.append(.invalidQuota) }
        }
        return issues
    }

    /// 调用前的判定：超限返回具体原因（不是静默失败）。
    /// 是否放行本次调用（NFR-AI-04：**超限即终止并提示**）。
    ///
    /// - `requestedOutputTokens` 是**本次调用最多还要用多少 token 的预算**（真实路径传 `maxOutputTokensPerRequest`，
    ///   它同时作为 `max_tokens` 下发给模型）。有了它，累计上限才是"提前拦"而不是"超了才拦"。
    ///
    /// **一个必须讲清的边界**：客户端**不数 token**，所以预算只覆盖**输出侧**；
    /// 提示词很大时，一次调用仍可能把累计量顶过上限（下一次才会被拦）。这不是疏忽，
    /// 而是"不为了精确而引入一个 tokenizer"的取舍，已在需求书 R-41 登记。
    public func decision(
        ledger: AgentQuotaLedger,
        requestedOutputTokens: Int? = nil
    ) -> AgentQuotaDecision {
        if let limit = maxRequestsPerSession, ledger.requestCount >= limit {
            return .requestLimitReached(limit: limit)
        }
        if let limit = maxTotalTokens {
            // 已经用满 → 拦；再加本次预算就会超 → 也拦（这一条此前永远不会触发：
            // 调用方传进来的就是它自己比较的那个上限，见 v3.88 的修正说明）。
            let expected = ledger.totalTokens + max(0, requestedOutputTokens ?? 0)
            if ledger.totalTokens >= limit {
                return .tokenLimitReached(limit: limit, used: ledger.totalTokens)
            }
            if expected > limit {
                return .tokenLimitReached(limit: limit, used: expected)
            }
        }
        if let limit = maxOutputTokensPerRequest, let requested = requestedOutputTokens, requested > limit {
            return .outputTokenLimitExceeded(requested: requested, limit: limit)
        }
        return .allowed
    }

    /// 调用完成后记账。
    public func record(ledger: AgentQuotaLedger, usedTokens: Int) -> AgentQuotaLedger {
        AgentQuotaLedger(
            requestCount: ledger.requestCount + 1,
            totalTokens: ledger.totalTokens + max(0, usedTokens)
        )
    }
}

/// 已消耗的配额。
public struct AgentQuotaLedger: Codable, Equatable, Sendable {
    public var requestCount: Int
    public var totalTokens: Int

    public init(requestCount: Int = 0, totalTokens: Int = 0) {
        self.requestCount = requestCount
        self.totalTokens = totalTokens
    }

    public static let empty = AgentQuotaLedger()
}

/// 配额判定结果。
public enum AgentQuotaDecision: Equatable, Sendable {
    case allowed
    case requestLimitReached(limit: Int)
    case tokenLimitReached(limit: Int, used: Int)
    case outputTokenLimitExceeded(requested: Int, limit: Int)

    public var isAllowed: Bool { self == .allowed }

    /// 可读提示：超限即终止并说明原因（NFR-AI-04）。
    public var message: String {
        switch self {
        case .allowed:
            return ""
        case .requestLimitReached(let limit):
            return "已达到本会话的调用次数上限（\(limit) 次），本次请求已终止。"
        case .tokenLimitReached(let limit, let used):
            return "已达到累计 token 上限（\(limit)，已用 \(used)），本次请求已终止。"
        case .outputTokenLimitExceeded(let requested, let limit):
            return "本次请求要求输出 \(requested) token，超过单次上限 \(limit)，已终止。"
        }
    }
}
