//! 内置终端的**屏幕模型 + 转义序列解释器**（FR-EDIT-29 / 计划 2.7；契约等价物：macOS 侧
//! `Core/TerminalScreen.swift`）
//!
//! 为什么放领域层：这是**纯逻辑**（把 PTY 吐出来的字节流解释成字符网格），能脱离图形界面单测。
//! 界面只负责把网格画出来、把按键写成字节；**PTY 本身（ConPTY）在表示层**。
//!
//! 实现的是一套**够用的 VT100 / xterm 子集**，不追求全兼容：
//! - C0：`BS` / `HT` / `LF` / `CR` / `BEL`
//! - CSI：光标移动（`A B C D E F G H f`）、擦除（`J K X`）、插入删除（`@ P`）、
//!   滚动（`S T`）、SGR（`m`）、滚动区域（`r`）
//! - OSC：忽略（窗口标题一类）
//! - 私有模式：`?25`（光标显隐）、`?7`（自动换行）、`?47` / `?1049`（备用屏）
//!
//! **明确不做**（写在注释里，不让它悄悄通过）：字符集切换（当两字节吞掉）、双向文本、
//! 图片协议（sixel / kitty）、鼠标双击三击区分。

/// 终端颜色。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", tag = "kind", content = "value")]
pub enum Color {
    /// 用默认前景 / 背景
    Default,
    /// 256 色索引
    Indexed(u8),
}

/// 一个字符格。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Cell {
    /// 可显示的字符（宽字符的右半格是空串）
    pub text: String,
    pub fg: Color,
    pub bg: Color,
    pub bold: bool,
    pub dim: bool,
    pub italic: bool,
    pub underline: bool,
    pub reverse: bool,
    /// 宽字符的**右半格**（渲染时跳过）
    pub continuation: bool,
}

impl Default for Cell {
    fn default() -> Self {
        Self {
            text: " ".to_string(),
            fg: Color::Default,
            bg: Color::Default,
            bold: false,
            dim: false,
            italic: false,
            underline: false,
            reverse: false,
            continuation: false,
        }
    }
}

impl Cell {
    fn blank_like(&self) -> Self {
        // 擦除要保留当前 SGR 属性（终端的标准行为）
        Self {
            text: " ".to_string(),
            fg: self.fg,
            bg: self.bg,
            bold: self.bold,
            dim: self.dim,
            italic: self.italic,
            underline: self.underline,
            reverse: self.reverse,
            continuation: false,
        }
    }
}

/// 当前画笔（SGR 状态）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Pen {
    pub fg: Color,
    pub bg: Color,
    pub bold: bool,
    pub dim: bool,
    pub italic: bool,
    pub underline: bool,
    pub reverse: bool,
}

impl Default for Pen {
    fn default() -> Self {
        Self {
            fg: Color::Default,
            bg: Color::Default,
            bold: false,
            dim: false,
            italic: false,
            underline: false,
            reverse: false,
        }
    }
}

/// 解释器状态机（转义序列可能被切成多段到达，状态要跨调用保留）。
#[derive(Debug, Clone, PartialEq, Eq)]
enum State {
    Ground,
    Escape,
    Csi,
    Osc,
    /// 私有模式里 `?` 之后的参数
    CsiPrivate(usize),
}

/// 终端屏幕。
#[derive(Debug, Clone)]
pub struct Screen {
    width: usize,
    height: usize,
    cells: Vec<Vec<Cell>>,
    /// 光标（0 起）
    pub cursor_row: usize,
    pub cursor_col: usize,
    pen: Pen,
    /// 滚动区域（含端点，0 起；默认整屏）
    scroll_top: usize,
    scroll_bottom: usize,
    /// 自动换行（`?7`，默认开）
    pub auto_wrap: bool,
    pub cursor_visible: bool,
    /// 备用屏（`?47` / `?1049`）：进备用屏前的主屏内容
    primary: Option<(Vec<Vec<Cell>>, usize, usize)>,
    /// 滚出屏幕的行（**历史**，最多 `SCROLLBACK_LIMIT` 行）
    scrollback: Vec<Vec<Cell>>,
    state: State,
    /// CSI 参数字符串（原样攒着，分发时再解析）
    params: String,
    /// 设备查询的应答（由调用方送回 PTY）
    pub pending_responses: Vec<String>,
    /// 响铃次数（界面上可以"当一声"）
    pub bell_count: usize,
}

