//! 标题栏居中搜索栏的**宽度纯函数**（2.0 出口里点名的等价物；窗口 L-141 / 内测甲1）
//!
//! 对侧等价物：macOS `Core/TitleBarSearchLayout.swift`。本侧按**同一行为**重建，不照抄实现。
//!
//! ## 这一版为什么要重写（2026-10-03）
//! 原先本文件用的是"**两侧各留固定 240**"的保守算法，而界面上跑的是
//! `App/src/shell/titleBarSearch.ts` 里"**按标题实际宽度算**"的那一套 ——
//! **同一件事两处实现、且两处算出来的数不一样**（同事的收口审计点出的正是这条）。
//! 现在把这里改成**与界面完全同一套算法**（同一组常量、同一个几何模型）：
//! Rust 侧是**口径的唯一出处与判据所在**；界面侧保留同样算法的 TS 实现（resize 要同步算，
//! 不能每次去问 Rust），但**靠一例"常数与口径对齐"的判据互相钉住**。
//!
//! ## 几何模型（与 TS 侧逐字一致）
//! 搜索栏**居中**，标题占它左边那一段（标题栏左端还有窗口按钮 —— `LEADING_INSET`）。
//! 居中意味着**两侧对称让位**：给左边让出多少，右边也就让出同样多。于是"不长到标题带上"的条件是
//!
//! ```text
//! 搜索栏宽度 ≤ 窗口宽度 − 2 ×（LEADING_INSET + 标题宽度 + TITLE_GAP）
//! ```
//!
//! ## 两条不变量（判据就是它们，**逐宽度扫描**）
//! ① **标题永远完整可见**（任何窗口宽度下搜索栏都不侵入标题带）；
//! ② **不挤成一条缝** —— 可用宽度连 `MIN_WIDTH` 都不到时，搜索栏**收成 0**（这一档不显示），
//!    不做"宽 40px 的搜索框"这种既不显示标题、也不能用的东西。

use serde::{Deserialize, Serialize};

/// 理想宽度：够放一句检索词，也不至于霸占标题左侧那一块。
pub const IDEAL_WIDTH: f64 = 360.0;
/// 能让搜索栏**真的可用**的最小宽度；低于它就不该挤在那里（不变量 ②）。
pub const MIN_WIDTH: f64 = 180.0;
/// 搜索栏与标题之间**必须留出的空档**。
pub const TITLE_GAP: f64 = 24.0;
/// 标题左端之外还要占掉的固定 chrome（窗口按钮 + 标题栏左内边距）。
pub const LEADING_INSET: f64 = 90.0;
/// 标题宽度的估算单位：中文按 2 个单位、其余按 1 个（字号由令牌给，这里只给比例）。
pub const TITLE_CHAR_UNIT_PX: f64 = 9.0;

/// 一次布局计算的结果。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SearchLayout {
    /// 搜索栏宽度（0 = 整条不显示）
    pub width: f64,
    /// 是否显示
    pub visible: bool,
    /// **左右各让出多少**（居中 ⇒ 两侧同值）
    pub side_yield: f64,
    /// 是否已经收到最小档（界面据此提示"窗口再窄就收起来了"）
    pub at_minimum: bool,
}

/// 标题宽度估算（与 TS 侧 `estimateTitleWidth` 同口径）。
///
/// 中文与全角标点（`U+3000..=U+9FFF` / `U+FF00..=U+FFEF`）按 2 个单位，其余按 1 个。
pub fn estimate_title_width(title: &str) -> f64 {
    let mut units = 0.0;
    for ch in title.chars() {
        let code = ch as u32;
        let wide = (0x3000..=0x9fff).contains(&code) || (0xff00..=0xffef).contains(&code);
        units += if wide { 2.0 } else { 1.0 };
    }
    units * TITLE_CHAR_UNIT_PX
}

/// 这一档**留给搜索栏**的宽度（小于 0 按 0 计 —— 不猜、不取绝对值）。
pub fn available_width(window_width: f64, title_width: f64) -> f64 {
    if !window_width.is_finite() || !title_width.is_finite() {
        return 0.0;
    }
    let band = LEADING_INSET + title_width.max(0.0) + TITLE_GAP;
    (window_width - 2.0 * band).max(0.0)
}

/// 搜索栏宽度：`0` = 这一档放不下、整条不显示（此时只剩标题与快捷键入口）。
pub fn search_field_width(window_width: f64, title_width: f64) -> f64 {
    let available = available_width(window_width, title_width);
    if available < MIN_WIDTH {
        return 0.0;
    }
    available.min(IDEAL_WIDTH)
}

/// 给定一个宽度摆上去，会不会**压到标题带**（不变量 ① 的机械形式）。
pub fn fits_without_covering_title(window_width: f64, title_width: f64, field_width: f64) -> bool {
    if !field_width.is_finite() {
        return false;
    }
    field_width.max(0.0) <= available_width(window_width, title_width)
}

/// 按窗口宽度与标题宽度算搜索栏布局（**界面就照它摆**）。
pub fn layout(window_width: f64, title_width: f64) -> SearchLayout {
    let width = search_field_width(window_width, title_width);
    if width <= 0.0 {
        // 连最小都放不下 ⇒ **整条不显示**，而不是挤成一条看不见的缝
        return SearchLayout { width: 0.0, visible: false, side_yield: 0.0, at_minimum: false };
    }
    // 居中 ⇒ 两侧对称让位：各让出"标题带 + 空档"（**与自身宽度无关**）
    SearchLayout {
        width,
        visible: true,
        side_yield: LEADING_INSET + title_width.max(0.0) + TITLE_GAP,
        at_minimum: width < IDEAL_WIDTH,
    }
}

