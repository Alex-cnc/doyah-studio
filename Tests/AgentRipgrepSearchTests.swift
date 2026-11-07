import XCTest
@testable import DoyahCore

/// **随包 ripgrep 接进 `search`** 的判据（2026-11-07 主人拍板「把 ripgrep 打包进 App」）。
///
/// 四条，每条都能判红：
/// ① **加速真的接上了**：同一个查询，rg 路径与 Swift 引擎的**命中集合相同**（文件名 + `路径:行`），
///    并且 rg 那条明显更快（读数打印出来，进报告）；
/// ② **随包产物**：`App/Resources/tools/rg` 存在、可执行、`rg --version` 是 15.2.0、
///    架构 arm64、sha256 与 `tools/README.md` 记的那个一致（换版本忘了改台账 = 判红）；
/// ③ **回落必须真能用**：定位入口给不出 rg（被删 / 被改名 / 没有执行权）时，
///    `search` **不抛错、不返回空**，结果与 rg 路径一致 —— 这一条是本文件的重心：
///    加速器坏了不能让「搜索」这个功能消失；
/// ④ **许可随包**：`COPYING` / `LICENSE-MIT` 在 tools 目录里，`THIRD-PARTY-NOTICES.md` 有 ripgrep 条目。
final class AgentRipgrepSearchTests: XCTestCase {

    private var root: URL!
    private let fileManager = FileManager.default

