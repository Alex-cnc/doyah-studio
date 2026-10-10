import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **笔记左栏顶部增改删图标 = 等距 + 精致**（`FR-NOTEUI-21` · 派单 `T-20261010-166` §三.3 ①②③）。
///
/// ## 由头（人类主人 2026-10-10 原话逐字）
///
/// 「**笔记左栏上面的增改删图标间距太大了，不够精致。**」
///
/// 改前实况（真机实拍 2026-10-10 20:08）：左栏顶部三枚入口 ＋ / ✏ / 🗑 走的是
/// `App/Views/ToolbarIcon.swift` 的 `ToolbarIconButton` —— 那套的**命中区是 28 × 22**、
/// **图标字号是 `Theme.font(.icon)` = 13pt**（与正文同字号）。于是 28pt 宽的命中区里只有
/// 一枚 13pt 的图形，相邻两枚之间**看得见的留白**接近 19pt（`28 − 13 + 4`）——
/// 这就是「间距太大、不够精致」量出来的那个东西。
///
/// ## 判据（§三.3 逐条落成可跑断言 · 每条都印读数）
///
/// · **① 相邻 frame 间距逐个 ≤ 8pt**：活宿主里把三枚命中区（`_FocusRingView`）的矩形
///   按 x 排出来，逐个算 `next.minX − prev.maxX` —— 每个都必须 ≤ 8pt；
/// · **② 间距方差 ≤ 1pt**：同一组间距的**方差**（总体方差，`Σ(x−μ)²/n`）必须 ≤ 1pt；
///   「等距」量到的就是它（三个间距 4 / 4 / 4 ⇒ 方差 0）；
/// · **③ 与 SQL 编辑区工具条并排截图比对**：两者都是同一个 `ToolbarIcon` ——
///   成对截图里那两行必须**逐枚同形**（同图标字号、同命中区高），
///   几何那一半由「两边的命中区高逐个相等」判住，给人看的那一半是并排图；
/// · **④ 热区 ≥ 28 × 28**（契约原文）：命中区宽高都不小于 28pt；
/// · **⑤ 图标 16–18pt**（契约原文）：**两半**都判 ——
///   · **字号那一半**：图标画多大这件事只有一个出处 `Metrics.toolbarIconSize`，
///     它必须落在 [16, 18] 且是 `TypeScale` 刻度上的值（契约那一档用的币值就是 pt 字号）；
///   · **像素那一半**：把这一行渲染成 PNG，把「不是背景」的像素按**列**聚成簇，
///     每一簇就是一枚图形；改前 / 改后同一批符号的**可见高度之比**必须逐枚等于**字号之比**。
///     只判字号常量会被「写对了但被 `.frame` / `imageScale` 压回去」骗过去；
///     只判「改后 > 改前」又会被「顺带放大一点点」骗过去 —— 所以两边都要，且用比值对表。
///
/// ## 能判红（否则「量不到」会被读成「都对」）
///
/// 反例 = **改动前那一版**（`legacyRow`：13pt 图标 + 28 × 22 命中区，逐字复刻改前形态）。
/// 同一套量法量它：命中区高 **22 < 28** ⇒ 判据 ④ 当场红；图形可见高度也矮一档 ⇒ 判据 ⑤ 红。
/// 也就是说这一族断言**真的判得动**，不是恒真的。
///
/// ## 边界（如实登记）
///
/// · **悬浮 / 点击那两下真鼠标**不在判据面里（离屏宿主里 SwiftUI 手势不响应合成事件，
///   与 `NotesLayoutProbeTests` / `NotesSearchRevealProbeTests` 登记的边界同源）；
/// · **量「看得见的留白」用的是像素**（判据 ⑤），而**判据 ①② 量的是命中区矩形** ——
///   两者刻意分开：契约里「相邻 ≤ 8pt」的主体是**入口控件的 frame**（命中区），
///   而「不够精致」那一句是**像素**上的观感。两把尺子都量、都印读数，不互相冒充；
/// · 不判观感（配色 / 圆角好不好看）—— 那是并排截图给人看的那一半；
/// · 不碰用户数据：笔记库由 `DOYAH_NOTES_DIR` 指到每轮清空的临时目录（没设就跳过）。
///
/// 跑法：
///   `DOYAH_UI_SNAPSHOT=1 DOYAH_NOTES_DIR=<临时目录> swift test --filter NotesCrudIconSpacingProbeTests`
final class NotesCrudIconSpacingProbeTests: XCTestCase {

