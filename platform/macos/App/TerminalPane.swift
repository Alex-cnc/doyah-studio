import AppKit
import SwiftUI
import DoyahCore

// MARK: - 每个页签自己的那一半（会话 + 屏幕）

/// **一个终端页签 = 一条会话**：屏幕模型 + PTY 会话 + 回滚 / 选区状态。
///
/// 为什么从 `TerminalView.swift` 里单独拆出来（队列 L-84 ㈡）：多会话之后，
/// 「模型」这个词要指两样东西了 ——
/// · **本类**（`TerminalPane`）= 一个页签自己的东西（这台 shell 画在哪、光标在哪、跑没跑）；
/// · `App/TerminalTabsModel.swift` 的 `TerminalModel` = 整个面板（有几个页签、哪个是当前、
///   ⌘T / ⌘W / ⌘1…9 落到谁头上）。
/// 两者分开，才有「切页签不重启会话」这件事可说 —— 切的是协调器里的当前页签，
/// 而每个 `TerminalPane` 连同它的 `TerminalSession` 一直在那儿。
///
/// 视图（`TerminalHostView`）只负责画网格与把按键变成字节，所有状态在这里，
/// 这样界面重建（例如语言切换导致整树重建）不会把 shell 弄丢——会话挂在协调器的字典上。
@MainActor
final class TerminalPane: ObservableObject {
/// 终端面板的状态：屏幕模型 + PTY 会话。
///
/// 视图（`TerminalHostView`）只负责画网格与把按键变成字节，所有状态在这里，
/// 这样界面重建（例如语言切换导致整树重建）不会把 shell 弄丢——会话挂在 `@StateObject` 上。

    let screen: TerminalScreen
    private let session = TerminalSession()

    @Published private(set) var isRunning = false
    @Published private(set) var errorText: String?

    /// 屏幕内容变了要让视图重画；由视图注册。
    private var requestRedraw: (() -> Void)?
    private var didStart = false

    init(columns: Int = 80, rows: Int = 24) {
        screen = TerminalScreen(columns: columns, rows: rows)
    }

    func attach(redraw: @escaping () -> Void) {
        requestRedraw = redraw
    }

    /// PTY 是否已经起过（视图用它决定"首次布局时用真实几何启动"）。
    var hasStarted: Bool { didStart }

    /// 会话退出时回调（协调器据此把页签标成「已退出」并让标题不再装作有人在跑）。
    var onExitDetected: ((Int32) -> Void)?

    /// 前台进程的可执行路径（页签标题的唯一来源）。
    ///
    /// 查不到就是 nil —— 协调器**不编**一个名字出来（Core 的 `TerminalTabTitle` 那时返回 nil，
    /// 界面用语言表里的兜底词）。这条链路上「不知道」必须一路传成「不知道」。
    func foregroundProcessPath() -> String? { session.foregroundProcessPath() }

    /// 工作区路径（FR-EDIT-32）：终端启动目录以它为准。
    ///
    /// 说明：**只在启动那一刻读取** —— 已经跑起来的 shell 不会被"换工作区"搬走
    /// （与 VS Code 一致：换工作区是开新终端，而不是把正在跑的命令换目录）。
    var workspacePath: String?

    // MARK: 回滚区与选区

    /// 回滚区显示偏移（0 = 实时画面）。
    ///
    /// 只要不为 0，新输出**不会**把视口拽回底部（终端惯例：用户翻上去看东西时不被踢下来）；
    /// 按任意键 / ⌘↓ / ⌘End / 滚回底部才回到实时画面。
    /// 说明：偏移是相对**缓冲区底部**算的，因此回滚区被裁剪时看到的还是"底部往上第 N 行"。
    @Published private(set) var scrollOffset = 0

    /// 当前鼠标选区（nil = 没有选中）。
    @Published private(set) var selection: TerminalSelection?

    var maxScrollOffset: Int { screen.maxScrollOffset }

    /// 视图要画的那几行（已应用回滚偏移）。
    func displayLines() -> [[TerminalCell]] {
        screen.visibleLines(offset: scrollOffset, height: screen.rows)
    }

    func scroll(byLines delta: Int) {
        let clamped = min(max(0, scrollOffset + delta), screen.maxScrollOffset)
        guard clamped != scrollOffset else { return }
        scrollOffset = clamped
        requestRedraw?()
    }

    func scrollToBottom() {
        guard scrollOffset != 0 else { return }
        scrollOffset = 0
        requestRedraw?()
    }

    /// 清空回滚区（右键菜单项）：只丢历史行，不动当前屏幕、光标与模式位。
    func clearScrollback() {
        screen.clearScrollback()
        scrollOffset = 0
        requestRedraw?()
    }

    func beginSelection(at raw: TerminalCellPosition) {
        let position = TerminalSelection.snapped(raw, in: displayLines())
        selection = TerminalSelection(anchor: position, focus: position)
        requestRedraw?()
    }

