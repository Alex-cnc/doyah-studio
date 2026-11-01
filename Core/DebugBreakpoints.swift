import Foundation

/// 断点的**唯一账本**（`FR-STD-WS-TOOL-003` 的界面半：断点面板 / 行号槽点一下都写这里）。
///
/// 三条口径：
/// 1. **行号 1 起**（与行号列、`DAPSession.setBreakpoints` 同口径）—— 0 或负数直接不收，
///    免得把「点歪了」写成一个永远命不中的断点；
/// 2. **按文件全路径分组**（DAP 的 `setBreakpoints` 就是按 source.path 分组的形状），
///    路径做 `/private/var` ↔ `/var` 之外的**只做首尾空白与重复斜杠归一**，不解析符号链接
///    （解析了反而会把用户眼里的两个名字并成一个）；
/// 3. **可顺序化**：`dapMap()` 的行号**升序**，这样同一次会话里发给适配器的字节是确定的
///    （判据能逐字对账，不用比集合）。
public struct DebugBreakpointSet: Equatable, Sendable {

    private var byPath: [String: Set<Int>] = [:]

    public init() {}

    /// 归一：去首尾空白、把重复斜杠压成一个。`nil`/空串 ⇒ `nil`（不该有断点）。
    public static func normalizedPath(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var squeezed = trimmed
        while squeezed.contains("//") { squeezed = squeezed.replacingOccurrences(of: "//", with: "/") }
        return squeezed
    }

    /// 点一下：有就删、没有就加。返回「点完之后这里有没有断点」。
    @discardableResult
    public mutating func toggle(path: String, line: Int) -> Bool {
        guard let path = Self.normalizedPath(path), line >= 1 else { return false }
        var lines = byPath[path] ?? []
        if lines.contains(line) {
            lines.remove(line)
            if lines.isEmpty { byPath.removeValue(forKey: path) } else { byPath[path] = lines }
            return false
        }
        lines.insert(line)
        byPath[path] = lines
        return true
    }

    /// 这一行有没有断点。
    public func contains(path: String, line: Int) -> Bool {
        guard let path = Self.normalizedPath(path) else { return false }
        return byPath[path]?.contains(line) ?? false
    }

    /// 某个文件的断点行号（升序）。
    public func lines(for path: String) -> [Int] {
        guard let path = Self.normalizedPath(path) else { return [] }
        return (byPath[path] ?? []).sorted()
    }

    /// 全清一个文件（文件被删 / 页签关闭时用）。
    public mutating func clear(path: String) {
        guard let path = Self.normalizedPath(path) else { return }
        byPath.removeValue(forKey: path)
    }

    public mutating func removeAll() { byPath.removeAll() }

    public var isEmpty: Bool { byPath.isEmpty }

    /// 断点总数（面板标题上那个数）。
    public var count: Int { byPath.values.reduce(0) { $0 + $1.count } }

    /// 发给适配器的形状：`[path: [升序行号]]`。**空集不进 map**（省得发一条空 setBreakpoints）。
    public func dapMap() -> [String: [Int]] {
        byPath.mapValues { $0.sorted() }
    }

    /// 面板里的清单：按路径字典序，行号升序；同一行只出现一次。
    public var listing: [(path: String, lines: [Int])] {
        byPath.keys.sorted().map { ($0, (byPath[$0] ?? []).sorted()) }
    }
}
