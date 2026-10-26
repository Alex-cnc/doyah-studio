import Foundation

/// 会话生命周期的**界面侧唯一入口**（`FR-AGT-UX-SESS-001` 的接线面）。
///
/// 三件能力本体已经在 `AgentSessionLifecycle` 里（归档 / 恢复 / 真删 / 导出 / 重新导入），
/// 这一层不是重复实现，而是把三件**容易做错的事**从调用点收走：
///
/// ① **续跑旁挂件目录不许漏**：`delete` 的 `sidecarDirectories` 是可选参数，漏传的后果是
///    「会话删了、磁盘上还留着它的续跑件」—— 而这件事在界面上看不出来（列表确实空了）。
///    本层把旁挂目录钉在**构造处**，调用方没有机会忘。
/// ② **一次动作 = 一条可读结论**：界面只渲染 `AgentSessionLifecycleOutcome`，不再各自把
///    `Bool` / `Int` / `throw` 拼成人话（三处出口各说一套就是漂移的来源）。
/// ③ **工作区在构造处固定**：「别人的会话不许动」与本层同一个事实源，界面拿不到
///    「换个 workspace 再试一次」的口子。
///
/// 判据（`Tests/AgentSessionLifecycleDeskTests`）：正常路径 ①归档→恢复往返 ②真删连旁挂件
/// ③导出→导入回来；该拒路径 ④别人的工作区 ⑤同名会话号默认拒收；边界 ⑥幂等动作 `changed=false`
/// ⑦坏载荷不落半个文件。
public enum AgentSessionLifecycleAction: String, Equatable, Sendable {
    case archive
    case restore
    case delete
    /// 只产出数据（落盘由界面用保存面板做，本层不写别处目录）。
    case export
    case importSession

    /// 机器码（ASCII）：界面 / 日志 / 判据共用，展示层再翻人话。
    public var code: String {
        switch self {
        case .archive: return "archive"
        case .restore: return "restore"
        case .delete: return "delete"
        case .export: return "export"
        case .importSession: return "import"
        }
    }
}

public struct AgentSessionLifecycleOutcome: Equatable, Sendable {
    public var action: AgentSessionLifecycleAction
    public var sessionID: String
    /// 真的动了盘。幂等的那一下（归档一条已归档的 / 恢复一条已在活跃面的）为 `false` ——
    /// 界面据此说「本来就在归档里」而不是假装刚做完。
    public var changed: Bool
    /// `delete` 删掉的文件数（其余动作恒 0）。**读它才知道有没有漏删旁挂件**。
    public var removedFileCount: Int
    /// `export` 的字节数（其余动作恒 0）。
    public var byteCount: Int

    public init(action: AgentSessionLifecycleAction,
                sessionID: String,
                changed: Bool,
                removedFileCount: Int = 0,
                byteCount: Int = 0) {
        self.action = action
        self.sessionID = sessionID
        self.changed = changed
        self.removedFileCount = removedFileCount
        self.byteCount = byteCount
    }
}

/// 导入回来的那条会话（头 + 字节读数），界面拿它去刷新列表并切过去。
public struct AgentSessionImportReceipt: Equatable, Sendable {
    public var header: AgentSessionHeader
    public var outcome: AgentSessionLifecycleOutcome

    public init(header: AgentSessionHeader, outcome: AgentSessionLifecycleOutcome) {
        self.header = header
        self.outcome = outcome
    }
}

public struct AgentSessionLifecycleDesk: Sendable {
    public let store: AgentSessionStore
    public let workspace: String
    /// 续跑旁挂件目录（`AgentTurnResumeStore.directory`）—— **构造时必给**（见类型注释 ①）。
    public let sidecarDirectories: [URL]

    public init(store: AgentSessionStore, workspace: String, sidecarDirectories: [URL]) {
        self.store = store
        self.workspace = workspace
        self.sidecarDirectories = sidecarDirectories
    }

    // MARK: - 归档 / 恢复

