//! 终端**输入与应答**的纯函数层（FR-EDIT-29 / 计划 2.7；契约等价物：macOS 侧
//! `Core/TerminalInput.swift` + `Core/TerminalPaste.swift`）
//!
//! 为什么单独放一层：这些全是"**给定状态 → 一串字节**"的纯映射（方向键要不要走 SS3、
//! 鼠标事件怎么编码、粘贴要不要包起来），把它们从界面里拎出来才能单测，
//! 也才能一眼看懂"为什么会发出这几个字节"。界面只负责把按键事件翻成本层的入参。
//!
//! 规范来源：xterm 的 Control Sequences（底本 ECMA-48 / ISO 6429）。
//! **哪些是规范、哪些是惯例**逐条标在注释里。

/// 方向键 / Home / End。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum CursorKey {
    Up,
    Down,
    Right,
    Left,
    Home,
    End,
}

impl CursorKey {
    /// 普通模式（CSI 形式）的终止字符。
    pub const fn final_char(self) -> char {
        match self {
            CursorKey::Up => 'A',
            CursorKey::Down => 'B',
            CursorKey::Right => 'C',
            CursorKey::Left => 'D',
            CursorKey::Home => 'H',
            CursorKey::End => 'F',
        }
    }
}

/// 方向键 / Home / End 的字节。
///
/// `application_cursor_keys` = DECCKM（`?1`）是否置位。置位时用 **SS3**（`ESC O x`），
/// 否则用 CSI（`ESC [ x`）。**这是规范**（xterm ctlseqs 的 DECCKM 条目），不是惯例 ——
/// vim / less / 部分 TUI 靠它区分"方向键"与"应用光标键"。
pub fn cursor_key(key: CursorKey, application_cursor_keys: bool) -> Vec<u8> {
    let prefix = if application_cursor_keys { "\u{1b}O" } else { "\u{1b}[" };
    format!("{prefix}{}", key.final_char()).into_bytes()
}

/// 功能键（F1~F12）。F1~F4 用 SS3、F5 以上用 CSI（xterm 的惯例）。
pub fn function_key(number: u8) -> Option<Vec<u8>> {
    let bytes = match number {
        1 => "\u{1b}OP",
        2 => "\u{1b}OQ",
        3 => "\u{1b}OR",
        4 => "\u{1b}OS",
        5 => "\u{1b}[15~",
        6 => "\u{1b}[17~",
        7 => "\u{1b}[18~",
        8 => "\u{1b}[19~",
        9 => "\u{1b}[20~",
        10 => "\u{1b}[21~",
        11 => "\u{1b}[23~",
        12 => "\u{1b}[24~",
        _ => return None,
    };
    Some(bytes.as_bytes().to_vec())
}

/// 修饰键（与 xterm 的 `1;N` 编码一致：⇧+1 / ⌥+2 / ⌃+4 / 再 +1）。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Modifiers {
    pub shift: bool,
    pub alt: bool,
    pub ctrl: bool,
}

impl Modifiers {
    /// xterm 的修饰键参数值（无修饰 = 1）。
    pub const fn parameter(self) -> u32 {
        1 + (self.shift as u32) + ((self.alt as u32) << 1) + ((self.ctrl as u32) << 2)
    }

    pub const fn any(self) -> bool {
        self.shift || self.alt || self.ctrl
    }
}

/// 带修饰键的方向键 / Home / End：`CSI 1;<N> <final>`（有修饰键时**不走 SS3** —— 规范如此）。
pub fn cursor_key_with_modifiers(key: CursorKey, modifiers: Modifiers) -> Vec<u8> {
    if !modifiers.any() {
        return cursor_key(key, false);
    }
    format!("\u{1b}[1;{}{}", modifiers.parameter(), key.final_char()).into_bytes()
}

/// 鼠标按钮。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum MouseButton {
    Left,
    Middle,
    Right,
    /// 旧式编码里"松开"统一用它（编码里表达不出"哪个键松开"）
    Release,
}

