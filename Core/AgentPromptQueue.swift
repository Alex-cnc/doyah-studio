import Foundation

/// 一条**排队中的提问**。
public struct AgentQueuedPrompt: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var text: String

    public init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

/// 提问队列：`/queue` 的同义物（macOS 侧没有斜杠命令，用界面表达同一件事）。
///
/// 语义照 Hermes CLI 的 `_pending_input`：
/// · 一轮还在跑时提交的提问**不丢、不打断**，排进 FIFO，这一轮结束后**按序**接着跑；
/// · 队列归客户端所有，`AgentLoop` 完全不知道它的存在 —— 所以它不依赖任何平台能力，
///   macOS / Windows / Linux 三端都能有，且行为一致；
/// · 空串不入队（否则会跑出一轮没有提问的回合）。
public struct AgentPromptQueue: Equatable, Sendable {

    public private(set) var items: [AgentQueuedPrompt] = []

    public init(items: [AgentQueuedPrompt] = []) {
        self.items = items
    }

    public var count: Int { items.count }
    public var isEmpty: Bool { items.isEmpty }

    /// 入队；空白串拒收（返回 `nil`，调用方据此提示「没排队」）。
    @discardableResult
    public mutating func enqueue(_ text: String) -> AgentQueuedPrompt? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let item = AgentQueuedPrompt(text: trimmed)
        items.append(item)
        return item
    }

    /// 取队首（出队）。空队列返回 `nil`。
    public mutating func dequeue() -> AgentQueuedPrompt? {
        guard !items.isEmpty else { return nil }
        return items.removeFirst()
    }

    public mutating func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    /// 1 起算的下标（与界面上显示的序号一致）；越界静默不动。
    public mutating func remove(at index: Int) {
        guard index >= 1, index <= items.count else { return }
        items.remove(at: index - 1)
    }

    public mutating func edit(id: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].text = trimmed
    }

    /// 按 id 上移 / 下移（界面上那两枚 ↑ ↓）：**纯函数**，返回新队列，不原地改。
    ///
    /// 为什么不做成 `mutating func move(id:offset:)`：界面每枚按钮都要先算「移完是什么样」
    /// 才决定要不要画（第一行不给 ↑、最后一行不给 ↓）—— 纯函数让「算」和「改」用同一份逻辑，
    /// 不会出现「按钮说能移、真移了没动」。
    ///
    /// 边界一律**夹紧**而不是静默丢弃：第一行再上移 = 留在第一行（按钮本来就该禁用，夹紧只是兜底）。
    public func moving(id: UUID, offset: Int) -> AgentPromptQueue {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return self }
        let target = min(max(index + offset, 0), items.count - 1)
        guard target != index else { return self }
        var copy = items
        let item = copy.remove(at: index)
        copy.insert(item, at: target)
        return AgentPromptQueue(items: copy)
    }

    /// 调序：`from` / `to` 均为 1 起算。越界或原地不动都静默。
    public mutating func move(from: Int, to: Int) {
        guard from >= 1, from <= items.count, to >= 1, to <= items.count, from != to else { return }
        let item = items.remove(at: from - 1)
        items.insert(item, at: to - 1)
    }

    public mutating func clear() {
        items.removeAll()
    }

    /// 界面上那一行预览：**折成单行**再截断（多行提问在列表里会撑破一行的高度）。
    public static func preview(_ text: String, limit: Int = 80) -> String {
        let single = text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard single.count > limit else { return single }
        return String(single.prefix(limit)) + "…"
    }
}