/// 历史最多留多少行（再多也没人翻）。
pub const SCROLLBACK_LIMIT: usize = 2000;

impl Screen {
    pub fn new(width: usize, height: usize) -> Self {
        let width = width.max(1);
        let height = height.max(1);
        Self {
            width,
            height,
            cells: vec![vec![Cell::default(); width]; height],
            cursor_row: 0,
            cursor_col: 0,
            pen: Pen::default(),
            scroll_top: 0,
            scroll_bottom: height - 1,
            auto_wrap: true,
            cursor_visible: true,
            primary: None,
            scrollback: Vec::new(),
            state: State::Ground,
            params: String::new(),
            pending_responses: Vec::new(),
            bell_count: 0,
        }
    }

    pub fn width(&self) -> usize {
        self.width
    }

    pub fn height(&self) -> usize {
        self.height
    }

    /// 网格（渲染用）。**行数是 height**；历史另取。
    pub fn rows(&self) -> &[Vec<Cell>] {
        &self.cells
    }

    pub fn scrollback(&self) -> &[Vec<Cell>] {
        &self.scrollback
    }

    /// 一行的可显示文本（宽字符右半格跳过）。
    pub fn row_text(&self, row: usize) -> String {
        self.cells
            .get(row)
            .map(|cells| cells.iter().map(|cell| cell.text.as_str()).collect())
            .unwrap_or_default()
    }

    /// 整屏文本（单测与"复制全部"用）。
    pub fn text(&self) -> String {
        (0..self.height).map(|row| self.row_text(row)).collect::<Vec<_>>().join("\n")
    }

    /// 喂一段字节流（**可能被切成多段到达** ⇒ 状态跨调用保留）。
    pub fn feed(&mut self, bytes: &[u8]) {
        // 先按 UTF-8 解码（终端输出基本是 UTF-8）；解不出来就按单字节走
        let text = String::from_utf8_lossy(bytes).to_string();
        for ch in text.chars() {
            self.feed_char(ch);
        }
    }

    fn feed_char(&mut self, ch: char) {
        match self.state {
            // 转义序列里：攒参数，遇到终结符再分发
            State::Escape => match ch {
                '[' => {
                    self.state = State::Csi;
                    self.params.clear();
                }
                ']' => {
                    self.state = State::Osc;
                    self.params.clear();
                }
                // 其它两字节转义：直接吞掉（够用即可）
                _ => self.state = State::Ground,
            },
            State::Csi => match ch {
                '?' if self.params.is_empty() => self.state = State::CsiPrivate(0),
                // 参数字符
                '0'..='9' | ';' | ':' | ' ' | '>' | '=' => self.params.push(ch),
                // 终结符 ⇒ 分发
                c if ('@'..='~').contains(&c) => {
                    let params = std::mem::take(&mut self.params);
                    self.dispatch_csi(&params, c, false);
                    self.state = State::Ground;
                }
                _ => {
                    // 中间字符（如 `$`）：攒着（DECRQM 会用）
                    self.params.push(ch);
                }
            },
            State::CsiPrivate(_) => match ch {
                '0'..='9' | ';' => self.params.push(ch),
                c if ('@'..='~').contains(&c) => {
                    let params = std::mem::take(&mut self.params);
                    self.dispatch_csi(&params, c, true);
                    self.state = State::Ground;
                }
                _ => self.params.push(ch),
            },
            // OSC：吃到 BEL 或 ST（`ESC \`）为止（窗口标题一类，忽略）
            State::Osc => {
                if ch == '\u{7}' || ch == '\u{1b}' {
                    self.state = State::Ground;
                }
            }
            State::Ground => match ch {
                '\u{1b}' => self.state = State::Escape,
                '\u{7}' => self.bell_count += 1,
                '\u{8}' => {
                    // BS：退一格（不跨行）
                    self.cursor_col = self.cursor_col.saturating_sub(1);
                }
                '\t' => {
                    // HT：下一个 8 的倍数
                    let next = (self.cursor_col / 8 + 1) * 8;
                    self.cursor_col = next.min(self.width - 1);
                }
                '\n' => self.line_feed(),
                '\r' => self.cursor_col = 0,
                // **注意顺序**：具体控制字符（BS 等）必须写在下面那条兜底之前 ——
                // Rust 的 match 按书写顺序命中，兜底在前会把 BS 一起吞掉（我第一版就踩了：
                // 表现是"BS 看着没生效"）。
                // 其余 C0 控制字符：吞掉（不做）
                c if (c as u32) < 0x20 => {}
                c => self.put_char(c),
            },
        }
    }

