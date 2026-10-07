//! 内置终端的 PTY 层 —— Windows 侧（W-C 底部终端 · 段 2.7 · 第一片 `S-9a`）。
//!
//! ## 为什么全部 PTY 代码只在这一个文件里
//!
//! 前门裁决 `T-20261007-031` 定的是「**用成熟 crate 起真交互式 shell**」这条路，本片把
//! 它落成**单一隔离开关**：`portable_pty` 这个 crate 名**只许在本文件出现**，其余文件
//! （含 `lib.rs` 的命令层）只许经 `pty::` 的四个接口调用。理由有二：
//!
//! 1. **可整体替换**：PTY 是平台相关面里最容易换实现的一段（本侧此前手写
//!    `CreatePseudoConsole` / `STARTUPINFOEXW` 四轮实测未通，已整段回退）。把实现收在一处，
//!    换库 = 换这一个文件，命令层与前端一行不动；
//! 2. **判据判得了**：`Tools/check-platform-parity.ps1` 第五道「PTY 隔离」按文本判这条 ——
//!    crate 名跑到别的文件里就判红并点名 `文件:行号`。
//!
//! 本文件**严禁**再手写 `CreatePseudoConsole` / `STARTUPINFOEXW` 那一套（那是已回退的死路）。
//!
//! ## 三个语义（对上层承诺）
//!
//! - **起真 shell**：`open()` 起的是系统上真的 shell（默认 `%COMSPEC%`），不是模拟器；
//! - **退出可见**：子进程结束 / 会话关闭 ⇒ 读端拿到 `eof = true` 与退出码，**绝不挂住**；
//! - **失败可见**：起不来一律返回**带可读信息的** `Err`（不 `let _ = …` 吞掉，不拿空会话冒充成功）。
//!
//! ## 一处实测记下的坑（给 `S-9b` 接界面时看）
//!
//! Windows 伪控制台在会话起来后会先发一条**光标位置查询** `ESC[6n`，并**等终端回话**
//! `ESC[<行>;<列>R`，不回话会话就一个字都不往外吐（实测只有 `ESC[6n` 与模式序列，
//! 子进程的 `echo` 完全读不到 —— 本侧此前自写伪控制台四轮踩的正是这个现象）。
//! 回话是**终端仿真器**的职责（真终端 xterm.js 自动回），所以本层**不替终端回话**：
//! 集成测试里由测试自己扮终端回一次（见 `tests/pty_shell.rs` 的 `read_as_terminal`），
//! 产品里由前端的终端组件回。**`S-9b` 接界面时，读到的字节要原样喂给终端组件，别在中间丢掉它。**

use std::collections::HashMap;
use std::io::{Read, Write};
use std::sync::atomic::{AtomicBool, AtomicI32, AtomicU64, Ordering};
use std::sync::mpsc::{channel, Receiver, RecvTimeoutError, Sender};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use portable_pty::{native_pty_system, Child, CommandBuilder, MasterPty, PtySize};

/// 一次读的返回：这一窗口内读到的数据 + 是否已到读端尽头 + 退出码（拿到才给）。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PtyChunk {
    /// 本窗口读到的输出（非 UTF-8 字节按替换字符兜底，不丢整段）。
    pub data: String,
    /// 读端是否已到尽头（子进程结束 / 会话关闭）。
    pub eof: bool,
    /// 子进程退出码；`eof` 为真且收得到时才有值。
    pub exit_code: Option<i32>,
}

/// 读线程 → 命令层的事件。**先 `Data` 后 `Eof`**（同一通道，顺序即真实顺序）。
enum ReadEvent {
    Data(Vec<u8>),
    Eof,
}

