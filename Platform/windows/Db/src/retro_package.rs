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
    /// 发布日（`index.json` 的 `published`，`IR-05` 不变量 4 的契约字段）。
    ///
    /// 与 `generated_at` **不是一件事**：`published` 是「这份周报对外发布的日期」（契约必填），
    /// `generatedAt` 是「生成侧跑完那一刻的墙上时间」（契约没要求、生成侧自愿写）。
    /// 早先这里把 `publishedAt` 当生成时间兜底 ⇒ 真包（只写 `published`）在卡片上**一个时间都读不出来**，
    /// 而「拿发布日冒充生成时间」又会把两件事混成一件 —— 所以拆成两个字段，各显示各的。
    pub published: String,
    /// 日期范围起点（`YYYY-MM-DD`；包里没写就按期号推导，推导不出才是空串 —— 界面如实显示「未标注」）。
    pub date_start: String,
    /// 日期范围终点。
    pub date_end: String,
    /// 标签（去重、去空白，保持原顺序）。
    pub tags: Vec<String>,
    /// 封面（包内相对路径，已过白名单；没有 / 不合法 ⇒ `None`）。
    pub cover: Option<String>,
    /// 生成时间（包的 `generatedAt` / `createdAt`；没写就是空串）。
    ///
    /// **不再拿 `published` 兜底**：契约只要求 `published`，把它显示成「生成」就是换了意思。
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

/// 导入一个周报包的结果态（`FR-R-12-04` ① / ③）。
///
/// 判定在领域层，**逐字节比较与拷贝在外壳**（`App/src-tauri/src/retro_library.rs`）：
/// 本层只回答「同名期已存在时该怎么办」这一条口径问题。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ImportState {
    /// 这一次真的复制进来了。
    Imported,
    /// 落点已有同名期且**内容逐字节相同** ⇒ 幂等：不新增条目、不覆盖（①）。
    Already,
    /// 落点已有同名期但内容不同 ⇒ 判冲突，**不覆盖用户的包**。
    Conflict,
    /// 包本身不合法（缺 `index.json` / 缺 `report.md` / 编码错 / 期号不合法）⇒ 一个字节都不写（③）。
    Rejected,
    /// 复制中途失败（磁盘 / 权限）：临时目录已删除，目标目录不存在。
    Failed,
}

