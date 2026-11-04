import XCTest
@testable import DoyahRetroCore

// `IR-05` 周报包扫描 / 解析的机械证据（Retro macOS · M0 第 1 片）。
//
// 判据口径（与 `FR-R-12-04` ③ / `FR-R-13-08` ④ 同源）：坏包**逐条报告且不崩** ——
// 每个负例把**具体的一份坏包**放进临时扫描根，断言**恰好那一条** issue（而不是「没崩就算过」）。
// 三条纪律：
//   ① 跑**真目录真文件**（临时目录）—— 扫描 / 解析吃的是盘上的字节，纯内存测不出现场；
//   ② 负例逐条点名：缺件 · 空目录 · 坏 JSON · 非 UTF-8 · 带 BOM · 目录名非期号 · 字段缺失 / 类型错；
//   ③ `assets/` 缺失**不算错**（不变量 2 明写「可空」）—— 单列一条，防止把「可空」实现成「必填」。
final class ReportPackageTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-retro-report-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    // MARK: - 夹具

    /// 盘上 `index.json` 的一份合法最小集（键名与契约不变量 4 逐名对应）。
    private func validIndexJSON(
        id: String,
        title: String = "国际趋势分析周报",
        published: String = "2026-10-06",
        summary: String = "本期摘要：三条主线 + 两个风险",
        cover: String? = "assets/cover.png",
        mediaCount: Int = 3
    ) -> String {
        var fields = [
            "\"id\": \"\(id)\"",
            "\"title\": \"\(title)\"",
            "\"published\": \"\(published)\"",
            "\"summary\": \"\(summary)\""
        ]
        if let cover { fields.append("\"cover\": \"\(cover)\"") }
        fields.append("\"media_count\": \(mediaCount)")
        return "{ " + fields.joined(separator: ", ") + " }"
    }

    @discardableResult
    private func makeDirectory(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    /// 造一份「应有尽有」的包目录（`assets/` 可选）。
    private func makePackage(
        _ name: String,
        indexJSON: String? = nil,
        report: String = "# 本期周报\n\n正文第一段。",
        assets: Bool = true
    ) throws {
        let directory = try makeDirectory(name)
        try write(indexJSON ?? validIndexJSON(id: name), to: directory.appendingPathComponent("index.json"))
        try write(report, to: directory.appendingPathComponent("report.md"))
        if assets {
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent("assets", isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    /// 直接落字节（用于非 UTF-8 / 带 BOM 这类「非文本」夹具）。
    private func makeRaw(_ name: String, index: Data?, report: Data?) throws {
        let directory = try makeDirectory(name)
        if let index { try index.write(to: directory.appendingPathComponent("index.json")) }
        if let report { try report.write(to: directory.appendingPathComponent("report.md")) }
    }

    private func scan() throws -> ReportScanResult {
        try ReportPackageScanner.scan(rootDirectory: root)
    }

    // MARK: - 正例

    func testValidPackageIsScannedAndDecoded() throws {
        try makePackage("2026-W40")

        let result = try scan()

        XCTAssertEqual(result.issues.count, 0, "合法包不该产出 issue：\(result.issues.map(\.description))")
        XCTAssertEqual(result.packages.count, 1)
        let package = try XCTUnwrap(result.packages.first)
        XCTAssertEqual(package.directoryName, "2026-W40")
        XCTAssertEqual(package.metadata.id, "2026-W40", "目录名即 id（不变量 1）")
        XCTAssertEqual(package.metadata.title, "国际趋势分析周报")
        XCTAssertEqual(package.metadata.published, "2026-10-06")
        XCTAssertEqual(package.metadata.summary, "本期摘要：三条主线 + 两个风险")
        XCTAssertEqual(package.metadata.cover, "assets/cover.png")
        XCTAssertEqual(package.metadata.mediaCount, 3)
        XCTAssertEqual(package.directoryURL.lastPathComponent, "2026-W40")
    }

    func testPackageWithoutCoverYieldsNilCover() throws {
        try makePackage("20261006", indexJSON: validIndexJSON(id: "20261006", cover: nil))

        let result = try scan()

        let package = try XCTUnwrap(result.packages.first)
        XCTAssertNil(package.metadata.cover, "`cover` 是可选字段（不变量 4）")
        XCTAssertEqual(result.issues.count, 0)
    }

    func testReportMarkdownContentIsReturnedVerbatim() throws {
        let body = "# 核心行情\n\n- 上证 3200\n- 恒生 19800\n\n> 引用一段\n"
        try makePackage("2026-W41", report: body)

        let package = try XCTUnwrap(try scan().packages.first)

        XCTAssertEqual(package.reportMarkdown, body, "正文按原样读出，不改写")
    }

    func testPackagesAreSortedByPublishedDescending() throws {
        try makePackage("2026-W39", indexJSON: validIndexJSON(id: "2026-W39", published: "2026-09-21"))
        try makePackage("2026-W41", indexJSON: validIndexJSON(id: "2026-W41", published: "2026-10-06"))
        try makePackage("2026-W40", indexJSON: validIndexJSON(id: "2026-W40", published: "2026-09-28"))

        let result = try scan()

        XCTAssertEqual(result.packages.map(\.directoryName), ["2026-W41", "2026-W40", "2026-W39"], "新期在前")
    }

    func testLooseFilesInScanRootAreIgnored() throws {
        try makePackage("2026-W40")
        try write("这不是包，是个散落文件", to: root.appendingPathComponent("说明.txt"))
        try write("{}", to: root.appendingPathComponent("index.json"))

        let result = try scan()

        XCTAssertEqual(result.packages.count, 1)
        XCTAssertEqual(result.issues.count, 0, "根下普通文件不该被当成坏包：\(result.issues.map(\.description))")
    }

    /// 不变量 2 的机械形式：`assets/` 是**可空**的 ⇒ 没有它，包照样成立。
    func testMissingAssetsDirectoryIsNotAnIssue() throws {
        try makePackage("2026-W42", assets: false)

        let result = try scan()

        XCTAssertEqual(result.packages.count, 1, "缺 assets/ 不算错（不变量 2「媒体目录，可空」）")
        XCTAssertEqual(result.issues.count, 0)
    }

    // MARK: - 期号形状（不变量 1）—— 纯函数那半边

    func testPeriodShapeAcceptsISOWeekAndDate() {
        for name in ["2026-W01", "2026-W40", "2026-W53", "20261006", "19990101", "20261231"] {
            XCTAssertTrue(ReportPeriod.isValid(name), "\(name) 是合法期号")
        }
    }

    func testPeriodShapeRejectsNonPeriodNames() {
        for name in [
            "2026-W00",      // 周号下界外
            "2026-W54",      // 周号上界外
            "2026W40",       // 缺分隔符
            "2026-40",       // 缺 W
            "2026-w40",      // 小写 w
            "20261301",      // 月 13
            "20260132",      // 日 32
            "2026106",       // 少一位
            "202610066",     // 多一位
            "not-a-period",  // 完全不是期号
            ""               // 空
        ] {
            XCTAssertFalse(ReportPeriod.isValid(name), "\(name) 不是合法期号")
        }
    }

    // MARK: - 负例（逐条）

    func testMissingIndexJSONIsReported() throws {
        let directory = try makeDirectory("2026-W40")
        try write("# 只有正文", to: directory.appendingPathComponent("report.md"))

        let result = try scan()

        XCTAssertEqual(result.packages.count, 0)
        XCTAssertEqual(result.issues.map(\.kind), [.missingIndexJSON])
        XCTAssertEqual(result.issues.first?.directoryName, "2026-W40")
    }

    func testMissingReportMDIsReported() throws {
        let directory = try makeDirectory("2026-W40")
        try write(validIndexJSON(id: "2026-W40"), to: directory.appendingPathComponent("index.json"))

        let result = try scan()

        XCTAssertEqual(result.packages.count, 0)
        XCTAssertEqual(result.issues.map(\.kind), [.missingReportMD])
    }

    func testEmptyDirectoryIsReported() throws {
        try makeDirectory("2026-W40")

        let result = try scan()

        XCTAssertEqual(result.packages.count, 0)
        XCTAssertEqual(result.issues.map(\.kind), [.emptyDirectory])
    }

    func testBadJSONIsReported() throws {
        try makePackage("2026-W40", indexJSON: "{ 这不是 JSON ")

        let result = try scan()

        XCTAssertEqual(result.packages.count, 0)
        XCTAssertEqual(result.issues.map(\.kind).count, 1)
        guard case .invalidJSON = result.issues.first?.kind else {
            return XCTFail("应是 invalidJSON，实为 \(String(describing: result.issues.first?.kind))")
        }
    }

    func testNonUTF8IndexIsReported() throws {
        let broken = Data([0xFF, 0xFE, 0x7B, 0x7D]) // 0xFF 不是合法 UTF-8 起始字节
        try makeRaw("2026-W40", index: broken, report: Data("# 正文".utf8))

        let result = try scan()

        XCTAssertEqual(result.issues.map(\.kind), [.invalidEncoding(file: "index.json")])
    }

    func testIndexWithBOMIsReported() throws {
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        let withBOM = Data(bom) + Data(validIndexJSON(id: "2026-W40").utf8)
        try makeRaw("2026-W40", index: withBOM, report: Data("# 正文".utf8))

        let result = try scan()

        XCTAssertEqual(result.issues.map(\.kind), [.invalidEncoding(file: "index.json")],
                       "不变量 6：UTF-8 **无 BOM** —— 带 BOM 判不合规")
    }

    func testReportWithBOMIsReported() throws {
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        let withBOM = Data(bom) + Data("# 正文".utf8)
        try makeRaw("2026-W40", index: Data(validIndexJSON(id: "2026-W40").utf8), report: withBOM)

        let result = try scan()

        XCTAssertEqual(result.issues.map(\.kind), [.invalidEncoding(file: "report.md")])
    }

    func testNonPeriodDirectoryNameIsReported() throws {
        try makePackage("周报备份") // 内容齐全，但目录名不是期号形状

        let result = try scan()

        XCTAssertEqual(result.packages.count, 0)
        XCTAssertEqual(result.issues.map(\.kind), [.invalidPeriodName])
    }

    func testMissingMetadataFieldIsReported() throws {
        let incomplete = "{ \"id\": \"2026-W40\", \"published\": \"2026-10-06\", \"summary\": \"x\", \"media_count\": 1 }"
        try makePackage("2026-W40", indexJSON: incomplete)

        let result = try scan()

        XCTAssertEqual(result.issues.map(\.kind), [.missingMetadataField(field: "title")])
    }

    func testWrongTypeMediaCountIsReported() throws {
        let wrongType = "{ \"id\": \"2026-W40\", \"title\": \"t\", \"published\": \"2026-10-06\", \"summary\": \"s\", \"media_count\": \"三\" }"
        try makePackage("2026-W40", indexJSON: wrongType)

        let result = try scan()

        XCTAssertEqual(result.packages.count, 0)
        guard case .invalidJSON = result.issues.first?.kind else {
            return XCTFail("类型不符应是 invalidJSON，实为 \(String(describing: result.issues.first?.kind))")
        }
    }

    // MARK: - 整轮不崩（一个扫描根里好坏混杂）

    func testScanReportsEveryBadDirectoryWithoutCrashing() throws {
        try makePackage("2026-W20")                                   // 好
        try makeDirectory("2026-W21")                                 // 空目录
        let w22 = try makeDirectory("2026-W22")                       // 缺 index.json
        try write("# 正文", to: w22.appendingPathComponent("report.md"))
        try makePackage("2026-W23", indexJSON: "{ 坏 JSON ")          // 坏 JSON
        try makePackage("乱名")                                        // 目录名非期号

        let result = try scan()

        XCTAssertEqual(result.packages.map(\.directoryName), ["2026-W20"])
        XCTAssertEqual(result.issues.map(\.directoryName), ["2026-W21", "2026-W22", "2026-W23", "乱名"],
                       "坏目录逐条报告、按目录名排序")
        XCTAssertEqual(result.issues.count, 4)
        XCTAssertEqual(result.issues[0].kind, .emptyDirectory)
        XCTAssertEqual(result.issues[1].kind, .missingIndexJSON)
        guard case .invalidJSON = result.issues[2].kind else {
            return XCTFail("第 3 条应是 invalidJSON，实为 \(result.issues[2].kind)")
        }
        XCTAssertEqual(result.issues[3].kind, .invalidPeriodName)
    }

    func testScanThrowsWhenRootMissing() {
        let missing = root.appendingPathComponent("不存在的目录", isDirectory: true)
        XCTAssertThrowsError(try ReportPackageScanner.scan(rootDirectory: missing)) { error in
            XCTAssertEqual(error as? ReportPackageError, .rootMissing(missing.path))
        }
    }

    func testIssueDescriptionIsHumanReadable() {
        let issue = ReportPackageIssue(directoryName: "2026-W40", kind: .missingReportMD)
        XCTAssertEqual(issue.description, "2026-W40：缺 report.md")
    }
}
