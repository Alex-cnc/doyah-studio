import Foundation

/// IM 那一轮的**过程播报**（`FR-AGT-LINK-CHAN-003` 后半的可见性补齐）。
///
/// 由头（2026-11-04 真机）：手机那头派一句话，桌面这边**真在跑**（每 13 秒一次模型请求、
/// 步数一路涨），可聊天窗口里几分钟一片空白 ⇒ 人只看得见「跟断了」。
/// 那一轮的实际读数是：21 次模型调用 / 197 秒纯模型等待 / 82 次工具调用，
/// 而 QQ 侧从头到尾只收到一句结尾的英文失败文案。
///
/// 所以这一层补的是**「还活着」这件事本身**：
/// ① 收到即回一条 ack（`AgentIMReplyText.acknowledgement`）；
/// ② 跑的过程中按**节流**推一行「第几步 / 在干什么 / 跑了多久」；
/// ③ 收尾再回结论（含超时 / 失败的人话）。
///
/// 节流是必须的：一次真机轮次里工具调用 82 次、模型调用 21 次 —— 每次工具都推一条，
/// QQ 那边就是 82 条消息，比空白更糟。所以按「步数跳够了 **或** 时间到了」二选一放行，
/// 并且封顶（`maxPushes`）。
public struct AgentIMRunProgress: Equatable, Sendable {

    /// 当前第几跳（**1 起**：人话里「第 3 步」不是「第 2 步」）。
    public var hop: Int
    /// 正在跑的工具名（`nil` = 这一跳在等模型出话来）。
    public var tool: String?
    /// 参数摘要（`AgentToolSummary` 压过的一行；空 = 没有可报的）。
    public var summary: String
    /// 这一轮从开跑到现在过了多少秒。
    public var elapsed: TimeInterval
    /// 这一轮累计工具调用次数（进度行与失败行都用它：一眼看出走到哪儿了）。
    public var toolCalls: Int

    public init(hop: Int, tool: String? = nil, summary: String = "",
                elapsed: TimeInterval, toolCalls: Int) {
        self.hop = hop
        self.tool = tool
        self.summary = summary
        self.elapsed = elapsed
        self.toolCalls = toolCalls
    }
}

/// 进度节流（**纯判断，可单测**）。
///
/// 两条放行条件取「或」：
/// - **步数跳够了**（默认 3 跳）—— 跑得快的时候跟着步数报，人看到的是「在往前走」；
/// - **时间到了**（默认 25 秒）—— 一跳卡很久（模型慢 / 工具慢）时，也不会几个小时没动静。
///
/// 外加**总数封顶**（默认 6 条）：一轮再长，进度行也不超过 6 条 + 1 条 ack + 1 条结论。
public struct AgentIMProgressCadence: Equatable, Sendable {

    public var minInterval: TimeInterval
    public var minHopDelta: Int
    public var maxPushes: Int
    /// 开跑之后多久才允许推**第一条**进度（默认 12 秒）——
    /// 一开跑就报会跟 ack 撞在一起，人看到的是两条几乎一样的消息。
    public var firstPushAfter: TimeInterval

    public init(minInterval: TimeInterval = 25, minHopDelta: Int = 3, maxPushes: Int = 6,
                firstPushAfter: TimeInterval = 12) {
        self.minInterval = minInterval
        self.minHopDelta = minHopDelta
        self.maxPushes = maxPushes
        self.firstPushAfter = firstPushAfter
    }

    /// 已经推过几条、上一条是什么时候 / 第几跳推的。
    public struct Track: Equatable, Sendable {
        public var pushes: Int
        public var lastPushAt: Date?
        public var lastHop: Int

        public init(pushes: Int = 0, lastPushAt: Date? = nil, lastHop: Int = 0) {
            self.pushes = pushes
            self.lastPushAt = lastPushAt
            self.lastHop = lastHop
        }
    }

    /// 这一条该不该推。
    ///
    /// `elapsed` = 这一轮已经跑了多久（用于「别一开跑就播报」那条闸）。
    public func admits(hop: Int, elapsed: TimeInterval, at now: Date, track: Track) -> Bool {
        guard track.pushes < maxPushes else { return false }
        guard track.pushes > 0 else {
            // **第一条要等一会儿**：ack 刚发出去，紧接着再来一句「第 1 步」是噪音，
            // 而且它离 ack 只差一秒 —— 人看不出任何进展。
            return elapsed >= firstPushAfter
        }
        guard let last = track.lastPushAt else { return true }
        if hop - track.lastHop >= minHopDelta { return true }
        return now.timeIntervalSince(last) >= minInterval
    }
}

