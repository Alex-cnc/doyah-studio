import Foundation
import DoyahCore

/// 步数计数器（`N/M`）在**视图这一侧的取用点**。
///
/// 为什么单独一个文件而不是并进 `AgentChatModel.swift` 里那一串 `var xxx { state.xxx }` 代理：
/// 这一条读数有两处真值 —— 分子（已完成步数）来自本轮步骤清单、分母（步数预算）来自循环上限 ——
/// 而**分母必须是常量**（2026-11-04 真机：分母一度写成「本次运行已产生的步数」，于是它跟着步数
/// 一直跳，`95/150` 被印成 `95/96`、`96/97`…）。把它单拎出来，是为了让「分母从哪来」在这份文件里
/// 一眼可见，也方便探针直接量这个读数（`Tests/AgentStepCounterTests.swift`）。
///
/// 计算本身在 `AgentChatState.stepCounter`（纯值、无视图依赖）—— 这里只做一层转发。
extension AgentChatModel {

    /// 表头读数：**分子 = 已完成步数 / 分母 = 固定步数预算**（单位：步）。
    var stepCounter: AgentStepCounter { state.stepCounter }
}