struct Session {
    /// pty 主端。用 `Option` 是为了**能主动放掉**它 —— 子进程退出后若读端迟迟不见 EOF，
    /// 放掉主端即关掉伪控制台，读端立刻见 EOF（见 `spawn_monitor`）。
    master: Mutex<Option<Box<dyn MasterPty + Send>>>,
    writer: Mutex<Box<dyn Write + Send>>,
    /// 子进程句柄（监控线程取走后为 `None`）。
    child: Mutex<Option<Box<dyn Child + Send + Sync>>>,
    rx: Mutex<Receiver<ReadEvent>>,
    eof: AtomicBool,
    exit_code: AtomicI32,
    has_exit: AtomicBool,
    /// 读线程是否已收工（读到 0 或读端断开）。
    reader_done: Arc<AtomicBool>,
}

static SESSIONS: OnceLock<Mutex<HashMap<u64, Arc<Session>>>> = OnceLock::new();
static NEXT_ID: AtomicU64 = AtomicU64::new(1);

fn registry() -> &'static Mutex<HashMap<u64, Arc<Session>>> {
    SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn lock_err(what: &str) -> String {
    format!("{what}失败：终端内部锁已损坏（此前有一次操作 panic）")
}

fn session_of(id: u64) -> Result<Arc<Session>, String> {
    let map = registry()
        .lock()
        .map_err(|_| format!("终端会话 {id}：{}", lock_err("查找")))?;
    map.get(&id)
        .cloned()
        .ok_or_else(|| format!("终端会话 {id} 不存在（可能已经关闭）"))
}

/// 默认 shell：Windows 是 `%COMSPEC%`（通常是 `cmd.exe`）。
pub fn default_shell() -> String {
    std::env::var("COMSPEC").unwrap_or_else(|_| "cmd.exe".to_string())
}

/// 起一个真交互式会话，返回会话 id。
///
/// `args` 为空即起交互式 shell；给了 `args`（如 `["/c", "echo", "x"]`）就跑一次性命令。
/// 起不来一律 `Err`（错误串里带**程序名与底层原因**，便于定位）。
pub fn open(
    program: &str,
    args: &[String],
    cwd: Option<&str>,
    cols: u16,
    rows: u16,
) -> Result<u64, String> {
    let program = program.trim();
    if program.is_empty() {
        return Err("起 shell 失败：程序名为空".to_string());
    }

    let pty_system = native_pty_system();
    let pair = pty_system
        .openpty(PtySize {
            rows,
            cols,
            pixel_width: 0,
            pixel_height: 0,
        })
        .map_err(|e| format!("起 shell 失败：{program} 打不开伪控制台（{e}）"))?;

    let mut cmd = CommandBuilder::new(program);
    for a in args {
        cmd.arg(a);
    }
    if let Some(dir) = cwd {
        cmd.cwd(dir);
    }
    // 终端程序（vim / less / 颜色输出）靠 TERM 认终端类型；不给就按 dumb 走，按键与配色都会退。
    cmd.env("TERM", "xterm-256color");

    let child = pair
        .slave
        .spawn_command(cmd)
        .map_err(|e| format!("起 shell 失败：{program} 进程起不来（{e}）"))?;
    // spawn 之后**必须放掉从端**：留着它，子进程退出后 pty 也不会关，读端就永远等不到 EOF。
    drop(pair.slave);

    let reader = pair
        .master
        .try_clone_reader()
        .map_err(|e| format!("起 shell 失败：{program} 的读端拿不到（{e}）"))?;
    let writer = pair
        .master
        .take_writer()
        .map_err(|e| format!("起 shell 失败：{program} 的写端拿不到（{e}）"))?;

    let (tx, rx) = channel::<ReadEvent>();
    let id = NEXT_ID.fetch_add(1, Ordering::SeqCst);
    let session = Arc::new(Session {
        master: Mutex::new(Some(pair.master)),
        writer: Mutex::new(writer),
        child: Mutex::new(Some(child)),
        rx: Mutex::new(rx),
        eof: AtomicBool::new(false),
        exit_code: AtomicI32::new(-1),
        has_exit: AtomicBool::new(false),
        reader_done: Arc::new(AtomicBool::new(false)),
    });

    // 先起两条线程再登记：任一条起不来就整段放弃（不把半成品会话留给上层）。
    if let Err(e) = spawn_reader(id, reader, tx.clone(), session.reader_done.clone()) {
        teardown(&session, &tx);
        return Err(e);
    }
    if let Err(e) = spawn_monitor(id, tx.clone(), session.clone()) {
        teardown(&session, &tx);
        return Err(e);
    }

    registry()
        .lock()
        .map_err(|_| lock_err("登记会话"))?
        .insert(id, session);
    Ok(id)
}

