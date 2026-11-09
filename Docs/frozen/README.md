# 冻结清单（Doyah 产品 · 四书）

> **当前基线：v1.2（20261109）**。活书是从这里复制出来干活的；漂移变大时由 `Scripts/check-frozen-sync.py` 提示人类「是否冻结成新版本」，他同意才跑 `Scripts/freeze-books.py`。冻结件是**快照**，不承担版本号唯一/头部版本格纪律（见 `Scripts/check-doc-versions.py` 的 `COVERAGE_EXEMPT`）。

## v1.2（20261109）— 当前基线

冻结说明：beta1.1 收官：多端点模型档位 + 界面/工作区/对话导航进书；同日按主人令把 Linux / Windows 详设同步到同段（各 40 节）

- `Doyah产品需求规格说明书-v1.2-20261109.md` ← `Docs/Doyah产品需求规格说明书.md` · **2475 行** · sha256 `c2709b4bbbc4ac16` · 相对 v1.2-20261108 +2/−2 行
- `Doyah产品概要设计说明书-v1.2-20261109.md` ← `Docs/Doyah产品概要设计说明书.md` · **2500 行** · sha256 `df4bc08a7aacc60a` · 相对 v1.2-20261108 +2/−1 行
- `Doyah产品能力规划说明书-v1.2-20261109.md` ← `Docs/Doyah产品能力规划说明书.md` · **1788 行** · sha256 `dbab6e28c395423f` · 相对 v1.2-20261108 +2/−2 行
- `Doyah产品详细设计说明书-macOS-v1.2-20261109.md` ← `Docs/Doyah产品详细设计说明书-macOS.md` · **2838 行** · sha256 `a0703268daeac9da` · 相对 v1.2-20261108 +15/−7 行
- `Doyah产品详细设计说明书-Android-v1.2-20261109.md` ← `Docs/Doyah产品详细设计说明书-Android.md` · **188 行** · sha256 `b8e67fd24856b1c4` · 相对 v1.2-20261108 +0/−0 行
- `Doyah产品详细设计说明书-Linux-v1.2-20261109.md` ← `Docs/Doyah产品详细设计说明书-Linux.md` · **2186 行** · sha256 `a95adffe43ae88bf` · 相对 v1.2-20261108 +184/−5 行
- `Doyah产品开发计划任务清单-macOS-v1.2-20261109.md` ← `Docs/Doyah产品开发计划任务清单-macOS.md` · **978 行** · sha256 `a59e7b431b7144f8` · 相对 v1.2-20261108 +3/−1 行

- **纪律**：① 改活书 → 跑 `check-frozen-sync.py`（小差异正常，超阈值才提示冻结）；② 冻结 = 跑 `freeze-books.py --version vX.Y`，它自动复制 + 重写本清单 + `--strict` 自证；③ 旧版本文件保留，不覆盖（冻结史即目录列表）。
- **停用副本**：`~/.dsh/projects/DoyahStudio/Docs/` 已于 2026-10-26 停用，不是判据源。
