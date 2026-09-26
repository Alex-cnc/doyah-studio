import XCTest
@testable import DoyahCore

final class LocalizationTests: XCTestCase {

    func testEveryKeyHasBothLanguagesAndNoEmptyText() {
        for key in LKey.allCases {
            for language in AppLanguage.allCases {
                guard let value = LocalizedStrings.table[key]?[language] else {
                    XCTFail("缺少文案：\(key.rawValue) / \(language.rawValue)")
                    continue
                }
                XCTAssertFalse(
                    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "文案为空：\(key.rawValue) / \(language.rawValue)"
                )
            }
        }
    }

    func testTableCoversEveryDeclaredKey() {
        for key in LKey.allCases {
            XCTAssertNotNil(LocalizedStrings.table[key], "table 缺少 key：\(key.rawValue)")
        }
        XCTAssertEqual(LocalizedStrings.table.count, LKey.allCases.count)
    }

    func testLanguageIdentifiers() {
        XCTAssertEqual(AppLanguage.simplifiedChinese.rawValue, "zh-Hans")
        XCTAssertEqual(AppLanguage.english.rawValue, "en")
        XCTAssertEqual(AppLanguage.allCases.count, 2)
        XCTAssertEqual(AppLanguage.simplifiedChinese.displayName, "简体中文")
        XCTAssertEqual(AppLanguage.english.displayName, "English")
    }

    func testFormattingFollowsLanguage() {
        let zh = LocalizedStrings.format(.resultSize, language: .simplifiedChinese, 3, 2)
        let en = LocalizedStrings.format(.resultSize, language: .english, 3, 2)

        XCTAssertEqual(zh, "3 行 · 2 列")
        XCTAssertEqual(en, "3 rows · 2 columns")
    }

    func testDiagnosticsFollowLanguage() {
        let zh = SQLLinter(databaseType: .postgresql, language: .simplifiedChinese).analyze("SELECT 'abc")
        let en = SQLLinter(databaseType: .postgresql, language: .english).analyze("SELECT 'abc")

        XCTAssertEqual(zh.count, 1)
        XCTAssertTrue(zh[0].message.contains("字符串"))
        XCTAssertEqual(en.count, 1)
        XCTAssertTrue(en[0].message.lowercased().contains("unterminated string"))
    }

    func testSystemDefaultIsOneOfSupportedLanguages() {
        XCTAssertTrue(AppLanguage.allCases.contains(AppLanguage.systemDefault))
    }

    // MARK: - 文案内容自洽（防「串位」与漏翻）

    /// 语言中立的键：本来就是同一个串，或本来就不含汉字（URL / 模型名 / 通用术语）。
    ///
    /// 只有这三个键允许「中英同形」或「中文里没有汉字」，其余键都必须是真的中文，
    /// 否则就是「把英文抄进了中文槽位」。
    private static let languageNeutralKeys: Set<LKey> = [
        .agentEndpointPlaceholder,
        .agentModelPlaceholder,
        .agentAPIKey
    ]

    /// 英文文案里不得残留汉字。
    ///
    /// 这条直接对应 SRS 的验收口径「切换后逐页检查不得残留硬编码中 / 英文」，
    /// 也是夜间记录里那次「文案串位」（`字符串没有闭合` 变成 `功能尚未实现：%@`）
    /// 的自动化探针：key 覆盖齐全但内容对错了位，靠数量校验是查不出来的。
    func testEnglishTextCarriesNoChineseResidue() {
        let han = CharacterSet(charactersIn: "\u{4E00}"..."\u{9FFF}")
        for key in LKey.allCases where !Self.languageNeutralKeys.contains(key) {
            let english = LocalizedStrings.table[key]?[.english] ?? ""
            XCTAssertNil(
                english.rangeOfCharacter(from: han),
                "英文文案里出现汉字（疑似串位或漏翻）：\(key.rawValue) → \(english)"
            )
        }
    }

    /// 中文文案必须真的是中文，不能是英文原文。
    func testChineseTextIsLocalizedNotLeftInEnglish() {
        let han = CharacterSet(charactersIn: "\u{4E00}"..."\u{9FFF}")
        for key in LKey.allCases where !Self.languageNeutralKeys.contains(key) {
            let chinese = LocalizedStrings.table[key]?[.simplifiedChinese] ?? ""
            XCTAssertNotNil(
                chinese.rangeOfCharacter(from: han),
                "中文文案里没有汉字（疑似把英文抄进了中文槽位）：\(key.rawValue) → \(chinese)"
            )
        }
    }

    /// 两种语言的 `String(format:)` 占位符必须**逐位一致**。
    ///
    /// 占位符种类或顺序不一致时，`String(format:)` 会静默产出错值（甚至读越界），
    /// 界面上表现为「数字 / 名称串到了别的位置」——同样是数量校验查不出来的。
    func testFormatSpecifiersMatchBetweenLanguages() {
        for key in LKey.allCases {
            let chinese = LocalizedStrings.table[key]?[.simplifiedChinese] ?? ""
            let english = LocalizedStrings.table[key]?[.english] ?? ""
            XCTAssertEqual(
                Self.formatSpecifiers(in: chinese),
                Self.formatSpecifiers(in: english),
                "中英占位符不一致：\(key.rawValue)\n  中：\(chinese)\n  英：\(english)"
            )
        }
    }

