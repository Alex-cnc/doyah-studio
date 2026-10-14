//! Doyah Studio · Linux 端平台适配层（骨架片）
//!
//! **只有这一层谈 Linux 专有能力**（§8.6.1 第 4 行）。
//!
//! 本片落的是**能力探测**（存在性检查，标准库即可）与**可读缺失提示**：
//! §8.6.1 写着「该前置缺失时**给可读提示与补救指引，不静默失败**」—— 提示文本就在这里，
//! 因为它与「怎么探」是同一条知识；探到几档由领域层的 [`Availability`] 表达（前端按取值渲染）。
//!
//! **本片不做的事（如实登记，见 `Platform/linux/README.md` 未接网清单）**：
//! 真绑定（WebKitGTK 版本查询 / Secret Service 取凭据 / portable-pty 起真终端）**未落**；
//! 因此 [`Availability::Present`] 现在的含义是「**前置在盘上**」，不是「**接口可用**」。

use doyah_studio_core::capability::Availability;

/// 一项能力的探测结论 + 缺了怎么办（一句可读提示）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CapabilityProbe {
    /// 能力名（取自 `doyah_studio_core::capability::CAPABILITY_NAMES`，不另起名）
    pub name: &'static str,
    /// 三档取值（`present` / `missing` / `unknown`）
    pub state: Availability,
    /// 可读提示：在 ⇒ 说明探到了什么；缺 ⇒ 给补救指引（一行能照做）
    pub guidance: &'static str,
}

/// 六项一次探完（顺序 = [`doyah_studio_core::capability::CAPABILITY_NAMES`]）。
pub fn probe_all() -> Vec<CapabilityProbe> {
    vec![
        probe_webview(),
        probe_secret_service(),
        probe_pty(),
        probe_notifications(),
        probe_clipboard(),
        probe_tray(),
    ]
}

/// 只报「缺」的那些（CLI 的退出码与构建入口的提示都用它，避免各处自己过滤）。
pub fn missing(probes: &[CapabilityProbe]) -> Vec<&CapabilityProbe> {
    probes.iter().filter(|p| p.state == Availability::Missing).collect()
}

fn any_lib_exists(names: &[&str], dirs: &[&str]) -> bool {
    std::fs::read_dir("/usr/lib")
        .into_iter()
        .chain(std::fs::read_dir("/usr/lib64"))
        .chain(std::fs::read_dir("/lib"))
        .chain(dirs.iter().filter_map(|d| std::fs::read_dir(d).ok()))
        .flatten()
        .filter_map(|entry| entry.ok())
        .any(|entry| {
            let file = entry.file_name().to_string_lossy().to_string();
            names.iter().any(|name| file.starts_with(name))
        })
}

fn lib_dirs() -> Vec<&'static str> {
    vec![
        "/usr/lib/x86_64-linux-gnu",
        "/usr/lib/aarch64-linux-gnu",
        "/usr/lib64",
    ]
}

/// 承载面：系统 WebView = WebKitGTK `webkit2gtk-4.1`（**不打包浏览器内核**，§8.6.1 形态红线）。
///
/// 探测 = 共享库 / `pkg-config` 说明文件在不在盘上（**不手写 FFI**）。
pub fn probe_webview() -> CapabilityProbe {
    const NAME: &str = "webview";
    let libs = lib_dirs();
    let found = any_lib_exists(&["libwebkit2gtk-4.1.so"], &libs);
    let pc = std::path::Path::new("/usr/lib/x86_64-linux-gnu/pkgconfig/webkit2gtk-4.1.pc").exists()
        || std::path::Path::new("/usr/share/pkgconfig/webkit2gtk-4.1.pc").exists();
    if found || pc {
        CapabilityProbe {
            name: NAME,
            state: Availability::Present,
            guidance: "系统 WebView（WebKitGTK 4.1）在盘上",
        }
    } else {
        CapabilityProbe {
            name: NAME,
            state: Availability::Missing,
            guidance: "缺系统 WebView ⇒ sudo apt install libwebkit2gtk-4.1-0（Debian / Ubuntu；本端不打包浏览器内核，只能依赖系统 WebView）",
        }
    }
}

/// 凭据：系统密钥环（Secret Service，§8.6.4「**无可用密钥环时如实报错，不回落明文**」）。
pub fn probe_secret_service() -> CapabilityProbe {
    const NAME: &str = "secret-service";
    let session_bus = std::env::var("DBUS_SESSION_BUS_ADDRESS").is_ok();
    let service_file = std::path::Path::new("/usr/share/dbus-1/services/org.freedesktop.secrets.service").exists();
    if session_bus && service_file {
        CapabilityProbe {
            name: NAME,
            state: Availability::Present,
            guidance: "会话总线 + org.freedesktop.secrets 服务文件都在（密钥环走 Secret Service）",
        }
    } else if !session_bus {
        CapabilityProbe {
            name: NAME,
            state: Availability::Missing,
            guidance: "没有会话总线（DBUS_SESSION_BUS_ADDRESS 未设）⇒ 无密钥环可用：凭据功能如实报错、不回落明文",
        }
    } else {
        CapabilityProbe {
            name: NAME,
            state: Availability::Missing,
            guidance: "缺 org.freedesktop.secrets 服务 ⇒ 装 GNOME Keyring / KWallet（apt install gnome-keyring）后重试",
        }
    }
}

