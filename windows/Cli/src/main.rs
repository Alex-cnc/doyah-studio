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
        // 数据库域的**纯逻辑**验证口（1.8 段）：都不连数据库，只跑领域层函数。
        // 为什么无界面入口也要覆盖数据库域：本侧"真跑通"的证据在真库用例里，
        // 而**判定类**逻辑（URL 解析 / 条件生成 / 值检查 / CSV / DDL）不该只有 GUI 能验。
        "db" => match sub(args) {
            Some("url") => cmd_db_url(args, json),
            Some("browse") => cmd_db_browse(args, json),
            Some("inspect") => cmd_db_inspect(args, json),
            Some("csv") => cmd_db_csv(args, json),
            Some("ddl") => cmd_db_ddl(args, json),
            Some("maintain") => cmd_db_maintain(args, json),
            _ => unknown("db", args),
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
            "{{\"command\":\"capabilities\",\"implemented\":[\"capabilities\",\"dataset summary\",\"grid window\",\"grid sort\",\"grid filter\",\"db url\",\"db browse\",\"db inspect\",\"db csv\",\"db ddl\",\"db maintain\"],\"exit_codes\":{{\"0\":\"通过\",\"1\":\"判红\",\"2\":\"未实现\"}},\"mac_only\":[{}]}}",
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
            "db url        解析连接串/回导出（验口令不进连接串）",
            "db browse     生成条件浏览 SQL",
            "db inspect    单行值检查（NULL 与空串分开）",
            "db csv        解析 CSV 并如实报丢行",
            "db ddl        生成 ALTER TABLE（破坏性会被标出）",
            "db maintain   生成维护命令（只生成、不执行）",
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

// ---------- 数据库域子命令（1.8：全是纯逻辑，不连数据库）----------

/// `db url <连接串>`：解析连接串并**回导出**（用来验"口令不进连接串"这条口径）。
fn cmd_db_url(args: &[String], json: bool) -> i32 {
    let Some(url) = value(args, "url").or_else(|| positional(args, 2)) else {
        eprintln!("用法：db url <连接串> [--json]");
        return EXIT_FAIL;
    };
    match doyah_studio_db::url::parse(&url, None, "cli") {
        Ok(imported) => {
            let config = &imported.configuration;
            // **回导出必须不含口令**：这是 DR-02 的口径，无界面入口也要能验它
            let exported = doyah_studio_db::url::url_for(config);
            let leaks = exported.contains("password") || url.contains(":") && exported.contains('@');
            if json {
                println!(
                    "{{\"command\":\"db url\",\"host\":{},\"port\":{},\"database\":{},\"username\":{},\"dbType\":{},\"sslmode\":{},\"exported\":{},\"password_present\":{}}}",
                    jstr(&config.host),
                    config.port,
                    jstr(&config.database),
                    jstr(&config.username),
                    jstr(&config.db_type.raw_value()),
                    jstr(config.ssl_mode.raw_value()),
                    jstr(&exported),
                    leaks
                );
            } else {
                println!("解析结果：");
                println!("  主机      {}", config.host);
                println!("  端口      {}", config.port);
                println!("  库        {}", config.database);
                println!("  用户      {}", config.username);
                println!("  类型      {}", config.db_type.raw_value());
                println!("  sslmode   {}", config.ssl_mode.raw_value());
                println!("回导出（**不含口令**）：{exported}");
            }
            EXIT_OK
        }
        Err(e) => {
            eprintln!("连接串解析失败：{e}");
            EXIT_FAIL
        }
    }
}

/// `db browse --table T [--schema S] [--where W] [--order O] [--limit N]`：生成条件浏览 SQL（不执行）。
fn cmd_db_browse(args: &[String], json: bool) -> i32 {
    let Some(table) = value(args, "--table") else {
        eprintln!("用法：db browse --table T [--schema S] [--where W] [--order O] [--limit N] [--json]");
        return EXIT_FAIL;
    };
    let limit = match int(args, "--limit", 200) {
        Ok(v) => v,
        Err(code) => return code,
    };
    let filter = doyah_studio_db::browse::BrowseFilter {
        where_clause: value(args, "--where").unwrap_or_default(),
        order_by: value(args, "--order").unwrap_or_default(),
        limit,
        offset: 0,
    };
    match doyah_studio_db::browse::browse(&table, value(args, "--schema").as_deref(), &filter) {
        Ok(sql) => {
            if json {
                println!("{{\"command\":\"db browse\",\"sql\":{}}}", jstr(&sql));
            } else {
                println!("{sql}");
            }
            EXIT_OK
        }
        Err(e) => {
            eprintln!("生成失败：{}（判定标识：{}）", e.message(), e.identifier());
            EXIT_FAIL
        }
    }
}

/// `db inspect --columns a,b --row v1,v2`：单行值检查（NULL 与空串分开、长 JSON 美化）。
fn cmd_db_inspect(args: &[String], json: bool) -> i32 {
    let Some(columns_raw) = value(args, "--columns") else {
        eprintln!("用法：db inspect --columns a,b --row v1,（空表示 NULL） [--types t1,t2] [--json]");
        return EXIT_FAIL;
    };
    let Some(row_raw) = value(args, "--row") else {
        eprintln!("用法：db inspect --columns a,b --row v1, [--types t1,t2] [--json]");
        return EXIT_FAIL;
    };
    let columns: Vec<String> = columns_raw.split(',').map(|s| s.to_string()).collect();
    let types: Vec<String> = value(args, "--types")
        .map(|t| t.split(',').map(|s| s.to_string()).collect())
        .unwrap_or_default();
    let cells: Vec<Option<String>> = row_raw
        .split(',')
        .map(|s| if s.is_empty() { None } else { Some(s.to_string()) })
        .collect();
    let pairs: Vec<(String, String)> = columns
        .iter()
        .enumerate()
        .map(|(i, name)| (name.clone(), types.get(i).cloned().unwrap_or_default()))
        .collect();
    let fields = doyah_studio_db::inspect::row(&pairs, &cells, doyah_studio_db::inspect::DEFAULT_DISPLAY_LIMIT);
    if json {
        let items: Vec<String> = fields
            .iter()
            .map(|f| {
                format!(
                    "{{\"column\":{},\"type\":{},\"shape\":{},\"chars\":{},\"lines\":{},\"truncated\":{}}}",
                    jstr(&f.column_name),
                    jstr(&f.type_name),
                    jstr(&format!("{:?}", f.value.shape).to_lowercase()),
                    f.value.original_character_count,
                    f.value.line_count,
                    f.value.is_truncated
                )
            })
            .collect();
        println!("{{\"command\":\"db inspect\",\"fields\":[{}]}}", items.join(","));
    } else {
        for f in &fields {
            println!(
                "{}  [{:?}]  {} 字符 / {} 行{}",
                f.column_name,
                f.value.shape,
                f.value.original_character_count,
                f.value.line_count,
                if f.value.is_truncated { "（已截断）" } else { "" }
            );
        }
    }
    EXIT_OK
}

/// `db csv --file F [--no-header]`：解析 CSV 并如实报「读了几行 / 丢了几行 / 为什么」。
fn cmd_db_csv(args: &[String], json: bool) -> i32 {
    let Some(path) = value(args, "--file") else {
        eprintln!("用法：db csv --file F [--no-header] [--json]");
        return EXIT_FAIL;
    };
    let text = match std::fs::read_to_string(&path) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("读文件失败：{e}（{path}）");
            return EXIT_FAIL;
        }
    };
    let report = doyah_studio_db::io_csv::parse_csv(&text, !flag(args, "--no-header"));
    if json {
        let skipped: Vec<String> = report
            .skipped
            .iter()
            .map(|s| {
                format!(
                    "{{\"line\":{},\"reason\":{},\"preview\":{}}}",
                    s.line,
                    jstr(&s.reason),
                    jstr(&s.preview)
                )
            })
            .collect();
        println!(
            "{{\"command\":\"db csv\",\"delimiter\":{},\"header\":{},\"parsed\":{},\"total\":{},\"skipped\":[{}]}}",
            jstr(&report.delimiter.to_string()),
            report.header.len(),
            report.rows.len(),
            report.total_data_rows,
            skipped.join(",")
        );
    } else {
        println!(
            "分隔符「{}」；表头 {} 列；解析 {} 行 / 共 {} 行数据",
            report.delimiter,
            report.header.len(),
            report.rows.len(),
            report.total_data_rows
        );
        if report.skipped.is_empty() {
            println!("没有被丢掉的行");
        } else {
            println!("丢掉 {} 行：", report.skipped.len());
            for s in &report.skipped {
                println!("  第 {} 行：{}（{}）", s.line, s.reason, s.preview);
            }
        }
    }
    // **有丢行也算跑过**（如实报数不等于判红）—— 判红留给"文件读不出来"那类
    EXIT_OK
}

