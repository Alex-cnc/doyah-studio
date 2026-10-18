//! **恢复**（`FR-IO-05` 的 Windows 侧落法）：封装本机 `pg_restore`。
//!
//! 需求原文：「备份文件恢复到指定库（`pg_restore` 的 `--clean` / `--section` / `--jobs`）
//! 与失败续跑」。旗标与可取消运行器是第一片；**失败续跑**是这一片：
//!
//! 恢复的三段有**依赖顺序**（结构 → 数据 → 索引/约束），所以「续跑」不是一个开关，
//! 而是一份**账**：跑到哪一段停了、后面还有哪几段、接着跑的那条命令长什么样。
//! 做法 = 逐段执行（每段一条 `pg_restore --section=… --exit-on-error`），遇错即停，
//! 回执里带每段的退出码与日志尾部，失败段 + 它后面的段 = `resume_from`。
//!
//! **为什么失败就停、而不是自己接着跑**：恢复失败往往意味着目标库已处于半截状态，
//! 「该不该继续、要不要先清干净」是人的判断 —— 工具只负责把下一步说清楚
//! （给人一条能直接粘贴的命令 + 一个「从这一段起续跑」的按钮）。
//!
//! ## 与备份同源的四条口径（`backup.rs` 那四条在这里逐条对应）
//!
//! 1. **口令只走 `PGPASSWORD`**：不进 `argv`、不进 `display()`（那里写 `PGPASSWORD=***`）。
//! 2. **命令行先摊出来再跑**：`plan()` 只算不跑，界面把 `display()` 摆给用户看 ——
//!    恢复是**会改库**的动作，比备份更需要「我到底对你的库做了什么」的答案。
//! 3. **日志只带尾部**，被截断就如实说砍了多少字符。
//! 4. **程序查找与备份同一条口径**（`backup::find_program_named`）：显式路径 → PATH →
//!    各盘安装目录、新版本优先。两处各写一遍迟早出现「备份说找到了、恢复说没装」。
//!
//! ## 恢复特有的三条（每条都对应一个「不说清就会踩」的坑）
//!
//! 1. **`--clean` 必须配 `--if-exists`**：只写 `--clean` 时 `pg_restore` 会对每个不存在的
//!    对象发一条 `DROP ...` 并报错 —— 往一个新库里恢复会整段落败，看起来像「恢复功能坏了」。
//! 2. **`--jobs` 只对目录归档（`-F d`）有意义**：文件归档上带 `--jobs` 会被 `pg_restore`
//!    直接拒绝。所以这里**按源的形态门控**（`effective_jobs`），而不是让用户自己记；
//!    回执里带回**实际用了几个并行**，界面照它说话，不假装用户选的生效了。
//! 3. **纯 SQL 备份（`.sql`）`pg_restore` 不认**：那种文件要用 `psql -f` 灌。发现是 `.sql`
//!    就当场拒并说清替代做法 —— 让它跑起来只会得到一句 `input file does not appear to be
//!    a valid archive`，用户还得自己猜。

use std::io::{BufRead, Read};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::Arc;

use crate::backup::{self, CancelFlag};
use crate::postgres::DbFailure;

/// 轮询子进程的间隔（与备份同一档：太密白烧 CPU、太疏「点了取消要等好几秒」）。
const CANCEL_POLL: std::time::Duration = std::time::Duration::from_millis(100);

/// 恢复哪一段（`pg_restore --section`）。`All` = 不加旗标（`pg_restore` 的缺省就是全部）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Deserialize, serde::Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum RestoreSection {
    All,
    PreData,
    Data,
    PostData,
}

impl Default for RestoreSection {
    fn default() -> Self {
        Self::All
    }
}

impl RestoreSection {
    /// `--section=` 的取值；`All` 不加旗标（`None`）。
    pub fn pg_flag(self) -> Option<&'static str> {
        match self {
            Self::All => None,
            Self::PreData => Some("pre-data"),
            Self::Data => Some("data"),
            Self::PostData => Some("post-data"),
        }
    }

    /// 回执 / 日志里的短名（界面文案仍走 i18n，这里只给命令行回执）。
    pub fn label(self) -> &'static str {
        match self {
            Self::All => "全部",
            Self::PreData => "前段（结构）",
            Self::Data => "数据",
            Self::PostData => "后段（索引/约束）",
        }
    }
}

/// 三段恢复的**依赖顺序**：先结构、再数据、最后索引与约束。倒着做必然失败（数据要表先存在）。
pub const SECTION_SEQUENCE: [RestoreSection; 3] = [
    RestoreSection::PreData,
    RestoreSection::Data,
    RestoreSection::PostData,
];

/// 「失败续跑」要跑哪几段：从**失败那一段**起，把后面的段按顺序补完。
///
/// - `None` / `PreData` ⇒ 三段全跑（前段本来就是第一段）；
/// - `Data` ⇒ 数据 + 后段；`PostData` ⇒ 只剩后段；
/// - `All` ⇒ 三段全跑 —— 一次性模式失败时 `pg_restore` 不会告诉外界停在哪一段，
///   只能从第一段重来，文案里必须如实说「这次没有分段」。
pub fn resume_sections(failed: Option<RestoreSection>) -> Vec<RestoreSection> {
    match failed {
        Some(RestoreSection::Data) => vec![RestoreSection::Data, RestoreSection::PostData],
        Some(RestoreSection::PostData) => vec![RestoreSection::PostData],
        _ => SECTION_SEQUENCE.to_vec(),
    }
}

