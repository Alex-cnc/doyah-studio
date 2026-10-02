//! 工作区 Markdown 预览的**块级模型**（FR-EDIT-45 / 计划 2.5；契约等价物：macOS 侧
//! `Core/MarkdownDocument.swift`）
//!
//! 为什么要有这一层：预览必须**复用同一套解析**，不能一边用编辑器的高亮、一边用第三方的渲染器
//! —— 同一份文档两处口径，早晚对不上。本层只产出**模型**（纯函数、可单测），界面只负责画出来；
//! 模型里**没有可编辑控件**（预览是只读的，这条是结构上挡住的，不靠自觉）。
//!
//! ## 支持的子集（GFM 的可用子集，刻意小）
//! 标题（ATX `#`~`######`）· 段落（软换行**原样保留**）· 无序 / 有序列表（含嵌套）·
//! 任务列表（`- [x]`，复选框**从正文里摘出**变成 `checked`）· 表格（含对齐与 `\|` 转义）·
//! 围栏代码块（``` / ~~~，带语言串）· 引用（`>`）· 分隔线。
//!
//! ## 明确**不支持**（写在这里，而不是让它悄悄通过）
//! - **Setext 标题**（`标题` 下面一行 `===`）：`---` 一律按分隔线处理；
//! - **缩进式代码块**（四空格起）：按普通段落原样搬运；
//! - **HTML 块 / 脚注 / 删除线**：原样当纯文本搬运（**不吞不改**）；
//! - **链接的"能不能点、开在哪儿"不在本层判**：本层只把 `[文字](目标)` 拆成 span 带 `target`，
//!   由界面决定（本侧只读预览，**不自动打开外部链接**）。
//!
//! ## 行内标记
//! `**粗体**` / `*斜体*` / `` `代码` `` / `[文字](目标)`。行内解析只有**这一处实现**
//! （笔记侧与预览侧将来都用它）。

/// 文档模型的**版本号**：结构变了才升（与其它落盘结构同一套纪律）。
pub const MARKDOWN_FORMAT_VERSION: u32 = 1;

/// 表格列对齐（GFM 的 `:---` / `:---:` / `---:`）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ColumnAlignment {
    /// 没写冒号（`---`）
    None,
    /// `:---`
    Left,
    /// `:---:`
    Center,
    /// `---:`
    Right,
}

/// 行内 span（一段文字 + 可选链接目标）。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Span {
    pub text: String,
    pub bold: bool,
    pub italic: bool,
    pub code: bool,
    /// 链接目标（`None` = 普通文字）；本层**不判能不能点**
    pub target: Option<String>,
}

impl Span {
    fn plain(text: impl Into<String>) -> Self {
        Self {
            text: text.into(),
            bold: false,
            italic: false,
            code: false,
            target: None,
        }
    }
}

/// 一个块的**起始行号**（1 起）—— 跟随滚动时把行映射到预览锚点要用。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Block {
    /// 起始行（1 起）
    pub line: usize,
    pub kind: BlockKind,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", tag = "type")]
pub enum BlockKind {
    /// 标题（`level` 1..6）
    Heading { level: u8, spans: Vec<Span> },
    /// 段落（软换行**原样保留**在 `text` 里，怎么显示由界面决定）
    Paragraph { spans: Vec<Span> },
    /// 围栏代码块（**内容原样**，不做行内解析）
    CodeFence { language: Option<String>, text: String },
    /// 列表条目（无序 / 有序共用；嵌套的块进 `children`）
    ListItem {
        /// 有序列表的序号（无序为 `None`）
        number: Option<u64>,
        /// 任务列表的勾选态；`None` = 不是任务项（**复选框已从正文里摘出**）
        checked: Option<bool>,
        spans: Vec<Span>,
        children: Vec<Block>,
    },
    /// 表格
    Table {
        alignments: Vec<ColumnAlignment>,
        header: Vec<Vec<Span>>,
        rows: Vec<Vec<Vec<Span>>>,
    },
    /// 引用（内含块）
    Quote { children: Vec<Block> },
    /// 分隔线
    Rule,
}