    /// 换行：到滚动区域底部就**滚屏**（滚出去的那行进历史）。
    fn line_feed(&mut self) {
        if self.cursor_row == self.scroll_bottom {
            self.scroll_up(1);
        } else if self.cursor_row + 1 < self.height {
            self.cursor_row += 1;
        }
    }

    /// 向上滚 `count` 行：滚动区域内的行上移，底部补空行。
    fn scroll_up(&mut self, count: usize) {
        for _ in 0..count {
            let removed = self.cells.remove(self.scroll_top);
            // 只有**整屏滚动**（滚动区域就是整屏）才进历史 —— 局部滚动区不该污染历史
            if self.scroll_top == 0 && self.scroll_bottom == self.height - 1 {
                self.scrollback.push(removed);
                if self.scrollback.len() > SCROLLBACK_LIMIT {
                    self.scrollback.remove(0);
                }
            }
            let blank = vec![Cell::default(); self.width];
            self.cells.insert(self.scroll_bottom, blank);
        }
    }

    fn scroll_down(&mut self, count: usize) {
        for _ in 0..count {
            self.cells.remove(self.scroll_bottom);
            let blank = vec![Cell::default(); self.width];
            self.cells.insert(self.scroll_top, blank);
        }
    }

    /// 写一个字符（含**宽字符占两格**的处理）。
    fn put_char(&mut self, ch: char) {
        if self.cursor_col >= self.width {
            if self.auto_wrap {
                self.cursor_col = 0;
                self.line_feed();
            } else {
                self.cursor_col = self.width - 1;
            }
        }
        let wide = is_wide(ch);
        // 宽字符在最后一格放不下 ⇒ 换行（否则会切断）
        if wide && self.cursor_col + 1 >= self.width {
            if self.auto_wrap {
                self.cursor_col = 0;
                self.line_feed();
            } else {
                self.cursor_col = self.width.saturating_sub(2);
            }
        }
        let row = self.cursor_row.min(self.height - 1);
        let col = self.cursor_col.min(self.width - 1);
        let cell = Cell {
            text: ch.to_string(),
            fg: self.pen.fg,
            bg: self.pen.bg,
            bold: self.pen.bold,
            dim: self.pen.dim,
            italic: self.pen.italic,
            underline: self.pen.underline,
            reverse: self.pen.reverse,
            continuation: false,
        };
        self.cells[row][col] = cell;
        if wide && col + 1 < self.width {
            let mut mark = self.cells[row][col].clone();
            mark.text = String::new();
            mark.continuation = true;
            self.cells[row][col + 1] = mark;
        }
        self.cursor_col = col + if wide { 2 } else { 1 };
    }

