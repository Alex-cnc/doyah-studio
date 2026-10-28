import Foundation

/// 记忆写入的触发方式（`FR-AGT-KNOW-MEM-006` ①）。
///
/// 口径：**只有人说「记住」或人在界面上确认过，才允许落库** —— 模型自己觉得该记的，
/// 一律走「需确认」而不是直接写。这条不是防模型，是防「记忆越攒越脏、还没人知道它是怎么进去的」。
public enum AgentMemoryTrigger: String, Codable, Equatable, Sendable {

    /// 用户明确说「记住这个」。
    case userInstruction
    /// 用户在界面 / 求助卡上确认了一条候选。
    case userConfirmation
    /// 模型自己判断要记的（**不许直接落库**）。
    case modelSpontaneous
}

/// 写入前的最后一道闸（`FR-AGT-KNOW-MEM-006`）：触发方式 + 内容闸。
///
/// 判据：
/// ① 自发写入 ⇒ `needsConfirmation`（不落盘，给候选让人点）；
/// ② 用户指令 / 人确认 ⇒ 再过 `AgentMemoryIntake`（空正文 / 结果集行 / 密钥片段一律拒收）；
/// ③ 三种拒因都要**如实报**，不许静默改写或静默丢弃。
public enum AgentMemoryWriteGate {

    public enum Decision: Equatable, Sendable {
        /// 可以落库。
        case record
        /// 不许直接写：转成候选，等人确认（**不是报错**，是流程如此）。
        case needsConfirmation
        /// 拒收（内容不过闸）。
        case refused([AgentMemoryIntake.Rejection])
    }

    /// 纯函数：不碰盘。
    public static func decide(trigger: AgentMemoryTrigger,
                              draft: AgentMemoryDraft,
                              limits: AgentMemoryLimits = .standard) -> Decision {
        let verdict = AgentMemoryIntake.review(draft, limits: limits)
        // 内容不过闸时，无论谁要写都是拒收（这一步排在触发方式之前：脏内容不该被「确认」洗白）。
        guard verdict.isAccepted else { return .refused(verdict.rejections) }
        switch trigger {
        case .userInstruction, .userConfirmation:
            return .record
        case .modelSpontaneous:
            return .needsConfirmation
        }
    }

    /// 同键覆盖（`FR-AGT-KNOW-MEM-008`）：新者生效，旧值进 `supersededNotes` 可查，**不删旧值**。
    ///
    /// 返回新条目（调用方负责落盘）；历史最多留 20 条，超出从最早的丢 —— 报数由调用方从
    /// `supersededNotes` 长度看出，不静默。
    public static func superseding(_ existing: AgentMemoryEntry,
                                   with note: String,
                                   at date: Date,
                                   trigger: AgentMemoryTrigger,
                                   round: Int?,
                                   historyLimit: Int = 20) -> AgentMemoryEntry {
        var updated = existing
        if existing.note != note {
            var history = existing.supersededNotes ?? []
            history.append(existing.note)
            if history.count > historyLimit { history.removeFirst(history.count - historyLimit) }
            updated.supersededNotes = history
            updated.note = note
        }
        updated.lastUsedAt = date
        updated.useCount += 1
        updated.sourceTrigger = trigger.rawValue
        if let round { updated.sourceRound = round }
        return updated
    }
}
