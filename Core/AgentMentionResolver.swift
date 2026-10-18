import Foundation

/// 把 `@` 提及真正变成上下文（`FR-AI-22` ① 的落地段）。
///
/// 与解析器分开的理由：解析是纯字符串活（可离线判据），**取内容要碰磁盘**。
/// 这里仍保持可测：读取动作由调用方以 `reader` / `lister` 注入，判据里给假实现，
/// App 里给真 `FileManager` —— 一份逻辑，两种用法，不各写一套。
public enum AgentMentionResolver {

    /// 一段读文件的结果。
    public struct FileRead: Equatable, Sendable {
        public enum Status: Equatable, Sendable {
            case ok
            /// 二进制（含 NUL 字节）—— **不把字节流塞给模型**。
            case binary
            case unreadable
        }
        public let text: String
        public let status: Status
        public init(text: String, status: Status) {
            self.text = text
            self.status = status
        }
    }

    /// 解析结果 → 上下文引用。返回值第二项是**没带上时的说法**（界面/日志要如实说）。
    public static func references(for result: AgentMentionParseResult,
                                  limits: AgentContextLimits = AgentContextLimits(),
                                  root: URL,
                                  reader: (String) -> FileRead,
                                  lister: (String) -> [String]) -> (references: [AgentContextReference], notes: [String]) {
        var refs: [AgentContextReference] = []
        var notes: [String] = []

        for mention in result.mentions {
            switch mention.kind {
            case .file:
                let read = reader(mention.path)
                switch read.status {
                case .ok:
                    refs.append(.file(path: mention.path, text: read.text))
                case .binary:
                    notes.append("@\(mention.raw)：二进制文件，未带内容")
                case .unreadable:
                    notes.append("@\(mention.raw)：读不到，未带内容")
                }
            case .directory:
                let entries = lister(mention.path)
                if entries.isEmpty {
                    notes.append("@\(mention.raw)：目录为空或读不到")
                } else {
                    refs.append(.directory(path: mention.path, entries: entries))
                }
            }
        }

        for issue in result.issues {
            switch issue.reason {
            case .outsideWorkspace: notes.append("@\(issue.raw)：不在工作区内，已拒绝")
            case .notFound: notes.append("@\(issue.raw)：没有这个文件/目录")
            case .typeMismatch: notes.append("@\(issue.raw)：类型不符")
            }
        }
        return (refs, notes)
    }

    /// 真的从磁盘读（App 用这一个）。
    ///
    /// **二进制判定**：头 4096 字节里出现 NUL 就当二进制 —— 模型读字节流既没用又贵。
    public static func fileReader(root: URL, maxCharacters: Int) -> (String) -> FileRead {
        return { path in
            let url = root.appendingPathComponent(path)
            guard let data = try? Data(contentsOf: url) else {
                return FileRead(text: "", status: .unreadable)
            }
            if data.prefix(4096).contains(0) {
                return FileRead(text: "", status: .binary)
            }
            guard var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                return FileRead(text: "", status: .unreadable)
            }
            if text.count > maxCharacters {
                // 这里**不标 truncated**（那是 `AgentContextAssembler` 的活），只先挡一次极端大小
                text = String(text.prefix(maxCharacters))
            }
            return FileRead(text: text, status: .ok)
        }
    }

    /// 真的列目录（排好序，只给名字）。
    public static func directoryLister(root: URL, maxEntries: Int) -> (String) -> [String] {
        return { path in
            let url = root.appendingPathComponent(path)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return [] }
            return Array(names.sorted().prefix(maxEntries))
        }
    }
}
