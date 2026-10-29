import XCTest
@testable import DoyahCore

/// 「关于」页能力描述（主人 2026-10-29 令）的机械判据。
///
/// 盯住三处：**只有亮点**（五条封顶、一条一件事）、**说人话**（不许出现内部编号与内部词）、
/// **和授权对得上**（已含 / 需某版 由能力位判，不靠档位名猜）。
final class LicenseHighlightsTests: XCTestCase {

    // MARK: - 只写亮点

    func testFiveHighlightsInFixedOrder() {
        XCTAssertEqual(LicenseHighlights.all.count, 5, "只写最亮点：五条封顶")
        XCTAssertEqual(LicenseHighlights.all.map(\.titleKey),
                       [.licDoDatabaseTitle, .licDoCodeTitle, .licDoAgentTitle,
                        .licDoNotesTitle, .licDoLinkTitle])
    }

    func testEveryHighlightHasTitleAndOneLineInBothLanguages() {
        for highlight in LicenseHighlights.all {
            for key in [highlight.titleKey, highlight.lineKey] {
                let zh = LocalizedStrings.text(key, language: .simplifiedChinese)
                let en = LocalizedStrings.text(key, language: .english)
                XCTAssertFalse(zh.isEmpty, "缺中文：\(key)")
                XCTAssertFalse(en.isEmpty, "缺英文：\(key)")
                XCTAssertNotEqual(zh, en, "中英必须真的是两份文案：\(key)")
            }
        }
    }

    // MARK: - 说人话

    func testPlainLanguageHasNoInternalCodes() {
        let forbidden = ["FR-", "§", "Q1", "Q2", "能力位", "档位", "Entitlement", "capability"]
        for highlight in LicenseHighlights.all {
            for key in [highlight.titleKey, highlight.lineKey] {
                for language in [AppLanguage.simplifiedChinese, .english] {
                    let text = LocalizedStrings.text(key, language: language)
                    for token in forbidden {
                        XCTAssertFalse(text.contains(token),
                                       "「\(text)」里出现内部用语 \(token)（第 \(key) 条）")
                    }
                }
            }
        }
    }

    func testOneLineStaysShortEnoughToBeRead() {
        for highlight in LicenseHighlights.all {
            let zh = LocalizedStrings.text(highlight.lineKey, language: .simplifiedChinese)
            XCTAssertLessThanOrEqual(zh.count, 60, "一句话太长，没人读：\(zh)")
        }
    }

    // MARK: - 和授权对得上

    func testEditionMatchesItsRequiredCapabilities() {
        for highlight in LicenseHighlights.all {
            XCTAssertFalse(highlight.required.isEmpty)
            let fromEdition = highlight.edition.capabilities
            XCTAssertTrue(fromEdition.isSuperset(of: highlight.required),
                          "\(highlight.edition) 并不包含这条要求的能力")
        }
    }

    func testStandardOnlyHasNotes() {
        let included = LicenseHighlights.all.filter {
            LicenseHighlights.isIncluded($0, in: LicenseEdition.standard.capabilities)
        }
        XCTAssertEqual(included.map(\.titleKey), [.licDoNotesTitle], "标准版只有笔记（AI 采集不在亮点里）")
    }

    func testProHasDatabaseCodeAndAgentButNotNotes() {
        let included = LicenseHighlights.all.filter {
            LicenseHighlights.isIncluded($0, in: LicenseEdition.pro.capabilities)
        }
        XCTAssertEqual(included.map(\.titleKey),
                       [.licDoDatabaseTitle, .licDoCodeTitle, .licDoAgentTitle])
    }

    func testUltraHasEverything() {
        let included = LicenseHighlights.all.filter {
            LicenseHighlights.isIncluded($0, in: LicenseEdition.ultra.capabilities)
        }
        XCTAssertEqual(included.count, LicenseHighlights.all.count)
        for highlight in LicenseHighlights.all {
            XCTAssertNil(LicenseHighlights.upgradeTarget(for: highlight, in: LicenseEdition.ultra.capabilities),
                         "已含的不该再标「需某版」")
        }
    }

    func testUpgradeTargetNamesTheEditionThatUnlocksIt() {
        let notes = LicenseHighlights.all.first { $0.titleKey == .licDoNotesTitle }!
        XCTAssertEqual(LicenseHighlights.upgradeTarget(for: notes, in: LicenseEdition.pro.capabilities),
                       .standard)
        let database = LicenseHighlights.all.first { $0.titleKey == .licDoDatabaseTitle }!
        XCTAssertEqual(LicenseHighlights.upgradeTarget(for: database, in: LicenseEdition.standard.capabilities),
                       .pro)
    }

    // MARK: - 界面真的画了

    func testAboutSheetRendersTheSection() throws {
        let source = try String(contentsOfFile: "App/Views/AboutLicenseSheet.swift", encoding: .utf8)
        XCTAssertTrue(source.contains("capabilitySection"), "关于页必须真把这一段放进 body")
        XCTAssertTrue(source.contains("LicenseHighlights.all"), "条目只从 Core 那份数据来，界面不自写第二份")
        XCTAssertTrue(source.contains("about-capabilities-title"), "要有可定位的锚（判据与读屏共用）")
    }

    // MARK: - 照 App Store 商品页的写法（2026-10-29 主人让我去对照真实商品页）

    func testIntroAndTrustLineExistInBothLanguages() {
        for key in [LKey.licDoIntro, LKey.licDoTrust] {
            let zh = LocalizedStrings.text(key, language: .simplifiedChinese)
            let en = LocalizedStrings.text(key, language: .english)
            XCTAssertFalse(zh.isEmpty)
            XCTAssertFalse(en.isEmpty)
            XCTAssertNotEqual(zh, en)
        }
    }

    func testIntroIsOneShortSentence() {
        let zh = LocalizedStrings.text(.licDoIntro, language: .simplifiedChinese)
        XCTAssertLessThanOrEqual(zh.count, 40, "定位句要短：一句话说清替你干什么")
        XCTAssertLessThanOrEqual(zh.filter { $0 == "。" }.count, 1, "定位句只留一句，不堆句号")
    }

    func testTitlesAreShortNamesNotSentences() {
        for highlight in LicenseHighlights.all {
            let zh = LocalizedStrings.text(highlight.titleKey, language: .simplifiedChinese)
            XCTAssertLessThanOrEqual(zh.count, 10, "名字要短到能当小标题：\(zh)")
            XCTAssertFalse(zh.contains("，"), "名字里不要逗号（那是句子不是名字）")
        }
    }

    func testTrustLineSaysWhereDataGoes() {
        let zh = LocalizedStrings.text(.licDoTrust, language: .simplifiedChinese)
        XCTAssertTrue(zh.contains("本机") || zh.contains("服务器"), "收尾句要说清数据在哪，不喊口号")
    }
}
