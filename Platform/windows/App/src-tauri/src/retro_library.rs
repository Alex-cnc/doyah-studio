//! Retro 周报包：**读盘 + 交给领域层判 + 正文交给既有 Markdown 解析**
//! （`FR-R-12-01` 左列表 / `FR-R-12-02` 右正文 / `FR-R-13-08` 的 M0 只读面）
//!
//! 三层分工（与本仓其它域一致）：
//! - **领域层** `doyah_studio_db::retro_package`：什么算一张卡、什么算一处问题、路径合不合法；
//! - **本层**：扫哪个目录、读哪些字节、读不出来时给什么可读原因；
//! - **界面**：只画（`RetroView.vue`），不做第二套解析。
//!
//! 三条口径：
//! 1. **包目录不存在 = 空清单**，不是错误（第一次用还没有周报，界面要能说出「放包的地方在哪」）；
//! 2. **一期一处问题**：坏包不影响别的包被列出来（逐条报，不整批失败）；
//! 3. `period` 从界面回来时要**再校验一次**（它是唯一一个回到拼路径的字符串）。

use std::path::{Path, PathBuf};

use doyah_studio_db::{markdown, retro_package};

use crate::postgres::DbFailure;

/// 一次扫描的结果（左列表画什么、根目录在哪、哪些包读不出来）。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RetroSnapshot {
    /// 扫描根（界面的空态要把它显示出来 —— 用户得知道包该放哪儿）。
    pub root: String,
    /// 能画出来的期（生成时间倒序；领域层排序）。
    pub cards: Vec<retro_package::Card>,
    /// 读不出来的地方，逐条。
    pub problems: Vec<retro_package::Problem>,
}

/// 一期的正文（已解析成渲染模型，界面不再自己做 Markdown）。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RetroReport {
    /// 期号（= 目录名）。
    pub period: String,
    /// 正文文件路径（界面上「这一期来自哪儿」）。
    pub path: String,
    /// 正文字节数（读数，便于对账「渲染的是不是这份」）。
    pub bytes: usize,
    /// 渲染模型（领域层 `markdown::parse` 的产出）。
    pub document: markdown::Document,
    /// 正文里每一处媒体引用在盘上的判定（界面照着画：能读的显示、读不了的占位 + 原因）。
    pub media: Vec<RetroMedia>,
}

/// 一处媒体的判定结果（**判定只有这一处**：界面不再自己拼路径、不再自己判后缀）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub enum MediaState {
    /// 能读：`path` 给出绝对落点，`mime` 给出类型（界面建 blob 用）。
    Ok,
    /// 包里没有这个文件。
    Missing,
    /// 路径不合法（绝对路径 / `..` / 反斜杠 / 不在 `assets/` 下）。
    Rejected,
    /// 外链（`http`/`https`）—— 视图内**不加载**（不出网）。
    External,
    /// 白名单外的后缀（`avi` / `mov` 之类）—— 原位降级为占位。
    Unsupported,
}

/// 一处媒体引用的判定（形状与界面 `RetroMedia` 一一对应）。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RetroMedia {
    /// 正文里写的原文（界面的占位与取字节都用它）。
    pub target: String,
    pub state: MediaState,
    /// `Ok` 时是绝对路径（读数 + 排错用）。
    pub path: Option<String>,
    /// 可读原因（`Ok` 之外都有）。
    pub reason: Option<String>,
    /// `Ok` 时的 MIME（`image/png` / `video/mp4` …）。
    pub mime: Option<String>,
}

/// Retro 包目录。
pub struct RetroStore {
    /// 扫描根（`%APPDATA%\DoyahStudio\retro\packages`）。
    pub root: PathBuf,
}

impl RetroStore {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    /// 默认落点：`%APPDATA%\DoyahStudio\retro\packages`（与连接 / 归档同一个 `DoyahStudio` 家）。
    /// 取不到 `APPDATA` 就退到当前目录下的 `retro\packages` —— **不静默丢数据**，路径会回到界面上。
    pub fn default_root() -> PathBuf {
        match std::env::var("APPDATA") {
            Ok(base) if !base.trim().is_empty() => Path::new(&base)
                .join("DoyahStudio")
                .join("retro")
                .join("packages"),
            _ => PathBuf::from("retro").join("packages"),
        }
    }