/// 进度行的人话（拼句收在 Core，宿主只搬）。
public enum AgentIMProgressText {

    public static func line(for progress: AgentIMRunProgress, language: AppLanguage) -> String {
        let duration = durationText(progress.elapsed, language: language)
        let tool = progress.tool.map { toolName($0, summary: progress.summary) } ?? ""
        return tool.isEmpty
            ? LocalizedStrings.format(.agentIMProgressThinking, language: language,
                                      Int64(progress.hop), duration)
            : LocalizedStrings.format(.agentIMProgressTool, language: language,
                                      Int64(progress.hop), tool, duration)
    }

    /// 工具 + 参数摘要压成一段（摘要太长就截断 —— 进度行不是审计，别把命令原文整条推过去）。
    static func toolName(_ name: String, summary: String) -> String {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return name }
        let limit = 60
        let cut = trimmed.count > limit ? String(trimmed.prefix(limit)) + "…" : trimmed
        return "\(name)（\(cut)）"
    }

    /// 秒数 → 「1 分 12 秒」/「48 秒」（两种语言都按同一口径）。
    public static func durationText(_ seconds: TimeInterval, language: AppLanguage) -> String {
        let total = max(0, Int(seconds.rounded()))
        let minutes = total / 60
        let rest = total % 60
        if minutes == 0 {
            return language == .simplifiedChinese ? "\(rest) 秒" : "\(rest)s"
        }
        return language == .simplifiedChinese
            ? "\(minutes) 分 \(rest) 秒"
            : "\(minutes)m \(rest)s"
    }
}

/// 进度出口：**节流 + 串行发送都在这里，一处**。
///
/// 为什么是个 actor：循环的观察口可能在并发任务里被调用（工具分发走 detached），
/// 「第几条 / 上一次什么时候」这份账必须串行改进。
///
/// 为什么不在这里 `await` 发送：观察口是循环里的 `await`，把 QQ 的接口延迟塞进去
/// 等于让网络去拖慢模型轮次。所以 `report` 只做「判 + 入箱」，**立刻返回**，
/// 真正发送由内部一条串行泵按入箱顺序做（进度行之间的先后因此是稳的；
/// 收尾之后才发出去的迟到行由宿主按轮次纪元丢掉）。
public actor AgentIMProgressReporter {

    public private(set) var track = AgentIMProgressCadence.Track()

    private let cadence: AgentIMProgressCadence
    private let language: AppLanguage
    private let clock: @Sendable () -> Date
    private let deliver: @Sendable (String) async -> Bool

    private var outbox: [String] = []
    private var draining = false

    public init(cadence: AgentIMProgressCadence = AgentIMProgressCadence(),
                language: AppLanguage,
                clock: @escaping @Sendable () -> Date = { Date() },
                deliver: @escaping @Sendable (String) async -> Bool) {
        self.cadence = cadence
        self.language = language
        self.clock = clock
        self.deliver = deliver
    }

    /// 报一条；被节流挡下就什么都不做。返回是否**已入箱**（单测靠它断言条数）。
    @discardableResult
    public func report(_ progress: AgentIMRunProgress) -> Bool {
        let now = clock()
        guard cadence.admits(hop: progress.hop, elapsed: progress.elapsed,
                             at: now, track: track) else { return false }
        track.pushes += 1
        track.lastPushAt = now
        track.lastHop = progress.hop
        outbox.append(AgentIMProgressText.line(for: progress, language: language))
        startPumpIfNeeded()
        return true
    }

    /// 等这一箱都发完（收尾前用：结论不许跑在进度行前面）。
    public func drain() async {
        startPumpIfNeeded()
        while draining {
            await Task.yield()
        }
    }

    private func startPumpIfNeeded() {
        guard !draining, !outbox.isEmpty else { return }
        draining = true
        Task { await self.pump() }
    }

    private func pump() async {
        while !outbox.isEmpty {
            let next = outbox.removeFirst()
            _ = await deliver(next)
        }
        draining = false
        // 泵退出与 `report` 之间可能刚好有新行进来（actor 重入）⇒ 再确认一次。
        startPumpIfNeeded()
    }
}
