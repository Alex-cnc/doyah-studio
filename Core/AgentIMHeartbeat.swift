import Foundation

/// **超时之后还要不要继续吭声**（`FR-AGT-LINK-CHAN-003`，2026-11-11 真机：
/// 「跑到这里就没了：This turn has been running for 2m 40s and is still going…」）。
///
/// 那句话里写着「I will keep reporting progress」，可旧实现说完就再没动静 ——
/// 一轮跑 40 分钟，手机那头 40 分钟一片死寂，人只能以为它挂了。
///
/// 口径：
/// ① 只有**真的还在跑**才吭声（跑完了由结论那条说话，不该再补心跳）；
/// ② 节奏是**分钟级**（默认 5 分钟），不是秒级 —— 心跳不是进度条，是「我还活着」；
/// ③ **封顶**（默认 6 条）—— 跑一整夜也不会变成刷屏；
/// ④ 一次都不许和「还在跑」那条首报重叠（首报已经说过了，`elapsed` 要过 `firstAt`）。
public struct AgentIMHeartbeatPolicy: Equatable, Sendable {

    /// 两条心跳的最小间隔（秒）。
    public var interval: TimeInterval
    /// 最多补几条。
    public var maxSends: Int
    /// 距开跑多久之后才开始第一条（超时那一刻刚报过，别马上又来一条）。
    public var firstAt: TimeInterval

    public init(interval: TimeInterval = 300, maxSends: Int = 6, firstAt: TimeInterval = 360) {
        self.interval = interval
        self.maxSends = maxSends
        self.firstAt = firstAt
    }

    /// 该不该再发一条心跳。
    public func shouldSend(sent: Int, elapsed: TimeInterval, isRunning: Bool) -> Bool {
        guard isRunning else { return false }
        guard sent < maxSends else { return false }
        guard elapsed >= firstAt else { return false }
        guard sent == 0 else { return elapsed >= firstAt + Double(sent) * interval }
        return true
    }
}
