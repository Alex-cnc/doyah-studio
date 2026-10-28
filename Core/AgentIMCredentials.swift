import Foundation

/// IM 通道凭据的**唯一落点**（`FR-AGT-LINK-CHAN-003` 的配置面）。
///
/// 为什么单独一件、不塞进 `agent.json`：通道凭据与模型端点无关（换模型不该丢通道），
/// 而且 AppID 是明文、Secret 是密钥 —— 两者必须分家（密钥只进系统凭据存储）。
///
/// 三条口径：
/// ① **Secret 只进不出**：对外只有「已配置 / 长度 / 尾 4」，读本体只有一个口子，留给传输层；
/// ② **配置文件里不含 Secret**：`im-channel-<kind>.json` 只有 AppID（判据按字节复核）；
/// ③ **凭据不校验真伪**：能不能连上要等传输层真发一次 —— 这一层只挡「明显粘错」，
///    不假装知道 QQ 网关的账号格式。
public enum AgentIMChannelCredentialKind: String, Codable, Sendable, CaseIterable {
    case qq

    /// 系统凭据存储里的条目名（与模型 API Key 的 `agent.api-key` 分开）。
    public var secretAccount: String { "agent-im-\(rawValue)" }

    /// 非敏感配置文件名（只放 AppID）。
    public var configFileName: String { "im-channel-\(rawValue).json" }
}

/// 密钥存储抽象（与 `AgentKeyStore` 同一理由：`import Security` 不进 Core）。
/// 契约：Secret **不落配置文件**、重启后可恢复、可被明确清除、不进日志与审计。
public protocol AgentIMSecretStore: Sendable {
    func setSecret(_ secret: String, for kind: AgentIMChannelCredentialKind) throws
    func secret(for kind: AgentIMChannelCredentialKind) throws -> String?
    func deleteSecret(for kind: AgentIMChannelCredentialKind) throws
}

/// 拒绝原因（机器码；人话在语言表，见 `AgentIMCredentialRejectionText`）。
public enum AgentIMCredentialProblem: String, Error, Equatable, Sendable {
    case appIDEmpty
    case appIDNotNumeric
    case appIDTooLong
    case secretEmpty
    case secretContainsWhitespace
}

/// 对外只读的形状：**没有** Secret 本体 —— 面板与 CLI 都只拿这一份。
public struct AgentIMCredentialStatus: Equatable, Sendable {
    public var kind: AgentIMChannelCredentialKind
    /// 明文（非敏感）。
    public var appID: String?
    public var secretConfigured: Bool
    public var secretLength: Int?
    /// 尾 4：让用户确认「填的是哪一把」，又不泄露本体。
    public var secretTail: String?
    public var configFileURL: URL

    /// 「没配」「只配了一半」这两种在面板上要说清楚，不许都画成一句。
    public var isComplete: Bool {
        !(appID ?? "").isEmpty && secretConfigured
    }
}

/// 通道凭据的读写面（配置面的一半；另一半是 CLI 与面板）。
///
/// 落盘位置与 `AgentConfigurationStore` 同一个目录：
/// `~/Library/Application Support/DoyahStudio/im-channel-qq.json`（只有 AppID）。
public struct AgentIMCredentialStore: Sendable {

    public var directoryURL: URL
    private let secretStore: AgentIMSecretStore

    /// - Parameters:
    ///   - directoryURL: 缺省 = 应用支持目录（判据一律显式传临时目录）。
    ///   - secretStore: 系统凭据存储；macOS → `KeychainAgentIMSecretStore`。
    public init(directoryURL: URL? = nil, secretStore: AgentIMSecretStore) {
        self.directoryURL = directoryURL ?? AgentIMCredentialStore.defaultDirectory()
        self.secretStore = secretStore
    }

