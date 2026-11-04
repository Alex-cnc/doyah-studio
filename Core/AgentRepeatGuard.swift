import Foundation

/// **同一条调用不许在一轮里反复做**（提示词那条规矩的机械落地）。
///
/// 由头（2026-11-04 真机 · QQ 派活那一轮）：问了句「QQ 通道是通的吗」，助手在 13 分钟里
/// 发了 78 次模型请求、324 次工具调用，其中 **同一个文件被 `read_file` 读了 18 次**、
/// `list_dir Core` 14 次、`list_dir .` 10 次 —— 而系统提示词第 5 条早就写着
/// 「同一个查询（同工具 + 同参数）不许重复第三次」（`Core/AgentSystemPrompt.swift:57`）。
///
/// 也就是说：**规矩只在提示词里，循环不检查**。模型对「结果还在上文」没有记忆压力时，
/// 就会一遍遍重来，而每一次都是 9 秒左右的模型等待 + 一整段 token。
///
/// 这一层把那条规矩变成**可执行、可测**的闸：
/// - 只读三件（`read_file` / `list_dir` / `search`）记账；
/// - 同一 (工具, 参数) 在窗口内**第 3 次**开始不执行，回一句能照做的话给模型；
/// - 任何写 / 执行（`write_file` / `edit*` / `run_command`）**清空账本** ——
///   「写完再看一眼」是正当行为，不许被这道闸误挡。
public final class AgentRepeatGuard: @unchecked Sendable {

    /// 只记账的三件只读能力（按**能力**判，不按名字 —— 工具名字面量只许出现在登记表里）。
    public static let watched: Set<AgentToolCapability> = [.readFile, .listDirectory, .search]
    /// 写 / 执行类：出现即作废账本（磁盘变了，之前那份读结果不再可信）。
    public static let mutating: Set<AgentToolCapability> = [.writeFile, .editFile, .runCommand]

    public struct Policy: Equatable, Sendable {
        /// 窗口：这么久之内的重复才算「同一轮里在原地打转」。
        public var window: TimeInterval
        /// 允许的次数（第 `limit + 1` 次开始拒）。
        public var limit: Int

        public init(window: TimeInterval = 180, limit: Int = 2) {
            self.window = window
            self.limit = limit
        }
    }

    private struct Entry {
        var count: Int
        var firstAt: Date
    }

    public let policy: Policy
    private var entries: [String: Entry] = [:]
    private let lock = NSLock()

    public init(policy: Policy = Policy()) {
        self.policy = policy
    }

    /// 记一次调用；返回 `nil` = 放行（照常执行），返回一句话 = **不执行**，把这句回灌给模型。
    ///
    /// 回灌的话要**能照着做**（「换个问法 / 直接给结论」），不是一句「被拒了」。
    public func admit(capability: AgentToolCapability, tool: String,
                      arguments: String, at now: Date = Date()) -> String? {
        lock.lock()
        defer { lock.unlock() }

        if Self.mutating.contains(capability) {
            entries.removeAll()
            return nil
        }
        guard Self.watched.contains(capability) else { return nil }

        // 参数归一（键序 / 空白不同但语义相同的两次调用算同一条）。
        let key = "\(capability.rawValue)|\(Self.canonical(arguments))"
        var entry = entries[key]
        if let existing = entry, now.timeIntervalSince(existing.firstAt) > policy.window {
            entry = nil                                   // 过期：重新起算
        }
        let count = (entry?.count ?? 0) + 1
        entries[key] = Entry(count: count, firstAt: entry?.firstAt ?? now)
        guard count > policy.limit else { return nil }

        return "repeat-call: 同一条 \(tool)（同参数）本轮已经做过 \(policy.limit) 次，"
            + "结果就在上面的对话里，本次不再执行。换个问法 / 换个路径，或者直接用已有结果给结论。"
    }

    /// 这一轮已经记了几条（读数口：面板 / 日志要能说「拦掉了几次」）。
    public var trackedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return entries.count
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll()
    }

    /// 参数归一：解析成对象后按键排序重新序列化；解析不了就压掉空白。
    static func canonical(_ arguments: String) -> String {
        let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let normalized = try? JSONSerialization.data(withJSONObject: object,
                                                           options: [.sortedKeys]),
              let text = String(data: normalized, encoding: .utf8) else {
            return trimmed.split(whereSeparator: { $0.isWhitespace }).joined()
        }
        return text
    }
}