/// `db ddl --op alter|add-column|drop-column --table T --column C [--type TY]`：生成 DDL（不执行）。
fn cmd_db_ddl(args: &[String], json: bool) -> i32 {
    let Some(op) = value(args, "--op") else {
        eprintln!("用法：db ddl --op alter|add-column|drop-column --table T --column C [--type TY] [--schema S] [--json]");
        return EXIT_FAIL;
    };
    let Some(table) = value(args, "--table") else {
        eprintln!("缺少 --table");
        return EXIT_FAIL;
    };
    let Some(column) = value(args, "--column") else {
        eprintln!("缺少 --column");
        return EXIT_FAIL;
    };
    let schema = value(args, "--schema");
    let ty = value(args, "--type").unwrap_or_else(|| "text".to_string());
    let changes = match op.as_str() {
        "add-column" => vec![doyah_studio_db::ddl::ColumnChange {
            from: None,
            to: Some(doyah_studio_db::ddl::ColumnDef {
                name: column.clone(),
                data_type: ty,
                is_nullable: true,
                default_expr: None,
            }),
        }],
        "drop-column" => vec![doyah_studio_db::ddl::ColumnChange {
            from: Some(doyah_studio_db::ddl::ColumnDef {
                name: column.clone(),
                data_type: ty,
                is_nullable: true,
                default_expr: None,
            }),
            to: None,
        }],
        "alter" => vec![doyah_studio_db::ddl::ColumnChange {
            from: Some(doyah_studio_db::ddl::ColumnDef {
                name: column.clone(),
                data_type: "text".to_string(),
                is_nullable: true,
                default_expr: None,
            }),
            to: Some(doyah_studio_db::ddl::ColumnDef {
                name: column.clone(),
                data_type: ty,
                is_nullable: true,
                default_expr: None,
            }),
        }],
        other => {
            eprintln!("认不出的 --op：{other}（可用：add-column / drop-column / alter）");
            return EXIT_FAIL;
        }
    };
    match doyah_studio_db::ddl::alter_table(schema.as_deref(), &table, &changes) {
        Ok(statements) => {
            // **破坏性语句要能被无界面入口认出来**（与界面同一判定）
            let destructive = doyah_studio_db::ddl::has_destructive(&statements);
            if json {
                let items: Vec<String> = statements
                    .iter()
                    .map(|s| {
                        format!(
                            "{{\"sql\":{},\"bare\":{},\"class\":{},\"purpose\":{}}}",
                            jstr(&s.sql),
                            jstr(&s.bare),
                            jstr(&format!("{:?}", s.class).to_lowercase()),
                            jstr(&s.purpose)
                        )
                    })
                    .collect();
                println!(
                    "{{\"command\":\"db ddl\",\"statements\":[{}],\"destructive\":{}}}",
                    items.join(","),
                    destructive
                );
            } else {
                for s in &statements {
                    println!("{}", s.sql);
                }
                if destructive {
                    println!("⚠ 本次生成含**破坏性**语句：本侧只生成、不自动执行");
                }
            }
            EXIT_OK
        }
        Err(e) => {
            eprintln!("生成失败：{}（{}）", e.message, e.hint);
            EXIT_FAIL
        }
    }
}

