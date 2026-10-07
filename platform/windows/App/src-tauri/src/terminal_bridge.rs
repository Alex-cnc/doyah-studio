//! 底部终端「端到端接线」层：把真 PTY 的字节流**经领域层屏幕模型**跑通
//! （W-C 底部终端 · 第三片 `S-9c`）。
//!
//! ## 这一片补的缺口
//!
//! `Db/src/terminal*.rs` 已有 29 例（屏幕模型 11 / 按键编码 7 / 页签会话 11），但它们是**孤立单测** ——
//! `lib.rs` 的四条 `terminal_*` 命令此前只经 `pty.rs` 搬裸字节，那 29 例**没有被真字节流驱动**。
//! 本模块把这一环接上：
//!
//! - 每个会话持一份 `TerminalScreen`（尺寸 = `open` 的 cols×rows）：`read` 到的字节 `feed` 进屏幕
//!   ⇒ 屏幕模型由**真 shell 的输出**驱动；
//! - 一份 `TerminalTabs`（会话 id ↔ 页签 id）：子进程结束 / 会话关闭时 `mark_exited`
//!   ⇒ 退出态由**真退出码**驱动；
//! - 读回的投影带 `pending_responses`（`ESC[6n` 之类的设备查询应答）：本片只当**投影与断言**用，
//!   **不写回 PTY** —— 回话仍归前端（避免与前端 `cursorReport` 双回话；搬迁登记为下一片 `S-9d`）。
//!
//! ## 一条边界（判据在 `Tools/check-platform-parity.ps1` 第五道「PTY 隔离」）
//!
//! **PTY 代码只在本 crate 的 `pty.rs`**：本模块只经 `pty::` 接口调用，**不许出现 PTY crate 名**。
//! 对领域层**只读不写**：只用 `Db` 的既有公开面（`Screen` / `Tabs`），不改其行为与既有断言。

use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

use doyah_studio_db::{SessionState, TerminalScreen, TerminalTabs};

use crate::pty;

/// 一次 `read` 的返回：**裸字节原样保留**（前端仍靠它渲染）+ 领域层屏幕投影（新增字段，只增不减）。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TerminalChunk {
    /// PTY 本窗口读到的原始字节（解码后原样，**一字不动、不截断** —— 前端仍靠它渲染）。
    pub data: String,
    /// 读端是否已到尽头（子进程结束 / 会话关闭）。
    pub eof: bool,
    /// 子进程退出码；`eof` 为真且收得到时才有值。
    pub exit_code: Option<i32>,
    /// 领域层屏幕模型（`Db::terminal::Screen`）的投影。
    pub screen: ScreenProjection,
}

/// 光标位置（0 起，与领域层同口径）。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Cursor {
    pub row: usize,
    pub col: usize,
}

/// 领域层屏幕模型的投影：前端薄壳化（`S-9d`）后只渲染它。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ScreenProjection {
    /// 网格每行的可显示文本（宽字符右半格跳过）。
    pub rows: Vec<String>,
    /// 整屏文本（各行以 `\n` 相连）—— 核心判据断言的就是它。
    pub text: String,
    pub cursor: Cursor,
    pub cursor_visible: bool,
    /// 设备查询应答（如 `ESC[6n` 的 `ESC[1;1R`）—— 本片只投影，不写回 PTY。
    pub pending_responses: Vec<String>,
    pub eof: bool,
    pub exit_code: Option<i32>,
}

/// 一个会话的页签信息（会话 id ↔ 页签 id 与退出态）。
///
/// 标题沿用领域层口径（**用户重命名 > 前台进程名 > `None`**）；本片不接前台进程名
/// （要 shell integration / OSC 7-9，属后续片），故这里通常是 `None`，兜底词由界面出。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionInfo {
    pub session_id: u64,
    pub tab_id: u64,
    pub title: Option<String>,
    pub state: SessionState,
    pub running: bool,
}