/// 终端：PTY + shell 探测（`$SHELL`，`/bin/sh` 兜底 —— §8.6.4）。
pub fn probe_pty() -> CapabilityProbe {
    const NAME: &str = "pty";
    let shell = std::env::var("SHELL").unwrap_or_default();
    let fallback = std::path::Path::new("/bin/sh").exists();
    if !shell.is_empty() && std::path::Path::new(&shell).exists() {
        CapabilityProbe {
            name: NAME,
            state: Availability::Present,
            guidance: "探测到用户 shell（$SHELL 指向的解释器在盘上）",
        }
    } else if fallback {
        CapabilityProbe {
            name: NAME,
            state: Availability::Present,
            guidance: "$SHELL 未设或不在盘上 ⇒ 按 §8.6.4 兜底到 /bin/sh（在盘上）",
        }
    } else {
        CapabilityProbe {
            name: NAME,
            state: Availability::Missing,
            guidance: "找不到可用解释器（$SHELL 与 /bin/sh 都不可用）⇒ 内置终端不可用，界面按取值灰着",
        }
    }
}

/// 通知：freedesktop 通知规范（§8.6.4「权限未授予时**如实降级并说明**，不静默丢」）。
pub fn probe_notifications() -> CapabilityProbe {
    const NAME: &str = "notifications";
    let service_file = std::path::Path::new("/usr/share/dbus-1/services/org.freedesktop.Notifications.service").exists();
    if std::env::var("DBUS_SESSION_BUS_ADDRESS").is_ok() && service_file {
        CapabilityProbe {
            name: NAME,
            state: Availability::Present,
            guidance: "会话总线 + 通知服务文件都在（走 freedesktop 通知）",
        }
    } else {
        CapabilityProbe {
            name: NAME,
            state: Availability::Missing,
            guidance: "会话总线或通知服务缺失 ⇒ 通知如实降级并说明（不静默丢）",
        }
    }
}

/// 剪贴板：X11 / Wayland 会话（§8.6.4 剪贴板面）。
pub fn probe_clipboard() -> CapabilityProbe {
    const NAME: &str = "clipboard";
    let wayland = std::env::var("WAYLAND_DISPLAY").is_ok();
    let x11 = std::env::var("DISPLAY").is_ok();
    if wayland || x11 {
        CapabilityProbe {
            name: NAME,
            state: Availability::Present,
            guidance: if wayland { "Wayland 会话（WAYLAND_DISPLAY 已设）" } else { "X11 会话（DISPLAY 已设）" },
        }
    } else {
        CapabilityProbe {
            name: NAME,
            state: Availability::Unknown,
            guidance: "无图形会话变量（DISPLAY / WAYLAND_DISPLAY 都没设）⇒ 问不出来（不是「不支持」）：按 unknown 渲染",
        }
    }
}

/// 托盘：`libayatana-appindicator3`（**可选面**；§8.6.6 待定项 2「无托盘时降级成什么」待前门 / 人类主人裁）。
pub fn probe_tray() -> CapabilityProbe {
    const NAME: &str = "tray";
    let libs = lib_dirs();
    if any_lib_exists(&["libayatana-appindicator3.so"], &libs) {
        CapabilityProbe {
            name: NAME,
            state: Availability::Present,
            guidance: "libayatana-appindicator3 在盘上（托盘可用）",
        }
    } else {
        CapabilityProbe {
            name: NAME,
            state: Availability::Missing,
            guidance: "缺 libayatana-appindicator3 ⇒ 不打托盘（可选面，不阻塞启动；降级形态见 §8.6.6 待定项 2）",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn probe_all_covers_the_frozen_name_table_in_order() {
        let probes = probe_all();
        let names: Vec<&str> = probes.iter().map(|p| p.name).collect();
        assert_eq!(names, doyah_studio_core::capability::CAPABILITY_NAMES.to_vec());
    }

    #[test]
    fn every_probe_carries_a_guidance_line() {
        for probe in probe_all() {
            assert!(!probe.guidance.trim().is_empty(), "{} 缺可读提示", probe.name);
            // 提示必须是「认得出」的取值串，前端拿它只做取值渲染
            assert!(["present", "missing", "unknown"].contains(&probe.state.as_str()));
        }
    }

    #[test]
    fn missing_filter_returns_only_missing() {
        let probes = vec![
            CapabilityProbe { name: "a", state: Availability::Present, guidance: "x" },
            CapabilityProbe { name: "b", state: Availability::Missing, guidance: "y" },
            CapabilityProbe { name: "c", state: Availability::Unknown, guidance: "z" },
        ];
        let got: Vec<&str> = missing(&probes).iter().map(|p| p.name).collect();
        assert_eq!(got, vec!["b"], "unknown 不许被算成 missing");
    }

    #[test]
    fn probes_on_a_non_linux_host_are_honest_not_optimistic() {
        // 本片在非 Linux 宿主（开发机）上跑：库文件探测必然探不到 ⇒ webview 只许报 missing，
        // 不许因为「反正要上 Linux」就报 present（那是假绿）。
        let probe = probe_webview();
        if !cfg!(target_os = "linux") {
            assert_eq!(probe.state, Availability::Missing);
        }
    }
}
