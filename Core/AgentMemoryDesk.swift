import Foundation

/// 「记住这个」这句话的解析（`FR-AGT-KNOW-MEM-003` 的**写入入口**）。
///
/// 为什么要把「人说不说这句话」做成一个可单测的纯函数：写入这条链路过去**除测试零调用点**
/// （台账 2026-10-28 降级的原话），补的第一个真调用点就是「对话里他说了记住」。
/// 于是「什么算他说了」必须是一处说得清的判定，而不是散在界面里的 `contains("记住")`。
///
/// 判据（每条都配负例，见 `Tests/AgentMemoryDeskTests`）：
/// ① 从句首触发词起算（`帮我记住` / `请记住` / `记住这个` / `记住一下` / `记住`，长词优先）；
/// ② 触发词后允许一个冒号 / 逗号 / 顿号，正文是剩下的那一段；
/// ③ 剩下不到两个字 ⇒ 不当作指令（「记住」两个字本身没有可记的内容）；
/// ④ **问句不算指令**（「记住这个字段叫什么？」是在问，不是在让我记）—— 以 `？` / `?` 收尾一律不认；
/// ⑤ 只认句首：句中出现「记住」不算（「我记得这个字段」里的「记得」也不是触发词）。
public enum AgentMemoryInstruction {

    /// 触发词，**长的在前**（`记住这个` 必须先于 `记住` 命中，否则正文会多出「这个」两个字）。
    public static let triggers = ["帮我记住", "请记住", "记住这个", "记住一下", "记住"]

    /// 触发词与正文之间允许出现的分隔符（中英文都收）。
    private static let separators: Set<Character> = ["：", ":", "，", ",", "、", "—", " ", "\t"]

    /// 解析一句用户原话。`nil` = 这句话不是在让我记东西。
    ///
    /// - Parameters:
    ///   - workspace: 归属工作区（隔离的第一层，由调用方给 —— 本函数不猜）。
    ///   - connection: 归属连接（隔离的第二层；没有连接的对话传空串，与 `AgentMemoryDraft` 的既有口径一致）。
    public static func draft(from prompt: String,
                             workspace: String,
                             connection: String,
                             kind: MemoryKind = .pinned) -> AgentMemoryDraft? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let trigger = triggers.first(where: { trimmed.hasPrefix($0) }) else { return nil }

        var rest = String(trimmed.dropFirst(trigger.count))
        // 只剥一个分隔符（「记住：：X」这种手滑保留一个冒号，正文会原样落库 —— 不替人改字）。
        if let first = rest.first, separators.contains(first) {
            rest.removeFirst()
        }
        rest = rest.trimmingCharacters(in: .whitespacesAndNewlines)

        // ③ 没有可记的内容；④ 问句不是指令。
        guard rest.count >= 2 else { return nil }
        guard !rest.hasSuffix("？"), !rest.hasSuffix("?") else { return nil }

        return AgentMemoryDraft(workspace: workspace,
                                connection: connection,
                                kind: kind,
                                note: rest)
    }
}

// MARK: - 面板 / 操作结论

/// 一次读盘后的**完整投影**（面板只读这一份，不自己再读第二遍盘）。
public struct AgentMemorySnapshot: Equatable, Sendable {

    public var workspace: String
    /// 当前筛的连接（`nil` = 这个工作区全部连接）。
    public var connection: String?
    public var entries: [AgentMemoryEntry]
    /// 逐条理由（id → `MemoryExplanation.describe` 的四行原文；`FR-AI-15` 的口径，本层不改写）。
    public var reasonLines: [String: [String]]
    /// 按 `FR-AI-15` 仍该记着的那些 id（这些才会进上下文）。
    public var retainedIDs: Set<String>

    public var skippedLines: Int
    public var unknownEntries: Int
    public var foreignEntries: Int
    public var skippedFiles: Int
    public var missingHeader: Bool
    public var workspaceMismatch: Bool

