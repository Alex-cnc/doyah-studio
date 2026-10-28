import Foundation

/// 一次许愿里**某个文件的改动**（`FR-STD-WS-AI-002` 验收要点 ①：交付前给出改动清单与差异）。
///
/// 差异复用 `AgentTextDiff`（审批单的差异预览与这里同一套切分）—— 不另写一套，
/// 否则「审批单上看到的」与「许愿清单上看到的」迟早两样。
public struct WishFileChange: Equatable, Sendable {

    public enum Kind: String, Equatable, Sendable {
        case created
        case modified
        case deleted
    }

    /// 相对工作区根的路径（与 `AgentWriteSnapshot.path` 同一口径，撤回时能直接对上）。
    public var path: String
    public var kind: Kind
    public var diff: [AgentTextDiff.Line]
    public var addedLines: Int
    public var removedLines: Int
    /// 暂存开始前盘上那份的摘要（`nil` = 本来不存在）。
    public var beforeDigest: String?
    /// 计划交付的那份的摘要（`nil` = 计划删掉）。
    public var afterDigest: String?

    public init(path: String,
                kind: Kind,
                diff: [AgentTextDiff.Line],
                addedLines: Int,
                removedLines: Int,
                beforeDigest: String?,
                afterDigest: String?) {
        self.path = path
        self.kind = kind
        self.diff = diff
        self.addedLines = addedLines
        self.removedLines = removedLines
        self.beforeDigest = beforeDigest
        self.afterDigest = afterDigest
    }
}

/// 暂存被拒的原因（**机器码**：展示文案由界面按语言表渲染，Core 不写死展示文本）。
public enum WishRejectReason: String, Equatable, Sendable {
    /// 路径不在工作区内（`../` 越界 / 绝对路径出根）。
    case outsideWorkspace
    /// 目标是目录，不是文件。
    case notAFile
    /// 盘上文件读不出正文（编码 / 权限）。
    case unreadable
    /// 要删的东西本来就不存在。
    case missingTarget
    /// 单个文件超过上限。
    case fileTooLarge
    /// 本轮改动文件数超过上限。
    case tooManyFiles
}

public struct WishRejection: Equatable, Sendable {

    public var path: String
    public var reason: WishRejectReason
    /// 机器面细节（越界解析出的绝对路径 / 上限数值），不是给人读的句子。
    public var detail: String

    public init(path: String, reason: WishRejectReason, detail: String = "") {
        self.path = path
        self.reason = reason
        self.detail = detail
    }
}

/// 验证结果（验收要点 ③：未通过验证的产出必须标明「没跑通」）。
public struct WishValidation: Equatable, Sendable {

    public var command: String
    public var exitCode: Int
    /// 输出尾部（界面折叠展示用；不参与判定）。
    public var outputTail: String

    public var passed: Bool { exitCode == 0 }

    public init(command: String, exitCode: Int, outputTail: String = "") {
        self.command = command
        self.exitCode = exitCode
        self.outputTail = outputTail
    }
}

/// 一次暂存动作的结果。
public enum WishStageOutcome: Equatable, Sendable {
    case staged(path: String, kind: WishFileChange.Kind)
    /// 与盘上逐字相同（或先写后删、先删后写回原样）⇒ **不算改动**，不进清单。
    case unchanged(path: String)
    case rejected(WishRejection)
}

/// 交付面（验收要点 ①③ + 红线「不是改完就生效」）。
public struct WishProposal: Equatable, Sendable {

    public enum State: String, Equatable, Sendable {
        /// 有改动、等验收（验证通过或尚未验证）。
        case awaitingAcceptance
        /// 一个改动都没有 —— 如实说「没改」，不编工作量。
        case noChanges
        /// 有改动但验证没跑通 ⇒ **必须标「没跑通」**，不许算交付。
        case validationFailed
    }

    public var runID: String
    public var root: String
    public var changes: [WishFileChange]
    public var rejections: [WishRejection]
    public var validation: WishValidation?
    public var state: State

    /// 清单摘要的**机器面**（计数由 Core 给，句子由界面按语言表拼）。
    public var addedTotal: Int
    public var removedTotal: Int
    public var createdCount: Int
    public var modifiedCount: Int
    public var deletedCount: Int

