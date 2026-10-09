import Foundation

/// 笔记正文的**权威源与投影**。
///
/// **2026-10-08 改版（片 `WY-1a` · 派单 `T-20261009-029` / `T-20261008-050`；依据 `DR-09` 第三改 /
/// `FR-RT-10` / `FR-RT-11` / 概要设计 `ADR-11`）**：权威源从 v1 的「Markdown + 样式旁挂」
/// **切到 v2 的 span 树**（`{version: 2, spans: [...]}`）。从此：
///   · **`spans` 是权威源** —— 一篇笔记的正文以它为准；
///   · **`body`（Markdown 文本）降为单向投影** —— 由 `spans` 派生（`body` / 兼容别名 `markdown`
///     都是 `NoteBodyProjection.markdown(from:)` 的产物），**不反向回写**（改文本不会回改 spans 的语义）；
///   · 落库侧：`note` 表新增 **`spans` 列**（schema v8），正文的**单一写入口** = `NoteDatabase.setNoteSpans`；
///     **交换面不变** —— JSON 备份格式仍走纯文本 `body`（`Note.body`），不塞富文本结构。
///
/// **v1 → v2 的迁移规则**（`NoteBody.migrated()`）：
///   · 旧文档（`{version: 1, markdown, sidecar}`）仍可**反序列化**（`NoteSidecarStyle` 兼容）；
///   · 迁移把 v1 的「Markdown + 旁挂」投影成 v2 的 spans —— **旁挂里的颜色 / 字号会被搬到 span 上，
///     不许静默丢**（搬不动的那几条由 `NoteBodyProjection.project(_:sidecar:language:)` 如实报降级）；
///   · 更高版本如实拒绝（`MigrationError.fromFuture`）。
///
/// 「支持的子集刻意很小」这条 v1 口径**一字未改**：粗体 `**x**`、斜体 `*x*`、行内代码 `` `x` ``、
/// 链接 `[文字](目标)`（2026-10-01 第 146 轮补，队列 `L-137` 剩余③ —— 人类主人答「#2，进」）；
/// 行内颜色与字号 Markdown 表达不了 → 落 span 的 `color` / `size`；
/// 其余 Markdown 语法（标题、列表、表格…）**原样当纯文本搬运**，不解析也不破坏 ——
/// 这保证了「AI 写进来的 Markdown 不会被我们改坏」。
/// **链接刻意只到「目标」为止**：它是不是能加载的地址、该开在哪儿，都不在这一层判
/// （前者是浏览器那条唯一入口，后者是契约「默认开在已内嵌的浏览器页签里」）。
public enum NoteBodyFormat {
    /// 权威源的版本号：结构变了才升，并必须给出迁移规则（Q8 的硬要求）。
    /// **v1 → v2**：权威源 Markdown + 旁挂 → `spans`（片 `WY-1a`）。
    public static let currentVersion = 2
}

/// 旁挂样式：v1 权威源里承载 **Markdown 表达不了**的属性（颜色 / 字号）的那一半，
/// 按「文本 + 第几次出现」定位。
///
/// v2 起旁挂**不再是权威源的一部分**（颜色 / 字号直接落在 span 上）；这个类型只作为 **v1 的反序列化面**
/// 保留 —— 老文档里的那一段 JSON 仍要认得出来，且**不许静默丢**（见 `NoteBody.migrated()`）。
///
/// 为什么用「文本 + 序号」而不是偏移量：偏移量在 AI 改写后会整体失效（一改就全错位），
/// 而「这段文字 + 它是第几次出现」在人改、AI 改之后**仍大概率对得上**；对不上就如实降级（见 `project`）。
public struct NoteSidecarStyle: Codable, Equatable, Sendable {
    public var text: String
    /// 同一段文字在一篇笔记里出现的次序（从 0 开始）。
    public var occurrence: Int
    /// `#RRGGBB`。
    public var color: String?
    /// 字号（缺省 nil = 跟随主题）。
    public var size: Int?

    public init(text: String, occurrence: Int = 0, color: String? = nil, size: Int? = nil) {
        self.text = text
        self.occurrence = occurrence
        self.color = color
        self.size = size
    }
}

/// 任意 JSON 值（保真用）：`NoteSpan` 里**不认得**的字段原样装在这里，**往返不丢**。
///
/// 这是前向兼容的地基：契约 v1.27 之后会给 span 加字段（`link` / `code` …），老版本读新数据
/// 再写回时**不许把这些字段丢掉**（片 `WY-1a` 明文：本片不新增那两个字段，但模型要留得住）。
public enum NoteJSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([NoteJSONValue])
    case object([String: NoteJSONValue])
}