    /// 扫一遍包目录。
    pub fn snapshot(&self) -> Result<RetroSnapshot, DbFailure> {
        let mut problems: Vec<retro_package::Problem> = Vec::new();
        let entries = match std::fs::read_dir(&self.root) {
            Ok(entries) => entries,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                return Ok(RetroSnapshot {
                    root: self.root.display().to_string(),
                    cards: Vec::new(),
                    problems: Vec::new(),
                })
            }
            Err(error) => {
                return Err(DbFailure {
                    message: format!("读 Retro 包目录失败：{error}（{}）", self.root.display()),
                    hint: "确认该目录存在且可读；它只是周报包目录，删掉只丢已导入的周报。".to_string(),
                })
            }
        };

        // 先按目录名排序再读：不依赖文件系统的遍历顺序（两次扫描的 problems 顺序才稳定）。
        let mut dirs: Vec<PathBuf> = entries
            .flatten()
            .map(|entry| entry.path())
            .filter(|path| path.is_dir())
            .collect();
        dirs.sort();

        let mut sources: Vec<PackageSource> = Vec::new();
        for dir in &dirs {
            let Some(dir_name) = dir.file_name().and_then(|name| name.to_str()) else {
                problems.push(retro_package::Problem {
                    period: dir.display().to_string(),
                    message: "目录名不是合法 UTF-8：这一期当不了期号".to_string(),
                });
                continue;
            };
            if dir_name.starts_with('.') {
                // 隐藏目录（`.git` / `.tmp` 之类）不是包，静默跳过 —— 报出来只会淹掉真问题。
                continue;
            }
            let index_text = match read_text(&dir.join(retro_package::INDEX_FILE)) {
                Ok(text) => text,
                Err(reason) => {
                    problems.push(retro_package::Problem {
                        period: dir_name.to_string(),
                        message: reason,
                    });
                    continue;
                }
            };
            let has_report = dir.join(retro_package::REPORT_FILE).is_file();
            let assets = list_assets(&dir.join(retro_package::ASSET_DIR));
            sources.push(PackageSource { dir_name: dir_name.to_string(), index_text, has_report, assets });
        }

        let borrowed: Vec<retro_package::Source<'_>> = sources
            .iter()
            .map(|source| retro_package::Source {
                dir_name: &source.dir_name,
                index_json: source.index_text.as_deref(),
                has_report: source.has_report,
                assets: &source.assets,
            })
            .collect();

        let (cards, mut domain_problems) = retro_package::collect(&borrowed);
        problems.append(&mut domain_problems);
        problems.sort_by(|a, b| a.period.cmp(&b.period).then_with(|| a.message.cmp(&b.message)));

