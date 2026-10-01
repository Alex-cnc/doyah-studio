import Foundation

/// 星空紫「星云皮肤」的**偏好规则**（开关的键、缺省值、读法、生效条件）。
///
/// ## 为什么这条规则住在 Core
///
/// 「皮肤开关」看起来只是 `App` 里的一个 `@Published`，但它的规则有四件事，
/// 每一件都**只有一种正确写法**，而且没有一件能被 App 侧的单测钉住：
///
///  1. **落盘键**（`ui.nebulaSkin`）—— 键名就是契约：改一个字，老用户的选择当场失效，
///     而界面看起来只是"皮肤又变成默认打开了"；
///  2. **缺省值 = 开** —— 需求提出者 2026-10-01 明确要这层质感（原话「我说的可能是皮肤更准确」），
///     新装用户就该直接看到它；
///  3. **读法必须是 `object(forKey:) as? Bool ?? 缺省`** —— `bool(forKey:)` 对「从未设过」
///     也返回 `false` ⇒ 缺省值会被静默改成关（"新装看不到皮肤"的经典坑，`DesignThemeManager`
///     的初始化注释里记着同一个理由）；
///  4. **生效条件 = 主题是星空紫 且 开关开** —— 两个条件缺一不可：少了主题那一半，
///     别的主题会莫名其妙长出星星（走样）；少了开关那一半，用户关不掉。
///
/// 与 `AppearancePreference` 同一个理由（那份也住在 Core）：**一份实现，两个消费者** ——
/// 现在是 `App/DesignThemeManager` 与 `App/Views/NebulaBackground`；将来星空紫要跟着
/// 令牌表走到别的端时，规则不用再抄一遍。住在 Core 还顺带让 ②③ 变成**能跑的单测**
/// （`Tests/NebulaSkinPreferenceTests.swift`，注入 `UserDefaults(suiteName:)` 即可，"重开"这一态
/// 不再需要重启进程）。
public enum NebulaSkinPreference {

    /// 落盘键（与 `DesignTheme.Storage.key` 同一前缀，便于一起清理）。
    public static let key = "ui.nebulaSkin"

    /// 缺省值：**开**。
    public static let defaultEnabled = true

    /// 从偏好里读回开关。
    ///
    /// **读法就是规格**：先 `object(forKey:)` 拿到"有没有设过"，再退回 `defaultEnabled`。
    /// 不要改成 `bool(forKey:)` —— 它对「从未设过」返回 `false`，等于把缺省值改成关。
    public static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultEnabled
    }

    /// **视觉生效条件**：星云只在这一个组合下画。
    ///
    /// 这个函数是那个组合的**唯一出处** —— `NebulaBackground` 的 `body` 调它，
    /// 门禁（`Scripts/check-design-themes.py` 判据 I）也判它。写在两处会让
    /// "皮肤偷偷跑到别的主题上"变成一次没人发现的复制粘贴。
    public static func paintsNebula(theme: DesignTheme, isSkinEnabled: Bool) -> Bool {
        theme == .stardust && isSkinEnabled
    }
}