extension NoteJSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() { self = .null; return }
        if let value = try? single.decode(Bool.self) { self = .bool(value); return }
        if let value = try? single.decode(Double.self) { self = .number(value); return }
        if let value = try? single.decode(String.self) { self = .string(value); return }
        if let value = try? single.decode([NoteJSONValue].self) { self = .array(value); return }
        if let value = try? single.decode([String: NoteJSONValue].self) { self = .object(value); return }
        throw DecodingError.dataCorruptedError(in: single, debugDescription: "unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var single = encoder.singleValueContainer()
        switch self {
        case .null: try single.encodeNil()
        case .bool(let value): try single.encode(value)
        case .number(let value): try single.encode(value)
        case .string(let value): try single.encode(value)
        case .array(let value): try single.encode(value)
        case .object(let value): try single.encode(value)
        }
    }
}

/// 权威源 **v2**：`{version, spans}` —— 一篇笔记的正文以 **span 树**为准。
///
/// `body` / `markdown` 都是**单向投影**（由 `spans` 派生，见类型头部注释），**不是**存储字段。
public struct NoteBody: Codable, Equatable, Sendable {
    /// 权威源的版本号（`NoteBodyFormat.currentVersion`）。
    public var version: Int
    /// **权威源**：正文的 span 树（v2 起）。
    public var spans: [NoteSpan]

    public init(version: Int = NoteBodyFormat.currentVersion, spans: [NoteSpan] = []) {
        self.version = version
        self.spans = spans
    }

    /// **v1 兼容构造**：`markdown` + `sidecar` 是 v1 的权威源 —— 当场按 1→2 规则投影成 v2 的 `spans`。
    /// **旁挂里的颜色 / 字号会被搬到 span 上（不静默丢）**；搬不动的那些交给
    /// `NoteBodyProjection.project(_:sidecar:language:)` 由调用方按语言如实报降级。
    public init(version: Int = NoteBodyFormat.currentVersion, markdown: String, sidecar: [NoteSidecarStyle] = []) {
        self.version = version
        self.spans = NoteBodyProjection.spans(fromMarkdown: markdown, sidecar: sidecar)
    }

    /// **单向投影**：由 `spans` 派生的 Markdown 正文 —— **不是存储字段，也不反向回写**。
    /// 落库的 `note.body` 列 = 它的产物；改这段文本不会回改 `spans`（spans 仍是权威源）。
    public var body: String { NoteBodyProjection.markdown(from: spans) }

    /// 兼容别名：v1 时代这个读点叫 `markdown`（= 同一份投影）。
    public var markdown: String { body }

    /// 版本迁移：**只认自己认识的版本**，更高的版本如实拒绝（不猜、不静默降级）。
    public enum MigrationError: Error, Equatable {
        case fromFuture(Int)
    }

    /// **1→2 规则**：v1 的「Markdown + 旁挂」在**解码 / 构造**时已经投影成 `spans`
    /// （旁挂的颜色 / 字号那一步就搬到了 span 上 —— 见 `init(markdown:sidecar:)` 与 `init(from:)`）；
    /// 这里把版本号落到 `currentVersion`。更高的版本如实拒绝。
    public func migrated() throws -> NoteBody {
        guard version <= NoteBodyFormat.currentVersion else {
            throw MigrationError.fromFuture(version)
        }
        var copy = self
        copy.version = NoteBodyFormat.currentVersion
        return copy
    }
}

extension NoteBody {
    private enum CodingKeys: String, CodingKey {
        case version, spans
        /// v1 的两个键（只在解码时出现；`body` 是更早的旧名，一并对上）。
        case markdown, body, sidecar
    }

    /// **可解 v1 也可解 v2**：有 `spans` 走 v2；否则按 v1 的 `markdown`（或旧名 `body`）+ `sidecar`
    /// 经 1→2 规则投影成 spans。**更高版本不在这里拒** —— 版本门在 `migrated()`（与 v1 同口径）。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        if let spans = try container.decodeIfPresent([NoteSpan].self, forKey: .spans) {
            self.spans = spans
        } else {
            let markdown = try container.decodeIfPresent(String.self, forKey: .markdown)
                ?? container.decodeIfPresent(String.self, forKey: .body)
                ?? ""
            let sidecar = try container.decodeIfPresent([NoteSidecarStyle].self, forKey: .sidecar) ?? []
            spans = NoteBodyProjection.spans(fromMarkdown: markdown, sidecar: sidecar)
        }
    }

    /// **只写权威源**：`{version, spans}`（`body` / `markdown` 是派生投影，不落 JSON）。
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(spans, forKey: .spans)
    }
}

