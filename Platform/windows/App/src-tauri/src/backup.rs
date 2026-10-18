//! **备份**（`FR-IO-04` 的 Windows 侧落法）：封装本机 `pg_dump`。
//!
//! ## 为什么是「起子进程」而不是自己写导出
//!
//! 备份要一致快照（`pg_dump` 自己会开可重复读事务）、要三种格式（plain / custom / directory）、
//! 要处理大对象与序列 —— 自己拼 `COPY` 只能做到「看起来像备份」。三书写的就是「封装 `pg_dump`
//! / `pg_restore`，**展示实际命令行与执行日志**」：命令行要真的能看见，日志要真的是子进程吐的那份。
//!
//! ## 四条口径（每条都对应一个已发生过的坑）
//!
//! 1. **口令只走环境变量 `PGPASSWORD`**：绝不进 `argv`（进 argv 就会出现在 `ps` / 任务管理器 /
//!    我们自己的日志里），也绝不进 `display()` 的字符串（那里写 `PGPASSWORD=***`）。
//! 2. **命令行先摊出来再跑**：`plan()` 只算不跑，界面把 `display()` 摆给用户看 —— 这是需求的
//!    原文要求，也是「我到底对你的库做了什么」的答案。
//! 3. **不覆盖既有备份**：目标已存在 ⇒ 拒绝并说明（备份是「怕丢」的东西，静默覆盖等于用新的一次
//!    赌旧的那份没用）。目录形式（`-F d`）另有 `pg_dump` 自己的要求：目标目录必须不存在。
//! 4. **日志尾部有上限**：一次大库备份的日志可以几十万行 —— 回执只带**尾部**，并在被截断时
//!    如实说「前面还有 N 字符没带回来」。真要看全文，日志里给出的就是用户自己选的路径旁边。
//!
//! ## 失败一律带可读信息
//!
//! 程序找不到 ⇒ 说清「去哪儿找过」并把候选位置列出来（不静默退化成一句「失败」）；
//! 退出码非零 ⇒ 服务端/`pg_dump` 的原话原样保留，附一句「怎么看」。

use std::io::{BufRead, Read};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use crate::postgres::DbFailure;

/// 轮询子进程的间隔：太密白烧 CPU（每 100ms 一次 `try_wait` 对一次备份可忽略），
/// 太疏则「点了取消还要等好几秒才停」—— 用户对取消的容忍度比对进度条低得多。
const CANCEL_POLL: std::time::Duration = std::time::Duration::from_millis(100);

/// **取消旗**（一次备份一个）：界面按「取消」⇒ 外壳置位 ⇒ `run_cancellable` 看见就杀掉子进程。
///
/// 为什么用「轮询 + `kill`」而不是等它自己结束：`pg_dump` 一次性备份一个大库可能几分钟，
/// 期间它不读 stdin、也不响应 Ctrl-C 之外的信号 —— 用户在界面上已经决定不要这份备份了，
/// 唯一的出路是终止进程。代价是**强杀**（Windows 上是 `TerminateProcess`）：进程不会做清理，
/// 于是**半截产物必须由我们来删**（见 `clear_partial`），这条与失败路径是同一条口径。
#[derive(Debug, Clone)]
pub struct CancelFlag(Arc<AtomicBool>);

impl CancelFlag {
    pub fn new() -> Self {
        Self(Arc::new(AtomicBool::new(false)))
    }

    /// 置位（可重复调；已经取消过就保持取消）。
    pub fn cancel(&self) {
        self.0.store(true, Ordering::SeqCst);
    }

    pub fn is_cancelled(&self) -> bool {
        self.0.load(Ordering::SeqCst)
    }
}

impl Default for CancelFlag {
    fn default() -> Self {
        Self::new()
    }
}

/// **跑着的读数**（界面轮询这一条）。三个数**全是实测的** —— 没有一个按比例估：
/// 我们不知道总量（`pg_dump` 也不告诉我们），所以界面上永远不出现「已经 63%」这种编出来的东西。
///
/// 两个来源各管一段：
///   · `lines` / `last_line` 来自 stderr 的**逐行**到达（`--verbose` 下一张表一行）；
///   · `bytes` 来自每 100ms 量一次目标体积 —— 导一张**大表**时十几分钟不吐一行，
///     体积在涨就是「它还活着」的唯一证据。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BackupProgress {
    /// 这次跑了多少毫秒
    pub elapsed_ms: u64,
    /// 目标现在多大（目录形式为其中各文件之和）
    pub bytes: u64,
    /// 子进程已经吐了多少行（空行不算）
    pub lines: usize,
    /// 最近一行原话；还没吐过就是 `None`
    pub last_line: Option<String>,
}

/// 一次备份共享的读数槽（外壳放进全局槽、界面按命令轮询它，两边看的是同一份）。
#[derive(Debug, Clone, Default)]
pub struct ProgressSink(std::sync::Arc<std::sync::Mutex<ProgressInner>>);

#[derive(Debug, Default)]
struct ProgressInner {
    started: Option<std::time::Instant>,
    bytes: u64,
    lines: usize,
    last_line: Option<String>,
}

impl ProgressSink {
    pub fn new() -> Self {
        Self::default()
    }

    /// 记下开跑时刻（`elapsed_ms` 从它算）。没调过 ⇒ 读数里的耗时是 0，不是「跑了很久」。
    fn start(&self) {
        self.lock().started = Some(std::time::Instant::now());
    }