    /// 宿主尺寸：与 `NotesLayoutProbeTests.areaSize` 同一个（三栏骨架的最小整窗内容宽）。
    private static let areaSize = CGSize(width: 1100, height: 700)

    /// 「左区顶部操作行」那一条带的高度（pt）：宿主上缘往下这么多。
    private static let actionRowBand: CGFloat = 60

    /// 入口图标那一簇的**右界**（pt）：改前/改后三枚都落在 `0 … 100`，紧随其后的
    /// 「查」那一格改前从 108 起 —— 取 **104** 把三枚与它分开（两侧都留得下）。
    private static let clusterRight: CGFloat = 104

    private typealias Host = (
        state: AppState, workspace: WorkspaceStore, tabs: WorkspaceTabsModel, terminal: TerminalModel
    )

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏渲染要显式打开：DOYAH_UI_SNAPSHOT=1（取证工具，不进每轮门禁）"
        )
        try XCTSkipIf(
            (ProcessInfo.processInfo.environment["DOYAH_NOTES_DIR"] ?? "").isEmpty,
            "本探针要起真 `AppState`（它读笔记库）⇒ 必须在临时数据家里跑：`DOYAH_NOTES_DIR` 没设就跳过"
        )
        try requireIsolatedNotesDirectory()
    }

    /// 同一族的收尾（队列 `L-185` ①）：单跑一族探针时没有别人替它写清单。
    override class func tearDown() {
        UISnapshot.finishManifestIfEnabled()
    }

    // MARK: - 装配

    @MainActor
    private func makeHost() -> Host {
        let scratch = UISnapshot.outputDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("ui-snapshot-scratch", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let state = AppState()
        state.connections = []
        state.selectedConnectionID = nil
        return (
            state,
            WorkspaceStore.shared,
            WorkspaceTabsModel(
                store: WorkspaceHistoryStore(
                    fileURL: scratch.appendingPathComponent("noteui-21-\(UUID().uuidString).json")
                )
            ),
            TerminalModel()
        )
    }

    /// 夹具要往笔记库写 / 读 ⇒ 必须在临时数据家里（口径与 `NotesLayoutProbeTests` 同一条）。
    private func requireIsolatedNotesDirectory() throws {
        try XCTSkipIf(
            (ProcessInfo.processInfo.environment["DOYAH_NOTES_DIR"] ?? "").isEmpty,
            "本用例要起真笔记库 ⇒ 必须在临时数据家里跑（`DOYAH_NOTES_DIR` 没设就跳过）"
        )
    }

    @MainActor
    private func environment<V: View>(_ view: V, _ host: Host) -> some View {
        view.snapshotEnvironment(
            state: host.state, workspace: host.workspace, tabs: host.tabs, terminal: host.terminal
        )
    }

    /// 笔记区那一份**真内容**（`NotesAreaView`：左区顶部操作行 + 三栏）。
    @MainActor
    private func notesArea(_ host: Host) -> AnyView {
        AnyView(environment(NotesAreaView(), host))
    }

    /// **改后**那一行（生产件）：三枚都走 `App/Views/ToolbarIcon.swift` 的 `ToolbarIconButton`
    /// —— 与 `NotesPanel.crudEntries` **同一个组件、同一个间距**（源锚点在判据那一半钉住）。
    @MainActor
    private func productionRow() -> AnyView {
        AnyView(
            HStack(spacing: Spacing.xs) {
                ToolbarIconButton(systemName: "plus", help: "notes-new") {}
                ToolbarIconButton(systemName: "pencil", help: "notes-edit") {}
                ToolbarIconButton(systemName: "trash", help: "notes-delete") {}
            }
            .padding(.leading, Spacing.s)
        )
    }

    /// **改前那一版的复刻件**（`N2-LW` / `notes-01` 那两条判据的同一个做法）：
    /// 13pt 图标 + 28 × 22 命中区 + 4pt 间距 —— 逐字复刻改前形态。
    ///
    /// 为什么必须有它：判据 ④⑤ 说的是「改后命中区 ≥28×28 / 图标 16–18pt」——
    /// 若量法自己恒读一个合格值（挑错了控件类 / 挑错了带），这两句话就没有内容。
    /// 复刻件用**同一条量法**量出「命中区高 22 / 图形更矮」，于是「改前 → 改后」这一对读数
    /// 才是判得动的。
    @MainActor
    private func legacyRow() -> AnyView {
        AnyView(
            HStack(spacing: Spacing.xs) {
                legacyIconButton("plus")
                legacyIconButton("pencil")
                legacyIconButton("trash")
            }
            .padding(.leading, Spacing.s)
        )
    }

    /// 改前那一枚：命中区 28 × 22、图标 13pt（= 改前的 `Theme.font(.icon)` / `TypeScale.bodySize`）。
    private func legacyIconButton(_ systemName: String) -> some View {
        Button {} label: {
            Image(systemName: systemName)
                .font(.system(size: TypeScale.bodySize, weight: .semibold))
                .foregroundStyle(Theme.text(.secondary))
                .frame(width: 28, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(systemName))
    }

    // MARK: - 量法（命中区矩形）

    private struct Frame {
        let className: String
        let rect: CGRect
    }

    /// 宿主上缘往下 `band` 那一条带里的**命中区**矩形（`_FocusRingView`），按 x 排。
    ///
    /// SwiftUI 的 `Button`（`.plain` + 图标）在离屏宿主里落成的就是 `_FocusRingView`
    /// （`NotesLayoutProbeTests` / 待办那两族的 dump 量到的都是它，28 × 22 那一层）。
    @MainActor
    private func hitFrames(
        in hosting: NSView,
        band: CGFloat = NotesCrudIconSpacingProbeTests.actionRowBand,
        within maxX: CGFloat? = nil
    ) -> [Frame] {
        UISnapshot.LiveHost<Never>.findViews(ofType: NSView.self, in: hosting)
            .filter { NSStringFromClass(type(of: $0)).contains("FocusRingView") }
            .compactMap { view in
                let rect = hosting.convert(view.bounds, from: view)
                guard !rect.isEmpty, rect.width > 1, rect.height > 1 else { return nil }
                let top = hosting.isFlipped ? rect.minY : hosting.bounds.height - rect.maxY
                guard top >= -1, top <= band else { return nil }
                if let maxX, rect.maxX > maxX { return nil }
                return Frame(className: NSStringFromClass(type(of: view)), rect: rect)
            }
            .sorted { $0.rect.minX < $1.rect.minX }
    }

    /// 相邻两个矩形的**间距**（`next.minX − prev.maxX`）。
    private func gaps(_ frames: [Frame]) -> [CGFloat] {
        guard frames.count > 1 else { return [] }
        return (1..<frames.count).map { frames[$0].rect.minX - frames[$0 - 1].rect.maxX }
    }

    /// 总体方差（`Σ(x−μ)²/n`）。「间距方差 ≤ 1pt」量的就是它。
    private func variance(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / CGFloat(values.count)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / CGFloat(values.count)
    }

    private func pt(_ value: CGFloat) -> String { String(format: "%.1f", value) }

    private func describe(_ frames: [Frame]) -> String {
        frames.map { "\($0.className.split(separator: ".").last.map(String.init) ?? $0.className)"
            + " x=[\(pt($0.rect.minX))…\(pt($0.rect.maxX))] y=[\(pt($0.rect.minY))…\(pt($0.rect.maxY))]"
            + " (\(pt($0.rect.width))×\(pt($0.rect.height)))" }
            .joined(separator: " ｜ ")
    }

    // MARK: - 量法（像素：图形真的画了多大）

    /// 一枚图形在像素上的**可见画幅**（pt）。
    private struct InkCluster {
        let minX: CGFloat
        let maxX: CGFloat
        /// 图形的可见高度（pt）—— 竖直朝向不影响它（两种行序数出来一样）。
        let height: CGFloat
        var width: CGFloat { maxX - minX }
    }

    /// 把一张 PNG 里「不是背景」的像素按**列**聚成簇；每一簇 = 一枚图形。
    ///
    /// 背景 = 整幅图里出现次数最多的那个颜色；某像素与它三通道差的和 > 0.10 即算「墨迹」。
    /// 只在**整幅图**上做（判据用的那几张图里除了这几枚图形什么都没有），
    /// 于是不必依赖 PNG 的行序朝向。
    private func inkClusters(pngAt path: String, scale: CGFloat) throws -> [InkCluster] {
        let rep = try XCTUnwrap(
            NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: path))),
            "读不回刚渲染的 PNG：\(path)"
        )
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        XCTAssertGreaterThan(width, 0); XCTAssertGreaterThan(height, 0)

        func components(_ x: Int, _ y: Int) -> (Double, Double, Double) {
            guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return (0, 0, 0) }
            return (Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent))
        }

        // ① 出现最多的颜色 = 背景。
        var histogram: [UInt32: Int] = [:]
        var pixels: [(Double, Double, Double)] = []
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                let rgb = components(x, y)
                pixels.append(rgb)
                let key = UInt32(rgb.0 * 255) << 16 | UInt32(rgb.1 * 255) << 8 | UInt32(rgb.2 * 255)
                histogram[key, default: 0] += 1
            }
        }
        guard let backgroundKey = histogram.max(by: { $0.value < $1.value })?.key else { return [] }
        let background = (
            Double((backgroundKey >> 16) & 0xFF) / 255,
            Double((backgroundKey >> 8) & 0xFF) / 255,
            Double(backgroundKey & 0xFF) / 255
        )

        // ② 逐列数墨迹像素。
        func isInk(_ rgb: (Double, Double, Double)) -> Bool {
            abs(rgb.0 - background.0) + abs(rgb.1 - background.1) + abs(rgb.2 - background.2) > 0.10
        }
        var columnInk = [Int](repeating: 0, count: width)
        var columnRows = [[Int]](repeating: [], count: width)
        for y in 0..<height {
            for x in 0..<width where isInk(pixels[y * width + x]) {
                columnInk[x] += 1
                columnRows[x].append(y)
            }
        }

        // ③ 连成一簇的列 = 一枚图形（阈值 2：滤掉抗锯齿的单像素毛刺）。
        var clusters: [InkCluster] = []
        var start: Int? = nil
        for x in 0...width {
            let hasInk = x < width && columnInk[x] >= 2
            if hasInk, start == nil { start = x }
            if !hasInk, let from = start {
                let rows = (from..<x).flatMap { columnRows[$0] }
                clusters.append(
                    InkCluster(
                        minX: CGFloat(from) / scale,
                        maxX: CGFloat(x) / scale,
                        height: rows.isEmpty ? 0 : CGFloat((rows.max()! - rows.min()! + 1)) / scale
                    )
                )
                start = nil
            }
        }
        return clusters
    }

    // MARK: - 判据 ① ② ④：命中区与间距（活宿主 · 真笔记区）

    /// **左区顶部那三枚入口：等距、相邻 ≤ 8pt、热区 ≥ 28 × 28。**
    ///
    /// 四个读数都在**同一个活宿主实例**上量出来（真 `NotesAreaView`）⇒ 判据自足，
    /// 不靠回执里手抄一个数。反例见类头注释（改动前那一版判据 ④ 当场红）。
    @MainActor
    func testCrudEntryIconsAreEquidistantWithinEightPoints() throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        let load = try UISnapshot.applyLicense(.standard, to: host.state)
        XCTAssertEqual(load.entitlements.basis, .licensed, "临时许可证没落地 ⇒ 笔记区渲染不出来")
        XCTAssertTrue(host.state.notesEnabled, "Standard 档必须带笔记能力（capabilities.notes）")

        let live = UISnapshot.LiveHost(notesArea(host), size: Self.areaSize)
        live.pump(0.6)

        let frames = hitFrames(in: live.hosting, within: Self.clusterRight)
        print("NOTEUI-21 ① 左区顶部入口 dump（\(frames.count) 件）：\(describe(frames))")
        XCTAssertEqual(
            frames.count, 3,
            "左区顶部那一簇入口不是三枚（实测 \(frames.count) 枚）—— 量法挑错了带 / 控件类"
                + "（dump：\(describe(frames))）"
        )

        let spacing = gaps(frames)
        let spread = variance(spacing)
        print("NOTEUI-21 ① 相邻间距 \(spacing.map { pt($0) })pt ｜ 方差 \(String(format: "%.3f", spread))pt²"
              + " ｜ 热区 \(frames.map { "\(pt($0.rect.width))×\(pt($0.rect.height))" })")

        for (index, gap) in spacing.enumerated() {
            XCTAssertLessThanOrEqual(
                gap, 8,
                "第 \(index + 1) 与第 \(index + 2) 枚之间 \(pt(gap))pt > 8pt —— 「相邻 ≤ 8pt」没落地"
            )
        }
        XCTAssertLessThanOrEqual(
            spread, 1,
            "间距方差异 \(String(format: "%.3f", spread))pt² > 1 —— 三枚没有等距"
                + "（实测间距 \(spacing.map { pt($0) })pt）"
        )
        for (index, frame) in frames.enumerated() {
            XCTAssertGreaterThanOrEqual(
                frame.rect.width, 28,
                "第 \(index + 1) 枚的命中区只有宽 \(pt(frame.rect.width))pt < 28pt（契约「热区 ≥ 28 × 28」）"
            )
            XCTAssertGreaterThanOrEqual(
                frame.rect.height, 28,
                "第 \(index + 1) 枚的命中区只有高 \(pt(frame.rect.height))pt < 28pt（契约「热区 ≥ 28 × 28」）"
                    + " —— 改前那一版是 28 × 22"
            )
        }

        try writeEvidence("crud-gaps-dump", [
            "entryCount": frames.count,
            "frames": frames.map { ["x0": pt($0.rect.minX), "x1": pt($0.rect.maxX),
                                    "y0": pt($0.rect.minY), "y1": pt($0.rect.maxY),
                                    "w": pt($0.rect.width), "h": pt($0.rect.height)] },
            "gaps": spacing.map { pt($0) },
            "gapVariance": String(format: "%.3f", spread),
            "maxGap": pt(spacing.max() ?? 0),
            "clusterRight": pt(Self.clusterRight),
        ])
    }

    // MARK: - 判据 ⑤：图标尺寸（像素）＋ 改前 / 改后成对读数

    /// **图标 16–18pt 是「画出来的」而不是「写着的」** —— 走像素。
    ///
    /// 成对读数：改前复刻件（13pt 图标 + 28 × 22 命中区）与改后生产件（`ToolbarIconButton`）
    /// 各渲染一遍，同一套量法量图形的**可见高度**与命中区高。改前那一边必须**矮一档**
    /// 且命中区高 < 28，否则这一族断言是恒真的。
    @MainActor
    func testIconAndHitAreaSizesAreTheSameOnEveryToolbar() throws {
        let size = CGSize(width: 200, height: 44)

        let legacy = try UISnapshot.write("noteui-21-legacy-entry-row", size: size, scale: 2) { legacyRow() }
        let current = try UISnapshot.write("noteui-21-entry-icon-row", size: size, scale: 2) { productionRow() }

        let legacyClusters = try inkClusters(pngAt: legacy.file, scale: 2)
        let currentClusters = try inkClusters(pngAt: current.file, scale: 2)
        print("NOTEUI-21 ⑤ 改前（复刻件）图形簇 \(legacyClusters.count) 枚："
              + legacyClusters.map { "x=[\(pt($0.minX))…\(pt($0.maxX))] h=\(pt($0.height))" }
                .joined(separator: " ｜ "))
        print("NOTEUI-21 ⑤ 改后（生产件）图形簇 \(currentClusters.count) 枚："
              + currentClusters.map { "x=[\(pt($0.minX))…\(pt($0.maxX))] h=\(pt($0.height))" }
                .joined(separator: " ｜ "))

        XCTAssertEqual(currentClusters.count, 3, "改后那一行没量出三枚图形（实测 \(currentClusters.count)）")
        XCTAssertEqual(legacyClusters.count, 3, "改前复刻件没量出三枚图形（实测 \(legacyClusters.count)）")

        // ① 命中区（同一套量法：两条都走活宿主里的 `_FocusRingView`）。
        func hitHeights(_ view: AnyView) -> [CGFloat] {
            let live = UISnapshot.LiveHost(view, size: size)
            live.pump(0.4)
            return hitFrames(in: live.hosting).map { $0.rect.height }
        }
        let legacyHits = hitHeights(legacyRow())
        let currentHits = hitHeights(productionRow())
        print("NOTEUI-21 ⑤ 命中区高：改前 \(legacyHits.map { pt($0) })pt ｜ 改后 \(currentHits.map { pt($0) })pt")
        XCTAssertEqual(legacyHits.count, 3, "改前复刻件没量出三枚命中区")
        XCTAssertEqual(currentHits.count, 3, "改后那一行没量出三枚命中区")
        XCTAssertTrue(
            legacyHits.allSatisfy { $0 < 28 },
            "改前复刻件的命中区高不是 22pt（实测 \(legacyHits.map { pt($0) })）—— 反例不成立，下面那条说明不了事"
        )
        XCTAssertTrue(
            currentHits.allSatisfy { $0 >= 28 },
            "改后命中区高还不是 ≥28pt（实测 \(currentHits.map { pt($0) })）—— 契约「热区 ≥ 28 × 28」没落地"
        )

        // ② 契约「图标 16–18pt」：那一档的币值是**字号**（pt）—— 先判它在档内、且落在字号刻度上，
        //    再看**像素**证不证明它真的画大了（下一段）。
        let iconSize = Metrics.toolbarIconSize
        XCTAssertGreaterThanOrEqual(
            iconSize, 16,
            "工具条图标字号 \(pt(iconSize))pt < 16pt —— 契约「图标 16–18pt」没落地"
        )
        XCTAssertLessThanOrEqual(
            iconSize, 18,
            "工具条图标字号 \(pt(iconSize))pt > 18pt —— 越出契约「图标 16–18pt」"
        )
        XCTAssertTrue(
            TypeScale.isOnScale(iconSize),
            "工具条图标字号 \(pt(iconSize))pt 不在字号刻度上（`TypeScale.scale`）—— 加出来的裸数字"
        )

        // ③ **像素**证明「真的画大了」：同一批符号在两档字号下的可见高度之比必须逐枚等于
        //    字号之比（`iconSize / 改前的 13`）。只判「改后 > 改前」会被「顺带放大一点点」骗过去；
        //    比值判据把「按契约那一档字号画」这件事钉住（改前那一版是 `Theme.font(.icon)` = 13）。
        let legacyHeights = legacyClusters.map(\.height)
        let currentHeights = currentClusters.map(\.height)
        let expectedRatio = iconSize / TypeScale.bodySize
        print("NOTEUI-21 ⑤ 图形可见高度 改前 \(legacyHeights.map { pt($0) })pt → 改后 "
              + "\(currentHeights.map { pt($0) })pt ｜ 比值实测 "
              + zip(currentHeights, legacyHeights).map { String(format: "%.3f", $0 / $1) }.joined(separator: " / ")
              + " ｜ 字号之比 \(String(format: "%.3f", expectedRatio))")
        for (index, (current, legacy)) in zip(currentHeights, legacyHeights).enumerated() {
            XCTAssertGreaterThan(
                current, legacy,
                "第 \(index + 1) 枚图形没变大（改前 \(pt(legacy))pt / 改后 \(pt(current))pt）"
            )
            XCTAssertEqual(
                current / legacy, expectedRatio, accuracy: 0.06,
                "第 \(index + 1) 枚图形的放大倍数与字号之比对不上（实测 \(String(format: "%.3f", current / legacy))"
                    + " / 期望 \(String(format: "%.3f", expectedRatio))）—— 像素没跟着字号走"
            )
            XCTAssertLessThanOrEqual(
                current, Metrics.toolbarButtonHeight,
                "第 \(index + 1) 枚图形 \(pt(current))pt 比命中区还高（\(pt(Metrics.toolbarButtonHeight))pt）—— 越框了"
            )
        }

        try writeEvidence("icon-size-dump", [
            "iconSize": pt(iconSize),
            "expectedScaleRatio": String(format: "%.4f", expectedRatio),
            "legacyClusterHeights": legacyHeights.map { pt($0) },
            "currentClusterHeights": currentHeights.map { pt($0) },
            "measuredScaleRatios": zip(currentHeights, legacyHeights).map { String(format: "%.4f", $0 / $1) },
            "legacyHitHeights": legacyHits.map { pt($0) },
            "currentHitHeights": currentHits.map { pt($0) },
            "contractIconRange": [16, 18],
            "contractHitAreaMin": 28,
        ])
    }

    // MARK: - 判据 ③：与 SQL 编辑区工具条并排（同形那半 + 成对截图）

    /// **笔记左栏入口图标与 SQL 编辑区工具条是同一套呈现**（契约 §三.3 ③）。
    ///
    /// 两半：
    ///   · **源锚点**：两边都是 `App/Views/ToolbarIcon.swift` 的 `ToolbarIcon` / `ToolbarIconButton`
    ///     （`NotesPanel.swift` 的 `crudEntries` 与 `QueryToolbar.swift` 的 `toolbarIcon` 各引用它），
    ///     `App/Views/` 里画这套「图标 + 固定命中区」的**只有那一个文件**；
    ///   · **几何同形**：两边的命中区高**逐个相等**（同一段壳 = 同一个高度；若哪一面自己又画了一套，
    ///     高度当场分家）。
    @MainActor
    func testEntryIconsShareThePresentationWithTheSQLEditorToolbar() throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        _ = try UISnapshot.applyLicense(.standard, to: host.state)

        // ── 源锚点：唯一出处 + 两个消费者 ─────────────────────────────────────────
        let component = try source("App/Views/ToolbarIcon.swift")
        for anchor in [
            "struct ToolbarIcon: View",
            "struct ToolbarIconButton: View",
            "Metrics.toolbarButtonHeight",
            "Metrics.toolbarIconSize",
        ] {
            XCTAssertTrue(component.contains(anchor), "`App/Views/ToolbarIcon.swift` 里找不到锚点 `\(anchor)`")
        }
        let panel = try source("App/Views/NotesPanel.swift")
        for anchor in [
            "ToolbarIconButton(systemName: \"plus\", help: L(.notesNew))",
            "ToolbarIconButton(systemName: \"pencil\", help: L(.commonEdit))",
            "ToolbarIconButton(systemName: \"trash\", help: L(.notesDelete))",
            "private var crudEntries: some View {\n        HStack(spacing: Spacing.xs) {",
            // **入口图标一行只用一个间距值**（`FR-NOTEUI-21` 那条「等距」的机械锚点）：
            // 顶栏那一行的 `HStack(spacing:)` 必须与 `crudEntries` 内部**同一个值** ——
            // 两处一个值 ⇒ 从「＋」到这一行里最后一枚入口图标逐个等距。改前这一处是 `Spacing.s`。
            "private var topBar: some View {\n        HStack(spacing: Spacing.xs) {",
        ] {
            XCTAssertTrue(panel.contains(anchor), "`App/Views/NotesPanel.swift` 里找不到锚点 `\(anchor)`")
        }
        let toolbar = try source("App/Views/QueryToolbar.swift")
        for anchor in ["ToolbarIcon(systemName: systemName)", "Metrics.toolbarButtonHeight"] {
            XCTAssertTrue(toolbar.contains(anchor), "`App/Views/QueryToolbar.swift` 里找不到锚点 `\(anchor)`")
        }
        // 负向：图标**字号**这件事只有一个出处 —— `App/Views/` 里提到 `Metrics.toolbarIconSize`
        // 的文件只许是那一个（哪个面自己另写一个字号，同一个窗口里当场出现两套大小的图标）。
        let sizeSources = try appViewFilesContaining("Metrics.toolbarIconSize")
        XCTAssertEqual(
            sizeSources, ["App/Views/ToolbarIcon.swift"],
            "图标字号在别的视图文件里又写了一遍：\(sizeSources) —— 呈现函数必须只有一处"
        )

        // ── 几何同形：两边的命中区高逐个相等 ──────────────────────────────────────
        let size = CGSize(width: 1000, height: 60)
        let notesLive = UISnapshot.LiveHost(productionRow(), size: size)
        notesLive.pump(0.4)
        let notesHits = hitFrames(in: notesLive.hosting)

        let sqlLive = UISnapshot.LiveHost(environment(sqlToolbar(host), host), size: size)
        sqlLive.pump(0.4)
        let sqlHits = hitFrames(in: sqlLive.hosting)
        let sqlHeights = Set(sqlHits.map { pt($0.rect.height) })

        print("NOTEUI-21 ③ 命中区高：笔记入口 \(Set(notesHits.map { pt($0.rect.height) }) )pt"
              + " ｜ SQL 编辑区工具条 \(sqlHeights)pt（\(sqlHits.count) 枚）")
        XCTAssertFalse(notesHits.isEmpty, "笔记入口那一行没量到命中区")
        XCTAssertFalse(sqlHits.isEmpty, "SQL 编辑区工具条没量到命中区 —— 同形这一半没有对照件")
        XCTAssertEqual(
            Set(notesHits.map { pt($0.rect.height) }), sqlHeights,
            "两面的命中区高不一样（笔记 \(Set(notesHits.map { pt($0.rect.height) })) / SQL \(sqlHeights)）"
                + " —— 有一面在自己画「图标 + 命中区」"
        )
    }

    // MARK: - 成对截图（给人判的那一半）

    /// **成对截图**：改前 / 改后各一张（那一行本体），外加一张**并排**（笔记入口行 ↔ SQL 编辑区工具条）。
    ///
    /// 三种图落在 `DOYAH_SNAPSHOT_DIR`（与其余取证图同一处），中英各一 ——
    /// 并排那一张里有标签文案，所以中英两遍**本来就该不同**（不是「语言没到像素上」）。
    @MainActor
    func testPairedScreenshots() throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        _ = try UISnapshot.applyLicense(.standard, to: host.state)

        let rowSize = CGSize(width: 200, height: 44)
        try UISnapshot.writeBothLanguages("noteui-21-entry-icons-legacy", size: rowSize) { legacyRow() }
        try UISnapshot.writeBothLanguages("noteui-21-entry-icons", size: rowSize) { productionRow() }

        // **改前 ↔ 改后并排**：同一把尺子下的两张（同一行、同一间距，只有图标字号与命中区高不同）——
        // 给人看的那一半就是这一张：图形变大、看得见的留白收紧，而三枚仍是等距的四点。
        try UISnapshot.writeBothLanguages(
            "noteui-21-entry-icons-legacy-vs-current", size: CGSize(width: 240, height: 130)
        ) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(L(.notesNew)).font(Theme.font(.caption)).foregroundStyle(Theme.text(.tertiary))
                legacyRow()
                Text(L(.notesTitle)).font(Theme.font(.caption)).foregroundStyle(Theme.text(.tertiary))
                productionRow()
                Spacer(minLength: 0)
            }
            .padding(.leading, Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        try UISnapshot.writeBothLanguages(
            "noteui-21-entry-icons-vs-sql-toolbar", size: CGSize(width: 1000, height: 130)
        ) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(L(.notesTitle)).font(Theme.font(.caption)).foregroundStyle(Theme.text(.tertiary))
                productionRow()
                Text(L(.toolbarExecuteHelp)).font(Theme.font(.caption)).foregroundStyle(Theme.text(.tertiary))
                environment(sqlToolbar(host), host)
                Spacer(minLength: 0)
            }
            .padding(.leading, Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        print("NOTEUI-21 🖼 三种图（中英各一）落 \(UISnapshot.outputDirectory.path)")
    }

    /// SQL 编辑区那一面：工具条本体（`App/Views/QueryToolbar.swift`）。
    @MainActor
    private func sqlToolbar(_ host: Host) -> AnyView {
        AnyView(
            QueryToolbar(
                tab: QueryTab(title: "Q1"),
                onOpenFile: {}, onSaveFile: {}, onSaveFileAs: {}, onSaveQuery: {},
                onRequestGoToLine: {}, onEditCommand: { _ in }
            )
        )
    }

    // MARK: - 证据与源码

    private func writeEvidence(_ name: String, _ payload: [String: Any]) throws {
        let directory = UISnapshot.outputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(
            to: directory.appendingPathComponent("noteui-21-\(name).json"),
            options: .atomic
        )
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// `App/Views/` 里含某个字面量的文件（相对路径升序）—— 「唯一出处」那一条判据靠它。
    private func appViewFilesContaining(_ needle: String) throws -> [String] {
        let views = repoRoot().appendingPathComponent("App/Views")
        let files = try FileManager.default.contentsOfDirectory(at: views, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        return try files
            .filter { try String(contentsOf: $0, encoding: .utf8).contains(needle) }
            .map { "App/Views/\($0.lastPathComponent)" }
            .sorted()
    }
}