    /// 派生索引在不在盘上。
    public var indexExists: Bool
    /// 索引里有几条（读不出来 = `nil`）。
    public var indexEntryCount: Int?
    /// 索引与事实源**不一致**（条数或 id 集合对不上 ⇒ 该重建）。
    public var indexIsStale: Bool

    public var entryCount: Int { entries.count }

    /// 这一层现在**能读**吗（坏文件 / 头找不着 / 归属不符都算不能读 —— 面板要如实说，不装作空）。
    public var isReadable: Bool { !missingHeader && !workspaceMismatch && skippedFiles == 0 }

    /// 有没有「读不进来」的读数（与 `AgentMemoryLoadResult.hasSkippedReadings` 同一套口径）。
    public var hasSkippedReadings: Bool {
        skippedLines > 0 || unknownEntries > 0 || foreignEntries > 0 || skippedFiles > 0
            || missingHeader || workspaceMismatch
    }
}

/// 一次写 / 删 / 重建的结论（**机器形态**：人话由带语言的视图给，本层不带语言上下文）。
public enum AgentMemoryNotice: Equatable, Sendable {

    /// 记下了（`merged` = 同一条合并 +1；`useCount` = 这一条现在累计几次；
    /// `evicted` = 因上限被挤掉的条数）。
    case remembered(merged: Bool, useCount: Int, truncatedCharacters: Int, evicted: Int)
    /// 拒收（空正文 / 结果集行 / 密钥片段）—— 一条都没落盘，理由逐类报。
    case refused([AgentMemoryIntake.Rejection], truncatedCharacters: Int)
    /// 模型自发的写入：转候选等人确认，**没落库**。
    case needsConfirmation
    /// 删掉了；`indexRebuilt` 说明派生索引有没有跟着对齐。
    case deleted(indexRebuilt: Bool)
    /// 这条不在（可能已经被删过）。
    case notFound
    /// 清空了多少条。
    case cleared(Int, indexRebuilt: Bool)
    /// 索引重建后的条数。
    case indexRebuilt(Int)
    /// 写盘 / 重建失败（盘上没变，或索引没对齐）—— 如实说，不假装成功。
    case failed
}

// MARK: - 工作面

/// 记忆的**工作面**：把「事实源 + 派生索引 + 六个验收要点」收在一处，
/// 让界面与判据读同一个东西（`AppState` 只做转接，不自己拼读法）。
///
/// 与 `AgentMemoryStore` 的分工：Store 只管读写盘（它已经是完整的实现），
/// 本类型只加三件现有 Store 故意不做的编排 ——
/// ① **每次改完都对派生索引**（`②` 要求「删掉后重建索引也不再出现」；
///    让索引长期停在旧状态就是把这条判据交给运气）；
/// ② **一句原话 → 一条记忆**（`AgentMemoryInstruction` + 过闸 + 落盘）；
/// ③ **面板要的那一份投影**（条目 / 理由 / 保留判定 / 索引态 / 跳过读数）。
public struct AgentMemoryDesk: Sendable {

    public var store: AgentMemoryStore
    public var workspace: String
    public var connection: String?

    public init(store: AgentMemoryStore = AgentMemoryStore(directory: AgentMemoryStore.defaultDirectory),
                workspace: String,
                connection: String? = nil) {
        self.store = store
        self.workspace = workspace
        self.connection = connection
    }

    // MARK: 读