        Ok(RetroSnapshot {
            root: self.root.display().to_string(),
            cards,
            problems,
        })
    }

    /// 读一期的正文（`report.md`）并解析成渲染模型。
    ///
    /// `period` **只认扫出来的那个目录名**：先过领域层校验（不许 `..` / 分隔符），
    /// 再确认它真是包目录下的一个目录；两步都过才读 —— 这是「周报包读不到包外文件」的机械保证。
    pub fn report(&self, period: &str) -> Result<RetroReport, DbFailure> {
        if let Err(reason) = retro_package::validate_period(period) {
            return Err(DbFailure {
                message: format!("期号不可用：「{period}」({reason})"),
                hint: "期号 = 包目录名；请不要手工拼接路径。".to_string(),
            });
        }
        let dir = self.root.join(period);
        if !dir.is_dir() {
            return Err(DbFailure {
                message: format!("找不到这一期：{}", dir.display()),
                hint: "刷新列表看看它还在不在；包可能被移走或改名了。".to_string(),
            });
        }
        let path = dir.join(retro_package::REPORT_FILE);
        let bytes = match std::fs::read(&path) {
            Ok(bytes) => bytes,
            Err(error) => {
                return Err(DbFailure {
                    message: format!("读正文失败：{error}（{}）", path.display()),
                    hint: "确认该文件可读；缺正文的包在列表里本来就不该出现。".to_string(),
                })
            }
        };
        let text = retro_package::decode_report(&bytes).map_err(|message| DbFailure {
            message: format!("{period}：{message}"),
            hint: "把这份正文另存为 UTF-8（无 BOM 也可以）再放回包里。".to_string(),
        })?;
        let document = markdown::parse(&text);
        let media = self.resolve_media_in(period, &document);
        Ok(RetroReport {
            period: period.to_string(),
            path: path.display().to_string(),
            bytes: text.len(),
            document,
            media,
        })
    }

    /// 正文里每一处媒体引用的判定（去重、保序：同一目标只判一次）。
    fn resolve_media_in(&self, period: &str, document: &markdown::Document) -> Vec<RetroMedia> {
        let mut targets: Vec<(markdown::MediaKind, String)> = Vec::new();
        collect_media(&document.blocks, &mut targets);
        let dir = self.root.join(period);
        targets
            .into_iter()
            .map(|(kind, target)| resolve_one(&dir, kind, &target))
            .collect()
    }

    /// 读一处媒体的字节（`retro_asset` 的实现）。
    ///
    /// **路径校验两道**：① 领域层 `normalize_asset_path`（相对、在 `assets/` 下、无 `..`、
    /// 后缀白名单）；② 落点必须在包目录内且是文件。两道都过才读 —— 界面的路径来自正文，
    /// 正文来自别人给的包，这里当不可信输入处理。
    pub fn asset(&self, period: &str, target: &str) -> Result<Vec<u8>, DbFailure> {
        if let Err(reason) = retro_package::validate_period(period) {
            return Err(DbFailure {
                message: format!("期号不可用：「{period}」({reason})"),
                hint: "期号 = 包目录名；请不要手工拼接路径。".to_string(),
            });
        }
        let normalized = retro_package::normalize_asset_path(target).map_err(|reason| DbFailure {
            message: format!("媒体路径不可用：「{target}」({reason})"),
            hint: "正文里的媒体只能写包内相对路径（assets/ 下）。".to_string(),
        })?;
        let package = self.root.join(period);
        let path = package.join(&normalized);
        let escaped = match (std::fs::canonicalize(&path), std::fs::canonicalize(&package)) {
            (Ok(file), Ok(dir)) => !file.starts_with(&dir),
            _ => false,
        };
        if escaped {
            return Err(DbFailure {
                message: format!("媒体路径越出包目录：{normalized}"),
                hint: "正文里的媒体只能指向本包 assets/ 下的文件。".to_string(),
            });
        }
        let meta = match std::fs::metadata(&path) {
            Ok(meta) if meta.is_file() => meta,
            Ok(_) => {
                return Err(DbFailure {
                    message: format!("媒体不是一个文件：{normalized}"),
                    hint: "把媒体换成文件（不是目录）再放回包里。".to_string(),
                })
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                return Err(DbFailure {
                    message: format!("包里没有这个媒体：{normalized}"),
                    hint: "确认文件在 assets/ 下、名字与正文写的一致（大小写也要一致）。".to_string(),
                })
            }
            Err(error) => {
                return Err(DbFailure {
                    message: format!("读媒体失败：{error}（{}）", path.display()),
                    hint: "确认该文件可读；被别的程序占着也可能失败。".to_string(),
                })
            }
        };
        if meta.len() > MAX_MEDIA_BYTES {
            return Err(DbFailure {
                message: format!(
                    "媒体太大：{normalized} 有 {} 字节（上限 {MAX_MEDIA_BYTES}）",
                    meta.len()
                ),
                hint: "把视频压小一点再放回包里；超大文件一次读进内存会拖住界面。".to_string(),
            });
        }
        std::fs::read(&path).map_err(|error| DbFailure {
            message: format!("读媒体失败：{error}（{}）", path.display()),
            hint: "确认该文件可读。".to_string(),
        })
    }
}

/// 媒体字节上限（256 MiB）：再大就不一次读进内存了 —— 宁可如实说「太大」。
pub const MAX_MEDIA_BYTES: u64 = 256 * 1024 * 1024;

