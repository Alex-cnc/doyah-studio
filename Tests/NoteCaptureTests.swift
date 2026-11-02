import XCTest
@testable import DoyahCore

// `FR-NTS-NOTE-CAPTURE-001`（快速捕获）的机械证据。题面三条判据，逐条对一组用例：
//
//   ① 从触发到可输入 ≤1 个动作 —— `QuickCaptureSession.begin()` 之后捕获面成立且焦点已请求，
//      **没有**「选笔记本 / 选标签」这一步（捕获接口根本不收这两个参数）；
//      快捷键只注册一次（重复 start 不叠 handler ⇒ 不会一次按键弹出两个面）。
//   ② 断网也能记 —— `commit` 只走本地库：临时目录里跑真库文件，写完立刻读得回来；
//      捕获路径里没有网络调用（没有可注入的网络后端 ⇒ 结构上不可能依赖网络）。
//   ③ 不填标题也能存 —— 标题由首行推出（跳开头空行 / 压空白 / 超长截断），
//      整段空白时用兜底标题；正文**逐字保留**。
//
// 纪律与 `NoteAttachmentTests` 同源：跑真库文件（临时目录）、每条「应该」配一条「不该」的对照。
final class NoteCaptureTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-note-capture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func library() -> NoteLibrary {
        NoteLibrary(databaseURL: directory.appendingPathComponent(NoteLibrary.fileName, isDirectory: false))
    }

    private let fallback = "未命名速记"

    // MARK: - ③ 不填标题也能存：首行当标题

    func testFirstLineBecomesTitleWithoutBeingAsked() {
        let body = "明天 9:30 站会（记得带笔记本）\n顺带把上周的慢查询清单带上"
        XCTAssertEqual(QuickCapture.title(from: body, fallback: fallback), "明天 9:30 站会（记得带笔记本）")
    }

    func testLeadingBlankLinesAreSkipped() {
        XCTAssertEqual(QuickCapture.title(from: "\n\n   \n\t\n第二段才是第一行\n后面", fallback: fallback), "第二段才是第一行")
    }

    func testBlankBodyFallsBackInsteadOfSavingAnEmptyTitle() {
        XCTAssertEqual(QuickCapture.title(from: "", fallback: fallback), fallback)
        XCTAssertEqual(QuickCapture.title(from: "  \n\t\n\r\n ", fallback: fallback), fallback)
    }

    func testLongFirstLineIsTruncatedWithEllipsis() {
        let long = String(repeating: "慢", count: QuickCapture.maxTitleLength + 40)
        let title = QuickCapture.title(from: long + "\n第二行", fallback: fallback)
        XCTAssertEqual(title.count, QuickCapture.maxTitleLength + 1)
        XCTAssertTrue(title.hasSuffix("…"))
        XCTAssertFalse(title.contains("第二行"))
    }

    func testInlineWhitespaceIsCollapsedButWordsKeptInOrder() {
        XCTAssertEqual(QuickCapture.title(from: "  复盘   这次   事故\t经过 \n细节", fallback: fallback), "复盘 这次 事故 经过")
    }

    // MARK: - ①② 一个动作 → 立刻可输入；落盘只走本地

    func testBeginMakesCaptureInputReadyInOneStep() {
        let session = QuickCaptureSession()
        XCTAssertFalse(session.isPresenting)
        XCTAssertFalse(session.focusRequested)

        session.begin()   // ← 这就是「一个动作」：快捷键 → 可输入，中间没有选笔记本 / 选标签

        XCTAssertTrue(session.isPresenting)
        XCTAssertTrue(session.focusRequested)
        XCTAssertEqual(session.body, "")

        session.focusDidLand()
        XCTAssertFalse(session.focusRequested, "焦点落地后不该再抢一次")

        session.end()
        XCTAssertFalse(session.isPresenting)
    }

    func testCommitWritesToLocalLibraryAndReadsBackOffline() async throws {
        // 没有任何网络配置 / 后端可注入 —— 捕获路径里不存在网络调用（判据②）
        let library = library()
        let body = "地铁上想到的索引优化\norders(created_at) 补复合索引"

        let saved = try await QuickCapture.commit(body: body, fallbackTitle: fallback, into: library)

        XCTAssertEqual(saved.title, "地铁上想到的索引优化")
        XCTAssertEqual(saved.body, body, "正文必须逐字保留（不做 Markdown 解析、不 trim）")
        XCTAssertEqual(saved.source.kind, .quickCapture)
        XCTAssertTrue(saved.tags.isEmpty, "捕获不要求标签 ⇒ 不该凭空造标签")

        let loaded = try await library.load()
        let readBack = loaded.first { $0.id == saved.id }
        XCTAssertEqual(readBack?.title, "地铁上想到的索引优化")
        XCTAssertEqual(readBack?.body, body)
    }

    func testCaptureLandsWithoutChoosingANotebook() async throws {
        let library = library()
        let saved = try await QuickCapture.commit(body: "先记下，回头再归类", fallbackTitle: fallback, into: library)

        let placements = try await library.placements()
        XCTAssertFalse(placements.contains { $0.noteID == saved.id.uuidString && $0.notebookUid != nil },
                       "捕获不许替人挑笔记本 —— 归属留空，落默认笔记本")
    }

    func testBlankCaptureStillStoresTheFallbackTitle() async throws {
        let library = library()
        let saved = try await QuickCapture.commit(body: "   \n", fallbackTitle: fallback, into: library)
        XCTAssertEqual(saved.title, fallback)
        let stored = try await library.load()
        XCTAssertEqual(stored.count, 1)
    }

    // MARK: - ① 快捷键只注册一次（不叠 handler、失败可重试、能注销）

    func testHotKeyRegistersExactlyOnceEvenWhenStartedTwice() {
        let backend = FakeHotKeyBackend()
        let hotKey = QuickCaptureHotKey(backend: backend)
        var fired = 0

        XCTAssertEqual(hotKey.start { fired += 1 }, .registered(.standard))
        XCTAssertEqual(hotKey.start { fired += 1 }, .alreadyRegistered(.standard))

        XCTAssertEqual(backend.registers.count, 1, "重复 start 不许叠第二次注册（否则一次按键弹两个面）")
        backend.handler?()
        XCTAssertEqual(fired, 1, "只该有第一个 handler 生效")
    }

    func testHotKeyFailureIsReportedAndRetryable() {
        let backend = FakeHotKeyBackend()
        backend.allowsRegistration = false
        let hotKey = QuickCaptureHotKey(backend: backend)

        XCTAssertEqual(hotKey.start {}, .failed(.standard), "组合被别人占住要如实报失败")
        backend.allowsRegistration = true
        XCTAssertEqual(hotKey.start {}, .registered(.standard), "失败不许粘住 —— 人能再试一次")
        XCTAssertEqual(backend.registers.count, 2)
    }

    func testStopUnregistersSoRestartDoesNotLeak() {
        let backend = FakeHotKeyBackend()
        let hotKey = QuickCaptureHotKey(backend: backend)
        hotKey.start {}
        hotKey.stop()

        XCTAssertEqual(backend.unregisterCount, 1)
        XCTAssertNil(hotKey.outcome)
        XCTAssertEqual(hotKey.start {}, .registered(.standard))
        XCTAssertEqual(backend.registers.count, 2)
    }

    func testStandardShortcutIsTheDocumentedOne() {
        XCTAssertEqual(QuickCaptureShortcut.standard.display, "⌥⌘N")
        XCTAssertEqual(QuickCaptureShortcut(key: "N", modifiers: [.shift, .command]).display, "⇧⌘N")
    }
}

/// 热键替身：只记账，不真装 Carbon 热键（单测无窗口 / 无事件循环）。
private final class FakeHotKeyBackend: QuickCaptureHotKeyBackend {
    var registers: [QuickCaptureShortcut] = []
    var unregisterCount = 0
    var allowsRegistration = true
    var handler: (() -> Void)?

    func register(_ shortcut: QuickCaptureShortcut, handler: @escaping () -> Void) -> Bool {
        registers.append(shortcut)
        guard allowsRegistration else { return false }
        self.handler = handler
        return true
    }

    func unregister() {
        unregisterCount += 1
        handler = nil
    }
}


