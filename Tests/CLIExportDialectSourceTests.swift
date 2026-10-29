import XCTest
@testable import DoyahCore

/// `FR-STD-DB-IO-002` 的 **CLI 接线判据**（源树）：导出那条路的方言必须**随连接**取，
/// 走不了流式时必须在动手之前拦下、并且说人话。
///
/// 为什么要有它：Core 的裁定（`TableExport.decision`）全绿也不代表命令行真的问了它 ——
/// 这正是本仓反复出现的那一档（机制有、接线没有）。第七十二批之前的实况是两处：
/// ① 默认路径把方言**钉成** `PostgresDialect()`（与「连的是哪种库」是两句互不相干的说法）；
/// ② `doyah mysql --export …` 里那个 `--export`**被静默忽略**（退出码 0、没有文件）。
/// 两个都不会让任何 Core 判据变红，只有在源树这一层钉得住。
///
/// 这些判据只读源码、不连库：连库那一半在 `.agent/evidence/2026-10-29-CLI-export-dialect.md`
/// 里用真二进制跑过一遍（`mysql --export` ⇒ rc=69 且没有文件）。
final class CLIExportDialectSourceTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
        return Self.stripComments(text)
    }

    /// 只剥 `//` 行注释 —— 这几处的注释里满是 `--export` / `PostgresDialect()` / 「服务端游标」
    /// 这类词，不剥就会把注释当成接线（同族判据既有做法）。
    private static func stripComments(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let range = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<range.lowerBound])
            }
            .joined(separator: "\n")
    }

    /// 取一段：从 `start` 标记开始、到 `end` 标记出现为止。
    ///
    /// 找不到标记就**抛错**（测试失败），不是静默跳过 —— 「空跑的判据」是这个仓的老病：
    /// 源码一改名，正则一条都不命中，判据照样绿。
    private struct MissingMarker: Error, CustomStringConvertible {
        let marker: String
        var description: String { "源码里找不到标记「\(marker)」—— 这条判据要跟着源码改，别让它空转" }
    }

    private func slice(_ text: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = text.range(of: start) else { throw MissingMarker(marker: start) }
        guard let endRange = text.range(of: end, range: startRange.upperBound..<text.endIndex) else {
            throw MissingMarker(marker: end)
        }
        return text[startRange.upperBound..<endRange.lowerBound]
    }

    private func cli() throws -> String {
        let text = try source("CLI/main.swift")
        XCTAssertGreaterThan(text.count, 50_000, "读到的 CLI 源码太小 —— 多半是路径或空跑问题")
        return text
    }

    // MARK: - 方言随连接

    /// 出口必须把**连接的类型**交给导出命令，不许在调用点钉一个方言字面量。
    func testExportEntryPassesTheConnectionType() throws {
        let text = try cli()
        let entry = try slice(
            text,
            from: "if arguments.contains(\"--export\") || arguments.first == \"export\" {",
            to: "await service.disconnect()"
        )
        XCTAssertTrue(entry.contains("dbType: config.dbType"),
                      "导出命令必须拿到连接的类型（`dbType: config.dbType`）")
        XCTAssertFalse(entry.contains("PostgresDialect"),
                       "出口不许再钉方言字面量 —— 那正是第七十二批修掉的那一处")
    }

    /// 命令内部按类型取方言（`SQLDialectFactory`），不是自己再写一个 `switch`。
    func testExportCommandDerivesTheDialectFromTheType() throws {
        let text = try cli()
        let body = try slice(
            text,
            from: "private static func runExportCommand(",
            to: "func value(for flag: String)"
        )
        XCTAssertTrue(body.contains("SQLDialectFactory.make(for: dbType)"),
                      "方言必须由连接类型派生（`SQLDialectFactory.make(for: dbType)`）")
        XCTAssertFalse(body.contains("PostgresDialect"),
                       "命令内部不许出现 PG 方言字面量")
    }

    /// 三个取数函数的方言入参都是协议类型 —— 钉具体类型等于让非 PG 连接编不过、也就永远接不上。
    func testTheThreeExportFunctionsTakeAnyDialect() throws {
        let text = try cli()
        for marker in ["static func tableSelect(",
                       "static func exportAllTables(",
                       "static func exportQueryToFile("] {
            guard let range = text.range(of: marker) else {
                return XCTFail("找不到「\(marker)」—— 这条判据要跟着源码改")
            }
            let head = text[range.upperBound...].prefix(400)
            XCTAssertTrue(head.contains("dialect: any SQLDialect"),
                          "\(marker) 的方言入参必须是 `any SQLDialect`")
            XCTAssertFalse(head.contains("dialect: PostgresDialect"),
                           "\(marker) 仍钉着具体方言")
        }
    }

    // MARK: - 拦在动手之前

    /// 裁定必须发生在**任何一条语句、任何一个目录**之前：否则 `--all-tables` 会先建目录、
    /// 再逐表拼 PG 语句，用户拿到一个装满失败信息的半截目录。
    func testTheGateRunsBeforeAnyWork() throws {
        let text = try cli()
        let body = try slice(
            text,
            from: "private static func runExportCommand(",
            to: "static func exportDialectMessage("
        )
        guard let gate = body.range(of: "TableExport.decision(for: dbType)") else {
            return XCTFail("导出命令没有问 Core 的裁定（`TableExport.decision(for: dbType)`）")
        }
        for later in ["\"--all-tables\"", "exportAllTables(", "exportQueryToFile("] {
            guard let index = body.range(of: later) else {
                return XCTFail("找不到「\(later)」—— 这条判据要跟着源码改")
            }
            XCTAssertLessThan(gate.lowerBound, index.lowerBound,
                              "裁定必须在「\(later)」之前（之后就是先动手再说话）")
        }
        XCTAssertTrue(body.contains("return 69"),
                      "判红必须以 69 退出（有别于用法错 64 / 执行失败 67）")
    }

    /// MySQL 子命令那条路：`--export` 必须在**建连接之前**被拒绝。
    ///
    /// 第七十二批实测的旧行为是「静默忽略 + 退出码 0」—— 一次看起来成功的空操作，
    /// 用户会以为文件已经导出好了。
    func testMySQLSubcommandRefusesExportBeforeConnecting() throws {
        let text = try cli()
        let body = try slice(
            text,
            from: "private static func runMySQLCommand(",
            to: "private static func runTunnelCommand("
        )
        guard let refusal = body.range(of: "arguments.contains(\"--export\")") else {
            return XCTFail("`mysql` 子命令没有拒绝 `--export`（旧行为是静默忽略）")
        }
        guard let connect = body.range(of: "service.connect()") else {
            return XCTFail("找不到 `service.connect()` —— 这条判据要跟着源码改")
        }
        XCTAssertLessThan(refusal.lowerBound, connect.lowerBound,
                          "拒绝必须发生在建连接之前（连了库再拒绝等于白连一次）")
        let head = body[refusal.lowerBound...].prefix(400)
        XCTAssertTrue(head.contains("return 69"), "拒绝要以 69 退出，不许悄悄返回 0")
    }

    // MARK: - 只有一句话

    /// 两处拒绝必须共用**同一句话**（一处定义 + 两处调用）：各写一句迟早一处说「暂不支持」
    /// 另一处说「连接失败」，而用户拿这两句去搜会得出两个互斥的原因。
    func testBothRefusalsSpeakThroughOneSentence() throws {
        let text = try cli()
        let occurrences = text.components(separatedBy: "exportDialectMessage(").count - 1
        XCTAssertEqual(occurrences, 3,
                       "应当是「一处定义 + 两处叫用」= 3 次；实际 \(occurrences) 次")
        XCTAssertEqual(text.components(separatedBy: "static func exportDialectMessage(").count - 1, 1,
                       "同一句话只许定义一次")
    }

    /// 那句话得写清「一条语句都没发出去」并给替代路径 —— 只回「不支持」等于把排查留给用户。
    func testTheRefusalSaysNothingWasSentAndOffersAWayOut() throws {
        let text = try cli()
        let message = try slice(
            text,
            from: "static func exportDialectMessage(",
            to: "static func exportFormatNameMessage("
        )
        XCTAssertTrue(message.contains("服务端游标"), "要说出缺的是什么")
        XCTAssertTrue(message.contains("一条语句都没有发出去"), "要说明目标库没有被动过")
        XCTAssertTrue(message.contains("--json"), "要给一条今天能走的替代路径")
        XCTAssertTrue(message.contains("displayName"), "拒绝理由要带上认出来的连接类型")
    }
}
