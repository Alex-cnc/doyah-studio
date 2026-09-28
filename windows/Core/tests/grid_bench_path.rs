//! 基准路径集成测试（小规模，`cargo test` 里跑得动）：
//! `generate → sort → filter → window` 这条链正是 `grid-bench` 与前端基准台共同依赖的取数面。
//! 40 万行 × 20 列的全量读数由闸门的基准项复跑，不进单测（单测要快）。

use doyah_studio_core::dataset::{generate, Column};

#[test]
fn bench_path_is_consistent_at_small_scale() {
    let rows = 5_000usize;
    let cols = 20usize;
    let ds = generate(rows, cols, 20260928);

    assert_eq!(ds.rows, rows);
    assert_eq!(ds.cols(), cols);

    // 排序：置换 + 真有序（数值列）
    let order = ds.sort_order(1, true);
    assert_eq!(order.len(), rows);
    if let Column::Num(v) = &ds.data[1] {
        for w in order.windows(2) {
            assert!(v[w[0]] >= v[w[1]], "降序被打断");
        }
    } else {
        panic!("列 1 应当是数值列");
    }

    // 窗口取数：内容与排序置换一致
    let w = ds.window(&order, 100, 32);
    assert_eq!(w.rows.len(), 32);
    assert_eq!(w.rows[0][1], ds.cell_text(order[100], 1));

    // 筛选：命中行全在原数据里、且计数与逐行扫描一致
    let text_col = ds.first_text_col().expect("应有文本列");
    let needle = ds.cell_text(11, text_col);
    let hits = ds.filter_text(text_col, &needle);
    let manual = (0..rows).filter(|&r| ds.cell_text(r, text_col) == needle).count();
    assert_eq!(hits.len(), manual);
    assert!(hits.iter().all(|&r| ds.cell_text(r, text_col) == needle));

    // 确定性：同 seed 同结果（基准可复跑的前提）
    let again = generate(rows, cols, 20260928);
    assert_eq!(ds.data, again.data);
}