    /// 子进程吐了一行（空行不算 —— 它只会让「行数」这个读数变脏）。
    fn note_line(&self, line: &str) {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            return;
        }
        let mut inner = self.lock();
        inner.lines += 1;
        inner.last_line = Some(trimmed.to_string());
    }

    /// 心跳量到的体积（只进不退：目标被删掉时读数是 0，也不该把界面的读数拉回去）。
    fn note_bytes(&self, bytes: u64) {
        let mut inner = self.lock();
        if bytes > inner.bytes {
            inner.bytes = bytes;
        }
    }

    pub fn snapshot(&self) -> BackupProgress {
        let inner = self.lock();
        BackupProgress {
            elapsed_ms: inner
                .started
                .map(|at| at.elapsed().as_millis() as u64)
                .unwrap_or(0),
            bytes: inner.bytes,
            lines: inner.lines,
            last_line: inner.last_line.clone(),
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, ProgressInner> {
        self.0.lock().unwrap_or_else(|poison| poison.into_inner())
    }
}

/// 回执里带的日志字符上限（只留尾部）。
pub const LOG_LIMIT: usize = 4000;

/// 备份格式（与 `pg_dump -F` 一一对应）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Deserialize, serde::Serialize)]
#[serde(rename_all = "lowercase")]
pub enum BackupFormat {
    /// `-F p`：纯 SQL 文本（能直接看、能 psql 直接灌）
    Plain,
    /// `-F c`：自定义归档（体积小、可 `pg_restore --section` 选段）
    Custom,
    /// `-F d`：目录形式（可并行 `--jobs`，但目标目录必须不存在）
    Directory,
}

impl BackupFormat {
    /// `pg_dump -F` 的取值。
    pub fn pg_dump_flag(self) -> &'static str {
        match self {
            Self::Plain => "p",
            Self::Custom => "c",
            Self::Directory => "d",
        }
    }

    /// 这一档产出的是**目录**还是**文件**（决定「目标已存在」怎么判、体积怎么算）。
    pub fn produces_directory(self) -> bool {
        matches!(self, Self::Directory)
    }

    /// 档位的中文短名（回执里用；界面文案仍走 i18n，这里只给日志/命令回执）。
    pub fn label(self) -> &'static str {
        match self {
            Self::Plain => "纯 SQL",
            Self::Custom => "自定义归档",
            Self::Directory => "目录形式",
        }
    }
}

/// 连到哪台服务器、备份哪个库（从**当前会话**里取，不从配置里猜）。
#[derive(Debug, Clone)]
pub struct BackupTarget {
    pub host: String,
    pub port: u16,
    pub user: String,
    pub database: String,
}

/// 一份**还没跑**的备份计划。
#[derive(Debug, Clone)]
pub struct BackupPlan {
    /// 找到的程序（找不到就是 `None` —— 计划仍可展示，跑不了）
    pub program: Option<PathBuf>,
    /// `pg_dump` 的参数（**口令不在这里面**）
    pub args: Vec<String>,
    pub target: PathBuf,
    pub format: BackupFormat,
    pub database: String,
}

impl BackupPlan {
    /// **给用户看的命令行**：口令位置写 `PGPASSWORD=***`；带空格的参数加引号。
    pub fn display(&self) -> String {
        let program = match &self.program {
            Some(path) => path.display().to_string(),
            None => "pg_dump".to_string(),
        };
        display_command(&program, &self.args, true)
    }
}

/// 拼一条可读的命令行（`mask_password` ⇒ 前面挂 `PGPASSWORD=***`）。
pub fn display_command(program: &str, args: &[String], mask_password: bool) -> String {
    let mut parts: Vec<String> = Vec::with_capacity(args.len() + 2);
    if mask_password {
        parts.push("PGPASSWORD=***".to_string());
    }
    parts.push(quote_if_needed(program));
    for arg in args {
        parts.push(quote_if_needed(arg));
    }
    parts.join(" ")
}

/// 含空白或引号的参数加双引号（只为**可读 / 可复制**，真正执行走 argv，不经过 shell）。
fn quote_if_needed(value: &str) -> String {
    if value.is_empty() || value.chars().any(|c| c.is_whitespace() || c == '"') {
        format!("\"{}\"", value.replace('"', "\\\""))
    } else {
        value.to_string()
    }
}

/// 纯函数：`pg_dump` 的参数表。
///
/// 口径：**只放「连哪儿、备份哪个库、什么格式、写到哪」** + 一个 `--verbose`。
/// 加密 / 压缩 / 并行都不在这里猜 —— 猜出来的默认值会让「同一条命令两次产出不同」，
/// 而备份最怕的就是不可复现。
///
/// `--verbose` 是**进度读数的唯一来源**：不带它 `pg_dump` 全程一个字都不说（stderr 静默），
/// 界面上就只剩一个没人知道真假的转圈。它只往 stderr 写，不污染归档与纯 SQL 产出。
pub fn plan_args(target: &BackupTarget, path: &str, format: BackupFormat) -> Vec<String> {
    vec![
        "-h".to_string(),
        target.host.clone(),
        "-p".to_string(),
        target.port.to_string(),
        "-U".to_string(),
        target.user.clone(),
        "-d".to_string(),
        target.database.clone(),
        "-F".to_string(),
        format.pg_dump_flag().to_string(),
        "-f".to_string(),
        path.to_string(),
        "--verbose".to_string(),
    ]
}

/// 校验目标路径，并按格式判「已存在」。
///
/// 三条不同的拒绝理由（**分开说**，因为它们对用户意味着不同的下一步）：
/// 路径空 / 目录形式要求目标不存在 / 覆盖已有备份必须由用户自己先处理。
pub fn check_target(path: &str, format: BackupFormat) -> Result<PathBuf, DbFailure> {
    let trimmed = path.trim();
    if trimmed.is_empty() {
        return Err(DbFailure {
            message: "还没填备份写到哪儿".to_string(),
            hint: "填一个完整路径（例如 D:\\backup\\shop-20261018.dump）；目录形式（-F d）填一个尚不存在的目录。"
                .to_string(),
        });
    }
    let target = PathBuf::from(trimmed);
    if target.exists() {
        return Err(if format.produces_directory() {
            DbFailure {
                message: format!("{} 已经存在，而目录形式的备份要求目标目录不存在", target.display()),
                hint: "换一个新目录名（pg_dump 会自己建它）；要重做请自己先把旧目录挪走。".to_string(),
            }
        } else {
            DbFailure {
                message: format!("{} 已经存在 —— 备份不覆盖既有文件", target.display()),
                hint: "换一个文件名，或自己先把旧备份挪走（覆盖等于用这一次赌上一次没用）。".to_string(),
            }
        });
    }
    Ok(target)
}