/// 往会话写（用户按键 / 粘贴）。写不进去 = `Err`，不吞。
pub fn write(id: u64, data: &str) -> Result<(), String> {
    let session = session_of(id)?;
    let mut w = session.writer.lock().map_err(|_| lock_err("写终端"))?;
    w.write_all(data.as_bytes())
        .map_err(|e| format!("写终端失败（会话 {id}）：{e}"))?;
    w.flush().map_err(|e| format!("写终端失败（会话 {id}）：{e}"))
}

/// 读一个窗口（最多等 `timeout_ms`），返回数据 + 是否结束 + 退出码。
///
/// 读到一截后若短暂安静即返回（界面要能边跑边显示）；`timeout_ms = 0` 即只取当前可读部分。
pub fn read(id: u64, timeout_ms: u64) -> Result<PtyChunk, String> {
    let session = session_of(id)?;
    let deadline = Instant::now() + Duration::from_millis(timeout_ms);
    let mut data = String::new();
    let mut eof = session.eof.load(Ordering::SeqCst);

    {
        let rx = session.rx.lock().map_err(|_| lock_err("读终端"))?;
        while !eof {
            let now = Instant::now();
            if now >= deadline {
                break;
            }
            let slice = (deadline - now).min(Duration::from_millis(60));
            match rx.recv_timeout(slice) {
                Ok(ReadEvent::Data(bytes)) => data.push_str(&String::from_utf8_lossy(&bytes)),
                Ok(ReadEvent::Eof) => eof = true,
                Err(RecvTimeoutError::Timeout) => {
                    // 已经拿到一截、又安静了片刻 ⇒ 先交给调用方
                    if !data.is_empty() {
                        break;
                    }
                }
                Err(RecvTimeoutError::Disconnected) => eof = true,
            }
        }
    }

    if eof {
        session.eof.store(true, Ordering::SeqCst);
    }
    let exit_code = if eof {
        wait_exit_code(&session, Duration::from_millis(1500))
    } else {
        None
    };

    Ok(PtyChunk {
        data,
        eof,
        exit_code,
    })
}

/// 关闭会话：结束子进程（若还在跑）、放掉 pty、让两条线程收工。会话不存在 = `Err`。
pub fn close(id: u64) -> Result<(), String> {
    let session = {
        let mut map = registry().lock().map_err(|_| lock_err("关闭终端"))?;
        map.remove(&id)
            .ok_or_else(|| format!("关闭终端失败：会话 {id} 不存在（可能已经关闭）"))?
    };

    if let Ok(mut guard) = session.child.lock() {
        if let Some(mut child) = guard.take() {
            if child.kill().is_err() {
                // 进程可能刚好自己退出了 —— 不是错误。
            }
        }
    }
    // 放掉 pty 主端 ⇒ 读端立刻见 EOF，监控线程与读线程收工，不留挂着的线程。
    if let Ok(mut guard) = session.master.lock() {
        guard.take();
    }
    session.eof.store(true, Ordering::SeqCst);
    if !wait_reader_done(&session.reader_done, Duration::from_millis(1000)) {
        // 读线程会随 pty 关闭自行收工；这里只是不让 `close` 卡住。
    }
    Ok(())
}

/// 丢弃一个没登记成功的半成品会话（线程起不来时的清理路径）。
fn teardown(session: &Arc<Session>, tx: &Sender<ReadEvent>) {
    if let Ok(mut guard) = session.child.lock() {
        if let Some(mut child) = guard.take() {
            if child.kill().is_err() {
                // 已经死了就算了。
            }
        }
    }
    if let Ok(mut guard) = session.master.lock() {
        guard.take();
    }
    session.eof.store(true, Ordering::SeqCst);
    if tx.send(ReadEvent::Eof).is_err() {
        // 读线程已收工。
    }
}

