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

/// 把正文里的一处外链交给**系统默认处理**（`FR-R-13-09` ②）。
///
/// 两层分工：
/// - **领域层** `doyah_studio_db::external_plan`：只认 http / https、拒空白与控制字符、
///   给出「程序 + 独立参数」（不经 shell）；
/// - **本层**：把拒绝翻成两句人话（原话 + 怎么办），并真启动 —— **不等进程**
///   （浏览器 / 播放器立刻返回，等它会卡住界面线程）。
pub fn open_external(url: &str) -> Result<doyah_studio_db::ExternalPlan, DbFailure> {
    let plan = doyah_studio_db::external_plan(url).map_err(|reason| DbFailure {
        message: format!("这个链接不能打开：{reason}"),
        hint: "外链只支持 http / https。file: / javascript: / ms-* 这类协议一点就在本机执行东西，本视图不交给系统。"
            .to_string(),
    })?;
    std::process::Command::new(&plan.program)
        .args(&plan.args)
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
        .map_err(|error| DbFailure {
            message: format!("交给系统默认处理失败：{error}（{}）", plan.program),
            hint: "确认 rundll32.exe 可用（Windows 自带）；被安全软件拦下时也会走到这里。".to_string(),
        })?;
    Ok(plan)
}

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

// ── 包导入（`FR-R-12-04` ① 幂等 / ③ 逐条报错、不写半截）──────────────────────────────
//
// 三条口径：
// 1. **先判后拷**：包不合法（缺 index / 缺正文 / 编码错 / 期号不合法）⇒ 一个字节都不写；
// 2. **幂等**：落点已有同名期且内容逐字节相同 ⇒ 报「已导入」，不新增条目、不覆盖；
// 3. **不留半截**：先拷进 `.import-<pid>-<seq>-<期号>` 临时目录（隐藏目录，扫描器本来就会跳过），
//    验过再改名；任何一步失败都删掉自己那份临时目录，**已有包一个字节不碰**。

/// 一次导入的结果（界面照这个报一句人话：态 + 原因 + 落点）。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RetroImport {
    /// 期号（= 源目录名）。
    pub period: String,
    /// 结果态：`imported` / `already` / `conflict` / `rejected` / `failed`。
    pub state: retro_package::ImportState,
    /// 一句人话（成功说落到哪，失败说为什么）。
    pub message: String,
    /// 落点路径（`imported` 是新包；`already` / `conflict` 是库里那一份）。
    pub path: String,
}

/// 临时目录序号（同一进程里连续导入不撞名）。
static IMPORT_SEQ: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

