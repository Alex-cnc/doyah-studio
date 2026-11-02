import Foundation

/// **「版本 + 授权状态」那一行**（`FR-STD-ALL-LIC-002` / `FR-STD-WS-LIC-001`）。
///
/// 为什么要有这一个类型：主人 2026-11-02 前的口径是「授权状态与版本号在 **Home 与帮助**里能查到」
/// —— 两处各写一遍必然漂（一处改了档位名、另一处还是旧的；一处不写原因、另一处写了）。
/// 所以这里只留**一个拼装函数**，Home、帮助面板、以及「版本与许可证」页的标题行都调它。
///
/// 三件事一句话说完，顺序固定：
/// `Doyah Studio 0.6.0 · Ultra · 许可证有效`
///   ① 产品名（`.appBrand`，中英同值）
///   ② 版本号（界面传 `CFBundleShortVersionString`；CLI 传自己那一版）
///   ③ 档位名（`LicensePresentation.displayNameKey`，跟着语言变）
///   ④ 依据（`LicenseLoader.summary` 已经会区分「没放 / 坏了 / 到期 / 签名不对」）
///
/// **语言由调用方给**（Core 里不许按当前语言取串，见 R-45 / 队列 L-65）。
public enum LicenseStatusLine {

    /// 拼这一行。`summary` 传 `LicenseLoader.summary(for:language:)` 的结果 ——
    /// 那已经是「为什么是这一档」的人话，这里不重写一遍（两套说辞必然对不上）。
    public static func text(
        version: String,
        entitlements: LicenseEntitlements,
        summary: String,
        language: AppLanguage
    ) -> String {
        let brand = LocalizedStrings.text(.appBrand, language: language)
        let edition = LocalizedStrings.text(
            LicensePresentation.displayNameKey(of: entitlements.edition),
            language: language
        )
        return [brand + " " + version, edition, summary]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// 便捷入口：直接从装载结果拼（Home / 帮助都用这一条，少一处抄错的机会）。
    public static func text(
        version: String,
        load: LicenseLoader.LoadResult,
        language: AppLanguage
    ) -> String {
        text(
            version: version,
            entitlements: load.entitlements,
            summary: LicenseLoader.summary(for: load, language: language),
            language: language
        )
    }
}