/// 整篇文档。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Document {
    pub version: u32,
    pub blocks: Vec<Block>,
}

/// 解析一篇 Markdown（**纯函数**：同样输入永远同样输出）。
pub fn parse(text: &str) -> Document {
    let lines: Vec<&str> = text.split('\n').collect();
    let (blocks, _) = parse_blocks(&lines, 0);
    Document {
        version: MARKDOWN_FORMAT_VERSION,
        blocks,
    }
}

/// 行内解析：`**粗体**` / `*斜体*` / `` `代码` `` / `[文字](目标)`。
///
/// **只有这一处实现**（预览与将来的笔记共用）。刻意不做嵌套强调（`**a *b* c**` 里的斜体不单列）：
/// 嵌套是另一个量级的事，而"看得懂常见写法"已经够预览用。
pub fn parse_inline(text: &str) -> Vec<Span> {
    let mut spans: Vec<Span> = Vec::new();
    let mut plain = String::new();
    let chars: Vec<char> = text.chars().collect();
    let mut index = 0usize;

    let flush = |plain: &mut String, spans: &mut Vec<Span>| {
        if !plain.is_empty() {
            spans.push(Span::plain(std::mem::take(plain)));
        }
    };

    while index < chars.len() {
        // ① 代码（**优先于强调**：`` `a*b*c` `` 里的星号不算强调）
        if chars[index] == '`' {
            if let Some(end) = chars[index + 1..].iter().position(|c| *c == '`') {
                flush(&mut plain, &mut spans);
                let inner: String = chars[index + 1..index + 1 + end].iter().collect();
                spans.push(Span {
                    text: inner,
                    bold: false,
                    italic: false,
                    code: true,
                    target: None,
                });
                index += end + 2;
                continue;
            }
        }
        // ② 链接 `[文字](目标)`
        if chars[index] == '[' {
            if let Some((label, target, consumed)) = parse_link(&chars[index..]) {
                flush(&mut plain, &mut spans);
                spans.push(Span {
                    text: label,
                    bold: false,
                    italic: false,
                    code: false,
                    target: Some(target),
                });
                index += consumed;
                continue;
            }
        }
        // ③ 粗体 `**...**`
        if chars[index] == '*' && chars.get(index + 1) == Some(&'*') {
            if let Some(end) = find_close(&chars, index + 2, "**") {
                flush(&mut plain, &mut spans);
                let inner: String = chars[index + 2..end].iter().collect();
                let mut inner_spans = parse_inline(&inner);
                for span in &mut inner_spans {
                    span.bold = true;
                }
                spans.extend(inner_spans);
                index = end + 2;
                continue;
            }
        }
        // ④ 斜体 `*...*`
        if chars[index] == '*' {
            if let Some(end) = find_close(&chars, index + 1, "*") {
                if end > index + 1 {
                    flush(&mut plain, &mut spans);
                    let inner: String = chars[index + 1..end].iter().collect();
                    let mut inner_spans = parse_inline(&inner);
                    for span in &mut inner_spans {
                        span.italic = true;
                    }
                    spans.extend(inner_spans);
                    index = end + 1;
                    continue;
                }
            }
        }
        plain.push(chars[index]);
        index += 1;
    }
    flush(&mut plain, &mut spans);
    if spans.is_empty() {
        spans.push(Span::plain(String::new()));
    }
    spans
}

/// 找配对的收尾标记（不跨行：预览按块解析，行内标记不跨块）。
fn find_close(chars: &[char], from: usize, marker: &str) -> Option<usize> {
    let needle: Vec<char> = marker.chars().collect();
    let mut index = from;
    while index + needle.len() <= chars.len() {
        if chars[index..index + needle.len()] == needle[..] {
            return Some(index);
        }
        // 反斜杠转义：跳过下一个字符
        if chars[index] == '\\' {
            index += 2;
            continue;
        }
        index += 1;
    }
    None
}