/// 恢复的**源**是文件还是目录归档（决定体积怎么算、`--jobs` 允不允许）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SourceKind {
    /// `-F c` 自定义归档 / `-F t` tar：单文件
    File,
    /// `-F d` 目录形式：一个目录（`pg_restore -j` 只认它）
    Directory,
}

impl SourceKind {
    pub fn is_directory(self) -> bool {
        matches!(self, Self::Directory)
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::File => "归档文件",
            Self::Directory => "目录归档",
        }
    }
}

/// 恢复到哪台服务器、哪个库（从**当前会话**里取，不从配置里猜）。
#[derive(Debug, Clone)]
pub struct RestoreTarget {
    pub host: String,
    pub port: u16,
    pub user: String,
    pub database: String,
}

/// 恢复的三个开关。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RestoreOptions {
    /// 先删后建（`--clean`，自动配 `--if-exists`）
    pub clean: bool,
    pub section: RestoreSection,
    /// 并行度（只有目录归档生效；`<= 1` 等于不并行）
    pub jobs: u32,
    /// 遇错即停（`--exit-on-error`）。逐段恢复恒为真：一段失败就必须停，
    /// 否则 `pg_restore` 会带着半截结构继续往下做，退出码还可能是 0。
    pub fail_fast: bool,
}

impl Default for RestoreOptions {
    fn default() -> Self {
        Self {
            clean: false,
            section: RestoreSection::All,
            jobs: 0,
            fail_fast: false,
        }
    }
}

/// 一份**还没跑**的恢复计划。
#[derive(Debug, Clone)]
pub struct RestorePlan {
    /// 找到的程序（找不到就是 `None` —— 计划仍可展示，跑不了）
    pub program: Option<PathBuf>,
    /// `pg_restore` 的参数（**口令不在这里面**）
    pub args: Vec<String>,
    pub source: PathBuf,
    pub kind: SourceKind,
    pub database: String,
    pub section: RestoreSection,
    /// **实际会用上的并行度**（0 = 不加 `-j`）
    pub jobs: u32,
}

impl RestorePlan {
    /// **给用户看的命令行**：口令位置写 `PGPASSWORD=***`；带空格的参数加引号。
    pub fn display(&self) -> String {
        let program = match &self.program {
            Some(path) => path.display().to_string(),
            None => "pg_restore".to_string(),
        };
        backup::display_command(&program, &self.args, true)
    }
}

/// 并行度的**实际值**：目录归档才允许并行，文件归档一律 0（= 不加 `-j`，`pg_restore` 也不接受）。
///
/// 上限 16 与 `pg_restore` 的习惯用法一致；更关键的是**不要静默**：回执里带回这个实际值，
/// 界面照它说话（用户选了 4 但源是单文件 ⇒ 界面显示「本次串行」而不是假装并行）。
pub fn effective_jobs(kind: SourceKind, requested: u32) -> u32 {
    if !kind.is_directory() {
        return 0;
    }
    if requested <= 1 {
        return 0;
    }
    requested.min(16)
}

/// 纯函数：`pg_restore` 的参数表。
///
/// 顺序写死（命令行要能一眼读）：
/// `-h -p -U -d <库> --verbose [--clean --if-exists] [--section=...] [--jobs=N] <源>`
pub fn plan_args(
    target: &RestoreTarget,
    source: &Path,
    kind: SourceKind,
    options: &RestoreOptions,
) -> Vec<String> {
    let mut args: Vec<String> = vec![
        "-h".to_string(),
        target.host.clone(),
        "-p".to_string(),
        target.port.to_string(),
        "-U".to_string(),
        target.user.clone(),
        "-d".to_string(),
        target.database.clone(),
        // 进度与错误都只有带上它才吐字（不带时 stderr 全程静默，界面上只剩一个转圈）
        "--verbose".to_string(),
    ];
    if options.clean {
        args.push("--clean".to_string());
        // 必须成对：只带 --clean 时每条 DROP 都会对不存在的对象报错并中断
        args.push("--if-exists".to_string());
    }
    if let Some(section) = options.section.pg_flag() {
        args.push(format!("--section={section}"));
    }
    let jobs = effective_jobs(kind, options.jobs);
    if jobs > 1 {
        args.push(format!("--jobs={jobs}"));
    }
    if options.fail_fast {
        args.push("--exit-on-error".to_string());
    }
    args.push(source.display().to_string());
    args
}

/// 逐段恢复的**计划表**：按依赖顺序给每一段拼一条计划（每段都带 `--exit-on-error`）。
///
/// `from` = 从哪一段起（失败续跑时传失败那一段，见 `resume_sections`）。
/// 界面把这张表整张摊给用户看 —— 逐段模式的「命令行先摊出来」是三行，不是一行。
pub fn section_plans(
    program: Option<PathBuf>,
    target: &RestoreTarget,
    source: &Path,
    kind: SourceKind,
    options: RestoreOptions,
    from: Option<RestoreSection>,
) -> Vec<RestorePlan> {
    resume_sections(from)
        .into_iter()
        .map(|section| {
            let per_section = RestoreOptions {
                section,
                // 逐段跑必须遇错即停：否则「第 2 段失败」会被后面几段的成功掩掉
                fail_fast: true,
                ..options
            };
            RestorePlan {
                program: program.clone(),
                args: plan_args(target, source, kind, &per_section),
                source: source.to_path_buf(),
                kind,
                database: target.database.clone(),
                section,
                jobs: effective_jobs(kind, per_section.jobs),
            }
        })
        .collect()
}