/// **canonical JSON（确定性序列化）** —— 正文落库 / 交换面的**唯一**序列化配置。
///
/// 片 `云-编码canonical`（前置 `云D` `t_806b2f9f`；依据前门裁 `T-20261009-134` §二「序列化确定性」·
/// 读数出处 `云E` `t_571c7e65` · `cloud-sync/格式自证-macOS.md` §三.5 / §四）。三条口径：
///   · **B1 键序**：JSON 对象键按**字典序升序**（Swift `JSONEncoder.OutputFormatting.sortedKeys`）；
///   · **B2 空白**：**紧凑**输出（不加 `.prettyPrinted` —— 这一份是机器比对 / 附件 `sha256` 的载体，
///     不是给人读的）；与同族两处**逐条同源**：元数据面 `NoteStore.save`（`Core/Note.swift`）与
///     云端行面 `CloudSyncService.encoder()`（`Core/NoteSync/CloudSyncService.swift`）都带这两条 flag；
///   · **B5 `/`**：**不转义**（`.withoutEscapingSlashes`）—— 同上两处也是不转义。
///
/// 为什么必须定住：`云E` 实测**默认 `JSONEncoder()` 的键序跨进程不保序** —— 同一份正文两次运行
/// 给出**不同字节**（RUN A ≠ RUN B，同进程非首次编码亦未必相同）；而跨端互验与附件 `sha256` /
/// 冲突判定都以「同一输入 ⇒ 同一字节」为前提（裁定第 2 条原文）。
///
/// **两处刻意不在这里定（不是漏定）**：
///   · **B4 时间**：`NoteBody` 面**没有 `Date` 字段**（`version` 是 `Int`，`spans` 全是字符串 /
///     整数 / 布尔）⇒ 这一份不需要日期策略。时间只出现在**元数据面**（`NoteStore.save` 的
///     `.iso8601`）与**同步行面**（`CloudSyncService.encoder()` 的 UTC ISO8601），各在那一处定；
///   · **B6 字段名**：由各自的 `CodingKeys` 负责（本面是 `version` / `spans`，本片**未改**）。
///
/// 定义落在**编解码面自己身上**（而不是某一个调用点）：本文件头部那条「`NoteBody` 的编解码面 =
/// 交换面，**不另起一套序列化**」—— 写入口（`AppState.encodedSpans`）、单测、探针取的都该是**这一条**，
/// 免得三处各定一套（同一件事有两套口径，跨端一读就分家）。
public enum NoteBodyCanonical {
    /// canonical 编码器：键按字典序、紧凑、`/` 不转义。
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// 正文权威源的 **canonical JSON 文本** —— 落库 `note.spans` 列 / 上行 `content` 用的就是这一条。
    public static func json(_ body: NoteBody) throws -> String {
        String(decoding: try encoder().encode(body), as: UTF8.self)
    }
}

/// 交换面上 span 的 **`type` 字段取值**（片 `WY-1b2` · 契约 v1.30 §2.4 / §3.3）。
///
/// **这是契约字面量的唯一出处**：三档块级类型写进交换面 / 备份 / 跨端传输时**必须**逐字是
/// `LIST_ORDERED` / `LIST_UNORDERED` / `LIST_CHECKBOX` —— 各端**不许自定义交换字段名**
/// （契约 §2.4 不变量④：「内部模型可异、交换形态必须同形」）。
///
/// 为什么单出一份而不是把 Swift 内部名（`ordered` / `bullet` / `task`）直接写进 JSON：
/// 那样同一件事就有了两套命名，跨端一读就分家 —— 契约那条硬话钉的正是这一点。
public enum NoteSpanType: String, Equatable, Sendable {
    /// 有序编号列表项（块级）。编号由**渲染层**按相邻同类 span 顺序生成，不落库（契约 §3.3 / 不变量⑤）。
    case listOrdered = "LIST_ORDERED"
    /// 无序编号列表项（块级）。渲染为圆点，同上。
    case listUnordered = "LIST_UNORDERED"
    /// 勾选框（任务项，块级）。勾选状态 = 本 span 的 `checked` 字段。
    case listCheckbox = "LIST_CHECKBOX"
}

/// span 树（编辑器渲染用）：一段文字 + 它带的样式 +（链接才有）目标。
///
/// **可编解码，且留得住不认得的字段**：JSON 里出现 `knownFieldNames` 之外的键时原样进
/// `unknownFields`，再写回时一并带出 —— 契约 v1.27 之后会加 `link` / `code` 等字段，
/// 老版本读新数据**不许把它们丢掉**（片 `WY-1a` 的判据 ③）。
public struct NoteSpan: Equatable, Sendable {
    public enum Style: String, Equatable, Sendable, CaseIterable {
        case bold
        case italic
        /// **下划线**（片 `WY-1b1` · 派单 `T-20261009-045` 第 ③ 项）：Markdown 表达不了，
        /// 与 `bold` / `italic` 同形（进 `styles` 集合），即时呈现在富文本编辑面上。
        case underline
        case code
        /// 行内颜色（Markdown 表达不了，v2 起是 span 自己的字段）
        case color
        /// 字号（同上）
        case size
    }

