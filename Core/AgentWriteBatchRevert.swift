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
        // 同一路径多次写入：只留最后一次的前像（撤回到本轮开始前）。
        var ordered: [AgentWriteSnapshot] = []
        var indexByPath: [String: Int] = [:]
        for snapshot in snapshots {
            if let index = indexByPath[snapshot.path] {
                ordered[index] = snapshot
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