    @discardableResult
    public func archive(sessionID: String) throws -> AgentSessionLifecycleOutcome {
        let changed = try store.archive(sessionID: sessionID, workspace: workspace)
        return AgentSessionLifecycleOutcome(action: .archive, sessionID: sessionID, changed: changed)
    }

    @discardableResult
    public func restore(sessionID: String) throws -> AgentSessionLifecycleOutcome {
        let changed = try store.restore(sessionID: sessionID, workspace: workspace)
        return AgentSessionLifecycleOutcome(action: .restore, sessionID: sessionID, changed: changed)
    }

    /// 归档面里这个工作区的会话（带上跳数与时间 —— 与活跃面同一套展示字段）。
    ///
    /// 为什么不复用 `store.summaryList`：它只扫活跃目录。归档面没走摘要那条路，
    /// 这里按同一口径补一份（坏文件跳过并计数，不静默吞）。
    public func archivedSummaries() -> AgentSessionSummaryResult {
        let listed = store.archivedSessions(workspace: workspace)
        var summaries: [AgentSessionSummary] = []
        for header in listed.headers {
            let url = store.archivedFileURL(sessionID: header.id)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            // 逐行解码：头一行是 `AgentSessionHeader`，其余是跳。**解不出来的行不算跳**
            // （与 `load` 的 `skippedLines` 同一口径 —— 坏行不该把跳数抬高）。
            var turns: [AgentSessionTurn] = []
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
                guard let data = line.data(using: .utf8) else { continue }
                if index == 0 { continue }
                if let turn = try? AgentSessionStore.decoder.decode(AgentSessionTurn.self, from: data) {
                    turns.append(turn)
                }
            }
            summaries.append(AgentSessionSummary(id: header.id, title: header.title, workspace: header.workspace,
                                                 createdAt: header.createdAt, turnCount: turns.count,
                                                 lastTurnAt: turns.last?.at))
        }
        // 排序与活跃面**同一口径**（最近活动在前）：两个列表并排看时才不会一个按创建、一个按活动。
        summaries.sort { left, right in
            if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
            return left.id < right.id
        }
        return AgentSessionSummaryResult(summaries: summaries, skippedFiles: listed.skippedFiles)
    }

    // MARK: - 删除（真删）

    /// 真删：活跃文件 + 归档副本 + **续跑旁挂件**。返回的 `removedFileCount` 就是删掉几个。
    @discardableResult
    public func delete(sessionID: String) throws -> AgentSessionLifecycleOutcome {
        let removed = try store.delete(sessionID: sessionID, workspace: workspace,
                                       sidecarDirectories: sidecarDirectories)
        return AgentSessionLifecycleOutcome(action: .delete, sessionID: sessionID,
                                            changed: removed > 0, removedFileCount: removed)
    }

    // MARK: - 导出 / 导入

    /// 导出成数据（**不**在这里写用户选的那个目录：落盘位置归界面的保存面板）。
    public func export(sessionID: String) throws -> (outcome: AgentSessionLifecycleOutcome, data: Data) {
        let loaded = store.load(sessionID: sessionID, workspace: workspace)
        if loaded.workspaceMismatch { throw AgentSessionLifecycleError.workspaceMismatch }
        guard let session = loaded.session else { throw AgentSessionLifecycleError.sessionNotFound }
        let data = try store.export(session)
        return (AgentSessionLifecycleOutcome(action: .export, sessionID: sessionID,
                                             changed: false, byteCount: data.count), data)
    }

    /// 重新导入：落到**本层固定的工作区**；同名按 `conflict` 处置（默认拒收）。
    @discardableResult
    public func importSession(_ data: Data,
                              conflict: AgentSessionIDConflictPolicy = .reject,
                              sessionID: String? = nil) throws -> AgentSessionImportReceipt {
        let header = try store.importSession(from: data, workspace: workspace,
                                            conflict: conflict, sessionID: sessionID)
        return AgentSessionImportReceipt(
            header: header,
            outcome: AgentSessionLifecycleOutcome(action: .importSession, sessionID: header.id,
                                                  changed: true, byteCount: data.count)
        )
    }
}
