import XCTest

/// `FR-STD-WS-UI-014` 的**源树判据**：`App/Views/*Sheet*.swift` 这一族对话框里
///
///   ① 不许出现**纯图标动作**（`label: { Image(systemName:) }` 里没有任何文字）；
///   ② 取消 / 关闭 / 稍后这类动作必须带 `role: .cancel`；
///   ③ 动作行必须走 `DialogActionRow`（否则 `Core/DialogButtonPolicy` 又会变成没人用的死代码）。
///
/// ## 为什么要有这一条
///
/// 需求那句话（「Sheet / Form 内无纯图标按钮，取消为 `role: .cancel`」）在本仓库已经存在很久，
/// 但它此前**没有任何东西在管**：25 个对话框各自手搭 `HStack`，取消按钮只挂
/// `.keyboardShortcut(.cancelAction)` 凑 Esc、`ButtonRole` 一枚没写 —— 于是「Esc 能关」在、
/// 「这是取消」不在。判据不落到源树上，下一个对话框会原样再长出来一份。
///
/// ## 不是正则匹配就算过
///
/// 扫描前先把**注释去掉、字符串正文抹成下划线**（保留字符位置与行号）：注释里写着
/// `Image(systemName:)` 不算接线，而字符串里的括号会把配对算错。
final class DialogButtonSourceTests: XCTestCase {

    /// 取消 / 关闭 / 稍后 —— 这一族动作必须是 `role: .cancel`。
    private static let cancelKeys = ["commonCancel", "commonClose", "safetyConfirmCancel", "relaunchLater"]

    /// 非空跑的下限：对话框文件数少于这个数说明扫描范围坏了（不是「没有违规」）。
    private static let minimumDialogFiles = 20

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    // MARK: - 扫描底座

    /// 去掉注释、把字符串正文抹成 `_`（保持字符位置与换行，行号才对得上）。
    static func sanitized(_ text: String) -> String {
        var out: [Character] = []
        var index = text.startIndex
        var inLineComment = false
        var inBlockComment = false
        var inString = false

        while index < text.endIndex {
            let character = text[index]
            let next: Character? = text.index(after: index) < text.endIndex
                ? text[text.index(after: index)]
                : nil

            if inLineComment {
                if character == "\n" {
                    inLineComment = false
                    out.append(character)
                } else {
                    out.append(" ")
                }
            } else if inBlockComment {
                if character == "*", next == "/" {
                    inBlockComment = false
                    out.append(" ")
                    out.append(" ")
                    index = text.index(after: index)
                } else {
                    out.append(character == "\n" ? "\n" : " ")
                }
            } else if inString {
                if character == "\\" {
                    out.append("_")
                    if let next {
                        out.append(next == "\n" ? "\n" : "_")
                        index = text.index(after: index)
                    }
                } else if character == "\"" {
                    inString = false
                    out.append(character)
                } else {
                    out.append(character == "\n" ? "\n" : "_")
                }
            } else if character == "/", next == "/" {
                inLineComment = true
                out.append(" ")
                out.append(" ")
                index = text.index(after: index)
            } else if character == "/", next == "*" {
                inBlockComment = true
                out.append(" ")
                out.append(" ")
                index = text.index(after: index)
            } else if character == "\"" {
                inString = true
                out.append(character)
            } else {
                out.append(character)
            }
            index = text.index(after: index)
        }
        return String(out)
    }

    private func lineNumber(at index: Int, in text: String) -> Int {
        guard let target = text.index(text.startIndex, offsetBy: index, limitedBy: text.endIndex) else {
            return 0
        }
        return text[text.startIndex..<target].reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }

