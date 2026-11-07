import Foundation

/// 九个显示开关的**唯一真源**（`FR-AGT-UX-CONV-012`；契约表 = 概设 §8.9 ⑤）。
///
/// ## 为什么键名与取值域要写在这里
///
/// 概设那句「键名、默认值、取值域三样都定」是一条**跨端一致性**要求：三端（macOS /
/// iOS / 其它壳）读同一份键名表，同一个键在各端含义必须相同。所以键名字符串只在
/// 这一个类型里出现一次，别端要么读这份文件、要么在判据里钉住同一组字面量 ——
/// 各端自己发明一套键名，同一个「紧凑模式」就会变成三个不同的开关。
///
/// ## 与「运行策略」的区别（`FR-AGT-OPS-OBS-002`）
///
/// 运行策略改动是**有后果的**（超时 / 配额 / 白名单），所以那边要填理由、要批量原子校验。
/// 显示开关改了只是**看起来不一样**，所以这边**改一项立刻落盘生效**，不要求理由、
/// 不留改动史 —— 把纯观感的开关也塞进审计，会把审计淹掉。
public enum AgentDisplayKey: String, CaseIterable, Sendable {
    /// 流式输出（默认开）：关时收齐再显示。
    case streaming = "display.streaming"
    /// 紧凑模式（默认关）：开时工具块默认折叠、块间距取紧档。
    case compact = "display.compact"
    /// 显示思考段（默认关）：关时**零占位**（不留空行）。
    case thinking = "display.thinking"
    /// 时间戳（默认关）：行首栏宽度不变（不抖动）。
    case timestamps = "display.timestamps"
    /// 工具进度（默认全部）：全部 / 摘要（只留折叠头 + 条数）/ 关（只留调用次数）。
    case toolProgress = "display.toolProgress"
    /// 状态指示字形（默认表情字形档）：三档都要能表达就绪 / 运行中 / 错误。
    case indicatorGlyph = "display.indicatorGlyph"
    /// 长消息预览（**默认关 = 不折**，2026-11-07 起；旧默认 `2+2` 见 §3.33 的迁移）：
    /// 打开后折叠处有省略号且可展开。
    case longPreview = "display.longPreview"
    /// 运行底栏元数据（默认关）：开时状态行追加模型 / 上下文百分比 / 工作目录。
    case bottomBarMeta = "display.bottomBarMeta"
    /// 运行中提交（默认打断）：打断 = 先停后发；排队 = 这一轮结束后接着跑。
    case submitWhileRunning = "display.submitWhileRunning"
}

/// 工具进度三档（`FR-AGT-UX-CONV-012`）。
public enum AgentToolProgressMode: String, CaseIterable, Sendable {
    case all
    case summary
    case off
}

/// 状态指示字形三档（`FR-AGT-UX-CONV-012`）：三档都必须能表达就绪 / 运行中 / 错误。
public enum AgentIndicatorGlyph: String, CaseIterable, Sendable {
    case emoji
    case unicode
    case ascii
}

/// 运行中提交的处置（`FR-AGT-UX-CONV-012`）。
public enum AgentSubmitWhileRunning: String, CaseIterable, Sendable {
    /// 先停后发。
    case interrupt
    /// 排进队列，这一轮结束后接着跑。
    case queue
}

/// 长消息预览的行数对（`FR-AGT-UX-CONV-012`：首 2 末 2）。
///
/// 取值域是**行数对**：`off` 或 `H+T`（`H`/`T` 各 1…`maxLinesPerEdge`）。
/// 上界不是洁癖：`H`/`T` 大到跟正文一样多时「预览」这个词就没意义了，
/// 而且界面按行数算折叠提示，给个 999 会画出一行「折叠 0 行」。
public enum AgentLongMessagePreview: Equatable, Hashable, Sendable {
    case off
    case headTail(head: Int, tail: Int)