    func extendSelection(to raw: TerminalCellPosition) {
        guard var current = selection else { return }
        current.focus = TerminalSelection.snapped(raw, in: displayLines())
        selection = current
        requestRedraw?()
    }

    func clearSelection() {
        guard selection != nil else { return }
        selection = nil
        requestRedraw?()
    }

    /// 选区文本（没选中或选到空白时返回 nil）。取的是**当前显示的那几行**，
    /// 所以"看到什么就复制什么"。
    func selectedText() -> String? {
        guard let selection else { return nil }
        let text = selection.text(in: displayLines())
        return text.isEmpty ? nil : text
    }

    /// ⌘C / 菜单「复制」：把选区写进系统剪贴板；没有选中时返回 false，让按键继续往下走。
    @discardableResult
    func copySelectionToPasteboard() -> Bool {
        guard let text = selectedText() else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return true
    }

    /// ⌘V / 菜单「粘贴」：读系统剪贴板并发给 shell。
    ///
    /// 走 `TerminalPaste`（Core 的纯函数）而不是直接 `session.write(text:)`：
    /// 前台程序开了**括号粘贴**（SGR 2004）时必须把内容包起来，否则 vim 会逐行自动缩进、
    /// 多行 SQL 可能被逐行提交。包装规则与换行处理都是纯逻辑，那边有单测。
    @discardableResult
    func pasteFromPasteboard() -> Bool {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return false }
        let payload = TerminalPaste.payload(
            for: text,
            isBracketedPasteEnabled: screen.isBracketedPasteEnabled
        )
        guard !payload.isEmpty else { return false }
        send(payload)
        return true
    }

    /// ⌘A：全选**当前显示的那几行**（含回滚区偏移后的视图）。
    ///
    /// 只选可见范围而不是整个回滚区：回滚区可能有上万行，全选之后复制会得到一个
    /// 巨大字符串；终端惯例（Terminal.app / iTerm2）也是按可见范围来的。
    func selectAllVisible() {
        let lines = displayLines()
        guard let last = lines.indices.last, lines[last].indices.last != nil else { return }
        selection = TerminalSelection(
            anchor: TerminalCellPosition(row: 0, column: 0),
            focus: TerminalCellPosition(row: last, column: max(0, lines[last].count - 1))
        )
        requestRedraw?()
    }

    func startIfNeeded(columns: Int, rows: Int) {
        guard !didStart else { return }
        didStart = true
        session.onOutput = { [weak self] data in
            guard let self else { return }
            self.screen.feed([UInt8](data))
            // 设备查询应答（DA1 / DSR / DECRQM / XTVERSION）要**回给前台程序**：
            // 不回话的话，vim / tmux 一类程序会一直等这一行，表现为"界面卡住"。
            let responses = self.screen.drainResponses()
            if !responses.isEmpty { self.session.write(responses) }
            self.requestRedraw?()
        }
        session.onExit = { [weak self] code in
            guard let self else { return }
            self.isRunning = false
            self.screen.feed(text: "\r\n[进程已退出，代码 \(code)]\r\n")
            self.requestRedraw?()
            // 页签状态是**协调器**的事（它才知道这个会话是哪个页签、还有几个页签在跑）。
            self.onExitDetected?(code)
        }
        screen.resize(columns: columns, rows: rows)
        if session.start(columns: columns, rows: rows, workingDirectory: launchDirectory()) {
            isRunning = true
        } else {
            isRunning = false
            errorText = session.lastError
        }
        requestRedraw?()
    }

    func restart(columns: Int, rows: Int) {
        session.terminate()
        screen.reset()
        scrollOffset = 0
        selection = nil
        didStart = false
        errorText = nil
        startIfNeeded(columns: columns, rows: rows)
    }

    func send(_ bytes: [UInt8]) {
        session.write(bytes)
    }

    func send(text: String) {
        session.write(text: text)
    }

    func resize(columns: Int, rows: Int) {
        screen.resize(columns: columns, rows: rows)
        session.resize(columns: columns, rows: rows)
        requestRedraw?()
    }

    func stop() {
        session.terminate()
        isRunning = false
    }

    /// 终端启动目录：工作区（待 Explorer 接入）＞ 有意义的启动目录 ＞ 家目录。
    ///
    /// 实测：Finder 双击 / `open` 拉起时 `currentDirectoryPath` 是 `/`，直接继承会让
    /// 终端一进去就是根目录；从命令行直接跑才是真正的"启动目录"。
    private func launchDirectory() -> String {
        let fileManager = FileManager.default
        let isUsableDirectory: (String) -> Bool = { path in
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
            return exists && isDirectory.boolValue && fileManager.isReadableFile(atPath: path)
        }
        return TerminalWorkingDirectory.resolve(
            workspace: workspacePath,
            launchDirectory: fileManager.currentDirectoryPath,
            home: fileManager.homeDirectoryForCurrentUser.path,
            isUsableDirectory: isUsableDirectory
        )
    }
}
