//! Doyah Studio · Linux 端 · 无界面验证入口（Cli）—— §8.6.1 第 3 行。
//!
//! **零第三方依赖**：`--json` 由本文件手写输出（骨架片只出两个子命令的固定形状），
//! 这样 CLI 在**任何**宿主上都能跑（含非 Linux 开发机）—— 它的职责正是「不启 GUI 也能验」。
//!
//! 退出码表（**与 `Platform/linux/build.sh` 同款口径：非零 = 如实，不当绿**）：
//!
//! | 码 | 含义 |
//! |---|---|
//! | 0 | 命令跑完，且**没有**缺失项 |
//! | 1 | 用法错（认不出的子命令 / 认不出的参数） |
//! | 2 | 跑完但**有缺失项**（逐条点名 + 补救指引）—— 「有缺失」不是「跑失败」，故与 1 分开 |

use std::process::ExitCode;

use doyah_studio_linux_platform::{missing, probe_all, CapabilityProbe};

const USAGE: &str = "\
Doyah Studio · Linux 端无界面入口（doyah-studio-cli）

用法：
  doyah-studio-cli capabilities [--json]   平台能力表（六项；缺项逐条给补救指引）
  doyah-studio-cli version                 进程内版本口径（Core 的 `PRODUCT_VERSION`；本工程刻意 0.0.0
                                           —— 发布产物版本号的口径在别处，见 Platform/windows/Tools/release-version.json）

退出码：0 = 完成（无缺失项）· 1 = 用法错 · 2 = 完成但有缺失项
";

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let command = args.first().map(String::as_str).unwrap_or("");
    match command {
        "capabilities" => {
            let json = args.iter().any(|a| a == "--json");
            let unknown: Vec<&String> = args[1..].iter().filter(|a| *a != "--json").collect();
            if !unknown.is_empty() {
                eprintln!("认不出的参数：{}（capabilities 只认 --json）", unknown.iter().map(|s| s.as_str()).collect::<Vec<_>>().join(" "));
                return ExitCode::from(1);
            }
            report_capabilities(json)
        }
        "version" => {
            println!("{}", doyah_studio_core::PRODUCT_VERSION);
            ExitCode::SUCCESS
        }
        "" | "-h" | "--help" => {
            print!("{}", USAGE);
            ExitCode::SUCCESS
        }
        other => {
            eprintln!("认不出的子命令：{}", other);
            eprint!("{}", USAGE);
            ExitCode::from(1)
        }
    }
}

fn report_capabilities(json: bool) -> ExitCode {
    let probes = probe_all();
    if json {
        println!("{{");
        println!("  \"host\": \"{}\",", host_label());
        println!("  \"capabilities\": [");
        for (index, probe) in probes.iter().enumerate() {
            let comma = if index + 1 == probes.len() { "" } else { "," };
            println!("    {{");
            println!("      \"name\": \"{}\",", probe.name);
            println!("      \"state\": \"{}\",", probe.state.as_str());
            println!("      \"guidance\": \"{}\"", json_escape(probe.guidance));
            println!("    }}{}", comma);
        }
        println!("  ]");
        println!("}}");
    } else {
        println!("== 平台能力表（取值 present / missing / unknown）==");
        for probe in &probes {
            println!("  {:<9} {:<8} {}", probe.name, probe.state.as_str(), probe.guidance);
        }
    }
    let absent = missing(&probes);
    if absent.is_empty() {
        ExitCode::SUCCESS
    } else {
        let names: Vec<&str> = absent.iter().map(|p| p.name).collect();
        eprintln!("缺 {} 项：{}（逐条补救指引见上；unknown 不计入缺失）", absent.len(), names.join(", "));
        ExitCode::from(2)
    }
}

fn host_label() -> String {
    std::env::var("HOSTNAME")
        .or_else(|_| std::env::var("COMPUTERNAME"))
        .unwrap_or_else(|_| "unknown".to_string())
}

fn json_escape(text: &str) -> String {
    text.replace('\\', "\\\\").replace('"', "\\\"").replace('\n', "\\n")
}

#[allow(dead_code)]
fn assert_shape(probe: &CapabilityProbe) -> bool {
    !probe.guidance.is_empty()
}
