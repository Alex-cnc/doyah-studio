//! 结果集查询的**可测内核**（platform/windows/App/src-tauri/src/query.rs）
//!
//! 为什么单独一层：命令（`lib.rs` 里的 `#[tauri::command]`）只能靠跑起窗口来验，而窗口在
//! CI / 无人值守里起不来 ⇒ 逻辑全放这里，**不依赖 tauri**，`cargo test` 就能判。
//!
//! 口径（§8.5.6-3 三候选之一「Rust 侧切片喂前端」）：
//! - 前端**不持有整份结果集**：一次只要 `len` 行；
//! - 数据集与**上一次的排序置换**都缓存（同键复用）—— 每次滚动都重生成 20 万 × 20 列是不可能接受的；
//! - `len` 有上限（`MAX_WINDOW_ROWS`）：窗口请求是外部输入，不设上限等于把「前端要多少给多少」写进实现。

use doyah_studio_core::{generate, Dataset};

/// 单次窗口取数的行数上限。超出即按上限截断（并在返回值里如实反映实际长度）。
pub const MAX_WINDOW_ROWS: usize = 4096;

#[derive(Debug, Clone, PartialEq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DatasetSummary {
    pub rows: usize,
    pub cols: usize,
    /// 列数据驻留字节**估算**（不是进程 RSS）—— 口径同 `Core::Column::bytes`。
    pub bytes: usize,
    /// 第一个文本列的下标（没有文本列则为 0）。
    pub text_col: usize,
    pub col_names: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GridWindowPayload {
    pub total: usize,
    pub start: usize,
    pub cells: Vec<Vec<String>>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ViewRequest {
    pub rows: usize,
    pub cols: usize,
    pub seed: u64,
    pub order_desc: bool,
    pub start: usize,
    pub len: usize,
}

/// 数据集缓存 + 排序置换缓存。`Mutex` 由调用方（tauri state）持。
#[derive(Debug, Default)]
pub struct ViewCache {
    dataset: Option<(usize, usize, u64, Dataset)>,
    order: Option<(u64, bool, Vec<usize>)>,
}

impl ViewCache {
    pub fn new() -> Self {
        Self::default()
    }

    fn dataset_for(&mut self, rows: usize, cols: usize, seed: u64) -> &Dataset {
        let hit = matches!(&self.dataset, Some((r, c, s, _)) if *r == rows && *c == cols && *s == seed);
        if !hit {
            self.dataset = Some((rows, cols, seed, generate(rows, cols, seed)));
            self.order = None; // 数据集换了，排序置换随之作废
        }
        &self.dataset.as_ref().expect("刚写入").3
    }

    /// 排序置换（`order_desc` 为 true 时降序）。按 (seed, desc) 缓存 —— 与真实实现一样，
    /// 排序是「一次算、多次切片」，不是「每滚动一次排一次」。
    fn order_for(&mut self, rows: usize, cols: usize, seed: u64, order_desc: bool) -> Vec<usize> {
        self.dataset_for(rows, cols, seed);
        let hit = matches!(&self.order, Some((s, d, _)) if *s == seed && *d == order_desc);
        if !hit {
            let dataset = &self.dataset.as_ref().expect("刚写入").3;
            // 排序键 = 第 0 列（与基准台同一口径）；置换由领域层给，本层不自己排。
            let order = dataset.sort_order(0, order_desc);
            self.order = Some((seed, order_desc, order));
        }
        self.order.as_ref().expect("刚写入").2.clone()
    }

    pub fn summary(&mut self, rows: usize, cols: usize, seed: u64) -> DatasetSummary {
        let dataset = self.dataset_for(rows, cols, seed);
        DatasetSummary {
            rows: dataset.rows,
            cols: dataset.cols(),
            bytes: dataset.bytes(),
            text_col: dataset.first_text_col().unwrap_or(0),
            col_names: dataset.columns.clone(),
        }
    }

    pub fn window(&mut self, request: &ViewRequest) -> GridWindowPayload {
        let order = self.order_for(request.rows, request.cols, request.seed, request.order_desc);
        let total = order.len();
        if request.start >= total || request.len == 0 {
            return GridWindowPayload { total, start: request.start.min(total), cells: Vec::new() };
        }
        let len = request.len.min(MAX_WINDOW_ROWS).min(total - request.start);
        let dataset = &self.dataset.as_ref().expect("上面取过").3;
        // 领域层负责实体化：给它行索引置换 + 窗口区间，它回一张只有这么多行的表。
        let window = dataset.window(&order[request.start..request.start + len], 0, len);
        debug_assert_eq!(window.rows.len(), len);
        GridWindowPayload { total, start: request.start, cells: window.rows }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request(start: usize, len: usize, order_desc: bool) -> ViewRequest {
        ViewRequest { rows: 50, cols: 7, seed: 7, order_desc, start, len }
    }

    #[test]
    fn 概要给出列名与列型规则() {
        let mut cache = ViewCache::new();
        let summary = cache.summary(50, 7, 7);
        assert_eq!(summary.rows, 50);
        assert_eq!(summary.cols, 7);
        assert_eq!(summary.col_names.len(), 7);
        // 列名规则与 Core 一致：每 5 列的第 5 列是文本列。
        assert_eq!(summary.col_names[0], "metric_0");
        assert_eq!(summary.col_names[4], "label_4");
        assert_eq!(summary.text_col, 4);
        assert!(summary.bytes > 0);
    }

    #[test]
    fn 窗口只取要的那几行() {
        let mut cache = ViewCache::new();
        let payload = cache.window(&request(3, 4, false));
        assert_eq!(payload.total, 50);
        assert_eq!(payload.start, 3);
        assert_eq!(payload.cells.len(), 4);
        for row in &payload.cells {
            assert_eq!(row.len(), 7);
            assert!(!row[0].is_empty());
        }
    }

    #[test]
    fn 越界与零长度窗口返回空片而不是报错() {
        let mut cache = ViewCache::new();
        assert!(cache.window(&request(50, 4, false)).cells.is_empty());
        assert!(cache.window(&request(0, 0, false)).cells.is_empty());
        // start 越界时如实地把 start 收到 total（不假装取到了）
        assert_eq!(cache.window(&request(999, 4, false)).start, 50);
    }

    #[test]
    fn 长度有上限() {
        let mut cache = ViewCache::new();
        let payload = cache.window(&ViewRequest { rows: 50, cols: 3, seed: 1, order_desc: false, start: 0, len: 10_000 });
        assert_eq!(payload.cells.len(), 50, "不大于总行数");
        let payload = cache.window(&ViewRequest { rows: 50_000, cols: 3, seed: 1, order_desc: false, start: 0, len: 10_000 });
        assert_eq!(payload.cells.len(), MAX_WINDOW_ROWS, "截断到上限");
    }

    #[test]
    fn 升序降序给出不同窗口() {
        let mut cache = ViewCache::new();
        let asc = cache.window(&request(0, 3, false));
        let desc = cache.window(&request(0, 3, true));
        assert_ne!(asc.cells[0][0], desc.cells[0][0], "第 0 列是排序键，两个方向的首行不该相同");
    }

    #[test]
    fn 同键复用缓存且换数据集即作废() {
        let mut cache = ViewCache::new();
        let first = cache.window(&request(0, 2, false));
        let again = cache.window(&request(0, 2, false));
        assert_eq!(first, again, "同 seed 同窗口必须逐字一致（确定性）");
        let other = cache.window(&ViewRequest { rows: 10, cols: 7, seed: 7, order_desc: false, start: 0, len: 2 });
        assert_eq!(other.total, 10, "换了规模即换数据集");
    }
}