/// `[文字](目标)` → `(文字, 目标, 吃掉的字符数)`。
fn parse_link(chars: &[char]) -> Option<(String, String, usize)> {
    if chars.first() != Some(&'[') {
        return None;
    }
    let close_bracket = chars.iter().position(|c| *c == ']')?;
    if chars.get(close_bracket + 1) != Some(&'(') {
        return None;
    }
    let close_paren = chars[close_bracket + 2..].iter().position(|c| *c == ')')? + close_bracket + 2;
    let label: String = chars[1..close_bracket].iter().collect();
    let target: String = chars[close_bracket + 2..close_paren].iter().collect();
    Some((label, target, close_paren + 1))
}

/// 解析若干行（`from` 起），返回 `(块列表, 吃掉的行数)`。
fn parse_blocks(lines: &[&str], from: usize) -> (Vec<Block>, usize) {
    let mut blocks: Vec<Block> = Vec::new();
    let mut index = from;

    while index < lines.len() {
        let raw = lines[index];
        let trimmed = raw.trim();

        // 空行：跳过（段落的边界）
        if trimmed.is_empty() {
            index += 1;
            continue;
        }

        // 围栏代码块（``` / ~~~）
        if let Some(fence) = fence_marker(trimmed) {
            let language = trimmed[fence.len()..].trim();
            let start_line = index + 1;
            index += 1;
            let mut body: Vec<&str> = Vec::new();
            while index < lines.len() {
                let candidate = lines[index].trim();
                if candidate.starts_with(&fence) {
                    index += 1;
                    break;
                }
                body.push(lines[index]);
                index += 1;
            }
            blocks.push(Block {
                line: start_line,
                kind: BlockKind::CodeFence {
                    language: if language.is_empty() { None } else { Some(language.to_string()) },
                    // **内容原样**（不做行内解析、也不 trim 掉缩进）
                    text: body.join("\n"),
                },
            });
            continue;
        }

        // 分隔线（`---` / `***` / `___`，三个以上）
        if is_rule(trimmed) {
            blocks.push(Block { line: index + 1, kind: BlockKind::Rule });
            index += 1;
            continue;
        }

        // 标题（ATX）
        if let Some((level, rest)) = atx_heading(trimmed) {
            blocks.push(Block {
                line: index + 1,
                kind: BlockKind::Heading {
                    level,
                    spans: parse_inline(rest.trim_end_matches('#').trim()),
                },
            });
            index += 1;
            continue;
        }

        // 引用（`>`）：把连续的 `>` 行收进 children
        if trimmed.starts_with('>') {
            let start_line = index + 1;
            let mut inner: Vec<String> = Vec::new();
            while index < lines.len() {
                let candidate = lines[index].trim_start();
                if !candidate.starts_with('>') {
                    break;
                }
                inner.push(candidate.trim_start_matches('>').trim_start().to_string());
                index += 1;
            }
            let inner_refs: Vec<&str> = inner.iter().map(String::as_str).collect();
            let (children, _) = parse_blocks(&inner_refs, 0);
            blocks.push(Block {
                line: start_line,
                kind: BlockKind::Quote { children },
            });
            continue;
        }

        // 表格：当前行含 `|`，且下一行是分隔行（`---|---`）
        if trimmed.contains('|') && index + 1 < lines.len() && is_table_separator(lines[index + 1].trim()) {
            let start_line = index + 1;
            let header: Vec<Vec<Span>> = split_row(trimmed).into_iter().map(|cell| parse_inline(&cell)).collect();
            let alignments = parse_alignments(lines[index + 1].trim());
            index += 2;
            let mut rows: Vec<Vec<Vec<Span>>> = Vec::new();
            while index < lines.len() {
                let candidate = lines[index].trim();
                if candidate.is_empty() || !candidate.contains('|') {
                    break;
                }
                rows.push(split_row(candidate).into_iter().map(|cell| parse_inline(&cell)).collect());
                index += 1;
            }
            blocks.push(Block {
                line: start_line,
                kind: BlockKind::Table { alignments, header, rows },
            });
            continue;
        }

        // 列表：`-` / `*` / `+` / `1.` / `1)`
        if let Some(item) = list_marker(raw) {
            let start_line = index + 1;
            let (children, consumed) = parse_list(lines, index, item.indent);
            let _ = start_line;
            blocks.extend(children);
            index += consumed;
            continue;
        }

        // 段落：连续的普通行（软换行**原样保留**）
        let start_line = index + 1;
        let mut buffer: Vec<&str> = Vec::new();
        while index < lines.len() {
            let candidate = lines[index];
            let candidate_trimmed = candidate.trim();
            if candidate_trimmed.is_empty()
                || fence_marker(candidate_trimmed).is_some()
                || is_rule(candidate_trimmed)
                || atx_heading(candidate_trimmed).is_some()
                || candidate_trimmed.starts_with('>')
                || list_marker(candidate).is_some()
            {
                break;
            }
            buffer.push(candidate);
            index += 1;
        }
        if !buffer.is_empty() {
            blocks.push(Block {
                line: start_line,
                kind: BlockKind::Paragraph {
                    spans: parse_inline(&buffer.join("\n")),
                },
            });
        }
    }
    (blocks, index - from)
}

