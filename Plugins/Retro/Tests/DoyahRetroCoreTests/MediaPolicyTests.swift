import XCTest
@testable import DoyahRetroCore

// 多媒体策略（白名单 / 占位 / 越界与缺失报告 / 外链标记）的机械证据
// （Retro macOS · M0 第 3 片 · 派单卡 `t_b92f9c11`）。
//
// 判据口径（`FR-R-13-09` ①②③④ 与 `IR-05` 不变量 3 / 5 同源）：
//   ① **白名单内联**：图片 `png`/`jpg`/`jpeg`/`webp`/`gif` ⇒ 图片内联；视频 `mp4` ⇒ 本地内联可播候选；
//   ② **白名单外占位 + 一条报告**：`avi` / `mov`（含无扩展名 / 其它扩展名）⇒ 原位占位，**不报错、不崩**；
//   ③ **缺失 / 越界 / 非相对**：文件缺失 ⇒ 占位 + 报告；含 `../` ⇒ 拒绝 + 报告；绝对路径 / base64 ⇒ 拒绝 + 报告；
//   ④ **外链标记**：`http(s)://` ⇒ 标记「交系统默认处理」、**不产生报告**（合法形态）。
// 三条纪律：跑**真目录真文件**（临时目录）；负例逐条点名；**不静默丢弃**（每条占位都必须对上一条报告）。
final class MediaPolicyTests: XCTestCase {

    private var packageDirectory: URL!

    override func setUpWithError() throws {
        packageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-retro-media-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let packageDirectory { try? FileManager.default.removeItem(at: packageDirectory) }
    }

    // MARK: - 夹具

    /// 在包目录里落一个文件（逐级建目录），返回**包内绝对路径**（构造口径与解析层一致）。
    @discardableResult
    private func writeFile(_ relativePath: String, bytes: Data = Data([0x00, 0x01, 0x02])) throws -> URL {
        let url = inPackageURL(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url)
        return url
    }

    private func resolve(_ reference: String, line: Int? = nil) -> MediaResolveOutcome {
        MediaResolve.resolve(reference: reference, packageDirectory: packageDirectory, line: line)
    }

    /// 期望的「包内绝对路径」：与解析层同一种构造（`relativeTo:` + 标准化）。
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

    // MARK: - ① 白名单内联

    /// 图片五条扩展名逐条：落盘即内联，解析成**包内绝对路径**。
    func testWhitelistedImageExtensionsResolveToInlineImage() throws {
        for fileExtension in ["png", "jpg", "jpeg", "webp", "gif"] {
            let reference = "assets/trend.\(fileExtension)"
            let expected = try writeFile(reference)

            let outcome = resolve(reference)

            XCTAssertNil(outcome.issue, "\(fileExtension)：合法内联不该有报告")
            guard case .inlineImage(let ref, let url) = outcome.resolution else {
                return XCTFail("\(fileExtension)：应是图片内联，实为 \(outcome.resolution)")
            }
            XCTAssertEqual(ref, reference)
            XCTAssertEqual(url, expected.standardizedFileURL, "\(fileExtension)：须解析成包内绝对路径")
            XCTAssertTrue(url.path.hasPrefix(packageDirectory.standardizedFileURL.path + "/"),
                          "\(fileExtension)：解析结果须落在包目录内：\(url.path)")
        }
    }

    /// 视频白名单：`mp4` ⇒ **本地内联可播候选**（本层不接播放器，只给去向）。
    func testMp4ResolvesToInlineVideo() throws {
        let expected = try writeFile("assets/clip.mp4")

        let outcome = resolve("assets/clip.mp4")

        XCTAssertNil(outcome.issue)
        guard case .inlineVideo(let reference, let url) = outcome.resolution else {
            return XCTFail("mp4 应是本地内联可播候选，实为 \(outcome.resolution)")
        }
        XCTAssertEqual(reference, "assets/clip.mp4")
        XCTAssertEqual(url, expected.standardizedFileURL)
        XCTAssertTrue(outcome.resolution.isInline)
    }

    /// 白名单集合与契约 `IR-05` 不变量 5 **逐名**一致（防白名单被悄悄改宽 / 改窄）。
    func testWhitelistMatchesContractExactly() {
        XCTAssertEqual(MediaWhitelist.imageExtensions, ["png", "jpg", "jpeg", "webp", "gif"])
        XCTAssertEqual(MediaWhitelist.videoExtensions, ["mp4"])
        XCTAssertEqual(MediaWhitelist.allExtensions, ["png", "jpg", "jpeg", "webp", "gif", "mp4"])
        XCTAssertEqual(MediaWhitelist.kind(forFileExtension: "png"), .image)
        XCTAssertEqual(MediaWhitelist.kind(forFileExtension: "mp4"), .video)
        XCTAssertNil(MediaWhitelist.kind(forFileExtension: "avi"))
    }

