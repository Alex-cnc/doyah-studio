import Foundation

/// 运行策略的可配置面（`FR-AGT-OPS-OBS-002`）：**草稿 → 差异 → 原子落盘 → 立即生效**。
///
/// 三件东西分工：
/// · `AgentRuntimeConfigDraft` —— 界面那一格一格填的**文本**（不校验、不清洗，什么都不改）；
/// · `edits(against:)` —— 草稿与当前快照的**差异**（没变的不进名单，变了的一条一条列出来）；
/// · `AgentConfigStore.applyBatch` —— **一次全落或一条都不落**（第三条验收要点「非法配置拒绝保存」
///   在批量里最难保证：逐条 apply 时前两条已经落进去了，界面再报「保存失败」就变成了半套生效）。
///
/// 判据在 `Tests/AgentRuntimeConfigTests`：差异口径（没变⇒空 / 改了⇒一条）、
/// 批量原子性（中途非法⇒快照与留痕都不动）、文件往返（存了什么读回什么）、
/// 坏文件与手改非法值**如实降级**（不静默采信）。
public struct AgentConfigEdit: Equatable, Sendable {
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// 界面上的那一份草稿。**全用文本**：非法输入要能被送去校验并拿到理由，
/// 而不是在界面层被 `Int(...) ?? 0` 悄悄夹成合法值。
public struct AgentRuntimeConfigDraft: Equatable, Sendable {
    public var maxConcurrentSubtasks: String
    public var commandTimeoutSeconds: String
    public var dailyTokenQuota: String
    public var notificationsEnabled: Bool
    /// 逗号分隔的工具名（空串 = 不限制）。
    public var toolWhitelist: String
    /// 审批策略基线（文本：`allow` / `ask` / `deny`；词表见 `AgentPolicyLevel.configTokens`）。
    public var approvalPolicy: String

    public init(maxConcurrentSubtasks: String,
                commandTimeoutSeconds: String,
                dailyTokenQuota: String,
                notificationsEnabled: Bool,
                toolWhitelist: String,
                approvalPolicy: String = AgentPolicyLevel.allow.configToken) {
        self.maxConcurrentSubtasks = maxConcurrentSubtasks
        self.commandTimeoutSeconds = commandTimeoutSeconds
        self.dailyTokenQuota = dailyTokenQuota
        self.notificationsEnabled = notificationsEnabled
        self.toolWhitelist = toolWhitelist
        self.approvalPolicy = approvalPolicy
    }

    /// 从盘上那份快照回填（重开面板不许显示空白 —— 空白保存一次就等于把用户的设置清掉）。
    public init(snapshot: AgentConfigSnapshot) {
        self.init(maxConcurrentSubtasks: String(snapshot.maxConcurrentSubtasks),
                  commandTimeoutSeconds: String(snapshot.commandTimeoutSeconds),
                  dailyTokenQuota: String(snapshot.dailyTokenQuota),
                  notificationsEnabled: snapshot.notificationsEnabled,
                  toolWhitelist: snapshot.toolWhitelist.joined(separator: ","),
                  approvalPolicy: snapshot.approvalPolicy.configToken)
    }

    /// 与当前快照的差异。**一条都没变 ⇒ 空数组**（界面据此把「保存」灰着，不留空留痕）。
    ///
    /// 两条口径：
    /// ① 数字项按**数值**比（`" 60 "` 与 `60` 是同一件事，不该算改动）；
    /// ② 数字项**解不出来就是改动**（送给 `AgentConfigStore` 去拒收并给理由）——
    ///    在界面层把非法输入静默丢弃，用户会以为「保存成功了」。
    public func edits(against snapshot: AgentConfigSnapshot) -> [AgentConfigEdit] {
        var edits: [AgentConfigEdit] = []
        if isChangedInt(maxConcurrentSubtasks, current: snapshot.maxConcurrentSubtasks) {
            edits.append(.init(key: "maxConcurrentSubtasks", value: maxConcurrentSubtasks.trimmingCharacters(in: .whitespaces)))
        }
        if isChangedInt(commandTimeoutSeconds, current: snapshot.commandTimeoutSeconds) {
            edits.append(.init(key: "commandTimeoutSeconds", value: commandTimeoutSeconds.trimmingCharacters(in: .whitespaces)))
        }
        if isChangedInt(dailyTokenQuota, current: snapshot.dailyTokenQuota) {
            edits.append(.init(key: "dailyTokenQuota", value: dailyTokenQuota.trimmingCharacters(in: .whitespaces)))
        }
        if notificationsEnabled != snapshot.notificationsEnabled {
            edits.append(.init(key: "notificationsEnabled", value: notificationsEnabled ? "true" : "false"))
        }
        let normalized = Self.toolNames(toolWhitelist)
        if normalized != snapshot.toolWhitelist {
            edits.append(.init(key: "toolWhitelist", value: normalized.joined(separator: ",")))
        }
        // 审批策略：按**档位**比（`ASK` / ` ask ` 与 `ask` 是同一件事）；认不出的照样算改动，
        // 交给 store 拒收并说清允许哪三档 —— 在界面层静默吞掉会让用户以为「已经改成只读模式了」。
        let policyToken = approvalPolicy.trimmingCharacters(in: .whitespaces).lowercased()
        if AgentPolicyLevel(configToken: policyToken) != snapshot.approvalPolicy {
            edits.append(.init(key: "approvalPolicy", value: policyToken))
        }
        return edits
    }

