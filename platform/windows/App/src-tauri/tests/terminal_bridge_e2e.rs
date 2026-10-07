//! S-9c 的集成判据：真 shell 的字节流**经领域层**跑通（S-9d 起加「单点回话」）
//! （platform/windows/App/src-tauri/tests/terminal_bridge_e2e.rs）。
//!
//! 五条口径，对卡面验收判据 1 与边界：
//!   ① **核心**：起真 `cmd` 跑一次性命令，**领域层屏幕模型（`Db::terminal::Screen`）的正文里读到标记**
//!      （裸字节里也读到 ⇒ `data` 字段一字未动）；
//!   ② 子进程结束 ⇒ 读端收到 EOF + 退出码，且**页签落 `Exited(Some(7))`**（退出态由真退出码驱动）；
//!   ③ **领域层按键编码**（`terminal_input`）编码出的按键字节**送进真交互式 shell** 并驱动屏幕模型；
//!   ④ 坏路径 ⇒ `open` 必须 `Err` 且错误串非空（不拿空会话冒充成功）；
//!   ⑤ **（S-9d 新增核心）单点回话**：设备查询（`ESC[6n`）**由桥接层回、且恰好回一条** ——
//!      测试侧**不再替终端回话**，桥接回了话真 shell 才吐字节（否则按 S-9a 零字节）；
//!      投影里出现的光标报告形状应答**计数 = 1**（消费后清空 ⇒ 不回两次、不每次 `read` 重发）。
//!
//! 只经 `terminal_bridge::` 接口调用（它内部只经 `pty::`）：本文件**不许**出现 PTY crate 名。
//!
//! ## 测试侧不再替终端回话（`S-9d` 裁决 Q3 落实）
//!
//! `S-9c` 时 ConPTY 起会话后先发 `ESC[6n` 并**等终端回话**，那时回话归前端，测试自己扮终端回一次。
//! `S-9d` 把回话搬到桥接层单点 ⇒ 测试若再手工回话就是**双回话**（正是本片要消灭的缺陷）——
//! 故本文件一律**删掉手工回话**，改为**依赖桥接回话**：桥接回了话真 shell 才吐字节。

use std::time::{Duration, Instant};

use doyah_studio_db::terminal_input;
use doyah_studio_db::SessionState;
use doyah_studio_shell::terminal_bridge as bridge;

/// 光标位置查询（ConPTY 起会话后发的第一条）。测试只用来**认原始字节**（不再回话）。
const CURSOR_QUERY: &str = "\u{1b}[6n";

/// 判断一条应答是不是「光标位置报告」（`ESC[<行>;<列>R`）—— 手写解析，不引依赖。
fn is_cursor_report(text: &str) -> bool {
    let Some(rest) = text.strip_prefix("\u{1b}[") else {
        return false;
    };
    let Some(rest) = rest.strip_suffix('R') else {
        return false;
    };
    let mut parts = rest.split(';');
    let (Some(row), Some(col), None) = (parts.next(), parts.next(), parts.next()) else {
        return false;
    };
    !row.is_empty()
        && !col.is_empty()
        && row.bytes().all(|b| b.is_ascii_digit())
        && col.bytes().all(|b| b.is_ascii_digit())
}

/// 扮终端读一圈的结果：裸字节累计 + 最近一次屏幕正文 + 结束信息 + 投影出的光标报告应答计数。
struct Seen {
    raw: String,
    screen_text: String,
    eof: bool,
    exit_code: Option<i32>,
    /// 整段会话里**投影出来**的光标报告形状应答条数（消费后清空 ⇒ 每条至多一次）。
    replies: usize,
}

/// 扮终端读到 `needle` 出现在**屏幕正文**、读到结束、或超时为止。
///
/// **不再替终端回话**：回话已归桥接层单点（见文件头）。本函数只累计裸字节、屏幕正文与应答计数。
fn read_as_terminal(id: u64, needle: &str, budget: Duration) -> Seen {
    let deadline = Instant::now() + budget;
    let mut raw = String::new();
    let mut eof = false;
    let mut exit_code = None;
    let mut screen_text = String::new();
    let mut replies = 0usize;

    while Instant::now() < deadline {
        let chunk = match bridge::read(id, 300) {
            Ok(chunk) => chunk,
            Err(_) => break,
        };
        raw.push_str(&chunk.data);
        screen_text = chunk.screen.text.clone();
        replies += chunk
            .screen
            .pending_responses
            .iter()
            .filter(|response| is_cursor_report(response))
            .count();
        if chunk.eof {
            eof = true;
            exit_code = chunk.exit_code;
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
        replies,
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
    let mut screen_text = String::new();
    let mut sent = false;

    while Instant::now() < deadline {
        let chunk = match bridge::read(id, 300) {
            Ok(chunk) => chunk,
            Err(_) => break,
        };
        screen_text = chunk.screen.text.clone();

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

/// 判据 ⑤（`S-9d` 新增核心）：设备查询**由桥接层回、且恰好回一条**。
///
/// 两半合起来才证明「**单点**回话」：
///   (a) 桥接真回了话 —— 测试**不再手工回话**，真 shell 却仍吐出了标记
///       （否则按 S-9a：不回话一个字节都不吐 ⇒ 屏幕正文 / 裸字节里都不会有标记）；
///   (b) 投影出的光标报告形状应答**恰好一条** —— `pending_responses` 消费后清空，
///       故「同一条查询回两次」与「每次 `read` 重发」都会让计数 > 1 而判红。
#[test]
fn 设备查询经桥接恰好回一条应答() {
    let marker = format!("DOYAH-REPLY-MARK-{}", std::process::id());
    let args = vec!["/c".to_string(), format!("echo {marker}")];
    let id = bridge::open("cmd.exe", &args, None, 80, 24).expect("起 cmd.exe 会话应成功");

    let seen = read_as_terminal(id, &marker, Duration::from_secs(25));
    bridge::close(id).expect("关闭会话应成功");

    // (a) 桥接真回了话：真 shell 吐出了标记（前端未回话、测试也未回话）。
    assert!(
        !seen.raw.is_empty(),
        "桥接回话后真 shell 应有输出，但裸字节为空（说明回话没送出去）"
    );
    assert!(
        seen.screen_text.contains(&marker),
        "真 shell 没吐出标记 {marker} —— 桥接的回话大概率没写回 PTY；实际屏幕：{:?}",
        seen.screen_text
    );
    // 顺带确认 ConPTY 发来的设备查询原文留在裸字节里（前端不吞、桥接也不吞）。
    assert!(
        seen.raw.contains(CURSOR_QUERY),
        "裸字节里应留下 ConPTY 发来的设备查询原文；实际：{:?}",
        seen.raw
    );
    // (b) 投影出的光标报告应答恰好一条（消费后清空）。
    assert_eq!(
        seen.replies, 1,
        "设备查询应答应恰好投影一条（消费后清空），实际 {} 条；裸字节：{:?}",
        seen.replies, seen.raw
    );
}