    /// 扩展名大小写不敏感：`TREND.PNG` 与 `trend.png` 同判（盘上大小写混写常见）。
    func testUppercaseExtensionIsStillWhitelisted() throws {
        try writeFile("assets/TREND.PNG")

        let outcome = resolve("assets/TREND.PNG")

        XCTAssertNil(outcome.issue)
        guard case .inlineImage = outcome.resolution else {
            return XCTFail("大写扩展名应同判白名单，实为 \(outcome.resolution)")
        }
    }

    // MARK: - ② 白名单外占位 + 一条报告

    /// `avi` / `mov` ⇒ 原位占位 + **恰好一条**报告（不报错、不崩）。
    ///
    /// 两个文件都**真落盘**：证明**格式门在存盘门之前** —— 盘上就算有同名合法文件，
    /// 白名单外也照样占位（不会因为「文件在」就放行）。
    func testNonWhitelistedVideoFormatsArePlaceholderAndReported() throws {
        for fileExtension in ["avi", "mov"] {
            let reference = "assets/clip.\(fileExtension)"
            try writeFile(reference)

            let outcome = resolve(reference, line: 7)

            XCTAssertEqual(outcome.resolution.isPlaceholder, true, "\(fileExtension)：白名单外须占位")
            XCTAssertEqual(outcome.resolution,
                           .placeholder(reason: .formatNotWhitelisted(fileExtension: fileExtension),
                                        reference: reference),
                           "\(fileExtension)：占位原因须点名格式")
            XCTAssertEqual(outcome.issue,
                           MediaIssue(line: 7, kind: .formatNotWhitelisted(reference: reference,
                                                                           fileExtension: fileExtension)),
                           "\(fileExtension)：须恰好一条报告（带行号）")
        }
    }

    /// 无扩展名 / 其它扩展名的相对路径 ⇒ 白名单外占位（`fileExtension` 为 `nil` 时报告写「无扩展名」）。
    func testUnknownOrMissingExtensionIsNotWhitelisted() {
        let noExtension = resolve("assets/notes")
        XCTAssertEqual(noExtension.resolution, .placeholder(reason: .formatNotWhitelisted(fileExtension: nil),
                                                            reference: "assets/notes"))
        XCTAssertEqual(noExtension.issue,
                       MediaIssue(line: nil, kind: .formatNotWhitelisted(reference: "assets/notes",
                                                                         fileExtension: nil)))

        let otherExtension = resolve("assets/data.txt")
        XCTAssertEqual(otherExtension.resolution, .placeholder(reason: .formatNotWhitelisted(fileExtension: "txt"),
                                                              reference: "assets/data.txt"))
        XCTAssertEqual(otherExtension.issue?.kind, .formatNotWhitelisted(reference: "assets/data.txt",
                                                                         fileExtension: "txt"))
    }

    // MARK: - ③ 缺失 / 越界 / 非相对

    /// 白名单内但文件缺失 ⇒ 占位 + 一条报告（不静默丢弃）。
    func testMissingMediaFileYieldsPlaceholderAndOneIssue() {
        let outcome = resolve("assets/missing.png", line: 3)

        XCTAssertEqual(outcome.resolution, .placeholder(reason: .fileMissing, reference: "assets/missing.png"))
        XCTAssertEqual(outcome.issue,
                       MediaIssue(line: 3, kind: .fileMissing(reference: "assets/missing.png")))
    }

    /// 含 `../` 的越界路径 ⇒ 拒绝 + 报告；`../` 即使「绕回包内」也一律拒绝。
    func testParentTraversalIsRejectedAndReported() throws {
        let escape = resolve("../outside.png", line: 1)
        XCTAssertEqual(escape.resolution, .placeholder(reason: .pathOutOfPackage, reference: "../outside.png"))
        XCTAssertEqual(escape.issue, MediaIssue(line: 1, kind: .pathOutOfPackage(reference: "../outside.png")))

        try writeFile("assets/x.png")        // 盘上真有 assets/x.png —— 但 `..` 已先判越界
        let detour = resolve("assets/../assets/x.png")
        XCTAssertEqual(detour.resolution, .placeholder(reason: .pathOutOfPackage,
                                                       reference: "assets/../assets/x.png"),
                       "`../` 即使绕回包内也拒绝（判据原文：含 `../` 的越界路径）")
        XCTAssertEqual(detour.issue?.kind, .pathOutOfPackage(reference: "assets/../assets/x.png"))
    }

