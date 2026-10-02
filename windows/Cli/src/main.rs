//! Doyah Studio · Windows 侧无界面验证入口（`Cli/`）
//!
//! 契约与归属（概要设计 §8.5.1 / §8.5.3，本 crate 属实现层）：
//! - 形态 = **子命令 + 退出码表 + `--json`** —— 对侧 `CLI/main.swift` 的等价物，
//!   目的是「**无 GUI 也能验证领域层**」；
//! - **零第三方依赖**：不引 `clap` / `serde`，参数表与 JSON 自己写（构建期不联网取 crate）；
//! - **缺席必须可见**：对侧有、本侧尚无等价物的子命令一律登记在 `MAC_ONLY` —— 调用它们
//!   返回退出码 2 并逐条打印「缺哪一层」，不静默、不假装支持；
//! - 只读领域层公开面（`doyah_studio_core`），不引平台专有 API（那是 `Platform/Windows/` 的事）。

use std::process::exit;

use doyah_studio_core::dataset::{generate, Column};
use doyah_studio_core::Dataset;

/// 退出码表（与 `windows/Tools/README.md` 的闸门协议对齐）
const EXIT_OK: i32 = 0; // 跑过且通过
const EXIT_FAIL: i32 = 1; // 判红：参数非法 / 自检不成立 / 未知子命令
const EXIT_UNIMPLEMENTED: i32 = 2; // 未实现：对侧有、本侧尚无等价物（缺席可见）

/// 窗口取数单次最多实体化多少行（防手滑把 40 万行打到终端；截断时如实报 `capped: true`）
const WINDOW_ROW_CAP: usize = 1000;

/// 对侧（macOS `CLI/main.swift`）已有、本侧**尚未落地**的子命令：名字 → 缺哪一层。
const MAC_ONLY: &[(&str, &str)] = &[
    ("secret", "凭据存储（Platform/Windows/ 的凭据管理器未建）"),
    ("notes", "笔记存储（Core 的笔记分层未建）"),
    ("agent-sql", "智能体 SQL 通道（数据库驱动未选型）"),
    ("archive-add", "归档写入（Core 归档面未建）"),
    ("specs", "规格导出（本地化层未建）"),
    (
        "terminal-palette",
        "终端配色（Platform/Windows/ 的 ConPTY 未建）",
    ),
    ("terminal-modes", "终端模式（同上）"),
    ("code-tokens", "代码高亮令牌（Core 语言面未建）"),
    ("tunnel", "SSH 隧道（P-25，未开工）"),
    ("mysql", "MySQL 驱动（未选型）"),
    ("diagnose", "自诊断（未开工）"),
    ("maintain", "维护任务（未开工）"),
    ("mcp", "MCP 桥（未开工）"),
    ("memory", "记忆库（未开工）"),
    ("connections", "连接管理（未开工）"),
    ("backup", "备份（未开工）"),
];

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    exit(run(&args));
}

fn run(args: &[String]) -> i32 {
    let Some(cmd) = args.first().map(String::as_str) else {
        print_help();
        return EXIT_OK;
    };
    if matches!(cmd, "--help" | "-h" | "help") {
        print_help();
        return EXIT_OK;
    }
    let json = flag(args, "--json");
    match cmd {
        "capabilities" => cmd_capabilities(json),
        "dataset" => match sub(args) {
            Some("summary") => cmd_dataset_summary(args, json),
            _ => unknown("dataset", args),
        },
        "grid" => match sub(args) {
            Some("window") => cmd_grid_window(args, json),
            Some("sort") => cmd_grid_sort(args, json),
            Some("filter") => cmd_grid_filter(args, json),
            _ => unknown("grid", args),
        },
        other => {
            if let Some((_, reason)) = MAC_ONLY.iter().find(|(n, _)| *n == other) {
                eprintln!("未实现：{other}");
                eprintln!("  缺的层：{reason}");
                eprintln!("  退出码 2 = 未实现（对侧有、本侧尚无等价物）；完整缺席清单见 `capabilities`。");
                EXIT_UNIMPLEMENTED
            } else {
                eprintln!("未知子命令：{other}");
                print_help();
                EXIT_FAIL
            }
        }
    }
}