fn spawn_reader(
    id: u64,
    mut reader: Box<dyn Read + Send>,
    tx: Sender<ReadEvent>,
    done: Arc<AtomicBool>,
) -> Result<(), String> {
    std::thread::Builder::new()
        .name(format!("pty-reader-{id}"))
        .spawn(move || {
            let mut buf = [0u8; 8192];
            loop {
                match reader.read(&mut buf) {
                    // 读到 0 = 对端关上了（子进程退出 / 伪控制台关闭）。
                    Ok(0) => break,
                    Ok(n) => {
                        if tx.send(ReadEvent::Data(buf[..n].to_vec())).is_err() {
                            break; // 会话已关，没人再读了。
                        }
                    }
                    // 读端断开与 EOF 同义。
                    Err(_) => break,
                }
            }
            done.store(true, Ordering::SeqCst);
            if tx.send(ReadEvent::Eof).is_err() {
                // 接收端已走（会话已关）—— 正常收场。
            }
        })
        .map(|_| ())
        .map_err(|e| format!("起 shell 失败：读线程起不来（{e}）"))
}

/// 监控线程：等子进程结束 → 记退出码 → 保证读端一定收到结束信号（**绝不挂住**）。
///
/// 为什么要有它：ConPTY 的收尾时机不归我们管 —— 子进程退出后，读端未必立刻拿到 EOF。
/// 这里做三段兜底：先给读端自然收尾的时间；不行就**主动放掉 pty 主端**（关掉伪控制台，
/// 读端必然见 EOF）；再不行就把结束信号直接发给上层。
fn spawn_monitor(id: u64, tx: Sender<ReadEvent>, session: Arc<Session>) -> Result<(), String> {
    std::thread::Builder::new()
        .name(format!("pty-monitor-{id}"))
        .spawn(move || {
            // ① 等子进程结束（交互式 shell 会一直等下去 —— 那是对的）。
            let waited = match session.child.lock() {
                Ok(mut guard) => guard.take(),
                Err(_) => None,
            };
            if let Some(mut child) = waited {
                if let Ok(status) = child.wait() {
                    session.exit_code.store(status.exit_code() as i32, Ordering::SeqCst);
                    session.has_exit.store(true, Ordering::SeqCst);
                }
            }

            // ② 给读端自然见 EOF 的时间。
            if wait_reader_done(&session.reader_done, Duration::from_millis(2000)) {
                return;
            }

            // ③ 还没收工 ⇒ 放掉伪控制台，读端必然见 EOF（配置了 ConPTY 的收尾惰性）。
            if let Ok(mut guard) = session.master.lock() {
                guard.take();
            }
            if wait_reader_done(&session.reader_done, Duration::from_millis(2000)) {
                return;
            }

            // ④ 兜底：读线程卡死也把结束信号给出去，绝不让上层挂住。
            session.eof.store(true, Ordering::SeqCst);
            if tx.send(ReadEvent::Eof).is_err() {
                // 会话已关。
            }
        })
        .map(|_| ())
        .map_err(|e| format!("起 shell 失败：监控线程起不来（{e}）"))
}

fn wait_reader_done(done: &AtomicBool, budget: Duration) -> bool {
    let deadline = Instant::now() + budget;
    while Instant::now() < deadline {
        if done.load(Ordering::SeqCst) {
            return true;
        }
        std::thread::sleep(Duration::from_millis(20));
    }
    done.load(Ordering::SeqCst)
}

fn wait_exit_code(session: &Session, budget: Duration) -> Option<i32> {
    let deadline = Instant::now() + budget;
    loop {
        if session.has_exit.load(Ordering::SeqCst) {
            return Some(session.exit_code.load(Ordering::SeqCst));
        }
        if Instant::now() >= deadline {
            return None;
        }
        std::thread::sleep(Duration::from_millis(20));
    }
}