    /// 非相对形态：绝对路径 / `data:` base64 ⇒ 拒绝 + 报告（本层无这两条取图分支）。
    func testAbsolutePathAndBase64AreRejectedAndReported() {
        let absolute = resolve("/etc/hosts", line: 2)
        XCTAssertEqual(absolute.resolution, .placeholder(reason: .referenceNotRelative, reference: "/etc/hosts"))
        XCTAssertEqual(absolute.issue, MediaIssue(line: 2, kind: .referenceNotRelative(reference: "/etc/hosts")))

        let base64 = resolve("data:image/png;base64,iVBORw0KGgo=")
        XCTAssertEqual(base64.resolution, .placeholder(reason: .referenceNotRelative,
                                                       reference: "data:image/png;base64,iVBORw0KGgo="))
        XCTAssertEqual(base64.issue?.kind, .referenceNotRelative(reference: "data:image/png;base64,iVBORw0KGgo="))
    }

    // MARK: - ④ 外链标记

    /// `http(s)://` ⇒ 标记「交系统默认处理」，**不产生报告**；盘上无文件也照常标记（不碰盘）。
    func testHttpAndHttpsExternalLinksAreMarkedForSystemHandling() {
        for reference in ["https://example.com/a/b.mp4", "http://example.com/pic.png"] {
            let outcome = resolve(reference)

            XCTAssertNil(outcome.issue, "外链是合法形态，不该产生报告")
            guard case .externalLink(let url) = outcome.resolution else {
                return XCTFail("\(reference)：应是外链标记，实为 \(outcome.resolution)")
            }
            XCTAssertEqual(url.absoluteString, reference)
            XCTAssertFalse(outcome.resolution.isInline)
            XCTAssertFalse(outcome.resolution.isPlaceholder)
            XCTAssertTrue(outcome.resolution.description.contains("交系统默认处理"))
        }
    }

    // MARK: - 纯函数与逐条不崩

    /// **同一条引用连续两次解析 ⇒ 产物逐字节相同**（同一口径：不读时钟 / 环境 / 随机）。
    func testResolveIsPureFunction() throws {
        try writeFile("assets/cover.png")
        let references = [
            "assets/cover.png",
            "assets/clip.mp4",
            "assets/missing.png",
            "../escape.png",
            "data:image/png;base64,AAAA",
            "https://example.com/a/b.mp4"
        ]

        var firstDump: [String] = []
        var secondDump: [String] = []
        for reference in references {
            let first = resolve(reference, line: 5)
            let second = resolve(reference, line: 5)
            XCTAssertEqual(first, second, "\(reference)：两次解析的产物必须相等")
            firstDump.append(first.resolution.description + " | " + (first.issue?.description ?? "-"))
            secondDump.append(second.resolution.description + " | " + (second.issue?.description ?? "-"))
        }

        let firstBytes = Data(firstDump.joined(separator: "\n").utf8)
        let secondBytes = Data(secondDump.joined(separator: "\n").utf8)
        XCTAssertEqual(firstBytes, secondBytes, "两次解析的产物必须**逐字节相同**")
        print("[媒体纯函数判据] 产物字节数=\(firstBytes.count) FNV-1a=\(fnv1a64(firstBytes)) 例数=\(references.count)")
    }

    /// 好坏混排：坏引用**不影响**别的引用 —— 好图照样内联、坏引用逐条占位（逐条报告且不崩）。
    func testMixedReferencesReportEachBadOneWithoutStopping() throws {
        let goodImage = try writeFile("assets/good.png")
        let goodVideo = try writeFile("assets/good.mp4")

        let image = resolve("assets/good.png")
        let video = resolve("assets/good.mp4")
        let bad = resolve("assets/bad.avi")
        let missing = resolve("assets/none.png")

        XCTAssertEqual(image.resolution, .inlineImage(reference: "assets/good.png",
                                                      url: goodImage.standardizedFileURL))
        XCTAssertEqual(video.resolution, .inlineVideo(reference: "assets/good.mp4",
                                                      url: goodVideo.standardizedFileURL))
        XCTAssertEqual(bad.issue?.kind, .formatNotWhitelisted(reference: "assets/bad.avi", fileExtension: "avi"))
        XCTAssertEqual(missing.issue?.kind, .fileMissing(reference: "assets/none.png"))
        XCTAssertNil(image.issue)
        XCTAssertNil(video.issue)
    }
}
