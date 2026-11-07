import Foundation

/// 审批授权的**三档**（详设 §3.36）。
///
/// 由头（beta1.0.6 真机）：每一条危险调用都拦一次，同一条命令重跑十几遍就要点十几遍 ——
/// 于是人开始「闭眼点批准」，那一层就只剩下仪式感。三档把「问几次」交给用户自己定，
/// 但**档位越高，记的键越窄**：范围不糊，才轮得到「少问」而不等于「放行一切」。
public enum AgentApprovalTier: String, Codable, Equatable, Sendable, CaseIterable {

    /// **仅这一次**（默认）：不记任何东西 —— 下一次同样调用照样问。
    case once

    /// **本会话内允许**：只在当前会话内、同一「工具 + 作用域」不再询问；
    /// 会话结束（或换一个会话）即失效，**不落盘**到全局设置。
    case session

    /// **总是允许**：落盘到设置，跨重启生效。
    case always

    /// 这一档要不要留下一条可复用的授权（`once` 不留）。
    public var remembersGrant: Bool { self != .once }

    /// 落盘的档位（只有 `always` 进全局文件）。
    public var isPersistent: Bool { self == .always }
}

/// 一条授权的**作用域** = 工具名 + 规范化后的作用域值。
///
/// 契约（§3.36 ②）：键**不许只写工具名**。只写工具名，等于「允许写 a.txt」顺带允许写全盘 ——
/// 那一档比逐次审批更危险，因为人以为自己只批了一条。
///
/// 作用域值的取法按工具各自的**事实**来（不猜、不概括）：
/// · 文件写 / 改 = 规范化路径（`AgentWorkspaceTools` 那边出单时就已经算好）；
/// · 执行命令 = **首个词**（`python3` / `git` / `swift`）；
/// · 无路径类参数的调用（远端 MCP、SQL）= **参数原文的摘要**（同一条再批不用问，换一个字就重新问）。
public struct AgentApprovalScope: Equatable, Hashable, Sendable {

    /// 工具名（注册表里那一份，不自造）。
    public var tool: String
    /// 规范化后的作用域值（非空；空值时由调用方用参数指纹兜底）。
    public var value: String

    public init(tool: String, value: String) {
        self.tool = tool
        self.value = value
    }

    /// 记账键：`工具名|作用域`。**唯一** —— 比较、落盘、撤销都认这一个串。
    public var key: String { tool + "|" + value }

    // MARK: - 规范化

    /// 路径规范化：去掉首尾空白、折叠 `.` 与 `..`、去掉尾部 `/`。
    ///
    /// **不做字符串前缀匹配**：`/a/x.txt` 与 `/a/x.txt.bak` 是两份文件，
    /// 前者被允许不等于后者被允许（`AgentPermissionConfig.isInside` 的同一条纪律）。
    public static func normalizedPath(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        var path = (trimmed as NSString).standardizingPath
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    /// 命令的作用域 = **首个词**（小写）：`python3 -V` 与 `python3 hello.py` 同一档。
    /// 参数换了不再问 —— 这正是「少问」的边界；越出这一档（换成 `git`）仍要问。
    public static func commandWord(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).first ?? ""
        return String(first).lowercased()
    }

    /// 无路径类参数时的作用域：参数原文的摘要（等价于「原样调用过的那一次」）。
    public static func argumentDigest(_ raw: String) -> String {
        "fp:" + AgentFingerprint.hash(raw)
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(key) }
}

/// 一类动作的**危险面**（§3.36 ③）：档位不许把不可逆的事一起放行。
///
/// 只有 `ordinary` 能被记成「本会话内」或「总是允许」；其余四档**只保留「仅这一次」**，
/// 面板上那两档置灰并写明原因。判据（`Tests/AgentApprovalGrantTests`）把这一条钉成红/绿：
/// 即使盘上已经存在一条针对该作用域的全局授权（历史遗留 / 手改文件），判定也**不认**它。
public enum AgentApprovalHazard: String, Codable, Equatable, Sendable, CaseIterable {

    /// 普通读写：可记档。
    case ordinary
    /// 越界（工作区外，§3.26）：一次一单，永不记档。
    case outsideWorkspace
    /// 删除 / 覆盖 / 改写历史：不可逆，每次都要问。
    case destructive
    /// 对外发送（QQ / webhook / 邮件 …）：发出去就收不回。
    case outbound
    /// 口令 / 凭据：读到即泄。
    case credential

    /// 这一档能不能被「本会话内 / 总是允许」覆盖。
    public var allowsGrant: Bool { self == .ordinary }

    /// 严重度（合并时取大的那个）。
    var rank: Int {
        switch self {
        case .ordinary: return 0
        case .credential, .outbound: return 1
        case .destructive: return 2
        case .outsideWorkspace: return 3
        }
    }

