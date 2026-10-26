import Foundation

/// **恢复简报**（`FR-AGT-QUAL-VERIFY-002`：长任务跨小时不丢目标）。
///
/// 三条判据落在这里：
/// ① 中断 / 重启 / 换端之后**能接着做** —— `fromStep` 就是要接着跑的那一跳，不是从头；
///    `skippedSteps` 如实报回退了几跳（不假装 0）。
/// ② 恢复的**第一步先复述**目标与已完成部分 —— `narration` 就是那句话，且只在恢复时给
///    （`shouldRestate(isResume:)` 为假时不许开口，避免每一步都复述成噪音）。
/// ③ 目标被用户改过时**以最新为准** —— `goalChanged` 由「当前目标的指纹」与检查点里存的
///    指纹对比得出；只要不一致，简报用的就是传入的最新目标，并在叙述里点明改过。
///
/// 边界：简报只装**摘要**（目标原文 + 已完成步骤摘要），不装任何结果集行数据；检查点里也不存目标原文，
/// 只存 `AgentFingerprint.hash` 的摘要值。
public struct AgentResumeBrief: Equatable, Sendable {

    /// 当前目标（**最新**的那份，用户改过就已是新版）。
    public let goal: String
    /// 已完成步骤的摘要（与检查点同源，逐条一句话）。
    public let completedSteps: [String]
    /// 接着做的那一跳（0 起；无检查点时为 0）。
    public let fromStep: Int
    /// 回退了几跳（检查点比请求位落后多少，如实报）。
    public let skippedSteps: Int
    /// 目标相对检查点是否改过（指纹不一致）。
    public let goalChanged: Bool
    /// 是不是全新开始（没有任何可用检查点）。
    public let isFreshStart: Bool

    public init(goal: String,
                completedSteps: [String] = [],
                fromStep: Int = 0,
                skippedSteps: Int = 0,
                goalChanged: Bool = false,
                isFreshStart: Bool = true) {
        self.goal = goal
        self.completedSteps = completedSteps
        self.fromStep = fromStep
        self.skippedSteps = skippedSteps
        self.goalChanged = goalChanged
        self.isFreshStart = isFreshStart
    }

    // MARK: - 生成

    /// 从「检查点恢复结果」+「当前目标」生成简报。
    ///
    /// - 有检查点：从 `stepIndex + 1` 接着做；已完成步骤取检查点摘要；
    ///   目标指纹与检查点里的不一致 ⇒ `goalChanged = true`（以传入的最新目标为准）。
    /// - 无检查点：`fromStep = 0`、`isFreshStart = true`，已完成步骤为空 —— **不假装已经有进度**。
    public static func make(goal: String,
                            recovery: AgentCheckpointRecovery,
                            at _: Date? = nil) -> AgentResumeBrief {
        let normalizedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let checkpoint = recovery.checkpoint else {
            return AgentResumeBrief(goal: normalizedGoal,
                                    completedSteps: [],
                                    fromStep: 0,
                                    skippedSteps: recovery.skippedSteps,
                                    goalChanged: false,
                                    isFreshStart: true)
        }
        let currentDigest = AgentFingerprint.hash(normalizedGoal)
        // 空串 = 老记录没指纹 ⇒ 判「没改过」；有指纹但不一致 ⇒ 改过（以最新目标为准）。
        let changed = !checkpoint.goalDigest.isEmpty && checkpoint.goalDigest != currentDigest
        return AgentResumeBrief(goal: normalizedGoal,
                                completedSteps: checkpoint.completedSteps,
                                fromStep: checkpoint.stepIndex + 1,
                                skippedSteps: recovery.skippedSteps,
                                goalChanged: changed,
                                isFreshStart: false)
    }

    // MARK: - 何时说

    /// 只在**恢复**时复述；同一轮里的后续每一步不复述（判据反例：不是每一步都复述目标）。
    public static func shouldRestate(isResume: Bool) -> Bool { isResume }

    // MARK: - 叙述

    /// 恢复第一步说的那句话：目标 + 已完成 + 从第几跳接着做（+ 目标改过则点明）。
    public func narration(language: AppLanguage = .simplifiedChinese) -> String {
        switch language {
        case .simplifiedChinese:
            return Self.chinese(self)
        case .english:
            return Self.english(self)
        }
    }

    private static func chinese(_ brief: AgentResumeBrief) -> String {
        var parts: [String] = []
        parts.append("目标：" + brief.goal)
        if brief.isFreshStart {
            parts.append("这是新开始，之前没有可用的进度记录。")
        } else {
            if brief.completedSteps.isEmpty {
                parts.append("已完成：还没有跑完的步骤。")
            } else {
                parts.append("已完成：" + brief.completedSteps.joined(separator: "；") + "。")
            }
            var resume = "从第 \(brief.fromStep + 1) 步接着做。"
            if brief.skippedSteps > 0 {
                resume += "（有 \(brief.skippedSteps) 步没有可用记录，需要时重做。）"
            }
            parts.append(resume)
        }
        if brief.goalChanged {
            parts.append("注意：目标与上次不同，以现在这份为准。")
        }
        return parts.joined(separator: "\n")
    }

    private static func english(_ brief: AgentResumeBrief) -> String {
        var parts: [String] = []
        parts.append("Goal: " + brief.goal)
        if brief.isFreshStart {
            parts.append("Fresh start: no usable progress on record.")
        } else {
            if brief.completedSteps.isEmpty {
                parts.append("Done so far: no completed steps yet.")
            } else {
                parts.append("Done so far: " + brief.completedSteps.joined(separator: "; ") + ".")
            }
            var resume = "Resuming at step \(brief.fromStep + 1)."
            if brief.skippedSteps > 0 {
                resume += " (\(brief.skippedSteps) step(s) had no usable record; redo if needed.)"
            }
            parts.append(resume)
        }
        if brief.goalChanged {
            parts.append("Note: the goal changed since the checkpoint — this newer version wins.")
        }
        return parts.joined(separator: "\n")
    }
}
