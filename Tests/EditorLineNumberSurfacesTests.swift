import XCTest

/// `Scripts/check-editor-line-numbers.py` 的 Swift 版（2026-11-10 判据搬家第三批 · UI 交互 9 条之一）。
///
/// **为什么搬**：三次真红并导致改产品 / 补台账 ——
/// `8e4690c8`（L-181 收口）「App/ 里必须只在绘制件出现一处，实测两份」⇒ 把编辑面第二处行起点算法
/// 改走 `CodeLines.count(in:)`；`0371913b` `App/Views/NotePreviewBody.swift` 的 `PreviewTextView`
/// 未登记 ⇒ 补一条「只读预览面不画」；`fb539b30` 同族红灯（N2-10 的 `PreviewTextView` 未登记）。
/// 判定物是**盘上的类清单 + 台账 + 三个字面锚点**，纯数据 ⇒ 属于测试。
///
/// 它守什么（队列 L-111）：行号一半是口径（`Core/CodeLines`，15 项单测）、一半是画法。
/// 画法这一半没有判据时，数据库侧 SQL 编辑器四天没行号，而「补上」最容易被做错 ——
/// 再画一套的下场是同一个文件在两个编辑器里行号不一致。
///
/// 判据（与老脚本逐条同口径）：
/// A 双向对账：`App/` + `Plugins/Notes/Views/` 里每个 `NSTextView` / `NSTextField` 子类都在台账里
///   （盘上多一个未登记 ⇒ 红；台账指向的文件不在盘上 / 类已搬走 ⇒ 红）。
/// B 挂法三件齐备：登记「画行号」的面必须同时出现 `LineNumberGutter` / `gutter.reload(` /
///   `gutter.draw(in:`，且自己不许算行起点。
/// C 唯一出处：`CodeLines.lineStarts(` 与 `static func width(digits:` 在 `App/` 里各恰好一处；
///   `gutterWidth(digits:)` 的定义行必须是**转发**。
/// D 台账口径非空话：「画」的要有 registry，「不画」的理由 ≥ 12 字。
/// E 文档锚点（文档不在盘上 ⇒ 跳过，不算红）。
/// F 空跑防护：面下限 / 编辑面下限 / 绘制件在位。
final class EditorLineNumberSurfacesTests: XCTestCase {

    enum Gate {
        static let scopeDirs = ["App", "Plugins/Notes/Views"]
        static let component = "App/Views/LineNumberGutter.swift"
        static let componentType = "LineNumberGutter"
        static let ledgerPath = "Scripts/editor-line-number-surfaces.json"
        static let hooks: [(String, String)] = [
            ("component", "LineNumberGutter"),
            ("reload", "gutter.reload("),
            ("draw", "gutter.draw(in:"),
        ]
        static let docAnchors: [(String, String)] = [
            ("Docs/Doyah产品概要设计说明书.md", "行号列不只工作区编辑器有"),
            ("Docs/Doyah产品需求规格说明书.md", "数据库侧 SQL 编辑器也有行号列"),
        ]
        /// 2026-11-10 实测：190 份源文件 / 8 个编辑面（7 条台账 + 本轮补登的 AgentComposerTextView）。
        static let scanFloor = 90
        static let subclassFloor = 2
    }

    struct Surface {
        let kind: String
        let name: String
        let file: String
    }

    struct Entry {
        let kind: String
        let name: String
        let file: String
        let hasGutter: Bool
        let registry: String
        let reason: String
    }

