//! Retro 周报包的**领域口径**（FR-R-12-01 / FR-R-12-02 / FR-R-13-08 的 M0 只读面）
//!
//! 口径来源 = `Docs/需求规范书.md` §3.14（`FR-R-12-04` / `FR-R-13-03` / `FR-R-13-08`）：
//! 一个周报包 = **目录名即期号** + 三件固定（`index.json` / `report.md` / `assets/`）。
//!
//! 本模块只做**纯判定**（读盘在外壳 `App/src-tauri/src/retro_library.rs`）：
//!
//! 1. 卡片字段从 `index.json` 取，**缺字段不猜**：「读不出来」与「空字符串」是两件事，
//!    前者进 `problems` 逐条报（`FR-R-12-04` ③「导入失败逐条报告…不写半截」）；
//! 2. 缺 `index.json` / 缺 `report.md` / JSON 坏 / 标题空 ⇒ 这一期**不进列表**且报一条，
//!    宁可少画一张卡，也不画一张点开是空白的卡；
//! 3. 媒体路径**只认包内相对路径**（`assets/x.png`）：`..`、绝对路径、反斜杠、非白名单后缀一律拒
//!    —— 视图要拿它去读盘，越界就等于「周报包」能读整台机器（`FR-R-13-09` ④ 路径越界）；
//! 4. 排序是**确定性**的：按生成时间倒序、同期用期号倒序兜底（两次读同一批包，顺序一样）。

/// 媒体白名单后缀（`FR-R-13-09`：图片按 `IR-05`；视频只认 `mp4` / H.264 + AAC）。
pub const IMAGE_EXTENSIONS: &[&str] = &["png", "jpg", "jpeg", "webp", "gif"];
/// 视频白名单后缀（本地内联播放只认这两种容器）。
pub const VIDEO_EXTENSIONS: &[&str] = &["mp4", "m4v"];
/// 包内资源目录名（契约三件之一）。
pub const ASSET_DIR: &str = "assets";
/// 包内元数据文件名。
pub const INDEX_FILE: &str = "index.json";
/// 包内正文文件名。
pub const REPORT_FILE: &str = "report.md";

/// 一张卡片（左侧列表的一项；字段与 `FR-R-13-08` ① 一一对应）。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Card {
    /// 期号（= 目录名；排序键与「打开哪一期」的键）。
    pub period: String,
    /// 标题（`index.json` 的 `title`）。
    pub title: String,
    /// 日期范围起点（`YYYY-MM-DD`；包里没写就是空串 —— 界面如实显示「未标注」）。
    pub date_start: String,
    /// 日期范围终点。
    pub date_end: String,
    /// 标签（去重、去空白，保持原顺序）。
    pub tags: Vec<String>,
    /// 封面（包内相对路径，已过白名单；没有 / 不合法 ⇒ `None`）。
    pub cover: Option<String>,
    /// 生成时间（包的 `generatedAt` / `publishedAt`；没写就是空串）。
    pub generated_at: String,
}

/// 一处「读不出来」（逐条报，不让整批失败）。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Problem {
    /// 出问题的期号（目录名；目录名本身不合法时是原样的目录名）。
    pub period: String,
    /// 可读原因（不是 `error` 一行）。
    pub message: String,
}

/// 一个包的**盘上事实**（目录名 + 两个文件的内容 / 在否）—— 由外壳填，本层只判。
pub struct Source<'a> {
    /// 目录名（= 期号）。
    pub dir_name: &'a str,
    /// `index.json` 的文本；文件不在就是 `None`。
    pub index_json: Option<&'a str>,
    /// `report.md` 在不在（内容本层不需要）。
    pub has_report: bool,
    /// `assets/` 下的文件名清单（只用于校验封面在不在）。
    pub assets: &'a [String],
}

/// 期号是否可用作目录名 / 打开键。
///
/// 要求：非空、≤64 字符、不含路径分隔符与 `..`、不含控制字符、不是 `.` / `..`。
/// 为什么这条要单独成函数：期号会**回传给外壳去拼路径**（打开某一期），它是唯一一个
/// 从界面回到盘上的字符串 —— 放行一次就够读包外的文件。
pub fn validate_period(name: &str) -> Result<(), String> {
    let trimmed = name.trim();
    if trimmed.is_empty() {
        return Err("期号为空".to_string());
    }
    if trimmed != name {
        return Err("期号首尾带空白".to_string());
    }
    if trimmed.chars().count() > 64 {
        return Err(format!("期号过长（{} 字符，上限 64）", trimmed.chars().count()));
    }
    if trimmed == "." || trimmed == ".." {
        return Err("期号不能是 . 或 ..".to_string());
    }
    if trimmed.contains('/') || trimmed.contains('\\') {
        return Err("期号里不能有路径分隔符".to_string());
    }
    if trimmed.contains("..") {
        return Err("期号里不能有 ..".to_string());
    }
    if trimmed.chars().any(|c| c.is_control()) {
        return Err("期号里不能有控制字符".to_string());
    }
    Ok(())
}