/// 便捷入口：标题文本进来，自己估宽再算（界面常用这条）。
pub fn layout_for_title(window_width: f64, title: &str) -> SearchLayout {
    layout(window_width, estimate_title_width(title))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 本侧标题的典型文本（估宽用）。
    const SAMPLE_TITLE: &str = "Doyah Studio - 工作区";

    #[test]
    fn title_width_estimation_counts_cjk_as_two_units() {
        // 纯 ASCII：一字一单位
        assert_eq!(estimate_title_width("abc"), 3.0 * TITLE_CHAR_UNIT_PX);
        // 中文：一字两单位
        assert_eq!(estimate_title_width("工作区"), 3.0 * 2.0 * TITLE_CHAR_UNIT_PX);
        // 混排：ASCII 1 + 中文 2
        assert_eq!(estimate_title_width("a中"), 3.0 * TITLE_CHAR_UNIT_PX);
        assert_eq!(estimate_title_width(""), 0.0);
    }

    #[test]
    fn a_wide_window_gets_the_ideal_width() {
        let l = layout_for_title(1920.0, SAMPLE_TITLE);
        assert!(l.visible);
        assert_eq!(l.width, IDEAL_WIDTH);
        assert!(!l.at_minimum, "宽窗应当给理想宽，不算收到最小档");
    }

    #[test]
    fn the_width_shrinks_before_it_disappears() {
        // 让"可用宽"落在最小与理想之间：可用 = W − 2×(90 + 标题宽 + 24)
        let title = estimate_title_width(SAMPLE_TITLE);
        let window = 2.0 * (LEADING_INSET + title + TITLE_GAP) + (MIN_WIDTH + 20.0);
        let l = layout(window, title);
        assert!(l.visible, "这一档应当还看得见");
        assert!(l.width >= MIN_WIDTH, "显示了就不能小于最小宽");
        assert!(l.width < IDEAL_WIDTH, "这一档应当已经缩过：{}", l.width);
        assert!(l.at_minimum);
    }

    #[test]
    fn when_even_the_minimum_does_not_fit_it_collapses_to_zero() {
        // 按口径 ②：**整条不显示**，不是"挤成一条缝"
        let title = estimate_title_width(SAMPLE_TITLE);
        let window = 2.0 * (LEADING_INSET + title + TITLE_GAP) + (MIN_WIDTH - 1.0);
        let l = layout(window, title);
        assert!(!l.visible, "连最小都放不下就该收起来");
        assert_eq!(l.width, 0.0);
        assert_eq!(l.side_yield, 0.0);
    }

    #[test]
    fn yielding_is_symmetric_because_the_bar_is_centred() {
        let title = estimate_title_width(SAMPLE_TITLE);
        let expected = LEADING_INSET + title + TITLE_GAP;
        // 两种宽度下让位都等于"标题带 + 空档"（与自身宽度无关）
        for window in [1920.0, 1200.0, 700.0] {
            let l = layout(window, title);
            if l.visible {
                assert_eq!(l.side_yield, expected, "宽度 {window} 下让位应当对称且与自身宽度无关");
            }
        }
    }

    #[test]
    fn the_never_invade_the_title_band_invariant_holds_at_every_width() {
        // 不变量①：**逐宽度扫描** —— 任何窗口宽度下搜索栏都不侵入标题带
        let title = estimate_title_width(SAMPLE_TITLE);
        let mut w = 1.0;
        while w <= 4000.0 {
            let l = layout(w, title);
            if l.visible {
                assert!(
                    fits_without_covering_title(w, title, l.width),
                    "宽度 {w} 下宽度 {} 会压到标题带",
                    l.width
                );
                // 占用 = 两侧让位 + 自身宽，不许超过窗口
                let occupied = l.side_yield * 2.0 + l.width;
                assert!(occupied <= w, "宽度 {w} 下占用 {occupied} 超过了窗口");
            } else {
                assert_eq!(l.width, 0.0, "不显示时宽度必须是 0（不做'既遮标题又不能用'那一档）");
            }
            w += 7.0;
        }
    }

    #[test]
    fn there_is_no_width_where_it_is_shown_but_unusable() {
        // 不变量②：**要么不显示，要么至少 MIN_WIDTH** —— 不存在"显示着但没法用"的中间档
        let title = estimate_title_width(SAMPLE_TITLE);
        let mut w = 1.0;
        while w <= 4000.0 {
            let l = layout(w, title);
            if l.visible {
                assert!(l.width >= MIN_WIDTH, "宽度 {w} 下显示了但只有 {} —— 正是要避免的那一档", l.width);
            }
            w += 3.0;
        }
    }

    #[test]
    fn illegal_widths_are_handled_without_panicking() {
        let title = estimate_title_width(SAMPLE_TITLE);
        for bad in [0.0, -100.0, f64::NAN, f64::INFINITY] {
            let l = layout(bad, title);
            assert!(!l.visible, "非法宽度 {bad} 应当按'没有空间'处理");
            assert_eq!(l.width, 0.0);
        }
        // 标题宽非法（NaN）也按 0 处理，不 panic
        assert_eq!(available_width(1920.0, f64::NAN), 0.0);
        assert!(!fits_without_covering_title(1920.0, 100.0, f64::NAN));
    }

    #[test]
    fn a_longer_title_yields_more_space_to_it() {
        // 标题越长，留给搜索栏的越少 —— 这是"按标题实际宽度算"的直接后果
        let short = layout(1200.0, estimate_title_width("Doyah Studio"));
        let long = layout(1200.0, estimate_title_width("Doyah Studio - 工作区 - 一个很长的标题"));
        assert!(long.side_yield > short.side_yield, "长标题应当让出更多");
        assert!(long.width <= short.width, "长标题下搜索栏不该更宽");
    }
}
