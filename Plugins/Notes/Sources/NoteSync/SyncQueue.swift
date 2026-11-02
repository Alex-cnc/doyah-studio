import Foundation

// MARK: - 队列里的操作种类
/// 一条 `uid` 欠云端的一次操作。
public enum SyncOperation: String, Codable, Sendable, CaseIterable, Equatable {
    /// 新增 / 修改（上行写入，`IR-16`）
    case upsert
    /// 删除（墓碑上行，`IR-17`）
    case delete
}

// MARK: - 记录家族（同一套链路上的两类对象）
/// **同一条同步链路上的两类对象**（`FR-NTS-TODO-LIST-001` 判据②：与笔记走同一条链路、不做第二套）。
///
/// 为什么是一个字段、而不是第二条队列 / 第二个服务：契约要求的是「同一条链路」——
/// 一个队列（同一份退避、同一份入队序）、一个决胜引擎（`SyncResolution`）、一次认证、
/// 一个重放循环。差别只有一处：**上行到哪张表**。把它做成枚举，新增一类对象时
/// 只多一个 case，而不是再抄一份 `SyncQueue` + `CloudSyncService`。
///
/// 取值即协议、**只增不改**：认不出的家族在解码时按 `.note` 落（与 `TodoPriority` 同一条
/// 「当没给」口径 —— 旧状态文件里没有这一格，读出来就是笔记）。
public enum SyncFamily: String, Codable, Sendable, CaseIterable, Equatable {
    /// 笔记（云端 `notes` 表）。
    case note
    /// 待办任务（云端 `todos` 表）。
    case todo

    /// 云端表名（`CloudSyncEndpoints.tableURL` 的直接入参）。
    public var tableName: String {
        switch self {
        case .note: return "notes"
        case .todo: return "todos"
        }
    }

    /// 认不出的取值 ⇒ `.note`（旧状态文件没有这一格）。
    public init(raw: String) {
        self = SyncFamily(rawValue: raw) ?? .note
    }
}

// MARK: - 队列条目
/// 队列里的一条待办：**只记「哪条 `uid` 欠一次什么操作」**。
///
/// 为什么不把正文也塞进队列：离线优先下**本地库是唯一事实源**（契约 §10.4 `S1`/`S2`），
/// 队列只是「欠账索引」。正文进队列会立刻出现两份可写副本 —— 编辑后队列里还是旧正文，
/// 重放上去又把新正文盖回旧值。所以重放时**现取**，队列本身很小、也不会与库分叉。
public struct SyncQueueEntry: Equatable, Codable, Sendable {
    public var uid: String
    public var operation: SyncOperation
    /// 这条欠账属于哪一类对象（`FR-NTS-TODO-LIST-001` 判据②：同一队列、同一退避，只差上行的表）。
    /// **缺这一格（旧状态文件）⇒ `.note`** —— 见下面的 `init(from:)`。
    public var family: SyncFamily
    /// 已失败次数（成功 / 从未失败为 0）。
    public var attempts: Int
    public var enqueuedAt: Date
    /// 下一次可以重放的时刻（失败退避后往后推）。
    public var nextAttemptAt: Date

    public init(
        uid: String,
        operation: SyncOperation = .upsert,
        family: SyncFamily = .note,
        attempts: Int = 0,
        enqueuedAt: Date,
        nextAttemptAt: Date
    ) {
        self.uid = uid
        self.operation = operation
        self.family = family
        self.attempts = attempts
        self.enqueuedAt = enqueuedAt
        self.nextAttemptAt = nextAttemptAt
    }

    /// **解码**：`family` 是后加的字段（旧状态文件的队列里没有它）⇒ 缺这一格按 `.note`。
    /// 与 `Todo.note` / `Note.isFavorite` 同一条纪律：加字段不许让旧文件解不出来
    /// （否则一次升级就把「断网时攒下的欠账」全丢了 —— 那是真的丢数据，不是显示问题）。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uid = try container.decode(String.self, forKey: .uid)
        operation = (try? container.decode(SyncOperation.self, forKey: .operation)) ?? .upsert
        family = SyncFamily(raw: (try? container.decodeIfPresent(String.self, forKey: .family)) ?? "")
        attempts = (try? container.decode(Int.self, forKey: .attempts)) ?? 0
        enqueuedAt = try container.decode(Date.self, forKey: .enqueuedAt)
        nextAttemptAt = try container.decode(Date.self, forKey: .nextAttemptAt)
    }

    private enum CodingKeys: String, CodingKey {
        case uid, operation, family, attempts, enqueuedAt, nextAttemptAt
    }
}

// MARK: - 指数退避（`IR-21`）
/// 失败重试的等待时长：`baseDelay · multiplier^(失败次数-1)`，**封顶 `maxDelay`**。
///
/// 两条口径写在明处：
///   · **无抖动**（不做 random jitter）—— 抖动很好看，但它让「退避序列表」不可断言；
///     本工程要的是可机械复核的序列，所以抖动留给将来有需要时**显式**加一层；
///   · 退避状态**不因新写入而重置** —— 否则用户一直编辑（每次编辑都入队）就会把退避
///     永远压回第一档，网络不通时反而变成「每次编辑都立刻猛试一轮」。
public struct SyncRetryPolicy: Equatable, Sendable {

