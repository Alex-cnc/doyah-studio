//! S-9c 的集成判据：真 shell 的字节流**经领域层**跑通
//! （platform/windows/App/src-tauri/tests/terminal_bridge_e2e.rs）。
//!
//! 四条口径，对卡面验收判据 1 与边界：
//!   ① **核心**：起真 `cmd` 跑一次性命令，**领域层屏幕模型（`Db::terminal::Screen`）的正文里读到标记**
//!      （裸字节里也读到 ⇒ `data` 字段一字未动）；
//!   ② 子进程结束 ⇒ 读端收到 EOF + 退出码，且**页签落 `Exited(Some(7))`**（退出态由真退出码驱动）；
//!   ③ **领域层按键编码**（`terminal_input`）编码出的按键字节**送进真交互式 shell** 并驱动屏幕模型；
//!   ④ 坏路径 ⇒ `open` 必须 `Err` 且错误串非空（不拿空会话冒充成功）。
//!
//! 只经 `terminal_bridge::` 接口调用（它内部只经 `pty::`）：本文件**不许**出现 PTY crate 名。
//!
//! ## 测试自己扮「终端」（与 S-9a 的 `pty_shell.rs` 同一姿势）
//!
//! ConPTY 起会话后先发 `ESC[6n` 并**等终端回话**，不回话一个字节都不吐。本片按裁决 Q3：
//! **回话仍归前端**，桥接层只把 `pending_responses` 当投影/断言用、**不写回 PTY** ——
//! 所以这里由测试自己扮演终端回一次话（真终端 = 前端 xterm.js）。

use std::time::{Duration, Instant};

use doyah_studio_db::terminal_input;
use doyah_studio_db::SessionState;
use doyah_studio_shell::terminal_bridge as bridge;

/// 光标位置查询（ConPTY 起会话后发的第一条）与终端应回的位置报告。
const CURSOR_QUERY: &str = "\u{1b}[6n";
const CURSOR_REPORT: &str = "\u{1b}[1;1R";

/// 扮终端读一圈的结果：裸字节累计 + 最近一次屏幕正文 + 结束信息。
struct Seen {
    raw: String,
    screen_text: String,
    eof: bool,
    exit_code: Option<i32>,
}

/// 扮终端读到 `needle` 出现在**屏幕正文**、读到结束、或超时为止；途中替终端回话光标查询。
fn read_as_terminal(id: u64, needle: &str, budget: Duration) -> Seen {
    let deadline = Instant::now() + budget;
    let mut raw = String::new();
    let mut scanned = 0usize; // 已扫过的字节数（同一条查询只回一次）
    let mut eof = false;
    let mut exit_code = None;
    let mut screen_text = String::new();

    while Instant::now() < deadline {
        let chunk = match bridge::read(id, 300) {
            Ok(chunk) => chunk,
            Err(_) => break,
        };
        raw.push_str(&chunk.data);
        screen_text = chunk.screen.text.clone();
        if chunk.eof {
            eof = true;
            exit_code = chunk.exit_code;
        }

        // 替终端回话（回话归终端：桥接层不写回，由这里回）。
        while let Some(rel) = raw[scanned..].find(CURSOR_QUERY) {
            let at = scanned + rel;
            bridge::write(id, CURSOR_REPORT).expect("替终端回话光标查询应成功");
            scanned = at + CURSOR_QUERY.len();
        }

        if screen_text.contains(needle) {
            break;
        }
        if eof {
            break;
        }
    }

    Seen {
        raw,
        screen_text,
        eof,
        exit_code,
    }
}

/// 判据 ①（核心）：真 shell 的字节流**经桥接驱动领域层屏幕模型**，屏幕正文里读到标记；
/// 裸字节里也应读到（`data` 字段一字未动）。
#[test]
fn 真shell字节流经桥接驱动领域层屏幕模型读到标记() {
    let marker = format!("DOYAH-BRIDGE-MARK-{}", std::process::id());
    let args = vec!["/c".to_string(), format!("echo {marker}")];
    let id = bridge::open("cmd.exe", &args, None, 80, 24).expect("起 cmd.exe 会话应成功");

    let seen = read_as_terminal(id, &marker, Duration::from_secs(25));

    bridge::close(id).expect("关闭会话应成功");
    assert!(
        seen.screen_text.contains(&marker),
        "领域层屏幕模型正文里没读到标记 {marker}；实际屏幕：{:?}",
        seen.screen_text
    );
    assert!(
        seen.raw.contains(&marker),
        "裸字节 data 里也没读到标记 {marker}（data 应一字不动）；实际：{:?}",
        seen.raw
    );
}