impl MouseButton {
    pub const fn code(self) -> u32 {
        match self {
            MouseButton::Left => 0,
            MouseButton::Middle => 1,
            MouseButton::Right => 2,
            MouseButton::Release => 3,
        }
    }
}

/// 鼠标动作。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum MouseAction {
    Press,
    Release,
    Motion,
    WheelUp,
    WheelDown,
}

/// 一次鼠标事件（坐标 **1 基**）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MouseEvent {
    pub button: MouseButton,
    pub action: MouseAction,
    pub modifiers: Modifiers,
    pub column: u32,
    pub row: u32,
}

/// 鼠标事件 → 上报字节。
///
/// 两种编码：
/// - **旧式（X10 / normal）**：`ESC [ M` + 三个字节 `(32+按钮码)(32+列)(32+行)`，
///   坐标 1 基、各加 32；松开统一用按钮码 3。单字节上限 223 ⇒ 行列过大时**截断到 223**
///   （xterm 同样表达不了，宁可截断也不发出会被误解成别的按钮的字节）。
/// - **SGR（`?1006`）**：`ESC [ < 按钮码 ; 列 ; 行 M`（按下 / 移动 / 滚轮）或结尾 `m`（松开），
///   坐标 1 基、**不加 32**，因此没有 223 限制，也分得清松开的是哪个键。
///
/// 按钮码：左 0 / 中 1 / 右 2、滚轮上 64 / 下 65，移动再 +32，修饰键 ⇧+4 / ⌥+8 / ⌃+16。
pub fn mouse_report(event: MouseEvent, sgr: bool) -> Vec<u8> {
    let mut code = match event.action {
        MouseAction::Press => event.button.code(),
        MouseAction::Release => {
            if sgr {
                event.button.code()
            } else {
                MouseButton::Release.code()
            }
        }
        MouseAction::Motion => event.button.code() + 32,
        MouseAction::WheelUp => 64,
        MouseAction::WheelDown => 65,
    };
    code += (event.modifiers.shift as u32) * 4
        + (event.modifiers.alt as u32) * 8
        + (event.modifiers.ctrl as u32) * 16;
    let column = event.column.max(1);
    let row = event.row.max(1);
    if sgr {
        // SGR 里松开用终止符 `m` 区分，按钮码保持原样
        let final_char = if event.action == MouseAction::Release { 'm' } else { 'M' };
        return format!("\u{1b}[<{code};{column};{row}{final_char}").into_bytes();
    }
    let clamp = |value: u32| 32u32.saturating_add(value).min(223) as u8;
    vec![
        0x1b,
        b'[',
        b'M',
        clamp(code),
        clamp(column),
        clamp(row),
    ]
}

/// 括号粘贴的开始 / 结束标记（xterm 约定）。
pub const PASTE_START: &str = "\u{1b}[200~";
pub const PASTE_END: &str = "\u{1b}[201~";

/// 粘贴的字节：**括号粘贴开着就包起来**，换行**原样发送**。
///
/// 为什么必须这样：
/// 1. **包起来**：shell / vim / psql 打开括号粘贴后，期望内容被包在 `ESC[200~ … ESC[201~` 之间
///    —— 这样它才知道"这些不是用户敲的"。不包的话：vim 会按每行重新自动缩进
///    （粘一段代码变成阶梯状），某些 REPL 会把多行里的换行当成"逐行提交"（粘一段 SQL 直接跑了）。
/// 2. **换行不转换**：PTY 的行规程默认开着 `ICRNL`，会把 CR 转成 NL；反过来把 LF 偷偷改成 CR
///    反而会在某些程序里出现"多一个空行"。所以这里**不做任何转换**（要改就得两边一起改）。
pub fn paste(text: &str, bracketed: bool) -> Vec<u8> {
    if bracketed {
        format!("{PASTE_START}{text}{PASTE_END}").into_bytes()
    } else {
        text.as_bytes().to_vec()
    }
}