    public var baseDelay: TimeInterval
    public var multiplier: Double
    public var maxDelay: TimeInterval

    public init(baseDelay: TimeInterval = 2, multiplier: Double = 2, maxDelay: TimeInterval = 300) {
        self.baseDelay = baseDelay
        self.multiplier = multiplier
        self.maxDelay = maxDelay
    }

    public static let `default` = SyncRetryPolicy()

    /// 第 `failures` 次失败之后要等多久（`failures <= 0` ⇒ 0，即「还没失败过」）。
    public func delay(afterFailures failures: Int) -> TimeInterval {
        guard failures > 0 else { return 0 }
        let raw = baseDelay * pow(multiplier, Double(failures - 1))
        return min(maxDelay, max(0, raw))
    }
}

// MARK: - 离线同步队列（`IR-21`）
/// 本地同步队列：**入队 / 出队 / 失败重试与指数退避**（契约 §6.4.2 `IR-21`）。
///
/// 本片是**纯逻辑**：时钟注入（`now`），只有「哪条欠什么 + 什么时候可以再试」这几件事。
/// 真正的网络调用属共享逻辑层的网络接线片（`IR-21` 的后半句），不在这里。
///
/// 三条口径：
///   · **同一条 `uid` 只欠一次操作**：重复入队不新增条目（`IR-16` 的幂等键落在队列上就是这条）；
///     已有未完成项时**后写覆盖操作种类**（先 `upsert` 后 `delete` ⇒ 记 `delete`）；
///   · **出队只发生在成功之后**：`dequeue(uid:)` 由重放成功的一方调用；失败走 `fail(uid:)`
///     （不入队新条目、不出队，只把 `nextAttemptAt` 往后推）；
///   · **重放按入队序**：`ready(at:)` 保持入队次序 —— 同一 `uid` 的写入次序是语义的一部分
///     （先建后删不能反过来重放）。
public struct SyncQueue: Sendable {

    /// 待办条目（入队序）。
    public private(set) var entries: [SyncQueueEntry]
    public var policy: SyncRetryPolicy
    private let clock: @Sendable () -> Date

    /// - Parameters:
    ///   - policy: 退避策略。
    ///   - now: **可注入时钟**（单测据此断言退避序列，不依赖真实等待）。
    public init(
        entries: [SyncQueueEntry] = [],
        policy: SyncRetryPolicy = .default,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.entries = entries
        self.policy = policy
        self.clock = now
    }

    // MARK: 读

    public var isEmpty: Bool { entries.isEmpty }
    public var pendingCount: Int { entries.count }

    public func entry(uid: String, family: SyncFamily = .note) -> SyncQueueEntry? {
        entries.first { $0.uid == uid && $0.family == family }
    }

    /// 到点可以重放的条目（**入队序**）。已到 `nextAttemptAt` 的算到点。
    public func ready(at date: Date) -> [SyncQueueEntry] {
        entries.filter { $0.nextAttemptAt <= date }
    }

    // MARK: 写

    /// **入队**。同 `(family, uid)` 已有未完成项 ⇒ 不新增条目（返回 `false`），只把操作种类按后写覆盖。
    ///
    /// 去重键是 `(family, uid)` 而不是单 `uid`：笔记与待办是两类对象，各自的 `uid` 各自命名空间
    /// （同一个 UUID 在两边同时出现不该被合成一条欠账）。
    @discardableResult
    public mutating func enqueue(uid: String, operation: SyncOperation = .upsert, family: SyncFamily = .note) -> Bool {
        let now = clock()
        if let index = entries.firstIndex(where: { $0.uid == uid && $0.family == family }) {
            // `delete` 是更重的语义：先 upsert 后 delete 记 delete；反向则保留 delete
            // （本地删了又被改回来的情况由下一次 upsert 的正常入队覆盖，不走这条路）。
            if operation == .delete || entries[index].operation != .delete {
                entries[index].operation = operation
            }
            return false
        }
        entries.append(
            SyncQueueEntry(
                uid: uid,
                operation: operation,
                family: family,
                attempts: 0,
                enqueuedAt: now,
                nextAttemptAt: now
            )
        )
        return true
    }

    /// **出队**（重放成功后调用）。返回是否真的移除了这一条。
    @discardableResult
    public mutating func dequeue(uid: String, family: SyncFamily = .note) -> Bool {
        guard let index = entries.firstIndex(where: { $0.uid == uid && $0.family == family }) else { return false }
        entries.remove(at: index)
        return true
    }

    /// **失败**：失败次数 +1，并按指数退避把 `nextAttemptAt` 推到「现在 + 等待秒数」。
    ///
    /// - Returns: 本轮等待秒数；队列里没有这一条时返回 `nil`。
    @discardableResult
    public mutating func fail(uid: String, family: SyncFamily = .note) -> TimeInterval? {
        guard let index = entries.firstIndex(where: { $0.uid == uid && $0.family == family }) else { return nil }
        let attempts = entries[index].attempts + 1
        let delay = policy.delay(afterFailures: attempts)
        entries[index].attempts = attempts
        entries[index].nextAttemptAt = clock().addingTimeInterval(delay)
        return delay
    }

    /// 全部清空（登出 / 换账号时由调用方决定，本片不自作主张）。
    public mutating func removeAll() {
        entries.removeAll()
    }
}
