import Foundation
import AppKit
import Combine
import DoyahCore

/// 工作区的页签与文件（FR-EDIT-35 / 36）。
///
/// **为什么在 App 层而不是塞进 `AppState`**：`AppState` 已经承担连接 / 执行 / 元数据 / 事务 / 智能体……
/// 再把工作区页签挂上去，它会变成那种"谁都不敢动"的中心类。工作区有自己的模型、自己的页签集合，
/// 与数据库那套**并列**（数据库侧当前处于冻结状态，见 SRS v3.180）。
@MainActor
final class WorkspaceTabsModel: ObservableObject {

    /// 单个文件的大小上限。超过就**如实拒绝**：把几十 MB 的日志塞进 `NSTextView`
    /// 会把界面卡死，而"能打开但卡死"比"明确说不打开"糟得多。
    static let maximumFileSize = 2 * 1024 * 1024

    @Published private(set) var tabs: [WorkspaceTab] = [.home(title: L(.workspaceTabHome))]
    @Published private(set) var selectedID: UUID?
    @Published private(set) var history = WorkspaceHistory()
    /// 失败原因（界面上如实显示，不静默）。
    @Published var errorText: String?
    /// 一次性提示（保存成功 / 按非 UTF-8 编码打开之类）。
    @Published var noticeText: String?

    /// 待确认的关闭请求（`FR-EDIT-46`）：有未保存改动时**弹确认框**，
    /// 而不是像以前那样直接拒绝关闭。`nil` = 没有框要弹。
    @Published var pendingClose: WorkspaceCloseRequest?

    /// 工作区右侧是否显示 **Markdown 只读预览**（队列 `L-137`）。
    ///
    /// 状态住在模型里、视图只读它 —— 与页签集、浏览器页签同一条纪律
    /// （放进视图的 `@State` 会在切页签 / 重建视图时把用户的选择丢掉）。
    /// 全局一个开关（不按页签各记一份）：用户要的是"看的时候分屏、写的时候全宽"。
    @Published var previewVisible = true

    /// 把文件交给**工作区的浏览器页签**那一侧（队列 `L-149` 剩余②）。
    ///
    /// 为什么是注入的闭包而不是本模型直接持一个 `WorkspaceBrowserModel`：浏览器页签的
    /// 状态归 `WorkspaceBrowserModel`（第 135 轮搬过来的，判据 `check-browser-tab-ownership.py`
    /// 守着「只此一处」）；工作区页签模型只负责「这个文件该去哪儿」，交接由宿主（`DoyahStudioApp`）
    /// 接线一次。**没接线时不静默丢失** —— 走文本编辑器打开（见 `openFile(at:)`）。
    var openInBrowserTab: ((URL) -> Void)?

    func togglePreview() {
        previewVisible.toggle()
    }

    private let store: WorkspaceHistoryStore

    init(store: WorkspaceHistoryStore = .standard()) {
        self.store = store
        var loaded = WorkspaceHistory()
        var problem: String?
        do {
            loaded = try store.load()
        } catch {
            problem = error.localizedDescription
        }
        history = loaded
        selectedID = tabs.first?.id
        if let problem {
            errorText = L(.workspaceHistoryLoadFailed, problem)
        }
    }

    // MARK: 选中与页签

    var selectedTab: WorkspaceTab? {
        tabs.first { $0.id == selectedID } ?? tabs.first
    }

