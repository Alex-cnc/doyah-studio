import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **行内动作悬停出、常驻不占位**（`FR-STD-WS-UI-013`）。
///
/// 需求三条验收（需求书原文）：
///   ① 未悬停时该行动作数为 **0** 且**行宽不因它变化**；
///   ② 悬停即出、移开即收；
///   ③ 同一条动作在工具条与行内**不得并存**（只画一次）。
///
/// ## 为什么这条要用像素量
///
/// 本批之前这条只有源码一行 `if isHovered || renaming` —— 没有一处读数。
/// 而「动作画没画出来」在离屏宿主里**数不到控件**：SwiftUI 的图标 `Button`
/// （`.buttonStyle(.plain)`）不落地成 `NSView`，`accessibilityIdentifier` 也不保证落到某个
/// `NSView` 上（`NotesLayoutProbeTests` 头注释实测：视图 50 个 / 带标识 0 个 / `NSButton` 0 枚）。
/// 合成悬停同样不响应（`window.sendEvent` 收得下，SwiftUI 手势不动）。
///
/// ⇒ 两条腿：
///   · **悬停态变成输入**：`WorkspaceTreeRow` / `ConnectionGroupHeader` 从父视图里抽出来，
///     `isHovered` 是参数（产线仍只有一个写入口 —— 父视图那条 `.onHover`），
///     于是探针能把**同一行**摆到两档各渲染一次；
///   · **读数取像素**：离屏 `NSWindow` + `cacheDisplay` 落 PNG，按**列**统计「与底色不同的像素」
///     并把连续列并成簇 —— 一枚图标 = 一簇。动作带（行右端那一截）里几簇 = 这一行画了几枚动作。
///
/// ## 判据必须能判红
///
/// `testDetectorSeesPermanentActions`（常驻版复刻件 ⇒ 未悬停也数出 3 簇）与
/// `testWidthMeasureDetectsANarrowerRow`（`fixedSize` 版 ⇒ 底色带比容器窄）两个玩具证明这套量法
/// **不是恒真**：前者要是数不出东西，① 那条断言就等于没写。
///
/// ## 边界（如实登记）
///
/// · 量的是**版面几何与墨迹**，不是观感（间距好不好看、图标配色）—— 那条不在本需求验收里；
/// · 不验「真鼠标移进来」那一下（离屏宿主里合成悬停不响应，同上）—— 验的是「悬停态对应的
///   版面」，两档由同一个视图渲染，差别只有 `isHovered` 这一个输入；
/// · 不碰用户数据：夹具是 `.build/` 下的临时目录。
final class RowActionRevealProbeTests: XCTestCase {

    /// 侧栏宽度（`Metrics.sidebarWidth`，三面共用那一档）。行宽就按它量。
    private let rowWidth = Metrics.sidebarWidth
    private let scale: CGFloat = 2

    /// 右侧「动作带」的宽度（pt）：三枚动作在最拥挤的目录行上实测 76pt 上下，取 84 留余量。
    private let actionBandWidth: CGFloat = 84

    private var scratch: URL!

    /// 离屏窗口只持有、不关闭（关掉会带着渲染中的宿主一起走，R47 / R48 同款）。
    @MainActor private static var retainedWindows: [NSWindow] = []