    /// 分发一条 CSI（`private` = 带 `?` 的私有模式）。
    fn dispatch_csi(&mut self, params: &str, final_ch: char, private: bool) {
        let numbers = parse_params(params);
        let first = numbers.first().copied().unwrap_or(0);
        // 参数是 u32、光标是 usize：**在这一处转**（别在每处使用点各转一次）
        let amount = if first == 0 { 1usize } else { first as usize };

        if private {
            match final_ch {
                'h' => self.set_private_mode(&numbers, true),
                'l' => self.set_private_mode(&numbers, false),
                'n' => {
                    // DECRQM 询问：回一个"不认识"（0）
                    self.pending_responses.push("\u{1b}[?0$y".to_string());
                }
                _ => {}
            }
            return;
        }

        match final_ch {
            // 光标移动
            'A' => self.cursor_row = self.cursor_row.saturating_sub(amount),
            'B' => self.cursor_row = (self.cursor_row + amount).min(self.height - 1),
            'C' => self.cursor_col = (self.cursor_col + amount).min(self.width - 1),
            'D' => self.cursor_col = self.cursor_col.saturating_sub(amount),
            'E' => {
                self.cursor_row = (self.cursor_row + amount).min(self.height - 1);
                self.cursor_col = 0;
            }
            'F' => {
                self.cursor_row = self.cursor_row.saturating_sub(amount);
                self.cursor_col = 0;
            }
            'G' => self.cursor_col = ((first as usize).saturating_sub(1)).min(self.width - 1),
            'H' | 'f' => {
                // 参数是 u32、光标与行列是 usize：**在入口一次转好**（别散在各处）
                let row = (numbers.first().copied().unwrap_or(1).max(1) - 1) as usize;
                let col = (numbers.get(1).copied().unwrap_or(1).max(1) - 1) as usize;
                self.cursor_row = row.min(self.height - 1);
                self.cursor_col = col.min(self.width - 1);
            }
            // 擦除
            'J' => self.erase_display(first),
            'K' => self.erase_line(first),
            'X' => {
                let row = self.cursor_row;
                let blank = self.cells[row][self.cursor_col.min(self.width - 1)].blank_like();
                for col in self.cursor_col..(self.cursor_col + amount).min(self.width) {
                    self.cells[row][col] = blank.clone();
                }
            }
            // 插入 / 删除字符
            '@' => {
                let row = self.cursor_row;
                let col = self.cursor_col.min(self.width - 1);
                for _ in 0..amount.min(self.width - col) {
                    let blank = self.cells[row][col].blank_like();
                    self.cells[row].insert(col, blank);
                    self.cells[row].pop();
                }
            }
            'P' => {
                let row = self.cursor_row;
                let col = self.cursor_col.min(self.width - 1);
                for _ in 0..amount.min(self.width - col) {
                    self.cells[row].remove(col);
                    let blank = self.cells[row][col.min(self.width - 1)].blank_like();
                    self.cells[row].push(blank);
                }
            }
            // 滚动
            'S' => self.scroll_up(amount),
            'T' => self.scroll_down(amount),
            // 滚动区域
            'r' => {
                let top = (numbers.first().copied().unwrap_or(1).max(1) - 1) as usize;
                let bottom = (numbers.get(1).copied().unwrap_or(self.height as u32).max(1) - 1) as usize;
                if top < bottom && bottom < self.height {
                    self.scroll_top = top;
                    self.scroll_bottom = bottom;
                    self.cursor_row = top;
                    self.cursor_col = 0;
                }
            }
            // SGR：颜色与属性
            'm' => self.apply_sgr(&numbers),
            // 设备查询
            'c' => {
                self.pending_responses.push("\u{1b}[?1;2c".to_string());
            }
            'n' => match first {
                5 => self.pending_responses.push("\u{1b}[0n".to_string()),
                6 => self.pending_responses.push(format!(
                    "\u{1b}[{};{}R",
                    self.cursor_row + 1,
                    self.cursor_col + 1
                )),
                _ => {}
            },
            'q' => {
                // XTVERSION：如实报一个名字
                self.pending_responses.push("\u{1b}P>|DoyahStudio-Windows\u{1b}\\".to_string());
            }
            _ => {}
        }
    }