/// 校验一份媒体 / 封面路径，回**规范化后的相对路径**。
///
/// 只接受 `assets/<文件名>`：反斜杠、绝对路径、`.` / `..` 段、白名单外后缀一律拒。
pub fn normalize_asset_path(raw: &str) -> Result<String, String> {
    let text = raw.trim();
    if text.is_empty() {
        return Err("路径为空".to_string());
    }
    if text.contains('\\') {
        return Err(format!("路径里出现反斜杠（{text}）：包内路径一律用 /"));
    }
    if text.starts_with('/') || text.split(':').next().map(|s| s.len()).unwrap_or(0) == 1 {
        return Err(format!("路径是绝对路径（{text}）：只允许包内相对路径"));
    }
    let segments: Vec<&str> = text.split('/').collect();
    if segments.iter().any(|s| *s == "..") {
        return Err(format!("路径越出包目录（{text}）：不允许 .."));
    }
    if segments.iter().any(|s| s.is_empty() || *s == ".") {
        return Err(format!("路径里有空段（{text}）"));
    }
    if segments.len() < 2 || segments[0] != ASSET_DIR {
        return Err(format!("路径不在 {ASSET_DIR}/ 下（{text}）"));
    }
    let file = segments[segments.len() - 1];
    let ext = file
        .rsplit_once('.')
        .map(|(_, e)| e.to_ascii_lowercase())
        .unwrap_or_default();
    let allowed = IMAGE_EXTENSIONS.contains(&ext.as_str()) || VIDEO_EXTENSIONS.contains(&ext.as_str());
    if !allowed {
        return Err(format!("后缀不在白名单（{text}）：只认图片与 mp4 / m4v"));
    }
    Ok(text.to_string())
}

/// 一段 JSON 里取字符串（同时认 camelCase 与 snake_case）。
fn pick_str<'a>(value: &'a serde_json::Value, keys: &[&str]) -> Option<&'a str> {
    for key in keys {
        if let Some(found) = value.get(*key).and_then(|v| v.as_str()) {
            let trimmed = found.trim();
            if !trimmed.is_empty() {
                return Some(trimmed);
            }
        }
    }
    None
}

/// 日期范围：认 `{ "start": "...", "end": "..." }`、`"2026-10-12 ~ 2026-10-18"`
/// 与平铺的 `dateStart` / `dateEnd` 三种写法（**都写在契约里**过的形状，不是猜的）。
fn parse_range(value: &serde_json::Value) -> (String, String) {
    if let Some(range) = value.get("dateRange") {
        if let Some(pair) = range.as_object() {
            let start = pair.get("start").and_then(|v| v.as_str()).unwrap_or("").trim().to_string();
            let end = pair.get("end").and_then(|v| v.as_str()).unwrap_or("").trim().to_string();
            return (start, end);
        }
        if let Some(text) = range.as_str() {
            let (start, end) = split_range_text(text);
            return (start, end);
        }
    }
    let start = pick_str(value, &["dateStart", "date_start", "start"]).unwrap_or("").to_string();
    let end = pick_str(value, &["dateEnd", "date_end", "end"]).unwrap_or("").to_string();
    (start, end)
}

/// `2026-10-12 ~ 2026-10-18` / `2026-10-12 - 2026-10-18` / `2026-10-12…2026-10-18` 三种分隔符。
fn split_range_text(text: &str) -> (String, String) {
    for sep in ["~", "～", "…", "—", " - "] {
        if let Some((left, right)) = text.split_once(sep) {
            return (left.trim().to_string(), right.trim().to_string());
        }
    }
    let only = text.trim().to_string();
    (only.clone(), only)
}

/// 标签：只认字符串数组（也认单字符串），去空白、去重、保序。
fn parse_tags(value: &serde_json::Value) -> Vec<String> {
    let raw: Vec<String> = match value.get("tags") {
        Some(serde_json::Value::Array(items)) => items
            .iter()
            .filter_map(|v| v.as_str())
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect(),
        Some(serde_json::Value::String(text)) => text
            .split([',', '，', ' '])
            .map(|s| s.trim().trim_start_matches('#').trim().to_string())
            .filter(|s| !s.is_empty())
            .collect(),
        _ => Vec::new(),
    };
    let mut out: Vec<String> = Vec::new();
    for tag in raw {
        if !out.contains(&tag) {
            out.push(tag);
        }
    }
    out
}

