import Foundation

/// **快速捕获**（`FR-NTS-NOTE-CAPTURE-001`）。
///
/// 三条判据 → 三条硬纪律，写进类型里，而不是靠调用方自觉：
///
/// ① **一个动作就能开始输入**：捕获面由快捷键直接打开（`QuickCaptureHotKey` + `QuickCaptureSession`），
///    **不选笔记本、不选标签、不选模板** —— 所以 `draft` 与 `commit` 都不接受这两样前置参数；
/// ② **断网也能记**：`commit` 只写本地库（`NoteLibrary.save`），一次记录 = 一次本地事务；
///    网络那一半（联网后自动上传）归同步队列，不在这里做网络调用 —— 捕获路径里没有网络代码，
///    「断网记不下来」在实现上不可能发生，而不是「祈祷它不超时」；
/// ③ **不填标题也能存**：标题由正文首行推出（跳过开头空行），首行过长截断、正文整段空白时用兜底标题。
public enum QuickCapture {

    /// 标题上限（首行超过这么长就截断 + 省略号）：标题是列表里的一行，不是全文。
    public static let maxTitleLength = 80

    /// 从正文推标题：**首个非空行**（去首尾空白、行内连续空白压成一个空格）。
    ///
    /// 为什么是「首行」而不是「第一句」：人快速记的时候第一行就是他给这条笔记起的名字；
    /// 拿第一句会把「明天 9:30 站会（记得带笔记本）」切成「明天 9:30 站会」，
    /// 括号里的限定反而丢了 —— 首行整行保留信息更完整。
    public static func title(from body: String, fallback: String) -> String {
        // 先统一换行：Swift 里 `"\r\n"` 是**一个** Character（CRLF 连字），直接按 "\n" 切会切不开，
        // Windows / 剪贴板来的正文会把整行 `\r\n` 当成首行标题。
        let unified = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        for rawLine in unified.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = normalized(rawLine)
            guard !line.isEmpty else { continue }
            return truncated(line)
        }
        return truncated(normalized(fallback))
    }

    /// 捕获草稿：正文**逐字保留**（不做 Markdown 解析、不 trim 正文），标签为空，
    /// 来源标 `.quickCapture`（半年后能回答「这条是一次快捷键记下来的」）。
    public static func draft(
        body: String,
        fallbackTitle: String,
        capturedAt: Date = Date()
    ) -> NoteDraft {
        NoteDraft(
            title: title(from: body, fallback: fallbackTitle),
            body: body,
            tags: [],
            source: NoteSource(kind: .quickCapture, capturedAt: capturedAt)
        )
    }

    /// 一条捕获 = 一次本地保存（判据②）。返回**库里读回来的那一份**，不用内存里那份猜。
    ///
    /// `spans` 不传：捕获是纯文本输入，没有富文本权威源，别拿投影去覆盖别人的正文。
    @discardableResult
    public static func commit(
        body: String,
        fallbackTitle: String,
        into library: NoteLibrary,
        now: Date = Date()
    ) async throws -> Note {
        let draft = self.draft(body: body, fallbackTitle: fallbackTitle, capturedAt: now)
        return try await library.save(draft, id: nil, now: now)
    }

    private static func normalized<S: StringProtocol>(_ line: S) -> String {
        line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\r" })
            .joined(separator: " ")
    }

    private static func truncated(_ text: String) -> String {
        guard text.count > maxTitleLength else { return text }
        return String(text.prefix(maxTitleLength)) + "…"
    }
}

/// 捕获面的状态（判据①的机器证据）：`begin()` 之后**立刻可输入** ——
/// 没有「选笔记本」这一步、没有「选标签」这一步，光标已经落在正文框里（`focusRequested`）。
public final class QuickCaptureSession {

    /// 捕获面是否呈现。
    public private(set) var isPresenting = false
    /// 是否请求把焦点放进正文框（界面层读它决定 `@FocusState = true`）。
    public private(set) var focusRequested = false
    /// 正在输入的正文。
    public var body = ""

    public init() {}