    /// 白名单文本 → 名字数组（去空白、去空项、**保序**）。
    ///
    /// 保序是很实际的一条：用户在面板里排的顺序就是他心里的优先级，重排会让人以为设错了。
    public static func toolNames(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func isChangedInt(_ text: String, current: Int) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }                    // 清空 ≠ 保持：交给 store 拒收并说清允许范围
        guard let value = Int(trimmed) else { return true }    // 非法 ⇒ 也算改动，让 store 给理由
        return value != current
    }
}

public extension AgentConfigStore {

    /// 一批改动一次性落：**任一失败 ⇒ 整体回退**（快照与留痕都不动）。
    ///
    /// 为什么不做成逐条 apply 后继续：界面上一次「保存」就是一次承诺，
    /// 三条里落了两条、第三条报错，用户看到的是「保存失败」而他的一半设置已经生效了。
    @discardableResult
    mutating func applyBatch(_ edits: [AgentConfigEdit], reason: String, at: Date = Date()) throws -> [AgentConfigChange] {
        guard !edits.isEmpty else { return [] }
        var staged = self
        var applied: [AgentConfigChange] = []
        for edit in edits {
            let before = staged.changes.count
            try staged.apply(key: edit.key, value: edit.value, reason: reason, at: at)
            applied.append(contentsOf: staged.changes[before...])
        }
        self = staged
        return applied
    }
}

/// 盘上那份运行策略（`agent-runtime-config.json`）。
///
/// 三条口径：
/// ① **存了什么读回什么**（快照 + 全部留痕，逐字段往返）；
/// ② **没有文件 = 全新安装**（用默认值，`state = .fresh`，不是「坏了」）；
/// ③ **文件坏了 / 手改塞了非法值 ⇒ 如实降级**（用默认值 + 机器码原因，界面照实说一句），
///    绝不静默采信 —— 配额被手改成 0 还照着跑，比报一句「配置读不出来」危险得多。
public struct AgentRuntimeConfigFile: Sendable {
    public enum LoadState: Equatable, Sendable {
        /// 盘上还没有这份配置（全新安装）。
        case fresh
        /// 读到了并且每一项都过了校验。
        case loaded
        /// 读到了但用不了（`reason` 是 ASCII 机器码，展示层再翻人话）。
        case degraded(reason: String)
    }

    public struct LoadResult: Sendable {
        public var store: AgentConfigStore
        public var state: LoadState
        public var fileURL: URL

        public init(store: AgentConfigStore, state: LoadState, fileURL: URL) {
            self.store = store
            self.state = state
            self.fileURL = fileURL
        }
    }

    /// 盘上形状（内层键 = 快照字段名；`changes` = 留痕，只追加）。
    private struct Payload: Codable, Equatable {
        struct Snapshot: Codable, Equatable {
            var model: String
            var maxConcurrentSubtasks: Int
            var commandTimeoutSeconds: Int
            var dailyTokenQuota: Int
            var notificationsEnabled: Bool
            var toolWhitelist: [String]
            /// **可选**：这一项是后加的，旧文件里没有它 ⇒ 按默认 `allow` 走（不判降级）。
            /// 写成必填会让所有旧配置在升级那一次变成 `parseFailed`，用户看到的是「设置全丢了」。
            var approvalPolicy: String?
        }

        struct Change: Codable, Equatable {
            var key: String
            var oldValue: String?
            var newValue: String
            var reason: String
            var at: Date
        }

        var snapshot: Snapshot
        var changes: [Change]
    }