    func select(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    func openHome() {
        if let home = tabs.first(where: { $0.isHome }) {
            selectedID = home.id
        }
    }

    /// 关闭页签（`FR-EDIT-46`）。
    ///
    /// **点关闭按钮走 `requestClose(_:)`** —— 干净页签直接关，有未保存改动则挂一个
    /// `pendingClose` 让界面弹确认框（需求提出者 2026-10-03：「弹出确认框让用户选择，
    /// 是保存关闭还是不修改直接退出」）。旧行为是**直接拒绝关闭**并只给一句话，
    /// 那是阻塞不是确认。
    ///
    /// 本函数仍是**无条件关闭**（确认过之后的落实点），但**脏页签一律拒收** ——
    /// 那条纪律不因为加了确认框而作废：任何绕过确认的调用点（将来新增的菜单 / 快捷键）
    /// 都不会让改动**静默**消失。
    func close(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        guard !tab.isDirty else {
            // 到不了这里才叫「有确认框」：脏页签必须先经过 `requestClose(_:)`。
            pendingClose = WorkspaceCloseRequest(id: tab.id, title: tab.title, actions: WorkspaceClosePolicy.confirmActions)
            return
        }
        forceClose(id)
    }

    /// 用户点了关闭按钮 / 关闭入口：**先问清楚再关**。
    func requestClose(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        let plan = WorkspaceClosePolicy.plan(isDirty: tab.isDirty)
        guard plan.needsConfirmation else {
            forceClose(id)
            return
        }
        pendingClose = WorkspaceCloseRequest(id: tab.id, title: tab.title, actions: plan.actions)
    }

    /// 确认框里选了某个动作。**保存的成败在这里算**：失败就不关（`WorkspaceClosePolicy`）。
    func resolvePendingClose(_ action: WorkspaceCloseAction) {
        guard let request = pendingClose else { return }
        pendingClose = nil
        switch action {
        case .cancel:
            return
        case .discardChanges:
            forceClose(request.id)
        case .saveAndClose:
            let saved = save(request.id)
            guard !WorkspaceClosePolicy.keepsTab(action: action, saveSucceeded: saved) else { return }
            forceClose(request.id)
        }
    }

    /// 关掉确认框但**不关页签**（按 ESC / 点框外走这条，与「取消」同一个结局）。
    func cancelPendingClose() {
        pendingClose = nil
    }

    /// 真正把页签从集合里挪走（**只有确认过、或本来就不脏**才允许到这里）。
    private func forceClose(_ id: UUID) {
        let next = WorkspaceTabSet.selection(afterClosing: id, in: tabs, selected: selectedID)
        tabs = WorkspaceTabSet.closing(id: id, in: tabs)
        selectedID = next ?? tabs.first?.id
    }

    func updateContent(_ text: String, for id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }), tabs[index].content != text else { return }
        tabs[index].content = text
    }

    // MARK: 打开 / 保存

    /// 打开一个文件：已经开着就切过去（**不重复开**）。
    ///
    /// **去哪儿开由语言登记表说**（`FR-EDIT-36` 的消费者口径）：登记项声明
    /// `defaultView == .browser` 的那一类（今天 = `.html` / `.htm` / `.xhtml`）交给工作区的
    /// 浏览器页签；其余（含认不出的）当文本打开。**这里刻意不写「扩展名 == "html"」** ——
    /// 那是把语言知识搬回核心代码，正是 `FR-EDIT-38` ① 要清掉的形状
    /// （判据 `Scripts/check-language-registry.py` 的 E 档守着「读这一档的地方只有一处」）。
    func openFile(at url: URL) {
        let path = url.path
        if CodeLanguageRegistry.defaultView(forPath: path) == .browser, let openInBrowserTab {
            openInBrowserTab(url)
            record(file: path)
            return
        }
        if let existing = tabs.first(where: { $0.path == path }) {
            selectedID = existing.id
            return
        }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            guard values.isDirectory != true else {
                errorText = L(.workspaceOpenFailedDirectory, url.lastPathComponent)
                return
            }
            if let size = values.fileSize, size > Self.maximumFileSize {
                errorText = L(
                    .workspaceFileTooLarge,
                    url.lastPathComponent,
                    Self.sizeText(Int64(size)),
                    Self.sizeText(Int64(Self.maximumFileSize))
                )
                return
            }
            let data = try Data(contentsOf: url)
            guard !data.contains(0) else {
                errorText = L(.workspaceFileBinary, url.lastPathComponent)
                return
            }
            let decoded = try TextFileDecoder.decode(data)
            let opened = WorkspaceTabSet.opening(path: path, in: tabs, content: decoded.text)
            tabs = opened.tabs
            selectedID = opened.selected
            record(file: path)
            // 编码不是 UTF-8 时说出来：用户得知道"看到的字为什么对了"（FR-IO-07 的同一套判决）。
            if decoded.isFallback {
                noticeText = L(.workspaceOpenedWithEncoding, url.lastPathComponent, decoded.encoding.shortName)
            }
        } catch {
            errorText = L(.workspaceOpenFailed, url.lastPathComponent, error.localizedDescription)
        }
    }

    /// 保存（⌘S）：写回原路径。返回**是否写成功** —— 「保存并关闭」那条路要靠它决定关不关
    /// （`FR-EDIT-46`：保存失败就不关，见 `WorkspaceClosePolicy.keepsTab`）。
    @discardableResult
    func save(_ id: UUID) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return false }
        guard let path = tabs[index].path else { return false }
        do {
            try tabs[index].content.write(toFile: path, atomically: true, encoding: .utf8)
            tabs[index].markSaved()
            noticeText = L(.workspaceFileSaved, tabs[index].title)
            return true
        } catch {
            errorText = L(.workspaceSaveFailed, tabs[index].title, error.localizedDescription)
            return false
        }
    }

    /// 当前选中页签的保存（给 ⌘S 用）。
    func saveSelected() {
        guard let id = selectedID else { return }
        save(id)
    }

    // MARK: 跳到命中行（FR-EDIT-44 标头搜索框）

    /// 「打开文件并**跳到第 N 行**」的一次性投递 —— 与格式化同一形状（`FormatDelivery`）：
    /// 模型只算「跳去哪儿」，真正挪光标与滚动的是编辑器视图那一层（`NSTextView`）。
    struct RevealDelivery: Equatable {
        let id: UUID
        let tabID: UUID
        /// 行号，**1 起**（与行号列同口径）。
        let line: Int
    }

    @Published private(set) var revealDelivery: RevealDelivery?

    /// 打开文件并跳到某一行（`FR-EDIT-44` 的「回车打开并跳到命中行」）。
    ///
    /// 为什么收成一个入口：`openFile(at:)` 里的路由（浏览器页签 / 已开着就切过去 / 太大 / 二进制）
    /// 是**唯一**一份实现，跳行只是「在打开成功之后再做一件事」—— 视图里各写一遍会绕开那些拒绝路径
    /// （症状：点了一个打不开的文件，界面却像是跳过去了）。
    func openFile(at url: URL, line: Int?) {
        openFile(at: url)
        guard let line, line > 0 else { return }
        // 落到浏览器页签那一类没有「行」可跳（`tabs` 里也就没有对应页签）—— 不静默编一个。
        guard let tab = tabs.first(where: { $0.path == url.path }) else { return }
        selectedID = tab.id
        revealDelivery = RevealDelivery(id: UUID(), tabID: tab.id, line: line)
    }

    // MARK: 代码格式化（FR-EDIT-39，形态 = ③ 混合）

    /// 格式化结果的一次性投递：模型算好文本，**由编辑器视图自己**做那一次替换。
    ///
    /// 为什么不直接改 `content`：那条路最终是 `updateNSView` 里的 `textView.string = text`，
    /// 而它**不注册撤销** —— 用户按 ⌘Z 拿不回来。需求要求「格式化前后可撤销」，
    /// 所以替换必须发生在 `NSTextView` 上（`CodeTextView.applyFormat`）。
    struct FormatDelivery: Equatable {
        let id: UUID
        let tabID: UUID
        let text: String
    }

    @Published private(set) var formatDelivery: FormatDelivery?

    /// 「格式化代码」：菜单与 ⇧⌘F 走**同一个入口**（两个入口两条路迟早不一致）。
    func formatSelected() {
        guard let tab = selectedTab, !tab.isHome else {
            // 工作区首页不是文件：这句话本身也是「说说清楚」，不是静默 return。
            errorText = L(.workspaceFormatNoFile)
            return
        }
        let language = tab.language
        let text = tab.content
        Task {
            // **只用内置**（需求提出者 2026-10-02 定案；「外部优先 / 回退内置」那版作废）。
            // 这一层被删掉了：不探 `PATH`、不探测工具，`runBuiltin` 连 `runner` 都不收 ⇒ 结构上起不了子进程。
            let execution = CodeFormatService.runBuiltin(language: language, text: text)
            apply(execution, to: tab.id)
        }
    }

    /// 三种结局都要说话 —— 需求原文：不静默失败、也不给出「看起来变了但没变」的结果。
    private func apply(_ execution: CodeFormatExecution, to tabID: UUID) {
        switch execution {
        case .refused(let reason):
            errorText = Self.refusalText(reason)
        case .failed(let failure):
            errorText = L(
                .workspaceFormatFailed,
                Self.engineName(failure.engine),
                failure.exitCode.map(String.init) ?? "—",
                failure.message
            )
        case .ready(let outcome):
            guard outcome.changed else {
                noticeText = L(.workspaceFormatUnchanged, Self.engineName(outcome.engine))
                return
            }
            // 投给视图去做可撤销替换；文本到那时才进编辑器。
            formatDelivery = FormatDelivery(id: UUID(), tabID: tabID, text: outcome.text)
            noticeText = L(.workspaceFormatDone, Self.engineName(outcome.engine))
        }
    }

    /// 界面文案这一半（Core 只给结构化的结局，中文/英文都在语言表里）。
    private static func engineName(_ engine: CodeFormatEngine) -> String {
        switch engine {
        case .external(let name, let version):
            // 契约层口径（b）：说了用外部工具，就要说得清**哪一个、哪一版**。
            // 版本探测不到（或工具不认 `--version`）就只说名字 —— 不编版本号。
            guard let version, !version.isEmpty else { return name }
            return "\(name) \(version)"
        case .builtin: return L(.workspaceFormatEngineBuiltin)
        }
    }

    private static func refusalText(_ reason: CodeFormatRefusal) -> String {
        switch reason {
        case .unknownLanguage:
            return L(.workspaceFormatRefusedUnknown)
        case .noFormatter(let language):
            return L(.workspaceFormatRefusedNoFormatter, language.displayName)
        }
    }

    // MARK: 最近打开（Home 用）

    func record(file path: String) {
        history = WorkspaceHistory.recording(file: path, into: history)
        persistHistory()
    }

    func record(workspace path: String?) {
        guard let path, !path.isEmpty else { return }
        history = WorkspaceHistory.recording(workspace: path, into: history)
        persistHistory()
    }

    func removeRecentFile(_ path: String) {
        history = WorkspaceHistory.removing(file: path, from: history)
        persistHistory()
    }

    func clearHistory() {
        history = WorkspaceHistory()
        persistHistory()
    }

    private func persistHistory() {
        do {
            try store.save(history)
        } catch {
            // 存不下不影响使用，但要如实说一句
            errorText = L(.workspaceHistorySaveFailed, error.localizedDescription)
        }
    }

    private static func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
