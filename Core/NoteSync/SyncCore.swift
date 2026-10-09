import Foundation

// MARK: - 回执三态（`IR-16`）
//
// 上行写入的幂等键 = **`uid` + `rev`**（契约 `Docs/需求规范书.md` §6.4.2）。服务端按 LWW 决胜，
// 回给调用方的一律是这三态之一 —— 这里把「三态」写成类型，于是「本地覆盖 / 本地不变 / 留两版」
// 这件事无法被某个调用点悄悄简化成两态。
public enum SyncVerdict: String, Codable, Sendable, CaseIterable, Equatable {
    /// 已接收（上行那一版更新 ⇒ 本地覆盖）
    case accepted
    /// 已过期（上行那一版更旧 ⇒ 丢弃，本地不变）
    case expired
    /// 冲突留两版（`rev` 相同而内容 / 时刻不同 ⇒ 两版都在，不静默丢弃）
    case conflict
}

// MARK: - 幂等键（`IR-16`）
/// 「同一次写入」的身份：同一个 `uid` 的第 `rev` 版。
///
/// 为什么单独成类型：幂等键进的是**交换面**（上行去重、下行去重、队列里回查都靠它），
/// 而不是某个调用点的局部判断 —— 写成类型后，比较两处「是不是同一次写入」只有一处定义。
public struct SyncIdentity: Hashable, Codable, Sendable {
    public let uid: String
    public let rev: Int

    public init(uid: String, rev: Int) {
        self.uid = uid
        self.rev = rev
    }
}

// MARK: - 同步记录（云端 `notes` 行的同步面）
/// 一行记录的**同步面**：身份（`uid`）+ 版本（`rev`）+ 时刻 + 墓碑 + 出端 + 不透明快照。
///
/// 三条口径写在这里，免得被下一个改它的人重新猜一遍：
///   ① **字段名照契约**（§6.4.1 的通用列 `uid` / `rev` / `updated_at` / `deleted_at` / `device_id`）；
///   ② `payload` 是**不透明快照** —— 本片（同步内核）**不解释正文**：云侧照 `notes` 表的列拼、
///      本地照 `Note` 拼，谁能拼、拼什么属于各自的装配面，不属于决胜规则。这样「记录级 LWW」
///      才不必随正文格式变化而改一次；
///   ③ `deletedAt` 非空 = **墓碑**（§6.4.2 `IR-17`）：物理行**不删**，本地只是不再把它当活行。
public struct SyncRecord: Codable, Equatable, Sendable {
    /// 跨端稳定身份（契约 §2.11：首次落库生成、此后不变、不进界面）。
    public var uid: String
    /// 单调版本号（每次内容变更 +1；组织类变更按本地口径不刷新 `updatedAt`，见契约 §2.1）。
    public var rev: Int
    public var updatedAt: Date
    /// 墓碑时刻；非空 = 这一行已被删除（但物理行还在）。
    public var deletedAt: Date?
    public var deviceId: String?
    /// 不透明快照（见类型注释 ②）。本片只搬运它，不解析它。
    public var payload: String

    public init(
        uid: String,
        rev: Int,
        updatedAt: Date,
        deletedAt: Date? = nil,
        deviceId: String? = nil,
        payload: String = ""
    ) {
        self.uid = uid
        self.rev = rev
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.deviceId = deviceId
        self.payload = payload
    }

    /// 幂等键（`uid` + `rev`）。
    public var identity: SyncIdentity { SyncIdentity(uid: uid, rev: rev) }

    /// 墓碑（§6.4.2 `IR-17`）。
    public var isTombstone: Bool { deletedAt != nil }
}

// MARK: - 决胜结果
/// 一次决胜的**全部**产出：三态回执 + 本地应持有的主版本 + 被留下的另一版（非冲突时为 `nil`）。
public struct SyncMerge: Equatable, Sendable {
    public var verdict: SyncVerdict
    /// 决胜后本地应持有的**主版本**（无本地行时 = 上行那一版；已过期时 = 本地那一版）。
    public var primary: SyncRecord
    /// 冲突时被留下的**另一版**。非空即「两版都在」—— 调用方负责把它也存下来。
    public var conflict: SyncRecord?

    public init(verdict: SyncVerdict, primary: SyncRecord, conflict: SyncRecord? = nil) {
        self.verdict = verdict
        self.primary = primary
        self.conflict = conflict
    }
}