/// 判一个包：要么 `(卡片, 若干小毛病)`，要么一条「这一期画不出来」的 problem。
///
/// 两种毛病的区别是**要不要画卡**：缺 `index.json` / 缺 `report.md` / JSON 坏 / 没标题
/// ⇒ 不画；期号与目录名不一致、封面缺失或越界 ⇒ 照画，但如实说一句（正文仍值得看）。
pub fn card_of(source: &Source<'_>) -> Result<(Card, Vec<String>), Problem> {
    let period = source.dir_name.trim().to_string();
    let mut extra: Vec<String> = Vec::new();

    if let Err(reason) = validate_period(source.dir_name) {
        return Err(Problem { period, message: format!("目录名不能当期号：{reason}") });
    }
    let Some(text) = source.index_json else {
        return Err(Problem {
            period,
            message: format!("缺 {INDEX_FILE}：这个目录不算一个周报包"),
        });
    };
    if !source.has_report {
        return Err(Problem {
            period,
            message: format!("缺 {REPORT_FILE}：包不完整，这一期不列出来"),
        });
    }
    let value: serde_json::Value = match serde_json::from_str(text) {
        Ok(value) => value,
        Err(error) => {
            return Err(Problem {
                period,
                message: format!("{INDEX_FILE} 不是合法 JSON：{error}"),
            })
        }
    };
    let Some(title) = pick_str(&value, &["title", "name"]).map(|s| s.to_string()) else {
        return Err(Problem {
            period,
            message: format!("{INDEX_FILE} 里没有 title：标题空着就不画卡（宁缺勿猜）"),
        });
    };

    if let Some(declared) = pick_str(&value, &["period"]) {
        if declared != period {
            extra.push(format!("{INDEX_FILE} 写的期号是 {declared}，与目录名不一致；按目录名显示"));
        }
    }

    let (date_start, date_end) = parse_range(&value);
    let generated_at = pick_str(&value, &["generatedAt", "generated_at", "publishedAt", "published_at", "createdAt"])
        .unwrap_or("")
        .to_string();

    let cover = match pick_str(&value, &["cover", "coverImage", "cover_image"]) {
        None => None,
        Some(raw) => match normalize_asset_path(raw) {
            Ok(path) => {
                let file = path.rsplit('/').next().unwrap_or("").to_string();
                if !source.assets.iter().any(|name| name == &file) {
                    extra.push(format!("封面 {path} 不在包里：这一期先不显示封面"));
                    None
                } else {
                    Some(path)
                }
            }
            Err(reason) => {
                extra.push(format!("封面路径不合法：{reason}"));
                None
            }
        },
    };

    Ok((
        Card {
            period,
            title,
            date_start,
            date_end,
            tags: parse_tags(&value),
            cover,
            generated_at,
        },
        extra,
    ))
}