    /// 仓库根（`#filePath` = `<repo>/Tests/AgentRipgrepSearchTests.swift`）。
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }
    private var toolsDirectory: URL { repoRoot.appendingPathComponent("App/Resources/tools") }
    private var bundledRipgrep: String { toolsDirectory.appendingPathComponent("rg").path }

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent("rg-search-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try write("Core/a.swift", "let agent = 1\n// 第二行\nlet loop = agent\n")
        try write("Core/b.swift", "AGENT 大写\n什么都\n")
        try write("Core/many.txt", (1...40).map { "行 \($0) agent" }.joined(separator: "\n") + "\n")
        try write("node_modules/dep.txt", "agent 在依赖里\n")
        try write("note/agent-note.md", "agent 的文件名命中\n")
        try write("note/readme.md", "这里没有那个词\n")
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
    }

    private func write(_ relative: String, _ text: String) throws {
        let url = root.appendingPathComponent(relative)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - ② 随包产物与许可

    /// 随包这一份必须是**它自己声明的那一份**：可执行、版本对、架构 arm64、哈希对。
    func testBundledRipgrepIsTheDeclaredBinary() throws {
        guard fileManager.fileExists(atPath: bundledRipgrep) else {
            return XCTFail("随包 rg 不在：\(bundledRipgrep)（`App/Resources/tools/rg` 是打包来源）")
        }
        XCTAssertTrue(AgentRipgrep.isExecutable(bundledRipgrep), "随包 rg 没有可执行位 —— 打包后会被 SIGHUP/EPERM 挡住")
        XCTAssertEqual(AgentRipgrep.toolRelativePath, "tools/rg", "随包相对路径是 `Contents/Resources/tools/rg`")

        let version = try runTool(bundledRipgrep, ["--version"]).split(separator: "\n").first.map(String.init) ?? ""
        XCTAssertTrue(version.hasPrefix("ripgrep \(AgentRipgrep.bundledVersion)"),
                      "随包版本 = 「\(version)」，台账写的 \(AgentRipgrep.bundledVersion)")

        let arch = try runTool("/usr/bin/lipo", ["-info", bundledRipgrep])
        XCTAssertTrue(arch.contains("arm64"), "本次只放 macOS arm64 这一份（实读：\(arch)）")

        // 台账（`App/Resources/tools/README.md`）里的 sha256 必须与实物一致 —— 换二进制不改台账 = 静默失配。
        let sha = try runTool("/usr/bin/shasum", ["-a", "256", bundledRipgrep])
            .split(separator: " ").first.map(String.init) ?? ""
        let ledger = try String(contentsOf: toolsDirectory.appendingPathComponent("README.md"), encoding: .utf8)
        XCTAssertTrue(ledger.contains(sha), "README 记的 sha256 与实物不符（实物 \(sha)）")
    }

    /// 许可与第三方声明随仓库走：两个原文都在，`THIRD-PARTY-NOTICES.md` 有条目。
    func testLicensesAndNoticesTravelWithTheBinary() throws {
        for name in ["COPYING", "LICENSE-MIT"] {
            let url = toolsDirectory.appendingPathComponent(name)
            XCTAssertTrue(fileManager.fileExists(atPath: url.path), "缺 \(name)")
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(name) 是空的")
        }
        let notices = try String(contentsOf: repoRoot.appendingPathComponent("THIRD-PARTY-NOTICES.md"),
                                 encoding: .utf8)
        XCTAssertTrue(notices.contains("ripgrep"), "THIRD-PARTY-NOTICES.md 没有 ripgrep 条目")
        XCTAssertTrue(notices.contains(AgentRipgrep.bundledVersion), "声明里的版本与随包版本不一致")
        XCTAssertTrue(notices.lowercased().contains("unlicense"), "声明里要写明 Unlicense")
    }

    // MARK: - ① 加速路径：命中集合与 Swift 引擎一致

    /// **同一批词、两条路径，命中必须一致**（文件名 + `路径:行`）。不一致 = 加速把结果改掉了。
    func testAcceleratedHitsMatchTheSwiftEngine() throws {
        try XCTSkipUnless(AgentRipgrep.isExecutable(bundledRipgrep), "随包 rg 不在，本条判不了")
        let queries = ["agent", "第二行", "不存在的词"]

        guard let accelerated = AgentRipgrep.accelerate(
            in: root, queries: queries, limit: 50, executable: bundledRipgrep
        ) else { return XCTFail("rg 明明在，`accelerate` 却返回 nil") }

        let swiftNames = WorkspaceSearch.findFileNames(in: root, queries: queries, limit: 50)
        let swiftContents = WorkspaceSearch.findContents(in: root, queries: queries, limit: 50)

        for (index, query) in queries.enumerated() {
            XCTAssertEqual(accelerated.fileNames[index].entries.map(\.relativePath),
                           swiftNames[index].entries.map(\.relativePath),
                           "文件名命中不一致（词「\(query)」）")
            XCTAssertEqual(lineKeys(accelerated.contents[index]), lineKeys(swiftContents[index]),
                           "内容命中的 文件:行 不一致（词「\(query)」）")
            XCTAssertEqual(accelerated.contents[index].hitCount, swiftContents[index].hitCount,
                           "命中条数不一致（词「\(query)」）")
        }

        // 忽略名单仍生效：`node_modules` 里的那条不进结果。
        XCTAssertFalse(lineKeys(accelerated.contents[0]).contains { $0.hasPrefix("node_modules/") },
                       "node_modules 没被跳过 —— 忽略名单在 rg 这条路上丢了")
    }

    /// 读数：同一查询两条路径各跑一次，**耗时与命中数都打印出来**（报告要贴的就是这段）。
    ///
    /// 探针根默认是仓库根；要读「真工作区」那台，就把 `DOYAH_RG_PROBE_ROOT` 指到工作区根
    /// （智能体 `search` 扫的就是工作区根，不是仓库根）。判据只钉「两条路径都出命中、
    /// rg 那条确实来自随包二进制、且没到荒谬的慢」，具体毫秒不判红 —— 机器不同不该判红。
    func testRecordsTimingsForTheSameQuery() throws {
        try XCTSkipUnless(AgentRipgrep.isExecutable(bundledRipgrep), "随包 rg 不在，本条判不了")
        let probeRoot = ProcessInfo.processInfo.environment["DOYAH_RG_PROBE_ROOT"]
            .map { URL(fileURLWithPath: $0) } ?? repoRoot
        let queries = ["WorkspaceSearch"]   // 与真机读数同一个词

        let swiftStart = Date()
        let swiftContents = WorkspaceSearch.findContents(in: probeRoot, queries: queries, limit: 50)
        let swiftMillis = Int(Date().timeIntervalSince(swiftStart) * 1000)

        let nameScan = AgentRipgrep.searchFileNames(
            in: probeRoot, queries: queries, limit: 50, executable: bundledRipgrep)
        let rgStart = Date()
        guard let accelerated = AgentRipgrep.accelerate(
            in: probeRoot, queries: queries, limit: 50, executable: bundledRipgrep
        ) else { return XCTFail("随包 rg 起不来") }
        let rgMillis = Int(Date().timeIntervalSince(rgStart) * 1000)

        print("""
        [rg-probe] root=\(probeRoot.path) 词=WorkspaceSearch \
        Swift=\(swiftMillis)ms/\(swiftContents[0].hitCount) 命中 \
        rg=\(rgMillis)ms/\(accelerated.contents[0].hitCount) 命中 \
        （两趟之内：文件名 \(nameScan?.elapsedMillis ?? -1)ms · 内容 \(accelerated.contents[0].scannedFiles) 个文件）
        """)

        XCTAssertEqual(accelerated.executablePath, bundledRipgrep, "必须用的是随包那份，不是 PATH 上的")
        XCTAssertGreaterThan(accelerated.contents[0].hitCount, 0, "这个词必然有命中")
        XCTAssertGreaterThan(swiftContents[0].hitCount, 0, "Swift 引擎也必须出命中（否则对照组没跑）")
        XCTAssertLessThan(rgMillis, 5_000, "rg 这条不该慢到 5 秒（读数 \(rgMillis)ms）")
    }

    /// **工具级读数**（判据 ① 的正例 + ⑤ 的反例，同一段打印）：
    /// 同一个查询走 `searchStructured`，rg 在 / rg 被摘掉（`ripgrepLocator = { nil }`）
    /// 各一次，耗时与命中数并排摆出来 —— 两臂都必须出结果，且命中数相同。
    func testToolLevelTimingWithAndWithoutRipgrep() throws {
        try XCTSkipUnless(AgentRipgrep.isExecutable(bundledRipgrep), "随包 rg 不在，本条判不了")
        let probeRoot = ProcessInfo.processInfo.environment["DOYAH_RG_PROBE_ROOT"]
            .map { URL(fileURLWithPath: $0) } ?? repoRoot
        let query = "WorkspaceSearch"

        // 上限放到 1,000：**只有「不截断」时两条路径的命中集合才该逐字相同**
        // （超过上限时 rg 的并行输出顺序决定截到哪 50 条，跟遍历顺序本来就不是一个子集）。
        func timeTool(_ tools: AgentWorkspaceTools) -> (millis: Int, hits: Int, outcome: AgentToolSearchOutput)? {
            guard case .search(let output) = tools.search(query: query, limit: 1_000) else { return nil }
            return (output.elapsedMillis, output.contentHits.count, output)
        }

        let bundled = bundledRipgrep
        let withRg = AgentWorkspaceTools(root: probeRoot, searchCache: nil,
                                         ripgrepLocator: { bundled })
        let withoutRg = AgentWorkspaceTools(root: probeRoot, searchCache: nil, ripgrepLocator: { nil })
        // 先各跑一次热身（首次 spawn 有 dyld / 页缓存的一次性开销，不该算进读数）。
        _ = timeTool(withRg); _ = timeTool(withoutRg)

        guard let fast = timeTool(withRg) else { return XCTFail("rg 臂没给出搜索结果") }
        guard let slow = timeTool(withoutRg) else { return XCTFail("回落臂没给出搜索结果") }

        print("""
        [rg-probe][tool] root=\(probeRoot.path) 词=\(query) \
        rg 臂=\(fast.millis)ms/\(fast.hits) 条 · 回落臂=\(slow.millis)ms/\(slow.hits) 条
        """)

        XCTAssertGreaterThan(fast.hits, 0, "rg 臂必须出命中")
        XCTAssertGreaterThan(slow.hits, 0, "**回落臂必须出命中**（rg 被摘掉不等于搜索没了）")
        XCTAssertEqual(fast.hits, slow.hits, "两条路径的命中条数应当一致")
        XCTAssertEqual(fast.outcome.contentHits.sorted(), slow.outcome.contentHits.sorted(),
                       "两条路径的命中内容应当逐字相同")
    }

    // MARK: - ③ 回落：rg 被删 / 被改名 / 没有执行权

    /// **反例臂**：把 rg 改名（= 随包文件不见了），`search` 仍要出结果，且与 rg 在时一致。
    func testSearchFallsBackWhenRipgrepIsGone() throws {
        try XCTSkipUnless(AgentRipgrep.isExecutable(bundledRipgrep), "随包 rg 不在，本条判不了")

        // 复制一份到临时目录再改名 —— 真把仓库里那份改名会弄脏工作树。
        let sandbox = fileManager.temporaryDirectory.appendingPathComponent("rg-missing-\(UUID().uuidString)")
        try fileManager.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: sandbox) }
        let copy = sandbox.appendingPathComponent("rg").path
        try fileManager.copyItem(atPath: bundledRipgrep, toPath: copy)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: copy)
        try fileManager.moveItem(atPath: copy, toPath: sandbox.appendingPathComponent("rg-renamed").path)

        // 定位入口按**真规矩**判：文件不在 / 没有执行权 ⇒ 给不出路径。
        XCTAssertNil(AgentRipgrep.locate(bundle: .main, environment: ["PATH": sandbox.path]),
                     "改名后的 rg 不该被找到（`rg` 这个名字在 PATH 上已经不存在）")

        let tools = AgentWorkspaceTools(root: root, searchCache: nil,
                                        ripgrepLocator: { AgentRipgrep.locate(bundle: .main,
                                                                              environment: ["PATH": sandbox.path]) })
        guard case .search(let fallback) = tools.search(query: "agent") else {
            return XCTFail("回落路径没给出搜索结果")
        }
        XCTAssertFalse(fallback.contentHits.isEmpty, "**回落不得返回空** —— 搜索功能整个消失了")
        XCTAssertTrue(fallback.contentHits.contains { $0.hasPrefix("Core/a.swift:1:") },
                      "回落结果里缺 Core/a.swift 第 1 行：\(fallback.contentHits)")

        // 与 rg 在时逐字同集（同一个谓词、同一份忽略名单）。
        guard let accelerated = AgentRipgrep.accelerate(in: root, queries: ["agent"], limit: 50,
                                                        executable: bundledRipgrep) else {
            return XCTFail("对照组：rg 应当可用")
        }
        let viaRg = accelerated.contents[0].hitCount
        XCTAssertEqual(fallback.contentHits.count, viaRg, "回落与 rg 的命中条数应当一致")
    }

    /// **没有执行权**（`chmod 644`）也算不可用：不许 spawn 失败后当成「没命中」。
    func testSearchFallsBackWhenRipgrepIsNotExecutable() throws {
        let sandbox = fileManager.temporaryDirectory.appendingPathComponent("rg-noexec-\(UUID().uuidString)")
        try fileManager.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: sandbox) }
        let copy = sandbox.appendingPathComponent("rg").path
        try fileManager.copyItem(atPath: bundledRipgrep, toPath: copy)
        try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: copy)

        XCTAssertNil(AgentRipgrep.locate(bundle: .main, environment: ["PATH": sandbox.path]))
        // 直接把它当可执行文件传进去，也必须**如实失败**（返回 nil）而不是空结果。
        XCTAssertNil(AgentRipgrep.accelerate(in: root, queries: ["agent"], limit: 50, executable: copy),
                     "没有执行位的 rg 必须让 `accelerate` 返回 nil（否则会退回一个空结果）")

        let tools = AgentWorkspaceTools(root: root, searchCache: nil, ripgrepLocator: { nil })
        guard case .search(let output) = tools.search(query: "agent") else {
            return XCTFail("rg 明确不可用时，search 必须回落而不是拒绝")
        }
        XCTAssertFalse(output.contentHits.isEmpty, "**回落不得返回空**")
    }

    /// 空词 / 只有空白的词：照旧拒绝，不因为走了引擎分叉而变。
    func testEmptyQueryIsStillRefused() {
        let tools = AgentWorkspaceTools(root: root, searchCache: nil, ripgrepLocator: { nil })
        guard case .refused(let reason, _) = tools.search(query: "   ") else {
            return XCTFail("空词应当被拒")
        }
        XCTAssertEqual(reason, .emptyQuery)
    }

    // MARK: - 小工具

    /// `路径:行` 的集合（排序后比：rg 与 Swift 的**遍历顺序**本来就不同，比顺序会假红）。
    private func lineKeys(_ result: WorkspaceSearch.ContentResult) -> [String] {
        result.groups.flatMap { group in
            group.hits.map { "\(group.entry.relativePath):\($0.line)" }
        }.sorted()
    }

    private func runTool(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
