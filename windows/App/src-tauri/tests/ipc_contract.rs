//! 前端 `invoke` ↔ 本层命令注册的**双向判据**（windows/App/src-tauri/tests/ipc_contract.rs）
//!
//! 为什么要有它：前端 `invoke('grid_window')` 打错了名字 / 服务端忘了 `generate_handler!` 注册，
//! 现象都是**运行时静默失败**（界面空着，没有任何东西会红）。两侧都是文本，判据就按文本判：
//!   ① 前端 `COMMANDS` 里的每个命令名，必须在本层被 `#[tauri::command]` 声明**且**注册进 `generate_handler![]`；
//!   ② 本层注册的每个命令，前端至少有一处在用（多注册不报错，但**没人用**就是漏登记 —— 打印出来）。
//!
//! 这是「同一事实两份拷贝」的机械对账（两侧都在本仓，`include_str!` 直接读源）。

const IPC_SOURCE: &str = include_str!("../../src/ipc.ts");
const LIB_SOURCE: &str = include_str!("../src/lib.rs");

/// 取前端 `COMMANDS` 对象里的取值（`appInfo: 'app_info',` → `app_info`）。
fn frontend_commands() -> Vec<String> {
    let start = IPC_SOURCE
        .find("export const COMMANDS")
        .expect("前端 ipc.ts 里没有 COMMANDS —— 命令名没有单一出处了");
    let block = &IPC_SOURCE[start..];
    let end = block.find("} as const").expect("COMMANDS 的收尾标记变了");
    let block = &block[..end];
    let mut names = Vec::new();
    for line in block.lines() {
        if let Some(open) = line.find('\'') {
            if let Some(close) = line[open + 1..].find('\'') {
                names.push(line[open + 1..open + 1 + close].to_string());
            }
        }
    }
    assert!(names.len() >= 3, "只解析到 {} 个命令名 —— 形状变了，判据要跟着改", names.len());
    names
}

/// 取本层 `generate_handler![]` 里的注册项。
///
/// 注意（实测踩过）：别用 `split(',').skip(1)` —— 首项与开括号连在一起
/// （`generate_handler![app_info`），`skip(1)` 会把**真实存在的第一个命令**吃掉，
/// 于是「前端调了 `app_info`」被误判成「没注册」。开括号要**按长度切掉**。
fn registered_commands() -> Vec<String> {
    let marker = "generate_handler![";
    let start = LIB_SOURCE
        .find(marker)
        .expect("lib.rs 里没有 generate_handler! —— 命令没有注册处")
        + marker.len();
    let block = &LIB_SOURCE[start..];
    let end = block.find(']').expect("generate_handler! 的收尾标记变了");
    let commands: Vec<String> = block[..end]
        .split(',')
        .map(|item| item.trim().to_string())
        .filter(|item| !item.is_empty())
        .collect();
    assert!(!commands.is_empty(), "注册表解析出来是空的 —— 形状变了，判据要跟着改（空跑不许通过）");
    commands
}

#[test]
fn 前端命令名都在本层注册() {
    let registered = registered_commands();
    for name in frontend_commands() {
        assert!(
            LIB_SOURCE.contains(&format!("fn {name}(")),
            "前端 invoke 的 {name} 在本层没有 #[tauri::command] 声明（运行时静默失败）"
        );
        assert!(registered.contains(&name), "前端 invoke 的 {name} 没有注册进 generate_handler![]");
    }
}

#[test]
fn 本层注册的命令前端都在用() {
    for name in registered_commands() {
        assert!(
            IPC_SOURCE.contains(&format!("'{name}'")),
            "本层注册了 {name}，但前端 ipc.ts 里没有任何地方引用 —— 要么补前端，要么从 COMMANDS 里去掉"
        );
    }
}
