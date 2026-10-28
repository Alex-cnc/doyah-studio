import Foundation
import CryptoKit

/// 一次任务里某次写入的**前像**（`FR-STD-WS-EDIT-015` 整批撤回的原料）。
///
/// `previousText == nil` 表示这个文件**本来不存在**（Agent 新建的）—— 撤回就是把它删掉。
public struct AgentWriteSnapshot: Equatable, Sendable {

    public var path: String
    public var previousText: String?
    /// 写完之后的正文摘要（撤回时用来判「这之后有没有人又改过」）。
    public var writtenDigest: String

    public init(path: String, previousText: String?, writtenDigest: String) {
        self.path = path
        self.previousText = previousText
        self.writtenDigest = writtenDigest
    }

    public static func digest(_ text: String) -> String {
        let hash = SHA256.hash(data: Data(text.utf8))
        return hash.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }
}

/// 一步撤回动作（**先算计划、再落盘**：计划是纯函数，可逐条断言）。
public enum AgentRevertStep: Equatable, Sendable {
    /// 恢复成 `previousText`。
    case restore(path: String, text: String)
    /// 原本不存在 ⇒ 删掉。
    case delete(path: String)
    /// 当前内容与「写完之后」一致才走到这里；不一致的一律不许动。
    case conflict(path: String, reason: AgentRevertConflict)
}

public enum AgentRevertConflict: String, Equatable, Sendable {
    /// 撤回前文件已被别处改过（人改了 / 另一个任务改了）。
    case changedSinceWrite
    /// Agent 新建的文件已被删掉（没什么可撤，但要如实说）。
    case alreadyGone
    /// Agent 删掉的路径现在又有内容了。
    case reappeared
}

/// 整批撤回（`FR-STD-WS-EDIT-015`）。
///
/// 三条口径：
/// 1. **只撤 Agent 改的**：批次里只有写入过的路径，人手改的文件根本不在计划里；
/// 2. **人不背锅**：Agent 写完后又被人改过的文件 ⇒ `conflict`，**一个字都不动**；
/// 3. **纯函数出计划**：`plan` 只读不写，落盘由 `apply` 做，判据可以对拍计划再对拍磁盘。
public enum AgentWriteBatchRevert {

    /// 算撤回计划。`reader` 给「当前磁盘上这个路径的正文」（不存在给 `nil`）。
    public static func plan(snapshots: [AgentWriteSnapshot],
                            reader: (String) -> String?) -> [AgentRevertStep] {
        // 同一路径写了好几次：**前像取最早那份**（整批撤回 = 回到这一批开始之前），
        // 「写完之后的摘要」取**最新**那份（防人改的冲突判定比的是盘上现在这一份）。
        // 早先这里把整条换成后一条 ⇒ 一批里改两次的文件只撤得掉最后一次写，
        // 与「一次撤回把所有改动还原」正好相反（判据 `testRepeatedWritesCollapseToTheEarliestPreImage` 钉住）。
        var ordered: [AgentWriteSnapshot] = []
        var indexByPath: [String: Int] = [:]
        for snapshot in snapshots {
            if let index = indexByPath[snapshot.path] {
                ordered[index].writtenDigest = snapshot.writtenDigest
            } else {
                indexByPath[snapshot.path] = ordered.count
                ordered.append(snapshot)
            }
        }

        return ordered.map { snapshot in
            let current = reader(snapshot.path)
            switch (snapshot.previousText, current) {
            case (nil, nil):
                // 新建的文件已经没了：没什么可撤，但不假装撤过。
                return .conflict(path: snapshot.path, reason: .alreadyGone)
            case (nil, .some(let text)):
                guard AgentWriteSnapshot.digest(text) == snapshot.writtenDigest else {
                    return .conflict(path: snapshot.path, reason: .changedSinceWrite)
                }
                return .delete(path: snapshot.path)
            case (.some(let previous), nil):
                // 原来有、现在没了：两种可能 —— ① **这次任务自己删的**（快照里「写完之后」是空正文，
                // 许愿式编程的删除走这条路）⇒ 撤回 = 把前像还原；② 别处删的 ⇒ 不许凭空造回来。
                if snapshot.writtenDigest == AgentWriteSnapshot.digest("") {
                    return .restore(path: snapshot.path, text: previous)
                }
                return .conflict(path: snapshot.path, reason: .reappeared)
            case (.some(let previous), .some(let text)):
                guard AgentWriteSnapshot.digest(text) == snapshot.writtenDigest else {
                    return .conflict(path: snapshot.path, reason: .changedSinceWrite)
                }
                _ = text
                return .restore(path: snapshot.path, text: previous)
            }
        }
    }

