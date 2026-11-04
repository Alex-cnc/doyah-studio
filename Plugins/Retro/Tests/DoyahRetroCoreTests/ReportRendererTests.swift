import XCTest
@testable import DoyahRetroCore

// `report.md` ⇒ 块序列（纯函数渲染）的机械证据（Retro macOS · M0 第 2 片）。
//
// 判据口径（与 `FR-R-13-08` ②③④ / `IR-05` 不变量 3 / 概要设计 §3.5 不变量 1 同源）：
//   ① 块覆盖逐条成立：**标题 1–6 · 段落 · 引用 · 表格（含 `|` 分隔与列数一致）· 有序 / 无序列表 · 图片 · 分隔线**；
//   ② 图片**相对路径**：`![](assets/x.png)` ⇒ 解析为**包内绝对路径**；文件缺失 ⇒ **占位 + 一条报告**；
//      含 `../` 的越界路径 ⇒ **拒绝 + 报告**；绝对路径 / base64 ⇒ **拒绝 + 报告**（本渲染器无这两条分支）；
//   ③ **纯函数**：同一份 `report.md` 连续两次渲染 ⇒ 输出**逐字节相同**。
// 三条纪律：跑**真目录真文件**（临时目录）；负例逐条点名；**不静默丢弃**（每条坏引用都必须对上一条报告）。
final class ReportRendererTests: XCTestCase {

    private var packageDirectory: URL!

    override func setUpWithError() throws {
        packageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-retro-render-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let packageDirectory { try? FileManager.default.removeItem(at: packageDirectory) }
    }

    // MARK: - 夹具

    /// 在包目录里落一个文件（逐级建目录）。URL 构造口径与渲染器一致（`relativeTo:` + 标准化）。
    @discardableResult
    private func writeFile(_ relativePath: String, bytes: Data = Data([0x89, 0x50, 0x4E, 0x47])) throws -> URL {
        let url = inPackageURL(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url)
        return url
    }

    private func render(_ markdown: String) -> RenderedReport {
        ReportRenderer.render(markdown: markdown, packageDirectory: packageDirectory)
    }

    /// 期望的「包内绝对路径」：与渲染器同一种构造（`relativeTo:` + 标准化）。
    private func inPackageURL(_ reference: String) -> URL {
        URL(fileURLWithPath: reference, isDirectory: false, relativeTo: packageDirectory.standardizedFileURL)
            .standardizedFileURL
    }

    /// FNV-1a 64 —— 纯函数判据里贴出来给人对账的指纹（不引依赖，逐字节稳定）。
    private func fnv1a64(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx", hash)
    }

    // MARK: - 块覆盖（判据 ③）

    func testHeadingLevelsOneThroughSixAreCovered() {
        let markdown = """
        # 一级
        ## 二级
        ### 三级
        #### 四级
        ##### 五级
        ###### 六级
        ####### 七个井号不是标题
        """

        let report = render(markdown)

        XCTAssertEqual(report.issues.count, 0)
        XCTAssertEqual(report.blocks, [
            .heading(level: 1, text: "一级"),
            .heading(level: 2, text: "二级"),
            .heading(level: 3, text: "三级"),
            .heading(level: 4, text: "四级"),
            .heading(level: 5, text: "五级"),
            .heading(level: 6, text: "六级"),
            .paragraph(text: "####### 七个井号不是标题")
        ])
    }

    func testParagraphKeepsLinesAndBlankLineSeparatesParagraphs() {
        let markdown = "第一段第一行\n第一段第二行\n\n第二段"

        let report = render(markdown)

        XCTAssertEqual(report.blocks, [
            .paragraph(text: "第一段第一行\n第一段第二行"),
            .paragraph(text: "第二段")
        ])
    }

    func testQuoteBlockStripsMarkerPerLine() {
        let markdown = "> 引用第一行\n> 引用第二行\n\n普通段落"

        let report = render(markdown)

        XCTAssertEqual(report.blocks, [
            .quote(text: "引用第一行\n引用第二行"),
            .paragraph(text: "普通段落")
        ])
    }

