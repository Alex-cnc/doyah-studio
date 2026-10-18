//! 偏移空间换算：**领域层用字节偏移，界面用 JS 字符串下标**（UTF-16 码元）。
//!
//! 为什么需要这个模块（真缺陷，不是洁癖）：领域层的 `sql::tokenize` / `highlight::tokenize` 给的是
//! **字节**偏移（Rust 切片的天然口径），而前端 `String.prototype.slice` 的索引是 **UTF-16 码元**。
//! 两者在纯 ASCII 上恰好相等，于是一直没被发现；一旦 SQL 里有中文注释 / 中文字符串 / 表情，
//! 每个汉字（UTF-8 3 字节、UTF-16 1 码元）就多算 2，高亮片段从头歪到尾 ——
//! 用户看到的是「写了句中文注释，下面整段颜色乱了」。
//!
//! 口径（三条）：
//!   ① **换算只做在 IPC 边界**（`highlight_sql` / `diagnose_sql`）：领域层内部保持字节偏移，
//!      前端拿到的 `start` / `end` 一律是可以直接 `slice` 的 JS 下标；
//!   ② **只对字符边界有意义**：给的偏移落在多字节字符中间时，退化成「它左边那个字符边界」，
//!      不 panic、不返 `None`（脏数据只该让颜色难看一点，不该让编辑器白屏）；
//!   ③ 换算表一次建好 O(n)、之后 O(1) 查，避免「每个 token 都从文首数一遍」的 O(n²)。
//!
//! 与 `lint.rs` 的关系：`lint::diagnose` 内部产出的是**字符下标**（码点），本模块的
//! `char_to_utf16_map` 就是把它换成 JS 下标的那一步 —— 两者在 BMP 字符上数值相同，
//! 差别只在表情这类「一个码点占两个 UTF-16 码元」的字符上。

/// 字节偏移 → UTF-16 码元下标 的查找表（长度 = `text.len() + 1`）。
///
/// `map[i]` 是「字节偏移 `i` 对应的 JS 下标」；非字符边界的 `i` 取它左侧最近的字符边界值。
pub fn byte_to_utf16_map(text: &str) -> Vec<usize> {
    let mut map = vec![0usize; text.len() + 1];
    let mut bytes = 0usize;
    let mut units = 0usize;
    for ch in text.chars() {
        let len = ch.len_utf8();
        for offset in 0..len {
            map[bytes + offset] = units;
        }
        bytes += len;
        units += ch.len_utf16();
    }
    map[text.len()] = units;
    map
}

/// 字节偏移 → JS 下标（越界夹到表尾；见口径②）。
pub fn byte_to_utf16(map: &[usize], byte: usize) -> usize {
    match map.get(byte) {
        Some(value) => *value,
        None => map.last().copied().unwrap_or(0),
    }
}

/// 字符下标（码点）→ UTF-16 码元下标 的查找表（长度 = 字符数 + 1）。
pub fn char_to_utf16_map(text: &str) -> Vec<usize> {
    let count = text.chars().count();
    let mut map = Vec::with_capacity(count + 1);
    let mut units = 0usize;
    map.push(0);
    for ch in text.chars() {
        units += ch.len_utf16();
        map.push(units);
    }
    map
}

/// 字符下标 → JS 下标（越界夹到表尾）。
pub fn char_to_utf16(map: &[usize], index: usize) -> usize {
    match map.get(index) {
        Some(value) => *value,
        None => map.last().copied().unwrap_or(0),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ascii_offsets_are_identity() {
        let text = "select 1 from t";
        let map = byte_to_utf16_map(text);
        for index in 0..=text.len() {
            assert_eq!(map[index], index, "纯 ASCII 上两套口径必须相等");
        }
    }

    #[test]
    fn chinese_counts_one_unit_per_character_not_three_bytes() {
        let text = "-- 中文注释\nselect";
        let map = byte_to_utf16_map(text);
        // 注释部分：`-- ` 3 字节 + 4 个汉字 12 字节 = 15 字节 ⇒ JS 下标 7
        assert_eq!(byte_to_utf16(&map, 15), 7, "中文按码元算，不按字节算");
        // `select` 的起点
        assert_eq!(byte_to_utf16(&map, 16), 8);
        assert_eq!(byte_to_utf16(&map, text.len()), 14);
    }

    #[test]
    fn emoji_takes_two_units_so_char_and_js_indices_differ() {
        let text = "a😀b";
        let byte_map = byte_to_utf16_map(text);
        assert_eq!(byte_to_utf16(&byte_map, 1), 1, "表情起点在 JS 下标 1");
        assert_eq!(byte_to_utf16(&byte_map, 5), 3, "表情占 4 字节 / 2 码元");
        let char_map = char_to_utf16_map(text);
        assert_eq!(char_map, vec![0, 1, 3, 4], "码点下标 2 ⇒ JS 下标 3");
    }

    #[test]
    fn offsets_inside_a_multibyte_character_degrade_left_instead_of_panicking() {
        let text = "中";
        let map = byte_to_utf16_map(text);
        // 字节 1 / 2 落在汉字中间：退化成它左边的字符边界（0）
        assert_eq!(byte_to_utf16(&map, 1), 0);
        assert_eq!(byte_to_utf16(&map, 2), 0);
        assert_eq!(byte_to_utf16(&map, 3), 1);
        // 越界夹到表尾
        assert_eq!(byte_to_utf16(&map, 999), 1);
        assert_eq!(char_to_utf16(&char_to_utf16_map(text), 999), 1);
    }

    #[test]
    fn sql_tokens_after_a_chinese_comment_land_on_js_boundaries() {
        // 这条守的是真缺陷：字节口径下，中文注释之后的关键字会被切歪（错色 / 丢字符）
        let sql = "select 1 -- 中文注释\nselect '😀' from t";
        let tokens = crate::sql::tokenize(sql);
        assert!(!tokens.is_empty());
        let map = byte_to_utf16_map(sql);
        let units: Vec<u16> = sql.encode_utf16().collect();
        let slice = |start: usize, end: usize| String::from_utf16(&units[start..end]).expect("UTF-16 切片");
        let rendered: Vec<(String, crate::sql::TokenKind)> = tokens
            .iter()
            .map(|token| {
                let text = slice(byte_to_utf16(&map, token.start), byte_to_utf16(&map, token.end));
                (text, token.kind)
            })
            .collect();
        // 每段文本都必须是原文的真实片段（不歪、不丢字）
        for (text, _) in &rendered {
            assert!(sql.contains(text.as_str()), "切出来的片段必须真的在原文里：{:?}", text);
        }
        use crate::sql::TokenKind;
        assert!(
            rendered.iter().any(|(text, kind)| text == "from" && *kind == TokenKind::Keyword),
            "中文注释 + 表情之后的关键字仍要被认出来：{:?}",
            rendered
        );
        assert!(
            rendered
                .iter()
                .any(|(text, kind)| text == "-- 中文注释" && *kind == TokenKind::LineComment),
            "中文行注释整段是一段注释：{:?}",
            rendered
        );
    }
}