    /// 与 `AgentConfigurationStore` 同一个目录（`DoyahIdentity` 是唯一来源）。
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(DoyahIdentity.applicationSupportDirectoryName, isDirectory: true)
    }

    public func fileURL(for kind: AgentIMChannelCredentialKind) -> URL {
        directoryURL.appendingPathComponent(kind.configFileName, isDirectory: false)
    }

    // MARK: - 规范化与校验

    /// AppID：去首尾空白；**必须纯数字**。
    ///
    /// 位数上限 64 是**防粘错**（把 Secret 粘进 AppID 那一格），不是官方规定 ——
    /// 这里不假装知道 QQ 网关的账号位数。
    public static func normalizedAppID(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AgentIMCredentialProblem.appIDEmpty }
        guard trimmed.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw AgentIMCredentialProblem.appIDNotNumeric
        }
        guard trimmed.count <= 64 else { throw AgentIMCredentialProblem.appIDTooLong }
        return trimmed
    }

    /// Secret：去掉末尾一个换行（`echo` 会带）与首尾空白；**内部不许有空白**。
    ///
    /// 不设长度下限：真密钥的位数由平台决定，编一个下限只会把合法密钥挡在门外。
    public static func normalizedSecret(_ raw: String) throws -> String {
        var text = raw
        if text.hasSuffix("\n") { text.removeLast() }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AgentIMCredentialProblem.secretEmpty }
        guard !trimmed.contains(where: { $0.isWhitespace }) else {
            throw AgentIMCredentialProblem.secretContainsWhitespace
        }
        return trimmed
    }

    // MARK: - 读

    /// 只读形状（面板、CLI、审计都用这一份）。
    ///
    /// 密钥本体在这一步读出来只为算「长度 / 尾 4」—— 函数返回后不再持有它。
    public func status(for kind: AgentIMChannelCredentialKind) throws -> AgentIMCredentialStatus {
        let secret = try secretStore.secret(for: kind)
        return AgentIMCredentialStatus(
            kind: kind,
            appID: loadAppID(for: kind),
            secretConfigured: !(secret ?? "").isEmpty,
            secretLength: secret.flatMap { $0.isEmpty ? nil : $0.count },
            secretTail: secret.flatMap { $0.isEmpty ? nil : String($0.suffix(4)) },
            configFileURL: fileURL(for: kind)
        )
    }

    /// **唯一**的密钥读取口：留给传输层（握手签名用）。界面与 CLI 一律拿 `status`。
    public func secret(for kind: AgentIMChannelCredentialKind) throws -> String? {
        try secretStore.secret(for: kind)
    }

    public func appID(for kind: AgentIMChannelCredentialKind) -> String? {
        loadAppID(for: kind)
    }

    // MARK: - 写

    /// 存凭据。`secret == nil` ⇒ **只改 AppID、不动既有的 Secret**（面板留空 = 不改）。
    ///
    /// 顺序：先校验、再写密钥、最后写配置文件 —— 校验失败时**什么都不落盘**（判据钉住）。
    @discardableResult
    public func save(appID: String, secret: String?,
                     for kind: AgentIMChannelCredentialKind) throws -> AgentIMCredentialStatus {
        let cleanAppID = try Self.normalizedAppID(appID)
        var cleanSecret: String?
        if let secret {
            let normalized = try Self.normalizedSecret(secret)
            cleanSecret = normalized
        }

        if let cleanSecret { try secretStore.setSecret(cleanSecret, for: kind) }
        try writeAppID(cleanAppID, for: kind)
        return try status(for: kind)
    }

    /// 清除：密钥与配置文件一起清（只清一半会留下「看着配过、其实连不上」的假象）。
    public func clear(for kind: AgentIMChannelCredentialKind) throws {
        try secretStore.deleteSecret(for: kind)
        try? FileManager.default.removeItem(at: fileURL(for: kind))
    }

    // MARK: - 落盘（只有 AppID）

    private struct ChannelFile: Codable, Equatable {
        var appID: String
    }

    private func loadAppID(for kind: AgentIMChannelCredentialKind) -> String? {
        guard let data = try? Data(contentsOf: fileURL(for: kind)),
              let file = try? JSONDecoder().decode(ChannelFile.self, from: data) else { return nil }
        // 盘上被手改成空串 ⇒ 当作「没配」，不把空串当凭据。
        let trimmed = file.appID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func writeAppID(_ appID: String, for kind: AgentIMChannelCredentialKind) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(ChannelFile(appID: appID))
        try data.write(to: fileURL(for: kind), options: .atomic)
    }
}

/// 拒绝原因的人话（`language` 由调用方给：语言只有一个来源）。
public enum AgentIMCredentialRejectionText {

    public static func line(for problem: AgentIMCredentialProblem, language: AppLanguage) -> String {
        switch problem {
        case .appIDEmpty: return LocalizedStrings.text(.agentIMAppIDEmpty, language: language)
        case .appIDNotNumeric: return LocalizedStrings.text(.agentIMAppIDNotNumeric, language: language)
        case .appIDTooLong: return LocalizedStrings.text(.agentIMAppIDTooLong, language: language)
        case .secretEmpty: return LocalizedStrings.text(.agentIMSecretEmpty, language: language)
        case .secretContainsWhitespace:
            return LocalizedStrings.text(.agentIMSecretHasWhitespace, language: language)
        }
    }
}
