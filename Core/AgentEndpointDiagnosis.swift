import Foundation

/// 端点判定（`NFR-ALL-GATE-AI-006` ③）：**唯一出处**。
///
/// 为什么要有这一层：原先只有一句 `isLocalEndpoint: Bool`，于是三种完全不同的处境被压成一枚布尔：
/// 远端（该填 Key）、本地（免 Key）、**根本用不了**（少协议头 / 协议不对 / 没主机名）。
/// 第三种被读成「远端，需要 API Key」—— 人会去填一把 Key 再试，而真正的原因一个字都没说。
/// 这里把判定拆成三档，并且**每一档带上可读原因**；「什么算本地」仍然只有一份（`isLocalHost`），
/// `AgentConfiguration` 与提供商预设都问这一处，不在别处再判一遍。
public struct AgentEndpointDiagnosis: Equatable, Sendable {

    /// 三档判定。
    public enum Verdict: Equatable, Sendable {
        /// 本机 / 局域网端点：**免 API Key**（`NFR-ALL-GATE-AI-006` ①）。
        case local(host: String)
        /// 公网端点：走同一套 OpenAI 兼容接口，需要 API Key（②）。
        case remote(host: String)
        /// 端点不可用：给得出**具体是哪一步不对**（③）。
        case unusable(AgentEndpointProblem)
    }

    /// 用户敲进去的原文（已去首尾空白）。
    public let raw: String
    /// 判定结果。
    public let verdict: Verdict
    /// 解析出来的协议名（`http` / `https` / 别的什么）—— 「协议不支持」时用它把话说清。
    public let scheme: String?

    public init(endpoint: String) {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        raw = trimmed

        guard !trimmed.isEmpty else {
            verdict = .unusable(.empty)
            scheme = nil
            return
        }
        // 有没有协议头：`localhost:11434/v1` 这种写法里 `URL(string:)` 会把 `localhost`
        // 当成协议名（`scheme = "localhost"`），所以不能拿 `url.scheme` 来判「有没有协议头」——
        // 提前按 `://` 是否在场来分，报错才指得准（该补 `http://`，而不是「协议不支持」）。
        guard let separator = trimmed.range(of: "://") else {
            verdict = .unusable(.missingScheme)
            scheme = nil
            return
        }
        let rawScheme = String(trimmed[trimmed.startIndex..<separator.lowerBound]).lowercased()
        scheme = rawScheme.isEmpty ? nil : rawScheme

        guard rawScheme == "http" || rawScheme == "https" else {
            verdict = .unusable(.unsupportedScheme)
            return
        }

        guard let url = URL(string: trimmed) else {
            verdict = .unusable(.malformed)
            return
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            verdict = .unusable(.missingHost)
            return
        }

        verdict = Self.isLocalHost(host) ? .local(host: host) : .remote(host: host)
    }

    /// 是否本地 / 局域网端点。
    public var isLocal: Bool {
        if case .local = verdict { return true }
        return false
    }

    /// 是否远端端点（**只有它**需要 API Key）。
    public var isRemote: Bool {
        if case .remote = verdict { return true }
        return false
    }

    /// 端点是否可用（本地或远端都算可用；不可用单独一档）。
    public var isUsable: Bool { isLocal || isRemote }

    /// 是否需要 API Key：本机 / 局域网端点不需要（`NFR-ALL-GATE-AI-006` ①）。
    ///
    /// 不可用的端点这里返回 `false` —— 它不是「缺 Key」，而是**缺一个能用的地址**；
    /// 把它算成「需要 Key」会让人去补一把没用的 Key。
    public var requiresAPIKey: Bool { isRemote }

    /// 主机名（不可用时为 `nil`）。
    public var host: String? {
        switch verdict {
        case .local(let host), .remote(let host): return host
        case .unusable: return nil
        }
    }

    /// 不可用的那一档（可用时为 `nil`）。
    public var problem: AgentEndpointProblem? {
        if case .unusable(let problem) = verdict { return problem }
        return nil
    }

    /// 不可用时的可读原因；可用时为 `nil`。
    public func problemMessage(language: AppLanguage) -> String? {
        guard let problem else { return nil }
        if problem == .unsupportedScheme, let scheme {
            return LocalizedStrings.format(
                .agentEndpointProblemUnsupportedScheme,
                language: language,
                scheme
            )
        }
        return problem.message(language: language)
    }

    /// 一行结论（命令行与设置面板共用同一句）。
    public func summary(language: AppLanguage) -> String {
        switch verdict {
        case .local(let host):
            return LocalizedStrings.format(.agentEndpointVerdictLocal, language: language, host)
        case .remote(let host):
            return LocalizedStrings.format(.agentEndpointVerdictRemote, language: language, host)
        case .unusable:
            return LocalizedStrings.format(
                .agentEndpointVerdictUnusable,
                language: language,
                problemMessage(language: language) ?? ""
            )
        }
    }

    /// 「什么算本地」的**唯一定义**。
    ///
    /// 覆盖：`localhost`（含 `*.localhost`）、`*.local`、`0.0.0.0`、IPv4 环回 `127/8`、
    /// RFC1918 私有段（`10/8`、`192.168/16`、`172.16/12`）、链路本地 `169.254/16`、
    /// IPv6 环回 `::1` 与唯一本地地址 `fc00::/7` / 链路本地 `fe80::/10`。
    /// 这些地址不会把数据带到公网。
    public static func isLocalHost(_ rawHost: String) -> Bool {
        let lowered = rawHost.lowercased()
        // IPv6 字面量在 URL 里带方括号（`[::1]`），先剥掉再判断。
        let host = lowered.hasPrefix("[") && lowered.hasSuffix("]")
            ? String(lowered.dropFirst().dropLast())
            : lowered

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
}

/// 端点判不了的那一步（`NFR-ALL-GATE-AI-006` ③：判定失败要给可读原因）。
public enum AgentEndpointProblem: String, Equatable, Sendable, CaseIterable {
    /// 端点没填。
    case empty
    /// 少了协议头（`localhost:11434/v1`）。
    case missingScheme
    /// 协议不是 http / https（`ftp://…`、`postgres://…`）。
    case unsupportedScheme
    /// 有协议头但没主机名（`http://`、`http:///v1`）。
    case missingHost
    /// 其余解析不了的形状（含空格等非法字符）。
    case malformed

    /// 可读原因。
    public func message(language: AppLanguage) -> String {
        switch self {
        case .empty:
            return LocalizedStrings.text(.agentEndpointProblemEmpty, language: language)
        case .missingScheme:
            return LocalizedStrings.text(.agentEndpointProblemMissingScheme, language: language)
        case .unsupportedScheme:
            return LocalizedStrings.text(.agentEndpointProblemUnsupportedScheme, language: language)
        case .missingHost:
            return LocalizedStrings.text(.agentEndpointProblemMissingHost, language: language)
        case .malformed:
            return LocalizedStrings.text(.agentEndpointProblemMalformed, language: language)
        }
    }
}