impl RetroStore {
    /// 导入一个包（`source` = 用户用系统选择器选中的**包目录**，目录名即期号）。
    ///
    /// 返回 `Ok` = 判定完成（`rejected` / `conflict` 是**逐条报**的结果，不是程序错误）；
    /// `Err` 只留给「连判都判不了」（空串 / 源不是目录）。
    pub fn import(&self, source: &str) -> Result<RetroImport, DbFailure> {
        let text = source.trim();
        if text.is_empty() {
            return Err(DbFailure {
                message: "没有给出要导入的包目录".to_string(),
                hint: "点「导入包…」用系统选择器选一个包目录；目录名就是期号。".to_string(),
            });
        }
        let src = Path::new(text);
        if !src.is_dir() {
            return Err(DbFailure {
                message: format!("这不是一个目录：{text}"),
                hint: "包 = 一个目录（里面要有 index.json / report.md）；选目录，不要选文件。"
                    .to_string(),
            });
        }
        let Some(period) = src.file_name().and_then(|name| name.to_str()).map(str::to_string) else {
            return Ok(import_result(
                text,
                retro_package::ImportState::Rejected,
                "目录名不是合法 UTF-8：期号无从取，这一包没导入".to_string(),
                src,
            ));
        };
        if let Err(reason) = retro_package::validate_period(&period) {
            return Ok(import_result(
                &period,
                retro_package::ImportState::Rejected,
                format!("期号不可用：{reason}"),
                src,
            ));
        }
        // ① 先判：这个包画不画得出来（缺件 / 编码错 / JSON 坏都在这一步报，一个字节都不写）。
        if let Err(reason) = validate_package(src, &period) {
            return Ok(import_result(
                &period,
                retro_package::ImportState::Rejected,
                reason,
                src,
            ));
        }
        let target = self.root.join(&period);
        if target.exists() {
            let state = retro_package::existing_decision(same_tree(src, &target));
            let message = match state {
                retro_package::ImportState::Already => {
                    "已导入（与库里那份逐字节相同，未覆盖）".to_string()
                }
                _ => "库里已有同名期且内容不同：保留原包，没有覆盖".to_string(),
            };
            return Ok(import_result(&period, state, message, &target));
        }
        // ② 先拷进临时目录，验过再改名 —— 失败只删自己那份。
        if let Err(error) = std::fs::create_dir_all(&self.root) {
            return Err(DbFailure {
                message: format!("建包目录失败：{error}（{}）", self.root.display()),
                hint: "确认 %APPDATA% 可写，或换一台机器上的可写位置。".to_string(),
            });
        }
        let seq = IMPORT_SEQ.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let staging = self
            .root
            .join(format!(".import-{}-{seq}-{period}", std::process::id()));
        let _ = std::fs::remove_dir_all(&staging);
        if let Err(reason) = copy_tree(src, &staging) {
            let _ = std::fs::remove_dir_all(&staging);
            return Ok(import_result(
                &period,
                retro_package::ImportState::Failed,
                format!("复制失败：{reason}（临时目录已清掉，库里原有的包没动）"),
                &target,
            ));
        }
        // 拷完再验一次：源在拷贝过程中被改 / 拷贝丢文件 ⇒ 宁可报出来，也不落一个坏包。
        if let Err(reason) = validate_package(&staging, &period) {
            let _ = std::fs::remove_dir_all(&staging);
            return Ok(import_result(
                &period,
                retro_package::ImportState::Rejected,
                format!("复制出来的包读不出来：{reason}（临时目录已清掉）"),
                &target,
            ));
        }
        if let Err(error) = std::fs::rename(&staging, &target) {
            let _ = std::fs::remove_dir_all(&staging);
            return Ok(import_result(
                &period,
                retro_package::ImportState::Failed,
                format!("落位失败：{error}（临时目录已清掉）"),
                &target,
            ));
        }
        Ok(import_result(
            &period,
            retro_package::ImportState::Imported,
            format!("已导入到 {}", target.display()),
            &target,
        ))
    }
}

/// 拼一条导入结果（`path` 只为读数 —— 失败时它可能还不存在）。
fn import_result(
    period: &str,
    state: retro_package::ImportState,
    message: String,
    path: &Path,
) -> RetroImport {
    RetroImport {
        period: period.to_string(),
        state,
        message,
        path: path.display().to_string(),
    }
}

/// 校验一个包目录能不能画出来（与 `snapshot` 同一套判定：缺 index / 缺正文 / 编码错 / 字段缺）。
fn validate_package(dir: &Path, period: &str) -> Result<(), String> {
    let index_text = read_text(&dir.join(retro_package::INDEX_FILE))?;
    let report_path = dir.join(retro_package::REPORT_FILE);
    let bytes = match std::fs::read(&report_path) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Err("包里没有 report.md（正文是契约三件之一）".to_string())
        }
        Err(error) => return Err(format!("读 report.md 失败：{error}")),
    };
    if let Err(reason) = retro_package::decode_report(&bytes) {
        return Err(format!("report.md 读不出来：{reason}"));
    }
    let assets = list_assets(&dir.join(retro_package::ASSET_DIR));
    let source = retro_package::Source {
        dir_name: period,
        index_json: index_text.as_deref(),
        has_report: true,
        assets: &assets,
    };
    retro_package::card_of(&source)
        .map(|_| ())
        .map_err(|problem| problem.message)
}