    /// 没验证过（`validation == nil`）不许当成「跑通了」——
    /// 界面据此把这一批显示成「未验证」，而不是默认成功。
    public var isValidationMissing: Bool { validation == nil }

    public init(runID: String,
                root: String,
                changes: [WishFileChange],
                rejections: [WishRejection],
                validation: WishValidation?,
                state: State) {
        self.runID = runID
        self.root = root
        self.changes = changes
        self.rejections = rejections
        self.validation = validation
        self.state = state
        self.addedTotal = changes.reduce(0) { $0 + $1.addedLines }
        self.removedTotal = changes.reduce(0) { $0 + $1.removedLines }
        self.createdCount = changes.filter { $0.kind == .created }.count
        self.modifiedCount = changes.filter { $0.kind == .modified }.count
        self.deletedCount = changes.filter { $0.kind == .deleted }.count
    }
}

/// 验收被挡住的原因。
public enum WishApplyBlock: String, Equatable, Sendable {
    case noChanges
    case validationFailed
}

public struct WishApplyResult: Equatable, Sendable {

    public var applied: [String]
    public var failed: [String]
    /// 落盘时记下的前像 —— 交给 `AgentWriteBatchRevert` 就能整批撤回（验收要点 ②）。
    public var snapshots: [AgentWriteSnapshot]
    /// 非 `nil` = **一个字节都没动**（没改动 / 验证没跑通而没强行验收）。
    public var block: WishApplyBlock?

    public init(applied: [String] = [],
                failed: [String] = [],
                snapshots: [AgentWriteSnapshot] = [],
                block: WishApplyBlock? = nil) {
        self.applied = applied
        self.failed = failed
        self.snapshots = snapshots
        self.block = block
    }

    public var didWriteAnything: Bool { !applied.isEmpty }
}

/// 许愿式编程（`FR-STD-WS-AI-002`）的**暂存面**：Agent 在整个工作区里多次读写，
/// 结果先落暂存、**不落磁盘**；交付前给出「改了哪些文件 + 逐行差异」，等人验收才写盘。
///
/// 四条口径（需求书 §3.3 验收要点 ①③ + 红线「不是改完就生效，一律先出改动、等人验收」）：
/// 1. **先出改动、后生效**：`stageWrite` / `stageDelete` 只动内存，磁盘只在 `accept` 被写一次；
/// 2. **清单与差异成对**：每个改动带相对路径 / 类别 / 逐行差异 / 增删行数，差异复用 `AgentTextDiff`；
/// 3. **没跑通要说没跑通**：验证非零退出 ⇒ `state = .validationFailed`，`accept` 默认拒绝；
/// 4. **只在工作区内**：路径越界一律进 `rejections`（复用 `AgentWorkspaceSandbox`，与真写同一套判定），
///    不进改动清单 —— 越界的东西既不该出现在「改了哪些文件」里，也不该有落盘路径。
///
/// 同一路径多次暂存：**只出最后一条改动、前像按暂存开始前那一份算**（否则差异会漏掉中间态）。
/// 先写后删（或写回盘上原文）⇒ 净效果为零 ⇒ `unchanged`，不进清单。
public final class WishStaging: @unchecked Sendable {

    public let root: URL
    public let runID: String
    /// 本轮最多几个文件有改动（超出的如实拒，不静默截断）。
    public let maxFiles: Int
    /// 单个文件的正文上限（字节）。
    public let maxFileBytes: Int

    private struct Entry {
        var path: String
        var before: String?
        var after: String?
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private var rejections: [WishRejection] = []
    private var validation: WishValidation?

    public init(root: URL,
                runID: String,
                maxFiles: Int = 64,
                maxFileBytes: Int = 512 * 1024) {
        self.root = root.standardizedFileURL
        self.runID = runID
        self.maxFiles = maxFiles
        self.maxFileBytes = maxFileBytes
    }

    // MARK: - 暂存（只动内存）