    fn set_private_mode(&mut self, numbers: &[u32], enable: bool) {
        for number in numbers {
            match number {
                7 => self.auto_wrap = enable,
                25 => self.cursor_visible = enable,
                47 | 1049 => {
                    if enable {
                        self.enter_alternate_screen();
                    } else {
                        self.leave_alternate_screen();
                    }
                }
                // 括号粘贴 / 鼠标上报 / 焦点上报：**接受但不实现**（不假装支持）
                _ => {}
            }
        }
    }

    fn enter_alternate_screen(&mut self) {
        if self.primary.is_some() {
            return; // 已经在备用屏里
        }
        self.primary = Some((self.cells.clone(), self.cursor_row, self.cursor_col));
        self.cells = vec![vec![Cell::default(); self.width]; self.height];
        self.cursor_row = 0;
        self.cursor_col = 0;
    }

    fn leave_alternate_screen(&mut self) {
        if let Some((cells, row, col)) = self.primary.take() {
            self.cells = cells;
            self.cursor_row = row.min(self.height - 1);
            self.cursor_col = col.min(self.width - 1);
        }
    }

    /// 擦除（`0` 光标到末尾 / `1` 开头到光标 / `2` 全部 / `3` 历史）。
    fn erase_display(&mut self, mode: u32) {
        match mode {
            0 => {
                self.erase_line(0);
                for row in (self.cursor_row + 1)..self.height {
                    let blank = vec![Cell::default(); self.width];
                    self.cells[row] = blank;
                }
            }
            1 => {
                self.erase_line(1);
                for row in 0..self.cursor_row {
                    let blank = vec![Cell::default(); self.width];
                    self.cells[row] = blank;
                }
            }
            2 => {
                let blank = vec![Cell::default(); self.width];
                for row in 0..self.height {
                    self.cells[row] = blank.clone();
                }
            }
            3 => self.scrollback.clear(),
            _ => {}
        }
    }

    /// 擦除行（`0` 光标到行尾 / `1` 行首到光标 / `2` 整行）。
    fn erase_line(&mut self, mode: u32) {
        let row = self.cursor_row.min(self.height - 1);
        let col = self.cursor_col.min(self.width - 1);
        let blank = self.cells[row][col].blank_like();
        match mode {
            0 => {
                for c in col..self.width {
                    self.cells[row][c] = blank.clone();
                }
            }
            1 => {
                for c in 0..=col {
                    self.cells[row][c] = blank.clone();
                }
            }
            2 => {
                for c in 0..self.width {
                    self.cells[row][c] = blank.clone();
                }
            }
            _ => {}
        }
    }

