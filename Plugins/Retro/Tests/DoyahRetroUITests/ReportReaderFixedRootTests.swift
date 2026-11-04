import XCTest

import DoyahRetroCore
import DoyahRetroUI

// `M7-R` —— App **固定扫描目录** + 用前门（生成侧）产的两包跑通 `FR-R-12` **只读阅读器**
// （Retro macOS · 派单 `T-20261009-027` ②③④ · 任务卡 `t_13081cc7`）。
//
// 契约出处 = `Docs/需求规范书.md` §6.5 `IR-05`「导入面」（扫**固定目录**的直接子目录，含
// `index.json` + `report.md` 者为一包）+ §3.12 `FR-R-12-01` / `FR-R-12-02`（列表按发布日倒序 /
// 右侧按源文渲染）+ `FR-R-13-08` 判据 ① ② ④。
//
// 本族两条判据：
//   ① **声明形状**：`ReportReader.fixedScanRootPath` 是一条**绝对路径**，末两段 = `geopolitics-weekly`
//      / `packages`（唯一出处见 `ReportListView.swift` 的 `ReportReader` 注释）；
//   ② **两包实跑**：按固定目录建模型 ⇒ 列表 **2 条** · **倒序**（`2026-W41` 在前）· 右侧块模型 **≥1 条**
//      且首块 = `report.md` 的**首个标题**（读数打印成 `READING …` 行，见 `swift test` 输出）。
// 空态（空扫描根 ⇒ 0 条 + 提示）**沿用既有负例** `ReportViewShellTests.testEmptyScanRootShowsEmptyStateWithoutCrashing`。
//
// 夹具口径：两包由**前门（生成侧）**投放，本片**不自己造**顶替真包；本机没有那个固定目录时**如实跳过**
// （`XCTSkip`）—— **跳过 ≠ 通过**。
final class ReportReaderFixedRootTests: XCTestCase {

    // MARK: - 判据 ①：声明形状（不依赖盘上有没有那两包）

    /// 固定扫描目录是**绝对路径**，且末两段 = `geopolitics-weekly` / `packages`（唯一字面量在 Sources 里只出现一次）。
    func testFixedScanRootIsAnAbsolutePackagesDirectory() {
        let path = ReportReader.fixedScanRootPath
        XCTAssertTrue(path.hasPrefix("/"), "固定扫描目录应是绝对路径，实际 \(path)")

        let components = URL(fileURLWithPath: path).pathComponents
        XCTAssertEqual(Array(components.suffix(2)), ["geopolitics-weekly", "packages"])

        // `URL` 形态与字符串形态同源（不是第二份路径）。
        XCTAssertEqual(ReportReader.fixedScanRootURL.path, path)
        XCTAssertTrue(ReportReader.fixedScanRootURL.hasDirectoryPath)
    }

    // MARK: - 判据 ②：两包实跑（列表 2 条倒序 + 右侧渲染）

    /// 按固定目录建模型 ⇒ 列表 **2 条** · **倒序**（`2026-W41` → `2026-W40`）；选中新期 ⇒
    /// 右侧块模型 **≥1 条**且**首块 = `report.md` 的首个标题文本**。
    @MainActor
    func testFixedScanRootListsFrontDoorPackagesInReverseOrderAndRendersBody() throws {
        let root = ReportReader.fixedScanRootURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw XCTSkip("本机没有固定扫描目录（\(root.path)）—— 真包由前门投放，如实跳过，不造夹具顶替")
        }

        let model = ReportListModel.fixed()
        let names = model.state.packages.map(\.directoryName)
        let titles = model.state.packages.map(\.metadata.title)
        print("READING list.count=\(names.count) order=[\(names.joined(separator: " , "))] titles=[\(titles.joined(separator: " | "))]")
        XCTAssertEqual(names, ["2026-W41", "2026-W40"], "列表应为 2 条且倒序（新期在前）")
        XCTAssertTrue(model.state.issues.isEmpty, "两包都该是成包的，逐条报告应为空")

        // 右侧：选中列表首条（新期）⇒ 块模型 ≥1 条且首块是 `report.md` 的第一个标题。
        let newest = try XCTUnwrap(model.state.packages.first)
        model.selectedDirectoryName = newest.directoryName
        XCTAssertEqual(model.selectedPackage?.metadata.id, newest.metadata.id)

        let expectedHeading = try XCTUnwrap(firstHeadingText(of: newest.reportMarkdown),
                                            "report.md 应有首个标题")
        let detail = ReportDetailView(package: newest)
        print("READING detail.period=\(newest.directoryName) title=\(newest.metadata.title) blocks=\(detail.rendered.blocks.count) firstHeading=\(expectedHeading)")

        XCTAssertGreaterThanOrEqual(detail.rendered.blocks.count, 1, "右侧块模型至少 1 条")
        guard case .heading(let level, let text)? = detail.rendered.blocks.first else {
            return XCTFail("首块应为标题，实际 \(String(describing: detail.rendered.blocks.first))")
        }
        XCTAssertEqual(level, 1)
        XCTAssertEqual(text, expectedHeading)
    }

    // MARK: - 夹具

    /// `report.md` 第一行标题的**文本**（剥掉前导 `#` 与空白）；没有标题 ⇒ `nil`。
    private func firstHeadingText(of markdown: String) -> String? {
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") else { continue }
            let text = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { return text }
        }
        return nil
    }
}