fn sub<'a>(args: &'a [String]) -> Option<&'a str> {
    args.get(1).map(String::as_str)
}

fn unknown(group: &str, args: &[String]) -> i32 {
    eprintln!(
        "{group}：缺少或未知的子命令（{}）",
        args.get(1).map(String::as_str).unwrap_or("")
    );
    print_help();
    EXIT_FAIL
}

// ---------- 子命令 ----------

fn cmd_capabilities(json: bool) -> i32 {
    if json {
        let mac_only: Vec<String> = MAC_ONLY
            .iter()
            .map(|(n, r)| format!("{{\"name\":{},\"missing_layer\":{}}}", jstr(n), jstr(r)))
            .collect();
        println!(
            "{{\"command\":\"capabilities\",\"implemented\":[\"capabilities\",\"dataset summary\",\"grid window\",\"grid sort\",\"grid filter\"],\"exit_codes\":{{\"0\":\"通过\",\"1\":\"判红\",\"2\":\"未实现\"}},\"mac_only\":[{}]}}",
            mac_only.join(",")
        );
    } else {
        println!("已实现：");
        for c in [
            "capabilities",
            "dataset summary",
            "grid window",
            "grid sort",
            "grid filter",
        ] {
            println!("  {c}");
        }
        println!("缺席（对侧有、本侧尚无等价物；调用即退出码 2）：");
        for (n, r) in MAC_ONLY {
            println!("  {n:<18} 缺的层：{r}");
        }
        println!("退出码：0 通过 / 1 判红 / 2 未实现");
    }
    EXIT_OK
}

fn cmd_dataset_summary(args: &[String], json: bool) -> i32 {
    let (rows, cols, seed) = match shape(args) {
        Ok(v) => v,
        Err(code) => return code,
    };
    let ds = generate(rows, cols, seed);
    if json {
        let cols_json: Vec<String> = ds
            .data
            .iter()
            .enumerate()
            .map(|(i, c)| {
                format!(
                    "{{\"index\":{},\"name\":{},\"kind\":{},\"bytes\":{}}}",
                    i,
                    jstr(&ds.columns[i]),
                    jstr(c.kind()),
                    c.bytes()
                )
            })
            .collect();
        println!(
            "{{\"command\":\"dataset summary\",\"rows\":{},\"cols\":{},\"seed\":{},\"bytes\":{},\"columns\":[{}]}}",
            ds.rows,
            ds.cols(),
            seed,
            ds.bytes(),
            cols_json.join(",")
        );
    } else {
        println!("数据集：{} 行 × {} 列（seed {}）", ds.rows, ds.cols(), seed);
        println!("驻留字节估算：{}", ds.bytes());
        for (i, c) in ds.data.iter().enumerate() {
            println!(
                "  [{i}] {:<10} {:<5} {} 字节",
                ds.columns[i],
                c.kind(),
                c.bytes()
            );
        }
    }
    EXIT_OK
}

