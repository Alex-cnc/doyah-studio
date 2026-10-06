//! `grid-bench` —— 结果网格压力基准的**数据侧**（§8.5.6-3 的开工令第一件事）。
//!
//! 它做两件事：
//! 1. **测 Rust 侧**：合成数据集（默认 40 万行 × 20 列）的生成 / 排序 / 筛选 / 窗口取数 / 单元格访问延迟；
//! 2. **喂前端**：把同一份数据按前端能直接读的形状写盘（`grid.meta.json` + `grid.f64.bin`，
//!    文本列写成字典下标），供 `platform/windows/Bench/grid` 的前端基准台取数。
//!
//! 用法：
//! ```text
//! cargo run --release --bin grid-bench -- --rows 400000 --cols 20 \
//!     --data-dir ../Bench/grid/public/data --out ../Bench/grid/public/data/rust-result.json
//! ```
//! 退出码：0 = 跑通（判据：各阶段都产出非负读数、写盘成功）；2 = 参数/写盘错误。
//!
//! 口径（如实）：内存读数是**列数据字节估算**（不是进程 RSS）；延迟是**单次**读数（未做统计分布）。

use std::collections::HashMap;
use std::env;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::Instant;

use doyah_studio_core::dataset::{generate, Column, Dataset, XorShift64};
use doyah_studio_core::result_set::Window;

fn arg_val(args: &mut impl Iterator<Item = String>, name: &str) -> String {
    match args.next() {
        Some(v) => v,
        None => {
            eprintln!("参数 {} 缺少取值", name);
            std::process::exit(2);
        }
    }
}

fn main() {
    let mut rows: usize = 400_000;
    let mut cols: usize = 20;
    let mut seed: u64 = 20_260_928;
    let mut out: Option<PathBuf> = None;
    let mut data_dir: Option<PathBuf> = None;
    let mut use_stdout_only = false;

    let mut args = env::args().skip(1);
    while let Some(a) = args.next() {
        match a.as_str() {
            "--rows" => rows = arg_val(&mut args, "--rows").parse().unwrap_or_else(|_| die("--rows 必须是整数")),
            "--cols" => cols = arg_val(&mut args, "--cols").parse().unwrap_or_else(|_| die("--cols 必须是整数")),
            "--seed" => seed = arg_val(&mut args, "--seed").parse().unwrap_or_else(|_| die("--seed 必须是整数")),
            "--out" => out = Some(PathBuf::from(arg_val(&mut args, "--out"))),
            "--data-dir" => data_dir = Some(PathBuf::from(arg_val(&mut args, "--data-dir"))),
            "--stdout-only" => use_stdout_only = true,
            "--help" | "-h" => {
                println!("grid-bench --rows N --cols N [--seed N] [--out FILE] [--data-dir DIR] [--stdout-only]");
                return;
            }
            other => die(&format!("未知参数 {}", other)),
        }
    }
    if rows == 0 || cols == 0 {
        die("rows / cols 必须 > 0");
    }

    // ① 生成
    let t = Instant::now();
    let ds = generate(rows, cols, seed);
    let gen_ms = ms(t);
    let bytes = ds.bytes();

    // ② 排序（数值列降序，取第 1 列）
    let t = Instant::now();
    let sorted = ds.sort_order(1, true);
    let sort_ms = ms(t);
    debug_assert_eq!(sorted.len(), rows);

    // ③ 筛选（首个文本列等值；再补一个数值区间筛选）
    let text_col = ds.first_text_col();
    let t = Instant::now();
    let hits = match text_col {
        Some(c) => ds.filter_text(c, &ds.data[c].cell(7)),
        None => Vec::new(),
    };
    let filter_ms = ms(t);
    let t = Instant::now();
    let range_hits = ds.filter_num_range(0, 100_000.0, 200_000.0);
    let range_ms = ms(t);

    // ④ 窗口取数：200 个 64 行窗口（滚动时前端每帧要的就是这种形状）
    let t = Instant::now();
    let mut windows: Vec<Window> = Vec::with_capacity(200);
    let mut rng = XorShift64::new(0x5EED);
    let max_start = rows.saturating_sub(64);
    for _ in 0..200 {
        let start = if max_start == 0 { 0 } else { rng.next_in(max_start as u64) as usize };
        windows.push(ds.window(&sorted[start..], 0, 64));
    }
    let window_ms = ms(t);
    let window_rows: usize = windows.iter().map(|w| w.rows.len()).sum();

    // ⑤ 单元格访问：20 万次随机取数（滚动热路径的上界）
    let t = Instant::now();
    let mut checksum = 0usize;
    for _ in 0..200_000 {
        let r = rng.next_in(rows as u64) as usize;
        let c = rng.next_in(cols as u64) as usize;
        checksum = checksum.wrapping_add(ds.cell_text(r, c).len());
    }
    let cell_ms = ms(t);

    println!(
        "GRID_BENCH rows={} cols={} gen_ms={:.1} sort_ms={:.1} filter_ms={:.2} range_ms={:.2} window_ms={:.1} cell200k_ms={:.1} bytes={}",
        rows, cols, gen_ms, sort_ms, filter_ms, range_ms, window_ms, cell_ms, bytes
    );
    println!(
        "  · 排序命中 {} 行（置换长度核对 {}）/ 文本等值命中 {} 行 / 区间命中 {} 行 / 窗口实体化 {} 行 / 校验和 {}",
        sorted.len(),
        rows,
        hits.len(),
        range_hits.len(),
        window_rows,
        checksum
    );

    // ⑥ 喂前端：写数据（`grid.f64.bin` + `grid.meta.json`）
    if let Some(dir) = &data_dir {
        if let Err(e) = write_data_dir(&ds, dir) {
            eprintln!("写数据目录失败：{}", e);
            std::process::exit(2);
        }
        println!("  · 数据已写 {}（供前端基准台读）", dir.display());
    }

    // ⑦ 结果 JSON
    if !use_stdout_only {
        if let Some(path) = &out {
            let json = render_json(rows, cols, seed, gen_ms, sort_ms, filter_ms, range_ms, window_ms, cell_ms, bytes, hits.len(), range_hits.len(), window_rows);
            if let Err(e) = write_file(path, json.as_bytes()) {
                eprintln!("写结果 JSON 失败：{}", e);
                std::process::exit(2);
            }
            println!("  · 结果已写 {}", path.display());
        }
    }

    println!("RESULT: PASS");
}