/// 一个列表标记：类型、序号、内容、缩进（空格数）。
struct ListMarker {
    number: Option<u64>,
    content: String,
    indent: usize,
}

fn list_marker(raw: &str) -> Option<ListMarker> {
    let indent = raw.len() - raw.trim_start().len();
    let trimmed = raw.trim_start();
    // 无序
    for marker in ["- ", "* ", "+ "] {
        if let Some(rest) = trimmed.strip_prefix(marker) {
            return Some(ListMarker {
                number: None,
                content: rest.to_string(),
                indent,
            });
        }
    }
    // 有序：`1. ` / `1) `
    let digits: String = trimmed.chars().take_while(|c| c.is_ascii_digit()).collect();
    if !digits.is_empty() {
        let rest = &trimmed[digits.len()..];
        for marker in [". ", ") "] {
            if let Some(content) = rest.strip_prefix(marker) {
                return Some(ListMarker {
                    number: digits.parse().ok(),
                    content: content.to_string(),
                    indent,
                });
            }
        }
    }
    None
}

/// 解析一串列表条目（**含嵌套**：缩进更深的行进 `children`）。
fn parse_list(lines: &[&str], from: usize, base_indent: usize) -> (Vec<Block>, usize) {
    let mut items: Vec<Block> = Vec::new();
    let mut index = from;
    while index < lines.len() {
        let Some(item) = list_marker(lines[index]) else { break };
        if item.indent < base_indent {
            break;
        }
        if item.indent > base_indent {
            // 比本层更深：交给嵌套处理（正常情况下不会走到这里）
            break;
        }
        let line_number = index + 1;
        // 任务列表：`- [x] 内容`
        let (checked, content) = task_prefix(&item.content);
        let spans = parse_inline(&content);
        index += 1;

        // 嵌套：后续缩进更深的列表行 / 或本条目下的块
        let mut children: Vec<Block> = Vec::new();
        while index < lines.len() {
            let Some(next) = list_marker(lines[index]) else { break };
            if next.indent <= base_indent {
                break;
            }
            let (nested, consumed) = parse_list(lines, index, next.indent);
            children.extend(nested);
            index += consumed;
        }
        items.push(Block {
            line: line_number,
            kind: BlockKind::ListItem {
                number: item.number,
                checked,
                spans,
                children,
            },
        });
    }
    (items, index - from)
}

/// `[x] 内容` / `[ ] 内容` ⇒ `(Some(true|false), 内容)`；不是任务项就 `(None, 原文)`。
fn task_prefix(content: &str) -> (Option<bool>, String) {
    let trimmed = content.trim_start();
    for (marker, value) in [("[x] ", true), ("[X] ", true), ("[ ] ", false)] {
        if let Some(rest) = trimmed.strip_prefix(marker) {
            return (Some(value), rest.to_string());
        }
    }
    (None, content.to_string())
}