/// 递归收集正文里的媒体引用（同一目标只留一次，保序）。
fn collect_media(blocks: &[markdown::Block], out: &mut Vec<(markdown::MediaKind, String)>) {
    for block in blocks {
        match &block.kind {
            markdown::BlockKind::Media { media, target, .. } => {
                if !out.iter().any(|(_, seen)| seen == target) {
                    out.push((*media, target.clone()));
                }
            }
            markdown::BlockKind::Quote { children } => collect_media(children, out),
            markdown::BlockKind::ListItem { children, .. } => collect_media(children, out),
            _ => {}
        }
    }
}

/// 判一处媒体：分类 → 路径 → 文件在不在 → MIME。
fn resolve_one(package: &Path, kind: markdown::MediaKind, target: &str) -> RetroMedia {
    let placeholder = |state: MediaState, reason: String| RetroMedia {
        target: target.to_string(),
        state,
        path: None,
        reason: Some(reason),
        mime: None,
    };
    match kind {
        markdown::MediaKind::External => placeholder(
            MediaState::External,
            "外链：视图内不加载（防出网），需要时自己用浏览器打开".to_string(),
        ),
        markdown::MediaKind::Unsupported => placeholder(
            MediaState::Unsupported,
            format!("格式不在白名单（{}）：只认图片与 mp4 / m4v", extension_of(target)),
        ),
        markdown::MediaKind::Image | markdown::MediaKind::Video => {
            let normalized = match retro_package::normalize_asset_path(target) {
                Ok(normalized) => normalized,
                Err(reason) => return placeholder(MediaState::Rejected, reason),
            };
            let path = package.join(&normalized);
            if !path.is_file() {
                return placeholder(MediaState::Missing, format!("包里没有 {normalized}"));
            }
            RetroMedia {
                target: target.to_string(),
                state: MediaState::Ok,
                path: Some(path.display().to_string()),
                reason: None,
                mime: Some(mime_of(&normalized).to_string()),
            }
        }
    }
}

/// 后缀（小写；没有就是空串）。
fn extension_of(target: &str) -> String {
    target
        .trim()
        .rsplit('.')
        .next()
        .unwrap_or("")
        .to_ascii_lowercase()
}

/// 媒体 MIME（白名单内的后缀才有）。
fn mime_of(path: &str) -> &'static str {
    match extension_of(path).as_str() {
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "webp" => "image/webp",
        "gif" => "image/gif",
        "mp4" => "video/mp4",
        "m4v" => "video/x-m4v",
        _ => "application/octet-stream",
    }
}

/// 一个包的盘上事实（本层先攒齐，再一次性交给领域层判）。
struct PackageSource {
    dir_name: String,
    /// `index.json` 的文本；**缺失**才是 `None`（读不出来已单独记成 problem，不走这条路）。
    index_text: Option<String>,
    has_report: bool,
    assets: Vec<String>,
}

/// 读一个文本文件：不在 ⇒ `Ok(None)`；读不出来 / 不是 UTF-8 ⇒ 可读原因。
fn read_text(path: &Path) -> Result<Option<String>, String> {
    let bytes = match std::fs::read(path) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(format!("读 {} 失败：{error}", path.display())),
    };
    let body = bytes.strip_prefix(&[0xEF, 0xBB, 0xBF]).unwrap_or(&bytes);
    match std::str::from_utf8(body) {
        Ok(text) => Ok(Some(text.to_string())),
        Err(error) => Err(format!(
            "{} 不是 UTF-8（第 {} 字节处断开）",
            path.display(),
            error.valid_up_to()
        )),
    }
}

/// `assets/` 下的文件名清单（目录不在 ⇒ 空）；读不出来也当空 —— 它只用于校验封面在不在。
fn list_assets(dir: &Path) -> Vec<String> {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return Vec::new();
    };
    let mut names: Vec<String> = entries
        .flatten()
        .filter(|entry| entry.path().is_file())
        .filter_map(|entry| entry.file_name().to_str().map(|name| name.to_string()))
        .collect();
    names.sort();
    names
}

#[cfg(test)]
mod tests {
    use super::*;

