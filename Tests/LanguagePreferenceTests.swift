import XCTest
@testable import DoyahCore

/// `NFR-ALL-GATE-LANG-001` ③④ / `NFR-ALL-GATE-LANG-003` ①② 的机器面：
/// **「用户选过就按用户选的」「没选过按系统档」「重启后仍是同一档」**。
///
/// 为什么把这三件事钉在 Core 的纯函数上，而不是去点设置面板：
/// 面板点一遍得到的是「这一台机器这一次」的读数，换台机器就没有了；而这三条要求的
/// 本质是**解析规则**（存的值优先、坏值退化、键只有一处），规则判不住的话，面板点绿也没意义。
/// 面板那一层另有判据：`Scripts/check-effective-language.py`（语言来源只有一个入口）
/// 与 `Scripts/check-menu-language.py`（真启动读菜单栏原样）。
final class LanguagePreferenceTests: XCTestCase {

    /// ③ 用户在设置里改过语言后按用户选择（覆盖默认）。两档都要成立 ——
    /// 只判一档的话，「恒返回系统档」这种退化实现也能过。
    func testStoredChoiceOverridesSystemDefault() {
        XCTAssertEqual(
            LanguagePreference.resolve(stored: AppLanguage.english.rawValue,
                                       systemDefault: .simplifiedChinese),
            .english
        )
        XCTAssertEqual(
            LanguagePreference.resolve(stored: AppLanguage.simplifiedChinese.rawValue,
                                       systemDefault: .english),
            .simplifiedChinese
        )
    }

    /// ① 没选过（键不存在）⇒ 跟随系统档。
    /// 两种系统档各判一次：这就是「默认」这条口径的全部内容，只判中文会让「恒中文」的实现过关。
    func testNoStoredChoiceFollowsSystemDefault() {
        XCTAssertEqual(LanguagePreference.resolve(stored: nil, systemDefault: .simplifiedChinese), .simplifiedChinese)
        XCTAssertEqual(LanguagePreference.resolve(stored: nil, systemDefault: .english), .english)
    }

    /// 坏值（历史遗留 / 手改过的 plist）⇒ 退到系统档，**不锁死**在某一档、也不崩。
    func testUnreadableStoredValueFallsBackToSystemDefault() {
        XCTAssertEqual(LanguagePreference.resolve(stored: "", systemDefault: .simplifiedChinese), .simplifiedChinese)
        XCTAssertEqual(LanguagePreference.resolve(stored: "zh-CN", systemDefault: .english), .english)
    }

    /// ④ 重启后保持 = 写进去的值能被同一个键读回来。
    ///
    /// 这里走**真 `UserDefaults`**（独立 suite，不污染用户的那一份）：`set` 之后重新读，
    /// 读数必须与写入档一致；顺带钉住「键就是 `app.language`」—— 键改名而两处不同步，
    /// 就是「面板里改了、重启又变回去」那一类缺陷的形状。
    func testStoredChoiceRoundTripsThroughTheSameKey() throws {
        XCTAssertEqual(LanguagePreference.storageKey, "app.language")
        let suiteName = "doyah.tests.language-preference"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(AppLanguage.english.rawValue, forKey: LanguagePreference.storageKey)
        let readBack = LanguagePreference.resolve(
            stored: defaults.string(forKey: LanguagePreference.storageKey),
            systemDefault: .simplifiedChinese
        )
        XCTAssertEqual(readBack, .english, "写进去的值读回来必须是同一档（重启保持的那条机器形态）")
    }

    /// 空跑防护：`AppLanguage` 只剩一档时上面几条会「怎么判都过」——
    /// 语言表的两档都必须还在（盘上删一档，这里当场红）。
    func testBothLanguagesStillExist() {
        XCTAssertEqual(Set(AppLanguage.allCases.map(\.rawValue)), ["zh-Hans", "en"])
        XCTAssertEqual(AppLanguage.simplifiedChinese.displayName, "简体中文")
    }
}