/// 校验源路径，并判它是文件还是目录归档。
///
/// 三条不同的拒绝理由（**分开说**，因为它们对用户意味着不同的下一步）：
/// 路径空 / 文件不存在 / 这是一份 `pg_restore` 不认的纯 SQL 备份。
pub fn check_source(path: &str) -> Result<(PathBuf, SourceKind), DbFailure> {
    let trimmed = path.trim();
    if trimmed.is_empty() {
        return Err(DbFailure {
            message: "还没选要恢复哪份备份".to_string(),
            hint: "选一个备份文件（*.dump / *.backup / *.tar）或一个目录形式的备份（-F d 产出的目录）。"
                .to_string(),
        });
    }
    let source = PathBuf::from(trimmed);
    if !source.exists() {
        return Err(DbFailure {
            message: format!("{} 不存在", source.display()),
            hint: "恢复读的是**已有**的备份：先确认那份备份还在（备份默认落在你上次选的位置）。"
                .to_string(),
        });
    }
    if source.is_dir() {
        return Ok((source, SourceKind::Directory));
    }
    let lower = source
        .file_name()
        .map(|name| name.to_string_lossy().to_ascii_lowercase())
        .unwrap_or_default();
    if lower.ends_with(".sql") {
        return Err(DbFailure {
            message: format!("{} 是纯 SQL 备份，pg_restore 不认这种文件", source.display()),
            hint: "纯 SQL 用 psql 灌（psql -f 文件名）；要在本界面里恢复，请用备份里的「自定义归档」或「目录形式」。"
                .to_string(),
        });
    }
    Ok((source, SourceKind::File))
}

/// 找 `pg_restore`（口径与 `pg_dump` 完全一致，见 `backup::find_program_named`）。
pub fn find_program(explicit: Option<&str>) -> Result<PathBuf, DbFailure> {
    let name = if cfg!(windows) {
        "pg_restore.exe"
    } else {
        "pg_restore"
    };
    backup::find_program_named(explicit, name)
}

/// 一次恢复的结局（**成功与失败都带日志与退出码**）。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RestoreReport {
    /// 展示用的命令行（口令打码）
    pub display: String,
    /// 退出码（进程被强杀时是 `None`）
    pub exit_code: Option<i32>,
    /// **日志尾部**（stdout + stderr 按到达顺序拼）
    pub log: String,
    /// 前面还有多少字符没带回来（没截断就是 0）
    pub log_trimmed_chars: usize,
    /// 耗时（毫秒）
    pub elapsed_ms: u64,
    /// 从哪儿恢复
    pub source: String,
    pub section: RestoreSection,
    /// **实际用上的并行度**（0 = 串行；文件归档恒 0）
    pub jobs: u32,
    /// 目标库
    pub database: String,
}

/// 一次子进程恢复的**完整结局**：报告 + （失败时的）可读原因 + 是否被取消。
///
/// 为什么不像 `run_cancellable` 那样只回 `Result`：逐段模式要留住**失败那一段**的
/// 退出码与日志尾部（`Err` 里只有一个字符串），否则界面上只会剩下「失败了」三个字。
#[derive(Debug, Clone)]
pub struct Attempt {
    pub report: RestoreReport,
    /// `None` = 这一段成功了
    pub failure: Option<DbFailure>,
    pub cancelled: bool,
}

/// 逐段恢复里**一段**的结局（回执 / 界面按它一行一段地说话）。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SectionOutcome {
    pub section: RestoreSection,
    pub ok: bool,
    pub cancelled: bool,
    pub exit_code: Option<i32>,
    pub elapsed_ms: u64,
    /// 这一段实际跑的命令行（口令打码）—— 续跑时用户要粘贴的就是它
    pub display: String,
    pub log: String,
    pub log_trimmed_chars: usize,
}

/// 逐段恢复的**整份账**：跑到哪、停在哪、接下来从哪一段起。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SectionsReport {
    pub source: String,
    pub database: String,
    /// 实际并行度（0 = 串行）
    pub jobs: u32,
    /// **只包含真的跑过的段**（失败之后的那几段没有记录 —— 它们没跑，不是失败）
    pub sections: Vec<SectionOutcome>,
    /// 停在哪一段（`None` = 三段都过了）
    pub failed: Option<RestoreSection>,
    pub cancelled: bool,
    /// 失败那一段的可读原因（成功时 `None`）
    pub failure: Option<DbFailure>,
    /// 续跑要从哪几段起（失败段 + 它后面的段；成功时为空）
    pub resume_from: Vec<RestoreSection>,
    /// 能直接粘贴接着跑的那一条命令（失败段的；成功时 `None`）
    pub resume_command: Option<String>,
    /// 各段实测耗时之和（毫秒）
    pub elapsed_ms: u64,
}

/// 一次子进程运行的裸结局（**不做任何业务判断**，好让单测用 `cmd /C` 走同一条路）。
#[derive(Debug, Clone)]
pub struct RawRun {
    pub exit_code: Option<i32>,
    pub success: bool,
    /// stdout 与 stderr 按到达顺序拼起来的**全文**（未截断）
    pub log: String,
    pub elapsed_ms: u64,
    pub cancelled: bool,
}