/// 判据 ②：子进程结束 ⇒ EOF + 退出码，且**页签落退出态**（真退出码驱动 `mark_exited`）。
#[test]
fn 子进程退出经桥接落入页签退出态() {
    let args = vec!["/c".to_string(), "exit 7".to_string()];
    let id = bridge::open("cmd.exe", &args, None, 80, 24).expect("起 cmd.exe 会话应成功");

    // needle 取一个读端绝不会出现的串 —— 这条只等「结束」。
    let seen = read_as_terminal(id, "\u{0}DOYAH-NEVER", Duration::from_secs(25));

    // 退出态要在关会话前查（关掉就查不到了）。
    let info = bridge::session_info(id).expect("会话应仍在盘上");
    bridge::close(id).expect("关闭会话应成功");

    assert!(seen.eof, "子进程结束后读端应收到结束信号（EOF），但一直没等到（挂住了）");
    assert_eq!(seen.exit_code, Some(7), "子进程退出码应为 7");
    assert!(
        matches!(info.state, SessionState::Exited(Some(7))),
        "页签应落 Exited(Some(7))，实际：{:?}",
        info.state
    );
    assert!(!info.running, "已退出的会话 running 应为 false");
}

/// 判据 ③：**领域层按键编码**（`terminal_input`）产生的字节送进真交互式 shell，驱动屏幕模型。
///
/// 这条把「键盘事件经 `terminal_input` 编码」真正接到真 PTY 字节流上：
/// 逐键编码 `echo <标记>` 再把回车（`key_char('\n')` → CR）送进去，断言屏幕正文读到标记。
#[test]
fn 领域层按键编码经桥接送入真shell并驱动屏幕() {
    let marker = format!("DOYAH-KEY-MARK-{}", std::process::id());
    let id = bridge::open("cmd.exe", &[], None, 80, 24).expect("起交互式 cmd.exe 应成功");

    // 用领域层 `terminal_input::key_char` 逐键编码（可打印字符原样、回车 → CR）。
    let mut typed: Vec<u8> = Vec::new();
    for ch in format!("echo {marker}").chars() {
        typed.extend_from_slice(&terminal_input::key_char(ch));
    }
    typed.extend_from_slice(&terminal_input::key_char('\n'));
    let typed = String::from_utf8(typed).expect("按键编码字节应是合法 UTF-8");

    let deadline = Instant::now() + Duration::from_secs(30);
    let mut raw = String::new();
    let mut scanned = 0usize;
    let mut screen_text = String::new();
    let mut sent = false;

    while Instant::now() < deadline {
        let chunk = match bridge::read(id, 300) {
            Ok(chunk) => chunk,
            Err(_) => break,
        };
        raw.push_str(&chunk.data);
        screen_text = chunk.screen.text.clone();

        while let Some(rel) = raw[scanned..].find(CURSOR_QUERY) {
            let at = scanned + rel;
            bridge::write(id, CURSOR_REPORT).expect("替终端回话光标查询应成功");
            scanned = at + CURSOR_QUERY.len();
        }

        // 等 shell 提示符出来再送按键（过早送进会被行规程丢掉）。
        if !sent && screen_text.contains('>') {
            bridge::write(id, &typed).expect("送按键字节应成功");
            sent = true;
        }
        if screen_text.contains(&marker) {
            break;
        }
        if chunk.eof {
            break;
        }
    }

    bridge::close(id).expect("关闭会话应成功");
    assert!(sent, "一直没等到交互式 shell 的提示符，按键没送出去");
    assert!(
        screen_text.contains(&marker),
        "领域层按键编码送进 shell 后，屏幕模型没读到标记 {marker}；实际屏幕：{:?}",
        screen_text
    );
}

/// 判据 ④：坏路径 ⇒ 桥接 `open` 必须 `Err` 且错误串非空（不拿空会话冒充成功）。
#[test]
fn 桥接坏路径必须返回错误且错误串非空() {
    let missing = r"C:\doyah-bridge-not-exist-9c\no-such-shell-9c.exe";
    let result = bridge::open(missing, &[], None, 80, 24);

    assert!(result.is_err(), "可执行文件不存在时必须返回 Err，实际拿到：{result:?}");
    let message = result.expect_err("上面已断言是 Err");
    assert!(!message.is_empty(), "错误串不许为空");
}