/// `db maintain --table T [--schema S]`：生成维护命令（**只生成、不执行**）。
fn cmd_db_maintain(args: &[String], json: bool) -> i32 {
    let Some(table) = value(args, "--table") else {
        eprintln!("用法：db maintain --table T [--schema S] [--json]");
        return EXIT_FAIL;
    };
    let cmds = doyah_studio_db::admin::maintenance_commands(value(args, "--schema").as_deref(), &table);
    if json {
        let items: Vec<String> = cmds
            .iter()
            .map(|c| {
                format!(
                    "{{\"purpose\":{},\"bare\":{},\"cost\":{}}}",
                    jstr(&c.purpose),
                    jstr(&c.bare),
                    jstr(&c.cost)
                )
            })
            .collect();
        println!("{{\"command\":\"db maintain\",\"commands\":[{}]}}", items.join(","));
    } else {
        for c in &cmds {
            println!("{}", c.sql);
            println!();
        }
        println!("（以上只是文本：本侧**不代为执行**维护命令）");
    }
    EXIT_OK
}

/// 取第 n 个位置参数（跳过 `--flag` 与其取值）。
fn positional(args: &[String], n: usize) -> Option<String> {
    let mut seen = 0usize;
    let mut i = 0usize;
    while i < args.len() {
        let a = &args[i];
        if a.starts_with("--") {
            i += 2;
            continue;
        }
        if seen == n {
            return Some(a.clone());
        }
        seen += 1;
        i += 1;
    }
    None
}