    override func setUpWithError() throws {
        scratch = UISnapshot.outputDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("row-action-probe", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: scratch.appendingPathComponent("src", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "x\n".write(to: scratch.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "x\n".write(
            to: scratch.appendingPathComponent("a-very-long-file-name-that-should-not-push-the-row-wider.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    override func tearDownWithError() throws {
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
        scratch = nil
    }

    // MARK: - 夹具（真列目录出来的条目，不是手搓的结构体）

    private func entry(named name: String) throws -> WorkspaceEntry {
        let entries = try WorkspaceTree.children(of: scratch, relativeTo: scratch)
        return try XCTUnwrap(entries.first { $0.name == name }, "夹具里没有 `\(name)`")
    }

    // MARK: - ① 未悬停：动作数 0

    @MainActor
    func testUnhoveredDirectoryRowDrawsNoActions() throws {
        let row = try entry(named: "src")
        let shot = try render(row, isHovered: false, tag: "dir-resting")
        let clusters = shot.clusters(inX: actionBand, background: shot.modeOutsideActionBand)
        print("ROW-ACTION[dir·未悬停] 动作带簇数 \(clusters.count) · 墨迹右界 \(String(describing: shot.inkBounds.map { "\($0.lowerBound)…\($0.upperBound)" }))")
        XCTAssertEqual(clusters.count, 0, "未悬停的目录行在动作带里画了 \(clusters.count) 簇 —— 需求 ① 要求 0")
    }

    @MainActor
    func testUnhoveredFileRowDrawsNoActions() throws {
        let row = try entry(named: "a.txt")
        let shot = try render(row, isHovered: false, tag: "file-resting")
        let clusters = shot.clusters(inX: actionBand, background: shot.modeOutsideActionBand)
        print("ROW-ACTION[file·未悬停] 动作带簇数 \(clusters.count)")
        XCTAssertEqual(clusters.count, 0, "未悬停的文件行在动作带里画了 \(clusters.count) 簇")
    }

    // MARK: - ② 悬停：三枚（目录）/ 两枚（文件）

    @MainActor
    func testHoveredDirectoryRowDrawsThreeActions() throws {
        let row = try entry(named: "src")
        let shot = try render(row, isHovered: true, tag: "dir-hovered")
        let clusters = shot.clusters(inX: actionBand, background: shot.modeOutsideActionBand)
        print("ROW-ACTION[dir·悬停] 簇数 \(clusters.count) · 各簇宽 \(clusters.map { $0.count }) 像素")
        // **期望值写死成需求口径**（3 枚），不从 `RowActionPolicy` 取 ——
        // 从被测实现取期望值时，实现把文件行也改成三枚照样绿（本轮反例 B 实测踩到过这个假绿）。
        XCTAssertEqual(clusters.count, 3, "悬停的目录行动作簇数 \(clusters.count) ≠ 3 枚（新建 / 删除 / 改名）")
        for cluster in clusters {
            XCTAssertGreaterThanOrEqual(cluster.count, 8, "有一簇只有 \(cluster.count) 像素宽 —— 不像一枚图标")
            XCTAssertLessThanOrEqual(cluster.count, 60, "有一簇宽 \(cluster.count) 像素 —— 几枚图标粘成了一团")
        }
    }

    @MainActor
    func testHoveredFileRowDrawsTwoActions() throws {
        let row = try entry(named: "a.txt")
        let shot = try render(row, isHovered: true, tag: "file-hovered")
        let clusters = shot.clusters(inX: actionBand, background: shot.modeOutsideActionBand)
        print("ROW-ACTION[file·悬停] 簇数 \(clusters.count) · 各簇宽 \(clusters.map { $0.count }) 像素")
        XCTAssertEqual(clusters.count, 2, "悬停的文件行动作簇数 \(clusters.count) ≠ 2 枚（文件行不该有「新建」）")
    }

    // MARK: - ② 移开即收（同一行、同一个窗口，只翻 `isHovered`）

    @MainActor
    func testActionsDisappearWhenHoverEnds() throws {
        let row = try entry(named: "src")
        let (window, hosting) = try host(rowView(row, isHovered: true), tag: "toggle")
        defer { Self.closeLater(window) }

        let hovered = try capture(hosting, tag: "toggle-1-hovered")
        let hoveredClusters = hovered.clusters(inX: actionBand, background: hovered.modeOutsideActionBand)
        XCTAssertEqual(hoveredClusters.count, 3, "起点就得是悬停态（3 枚），否则后半段无从比较")

        hosting.rootView = AnyView(rowView(row, isHovered: false))
        let resting = try recapture(hosting, tag: "toggle-2-resting")
        let restingClusters = resting.clusters(inX: actionBand, background: resting.modeOutsideActionBand)
        print("ROW-ACTION[移开] 悬停 \(hoveredClusters.count) 簇 → 移开 \(restingClusters.count) 簇")
        XCTAssertEqual(restingClusters.count, 0, "鼠标移开之后动作还在（\(restingClusters.count) 簇）—— 需求 ② 的「离开即收」不成立")

        hosting.rootView = AnyView(rowView(row, isHovered: true))
        let again = try recapture(hosting, tag: "toggle-3-hovered-again")
        let againClusters = again.clusters(inX: actionBand, background: again.modeOutsideActionBand)
        XCTAssertEqual(againClusters.count, 3, "再悬停一次没有回到 3 簇（\(againClusters.count)）—— 「悬停即出」只在第一次成立")
    }

    // MARK: - ① 行宽不因动作变化（选中态给了一条能读到行宽的底色带）

    @MainActor
    func testRowWidthIsIdenticalWithAndWithoutActions() throws {
        let row = try entry(named: "src")
        let resting = try render(row, isHovered: false, isSelected: true, tag: "width-resting")
        let hovered = try render(row, isHovered: true, isSelected: true, tag: "width-hovered")

        let restingBand = try XCTUnwrap(resting.tintedExtent(), "选中行的底色带没量到（行宽读不出）")
        let hoveredBand = try XCTUnwrap(hovered.tintedExtent(), "选中行的底色带没量到（行宽读不出）")
        print(
            "ROW-ACTION[行宽] 未悬停 \(restingBand) 像素 · 悬停 \(hoveredBand) 像素 · 容器 \(Int(rowWidth * scale)) 像素"
        )
        XCTAssertEqual(restingBand.lowerBound, hoveredBand.lowerBound, "悬停让行左界动了")
        XCTAssertEqual(restingBand.upperBound, hoveredBand.upperBound, "悬停让行右界动了 —— 行宽随动作变化（需求 ① 不成立）")
        XCTAssertEqual(
            hoveredBand.count,
            Int(rowWidth * scale),
            accuracy: 2,
            "行宽 \(hoveredBand.count) 像素 ≠ 容器 \(Int(rowWidth * scale)) 像素 —— 行没有占满侧栏那一档"
        )
    }

    // MARK: - ① 长文件名 + 悬停：动作不许被挤出容器

    @MainActor
    func testLongNameRowKeepsActionsInsideTheRow() throws {
        let row = try entry(named: "a-very-long-file-name-that-should-not-push-the-row-wider.txt")
        let shot = try render(row, isHovered: true, tag: "long-name-hovered")
        // 文件行只有两枚（删除 / 改名 = 28 + 28 + 间距 2 + 右侧留白 12 ≈ 70pt）。
        // 带子按这个宽度取，不要把「长文件名自己伸过来的尾巴」数成动作 ——
        // 那正是本行在这一例里要量的另一半：名字可以被截断，行不许被撑宽。
        let clusters = shot.clusters(inX: band(width: 66), background: shot.modeOutsideActionBand)
        let bounds = try XCTUnwrap(shot.inkBounds)
        print("ROW-ACTION[长文件名·悬停] 簇数 \(clusters.count) · 墨迹右界 \(bounds.upperBound) / 允许 \(Int(rowWidth * scale) - 2)")
        XCTAssertEqual(clusters.count, 2, "长文件名行悬停时应是 2 枚（删除 / 改名），实测 \(clusters.count) 簇")
        XCTAssertLessThanOrEqual(
            bounds.upperBound,
            Int(rowWidth * scale),
            "墨迹越过行右界（\(bounds.upperBound) > \(Int(rowWidth * scale))）—— 动作把行撑宽了"
        )
    }

    // MARK: - 分组标题（同一套口径：悬停才出的那枚「＋」）

    @MainActor
    func testGroupHeaderPlusAppearsOnlyOnHover() throws {
        let resting = try renderHeader(isHovered: false, tag: "group-resting")
        let hovered = try renderHeader(isHovered: true, tag: "group-hovered")

        let restingClusters = resting.clusters(inX: actionBand, background: resting.modeOutsideActionBand)
        let hoveredClusters = hovered.clusters(inX: actionBand, background: hovered.modeOutsideActionBand)
        print("ROW-ACTION[分组标题] 未悬停 \(restingClusters.count) 簇 → 悬停 \(hoveredClusters.count) 簇")
        XCTAssertEqual(restingClusters.count, 0, "未悬停的分组标题上已经画了 \(restingClusters.count) 簇动作")
        XCTAssertEqual(hoveredClusters.count, 1, "悬停的分组标题应恰好 1 枚「＋」，实测 \(hoveredClusters.count) 簇")

        // 标题那一段**逐列墨迹不变** —— 动作出现不许把标题挤走（这就是分组标题的「行宽不因它变」）。
        let titleColumns = (0..<(Int(rowWidth * scale) - Int(actionBandWidth * scale)))
        let restingTitle = resting.inkColumns(inX: titleColumns)
        let hoveredTitle = hovered.inkColumns(inX: titleColumns)
        XCTAssertEqual(restingTitle, hoveredTitle, "标题那一段的墨迹在悬停前后不一致 —— 动作把标题挤走了")
    }

    // MARK: - ③ 只画一次（源码锚点：动作标识只有一个出处，工具条上没有第二个入口）

    func testRowActionsHaveASingleDrawSite() throws {
        let appSources = try swiftSources(under: UISnapshot.packageRoot.appendingPathComponent("App"))
        let literal = appSources.filter { $0.value.contains("workspace-action-") }
        XCTAssertEqual(
            literal.map(\.key), [],
            "App/ 里还有自己拼行内动作标识的地方（\(literal.map(\.key))）—— 唯一出处应当是 Core 的 `RowActionPolicy`"
        )

        let drawSites = appSources.filter {
            $0.value.contains("RowActionPolicy.accessibilityIdentifier(")
        }
        XCTAssertEqual(
            drawSites.map(\.key).count, 1,
            "行内动作有 \(drawSites.count) 处绘制点（\(drawSites.map(\.key))）—— 需求 ③ 要求只画一次"
        )

        let groupAddSites = appSources.filter {
            $0.value.contains("RowActionPolicy.groupAddAccessibilityIdentifier(")
        }
        XCTAssertEqual(groupAddSites.count, 1, "分组标题「＋」有 \(groupAddSites.count) 处绘制点")

        let newConnectionEntries = appSources.filter { $0.value.contains("L(.connectionNew)") }
        XCTAssertEqual(
            newConnectionEntries.map(\.key), ["App/Views/ConnectionListView.swift"],
            "「新建连接」还有别的入口（\(newConnectionEntries.map(\.key))）—— 需求 ③：同一条动作不许在工具条与行内并存"
        )
    }

    // MARK: - 反例（证明这套量法不是恒真）

    /// 玩具一：**常驻**动作的复刻件（本批之前那种「一排图标」的形态）⇒ 未悬停也该数出 3 簇。
    /// 它要是也数出 0，`testUnhoveredDirectoryRowDrawsNoActions` 就等于恒过。
    @MainActor
    func testDetectorSeesPermanentActions() throws {
        let shot = try renderLegacyPermanentActionsRow(tag: "toy-permanent")
        let clusters = shot.clusters(inX: actionBand, background: shot.modeOutsideActionBand)
        print("ROW-ACTION[玩具·常驻动作] 未悬停动作带簇数 \(clusters.count)（期望 3 —— 证明数得到）")
        XCTAssertEqual(clusters.count, 3, "常驻动作的复刻件在动作带里数出 \(clusters.count) 簇 —— 数法看不见常驻图标，① 那条断言不可信")
    }

    /// 玩具二：把行按内容宽度收紧（`fixedSize`）⇒ 底色带比容器窄。它要是也报满宽，
    /// 「行宽不变」那条断言就只是在读常量。
    @MainActor
    func testWidthMeasureDetectsANarrowerRow() throws {
        let shot = try renderNarrowRow(tag: "toy-narrow")
        let band = try XCTUnwrap(shot.tintedExtent(), "收紧版的底色带没量到")
        print("ROW-ACTION[玩具·收紧行] 底色带 \(band.count) 像素 / 容器 \(Int(rowWidth * scale)) 像素")
        XCTAssertLessThan(
            band.count,
            Int(rowWidth * scale) - 8,
            "收紧版的行宽 \(band.count) 像素读数与满宽几乎一样 —— 行宽那一条量不到差异"
        )
    }

    // MARK: - 渲染

    private var actionBand: Range<Int> { band(width: actionBandWidth) }

    /// 行右端那一条带（宽 `width` pt）。
    private func band(width: CGFloat) -> Range<Int> {
        let total = Int(rowWidth * scale)
        return (total - Int(width * scale))..<total
    }

    /// 一行的视图（外面垫一层白底：未悬停行的 `Color.clear` 需要有东西可对比）。
    @MainActor
    private func rowView(
        _ entry: WorkspaceEntry,
        isHovered: Bool,
        isSelected: Bool = false,
        expanded: Bool = true,
        width: CGFloat? = nil
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Color(white: 1.0)
            WorkspaceTreeRow(
                entry: entry,
                depth: 0,
                isSelected: isSelected,
                isHovered: isHovered,
                isRenaming: false,
                expanded: expanded,
                renamingText: .constant(""),
                tint: Theme.accentColor,
                accentColor: Theme.accentColor,
                onOpen: {},
                onSelect: {},
                onHoverChange: { _ in },
                onCreate: { _ in },
                onDelete: {},
                onBeginRename: {},
                onCommitRename: {},
                onCancelRename: {},
                onReveal: {}
            )
            .frame(width: width ?? rowWidth)
            .fixedSize(horizontal: width != nil, vertical: false)
        }
        .frame(width: rowWidth, height: Metrics.listRowHeight, alignment: .topLeading)
    }

    @MainActor
    private func renderHeader(isHovered: Bool, tag: String) throws -> Shot {
        let view = ZStack(alignment: .topLeading) {
            Color(white: 1.0)
            ConnectionGroupHeader(
                title: "测试分组",
                count: 2,
                groupID: "g1",
                isHovered: isHovered,
                onAdd: {},
                onHoverChange: { _ in }
            )
            .frame(width: rowWidth - 24)
            .padding(.horizontal, 12)
        }
        .frame(width: rowWidth, height: 20, alignment: .topLeading)
        let (window, hosting) = try host(view, tag: tag, height: 20)
        defer { Self.closeLater(window) }
        return try capture(hosting, tag: tag)
    }

    /// 反例一：本批之前那种「动作常驻」的形态（逐字复刻：无 `isHovered` 判断）。
    @MainActor
    private func renderLegacyPermanentActionsRow(tag: String) throws -> Shot {
        let view = ZStack(alignment: .topLeading) {
            Color(white: 1.0)
            HStack(spacing: Spacing.xs) {
                Image(systemName: "folder")
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.tertiary))
                    .frame(width: 14)
                Text("src")
                    .font(Theme.font(.body))
                    .foregroundStyle(Theme.text(.secondary))
                    .lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: Spacing.hair) {
                    Image(systemName: "plus")
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.tertiary))
                        .frame(width: 16, height: 16)
                    ToolbarIconButton(systemName: "minus", help: "删除") {}
                    ToolbarIconButton(systemName: "pencil", help: "改名") {}
                }
            }
            .padding(.leading, Spacing.s)
            .padding(.trailing, Spacing.m)
            .frame(width: rowWidth, height: Metrics.listRowHeight)
        }
        .frame(width: rowWidth, height: Metrics.listRowHeight, alignment: .topLeading)
        let (window, hosting) = try host(view, tag: tag)
        defer { Self.closeLater(window) }
        return try capture(hosting, tag: tag)
    }

    /// 反例二：同一个选中行，但按内容宽度收紧（没有「占满侧栏」那一档）。
    @MainActor
    private func renderNarrowRow(tag: String) throws -> Shot {
        let row = try entry(named: "src")
        let view = ZStack(alignment: .topLeading) {
            Color(white: 1.0)
            WorkspaceTreeRow(
                entry: row,
                depth: 0,
                isSelected: true,
                isHovered: true,
                isRenaming: false,
                expanded: true,
                renamingText: .constant(""),
                tint: Theme.accentColor,
                accentColor: Theme.accentColor,
                onOpen: {},
                onSelect: {},
                onHoverChange: { _ in },
                onCreate: { _ in },
                onDelete: {},
                onBeginRename: {},
                onCommitRename: {},
                onCancelRename: {},
                onReveal: {}
            )
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(width: rowWidth, height: Metrics.listRowHeight, alignment: .topLeading)
        let (window, hosting) = try host(view, tag: tag)
        defer { Self.closeLater(window) }
        return try capture(hosting, tag: tag)
    }

    @MainActor
    private func render(
        _ entry: WorkspaceEntry, isHovered: Bool, isSelected: Bool = false, tag: String
    ) throws -> Shot {
        let (window, hosting) = try host(rowView(entry, isHovered: isHovered, isSelected: isSelected), tag: tag)
        defer { Self.closeLater(window) }
        return try capture(hosting, tag: tag)
    }

    /// 不上屏的窗口：给确定尺寸 + 浅色外观 → 布局 → **跑一段 runloop**（SwiftUI 布局下一跳才落）→ 再布局一次。
    @MainActor
    private func host<V: View>(_ view: V, tag: String, height: CGFloat? = nil) throws -> (NSWindow, NSHostingView<AnyView>) {
        let size = CGSize(width: rowWidth, height: height ?? Metrics.listRowHeight)
        let appearance = NSAppearance(named: .aqua)
        let hosting = NSHostingView(rootView: AnyView(view))
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
        settle(hosting)
        Self.retainedWindows.append(window)
        return (window, hosting)
    }

    @MainActor
    private func settle(_ hosting: NSView) {
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
    }

    @MainActor
    private func recapture(_ hosting: NSHostingView<AnyView>, tag: String) throws -> Shot {
        settle(hosting)
        return try capture(hosting, tag: tag)
    }

    @MainActor
    private func capture(_ hosting: NSView, tag: String) throws -> Shot {
        let size = hosting.bounds.size
        guard size.width > 10, size.height > 4 else {
            throw UISnapshot.SnapshotError.renderFailed("\(tag)：宿主退化帧 \(size)")
        }
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
            throw UISnapshot.SnapshotError.renderFailed("\(tag)：位图分配失败")
        }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw UISnapshot.SnapshotError.encodeFailed(tag)
        }
        let directory = UISnapshot.outputDirectory.deletingLastPathComponent()
            .appendingPathComponent("ui-snapshot-state", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("row-action-\(tag).png")
        try data.write(to: url)
        guard data.count > 400 else {
            throw UISnapshot.SnapshotError.renderFailed("\(tag)：PNG 只有 \(data.count) 字节（多半是空图）")
        }
        return try Shot(pngAt: url.path)
    }

    @MainActor
    private static func closeLater(_ window: NSWindow) {
        // 不是马上关（这一跳还在用它量）；交给下一次运行回收：只从持有表里摘掉引用即可。
        retainedWindows.removeAll { $0 === window }
        window.orderOut(nil)
    }

    // MARK: - 源码锚点要用的扫盘

    private func swiftSources(under root: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return result
        }
        for case let url as URL in walker where url.pathExtension == "swift" {
            let relative = url.path.replacingOccurrences(of: UISnapshot.packageRoot.path + "/", with: "")
            result[relative] = try String(contentsOf: url, encoding: .utf8)
        }
        return result
    }

    // MARK: - 像素读数

    /// 一张落盘 PNG 的逐像素读数 + 这一族要的三件量法。
    struct Shot {
        let width: Int
        let height: Int
        private let bytesPerRow: Int
        private let bytesPerPixel: Int
        private let pixels: [UInt8]

        init(pngAt path: String) throws {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let rep = NSBitmapImageRep(data: data),
                  let raw = rep.bitmapData else {
                throw UISnapshot.SnapshotError.renderFailed("读不出 \(path)")
            }
            width = rep.pixelsWide
            height = rep.pixelsHigh
            bytesPerRow = rep.bytesPerRow
            bytesPerPixel = max(1, rep.bitsPerPixel / 8)
            var copy = [UInt8](repeating: 0, count: bytesPerRow * height)
            copy.withUnsafeMutableBytes { buffer in
                if let base = buffer.baseAddress {
                    memcpy(base, raw, buffer.count)
                }
            }
            pixels = copy
        }

        /// 底色 = **动作带之外**那一块里出现最多的颜色（未悬停行是白底、悬停行是那层极淡的底色）。
        /// 为什么取「动作带之外」：带内一旦画了图标，众数还是底色，但若动作带被涂满就会把底色读错。
        var modeOutsideActionBand: RGB {
            let cut = max(width - Int(Double(width) * 0.35), 1)
            return mode(inX: 0..<cut)
        }

        typealias RGB = (red: Int, green: Int, blue: Int)

        func rgb(_ x: Int, _ y: Int) -> RGB {
            guard x >= 0, x < width, y >= 0, y < height else { return (0, 0, 0) }
            let index = y * bytesPerRow + x * bytesPerPixel
            guard index + 2 < pixels.count else { return (0, 0, 0) }
            return (Int(pixels[index]), Int(pixels[index + 1]), Int(pixels[index + 2]))
        }

        func mode(inX range: Range<Int>) -> RGB {
            var counts: [Int: Int] = [:]
            for x in range {
                for y in 0..<height {
                    let color = rgb(x, y)
                    let key = (color.red << 16) | (color.green << 8) | color.blue
                    counts[key, default: 0] += 1
                }
            }
            let winner = counts.max { $0.value < $1.value }?.key ?? 0
            return ((winner >> 16) & 0xFF, (winner >> 8) & 0xFF, winner & 0xFF)
        }

        /// 逐列的「与底色差 > 阈值」的像素数（`0` = 这一列是空的）。
        func inkColumns(inX range: Range<Int>, background: RGB? = nil, threshold: Int = 6) -> [Int] {
            let reference = background ?? modeOutsideActionBand
            var result: [Int] = []
            for x in range {
                var ink = 0
                for y in 0..<height where differs(rgb(x, y), reference, threshold: threshold) {
                    ink += 1
                }
                result.append(ink)
            }
            return result
        }

        /// 把连续的非空列并成簇（中间空 ≤ `maxGap` 列仍算同一簇：抗锯齿会把一枚图标切出细缝）。
        func clusters(inX range: Range<Int>, background: RGB? = nil, maxGap: Int = 4) -> [[Int]] {
            let columns = inkColumns(inX: range, background: background)
            var clusters: [[Int]] = []
            var current: [Int] = []
            var gap = 0
            for ink in columns {
                if ink > 0 {
                    current.append(ink)
                    gap = 0
                } else if !current.isEmpty {
                    gap += 1
                    if gap > maxGap {
                        clusters.append(current)
                        current = []
                        gap = 0
                    }
                }
            }
            if !current.isEmpty { clusters.append(current) }
            return clusters
        }

        /// 最左 / 最右的墨迹列（`nil` = 全空）。
        var inkBounds: ClosedRange<Int>? {
            let columns = inkColumns(inX: 0..<width)
            let hits = columns.enumerated().filter { $0.element > 0 }.map(\.offset)
            guard let first = hits.first, let last = hits.last else { return nil }
            return first...last
        }

        /// 底色带（选中行那一条 accent 底）的横向范围，用来读**行宽**。
        /// 判据：这一列在竖直方向上有过半像素与白底不同 ⇒ 算在这条带里。
        func tintedExtent() -> ClosedRange<Int>? {
            let white: RGB = (255, 255, 255)
            let columns = inkColumns(inX: 0..<width, background: white, threshold: 10)
            let threshold = max(height / 2, 1)
            let hits = columns.enumerated().filter { $0.element >= threshold }.map(\.offset)
            guard let first = hits.first, let last = hits.last else { return nil }
            return first...last
        }

        private func differs(_ lhs: RGB, _ rhs: RGB, threshold: Int) -> Bool {
            abs(lhs.red - rhs.red) > threshold
                || abs(lhs.green - rhs.green) > threshold
                || abs(lhs.blue - rhs.blue) > threshold
        }
    }
}

