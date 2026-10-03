//! 标题栏居中搜索栏的**宽度纯函数**（2.0 出口里点名的等价物）
//!
//! 对侧等价物：macOS `Core/TitleBarSearchLayout.swift`（`L-141` 那笔的产物）。本侧按**同一行为**
//! 重建，不照抄实现。
//!
//! 四条口径（照抄契约、逐条可判）：
//! ① **居中 ⇒ 两侧对称让位**：搜索栏居中，所以它变宽时**左右各让出一半**；
//! ② **两档**：理想宽 360 / 最小宽 180（与对侧同值）；
//! ③ **连最小都放不下 ⇒ 收成 0**：整条不显示（**不是**"挤成一条看不见的缝"），
//!    回车入口仍在快捷键与命令面板里；
//! ④ **两条不变量**：任何窗口宽度下**都不侵入标题带**；**不做"既遮标题又不能用"那一档**。
//!
//! 为什么要有纯函数而不是让 CSS 自己算：居中让位这件事一旦交给"系统件 + 弹性布局"，
//! 就会出现"窄窗时搜索框压住标题"这种只有截图才能发现的问题（对侧内测清单甲1 就是这么来的）。

use serde::{Deserialize, Serialize};

/// 理想宽度（窗口够宽时就用它）。
pub const IDEAL_WIDTH: f64 = 360.0;
/// 最小可用宽度（再窄就没法用，宁可收起来）。
pub const MIN_WIDTH: f64 = 180.0;
/// 标题带两侧要留给标题与右侧控件的最小空间（**这是"不侵入"的物质基础**）。
pub const SIDE_RESERVE: f64 = 240.0;
/// 左右各留的内边距（让位从这两条边开始算）。
pub const GUTTER: f64 = 16.0;

/// 一次布局计算的结果。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SearchLayout {
    /// 搜索栏宽度（0 = 整条不显示）
    pub width: f64,
    /// 是否显示
    pub visible: bool,
    /// 左右各让出多少（居中 ⇒ 两侧同值）
    pub side_yield: f64,
    /// 是否已经收到最小档（界面据此提示"窗口再窄就收起来了"）
    pub at_minimum: bool,
}

/// 按窗口宽度算搜索栏布局。
///
/// **几何要说清**（第一次写错过，两条不变量用例当场抓到）：
/// 搜索栏居中，标题与右侧控件分列**它让出的那两条边**里。所以窗口宽度要同时喂三处：
/// `侧栏预留（左）+ 自身（中）+ 侧栏预留（右）+ 两条内边距`。
/// ⇒ 自身可用宽 = 窗口宽 − 两侧预留 − 两条内边距（**预留要减两次**）。
/// 写成"只减一次预留"会让窄窗下搜索栏把标题挤到负空间（就是"侵入标题带"）。
pub fn layout(window_width: f64) -> SearchLayout {
    // 非法宽度（NaN / 负数）按"没有任何空间"处理 —— 不 panic、不返回负数
    if !window_width.is_finite() || window_width <= 0.0 {
        return SearchLayout { width: 0.0, visible: false, side_yield: 0.0, at_minimum: false };
    }
    let available = window_width - SIDE_RESERVE * 2.0 - GUTTER * 2.0;
    if available < MIN_WIDTH {
        // **连最小都放不下 ⇒ 收成 0**：整条不显示，而不是显示一条挤扁的
        return SearchLayout { width: 0.0, visible: false, side_yield: 0.0, at_minimum: false };
    }
    let width = available.min(IDEAL_WIDTH);
    SearchLayout {
        width,
        visible: true,
        // 居中 ⇒ 两侧对称让位：各让出自己的预留与内边距（**与自身宽度无关**）
        side_yield: SIDE_RESERVE + GUTTER,
        at_minimum: width < IDEAL_WIDTH,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_wide_window_gets_the_ideal_width() {
        let l = layout(1920.0);
        assert!(l.visible);
        assert_eq!(l.width, IDEAL_WIDTH);
        assert!(!l.at_minimum, "宽窗应当给理想宽，不算收到最小档");
    }

    #[test]
    fn yielding_is_symmetric_because_the_bar_is_centred() {
        let l = layout(1920.0);
        // 居中 ⇒ 各让一半（这是契约里的"两侧对称让位"）
        assert_eq!(l.side_yield, SIDE_RESERVE + GUTTER);
        let narrow = layout(700.0);
        assert!(narrow.visible);
        assert_eq!(narrow.side_yield, SIDE_RESERVE + GUTTER, "任何宽度下让位都对称且与自身宽度无关");
    }

    #[test]
    fn the_width_shrinks_before_it_disappears() {
        let l = layout(700.0);
        assert!(l.visible, "700 仍够放最小档：available = 700 - 480 - 32 = 188");
        assert!(l.width >= MIN_WIDTH);
        assert!(l.width < IDEAL_WIDTH, "窄窗时应当已经缩过：{}", l.width);
        assert!(l.at_minimum);
    }

    #[test]
    fn when_even_the_minimum_does_not_fit_it_collapses_to_zero() {
        // 按口径 ③：**整条不显示**，不是"挤成一条缝"
        // available = 300 - 480 - 32 < 0 ⇒ 连最小都放不下
        let l = layout(300.0);
        assert!(!l.visible, "连最小都放不下就该收起来");
        assert_eq!(l.width, 0.0);
        assert_eq!(l.side_yield, 0.0);
    }

    #[test]
    fn the_never_invade_the_title_band_invariant_holds_at_every_width() {
        // 不变量①：任何窗口宽度下，搜索栏 + 它让出的两侧都不超过窗口
        let mut w = 1.0;
        while w <= 3000.0 {
            let l = layout(w);
            if l.visible {
                // 占用 = 让位（两侧）+ 自身宽 = 2 * (width/2) + width = 2 * width
                let occupied = l.side_yield * 2.0 + l.width;
                assert!(
                    occupied <= w,
                    "宽度 {w} 下占用 {occupied} 超过了窗口 —— 会侵入标题带"
                );
                assert!(
                    w - occupied >= 0.0,
                    "留给标题与右侧控件的空间不许为负（宽度 {w}）"
                );
            } else {
                assert_eq!(l.width, 0.0, "不显示时宽度必须是 0（不做'既遮标题又不能用'那一档）");
            }
            w += 7.0;
        }
    }

    #[test]
    fn there_is_no_width_where_it_is_shown_but_unusable() {
        // 不变量②：**要么不显示，要么至少 MIN_WIDTH** —— 不存在"显示着但没法用"的中间档
        let mut w = 1.0;
        while w <= 3000.0 {
            let l = layout(w);
            if l.visible {
                assert!(l.width >= MIN_WIDTH, "宽度 {w} 下显示了但只有 {} —— 这正是要避免的那一档", l.width);
            }
            w += 3.0;
        }
    }

    #[test]
    fn illegal_widths_are_handled_without_panicking() {
        for bad in [0.0, -100.0, f64::NAN, f64::INFINITY] {
            let l = layout(bad);
            assert!(!l.visible, "非法宽度 {bad} 应当按'没有空间'处理");
            assert_eq!(l.width, 0.0);
        }
    }
}
