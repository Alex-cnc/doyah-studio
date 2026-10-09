import AppKit
import SwiftUI
import XCTest

import DoyahCore
import DoyahRetroUI
@testable import DoyahStudioApp

/// 片 `M7-HOST`（派单 `T-20261009-080`）的机器判据：**活动栏 `Retro` 项 + 装配 `DoyahRetroUI`**。
///
/// ## 判什么（卡上判据 3 的四条，逐条对应）
///
///   ① `ActivityBarItem.allCases` 含 `retro`（栏上多一项，且它自己的图标 / 名字 / 菜单键齐）；
///   ② `symbolName` / `titleKey` / `menuKey` 三处 switch **穷尽且无 `default`**
///      —— 穷尽由编译期保证，这里把「有没有偷偷写 `default`」也钉成源判据
///      （`default` 会让将来新增的区**静默**落进某个分支，那正是这一片要避免的）；
///   ③ `LicensePresentation.activityItems(for: .all)` 含 `.retro`，且**三档都有它**
///      （「不挂授权 ⇒ 全档可见」，同时**不新增能力位** —— 能力位仍恰好三个）；
///   ④ `ReportListModel.fixed()` **真读固定扫描目录**（本机两包：`2026-W41` / `2026-W40`），
///      且 `RetroHostView()` **可构造、可布局、不崩**（视图树里真的落下列表）。
///
/// ## 为什么这一族可以进「不落快照」那一档
///
/// 判据读的是 **Core 的真值**（活动栏项 / 可见性 / 扫描读数）与 **AppKit 视图树的事实**
/// （有没有滚动容器）—— 不是像素。落图只会搅乱「张数 / 组数」那类派生计数
/// （与 `NotesEditorFormatProbeTests` / `NotesEditorSaveProbeTests` 刻意不调 `write` 同款理由）。
///
/// 跑法：`env DOYAH_UI_SNAPSHOT=1 swift test --filter RetroHost`
/// （`Scripts/verify-ui-interactions.sh` 那条入口的收尾核对盯的是它自己那十五条，不适合带 `--filter`；
/// 卡上的判据 3 也写了「或 `swift test --filter RetroHost`」这一档）。
final class RetroHostProbeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "宿主装配探针要起离屏宿主：DOYAH_UI_SNAPSHOT=1（取证工具，不进每轮门禁）"
        )
    }

    /// 仓根：`#filePath` = 本文件在仓里的绝对路径 ⇒ 上两级就是根（与兄弟探针同款）。
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TestsUISnapshot
            .deletingLastPathComponent()  // 仓根
    }

    private func source(_ relative: String) throws -> String {
        try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(relative),
            encoding: .utf8
        )
    }

    // MARK: - 判据 ① 栏上多了一项 `retro`

    @MainActor
    func testRetroHostActivityItemHasItsOwnSymbolTitleAndMenuName() throws {
        let items = ActivityBarItem.allCases
        XCTAssertTrue(items.contains(.retro), "活动栏项里没有 `retro`（M7 判据 ①：入口可见）")

        // ①-a 图标 / 名字 / 菜单键三处**都**跟着涨：漏一处就会出「有图标没名字」这种半拉状态。
        XCTAssertEqual(ActivityBarItem.allCases.count, 4, "栏上应当恰好四项（workspace / database / notes / retro）")
        XCTAssertEqual(
            Set(items.map(\.symbolName)).count, items.count,
            "两项共用一个图标：\(items.map(\.symbolName))"
        )
        XCTAssertEqual(Set(items.map(\.titleKey)).count, items.count, "两项共用一个视图名键")
        XCTAssertEqual(Set(items.map(\.menuKey)).count, items.count, "两项共用一个菜单键")

        let symbol = ActivityBarItem.retro.symbolName
        XCTAssertFalse(symbol.isEmpty, "`retro` 没有图标名 ⇒ 窄条上是一个空白")
        let title = ActivityBarItem.retro.titleKey
        let menu = ActivityBarItem.retro.menuKey

        // ①-b 名字与菜单键**中英都有**（缺一边 = 一种语言下这一项没字）。
        for (label, key) in [("视图名", title), ("菜单键", menu)] {
            let chinese = LocalizedStrings.text(key, language: .simplifiedChinese)
            let english = LocalizedStrings.text(key, language: .english)
            XCTAssertFalse(chinese.isEmpty, "`retro` 的\(label)缺中文（\(key.rawValue)）")
            XCTAssertFalse(english.isEmpty, "`retro` 的\(label)缺英文（\(key.rawValue)）")
            XCTAssertNotEqual(chinese, english, "`retro` 的\(label)中英一模一样 ⇒ 语言表那一半没落地")
            print("📄 M7-HOST ① `retro` 的\(label)：中「\(chinese)」／ 英「\(english)」")
        }

        // ①-c 窗口标题的形状（`FR-EDIT-37`：标题由活动栏项派生 ⇒ 这一项自动跟上）。
        XCTAssertEqual(
            WindowTitle.text(
                brand: LocalizedStrings.text(.appBrand, language: .english),
                suffix: LocalizedStrings.text(title, language: .english)
            ),
            "Doyah Studio - Retro",
            "英文界面的窗口标题应当出 `Doyah Studio - Retro`（需求原话给的那组形状）"
        )

        // ①-d 序号跟着栏上顺序算：Ultra 档四项 ⇒ `retro` 是 ⌘4（不是写死的某个数）。
        XCTAssertEqual(
            ActivityBarItem.shortcutIndex(of: .retro, in: items), 4,
            "四项都在栏上时 `retro` 应当是 ⌘4"
        )
        print("📄 M7-HOST ① 栏上四项：\(items.map(\.rawValue)) ／ `retro` 图标 = \(symbol)")

        UISnapshot.finishManifestIfEnabled()
    }

    // MARK: - 判据 ② 三处 switch 穷尽、且**没有一个 default**

    func testRetroHostThreeLabelSwitchesAreExhaustiveWithoutADefault() throws {
        let bar = try source("Core/ActivityBar.swift")

        for name in ["symbolName", "titleKey", "menuKey"] {
            let body = Self.codeOnly(
                try XCTUnwrap(
                    Self.memberBody(named: name, in: bar),
                    "`Core/ActivityBar.swift` 里找不到 `\(name)` —— 判据的锚点被改名了？"
                )
            )
            XCTAssertTrue(body.contains("case .retro"), "`\(name)` 那一处 switch 没有 `case .retro`（新项漏在这处）")
            for other in ["case .database", "case .workspace", "case .notes"] {
                XCTAssertTrue(body.contains(other), "`\(name)` 那一处 switch 少了 `\(other)`")
            }
            XCTAssertFalse(
                body.contains("default"),
                "`\(name)` 那一处 switch 里出现了 `default` —— 将来再加一个区会**静默**落进它，"
                    + "「谁在上面 / 谁叫什么」就不再是编译期能查的事了"
            )
        }

        // 可见性那一处同样不许 `default`（它决定「哪些区出现」，写 `default` 就等于放行未授权区）。
        let presentation = try source("Core/LicensePresentation.swift")
        let visibility = Self.codeOnly(
            try XCTUnwrap(
                Self.memberBody(named: "activityItems", in: presentation),
                "`Core/LicensePresentation.swift` 里找不到 `activityItems`"
            )
        )
        XCTAssertTrue(visibility.contains("case .retro"), "可见性判定里没有 `case .retro`")
        XCTAssertFalse(visibility.contains("default"), "可见性判定里出现了 `default`（未授权的区会被放行）")

        print("📄 M7-HOST ② `symbolName` / `titleKey` / `menuKey` / 可见性判定：四处都穷尽、都没有 `default`")
        UISnapshot.finishManifestIfEnabled()
    }

    // MARK: - 判据 ③ 三档都可见，但**不新增能力位**

    func testRetroHostIsVisibleInEveryEditionWithoutANewCapabilityBit() throws {
        let ultra = LicensePresentation.activityItems(for: .all)
        XCTAssertTrue(ultra.contains(.retro), "Ultra 档的活动栏里没有 `retro`")

        // 「不挂授权 ⇒ 全档可见」：三档都给得出它。
        let editions: [(String, LicenseCapabilities)] = [
            ("Standard", .notesOnly),
            ("Pro", [.workspaces, .database]),
            ("Ultra", .all),
        ]
        for (label, capabilities) in editions {
            let items = LicensePresentation.activityItems(for: capabilities)
            XCTAssertTrue(items.contains(.retro), "\(label) 档的活动栏里没有 `retro`（口径是「全档可见」）")
            print("📄 M7-HOST ③ \(label) 档可见项：\(items.map(\.rawValue))")
        }

        // **不扩授权模型**：能力位仍然恰好三个（加一个就等于改了卖点矩阵）。
        XCTAssertEqual(
            LicenseCapabilities.all.rawValue,
            LicenseCapabilities.workspaces.rawValue
                | LicenseCapabilities.database.rawValue
                | LicenseCapabilities.notes.rawValue,
            "能力位不再恰好是 workspace / database / notes 三个 —— Retro 不许挂能力位"
        )
        XCTAssertTrue(LicensePresentation.activityItems(for: .notesOnly).contains(.notes), "Standard 仍以笔记为家")

        UISnapshot.finishManifestIfEnabled()
    }

    // MARK: - 判据 ④-a 真读固定扫描目录（模型那一半）

    @MainActor
    func testRetroHostModelReallyReadsTheFixedScanRoot() throws {
        let root = ReportReader.fixedScanRootPath
        let model = ReportListModel.fixed()
        let order = model.state.packages.map(\.directoryName)

        print(
            "READING retro fixedRoot=\(root) packages=\(model.state.packages.count)"
                + " issues=\(model.state.issues.count) order=\(order)"
        )
        XCTAssertEqual(
            model.state.packages.count, 2,
            "固定扫描目录（\(root)）里应当恰好两包 —— 真读而不是造夹具；实测 \(model.state.packages.count) 条"
        )
        XCTAssertEqual(order, ["2026-W41", "2026-W40"], "列表应为新期在前（`FR-R-12` 倒序）")
        XCTAssertTrue(model.state.issues.isEmpty, "两包都该是成包的：\(model.state.issues.map(\.description))")

        // 「宿主不另传参」：模型走的是 Retro 侧那个唯一出处，不是本仓另写的一条路径。
        XCTAssertEqual(model.root.path, root, "模型扫的不是固定扫描目录 ⇒ 有两处真值")

        UISnapshot.finishManifestIfEnabled()
    }

    // MARK: - 判据 ④-b 宿主视图可构造、可布局、不崩

    @MainActor
    func testRetroHostViewLaysOutTheReaderWithoutCrashing() throws {
        let size = CGSize(width: 900, height: 560)
        let live = UISnapshot.LiveHost(RetroHostView(), size: size, scheme: .light)
        live.pump(0.5)

        // 证据（不是「没崩就算过」）：视图树里真的落下了滚动容器 —— SwiftUI 的 `List`
        // （期次列表）与右半边的 `ScrollView`（正文）都靠它。零个 ⇒ 这台阅读器其实没装配起来。
        let scrollViews = UISnapshot.LiveHost<Never>.findViews(ofType: NSScrollView.self, in: live.hosting)
        let tableViews = UISnapshot.LiveHost<Never>.findViews(ofType: NSTableView.self, in: live.hosting)
        XCTAssertGreaterThan(
            scrollViews.count, 0,
            "宿主视图树里一个滚动容器都没有 ⇒ 阅读器（列表 / 正文）没装配起来"
        )
        XCTAssertGreaterThan(live.hosting.bounds.width, 0, "宿主没有布局出宽度")
        XCTAssertGreaterThan(live.hosting.bounds.height, 0, "宿主没有布局出高度")

        // 能出图 = 整棵树可渲染（`signature()` 自己会 `settle()` 再取位图）。
        let first = try live.signature()
        let second = try live.signature()
        XCTAssertEqual(first.count, 64, "内容指纹不是 64 位十六进制：\(first)")
        print(
            "📄 M7-HOST ④ 宿主布局：滚动容器 \(scrollViews.count) 个 · 表格 \(tableViews.count) 个"
                + " · 尺寸 \(Int(live.hosting.bounds.width))×\(Int(live.hosting.bounds.height))"
                + " · 指纹 \(first.prefix(12))（两次一致 = \(first == second)）"
        )

        UISnapshot.finishManifestIfEnabled()
    }

    // MARK: - 判据 ④-c 接线（源锚点）+ 「宿主不造第二处真值」

    func testRetroHostWiringKeepsTheScanPathOutOfThisRepository() throws {
        let mainWindow = try source("App/Views/MainWindow.swift")
        XCTAssertTrue(
            mainWindow.contains("case .retro:"),
            "`MainWindow` 里没有 `.retro` 那一支 —— 活动栏切过去右侧不会换内容"
        )
        XCTAssertTrue(mainWindow.contains("RetroHostView()"), "`MainWindow` 没有装配 `RetroHostView`")
        XCTAssertTrue(
            mainWindow.contains("RetroSidebarPlaceholderView()"),
            "`MainWindow` 的 `.retro` 左栏支没有接上（`switch` 会漏掉一个分支）"
        )

        let host = try source("App/Views/RetroHostView.swift")
        for anchor in [
            "import DoyahRetroUI",              // 依赖真的接上来
            "ReportListModel.fixed()",          // 模型走 Retro 侧的唯一出处
            "ReportListView(model: model)",     // 左列表（视图代码在 Retro 仓）
            "ReportDetailView(package: package)", // 右正文（同上）
        ] {
            XCTAssertTrue(host.contains(anchor), "`RetroHostView.swift` 里找不到「\(anchor)」—— 装配那一步掉了")
        }

        // **宿主不另传参 / 不造第二处真值**：那个盘上路径在本仓的 `Core/` `App/` 里**零命中**。
        let forbidden = "geopolitics-weekly/packages"
        var offenders: [String] = []
        for directory in ["Core", "App"] {
            let base = Self.repositoryRoot.appendingPathComponent(directory)
            guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                if text.contains(forbidden) {
                    offenders.append(url.path.replacingOccurrences(of: Self.repositoryRoot.path + "/", with: ""))
                }
            }
        }
        XCTAssertTrue(
            offenders.isEmpty,
            "本仓 `Core/` `App/` 里出现了固定扫描目录的第二份字面量：\(offenders.sorted()) —— "
                + "唯一出处是 Retro 仓的 `ReportReader.fixedScanRootPath`"
        )

        print("📄 M7-HOST ④-c 接线：`MainWindow` / `RetroHostView` 锚点齐 · 本仓 `\(forbidden)` 零命中")
        UISnapshot.finishManifestIfEnabled()
    }

    // MARK: - 小工具

    /// 一个**成员**（`var` 访问器或 `func`）从声明处到它自己那个收尾花括号之间的源文本。
    ///
    /// 判据要的是「**这一处** switch 里有没有 `default`」—— 拿整个文件判会把别处的 `default`
    /// 也算进来（`ActivityBar.swift` 里就有别的 switch）。所以必须**按成员切**，而不是按文件切。
    private static func memberBody(named name: String, in source: String) -> String? {
        let heads = ["func \(name)(", "var \(name): "]
        guard let head = heads.compactMap({ source.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) else {
            return nil
        }
        let rest = source[head.lowerBound...]
        guard let end = rest.range(of: "\n    }") else { return String(rest) }
        return String(rest[..<end.lowerBound])
    }

    /// 去掉**整行注释**之后的源文本。
    ///
    /// 为什么必须去注释：判据查的是「这里有没有 `default`」这个**代码形状**，而注释里完全
    /// 可以写出 `default` 这个词（本仓的注释就写着「这一支不是 `default`」）—— 不剥注释的话，
    /// 判据会被自己的说明文字判红（这一条是实测踩出来的）。
    private static func codeOnly(_ source: String) -> String {
        source
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }
}
