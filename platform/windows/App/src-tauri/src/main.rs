// Windows 子系统：发布构建不弹控制台窗口（调试构建保留，方便看 panic 与日志）。
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    doyah_studio_shell::run()
}