    /// 契约默认值：**不折**（`off`）。
    ///
    /// 2026-11-07 改（详设 §3.33「对话区展示优先级」）：人类主人实机反馈
    /// 「**结论竟然折叠起来**，却把 29 个 claims 全展开放屏幕上」——
    /// 首 2 末 2 折的正是**结论本身**（回答正文 / 代码块），而答案才是他要读的那一块。
    /// 于是默认改成不折：**结论默认整体呈现**。开关仍然在（有人确实想要长消息折叠时能自己打开），
    /// 但那是**显式 opt-in**，不是默认形态。
    ///
    /// 契约表（概设 §8.9 ⑤）随这一条同步改了默认值 —— 判据 `Tests/AgentDisplayPreferencesTests`
    /// 钉的就是「默认等于这一格」，不是钉「首 2 末 2」这个历史值。
    public static let contractDefault = AgentLongMessagePreview.off

    /// **旧契约默认**（`2+2`）的规范串。只给迁移用（见 `AgentDisplayPreferencesFile.load`）：
    /// 已装机器盘上存着这个值时，它不是用户的选择，是**当年那份默认**。
    public static let legacyContractDefault = "2+2"

    /// 单边行数上界（取值域的一部分，写进拒绝理由里）。
    public static let maxLinesPerEdge = 20

    /// 盘上 / 界面上的规范形态：`off` 或 `2+2`。
    public var canonicalValue: String {
        switch self {
        case .off: return "off"
        case let .headTail(head, tail): return "\(head)+\(tail)"
        }
    }

    /// 解析（严格）：解不出来就 `nil`（调用方把「允许什么」写进拒绝理由，别静默夹成默认值）。
    public init?(canonicalValue: String) {
        let text = canonicalValue.trimmingCharacters(in: .whitespaces)
        if text == "off" { self = .off; return }
        let parts = text.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let head = Int(parts[0]), let tail = Int(parts[1]),
              (1...Self.maxLinesPerEdge).contains(head),
              (1...Self.maxLinesPerEdge).contains(tail) else { return nil }
        self = .headTail(head: head, tail: tail)
    }

    /// 需要折叠判定用的两个数（`off` ⇒ 两侧都不折叠，返回 `nil`）。
    public var edges: (head: Int, tail: Int)? {
        switch self {
        case .off: return nil
        case let .headTail(head, tail): return (head, tail)
        }
    }
}

/// 显示开关被拒的两种原因（机器码，界面按 `AgentDisplayRejectionText` 翻人话）。
public enum AgentDisplayError: Error, Equatable {
    /// 键名不在九个里（写错一个键 = 用户以为改了、其实没改）。
    case unknownKey(String)
    /// 值不在该键的取值域里（`allowed` 是给人看的取值域说明）。
    case invalidValue(key: String, value: String, allowed: String)
}

extension AgentDisplayError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .unknownKey(key): return "unknownKey:\(key)"
        case let .invalidValue(key, value, allowed): return "invalidValue:\(key)=\(value) allowed \(allowed)"
        }
    }
}

/// 九个开关的那一份值（`FR-AGT-UX-CONV-012`）。
///
/// **默认值逐项对契约表**（概设 §8.9 ⑤）：流式输出开 / 紧凑关 / 显示思考段关 / 时间戳关 /
/// 工具进度全部 / 字形表情字形档 / 长消息预览**不折**（2026-11-07 改，见 §3.33）/ 底栏元数据关 / 运行中提交打断。
/// 判据 `Tests/AgentDisplayPreferencesTests` 把这张表逐格钉住 —— 默认值改了就是改了契约，
/// 该红的必须红。
///
/// 「花费显示」**不在这里**：契约把它定成「固定关、不设开关」，多一个键就等于让人
/// 以为自己能打开它。判据里断言九个键之外没有第十个。
public struct AgentDisplayPreferences: Equatable, Sendable {
    public var streaming: Bool
    public var compact: Bool
    public var thinking: Bool
    public var timestamps: Bool
    public var toolProgress: AgentToolProgressMode
    public var indicatorGlyph: AgentIndicatorGlyph
    public var longPreview: AgentLongMessagePreview
    public var bottomBarMeta: Bool
    public var submitWhileRunning: AgentSubmitWhileRunning