    /// 两处判定取**更严**的那一个（工具名的网 + 参数里的网）。
    public static func stricter(_ lhs: AgentApprovalHazard, _ rhs: AgentApprovalHazard) -> AgentApprovalHazard {
        lhs.rank >= rhs.rank ? lhs : rhs
    }
}

/// 从**事实**判危险面（纯函数；判据直接打这几条）。
///
/// 三张网，任一张命中就升级：
/// 1. **命令首词 / git 子命令**：`rm` / `mv` / `dd` / `chmod` 这类，以及
///    `git reset` / `git clean` / `git checkout` / `git restore` / `git push`（都会丢东西或改远端）；
/// 2. **SQL 首个关键字**：`DELETE` / `DROP` / `TRUNCATE`（`UPDATE` / `INSERT` 不在此列 ——
///    它们可回滚、可重放，归普通档）；
/// 3. **工具名 / 参数里的对外与凭据字样**：发送、消息、webhook、QQ、邮件；口令、密钥、凭据。
///
/// 宁可多拦：命中只是「这一档不能记授权」，不是「直接拒」—— 用户照样可以一次一次地批。
public enum AgentApprovalHazardRules {

    /// 不改盘 / 不删东西的执行器之外，这些首词一律算不可逆。
    static let destructiveCommands: Set<String> = [
        "rm", "rmdir", "mv", "dd", "shred", "truncate", "chmod", "chown", "mkfs", "kill", "pkill",
    ]

    /// `git` 的子命令里会丢工作 / 改远端的那几个。
    static let destructiveGitSubcommands: Set<String> = [
        "reset", "clean", "checkout", "restore", "rm", "push", "stash", "rebase",
    ]

    /// 对外发送的窄口（工具名或参数里出现即算 —— 发出去收不回）。
    static let outboundWords: [String] = [
        "send", "message", "webhook", "qq", "mail", "email", "notify", "publish",
    ]

    /// 凭据类窄口。
    static let credentialWords: [String] = [
        "password", "passwd", "secret", "credential", "token", "apikey",
    ]

    /// 执行一条命令行 ⇒ 危险面。首词命中的是「不可逆」，`git` 再看第二个词。
    public static func command(_ line: String) -> AgentApprovalHazard {
        let words = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .map { String($0).lowercased() }
        guard let head = words.first else { return .ordinary }
        // 首词可能带路径（`/bin/rm`）：只看最后一个分量，别让前缀把它藏起来。
        let name = head.split(separator: "/").last.map(String.init) ?? head
        if destructiveCommands.contains(name) { return .destructive }
        if name == "git", words.count > 1, destructiveGitSubcommands.contains(words[1]) {
            return .destructive
        }
        return .ordinary
    }

    /// 一条 SQL ⇒ 危险面（首个关键字，跳过注释与前置空白）。
    public static func sql(_ text: String) -> AgentApprovalHazard {
        let keywords = AgentPermissionScope.leadingKeywords(in: text, limit: 2)
        guard let first = keywords.first else { return .ordinary }
        if ["DELETE", "DROP", "TRUNCATE"].contains(first) { return .destructive }
        // `ALTER ... DROP COLUMN` 也算删：第二个词是 DROP 就升级。
        if keywords.count > 1, keywords[1] == "DROP" { return .destructive }
        return .ordinary
    }

    /// 工具名 / 参数原文 ⇒ 对外与凭据那两张网（不改则归普通）。
    public static func text(_ raw: String) -> AgentApprovalHazard {
        let lowered = raw.lowercased()
        if credentialWords.contains(where: { lowered.contains($0) }) { return .credential }
        if outboundWords.contains(where: { lowered.contains($0) }) { return .outbound }
        return .ordinary
    }

    /// 合成：文本网 + 命令 / SQL 网取更严的那一个。
    public static func merged(_ lhs: AgentApprovalHazard, _ rhs: AgentApprovalHazard) -> AgentApprovalHazard {
        AgentApprovalHazard.stricter(lhs, rhs)
    }
}

/// 一条记下来的授权（可列出、可逐条撤销 —— §3.36 ④）。
public struct AgentApprovalGrant: Codable, Equatable, Sendable, Identifiable {

    /// 稳定 id = 作用域键 + 档位（同一条不会被记两遍）。
    public var id: String
    public var tool: String
    public var scope: String
    public var tier: AgentApprovalTier
    /// 会话级授权属于哪个会话；全局级为 `nil`。
    public var sessionID: String?
    public var grantedAt: Date

    public init(tool: String, scope: String, tier: AgentApprovalTier,
                sessionID: String? = nil, grantedAt: Date = Date()) {
        self.tool = tool
        self.scope = scope
        self.tier = tier
        self.sessionID = sessionID
        self.grantedAt = grantedAt
        self.id = [tool, scope, tier.rawValue, sessionID ?? ""].joined(separator: "|")
    }

