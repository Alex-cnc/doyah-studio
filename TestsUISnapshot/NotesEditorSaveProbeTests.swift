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
///   ① **空着灰**：底部按钮那一带（y ≥ 1000，见下）**最暗墨水亮度 ≥ 80**（实测 **91**）；
///   ② **有内容亮**：填一个字之后，同一带出现深墨水（**≤ 60**，实测 **36**），
///      且**按钮那一带确实变了**（两态差异像素落在 y ≥ 1000 的 ≥ 2000 个，实测 **5028**）；
///   ③ **删回灰**：清空之后与空态**逐字节相同**（差异像素 **0**）—— 「删回灰」不是「看着差不多」。
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

    /// 按钮行落在图上哪一带：按本机实测（2× 渲染 ⇒ 1120 px 高，按钮行在 y ≈ 1030…1090）。
    /// 取 1000 当分界是**留了余量**的：只要按钮还在最后 120 px 里，这条带就成立。
    private static let buttonBandFromTop = 1000

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
        let buttonCluster = changedPixels(empty, typed, fromTop: Self.buttonBandFromTop)
        XCTAssertGreaterThanOrEqual(
            buttonCluster.count, 2000,
            "按钮那一带（y ≥ \(Self.buttonBandFromTop)）只变了 \(buttonCluster.count) 个像素"
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
        let size = Self.size
        let view = ZStack {
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

        // 正文编辑器是 AppKit 自绘（`TextEditor` → 真 `NSTextView`）：没有真实窗口就画不出内容
        // （与 `UISnapshotSidebarStateTests` 同一条实测），所以给一个**不上屏**的 borderless 窗口。
        let appearance = NSAppearance(named: .aqua)
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
        try data.write(to: directory.appendingPathComponent("notes-save-\(label).png"))
        return rep
    }

    // MARK: - 像素判读

    /// 两张图在 `y ≥ fromTop` 那一带里**变掉的像素**（含两侧的亮度，供断言消息里报读数）。
    ///
    /// 容差 8（RGB 绝对值之和）：抗锯齿与字体光栅化在两遍之间本来就可能有 1~2 的差，
    /// 而「灰 → 深」这种变化是几十上百的量级（实测 118 → 33）。
    private func changedPixels(
        _ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, fromTop: Int
    ) -> [(x: Int, y: Int, left: Int, right: Int)] {
        guard let lData = lhs.bitmapData, let rData = rhs.bitmapData else { return [] }
        let lRow = lhs.bytesPerRow, rRow = rhs.bytesPerRow
        let spp = lhs.samplesPerPixel
        var out: [(Int, Int, Int, Int)] = []
        for y in fromTop..<lhs.pixelsHigh {
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
    /// 为什么用「最暗」而不是平均：这一带上除了按钮还有一句灰色的来源提示
    /// （`L(.notesSourceHint)`），平均会把两者的差摊平；而「灰着 / 亮着」的区别恰恰
    /// 就在**最深的那一笔**上 —— 减淡的标签画不出深墨水（实测空态 91 / 有内容态 36 —— 2026-09-30 笔记正文补了主题底色后重测，原 34）。
    private func bandDarkest(_ rep: NSBitmapImageRep) -> Int {
        guard let data = rep.bitmapData else { return 255 }
        var darkest = 255
        for y in Self.buttonBandFromTop..<rep.pixelsHigh {
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