/// 从一堆候选里挑**版本最高**的一个（纯函数，供 `find_program` 用与单测判）。
///
/// 版本按「点分段、逐段比数字」排；认不出版本的排最后（不让怪名字挤掉真版本）。
pub fn best_candidate(candidates: &[(String, PathBuf)]) -> Option<PathBuf> {
    let mut best: Option<(Vec<u32>, &PathBuf)> = None;
    for (version, path) in candidates {
        let parsed: Vec<u32> = version
            .split('.')
            .filter_map(|part| part.trim().parse::<u32>().ok())
            .collect();
        let replace = match &best {
            None => true,
            Some((current, _)) => parsed > *current,
        };
        if replace {
            best = Some((parsed, path));
        }
    }
    best.map(|(_, path)| path.clone())
}

/// 找 `pg_dump`：**显式路径 → PATH → 各盘 PostgreSQL 安装目录**（新版本优先）。
///
/// 为什么还要扫安装目录：Windows 上 PostgreSQL 装完**默认不进 PATH**，而 `pg_dump` 就在那里。
/// 只认 PATH 的话，用户明明装了数据库客户端却得到「找不到程序」，那种失败最难解释。
pub fn find_program(explicit: Option<&str>) -> Result<PathBuf, DbFailure> {
    find_program_named(explicit, program_name())
}

/// 同一条查找口径，但程序名可换（`FR-IO-05` 恢复要找 `pg_restore`）。
///
/// 为什么参数化而不是在恢复侧另抄一份：三处搜索顺序（显式路径 → PATH → 各盘安装目录、
/// 新版本优先）**必须与备份一致** —— 两处各写一遍，迟早出现「备份说找到了、恢复说没装」。
pub fn find_program_named(explicit: Option<&str>, program: &str) -> Result<PathBuf, DbFailure> {
    if let Some(given) = explicit.map(str::trim).filter(|text| !text.is_empty()) {
        let path = PathBuf::from(given);
        if path.is_file() {
            return Ok(path);
        }
        return Err(DbFailure {
            message: format!("指定的程序不是可执行文件：{}", path.display()),
            hint: format!(
                "填 {program} 的完整路径（Windows 一般在 C:\\Program Files\\PostgreSQL\\<版本>\\bin\\{program}）；留空则自动找。"
            ),
        });
    }

    let mut searched: Vec<String> = Vec::new();
    if let Some(found) = on_path(program) {
        return Ok(found);
    }
    searched.push("PATH".to_string());

    let mut candidates: Vec<(String, PathBuf)> = Vec::new();
    let mut roots: Vec<PathBuf> = vec![PathBuf::from(r"C:\Program Files\PostgreSQL")];
    if let Ok(extra) = std::env::var("DOYAH_PG_ROOT") {
        if !extra.trim().is_empty() {
            roots.insert(0, PathBuf::from(extra));
        }
    }
    for root in &roots {
        searched.push(format!("{}\\<版本>\\bin", root.display()));
        let Ok(entries) = std::fs::read_dir(root) else {
            continue;
        };
        for entry in entries.flatten() {
            let candidate = entry.path().join("bin").join(program);
            if candidate.is_file() {
                let version = entry.file_name().to_string_lossy().to_string();
                candidates.push((version, candidate));
            }
        }
    }
    if let Some(found) = best_candidate(&candidates) {
        return Ok(found);
    }

    Err(DbFailure {
        message: format!("找不到 {program}（本机没装 PostgreSQL 客户端，或装在了别处）"),
        hint: format!(
            "找过这些地方：{}。要么装 PostgreSQL 客户端，要么在上面「程序」一格填 {program} 的完整路径。",
            searched.join(" / ")
        ),
    })
}

/// 平台上的可执行文件名。
fn program_name() -> &'static str {
    if cfg!(windows) {
        "pg_dump.exe"
    } else {
        "pg_dump"
    }
}

/// 在 `PATH` 里找（**只看是不是真文件**，不执行 —— 执行留到 `run`）。
fn on_path(program: &str) -> Option<PathBuf> {
    let raw = std::env::var_os("PATH")?;
    for dir in std::env::split_paths(&raw) {
        let candidate = dir.join(program);
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    None
}

/// 一次备份的结局（**成功与失败都带日志与退出码**）。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BackupReport {
    /// 展示用的命令行（口令打码）
    pub display: String,
    /// 退出码（进程被信号干掉时是 `None`）
    pub exit_code: Option<i32>,
    /// **日志尾部**（stdout + stderr 按发生顺序拼）
    pub log: String,
    /// 前面还有多少字符没带回来（没截断就是 0）
    pub log_trimmed_chars: usize,
    /// 产出的字节数（目录形式是其中各文件之和）
    pub bytes: u64,
    /// 耗时（毫秒）
    pub elapsed_ms: u64,
    /// 备份写到哪儿
    pub target: String,
    pub format: BackupFormat,
}

/// 日志只留尾部：返回（尾部文本，被砍掉的字符数）。
pub fn tail_log(text: &str, limit: usize) -> (String, usize) {
    let total = text.chars().count();
    if total <= limit {
        return (text.to_string(), 0);
    }
    let skip = total - limit;
    let tail: String = text.chars().skip(skip).collect();
    (tail, skip)
}

/// 跑一份计划（**不关心取消**：内部用一面永远不会被置位的旗）。
///
/// 需要「跑着能停」就调 `run_cancellable`，把界面按下去的那面旗传进来。
pub fn run(plan: &BackupPlan, password: Option<&str>, sslmode: Option<&str>) -> Result<BackupReport, DbFailure> {
    run_cancellable(plan, password, sslmode, &CancelFlag::new())
}

/// 跑一份计划，**跑着可以被取消**（不关心进度读数：内部用一份没人看的读数槽）。
pub fn run_cancellable(
    plan: &BackupPlan,
    password: Option<&str>,
    sslmode: Option<&str>,
    cancel: &CancelFlag,
) -> Result<BackupReport, DbFailure> {
    run_cancellable_with_progress(plan, password, sslmode, cancel, &ProgressSink::new())
}

