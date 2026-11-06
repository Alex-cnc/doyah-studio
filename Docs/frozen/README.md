# 冻结清单（Doyah 产品 · 四书）

> **当前基线：v1.1（20261106）**。活书是从这里复制出来干活的；漂移变大时由 `Scripts/check-frozen-sync.py` 提示人类「是否冻结成新版本」，他同意才跑 `Scripts/freeze-books.py`。冻结件是**快照**，不承担版本号唯一/头部版本格纪律（见 `Scripts/check-doc-versions.py` 的 `COVERAGE_EXEMPT`）。

## v1.1（20261106）— 当前基线

冻结说明：beta1 里程碑基线（主人 2026-11-05 令：betaN ⟷ 冻结 v1.N 四书；beta2 冻结 v1.2.0）

- `Doyah产品需求规格说明书-v1.1-20261106.md` ← `Docs/Doyah产品需求规格说明书.md` · **2473 行** · sha256 `35a2c7e8020f5e18` · 相对 v1.0-20261025 +151/−73 行
- `Doyah产品概要设计说明书-v1.1-20261106.md` ← `Docs/Doyah产品概要设计说明书.md` · **2447 行** · sha256 `b871b42b93ee564c` · 相对 v1.0-20261025 +145/−60 行
- `Doyah产品能力规划说明书-v1.1-20261106.md` ← `Docs/Doyah产品能力规划说明书.md` · **1778 行** · sha256 `bf65658ebbdb22ad` · 相对 v1.0-20261025 +84/−21 行
- `Doyah产品详细设计说明书-macOS-v1.1-20261106.md` ← `Docs/Doyah产品详细设计说明书-macOS.md` · **1959 行** · sha256 `7c80404e548833cd` · 相对 v1.0-20261025 +340/−31 行
- `Doyah产品详细设计说明书-Android-v1.1-20261106.md` ← `Docs/Doyah产品详细设计说明书-Android.md` · **188 行** · sha256 `d03e382586d63ef2` · 相对 v1.0-20261101 +1/−1 行
- `Doyah产品开发计划任务清单-macOS-v1.1-20261106.md` ← `Docs/Doyah产品开发计划任务清单-macOS.md` · **961 行** · sha256 `cdfe1a3d96992f4a` · 相对 首版 +961/−0 行

- **纪律**：① 改活书 → 跑 `check-frozen-sync.py`（小差异正常，超阈值才提示冻结）；② 冻结 = 跑 `freeze-books.py --version vX.Y`，它自动复制 + 重写本清单 + `--strict` 自证；③ 旧版本文件保留，不覆盖（冻结史即目录列表）。
- **停用副本**：`~/.dsh/projects/DoyahStudio/Docs/` 已于 2026-10-26 停用，不是判据源。
