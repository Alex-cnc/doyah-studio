//! **外观偏好**（FR-EDIT-26 / 计划 2.8；契约等价物：macOS 侧 `Core/AppearancePreference.swift`
//! 与 `Core/NebulaSkinPreference.swift`）
//!
//! ## 为什么规则要住在领域层
//!
//! 「主题下拉 + 皮肤开关」看着只是界面上的两个控件，但它们的规则**每一件都只有一种正确写法**，
//! 而且都**没法靠肉眼在界面上发现**：
//!
//! 1. **落盘键名就是契约**（`appearance.mode` / `ui.nebulaSkin`）—— 改一个字，老用户的选择当场失效，
//!    而界面看起来只是"又变回默认了"；
//! 2. **未知值回落到「跟随系统」**，不抛错 —— 偏好文件被手改、或版本降级读到新值，
//!    都不该让界面起不来；
//! 3. **皮肤缺省是「开」** —— 新装用户就该看到它；这里有个经典坑：如果按"缺省布尔是 false"读，
//!    缺省值会被**静默改成关**（"新装看不到皮肤"）；
//! 4. **皮肤生效条件 = 主题是星空紫 且 最终是深色 且 开关开** —— 三个条件缺一不可：
//!    少了主题那一半，别的主题会莫名其妙长出星星（走样）；少了开关那一半，用户关不掉。
//!
//! ## 两条轴**正交**
//! 深浅轴（跟随系统 / 总深 / 总浅）× 配色轴（科技蓝 / 豆芽绿 / 玫瑰金 / 星空紫）。
//! 组合起来是 3 × 4 = 12 种外观，但**只有四条规则**（上面那四条），不是一个 12 项的表。

/// 深浅轴（三态）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum AppearanceMode {
    FollowSystem,
    AlwaysDark,
    AlwaysLight,
}

impl AppearanceMode {
    /// 落盘值（**键名与取值都是契约**，别改）。
    pub const fn raw(self) -> &'static str {
        match self {
            AppearanceMode::FollowSystem => "followSystem",
            AppearanceMode::AlwaysDark => "alwaysDark",
            AppearanceMode::AlwaysLight => "alwaysLight",
        }
    }

    /// 从偏好里读回来。**未知值回落到「跟随系统」**，不抛错。
    pub fn resolve(raw: Option<&str>) -> Self {
        match raw.map(str::trim) {
            Some("alwaysDark") => AppearanceMode::AlwaysDark,
            Some("alwaysLight") => AppearanceMode::AlwaysLight,
            _ => AppearanceMode::FollowSystem,
        }
    }

    /// 系统当前是深色时，这一档的**最终结果**是不是深色（纯函数，可单测）。
    pub const fn resolves_to_dark(self, system_is_dark: bool) -> bool {
        match self {
            AppearanceMode::FollowSystem => system_is_dark,
            AppearanceMode::AlwaysDark => true,
            AppearanceMode::AlwaysLight => false,
        }
    }

    /// 落进 DOM 的 `data-theme` 取值：
    /// `None` = **不写这个属性**（让令牌层里那段"系统跟随"的媒体查询生效）。
    ///
    /// 为什么不是"算出深浅再写死"：令牌层同时提供了「显式浅」「显式深」「跟随系统」三块
    /// （`data-theme='dark'` / `data-theme='light'` / `:not([data-theme='light']):not([data-theme='dark'])`），
    /// 跟随系统交给**媒体查询**做，比在脚本里监听系统变化更省事、也不会与令牌层打架。
    pub const fn data_theme(self) -> Option<&'static str> {
        match self {
            AppearanceMode::FollowSystem => None,
            AppearanceMode::AlwaysDark => Some("dark"),
            AppearanceMode::AlwaysLight => Some("light"),
        }
    }
}

/// 配色轴（四个主题；取值与令牌层的 `data-theme-scheme` 一一对应）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ColorScheme {
    TechBlue,
    BeanGreen,
    RoseGold,
    Stardust,
}

impl ColorScheme {
    /// 落盘值 = 令牌层的选择器取值（同一串，别各造一套）。
    pub const fn raw(self) -> &'static str {
        match self {
            ColorScheme::TechBlue => "tech-blue",
            ColorScheme::BeanGreen => "bean-green",
            ColorScheme::RoseGold => "rose-gold",
            ColorScheme::Stardust => "stardust",
        }
    }

    /// 缺省主题 = **星空紫**（契约的 `DesignTheme.fallback`；也是人类主人 2026-10-01 点名要的那一档）。
    pub const fn default_scheme() -> Self {
        ColorScheme::Stardust
    }

    /// 未知值回落到缺省主题。
    pub fn resolve(raw: Option<&str>) -> Self {
        match raw.map(str::trim) {
            Some("tech-blue") => ColorScheme::TechBlue,
            Some("bean-green") => ColorScheme::BeanGreen,
            Some("rose-gold") => ColorScheme::RoseGold,
            Some("stardust") => ColorScheme::Stardust,
            _ => ColorScheme::default_scheme(),
        }
    }
}