    public var scopeKey: String { tool + "|" + scope }
}

/// 授权的**唯一一本账**：会话级在内存、全局级在盘上（`agent-approval-grants.json`）。
///
/// 三条纪律（判据逐条打它们）：
/// 1. **`once` 不记账** —— `remember` 直接返回 `nil`，下一次照样问；
/// 2. **会话级不落盘** —— 只在 `sessionID` 相同的那一段里有效，换会话 / 重开 App 即失效；
/// 3. **危险面不认账** —— `isGranted` 先看 `hazard.allowsGrant`，盘上有历史授权也不放行。
public struct AgentApprovalGrantStore: Sendable {

    public var directory: URL
    /// 全局级（落盘）。
    public private(set) var persistentGrants: [AgentApprovalGrant]
    /// 会话级（只在内存）。
    public private(set) var sessionGrants: [AgentApprovalGrant]
    /// 读盘失败的那一句（`nil` = 没出错）。
    public private(set) var lastError: String?

    public init(directory: URL = AgentApprovalGrantStore.defaultDirectory) {
        self.directory = directory
        self.persistentGrants = Self.load(from: directory.appendingPathComponent(Self.fileName))
        self.sessionGrants = []
    }

    static let fileName = "agent-approval-grants.json"

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent(DoyahIdentity.applicationSupportDirectoryName, isDirectory: true)
    }

    public var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    /// 两档一起列（设置里那一份清单：能看见，才能逐条撤）。
    public var grants: [AgentApprovalGrant] {
        (persistentGrants + sessionGrants).sorted { $0.grantedAt > $1.grantedAt }
    }

    // MARK: - 判

    /// 这一次调用还要不要问人。
    ///
    /// **顺序**：先看危险面（不可逆的一律要问），再看会话级（同一个会话才算），最后看全局级。
    public func isGranted(_ scope: AgentApprovalScope, hazard: AgentApprovalHazard, sessionID: String) -> Bool {
        guard hazard.allowsGrant else { return false }
        let key = scope.key
        if sessionGrants.contains(where: { $0.scopeKey == key && ($0.sessionID ?? "") == sessionID }) {
            return true
        }
        return persistentGrants.contains { $0.scopeKey == key }
    }

    // MARK: - 记

    /// 记一条授权。`once` / 危险面 ⇒ **什么都不记**并返回 `nil`（不是报错：用户点的那一档照样生效，
    /// 只是不留授权）。
    @discardableResult
    public mutating func remember(_ scope: AgentApprovalScope, tier: AgentApprovalTier,
                                  hazard: AgentApprovalHazard, sessionID: String,
                                  at: Date = Date()) throws -> AgentApprovalGrant? {
        guard tier.remembersGrant, hazard.allowsGrant, !scope.value.isEmpty else { return nil }
        let grant = AgentApprovalGrant(tool: scope.tool, scope: scope.value, tier: tier,
                                       sessionID: tier == .session ? sessionID : nil, grantedAt: at)
        switch tier {
        case .once:
            return nil
        case .session:
            sessionGrants.removeAll { $0.scopeKey == grant.scopeKey && ($0.sessionID ?? "") == sessionID }
            sessionGrants.append(grant)
        case .always:
            persistentGrants.removeAll { $0.scopeKey == grant.scopeKey }
            persistentGrants.append(grant)
            try persist()
        }
        return grant
    }

    // MARK: - 撤

    /// 逐条撤销（§3.36 ④）：撤掉之后**立刻**恢复询问。
    public mutating func revoke(id: String) throws {
        let before = persistentGrants.count
        persistentGrants.removeAll { $0.id == id }
        sessionGrants.removeAll { $0.id == id }
        if persistentGrants.count != before { try persist() }
    }

    /// 全部撤销（设置里那一枚「全部撤销」）。
    public mutating func revokeAll() throws {
        let hadPersistent = !persistentGrants.isEmpty
        persistentGrants.removeAll()
        sessionGrants.removeAll()
        if hadPersistent { try persist() }
    }

    /// 会话结束：会话级整批失效（**全局级不动**）。
    public mutating func endSession(sessionID: String? = nil) {
        guard let sessionID else { sessionGrants.removeAll(); return }
        sessionGrants.removeAll { ($0.sessionID ?? "") == sessionID }
    }

    // MARK: - 盘

    private func persist() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = AgentStoredDate.encoding
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(persistentGrants).write(to: fileURL, options: .atomic)
    }

    static func load(from url: URL) -> [AgentApprovalGrant] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = AgentStoredDate.decoding
        return (try? decoder.decode([AgentApprovalGrant].self, from: data)) ?? []
    }
}