/// 起一个子进程并等它（**可以被取消**）：`envs` 里的东西只进环境，不进 `argv`。
///
/// 与 `Command::output()` 的区别（为什么不用它）：`output()` 会一直阻塞到子进程结束 ——
/// 期间**没有任何地方**能把「用户点了取消」传进来，大库恢复几分钟就变成一个关不掉的转圈。
pub fn run_program(
    program: &Path,
    args: &[String],
    envs: &[(String, String)],
    cancel: &CancelFlag,
) -> Result<RawRun, DbFailure> {
    let mut command = Command::new(program);
    command
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    for (key, value) in envs {
        command.env(key, value);
    }
    let started = std::time::Instant::now();
    let mut child = command.spawn().map_err(|err| DbFailure {
        message: format!("起不来 {}：{err}", program.display()),
        hint: format!(
            "确认 {} 能直接运行（杀毒软件拦截 / 权限不足都会这样报）。",
            program.display()
        ),
    })?;

    // 两路读线程：**必须同时读**。子进程往满的 pipe 里写会阻塞 —— 只读一路的话，
    // 另一路话一多就把子进程憋死，看起来就是「恢复卡住不动」。
    let log: Arc<std::sync::Mutex<String>> = Arc::new(std::sync::Mutex::new(String::new()));
    let mut stdout_pipe = child.stdout.take().ok_or_else(|| DbFailure {
        message: "拿不到子进程的输出管道，恢复没有开始".to_string(),
        hint: "这属实现缺陷：请保留现场并报告。".to_string(),
    })?;
    let stderr_pipe = child.stderr.take().ok_or_else(|| DbFailure {
        message: "拿不到子进程的错误输出管道，恢复没有开始".to_string(),
        hint: "这属实现缺陷：请保留现场并报告。".to_string(),
    })?;
    let stdout_sink = log.clone();
    let stdout_reader = std::thread::spawn(move || {
        let mut buffer = Vec::new();
        let _ = stdout_pipe.read_to_end(&mut buffer);
        if let Ok(mut guard) = stdout_sink.lock() {
            guard.push_str(&String::from_utf8_lossy(&buffer));
        }
    });
    let stderr_sink = log.clone();
    let stderr_reader = std::thread::spawn(move || {
        let mut reader = std::io::BufReader::new(stderr_pipe);
        let mut chunk: Vec<u8> = Vec::new();
        loop {
            chunk.clear();
            match reader.read_until(b'\n', &mut chunk) {
                Ok(0) => break,
                Ok(_) => {
                    // 非 UTF-8（中文 Windows 的代码页）也按有损解码记账 —— 乱码也比如实丢字强
                    if let Ok(mut guard) = stderr_sink.lock() {
                        guard.push_str(&String::from_utf8_lossy(&chunk));
                    }
                }
                Err(_) => break,
            }
        }
    });

    let mut cancelled = false;
    let status = loop {
        if cancel.is_cancelled() {
            let _ = child.kill();
            cancelled = true;
            break child.wait().ok();
        }
        match child.try_wait() {
            Ok(Some(status)) => break Some(status),
            Ok(None) => std::thread::sleep(CANCEL_POLL),
            Err(err) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(DbFailure {
                    message: format!("等待 pg_restore 时出错：{err}（恢复可能没跑完）"),
                    hint: "这属实现缺陷：请保留现场并报告。".to_string(),
                });
            }
        }
    };
    let elapsed_ms = started.elapsed().as_millis() as u64;
    let _ = stdout_reader.join();
    let _ = stderr_reader.join();
    let full = log
        .lock()
        .map(|guard| guard.clone())
        .unwrap_or_else(|poison| poison.into_inner().clone());

    Ok(RawRun {
        exit_code: status.as_ref().and_then(|status| status.code()),
        success: status.as_ref().map(|status| status.success()).unwrap_or(false),
        log: full,
        elapsed_ms,
        cancelled,
    })
}

/// 跑一份计划（**不关心取消**：内部用一面永远不会被置位的旗）。
pub fn run(
    plan: &RestorePlan,
    password: Option<&str>,
    sslmode: Option<&str>,
) -> Result<RestoreReport, DbFailure> {
    run_cancellable(plan, password, sslmode, &CancelFlag::new())
}

/// 跑一份计划，**跑着可以被取消**。`password` / `sslmode` 都走环境变量（不进 argv）。
///
/// 单段模式的入口：失败时把可读原因当 `Err` 抛出去（与第一片的行为逐字一致）。
/// 逐段模式用 `attempt`，因为它要留失败那一段的退出码与日志。
pub fn run_cancellable(
    plan: &RestorePlan,
    password: Option<&str>,
    sslmode: Option<&str>,
    cancel: &CancelFlag,
) -> Result<RestoreReport, DbFailure> {
    let attempt = attempt(plan, password, sslmode, cancel)?;
    match attempt.failure {
        Some(failure) => Err(failure),
        None => Ok(attempt.report),
    }
}