/// 递归复制（不跟随符号链接：包里出现链接就当场拒，别把包外的东西拖进来）。
fn copy_tree(src: &Path, dst: &Path) -> Result<(), String> {
    std::fs::create_dir_all(dst).map_err(|error| format!("建 {} 失败：{error}", dst.display()))?;
    let entries =
        std::fs::read_dir(src).map_err(|error| format!("读 {} 失败：{error}", src.display()))?;
    for entry in entries {
        let entry = entry.map_err(|error| format!("遍历 {} 失败：{error}", src.display()))?;
        let path = entry.path();
        let file_type = entry
            .file_type()
            .map_err(|error| format!("读 {} 的类型失败：{error}", path.display()))?;
        if file_type.is_symlink() {
            return Err(format!(
                "{} 是符号链接：包只认实体文件与目录",
                path.display()
            ));
        }
        let out = dst.join(entry.file_name());
        if file_type.is_dir() {
            copy_tree(&path, &out)?;
        } else if file_type.is_file() {
            std::fs::copy(&path, &out)
                .map_err(|error| format!("复制 {} 失败：{error}", path.display()))?;
        }
    }
    Ok(())
}

/// 两棵目录树**逐字节**比（文件名集合相同 + 每个文件内容相同）。任一读不出来 ⇒ 当作不同。
fn same_tree(left: &Path, right: &Path) -> bool {
    match (list_tree(left), list_tree(right)) {
        (Ok(left_files), Ok(right_files)) if left_files == right_files => left_files
            .iter()
            .all(|rel| same_file(&left.join(rel), &right.join(rel))),
        _ => false,
    }
}

/// 目录下的**相对文件路径**清单（排序；目录不进清单 —— 空目录差异不影响「这期是不是同一份」）。
fn list_tree(root: &Path) -> Result<Vec<PathBuf>, String> {
    fn walk(base: &Path, dir: &Path, out: &mut Vec<PathBuf>) -> Result<(), String> {
        let entries =
            std::fs::read_dir(dir).map_err(|error| format!("读 {} 失败：{error}", dir.display()))?;
        for entry in entries {
            let entry = entry.map_err(|error| format!("遍历 {} 失败：{error}", dir.display()))?;
            let path = entry.path();
            let file_type = entry
                .file_type()
                .map_err(|error| format!("读 {} 的类型失败：{error}", path.display()))?;
            if file_type.is_dir() {
                walk(base, &path, out)?;
            } else if file_type.is_file() {
                if let Ok(rel) = path.strip_prefix(base) {
                    out.push(rel.to_path_buf());
                }
            }
        }
        Ok(())
    }
    let mut files = Vec::new();
    walk(root, root, &mut files)?;
    files.sort();
    Ok(files)
}

