import Foundation

/// 结论里的对象名 → 可点的链接（`FR-STD-DB-DIAG-006` 判据 ②：「结论里的对象名可点击跳到对应节点」）。
///
/// ## 为什么切段是 Core 的纯函数
///
/// 判据要能机械复核「哪几个词被变成了链接、跳到哪」，而**渲染出来的 `Text` 读不回来**。
/// 于是把「这句话里哪些字是对象名」做成一个纯函数（`segments(in:targets:)`），
/// 面板只负责把 `target != nil` 的那些段包成链接，探针读的是同一份切段结果。
///
/// ## 匹配口径（三条，都是踩过形状之后定的）
///
/// 1. **长名优先**：`public.orders` 与 `orders` 同时在候选里时，先试长的 —— 否则
///    「结论里写的是 public.orders」会被切成「public.[orders]」，跳过去只剩半条身份。
/// 2. **边界必须是边界**：`orders` 不许在 `orders_archive` / `myorders` / `public.orders`
///    里被认出来（标识符字符 = 字母 / 数字 / `_` / `$` / `.`）。词中间切一刀，用户点的是
///    一个名字、跳过去是另一个对象 —— 比不给链接更坏。
/// 3. **大小写不敏感、显示原样**：库里叫 `Orders`、结论里写 `orders` 也该能点；
///    但显示的是**结论原文那一段**，不改写用户看到的话。
///
/// 候选集只放「已知身份」的对象（本片 = 被诊断的那一个，见 `DiagnosisScope.linkTargets`）：
/// 同名对象在不同库 / 不同 schema 都存在，凭一个词猜身份会跳到错的地方。
public enum DiagnosisObjectLinker {

    /// 链接的 URL scheme（面板把它交给 `OpenURLAction` 自己处理，绝不弹系统浏览器）。
    public static let scheme = "doyah-object"
    public static let host = "object"

    /// 可点的对象：类型 + 名字 + schema。
    public struct Target: Equatable, Hashable, Sendable {

        public var kind: DatabaseObject.Kind
        public var name: String
        public var schema: String?

        public init(kind: DatabaseObject.Kind, name: String, schema: String? = nil) {
            self.kind = kind
            self.name = name
            self.schema = schema
        }

        public var qualifiedName: String {
            guard let schema, !schema.isEmpty else { return name }
            return "\(schema).\(name)"
        }

        /// 链接文本形态：`doyah-object://object?kind=table&name=orders&schema=public`。
        ///
        /// 用 `URLComponents` 而不是手拼字符串：schema / 表名里可能有空格与中文，
        /// 手拼出来的串在 `URL(string:)` 上会直接变 `nil`（那么链接就静默失效）。
        public var url: URL? {
            var components = URLComponents()
            components.scheme = DiagnosisObjectLinker.scheme
            components.host = DiagnosisObjectLinker.host
            var items = [
                URLQueryItem(name: "kind", value: kind.rawValue),
                URLQueryItem(name: "name", value: name)
            ]
            if let schema, !schema.isEmpty {
                items.append(URLQueryItem(name: "schema", value: schema))
            }
            components.queryItems = items
            return components.url
        }

        public init?(url: URL) {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  components.scheme == DiagnosisObjectLinker.scheme,
                  components.host == DiagnosisObjectLinker.host,
                  let items = components.queryItems,
                  let kindRaw = items.first(where: { $0.name == "kind" })?.value,
                  let kind = DatabaseObject.Kind(rawValue: kindRaw),
                  let name = items.first(where: { $0.name == "name" })?.value,
                  !name.isEmpty
            else { return nil }
            self.init(
                kind: kind,
                name: name,
                schema: items.first(where: { $0.name == "schema" })?.value
            )
        }
    }

    /// 一段话切出来的一段：`target == nil` = 普通文字；非空 = 要变链接的对象名。
    public struct Segment: Equatable, Sendable {
        public var text: String
        public var target: Target?

        public init(text: String, target: Target? = nil) {
            self.text = text
            self.target = target
        }
    }

    /// 切段（纯函数）。
    public static func segments(in text: String, targets: [Target]) -> [Segment] {
        guard !text.isEmpty else { return [] }
        let patterns = patterns(for: targets)
        guard !patterns.isEmpty else { return [Segment(text: text)] }

        let characters = Array(text)
        var result: [Segment] = []
        var plain: [Character] = []
        var index = 0

        while index < characters.count {
            var hit: (length: Int, target: Target)?
            for pattern in patterns {
                let length = pattern.characters.count
                guard index + length <= characters.count else { continue }
                let candidate = String(characters[index ..< (index + length)]).lowercased()
                guard candidate == pattern.lowercased else { continue }
                let before: Character? = index > 0 ? characters[index - 1] : nil
                let afterIndex = index + length
                let after: Character? = afterIndex < characters.count ? characters[afterIndex] : nil
                if isBoundary(before), isBoundary(after) {
                    hit = (length, pattern.target)
                    break
                }
            }

            if let hit {
                if !plain.isEmpty {
                    result.append(Segment(text: String(plain)))
                    plain = []
                }
                result.append(Segment(
                    text: String(characters[index ..< (index + hit.length)]),
                    target: hit.target
                ))
                index += hit.length
            } else {
                plain.append(characters[index])
                index += 1
            }
        }

        if !plain.isEmpty { result.append(Segment(text: String(plain))) }
        return result
    }

    /// 带链接属性的富文本（面板直接交给 `Text(_:)`）。
    ///
    /// 只给对象名那几段装 `.link`；其余一个字都不动 —— 结论是模型写的话，
    /// 我们只加「可以点」这一件事，不改写、不加粗、不截断。
    public static func attributed(_ text: String, targets: [Target]) -> AttributedString {
        var output = AttributedString()
        for segment in segments(in: text, targets: targets) {
            var piece = AttributedString(segment.text)
            if let target = segment.target, let url = target.url {
                piece.link = url
            }
            output += piece
        }
        return output
    }

    /// 这段话里有没有可点的对象名（面板据此决定要不要出那句提示）。
    public static func hasLinks(in text: String, targets: [Target]) -> Bool {
        segments(in: text, targets: targets).contains { $0.target != nil }
    }

    // MARK: - 内部

    /// 候选模式：qualified 在前、裸名在后，按长度倒序；同一个（模式 + 身份）只留一份。
    private static func patterns(for targets: [Target]) -> [(characters: [Character], lowercased: String, target: Target)] {
        var seen = Set<String>()
        var raw: [(String, Target)] = []
        for target in targets {
            guard !target.name.isEmpty else { continue }
            if let schema = target.schema, !schema.isEmpty {
                raw.append(("\(schema).\(target.name)", target))
            }
            raw.append((target.name, target))
        }
        raw.sort { $0.0.count > $1.0.count }
        var patterns: [(characters: [Character], lowercased: String, target: Target)] = []
        for (pattern, target) in raw {
            let key = "\(pattern.lowercased())|\(target.kind.rawValue)|\(target.qualifiedName)"
            guard seen.insert(key).inserted else { continue }
            patterns.append((Array(pattern), pattern.lowercased(), target))
        }
        return patterns
    }

    /// 标识符字符：出现在对象名两侧时说明「这不是一个独立的词」。
    private static func isBoundary(_ character: Character?) -> Bool {
        guard let character else { return true }
        if character == "_" || character == "$" || character == "." { return false }
        return !(character.isLetter || character.isNumber)
    }
}