    fn root(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("doyah-retro-{}-{tag}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("建临时目录");
        dir
    }

    fn write_package(root: &Path, period: &str, index: Option<&str>, report: Option<&str>) {
        let dir = root.join(period);
        std::fs::create_dir_all(dir.join("assets")).expect("建包目录");
        if let Some(text) = index {
            std::fs::write(dir.join("index.json"), text).expect("写 index");
        }
        if let Some(text) = report {
            std::fs::write(dir.join("report.md"), text).expect("写正文");
        }
    }

    #[test]
    fn a_missing_root_is_an_empty_library_not_an_error() {
        let missing = std::env::temp_dir().join(format!("doyah-retro-none-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&missing);
        let store = RetroStore::new(&missing);
        let snapshot = store.snapshot().expect("第一次使用不该报错");
        assert!(snapshot.cards.is_empty());
        assert!(snapshot.problems.is_empty());
        assert!(snapshot.root.contains("doyah-retro-none-"), "空态要告诉用户包该放哪儿");
    }

    #[test]
    fn a_package_on_disk_is_listed_with_its_title() {
        let dir = root("list");
        write_package(
            &dir,
            "2026-W42",
            Some(r#"{"title":"芯片周报","dateRange":"2026-10-12 ~ 2026-10-18"}"#),
            Some("# 芯片周报\n\n正文"),
        );
        let snapshot = RetroStore::new(&dir).snapshot().expect("扫目录");
        assert_eq!(snapshot.cards.len(), 1);
        assert_eq!(snapshot.cards[0].title, "芯片周报");
        assert_eq!(snapshot.cards[0].period, "2026-W42");
        assert!(snapshot.problems.is_empty(), "{:?}", snapshot.problems);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_broken_package_is_reported_and_the_good_one_still_shows() {
        let dir = root("mixed");
        write_package(&dir, "2026-W41", Some(r#"{"title":"好的"}"#), Some("正文"));
        write_package(&dir, "2026-W42", None, Some("没有 index 的包"));
        let snapshot = RetroStore::new(&dir).snapshot().expect("扫目录");
        assert_eq!(snapshot.cards.len(), 1, "坏包不该拖垮好包");
        assert_eq!(snapshot.cards[0].period, "2026-W41");
        assert_eq!(snapshot.problems.len(), 1);
        assert_eq!(snapshot.problems[0].period, "2026-W42");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_hidden_directory_is_not_treated_as_a_package() {
        let dir = root("hidden");
        write_package(&dir, ".tmp", Some("不是包"), Some("x"));
        let snapshot = RetroStore::new(&dir).snapshot().expect("扫目录");
        assert!(snapshot.cards.is_empty());
        assert!(snapshot.problems.is_empty(), "隐藏目录不该报成问题");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn an_index_that_is_not_utf8_is_reported_as_such() {
        let dir = root("encoding");
        let package = dir.join("2026-W40");
        std::fs::create_dir_all(&package).expect("建包目录");
        std::fs::write(package.join("index.json"), [0x7B, 0xFF, 0x7D]).expect("写坏 index");
        std::fs::write(package.join("report.md"), "正文").expect("写正文");
        let snapshot = RetroStore::new(&dir).snapshot().expect("扫目录");
        assert!(snapshot.cards.is_empty());
        assert_eq!(snapshot.problems.len(), 1);
        assert!(snapshot.problems[0].message.contains("不是 UTF-8"), "{:?}", snapshot.problems);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn the_report_of_a_period_is_parsed_into_render_blocks() {
        let dir = root("report");
        write_package(&dir, "2026-W42", Some(r#"{"title":"有正文"}"#), Some("# 标题\n\n一段话"));
        let report = RetroStore::new(&dir).report("2026-W42").expect("读正文");
        assert_eq!(report.period, "2026-W42");
        assert!(report.bytes > 0);
        assert!(!report.document.blocks.is_empty(), "正文要解析成块，界面才有东西画");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_period_that_tries_to_escape_the_root_is_refused_before_reading() {
        let dir = root("escape");
        let store = RetroStore::new(&dir);
        for bad in ["../Windows", "..", "a/b", "C:\\Windows"] {
            let failure = store.report(bad).unwrap_err();
            assert!(failure.message.contains("期号不可用"), "{bad} ⇒ {}", failure.message);
        }
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn asking_for_a_period_that_is_not_on_disk_says_so() {
        let dir = root("absent");
        let failure = RetroStore::new(&dir).report("2026-W01").unwrap_err();
        assert!(failure.message.contains("找不到这一期"), "{}", failure.message);
        let _ = std::fs::remove_dir_all(&dir);
    }

    // ── 正文媒体（`FR-R-12-03`：图片 / 视频就地渲染）────────────────────────────────

    #[test]
    fn media_in_the_body_is_judged_against_the_package_on_disk() {
        let dir = root("media");
        write_package(
            &dir,
            "2026-W42",
            Some(r#"{"title":"带图的周报"}"#),
            Some(
                "# 本周\n\n![净值曲线](assets/curve.png)\n\n![录屏](assets/clip.mp4)\n\n![外链](https://example.com/a.png)\n\n![老格式](assets/old.avi)\n\n![越界](../../secret.png)\n",
            ),
        );
        std::fs::write(dir.join("2026-W42/assets/curve.png"), [0x89, 0x50, 0x4E, 0x47]).expect("写入图片");
        let report = RetroStore::new(&dir).report("2026-W42").expect("读正文");
        assert_eq!(report.media.len(), 5, "{:?}", report.media);

        let find = |target: &str| report.media.iter().find(|media| media.target == target).cloned().expect(target);
        let curve = find("assets/curve.png");
        assert_eq!(curve.state, MediaState::Ok);
        assert_eq!(curve.mime.as_deref(), Some("image/png"));
        assert!(curve.path.as_deref().unwrap_or("").ends_with("curve.png"));

        // 正文里有、包里没有 ⇒ missing（占位 + 原因，不白屏）
        assert_eq!(find("assets/clip.mp4").state, MediaState::Missing);
        // 外链不加载
        assert_eq!(find("https://example.com/a.png").state, MediaState::External);
        // 白名单外后缀降级
        assert_eq!(find("assets/old.avi").state, MediaState::Unsupported);
        // 越界路径直接拒（路径校验在领域层）
        let escaped = find("../../secret.png");
        assert_eq!(escaped.state, MediaState::Rejected);
        assert!(escaped.reason.unwrap_or_default().contains(".."));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn media_inside_a_quote_is_judged_too() {
        let dir = root("media-quote");
        write_package(
            &dir,
            "2026-W42",
            Some(r#"{"title":"引用里的图"}"#),
            Some("> [!摘录]\n> ![图](assets/a.png)\n"),
        );
        std::fs::write(dir.join("2026-W42/assets/a.png"), [1, 2, 3]).expect("写入图片");
        let report = RetroStore::new(&dir).report("2026-W42").expect("读正文");
        assert_eq!(report.media.len(), 1, "{:?}", report.media);
        assert_eq!(report.media[0].state, MediaState::Ok);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn asset_bytes_of_a_file_inside_the_package_are_returned() {
        let dir = root("asset-read");
        write_package(&dir, "2026-W42", Some(r#"{"title":"读字节"}"#), Some("正文"));
        std::fs::write(dir.join("2026-W42/assets/a.png"), [0xAA, 0xBB]).expect("写入图片");
        let bytes = RetroStore::new(&dir).asset("2026-W42", "assets/a.png").expect("读媒体");
        assert_eq!(bytes, vec![0xAA, 0xBB]);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn asset_bytes_are_refused_for_missing_or_outside_paths() {
        let dir = root("asset-refuse");
        write_package(&dir, "2026-W42", Some(r#"{"title":"拒读"}"#), Some("正文"));
        let store = RetroStore::new(&dir);
        let missing = store.asset("2026-W42", "assets/none.png").unwrap_err();
        assert!(missing.message.contains("包里没有这个媒体"), "{}", missing.message);
        for bad in ["../report.md", "assets/../../report.md", "C:\\Windows\\win.ini", "report.md"] {
            let failure = store.asset("2026-W42", bad).unwrap_err();
            assert!(
                failure.message.contains("媒体路径不可用"),
                "{bad} ⇒ {}",
                failure.message
            );
        }
        // 期号同样要过校验（它是回到拼路径的字符串）
        let bad_period = store.asset("..", "assets/a.png").unwrap_err();
        assert!(bad_period.message.contains("期号不可用"), "{}", bad_period.message);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