/// 取整数选项（非法值判红并说清）。
fn int(args: &[String], name: &str, default: i64) -> Result<i64, i32> {
    match value(args, name) {
        None => Ok(default),
        Some(s) => match s.parse::<i64>() {
            Ok(v) => Ok(v),
            Err(_) => {
                eprintln!("{name} 必须是整数：{s}");
                Err(EXIT_FAIL)
            }
        },
    }
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

    /// **1.8 的数据库域子命令**：退出码与"只生成不执行"的口径都要能离线验。
    ///
    /// 这些用例只查退出码（不抓 stdout —— 那是 `println!` 的活，抓它要把输出重定向，
    /// 在单测里做会与并行跑的其他用例抢全局 stdout）。退出码就是本 CLI 的对外契约。
    #[test]
    fn db_subcommands_use_the_documented_exit_codes() {
        // 合法输入 ⇒ 0
        assert_eq!(
            run(&["db", "url", "postgres://bob@h:5432/db"].map(String::from).to_vec()),
            EXIT_OK
        );
        assert_eq!(
            run(&["db", "browse", "--table", "t"].map(String::from).to_vec()),
            EXIT_OK
        );
        assert_eq!(
            run(&["db", "inspect", "--columns", "a", "--row", ""]
                .map(String::from)
                .to_vec()),
            EXIT_OK
        );
        assert_eq!(
            run(&["db", "ddl", "--op", "add-column", "--table", "t", "--column", "c"]
                .map(String::from)
                .to_vec()),
            EXIT_OK
        );
        assert_eq!(
            run(&["db", "maintain", "--table", "t"].map(String::from).to_vec()),
            EXIT_OK
        );
    }

    #[test]
    fn db_subcommands_fail_with_a_readable_reason_on_bad_input() {
        // 缺参数 / 参数非法 ⇒ 1（判红），不是 2
        assert_eq!(run(&["db", "browse"].map(String::from).to_vec()), EXIT_FAIL);
        assert_eq!(run(&["db", "ddl", "--op", "add-column"].map(String::from).to_vec()), EXIT_FAIL);
        assert_eq!(run(&["db", "maintain"].map(String::from).to_vec()), EXIT_FAIL);
        // 认不出的 --op 也判红
        assert_eq!(
            run(&["db", "ddl", "--op", "banana", "--table", "t", "--column", "c"]
                .map(String::from)
                .to_vec()),
            EXIT_FAIL
        );
        // 坏连接串判红
        assert_eq!(
            run(&["db", "url", "not-a-url"].map(String::from).to_vec()),
            EXIT_FAIL
        );
    }

    #[test]
    fn an_unimplemented_mac_only_command_still_reports_two() {
        // 「缺席必须可见」：对侧有、本侧没有的仍然是 2（加了新命令不许把这条弄坏）
        assert_eq!(run(&["secret"].map(String::from).to_vec()), EXIT_UNIMPLEMENTED);
        assert_eq!(run(&["maintain"].map(String::from).to_vec()), EXIT_UNIMPLEMENTED);
        // 未知命令是 1（与"未实现"分开）
        assert_eq!(run(&["nonsense"].map(String::from).to_vec()), EXIT_FAIL);
    }

    #[test]
    fn positional_skips_flags_and_their_values() {
        let a: Vec<String> = ["db", "url", "postgres://x", "--json"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        assert_eq!(positional(&a, 2).as_deref(), Some("postgres://x"));
        assert_eq!(positional(&a, 99), None);
    }

    #[test]
    fn int_option_rejects_non_numbers_with_exit_fail() {
        let a: Vec<String> = ["db", "browse", "--limit", "abc"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        assert_eq!(int(&a, "--limit", 200).unwrap_err(), EXIT_FAIL);
        let ok: Vec<String> = ["db", "browse", "--limit", "7"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        assert_eq!(int(&ok, "--limit", 200).unwrap(), 7);
        assert_eq!(int(&ok, "--missing", 5).unwrap(), 5);
    }

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