/// 跑一份计划，**跑着可以被取消、也可以被观察**。`password` / `sslmode` 都走环境变量（不进 argv）。
///
/// 与 `Command::output()` 的区别（为什么不用它）：
///   · `output()` 会一直阻塞到子进程结束 —— 期间**没有任何地方**能把「用户点了取消」传进来；
///   · 它把 stdout / stderr 读到内存才返回，于是也不存在「边跑边知道它说了什么」。
/// 这里改成「起进程 → 两路读线程（漏读会因 pipe 满把子进程憋死）→ 每 100ms 看一眼旗、
/// 顺手量一次体积并把新到的行记进读数槽」。
pub fn run_cancellable_with_progress(
    plan: &BackupPlan,
    password: Option<&str>,
    sslmode: Option<&str>,
    cancel: &CancelFlag,
    progress: &ProgressSink,
) -> Result<BackupReport, DbFailure> {
    let program = plan.program.clone().ok_or_else(|| DbFailure {
        message: "没有可用的 pg_dump 程序，备份没有开始".to_string(),
        hint: "先在「程序」一格填 pg_dump 的完整路径（自动查找的结果会显示在同一处）。".to_string(),
    })?;

    let mut envs: Vec<(String, String)> = Vec::new();
    if let Some(secret) = password.filter(|value| !value.is_empty()) {
        envs.push(("PGPASSWORD".to_string(), secret.to_string()));
    }
    if let Some(mode) = sslmode.filter(|value| !value.trim().is_empty()) {
        envs.push(("PGSSLMODE".to_string(), mode.trim().to_lowercase()));
    }

    let started = std::time::Instant::now();
    // 动手前的存在性：**取消 / 失败后只清我们自己造出来的东西**（见 `clear_partial`）
    let existed_before = plan.target.exists();
    let mut command = Command::new(&program);
    command
        .args(&plan.args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    for (key, value) in &envs {
        command.env(key, value);
    }
    let mut child = command.spawn().map_err(|err| DbFailure {
        message: format!("起不来 pg_dump：{err}"),
        hint: format!("确认 {} 能直接运行（杀毒软件拦截 / 权限不足都会这样报）。", program.display()),
    })?;
    // 读数槽从这一刻开始计时（「已跑 N 秒」是给用户看的，起点必须是真起进程那一刻）
    progress.start();

    // 两路读线程：**必须同时读**。子进程往满的 pipe 里写会阻塞 —— 只读 stdout 的话，
    // 一个话多的 `pg_dump`（stderr 上进度信息不少）会把两边都卡死。
    // 注：join 这两个线程的前提是**管子由子进程自己握着**（`pg_dump` 不起孙子进程）；若哪天改成
    // 经 shell 包一层，kill 只杀 shell，孙子进程仍握着管子 ⇒ 取消退化成「等它跑完」。
    let mut stdout_pipe = match child.stdout.take() {
        Some(pipe) => pipe,
        None => {
            return Err(DbFailure {
                message: "拿不到 pg_dump 的输出管道，备份没有开始".to_string(),
                hint: "这属实现缺陷：请保留现场并报告。".to_string(),
            })
        }
    };
    let stderr_pipe = match child.stderr.take() {
        Some(pipe) => pipe,
        None => {
            return Err(DbFailure {
                message: "拿不到 pg_dump 的错误输出管道，备份没有开始".to_string(),
                hint: "这属实现缺陷：请保留现场并报告。".to_string(),
            })
        }
    };
    let out_reader = std::thread::spawn(move || {
        let mut buffer = Vec::new();
        let _ = stdout_pipe.read_to_end(&mut buffer);
        buffer
    });
    // stderr **逐行读**（不是 `read_to_end` 一口气读到底）：进度读数的唯一来源就是它 ——
    // 等子进程跑完再读，进度就只能事后补一个动画，那不是进度。
    let line_sink = progress.clone();
    let err_reader = std::thread::spawn(move || {
        let mut buffer = Vec::new();
        let mut reader = std::io::BufReader::new(stderr_pipe);
        let mut chunk: Vec<u8> = Vec::new();
        loop {
            chunk.clear();
            match reader.read_until(b'\n', &mut chunk) {
                Ok(0) => break,
                Ok(_) => {
                    buffer.extend_from_slice(&chunk);
                    // 非 UTF-8（中文 Windows 的代码页）也要能记账：按有损解码 ——
                    // 中文乱成方块时，至少「行数在涨、体积在涨」这两个读数还是真的。
                    line_sink.note_line(&String::from_utf8_lossy(&chunk));
                }
                Err(_) => break,
            }
        }
        buffer
    });

    let mut cancelled = false;
    progress.note_bytes(produced_bytes(&plan.target, plan.format));
    let status = loop {
        if cancel.is_cancelled() {
            // 强杀（Windows 上是 TerminateProcess）：pg_dump 自己不会收尾，
            // 半截产物由下面的 `clear_partial` 收拾 —— 与失败路径同一条口径。
            let _ = child.kill();
            cancelled = true;
            break child.wait().ok();
        }
        match child.try_wait() {
            Ok(Some(status)) => break Some(status),
            Ok(None) => {
                std::thread::sleep(CANCEL_POLL);
                // 心跳：每 100ms 量一次目标体积。导一张大表可以十几分钟不吐一行，
                // 「体积在涨」就是它还活着、而且真的在往外写 —— 比任何百分比都可信。
                progress.note_bytes(produced_bytes(&plan.target, plan.format));
            }
            Err(err) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(DbFailure {
                    message: format!("等待 pg_dump 时出错：{err}（备份可能没跑完）"),
                    hint: "这属实现缺陷：请保留现场并报告。".to_string(),
                });
            }
        }
    };
    let elapsed_ms = started.elapsed().as_millis() as u64;

    let stdout = String::from_utf8_lossy(&out_reader.join().unwrap_or_default()).to_string();
    let stderr = String::from_utf8_lossy(&err_reader.join().unwrap_or_default()).to_string();
    let combined = match (stdout.trim().is_empty(), stderr.trim().is_empty()) {
        (true, true) => String::new(),
        (true, false) => stderr,
        (false, true) => stdout,
        (false, false) => format!("{stderr}\n{stdout}"),
    };
    let (log, trimmed) = tail_log(&combined, LOG_LIMIT);
    // 失败 / 取消回执要用第一行，而 `log` 会被移进回执 —— 先取出来，别在移动之后再借
    let headline = first_line(&log);

    // 取消的结局**与失败分开说**：它不是「备份出错了」，是「你叫停了，我们把它留下的东西清了」。
    if cancelled {
        let cleaned = clear_partial(&plan.target, plan.format, existed_before);
        let tail_note = if combined.trim().is_empty() {
            String::new()
        } else {
            format!("子进程最后说：{headline}。")
        };
        return Err(DbFailure {
            message: format!("备份已取消：你在第 {} ms 叫停了它，这次没有产出可用的备份", elapsed_ms),
            hint: format!(
                "{tail_note}{}",
                match cleaned {
                    Some(note) => format!("{note}。还想备份就再点一次「开始备份」。"),
                    None => "盘上没有留下半截产物。还想备份就再点一次「开始备份」。".to_string(),
                }
            ),
        });
    }

    let exit_code = status.as_ref().and_then(|status| status.code());
    let success = status.as_ref().map(|status| status.success()).unwrap_or(false);
    let bytes = produced_bytes(&plan.target, plan.format);
    let report = BackupReport {
        display: plan.display(),
        exit_code,
        log,
        log_trimmed_chars: trimmed,
        bytes,
        elapsed_ms,
        target: plan.target.display().to_string(),
        format: plan.format,
    };

    if success {
        return Ok(report);
    }
    // 失败：把子进程的原话端出去（**不加工成「备份失败」四个字**）
    let code = match exit_code {
        Some(code) => format!("退出码 {code}"),
        None => "进程被意外终止（没有退出码）".to_string(),
    };
    let hint = if combined.to_lowercase().contains("password")
        || combined.contains("口令")
        || combined.contains("authentication")
    {
        "口令被拒：核对连接里的用户名与口令（口令只进环境变量，不进命令行）。"
    } else if combined.contains("does not exist") || combined.contains("不存在") {
        "库名或路径不对：确认数据库名，以及目标路径的上级目录存在且可写。"
    } else {
        "看上面子进程的原话；日志尾部已带回，完整输出由 pg_dump 打印。"
    };
    Err(DbFailure {
        message: format!("pg_dump {code}：{headline}"),
        hint: match clear_partial(&plan.target, plan.format, existed_before) {
            Some(note) => format!("{hint}（{note}；本次耗时 {elapsed_ms} ms）"),
            None => format!("{hint}（本次耗时 {elapsed_ms} ms）"),
        },
    })
}