    /// **块级类型**（片 `WY-1b2` · 派单 `T-20261009-045` 第 ⑤⑥⑦ 项 · 契约 v1.30 §2.4 / §3.3）。
    ///
    /// 这三档与 `Style` 那些**行内**样式不同：它们描述的是**整个段落 / 块**（有序编号 / 无序编号 /
    /// 勾选框任务项），而不是段落里某几个字的字形。
    ///
    /// **内部模型可异、交换形态必须同形**（契约 §2.4 不变量④）：Swift 这一侧用 `ordered` /
    /// `bullet` / `task`，但**写进 JSON 的是 `type` = `LIST_ORDERED` / `LIST_UNORDERED` /
    /// `LIST_CHECKBOX`**（见 `exchangeType`）—— Swift 内部名**绝不直接进 JSON**。
    ///
    /// **编号 / 层级由渲染层生成、不落库**（契约不变量⑤）：这里只存「这一段是哪一档块级」，
    /// 不存「它是第几号」；将来要嵌套层级 ⇒ 走提案改契约，不得各端私加。
    public enum Block: Equatable, Sendable {
        /// 有序编号列表项。
        case ordered
        /// 无序编号列表项（圆点）。
        case bullet
        /// 勾选框（任务项）；`checked` 是勾选状态（缺省未勾）。
        case task(checked: Bool)

        /// 写进交换面 `type` 字段的字面量（**契约逐字同形**，见 `NoteSpanType`）。
        public var exchangeType: String {
            switch self {
            case .ordered: return NoteSpanType.listOrdered.rawValue
            case .bullet: return NoteSpanType.listUnordered.rawValue
            case .task: return NoteSpanType.listCheckbox.rawValue
            }
        }

        /// 从交换面的 `type` 字面量 + `checked` 还原块级类型；**不是那三档的字面量 ⇒ `nil`**
        /// （未知 `type` 不在这里判——解码面会原样留进 `unknownFields`，前向兼容不丢）。
        public static func from(exchangeType raw: String, checked: Bool) -> Block? {
            switch raw {
            case NoteSpanType.listOrdered.rawValue: return .ordered
            case NoteSpanType.listUnordered.rawValue: return .bullet
            case NoteSpanType.listCheckbox.rawValue: return .task(checked: checked)
            default: return nil
            }
        }
    }

    public var text: String
    public var styles: Set<Style>
    public var color: String?
    public var size: Int?
    /// **链接目标**（`[文字](目标)` 里那段括号），**原样**保存。
    ///
    /// 两件事刻意**不在这里**判：① 它是不是一个能加载的地址（那是浏览器那条唯一入口的事，
    /// 见 `BrowserSession.parseAddress`）；② 它该开在哪儿（契约：默认在已内嵌的浏览器页签里）。
    /// 链接 span 的 `text` 是**显示文字**（点之前看见的那几个字）；非链接 span 是 `nil`。
    /// **链接不进 `styles`** —— 它不是粗体那种「样式」，它是**目标**。
    public var link: String?
    /// **背景高亮色**（片 `WY-1b1` · 派单 `T-20261009-048`：第 ④ 项「笔刷」= 荧光笔·淡黄底色）。
    ///
    /// 与 `color`（行内**文字**色）同形：`#RRGGBB` 串，缺省 `nil` = 无底色。**唯一权威值**是
    /// `NoteHighlight.backgroundColorHex`（本片只做固定淡黄，不做多色选择器 —— 判据作废那条口径）。
    /// Markdown 表达不了它 ⇒ 不进 `NoteBody.body` 投影（落库归 `WY-2` 的 span 直存）。
    public var backgroundColor: String?
    /// **块级类型**（片 `WY-1b2`）：`nil` = 普通文本 span（本片之前**所有** span 都是这一档）；
    /// 非 nil = 有序编号 / 无序编号 / 勾选框任务项（见 `Block`）。缺省 `nil` 是刻意的 ——
    /// 老数据（WY-1a 写的 `{version:2, spans:[...]}`）里没有它，读回来就该是文本 span。
    public var block: Block?
    /// **不认得的字段原样保留**（前向兼容，见 `NoteJSONValue`）。已知字段名不在此列。
    public var unknownFields: [String: NoteJSONValue]

    /// 已知字段名：解码时这些各走各的分支，其余一律进 `unknownFields`。
    static let knownFieldNames: Set<String> = ["text", "styles", "color", "size", "link", "backgroundColor"]