/// 两个文件内容相同（分块比，不把整份读进内存 —— 媒体可能有几百 MB）。
fn same_file(left: &Path, right: &Path) -> bool {
    use std::io::Read;
    let (Ok(mut a), Ok(mut b)) = (std::fs::File::open(left), std::fs::File::open(right)) else {
        return false;
    };
    let mut buf_a = vec![0u8; 64 * 1024];
    let mut buf_b = vec![0u8; 64 * 1024];
    loop {
        let read_a = match a.read(&mut buf_a) {
            Ok(n) => n,
            Err(_) => return false,
        };
        let read_b = match b.read(&mut buf_b) {
            Ok(n) => n,
            Err(_) => return false,
        };
        if read_a != read_b {
            return false;
        }
        if read_a == 0 {
            return true;
        }
        if buf_a[..read_a] != buf_b[..read_b] {
            return false;
        }
    }
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

    /// 判据②（`FR-R-13-08`）：「右区按 `report.md` 渲染，标题层级 / 表格 / 引用 / 列表与源文一致」。
    ///
    /// 为什么从**盘上真实包**读而不是直接调 `markdown::parse`：判据要证明的是这条链
    /// （读文件 → 解码 → 解析 → 回给界面）整体成立，`markdown.rs` 自己的单测只证明它那一层。
    #[test]
    fn a_real_report_keeps_its_heading_levels_table_quote_and_nested_list() {
        let dir = root("structure");
        let body = concat!(
            "# 芯片周报\n\n",
            "## 一、本周行情\n\n",
            "### 1.1 存储器\n\n",
            "| 品类 | 涨幅 | 备注 |\n",
            "| :--- | :---: | ---: |\n",
            "| DRAM | +3.2% | 现货 |\n",
            "| NAND | -1.1% | 合约 |\n\n",
            "---\n\n",
            "> 行情只做记录，不构成建议。\n\n",
            "- 供给端\n",
            "  - 三大厂减产\n\n",
            "1. 需求端回升\n",
        );
        write_package(&dir, "2026-W42", Some(r#"{"title":"结构"}"#), Some(body));
        let report = RetroStore::new(&dir).report("2026-W42").expect("读正文");

        let kinds: Vec<&str> = report
            .document
            .blocks
            .iter()
            .map(|block| match &block.kind {
                markdown::BlockKind::Heading { .. } => "heading",
                markdown::BlockKind::Paragraph { .. } => "paragraph",
                markdown::BlockKind::Table { .. } => "table",
                markdown::BlockKind::Quote { .. } => "quote",
                markdown::BlockKind::ListItem { .. } => "item",
                markdown::BlockKind::Rule => "rule",
                markdown::BlockKind::CodeFence { .. } => "code",
                markdown::BlockKind::Media { .. } => "media",
            })
            .collect();
        assert_eq!(
            kinds,
            ["heading", "heading", "heading", "table", "rule", "quote", "item", "item"],
            "块序列要按源文顺序，不许把表格 / 引用 / 列表降级成段落"
        );

        // 标题层级原样保留（不塌成同一级）
        let levels: Vec<u8> = report
            .document
            .blocks
            .iter()
            .filter_map(|block| match &block.kind {
                markdown::BlockKind::Heading { level, .. } => Some(*level),
                _ => None,
            })
            .collect();
        assert_eq!(levels, [1, 2, 3]);

        // 表格：三列 + 对齐按 `:---` / `:---:` / `---:` + 两行两列都对上
        let table = report
            .document
            .blocks
            .iter()
            .find_map(|block| match &block.kind {
                markdown::BlockKind::Table {
                    alignments,
                    header,
                    rows,
                } => Some((alignments, header, rows)),
                _ => None,
            })
            .expect("表格块");
        assert_eq!(table.0.len(), 3);
        assert_eq!(
            *table.0,
            [
                markdown::ColumnAlignment::Left,
                markdown::ColumnAlignment::Center,
                markdown::ColumnAlignment::Right
            ]
        );
        let head: Vec<&str> = table.1.iter().map(|cell| cell[0].text.as_str()).collect();
        assert_eq!(head, ["品类", "涨幅", "备注"]);
        assert_eq!(table.2.len(), 2, "两行数据");
        assert_eq!(table.2[1][1][0].text, "-1.1%");

        // 引用：里面是真的段落块（不是把整段当纯文本）
        let quote = report
            .document
            .blocks
            .iter()
            .find_map(|block| match &block.kind {
                markdown::BlockKind::Quote { children } => Some(children),
                _ => None,
            })
            .expect("引用块");
        assert_eq!(quote.len(), 1);
        match &quote[0].kind {
            markdown::BlockKind::Paragraph { spans } => assert!(
                spans.iter().any(|span| span.text.contains("不构成建议")),
                "引用里的段落：{:?}",
                spans
            ),
            other => panic!("引用里应是段落：{other:?}"),
        }

        // 列表：无序两项（第二项是嵌套子项，进 children）+ 有序项带序号 1
        let items: Vec<&markdown::Block> = report
            .document
            .blocks
            .iter()
            .filter(|block| matches!(&block.kind, markdown::BlockKind::ListItem { .. }))
            .collect();
        assert_eq!(items.len(), 2, "顶层两条（嵌套项不算顶层）");
        match &items[0].kind {
            markdown::BlockKind::ListItem {
                number,
                checked,
                spans,
                children,
            } => {
                assert!(number.is_none() && checked.is_none(), "无序、非任务项");
                assert_eq!(spans[0].text, "供给端");
                assert_eq!(children.len(), 1, "缩进的子项要进 children");
                match &children[0].kind {
                    markdown::BlockKind::ListItem { spans, .. } => {
                        assert_eq!(spans[0].text, "三大厂减产")
                    }
                    other => panic!("子项应是列表条目：{other:?}"),
                }
            }
            other => panic!("{other:?}"),
        }
        match &items[1].kind {
            markdown::BlockKind::ListItem { number, spans, .. } => {
                assert_eq!(*number, Some(1), "有序列表的序号要带过来");
                assert_eq!(spans[0].text, "需求端回升");
            }
            other => panic!("{other:?}"),
        }

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

    // ── 外链交给系统默认处理（`FR-R-13-09` ②）──────────────────────────────────────

    /// 判据②的**否定面**：不是 http / https 的链接**在启动任何进程之前**就被拒，
    /// 且给的是两句人话（原话 + 怎么办）。这一段不会 spawn —— 断言失败也污染不到环境。
    #[test]
    fn a_link_that_is_not_http_is_refused_before_anything_is_started() {
        for bad in [
            "file:///C:/Windows/win.ini",
            "javascript:alert(1)",
            "ms-msdt:/id PCWDiagnostic",
            "",
            "https://exa mple.com/a.mp4",
        ] {
            let failure = open_external(bad).unwrap_err();
            assert!(
                failure.message.contains("这个链接不能打开"),
                "{bad} ⇒ {}",
                failure.message
            );
            assert!(failure.hint.contains("http"), "{bad} 的提示要写清只认 http / https：{}", failure.hint);
        }
    }

    // ── 包导入（`FR-R-12-04` ① 幂等 / ③ 逐条报错不写半截）──────────────────────────

    /// 库里有没有遗留的临时目录（`.import-*`）—— 判据③的「不留半截」看这个。
    fn staging_leftovers(root: &Path) -> Vec<String> {
        let Ok(entries) = std::fs::read_dir(root) else {
            return Vec::new();
        };
        entries
            .flatten()
            .filter_map(|entry| entry.file_name().to_str().map(str::to_string))
            .filter(|name| name.starts_with('.'))
            .collect()
    }

    #[test]
    fn importing_a_readable_package_copies_it_in_and_it_shows_in_the_list() {
        let base = root("import-ok");
        let inbox = base.join("inbox");
        let lib = base.join("lib");
        write_package(
            &inbox,
            "2026-W43",
            Some(r#"{"title":"导入的周报","dateRange":"2026-10-19 ~ 2026-10-25"}"#),
            Some("# 导入的周报\n\n段落"),
        );
        // 媒体也要跟着包一起进来（判据①「正文与媒体随包落本机」）
        std::fs::write(inbox.join("2026-W43").join("assets").join("a.png"), b"\x89PNG-ish").expect("写媒体");

        let store = RetroStore::new(&lib);
        let source = inbox.join("2026-W43");
        let result = store.import(&source.display().to_string()).expect("导入");
        assert_eq!(result.state, retro_package::ImportState::Imported, "{}", result.message);
        assert_eq!(result.period, "2026-W43");

        let snapshot = store.snapshot().expect("扫目录");
        assert_eq!(snapshot.cards.len(), 1, "导进来就该在列表里");
        assert_eq!(snapshot.cards[0].title, "导入的周报");
        assert!(snapshot.problems.is_empty(), "{:?}", snapshot.problems);
        assert!(
            lib.join("2026-W43").join("assets").join("a.png").is_file(),
            "媒体没跟进来：{}",
            result.message
        );
        assert!(staging_leftovers(&lib).is_empty(), "不许留临时目录：{:?}", staging_leftovers(&lib));
        let _ = std::fs::remove_dir_all(&base);
    }

    #[test]
    fn importing_the_same_package_twice_reports_already_and_never_duplicates_it() {
        let base = root("import-twice");
        let inbox = base.join("inbox");
        let lib = base.join("lib");
        write_package(&inbox, "2026-W43", Some(r#"{"title":"同一份"}"#), Some("正文"));
        let source = inbox.join("2026-W43").display().to_string();
        let store = RetroStore::new(&lib);

        let first = store.import(&source).expect("第一次导入");
        assert_eq!(first.state, retro_package::ImportState::Imported, "{}", first.message);
        let second = store.import(&source).expect("第二次导入");
        assert_eq!(
            second.state,
            retro_package::ImportState::Already,
            "同包重复导入必须报「已导入」而不是再写一份：{}",
            second.message
        );
        assert_eq!(store.snapshot().expect("扫目录").cards.len(), 1, "不许出现重复条目");
        assert!(staging_leftovers(&lib).is_empty());
        let _ = std::fs::remove_dir_all(&base);
    }

    #[test]
    fn a_different_package_at_the_same_period_is_refused_and_the_library_copy_is_untouched() {
        let base = root("import-conflict");
        let inbox = base.join("inbox");
        let lib = base.join("lib");
        write_package(&inbox, "2026-W43", Some(r#"{"title":"新的"}"#), Some("新的正文"));
        write_package(&lib, "2026-W43", Some(r#"{"title":"库里的"}"#), Some("库里的正文"));
        let store = RetroStore::new(&lib);
        let source = inbox.join("2026-W43").display().to_string();

        let result = store.import(&source).expect("导入流程走完");
        assert_eq!(result.state, retro_package::ImportState::Conflict, "{}", result.message);
        let kept = std::fs::read_to_string(lib.join("2026-W43").join("report.md")).expect("读库里正文");
        assert_eq!(kept, "库里的正文", "同名期不许被覆盖（用户的原包是证据）");
        assert_eq!(store.snapshot().expect("扫目录").cards[0].title, "库里的");
        assert!(staging_leftovers(&lib).is_empty());
        let _ = std::fs::remove_dir_all(&base);
    }

    #[test]
    fn a_package_without_a_body_is_refused_with_a_reason_and_writes_nothing() {
        let base = root("import-nobody");
        let inbox = base.join("inbox");
        let lib = base.join("lib");
        write_package(&inbox, "2026-W44", Some(r#"{"title":"只有 index"}"#), None);
        let store = RetroStore::new(&lib);

        let result = store.import(&inbox.join("2026-W44").display().to_string()).expect("导入流程走完");
        assert_eq!(result.state, retro_package::ImportState::Rejected, "{}", result.message);
        assert!(result.message.contains("report.md"), "原因要点名缺哪件：{}", result.message);
        // 先判后拷：拒收必须发生在**拷贝之前**（拷完才发现＝已经写过一个坏包）
        assert!(
            !result.message.contains("复制出来的包"),
            "先判后拷：{}",
            result.message
        );
        assert!(!lib.join("2026-W44").exists(), "拒了就不许落目录");
        assert!(staging_leftovers(&lib).is_empty(), "拒了也不许留临时目录");
        let _ = std::fs::remove_dir_all(&base);
    }

    #[test]
    fn an_index_that_is_not_valid_json_is_refused_before_anything_is_copied() {
        let base = root("import-badjson");
        let inbox = base.join("inbox");
        let lib = base.join("lib");
        // 缺 title：领域层判「这一期画不出卡」
        write_package(&inbox, "2026-W45", Some(r#"{"dateRange":"2026-10-19 ~ 2026-10-25"}"#), Some("正文"));
        let store = RetroStore::new(&lib);
        let result = store.import(&inbox.join("2026-W45").display().to_string()).expect("导入流程走完");
        assert_eq!(result.state, retro_package::ImportState::Rejected, "{}", result.message);
        // 同样要「先判后拷」：坏 JSON 不该被复制一份再报
        assert!(!result.message.contains("复制出来的包"), "先判后拷：{}", result.message);
        assert!(!lib.join("2026-W45").exists());
        let _ = std::fs::remove_dir_all(&base);
    }

    #[test]
    fn a_period_name_that_cannot_be_a_directory_key_is_refused() {
        let base = root("import-badperiod");
        let inbox = base.join("inbox");
        let lib = base.join("lib");
        let long_name = "9".repeat(70); // 期号上限 64 字符
        write_package(&inbox, &long_name, Some(r#"{"title":"期号太长"}"#), Some("正文"));
        let store = RetroStore::new(&lib);
        let result = store.import(&inbox.join(&long_name).display().to_string()).expect("导入流程走完");
        assert_eq!(result.state, retro_package::ImportState::Rejected, "{}", result.message);
        assert!(result.message.contains("期号"), "{}", result.message);
        assert!(staging_leftovers(&lib).is_empty());
        let _ = std::fs::remove_dir_all(&base);
    }

    #[test]
    fn importing_something_that_is_not_a_directory_is_an_error_not_a_silent_success() {
        let base = root("import-file");
        let file = base.join("single-file.txt");
        std::fs::write(&file, "不是包".as_bytes()).expect("写文件");
        let store = RetroStore::new(&base.join("lib"));
        let failure = store.import(&file.display().to_string()).unwrap_err();
        assert!(failure.message.contains("不是一个目录"), "{}", failure.message);
        assert!(!failure.hint.is_empty(), "要告诉用户怎么办");
        let _ = std::fs::remove_dir_all(&base);
    }
}