/// 失败后收拾**这次留下的半截产物**。
///
/// 这是本轮由真 `pg_dump` 判出来的一条真缺陷：`pg_dump -F c` **先建文件、再连服务器**，
/// 连不上时盘上会留一个 0 字节（或半截）的 `*.dump` —— 而备份最危险的情形正是
/// 「看起来有一份、其实是空的」。
///
/// 口径：**只删我们这次建的**（`existed_before == false` 且现在存在）—— 目标此前不存在是
/// `check_target` 的前提，所以删掉它等于精确回到动手前的状态；之前就存在的东西一个字节都不碰。
///
/// 返回值：`None` = 没有要收拾的；`Some(说明)` = 收拾掉了 / 没能收拾（都要如实说出去）。
fn clear_partial(target: &Path, format: BackupFormat, existed_before: bool) -> Option<String> {
    if existed_before || !target.exists() {
        return None;
    }
    let outcome = if format.produces_directory() {
        std::fs::remove_dir_all(target)
    } else {
        std::fs::remove_file(target)
    };
    Some(match outcome {
        Ok(()) => format!("已删掉这次留下的半截产物：{}", target.display()),
        Err(err) => format!(
            "这次留下了半截产物 {}（删不掉：{err}）—— 请自己删掉，别把它当可用备份",
            target.display()
        ),
    })
}

/// 失败回执里只带**第一行**（日志尾部整段在 `BackupReport.log`，别把两者搅在一起）。
fn first_line(text: &str) -> String {
    text.lines()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .unwrap_or("（子进程没有输出）")
        .to_string()
}

