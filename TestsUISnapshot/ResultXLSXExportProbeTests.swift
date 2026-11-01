import AppKit
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 「结果集导出 Excel（.xlsx）」的 **App 侧探针**（`FR-STD-DB-RES-014`）—— v0.3.0 数据库运维面 B2 批次。
///
/// ## 这一行为什么原来停在 🟡
/// 台账备注原文是「Excel / Numbers 打开需人工（外部软件）」。可「打开」只是最后一步 ——
/// 前面那些**能机器判**的部分此前一条判据都没有：工作簿可以是坏的 ZIP、可以只写文本不写数值
/// （`42` 变字符串，用户算不了和）、`007` 可以被「聪明地」转成数字（前导零悄悄没了）、
/// 同一份输入两次导出可以不一样（没法 diff、没法校验）。
///
/// ## 这一片怎么量（判据不拿产品自己的代码当依据）
/// 导出走**生产那一条路**（`ResultExporter.data(for:format:.xlsx)`，与 `AppState.exportResult`
/// 同一处渲染），然后把产物交给**外部工具**核对：
///   · `/usr/bin/unzip`（Info-ZIP，系统自带）—— 证明它是个标准 ZIP、每个条目 CRC 都对；
///   · Foundation 的 `XMLDocument`（标准库解析器，不是本仓的 `XLSXReader`）—— 读工作表 XML 判
///     「这一格是数值还是文本、文本是什么」。
/// 用自家 `XLSXReader` 读自己的 `XLSXWriter` 是循环论证（写错一处、读也照着错，两边照样一致），
/// 所以这里刻意不用它。
///
/// ## 边界（如实登记）
/// · 证得住：产物是标准 ZIP（`unzip -t` 全条目 CRC 通过）、六个部件齐全、表头与行列数对得上、
///   数值列写成数值单元格（无 `t` 属性 + `<v>`）、文本列写成文本（`t="inlineStr"`）、
///   空值不写格、前导零不被吞、中文与 `<` / `&` / 引号原样保留、同一输入两次导出逐字节相同、
///   仓里没有第三方 xlsx 依赖；
/// · **证不住**：Excel / Numbers / WPS 真的打开它长什么样（外部软件行为，只能人看）；
///   单元格样式 / 列宽 / 冻结表头这些「好看」的部分本实现不做（需求没要求，也不在这条判据里）；
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）。
final class ResultXLSXExportProbeTests: XCTestCase {

    // MARK: - 合成结果

    /// 刻意带上判据要用的东西：中文、`<` / `&` / 引号、空值、负数、0、前导零。
    private let columns = [
        ColumnMeta(id: 0, name: "id", typeName: "integer"),
        ColumnMeta(id: 1, name: "name", typeName: "text"),
        ColumnMeta(id: 2, name: "amount", typeName: "numeric(10,2)"),
        ColumnMeta(id: 3, name: "note", typeName: "text"),
    ]

    private let rows: [[String?]] = [
        ["1", "订单一", "12.50", "含 <标签> & 引号\""],
        ["2", "订单二", "-3.25", nil],
        ["3", "Order 三", "0", "007"],
    ]

    private func skipUnlessProbeEnabled() throws {
        guard ProcessInfo.processInfo.environment["DOYAH_UI_SNAPSHOT"] == "1" else {
            throw XCTSkip("xlsx 导出探针要起真写盘与外部 unzip：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）")
        }
    }

    private func temporaryURL(_ name: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xlsx-probe-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
    }