    public init(
        text: String,
        styles: Set<Style> = [],
        color: String? = nil,
        size: Int? = nil,
        link: String? = nil,
        backgroundColor: String? = nil,
        block: Block? = nil,
        unknownFields: [String: NoteJSONValue] = [:]
    ) {
        self.text = text
        self.styles = styles
        self.color = color
        self.size = size
        self.link = link
        self.backgroundColor = backgroundColor
        self.block = block
        self.unknownFields = unknownFields
    }
}

extension NoteSpan: Codable {
    /// 动态键：span 的字段名不是有限集合（前向兼容要求留得住未知键），所以用字符串键容器。
    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var text = ""
        var styles: Set<Style> = []
        var color: String?
        var size: Int?
        var link: String?
        var backgroundColor: String?
        // **块级那两个字段**（片 `WY-1b2`）：`type` 与 `checked` 是**交换面**的键（契约 §2.4）。
        // 认得出那三档 ⇒ 落成 `block`；认不出 / 不该在这儿出现 ⇒ 原样留进 `unknownFields`（前向兼容）。
        var typeRaw: String?
        var checkedRaw: Bool?
        var unknown: [String: NoteJSONValue] = [:]
        for key in container.allKeys {
            switch key.stringValue {
            case "text": text = (try? container.decode(String.self, forKey: key)) ?? ""
            case "styles":
                let raws = (try? container.decode([String].self, forKey: key)) ?? []
                styles = Set(raws.compactMap(Style.init(rawValue:)))
            case "color": color = try? container.decode(String.self, forKey: key)
            case "size": size = try? container.decode(Int.self, forKey: key)
            case "link": link = try? container.decode(String.self, forKey: key)
            case "backgroundColor": backgroundColor = try? container.decode(String.self, forKey: key)
            case "type": typeRaw = try? container.decode(String.self, forKey: key)
            case "checked": checkedRaw = try? container.decode(Bool.self, forKey: key)
            default:
                if let value = try? container.decode(NoteJSONValue.self, forKey: key) {
                    unknown[key.stringValue] = value
                }
            }
        }
        // `type` 三档 ⇒ `block`；未知 `type`（老版本读新数据）**不得丢弃**（契约 §2.4 不变量②）——
        // 连同 `checked` 一起原样留进 `unknownFields`，再写回时带出。
        var block: Block?
        if let typeRaw {
            if let recognized = Block.from(exchangeType: typeRaw, checked: checkedRaw ?? false) {
                block = recognized
            } else {
                unknown["type"] = .string(typeRaw)
                if let checkedRaw { unknown["checked"] = .bool(checkedRaw) }
            }
        } else if let checkedRaw {
            // 没有 `type` 却带着 `checked`：同样原样留住（不猜它属于谁）。
            unknown["checked"] = .bool(checkedRaw)
        }
        self.init(
            text: text,
            styles: styles,
            color: color,
            size: size,
            link: link,
            backgroundColor: backgroundColor,
            block: block,
            unknownFields: unknown
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        try container.encode(text, forKey: DynamicKey(stringValue: "text"))
        if !styles.isEmpty {
            // 排序后再写：集合无序，写出来的字节也应当是确定的（人工比对与 diff 才读得懂）。
            try container.encode(styles.map(\.rawValue).sorted(), forKey: DynamicKey(stringValue: "styles"))
        }
        if let color { try container.encode(color, forKey: DynamicKey(stringValue: "color")) }
        if let size { try container.encode(size, forKey: DynamicKey(stringValue: "size")) }
        if let link { try container.encode(link, forKey: DynamicKey(stringValue: "link")) }
        if let backgroundColor { try container.encode(backgroundColor, forKey: DynamicKey(stringValue: "backgroundColor")) }
        // **块级**（片 `WY-1b2`）：写的是**交换面**的 `type` 字面量（`LIST_ORDERED` / …），
        // **不是** Swift 内部名 —— 契约 §2.4 不变量④钉的就是这一条。
        // `checked` 只在勾选框那档出现；显式写出（含 `false`）⇒「勾选状态必须落库」在交换面上是**看得见的**。
        if let block {
            try container.encode(block.exchangeType, forKey: DynamicKey(stringValue: "type"))
            if case .task(let checked) = block {
                try container.encode(checked, forKey: DynamicKey(stringValue: "checked"))
            }
        }
        for (name, value) in unknownFields where !Self.knownFieldNames.contains(name) {
            try container.encode(value, forKey: DynamicKey(stringValue: name))
        }
    }
}

