import XCTest

import DoyahRetroCore
import DoyahRetroUI

// `FR-R-13-08` 判据 ④ 的机械形式 —— **视图层**口径（Retro macOS · M0 第 4 片 · 派单卡 `t_66956c06`）：
//
//   > 空包 / 缺件 / 编码错 ⇒ **逐条报告且不崩**（与 `FR-R-12-04` ③ 同口径）
//
// 四条负例逐条点名：**空扫描根 / 缺 `index.json` / 坏 JSON / 缺 `report.md`** —— 每例都断言
// 「拿到一个确定状态（空态或逐条报告）」，没有任何异常冒到视图树里。另附正例 / 混排 /
// 详情渲染的兜底用例（渲染报告与媒体报告都不静默）。
//
// 本族测的是**视图层的数据源与装配**（`ReportListPresenter` / `ReportListModel` / `ReportDetailView`），
// 不是像素：界面「出不出空态 / 出不出逐条」由这些状态决定，故判据钉在这里。
final class ReportViewShellTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("doyah-retro-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    // MARK: - 负例四条（判据 ④，逐条点名）

    /// 空扫描根（目录在、一个子目录都没有）⇒ **空态**，不崩。
    func testEmptyScanRootShowsEmptyStateWithoutCrashing() {
        let state = ReportListPresenter.present(root: root)
        XCTAssertEqual(state, .scanned(packages: [], issues: []))
        XCTAssertTrue(state.isEmpty)
    }

    /// 扫描根不可用（不存在）⇒ **空态**（不是异常冒到界面），不崩。
    func testMissingScanRootShowsEmptyStateWithoutCrashing() {
        let missing = root.appendingPathComponent("nothing-here", isDirectory: true)
        let state = ReportListPresenter.present(root: missing)
        XCTAssertEqual(state, .rootUnavailable(path: missing.path))
        XCTAssertTrue(state.isEmpty)
    }

    /// 缺 `index.json`（有 `report.md`）⇒ 逐条报告一条。
    func testMissingIndexJSONIsReportedPerItem() throws {
        try makeDirectory("2026-W40", files: ["report.md": "# 正文\n"])
        let state = ReportListPresenter.present(root: root)
        XCTAssertEqual(state.issues.map(\.kind), [ReportPackageIssue.Kind.missingIndexJSON])
        XCTAssertTrue(state.packages.isEmpty)
    }

    /// 坏 JSON ⇒ 逐条报告一条（不崩、不吞）。
    func testBadJSONIsReportedPerItem() throws {
        try makeDirectory("2026-W40", files: ["index.json": "{ 这不是 JSON", "report.md": "# 正文\n"])
        let state = ReportListPresenter.present(root: root)
        XCTAssertEqual(state.issues.map(\.directoryName), ["2026-W40"])
        XCTAssertEqual(state.issues.count, 1)
        guard case .invalidJSON = state.issues[0].kind else {
            return XCTFail("坏 JSON 应逐条报 invalidJSON，实际 \(state.issues[0].kind)")
        }
    }

    /// 缺 `report.md`（有 `index.json`）⇒ 逐条报告一条。
    func testMissingReportMDIsReportedPerItem() throws {
        try makeDirectory("2026-W40", files: ["index.json": indexJSON()])
        let state = ReportListPresenter.present(root: root)
        XCTAssertEqual(state.issues.map(\.kind), [ReportPackageIssue.Kind.missingReportMD])
        XCTAssertTrue(state.packages.isEmpty)
    }

    // MARK: - 正例 / 混排（好包仍列出，坏包不打断）

    /// 好包 ⇒ 一张卡，字段齐（期号 / 标题 / 日期）。
    func testGoodPackageIsListedWithCardFields() throws {
        try makeDirectory("2026-W40", files: ["index.json": indexJSON(), "report.md": "# 标题\n\n正文\n"])
        let state = ReportListPresenter.present(root: root)
        XCTAssertEqual(state.packages.count, 1)
        let package = try XCTUnwrap(state.packages.first)
        XCTAssertEqual(package.metadata.id, "2026-W40")
        XCTAssertEqual(package.metadata.title, "示例周报")
        XCTAssertEqual(package.metadata.published, "2026-10-06")
        XCTAssertTrue(state.issues.isEmpty)
    }

    /// 好包 + 坏包混排 ⇒ 好包照列、坏包逐条 —— 互不打断。
    func testGoodAndBadPackagesCoexistWithoutCrashing() throws {
        try makeDirectory("2026-W40", files: ["index.json": indexJSON(), "report.md": "# 标题\n"])
        try makeDirectory("2026-W41", files: ["index.json": indexJSON()])
        let state = ReportListPresenter.present(root: root)
        XCTAssertEqual(state.packages.map(\.directoryName), ["2026-W40"])
        XCTAssertEqual(state.issues.map(\.directoryName), ["2026-W41"])
        XCTAssertFalse(state.isEmpty)
    }

    // MARK: - 模型 / 详情（一次都不崩）

    /// 模型的重复刷新是确定的（纯映射），选中关系对得上期号。
    @MainActor
    func testListModelReloadKeepsDeterministicState() throws {
        try makeDirectory("2026-W40", files: ["index.json": indexJSON(), "report.md": "# 标题\n"])
        let model = ReportListModel(root: root)
        let first = model.state
        model.reload()
        XCTAssertEqual(model.state, first)
        XCTAssertNil(model.selectedPackage)
        model.selectedDirectoryName = "2026-W40"
        XCTAssertEqual(model.selectedPackage?.metadata.id, "2026-W40")
    }

    /// 详情：好包渲染出块序列，且没有报告条目。
    func testDetailRendersGoodPackageBlocksWithoutCrashing() throws {
        try makeDirectory("2026-W40", files: ["index.json": indexJSON(), "report.md": "# 标题\n\n正文\n"])
        let package = try XCTUnwrap(ReportListPresenter.present(root: root).packages.first)
        let detail = ReportDetailView(package: package)
        XCTAssertEqual(detail.rendered.blocks.count, 2)
        XCTAssertTrue(detail.rendered.issues.isEmpty)
        XCTAssertTrue(detail.mediaIssues.isEmpty)
    }

    /// 详情：图片缺失 ⇒ 渲染报告与媒体报告**各**一条（不静默），界面仍把这一期画完。
    func testDetailReportsMissingImagePerItem() throws {
        let markdown = "# 标题\n\n![趋势图](assets/missing.png)\n"
        try makeDirectory("2026-W40", files: ["index.json": indexJSON(), "report.md": markdown])
        let package = try XCTUnwrap(ReportListPresenter.present(root: root).packages.first)
        let detail = ReportDetailView(package: package)
        XCTAssertEqual(detail.rendered.blocks.count, 2)
        XCTAssertEqual(detail.rendered.issues.count, 1)
        guard case .imageFileMissing(let reference) = detail.rendered.issues[0].kind else {
            return XCTFail("应为 imageFileMissing，实际 \(detail.rendered.issues[0].kind)")
        }
        XCTAssertEqual(reference, "assets/missing.png")
        XCTAssertEqual(detail.mediaIssues.count, 1)
        XCTAssertEqual(detail.mediaIssues[0].reference, "assets/missing.png")
    }

    // MARK: - 夹具

    private func indexJSON(mediaCount: Int = 0) -> String {
        """
        {"id":"2026-W40","title":"示例周报","published":"2026-10-06","summary":"摘要","media_count":\(mediaCount)}
        """
    }

    private func makeDirectory(_ name: String, files: [String: String]) throws {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (file, body) in files {
            try Data(body.utf8).write(to: directory.appendingPathComponent(file))
        }
    }
}