    private func makeDirectory(for url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    /// 走生产那条路导出一次，写到盘上（`AppState.exportResult` 的 xlsx 分支也是这一步）。
    private func exportWorkbook(to url: URL) throws {
        let result = QueryResult(columns: columns, rows: rows)
        let data = try ResultExporter.data(for: result, format: .xlsx)
        try makeDirectory(for: url)
        try data.write(to: url)
    }

    // MARK: - 外部工具

    /// 系统自带的 `unzip`（Info-ZIP）。不用本仓的 `Inflate`：那是被判方自己的代码。
    @discardableResult
    private func unzip(_ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private func entries(inWorkbookAt url: URL) throws -> [String] {
        let listing = try unzip(["-l", url.path]).output
        return listing
            .components(separatedBy: "\n")
            .filter { $0.contains("  ") && !$0.contains("Archive:") }
            .compactMap { line -> String? in
                guard let name = line.split(separator: " ", omittingEmptySubsequences: true).last else { return nil }
                let text = String(name)
                return text.contains(".") ? text : nil
            }
    }

    /// 把整个工作簿解到一个临时目录里再按名字读。
    ///
    /// 为什么不用 `unzip -p <file> <name>`：`[Content_Types].xml` 里的方括号在 unzip 里是**通配符**，
    /// 按名字取会被回一句 `filename not matched` —— 那不是文件的问题，是取法的坑。
    private func extract(_ url: URL) throws -> URL {
        let directory = url.deletingLastPathComponent()
            .appendingPathComponent("parts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let result = try unzip(["-o", "-q", url.path, "-d", directory.path])
        XCTAssertEqual(result.status, 0, "unzip 解不开工作簿：\(result.output)")
        return directory
    }

    private func part(_ name: String, in directory: URL) throws -> String {
        let file = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: file.path) else {
            let present = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            XCTFail("解包目录里没有 \(name)（有：\(present)）")
            return ""
        }
        return try String(contentsOf: file, encoding: .utf8)
    }

    /// 工作表里的一格：`(引用, 文本, 是否文本格)`。
    private struct Cell {
        let reference: String
        let value: String
        /// `true` = `t="inlineStr"`（文本格）；`false` = 数值格（没有 `t`，只有一个 `<v>`）。
        let isInlineText: Bool
    }

    private func cells(inSheet xml: String) throws -> [Cell] {
        let document = try XMLDocument(data: Data(xml.utf8), options: [])
        let nodes = try document.nodes(forXPath: "//*[local-name()='c']")
        return try nodes.compactMap { node in
            guard let element = node as? XMLElement,
                  let reference = element.attribute(forName: "r")?.stringValue else { return nil }
            let type = element.attribute(forName: "t")?.stringValue
            let inlineText = try element.nodes(forXPath: "*[local-name()='is']/*[local-name()='t']").first?.stringValue
            let numeric = try element.nodes(forXPath: "*[local-name()='v']").first?.stringValue
            let value = inlineText ?? numeric ?? ""
            return Cell(reference: reference, value: value, isInlineText: type == "inlineStr")
        }
    }

    // MARK: - ① 标准 ZIP · 六件齐全

    @MainActor
    func testWorkbookIsARealZipWithEveryPartInside() throws {
        try skipUnlessProbeEnabled()
        let url = temporaryURL("orders.xlsx")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try exportWorkbook(to: url)

        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(size, 0, "导出的是空文件")

        // ① ZIP 本身能被标准实现完整读出：`unzip -t` 逐条目校验 CRC，任何一个坏都会非 0 退出。
        let tested = try unzip(["-t", url.path])
        XCTAssertEqual(tested.status, 0, "产物不是合法的 ZIP（unzip -t 非 0）：\(tested.output)")
        // 注意：`unzip -t` 成功时打的是 "No errors detected"（里面也有 error 这个词），
        // 所以这里判的是**警告 / 失败**那两种标记，不是「出现过 error 这个词」。
        XCTAssertFalse(tested.output.contains("caution"), "unzip 报不确定的地方：\(tested.output)")
        XCTAssertFalse(tested.output.contains("cannot"), "unzip 读不动：\(tested.output)")

        let listed = try entries(inWorkbookAt: url)
        let directory = try extract(url)
        for required in [
            "[Content_Types].xml",
            "_rels/.rels",
            "xl/workbook.xml",
            "xl/_rels/workbook.xml.rels",
            "xl/styles.xml",
            "xl/worksheets/sheet1.xml",
        ] {
            XCTAssertTrue(listed.contains(required), "工作簿里缺部件 \(required)（实际：\(listed)）")
        }

        // 部件里的 XML 都要能被标准解析器读出来（片断拼错时 Excel 会说「文件已损坏」）。
        for name in listed where name.hasSuffix(".xml") || name.hasSuffix(".rels") {
            let content = try part(name, in: directory)
            XCTAssertNoThrow(try XMLDocument(data: Data(content.utf8), options: []),
                             "\(name) 不是合法 XML")
        }
        print("🧪 工作簿读数：\(size) 字节 · 部件 \(listed.count) 个 · unzip -t 通过")
        print("🧪 部件清单：\(listed)")
    }

    // MARK: - ② 类型映射：数字是数值格、文本是文本格、空值不写格

    @MainActor
    func testNumericAndTextCellsAreTypedTheWayTheResultSays() throws {
        try skipUnlessProbeEnabled()
        let url = temporaryURL("orders.xlsx")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try exportWorkbook(to: url)

        let cells = try cells(inSheet: try part("xl/worksheets/sheet1.xml", in: try extract(url)))
        let byReference = Dictionary(uniqueKeysWithValues: cells.map { ($0.reference, $0) })

        // 表头：四列都在、都是文本格。
        for (index, column) in columns.enumerated() {
            let reference = "\(Character(UnicodeScalar(UInt8(65 + index))))1"
            let cell = try XCTUnwrap(byReference[reference], "表头 \(reference) 没有格子")
            XCTAssertEqual(cell.value, column.name, "表头 \(reference) 不是列名")
            XCTAssertTrue(cell.isInlineText, "表头 \(reference) 不是文本格")
        }

        // 数值列（`integer` / `numeric`）：写成数值格 —— 用户要能直接求和。
        let id2 = try XCTUnwrap(byReference["A2"], "A2 没有格子")
        XCTAssertFalse(id2.isInlineText, "`integer` 列的 1 被写成了文本格（那列在 Excel 里算不了和）")
        XCTAssertEqual(Double(id2.value), 1, "A2 的数值不是 1：\(id2.value)")

        let amount2 = try XCTUnwrap(byReference["C2"], "C2 没有格子")
        XCTAssertFalse(amount2.isInlineText, "`numeric(10,2)` 列写成了文本格")
        XCTAssertEqual(Double(amount2.value), 12.5, "C2 的数值不是 12.50：\(amount2.value)")

        // 文本列：`t="inlineStr"`，中文与 `<` / `&` / 引号原样保留（转义错了 Excel 会说文件损坏）。
        let name2 = try XCTUnwrap(byReference["B2"], "B2 没有格子")
        XCTAssertTrue(name2.isInlineText, "`text` 列写成了数值格")
        XCTAssertEqual(name2.value, "订单一", "中文没有原样落进格子：\(name2.value)")

        let note2 = try XCTUnwrap(byReference["D2"], "D2 没有格子")
        XCTAssertEqual(note2.value, "含 <标签> & 引号\"", "尖括号 / & / 引号被吃了：\(note2.value)")

        // 空值（NULL）不写格：写了空串就与「值是空串」分不出来。
        XCTAssertNil(byReference["D3"], "NULL 那一格被写成了一个空格子")

        // 「看着像数字」的文本不许被吞掉前导零（宁可当文本，也不要悄悄改用户查出来的东西）。
        XCTAssertTrue(byReference["D4"]?.isInlineText ?? false, "`007` 被当成数字写了（前导零会没）")
        XCTAssertEqual(byReference["D4"]?.value, "007", "`007` 的值变了：\(byReference["D4"]?.value ?? "nil")")

        // 0 仍然是数值格（`0` 与「空」是两件事）。
        XCTAssertFalse(byReference["C4"]?.isInlineText ?? true, "`0` 被写成了文本格")
        XCTAssertEqual(byReference["C4"]?.value, "0")
        print("🧪 类型读数：A2 数值 \(id2.value) · C2 数值 \(amount2.value) · D4 文本 \(byReference["D4"]?.value ?? "nil")")
    }

    // MARK: - ③ 行列数与结果一致 · 同一输入逐字节一致

    @MainActor
    func testEveryRowLandsOnceAndTheSameInputExportsIdenticalBytes() throws {
        try skipUnlessProbeEnabled()
        let first = temporaryURL("a.xlsx")
        let second = temporaryURL("b.xlsx")
        defer {
            try? FileManager.default.removeItem(at: first.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: second.deletingLastPathComponent())
        }
        try exportWorkbook(to: first)
        try exportWorkbook(to: second)

        let sheet = try part("xl/worksheets/sheet1.xml", in: try extract(first))
        let document = try XMLDocument(data: Data(sheet.utf8), options: [])
        let rowNodes = try document.nodes(forXPath: "//*[local-name()='row']")
        XCTAssertEqual(rowNodes.count, rows.count + 1, "行数不是「表头 + \(rows.count) 行」（实际 \(rowNodes.count)）")

        // 每行每列都落在自己的位置：逐行逐格比对（少一格 = 错位）。
        let cells = try cells(inSheet: sheet)
        let byReference = Dictionary(uniqueKeysWithValues: cells.map { ($0.reference, $0) })
        for (rowIndex, row) in rows.enumerated() {
            for (columnIndex, value) in row.enumerated() {
                let letter = Character(UnicodeScalar(UInt8(65 + columnIndex)))
                let reference = "\(letter)\(rowIndex + 2)"
                if let value {
                    XCTAssertEqual(byReference[reference]?.value, value, "\(reference) 的值不对")
                } else {
                    XCTAssertNil(byReference[reference], "\(reference) 该是空格子")
                }
            }
        }

        let a = try Data(contentsOf: first)
        let b = try Data(contentsOf: second)
        XCTAssertEqual(a, b, "同一份输入两次导出的字节不同 —— 没法 diff、没法校验（时间戳没固定？）")
        print("🧪 行数读数：\(rowNodes.count) 行（表头 1 + \(rowNodes.count - 1)）· 两次导出逐字节一致 \(a == b)")
    }

    // MARK: - ④ 不引第三方 xlsx 依赖（需求 ③）

    @MainActor
    func testTheWriterDoesNotPullAThirdPartyXLSXLibrary() throws {
        try skipUnlessProbeEnabled()
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        for forbidden in ["CoreXLSX", "xlsxwriter", "ExcelKit", "ZIPFoundation", "libxlsxwriter", "Spreadsheet"] {
            XCTAssertFalse(
                manifest.contains(forbidden),
                "Package.swift 里出现了 \(forbidden) —— 需求 ③ 要求导出不引第三方 xlsx 依赖"
            )
        }
        // 本仓自己的写入器在 Core，且只用 Foundation（ZIP 是自己拼的）。
        let writer = try String(
            contentsOf: root.appendingPathComponent("Core/XLSXWriter.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(writer.contains("import Foundation"), "XLSXWriter 不再只依赖 Foundation")
        XCTAssertFalse(writer.contains("import ZIPFoundation"), "XLSXWriter 引了第三方 ZIP 库")
        print("🧪 依赖读数：Package.swift 命中 0 个第三方 xlsx 库 · 写入器只 import Foundation")
    }
}