/// **荧光笔·淡黄的唯一色值出处**（片 `WY-1b1` · 派单 `T-20261009-048`）。
///
/// 第 ④ 项「笔刷」的口径是**固定淡黄**（原文那句「颜色可选」**判据作废** ⇒ 本片不做多色选择器）：
/// 色值只在这里写一次，界面侧经 `Theme.nsColor(hex:)` 取 `NSColor`、写进 `NoteSpan.backgroundColor`
/// 用的是同一份十六进制串 —— 「一处定义」这条是判据 `TestsUISnapshot/NotesEditorFormatProbeTests.swift`
/// 与它两侧读的同一个常量。
public enum NoteHighlight {
    /// 淡黄底色的数值形态（`0xRRGGBB`）。
    public static let rgb: UInt32 = 0xFFF3B0
    /// 淡黄底色的字符串形态（`NoteSpan.backgroundColor` 的权威值）。
    public static let backgroundColorHex = "#FFF3B0"
}

/// 投影结果：spans + **如实报出的降级**（哪些样式没能落到 span 上、为什么）。
public struct NoteProjection: Equatable, Sendable {
    public var spans: [NoteSpan]
    public var degradations: [String]

    public init(spans: [NoteSpan], degradations: [String] = []) {
        self.spans = spans
        self.degradations = degradations
    }
}

public enum NoteBodyProjection {

    // MARK: - 权威源 → span 树

    /// **行内标记的唯一解析处**（全局只有这一份，见下）。
    ///
    /// 抽出来是因为队列 `L-137`（工作区 Markdown 预览）：预览的**块级**结构由
    /// `MarkdownDocument` 产出，而每一块里的**行内**标记必须与笔记侧**同一份实现** ——
    /// 否则同一个 `**粗体**` 在笔记里是粗体、在预览里是星号，两套口径。
    /// 门禁 `Scripts/check-markdown-single-source.py` 就守这一条（`nextMarker` 只许在 `NoteBody.swift`）。
    ///
    /// **口径一字未改**（提取前它长在 `toSpans` 里）：只认 `**` / `*` / `` ` `` 三个标记；
    /// **取最早出现的那个**（不是「先试代码再试粗体」）；未闭合 / 空内容不算一对；
    /// 扫到谁先出现就切谁，切不动就整段退化成纯文本（不吞、不改写）。
    ///
    /// **2026-10-01 第 146 轮补第 4 个候选：链接**（队列 `L-137` 剩余③；人类主人答「#2，进」⇒
    /// 口径 = **链接进笔记侧 span 树**）。三条与上面同一族的口径：
    ///   · `[文字](目标)` 形态要求**紧挨着**的 `](`，文字与目标**都非空** —— 空的不算一对（同「空内容不算一对」）；
    ///   · 与其它标记**同一个先来后到**：谁在文本里先出现就先切谁（`**[a](b)**` 得到的是一个粗体 span，
    ///     文字是 `[a](b)` 原文 —— **标记里的标记不再解析**，子集刻意很小）；
    ///   · **不跨行、不做括号平衡**：文字与目标里出现换行 ⇒ 退回普通文本；目标里出现不成对的 `)`
    ///     ⇒ 截到**第一个 `)`**（多出来那个留在剩余文本里）。两条都有用例钉着，别改口径时忘掉。
    /// 目标落 `NoteSpan.link`（**不进 `styles`**）；能不能加载不在这里判（浏览器那条入口的事）。
    public static func parseInline(_ markdown: String) -> [NoteSpan] {
        var spans: [NoteSpan] = []
        var remaining = Substring(markdown)
        while !remaining.isEmpty {
            if let marker = nextMarker(in: remaining) {
                if !marker.before.isEmpty {
                    spans.append(NoteSpan(text: String(marker.before)))
                }
                switch marker.marker {
                case "**": spans.append(NoteSpan(text: String(marker.inner), styles: [.bold]))
                case "*": spans.append(NoteSpan(text: String(marker.inner), styles: [.italic]))
                case "[": spans.append(NoteSpan(text: String(marker.inner), link: marker.target.map(String.init)))
                default: spans.append(NoteSpan(text: String(marker.inner), styles: [.code]))
                }
                remaining = marker.after
            } else {
                spans.append(NoteSpan(text: String(remaining)))
                remaining = ""
            }
        }
        return spans
    }