/// 一批包 → 卡片清单 + 逐条问题。
///
/// 返回的卡片按「生成时间倒序 → 期号倒序」排；问题按 `(期号, 原因)` 排，
/// 这样两次读同一批包得到逐字一样的输出（界面不会因盘上遍历顺序跳）。
pub fn collect(sources: &[Source<'_>]) -> (Vec<Card>, Vec<Problem>) {
    let mut cards: Vec<Card> = Vec::new();
    let mut problems: Vec<Problem> = Vec::new();
    for source in sources {
        match card_of(source) {
            Ok((card, notes)) => {
                for note in notes {
                    problems.push(Problem { period: card.period.clone(), message: note });
                }
                cards.push(card);
            }
            Err(problem) => problems.push(problem),
        }
    }
    cards.sort_by(|a, b| {
        b.generated_at
            .cmp(&a.generated_at)
            .then_with(|| b.period.cmp(&a.period))
    });
    problems.sort_by(|a, b| a.period.cmp(&b.period).then_with(|| a.message.cmp(&b.message)));
    (cards, problems)
}

/// 把 `report.md` 的字节解成文本。
///
/// - 去 BOM（Windows 记事本存的 UTF-8 常带 BOM，留着会让首个标题渲染成 `#` 前面多一个怪字符）；
/// - 非 UTF-8 ⇒ **可读原因**（说清是编码问题、在哪一段），不是 `invalid utf-8` 一行。
pub fn decode_report(bytes: &[u8]) -> Result<String, String> {
    if bytes.is_empty() {
        return Err(format!("{REPORT_FILE} 是空文件"));
    }
    let body = bytes.strip_prefix(&[0xEF, 0xBB, 0xBF]).unwrap_or(bytes);
    match std::str::from_utf8(body) {
        Ok(text) => Ok(text.to_string()),
        Err(error) => Err(format!(
            "{REPORT_FILE} 不是 UTF-8（第 {} 字节处断开）：请把这份正文另存为 UTF-8 再放进包里",
            error.valid_up_to()
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn source<'a>(dir: &'a str, index: Option<&'a str>, report: bool, assets: &'a [String]) -> Source<'a> {
        Source { dir_name: dir, index_json: index, has_report: report, assets }
    }

    #[test]
    fn a_complete_package_becomes_a_card_with_every_field() {
        let index = r#"{
            "period": "2026-W42",
            "title": "芯片与半导体 · 第 42 周",
            "dateRange": { "start": "2026-10-12", "end": "2026-10-18" },
            "tags": ["周报", "半导体", "周报"],
            "cover": "assets/cover.png",
            "generatedAt": "2026-10-18T09:30:00+08:00"
        }"#;
        let assets = vec!["cover.png".to_string(), "chart-1.png".to_string()];
        let (cards, problems) = collect(&[source("2026-W42", Some(index), true, &assets)]);
        assert_eq!(problems, Vec::<Problem>::new());
        assert_eq!(cards.len(), 1);
        let card = &cards[0];
        assert_eq!(card.period, "2026-W42");
        assert_eq!(card.title, "芯片与半导体 · 第 42 周");
        assert_eq!(card.date_start, "2026-10-12");
        assert_eq!(card.date_end, "2026-10-18");
        // 重复标签只留一枚，顺序不变
        assert_eq!(card.tags, vec!["周报".to_string(), "半导体".to_string()]);
        assert_eq!(card.cover.as_deref(), Some("assets/cover.png"));
        assert_eq!(card.generated_at, "2026-10-18T09:30:00+08:00");
    }

    #[test]
    fn a_missing_index_file_is_reported_and_the_package_is_not_listed() {
        let (cards, problems) = collect(&[source("2026-W41", None, true, &[])]);
        assert!(cards.is_empty());
        assert_eq!(problems.len(), 1);
        assert_eq!(problems[0].period, "2026-W41");
        assert!(problems[0].message.contains("index.json"), "{}", problems[0].message);
    }

    #[test]
    fn a_missing_report_is_reported_and_the_package_is_not_listed() {
        let index = r#"{"title":"有标题但没正文"}"#;
        let (cards, problems) = collect(&[source("2026-W40", Some(index), false, &[])]);
        assert!(cards.is_empty(), "缺正文的包不该画成一张能点开的卡");
        assert_eq!(problems.len(), 1);
        assert!(problems[0].message.contains("report.md"), "{}", problems[0].message);
    }

    #[test]
    fn broken_json_is_reported_with_the_parser_reason() {
        let (cards, problems) = collect(&[source("2026-W39", Some("{ title: "), true, &[])]);
        assert!(cards.is_empty());
        assert_eq!(problems.len(), 1);
        assert!(problems[0].message.contains("不是合法 JSON"), "{}", problems[0].message);
    }

    #[test]
    fn a_package_without_a_title_is_not_listed() {
        let index = r#"{"title":"   ","period":"2026-W38"}"#;
        let (cards, problems) = collect(&[source("2026-W38", Some(index), true, &[])]);
        assert!(cards.is_empty(), "空标题会让列表出一行没有名字的卡");
        assert_eq!(problems.len(), 1);
        assert!(problems[0].message.contains("title"), "{}", problems[0].message);
    }

    #[test]
    fn a_cover_pointing_out_of_the_package_is_dropped_with_a_reason() {
        let index = r#"{"title":"越界封面","cover":"../../Users/Alex/secret.png"}"#;
        let (cards, problems) = collect(&[source("2026-W37", Some(index), true, &[])]);
        assert_eq!(cards.len(), 1, "封面坏了不该连正文一起不给看");
        assert_eq!(cards[0].cover, None);
        assert_eq!(problems.len(), 1);
        assert!(problems[0].message.contains("封面路径不合法"), "{}", problems[0].message);
    }

    #[test]
    fn a_cover_file_that_is_not_in_the_package_is_reported() {
        let index = r#"{"title":"封面没落盘","cover":"assets/cover.png"}"#;
        let (cards, problems) = collect(&[source("2026-W36", Some(index), true, &[])]);
        assert_eq!(cards.len(), 1);
        assert_eq!(problems.len(), 1);
        assert!(problems[0].message.contains("不在包里"), "{}", problems[0].message);
    }

    #[test]
    fn cards_are_sorted_newest_first_and_ties_fall_back_to_the_period() {
        let older = r#"{"title":"旧","generatedAt":"2026-10-01T00:00:00+08:00"}"#;
        let newer = r#"{"title":"新","generatedAt":"2026-10-18T00:00:00+08:00"}"#;
        let same_a = r#"{"title":"同 A","generatedAt":"2026-10-10T00:00:00+08:00"}"#;
        let same_b = r#"{"title":"同 B","generatedAt":"2026-10-10T00:00:00+08:00"}"#;
        let (cards, _) = collect(&[
            source("2026-W01", Some(older), true, &[]),
            source("2026-W42", Some(newer), true, &[]),
            source("2026-W20", Some(same_b), true, &[]),
            source("2026-W21", Some(same_a), true, &[]),
        ]);
        let periods: Vec<&str> = cards.iter().map(|c| c.period.as_str()).collect();
        assert_eq!(periods, vec!["2026-W42", "2026-W21", "2026-W20", "2026-W01"]);
    }

    #[test]
    fn a_date_range_written_as_text_is_split_in_two() {
        let index = r#"{"title":"文字区间","dateRange":"2026-10-12 ~ 2026-10-18"}"#;
        let (cards, _) = collect(&[source("2026-W35", Some(index), true, &[])]);
        assert_eq!(cards[0].date_start, "2026-10-12");
        assert_eq!(cards[0].date_end, "2026-10-18");
    }

    #[test]
    fn a_flat_date_range_is_understood_too() {
        let index = r#"{"title":"平铺区间","dateStart":"2026-10-05","dateEnd":"2026-10-11"}"#;
        let (cards, _) = collect(&[source("2026-W34", Some(index), true, &[])]);
        assert_eq!(cards[0].date_start, "2026-10-05");
        assert_eq!(cards[0].date_end, "2026-10-11");
    }

    #[test]
    fn a_directory_name_that_could_escape_the_package_root_is_refused() {
        for name in ["..", "a/b", "a\\b", ".", "", " 2026-W42", "2026..W42"] {
            let index = r#"{"title":"坏名字"}"#;
            let (cards, problems) = collect(&[source(name, Some(index), true, &[])]);
            assert!(cards.is_empty(), "目录名 {name:?} 不该能当期号");
            assert_eq!(problems.len(), 1, "目录名 {name:?} 该报一条");
        }
    }

    #[test]
    fn asset_paths_accept_only_relative_paths_inside_assets() {
        assert_eq!(normalize_asset_path("assets/a.png").unwrap(), "assets/a.png");
        assert_eq!(normalize_asset_path("assets/video.mp4").unwrap(), "assets/video.mp4");
        for bad in [
            "",
            "/etc/passwd",
            "C:/Users/Alex/a.png",
            "assets/../../a.png",
            "assets//a.png",
            "cover.png",
            "assets/a.avi",
            "assets\\a.png",
        ] {
            assert!(normalize_asset_path(bad).is_err(), "{bad:?} 不该通过");
        }
    }

    #[test]
    fn a_report_saved_with_a_windows_bom_is_read_without_it() {
        let mut bytes = vec![0xEF, 0xBB, 0xBF];
        bytes.extend_from_slice("# 本期".as_bytes());
        assert_eq!(decode_report(&bytes).unwrap(), "# 本期");
    }

    #[test]
    fn a_report_that_is_not_utf8_says_where_it_breaks() {
        let bytes = vec![b'#', b' ', 0xFF, 0xFE, b'x'];
        let message = decode_report(&bytes).unwrap_err();
        assert!(message.contains("不是 UTF-8"), "{message}");
        assert!(message.contains('2'), "{message}");
    }

    #[test]
    fn an_empty_report_is_refused_instead_of_rendered_as_blank() {
        assert!(decode_report(&[]).unwrap_err().contains("空文件"));
    }

    #[test]
    fn the_same_batch_twice_gives_byte_identical_output() {
        let index = r#"{"title":"稳定","generatedAt":"2026-10-10T00:00:00Z","tags":"周报, 半导体"}"#;
        let sources = [
            source("2026-W20", Some(index), true, &[]),
            source("2026-W21", None, true, &[]),
        ];
        let (cards_a, problems_a) = collect(&sources);
        let (cards_b, problems_b) = collect(&sources);
        assert_eq!(cards_a, cards_b);
        assert_eq!(problems_a, problems_b);
        assert_eq!(cards_a[0].tags, vec!["周报".to_string(), "半导体".to_string()]);
    }
}