    /// **一个动作**：快捷键触发 → 捕获面出现 + 焦点进正文框 + 正文空。
    public func begin() {
        isPresenting = true
        focusRequested = true
        body = ""
    }

    /// 焦点已落地（界面层 `onAppear` 里调一次），避免重复抢焦点。
    public func focusDidLand() {
        focusRequested = false
    }

    public func end() {
        isPresenting = false
        focusRequested = false
        body = ""
    }
}

/// 全局快捷键的组合（键 + 修饰键）。
public struct QuickCaptureShortcut: Equatable, Sendable {

    public enum Modifier: String, Comparable, Sendable {
        case control, option, shift, command

        /// 显示顺序按 macOS 习惯：⌃ ⌥ ⇧ ⌘。
        fileprivate var order: Int {
            switch self {
            case .control: return 0
            case .option: return 1
            case .shift: return 2
            case .command: return 3
            }
        }

        fileprivate var glyph: String {
            switch self {
            case .control: return "⌃"
            case .option: return "⌥"
            case .shift: return "⇧"
            case .command: return "⌘"
            }
        }

        public static func < (lhs: Modifier, rhs: Modifier) -> Bool { lhs.order < rhs.order }
    }

    /// 主键（小写字母 / 数字 / 符号名，如 `n`）。
    public let key: String
    public let modifiers: Set<Modifier>

    public init(key: String, modifiers: Set<Modifier>) {
        self.key = key.lowercased()
        self.modifiers = modifiers
    }

    /// 显示形态（菜单里写的就这一个）：`⌥⌘N`。
    public var display: String {
        modifiers.sorted().map(\.glyph).joined() + key.uppercased()
    }

    /// 默认组合 = ⌥⌘N。选它而不是 ⌘N（新建笔记）：⌘N 已被「新建」占住，
    /// 捕获与新建是两条不同的路（捕获不选笔记本），同一个键会让人以为两者一样。
    public static let standard = QuickCaptureShortcut(key: "n", modifiers: [.option, .command])
}

/// 全局快捷键的后端（可替身 ⇒ 不装热键也能在单测里判「注册了几次 / 失败怎么报」）。
public protocol QuickCaptureHotKeyBackend: AnyObject {
    /// 注册一个全局热键；返回 `false` = 系统里这个组合已被别人占住。
    @discardableResult
    func register(_ shortcut: QuickCaptureShortcut, handler: @escaping () -> Void) -> Bool
    func unregister()
}

/// 快捷键的生命周期（判据①的入口）：**只注册一次**，重复 `start` 不叠加 handler。
///
/// 为什么把「只注册一次」写进类型而不是靠调用方自觉：`start` 会在应用激活 / 窗口重建时被反复调用，
/// 叠两次 handler 的后果是**按一次快捷键弹出两个捕获面** —— 人看到的是「这东西重影了」。
public final class QuickCaptureHotKey {

    public enum Outcome: Equatable {
        /// 注册成功。
        case registered(QuickCaptureShortcut)
        /// 之前已经注册过，本次没有重复注册。
        case alreadyRegistered(QuickCaptureShortcut)
        /// 系统里这个组合被别的东西占住（注册失败 ⇒ 界面要给人一条别的入口）。
        case failed(QuickCaptureShortcut)
    }

    private let backend: QuickCaptureHotKeyBackend
    public let shortcut: QuickCaptureShortcut
    public private(set) var outcome: Outcome?

    public init(backend: QuickCaptureHotKeyBackend, shortcut: QuickCaptureShortcut = .standard) {
        self.backend = backend
        self.shortcut = shortcut
    }

    @discardableResult
    public func start(handler: @escaping () -> Void) -> Outcome {
        if outcome == .registered(shortcut) { return .alreadyRegistered(shortcut) }
        let result: Outcome = backend.register(shortcut, handler: handler)
            ? .registered(shortcut)
            : .failed(shortcut)
        outcome = result
        return result
    }

    public func stop() {
        guard outcome != nil else { return }
        backend.unregister()
        outcome = nil
    }
}