    /// 从 `start`（指向 `{` 或 `(`）起配对到闭合位置；字符串已被抹平，所以直接数括号。
    static func match(_ open: Character, _ close: Character, from start: Int, in text: String) -> Int? {
        var depth = 0
        var index = text.index(text.startIndex, offsetBy: start)
        while index < text.endIndex {
            let character = text[index]
            if character == open { depth += 1 }
            if character == close {
                depth -= 1
                if depth == 0 { return text.distance(from: text.startIndex, to: index) }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private func dialogFiles() throws -> [URL] {
        let views = root.appendingPathComponent("App/Views")
        let all = try FileManager.default.contentsOfDirectory(at: views, includingPropertiesForKeys: nil)
        return all
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent.contains("Sheet") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - ① 纯图标动作

    func testNoIconOnlyActionInsideDialogs() throws {
        let files = try dialogFiles()
        XCTAssertGreaterThanOrEqual(
            files.count, Self.minimumDialogFiles,
            "只扫到 \(files.count) 个对话框文件 —— 扫描范围坏了，『没有违规』不作数"
        )

        var findings: [String] = []
        for file in files {
            let raw = try String(contentsOf: file, encoding: .utf8)
            let text = Self.sanitized(raw)

            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(of: "label:", range: searchRange) {
                searchRange = range.upperBound..<text.endIndex
                guard let brace = text[range.upperBound...].firstIndex(of: "{") else { continue }
                let offset = text.distance(from: text.startIndex, to: brace)
                guard let end = Self.match("{", "}", from: offset, in: text) else {
                    findings.append("\(file.lastPathComponent):\(lineNumber(at: offset, in: text)) 括号没配上")
                    continue
                }
                let start = text.index(text.startIndex, offsetBy: offset)
                let stop = text.index(text.startIndex, offsetBy: end)
                let block = String(text[start...stop])
                let hasIcon = block.contains("Image(systemName:")
                let hasText = block.contains("Text(") || block.contains("Label(")
                if hasIcon && !hasText {
                    findings.append("\(file.lastPathComponent):\(lineNumber(at: offset, in: text)) 纯图标动作")
                }
            }
        }

        XCTAssertTrue(findings.isEmpty, "对话框里出现无文字的动作：\n" + findings.joined(separator: "\n"))
    }

    // MARK: - ② 取消档必须是 role: .cancel

    func testCancelKindActionsCarryCancelRole() throws {
        let files = try dialogFiles()
        XCTAssertGreaterThanOrEqual(files.count, Self.minimumDialogFiles)

        var findings: [String] = []
        var checked = 0
        for file in files {
            let raw = try String(contentsOf: file, encoding: .utf8)
            let text = Self.sanitized(raw)

            for maker in ["DialogActionButton(", "DialogActionSpec(", "Button(", "Menu("] {
                var searchRange = text.startIndex..<text.endIndex
                while let range = text.range(of: maker, range: searchRange) {
                    searchRange = range.upperBound..<text.endIndex
                    let openIndex = text.distance(from: text.startIndex, to: range.upperBound) - 1
                    guard let closeIndex = Self.match("(", ")", from: openIndex, in: text) else { continue }
                    let start = text.index(text.startIndex, offsetBy: openIndex)
                    let stop = text.index(text.startIndex, offsetBy: closeIndex)
                    let call = String(text[start...stop])

                    let isCancelKind = Self.cancelKeys.contains { call.contains(".\($0)") }
                        || call.contains("取消") || call.contains("关闭")
                    guard isCancelKind else { continue }
                    checked += 1
                    if !call.contains("role: .cancel") {
                        findings.append("\(file.lastPathComponent):\(lineNumber(at: openIndex, in: text)) \(call.prefix(60))")
                    }
                }
            }
        }

        XCTAssertGreaterThan(checked, 10, "只认到 \(checked) 处取消类动作 —— 太少，扫描口径可能失效")
        XCTAssertTrue(findings.isEmpty, "取消类动作没挂 role: .cancel：\n" + findings.joined(separator: "\n"))
    }

    // MARK: - ③ 动作行必须走 DialogActionRow（否则口径又成死代码）

    func testDialogActionRowsAreWiredInProductionSheets() throws {
        let files = try dialogFiles()
        var wired: [String] = []
        for file in files {
            let raw = try String(contentsOf: file, encoding: .utf8)
            if Self.sanitized(raw).contains("DialogActionRow(") {
                wired.append(file.lastPathComponent)
            }
        }

        XCTAssertGreaterThanOrEqual(
            wired.count, 3,
            "只有 \(wired.count) 个对话框用了 DialogActionRow（\(wired.joined(separator: ", "))）—— 口径没接线"
        )
    }

    func testDialogActionButtonAlwaysRendersVisibleText() throws {
        let file = root.appendingPathComponent("App/Views/DialogActionButton.swift")
        let text = Self.sanitized(try String(contentsOf: file, encoding: .utf8))

        XCTAssertTrue(
            text.contains("Label(title, systemImage: systemName)"),
            "DialogActionButton 必须画「图标 + 文字」；退回纯图标就等于需求被静默推翻"
        )
    }

    func testActionRowMapsCancelRoleToButtonRoleCancel() throws {
        let file = root.appendingPathComponent("App/Views/DialogActionRow.swift")
        let text = Self.sanitized(try String(contentsOf: file, encoding: .utf8))

        XCTAssertTrue(
            text.contains("case .cancel: return .cancel"),
            "取消档必须翻成 ButtonRole.cancel（需求原话：取消为 role: .cancel）"
        )
        XCTAssertTrue(
            text.contains("DialogButtonPolicy.resolve("),
            "画什么必须由 Core 的投影决定，不许在视图里另写一套次序"
        )
    }
}