    /// 暂存一次写入（新建或覆盖）。**这里不写盘**。
    @discardableResult
    public func stageWrite(path: String, text: String) -> WishStageOutcome {
        switch AgentWorkspaceSandbox.resolve(path, in: root) {
        case .outside(let detail):
            return reject(WishRejection(path: path, reason: .outsideWorkspace, detail: detail))
        case .inside(let url):
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if exists, isDirectory.boolValue {
                return reject(WishRejection(path: relativePath(url), reason: .notAFile))
            }
            let bytes = text.utf8.count
            if bytes > maxFileBytes {
                return reject(WishRejection(path: relativePath(url),
                                            reason: .fileTooLarge,
                                            detail: "\(maxFileBytes)"))
            }
            var disk: String?
            if exists {
                guard let read = try? String(contentsOf: url, encoding: .utf8) else {
                    return reject(WishRejection(path: relativePath(url), reason: .unreadable))
                }
                disk = read
            }
            return upsert(Entry(path: relativePath(url), before: disk, after: text))
        }
    }

    /// 暂存一次删除。**这里不删盘**；删一个不存在的东西如实拒。
    @discardableResult
    public func stageDelete(path: String) -> WishStageOutcome {
        switch AgentWorkspaceSandbox.resolve(path, in: root) {
        case .outside(let detail):
            return reject(WishRejection(path: path, reason: .outsideWorkspace, detail: detail))
        case .inside(let url):
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if exists, isDirectory.boolValue {
                return reject(WishRejection(path: relativePath(url), reason: .notAFile))
            }
            let relative = relativePath(url)
            var disk: String?
            if exists {
                guard let read = try? String(contentsOf: url, encoding: .utf8) else {
                    return reject(WishRejection(path: relative, reason: .unreadable))
                }
                disk = read
            }
            // 盘上没有、本次也没暂存过它 ⇒ 没有可删的东西。
            if !exists, stagedEntry(relative) == nil {
                return reject(WishRejection(path: relative, reason: .missingTarget))
            }
            return upsert(Entry(path: relative, before: disk, after: nil))
        }
    }

    /// 记一次验证（验收要点 ③）。**只记读数，不跑命令** —— 跑命令是调用方的事。
    public func recordValidation(command: String, exitCode: Int, outputTail: String = "") {
        lock.lock(); defer { lock.unlock() }
        validation = WishValidation(command: command, exitCode: exitCode, outputTail: outputTail)
    }

    /// 丢掉整批暂存（对应界面的「算了，不要了」）。**盘上什么都没动过，所以这里是空操作**。
    public func discard() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll()
        order.removeAll()
        validation = nil
    }