/// 一个会话在桥接层的状态：领域层屏幕（可跨线程共享，读时不占全局锁）+ 对应页签 id。
struct Bridged {
    screen: Arc<Mutex<TerminalScreen>>,
    /// 该会话对应的页签 id（页签集合见 `Bridge.tabs`）。
    tab_id: u64,
}

/// 桥接层全局状态：会话表 + 一份页签集合（会话 id ↔ 页签）。
struct Bridge {
    sessions: HashMap<u64, Bridged>,
    /// 页签集合懒建（首次 `open` 时按程序名建），此后 `new_tab` 追加。
    tabs: Option<TerminalTabs>,
}

static BRIDGE: OnceLock<Mutex<Bridge>> = OnceLock::new();

fn bridge() -> &'static Mutex<Bridge> {
    BRIDGE.get_or_init(|| {
        Mutex::new(Bridge {
            sessions: HashMap::new(),
            tabs: None,
        })
    })
}

fn lock_err(what: &str) -> String {
    format!("{what}失败：终端桥接内部锁已损坏（此前有一次操作 panic）")
}

/// 起一个真交互式终端会话，同时建好领域层屏幕与页签；返回会话 id。
///
/// 起不来一律 `Err`（经 `pty::open` 的真实错误，不拿空会话冒充成功）。
pub fn open(
    program: &str,
    args: &[String],
    cwd: Option<&str>,
    cols: u16,
    rows: u16,
) -> Result<u64, String> {
    let id = pty::open(program, args, cwd, cols, rows)?;
    let screen = Arc::new(Mutex::new(TerminalScreen::new(cols as usize, rows as usize)));

    let mut guard = bridge().lock().map_err(|_| lock_err("登记会话"))?;
    let fresh = guard.tabs.is_none();
    if fresh {
        // 首次：领域层 `Tabs::new` 自带一个页签（终端没有「零个页签」这一态），
        // 直接把它当作本会话的页签，不另起一个空壳。
        guard.tabs = Some(TerminalTabs::new(program));
    }
    let tabs = guard
        .tabs
        .as_mut()
        .ok_or_else(|| "登记会话失败：页签集合建不起来".to_string())?;
    let tab_id = if fresh {
        tabs.selected
            .or_else(|| tabs.tabs.first().map(|tab| tab.id))
            .ok_or_else(|| "登记会话失败：新页签集合里没有页签".to_string())?
    } else {
        tabs.new_tab(Some(program))
    };

    guard.sessions.insert(id, Bridged { screen, tab_id });
    Ok(id)
}

/// 往会话写（用户按键 / 粘贴的**已编码字节**）。
///
/// 界面侧（`S-9b` 的 `keyToBytes`）已把按键翻成字节，本片不动前端，故这里**原样转交** `pty::write`。
/// 领域层的按键编码（`terminal_input`）由集成判据以**真按键字节流**驱动
/// （见 `tests/terminal_bridge_e2e.rs` 的按键用例），前端薄壳化（`S-9d`）时再统一由此出字节。
pub fn write(id: u64, data: &str) -> Result<(), String> {
    pty::write(id, data)
}

