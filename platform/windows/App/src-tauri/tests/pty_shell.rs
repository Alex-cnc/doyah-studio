//! S-9a 的集成判据：用成熟 crate 起**真交互式 shell**（platform/windows/App/src-tauri/tests/pty_shell.rs）。
//!
//! 三条口径，对卡面验收判据 1 / 2 / 3：
//!   ① 起真 shell，送入 `cmd /c echo <唯一标记>`，**在读端读到该标记**（不是只断言拿到句柄）；
//!   ② 子进程结束 ⇒ 读端收到结束信号（EOF + 退出码）**且不挂住**；
//!   ③ 坏路径（可执行文件不存在）⇒ `open` 必须返回 `Err` 且错误串非空、含路径或「未找到」语义。
//!
//! 只经 `pty::` 接口调用：本文件**不许**出现 PTY crate 名（由
//! `Tools/check-platform-parity.ps1` 第五道「PTY 隔离」判据机械化）。
//!
//! ## 测试自己扮「终端」（这条不是产品代码，是复现真终端的行为）
//!
//! Windows 的伪控制台在会话起来后会先发一条**光标位置查询** `ESC[6n`，并等终端回话
//! `ESC[<行>;<列>R`；不回话，会话就一直不往外吐字（实测：只有 `ESC[6n` 与模式序列，
//! 子进程的 `echo` 一个字都读不到）。真终端（前端的 xterm.js）会自动回话，所以这里照做。
//! **PTY 层只搬字节，回话是终端仿真器的事** —— 界面接线属 `S-9b`，本层不替终端回话。

use std::time::{Duration, Instant};

use doyah_studio_shell::pty;

/// 光标位置查询（ConPTY 起会话后发的第一条）与终端应回的位置报告。
const CURSOR_QUERY: &str = "\u{1b}[6n";
const CURSOR_REPORT: &str = "\u{1b}[1;1R";

struct TerminalRead {
    text: String,
    eof: bool,
    exit_code: Option<i32>,
}

/// 扮终端读：读到 `needle` / 读到结束 / 超时为止；途中替终端回话光标查询。
fn read_as_terminal(id: u64, needle: &str, budget: Duration) -> TerminalRead {
    let deadline = Instant::now() + budget;
    let mut text = String::new();
    let mut scanned = 0usize; // 已扫过的字节数（同一条查询只回一次）
    let mut eof = false;
    let mut exit_code = None;

    while Instant::now() < deadline {
        let chunk = match pty::read(id, 300) {
            Ok(chunk) => chunk,
            Err(_) => break,
        };
        text.push_str(&chunk.data);

        while let Some(rel) = text[scanned..].find(CURSOR_QUERY) {
            let at = scanned + rel;
            pty::write(id, CURSOR_REPORT).expect("替终端回话光标查询应成功");
            scanned = at + CURSOR_QUERY.len();
        }

        if text.contains(needle) {
            break;
        }
        if chunk.eof {
            eof = true;
            if let Some(code) = chunk.exit_code {
                exit_code = Some(code);
                break;
            }
        }
    }

    TerminalRead {
        text,
        eof,
        exit_code,
    }
}

/// 判据 ①：起真 shell，送入一条命令，**读端真读到回显标记**。
#[test]
fn 起真shell并在读端读到唯一标记() {
    // 唯一标记：带进程号，避免与 shell 自己的回显 / 提示符撞车。
    let marker = format!("DOYAH-PTY-MARK-{}", std::process::id());
    let args = vec!["/c".to_string(), format!("echo {marker}")];
    let id = pty::open("cmd.exe", &args, None, 80, 24).expect("起 cmd.exe 会话应成功");

    let seen = read_as_terminal(id, &marker, Duration::from_secs(20));

    pty::close(id).expect("关闭会话应成功");
    assert!(
        seen.text.contains(&marker),
        "读端没读到标记 {marker}；实际读到：{:?}",
        seen.text
    );
}

/// 判据 ②：子进程结束 ⇒ 读端拿到结束信号（EOF + 退出码）且不挂住。
#[test]
fn 子进程结束后读端收到结束信号且不挂住() {
    let args = vec!["/c".to_string(), "exit 7".to_string()];
    let id = pty::open("cmd.exe", &args, None, 80, 24).expect("起 cmd.exe 会话应成功");

    // 标记取一个读端绝不会出现的串 —— 这条只等「结束」。
    let read = read_as_terminal(id, "\u{0}DOYAH-NEVER", Duration::from_secs(25));

    pty::close(id).expect("关闭会话应成功");
    assert!(
        read.eof,
        "子进程结束后读端应收到结束信号（EOF），但一直没等到（挂住了）"
    );
    assert_eq!(read.exit_code, Some(7), "子进程退出码应为 7");
}

/// 判据 ③：坏路径必须 `Err`，且错误串非空、含路径或「未找到」语义（禁止拿空会话冒充成功）。
#[test]
fn 坏路径必须返回错误且错误串非空() {
    let missing = r"C:\doyah-pty-not-exist-9a\no-such-shell-9a.exe";
    let result = pty::open(missing, &[], None, 80, 24);

    assert!(
        result.is_err(),
        "可执行文件不存在时必须返回 Err，实际拿到：{result:?}"
    );
    let message = result.expect_err("上面已断言是 Err");
    assert!(!message.is_empty(), "错误串不许为空");
    let lower = message.to_lowercase();
    assert!(
        message.contains("no-such-shell-9a")
            || message.contains("未找到")
            || message.contains("找不到")
            || lower.contains("cannot find")
            || lower.contains("not find"),
        "错误串应含路径或「未找到」语义，实际：{message}"
    );
}