    public init(streaming: Bool = true,
                compact: Bool = false,
                thinking: Bool = false,
                timestamps: Bool = false,
                toolProgress: AgentToolProgressMode = .all,
                indicatorGlyph: AgentIndicatorGlyph = .emoji,
                longPreview: AgentLongMessagePreview = AgentLongMessagePreview.contractDefault,
                bottomBarMeta: Bool = false,
                submitWhileRunning: AgentSubmitWhileRunning = .interrupt) {
        self.streaming = streaming
        self.compact = compact
        self.thinking = thinking
        self.timestamps = timestamps
        self.toolProgress = toolProgress
        self.indicatorGlyph = indicatorGlyph
        self.longPreview = longPreview
        self.bottomBarMeta = bottomBarMeta
        self.submitWhileRunning = submitWhileRunning
    }

    /// 契约默认那一份（`AgentDisplayPreferences()` 与它是同一个值，留着名字给界面说「恢复默认」）。
    public static let contractDefaults = AgentDisplayPreferences()

    /// 「花费显示」的固定值：**永远关**（契约：不设开关）。界面据此**不画**金额，
    /// 判据据此断言这个常量是 `false` —— 想让它可配就得先改契约。
    public static let spendingDisplayEnabled = false

    // MARK: - 逐键读写

    /// 某键当前的规范值（盘上写这个形态，界面也照它选中）。
    public func canonicalValue(for key: AgentDisplayKey) -> String {
        switch key {
        case .streaming: return streaming ? "on" : "off"
        case .compact: return compact ? "on" : "off"
        case .thinking: return thinking ? "on" : "off"
        case .timestamps: return timestamps ? "on" : "off"
        case .toolProgress: return toolProgress.rawValue
        case .indicatorGlyph: return indicatorGlyph.rawValue
        case .longPreview: return longPreview.canonicalValue
        case .bottomBarMeta: return bottomBarMeta ? "on" : "off"
        case .submitWhileRunning: return submitWhileRunning.rawValue
        }
    }

    /// 某键的取值域说明（拒绝理由与面板的提示都用它 —— 一处真相）。
    public static func allowedValues(for key: AgentDisplayKey) -> String {
        switch key {
        case .streaming, .compact, .thinking, .timestamps, .bottomBarMeta:
            return "on|off"
        case .toolProgress:
            return AgentToolProgressMode.allCases.map(\.rawValue).joined(separator: "|")
        case .indicatorGlyph:
            return AgentIndicatorGlyph.allCases.map(\.rawValue).joined(separator: "|")
        case .longPreview:
            return "off|H+T (1...\(AgentLongMessagePreview.maxLinesPerEdge))"
        case .submitWhileRunning:
            return AgentSubmitWhileRunning.allCases.map(\.rawValue).joined(separator: "|")
        }
    }

    /// 改一项。**非法值抛错、不静默夹成默认值**（静默夹会让「保存成功」变成谎话）。
    @discardableResult
    public mutating func apply(key: String, value: String) throws -> AgentDisplayPreferences {
        guard let displayKey = AgentDisplayKey(rawValue: key) else {
            throw AgentDisplayError.unknownKey(key)
        }
        let text = value.trimmingCharacters(in: .whitespaces)
        func boolean() throws -> Bool {
            switch text.lowercased() {
            case "on", "true", "1": return true
            case "off", "false", "0": return false
            default:
                throw AgentDisplayError.invalidValue(key: key, value: value,
                                                    allowed: Self.allowedValues(for: displayKey))
            }
        }
        switch displayKey {
        case .streaming: streaming = try boolean()
        case .compact: compact = try boolean()
        case .thinking: thinking = try boolean()
        case .timestamps: timestamps = try boolean()
        case .bottomBarMeta: bottomBarMeta = try boolean()
        case .toolProgress:
            guard let mode = AgentToolProgressMode(rawValue: text.lowercased()) else {
                throw AgentDisplayError.invalidValue(key: key, value: value,
                                                    allowed: Self.allowedValues(for: displayKey))
            }
            toolProgress = mode
        case .indicatorGlyph:
            guard let glyph = AgentIndicatorGlyph(rawValue: text.lowercased()) else {
                throw AgentDisplayError.invalidValue(key: key, value: value,
                                                    allowed: Self.allowedValues(for: displayKey))
            }
            indicatorGlyph = glyph
        case .longPreview:
            guard let preview = AgentLongMessagePreview(canonicalValue: text) else {
                throw AgentDisplayError.invalidValue(key: key, value: value,
                                                    allowed: Self.allowedValues(for: displayKey))
            }
            longPreview = preview
        case .submitWhileRunning:
            guard let submit = AgentSubmitWhileRunning(rawValue: text.lowercased()) else {
                throw AgentDisplayError.invalidValue(key: key, value: value,
                                                    allowed: Self.allowedValues(for: displayKey))
            }
            submitWhileRunning = submit
        }
        return self
    }