/// 围栏标记（``` 或 ~~~，三个以上）。
fn fence_marker(trimmed: &str) -> Option<String> {
    for fence in ["```", "~~~"] {
        if trimmed.starts_with(fence) {
            let count = trimmed.chars().take_while(|c| fence.starts_with(*c)).count();
            if count >= 3 {
                return Some(fence.chars().take(count).collect());
            }
        }
    }
    None
}

/// 分隔线：`---` / `***` / `___`（三个以上同一字符，允许中间有空格）。
fn is_rule(trimmed: &str) -> bool {
    let compact: String = trimmed.chars().filter(|c| !c.is_whitespace()).collect();
    if compact.len() < 3 {
        return false;
    }
    let first = compact.chars().next().unwrap_or(' ');
    matches!(first, '-' | '*' | '_') && compact.chars().all(|c| c == first)
}

/// ATX 标题：`## 文字` ⇒ `(2, "文字")`。
fn atx_heading(trimmed: &str) -> Option<(u8, &str)> {
    let hashes = trimmed.chars().take_while(|c| *c == '#').count();
    if hashes == 0 || hashes > 6 {
        return None;
    }
    let rest = &trimmed[hashes..];
    // `#文字` 与 `# 文字` 都认（`#` 之后要么是空白要么直接是内容）
    if !rest.is_empty() && !rest.starts_with(' ') && !rest.starts_with('\t') {
        return None;
    }
    Some((hashes as u8, rest.trim_start()))
}

/// 表格分隔行：`|---|---:|:---:|`
fn is_table_separator(trimmed: &str) -> bool {
    if !trimmed.contains('-') {
        return false;
    }
    let cells = split_row(trimmed);
    !cells.is_empty()
        && cells.iter().all(|cell| {
            let cell = cell.trim();
            let stripped = cell.trim_matches(':');
            !stripped.is_empty() && stripped.chars().all(|c| c == '-')
        })
}

/// 拆一行表格（支持 `\|` 转义；首尾的 `|` 不算空列）。
fn split_row(trimmed: &str) -> Vec<String> {
    let inner = trimmed.trim().trim_start_matches('|').trim_end_matches('|');
    let mut cells: Vec<String> = Vec::new();
    let mut current = String::new();
    let mut escaped = false;
    for ch in inner.chars() {
        if escaped {
            current.push(ch);
            escaped = false;
            continue;
        }
        match ch {
            '\\' => escaped = true,
            '|' => {
                cells.push(current.trim().to_string());
                current = String::new();
            }
            other => current.push(other),
        }
    }
    cells.push(current.trim().to_string());
    cells
}

