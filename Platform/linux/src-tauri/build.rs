// Doyah Studio · Linux 端 · 构建脚本（tauri-build）
//
// 与 Windows 侧 App/src-tauri/build.rs 同形：只做 Tauri 的构建期代码生成
// （能力集校验 / 命令面注册），不含任何平台探测逻辑 —— 平台探测归 Platform/Linux/。

fn main() {
    tauri_build::build()
}