/// 普通按键 → 字节（可打印字符走它）。
///
/// 注意 `\r` 与 `\n`：**回车键发 CR**（终端惯例，行规程再按 `ICRNL` 处理）；
/// 换行键在终端里通常就是回车键，这里统一发 CR。
pub fn key_char(ch: char) -> Vec<u8> {
    match ch {
        '\n' => vec![b'\r'],
        other => other.to_string().into_bytes(),
    }
}

/// 控制键组合（`Ctrl+A` 之类）：字母转 1..26。
pub fn control_key(ch: char) -> Option<Vec<u8>> {
    let upper = ch.to_ascii_uppercase();
    if upper.is_ascii_uppercase() {
        return Some(vec![(upper as u8) - b'A' + 1]);
    }
    match ch {
        ' ' | '@' => Some(vec![0]),
        '[' => Some(vec![27]),
        '\\' => Some(vec![28]),
        ']' => Some(vec![29]),
        '^' => Some(vec![30]),
        '_' => Some(vec![31]),
        '?' => Some(vec![127]),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cursor_keys_switch_between_csi_and_ss3() {
        // 普通模式：CSI
        assert_eq!(cursor_key(CursorKey::Up, false), b"\x1b[A".to_vec());
        assert_eq!(cursor_key(CursorKey::End, false), b"\x1b[F".to_vec());
        // DECCKM 置位（应用光标键）：SS3 —— 这是**规范**，vim / less 靠它区分
        assert_eq!(cursor_key(CursorKey::Up, true), b"\x1bOA".to_vec());
        assert_eq!(cursor_key(CursorKey::Home, true), b"\x1bOH".to_vec());
    }

    #[test]
    fn function_keys_use_ss3_for_f1_to_f4_and_csi_above() {
        assert_eq!(function_key(1).unwrap(), b"\x1bOP".to_vec());
        assert_eq!(function_key(4).unwrap(), b"\x1bOS".to_vec());
        assert_eq!(function_key(5).unwrap(), b"\x1b[15~".to_vec());
        assert_eq!(function_key(12).unwrap(), b"\x1b[24~".to_vec());
        // 不存在的功能键 ⇒ None（**不编一个**）
        assert!(function_key(0).is_none());
        assert!(function_key(13).is_none());
    }

    #[test]
    fn modifiers_follow_the_xterm_encoding() {
        // 无修饰 = 1
        assert_eq!(Modifiers::default().parameter(), 1);
        assert_eq!(
            Modifiers {
                shift: true,
                ..Default::default()
            }
            .parameter(),
            2
        );
        assert_eq!(
            Modifiers {
                ctrl: true,
                ..Default::default()
            }
            .parameter(),
            5
        );
        assert_eq!(
            Modifiers {
                shift: true,
                alt: true,
                ctrl: true
            }
            .parameter(),
            8
        );
        // 带修饰键的方向键：**不走 SS3**（规范：带修饰一律 CSI `1;<N> x`）
        assert_eq!(
            cursor_key_with_modifiers(
                CursorKey::Right,
                Modifiers {
                    ctrl: true,
                    ..Default::default()
                }
            ),
            b"\x1b[1;5C".to_vec()
        );
        // 无修饰时退化成普通形式
        assert_eq!(
            cursor_key_with_modifiers(CursorKey::Right, Modifiers::default()),
            b"\x1b[C".to_vec()
        );
    }

    #[test]
    fn sgr_mouse_report_has_no_223_limit_and_distinguishes_release() {
        let press = MouseEvent {
            button: MouseButton::Left,
            action: MouseAction::Press,
            modifiers: Modifiers::default(),
            column: 10,
            row: 5,
        };
        assert_eq!(mouse_report(press, true), b"\x1b[<0;10;5M".to_vec());
        // 松开：SGR 用 `m` 且**保留按钮码**（分得清松开的是哪个键）
        let release = MouseEvent {
            action: MouseAction::Release,
            ..press
        };
        assert_eq!(mouse_report(release, true), b"\x1b[<0;10;5m".to_vec());
        // 大坐标不受限（旧式编码会截断）
        let far = MouseEvent {
            column: 500,
            row: 400,
            ..press
        };
        assert_eq!(mouse_report(far, true), b"\x1b[<0;500;400M".to_vec());
        // 修饰键：⇧+4 / ⌥+8 / ⌃+16
        let modified = MouseEvent {
            modifiers: Modifiers {
                shift: true,
                ctrl: true,
                alt: false,
            },
            ..press
        };
        assert_eq!(mouse_report(modified, true), b"\x1b[<20;10;5M".to_vec());
    }

    #[test]
    fn legacy_mouse_report_adds_32_and_clamps_to_223() {
        let press = MouseEvent {
            button: MouseButton::Left,
            action: MouseAction::Press,
            modifiers: Modifiers::default(),
            column: 1,
            row: 1,
        };
        // 坐标 1 基 ⇒ 加 32 后 33（0x21）
        assert_eq!(mouse_report(press, false), vec![0x1b, b'[', b'M', 32, 33, 33]);
        // 松开统一用按钮码 3 ⇒ 32+3 = 35
        let release = MouseEvent {
            action: MouseAction::Release,
            ..press
        };
        assert_eq!(mouse_report(release, false)[3], 35);
        // 滚轮：上 64 / 下 65 ⇒ +32 后 96 / 97
        let wheel = MouseEvent {
            action: MouseAction::WheelUp,
            ..press
        };
        assert_eq!(mouse_report(wheel, false)[3], 96);
        let wheel_down = MouseEvent {
            action: MouseAction::WheelDown,
            ..press
        };
        assert_eq!(mouse_report(wheel_down, false)[3], 97);
        // 坐标过大 ⇒ **截断到 223**（xterm 也表达不了）
        let far = MouseEvent {
            column: 5000,
            row: 5000,
            ..press
        };
        let bytes = mouse_report(far, false);
        assert_eq!(bytes[4], 223);
        assert_eq!(bytes[5], 223);
    }

    #[test]
    fn paste_wraps_only_when_bracketed_paste_is_on_and_never_rewrites_newlines() {
        // 括号粘贴开着 ⇒ 包起来（否则 vim 会把粘进来的代码按行自动缩进成阶梯状）
        let wrapped = paste("line1\nline2\n", true);
        let text = String::from_utf8(wrapped).unwrap();
        assert!(text.starts_with(PASTE_START));
        assert!(text.ends_with(PASTE_END));
        // **换行一个都不改**（不做 CR/LF 转换）
        assert!(text.contains("line1\nline2\n"));
        assert!(!text.contains('\r'));
        // 关着 ⇒ 原样
        assert_eq!(paste("abc", false), b"abc".to_vec());
        // 空粘贴也给合法字节
        assert_eq!(paste("", true), format!("{PASTE_START}{PASTE_END}").into_bytes());
    }

    #[test]
    fn enter_sends_carriage_return_and_control_keys_follow_ascii() {
        // 回车键发 CR（终端惯例；行规程再按 ICRNL 处理）
        assert_eq!(key_char('\n'), vec![b'\r']);
        assert_eq!(key_char('a'), b"a".to_vec());
        // Ctrl+A ⇒ 1、Ctrl+Z ⇒ 26
        assert_eq!(control_key('a').unwrap(), vec![1]);
        assert_eq!(control_key('Z').unwrap(), vec![26]);
        assert_eq!(control_key(' ').unwrap(), vec![0]);
        assert_eq!(control_key('[').unwrap(), vec![27]);
        // 没有控制键对应的字符 ⇒ None
        assert!(control_key('1').is_none());
        assert!(control_key('中').is_none());
    }
}