// MARK: - 记录级 LWW 决胜（`IR-16`）
/// 决胜规则集：**无状态**（同输入同输出），不碰网络、不碰库、不碰时钟（时刻由记录自带）。
public enum SyncResolution {

    /// 记录级 LWW（人类主人 2026-10-09 拍板）：`rev` 定胜负，`updatedAt` 只做「同版本」的兜底区分。
    ///
    /// 决策表（`local == nil` ⇒ 首次见到这条记录 ⇒ 直接接收）：
    ///   · 上行 `rev` **更大** ⇒ `.accepted`（本地覆盖）
    ///   · 上行 `rev` **更小** ⇒ `.expired`（丢弃，本地不变）
    ///   · 上行 `rev` **相同**：
    ///       - 时刻 / 快照 / 墓碑**全都相同** ⇒ `.accepted`（同一次写入的重放，幂等：本地不动）
    ///       - 否则 ⇒ `.conflict`：两版都留，主版本取 `updatedAt` 大的那一版；
    ///         时刻也相同（只有快照不同）时**本地这一版留作主版本**（确定性：同输入必同输出）
    public static func decide(incoming: SyncRecord, local: SyncRecord?) -> SyncMerge {
        guard let local else {
            return SyncMerge(verdict: .accepted, primary: incoming)
        }
        if incoming.rev > local.rev {
            return SyncMerge(verdict: .accepted, primary: incoming)
        }
        if incoming.rev < local.rev {
            return SyncMerge(verdict: .expired, primary: local)
        }
        if incoming.updatedAt == local.updatedAt,
           incoming.deletedAt == local.deletedAt,
           incoming.payload == local.payload {
            // 幂等键命中且内容一致：这是同一次写入的重放，不产生新版本、也不报冲突。
            return SyncMerge(verdict: .accepted, primary: local)
        }
        if incoming.updatedAt > local.updatedAt {
            return SyncMerge(verdict: .conflict, primary: incoming, conflict: local)
        }
        return SyncMerge(verdict: .conflict, primary: local, conflict: incoming)
    }

    /// 只问「上行这一版该不该覆盖本地」——给不需要两版兜底的调用点用（判据与 `decide` 同源）。
    public static func isNewer(incoming: SyncRecord, than local: SyncRecord?) -> Bool {
        decide(incoming: incoming, local: local).verdict == .accepted
    }
}

// MARK: - 本地账（纯内存）
/// 同步内核的本地账：每个 `uid` 一条**主版本**，外加**冲突版本**（不静默丢弃）。
///
/// 三件必须成立的事：
///   · **物理行不删**（`IR-17`）：应用一条墓碑后，这一行仍在账里（`record(uid:)` 非空），
///     只是不再出现在 `visible` 里 —— 「本地按墓碑删」删的是**可见性**，不是那一行；
///   · **冲突不丢**：`allVersions(uid:)` 能同时看到主版本与被留下的那一版；
///   · **顺序确定**：`uids` 按**首次出现序**返回（不按字典序、不按 `Dictionary` 的哈希序），
///     于是同样的输入序列在任何一次运行里都给出同样的列表。
public struct SyncLedger: Sendable {

    private var primaryByUID: [String: SyncRecord] = [:]
    private var extrasByUID: [String: [SyncRecord]] = [:]
    private var seenOrder: [String] = []

    public init() {}

    // MARK: 读

    /// 首次出现序的 `uid` 列表（确定性）。
    public var uids: [String] { seenOrder }

    /// 主版本（**含墓碑**：墓碑也是一条物理行）。
    public func record(uid: String) -> SyncRecord? { primaryByUID[uid] }

    /// 这一 `uid` 的**全部版本**：主版本在前，冲突版本按留下的次序在后。
    public func allVersions(uid: String) -> [SyncRecord] {
        var versions = primaryByUID[uid].map { [$0] } ?? []
        versions.append(contentsOf: extrasByUID[uid] ?? [])
        return versions
    }

    /// 全部主版本（首次出现序）。
    public var versions: [SyncRecord] {
        seenOrder.compactMap { primaryByUID[$0] }
    }

    /// 全部被留下的冲突版本（留下的次序）。
    public var conflicts: [SyncRecord] {
        seenOrder.flatMap { extrasByUID[$0] ?? [] }
    }

