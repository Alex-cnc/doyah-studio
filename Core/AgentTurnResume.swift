import Foundation

/// `NFR-AI-08` ⑤（检查点半的 **App 侧接线**）—— 检查点按**哪一轮提问**分账。
///
/// ## 为什么需要这一层
///
/// 检查点存储（`AgentCheckpointStore`）按 `sessionID` 回查「最后一条可用」。聊天窗口里
/// **一个会话有很多个提问**：如果检查点也按会话号落，那么第 2 个提问开跑时就会接上
/// 第 1 个提问的检查点 —— 模型会以为上一个问题的进展是这一次的前情，已完成的跳还会被
/// 当成「不用重放」。那是**假续跑**：看起来省了事，实际上把一个问题的状态冒充成另一个问题的。
///
/// 所以分两层：
/// - **会话号**（`sessionID`）留给会话留痕 / 审计 / 调用链 —— 那些本来就该按会话算；
/// - **分账号**（`checkpointScopeID`）按「第几轮提问」生成，检查点只按它落、按它回查。
///
/// ## 三条硬规矩（都是机械可判的）
///
/// 1. **新提问不许续上一个问题的检查点**：新一轮的分账号与上一轮**不同** ⇒ 回查必然落空 ⇒
///    从第 0 跳跑（`requestedStep = 0`，`skippedSteps = 0`）。
/// 2. **只有显式「继续上次」才按留痕跳号接上**：沿用**上一轮**的分账号，并把
///    `requestedStep` 设成上一轮停在的那一跳 —— 于是「退了几跳」这个数仍然如实报得出来。
/// 3. **不能续就如实说**：上一轮已经走完 / 压根没有上一轮 ⇒ **不冒充**能续，
///    回到新一轮并给一个**机器码**（人话在界面翻），绝不悄悄接上一个问题的检查点。
public struct AgentTurnRecord: Equatable, Sendable {

    /// 第几轮提问（**1 起**）。
    public var turn: Int
    /// 这一轮跑到第几跳（= 跑完的跳数；0 = 一跳都没跑完）。
    public var lastStep: Int
    /// 这一轮是不是**没走完就停了**（限额 / 取消 / 失败）—— 只有这种才值得续。
    public var unfinished: Bool

    public init(turn: Int, lastStep: Int, unfinished: Bool) {
        self.turn = turn
        self.lastStep = lastStep
        self.unfinished = unfinished
    }
}

/// 用户这一次要做什么（决定分账方式）。
public enum AgentTurnIntent: Equatable, Sendable {
    /// 新提问（打字发出）。
    case newQuestion
    /// **显式**「继续上次」（点按钮 / 点那一行读数）。
    case continueLast
}

/// 一次提问的落账：分账号 + 从第几跳起 + 续不续得上（+ 机器码，人话由界面翻）。
public struct AgentTurnPlan: Equatable, Sendable {

    /// 第几轮提问（1 起）。
    public var turn: Int
    /// **检查点的分账号**（`AgentCheckpoint.sessionID` 那一格吃的就是它）。
    public var checkpointScopeID: String
    /// 交给 `AgentLoop.run(requestedStep:)` 的「调用方以为自己停在第几跳」。
    public var requestedStep: Int
    /// 这一次是不是**真能**从检查点接上（`false` ⇒ 从第 0 跳跑，不是「假装续跑」）。
    public var resumes: Bool
    /// 机器码：`freshTurn:N` / `resume:tN:stepM` / `nothingToResume` / `previousFinished`。
    public var note: String

    public init(turn: Int, checkpointScopeID: String, requestedStep: Int,
                resumes: Bool, note: String) {
        self.turn = turn
        self.checkpointScopeID = checkpointScopeID
        self.requestedStep = requestedStep
        self.resumes = resumes
        self.note = note
    }
}

/// 分账规则的**唯一出处**（纯函数：同输入两次调用结果逐字一致）。
public enum AgentTurnPlanner {

    /// 分账号的形状：`<会话号>#turn-<N>`。
    ///
    /// 取这个形状而不是另起一套存储：检查点文件仍是一份 `agent-checkpoints.jsonl`，
    /// 只是键上多带一段「哪一轮」—— 存储层不必知道「轮」这个概念。
    public static func scopeID(sessionID: String, turn: Int) -> String {
        "\(sessionID)#turn-\(turn)"
    }

    /// 算这一次提问怎么落账。
    ///
    /// - Parameters:
    ///   - sessionID: 会话号（**不掺轮次**：它同时是会话留痕与审计的键）。
    ///   - previous: 上一次提问的落账（`nil` = 这个会话还没有跑过）。
    ///   - intent: 新提问 / 显式继续上次。
    public static func plan(sessionID: String,
                            previous: AgentTurnRecord?,
                            intent: AgentTurnIntent) -> AgentTurnPlan {
        switch intent {
        case .newQuestion:
            // **新提问 = 新的一轮** ⇒ 分账号必然是新的 ⇒ 回查落空 ⇒ 从第 0 跳跑。
            let turn = (previous?.turn ?? 0) + 1
            return fresh(sessionID: sessionID, turn: turn, note: "freshTurn:\(turn)")

        case .continueLast:
            guard let previous else {
                // 没跑过 = 没得续。**不冒充**（回的是新一轮 + 机器码）。
                return fresh(sessionID: sessionID, turn: 1, note: "nothingToResume")
            }
            guard previous.unfinished, previous.lastStep > 0 else {
                // 上一轮已经走完（或一跳都没跑完）⇒ 没得续：如实说，并落到**新的一轮**。
                return fresh(sessionID: sessionID,
                             turn: previous.turn + 1,
                             note: previous.unfinished ? "nothingToResume" : "previousFinished")
            }
            // 真能续：**沿用上一轮的分账号**，并报出「以为自己停在第几跳」。
            return AgentTurnPlan(turn: previous.turn,
                                 checkpointScopeID: scopeID(sessionID: sessionID, turn: previous.turn),
                                 requestedStep: previous.lastStep,
                                 resumes: true,
                                 note: "resume:t\(previous.turn):step\(previous.lastStep)")
        }
    }

    /// 一轮跑完之后怎么记账（下一轮「能不能续」看的就是它）。
    ///
    /// 只有 `.finished` 算走完；限额停 / 取消 / 失败都算**没走完**（都能接着跑）。
    public static func record(turn: Int, result: AgentLoopResult) -> AgentTurnRecord {
        let unfinished: Bool
        switch result.outcome {
        case .finished: unfinished = false
        case .stopped, .failed: unfinished = true
        }
        return AgentTurnRecord(turn: turn, lastStep: result.steps, unfinished: unfinished)
    }

    private static func fresh(sessionID: String, turn: Int, note: String) -> AgentTurnPlan {
        AgentTurnPlan(turn: turn,
                      checkpointScopeID: scopeID(sessionID: sessionID, turn: turn),
                      requestedStep: 0,
                      resumes: false,
                      note: note)
    }
}