fn cmd_grid_window(args: &[String], json: bool) -> i32 {
    let (rows, cols, seed) = match shape(args) {
        Ok(v) => v,
        Err(code) => return code,
    };
    let start = match uint(args, "--start", 0) {
        Ok(v) => v,
        Err(code) => return code,
    };
    let len = match uint(args, "--len", 40) {
        Ok(v) => v,
        Err(code) => return code,
    };
    let ds = generate(rows, cols, seed);
    let order = match maybe_order(&ds, args) {
        Ok(o) => o,
        Err(code) => return code,
    };
    let capped = len > WINDOW_ROW_CAP;
    let w = ds.window(&order, start, std::cmp::min(len, WINDOW_ROW_CAP));
    let rows_json: Vec<String> = w
        .rows
        .iter()
        .map(|r| {
            let cells: Vec<String> = r.iter().map(|c| jstr(c)).collect();
            format!("[{}]", cells.join(","))
        })
        .collect();
    if json {
        let cols_json: Vec<String> = w.columns.iter().map(|c| jstr(c)).collect();
        println!(
            "{{\"command\":\"grid window\",\"rows\":{},\"cols\":{},\"seed\":{},\"start\":{},\"len\":{},\"returned\":{},\"capped\":{},\"columns\":[{}],\"rows\":[{}]}}",
            ds.rows, ds.cols(), seed, start, len, w.rows.len(), capped,
            cols_json.join(","), rows_json.join(",")
        );
    } else {
        println!(
            "窗口：start={start} len={len} 取回 {} 行（capped={capped}）",
            w.rows.len()
        );
        println!("{}", w.columns.join(" | "));
        for r in &w.rows {
            println!("{}", r.join(" | "));
        }
    }
    EXIT_OK
}

fn cmd_grid_sort(args: &[String], json: bool) -> i32 {
    let (rows, cols, seed) = match shape(args) {
        Ok(v) => v,
        Err(code) => return code,
    };
    let col = match uint(args, "--col", usize::MAX) {
        Ok(v) => v,
        Err(code) => return code,
    };
    if col >= cols {
        eprintln!("--col {col} 越界（列数 {cols}）");
        return EXIT_FAIL;
    }
    let desc = flag(args, "--desc");
    let ds = generate(rows, cols, seed);
    let order = ds.sort_order(col, desc);
    let (perm, ordered) = checks(&ds, col, &order, desc);
    if json {
        println!(
            "{{\"command\":\"grid sort\",\"rows\":{},\"cols\":{},\"seed\":{},\"col\":{},\"desc\":{},\"is_permutation\":{},\"is_ordered\":{},\"first\":{},\"last\":{}}}",
            ds.rows, ds.cols(), seed, col, desc, perm, ordered,
            order.first().map(|v| v.to_string()).unwrap_or_else(|| "null".into()),
            order.last().map(|v| v.to_string()).unwrap_or_else(|| "null".into())
        );
    } else {
        println!(
            "排序：{rows} 行 × {cols} 列，按第 {col} 列{}",
            if desc { "降序" } else { "升序" }
        );
        println!(
            "  置换 = {perm} · 有序 = {ordered} · 首 {} 末 {}",
            order[0],
            order[rows - 1]
        );
    }
    if perm && ordered {
        EXIT_OK
    } else {
        eprintln!("自检不成立：置换 = {perm}、有序 = {ordered}");
        EXIT_FAIL
    }
}

fn cmd_grid_filter(args: &[String], json: bool) -> i32 {
    let (rows, cols, seed) = match shape(args) {
        Ok(v) => v,
        Err(code) => return code,
    };
    let col = match uint(args, "--col", usize::MAX) {
        Ok(v) => v,
        Err(code) => return code,
    };
    if col >= cols {
        eprintln!("--col {col} 越界（列数 {cols}）");
        return EXIT_FAIL;
    }
    let ds = generate(rows, cols, seed);
    let (hits, mode, spec, ok) = if let Some(t) = value(args, "--text") {
        let hits = ds.filter_text(col, &t);
        let ok = hits.iter().all(|&r| ds.data[col].cell(r) == t);
        (hits, "text", format!("text={t}"), ok)
    } else if let (Some(lo), Some(hi)) = (value(args, "--lo"), value(args, "--hi")) {
        let (lo, hi) = match (lo.parse::<f64>(), hi.parse::<f64>()) {
            (Ok(a), Ok(b)) => (a, b),
            _ => {
                eprintln!("--lo / --hi 必须是数值");
                return EXIT_FAIL;
            }
        };
        let hits = ds.filter_num_range(col, lo, hi);
        let ok = hits.iter().all(|&r| match &ds.data[col] {
            Column::Num(v) => v[r] >= lo && v[r] <= hi,
            Column::Text(_) => false,
        });
        (hits, "num_range", format!("lo={lo} hi={hi}"), ok)
    } else {
        eprintln!("需要 --text <值>，或 --lo <下界> --hi <上界>");
        return EXIT_FAIL;
    };
    if json {
        println!(
            "{{\"command\":\"grid filter\",\"rows\":{},\"cols\":{},\"seed\":{},\"col\":{},\"mode\":{},\"spec\":{},\"hits\":{},\"all_hits_match\":{}}}",
            ds.rows, ds.cols(), seed, col, jstr(mode), jstr(&spec), hits.len(), ok
        );
    } else {
        println!("筛选：{rows} 行 × {cols} 列，第 {col} 列 {mode}（{spec}）命中 {} 行；命中项全符合 = {ok}", hits.len());
    }
    if ok {
        EXIT_OK
    } else {
        eprintln!("自检不成立：命中项里存在不符合谓词的行");
        EXIT_FAIL
    }
}