    /// 落盘。返回（真撤了几条 / 冲突几条 + 冲突明细）。
    @discardableResult
    public static func apply(_ steps: [AgentRevertStep],
                             writer: (String, String?) throws -> Void) rethrows -> (applied: Int, conflicts: [AgentRevertStep]) {
        var applied = 0
        var conflicts: [AgentRevertStep] = []
        for step in steps {
            switch step {
            case .restore(let path, let text):
                try writer(path, text)
                applied += 1
            case .delete(let path):
                try writer(path, nil)
                applied += 1
            case .conflict:
                conflicts.append(step)
            }
        }
        return (applied, conflicts)
    }
}

/// 一轮任务里 Agent 写过的文件（`FR-STD-WS-EDIT-015` 的**采集端**）。
///
/// 只记「Agent 真写成功的那些写入」：审批没过、租约拿不到、基线过期的一律不记 ——
/// 没写成就没有「撤回」可言，记了反而会在撤回时误伤。
public final class AgentWriteBatchStore: @unchecked Sendable {

    public let runID: String
    private let lock = NSLock()
    private var snapshots: [AgentWriteSnapshot] = []

    public init(runID: String) { self.runID = runID }

    public func record(path: String, previousText: String?, writtenText: String) {
        lock.lock(); defer { lock.unlock() }
        snapshots.append(AgentWriteSnapshot(path: path,
                                            previousText: previousText,
                                            writtenDigest: AgentWriteSnapshot.digest(writtenText)))
    }

    /// 直接记一条现成的快照（`FR-STD-WS-AI-002` 验收时用：那时前像与「写完之后」的摘要
    /// 都已在暂存面里，再让调用方反推正文只会多一处拼错的机会）。
    public func record(_ snapshot: AgentWriteSnapshot) {
        lock.lock(); defer { lock.unlock() }
        snapshots.append(snapshot)
    }

    public var all: [AgentWriteSnapshot] {
        lock.lock(); defer { lock.unlock() }
        return snapshots
    }

    public var isEmpty: Bool { all.isEmpty }

    /// 算这一轮的撤回计划（纯函数，落盘由 `apply` 做）。
    public func plan(reader: (String) -> String?) -> [AgentRevertStep] {
        AgentWriteBatchRevert.plan(snapshots: all, reader: reader)
    }
}

// MARK: - 接线面：从「已应用的账」取批次（`FR-STD-WS-EDIT-015`）

extension AgentWriteBatchRevert {

    /// 把「已应用的账」映射成撤回原料。
    ///
    /// **账是唯一来源**：`FR-AI-25` ⑤ 的一步撤销与这里的整批撤回用的是同一份 `before`。
    /// 不为整批撤回另存一份前像 —— 两份前像迟早对不上，而界面上看不出哪一份是真的。
    public static func snapshots(from edits: [AgentAppliedEdit]) -> [AgentWriteSnapshot] {
        edits.map {
            AgentWriteSnapshot(path: $0.path,
                               previousText: $0.before,
                               writtenDigest: AgentWriteSnapshot.digest($0.after))
        }
    }