    public var stagedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return entries.count
    }

    public var currentRejections: [WishRejection] {
        lock.lock(); defer { lock.unlock() }
        return rejections
    }

    // MARK: - 交付面（清单 + 差异 + 状态）

    public var proposal: WishProposal {
        let (list, rejected, recordedValidation) = snapshotForProposal()
        let changes = list.map { entry -> WishFileChange in
            let before = entry.before ?? ""
            let after = entry.after ?? ""
            let kind: WishFileChange.Kind
            if entry.before == nil {
                kind = .created
            } else if entry.after == nil {
                kind = .deleted
            } else {
                kind = .modified
            }
            // 「空前像」在 `AgentTextDiff` 的切行口径里是一行空行 —— 新建 / 删除时那不是
            // 「删掉了一行」/「加了一行空行」，按类别把对面那一侧滤掉，免得清单上出现假读数。
            let diff = AgentTextDiff.lines(before: before, after: after).filter { line in
                switch kind {
                case .created: return line.kind != .removed
                case .deleted: return line.kind != .added
                case .modified: return true
                }
            }
            return WishFileChange(path: entry.path,
                                  kind: kind,
                                  diff: diff,
                                  addedLines: diff.filter { $0.kind == .added }.count,
                                  removedLines: diff.filter { $0.kind == .removed }.count,
                                  beforeDigest: entry.before.map(AgentWriteSnapshot.digest),
                                  afterDigest: entry.after.map(AgentWriteSnapshot.digest))
        }
        let state: WishProposal.State
        if changes.isEmpty {
            state = .noChanges
        } else if let recordedValidation, !recordedValidation.passed {
            state = .validationFailed
        } else {
            state = .awaitingAcceptance
        }
        return WishProposal(runID: runID,
                            root: root.path,
                            changes: changes,
                            rejections: rejected,
                            validation: recordedValidation,
                            state: state)
    }

    // MARK: - 验收（唯一写盘点）

    /// 验收并落盘。**验证没跑通时默认拒绝**（`allowFailedValidation` 只有界面在明确
    /// 「我知道没跑通，仍要装上去」时才传 `true`，且那不是「交付成功」）。
    @discardableResult
    public func accept(allowFailedValidation: Bool = false) -> WishApplyResult {
        let proposal = self.proposal
        if proposal.changes.isEmpty {
            return WishApplyResult(block: .noChanges)
        }
        if proposal.state == .validationFailed, !allowFailedValidation {
            return WishApplyResult(block: .validationFailed)
        }

        let list = snapshotForProposal().list
        var applied: [String] = []
        var failed: [String] = []
        var snapshots: [AgentWriteSnapshot] = []
        let manager = FileManager.default
        for entry in list {
            let target = root.appendingPathComponent(entry.path)
            do {
                if let after = entry.after {
                    let parent = target.deletingLastPathComponent()
                    if !manager.fileExists(atPath: parent.path) {
                        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
                    }
                    try after.write(to: target, atomically: true, encoding: .utf8)
                } else if manager.fileExists(atPath: target.path) {
                    try manager.removeItem(at: target)
                }
                applied.append(entry.path)
                snapshots.append(AgentWriteSnapshot(path: entry.path,
                                                    previousText: entry.before,
                                                    writtenDigest: AgentWriteSnapshot.digest(entry.after ?? "")))
            } catch {
                // 一个文件写不成不牵连别的：它留在暂存里（下次还能再试），失败路径如实点名。
                failed.append(entry.path)
            }
        }

        lock.lock()
        for path in applied {
            entries.removeValue(forKey: path)
            order.removeAll { $0 == path }
        }
        lock.unlock()

        return WishApplyResult(applied: applied, failed: failed, snapshots: snapshots, block: nil)
    }

    // MARK: - 与整批撤回的接口（验收要点 ②）

    /// 把这次验收记成**一个写入批次** —— 之后「改坏了」可以按 `AgentWriteBatchRevert` 整批撤回，
    /// 人在这之后又改过的文件一律判 `conflict`、一个字都不动。
    ///
    /// 由这里构造而不是让调用方自己拼 `AgentWriteSnapshot`：拼错一处（比如把
    /// `previousText` 记成写完后的正文）撤回就会**静默改坏文件**。
    public static func batchStore(runID: String, result: WishApplyResult) -> AgentWriteBatchStore {
        let store = AgentWriteBatchStore(runID: runID)
        for snapshot in result.snapshots {
            store.record(snapshot)
        }
        return store
    }

    // MARK: - 内部

    private func reject(_ rejection: WishRejection) -> WishStageOutcome {
        lock.lock(); defer { lock.unlock() }
        rejections.append(rejection)
        return .rejected(rejection)
    }

    private func stagedEntry(_ relative: String) -> Entry? {
        lock.lock(); defer { lock.unlock() }
        return entries[relative]
    }

    /// 同一路径多次暂存：前像取**暂存开始前**那一份；净效果为零就撤掉这条。
    private func upsert(_ entry: Entry) -> WishStageOutcome {
        lock.lock(); defer { lock.unlock() }
        var merged = entry
        if let existing = entries[entry.path] {
            merged.before = existing.before
        } else if entries.count >= maxFiles {
            let rejection = WishRejection(path: entry.path,
                                          reason: .tooManyFiles,
                                          detail: "\(maxFiles)")
            rejections.append(rejection)
            return .rejected(rejection)
        }
        if merged.before == merged.after {
            if entries.removeValue(forKey: merged.path) != nil {
                order.removeAll { $0 == merged.path }
            }
            return .unchanged(path: merged.path)
        }
        if entries[merged.path] == nil { order.append(merged.path) }
        entries[merged.path] = merged
        let kind: WishFileChange.Kind
        if merged.before == nil {
            kind = .created
        } else if merged.after == nil {
            kind = .deleted
        } else {
            kind = .modified
        }
        return .staged(path: merged.path, kind: kind)
    }

    private func snapshotForProposal() -> (list: [Entry], rejections: [WishRejection], validation: WishValidation?) {
        lock.lock(); defer { lock.unlock() }
        let list = order.compactMap { entries[$0] }
        return (list, rejections, validation)
    }

    private func relativePath(_ url: URL) -> String {
        let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
        if url.path == root.path { return url.lastPathComponent }
        return url.path.hasPrefix(base) ? String(url.path.dropFirst(base.count)) : url.lastPathComponent
    }
}