    func testTableSplitsHeaderAndRowsWithConsistentColumnCount() {
        let markdown = """
        | 指数 | 收盘 | 涨跌 |
        | --- | :---: | ---: |
        | 上证 | 3200 | +0.5% |
        | 恒生 | 19800 | -0.2% |
        """

        let report = render(markdown)

        guard case .table(let header, let rows) = report.blocks.first else {
            return XCTFail("首块应是表格，实为 \(String(describing: report.blocks.first))")
        }
        XCTAssertEqual(header, ["指数", "收盘", "涨跌"], "表头按未转义 `|` 分隔")
        XCTAssertEqual(rows, [["上证", "3200", "+0.5%"], ["恒生", "19800", "-0.2%"]])
        XCTAssertEqual(report.blocks.count, 1, "分隔行不是数据行")
        for row in rows {
            XCTAssertEqual(row.count, header.count, "数据行列数须与表头一致：\(row)")
        }
    }

    func testUnorderedListItems() {
        let markdown = "- 上证 3200\n- 恒生 19800\n* 道指 42000\n\n正文"

        let report = render(markdown)

        XCTAssertEqual(report.blocks, [
            .unorderedList(items: ["上证 3200", "恒生 19800", "道指 42000"]),
            .paragraph(text: "正文")
        ])
    }

    func testOrderedListItems() {
        let markdown = "1. 第一步\n2. 第二步\n3. 第三步"

        let report = render(markdown)

        XCTAssertEqual(report.blocks, [.orderedList(items: ["第一步", "第二步", "第三步"])])
    }

    func testCodeBlockKeepsLanguageAndBody() {
        let markdown = "```swift\nlet a = 1\nlet b = 2\n```\n\n收尾"

        let report = render(markdown)

        XCTAssertEqual(report.blocks, [
            .codeBlock(language: "swift", text: "let a = 1\nlet b = 2"),
            .paragraph(text: "收尾")
        ])
    }

    func testHorizontalRule() {
        let markdown = "上文\n\n---\n\n下文"

        let report = render(markdown)

        XCTAssertEqual(report.blocks, [
            .paragraph(text: "上文"),
            .horizontalRule,
            .paragraph(text: "下文")
        ])
    }

    /// 一份「应有尽有」的样例：九条块分支逐条各出现至少一次。
    func testFullSampleCoversEveryBlockKind() throws {
        try writeFile("assets/cover.png")
        let markdown = """
        # 国际趋势分析周报

        开篇段落。

        > 引用一句

        | 指数 | 收盘 |
        | --- | --- |
        | 上证 | 3200 |

        - 无序一
        - 无序二

        1. 有序一
        2. 有序二

        ![](assets/cover.png)

        ```text
        代码块
        ```

        ---
        """

        let report = render(markdown)

        XCTAssertEqual(report.issues.count, 0, "样例里没有坏引用：\(report.issues.map(\.description))")
        XCTAssertEqual(report.blocks.count, 9, "九条块分支各一块：标题 / 段落 / 引用 / 表格 / 无序 / 有序 / 图片 / 代码块 / 分隔线")
        XCTAssertEqual(report.blocks[0], .heading(level: 1, text: "国际趋势分析周报"))
        XCTAssertEqual(report.blocks[1], .paragraph(text: "开篇段落。"))
        XCTAssertEqual(report.blocks[2], .quote(text: "引用一句"))
        if case .table(let header, let rows) = report.blocks[3] {
            XCTAssertEqual(header, ["指数", "收盘"])
            XCTAssertEqual(rows, [["上证", "3200"]])
        } else {
            XCTFail("第 4 块应是表格")
        }
        XCTAssertEqual(report.blocks[4], .unorderedList(items: ["无序一", "无序二"]))
        XCTAssertEqual(report.blocks[5], .orderedList(items: ["有序一", "有序二"]))
        XCTAssertEqual(report.blocks[7], .codeBlock(language: "text", text: "代码块"))
        XCTAssertEqual(report.blocks[8], .horizontalRule)
        guard case .image(let image) = report.blocks[6] else {
            return XCTFail("第 7 块应是图片，实为 \(String(describing: report.blocks[6]))")
        }
        XCTAssertEqual(image.resolution, .inPackage(inPackageURL("assets/cover.png")))
    }