fn die(msg: &str) -> ! {
    eprintln!("{}", msg);
    std::process::exit(2)
}

fn ms(t: Instant) -> f64 {
    t.elapsed().as_secs_f64() * 1000.0
}

#[allow(clippy::too_many_arguments)]
fn render_json(
    rows: usize,
    cols: usize,
    seed: u64,
    gen_ms: f64,
    sort_ms: f64,
    filter_ms: f64,
    range_ms: f64,
    window_ms: f64,
    cell_ms: f64,
    bytes: usize,
    text_hits: usize,
    range_hits: usize,
    window_rows: usize,
) -> String {
    format!(
        "{{\n  \"rows\": {},\n  \"cols\": {},\n  \"seed\": {},\n  \"genMs\": {:.1},\n  \"sortMs\": {:.1},\n  \"filterTextMs\": {:.2},\n  \"filterRangeMs\": {:.2},\n  \"window200Ms\": {:.1},\n  \"cell200kMs\": {:.1},\n  \"datasetBytes\": {},\n  \"textHits\": {},\n  \"rangeHits\": {},\n  \"windowRows\": {},\n  \"notes\": [\"内存读数为列数据字节估算（非进程 RSS）\", \"各阶段为单次读数、未做统计分布\", \"排序/筛选取行索引置换，不改动原数据\"]\n}}\n",
        rows, cols, seed, gen_ms, sort_ms, filter_ms, range_ms, window_ms, cell_ms, bytes, text_hits, range_hits, window_rows
    )
}

fn write_file(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir)?;
    }
    let mut f = fs::File::create(path)?;
    f.write_all(bytes)
}

/// 写 `grid.meta.json` 与 `grid.f64.bin`（文本列 → 字典下标，前端渲染时展开）
fn write_data_dir(ds: &Dataset, dir: &Path) -> std::io::Result<()> {
    fs::create_dir_all(dir)?;
    let mut dict: Vec<String> = Vec::new();
    let mut index: HashMap<String, f64> = HashMap::new();
    let mut kinds: Vec<&str> = Vec::with_capacity(ds.cols());
    for c in &ds.data {
        kinds.push(c.kind());
    }

    let mut flat: Vec<f64> = vec![0.0; ds.rows * ds.cols()];
    for (ci, col) in ds.data.iter().enumerate() {
        match col {
            Column::Num(v) => {
                for (ri, x) in v.iter().enumerate() {
                    flat[ri * ds.cols() + ci] = *x;
                }
            }
            Column::Text(v) => {
                for (ri, s) in v.iter().enumerate() {
                    let id = match index.get(s) {
                        Some(id) => *id,
                        None => {
                            let id = dict.len() as f64;
                            dict.push(s.clone());
                            index.insert(s.clone(), id);
                            id
                        }
                    };
                    flat[ri * ds.cols() + ci] = id;
                }
            }
        }
    }

    let mut bin: Vec<u8> = Vec::with_capacity(flat.len() * 8);
    for x in &flat {
        bin.extend_from_slice(&x.to_le_bytes());
    }
    write_file(&dir.join("grid.f64.bin"), &bin)?;

    let names = ds
        .columns
        .iter()
        .map(|n| format!("\"{}\"", n))
        .collect::<Vec<_>>()
        .join(", ");
    let kind_json = kinds
        .iter()
        .map(|k| format!("\"{}\"", k))
        .collect::<Vec<_>>()
        .join(", ");
    let dict_json = dict
        .iter()
        .map(|s| format!("\"{}\"", s))
        .collect::<Vec<_>>()
        .join(", ");
    let meta = format!(
        "{{\n  \"rows\": {},\n  \"cols\": {},\n  \"colNames\": [{}],\n  \"kinds\": [{}],\n  \"dict\": [{}]\n}}\n",
        ds.rows,
        ds.cols(),
        names,
        kind_json,
        dict_json
    );
    write_file(&dir.join("grid.meta.json"), meta.as_bytes())
}