/// 表格对齐：`:---` 左 / `:---:` 中 / `---:` 右 / `---` 无。
fn parse_alignments(trimmed: &str) -> Vec<ColumnAlignment> {
    split_row(trimmed)
        .iter()
        .map(|cell| {
            let cell = cell.trim();
            let left = cell.starts_with(':');
            let right = cell.ends_with(':');
            match (left, right) {
                (true, true) => ColumnAlignment::Center,
                (true, false) => ColumnAlignment::Left,
                (false, true) => ColumnAlignment::Right,
                (false, false) => ColumnAlignment::None,
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn kinds(document: &Document) -> Vec<&'static str> {
        document
            .blocks
            .iter()
            .map(|block| match block.kind {
                BlockKind::Heading { .. } => "heading",
                BlockKind::Paragraph { .. } => "paragraph",
                BlockKind::CodeFence { .. } => "code",
                BlockKind::ListItem { .. } => "item",
                BlockKind::Table { .. } => "table",
                BlockKind::Quote { .. } => "quote",
                BlockKind::Rule => "rule",
            })
            .collect()
    }

    #[test]
    fn headings_paragraphs_and_rules_with_line_numbers() {
        let document = parse("# 标题\n\n段落第一行\n第二行\n\n---\n");
        assert_eq!(kinds(&document), vec!["heading", "paragraph", "rule"]);
        // 行号（1 起）—— 跟随滚动要用它映射锚点
        assert_eq!(document.blocks[0].line, 1);
        assert_eq!(document.blocks[1].line, 3);
        assert_eq!(document.blocks[2].line, 6);
        // 段落里的软换行**原样保留**
        if let BlockKind::Paragraph { spans } = &document.blocks[1].kind {
            assert_eq!(spans[0].text, "段落第一行\n第二行");
        } else {
            panic!("第二个块应当是段落");
        }
        // 标题级别
        if let BlockKind::Heading { level, spans } = &document.blocks[0].kind {
            assert_eq!(*level, 1);
            assert_eq!(spans[0].text, "标题");
        }
        // 版本号在模型里（结构变了才升）
        assert_eq!(document.version, MARKDOWN_FORMAT_VERSION);
    }

    #[test]
    fn fenced_code_keeps_content_verbatim_and_carries_the_language() {
        let document = parse("```rust\nlet a = **not bold**;\n```\n");
        assert_eq!(kinds(&document), vec!["code"]);
        if let BlockKind::CodeFence { language, text } = &document.blocks[0].kind {
            assert_eq!(language.as_deref(), Some("rust"));
            assert_eq!(text, "let a = **not bold**;", "代码块内容原样，不做行内解析");
        }
        // `~~~` 也认；没有语言串时是 None
        let tilde = parse("~~~\nx\n~~~");
        if let BlockKind::CodeFence { language, .. } = &tilde.blocks[0].kind {
            assert!(language.is_none());
        }
        // 未闭合的围栏 ⇒ 一直吃到文末（不吞内容）
        let open = parse("```\nline1\nline2");
        assert_eq!(kinds(&open), vec!["code"]);
        if let BlockKind::CodeFence { text, .. } = &open.blocks[0].kind {
            assert_eq!(text, "line1\nline2");
        }
    }

    #[test]
    fn lists_with_nesting_and_task_items() {
        let document = parse("- 第一\n- 第二\n  - 嵌套\n- [x] 做完的\n- [ ] 没做的\n");
        assert_eq!(kinds(&document), vec!["item", "item", "item", "item"]);
        // 第三个条目带嵌套
        if let BlockKind::ListItem { spans, children, .. } = &document.blocks[1].kind {
            assert_eq!(spans[0].text, "第二");
            assert_eq!(children.len(), 1, "嵌套条目进 children");
            if let BlockKind::ListItem { spans, .. } = &children[0].kind {
                assert_eq!(spans[0].text, "嵌套");
            }
        }
        // 任务项：复选框**从正文里摘出**（正文里不再留 `[x]` 那串字）
        if let BlockKind::ListItem { checked, spans, .. } = &document.blocks[2].kind {
            assert_eq!(*checked, Some(true));
            assert_eq!(spans[0].text, "做完的", "正文里不该再有 [x]");
        }
        if let BlockKind::ListItem { checked, spans, .. } = &document.blocks[3].kind {
            assert_eq!(*checked, Some(false));
            assert_eq!(spans[0].text, "没做的");
        }
        // 有序列表带序号
        let ordered = parse("1. 甲\n2. 乙\n");
        if let BlockKind::ListItem { number, .. } = &ordered.blocks[0].kind {
            assert_eq!(*number, Some(1));
        }
        if let BlockKind::ListItem { number, .. } = &ordered.blocks[1].kind {
            assert_eq!(*number, Some(2));
        }
    }

    #[test]
    fn tables_with_alignment_and_escaped_pipes() {
        let document = parse("| 左 | 中 | 右 |\n|:---|:---:|---:|\n| a | b | c |\n| d\\|e | f | g |\n");
        assert_eq!(kinds(&document), vec!["table"]);
        if let BlockKind::Table { alignments, header, rows } = &document.blocks[0].kind {
            assert_eq!(alignments, &vec![ColumnAlignment::Left, ColumnAlignment::Center, ColumnAlignment::Right]);
            assert_eq!(header.len(), 3);
            assert_eq!(header[1][0].text, "中");
            assert_eq!(rows.len(), 2);
            // `\|` 转义：竖线留在单元格里，不当分隔符
            assert_eq!(rows[1][0][0].text, "d|e");
        }
    }

    #[test]
    fn quotes_and_unsupported_syntax_passes_through_as_text() {
        let document = parse("> 引用第一行\n> 引用第二行\n");
        assert_eq!(kinds(&document), vec!["quote"]);
        if let BlockKind::Quote { children } = &document.blocks[0].kind {
            assert_eq!(children.len(), 1);
            if let BlockKind::Paragraph { spans } = &children[0].kind {
                assert_eq!(spans[0].text, "引用第一行\n引用第二行");
            }
        }
        // **明确不支持**的几种：原样当文本搬运（不吞不改）
        let setext = parse("标题\n===\n");
        assert_eq!(kinds(&setext), vec!["paragraph"], "Setext 标题不支持：按段落走");
        let html = parse("<div>原样</div>\n");
        assert_eq!(kinds(&html), vec!["paragraph"]);
        if let BlockKind::Paragraph { spans } = &html.blocks[0].kind {
            assert_eq!(spans[0].text, "<div>原样</div>", "HTML 块原样搬运");
        }
        let indented = parse("    四空格起的代码\n");
        assert_eq!(kinds(&indented), vec!["paragraph"], "缩进式代码块不支持：按段落走");
        // 引用里的惰性续行不支持（需要逐行显式 `>`）
        let lazy = parse("> 引用\n普通行\n");
        assert_eq!(kinds(&lazy), vec!["quote", "paragraph"]);
    }

    #[test]
    fn inline_spans_cover_the_common_writings() {
        let spans = parse_inline("普通 **粗** 与 *斜* 与 `代码` 与 [链接](https://x)");
        let find = |text: &str| spans.iter().find(|s| s.text == text).cloned();
        assert!(find("粗").unwrap().bold);
        assert!(find("斜").unwrap().italic);
        assert!(find("代码").unwrap().code);
        assert_eq!(find("链接").unwrap().target.as_deref(), Some("https://x"));
        // 普通文字也在（首尾相接）
        assert!(find("普通 ").is_some());
        // 代码里的星号不算强调（代码优先）
        let code_first = parse_inline("`a*b*c`");
        assert_eq!(code_first.len(), 1);
        assert!(code_first[0].code);
        assert_eq!(code_first[0].text, "a*b*c");
        // 未闭合的强调原样留着（不吞掉后面的字）
        let unclosed = parse_inline("**没闭合 后面");
        assert_eq!(unclosed.len(), 1);
        assert_eq!(unclosed[0].text, "**没闭合 后面");
        assert!(!unclosed[0].bold);
        // 空输入也给一个空 span（界面不用判 None）
        assert_eq!(parse_inline("").len(), 1);
        assert_eq!(parse_inline("").remove(0).text, "");
    }

    #[test]
    fn parsing_is_deterministic_and_serialises_with_the_version() {
        let text = "# 标题\n\n- a\n- b\n\n| x | y |\n|---|---|\n| 1 | 2 |\n";
        let first = parse(text);
        let second = parse(text);
        assert_eq!(first, second, "同样输入必须同样输出（纯函数）");
        let json = serde_json::to_string(&first).unwrap();
        assert!(json.contains("\"version\""), "{json}");
        let back: Document = serde_json::from_str(&json).unwrap();
        assert_eq!(back, first);
        // 模型里有**没有可编辑控件**这一条是结构性的：块类型里根本没有 input 之类的成员
        assert!(!json.contains("input") && !json.contains("editable"), "预览模型里不该有可编辑控件");
    }
}