// ---------- 工具 ----------

/// `--rows` / `--cols` / `--seed` 三个公共参数（默认 1000 行 × 5 列、seed 1）
fn shape(args: &[String]) -> Result<(usize, usize, u64), i32> {
    let rows = uint(args, "--rows", 1000)?;
    let cols = uint(args, "--cols", 5)?;
    if rows == 0 || cols == 0 {
        eprintln!("--rows / --cols 必须 ≥ 1");
        return Err(EXIT_FAIL);
    }
    let seed = match value(args, "--seed") {
        None => 1u64,
        Some(s) => match s.parse::<u64>() {
            Ok(v) => v,
            Err(_) => {
                eprintln!("--seed 必须是非负整数：{s}");
                return Err(EXIT_FAIL);
            }
        },
    };
    Ok((rows, cols, seed))
}

/// 需要排序时给出行索引置换（不给 `--col` 就是原序）
fn maybe_order(ds: &Dataset, args: &[String]) -> Result<Vec<usize>, i32> {
    match value(args, "--col") {
        None => Ok((0..ds.rows).collect()),
        Some(s) => match s.parse::<usize>() {
            Ok(c) if c < ds.cols() => Ok(ds.sort_order(c, flag(args, "--desc"))),
            Ok(c) => {
                eprintln!("--col {c} 越界（列数 {}）", ds.cols());
                Err(EXIT_FAIL)
            }
            Err(_) => {
                eprintln!("--col 必须是非负整数：{s}");
                Err(EXIT_FAIL)
            }
        },
    }
}

/// 排序自检：① 结果是 `0..rows` 的置换；② 按列型真的有序
fn checks(ds: &Dataset, col: usize, order: &[usize], desc: bool) -> (bool, bool) {
    let mut seen = order.to_vec();
    seen.sort_unstable();
    seen.dedup();
    let perm = seen.len() == ds.rows && order.len() == ds.rows;
    let ordered = order.windows(2).all(|w| {
        let (a, b) = (w[0], w[1]);
        match &ds.data[col] {
            Column::Num(v) => {
                if desc {
                    v[a] >= v[b]
                } else {
                    v[a] <= v[b]
                }
            }
            Column::Text(v) => {
                if desc {
                    v[a] >= v[b]
                } else {
                    v[a] <= v[b]
                }
            }
        }
    });
    (perm, ordered)
}

fn uint(args: &[String], name: &str, default: usize) -> Result<usize, i32> {
    match value(args, name) {
        None => Ok(default),
        Some(s) => match s.parse::<usize>() {
            Ok(v) => Ok(v),
            Err(_) => {
                eprintln!("{name} 必须是非负整数：{s}");
                Err(EXIT_FAIL)
            }
        },
    }
}

fn value(args: &[String], name: &str) -> Option<String> {
    let i = args.iter().position(|a| a == name)?;
    args.get(i + 1).cloned()
}

fn flag(args: &[String], name: &str) -> bool {
    args.iter().any(|a| a == name)
}

