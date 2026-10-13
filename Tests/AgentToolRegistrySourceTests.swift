import XCTest
@testable import DoyahCore

/// `FR-AI-19` 验收要点 ①（**源树判据**）：`Core/` 与 `App/` 里**不得按工具名分支** ——
/// 八个工具名的字面量只许出现在注册表的定义处。
///
/// 为什么这条必须是判据而不是纪律：工具名一旦散进分支，注册表就不再是「唯一出处」，
/// 而「唯一出处」恰恰是本条需求存在的全部理由。
final class AgentToolRegistrySourceTests: XCTestCase {

    /// 允许出现工具名的那**一个**文件。
    private static let registryFile = "Core/AgentToolRegistry.swift"

    /// 八个工具名的字面量（MVP 六件 + 第二批两件）。
    private static let toolNames = ["read_file", "list_dir", "search", "query_db",
                                    "write_file", "run_command", "read_notes", "fetch_url"]

    /// 剥掉注释：注释里写着工具名**不算**接线（同族判据的既有做法）。
    private static func stripComments(_ text: String) -> String {
        var output = ""
        var index = text.startIndex
        var inBlock = false
        var inLine = false
        var inString = false

        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index) < text.endIndex ? text[text.index(after: index)] : nil

            if inBlock {
                if character == "*", next == "/" { inBlock = false; index = text.index(after: index) }
            } else if inLine {
                if character == "\n" { inLine = false; output.append(character) }
            } else if inString {
                output.append(character)
                if character == "\"" { inString = false }
            } else if character == "/", next == "/" {
                inLine = true; index = text.index(after: index)
            } else if character == "/", next == "*" {
                inBlock = true; index = text.index(after: index)
            } else {
                if character == "\"" { inString = true }
                output.append(character)
            }
            index = text.index(after: index)
        }
        return output
    }

    private func swiftFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    func testToolNameLiteralsAppearOnlyInTheRegistry() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        var offenders: [String] = []
        var scanned = 0

        for folder in ["Core", "App"] {
            for file in swiftFiles(in: root.appendingPathComponent(folder)) {
                let relative = "\(folder)/\(file.lastPathComponent)"
                if relative == Self.registryFile { continue }
                scanned += 1
                let text = Self.stripComments((try? String(contentsOf: file, encoding: .utf8)) ?? "")
                for name in Self.toolNames where text.contains("\"\(name)\"") {
                    offenders.append("\(relative) 里出现了工具名字面量 \"\(name)\"")
                }
            }
        }

        XCTAssertGreaterThan(scanned, 20, "扫到的文件太少 ⇒ 判据自己失效（空跑防护）")
        XCTAssertTrue(offenders.isEmpty, "工具名只许出现在 \(Self.registryFile)：\n" + offenders.joined(separator: "\n"))
    }

    /// 反例的方向：**判据本身要能判红** —— 拿一段真的按工具名分支的代码试一下。
    func testTheCriterionActuallyFailsOnBranchingCode() {
        let branching = """
        switch toolName {
        case "run_command": return try run(command)
        default: return nil
        }
        """
        let stripped = Self.stripComments(branching)
        XCTAssertTrue(Self.toolNames.contains { stripped.contains("\"\($0)\"") },
                      "这段样例必须被抓到，否则判据是假的")

        let commentOnly = """
        // 这里提到 "run_command" 只是注释
        let value = 1
        """
        let strippedComment = Self.stripComments(commentOnly)
        XCTAssertFalse(Self.toolNames.contains { strippedComment.contains("\"\($0)\"") },
                       "注释里提到工具名不算接线（剥注释是判据的一部分）")
    }
}