    // MARK: - 占位符与实参的**类型**要对上（第 16 轮读图产出）

    /// 调用点传整数、模板就必须是整数占位符 —— 写成 `%@` 会在界面上印出 `(null)`。
    ///
    /// **背景（真缺陷，靠读图发现）**：界面快照 `mcp-approval-empty-{zh,en}{,-dark}` 的副行
    /// 写着「待审批（**(null)**）」/「Waiting for you ((null))」。根因在语言表：
    /// `mcpApprovalPending` 的模板是 `%@`（对象），而调用点
    /// （`App/Views/MCPApprovalPanel.swift:63`）传的是 `Int`（`mcpPendingApprovals.count`）
    /// —— `String(format:)` 拿到非对象参数时给的就是字面量 `(null)`。
    /// 同族的第二处：`startupSQLRefused`（模板 `%@`、调用点 `offenders.count`）。
    ///
    /// 为什么此前没人发现：数量校验（键齐不齐）、中英占位符一致性、语言门禁、
    /// 状态一致性**都看不见它** —— 它们只比较模板与模板，不比较模板与实参。
    ///
    /// 这里的台账就是**已知会收整数的调用点**；通用的机械门禁
    /// （模板占位符 ↔ 调用点实参类型逐条对账，含类型不明的实参登记）是**队列 L-25**，
    /// 本条本轮只修这两处 + 钉住已知调用点，**不半改**那条门禁。
    func testIntegerCallSitesUseIntegerPlaceholders() {
        // **前提自检**（判据的地基）：把整数喂给 `%@` 模板，`String(format:)` 真的会印 `(null)`。
        // 这条不成立的话，下面两条判据就是空的 —— 与第 5 轮给 bash 3.2 静默吞值写的做法同源
        // （先证明「祸害真的存在」，再拿它当判据）。
        let premise = String(
            format: "待审批（%@）",
            locale: Locale(identifier: "zh_Hans"),
            arguments: [Int32(0)]
        )
        XCTAssertTrue(
            premise.contains("(null)"),
            "前提不成立：`%@` 配整数并不印 (null)（实际 \(premise)）—— 本条判据要重新设计"
        )

        // (键, 那条语句渲染出来该带的数字)
        let ledger: [(LKey, Int32)] = [
            (.mcpApprovalPending, 0),      // 面板副行：没有待审批项时也该是「(0)」而不是「(null)」
            (.startupSQLRefused, 3)        // 只读连接上被整体跳过的写语句条数
        ]
        for (key, value) in ledger {
            for language in AppLanguage.allCases {
                let rendered = LocalizedStrings.format(key, language: language, value)
                XCTAssertFalse(
                    rendered.contains("(null)"),
                    "整数实参配了 %@ 模板 ⇒ 印出 (null)：\(key.rawValue) / \(language.rawValue) → \(rendered)"
                )
                XCTAssertTrue(
                    rendered.contains("\(value)"),
                    "渲染结果里没带上那个整数：\(key.rawValue) / \(language.rawValue) → \(rendered)"
                )
            }
        }
    }

    /// 机械扫一遍：模板里**只有整数占位符**的键，喂整数必须渲染出数字、且不许出现 `(null)`。
    ///
    /// 与上一条互补：上一条钉住「已知会收整数的调用点」，这一条把**所有**整数型模板一起扫，
    /// 扫到 0 个键说明判据失效（当场变红，不允许「什么都没检查」也算通过）。
    func testEveryIntegerPlaceholderAcceptsAnInt() {
        var checked = 0
        for key in LKey.allCases {
            for language in AppLanguage.allCases {
                let template = LocalizedStrings.table[key]?[language] ?? ""
                let specifiers = Self.formatSpecifiers(in: template)
                guard !specifiers.isEmpty,
                      specifiers.allSatisfy({ $0 == "%d" || $0 == "%i" })
                else { continue }

                let rendered: String
                switch specifiers.count {
                case 1: rendered = LocalizedStrings.format(key, language: language, 7)
                case 2: rendered = LocalizedStrings.format(key, language: language, 7, 8)
                case 3: rendered = LocalizedStrings.format(key, language: language, 7, 8, 9)
                case 4: rendered = LocalizedStrings.format(key, language: language, 7, 8, 9, 10)
                default: continue
                }

                XCTAssertFalse(
                    rendered.contains("(null)"),
                    "整数占位符渲染成了 (null)：\(key.rawValue) / \(language.rawValue) → \(rendered)"
                )
                XCTAssertTrue(
                    rendered.contains("7"),
                    "渲染结果里没带上那个整数：\(key.rawValue) / \(language.rawValue) → \(rendered)"
                )
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 0, "一个「纯整数占位符」的键都没扫到 —— 判据失效了")
    }

    /// 取出形如 `%@` / `%d` / `%.2f` / `%1$@` 的占位符（保持出现顺序）。
    private static func formatSpecifiers(in text: String) -> [String] {
        let pattern = #"%(?:\d+\$)?[-+ #0]*[\d.]*(?:hh|h|ll|l|L|z|j|t)?[@dioufFeEgGxXscpaA]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }
}