/// 最小 JSON 字符串转义（只覆盖我们真正输出的字符集：引号 / 反斜杠 / 控制字符）
fn jstr(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for ch in s.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

fn print_help() {
    println!("doyah-studio-cli —— Doyah Studio Windows 侧无界面验证入口（§8.5.1）");
    println!();
    println!("用法：doyah-studio-cli <子命令> [参数] [--json]");
    println!();
    println!("已实现：");
    println!("  capabilities                     子命令表 + 退出码表 + 缺席清单");
    println!("  dataset summary  --rows N --cols M [--seed S]");
    println!(
        "  grid window      --rows N --cols M [--seed S] [--start S] [--len L] [--col C] [--desc]"
    );
    println!("  grid sort        --rows N --cols M [--seed S] --col C [--desc]");
    println!("  grid filter      --rows N --cols M [--seed S] --col C (--text T | --lo X --hi Y)");
    println!();
    println!("缺席（对侧有、本侧尚无等价物；调用即退出码 2）：见 `capabilities`");
    println!("退出码：0 通过 / 1 判红 / 2 未实现");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn json_escaping_covers_quote_backslash_and_control() {
        assert_eq!(jstr("a\"b"), "\"a\\\"b\"");
        assert_eq!(jstr("a\\b"), "\"a\\\\b\"");
        assert_eq!(jstr("a\nb"), "\"a\\nb\"");
        assert_eq!(jstr("a\u{1}b"), "\"a\\u0001b\"");
        assert_eq!(jstr("中文"), "\"中文\"");
    }

    #[test]
    fn flag_and_value_read_the_expected_slots() {
        let a: Vec<String> = ["grid", "sort", "--col", "2", "--desc"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        assert!(flag(&a, "--desc"));
        assert!(!flag(&a, "--asc"));
        assert_eq!(value(&a, "--col").as_deref(), Some("2"));
        assert_eq!(value(&a, "--nope"), None);
    }

    #[test]
    fn mac_only_entries_all_carry_a_reason() {
        assert!(!MAC_ONLY.is_empty());
        for (n, r) in MAC_ONLY {
            assert!(!n.is_empty());
            assert!(!r.is_empty(), "{n} 缺理由");
        }
    }

    #[test]
    fn sort_self_check_holds_and_permutation_is_real() {
        let ds = generate(200, 5, 7);
        let order = ds.sort_order(0, false);
        let (perm, ordered) = checks(&ds, 0, &order, false);
        assert!(perm && ordered);
        let bad = vec![0usize; 200]; // 全 0 ⇒ 不是置换
        let (perm2, _) = checks(&ds, 0, &bad, false);
        assert!(!perm2, "非置换必须被自检抓到");
    }

    #[test]
    fn window_cap_is_reported_not_silently_truncated() {
        assert!(WINDOW_ROW_CAP >= 1);
        let ds = generate(5000, 3, 3);
        let order: Vec<usize> = (0..ds.rows).collect();
        let w = ds.window(&order, 0, WINDOW_ROW_CAP);
        assert_eq!(w.rows.len(), WINDOW_ROW_CAP);
    }

    #[test]
    fn run_returns_documented_exit_codes() {
        assert_eq!(run(&["capabilities".to_string()]), EXIT_OK);
        assert_eq!(
            run(
                &["grid", "sort", "--rows", "50", "--cols", "4", "--col", "0"]
                    .iter()
                    .map(|s| s.to_string())
                    .collect::<Vec<_>>()
            ),
            EXIT_OK
        );
        assert_eq!(run(&["nope".to_string()]), EXIT_FAIL);
        assert_eq!(run(&["secret".to_string()]), EXIT_UNIMPLEMENTED);
        assert_eq!(
            run(&["grid", "sort", "--rows", "0"]
                .iter()
                .map(|s| s.to_string())
                .collect::<Vec<_>>()),
            EXIT_FAIL
        );
    }
}
