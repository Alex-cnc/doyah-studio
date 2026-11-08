# 冻结清单（Doyah 产品 · 四书）

> **当前基线：v1.2（20261108）**。活书是从这里复制出来干活的；漂移变大时由 `Scripts/check-frozen-sync.py` 提示人类「是否冻结成新版本」，他同意才跑 `Scripts/freeze-books.py`。冻结件是**快照**，不承担版本号唯一/头部版本格纪律（见 `Scripts/check-doc-versions.py` 的 `COVERAGE_EXEMPT`）。

## v1.2（20261108）— 当前基线

**对应软件版本：`beta1.2` · marketing `1.2.0`**（2026-11-08 主人令：冻结哪个版本，软件就出哪个版本；判据 `Scripts/check-release-freeze-parity.py`）

冻结说明：beta1.1 收官：多端点模型档位 + 今日界面/工作区/对话导航全部进书

- `Doyah产品需求规格说明书-v1.2-20261108.md` ← `Docs/Doyah产品需求规格说明书.md` · **2475 行** · sha256 `a2190f87c7ae2163` · 相对 v1.1-20261106 +12/−10 行
- `Doyah产品概要设计说明书-v1.2-20261108.md` ← `Docs/Doyah产品概要设计说明书.md` · **2499 行** · sha256 `2dd6c4adb6b38cf8` · 相对 v1.1-20261106 +56/−4 行
- `Doyah产品能力规划说明书-v1.2-20261108.md` ← `Docs/Doyah产品能力规划说明书.md` · **1788 行** · sha256 `e474b8f1fa1bcb98` · 相对 v1.1-20261106 +12/−2 行
- `Doyah产品详细设计说明书-macOS-v1.2-20261108.md` ← `Docs/Doyah产品详细设计说明书-macOS.md` · **2809 行** · sha256 `3cee8f08429d1981` · 相对 v1.1-20261106 +858/−8 行
- `Doyah产品详细设计说明书-Android-v1.2-20261108.md` ← `Docs/Doyah产品详细设计说明书-Android.md` · **188 行** · sha256 `b8e67fd24856b1c4` · 相对 v1.1-20261106 +1/−1 行
- `Doyah产品详细设计说明书-Linux-v1.2-20261108.md` ← `Docs/Doyah产品详细设计说明书-Linux.md` · **2007 行** · sha256 `71f05781061ce8f9` · 相对 v1.1-20261106 +5/−5 行
- `Doyah产品开发计划任务清单-macOS-v1.2-20261108.md` ← `Docs/Doyah产品开发计划任务清单-macOS.md` · **977 行** · sha256 `fcf69cd9b057fc82` · 相对 v1.1-20261106 +18/−2 行

- **纪律**：① 改活书 → 跑 `check-frozen-sync.py`（小差异正常，超阈值才提示冻结）；② 冻结 = 跑 `freeze-books.py --version vX.Y`，它自动复制 + 重写本清单 + `--strict` 自证；③ 旧版本文件保留，不覆盖（冻结史即目录列表）。
- **停用副本**：`~/.dsh/projects/DoyahStudio/Docs/` 已于 2026-10-26 停用，不是判据源。