/// 跑一份计划并**把结局整个留住**（报告 + 失败原因 + 是否取消）。
///
/// `Err` 只用于「起不来」这类基础设施故障：那时连报告都不存在。
pub fn attempt(
    plan: &RestorePlan,
    password: Option<&str>,
    sslmode: Option<&str>,
    cancel: &CancelFlag,
) -> Result<Attempt, DbFailure> {
    let program = plan.program.clone().ok_or_else(|| DbFailure {
        message: "没有可用的 pg_restore 程序，恢复没有开始".to_string(),
        hint: "先在「程序」一格填 pg_restore 的完整路径（自动查找的结果会显示在同一处）。".to_string(),
    })?;
    let mut envs: Vec<(String, String)> = Vec::new();
    if let Some(secret) = password.filter(|value| !value.is_empty()) {
        envs.push(("PGPASSWORD".to_string(), secret.to_string()));
    }
    if let Some(mode) = sslmode.filter(|value| !value.trim().is_empty()) {
        envs.push(("PGSSLMODE".to_string(), mode.trim().to_lowercase()));
    }

    let outcome = run_program(&program, &plan.args, &envs, cancel)?;
    let (log, trimmed) = backup::tail_log(&outcome.log, backup::LOG_LIMIT);
    let headline = first_line(&log);
    let display = plan.display();

    let report = RestoreReport {
        display,
        exit_code: outcome.exit_code,
        log,
        log_trimmed_chars: trimmed,
        elapsed_ms: outcome.elapsed_ms,
        source: plan.source.display().to_string(),
        section: plan.section,
        jobs: plan.jobs,
        database: plan.database.clone(),
    };

    if outcome.cancelled {
        // 取消**与失败分开说**，而且要比备份多说一句：恢复已经写进库里了，
        // 强杀不会把已恢复的对象撤回 —— 半途的库必须让用户知道。
        return Ok(Attempt {
            report,
            failure: Some(DbFailure {
                message: format!(
                    "恢复已取消：你在第 {} ms 叫停了它，库里可能停在半途",
                    outcome.elapsed_ms
                ),
                hint: format!(
                    "已被 pg_restore 写进去的对象不会自动撤销。要一份干净的结果，勾上「先删后建（--clean）」重跑一次；\
                     只想恢复某一段就改「恢复哪一段」。子进程最后说：{headline}。"
                ),
            }),
            cancelled: true,
        });
    }

    if outcome.success {
        return Ok(Attempt {
            report,
            failure: None,
            cancelled: false,
        });
    }

    let code = match outcome.exit_code {
        Some(code) => format!("退出码 {code}"),
        None => "进程被意外终止（没有退出码）".to_string(),
    };
    let lowered = outcome.log.to_lowercase();
    let hint = if lowered.contains("authentication")
        || lowered.contains("password")
        || outcome.log.contains("口令")
    {
        "口令被拒：核对连接里的用户名与口令（口令只进环境变量，不进命令行）。"
    } else if lowered.contains("does not appear to be a valid archive")
        || lowered.contains("not a valid archive")
    {
        "这不是 pg_restore 认的归档：纯 SQL 备份要用 psql 灌；本界面只恢复「自定义归档」与「目录形式」。"
    } else if lowered.contains("already exists") || outcome.log.contains("已存在") {
        "对象已经存在于目标库里：勾上「先删后建（--clean）」再跑，或换一个空库。"
    } else {
        "看上面子进程的原话；日志尾部已带回，完整输出由 pg_restore 打印。"
    };
    Ok(Attempt {
        report,
        failure: Some(DbFailure {
            message: format!("pg_restore {code}：{headline}"),
            hint: format!("{hint}（本次耗时 {} ms）", outcome.elapsed_ms),
        }),
        cancelled: false,
    })
}

/// **逐段执行**：按计划表的顺序一段一段跑，**遇错即停**，把每段的账记下来。
///
/// 停在失败那一段之后**不做任何猜测**：不自动清库、不自动跳过、不自动重试 ——
/// 回执只回答三件事：跑过哪几段、停在哪一段为什么、接下来从哪一段起（`resume_from`）。
pub fn run_sections<F>(plans: &[RestorePlan], mut run_one: F) -> Result<SectionsReport, DbFailure>
where
    F: FnMut(&RestorePlan) -> Result<Attempt, DbFailure>,
{
    let mut sections: Vec<SectionOutcome> = Vec::new();
    let mut failed: Option<RestoreSection> = None;
    let mut cancelled = false;
    let mut failure: Option<DbFailure> = None;
    let mut resume_command: Option<String> = None;

    for plan in plans {
        let attempt = run_one(plan)?;
        let ok = attempt.failure.is_none();
        sections.push(SectionOutcome {
            section: plan.section,
            ok,
            cancelled: attempt.cancelled,
            exit_code: attempt.report.exit_code,
            elapsed_ms: attempt.report.elapsed_ms,
            display: attempt.report.display.clone(),
            log: attempt.report.log.clone(),
            log_trimmed_chars: attempt.report.log_trimmed_chars,
        });
        if !ok {
            failed = Some(plan.section);
            cancelled = attempt.cancelled;
            failure = attempt.failure;
            resume_command = Some(attempt.report.display.clone());
            // 本段失败 ⇒ 后面的段一律不跑：半截结构上灌数据只会把现场弄得更难收拾
            break;
        }
    }

    let elapsed_ms = sections.iter().map(|section| section.elapsed_ms).sum();
    let first = plans.first();
    Ok(SectionsReport {
        source: first.map(|plan| plan.source.display().to_string()).unwrap_or_default(),
        database: first.map(|plan| plan.database.clone()).unwrap_or_default(),
        jobs: first.map(|plan| plan.jobs).unwrap_or(0),
        resume_from: if failed.is_some() {
            resume_sections(failed)
        } else {
            Vec::new()
        },
        sections,
        failed,
        cancelled,
        failure,
        resume_command,
        elapsed_ms,
    })
}