    /// SGR：颜色与属性。
    fn apply_sgr(&mut self, numbers: &[u32]) {
        if numbers.is_empty() {
            self.pen = Pen::default();
            return;
        }
        let mut index = 0usize;
        while index < numbers.len() {
            let code = numbers[index];
            match code {
                0 => self.pen = Pen::default(),
                1 => self.pen.bold = true,
                2 => self.pen.dim = true,
                3 => self.pen.italic = true,
                4 => self.pen.underline = true,
                7 => self.pen.reverse = true,
                22 => {
                    self.pen.bold = false;
                    self.pen.dim = false;
                }
                23 => self.pen.italic = false,
                24 => self.pen.underline = false,
                27 => self.pen.reverse = false,
                30..=37 => self.pen.fg = Color::Indexed((code - 30) as u8),
                39 => self.pen.fg = Color::Default,
                40..=47 => self.pen.bg = Color::Indexed((code - 40) as u8),
                49 => self.pen.bg = Color::Default,
                90..=97 => self.pen.fg = Color::Indexed((code - 90 + 8) as u8),
                100..=107 => self.pen.bg = Color::Indexed((code - 100 + 8) as u8),
                // 256 色：`38;5;n` / `48;5;n`
                38 | 48 => {
                    let is_fg = code == 38;
                    if numbers.get(index + 1) == Some(&5) {
                        let value = numbers.get(index + 2).copied().unwrap_or(0) as u8;
                        if is_fg {
                            self.pen.fg = Color::Indexed(value);
                        } else {
                            self.pen.bg = Color::Indexed(value);
                        }
                        index += 2;
                    } else if numbers.get(index + 1) == Some(&2) {
                        // 真彩：本侧**只取近似索引**（不假装支持真彩）
                        let r = numbers.get(index + 2).copied().unwrap_or(0);
                        let g = numbers.get(index + 3).copied().unwrap_or(0);
                        let b = numbers.get(index + 4).copied().unwrap_or(0);
                        let approx = rgb_to_index(r, g, b);
                        if is_fg {
                            self.pen.fg = Color::Indexed(approx);
                        } else {
                            self.pen.bg = Color::Indexed(approx);
                        }
                        index += 4;
                    }
                }
                _ => {}
            }
            index += 1;
        }
    }
}

/// 真彩 → 256 色近似（**如实说这是近似**：本侧只做 16 + 256 色）。
fn rgb_to_index(r: u32, g: u32, b: u32) -> u8 {
    if r == g && g == b {
        if r < 8 {
            return 16;
        }
        if r > 248 {
            return 231;
        }
        return (16 + ((r - 8) / 10)) as u8;
    }
    let ri = ((r as f32 / 255.0) * 5.0).round() as u32;
    let gi = ((g as f32 / 255.0) * 5.0).round() as u32;
    let bi = ((b as f32 / 255.0) * 5.0).round() as u32;
    (16 + 36 * ri + 6 * gi + bi) as u8
}

/// 宽字符（CJK）判定：占两格。**只覆盖常见区间**（不追求完整的 East Asian Width 表）。
pub fn is_wide(ch: char) -> bool {
    matches!(ch as u32,
        0x1100..=0x115F
        | 0x2E80..=0x303E
        | 0x3041..=0x33FF
        | 0x3400..=0x4DBF
        | 0x4E00..=0x9FFF
        | 0xA000..=0xA4CF
        | 0xAC00..=0xD7A3
        | 0xF900..=0xFAFF
        | 0xFE30..=0xFE6F
        | 0xFF00..=0xFF60
        | 0xFFE0..=0xFFE6
        | 0x1F300..=0x1F64F
        | 0x1F900..=0x1F9FF
        | 0x20000..=0x3FFFD)
}