/// 落点已有同名期时的裁决：内容相同 ⇒ 幂等；不同 ⇒ 冲突（**永不覆盖**）。
pub fn existing_decision(same_bytes: bool) -> ImportState {
    if same_bytes {
        ImportState::Already
    } else {
        ImportState::Conflict
    }
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
///
/// 包里**一个范围字段都没写**时返回 `("", "")` —— 由调用方按期号推导（见 `period_range`），
/// 这里不擅自编一个区间。
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

/// 公历日期 → 距 1970-01-01 的天数（Howard Hinnant 的 `days_from_civil`：纯整数、无依赖，
/// `Db` 只依赖 `serde`，不为一个日期算术引 chrono）。
fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let year = year - i64::from(month <= 2);
    let era = if year >= 0 { year } else { year - 399 } / 400;
    let yoe = year - era * 400;
    let mp = (month + 9) % 12;
    let doy = (153 * mp + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// 天数 → 公历 `(年, 月, 日)`（同一套算法的反向）。
fn civil_from_days(days: i64) -> (i64, i64, i64) {
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let year = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    (year + i64::from(month <= 2), month, day)
}

/// ISO 星期（周一 = 1 … 周日 = 7）。
fn iso_weekday(days: i64) -> i64 {
    (days + 3).rem_euclid(7) + 1
}

/// 天数 → `YYYY-MM-DD`。
fn format_day(days: i64) -> String {
    let (year, month, day) = civil_from_days(days);
    format!("{year:04}-{month:02}-{day:02}")
}

/// `YYYY-MM-DD` / `YYYYMMDD` → 天数；`2026-02-31` 这种「看着像日期」的输入回算后对不上 ⇒ `None`。
fn parse_day(text: &str) -> Option<i64> {
    let bytes = text.as_bytes();
    let (year, month, day) = if text.len() == 8 && text.chars().all(|c| c.is_ascii_digit()) {
        (text[0..4].parse().ok()?, text[4..6].parse().ok()?, text[6..8].parse().ok()?)
    } else if text.len() == 10 && bytes[4] == b'-' && bytes[7] == b'-' {
        (text[0..4].parse().ok()?, text[5..7].parse().ok()?, text[8..10].parse().ok()?)
    } else {
        return None;
    };
    if !(1..=12).contains(&month) || !(1..=31).contains(&day) {
        return None;
    }
    let days = days_from_civil(year, month, day);
    if civil_from_days(days) != (year, month, day) {
        return None;
    }
    Some(days)
}

/// 期号 → 日期范围（`FR-R-13-08` ① 的「日期范围」）。
///
/// 契约包（`IR-05` 不变量 4）只写 `published` 与期号，**没有范围字段**；而卡片要显示「日期范围」。
/// 口径（**确定性算术，不是猜**）：
///   · `YYYY-Www`（ISO 周）⇒ 那一周的**周一到周日**（`2026-W40` = `2026-09-28 → 2026-10-04`）；
///     年份与周号对不上（那一年没有第 53 周）⇒ `None`；
///   · `YYYYMMDD` / `YYYY-MM-DD` ⇒ 当日；
///   · 其余形态 ⇒ `None`（界面如实说「未标注」）。
///
/// 只在**包里一个范围字段都没写**时才用它 —— 包里写了就以包为准。
pub fn period_range(period: &str) -> Option<(String, String)> {
    let text = period.trim();
    if let Some((year, week)) = split_iso_week(text) {
        let jan4 = days_from_civil(year, 1, 4);
        let monday = jan4 - (iso_weekday(jan4) - 1);
        let start = monday + (week - 1) * 7;
        // ISO 周的归属年 = 那一周**周四**所在的年；对不上说明这个年没有第 `week` 周。
        if civil_from_days(start + 3).0 != year {
            return None;
        }
        return Some((format_day(start), format_day(start + 6)));
    }
    let day = parse_day(text)?;
    let one = format_day(day);
    Some((one.clone(), one))
}

/// `2026-W40` / `2026-w40` → `(2026, 40)`。
fn split_iso_week(text: &str) -> Option<(i64, i64)> {
    let (year, rest) = text.split_once('-')?;
    if year.len() != 4 || !year.chars().all(|c| c.is_ascii_digit()) {
        return None;
    }
    let week = rest.strip_prefix('W').or_else(|| rest.strip_prefix('w'))?;
    if week.len() != 2 || !week.chars().all(|c| c.is_ascii_digit()) {
        return None;
    }
    let year: i64 = year.parse().ok()?;
    let week: i64 = week.parse().ok()?;
    if !(1..=53).contains(&week) {
        return None;
    }
    Some((year, week))
}

/// 卡片排序键：有生成时间就按生成时间，没有就按发布日（契约包只有发布日）。
fn sort_key(card: &Card) -> &str {
    if card.generated_at.is_empty() {
        &card.published
    } else {
        &card.generated_at
    }
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

    let (mut date_start, mut date_end) = parse_range(&value);
    if date_start.is_empty() && date_end.is_empty() {
        // 契约包不写范围 ⇒ 按期号推（ISO 周 = 周一到周日）；推不出来就留空，界面说「未标注」。
        if let Some((start, end)) = period_range(&period) {
            date_start = start;
            date_end = end;
        }
    }
    let published = pick_str(&value, &["published", "publishedAt", "published_at"])
        .unwrap_or("")
        .to_string();
    let generated_at = pick_str(&value, &["generatedAt", "generated_at", "createdAt", "created_at"])
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
            published,
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
        sort_key(b)
            .cmp(sort_key(a))
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

    // ── 契约字段（`IR-05` 不变量 4）与期号 → 日期范围（`FR-R-12-05` ② 真样本那轮）────────

    #[test]
    fn a_contract_package_shows_its_published_date_and_derives_the_week_range() {
        // 真包就是这六个字段（`id` / `title` / `published` / `summary` / `cover` / `media_count`），
        // 没有 dateStart / generatedAt —— 早先解析器不认 published，卡片上时间与范围都是空的。
        let index = r#"{
            "id": "2026-W40",
            "title": "国际趋势分析周报 · 2026-W40",
            "published": "2026-10-05",
            "summary": "端到端样例包",
            "cover": "assets/trend-01.png",
            "media_count": 3
        }"#;
        let assets = vec!["trend-01.png".to_string()];
        let (cards, problems) = collect(&[source("2026-W40", Some(index), true, &assets)]);
        assert!(problems.is_empty(), "{problems:?}");
        let card = &cards[0];
        assert_eq!(card.published, "2026-10-05");
        assert_eq!(card.date_start, "2026-09-28", "期号是 ISO 周 ⇒ 范围取那一周的周一");
        assert_eq!(card.date_end, "2026-10-04");
        assert_eq!(card.generated_at, "", "发布日不是生成时间，不许冒充");
        assert_eq!(card.cover.as_deref(), Some("assets/trend-01.png"));
    }

    #[test]
    fn an_explicit_range_in_the_package_beats_the_derived_one() {
        let index = r#"{"title":"写了范围","published":"2026-10-19","dateRange":"2026-10-13 ~ 2026-10-16"}"#;
        let (cards, _) = collect(&[source("2026-W42", Some(index), true, &[])]);
        assert_eq!(cards[0].date_start, "2026-10-13");
        assert_eq!(cards[0].date_end, "2026-10-16");
    }

    #[test]
    fn a_week_period_maps_to_its_monday_through_sunday() {
        assert_eq!(
            period_range("2026-W40"),
            Some(("2026-09-28".to_string(), "2026-10-04".to_string()))
        );
        // 跨年周：2026-W01 的周一落在 2025-12-29
        assert_eq!(
            period_range("2026-W01"),
            Some(("2025-12-29".to_string(), "2026-01-04".to_string()))
        );
        // 2026 有第 53 周，2025 没有 ⇒ 后者推不出来（不编一个下一年的日期）
        assert_eq!(
            period_range("2026-W53"),
            Some(("2026-12-28".to_string(), "2027-01-03".to_string()))
        );
        assert_eq!(period_range("2025-W53"), None);
        assert_eq!(period_range("2026-W54"), None);
        assert_eq!(period_range("2026-W00"), None);
    }

    #[test]
    fn a_compact_period_maps_to_its_own_day_and_other_shapes_derive_nothing() {
        assert_eq!(
            period_range("20261005"),
            Some(("2026-10-05".to_string(), "2026-10-05".to_string()))
        );
        assert_eq!(
            period_range("2026-10-05"),
            Some(("2026-10-05".to_string(), "2026-10-05".to_string()))
        );
        for bad in ["2026-02-31", "第40周", "2026-W4", "2026W40", "", "2026-W4x"] {
            assert_eq!(period_range(bad), None, "{bad:?} 不该推出日期");
        }
    }

    #[test]
    fn contract_packages_are_ordered_by_published_date_newest_first() {
        let older = r#"{"title":"旧","published":"2026-09-28"}"#;
        let newer = r#"{"title":"新","published":"2026-10-05"}"#;
        let (cards, _) = collect(&[
            source("2026-W40", Some(older), true, &[]),
            source("2026-W41", Some(newer), true, &[]),
        ]);
        let periods: Vec<&str> = cards.iter().map(|c| c.period.as_str()).collect();
        assert_eq!(periods, vec!["2026-W41", "2026-W40"]);
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

    // ── 导入裁决（`FR-R-12-04` ① / ③ 的领域口径）────────────────────────────────

    #[test]
    fn identical_content_at_the_same_period_is_idempotent_not_a_second_copy() {
        assert_eq!(
            existing_decision(true),
            ImportState::Already,
            "同一份包导两次必须报「已导入」，否则用户会看到两条同期"
        );
    }

    #[test]
    fn different_content_at_the_same_period_is_a_conflict_so_nothing_is_overwritten() {
        assert_eq!(
            existing_decision(false),
            ImportState::Conflict,
            "内容不同 ⇒ 冲突（保留库里那份），绝不静默覆盖用户的原包"
        );
    }
}