    // MARK: - 图片相对路径（判据 ④）

    func testImageReferenceResolvesToInPackageAbsolutePath() throws {
        let expected = try writeFile("assets/trend.png")

        let report = render("![趋势图](assets/trend.png)")

        XCTAssertEqual(report.issues.count, 0)
        guard case .image(let image) = report.blocks.first else {
            return XCTFail("应是图片块，实为 \(String(describing: report.blocks.first))")
        }
        XCTAssertEqual(image.alt, "趋势图")
        XCTAssertEqual(image.reference, "assets/trend.png")
        XCTAssertEqual(image.resolution, .inPackage(expected.standardizedFileURL))
        // 解析出来的必须是**包内绝对路径**（不是源文里的相对串）。
        if case .inPackage(let url) = image.resolution {
            XCTAssertTrue(url.path.hasPrefix(packageDirectory.standardizedFileURL.path + "/"),
                          "解析结果须落在包目录内：\(url.path)")
        }
    }

    func testMissingImageFileYieldsPlaceholderAndOneIssue() {
        let report = render("开头\n\n![](assets/missing.png)\n\n结尾")

        XCTAssertEqual(report.blocks.count, 3)
        guard case .image(let image) = report.blocks[1] else {
            return XCTFail("第 2 块应是图片")
        }
        XCTAssertEqual(image.resolution, .placeholder(reason: .fileMissing), "文件缺失 ⇒ 原位占位（不静默丢弃）")
        XCTAssertEqual(report.issues, [ReportRenderIssue(line: 3, kind: .imageFileMissing(reference: "assets/missing.png"))])
    }

    func testParentTraversalImageIsRejectedAndReported() {
        let report = render("![](../outside.png)")

        guard case .image(let image) = report.blocks.first else {
            return XCTFail("应是图片块（占位），实为 \(String(describing: report.blocks.first))")
        }
        XCTAssertEqual(image.resolution, .placeholder(reason: .pathOutOfPackage), "`../` ⇒ 拒绝")
        XCTAssertEqual(report.issues, [ReportRenderIssue(line: 1, kind: .imagePathOutOfPackage(reference: "../outside.png"))])
    }

    /// `../` 即使「绕回包内」（`assets/../assets/x.png`）也一律拒绝 —— 判据原文是「含 `../` 的越界路径」。
    func testDotDotInTheMiddleIsAlsoRejected() throws {
        try writeFile("assets/x.png")

        let report = render("![](assets/../assets/x.png)")

        guard case .image(let image) = report.blocks.first else {
            return XCTFail("应是图片块（占位）")
        }
        XCTAssertEqual(image.resolution, .placeholder(reason: .pathOutOfPackage))
        XCTAssertEqual(report.issues.count, 1)
    }

    func testAbsolutePathImageIsRejectedAndReported() {
        let report = render("![](/etc/hosts)")

        guard case .image(let image) = report.blocks.first else {
            return XCTFail("应是图片块（占位）")
        }
        XCTAssertEqual(image.resolution, .placeholder(reason: .referenceNotRelative),
                       "绝对路径 ⇒ 拒绝（本渲染器不设按绝对路径取图的分支）")
        XCTAssertEqual(report.issues, [ReportRenderIssue(line: 1, kind: .imageReferenceNotRelative(reference: "/etc/hosts"))])
    }