/// 一份完整的外观偏好。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Appearance {
    /// 落盘键 `appearance.mode`
    pub mode: AppearanceMode,
    /// 落盘键 `appearance.scheme`（配色轴；与深浅轴**正交**）
    pub scheme: ColorScheme,
    /// 落盘键 `ui.nebulaSkin` —— **缺省开**（缺省值在 `Default` 实现里）
    pub nebula_skin: bool,
}

impl Default for Appearance {
    fn default() -> Self {
        Self {
            mode: AppearanceMode::FollowSystem,
            scheme: ColorScheme::default_scheme(),
            // **缺省开**：新装用户就该看到这层质感（契约原话）
            nebula_skin: true,
        }
    }
}

impl Appearance {
    /// 从**可能缺项、可能有未知值**的落盘数据还原（缺项用缺省，未知值按规则回落）。
    pub fn resolve(
        mode_raw: Option<&str>,
        scheme_raw: Option<&str>,
        nebula_skin_raw: Option<bool>,
    ) -> Self {
        Self {
            mode: AppearanceMode::resolve(mode_raw),
            scheme: ColorScheme::resolve(scheme_raw),
            // `None`（从未设过）⇒ **缺省开**；显式 `false` 才是关
            nebula_skin: nebula_skin_raw.unwrap_or(true),
        }
    }

    /// 皮肤现在**生不生效**（三个条件缺一不可）。
    pub fn nebula_active(&self, system_is_dark: bool) -> bool {
        self.nebula_skin
            && self.scheme == ColorScheme::Stardust
            && self.mode.resolves_to_dark(system_is_dark)
    }

    /// 给界面的一整套 `data-*` 取值（**只在这里算**，界面照着设）。
    pub fn to_dom(&self, system_is_dark: bool) -> DomAppearance {
        DomAppearance {
            data_theme: self.mode.data_theme(),
            data_scheme: self.scheme.raw(),
            nebula: self.nebula_active(system_is_dark),
            is_dark: self.mode.resolves_to_dark(system_is_dark),
        }
    }
}

/// 落到 DOM 上的那几项（`data_theme` 为 `None` = **不写属性**，交给媒体查询）。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DomAppearance {
    pub data_theme: Option<&'static str>,
    pub data_scheme: &'static str,
    pub nebula: bool,
    pub is_dark: bool,
}

/// 落盘键（**键名是契约**：改一个字，老用户的选择当场失效）。
pub mod keys {
    pub const MODE: &str = "appearance.mode";
    pub const SCHEME: &str = "appearance.scheme";
    pub const NEBULA_SKIN: &str = "ui.nebulaSkin";
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mode_three_states_and_unknown_falls_back_to_follow_system() {
        assert!(AppearanceMode::FollowSystem.resolves_to_dark(true));
        assert!(!AppearanceMode::FollowSystem.resolves_to_dark(false));
        assert!(AppearanceMode::AlwaysDark.resolves_to_dark(false), "总深：系统浅也深");
        assert!(!AppearanceMode::AlwaysLight.resolves_to_dark(true), "总浅：系统深也浅");
        // 未知值 / 空值 / 大小写不合 ⇒ 跟随系统（**不抛错**：偏好文件被手改不该让界面起不来）
        assert_eq!(AppearanceMode::resolve(None), AppearanceMode::FollowSystem);
        assert_eq!(AppearanceMode::resolve(Some("alwaysDark")), AppearanceMode::AlwaysDark);
        assert_eq!(AppearanceMode::resolve(Some("  alwaysLight ")), AppearanceMode::AlwaysLight);
        assert_eq!(AppearanceMode::resolve(Some("nonsense")), AppearanceMode::FollowSystem);
        assert_eq!(AppearanceMode::resolve(Some("")), AppearanceMode::FollowSystem);
    }

    #[test]
    fn data_theme_is_absent_for_follow_system_only() {
        // 跟随系统 ⇒ **不写属性**（让令牌层里"系统跟随"那段媒体查询生效）
        assert_eq!(AppearanceMode::FollowSystem.data_theme(), None);
        assert_eq!(AppearanceMode::AlwaysDark.data_theme(), Some("dark"));
        assert_eq!(AppearanceMode::AlwaysLight.data_theme(), Some("light"));
    }