/// 读一个窗口（最多等 `timeout_ms`）：把真字节喂进领域层屏幕模型，返回裸字节 + 屏幕投影。
pub fn read(id: u64, timeout_ms: u64) -> Result<TerminalChunk, String> {
    // 先在锁内取出屏幕与页签 id，**放锁后再阻塞读**（一条慢读不堵别的会话）。
    let (screen, tab_id) = {
        let guard = bridge().lock().map_err(|_| lock_err("读终端"))?;
        let bridged = guard
            .sessions
            .get(&id)
            .ok_or_else(|| format!("终端会话 {id} 不存在（可能已经关闭）"))?;
        (bridged.screen.clone(), bridged.tab_id)
    };

    let chunk = pty::read(id, timeout_ms)?;

    // ── 接线本体：真 shell 的字节喂进领域层屏幕模型 ──
    feed_into_screen(&screen, chunk.data.as_bytes())?;

    // 退出可见：子进程结束 / 会话关闭 ⇒ 页签落退出态（既有语义，返回值 false = 页签不在，不当作错误）。
    if chunk.eof {
        let mut guard = bridge().lock().map_err(|_| lock_err("标记退出"))?;
        if let Some(tabs) = guard.tabs.as_mut() {
            tabs.mark_exited(tab_id, chunk.exit_code);
        }
    }

    let screen_projection = {
        let guard = screen.lock().map_err(|_| lock_err("读屏幕投影"))?;
        project(&guard, chunk.eof, chunk.exit_code)
    };

    Ok(TerminalChunk {
        data: chunk.data,
        eof: chunk.eof,
        exit_code: chunk.exit_code,
        screen: screen_projection,
    })
}

/// 关闭会话：关掉 PTY 会话，注销桥接状态并关闭对应页签。
///
/// PTY 侧会话不存在即 `Err`（不吞）；页签侧关掉最后一个时领域层返回 `false`
/// （终端没有「零个页签」这一态 —— **既有语义**，不是错误，故不当作失败）。
pub fn close(id: u64) -> Result<(), String> {
    pty::close(id)?;
    let mut guard = bridge().lock().map_err(|_| lock_err("注销会话"))?;
    if let Some(bridged) = guard.sessions.remove(&id) {
        if let Some(tabs) = guard.tabs.as_mut() {
            tabs.close(bridged.tab_id);
        }
    }
    Ok(())
}

/// 取一个会话的页签信息（会话 id ↔ 页签 id 与退出态）。会话不在 = `Err`。
pub fn session_info(id: u64) -> Result<SessionInfo, String> {
    let guard = bridge().lock().map_err(|_| lock_err("查会话"))?;
    let bridged = guard
        .sessions
        .get(&id)
        .ok_or_else(|| format!("终端会话 {id} 不存在（可能已经关闭）"))?;
    let tabs = guard
        .tabs
        .as_ref()
        .ok_or_else(|| format!("终端会话 {id}：页签集合缺失"))?;
    let tab = tabs
        .tabs
        .iter()
        .find(|tab| tab.id == bridged.tab_id)
        .ok_or_else(|| format!("终端会话 {id}：页签 {} 不存在", bridged.tab_id))?;
    Ok(SessionInfo {
        session_id: id,
        tab_id: tab.id,
        title: tab.title(),
        state: tab.state,
        running: tab.is_running(),
    })
}

/// 把一次读到的字节喂进领域层屏幕模型。
///
/// **本函数就是「接线」本体**：注入自证（本片 scratch harness）把它暂时改成空实现
/// ⇒「真字节流驱动屏幕模型」的用例必判红；还原 ⇒ 转绿。
/// 改点只有 `feed_into_screen` 里那一行 `guard.feed(bytes);`，便于 `finally` 还原后断言工作区 0 脏。
fn feed_into_screen(screen: &Mutex<TerminalScreen>, bytes: &[u8]) -> Result<(), String> {
    let mut guard = screen.lock().map_err(|_| lock_err("喂屏幕"))?;
    guard.feed(bytes);
    Ok(())
}

/// 把领域层屏幕投影成线上形态（只读既有公开面）。
fn project(screen: &TerminalScreen, eof: bool, exit_code: Option<i32>) -> ScreenProjection {
    let rows: Vec<String> = (0..screen.height()).map(|row| screen.row_text(row)).collect();
    ScreenProjection {
        text: screen.text(),
        rows,
        cursor: Cursor {
            row: screen.cursor_row,
            col: screen.cursor_col,
        },
        cursor_visible: screen.cursor_visible,
        pending_responses: screen.pending_responses.clone(),
        eof,
        exit_code,
    }
}
