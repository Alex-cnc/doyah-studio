import Foundation

import DoyahCore

/// 便携凭据存储（macOS）：**文件后端**，不再走系统钥匙串。
///
/// 为什么换掉钥匙串（2026-10-30 主人原话：「这个 keychain 太烦人了，总是要输入」）：
/// 本 App 每次重建都会换一次临时签名，钥匙串的 ACL 认的是签名 ⇒ **每装一版就重新授权一遍**，
/// 「始终允许」也留不住。开发期一天装五版，就是五遍口令 —— 这不是安全，是噪声。
///
/// 替代口径（三条都不放松）：
/// 1. **Secret 不落配置文件**：`agent.json` / `im-channel-*.json` 里按字节仍然没有密钥；
///    密钥在这份独立文件里，权限 `0600`，目录 `0700`（同用户可读，其他用户与全局不可读）；
/// 2. **不进日志与审计**：对外仍然只有「已配置 / 长度 / 尾 4」；
/// 3. **可明确清除**：`delete*` 删键；整份文件可在 Finder 里直接删掉。
public struct FileAgentSecretStore: AgentKeyStore, AgentIMSecretStore {

    /// 与 `KeychainAgentKeyStore.defaultAccount` 对齐，便于一次性迁移。
    public static let webSearchSlot = "agent-web-search-tavily"
    public static let apiKeySlot = "agent.api-key"

    private let fileURL: URL
    private let directoryURL: URL
    /// 模型 Key 落在哪个条目里。**多档模型接入**（2026-11-08 进 beta1.1）靠它：
    /// 一档一个条目（`AgentProfile.defaultSecretKey(for:)` = `agent.api-key.<档 id>`），
    /// 换档不会互相覆盖；老配置那一档仍用 `agent.api-key`（迁移过的 key 照旧读得回来）。
    private let entryKey: String
    private let lock = NSLock()

    public init(directoryURL: URL? = nil, entryKey: String = FileAgentSecretStore.apiKeySlot) {
        let base = directoryURL ?? FileAgentSecretStore.defaultDirectory()
        self.directoryURL = base
        self.fileURL = base.appendingPathComponent("secrets.json")
        self.entryKey = entryKey
    }

    public static func defaultDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        // 目录名走 `DoyahIdentity`：rc 变体（`--variant rc`）必须有自己的 `secrets.json` ——
        // 与 `agent.json` / `connections.json` 同一条口径（两份进程各写各的，不抢同一个文件）。
        return support.appendingPathComponent(DoyahIdentity.applicationSupportDirectoryName, isDirectory: true)
    }

    // MARK: - 一次性迁移（从钥匙串搬过来，之后永不读钥匙串）

    /// 老版本把密钥存在钥匙串里。这里**只搬一次**：搬完写标记文件，之后启动不再碰钥匙串。
    /// 搬不动（主人拒了授权 / 钥匙串里本来没有）也写标记 —— 宁可让人重扫一次，
    /// 也不要每次启动都弹一次口令。
    public static func migrateFromKeychainOnce() {
        let store = FileAgentSecretStore()
        let marker = store.directoryURL.appendingPathComponent("secrets.migrated")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }

        let keyStore = KeychainAgentKeyStore()
        if store.load()[apiKeySlot] == nil, let legacy = try? keyStore.apiKey(), !legacy.isEmpty {
            try? store.setAPIKey(legacy)
        }
        let imStore = KeychainAgentIMSecretStore()
        for kind in AgentIMChannelCredentialKind.allCases where store.load()[kind.secretAccount] == nil {
            if let legacy = try? imStore.secret(for: kind), !legacy.isEmpty {
                try? store.setSecret(legacy, for: kind)
            }
        }
        try? FileManager.default.createDirectory(at: store.directoryURL, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? Data("legacy-keychain-migrated".utf8).write(to: marker)
    }

    // MARK: - AgentKeyStore

    public func setAPIKey(_ key: String) throws { try write(slot: entryKey, value: key) }
    public func apiKey() throws -> String? { try read(slot: entryKey) }
    public func deleteAPIKey() throws { try remove(slot: entryKey) }

    // **联网检索的 Tavily key**（`FR-AGT-TOOL-INGEST-004`）：与模型 key 分槽位 ——
    // 「换模型服务」不该顺手把搜索后端也换掉。0600 文件，不进日志、不进审计、不回显。
    public func setWebSearchKey(_ key: String) throws { try write(slot: Self.webSearchSlot, value: key) }
    public func webSearchKey() throws -> String? { try read(slot: Self.webSearchSlot) }
    public func deleteWebSearchKey() throws { try remove(slot: Self.webSearchSlot) }

    // MARK: - AgentIMSecretStore

    public func setSecret(_ secret: String, for kind: AgentIMChannelCredentialKind) throws {
        try write(slot: kind.secretAccount, value: secret)
    }

    public func secret(for kind: AgentIMChannelCredentialKind) throws -> String? {
        try read(slot: kind.secretAccount)
    }

    public func deleteSecret(for kind: AgentIMChannelCredentialKind) throws {
        try remove(slot: kind.secretAccount)
    }

    // MARK: - 文件读写（0600 / 目录 0700 / 原子写）

    private func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let table = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return table
    }

    private func persist(_ table: [String: String]) throws {
        let manager = FileManager.default
        if !manager.fileExists(atPath: directoryURL.path) {
            try manager.createDirectory(at: directoryURL, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        }
        // 目录权限每次都对齐 0700（有些环境里目录是先被别的代码建出来的，默认 0755）
        try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
        let data = try JSONEncoder().encode(table)
        // 先写临时文件、再换名：半截文件不会留下「读得到但解不开」的状态。
        let temporary = fileURL.appendingPathExtension("tmp")
        try data.write(to: temporary, options: [.atomic])
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        if manager.fileExists(atPath: fileURL.path) { try manager.removeItem(at: fileURL) }
        try manager.moveItem(at: temporary, to: fileURL)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func write(slot: String, value: String) throws {
        lock.lock(); defer { lock.unlock() }
        var table = load()
        table[slot] = value
        try persist(table)
    }

    private func read(slot: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return load()[slot]
    }

    private func remove(slot: String) throws {
        lock.lock(); defer { lock.unlock() }
        var table = load()
        table.removeValue(forKey: slot)
        try persist(table)
    }
}