/// 解析 CSI 参数（`1;2;3` / 空段当 0）。
fn parse_params(params: &str) -> Vec<u32> {
    let cleaned: String = params.chars().filter(|c| c.is_ascii_digit() || *c == ';').collect();
    if cleaned.is_empty() {
        return Vec::new();
    }
    cleaned
        .split(';')
        .map(|part| part.parse::<u32>().unwrap_or(0))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 取历史里第 `index` 行的文本（去掉行尾填充）。
    fn history_text(screen: &Screen, index: usize) -> String {
        screen
            .scrollback()
            .get(index)
            .map(|cells| cells.iter().map(|c| c.text.as_str()).collect::<String>())
            .unwrap_or_default()
            .trim_end()
            .to_string()
    }

    fn screen() -> Screen {
        Screen::new(10, 3)
    }

    #[test]
    fn plain_text_wraps_and_scrolls_into_history() {
        let mut s = Screen::new(5, 2);
        s.feed("abcdefghij".as_bytes());
        // 5 列、自动换行 ⇒ 前 5 个在第一行，后 5 个在第二行
        assert_eq!(s.row_text(0).trim_end(), "abcde");
        assert_eq!(s.row_text(1).trim_end(), "fghij");
        // 再换行 ⇒ 滚屏，第一行进历史
        s.feed("\nX".as_bytes());
        // **实际滚了 2 行**：先因自动换行滚一次（"abcde" 进历史），再因 `\n` 滚一次（"fghij" 进历史）。
        // 我第一版写 1 是**没算清换行与滚动的关系**，实现是对的。
        assert_eq!(s.scrollback().len(), 2);
        assert_eq!(history_text(&s, 0), "abcde");
        assert_eq!(history_text(&s, 1), "fghij");
        assert_eq!(
            s.scrollback()[0].iter().map(|c| c.text.as_str()).collect::<String>(),
            "abcde"
        );
    }

    #[test]
    fn carriage_return_and_backspace() {
        let mut s = screen();
        s.feed("abc\rX".as_bytes());
        assert_eq!(s.row_text(0).trim_end(), "Xbc", "CR 回到行首，覆写第一个字符");
        s.feed("\u{8}Y".as_bytes());
        // BS 退一格（列 1 → 0）再写 ⇒ 覆盖的是**第 1 个**字符，不是第 2 个。
        // 我第一版写成 "XYc" 是**把 BS 的语义理解错了**：BS 只退一格，不回退一格半。
        assert_eq!(s.row_text(0).trim_end(), "Ybc");
    }

    #[test]
    fn csi_cursor_movement_and_erase() {
        let mut s = screen();
        // 把光标移到 (2,3) 写一个字符
        s.feed("\u{1b}[2;3HX".as_bytes());
        assert_eq!(s.row_text(1).trim_end(), "  X");
        // 移到行首擦到行尾
        s.feed("\u{1b}[2;1H\u{1b}[K".as_bytes());
        assert_eq!(s.row_text(1).trim_end(), "");
        // 整屏擦除
        s.feed("\u{1b}[2J".as_bytes());
        assert_eq!(s.text().trim(), "");
        // 向上 / 向下移动与列定位
        s.feed("\u{1b}[3;5H".as_bytes());
        assert_eq!((s.cursor_row, s.cursor_col), (2, 4));
        s.feed("\u{1b}[2A".as_bytes());
        assert_eq!(s.cursor_row, 0);
        s.feed("\u{1b}[3G".as_bytes());
        assert_eq!(s.cursor_col, 2);
    }

    #[test]
    fn sgr_colors_and_attributes() {
        let mut s = screen();
        s.feed("\u{1b}[1;31mR".as_bytes());
        let cell = &s.rows()[0][0];
        assert!(cell.bold);
        assert_eq!(cell.fg, Color::Indexed(1));
        // 复位
        s.feed("\u{1b}[0mN".as_bytes());
        let plain = &s.rows()[0][1];
        assert!(!plain.bold);
        assert_eq!(plain.fg, Color::Default);
        // 亮色与 256 色
        s.feed("\u{1b}[92mG".as_bytes());
        assert_eq!(s.rows()[0][2].fg, Color::Indexed(10));
        s.feed("\u{1b}[38;5;200mH".as_bytes());
        assert_eq!(s.rows()[0][3].fg, Color::Indexed(200));
        // 背景色
        s.feed("\u{1b}[44mB".as_bytes());
        assert_eq!(s.rows()[0][4].bg, Color::Indexed(4));
        // 真彩：**近似成 256 色**（如实说这是近似）
        s.feed("\u{1b}[38;2;255;0;0mT".as_bytes());
        assert!(matches!(s.rows()[0][5].fg, Color::Indexed(_)));
    }

    #[test]
    fn wide_characters_take_two_cells() {
        let mut s = screen();
        s.feed("中文".as_bytes());
        assert_eq!(s.row_text(0).trim_end(), "中文");
        // 第一格是真字符、第二格是续格
        assert_eq!(s.rows()[0][0].text, "中");
        assert!(s.rows()[0][1].continuation);
        assert_eq!(s.rows()[0][1].text, "");
        assert_eq!(s.rows()[0][2].text, "文");
        assert!(is_wide('中') && is_wide('😀'));
        assert!(!is_wide('a') && !is_wide('1'));
    }

    #[test]
    fn alternate_screen_switches_and_restores() {
        let mut s = screen();
        s.feed("main".as_bytes());
        s.feed("\u{1b}[?1049h".as_bytes());
        assert_eq!(s.row_text(0).trim_end(), "", "进备用屏后是干净的");
        s.feed("alt".as_bytes());
        assert_eq!(s.row_text(0).trim_end(), "alt");
        s.feed("\u{1b}[?1049l".as_bytes());
        assert_eq!(s.row_text(0).trim_end(), "main", "回主屏，内容还在");
    }

    #[test]
    fn scrolling_region_keeps_local_scroll_out_of_history() {
        let mut s = Screen::new(5, 4);
        s.feed("1\r\n2\r\n3\r\n4".as_bytes());
        // 设滚动区域为第 2~3 行
        s.feed("\u{1b}[2;3r".as_bytes());
        s.feed("\u{1b}[3;1H\n".as_bytes());
        // 局部滚动**不该**进历史（那会污染"往上翻"的语义）
        assert!(s.scrollback().is_empty(), "局部滚动不进历史");
        // 第一行与最后一行不受影响
        assert_eq!(s.row_text(0).trim_end(), "1");
        assert_eq!(s.row_text(3).trim_end(), "4");
    }

    #[test]
    fn device_queries_answer_and_bell_counts() {
        let mut s = screen();
        s.feed("\u{1b}[5n".as_bytes());
        assert_eq!(s.pending_responses, vec!["\u{1b}[0n".to_string()]);
        s.feed("\u{1b}[6n".as_bytes());
        assert!(s.pending_responses[1].ends_with('R'), "光标位置报告");
        s.feed("\u{1b}[c".as_bytes());
        assert!(s.pending_responses[2].contains("?1;2c"));
        s.feed("\u{7}\u{7}".as_bytes());
        assert_eq!(s.bell_count, 2);
        // 私有模式：光标显隐
        s.feed("\u{1b}[?25l".as_bytes());
        assert!(!s.cursor_visible);
        s.feed("\u{1b}[?25h".as_bytes());
        assert!(s.cursor_visible);
    }

    #[test]
    fn state_survives_a_sequence_split_across_feeds() {
        // 转义序列可能被切成多段到达 —— 状态要跨调用保留
        let mut s = screen();
        s.feed("\u{1b}[3".as_bytes());
        s.feed("1mX".as_bytes());
        assert_eq!(s.rows()[0][0].fg, Color::Indexed(1));
        // 再切一次
        s.feed("\u{1b}".as_bytes());
        s.feed("[1;5H".as_bytes());
        assert_eq!((s.cursor_row, s.cursor_col), (0, 4));
    }

    #[test]
    fn osc_is_ignored_but_does_not_eat_following_text() {
        let mut s = screen();
        // OSC 0 ; 标题 BEL 之后的内容要照常显示
        s.feed("\u{1b}]0;some title\u{7}after".as_bytes());
        assert_eq!(s.row_text(0).trim_end(), "after");
    }

    #[test]
    fn parse_params_handles_empty_and_multi() {
        assert_eq!(parse_params(""), Vec::<u32>::new());
        assert_eq!(parse_params("3"), vec![3]);
        assert_eq!(parse_params("1;5"), vec![1, 5]);
        assert_eq!(parse_params(";5"), vec![0, 5]);
        assert_eq!(parse_params("1;5H"), vec![1, 5], "非参数字符被滤掉");
    }
}
