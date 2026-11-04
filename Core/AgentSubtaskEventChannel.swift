import Foundation

/// **事件来源闸**（`FR-AGT-TOOL-SYS-002` ①「主控只收摘要，不收子任务的原始对话」）。
///
/// 由头（2026-11-04 真机）：子循环是 `var childLoop = loop` 复制出来的，`observer` 是**同一个对象**
/// ⇒ 三路子任务的 `delta` / `toolStarted` / `hopStarted` 直接灌进主对话：正文逐字交错成
/// `…Plug命中的ins是/ RetAppro//Sources…`，步数计数被三路的跳号顶着涨到 153
/// （`maxSteps` 是 150，而主控只有 19 条审计）。
///
/// 闸门放在**观察口的协议约定**上，而不是每个调用点各写一句 if：循环报事件只走
/// `AgentLoop.emit`，那里带上本循环的来源；观察口这一侧按来源决定收不收。
public extension AgentLoopObserver {

    /// 带来源的一版：**默认只放行主循环**。
    ///
    /// 为什么默认是「丢」而不是「转发」：观察口是界面那**一个**对象，它手里没有会话号，
    /// 自己分不出这条事件是谁的。默认放行 ⇒ 任何一个漏改的循环复制都会重新制造混流；
    /// 默认丢弃 ⇒ 漏改的代价只是「子路少一条进度显示」，不会污染主对话。
    func observe(_ event: AgentLoopEvent, origin: AgentSubtaskOrigin) async {
        guard case .mainLoop = origin else { return }
        await observe(event)
    }
}

/// 子路**已经吐出来的正文**的读口（预算到点时把这份成果当 partial 交回，不是杀了就丢）。
public protocol AgentSubtaskPartialSource: Sendable {
    func partialText(subtaskID: String) -> String?
}

/// **子路事件账**：子任务的事件只落这里（`AgentSubtaskLedger` 的并发落点）。
///
/// 三件事按契约落：
/// ① 主控只收摘要 —— 这里记的是「第几跳、调了什么工具、停在哪一档」（一行摘要），
///    正文单独存一份只给 partial 用，**不转发**给任何界面观察口；
/// ② 并发安全 —— 几路子代理同时写，锁在里面（`AgentSubtaskLedger` 是值类型，不能自己扛并发）；
/// ③ 可查 —— 主控/界面随时取 `snapshot()` 回答「谁干的、干了几步」。
public final class AgentSubtaskEventStore: @unchecked Sendable {

    private let lock = NSLock()
    private var ledger = AgentSubtaskLedger()
    private var streamed: [String: String] = [:]
    private var hops: [String: Int] = [:]

    public init() {}

    /// 派出去那一刻先立一条（来源标注的落点：`label#id` 与发起步号）。
    public func delegate(id: String, goal: String, atStep: Int) {
        lock.lock(); defer { lock.unlock() }
        ledger.delegate(id: id, goal: goal, atStep: atStep)
    }

    /// 收一条子路事件：只进这一路自己的账。
    public func absorb(_ event: AgentLoopEvent, subtaskID: String) {
        lock.lock(); defer { lock.unlock() }
        switch event {
        case .hopStarted(let index):
            hops[subtaskID, default: 0] += 1
            ledger.appendStep(subtaskID: subtaskID, kind: .decision, label: "hop:\(index + 1)")
        case .delta(let piece):
            streamed[subtaskID, default: ""] += piece
        case .reasoningDelta:
            break   // 思考段连子路的正文都不算：不落、不用来当 partial。
        case .toolStarted(let name, let summary):
            ledger.appendStep(subtaskID: subtaskID, kind: .tool,
                              label: summary.isEmpty ? name : "\(name) · \(summary)")
        case .approvalRequested(let name, _, _, _):
            ledger.appendStep(subtaskID: subtaskID, kind: .approval, label: name)
        case .stopped(let stop):
            ledger.appendStep(subtaskID: subtaskID, kind: .decision, label: stop.reason)
        case .failed(let message):
            ledger.appendStep(subtaskID: subtaskID, kind: .decision, label: "failed:\(message)")
        default:
            break
        }
    }

    /// 这一路已经吐出来的正文（`nil` = 一个字都还没吐）。
    public func partialText(subtaskID: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let text = streamed[subtaskID],
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    /// 这一路跑了几跳。
    public func hopCount(subtaskID: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return hops[subtaskID] ?? 0
    }

    /// 全部子路的账（主控/界面只读快照）。
    public func snapshot() -> AgentSubtaskLedger {
        lock.lock(); defer { lock.unlock() }
        return ledger
    }
}

/// 把一路子代理的事件搬进它自己的账：**不转发**给上层观察口。
public struct AgentSubtaskEventObserver: AgentLoopObserver {
    public let subtaskID: String
    public let store: AgentSubtaskEventStore

    public init(subtaskID: String, store: AgentSubtaskEventStore) {
        self.subtaskID = subtaskID
        self.store = store
    }

    public func observe(_ event: AgentLoopEvent) async {
        store.absorb(event, subtaskID: subtaskID)
    }

    /// 带来源的一版：**这一路自己的账不挑来源**（它就是收子路事件的那一格）。
    /// 不重写这一条，默认实现会把子路事件当「不该进主对话」直接丢掉 —— 账里就空了。
    public func observe(_ event: AgentLoopEvent, origin: AgentSubtaskOrigin) async {
        store.absorb(event, subtaskID: subtaskID)
    }
}

/// 「这一路跑完了吗」的一次性等待（执行器判预算用）。
///
/// 为什么不用 `withTaskGroup(任务 vs 计时器)`：`Task.value` 一旦被等就**要等它真回来**，
/// 组作用域退出时又必须收齐所有子任务 ⇒ 计时器那一路「到点」以后，组仍会等子代理跑完，
/// 预算等于没生效（真机 4 批 `timedOut` 就是这个形状）。这里换成「任务自己举手 + 到点自己醒」：
/// 到点立刻能判，不必等子代理收尾。
final class SubtaskCompletionFlag: @unchecked Sendable {

    private let lock = NSLock()
    private var completed = false
    private var waiter: CheckedContinuation<Bool, Never>?

    /// 任务侧举手：跑完了。
    func complete() {
        lock.lock()
        completed = true
        let pending = waiter
        waiter = nil
        lock.unlock()
        pending?.resume(returning: true)
    }

    /// 等到「跑完」或到点（`seconds` 秒）。返回 `true` = 跑完了。
    func wait(until seconds: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            lock.lock()
            if completed {
                lock.unlock()
                continuation.resume(returning: true)
                return
            }
            waiter = continuation
            lock.unlock()
            DispatchQueue.global().asyncAfter(deadline: .now() + max(0, seconds)) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let pending = self.waiter
                self.waiter = nil
                self.lock.unlock()
                pending?.resume(returning: false)
            }
        }
    }
}