    /// 把旁挂样式应用到 span 树上（**v1 → v2 投影的核心一步**）。返回**没能定位**的那些旁挂
    /// （调用方按语言如实报降级 —— 不静默丢）。
    ///
    /// 旁挂按「文本 + 第几次出现」定位 —— **要能在 span 内部再切一刀**。
    /// 一开始我按「整段 span 文本相等」定位，结果纯文本（没有任何 Markdown 标记）时整篇是一个大 span，
    /// 旁挂永远定位不到（测试当场抓到）。正确做法是：找到那段文字后**把 span 切成三份**再上样式。
    /// 已知简化：出现次序按「扫描顺序」计，不做跨 span 的严格计数（原型够用，正式实现要写清口径）。
    static func applySidecar(
        _ spans: [NoteSpan],
        _ sidecar: [NoteSidecarStyle]
    ) -> (spans: [NoteSpan], unplaced: [NoteSidecarStyle]) {
        var spans = spans
        var unplaced: [NoteSidecarStyle] = []
        for style in sidecar {
            var seen = 0
            var applied = false
            var index = 0
            while index < spans.count {
                guard let range = spans[index].text.range(of: style.text) else {
                    index += 1
                    continue
                }
                if seen < style.occurrence {
                    seen += 1
                    index += 1
                    continue
                }
                let text = spans[index].text
                var styled = NoteSpan(text: style.text, styles: spans[index].styles, color: style.color, size: style.size)
                if style.color != nil { styled.styles.insert(.color) }
                if style.size != nil { styled.styles.insert(.size) }
                let before = String(text[text.startIndex..<range.lowerBound])
                let after = String(text[range.upperBound...])
                var replacement: [NoteSpan] = []
                if !before.isEmpty { replacement.append(NoteSpan(text: before)) }
                replacement.append(styled)
                if !after.isEmpty { replacement.append(NoteSpan(text: after)) }
                spans.replaceSubrange(index...index, with: replacement)
                applied = true
                break
            }
            if !applied {
                unplaced.append(style)
            }
        }
        return (spans, unplaced)
    }

    /// **v1 → v2 规则**（语言中立的那一半）：Markdown + 旁挂 → span 树。
    /// 旁挂里的颜色 / 字号会被搬到 span 上；**搬不动的那些这里不报**（要给人看的话走 `project`）。
    public static func spans(fromMarkdown markdown: String, sidecar: [NoteSidecarStyle] = []) -> [NoteSpan] {
        applySidecar(parseInline(markdown), sidecar).spans
    }

    /// **v1 投影（带降级报告）**：Markdown + 旁挂 → span 树 + 如实报出的降级。
    ///
    /// **语言由调用方给定**（队列 L-47 / L-65 的口径）：降级说明是**给人看的话**，
    /// 界面要英文就传 `.english`。此前这里写死简体中文 ⇒ 语言表里
    /// `noteSidecarLost` / `noteLostColor` / `noteLostSize` / `noteExportDegraded`
    /// 的英文译文**永远不可达**（死译文）。**刻意不留默认值**：默认值等于把「写死语言」藏起来。
    public static func project(
        _ markdown: String,
        sidecar: [NoteSidecarStyle] = [],
        language: AppLanguage
    ) -> NoteProjection {
        let result = applySidecar(parseInline(markdown), sidecar)
        let degradations = result.unplaced.map {
            LocalizedStrings.format(.noteSidecarLost, language: language, String($0.occurrence + 1), $0.text)
        }
        return NoteProjection(spans: result.spans, degradations: degradations)
    }

    /// **v2 语义下的 `toSpans`**：权威源**已经是** spans，投影不再产生降级。
    ///
    /// 保留这个名字是为了既有读点与门禁口径：`MarkdownDocumentTests` 仍按
    /// `toSpans(NoteBody(markdown: ...), language:).spans == parseInline(同一段)` 钉住
    /// 「预览与笔记同一份行内解析」（`Scripts/check-markdown-single-source.py` ③）。
    public static func toSpans(_ body: NoteBody, language: AppLanguage) -> NoteProjection {
        NoteProjection(spans: body.spans, degradations: [])
    }

    /// 行内解析扫到的一个候选：切点 + 切点之前的文字 + 标记本身 + 标记里的文字 +
    ///（链接才有）目标 + 切点之后的剩余。
    private struct InlineMarker {
        var start: Range<String.Index>
        var before: Substring
        var marker: String
        var inner: Substring
        var target: Substring?
        var after: Substring
    }

    private static func nextMarker(in text: Substring) -> InlineMarker? {
        // **取最早出现的那个标记**（不是"先试代码再试粗体"——那样会把更早的粗体漏掉，
        // 本轮测试当场抓到：`普通 **加粗** … ` 里的粗体被当成了前导纯文本）。
        // 另外**空内容不算一对**（`**粗体` 未闭合时不该被剥掉一颗星）。
        // 链接（`[`）与三个成对标记**同一个先来后到**：谁先出现切谁。
        var best: InlineMarker?
        for marker in ["`", "**", "*", "["] {
            guard let start = text.range(of: marker) else { continue }
            if let best, best.start.lowerBound <= start.lowerBound { continue }
            guard let candidate = markerCandidate(in: text, marker: marker, at: start) else { continue }
            best = candidate
        }
        return best
    }

