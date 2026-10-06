//! 合成数据集（基准台用）：确定性、可按行列规模生成、贴近真实结果集的列型混合。
//!
//! 为什么要有它：§8.5.6-3 的网格压力基准要求「40 万行 × 20 列」这个量级，
//! 而真实库不总是可用 ⇒ 用**确定性**合成数据（同 seed 同结果，任何人可复跑）。
//! 这是基准的输入，不是业务数据模型。

const TEXT_WORDS: &[&str] = &[
    "alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota", "kappa",
    "lambda", "mu", "nu", "xi", "omicron", "pi", "rho", "sigma", "tau", "upsilon",
];

/// 一列：数值列或短文本列（真实结果集里最常见两类）
#[derive(Clone, Debug, PartialEq)]
pub enum Column {
    Num(Vec<f64>),
    Text(Vec<String>),
}

impl Column {
    pub fn len(&self) -> usize {
        match self {
            Column::Num(v) => v.len(),
            Column::Text(v) => v.len(),
        }
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    pub fn kind(&self) -> &'static str {
        match self {
            Column::Num(_) => "num",
            Column::Text(_) => "text",
        }
    }

    /// 单元格取文本（渲染侧真正拿到的东西）
    pub fn cell(&self, row: usize) -> String {
        match self {
            Column::Num(v) => format!("{:.4}", v[row]),
            Column::Text(v) => v[row].clone(),
        }
    }

    /// 该列驻留字节估算（`String` 按 24 字节头 + 内容；如实标「估算」，不是 RSS）
    pub fn bytes(&self) -> usize {
        match self {
            Column::Num(v) => v.len() * std::mem::size_of::<f64>(),
            Column::Text(v) => v.iter().map(|s| s.len() + 24).sum(),
        }
    }
}

/// 数据集：列名 + 列数据 + 行数
#[derive(Clone, Debug)]
pub struct Dataset {
    pub columns: Vec<String>,
    pub data: Vec<Column>,
    pub rows: usize,
}

impl Dataset {
    pub fn cols(&self) -> usize {
        self.data.len()
    }

    /// 驻留字节估算（列数据之和）
    pub fn bytes(&self) -> usize {
        self.data.iter().map(|c| c.bytes()).sum()
    }

    /// 第一个文本列的列号（筛选基准用；没有文本列时返回 None）
    pub fn first_text_col(&self) -> Option<usize> {
        self.data.iter().position(|c| matches!(c, Column::Text(_)))
    }
}

/// xorshift64*：确定性、零依赖的伪随机源（基准要可复跑，不能用系统随机）
#[derive(Clone, Debug)]
pub struct XorShift64(u64);

impl XorShift64 {
    pub fn new(seed: u64) -> Self {
        XorShift64(if seed == 0 { 0x9E37_79B9_7F4A_7C15 } else { seed })
    }

    pub fn next_u64(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.0 = x;
        x
    }

    pub fn next_in(&mut self, n: u64) -> u64 {
        if n == 0 {
            0
        } else {
            self.next_u64() % n
        }
    }

    pub fn next_f64(&mut self) -> f64 {
        (self.next_u64() >> 11) as f64 / (1u64 << 53) as f64
    }
}

/// 生成 `rows` × `cols` 的合成数据集。列型规则：每 5 列里第 5 列是短文本，其余数值。
pub fn generate(rows: usize, cols: usize, seed: u64) -> Dataset {
    let mut rng = XorShift64::new(seed);
    let mut names = Vec::with_capacity(cols);
    let mut data = Vec::with_capacity(cols);
    for c in 0..cols {
        if c % 5 == 4 {
            names.push(format!("label_{}", c));
            let mut v = Vec::with_capacity(rows);
            for _ in 0..rows {
                let w = TEXT_WORDS[rng.next_in(TEXT_WORDS.len() as u64) as usize];
                v.push(format!("{}-{:03}", w, rng.next_in(1000)));
            }
            data.push(Column::Text(v));
        } else {
            names.push(format!("metric_{}", c));
            let mut v = Vec::with_capacity(rows);
            for _ in 0..rows {
                v.push(rng.next_f64() * 1_000_000.0);
            }
            data.push(Column::Num(v));
        }
    }
    Dataset {
        columns: names,
        data,
        rows,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn same_seed_same_dataset() {
        let a = generate(64, 6, 42);
        let b = generate(64, 6, 42);
        assert_eq!(a.rows, b.rows);
        assert_eq!(a.columns, b.columns);
        assert_eq!(a.data, b.data);
    }

    #[test]
    fn different_seed_differs() {
        let a = generate(64, 6, 42);
        let b = generate(64, 6, 43);
        assert_ne!(a.data, b.data);
    }

    #[test]
    fn shape_and_column_kinds() {
        let ds = generate(10, 7, 1);
        assert_eq!(ds.rows, 10);
        assert_eq!(ds.cols(), 7);
        assert_eq!(ds.data[4].kind(), "text");
        assert_eq!(ds.data[6].kind(), "num");
        assert_eq!(ds.data[0].kind(), "num");
        assert_eq!(ds.first_text_col(), Some(4));
    }

    #[test]
    fn cell_text_is_rendered_text() {
        let ds = generate(3, 5, 7);
        assert_eq!(ds.data[0].cell(0).len() > 0, true);
        assert!(ds.data[0].cell(0).contains('.'));
        assert!(ds.data[4].cell(2).contains('-'));
    }

    #[test]
    fn bytes_estimate_is_positive_and_scales() {
        let small = generate(100, 5, 3);
        let big = generate(1_000, 5, 3);
        assert!(small.bytes() > 0);
        assert!(big.bytes() > small.bytes());
    }

    #[test]
    fn next_in_respects_bound() {
        let mut rng = XorShift64::new(9);
        for _ in 0..1000 {
            assert!(rng.next_in(7) < 7);
        }
        assert_eq!(rng.next_in(0), 0);
    }
}