    /// 一次改多项：**先全部校验再落地**（第三项非法时前两项也不许留在内存里 ——
    /// 否则面板报「保存失败」但界面已经变成半套新值）。
    @discardableResult
    public mutating func applyBatch(_ pairs: [(key: String, value: String)]) throws -> AgentDisplayPreferences {
        var candidate = self
        for pair in pairs {
            try candidate.apply(key: pair.key, value: pair.value)
        }
        self = candidate
        return self
    }

    /// 全部九项的规范形态（写盘用；顺序固定 = 契约表顺序，便于人工核对）。
    public var canonicalValues: [(key: AgentDisplayKey, value: String)] {
        AgentDisplayKey.allCases.map { ($0, canonicalValue(for: $0)) }
    }
}

// MARK: - 落盘

/// 九个开关在盘上的那一份（`FR-AGT-UX-CONV-012` ①「重启后保持」）。
///
/// 三条口径与运行策略那边一致（同一个 `AgentSessionStore.defaultDirectory`，
/// 不另开文件体系）：缺文件 = 全新；坏文件 / 越界值 = **降级到默认并点名是哪一项**；
/// 写盘原子（`.atomic`）—— 半份文件读回来会被判坏文件、把用户九个开关一起清掉。
public struct AgentDisplayPreferencesFile {

    public enum LoadState: Equatable {
        /// 盘上还没有这份文件（第一次跑）。
        case fresh
        case loaded
        /// 读不出来 / 解析失败 / 某一项越界 —— 已降级到默认值，`reason` 是机器码。
        case degraded(reason: String)
    }

    public struct LoadResult {
        public let preferences: AgentDisplayPreferences
        public let state: LoadState
        public let fileURL: URL
        /// 载入时做了一次**旧默认迁移** ⇒ 调用方应当写回一次（见 `load()` 的注释）。
        public let needsRewrite: Bool

        init(preferences: AgentDisplayPreferences,
             state: LoadState,
             fileURL: URL,
             needsRewrite: Bool = false) {
            self.preferences = preferences
            self.state = state
            self.fileURL = fileURL
            self.needsRewrite = needsRewrite
        }
    }

    /// 盘上文件名（跨端同名，便于三端对照排查）。
    public static let fileName = "agent-display-preferences.json"

    /// 盘上格式版本。`1` = beta1.0.3 及以前（`longPreview` 默认写 `2+2`）；`2` = 现行。
    public static let currentVersion = 2