    #[test]
    fn scheme_values_match_the_token_selectors_and_default_is_stardust() {
        // 落盘值必须与令牌层的 `data-theme-scheme` 取值逐字一致（别各造一套）
        assert_eq!(ColorScheme::TechBlue.raw(), "tech-blue");
        assert_eq!(ColorScheme::BeanGreen.raw(), "bean-green");
        assert_eq!(ColorScheme::RoseGold.raw(), "rose-gold");
        assert_eq!(ColorScheme::Stardust.raw(), "stardust");
        assert_eq!(ColorScheme::default_scheme(), ColorScheme::Stardust);
        // 未知值回落缺省主题
        assert_eq!(ColorScheme::resolve(Some("nope")), ColorScheme::Stardust);
        assert_eq!(ColorScheme::resolve(None), ColorScheme::Stardust);
        assert_eq!(ColorScheme::resolve(Some("rose-gold")), ColorScheme::RoseGold);
    }

    #[test]
    fn nebula_skin_defaults_to_on_and_never_gets_silently_turned_off() {
        // **缺省开**：从来没设过（None）⇒ 开
        let fresh = Appearance::resolve(None, None, None);
        assert!(fresh.nebula_skin, "新装用户就该看到皮肤（经典坑：按缺省 false 读就变成关）");
        assert_eq!(fresh.mode, AppearanceMode::FollowSystem);
        assert_eq!(fresh.scheme, ColorScheme::Stardust);
        // 显式关才是关
        assert!(!Appearance::resolve(None, None, Some(false)).nebula_skin);
        // 显式开也是开
        assert!(Appearance::resolve(None, None, Some(true)).nebula_skin);
    }

    #[test]
    fn nebula_requires_all_three_conditions() {
        let dark = true;
        let light = false;
        // ① 缺省（星空紫 + 跟随系统 + 开）：系统深 ⇒ 生效
        assert!(Appearance::default().nebula_active(dark));
        assert!(!Appearance::default().nebula_active(light), "系统浅时不该有星星");
        // ② 换成别的配色 ⇒ 不生效（**别的主题不该长出星星**）
        let mut other = Appearance::default();
        other.scheme = ColorScheme::TechBlue;
        assert!(!other.nebula_active(dark));
        // ③ 开关关掉 ⇒ 不生效（**用户关得掉**）
        let mut off = Appearance::default();
        off.nebula_skin = false;
        assert!(!off.nebula_active(dark));
        // ④ 总浅 ⇒ 不生效（深色档才谈得上星云）
        let mut always_light = Appearance::default();
        always_light.mode = AppearanceMode::AlwaysLight;
        assert!(!always_light.nebula_active(light));
        // ⑤ 总深 + 星空紫 + 开 ⇒ 生效（系统是浅色也生效）
        let mut always_dark = Appearance::default();
        always_dark.mode = AppearanceMode::AlwaysDark;
        assert!(always_dark.nebula_active(light));
    }

    #[test]
    fn dom_payload_carries_everything_the_view_needs() {
        let appearance = Appearance::resolve(Some("alwaysDark"), Some("rose-gold"), Some(false));
        let dom = appearance.to_dom(false);
        assert_eq!(dom.data_theme, Some("dark"));
        assert_eq!(dom.data_scheme, "rose-gold");
        assert!(dom.is_dark);
        assert!(!dom.nebula);
        // 跟随系统时 data_theme 是 None（界面据此**不设**那个属性，而不是设成空串）
        let follow = Appearance::resolve(None, None, None).to_dom(true);
        assert_eq!(follow.data_theme, None);
        assert!(follow.nebula, "缺省：星空紫 + 跟随系统 + 系统深 ⇒ 皮肤生效");
    }

    #[test]
    fn storage_keys_are_the_contract_and_round_trip() {
        assert_eq!(keys::MODE, "appearance.mode");
        assert_eq!(keys::SCHEME, "appearance.scheme");
        assert_eq!(keys::NEBULA_SKIN, "ui.nebulaSkin");
        let appearance = Appearance::resolve(Some("alwaysLight"), Some("bean-green"), Some(true));
        let json = serde_json::to_string(&appearance).unwrap();
        assert!(json.contains("\"nebulaSkin\""), "{json}");
        assert!(json.contains("\"alwaysLight\""), "{json}");
        let back: Appearance = serde_json::from_str(&json).unwrap();
        assert_eq!(back, appearance);
    }
}