    func testBase64ImageIsRejectedAndReported() {
        let report = render("![](data:image/png;base64,iVBORw0KGgo=)")

        guard case .image(let image) = report.blocks.first else {
            return XCTFail("应是图片块（占位）")
        }
        XCTAssertEqual(image.resolution, .placeholder(reason: .referenceNotRelative),
                       "base64 ⇒ 拒绝（`IR-05` 不变量 3：不内嵌 base64）")
        XCTAssertEqual(report.issues, [ReportRenderIssue(line: 1, kind: .imageReferenceNotRelative(reference: "data:image/png;base64,iVBORw0KGgo="))])
    }

    /// 坏引用**不影响**别的块与别的图：好图照样解析、坏图逐条占位（逐条报告且不崩）。
    func testMixedImagesReportEachBadOneWithoutStopping() throws {
        let good = try writeFile("assets/good.png")
        let markdown = "![](assets/good.png)\n![](assets/none.png)\n![](../escape.png)"

        let report = render(markdown)

        XCTAssertEqual(report.blocks.count, 3)
        guard case .image(let first) = report.blocks[0] else { return XCTFail("第 1 块应是图片") }
        XCTAssertEqual(first.resolution, .inPackage(good.standardizedFileURL))
        XCTAssertEqual(report.issues.map(\.line), [2, 3], "坏引用逐条报告（行号对上）")
        XCTAssertEqual(report.issues[0].kind, .imageFileMissing(reference: "assets/none.png"))
        XCTAssertEqual(report.issues[1].kind, .imagePathOutOfPackage(reference: "../escape.png"))
    }

    // MARK: - 纯函数（判据 ⑤）

    /// **同一份 `report.md` 连续两次渲染 ⇒ 输出逐字节相同**（概要设计 §3.5 不变量 1）。
    ///
    /// 跑法：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter testRenderIsPureFunction`
    func testRenderIsPureFunction() throws {
        try writeFile("assets/cover.png")
        let markdown = """
        # 国际趋势分析周报

        正文段落，含 `|` 与 `> ` 等干扰字符。

        > 引用

        | 指数 | 收盘 |
        | --- | --- |
        | 上证 | 3200 |

        - 无序
        1. 有序

        ![](assets/cover.png)
        ![](assets/missing.png)

        ```text
        代码
        ```

        ---
        """

        let first = render(markdown)
        let second = render(markdown)

        XCTAssertEqual(first, second, "两次渲染的块序列与报告条目必须相等")

        let firstBytes = Data(String(describing: first).utf8)
        let secondBytes = Data(String(describing: second).utf8)
        XCTAssertEqual(firstBytes, secondBytes, "两次渲染的产物必须**逐字节相同**")

        print("[纯函数判据] 产物字节数=\(firstBytes.count) FNV-1a=\(fnv1a64(firstBytes)) 块数=\(first.blocks.count) 报告条目=\(first.issues.count)")
        print("[纯函数判据] 第二次渲染 FNV-1a=\(fnv1a64(secondBytes))")
    }

    // MARK: - 与 R-01 的包接起来（真实盘上的一期）

    func testRenderFromScannedReportPackage() throws {
        // 造一期真包（`index.json` + `report.md` + `assets/`），过 R-01 的扫描器，再渲染。
        try writeFile("2026-W40/index.json", bytes: Data("""
        { "id": "2026-W40", "title": "国际趋势分析周报", "published": "2026-10-06", \
        "summary": "三条主线", "cover": "assets/cover.png", "media_count": 1 }
        """.utf8))
        try writeFile("2026-W40/report.md", bytes: Data("# 本期\n\n![](assets/cover.png)\n".utf8))
        try writeFile("2026-W40/assets/cover.png")

        let result = try ReportPackageScanner.scan(rootDirectory: packageDirectory)
        XCTAssertEqual(result.issues.count, 0)
        let package = try XCTUnwrap(result.packages.first)

        let report = ReportRenderer.render(package: package)

        XCTAssertEqual(report.issues.count, 0)
        XCTAssertEqual(report.blocks.count, 2)
        guard case .image(let image) = report.blocks[1] else { return XCTFail("第 2 块应是图片") }
        XCTAssertEqual(image.resolution, .inPackage(inPackageURL("2026-W40/assets/cover.png")))
    }
}