/// 回执里只带**第一行**（日志尾部整段在 `RestoreReport.log`，别把两者搅在一起）。
fn first_line(text: &str) -> String {
    text.lines()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .unwrap_or("（子进程没有输出）")
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn target() -> RestoreTarget {
        RestoreTarget {
            host: "127.0.0.1".to_string(),
            port: 5432,
            user: "postgres".to_string(),
            database: "shop".to_string(),
        }
    }

    fn options(clean: bool, section: RestoreSection, jobs: u32) -> RestoreOptions {
        RestoreOptions {
            clean,
            section,
            jobs,
            fail_fast: false,
        }
    }

    #[test]
    fn each_section_maps_to_one_pg_restore_flag() {
        assert_eq!(RestoreSection::All.pg_flag(), None);
        assert_eq!(RestoreSection::PreData.pg_flag(), Some("pre-data"));
        assert_eq!(RestoreSection::Data.pg_flag(), Some("data"));
        assert_eq!(RestoreSection::PostData.pg_flag(), Some("post-data"));

        let source = PathBuf::from(r"D:\backup\shop.dump");
        let args = plan_args(
            &target(),
            &source,
            SourceKind::File,
            &options(false, RestoreSection::Data, 0),
        );
        assert!(args.contains(&"--section=data".to_string()));
        // 「全部」不该出现任何 --section（让 pg_restore 走它自己的缺省）
        let all = plan_args(
            &target(),
            &source,
            SourceKind::File,
            &options(false, RestoreSection::All, 0),
        );
        assert!(!all.iter().any(|arg| arg.starts_with("--section")));
    }

    #[test]
    fn the_plan_never_carries_a_password_in_argv() {
        let source = PathBuf::from(r"D:\backup\shop.dump");
        let args = plan_args(
            &target(),
            &source,
            SourceKind::File,
            &options(true, RestoreSection::All, 0),
        );
        assert!(
            !args
                .iter()
                .any(|arg| arg.contains("PGPASSWORD") || arg == "--password"),
            "argv 里不许出现口令相关的任何东西：{args:?}"
        );
        let plan = RestorePlan {
            program: Some(PathBuf::from(r"C:\Program Files\PostgreSQL\18\bin\pg_restore.exe")),
            args: args.clone(),
            source,
            kind: SourceKind::File,
            database: "shop".to_string(),
            section: RestoreSection::All,
            jobs: 0,
        };
        let display = plan.display();
        assert!(display.starts_with("PGPASSWORD=*** "), "{display}");
        // 路径带空格 ⇒ 加引号（要么能复制去跑，要么这句话没有意义）
        assert!(display.contains("\"C:\\Program Files"), "{display}");
    }

    #[test]
    fn clean_is_always_paired_with_if_exists() {
        let source = PathBuf::from(r"D:\backup\shop.dump");
        let with = plan_args(
            &target(),
            &source,
            SourceKind::File,
            &options(true, RestoreSection::All, 0),
        );
        assert!(with.contains(&"--clean".to_string()));
        assert!(with.contains(&"--if-exists".to_string()));
        let without = plan_args(
            &target(),
            &source,
            SourceKind::File,
            &options(false, RestoreSection::All, 0),
        );
        assert!(!without.contains(&"--clean".to_string()));
        assert!(!without.contains(&"--if-exists".to_string()));
    }

    #[test]
    fn jobs_are_only_for_directory_archives_and_everything_else_is_serial() {
        let file = PathBuf::from(r"D:\backup\shop.dump");
        let dir = PathBuf::from(r"D:\backup\shop-dir");
        // 文件归档：用户填了 4 也不加 -j（pg_restore 会直接拒绝）
        assert_eq!(effective_jobs(SourceKind::File, 4), 0);
        let file_args = plan_args(
            &target(),
            &file,
            SourceKind::File,
            &options(false, RestoreSection::All, 4),
        );
        assert!(!file_args.iter().any(|arg| arg.starts_with("--jobs")));
        // 目录归档：4 就真的给 4；1 等于不并行
        assert_eq!(effective_jobs(SourceKind::Directory, 4), 4);
        let dir_args = plan_args(
            &target(),
            &dir,
            SourceKind::Directory,
            &options(false, RestoreSection::All, 4),
        );
        assert!(dir_args.contains(&"--jobs=4".to_string()));
        let serial = plan_args(
            &target(),
            &dir,
            SourceKind::Directory,
            &options(false, RestoreSection::All, 1),
        );
        assert!(!serial.iter().any(|arg| arg.starts_with("--jobs")));
        // 上限 16：填 200 不会变成一个荒唐的命令行
        assert_eq!(effective_jobs(SourceKind::Directory, 200), 16);
    }

    #[test]
    fn the_source_file_is_the_last_argument_so_the_command_reads_left_to_right() {
        let source = PathBuf::from(r"D:\backup\shop.dump");
        let args = plan_args(
            &target(),
            &source,
            SourceKind::File,
            &options(true, RestoreSection::PostData, 0),
        );
        assert_eq!(args.last(), Some(&source.display().to_string()));
    }

    #[test]
    fn an_empty_source_is_refused_before_anything_runs() {
        let failure = check_source("   ").expect_err("空路径必须被拒");
        assert!(failure.message.contains("还没选"), "{}", failure.message);
    }

    #[test]
    fn a_missing_source_is_refused_with_the_path_it_looked_for() {
        let missing = r"D:\backup\definitely-not-there-20261019.dump";
        let failure = check_source(missing).expect_err("不存在的源必须被拒");
        assert!(failure.message.contains(missing), "{}", failure.message);
        assert!(failure.hint.contains("已有"), "{}", failure.hint);
    }

    #[test]
    fn a_plain_sql_file_is_refused_with_the_real_alternative() {
        let dir = std::env::temp_dir().join("doyah-restore-src-test");
        let _ = std::fs::create_dir_all(&dir);
        let sql = dir.join("shop-20261019.sql");
        std::fs::write(&sql, "-- plain sql\n").expect("写临时文件");
        let failure = check_source(&sql.display().to_string()).expect_err("纯 SQL 必须被拒");
        assert!(failure.message.contains("纯 SQL"), "{}", failure.message);
        assert!(failure.hint.contains("psql"), "{}", failure.hint);
        let _ = std::fs::remove_file(&sql);
    }

    #[test]
    fn a_directory_archive_is_recognised_as_a_directory() {
        let dir = std::env::temp_dir().join("doyah-restore-dir-test");
        let _ = std::fs::create_dir_all(&dir);
        let (path, kind) = check_source(&dir.display().to_string()).expect("目录归档应被接受");
        assert_eq!(path, dir);
        assert_eq!(kind, SourceKind::Directory);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[cfg(windows)]
    #[test]
    fn a_real_child_process_reports_exit_code_and_log() {
        // 起一个真进程走同一条运行器：退出码、日志、耗时都得是真的读数
        let program = PathBuf::from("cmd.exe");
        let args = vec![
            "/C".to_string(),
            "echo restore-probe-line& exit 3".to_string(),
        ];
        let outcome = run_program(&program, &args, &[], &CancelFlag::new()).expect("起得来 cmd.exe");
        assert_eq!(outcome.exit_code, Some(3));
        assert!(!outcome.success);
        assert!(outcome.log.contains("restore-probe-line"), "{}", outcome.log);
        assert!(!outcome.cancelled);
    }

    #[cfg(windows)]
    #[test]
    fn cancelling_kills_the_child_and_says_so() {
        let program = PathBuf::from("cmd.exe");
        let args = vec![
            "/C".to_string(),
            "ping -n 10 127.0.0.1 > nul".to_string(),
        ];
        let cancel = CancelFlag::new();
        let flag = cancel.clone();
        std::thread::spawn(move || {
            std::thread::sleep(std::time::Duration::from_millis(400));
            flag.cancel();
        });
        let outcome = run_program(&program, &args, &[], &cancel).expect("起得来 cmd.exe");
        assert!(outcome.cancelled, "取消旗置位后必须判成取消");
        // ping -n 10 本机大约要 9 秒；400ms 就叫停 ⇒ 必须远小于它
        assert!(outcome.elapsed_ms < 5000, "耗时 {}", outcome.elapsed_ms);
    }

    // ── 逐段恢复 / 失败续跑（本片）──────────────────────────────────────────────

    fn section_plan_set(from: Option<RestoreSection>) -> Vec<RestorePlan> {
        section_plans(
            Some(PathBuf::from(r"C:\pg\bin\pg_restore.exe")),
            &target(),
            &PathBuf::from(r"D:\backup\shop.dump"),
            SourceKind::File,
            options(true, RestoreSection::All, 0),
            from,
        )
    }

    /// 一份「假装跑过」的结局：单测只验编排，真子进程由下面那条用例与既有 `run_program` 用例守。
    fn pretend(plan: &RestorePlan, ok: bool) -> Attempt {
        Attempt {
            report: RestoreReport {
                display: plan.display(),
                exit_code: Some(if ok { 0 } else { 1 }),
                log: if ok { "restored".to_string() } else { "boom: relation does not exist".to_string() },
                log_trimmed_chars: 0,
                elapsed_ms: 7,
                source: plan.source.display().to_string(),
                section: plan.section,
                jobs: plan.jobs,
                database: plan.database.clone(),
            },
            failure: if ok {
                None
            } else {
                Some(DbFailure {
                    message: "pg_restore 退出码 1：boom".to_string(),
                    hint: "看上面子进程的原话".to_string(),
                })
            },
            cancelled: false,
        }
    }

    #[test]
    fn resume_starts_at_the_failed_section_and_keeps_the_dependency_order() {
        assert_eq!(
            resume_sections(None),
            vec![RestoreSection::PreData, RestoreSection::Data, RestoreSection::PostData]
        );
        // 前段失败 ⇒ 还是三段全跑（它本来就是第一段，没有「更前面」可省）
        assert_eq!(resume_sections(Some(RestoreSection::PreData)).len(), 3);
        // 数据段失败 ⇒ 数据 + 后段（不能再回到前段：结构已经进去了）
        assert_eq!(
            resume_sections(Some(RestoreSection::Data)),
            vec![RestoreSection::Data, RestoreSection::PostData]
        );
        assert_eq!(
            resume_sections(Some(RestoreSection::PostData)),
            vec![RestoreSection::PostData]
        );
        // 一次性模式失败：pg_restore 不告诉外界停在哪 ⇒ 只能从头上，且不能假装知道
        assert_eq!(resume_sections(Some(RestoreSection::All)).len(), 3);
    }

    #[test]
    fn the_section_plans_carry_one_command_per_section_and_always_fail_fast() {
        let plans = section_plan_set(None);
        assert_eq!(plans.len(), 3);
        let sections: Vec<RestoreSection> = plans.iter().map(|plan| plan.section).collect();
        assert_eq!(sections, SECTION_SEQUENCE.to_vec(), "段序必须是 结构 → 数据 → 索引");

        for plan in &plans {
            let flag = plan.section.pg_flag().expect("逐段模式下每段都必须带 --section");
            assert!(
                plan.args.contains(&format!("--section={flag}")),
                "{} 少了 --section：{:?}",
                flag,
                plan.args
            );
            assert!(
                plan.args.contains(&"--exit-on-error".to_string()),
                "逐段模式下每段都必须 --exit-on-error（否则失败会被后面的成功掩掉）"
            );
            // clean 是用户的开关，逐段不改变它；每条都配 --if-exists
            assert!(plan.args.contains(&"--clean".to_string()));
            assert!(plan.args.contains(&"--if-exists".to_string()));
            // 源永远是最后一个参数
            assert_eq!(plan.args.last(), Some(&plan.source.display().to_string()));
        }
        // 从数据段起 ⇒ 只出两条（续跑不是「把三段重跑一遍」）
        let resumed = section_plan_set(Some(RestoreSection::Data));
        assert_eq!(resumed.len(), 2);
        assert_eq!(resumed[0].section, RestoreSection::Data);
        assert_eq!(resumed[1].section, RestoreSection::PostData);
    }

    #[test]
    fn a_failed_section_stops_the_sequence_and_points_at_the_next_step() {
        let plans = section_plan_set(None);
        let mut calls: Vec<RestoreSection> = Vec::new();
        let report = run_sections(&plans, |plan| {
            calls.push(plan.section);
            Ok(pretend(plan, plan.section != RestoreSection::Data))
        })
        .expect("编排本身不该出错");

        // 前段跑过、数据段失败 ⇒ 后段**一次都没跑**
        assert_eq!(calls, vec![RestoreSection::PreData, RestoreSection::Data]);
        assert_eq!(report.failed, Some(RestoreSection::Data));
        assert_eq!(report.sections.len(), 2);
        assert!(report.sections[0].ok);
        assert!(!report.sections[1].ok);
        assert_eq!(report.sections[1].exit_code, Some(1));
        assert!(report.sections[1].log.contains("relation does not exist"));
        // 续跑 = 失败段 + 它后面的段，且回执里有一条能直接粘贴的命令
        assert_eq!(
            report.resume_from,
            vec![RestoreSection::Data, RestoreSection::PostData]
        );
        let command = report.resume_command.expect("失败时必须给一条可粘贴的续跑命令");
        assert!(command.contains("--section=data"), "{command}");
        assert!(command.contains("--exit-on-error"), "{command}");
        assert!(command.starts_with("PGPASSWORD=*** "), "{command}");
        assert!(!report.cancelled);
        assert_eq!(report.elapsed_ms, 14);
    }

    #[test]
    fn a_clean_sequence_reports_every_section_and_has_nothing_to_resume() {
        let plans = section_plan_set(None);
        let report = run_sections(&plans, |plan| Ok(pretend(plan, true))).expect("编排本身不该出错");
        assert_eq!(report.sections.len(), 3);
        assert!(report.sections.iter().all(|section| section.ok));
        assert_eq!(report.failed, None);
        assert!(report.resume_from.is_empty(), "全过了就没有「续跑」这回事");
        assert_eq!(report.resume_command, None);
        assert_eq!(report.failure, None);
    }

    #[test]
    fn cancelling_a_section_stops_the_sequence_and_says_it_was_a_cancel() {
        let plans = section_plan_set(None);
        let report = run_sections(&plans, |plan| {
            if plan.section == RestoreSection::PreData {
                return Ok(pretend(plan, true));
            }
            let mut attempt = pretend(plan, false);
            attempt.cancelled = true;
            attempt.failure = Some(DbFailure {
                message: "恢复已取消：你在第 900 ms 叫停了它，库里可能停在半途".to_string(),
                hint: "已写入的对象不会自动撤销".to_string(),
            });
            Ok(attempt)
        })
        .expect("编排本身不该出错");
        assert_eq!(report.failed, Some(RestoreSection::Data));
        assert!(report.cancelled, "取消与失败必须分开说");
        assert_eq!(report.sections.len(), 2, "取消后不许再往下跑第三段");
    }

    #[cfg(windows)]
    #[test]
    fn a_real_child_process_becomes_a_failed_attempt_with_its_exit_code_and_log() {
        // 走 `attempt` 这条真路：报告要带退出码与日志尾部，失败原因要能读
        let plan = RestorePlan {
            program: Some(PathBuf::from("cmd.exe")),
            args: vec![
                "/C".to_string(),
                "echo restore-attempt-line& exit 2".to_string(),
            ],
            source: PathBuf::from(r"D:\backup\shop.dump"),
            kind: SourceKind::File,
            database: "shop".to_string(),
            section: RestoreSection::Data,
            jobs: 0,
        };
        let attempt = attempt(&plan, None, None, &CancelFlag::new()).expect("起得来 cmd.exe");
        assert_eq!(attempt.report.exit_code, Some(2));
        assert!(attempt.report.log.contains("restore-attempt-line"));
        assert!(!attempt.cancelled);
        let failure = attempt.failure.expect("退出码 2 必须判成失败");
        assert!(failure.message.contains("退出码 2"), "{}", failure.message);
    }
}
