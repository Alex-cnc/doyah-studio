import Foundation

/// 一次「正在写某个文件」的租约（`FR-AI-31` ①）。
///
/// 为什么要租约而不是全局大锁：并发写冲突只发生在**同一文件**上，
/// 按文件串行化就不会让「两次无关的写」互相排队（判据第 ③ 条：并发读不受影响）。
public struct AgentWriteLease: Equatable, Sendable {
    /// 归一化后的**绝对路径**（同一个文件的不同写法会归到同一个键）。
    public let path: String
    /// 谁握着（同一次调用一个号 ⇒ 只有持有者能还回租约，别人还不掉）。
    public let token: String
    public let startedAt: Date

    public init(path: String, token: String, startedAt: Date = Date()) {
        self.path = path
        self.token = token
        self.startedAt = startedAt
    }
}

/// 「谁正在写哪个文件」的**唯一台账**（`FR-AI-31` ①）。
///
/// 三条纪律：
/// · **不排队**：第二次写拿不到租约就**立刻如实说**「已有写入在进行」——
///   排队会把「并发」变成「静默等一会儿」，用户看不到、模型也不知道自己被挡过；
/// · **只锁写**：读路径完全不经过这里（不引入全局大锁，也不让读变慢）；
/// · **按文件**：不同文件的写互不影响。
public final class AgentWriteCoordinator: @unchecked Sendable {

    /// 同一进程里所有工具实例共用的那一本账。
    ///
    /// 为什么要共享：`AgentWorkspaceTools` 是**每轮现造**的值类型（宿主每次调用都 new 一个），
    /// 台账如果长在实例上就永远只有自己一个持有者 —— 并发写抓不到。
    public static let shared = AgentWriteCoordinator()

    private let lock = NSLock()
    private var holders: [String: AgentWriteLease] = [:]

    public init() {}

    /// 拿租约。已被别人握着 ⇒ `nil`（**不排队、不重试**）。
    public func acquire(path: String, token: String = UUID().uuidString,
                        at: Date = Date()) -> AgentWriteLease? {
        let key = Self.normalize(path)
        lock.lock()
        defer { lock.unlock() }
        guard holders[key] == nil else { return nil }
        let lease = AgentWriteLease(path: key, token: token, startedAt: at)
        holders[key] = lease
        return lease
    }

    /// 还租约。**只许持有者还**（token 对不上 ⇒ 不动，返回 false）。
    @discardableResult
    public func release(_ lease: AgentWriteLease) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard holders[lease.path]?.token == lease.token else { return false }
        holders.removeValue(forKey: lease.path)
        return true
    }

    /// 这个文件此刻有没有人正在写。
    public func isWriting(path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return holders[Self.normalize(path)] != nil
    }

    /// 正在写的文件（绝对路径，已排序 —— 排查与判据都读这一格）。
    public var activePaths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return holders.keys.sorted()
    }

    /// 一次写：**拿到租约才跑**；拿不到就回 `.busy`，一行都不写。
    public func withLease<T>(path: String, _ body: (AgentWriteLease) throws -> T) rethrows -> (value: T?, conflict: String?) {
        guard let lease = acquire(path: path) else { return (nil, AgentWriteGate.busy) }
        defer { release(lease) }
        return (try body(lease), nil)
    }

    /// 路径归一化：同一个文件的不同写法（相对 / 绝对 / `..`）落成同一个键。
    static func normalize(_ path: String) -> String {
        if path.hasPrefix("/") { return URL(fileURLWithPath: path).standardizedFileURL.path }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(path).standardizedFileURL.path
    }
}

/// 拿不到租约时的机器码（人话在界面翻；Core 不写死人话）。
public enum AgentWriteGate {
    /// 已有写入在进行。
    public static let busy = "writeConflict"
}

/// 写入目标的**基线状态**（`FR-AI-31` ①：批准之后目标被改过 ⇒ 不拿旧审批盖新内容）。
///
/// 为什么要一个「状态串」而不是只存正文：审批单要能**跨进程 / 跨轮**存活（卡片上只带一串），
/// 而正文可能很大 —— 存摘要就够：**同一份正文 ⇒ 同一串**，被改过一个字节就不同。
public enum AgentWriteTargetState {

    /// 目标不存在（新建文件）。
    public static let absent = "absent"
    /// 目标存在但读不出来（二进制 / 无权限）—— 与「不存在」分开：那两件事的处置不一样。
    public static let unreadable = "unreadable"

    /// 此刻盘上这份文件的基线串。**唯一一处实现**（审批出单与临写前复核共用 ⇒ 不会两边对不上）。
    public static func digest(at url: URL) -> String {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return absent
        }
        // 目标是个目录：不当「不存在」，也不当「可写」—— 它有自己的拒码（`notAFile`）。
        guard !isDirectory.boolValue, let text = try? String(contentsOf: url, encoding: .utf8) else {
            return unreadable
        }
        return "content:" + AgentFingerprint.hash(text)
    }
}