/// 产出的字节数：文件取长度，目录取其中各文件之和（读不出来算 0 —— 体积是附注，不是判据）。
fn produced_bytes(target: &Path, format: BackupFormat) -> u64 {
    if !format.produces_directory() {
        return std::fs::metadata(target).map(|meta| meta.len()).unwrap_or(0);
    }
    fn sum(dir: &Path) -> u64 {
        let Ok(entries) = std::fs::read_dir(dir) else {
            return 0;
        };
        entries
            .flatten()
            .map(|entry| {
                let path = entry.path();
                if path.is_dir() {
                    sum(&path)
                } else {
                    std::fs::metadata(&path).map(|meta| meta.len()).unwrap_or(0)
                }
            })
            .sum()
    }
    sum(target)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn target() -> BackupTarget {
        BackupTarget {
            host: "db.internal".to_string(),
            port: 5432,
            user: "doyah".to_string(),
            database: "shop".to_string(),
        }
    }

    /// 三档格式的旗标与「产出是文件还是目录」必须成对成立 —— 混淆这两件事会判错「目标已存在」。
    #[test]
    fn each_format_maps_to_one_pg_dump_flag() {
        assert_eq!(BackupFormat::Plain.pg_dump_flag(), "p");
        assert_eq!(BackupFormat::Custom.pg_dump_flag(), "c");
        assert_eq!(BackupFormat::Directory.pg_dump_flag(), "d");
        assert!(BackupFormat::Directory.produces_directory());
        assert!(!BackupFormat::Plain.produces_directory());
        assert!(!BackupFormat::Custom.produces_directory());
    }

    /// **口令不许进 argv**：参数表里只有「连哪儿 / 哪个库 / 什么格式 / 写到哪」+ `--verbose`。
    #[test]
    fn the_plan_never_carries_a_password_in_argv() {
        let args = plan_args(&target(), r"D:\backup\shop.dump", BackupFormat::Custom);
        assert_eq!(
            args.join(" "),
            r"-h db.internal -p 5432 -U doyah -d shop -F c -f D:\backup\shop.dump --verbose"
        );
        // `--verbose` 不是装饰：没有它 stderr 全程静默，进度读数就没有来源
        assert!(args.iter().any(|arg| arg == "--verbose"), "进度读数依赖 --verbose：{args:?}");
        let joined = args.join(" ");
        for forbidden in ["PGPASSWORD", "password", "secret="] {
            assert!(!joined.contains(forbidden), "argv 里出现了 {forbidden}");
        }
    }

    /// 展示的命令行：口令打码、带空格的路径加引号 —— 用户会照着它粘到终端里复现。
    #[test]
    fn the_display_command_masks_the_password_and_quotes_spaces() {
        let args = plan_args(&target(), r"C:\my backups\shop.dump", BackupFormat::Plain);
        let shown = display_command(r"C:\Program Files\PostgreSQL\18\bin\pg_dump.exe", &args, true);
        assert!(shown.starts_with("PGPASSWORD=*** "), "打码前缀缺失：{shown}");
        assert!(shown.contains(r#""C:\Program Files\PostgreSQL\18\bin\pg_dump.exe""#));
        assert!(shown.contains(r#""C:\my backups\shop.dump""#));
        assert!(!shown.contains("PGPASSWORD=abc"), "口令被写进了展示串：{shown}");
        // 不带打码前缀时（程序自己跑的时候）不许凭空多出一段
        let plain = display_command("pg_dump", &args, false);
        assert!(!plain.contains("PGPASSWORD"));
    }

    /// 空目标：拒绝并**说清楚该怎么填**（不是静默跑一次 `-f ""`）。
    #[test]
    fn an_empty_target_is_refused_before_anything_runs() {
        let err = check_target("   ", BackupFormat::Plain).expect_err("空路径应当被拒");
        assert!(err.message.contains("还没填"), "{}", err.message);
        assert!(err.hint.contains("路径"), "{}", err.hint);
    }

    /// 目录形式与文件形式的「已存在」是**两条不同的理由**（下一步动作不同）。
    #[test]
    fn an_existing_target_is_refused_with_reason_matching_the_format() {
        let dir = std::env::temp_dir().join(format!("doyah-backup-target-{}", std::process::id()));
        std::fs::create_dir_all(&dir).expect("建临时目录");

        let as_directory = check_target(&dir.display().to_string(), BackupFormat::Directory)
            .expect_err("目录形式遇到既有目录应当被拒");
        assert!(as_directory.message.contains("目标目录不存在"), "{}", as_directory.message);

        let file = dir.join("shop.dump");
        std::fs::write(&file, b"old").expect("写临时文件");
        let as_file = check_target(&file.display().to_string(), BackupFormat::Custom)
            .expect_err("文件形式遇到既有文件应当被拒");
        assert!(as_file.message.contains("不覆盖既有文件"), "{}", as_file.message);

        // 不存在的路径：放行，并**原样**返回（不做路径改写）
        let fresh = dir.join("new.dump");
        let target = check_target(&fresh.display().to_string(), BackupFormat::Custom).expect("新路径应当放行");
        assert_eq!(target, fresh);
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// 版本排序：`18 > 9`（按数字段比，不按字符串比 —— 字符串会把 9 排在 18 前面）。
    #[test]
    fn the_newest_installation_wins() {
        let candidates = vec![
            ("9.6".to_string(), PathBuf::from(r"C:\pg\9.6\bin\pg_dump.exe")),
            ("18".to_string(), PathBuf::from(r"C:\pg\18\bin\pg_dump.exe")),
            ("17.2".to_string(), PathBuf::from(r"C:\pg\17.2\bin\pg_dump.exe")),
        ];
        assert_eq!(
            best_candidate(&candidates),
            Some(PathBuf::from(r"C:\pg\18\bin\pg_dump.exe"))
        );
        // 认不出版本的排最后
        let odd = vec![
            ("nightly".to_string(), PathBuf::from("x")),
            ("16".to_string(), PathBuf::from("y")),
        ];
        assert_eq!(best_candidate(&odd), Some(PathBuf::from("y")));
        assert_eq!(best_candidate(&[]), None);
    }

    /// 显式指定一个不存在的程序：**点名那个路径并给出典型位置**（不是一句「找不到」）。
    #[test]
    fn a_missing_program_names_where_it_looked() {
        let err = find_program(Some(r"D:\nope\pg_dump.exe")).expect_err("不存在的路径应当报错");
        assert!(err.message.contains(r"D:\nope\pg_dump.exe"), "{}", err.message);
        assert!(err.hint.contains("pg_dump.exe"), "{}", err.hint);
        // 留空 ⇒ 走自动查找；本机装了客户端就该找得到，没装就该报「找过这些地方」
        match find_program(None) {
            Ok(path) => assert!(path.is_file(), "找到的路径必须是真文件：{}", path.display()),
            Err(msg) => assert!(msg.hint.contains("找过这些地方"), "{}", msg.hint),
        }
    }

    /// **真起一次子进程**：退出码、日志、耗时都要如实带回来（用 `cmd` 起，不依赖 PostgreSQL）。
    #[test]
    fn a_real_child_process_reports_exit_code_and_log() {
        let ok = run(
            &BackupPlan {
                program: Some(PathBuf::from(if cfg!(windows) { "cmd" } else { "sh" })),
                args: if cfg!(windows) {
                    vec!["/C".into(), "echo backup-ok".into()]
                } else {
                    vec!["-c".into(), "echo backup-ok".into()]
                },
                target: PathBuf::from("unused"),
                format: BackupFormat::Plain,
                database: "unused".to_string(),
            },
            None,
            None,
        )
        .expect("起子进程应当成功");
        assert_eq!(ok.exit_code, Some(0));
        assert!(ok.log.contains("backup-ok"), "日志里没有子进程的原话：{}", ok.log);

        let failed = run(
            &BackupPlan {
                program: Some(PathBuf::from(if cfg!(windows) { "cmd" } else { "sh" })),
                args: if cfg!(windows) {
                    vec!["/C".into(), "echo boom 1>&2 & exit 3".into()]
                } else {
                    vec!["-c".into(), "echo boom 1>&2; exit 3".into()]
                },
                target: PathBuf::from("unused"),
                format: BackupFormat::Plain,
                database: "unused".to_string(),
            },
            None,
            None,
        )
        .expect_err("非零退出必须是 Err");
        assert!(failed.message.contains("退出码 3"), "{}", failed.message);
        assert!(failed.message.contains("boom"), "{}", failed.message);
    }

    /// 没有程序就不许「跑」——回执必须说清没开始（不能产出一个空报告冒充成功）。
    #[test]
    fn a_plan_without_a_program_refuses_to_run() {
        let err = run(
            &BackupPlan {
                program: None,
                args: vec![],
                target: PathBuf::from("x"),
                format: BackupFormat::Plain,
                database: "shop".to_string(),
            },
            None,
            None,
        )
        .expect_err("没有程序应当拒绝");
        assert!(err.message.contains("没有开始"), "{}", err.message);
    }

    /// **半截产物只清我们自己造的那个**：动手前就存在的东西一个字节都不碰（备份失败时
    /// `pg_dump -F c` 会先建文件再连服务器，不清就留下一个 0 字节的「看起来有备份」）。
    #[test]
    fn a_failed_run_only_clears_what_this_run_created() {
        let dir = std::env::temp_dir().join(format!("doyah-backup-partial-{}", std::process::id()));
        std::fs::create_dir_all(&dir).expect("建临时目录");

        // ① 这次造的（此前不存在）⇒ 清掉并说明
        let ours = dir.join("ours.dump");
        std::fs::write(&ours, b"").expect("写半截文件");
        let note = clear_partial(&ours, BackupFormat::Custom, false).expect("应当有说明");
        assert!(note.contains("已删掉"), "{note}");
        assert!(!ours.exists(), "我们造的半截文件应当被删掉");

        // ② 动手前就存在的（`existed_before = true`）⇒ 一个字节都不碰
        let older = dir.join("older.dump");
        std::fs::write(&older, b"real backup").expect("写旧备份");
        assert!(clear_partial(&older, BackupFormat::Custom, true).is_none());
        assert_eq!(std::fs::read(&older).expect("旧备份还在"), b"real backup");

        // ③ 什么都没造出来 ⇒ 没有可收拾的
        assert!(clear_partial(&dir.join("never.dump"), BackupFormat::Plain, false).is_none());

        let _ = std::fs::remove_dir_all(&dir);
    }

    /// 日志截尾：留**尾部**，并如实报被砍掉多少（前面才是「开始备份」那几行）。
    #[test]
    fn the_log_keeps_the_tail_and_says_how_much_was_cut() {
        let text: String = (0..100).map(|i| format!("line-{i}\n")).collect();
        let (tail, cut) = tail_log(&text, 40);
        assert_eq!(tail.chars().count(), 40);
        assert_eq!(cut, text.chars().count() - 40);
        assert!(tail.ends_with("line-99\n"), "尾部不含最后一行：{tail}");

        let (whole, none) = tail_log("short", 40);
        assert_eq!(whole, "short");
        assert_eq!(none, 0);
    }

    /// 取消旗：一开始是没取消，置位之后一直是取消（可重复置位）。
    #[test]
    fn the_cancel_flag_starts_clear_and_stays_set() {
        let flag = CancelFlag::new();
        assert!(!flag.is_cancelled());
        flag.cancel();
        assert!(flag.is_cancelled());
        flag.cancel();
        assert!(flag.is_cancelled());
        // 克隆共享同一面旗（外壳装进槽里、界面按下去，必须是同一面）
        let clone = flag.clone();
        clone.cancel();
        assert!(flag.is_cancelled());
    }

    /// **取消真的能停下子进程**，并且**它留下的半截产物被清掉**。
    ///
    /// 两条断言缺一不可：只断言「回执说已取消」会放过「取消只回了一句好话、进程还在跑」；
    /// 只断言「进程停了」会放过「强杀留下的 0 字节文件被当备份」。`pg_dump -F c` 正是
    /// **先建文件、再连服务器**，所以「取消 ⇒ 删掉这次建的」与失败路径是同一条数据安全口径。
    #[test]
    fn a_cancel_stops_a_long_child_and_clears_what_it_left() {
        let dir = std::env::temp_dir().join(format!("doyah-backup-cancel-{}", std::process::id()));
        std::fs::create_dir_all(&dir).expect("建临时目录");
        let target = dir.join("half.dump");
        // 起一个约 10 秒的子进程（不依赖 PostgreSQL）。**必须是直接子进程**，不许经 `cmd /C` 包一层：
        // 那样子进程是孙进程，kill 只杀 cmd，孙进程还握着管子 ⇒ 读线程要等它自己跑完（9 秒），
        // 「取消」就变成了「等到结束」—— 这条踩过，判据当场红。
        let plan = BackupPlan {
            program: Some(PathBuf::from(if cfg!(windows) { "ping" } else { "sleep" })),
            args: if cfg!(windows) {
                vec!["-n".into(), "10".into(), "127.0.0.1".into()]
            } else {
                vec!["10".into()]
            },
            target: target.clone(),
            format: BackupFormat::Custom,
            database: "shop".to_string(),
        };

        let cancel = CancelFlag::new();
        let flag = cancel.clone();
        let made = target.clone();
        // 复刻 `pg_dump` 的时序：进程起来之后先把目标文件建出来
        let maker = std::thread::spawn(move || {
            std::thread::sleep(std::time::Duration::from_millis(200));
            let _ = std::fs::write(&made, b"");
        });
        let stopper = std::thread::spawn(move || {
            std::thread::sleep(std::time::Duration::from_millis(600));
            flag.cancel();
        });

        let started = std::time::Instant::now();
        let err = run_cancellable(&plan, None, None, &cancel)
            .expect_err("取消必须是 Err —— 不许交出一份看起来成功的回执");
        let elapsed = started.elapsed();
        maker.join().expect("造半截文件的线程");
        stopper.join().expect("置位线程");

        assert!(err.message.contains("已取消"), "{}", err.message);
        assert!(
            elapsed < std::time::Duration::from_secs(5),
            "取消了却还在等子进程跑完：{elapsed:?}"
        );
        assert!(!target.exists(), "取消后不许留下半截产物：{}", target.display());

        let _ = std::fs::remove_dir_all(&dir);
    }

    /// 读数记账：行数与最近一行（**空行不算一行**，最后一行是最后到的）。
    #[test]
    fn the_sink_counts_lines_and_keeps_the_last_one() {
        let sink = ProgressSink::new();
        let blank = sink.snapshot();
        assert_eq!(blank.lines, 0);
        assert_eq!(blank.bytes, 0);
        assert_eq!(blank.elapsed_ms, 0, "还没开跑就报「跑了多久」是编的");
        assert!(blank.last_line.is_none());

        sink.note_line("pg_dump: reading schemas\r\n");
        sink.note_line("   \r\n");
        sink.note_line("pg_dump: dumping contents of table \"public.orders\"\n");
        let snap = sink.snapshot();
        assert_eq!(snap.lines, 2, "空行不该算一行");
        assert_eq!(
            snap.last_line.as_deref(),
            Some("pg_dump: dumping contents of table \"public.orders\""),
            "最近一行必须原样留着（界面照它显示）"
        );

        // 体积只进不退：目标被删掉（读回 0）不把界面的读数拉回去
        sink.note_bytes(4096);
        sink.note_bytes(0);
        assert_eq!(sink.snapshot().bytes, 4096);
    }

    /// **跑着就能看见**：真起一个「先说一句、停一会儿、再说一句」的子进程 ——
    /// 第一行必须在它退出**之前**就进读数槽。否则进度只在结束时出现一次，等于没有进度。
    #[test]
    fn progress_lines_arrive_while_the_child_is_still_running() {
        let plan = BackupPlan {
            program: Some(PathBuf::from(if cfg!(windows) { "cmd" } else { "sh" })),
            args: if cfg!(windows) {
                vec![
                    "/C".to_string(),
                    "echo first 1>&2 & ping -n 3 127.0.0.1 >nul & echo second 1>&2".to_string(),
                ]
            } else {
                vec!["-c".to_string(), "echo first >&2; sleep 2; echo second >&2".to_string()]
            },
            target: PathBuf::from("unused"),
            format: BackupFormat::Plain,
            database: "shop".to_string(),
        };

        let sink = ProgressSink::new();
        let probe = sink.clone();
        let stop = Arc::new(AtomicBool::new(false));
        let stop_probe = stop.clone();
        // 采样线程：每 20ms 看一眼读数，记下「第一次看到行」离开始多久
        let sampler = std::thread::spawn(move || {
            let start = std::time::Instant::now();
            let mut first_line_at: Option<std::time::Duration> = None;
            while !stop_probe.load(Ordering::SeqCst) {
                if first_line_at.is_none() && probe.snapshot().lines > 0 {
                    first_line_at = Some(start.elapsed());
                }
                std::thread::sleep(std::time::Duration::from_millis(20));
            }
            first_line_at
        });

        let started = std::time::Instant::now();
        run_cancellable_with_progress(&plan, None, None, &CancelFlag::new(), &sink)
            .expect("真起子进程应当成功");
        let total = started.elapsed();
        stop.store(true, Ordering::SeqCst);
        let first_line_at = sampler.join().expect("采样线程");

        let snap = sink.snapshot();
        assert_eq!(snap.lines, 2, "两行都要记账（最近一行 {:?}）", snap.last_line);
        assert_eq!(snap.last_line.as_deref(), Some("second"));
        assert!(
            total >= std::time::Duration::from_millis(1200),
            "子进程太短，这条判据没意义：{total:?}"
        );
        let first = first_line_at.expect("整个过程一次都没看到行 ⇒ 进度只会在结束时出现");
        assert!(
            first < total,
            "第一行到得太晚（{first:?} / 总 {total:?}）—— 它不是边跑边到"
        );
    }

    /// 心跳量得到体积：导一张大表能十几分钟不吐一行，「已写多少」靠的就是这条。
    #[test]
    fn the_heartbeat_reports_bytes_while_the_child_runs() {
        let dir = std::env::temp_dir().join(format!("doyah-backup-heartbeat-{}", std::process::id()));
        std::fs::create_dir_all(&dir).expect("建临时目录");
        let target = dir.join("growing.dump");
        let plan = BackupPlan {
            program: Some(PathBuf::from(if cfg!(windows) { "ping" } else { "sleep" })),
            args: if cfg!(windows) {
                vec!["-n".to_string(), "3".to_string(), "127.0.0.1".to_string()]
            } else {
                vec!["2".to_string()]
            },
            target: target.clone(),
            format: BackupFormat::Custom,
            database: "shop".to_string(),
        };

        let sink = ProgressSink::new();
        let growing = target.clone();
        // 复刻 `pg_dump` 的行为：边跑边往目标里写（这里每 200ms 追加 512 字节）
        let writer = std::thread::spawn(move || {
            for _ in 0..4 {
                std::thread::sleep(std::time::Duration::from_millis(200));
                let mut file = std::fs::OpenOptions::new()
                    .create(true)
                    .append(true)
                    .open(&growing)
                    .expect("打开目标文件");
                let _ = std::io::Write::write_all(&mut file, &[b'x'; 512]);
            }
        });

        run_cancellable_with_progress(&plan, None, None, &CancelFlag::new(), &sink)
            .expect("子进程应当成功");
        writer.join().expect("写线程");

        let snap = sink.snapshot();
        assert!(snap.bytes >= 1024, "心跳没把体积记进读数：{}", snap.bytes);
        assert!(snap.elapsed_ms >= 1000, "耗时没记进读数：{}", snap.elapsed_ms);

        let _ = std::fs::remove_dir_all(&dir);
    }
}