    /// 从 `start` 处切一刀：成对标记看**同一个标记的下一处**，链接看**紧挨着的 `](` 与第一个 `)`**。
    private static func markerCandidate(
        in text: Substring,
        marker: String,
        at start: Range<String.Index>
    ) -> InlineMarker? {
        if marker == "[" {
            return linkMarker(in: text, at: start)
        }
        let afterStart = text[start.upperBound...]
        guard let end = afterStart.range(of: marker) else { return nil }
        let inner = afterStart[afterStart.startIndex..<end.lowerBound]
        guard !inner.isEmpty else { return nil }
        return InlineMarker(
            start: start,
            before: text[text.startIndex..<start.lowerBound],
            marker: marker,
            inner: inner,
            target: nil,
            after: afterStart[end.upperBound...]
        )
    }

    /// `[文字](目标)`（队列 `L-137` 剩余③）。
    ///
    /// 四条边界都写在这里，不留在"读代码的人自己想"：
    /// ① `](` 必须**紧挨着**（`[文字] (目标)` 不是链接）；
    /// ② 文字与目标**都非空**；
    /// ③ 文字与目标**都不许跨行** —— 一个 `](` 能跨过整篇把后面的文字吞进"链接文字"里，
    ///    那是"吞"，与这个文件的口径相反；
    /// ④ 目标取**第一个 `)`**，**不做括号平衡**（`[a](b(c))` 的目标是 `b(c`，
    ///    多出来那个 `)` 留在剩余文本里原样搬运）。
    private static func linkMarker(in text: Substring, at start: Range<String.Index>) -> InlineMarker? {
        guard let bracket = text.range(of: "](", range: start.upperBound..<text.endIndex) else { return nil }
        let inner = text[start.upperBound..<bracket.lowerBound]
        guard !inner.isEmpty, !inner.contains("\n") else { return nil }
        let targetStart = bracket.upperBound
        guard let close = text.range(of: ")", range: targetStart..<text.endIndex) else { return nil }
        let target = text[targetStart..<close.lowerBound]
        guard !target.isEmpty, !target.contains("\n") else { return nil }
        return InlineMarker(
            start: start,
            before: text[text.startIndex..<start.lowerBound],
            marker: "[",
            inner: inner,
            target: target,
            after: text[close.upperBound...]
        )
    }

    // MARK: - span 树 → 投影（单向）

    /// span 树 → **Markdown 投影**。这是 `NoteBody.body` 的实现 —— 单向：只从 spans 派生文本，
    /// 文本不反向回写 spans。（v1 那种「能进 Markdown 的进 Markdown、进不了的落旁挂」在 v2 不再是
    /// 权威源的一部分：颜色 / 字号本就存在 span 上。）
    public static func markdown(from spans: [NoteSpan]) -> String {
        var markdown = ""
        for span in spans {
            var text = span.text
            if let link = span.link {
                // **链接优先**：`[文字](目标)` 是 Markdown 表达得了的 ⇒ 与颜色 / 字号那两档不同，
                // **不落旁挂**（往返原样，见 `testLinkRoundTripStaysInMarkdown`）。
                text = "[" + span.text + "](" + link + ")"
            } else if span.styles.contains(.code) {
                text = "`" + text + "`"
            } else {
                if span.styles.contains(.bold) { text = "**" + text + "**" }
                if span.styles.contains(.italic) { text = "*" + text + "*" }
            }
            markdown += text
        }
        return markdown
    }

    /// span 树 → 权威源 `NoteBody`。v2 起权威源**就是** `spans` —— 直接装进 `NoteBody`，
    /// 不做「能进 Markdown 的进 Markdown」那一步（那是 v1 的形态）。
    public static func fromSpans(_ spans: [NoteSpan]) -> NoteBody {
        NoteBody(spans: spans)
    }

    // MARK: - 导出（给"导出 .md 文件"用，必须报降级）

    public struct ExportResult: Equatable, Sendable {
        public var markdown: String
        /// 导出后**一定会丢**的东西（人要看得到，而不是自己发现）。
        public var degradations: [String]
    }

    /// 导出报告：Markdown 表达不了的行内颜色 / 字号**必然丢** ⇒ 逐条如实报出来。
    public static func exportMarkdown(_ body: NoteBody, language: AppLanguage) -> ExportResult {
        var degradations: [String] = []
        for span in body.spans {
            var lost: [String] = []
            if let color = span.color { lost.append(LocalizedStrings.format(.noteLostColor, language: language, color)) }
            if let size = span.size { lost.append(LocalizedStrings.format(.noteLostSize, language: language, String(size))) }
            if !lost.isEmpty {
                degradations.append(LocalizedStrings.format(.noteExportDegraded, language: language, span.text, lost.joined(separator: " / ")))
            }
        }
        // 导出的是**投影本身**（不重排、不美化）：AI 写进来的排版不该被我们改掉。
        return ExportResult(markdown: body.body, degradations: degradations)
    }
}
