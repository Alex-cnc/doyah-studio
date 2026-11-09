# 冻结清单（Doyah 产品 · 四书）

> **当前基线：v1.3（20261109）**。活书是从这里复制出来干活的；漂移变大时由 `Scripts/check-frozen-sync.py` 提示人类「是否冻结成新版本」，他同意才跑 `Scripts/freeze-books.py`。冻结件是**快照**，不承担版本号唯一/头部版本格纪律（见 `Scripts/check-doc-versions.py` 的 `COVERAGE_EXEMPT`）。

## v1.3（20261109）— 当前基线

冻结说明：三书合一（能力规划书并入需求规格书）+ 多 Provider / IM 通道收口；冻结集改 6 份

- `Doyah产品需求规格说明书-v1.3-20261109.md` ← `Docs/Doyah产品需求规格说明书.md` · **4935 行** · sha256 `69f30d738a4b8764` · 相对 v1.3-20261109 +0/−0 行
- `Doyah产品概要设计说明书-v1.3-20261109.md` ← `Docs/Doyah产品概要设计说明书.md` · **2501 行** · sha256 `382c1f484cc5c39b` · 相对 v1.3-20261109 +0/−0 行
- `Doyah产品详细设计说明书-macOS-v1.3-20261109.md` ← `Docs/Doyah产品详细设计说明书-macOS.md` · **2839 行** · sha256 `897c085d915a0278` · 相对 v1.3-20261109 +0/−0 行
- `Doyah产品详细设计说明书-Android-v1.3-20261109.md` ← `Docs/Doyah产品详细设计说明书-Android.md` · **189 行** · sha256 `85851c2c1c5c51b1` · 相对 v1.3-20261109 +0/−0 行
- `Doyah产品详细设计说明书-Linux-v1.3-20261109.md` ← `Docs/Doyah产品详细设计说明书-Linux.md` · **2187 行** · sha256 `6b31dfcc6d7de567` · 相对 v1.3-20261109 +0/−0 行
- `Doyah产品详细设计说明书-Windows-v1.3-20261109.md` ← `Docs/Doyah产品详细设计说明书-Windows.md` · **511 行** · sha256 `206fe54f80e5ea8d` · 相对 v1.3-20261109 +1/−1 行

- **纪律**：① 改活书 → 跑 `check-frozen-sync.py`（小差异正常，超阈值才提示冻结）；② 冻结 = 跑 `freeze-books.py --version vX.Y`，它自动复制 + 重写本清单 + `--strict` 自证；③ 旧版本文件保留，不覆盖（冻结史即目录列表）。
- **停用副本**：`~/.dsh/projects/DoyahStudio/Docs/` 已于 2026-10-26 停用，不是判据源。
