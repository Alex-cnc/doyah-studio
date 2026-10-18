//! **编辑器字体偏好**（FR-EDIT-26 的字体面；契约等价物：macOS 侧 `Core/FontPreferences.swift`）
//!
//! ## 为什么这些规则必须住在领域层
//!
//! 「换个字体、把字号调大一档」看着是界面上的两个控件，但它们的规则**每一件都只有一种正确写法**，
//! 而且错法都不会报错：
//!
//! 1. **字号要夹取**（9~20）。落盘文件被手改、或版本降级读到 `200`，界面会直接崩掉排版；
//!    夹取而不是拒绝 —— 与 macOS 侧同口径（`FontPreferences` 的 `clamped`）。
//! 2. **空串 = 未选**（回系统等宽），不是「一个叫空串的族」。用户把输入框清空再点「应用」，
//!    意思就是「别用我指定的族」，把它当成一个族名会去查一个永远不存在的字体。
//! 3. **族名要按 CSS 字符串转义**：族名里带引号（`Foo "Bar"`）时若不转义，`font-family` 当场被
//!    截断成两段 —— 用户看到的是「字体没生效」，而代码里一切正常。**同时挡掉能闭合/注入的值**
//!    （`;` `{` `}` 尖括号与控制字符）：这个值最终会落进 `--ds-editor-font-family` 这个 CSS 变量，
//!    而变量的值会被当 CSS 解析。
//! 4. **缺省字号 = 13px**：`--ds-font-caption-size`（11px）是**说明文字**的量级，拿来当代码字号
//!    偏小；13px 是这一档「看得清 + 一屏够行」的取值，写在一处，界面不自己写死。
//!
//! 「这个族这台机器上有没有」**不在本模块判**：Windows 上要枚举字体得读注册表 / `Fonts` 目录，
//! 而本领域层零第三方依赖；真判据在界面侧用 canvas 实测字宽（见 `App/src/shell/editorFont.ts`），
//! 判出来「没装」时**如实说**、不静默装作选好了（与 macOS 的三档判定同一个口径）。

/// 字号下限（pt）。低于它代码在 100% 缩放下看不清。
pub const MIN_SIZE_PT: u32 = 9;
/// 字号上限（pt）。高于它一屏放不下几行，反而难用。
pub const MAX_SIZE_PT: u32 = 20;
/// 缺省字号（pt）。
pub const DEFAULT_SIZE_PT: u32 = 13;

/// 一份完整的编辑器字体偏好。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EditorFont {
    /// `None` = **系统等宽**（不指定族）。
    pub family: Option<String>,
    /// 字号（pt，已夹取到 [`MIN_SIZE_PT`]~[`MAX_SIZE_PT`]）。
    pub size_pt: u32,
}

impl Default for EditorFont {
    fn default() -> Self {
        Self {
            family: None,
            size_pt: DEFAULT_SIZE_PT,
        }
    }
}

/// 族名清洗的结果：`None` = 未选（系统等宽）；`Some` = 可安全落进 CSS 的族名。
///
/// 单独一个函数是为了**能被单测逐条咬住**：空串 / 全空白 / 只含控制字符 / 含能闭合 CSS 的字符
/// 都归到 `None`，而不是各自散在解析里。
pub fn sanitize_family(raw: Option<&str>) -> Option<String> {
    let name = raw?.trim();
    if name.is_empty() {
        return None;
    }
    // 能改变 CSS 结构的字符一律拒绝：这些值最终会落进 `--ds-editor-font-family`，
    // 而 CSS 变量的值会被当 CSS 解析 —— 放过去等于让偏好文件能改样式表结构。
    let unsafe_char = |c: char| {
        c.is_control()
            || matches!(
                c,
                ';' | '{' | '}' | '<' | '>' | '\\' | '"' | '\'' | '(' | ')' | '!' | '@'
            )
    };
    if name.chars().any(unsafe_char) {
        return None;
    }
    Some(name.to_string())
}

impl EditorFont {
    /// 从**可能缺项、可能是脏值**的落盘数据还原（缺项用缺省，越界值夹取，脏族名当未选）。
    pub fn resolve(family_raw: Option<&str>, size_raw: Option<u32>) -> Self {
        Self {
            family: sanitize_family(family_raw),
            size_pt: size_raw.unwrap_or(DEFAULT_SIZE_PT).clamp(MIN_SIZE_PT, MAX_SIZE_PT),
        }
    }