    /// 墓碑主版本（`IR-17`：这些行**还在**，只是本地当它删了）。
    public var tombstones: [SyncRecord] {
        versions.filter { $0.isTombstone }
    }

    /// 本地「活行」= 非墓碑的主版本。界面与检索看到的就是这一份。
    public var visible: [SyncRecord] {
        versions.filter { !$0.isTombstone }
    }

    // MARK: 写

    /// 应用一版记录，返回这一轮的决胜结果。
    @discardableResult
    public mutating func apply(_ incoming: SyncRecord) -> SyncMerge {
        let merge = SyncResolution.decide(incoming: incoming, local: primaryByUID[incoming.uid])
        if primaryByUID[incoming.uid] == nil {
            seenOrder.append(incoming.uid)
        }
        primaryByUID[incoming.uid] = merge.primary
        if let conflict = merge.conflict {
            var extras = extrasByUID[incoming.uid] ?? []
            // 同一版（幂等键 + 快照 + 时刻都相同）重复到达时不重复堆叠。
            if !extras.contains(where: { $0.identity == conflict.identity && $0 == conflict }) {
                extras.append(conflict)
            }
            extrasByUID[incoming.uid] = extras
        }
        return merge
    }

    /// 按页应用（`IR-15` 拉到的一页）。返回逐 `uid` 的回执三态，便于上行调用方统一处理。
    @discardableResult
    public mutating func apply(_ page: [SyncRecord]) -> [String: SyncVerdict] {
        var verdicts: [String: SyncVerdict] = [:]
        for record in page {
            verdicts[record.uid] = apply(record).verdict
        }
        return verdicts
    }
}

// MARK: - 增量游标（`IR-15`）
/// 增量拉取的游标（**持久化在本地**，契约 §6.4.2 `IR-15`）。
///
/// 为什么不是「存一个时间戳」那么简单：增量条件是 `updated_after=<游标>`，而**同一时刻可能有多行**
/// （一次同步里两台设备各写一条，`updated_at` 撞在同一微秒）。只存时间戳会出现两种错：
///   · 用 `>` 比较 ⇒ 与游标同刻的那些行**永远拉不到**（丢行）；
///   · 用 `>=` 比较 ⇒ 与游标同刻的那些行**每轮重复拉**（重复决胜，冲突账无谓膨胀）。
/// 所以游标是**两件**：`updatedAfter`（时刻）+ `boundaryUIDs`（该时刻已见过的 `uid`）。
/// 云侧照 `updated_at >= updatedAfter` 取、再把 `boundaryUIDs` 里那些滤掉，丢掉的行就补回来了。
public struct SyncCursor: Codable, Equatable, Sendable {

    /// 本机已经处理到的**最大** `updatedAt`。
    public private(set) var updatedAfter: Date?
    /// 恰好等于 `updatedAfter` 的那些 `uid`（已经处理过，下一轮滤掉）。
    public private(set) var boundaryUIDs: Set<String>

    public init(updatedAfter: Date? = nil, boundaryUIDs: Set<String> = []) {
        self.updatedAfter = updatedAfter
        self.boundaryUIDs = boundaryUIDs
    }

    /// 这一页里**本机还没处理过**的记录（判据只此一处：云侧取数与本地去重不许各写一份）。
    public func unseen(in page: [SyncRecord]) -> [SyncRecord] {
        guard let updatedAfter else { return page }
        return page.filter { record in
            if record.updatedAt > updatedAfter { return true }
            if record.updatedAt == updatedAfter { return !boundaryUIDs.contains(record.uid) }
            return false
        }
    }

    /// 用一页记录推进游标：取本页最大时刻为新游标，同刻的 `uid` 一并记住。
    ///
    /// 两条边界如实处理：空页 ⇒ 游标不动；整页都比当前游标旧（乱序回包）⇒ 游标不动
    /// （宁可多拉一轮，也不把游标往回退 —— 退回去就会把已处理的整段重新拉一遍）。
    public mutating func advance(with page: [SyncRecord]) {
        guard let newest = page.map(\.updatedAt).max() else { return }
        if let current = updatedAfter {
            if newest < current { return }
            if newest == current {
                boundaryUIDs.formUnion(page.lazy.filter { $0.updatedAt == current }.map(\.uid))
                return
            }
        }
        updatedAfter = newest
        boundaryUIDs = Set(page.lazy.filter { $0.updatedAt == newest }.map(\.uid))
    }
}
