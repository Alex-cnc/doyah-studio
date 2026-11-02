import XCTest

@testable import DoyahCore

/// `FR-STD-WS-NAV-014` 判据 ③（**只用内置实现**：不探外部工具、不起子进程）与
/// 判据 ④（**断网下也能格式化**：本地完成）的机器面。
///
/// 为什么判「源树里没有那条路」而不是「跑一次看结果」：这两条判的都是**没有发生的事**
/// （没有联网、没有起进程）。跑一次成功只能证明这一次没走那条路，证明不了代码里没有它 ——
/// 而「哪天有人把外部工具那档接回来」恰恰不会让任何一次成功运行变红。
///
/// 所以判三件，三件都不依赖「本机恰好没装 prettier」这种偶然：
///   ① `App/**` 里**一个**外部档的符号都不许出现（定位器 / 进程执行器 / 外部选路 / 带 runner 的执行口）；
///   ② 格式化这条链上的文件里不含任何联网 API 与起进程 API；
///   ③ `planBuiltinOnly` 与 `runBuiltin` 的**函数体**里不许出现外部档的任何名字
///      （文件里留着给单测用的外部实现不算违规，从内置那条路够不着它才算数）。
///
/// 边界（如实，写进台账「未验证」）：判的是**代码里没有入口**；真拔网线 / 真抓包没有做。
final class CodeFormatOfflineTests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // 仓根
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// 联网与起进程这两类 API：格式化这条路上一处都不许有。
    private static let networkSigns = [
        "URLSession", "URLRequest", "import Network", "NWConnection",
        "CFNetwork", "CFSocket", "getaddrinfo", "socket(", "Socket",
    ]

    private static let processSigns = [
        "Process(", "posix_spawn", "fork(", "execv", "system(", "/usr/bin/env",
        "isExecutableFile", "processInfo.environment",
    ]

    /// ③ 第一件：产品侧（`App/**`）够不到外部那条路。
    ///
    /// 判据不是「Core 里没有外部实现」（那份实现在、也允许在 —— 它的选路与执行各有单测），
    /// 而是「界面这一侧叫不起来它」：叫得起来的入口只有四个名字，出现一处就是判红。
    func testTheAppSideCanNeverReachTheExternalRoute() throws {
        let appRoot = root.appendingPathComponent("App")
        let files = try FileManager.default.subpathsOfDirectory(atPath: appRoot.path)
            .filter { $0.hasSuffix(".swift") }
        XCTAssertGreaterThan(files.count, 50, "App 源文件只有 \(files.count) 份 —— 扫描面不对")

        let forbidden = [
            "CodeFormatToolLocator",            // 按 PATH 找可执行文件
            "FoundationCodeFormatProcessRunner", // 起子进程
            "CodeFormatPlanner.decide",          // 外部优先的选路
            "CodeFormatService.run(",            // 收 runner 的执行口
            "CodeFormatDecision",                // 带外部回退原因的决策
        ]
        var hits: [String] = []
        for file in files {
            let text = try String(contentsOf: appRoot.appendingPathComponent(file), encoding: .utf8)
            for token in forbidden where text.contains(token) {
                hits.append("\(file) → \(token)")
            }
        }
        XCTAssertEqual(hits, [], "产品侧出现了外部格式化那条路的入口：\(hits)")
    }

    /// ③ 第二件 + ④：格式化这条链上的每一份文件都不含联网 / 起进程 API。
    ///
    /// 链 = 菜单（`DoyahStudioCommands`）→ 模型入口（`WorkspaceTabsModel`）→ 选路与内置档
    /// （`CodeFormatting`）→ 语言能力表（`CodeLanguageDefinitions`）→ SQL 那一档（`SQLFormatter`）
    /// → 编辑器落笔（`CodeEditorView`）。任何一环联网，④「断网可用」就不成立。
    func testTheWholeFormattingChainCarriesNoNetworkOrProcessCall() throws {
        let chain = [
            "Core/CodeFormatting.swift",
            "Core/CodeLanguageDefinitions.swift",
            "Core/SQLFormatter.swift",
            "App/WorkspaceTabsModel.swift",
            "App/Views/CodeEditorView.swift",
            "App/DoyahStudioCommands.swift",
        ]
        for path in chain {
            let text = try source(path)
            XCTAssertFalse(text.isEmpty, "\(path) 读成空 —— 链断了，判据也就空了")
            for token in Self.networkSigns where text.contains(token) {
                XCTFail("\(path) 里出现了联网 API「\(token)」⇒ 断网下格式化不成立")
            }
            // `Process(` 在 `CodeFormatting.swift` 里是外部档的实现（单测在用），
            // 所以这里只判其余五份；那一份由下一条逐函数体判。
            if path != "Core/CodeFormatting.swift" {
                for token in Self.processSigns where text.contains(token) {
                    XCTFail("\(path) 里出现了起进程 / 探 PATH 的入口「\(token)」⇒ 不是「只用内置」")
                }
            }
        }
    }

    /// ③ 第三件：内置那条路的两个函数**体内**够不到外部档。
    ///
    /// 为什么按函数体判而不按整份文件判：`CodeFormatting.swift` 同时住着外部档的实现
    /// （`CodeFormatToolLocator` / `FoundationCodeFormatProcessRunner` / 收 runner 的 `run`），
    /// 按整份文件判会逼着把那些删掉或改名 —— 那是在拆单测的夹具，不是在判需求。
    /// 需求要的是「产品走的那条路上没有外部工具」，也就是这两个函数体里没有它。
    func testTheBuiltinPathNeverTouchesTheExternalRoute() throws {
        let text = try source("Core/CodeFormatting.swift")

        let planner = try XCTUnwrap(
            Self.body(after: "public static func planBuiltinOnly(definition:", in: text),
            "`planBuiltinOnly(definition:)` 不在了 —— 内置选路没了出口，判据无从成立"
        )
        let runner = try XCTUnwrap(
            Self.body(after: "public static func runBuiltin(", in: text),
            "`runBuiltin` 不在了 —— 「只用内置」的执行入口没了"
        )

        let externalNames = [
            "CodeFormatToolLocator", "FoundationCodeFormatProcessRunner",
            "CodeFormatPlanner.decide", "runner", "Process(",
        ]
        for name in externalNames {
            XCTAssertFalse(planner.contains(name), "内置选路的函数体里出现了「\(name)」")
            XCTAssertFalse(runner.contains(name), "内置执行的函数体里出现了「\(name)」")
        }
        XCTAssertTrue(planner.contains("capability.builtin.isAvailable"),
                      "内置选路不再问「这门语言有没有内置档」⇒ 没有档的语言会被静默放过")
        XCTAssertTrue(runner.contains("CodeBuiltinFormatter.format("),
                      "内置执行不再直接调内置档 ⇒ 中间可能被换成别的路")
    }

    /// 花括号配平地切出一个函数体：从 `signature` 之后第一个 `{` 到它配对的 `}`。
    ///
    /// 先看到 `{` 才开始收（签名里的参数标签不带花括号），深度回到 0 就收工。
    /// 这两个函数体里没有字符串字面量，所以不必处理「字符串里的花括号」。
    private static func body(after signature: String, in source: String) -> String? {
        guard let found = source.range(of: signature) else { return nil }
        var index = found.upperBound
        var depth = 0
        var started = false
        var body = ""
        while index < source.endIndex {
            let character = source[index]
            if character == "{" {
                depth += 1
                started = true
            }
            if started { body.append(character) }
            if character == "}" {
                depth -= 1
                if started, depth == 0 { return body }
            }
            index = source.index(after: index)
        }
        return nil
    }
}
