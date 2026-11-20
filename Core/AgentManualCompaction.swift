import Foundation

/// 用户显式 `/compact`（详设 §3.21 · `FR-AGT-KNOW-CTX-002` · 会话边界 `userCompact`）。
///
/// 与自动压缩的分工：自动压缩在**超预算**时才动手，用户显式要的那一下是**强制**的 ——
/// 「现在就把早期回复折成一行」，不必等预算撞墙。
///
/// 三条不许破的线：
/// 1. **用户原话一个字都不动** —— 折叠只碰助手正文（`role == "assistant"`），
///    用户说过的话原样留在历史里（压掉「我问了什么」会让模型答非所问）；
/// 2. **回合内只许排队** —— 回合内返回 `.deferred(.userCompact)`，历史一个字不改
///    （§3.21：回合内能说话的只有预算报告）；
/// 3. **如实报数** —— 压了几条 / 约省多少 token / 丢了哪些，三个数都要交得出来；
///    压完仍超上限就 `.refused` 且**历史原样**，不许静默截断。
///
/// 形状是纯函数：给定「历史 + 预算 + 是否回合内」⇒ 结果只由入参决定，不读钟、不读盘。
public struct AgentManualCompactionResult: Equatable, Sendable {

    public enum Status: Equatable, Sendable {
        /// 真压了 —— `history` 是可以直接拿去当下一轮前情的新历史。
        case compacted
        /// 回合内：排队到下一个会话边界，`history` 原样。
        case deferred(next: AgentSessionBoundary)
        /// 没什么可压的（历史太短 / 助手正文少于三条）—— 不是失败，如实说。
        case nothingToCompress
        /// 压完还超上限 —— 拒不静默截断，`history` 原样。
        case refused(before: Int, after: Int)
    }

    public var status: Status
    /// 压缩后（或原样）的历史。
    public var history: [LLMTurn]
    /// `.compacted` 时的读数；其余状态为 `nil`（不虚报）。
    public var product: AgentCompressionProduct?

    public init(status: Status, history: [LLMTurn], product: AgentCompressionProduct? = nil) {
        self.status = status
        self.history = history
        self.product = product
    }
}

public enum AgentManualCompaction {

    /// 助手正文少于这个数就不折 —— 折两条老回复换一个 marker 是净损失。
    ///
    /// 定在 4 而不是 3：默认 `keepRecentEntries = 4`，压一遍之后真正的正文只剩
    /// `keep` 条左右，再想压时应当**什么都没得压**（幂等），而不是把 marker 再折一次。
    public static let minimumAssistantTurns = 4

    /// 折叠标记的抬头（与 `AgentContextCompressor.markerText` 同一个前缀）。
    /// 已经是 marker 的轮次不算「可折正文」—— 否则第二次 `/compact` 会把 marker 再折一遍。
    static let markerPrefix = "[context compressed"

    /// 手动压缩（严格模式：不看当前是否超预算，直接折早期助手正文）。
    /// - Parameters:
    ///   - history: 当前会发出去的前情（`context.priorTurns` 的来源）。
    ///   - budget: 预算（只借它的 `keepRecentEntries` 与上限口径；手动压缩不受「超了才动手」约束）。
    ///   - inTurn: 是否在回合内（`true` ⇒ 只排队，历史不动）。
    ///   - decisionsKept: 本次仍要保住的决策 / 约束（给人看的清单，压不掉它们）。
    public static func compact(history: [LLMTurn],
                               budget: AgentContextCompressionBudget,
                               inTurn: Bool,
                               decisionsKept: [String] = []) -> AgentManualCompactionResult {
        // ① 回合内：只排队。这是 §3.21 的硬约束，先判它。
        if inTurn {
            return AgentManualCompactionResult(status: .deferred(next: .userCompact), history: history)
        }

        let assistantBodies = history
            .filter { $0.role == "assistant" && !$0.content.hasPrefix(Self.markerPrefix) }
            .map(\.content)
        guard assistantBodies.count >= minimumAssistantTurns else {
            return AgentManualCompactionResult(status: .nothingToCompress, history: history)
        }

        // ② 强制预算：留最后 keep 条，其余一律算「超预算」。
        //    用压缩器本体（而不是在这里另写一套折叠）—— 全仓只有它一处实现压缩，
        //    读数（省了多少 / 丢了哪些 / marker）也只由它给。
        let keep = min(max(budget.keepRecentEntries, 1), assistantBodies.count - 1)
        let tailCharacters = assistantBodies.suffix(keep).reduce(0) { $0 + $1.count }
        let forcedBudget = AgentContextCompressionBudget(
            maxPromptCharacters: max(0, tailCharacters - 1),
            keepRecentEntries: keep,
            minimumEntries: 1)
        let compressed = AgentContextCompressor.compress(entries: assistantBodies,
                                                         baseCharacters: 0,
                                                         budget: forcedBudget)
        guard compressed.report.didCompress else {
            return AgentManualCompactionResult(status: .nothingToCompress, history: history)
        }

        // ③ 重建历史：用户原话逐字保留，被折掉的助手正文换成一行 marker（放在原来第一处的位置）。
        let summaryText = compressed.report.marker
            ?? Self.markerPrefix + ": \(compressed.report.compressedEntries) earlier replies folded]"
        let foldBoundary = assistantBodies.count - keep
        var rebuilt: [LLMTurn] = []
        rebuilt.reserveCapacity(history.count)
        var assistantIndex = 0
        var insertedSummary = false
        for turn in history {
            guard turn.role == "assistant" else {
                rebuilt.append(turn)          // 用户原话 / 其它角色：一个字都不动
                continue
            }
            if turn.content.hasPrefix(Self.markerPrefix) {
                rebuilt.append(turn)          // 旧的 marker 原样留着（不折 marker）
                continue
            }
            if assistantIndex < foldBoundary {
                if !insertedSummary {
                    rebuilt.append(LLMTurn(role: "assistant", content: summaryText))
                    insertedSummary = true
                }
            } else {
                rebuilt.append(turn)
            }
            assistantIndex += 1
        }

        // ④ 过闸门：压完仍超上限 ⇒ 如实拒，历史原样（不许静默截断）。
        let before = history.reduce(0) { $0 + $1.content.count }
        let after = rebuilt.reduce(0) { $0 + $1.content.count }
        let admission = AgentContextCompression.admit(
            at: .userCompact,
            inTurn: false,
            tokensBefore: AgentContextCompressor.estimatedTokens(characters: before),
            tokenLimit: AgentContextCompressor.estimatedTokens(characters: budget.maxPromptCharacters),
            estimatedAfter: AgentContextCompressor.estimatedTokens(characters: after),
            engineAvailable: true,
            decisionsKept: decisionsKept,
            droppedKinds: [.detail],
            marker: summaryText)
        switch admission {
        case .runNow(_, var product):
            product.foldedReplies = compressed.report.compressedEntries
            return AgentManualCompactionResult(status: .compacted, history: rebuilt, product: product)
        case .refuse(let reason):
            if case let .stillOverLimit(beforeTokens, afterTokens) = reason {
                return AgentManualCompactionResult(status: .refused(before: beforeTokens, after: afterTokens),
                                                   history: history)
            }
            return AgentManualCompactionResult(status: .refused(before: 0, after: 0), history: history)
        case .deferToBoundary(let next, _):
            // 不会走到（上面已按 inTurn = false 调用）；留一句「排队」比假装压过诚实。
            return AgentManualCompactionResult(status: .deferred(next: next), history: history)
        case .skip:
            return AgentManualCompactionResult(status: .nothingToCompress, history: history)
        }
    }
}
