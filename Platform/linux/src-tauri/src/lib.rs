//! Doyah Studio · Linux 端表示层外壳（骨架片）
//!
//! 承载面 = **Tauri 2 + 系统 WebView（WebKitGTK `webkit2gtk-4.1`）**；前端 = **与 Windows 侧同一套**
//! （`Platform/windows/App/`，见 `tauri.conf.json` 的 `frontendDist` / `devUrl`）—— Linux 只换外壳与平台适配层。
//!
//! **后端同源**（概设 §9.3.1）：命令层不再在本端另长一份 —— 132 条命令全部来自
//! `Platform/windows/App/src-tauri`（`doyah-studio-shell`），本端只做三件事：
//!   ① 起壳前的前置检查（缺 WebKitGTK ⇒ 可读提示 + 非零退出，不白屏）；
//!   ② 平台能力表（六项取值：密钥环 / PTY / 通知 / 剪贴板 / 托盘 / WebView）；
//!   ③ 自己的 `tauri.conf.json`（`$XDG_DATA_HOME` 落点、`.desktop`、打包目标）。
//!
//! 为什么第二条不再挂成 `#[tauri::command]`：Tauri 的 `invoke_handler` 只能设一次，
//! 同源命令层已经占住它。这份取值表改为**构建期 / CLI 期**可读（`--self-check`、`build.sh`），
//! 前端不再需要它 —— 前端本来就只调 Windows 那 132 条，一条都没少。

use doyah_studio_linux_platform::{missing, probe_all};
use serde::Serialize;

/// 一项能力（前端拿到的形状：名 + 取值 + 可读提示；前端**只做取值渲染**）。
#[derive(Debug, Clone, Serialize)]
pub struct CapabilityDto {
    pub name: &'static str,
    pub state: &'static str,
    pub guidance: &'static str,
}

/// 启动前的前置检查结论（缺承载面时的可读提示 —— **不静默失败**）。
#[derive(Debug, Clone, Serialize)]
pub struct StartupReport {
    pub webview_ready: bool,
    pub missing: Vec<&'static str>,
    pub guidance: Vec<&'static str>,
}

/// 平台能力表（六项，顺序 = `CAPABILITY_NAMES`）。**不是** tauri 命令，见文件头 ②。
pub fn capabilities() -> Vec<CapabilityDto> {
    probe_all()
        .into_iter()
        .map(|probe| CapabilityDto {
            name: probe.name,
            state: probe.state.as_str(),
            guidance: probe.guidance,
        })
        .collect()
}

/// 启动前置报告（承载面缺 ⇒ 打印可读提示后非零退出，而不是白屏）。
pub fn startup_report() -> StartupReport {
    let probes = probe_all();
    let absent = missing(&probes);
    StartupReport {
        webview_ready: probes
            .iter()
            .find(|p| p.name == "webview")
            .map(|p| p.state == doyah_studio_core::capability::Availability::Present)
            .unwrap_or(false),
        missing: absent.iter().map(|p| p.name).collect(),
        guidance: absent.iter().map(|p| p.guidance).collect(),
    }
}

/// 起壳。
///
/// 启动前检查**承载面**：缺 WebKitGTK ⇒ 打印可读提示并**非零退出**（不是白屏、不是静默失败）。
/// 其余缺项（托盘一类可选面）**不阻塞启动**，由前端按取值渲染。
pub fn run() {
    let report = startup_report();
    if !report.webview_ready {
        for line in &report.guidance {
            eprintln!("{}", line);
        }
        if report.missing.contains(&"webview") {
            eprintln!("系统 WebView 缺失 ⇒ 本端不打包浏览器内核（§8.6.1 形态红线），故无法启动；装好前置后重试。");
            std::process::exit(1);
        }
    }
    for line in &report.guidance {
        eprintln!("提示：{}", line);
    }
    // 命令层、状态、插件面全部来自同源外壳（`doyah_studio_shell::attach`）——
    // 本端**不**再自己 `.plugin(...)` / `.invoke_handler(...)`：重复注册同一插件会在启动期报错，
    // 而第二处 `invoke_handler` 会**静默覆盖**第一处（前端那条命令就成了「调不到」）。
    if let Err(error) = doyah_studio_shell::attach(tauri::Builder::default()).run(tauri::generate_context!()) {
        eprintln!("启动失败：{}", error);
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn capability_dtos_mirror_the_frozen_table() {
        let dtos = capabilities();
        let names: Vec<&str> = dtos.iter().map(|d| d.name).collect();
        assert_eq!(names, doyah_studio_core::capability::CAPABILITY_NAMES.to_vec());
        // 取值只许是三档之一（前端按此渲染，不许出现第四种）
        for dto in &dtos {
            assert!(["present", "missing", "unknown"].contains(&dto.state), "{} 的取值越界", dto.name);
        }
    }

    #[test]
    fn startup_report_is_serializable_and_matches_probe_facts() {
        let report = startup_report();
        let probes = probe_all();
        let expected: Vec<&str> = missing(&probes).iter().map(|p| p.name).collect();
        assert_eq!(report.missing, expected);
        assert_eq!(report.guidance.len(), report.missing.len());
    }
}