    private static let subclassRegex = try! NSRegularExpression(
        pattern: #"^\s*(?:public\s+|private\s+|internal\s+|final\s+)*class\s+([A-Za-z_]\w*)\s*:\s*(NSTextView|NSTextField)\b"#)

    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func text(_ relative: String) throws -> String {
        try String(contentsOf: Self.repoRoot.appendingPathComponent(relative), encoding: .utf8)
    }

    /// 扫描面 = `App/` + **插件目录下的宿主视图**（2026-10-13 概设 §7 P3 搬家，它们仍编进宿主模块）。
    func appFiles() throws -> [String] {
        var found: [String] = []
        for dir in Gate.scopeDirs {
            let base = Self.repoRoot.appendingPathComponent(dir)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: base.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  let enumerator = FileManager.default.enumerator(
                    at: base, includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                found.append(relative(url))
            }
        }
        return found.sorted()
    }

    func relative(_ url: URL) -> String {
        url.path.replacingOccurrences(of: Self.repoRoot.path + "/", with: "")
    }

    func surfaces() throws -> [Surface] {
        var found: [Surface] = []
        for file in try appFiles() {
            let content = try text(file)
            for (index, line) in content.components(separatedBy: "\n").enumerated() {
                _ = index
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                guard let match = Self.subclassRegex.firstMatch(in: line, range: range),
                      let name = Range(match.range(at: 1), in: line),
                      let kind = Range(match.range(at: 2), in: line) else { continue }
                found.append(Surface(kind: String(line[kind]), name: String(line[name]), file: file))
            }
        }
        return found.sorted { ($0.file, $0.name) < ($1.file, $1.name) }
    }

    func ledger() throws -> (entries: [Entry], singleSource: [String: String], scanFloor: Int, subclassFloor: Int) {
        let url = Self.repoRoot.appendingPathComponent(Gate.ledgerPath)
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let raw = object["surfaces"] as? [[String: Any]] ?? []
        let entries = raw.map { item in
            Entry(kind: item["kind"] as? String ?? "",
                  name: item["name"] as? String ?? "",
                  file: item["file"] as? String ?? "",
                  hasGutter: item["hasGutter"] as? Bool ?? false,
                  registry: item["registry"] as? String ?? "",
                  reason: item["reason"] as? String ?? "")
        }
        let single = object["singleSource"] as? [String: String] ?? [:]
        return (entries, single,
                object["scanFloor"] as? Int ?? Gate.scanFloor,
                object["subclassFloor"] as? Int ?? Gate.subclassFloor)
    }

    // MARK: - A 双向对账

    func testLedgerAndDiskAgreeBothWays() throws {
        let (entries, _, _, _) = try ledger()
        let onDisk = try surfaces()
        var problems: [String] = []
        for entry in entries {
            let path = Self.repoRoot.appendingPathComponent(entry.file)
            guard FileManager.default.fileExists(atPath: path.path) else {
                problems.append("台账里的编辑面 `\(entry.name)` 指向的文件不在盘上：\(entry.file)")
                continue
            }
            guard let found = onDisk.first(where: { $0.name == entry.name && $0.kind == entry.kind }) else {
                problems.append("台账登记 `\(entry.name)`（\(entry.kind)）但 \(entry.file) 里找不到这个类 ⇒ 台账陈旧")
                continue
            }
            if found.file != entry.file {
                problems.append("`\(entry.name)` 已经搬到 \(found.file)，台账还写着 \(entry.file)")
            }
        }
        for surface in onDisk where !entries.contains(where: { $0.name == surface.name && $0.kind == surface.kind }) {
            problems.append("\(surface.file) 里的 `\(surface.name)`（\(surface.kind)）**没有登记** —— "
                + "新编辑面必须说明「画不画行号、为什么」")
        }
        XCTAssertTrue(problems.isEmpty, problems.joined(separator: "\n"))
        XCTAssertEqual(onDisk.count, 7, "编辑面条数与搬家时实测不同（当前 \(onDisk.count)）—— 要么产品变了，要么口径坏了")
    }

    // MARK: - B 挂法三件 + C 唯一出处

    func testEveryGutterSurfaceMountsTheSharedComponent() throws {
        let (entries, _, _, _) = try ledger()
        var problems: [String] = []
        for entry in entries where entry.hasGutter {
            guard let content = try? text(entry.file) else { continue }
            for (label, token) in Gate.hooks where !content.contains(token) {
                problems.append("`\(entry.name)`（\(entry.file)）登记了「画行号」，但**挂法**里少了 \(label)："
                    + "源码里找不到 `\(token)`")
            }
            if content.contains("CodeLines.lineStarts(") {
                problems.append("`\(entry.name)`（\(entry.file)）自己算了行起点（`CodeLines.lineStarts(`）—— "
                    + "行号口径只许在绘制件里算一次")
            }
        }
        XCTAssertTrue(problems.isEmpty, problems.joined(separator: "\n"))
    }

    func testAlgorithmHasExactlyOneSource() throws {
        let (_, single, _, _) = try ledger()
        var startsFiles: [String] = []
        var widthDefs: [String] = []
        var forwardDefs: [(String, String)] = []
        var componentFile: String?
        for file in try appFiles() {
            let content = try text(file)
            if content.contains("CodeLines.lineStarts(") { startsFiles.append(file) }
            if content.contains("static func width(digits:") { widthDefs.append(file) }
            let componentPattern = #"final\s+class\s+"# + Gate.componentType + #"\b"#
            if content.range(of: componentPattern, options: .regularExpression) != nil {
                componentFile = file
            }
            for line in content.components(separatedBy: "\n")
            where line.contains("func gutterWidth(digits:") && !line.contains("LineNumberGutter.width(digits:") {
                forwardDefs.append((file, line.trimmingCharacters(in: .whitespaces)))
            }
        }
        var problems: [String] = []
        let expectedStarts = single["lineStarts"] ?? Gate.component
        if startsFiles != [expectedStarts] {
            problems.append("`CodeLines.lineStarts(` 在 `App/` 里必须只在 `\(expectedStarts)` 出现一处，"
                + "实测 \(startsFiles)")
        }
        let expectedWidth = single["widthAlgorithm"] ?? Gate.component
        if widthDefs != [expectedWidth] {
            problems.append("`static func width(digits:`（列宽算法）在 `App/` 里必须只在 `\(expectedWidth)` 出现一处，"
                + "实测 \(widthDefs)")
        }
        if componentFile != Gate.component {
            problems.append("绘制件 `\(Gate.componentType)` 不在 `\(Gate.component)`（实测 \(componentFile ?? "nil")）")
        }
        for (file, line) in forwardDefs {
            problems.append("\(file) 里的 `gutterWidth(digits:)` 不是转发，而是就地重算：`\(line)`")
        }
        XCTAssertTrue(problems.isEmpty, problems.joined(separator: "\n"))
    }

    // MARK: - D 台账口径 + E 文档锚点 + F 空跑防护

    func testLedgerPolicyIsNotEmptyTalk() throws {
        let (entries, _, _, _) = try ledger()
        var problems: [String] = []
        for entry in entries {
            if entry.hasGutter {
                if entry.registry.trimmingCharacters(in: .whitespaces).isEmpty {
                    problems.append("`\(entry.name)` 登记了「画行号」但没写它属哪条需求（registry 空）")
                }
            } else if entry.reason.trimmingCharacters(in: .whitespaces).count < 12 {
                problems.append("`\(entry.name)` 登记为「不画行号」但理由没写清（少于 12 字）")
            }
        }
        XCTAssertTrue(problems.isEmpty, problems.joined(separator: "\n"))
    }

    func testDocAnchorsStillSayTheRule() throws {
        for (relative, phrase) in Gate.docAnchors {
            let path = Self.repoRoot.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: path.path) else { continue }   // 文档不在盘上 ⇒ 跳过
            let content = try String(contentsOf: path, encoding: .utf8)
            XCTAssertTrue(content.contains(phrase),
                          "\(relative) 里找不到口径锚点「\(phrase)」—— 口径只活在代码里，下一个人还会各画一套")
        }
    }

