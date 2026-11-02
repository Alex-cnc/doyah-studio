import AppKit
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **工作区首页这一行**（`FR-STD-WS-FS-001`）的判据。
///
/// 台账原来只有一句「2026-11-01 取证：页签条几何两条探针」—— 那两条打的是页签条
/// （`WorkspaceTabStripOverflowProbeTests` / `WorkspaceChromeHeightProbeTests`，
/// 管的是「页签多了不换行、不撑高」），**没有一条打在首页内容上**。需求书那四点里
/// ②③（Home 里的欢迎语 / 版本 / 版权、三栏「最近打开」可点开）一直是空白，
/// 所以这一族补的是那一段。
///
/// ## 判据方向（需求书四点）
///
/// ① 切到工作区时编辑区不再沿用数据库查询界面，工作区页签是**独立类型**；
/// ② 默认打开 Home 欢迎页，含欢迎语 / 版本与构建号 / 版权；
/// ③ 三栏「最近打开」可点开对应文件；
/// ④ 数据库视图与工作区视图的页签互不影响。
///
/// ## 边界（如实登记）
///
/// · ①②③ 的**呈现**只判到源树与模型两层：本族不开窗口、不点鼠标（真点一次归人工点验）；
/// · 首页画出来的**观感**（字距 / 三栏宽度）不在本族视野里 —— 快照在 `UISnapshotTests`；
/// · 不写用户数据：历史 / 现场两份文件都落在 `.build/` 下的临时目录。
final class WorkspaceHomeProbeTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = UISnapshot.outputDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("workspace-home-probe", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
        scratch = nil
    }

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    @MainActor
    private func makeModel() -> WorkspaceTabsModel {
        WorkspaceTabsModel(
            store: WorkspaceHistoryStore(fileURL: scratch.appendingPathComponent("history.json")),
            sessionStore: WorkspaceSessionStore(
                fileURL: scratch.appendingPathComponent("session-\(UUID().uuidString).json")
            )
        )
    }

    // MARK: - ② 默认就是 Home 欢迎页

    /// 刚起来的工作区：**只有一页**，且那一页就是 Home（不是空编辑区、不是数据库查询界面）。
    @MainActor
    func testWorkspaceStartsOnASingleHomeTab() {
        let model = makeModel()

        XCTAssertEqual(model.tabs.count, 1, "工作区开局应当只有 Home 一页")
        let only = model.tabs[0]
        XCTAssertTrue(only.isHome, "开局那一页必须是 Home（kind == .home）")
        XCTAssertFalse(only.isAgentChat, "Home 不是对话页签（两者都 path == nil，容易混）")
        XCTAssertNil(only.path, "Home 不挂文件路径")
        XCTAssertEqual(model.selectedTab?.id, only.id, "开局选中的必须就是 Home")
    }

    /// 打开一个文件之后 Home **仍留着**（不是被顶掉）；关掉文件页签回到 Home。
    @MainActor
    func testHomeSurvivesFileTabsAndIsSelectedAfterClosingThem() throws {
        let file = scratch.appendingPathComponent("a.swift")
        try "let x = 1\n".write(to: file, atomically: true, encoding: .utf8)

        let model = makeModel()
        let home = try XCTUnwrap(model.tabs.first)
        model.openFile(at: file)

        XCTAssertEqual(model.tabs.count, 2)
        XCTAssertTrue(model.tabs.contains { $0.id == home.id }, "Home 页签不许被文件页签顶掉")
        XCTAssertEqual(model.selectedTab?.path, file.path, "打开文件后选中的是那一页文件")

        model.close(model.selectedTab!.id)
        XCTAssertEqual(model.selectedTab?.id, home.id, "关掉文件页签应当回到 Home")
    }

    // MARK: - ② 首页里那几行字（欢迎语 / 版本与构建号 / 版权）

    func testHomeCarriesWelcomeVersionBuildAndCopyright() throws {
        let view = try source("App/Views/WorkspaceAreaView.swift")

        XCTAssertTrue(view.contains("WorkspaceHomeView()"), "Home 页签必须画 WorkspaceHomeView")
        XCTAssertTrue(view.contains("if tab.isHome"), "Home 与文件页签必须是两条呈现分支（独立类型）")
        for key in [
            "workspaceHomeWelcome",      // 欢迎语
            "workspaceHomeBuildLine",    // 版本 + 构建号
            "workspaceHomeCopyright"     // 版权
        ] {
            XCTAssertTrue(view.contains(key), "首页缺这一行：\(key)")
        }
        XCTAssertTrue(
            view.contains("Self.appVersion") && view.contains("Self.buildStamp"),
            "版本行必须带真版本号与构建号，不能是常量文案"
        )
    }

    // MARK: - ③ 三栏「最近打开」各自接得上有东西的地方

    func testHomeHasThreeRecentSectionsEachWiredToARealAction() throws {
        let view = try source("App/Views/WorkspaceAreaView.swift")

        // 三栏都在：文件 / 工作区 / 连接
        for key in ["workspaceRecentFiles", "workspaceRecentWorkspaces", "workspaceConnections"] {
            XCTAssertTrue(view.contains(key), "首页缺这一栏：\(key)")
        }

        // 文件栏：点一行 = 在工作区里打开那个文件
        XCTAssertTrue(view.contains("tabs.openFile(at: URL(fileURLWithPath: entry.path))"),
                      "「最近文件」那一行必须真打开文件，不能只显示路径")

        // 连接栏：点一行 = 切到那个连接并进数据库视图（走统一入口，未授权时它会照实说一句）
        XCTAssertTrue(view.contains("appState.selectedConnectionID = configuration.id"),
                      "「最近连接」那一行必须真的切连接")
        XCTAssertTrue(view.contains("appState.selectActivityItem(.database)"),
                      "进数据库视图要走统一入口（权限判定只有那一处）")

        // 工作区栏：来源必须是「授权过的」清单，不是历史流水（历史路径在沙箱下打不开）
        XCTAssertTrue(view.contains("workspace.knownWorkspaces"),
                      "「最近工作区」必须读已知工作区清单（不是 history.workspaces 的流水）")
    }

    /// 历史记录真的能灌进「最近文件」那一栏（模型 → 视图那条线的数据端）。
    @MainActor
    func testOpeningAFileRecordsItForTheHomeList() throws {
        let file = scratch.appendingPathComponent("b.md")
        try "# 标题\n".write(to: file, atomically: true, encoding: .utf8)

        let model = makeModel()
        model.openFile(at: file)

        XCTAssertEqual(model.history.files.first?.path, file.path, "打开过的文件要进「最近打开」")
    }

    // MARK: - ④ 与数据库视图的页签互不影响

    /// 两边是**两个模型**（`AppState.tabs: [QueryTab]` 与 `WorkspaceTabsModel.tabs: [WorkspaceTab]`），
    /// 类型不同、集合不同 —— 这条钉的是「没有人图省事把两者并成一份」。
    func testWorkspaceAndDatabaseTabsOwnSeparateCollections() throws {
        let appState = try source("App/AppState.swift")
        XCTAssertTrue(appState.contains("[QueryTab]"), "数据库侧页签是 QueryTab 的集合")

        let workspace = try source("App/WorkspaceTabsModel.swift")
        XCTAssertTrue(workspace.contains("[WorkspaceTab]"), "工作区侧页签是 WorkspaceTab 的集合")
        XCTAssertFalse(workspace.contains("QueryTab"), "工作区页签模型不许直接读写数据库页签")
        XCTAssertFalse(appState.contains("[WorkspaceTab]"), "数据库侧状态机不许持有工作区页签")
    }
}