    public let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent(Self.fileName)
    }

    private struct Payload: Codable {
        var version: Int
        var values: [String: String]
    }

    public func load() -> LoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return LoadResult(preferences: AgentDisplayPreferences(), state: .fresh, fileURL: fileURL)
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            return LoadResult(preferences: AgentDisplayPreferences(),
                              state: .degraded(reason: "unreadable"), fileURL: fileURL)
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return LoadResult(preferences: AgentDisplayPreferences(),
                              state: .degraded(reason: "parseFailed"), fileURL: fileURL)
        }

        // **一次性迁移：旧默认 `2+2` → `off`**（详设 §3.33，2026-11-07 真机复验）。
        //
        // 为什么必须有这一条：上一批只把 `contractDefault` 改成 `off`，那只管**新装**机器。
        // 已装用户在 beta1.0.3 之前跑过一次 ⇒ 盘上那份是当时按旧默认写下的 `2+2`，
        // 于是「结论依旧被折成首 2 末 2 行」——默认值改了、人还是看不见结论。
        //
        // 判定口径（可用信息只有这些，故只能这样定）：盘上 `version` 还是 1（旧格式）
        // 且 `longPreview` 恰好等于旧契约默认 `2+2` ⇒ 视为**当年那份默认**，迁到 `off`。
        // 真正显式选过 `2+2` 的用户在 v1 里与默认值**不可区分** —— 这是 v1 格式的事实，
        // 不在这一层假装能分辨；迁移只做一次（写回 version 2），此后用户再自己设 `2+2`
        // 就按他的选择存，不再覆盖（判据 `Tests/AgentDisplayPreferencesTests` 钉住三条）。
        var values = payload.values
        var needsRewrite = false
        let previewKey = AgentDisplayKey.longPreview.rawValue
        if payload.version < Self.currentVersion,
           values[previewKey] == AgentLongMessagePreview.legacyContractDefault {
            values[previewKey] = AgentLongMessagePreview.contractDefault.canonicalValue
            needsRewrite = true
        }

        // **逐项过 `apply` 自己的校验**（范围与词表不在这里重写 —— 同一处真相）。
        // 每一项都调一次：一项越界就要点名那一项，而不是笼统说「文件坏了」。
        var preferences = AgentDisplayPreferences()
        for key in AgentDisplayKey.allCases {
            guard let stored = values[key.rawValue] else { continue }
            do {
                try preferences.apply(key: key.rawValue, value: stored)
            } catch let error as AgentDisplayError {
                return LoadResult(preferences: AgentDisplayPreferences(),
                                  state: .degraded(reason: Self.reasonCode(error)),
                                  fileURL: fileURL)
            } catch {
                return LoadResult(preferences: AgentDisplayPreferences(),
                                  state: .degraded(reason: "invalidValue:\(key.rawValue)"),
                                  fileURL: fileURL)
            }
        }
        return LoadResult(preferences: preferences, state: .loaded,
                          fileURL: fileURL, needsRewrite: needsRewrite)
    }

    public func save(_ preferences: AgentDisplayPreferences) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        var values: [String: String] = [:]
        for pair in preferences.canonicalValues {
            values[pair.key.rawValue] = pair.value
        }
        let payload = Payload(version: Self.currentVersion, values: values)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(payload).write(to: fileURL, options: .atomic)
    }

    static func reasonCode(_ error: AgentDisplayError) -> String {
        switch error {
        case let .unknownKey(key): return "unknownKey:\(key)"
        // 只留键名：降级那句话要说的是「哪一项读不出来」，取值域由面板照常列出
        // （把 allowed 也塞进机器码会让解析方为了取键名去切两刀，迟早切错）。
        case let .invalidValue(key, _, _): return "invalidValue:\(key)"
        }
    }

    /// 降级原因 → 一句话（界面照实说「盘上那一项读不出来、现在用的是默认值」）。
    /// 机器码原样返回（ASCII），人话由界面按语言表翻。
    public static func degradedKey(for reason: String) -> AgentDisplayKey? {
        let parts = reason.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        // 兼容带细节的老形态（`invalidValue:<键>=<值> allowed …`）：只取键名那一段。
        let raw = String(parts[1]).split(separator: "=", maxSplits: 1,
                                         omittingEmptySubsequences: false)[0]
        return AgentDisplayKey(rawValue: String(raw))
    }
}

// MARK: - 界面文案（拒绝 / 降级）

/// 拒绝与降级的**人话**（界面唯一出口；Core 里不写死中文 —— 语言表管这一层）。
public enum AgentDisplayRejectionText {

    /// 一句可贴到面板上的结论。`language` 由界面给（L-47：语言只有一个来源）。
    public static func line(for error: AgentDisplayError, language: AppLanguage) -> String {
        switch error {
        case let .unknownKey(key):
            return LocalizedStrings.format(.agentDisplayUnknownKey, language: language, key)
        case let .invalidValue(key, value, allowed):
            return LocalizedStrings.format(.agentDisplayInvalidValue, language: language, key, value, allowed)
        }
    }

    /// 载入降级那一句（`reason` 是 `AgentDisplayPreferencesFile.LoadState.degraded` 的原样机器码）。
    public static func degradedLine(reason: String, language: AppLanguage) -> String {
        if let key = AgentDisplayPreferencesFile.degradedKey(for: reason) {
            return LocalizedStrings.format(.agentDisplayDegradedKey, language: language, key.rawValue)
        }
        return LocalizedStrings.format(.agentDisplayDegradedFile, language: language, reason)
    }
}
