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

    /// 判据 ②：**两包装进一个临时扫描根** ⇒ 列表 2 条 · 严格倒序；选中新期 ⇒ 右侧块模型 ≥1 条且首块 = `report.md` 首个标题。
    ///
    /// 2026-11-05 改（主人令「Retro 基本能力都不具备，beta1 只是个里程碑」）：
    /// 这条判据原来直接读**本机固定扫描根**（前门投放的真包），并断言「恰好 W41 / W40」——
    /// 而真包会一周一周往下长（现在已有 W40–W45），断言必然红，且红的原因是**数据变了**、不是能力坏了。
    /// 现在改成：**判据自带两个合成包**（在临时目录里现建），判据与被测对象的距离拉回确定性；
    /// 「真目录里现在有多少包」不再由判据断言（那是前门的产出，不是阅读器的契约）。
    @MainActor
    func testScanRootListsPackagesInReverseOrderAndRendersBody() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("retro-fixture-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        func makePackage(_ id: String, title: String, body: String) throws -> URL {
            let dir = root.appendingPathComponent(id, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let meta = """
            {
              "id": "\(id)",
              "title": "\(title)",
              "published": "2026-10-05",
              "summary": "合成夹具：判据自带，不依赖前门投放的真包。",
              "media_count": 0
            }
            """
            try meta.write(to: dir.appendingPathComponent("index.json"), atomically: true, encoding: .utf8)
            try body.write(to: dir.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
            return dir
        }

        _ = try makePackage("2026-W40", title: "夹具 W40", body: "# 夹具 W40 首标题\n\n正文一。\n")
        _ = try makePackage("2026-W41", title: "夹具 W41", body: "# 夹具 W41 首标题\n\n正文二。\n")

        let model = ReportListModel(root: root)
        let names = model.state.packages.map(\.directoryName)
        XCTAssertEqual(names, ["2026-W41", "2026-W40"], "2 条且倒序（新期在前）")

        let newest = try XCTUnwrap(model.state.packages.first)
        model.selectedDirectoryName = newest.directoryName
        XCTAssertEqual(model.selectedPackage?.metadata.id, newest.metadata.id)

        let expectedHeading = try XCTUnwrap(firstHeadingText(of: newest.reportMarkdown))
        let detail = ReportDetailView(package: newest)
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