    /// 撤回**本身**的反向批次（验收 ③「撤回本身留痕且可再撤回」）。
    ///
    /// 撤完之后再撤一次 ⇒ 回到 Agent 写完的那一份。两条纪律：
    /// · **只对真会动盘的那几步生成** —— 冲突步不生成，否则「撤销这次撤回」会去改一个没被撤过的文件；
    /// · `reader` 取的是**落盘前**的正文（计划里"当前"的那一份）⇒ 这一步必须在 `apply` **之前**算。
    public static func inverse(of steps: [AgentRevertStep],
                               reader: (String) -> String?) -> [AgentWriteSnapshot] {
        steps.compactMap { step -> AgentWriteSnapshot? in
            switch step {
            case .restore(let path, let text):
                // 撤回把 `text` 写回盘上 ⇒ 反向 = 把当前那份（Agent 写的）还原。
                guard let current = reader(path) else { return nil }
                return AgentWriteSnapshot(path: path,
                                          previousText: current,
                                          writtenDigest: AgentWriteSnapshot.digest(text))
            case .delete(let path):
                // 撤回删掉 Agent 新建的文件 ⇒ 反向 = 把这个空位还原成当时那份。
                guard let current = reader(path) else { return nil }
                return AgentWriteSnapshot(path: path,
                                          previousText: current,
                                          writtenDigest: AgentWriteSnapshot.digest(""))
            case .conflict:
                return nil
            }
        }
    }
}

/// 一次整批撤回的**留痕**（`FR-STD-WS-EDIT-015` 验收 ③）。
///
/// 只记「这次撤了几条 / 哪几条没动 / 为什么 / 由哪几笔账算出来的」——
/// **不记正文**：正文在账上，回执里再存一份就等于第二份前像。
public struct AgentBatchRevertReceipt: Equatable, Sendable {

    /// 这一批里**没被撤**的那一条（人改过 / 已被删 / 又被造回来）。
    public struct Unmoved: Equatable, Sendable {
        public var path: String
        public var reason: AgentRevertConflict

        public init(path: String, reason: AgentRevertConflict) {
            self.path = path
            self.reason = reason
        }
    }

    public var batchID: UUID
    public var at: Date
    /// 真撤了几条（来自 `apply` 的读数，不是自己数的）。
    public var reverted: Int
    public var unmoved: [Unmoved]
    /// 这一次撤回覆盖了账上哪几笔（撤回后按它标已撤；「撤销这次撤回」按它还原可撤状态）。
    public var cardIDs: [UUID]

    public init(batchID: UUID, at: Date, reverted: Int, unmoved: [Unmoved], cardIDs: [UUID]) {
        self.batchID = batchID
        self.at = at
        self.reverted = reverted
        self.unmoved = unmoved
        self.cardIDs = cardIDs
    }

    public var total: Int { reverted + unmoved.count }
    /// 一条都没落下（含「这一批本来就是空的」以外的情况都由调用方先挡掉）。
    public var isClean: Bool { unmoved.isEmpty }

    /// **唯一生成口**：计数直接取 `apply` 回的那两个数，不在这里重算一遍
    /// （重算 = 第二个真相：落盘实际做了什么，只有 `apply` 知道）。
    public static func make(batchID: UUID,
                            at: Date,
                            result: (applied: Int, conflicts: [AgentRevertStep]),
                            cardIDs: [UUID]) -> AgentBatchRevertReceipt {
        let unmoved: [Unmoved] = result.conflicts.compactMap { step in
            if case .conflict(let path, let reason) = step { return Unmoved(path: path, reason: reason) }
            return nil
        }
        return AgentBatchRevertReceipt(batchID: batchID, at: at, reverted: result.applied,
                                       unmoved: unmoved, cardIDs: cardIDs)
    }
}

/// 整批撤回在界面上的三样读数（**只给界面看，不参与判定**）。
public struct AgentBatchRevertState: Equatable, Sendable {

    /// 这一批还能撤几个文件（按路径去重：同一文件改两次只算一个）。
    public var pending: Int
    /// 上一批的回执（留痕）；`nil` = 这一次会话还没撤过。
    public var receipt: AgentBatchRevertReceipt?
    /// 「撤销这次撤回」还能退几步（0 = 没有反向批次）。
    public var redoPending: Int
    /// 上一次撤回**整体失败**的机器码（写盘出错 / 路径越界）；`nil` = 没失败过。
    public var lastFailure: String?

    public init(pending: Int = 0,
                receipt: AgentBatchRevertReceipt? = nil,
                redoPending: Int = 0,
                lastFailure: String? = nil) {
        self.pending = pending
        self.receipt = receipt
        self.redoPending = redoPending
        self.lastFailure = lastFailure
    }
}
