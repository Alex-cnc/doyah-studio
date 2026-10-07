import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 清单「空编辑器上「保存」**灰否**」那一行的**渲染级**机器判据
/// （队列 `L-89` ㈢ ① —— 需求提出者 2026-09-29：「把两处待点击也降级成机器判据」；
/// 开发循环第 112 轮）。
///
/// ## 为什么还要这一层（已经有两层了）
///
/// 那一行原先要需求提出者点三下：**空着灰 / 有内容亮 / 删回灰**。已经有的两层是：
///   ① **模型**：`AppState.noteEditorHasContent` 三态断言（`UISnapshotPanelsTests` 的空态那批）；
///   ② **源码**：`Scripts/check-empty-action-buttons.py` 钉「`.disabled(!appState.noteEditorHasContent)`
///      这一处还在、判据属性没有第二处定义、视图没有自己再算一遍」。
///
/// 但这两层合起来**判不到「渲染出来的那只按钮真的跟着变」** —— 谓词对了、`.disabled(!…)`
/// 也写对了，界面仍可能因为别的原因不变（样式覆盖、外层再包一层 `disabled(false)`、
/// 状态没接到那个视图上）。本探针补的正是这一层：**三态各渲染一遍真视图，在像素上判**。
///
/// ## 判据
///
/// 前置（防判错画面）：三态的谓词必须是 `false` / `true` / `false`；每一遍都要有内容
/// （内容占比下限，防「渲染成空白」的假绿）。
///   ① **空着灰**：工具条那一带（**顶部** y ∈ [0, 100)，见下）**最暗墨水亮度 ≥ 80**（实测 **91**）；
///   ② **有内容亮**：填一个字之后，同一带出现深墨水（**≤ 60**，实测 **36**），
///      且**按钮那一带确实变了**（两态差异像素落在这一带的 ≥ 2000 个，实测 **5028**）；
///   ③ **删回灰**：清空之后与空态**逐字节相同**（差异像素 **0**）—— 「删回灰」不是「看着差不多」。
///
/// **判定带随片 `N2-3b` 从底带搬到顶带**：人类主人令 `T-20261007-004` 第 4 条把「保存」搬进了
/// **顶部编辑工具条**（`App/Views/NotesPanel.swift` 的 `NotesEditorToolbar`）⇒ 它不再落在
/// 底部那一带里。三态断言本身**一字未改**，只重定了量它的那一带 —— 本文件头注释原先就写着
/// 「判定带与亮度门槛是**按本机实测定的**：换字号 / 换排版会动这条带，届时按实测重定」。
///
/// ## 判不到的（如实登记，别把这条读成「按钮会被点」）
///
/// · **控件身份**：实测（macOS 27 / 本机）这块 SwiftUI `Button` 在离屏宿主里**不落到
///   `NSButton`**（`findViews(ofType: NSButton.self)` = **0** 个），`NSHostingView` 的无障碍树
///   在离屏时**不构建**（`accessibilityChildren()` = **0**）⇒ 读不到 `isEnabled`，只能判像素。
/// · 判定带（`y ≥ 1000`）与亮度门槛是**按本机实测定的**：换字号 / 换排版会动这条带，
///   届时按实测重定（实测值都写在断言的消息里，读数即证据）。
/// · 按钮**点下去真的存下来了**不在这里：那是 `Tests/` 的真库证据脚本与 `NoteSearchProbeTests`
///   那一批的事；本条只判「这一格该不该可点」到像素。
///
/// 跑法：`./Scripts/run-manual-verification-probes.sh --filter NotesEditorSaveProbeTests`
/// （单独跑要 `DOYAH_UI_SNAPSHOT=1` + `DOYAH_NOTES_DIR=<临时目录>`）。
/// 纪律同 L-01：要真渲染 ⇒ **不进** `verify-all.sh`；产物落 `.build/ui-snapshot-state/`
/// （**刻意不调 `UISnapshot.write`**：探针产物不进快照清单，免得搅乱「张数 / 组数」那类派生计数）。
///
/// ## 片 `N2-4` 追加的四条（自动保存 · 人工令 `T-20261007-006` 第二节第六条）
///
/// 判据编号与卡上那张验收表一一对应（都在**盘上**判：另开一个 `NoteLibrary` 独立连接读回，
/// 不读 `AppState.notes` —— 拿内存态判「存下来了」是自己判自己）：
///   · `testN24AutosavePersistsOnPauseWithoutAnyExitPath` —— **③ 强杀等价物**：
///     打字之后**不做任何离开 / 退出动作**，只等停顿窗口；成对读数（窗前后各读一次盘）；
///   · `testN24LeavingTheNoteFlushesImmediately` —— **① / ② 切走即存**：
///     同一篇重开（点回列表那一下）与换一篇再回来，两半都从盘上读回；
///   · `testN24FailureIsVisibleAndNeverAPopup` —— **⑥ 失败有可见线索 + ④ 无弹窗**：
///     把临时笔记库改成只读（可复跑的触发方式，读数里打印了 chmod 那条命令）⇒
///     状态进 `.failed` 且带原因、状态栏有那句话、**`errorMessage` 仍是 nil**（不弹框）、
///     编辑器里那一份没丢；另加**反向对照**（同一条坏路上手动保存仍给那个可复制的框）；
///   · `testN24ToolbarSaveStateKeyIsReadable` —— **⑤ 工具条保存状态键存在且可读**：
///     三态各有文案键且中英齐（缺一语言 = 死键就判红）、`idle` 无键、源锚点（工具条真读这份
///     状态 + `NoteAutosave.statusIdentifier` 唯一出处 + 自动保存那一段里没有弹框入口）、
///     渲染级（`.pending` 与「已写完」两态在工具条那一带逐像素不同 ⇒ 状态那一格真的画了）。
///   **边界（如实登记）**：③ 是**等价物**而不是真的 `kill -9` —— 判的是「没有任何退出路径，
///   内容也已经 `COMMIT` 到盘上」（`kill -9` 只丢内存）；真要跑一次带信号的那条，
///   见本片交接里那条可复跑命令（进程级演示不在本探针里）。
final class NotesEditorSaveProbeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏渲染要显式打开：DOYAH_UI_SNAPSHOT=1（取证工具，不进每轮门禁）"
        )
        try XCTSkipIf(
            (ProcessInfo.processInfo.environment["DOYAH_NOTES_DIR"] ?? "").isEmpty,
            "本用例要碰笔记库 ⇒ 必须在临时数据家里跑：`DOYAH_NOTES_DIR` 没设就跳过"
                + "（绝不允许往真实用户数据目录里写测试夹具）"
        )
    }

    // MARK: - 装配

    private typealias Host = (
        state: AppState, workspace: WorkspaceStore, tabs: WorkspaceTabsModel, terminal: TerminalModel
    )

    /// 画的尺寸：与清单里那两张空态图同规格（正文编辑器满宽）。
    private static let size = CGSize(width: 900, height: 560)

    /// 按钮落在图上哪一带：**顶部编辑工具条那一带**（片 `N2-3b` 把它从底带搬上来的）。
    /// 按本机实测（2× 渲染 ⇒ 1120 px 高）：编辑器内边距 16pt ⇒ 工具条 ≈ 16…48pt ⇒ **32…96px**；
    /// 它下面那一行（标题框）的顶边在 ~130px 之下 ⇒ 取 [0, 100) 只框住工具条，
    /// 不碰标题框里那个字（碰上了的话「有内容亮」会被标题里那个字判绿 —— 量的就不是按钮了）。
    private static let buttonBandFromTop = 0
    private static let buttonBandToTop = 100

    @MainActor
    private func makeHost() -> Host {
        let scratch = UISnapshot.outputDirectory.deletingLastPathComponent()
            .appendingPathComponent("ui-snapshot-scratch", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let historyURL = scratch.appendingPathComponent("workspace-history-\(UUID().uuidString).json")

        let state = AppState()
        let workspace = WorkspaceStore.shared
        let tabs = WorkspaceTabsModel(store: WorkspaceHistoryStore(fileURL: historyURL))
        let terminal = TerminalModel()
        return (state, workspace, tabs, terminal)
    }

    // MARK: - 用例

    @MainActor
    func testSaveButtonGreysOutInThreeStates() throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }

        // 笔记在 Standard 档下就是整个应用（`LicenseEdition.standard` → `.notesOnly`）。
        let load = try UISnapshot.applyLicense(.standard, to: host.state)
        XCTAssertTrue(host.state.notesEnabled, "Standard 档必须带笔记能力（capabilities.notes）")
        XCTAssertEqual(load.entitlements.edition, .standard, "笔记区在 Standard 档下才是「整个应用」")

        // 三态：空 / 有字 / 删回空。**每一态都从空开始**，只有中间那一态多一个标题字。
        host.state.noteEditorTitle = ""
        host.state.noteEditorBody = ""
        host.state.noteEditorTags = ""
        XCTAssertFalse(host.state.noteEditorHasContent, "前置：起点必须是空编辑器")
        let empty = try render(host, label: "01-empty")

        host.state.noteEditorTitle = "临"
        XCTAssertTrue(host.state.noteEditorHasContent, "前置：填了一个字，判据必须为真")
        let typed = try render(host, label: "02-typed")

        host.state.noteEditorTitle = ""
        XCTAssertFalse(host.state.noteEditorHasContent, "前置：删回空，判据必须回到假")
        let cleared = try render(host, label: "03-cleared")

        // ③ 删回灰：**逐字节相同** —— 这一条与下面两条是「同一只按钮的三个样子」里的收口。
        XCTAssertEqual(
            changedPixels(empty, cleared, fromTop: 0).count, 0,
            "清空之后画出来与空态**不是同一张图** ⇒ 「删回灰」这一条不成立"
        )

        // ① 空着灰：按钮那一带只有灰墨水。
        let emptyBand = bandDarkest(empty)
        XCTAssertGreaterThanOrEqual(
            emptyBand, 80,
            "空编辑器上按钮那一带出现了深墨水（最暗亮度 \(emptyBand)，门槛 ≥ 80，实测基准 91）"
                + " ⇒ 「保存」在空编辑器上不减淡（队列 L-50 的回归）"
        )

        // ② 有内容亮：同一带里出现深墨水，且变的正是按钮那一带。
        let typedBand = bandDarkest(typed)
        XCTAssertLessThanOrEqual(
            typedBand, 60,
            "填了字之后按钮那一带**没有**变深（最暗亮度 \(typedBand)，门槛 ≤ 60，实测基准 36）"
                + " ⇒ 「保存」不会亮（有内容却存不下去）"
        )
        let buttonCluster = changedPixels(
            empty, typed, fromTop: Self.buttonBandFromTop, toTop: Self.buttonBandToTop
        )
        XCTAssertGreaterThanOrEqual(
            buttonCluster.count, 2000,
            "按钮那一带（y ∈ [\(Self.buttonBandFromTop), \(Self.buttonBandToTop))）只变了"
                + " \(buttonCluster.count) 个像素"
                + "（实测基准 5028）⇒ 「亮 / 灰」的变化没落在按钮上，判的是别的东西"
        )
        // 反证方向：变化**不许只**发生在别处（标题输入框那一域另外还有变化，那是我们填进去的那个字）。
        XCTAssertGreaterThan(
            buttonCluster.count, changedPixels(empty, typed, fromTop: 0).count - buttonCluster.count,
            "变化主要落在按钮之外 ⇒ 这一条判的不是按钮"
        )

        // 三张图留档（`.build/`，已在 `.gitignore`）：判据是像素，图是给人复看的。
        print("📷 notes-save-01-empty 最暗亮度 \(emptyBand)")
        print("📷 notes-save-02-typed 最暗亮度 \(typedBand) ／ 按钮带差异 \(buttonCluster.count) 像素")
        print("📷 notes-save-03-cleared 与空态差异 0 像素")
    }

    // MARK: - 渲染（**不进快照清单**：本条的判据是像素比较，不是「图长这样」）

    @MainActor
    private func render(_ host: Host, label: String) throws -> NSBitmapImageRep {
        let view = ZStack {
            Theme.surface(.window)
            NotesEditorView()
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .snapshotEnvironment(
            state: host.state,
            workspace: host.workspace,
            tabs: host.tabs,
            terminal: host.terminal
        )
        return try renderPNG(view, label: "notes-save-\(label)", scheme: .aqua).rep
    }

    /// 把任意视图渲染成一张落盘 PNG（`.build/ui-snapshot-state/<label>.png`），返回位图与路径。
    ///
    /// **为什么要有它**（队列 `L-142` 那一批）：同一条渲染路径要跑三种外观（浅色 / 深色 / 对照件），
    /// 各写一遍会出现「三份真相」——底面渲染的差异（窗口 / 布局 / 位图）会伪装成判据的差异。
    @MainActor
    private func renderPNG<V: View>(
        _ view: V, label: String, scheme: NSAppearance.Name
    ) throws -> (rep: NSBitmapImageRep, path: String) {
        let size = Self.size
        // 正文编辑器是 AppKit 自绘（`TextEditor` → 真 `NSTextView`）：没有真实窗口就画不出内容
        // （与 `UISnapshotSidebarStateTests` 同一条实测），所以给一个**不上屏**的 borderless 窗口。
        let appearance = NSAppearance(named: scheme)
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = appearance
        hosting.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = appearance
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((size.width * scale).rounded()),
            pixelsHigh: Int((size.height * scale).rounded()),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw UISnapshot.SnapshotError.renderFailed("位图分配失败")
        }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw UISnapshot.SnapshotError.encodeFailed(label)
        }
        // 空跑防护：一张什么都没有的图也编码得出来，所以给一个内容下限。
        XCTAssertGreaterThan(
            data.count, 20000,
            "\(label) 只有 \(data.count) 字节 —— 像是渲染成了空白（编辑器没画出来）"
        )
        let directory = UISnapshot.outputDirectory.deletingLastPathComponent()
            .appendingPathComponent("ui-snapshot-state", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(label).png")
        try data.write(to: url)
        return (rep, url.path)
    }

    // MARK: - 编辑面底色：系统底色真的让位了吗（队列 `L-142` · 内测清单 甲2）

    /// 取样矩形（**像素**坐标、左上原点、含 2× 缩放）：落在笔记正文编辑区**内部**、避开正文与边框。
    ///
    /// 坐标按本机实测定（视图 900×560pt ⇒ 1800×1120px）：编辑区从标题行 / 标题框 / 标签框之下开始、
    /// 到按钮行之上结束（空正文时区里只有左上角一个光标）⇒ 取右侧中部这一块，
    /// 点在字上、边框上、或别处都判不出来。
    private static let surfaceSample = (leading: 1000, top: 450, width: 700, height: 220)

    /// 判据：**渲染出来的笔记正文编辑面画的是主题令牌那一种底色**（内测清单 **甲2**）。
    ///
    /// 源码层由 `Scripts/check-editor-surface-tokens.py` 判「每处编辑面都挂 `.editorSurface()`、
    /// 唯一出处走令牌」；这一条补的是「**那几行真的生效了吗**」——
    /// 系统底色那层没让位的话，`.background(...)` 会被它压在底下（**画了等于没画，源码判据看不出来**）。
    ///
    /// **为什么必须深色**：浅色下 `Surface.content` 就是 **纯白 `0xFFFFFF`**，与系统
    /// `textBackgroundColor`（也是纯白）**逐通道相同** ⇒ 浅色判据是**假绿**；
    /// 深色下两者分别是 `palette.content` 的深色值（科技蓝 **`0x0B1A2A`**）与系统的近中性深灰，
    /// 一取色就分得开（内测报的正是深色下的「不成套」）。
    ///
    /// 同一族里带**对照件**：一个**没挂**修饰的裸 `TextEditor`，同一位置取色**必须不等于**令牌值 ——
    /// 对照不红 ⇒ 「相等」这一条根本判不动东西（同第 105 / 108 条的纪律）。
    @MainActor
    func testNoteEditorSurfacePaintsThemeToken() throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        _ = try UISnapshot.applyLicense(.standard, to: host.state)
        host.state.noteEditorTitle = ""
        host.state.noteEditorTags = ""
        host.state.noteEditorBody = ""

        let size = Self.size
        let scheme = NSAppearance.Name.darkAqua

        let editorView = ZStack {
            Theme.surface(.window)
            NotesEditorView()
        }
        .frame(width: size.width, height: size.height)
        .snapshotEnvironment(
            state: host.state,
            workspace: host.workspace,
            tabs: host.tabs,
            terminal: host.terminal
        )
        let (_, editorPath) = try renderPNG(editorView, label: "notes-surface-dark", scheme: scheme)

        // 对照件：内测甲2 的原样（`TextEditor` 自带系统底色，没挂 `.editorSurface()`）。
        let controlView = ZStack {
            Theme.surface(.window)
            VStack { TextEditor(text: .constant("")) }
                .padding(Spacing.l)
        }
        .frame(width: size.width, height: size.height)
        let (_, controlPath) = try renderPNG(controlView, label: "notes-surface-control-dark", scheme: scheme)

        let expected = UISnapshot.channels(
            of: DesignThemeManager.shared.theme.palette.content.hex(dark: true)
        )
        let sample = Self.surfaceSample

        guard let editorBand = UISnapshot.region(
            ofPNGAt: editorPath, leading: sample.leading, top: sample.top,
            width: sample.width, height: sample.height
        ), let controlBand = UISnapshot.region(
            ofPNGAt: controlPath, leading: sample.leading, top: sample.top,
            width: sample.width, height: sample.height
        ) else {
            XCTFail("取样矩形落在图外了 —— 坐标按本机实测定（1800×1120px），改尺寸要重定")
            return
        }

        let editor = (Int(editorBand.background.0), Int(editorBand.background.1), Int(editorBand.background.2))
        let control = (Int(controlBand.background.0), Int(controlBand.background.1), Int(controlBand.background.2))
        print("🎨 编辑面底色（深色）：笔记正文 \(editor) / 令牌 \(expected) / 对照裸 TextEditor \(control)")

        // ① 笔记正文编辑区 = 主题令牌那一种底色（容差 8：PNG 往返实测偏移 ≤4，见 `sampledRGB` 的注释）。
        for (name, actual, want) in [
            ("R", editor.0, expected.red), ("G", editor.1, expected.green), ("B", editor.2, expected.blue),
        ] {
            XCTAssertLessThanOrEqual(
                abs(actual - want), 8,
                "笔记正文编辑区的 \(name) 通道实测 \(actual)、令牌 \(want) —— 编辑面没走主题令牌"
                    + "（内测清单甲2 的原病：它画的是系统 textBackgroundColor）"
            )
        }

        // ② 对照件必须判得出「不一样」，否则上面那三条是假绿。
        let controlDelta = max(
            abs(control.0 - expected.red),
            max(abs(control.1 - expected.green), abs(control.2 - expected.blue))
        )
        XCTAssertGreaterThan(
            controlDelta, 8,
            "对照件（没挂 `.editorSurface()` 的裸 TextEditor）在这套量法下取到的底色 \(control)"
                + " 与令牌 \(expected) 差不出 8 以上 ⇒ 这条量法分辨不了两种底色，笔记那三条不算数"
        )
    }

    // MARK: - N2-4 自动保存（停顿即存 + 切走即存 + 失败可见 + 无弹窗）

    /// 夹具：写 N 条笔记进**临时**笔记库，并把笔记能力打开。
    ///
    /// **先在临时家里再写**：`DOYAH_NOTES_DIR` 不在场就跳过（`setUpWithError` 已经把住）——
    /// 探针不许往真实用户数据家写夹具（与 `UISnapshotPanelsTests` / `NotesLayoutProbeTests` 同一条纪律）。
    @MainActor
    private func seedAutosaveNotes(_ state: AppState, titles: [String]) async throws -> [Note] {
        let load = try UISnapshot.applyLicense(.standard, to: state)
        XCTAssertEqual(load.entitlements.basis, .licensed, "临时许可证没落地 ⇒ 下面读不到笔记能力")
        XCTAssertTrue(state.notesEnabled, "Standard 档必须带笔记能力（capabilities.notes）")
        var created: [Note] = []
        for (index, title) in titles.enumerated() {
            created.append(
                try await NoteLibrary.defaultLibrary().upsert(
                    NoteDraft(title: title, body: "夹具正文 \(index)")
                )
            )
        }
        await state.reloadNotes()
        return created
    }

    /// **独立连接**读回一条笔记：另开一个 `NoteLibrary`（同一路径、另一个实例）。
    ///
    /// 为什么不用 `AppState.notes`：那是内存态 —— 拿它判「已经存到库里了」等于自己判自己
    /// （判据③「强杀之后内容还在」要的正是「盘上那一份」）。
    private func readBackFromLibrary(_ id: UUID) async throws -> Note? {
        let library = NoteLibrary(databaseURL: NoteLibrary.defaultDatabaseURL())
        return try await library.load().first { $0.id == id }
    }

    /// ## N2-4 判据③（**强杀等价物**）＋ 判据①的「停顿」那一半
    ///
    /// 「编辑 → **不做任何离开动作** → 内容已经在盘上」。为什么这一条就是 `kill -9` 等价物：
    /// `kill -9` 只丢**内存**里那一份，盘上那份是自动保存已经 `COMMIT` 掉的（SQLite 的写是一个事务）；
    /// 所以「没有任何退出 / 切走路径，停顿窗口一到内容就落库」成立 ⇒ 强杀之后重开读到的就是它。
    /// **成对读数**（两遍都读盘）：打字之后（还没到停顿窗口）→ 库里还是旧的；窗口到了 → 库里是新的。
    @MainActor
    func testN24AutosavePersistsOnPauseWithoutAnyExitPath() async throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        let seeded = try await seedAutosaveNotes(host.state, titles: ["N2-4 停顿即存夹具"])
        let note = try XCTUnwrap(seeded.first, "夹具没落库")

        host.state.edit(note)
        XCTAssertEqual(
            host.state.noteSaveState, .idle,
            "前置：刚装进编辑器就该是「没有未落库的改动」（`setNoteEditorContent` 那一道闸）"
        )

        let typed = "自动保存·停顿即存·\(UUID().uuidString)"
        host.state.noteEditorBody = typed
        XCTAssertEqual(
            host.state.noteSaveState, .pending,
            "改了一个字之后状态不是「未保存」⇒ 自动保存的判据根本立不起来"
        )

        // 成对读数①：还没到停顿窗口 —— **盘上**那一份还是旧的。
        let before = try await readBackFromLibrary(note.id)
        XCTAssertNotEqual(
            before?.body, typed,
            "还没到停顿窗口，盘上就已经是新内容了 ⇒ 这一段量的不是「停顿即存」"
        )

        // 只等停顿窗口 —— **不点任何东西**（这一条就是要证明「没有退出路径也会落库」）。
        await host.state.awaitPendingNoteAutosave()

        // 成对读数②：盘上那一份已经是新的了。
        let after = try await readBackFromLibrary(note.id)
        XCTAssertEqual(
            after?.body, typed,
            "停顿窗口到了（约 \(NoteAutosave.pauseWindow)）而盘上还是旧内容 ⇒ 停顿即存没落地"
        )
        XCTAssertEqual(host.state.noteSaveState, .idle, "写完 ⇒ 状态要回到「没有未落库的改动」")
        XCTAssertGreaterThan(
            after?.updatedAt ?? .distantPast, before?.updatedAt ?? .distantPast,
            "盘上那份的时间戳没往前走 ⇒ 这一条读到的可能还是写之前那一份"
        )
        print(
            "🧷 N2-4 ③ 停顿即存（无任何退出/切走动作）：独立连接读回正文 = 「\(after?.body ?? "nil")」"
                + "（写前 = 「\(before?.body ?? "nil")」）"
        )
    }

    /// ## N2-4 判据①②：**切走即存**（同一篇重开 / 换一篇再回来）
    ///
    /// 两半都在**盘上**判（独立连接），不是读内存：
    ///   ① 编辑 → **直接返回列表**（点同一条 = 单击进预览）→ 重开该篇 ⇒ 内容在；
    ///   ② 编辑 → **点选另一篇** → 回原篇 ⇒ 内容已存。
    @MainActor
    func testN24LeavingTheNoteFlushesImmediately() async throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        let seeded = try await seedAutosaveNotes(host.state, titles: ["N2-4 切走即存甲", "N2-4 切走即存乙"])
        let first = try XCTUnwrap(seeded.first, "夹具甲没落库")
        let second = try XCTUnwrap(seeded.last, "夹具乙没落库")
        XCTAssertNotEqual(first.id, second.id, "两篇夹具是同一条 —— 判据②「换一篇」就无从谈起")

        // ── ① 编辑 → 直接返回列表 → 重开该篇 ─────────────────────────────────────
        host.state.edit(first)
        let typed = "自动保存·切走即存甲·\(UUID().uuidString)"
        host.state.noteEditorBody = typed
        XCTAssertEqual(host.state.noteSaveState, .pending, "前置：有未落库的改动")

        host.state.handleNoteRowClick(first, modifiers: [])  // 无修饰单击 = 打开这一条（进预览）
        XCTAssertEqual(
            host.state.noteEditorBody, typed,
            "① 点回同一条之后编辑器里立刻不是刚写的那一份 ⇒ 「读完就没了」那一路又回来了"
        )
        await host.state.awaitPendingNoteAutosave()
        let storedAfterLeaving = try await readBackFromLibrary(first.id)
        XCTAssertEqual(
            storedAfterLeaving?.body, typed,
            "① 返回列表那一下没有把改动落库（盘上还是旧的）"
        )
        XCTAssertEqual(host.state.noteSaveState, .idle, "① 落库之后状态要回到干净")

        // 重开该篇：**从库里重新读**（把内存那份换掉），再点开它。
        await host.state.reloadNotes()
        let reopened = try XCTUnwrap(
            host.state.notes.first { $0.id == first.id }, "重读之后找不到那一篇了"
        )
        XCTAssertEqual(reopened.body, typed, "① 重读回来的正文不是刚写的那一份")
        host.state.handleNoteRowClick(reopened, modifiers: [])
        XCTAssertEqual(host.state.noteEditorBody, typed, "① 重开该篇之后编辑器里就是它")

        // ── ② 编辑 → 点选另一篇 → 回原篇 ⇒ 内容已存 ───────────────────────────────
        host.state.edit(reopened)
        let typedAgain = "自动保存·切走即存甲·第二遍·\(UUID().uuidString)"
        host.state.noteEditorBody = typedAgain
        XCTAssertEqual(host.state.noteSaveState, .pending, "前置：第二遍也有未落库的改动")

        host.state.handleNoteRowClick(second, modifiers: [])
        XCTAssertEqual(
            host.state.noteEditorBody, second.body,
            "② 点另一篇之后编辑器里不是那一篇 ⇒ 下面那条断言看的不是「换走」这件事"
        )
        await host.state.awaitPendingNoteAutosave()
        let storedSecond = try await readBackFromLibrary(first.id)
        XCTAssertEqual(
            storedSecond?.body, typedAgain,
            "② 点走之后原篇那一份没落库"
        )

        let backToFirst = try XCTUnwrap(host.state.notes.first { $0.id == first.id }, "① 的夹具不见了")
        host.state.handleNoteRowClick(backToFirst, modifiers: [])
        XCTAssertEqual(
            host.state.noteEditorBody, typedAgain,
            "② 回原篇之后编辑器里不是已存的那一份"
        )
        print(
            "🧷 N2-4 ①② 切走即存：两半都从独立连接读回 —— ①「\(storedAfterLeaving?.body ?? "nil")」"
                + " ②「\(storedSecond?.body ?? "nil")」"
        )
    }

    /// ## N2-4 判据⑥：**自动保存失败路径有可见线索**（并同时判判据④「全程无弹窗」）
    ///
    /// 触发方式（可复跑）：把临时笔记库那个目录 + 库文件**改成只读** —— 下一次写库必失败
    /// （SQLite 连 `-journal` 都建不出来）。判据四条：
    ///   ① 状态那一格进 `.failed` 且**带一句原因**（工具条那一枚画的就是它）；
    ///   ② 状态栏那句里有「自动保存失败」（第二个可见线索）；
    ///   ③ **不弹框**：`errorMessage`（那个框的开关）必须还是 `nil` —— 验收判据④；
    ///   ④ **改动没丢**：编辑器里还是刚敲的那一份（失败不等于把内容也抹了）。
    /// 另加**反向对照**：同一条坏路上手动「保存」**仍然**给那个可复制的框 ——
    /// 否则「上面第 ③ 条是绿的」也可能只是因为「压根没在写」。
    @MainActor
    func testN24FailureIsVisibleAndNeverAPopup() async throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        let seeded = try await seedAutosaveNotes(host.state, titles: ["N2-4 失败路径夹具"])
        let note = try XCTUnwrap(seeded.first, "夹具没落库")

        host.state.edit(note)
        let typed = "自动保存·失败路径·\(UUID().uuidString)"
        host.state.noteEditorBody = typed

        let directory = NoteLibrary.defaultDirectory()
        let databaseURL = NoteLibrary.defaultDatabaseURL()
        let fileManager = FileManager.default
        // 先记下原权限，判完**一定**还回去（否则临时数据家删不掉、下一轮清不干净）。
        let directoryPermissions = (try? fileManager.attributesOfItem(atPath: directory.path)[.posixPermissions]) as? NSNumber
        let filePermissions = (try? fileManager.attributesOfItem(atPath: databaseURL.path)[.posixPermissions]) as? NSNumber
        defer {
            try? fileManager.setAttributes(
                [.posixPermissions: directoryPermissions ?? NSNumber(value: 0o755)], ofItemAtPath: directory.path
            )
            try? fileManager.setAttributes(
                [.posixPermissions: filePermissions ?? NSNumber(value: 0o644)], ofItemAtPath: databaseURL.path
            )
        }
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o555)], ofItemAtPath: directory.path)
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o444)], ofItemAtPath: databaseURL.path)
        print("🧷 N2-4 ⑥ 触发方式：chmod 0555 \(directory.path) + chmod 0444 \(databaseURL.lastPathComponent)")

        await host.state.awaitPendingNoteAutosave()

        guard case .failed(let reason) = host.state.noteSaveState else {
            XCTFail("写库必失败的那条路上，状态还是 \(host.state.noteSaveState) ⇒ 失败没有出路（判据⑥）")
            return
        }
        XCTAssertFalse(reason.isEmpty, "失败那一档没有原因 ⇒ 工具条上那句话说不清「为什么没存上」")
        XCTAssertTrue(
            host.state.statusMessage.contains(L(.notesAutoSaveFailed)),
            "状态栏里没有「\(L(.notesAutoSaveFailed))」那句：实测「\(host.state.statusMessage)」"
        )
        XCTAssertNil(
            host.state.errorMessage,
            "自动保存失败弹了框（`errorMessage` 是那个框的开关）⇒ 验收判据④「全程无弹窗」不成立"
        )
        XCTAssertEqual(host.state.noteEditorBody, typed, "失败之后编辑器里那一份被抹掉了 —— 改动丢了")

        // 反向对照：同一条坏路上，手动「保存」仍然给那个可复制的框。
        await host.state.saveNoteFromEditor()
        XCTAssertNotNil(
            host.state.errorMessage,
            "反向对照不成立：同一条坏路上手动保存也没报错 ⇒ 上面「没弹框」那一条是假绿"
        )
        host.state.errorMessage = nil
        print("🧷 N2-4 ⑥ 失败可见：state=\(host.state.noteSaveState) 原因=「\(reason)」")
    }

    /// ## N2-4 判据⑤：**工具条保存状态键存在且可读**
    ///
    /// 「键」两头都要可读：
    ///   · **文案键**（`LKey`）：三态各一个、`idle` 不占地方；两个语言都没缺（缺一语言 = 死键）；
    ///   · **界面锚点**：工具条那一行读的就是 `appState.noteSaveState`，标识唯一出处是
    ///     `NoteAutosave.statusIdentifier`（源锚点，从仓里真读源码来判 —— 不把锚点抄进判据）。
    /// 再加**渲染级**一条：`.pending` 那一档真的画了东西 —— 与「已经写完、内容还在」那一态比，
    /// 唯一的差别就是那一枚状态字，两图必须不一样（按钮在两边都是亮的）。
    @MainActor
    func testN24ToolbarSaveStateKeyIsReadable() async throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        let seeded = try await seedAutosaveNotes(host.state, titles: ["N2-4 状态键夹具"])
        let note = try XCTUnwrap(seeded.first, "夹具没落库")

        // ① 三态各有键；`idle` 不画（没有未落库的改动就不占地方）。
        XCTAssertNil(NoteSaveState.idle.languageKey, "`idle` 不该有状态文字 —— 常态下多一行永远亮着的字看不出问题")
        let keyed: [NoteSaveState] = [.pending, .saving, .failed("原因")]
        for state in keyed {
            let key = try XCTUnwrap(state.languageKey, "\(state) 没有文案键")
            let chinese = LocalizedStrings.text(key, language: .simplifiedChinese)
            let english = LocalizedStrings.text(key, language: .english)
            XCTAssertFalse(chinese.isEmpty, "\(key) 缺中文")
            XCTAssertFalse(english.isEmpty, "\(key) 缺英文")
            XCTAssertNotEqual(chinese, english, "\(key) 中英一模一样 ⇒ 语言表那一半没落地")
            XCTAssertNotEqual(chinese, key.rawValue, "\(key) 在语言表里查不到（回落成了键名）")
        }
        XCTAssertEqual(NoteAutosave.statusIdentifier, "notes-editor-save-state", "状态那一格的可读名字被改了")

        // ② 源锚点：工具条读的就是这一份状态（判据与界面认同一个名字）。
        let root = Self.repositoryRoot
        let panel = try String(contentsOf: root.appendingPathComponent("App/Views/NotesPanel.swift"), encoding: .utf8)
        XCTAssertTrue(
            panel.contains("appState.noteSaveState.languageKey"),
            "`NotesPanel.swift` 里找不到「按状态取文案键」那一处 —— 工具条没有再读这份状态"
        )
        XCTAssertTrue(
            panel.contains("NoteAutosave.statusIdentifier"),
            "`NotesPanel.swift` 里找不到 `NoteAutosave.statusIdentifier` —— 状态那一格没有可读名字"
        )
        let appState = try String(contentsOf: root.appendingPathComponent("App/AppState.swift"), encoding: .utf8)
        for anchor in ["flushNoteAutosave()", "awaitPendingNoteAutosave()", "NoteAutosave.pauseWindow", "@Published private(set) var noteSaveState"] {
            XCTAssertTrue(appState.contains(anchor), "`AppState.swift` 里找不到「\(anchor)」—— 自动保存的接线掉了")
        }
        // 判据④的另一半（源码级）：自动保存这条路上**不许**出现弹框入口。
        let autosaveRegion = Self.sourceRegion(
            in: appState,
            from: "// MARK: - 自动保存（片 `N2-4` · 停顿即存 + 切走即存）",
            to: "func deleteNote(id: UUID) async"
        )
        XCTAssertFalse(autosaveRegion.isEmpty, "截不出自动保存那一段源码 —— 锚点被改了（判据自己失效）")
        for forbidden in [".alert(", "confirmationDialog(", "NSAlert"] {
            XCTAssertFalse(
                autosaveRegion.contains(forbidden),
                "自动保存那一段里出现了 `\(forbidden)` —— 验收判据④「全程无弹窗」"
            )
        }

        // ③ 渲染级：`.pending` 那一档真的画在工具条上。
        host.state.edit(note)
        host.state.noteEditorTitle = "临"
        XCTAssertEqual(host.state.noteSaveState, .pending, "前置：打字之后应当是「未保存」")
        let pending = try render(host, label: "04-autosave-pending")
        await host.state.awaitPendingNoteAutosave()
        XCTAssertEqual(host.state.noteSaveState, .idle, "写完 ⇒ 状态回到干净（这一态就是上面那一态的对照）")
        XCTAssertEqual(host.state.noteEditorTitle, "临", "对照态要求内容都还在 —— 两边只有那一枚状态字不同")
        let saved = try render(host, label: "05-autosave-idle")

        let band = changedPixels(
            pending, saved, fromTop: Self.buttonBandFromTop, toTop: Self.buttonBandToTop
        )
        XCTAssertGreaterThan(
            band.count, 0,
            "「未保存 / 已写完」两态在工具条那一带上逐像素相同 ⇒ 状态那一格没有真的画出来"
        )
        print(
            "🧷 N2-4 ⑤ 状态那一格：pending 最暗 \(bandDarkest(pending)) / 已写完最暗 \(bandDarkest(saved))"
                + " ／ 工具条带差异 \(band.count) 像素"
        )
    }

    // MARK: - N2-4 判据③ 的**进程级**那一半：真的 `SIGKILL` 自己

    /// 交接单：phase 1 把「哪一条笔记、期望正文」写下来给 phase 2 读。
    private struct Kill9Handoff: Codable {
        let noteID: UUID
        let expectedBody: String
        let databasePath: String
    }

    /// phase 1 要用的环境变量（驱动脚本 `Scripts/test-note-autosave-kill9.sh` 设它）。
    private static let kill9PhaseKey = "DOYAH_AUTOSAVE_KILL9"
    private static let kill9HandoffKey = "DOYAH_AUTOSAVE_KILL9_HANDOFF"

    /// **phase 1：打字 → 等停顿窗口 → 真的 `SIGKILL` 自己**。
    ///
    /// 为什么是 `kill(getpid(), SIGKILL)` 而不是「退出」：`SIGKILL` **不可捕获、不给任何收尾机会**
    /// —— 与用户从活动监视器里「强制退出」是同一条路（`kill -9 <pid>` 就是发它）。
    /// 于是「重开之后内容还在」这句话就只能靠**盘上那一份**成立，别的解释全被堵死。
    ///
    /// 默认跳过（`DOYAH_AUTOSAVE_KILL9` 不在场 ⇒ `XCTSkip`）：这一条会**把自己所在的进程杀掉**，
    /// 绝不能混进常规探针跑（那会把 `swift test` 的收尾也一起带走）。
    @MainActor
    func testN24Kill9PhaseOneTypeThenForceKill() async throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            environment[Self.kill9PhaseKey] == "type",
            "进程级那条要显式打开：`\(Self.kill9PhaseKey)=type`（驱动脚本在 Scripts/）"
        )
        let handoffPath = try XCTUnwrap(
            environment[Self.kill9HandoffKey],
            "没给交接单路径（`\(Self.kill9HandoffKey)`）⇒ 强杀之后那一遍读不到「期望什么」"
        )

        let host = makeHost()
        let seeded = try await seedAutosaveNotes(host.state, titles: ["N2-4 强杀夹具"])
        let note = try XCTUnwrap(seeded.first, "夹具没落库")
        host.state.edit(note)
        let typed = "自动保存·强杀·\(UUID().uuidString)"
        host.state.noteEditorBody = typed

        // 等停顿窗口：**不做任何离开 / 退出动作**（这一条要证明的就是「没人做任何事也落库了」）。
        await host.state.awaitPendingNoteAutosave()
        try await readBackFromLibrary(note.id)  // 落库自证：读得回来才写交接单

        let handoff = Kill9Handoff(
            noteID: note.id,
            expectedBody: typed,
            databasePath: NoteLibrary.defaultDatabaseURL().path
        )
        try JSONEncoder().encode(handoff).write(to: URL(fileURLWithPath: handoffPath))
        print("🧷 N2-4 ③ phase 1：已落库并写好交接单，接下来 `SIGKILL` 自己（pid \(getpid())）")
        // **必须刷新**：这一行之后进程就要被 `SIGKILL` 带走，而 stdout 重定向到文件时是块缓冲 ——
        // 不刷新的话读数会跟着缓冲区一起消失（实测：驱动脚本看不到这一行，只能判「没跑到」）。
        fflush(stdout)

        kill(getpid(), SIGKILL)
        // 到不了这儿 —— `SIGKILL` 不可捕获（留这一行是给读代码的人看的）。
        XCTFail("`SIGKILL` 之后还活着 ⇒ 这一条没有真的强杀")
    }

    /// **phase 2：另起一个进程**读交接单 + 读盘，断言「最近一次自动保存的内容在」。
    @MainActor
    func testN24Kill9PhaseTwoReadBackAfterForceKill() async throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            environment[Self.kill9PhaseKey] == "read",
            "phase 2 要显式打开：`\(Self.kill9PhaseKey)=read`（驱动脚本在 Scripts/）"
        )
        let handoffPath = try XCTUnwrap(environment[Self.kill9HandoffKey], "没给交接单路径")
        let handoff = try JSONDecoder().decode(
            Kill9Handoff.self, from: try Data(contentsOf: URL(fileURLWithPath: handoffPath))
        )
        // **另开一个连接、另起一个进程**读盘 —— 上一个进程已经被 `SIGKILL` 带走了。
        let library = NoteLibrary(databaseURL: URL(fileURLWithPath: handoff.databasePath))
        let stored = try await library.load().first { $0.id == handoff.noteID }
        XCTAssertEqual(
            stored?.body, handoff.expectedBody,
            "强杀之后重开，盘上没有「最近一次自动保存」的内容 ⇒ 判据③不成立"
        )
        print("🧷 N2-4 ③ phase 2：强杀后重开，独立进程读回正文 = 「\(stored?.body ?? "nil")」")
    }

    // MARK: - N2-4 辅助：仓里真读源码

    /// 仓库根：`#filePath` = 本文件在仓里的绝对路径 ⇒ 上两级就是根。
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TestsUISnapshot
            .deletingLastPathComponent()  // 仓根
    }

    /// 截一段源码（首尾锚点都必须找得到；找不到给空串 —— 调用方会据此判红，
    /// 「锚点被改了」不许静默当作「那一段干干净净」）。
    private static func sourceRegion(in text: String, from start: String, to end: String) -> String {
        guard let startRange = text.range(of: start),
              let endRange = text.range(of: end, range: startRange.upperBound..<text.endIndex) else {
            return ""
        }
        return String(text[startRange.upperBound..<endRange.lowerBound])
    }

    // MARK: - 像素判读

    /// 两张图在 `y ∈ [fromTop, toTop)` 那一带里**变掉的像素**（含两侧的亮度，供断言消息里报读数）。
    /// `toTop = nil` ⇒ 一直到图底（判「整图变了多少」时用它）。
    ///
    /// 容差 8（RGB 绝对值之和）：抗锯齿与字体光栅化在两遍之间本来就可能有 1~2 的差，
    /// 而「灰 → 深」这种变化是几十上百的量级（实测 118 → 33）。
    private func changedPixels(
        _ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, fromTop: Int, toTop: Int? = nil
    ) -> [(x: Int, y: Int, left: Int, right: Int)] {
        guard let lData = lhs.bitmapData, let rData = rhs.bitmapData else { return [] }
        let lRow = lhs.bytesPerRow, rRow = rhs.bytesPerRow
        let spp = lhs.samplesPerPixel
        var out: [(Int, Int, Int, Int)] = []
        let end = min(toTop ?? lhs.pixelsHigh, lhs.pixelsHigh)
        for y in fromTop..<end {
            for x in 0..<lhs.pixelsWide {
                let li = y * lRow + x * spp
                let ri = y * rRow + x * spp
                let lr = Int(lData[li]), lg = Int(lData[li + 1]), lb = Int(lData[li + 2])
                let rr = Int(rData[ri]), rg = Int(rData[ri + 1]), rb = Int(rData[ri + 2])
                let delta = abs(lr - rr) + abs(lg - rg) + abs(lb - rb)
                if delta > 8 {
                    out.append((x, y, luminance(lr, lg, lb), luminance(rr, rg, rb)))
                }
            }
        }
        return out.map { (x: $0.0, y: $0.1, left: $0.2, right: $0.3) }
    }

    /// 按钮那一带里**最暗的墨水亮度**（0 = 纯黑，255 = 纯白）。
    ///
    /// 为什么用「最暗」而不是平均：这一带（**顶部编辑工具条**，片 `N2-3b` 之后的位置）里
    /// 除了按钮还有一句灰色的来源提示（`L(.notesSourceHint)`），平均会把两者的差摊平；
    /// 而「灰着 / 亮着」的区别恰恰就在**最深的那一笔**上 —— 减淡的标签画不出深墨水。
    private func bandDarkest(_ rep: NSBitmapImageRep) -> Int {
        guard let data = rep.bitmapData else { return 255 }
        var darkest = 255
        for y in Self.buttonBandFromTop..<min(Self.buttonBandToTop, rep.pixelsHigh) {
            for x in 0..<rep.pixelsWide {
                let index = y * rep.bytesPerRow + x * rep.samplesPerPixel
                let value = luminance(
                    Int(data[index]), Int(data[index + 1]), Int(data[index + 2])
                )
                if value < darkest { darkest = value }
            }
        }
        return darkest
    }

    private func luminance(_ red: Int, _ green: Int, _ blue: Int) -> Int {
        (red * 299 + green * 587 + blue * 114) / 1000
    }
}