    public let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("agent-runtime-config.json")
    }

    public func load() -> LoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return LoadResult(store: AgentConfigStore(), state: .fresh, fileURL: fileURL)
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            return LoadResult(store: AgentConfigStore(), state: .degraded(reason: "unreadable"), fileURL: fileURL)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(Payload.self, from: data) else {
            return LoadResult(store: AgentConfigStore(), state: .degraded(reason: "parseFailed"), fileURL: fileURL)
        }

        // **逐项过一遍 store 自己的校验**（同一处真相：范围与词表不在这里重写）。
        // 任何一项非法 ⇒ 整份降级到默认值，并把是哪一项、允许什么写进原因码。
        var store = AgentConfigStore()
        var pairs: [(String, String)] = [
            ("model", payload.snapshot.model),
            ("maxConcurrentSubtasks", String(payload.snapshot.maxConcurrentSubtasks)),
            ("commandTimeoutSeconds", String(payload.snapshot.commandTimeoutSeconds)),
            ("dailyTokenQuota", String(payload.snapshot.dailyTokenQuota)),
            ("notificationsEnabled", payload.snapshot.notificationsEnabled ? "true" : "false"),
            ("toolWhitelist", payload.snapshot.toolWhitelist.joined(separator: ",")),
        ]
        // 旧文件没有这一项：**不给 pair**（默认值已经在 `AgentConfigStore()` 里），也不算降级。
        if let policy = payload.snapshot.approvalPolicy {
            pairs.append(("approvalPolicy", policy))
        }
        do {
            for (key, value) in pairs {
                try store.apply(key: key, value: value, reason: Self.loadReason, at: Date(timeIntervalSince1970: 0))
            }
        } catch let error as AgentConfigError {
            return LoadResult(store: AgentConfigStore(),
                              state: .degraded(reason: Self.reasonCode(error)),
                              fileURL: fileURL)
        } catch {
            return LoadResult(store: AgentConfigStore(), state: .degraded(reason: "invalidStoredValue"), fileURL: fileURL)
        }

        // 留痕照原样接上（它是历史，不是状态；读不出来就是空 —— 不影响快照可用）。
        // **整份替换**：校验那六条是脚手架，混进留痕就是假审计。
        var history: [AgentConfigChange] = []
        for change in payload.changes {
            history.append(AgentConfigChange(key: change.key, oldValue: change.oldValue,
                                             newValue: change.newValue, reason: change.reason, at: change.at))
        }
        store.replaceHistory(with: history)
        return LoadResult(store: store, state: .loaded, fileURL: fileURL)
    }

    public func save(_ store: AgentConfigStore) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                               withIntermediateDirectories: true)
        let snapshot = store.snapshot
        let payload = Payload(
            snapshot: .init(model: snapshot.model,
                            maxConcurrentSubtasks: snapshot.maxConcurrentSubtasks,
                            commandTimeoutSeconds: snapshot.commandTimeoutSeconds,
                            dailyTokenQuota: snapshot.dailyTokenQuota,
                            notificationsEnabled: snapshot.notificationsEnabled,
                            toolWhitelist: snapshot.toolWhitelist,
                            approvalPolicy: snapshot.approvalPolicy.configToken),
            changes: store.changes.map {
                .init(key: $0.key, oldValue: $0.oldValue, newValue: $0.newValue, reason: $0.reason, at: $0.at)
            }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(payload).write(to: fileURL, options: .atomic)
    }

    /// 载入校验那几条留痕的理由（ASCII：它是审计字段，展示层不翻译）。
    static let loadReason = "load-validation"

    static func reasonCode(_ error: AgentConfigError) -> String {
        switch error {
        case let .unknownKey(key): return "unknownKey:\(key)"
        case let .outOfRange(key, value, allowed): return "outOfRange:\(key)=\(value) allowed \(allowed)"
        case .missingReason: return "missingReason"
        }
    }
}

public extension AgentConfigStore {
    /// 盘上那份留痕接回来（只在载入路径用；它不是「新改动」，所以不经 `apply`）。
    /// 实现落在 `AgentConfigStore.swift`（`changes` 的 setter 是文件私有的）。
}

public extension AgentToolRegistry {

    /// **工具白名单生效面**（`FR-AGT-OPS-OBS-002` 的「改完立即生效」之一）。
    ///
    /// · 空名单 = 不限制（返回自己，一个都不隐藏）；
    /// · 有名单 ⇒ 名单外的注册项 `enabled = false`（与「按 profile 决定可见性」同一套开关，
    ///   不另造一条过滤路径 —— 否则循环里会出现「注册表说可见、分发器说不可用」两套答案）；
    /// · 名单里**没注册过的名字**如实回在 `unknown` 里（用户写错一个工具名要看得见，
    ///   静默忽略会让面板上那句「已限制为 3 个工具」变成谎话）。
    func applyingWhitelist(_ names: [String]) -> (registry: AgentToolRegistry, hidden: [String], unknown: [String]) {
        let wanted = Set(names.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        guard !wanted.isEmpty else { return (self, [], []) }
        var hidden: [String] = []
        var applied: [AgentToolDefinition] = []
        for definition in definitions {
            if wanted.contains(definition.name) {
                applied.append(definition)
            } else {
                if definition.enabled { hidden.append(definition.name) }
                var copy = definition
                copy.enabled = false
                applied.append(copy)
            }
        }
        let registered = Set(definitions.map(\.name))
        let unknown = wanted.filter { !registered.contains($0) }.sorted()
        return (AgentToolRegistry(definitions: applied), hidden.sorted(), unknown)
    }
}