    public func snapshot(now: Date = Date(), calendar: Calendar = .current) -> AgentMemorySnapshot {
        let loaded = store.entries(workspace: workspace, connection: connection, calendar: calendar)
        let inspection = store.inspect(workspace: workspace, connection: connection, now: now, calendar: calendar)

        var reasons: [String: [String]] = [:]
        var retained: Set<String> = []
        for explanation in inspection.explanations {
            reasons[explanation.id] = explanation.lines
            if explanation.isRetained { retained.insert(explanation.id) }
        }

        let index = store.loadIndex(workspace: workspace)
        let indexIDs = index?.ids ?? []
        let stale = index != nil && indexIDs != loaded.entries.map(\.id)

        return AgentMemorySnapshot(workspace: workspace,
                                   connection: connection,
                                   entries: loaded.entries,
                                   reasonLines: reasons,
                                   retainedIDs: retained,
                                   skippedLines: loaded.skippedLines,
                                   unknownEntries: loaded.unknownEntries,
                                   foreignEntries: loaded.foreignEntries,
                                   skippedFiles: loaded.skippedFiles,
                                   missingHeader: loaded.missingHeader,
                                   workspaceMismatch: loaded.workspaceMismatch,
                                   indexExists: index != nil,
                                   indexEntryCount: index?.entryCount,
                                   indexIsStale: stale)
    }

    // MARK: 写

    /// 一句原话里有没有「记住…」。`nil` = 这句话不是在让我记东西（**不改盘的读数**）。
    public func rememberFromPrompt(_ prompt: String,
                                   round: Int? = nil,
                                   at date: Date = Date()) -> AgentMemoryNotice? {
        guard let draft = AgentMemoryInstruction.draft(from: prompt,
                                                       workspace: workspace,
                                                       connection: connection ?? "") else { return nil }
        return remember(draft, round: round, at: date)
    }

    /// 落一条（触发方式固定 `.userInstruction`：这条路只在「他说了记住」时被调用）。
    /// 写完**立刻重建索引** —— 面板的索引读数与下一次读都对齐，不留「索引慢一拍」。
    public func remember(_ draft: AgentMemoryDraft,
                         trigger: AgentMemoryTrigger = .userInstruction,
                         round: Int? = nil,
                         limits: AgentMemoryLimits = .standard,
                         at date: Date = Date()) -> AgentMemoryNotice {
        let result: AgentMemoryWriteResult
        do {
            result = try store.record(draft, trigger: trigger, round: round, limits: limits, at: date)
        } catch {
            return .failed
        }
        guard result.accepted else {
            if result.rejections.contains(.needsUserConfirmation) { return .needsConfirmation }
            return .refused(result.rejections, truncatedCharacters: result.truncatedCharacters)
        }
        _ = rebuildIndexQuietly()
        return .remembered(merged: result.merged,
                           useCount: result.entry?.useCount ?? 0,
                           truncatedCharacters: result.truncatedCharacters,
                           evicted: result.evictedIDs.count)
    }

    // MARK: 删

    public func delete(id: String) -> AgentMemoryNotice {
        let removed: Bool
        do {
            removed = try store.remove(id: id, workspace: workspace)
        } catch {
            return .failed
        }
        guard removed else { return .notFound }
        return .deleted(indexRebuilt: rebuildIndexQuietly() != nil)
    }

    public func clear() -> AgentMemoryNotice {
        let count: Int
        do {
            count = try store.removeAll(workspace: workspace)
        } catch {
            return .failed
        }
        guard count > 0 else { return .cleared(0, indexRebuilt: rebuildIndexQuietly() != nil) }
        return .cleared(count, indexRebuilt: rebuildIndexQuietly() != nil)
    }

    // MARK: 索引（派生缓存）

    @discardableResult
    public func rebuildIndex(at date: Date = Date()) -> AgentMemoryNotice {
        do {
            let index = try store.rebuildIndex(workspace: workspace, builtAt: date)
            return .indexRebuilt(index.entryCount)
        } catch {
            return .failed
        }
    }

    /// 删 / 清之后的索引对齐：失败**不吞**（返回 `nil`，由调用方在结论里说「索引没对齐」）。
    private func rebuildIndexQuietly(at date: Date = Date()) -> AgentMemoryIndex? {
        try? store.rebuildIndex(workspace: workspace, builtAt: date)
    }
}