    /// 该用哪一族的 CSS 取值（落进自定义属性）。
    ///
    /// 未选族时给的是**令牌层的等宽栈**而不是空串：空串会让 `font-family` 整条失效、
    /// 回落到浏览器缺省字体（那是比例字体，代码会立刻不对齐）。
    pub fn css_family(&self) -> String {
        match &self.family {
            None => "var(--ds-font-stack-mono)".to_string(),
            // 清洗已挡掉引号与反斜杠，这里的族名**不需要再转义**就能直接进 CSS 字符串
            Some(name) => format!("\"{name}\", var(--ds-font-stack-mono)"),
        }
    }

    /// 字号对应的 CSS 取值（px）。pt 与 px 在这个量级按 1:1 用 —— 编辑器只认 px，
    /// 而用户看的是「字号几档」，不引入 DPI 换算（换了反而与 macOS 侧的 9~20 档对不上）。
    pub fn css_size(&self) -> String {
        format!("{}px", self.size_pt)
    }

    /// 界面上「当前使用」那一行的族名（未选时给 `None`，由界面翻成「系统等宽」）。
    pub fn display_family(&self) -> Option<&str> {
        self.family.as_deref()
    }
}

/// 落盘键（**键名是契约**：改一个字，老用户的选择当场失效）。
pub mod keys {
    pub const FAMILY: &str = "editor.fontFamily";
    pub const SIZE: &str = "editor.fontSize";
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_is_system_monospace_at_thirteen() {
        let font = EditorFont::default();
        assert_eq!(font.family, None, "缺省不指定族（系统等宽）");
        assert_eq!(font.size_pt, 13);
        assert_eq!(font.css_family(), "var(--ds-font-stack-mono)");
        assert_eq!(font.css_size(), "13px");
    }

    #[test]
    fn blank_family_means_unset_not_a_font_named_empty_string() {
        for raw in [None, Some(""), Some("   "), Some("\t\n")] {
            assert_eq!(
                EditorFont::resolve(raw, None).family,
                None,
                "空 / 全空白 = 未选（用户清空输入框的意思是别用他这个族）"
            );
        }
        // 正常族名去掉两头空白后原样保留（**不改大小写**：字体族名匹配是大小写不敏感的，
        // 但「当前使用」要显示用户输入的那个拼写）
        assert_eq!(
            EditorFont::resolve(Some("  Cascadia Code  "), None).family.as_deref(),
            Some("Cascadia Code")
        );
    }

    #[test]
    fn size_is_clamped_into_nine_to_twenty() {
        assert_eq!(EditorFont::resolve(None, Some(9)).size_pt, 9);
        assert_eq!(EditorFont::resolve(None, Some(20)).size_pt, 20);
        assert_eq!(EditorFont::resolve(None, Some(8)).size_pt, MIN_SIZE_PT, "过小夹到下限");
        assert_eq!(EditorFont::resolve(None, Some(200)).size_pt, MAX_SIZE_PT, "过大夹到上限");
        assert_eq!(EditorFont::resolve(None, Some(0)).size_pt, MIN_SIZE_PT);
        assert_eq!(EditorFont::resolve(None, None).size_pt, DEFAULT_SIZE_PT, "缺项用缺省");
    }

    #[test]
    fn family_with_css_breaking_characters_is_refused_rather_than_escaped() {
        // 这些值会落进 CSS 变量的值里，能被当 CSS 解析 —— 一律当「未选」，不静默转义成别的东西
        for raw in [
            "Foo; color: red",
            "Foo}",
            "Foo{",
            "<script>",
            "a\"b",
            "a'b",
            "a(b)",
            "a\\b",
            "a\u{7}b",
        ] {
            assert_eq!(
                sanitize_family(Some(raw)),
                None,
                "含能改变 CSS 结构的字符的族名必须被拒：{raw}"
            );
        }
        // 中文族名 / 带空格的族名必须正常通过（用户装的就是这些）
        assert_eq!(sanitize_family(Some("更纱黑体 SC")).as_deref(), Some("更纱黑体 SC"));
        assert_eq!(sanitize_family(Some("Cascadia Mono")).as_deref(), Some("Cascadia Mono"));
    }

    #[test]
    fn css_family_quotes_the_name_and_keeps_the_monospace_fallback() {
        let font = EditorFont::resolve(Some("JetBrains Mono"), Some(14));
        assert_eq!(
            font.css_family(),
            "\"JetBrains Mono\", var(--ds-font-stack-mono)",
            "挑的族不存在时仍要落在等宽栈上（不然回落到比例字体，列会错）"
        );
        assert_eq!(font.css_size(), "14px");
    }

    #[test]
    fn storage_keys_are_the_contract() {
        assert_eq!(keys::FAMILY, "editor.fontFamily");
        assert_eq!(keys::SIZE, "editor.fontSize");
    }
}