    func testFaceIsNotNarrowed() throws {
        let (entries, _, scanFloor, subclassFloor) = try ledger()
        let files = try appFiles()
        let found = try surfaces()
        XCTAssertGreaterThanOrEqual(files.count, scanFloor,
                                    "扫到的源文件只有 \(files.count) 份（下限 \(scanFloor)）⇒ 扫描路径可能写坏了")
        XCTAssertGreaterThanOrEqual(found.count, subclassFloor,
                                    "扫到的编辑面只有 \(found.count) 个（下限 \(subclassFloor)）")
        XCTAssertGreaterThanOrEqual(entries.count, subclassFloor,
                                    "台账里的编辑面只有 \(entries.count) 条（下限 \(subclassFloor)）")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: Self.repoRoot.appendingPathComponent(Gate.component).path),
                      "绘制件文件不在盘上：\(Gate.component)")
    }

    // MARK: - 口径自检（解析器不许在坏输入上静默通过）

    func testSubclassScanIgnoresModifiersAndOtherClasses() {
        func names(_ source: String) -> [String] {
            source.components(separatedBy: "\n").compactMap { line in
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                guard let match = Self.subclassRegex.firstMatch(in: line, range: range),
                      let name = Range(match.range(at: 1), in: line) else { return nil }
                return String(line[name])
            }
        }
        XCTAssertEqual(names("final class CodeTextView: NSTextView {"), ["CodeTextView"])
        XCTAssertEqual(names("private final class ResultCellTextField: NSTextField {"), ["ResultCellTextField"])
        XCTAssertEqual(names("    class Bad: NSTextViewish {"), [])
        XCTAssertEqual(names("struct NotAClass: NSTextView {"), [])
    }
}
