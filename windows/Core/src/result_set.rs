//! 结果集取数：排序 / 筛选 / 窗口取数（**不改动原数据**，全部以行索引置换表示）。
//!
//! 形态（与 §8.5.6-3 的方向性结论一致）：**后端排序 + 窗口取数**，前端一次只拿它要渲染的那几十行
//! —— 而不是把 40 万行交给前端控件去 `SortDescriptions`。

use crate::dataset::{Column, Dataset};

/// 实体化窗口：前端拿到的就是它（列名 + 若干行的文本单元格）
#[derive(Clone, Debug, PartialEq)]
pub struct Window {
    pub columns: Vec<String>,
    pub rows: Vec<Vec<String>>,
}

impl Dataset {
    /// 按列排序，返回行索引置换（`desc = true` 降序）。文本列按字典序、数值列按数值序。
    pub fn sort_order(&self, col: usize, desc: bool) -> Vec<usize> {
        let mut idx: Vec<usize> = (0..self.rows).collect();
        match &self.data[col] {
            Column::Num(v) => idx.sort_by(|&a, &b| {
                let (x, y) = (v[a], v[b]);
                let o = if desc {
                    y.partial_cmp(&x)
                } else {
                    x.partial_cmp(&y)
                };
                o.unwrap_or(std::cmp::Ordering::Equal)
            }),
            Column::Text(v) => idx.sort_by(|&a, &b| {
                if desc {
                    v[b].cmp(&v[a])
                } else {
                    v[a].cmp(&v[b])
                }
            }),
        }
        idx
    }

    /// 文本列等值筛选（返回命中行索引，保持原序）
    pub fn filter_text(&self, col: usize, needle: &str) -> Vec<usize> {
        match &self.data[col] {
            Column::Num(_) => Vec::new(),
            Column::Text(v) => (0..self.rows).filter(|&r| v[r] == needle).collect(),
        }
    }

    /// 数值列区间筛选（闭区间）
    pub fn filter_num_range(&self, col: usize, lo: f64, hi: f64) -> Vec<usize> {
        match &self.data[col] {
            Column::Text(_) => Vec::new(),
            Column::Num(v) => (0..self.rows).filter(|&r| v[r] >= lo && v[r] <= hi).collect(),
        }
    }

    /// 窗口取数：按 `order` 里的行索引，从第 `start` 行起取 `len` 行（越界自动截断）。
    pub fn window(&self, order: &[usize], start: usize, len: usize) -> Window {
        let end = std::cmp::min(start + len, order.len());
        let slice = if start < end { &order[start..end] } else { &[] };
        let rows: Vec<Vec<String>> = slice
            .iter()
            .map(|&r| self.data.iter().map(|c| c.cell(r)).collect())
            .collect();
        Window {
            columns: self.columns.clone(),
            rows,
        }
    }

    /// 单位置取单元格（滚动时前端最热的路径）
    pub fn cell_text(&self, row: usize, col: usize) -> String {
        self.data[col].cell(row)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dataset::generate;

    #[test]
    fn sort_order_is_a_permutation_and_ordered() {
        let ds = generate(200, 5, 11);
        let asc = ds.sort_order(0, false);
        assert_eq!(asc.len(), 200);
        let mut seen = asc.clone();
        seen.sort_unstable();
        seen.dedup();
        assert_eq!(seen.len(), 200, "排序结果必须是 0..rows 的一个置换");
        if let Column::Num(v) = &ds.data[0] {
            for w in asc.windows(2) {
                assert!(v[w[0]] <= v[w[1]], "升序被打断");
            }
        }
    }

    #[test]
    fn sort_desc_is_reverse_of_asc_for_numeric() {
        let ds = generate(150, 5, 12);
        let asc = ds.sort_order(1, false);
        let desc = ds.sort_order(1, true);
        if let Column::Num(v) = &ds.data[1] {
            assert!(v[asc[0]] <= v[asc[149]]);
            assert!(v[desc[0]] >= v[desc[149]]);
        }
    }

    #[test]
    fn text_sort_is_lexicographic() {
        let ds = generate(120, 5, 13);
        let order = ds.sort_order(4, false);
        if let Column::Text(v) = &ds.data[4] {
            for w in order.windows(2) {
                assert!(v[w[0]] <= v[w[1]]);
            }
        }
    }

    #[test]
    fn filter_text_finds_exact_cells() {
        let ds = generate(300, 5, 14);
        let needle = ds.data[4].cell(7);
        let hits = ds.filter_text(4, &needle);
        assert!(hits.contains(&7));
        for &r in &hits {
            assert_eq!(ds.data[4].cell(r), needle);
        }
    }

    #[test]
    fn filter_num_range_all_in_range() {
        let ds = generate(300, 5, 15);
        let (lo, hi) = (100_000.0, 200_000.0);
        let hits = ds.filter_num_range(0, lo, hi);
        if let Column::Num(v) = &ds.data[0] {
            for &r in &hits {
                assert!(v[r] >= lo && v[r] <= hi);
            }
        }
    }

    #[test]
    fn filter_on_wrong_kind_is_empty_not_panic() {
        let ds = generate(50, 5, 16);
        assert!(ds.filter_text(0, "nope").is_empty());
        assert!(ds.filter_num_range(4, 0.0, 1.0).is_empty());
    }

    #[test]
    fn window_clamps_and_materializes() {
        let ds = generate(100, 5, 17);
        let order: Vec<usize> = (0..100).collect();
        let w = ds.window(&order, 10, 5);
        assert_eq!(w.rows.len(), 5);
        assert_eq!(w.columns.len(), 5);
        assert_eq!(w.rows[0][0], ds.data[0].cell(10));
        let tail = ds.window(&order, 98, 5);
        assert_eq!(tail.rows.len(), 2, "越界自动截断");
        let past = ds.window(&order, 500, 5);
        assert!(past.rows.is_empty());
    }

    #[test]
    fn cell_text_matches_window_content() {
        let ds = generate(20, 6, 18);
        let order: Vec<usize> = (0..20).collect();
        let w = ds.window(&order, 0, 3);
        assert_eq!(w.rows[1][2], ds.cell_text(1, 2));
    }
}
