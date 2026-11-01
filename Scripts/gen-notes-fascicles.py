#!/usr/bin/env python3
"""生成 Notes 分册（4 本）到 ../notes/Docs/。

口径（人类主人 2026-11-01）：
- 分册 = 从全量四书**裁剪**，只裁剪不增删；条文与编号逐字一致，冲突以全量书为准；
- 除任务清单外，分册的一切（含 `[产品特有]` 条款）都**继承自全量书**，分册不许自造内容；
- 头部只允许「元信息表 + 收进来/不收的章清单 + 口径说明」，正文逐行必须能在全量书里找到
  （判据：`Scripts/check-book-subset.py` 的两根轴 —— 编号 ⊆ + 逐行 ⊆）。

用法：`python3 Scripts/gen-notes-fascicles.py [--check]`
`--check` 只比对不写盘，差异非空则 exit 1（供门禁用）。
"""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT.parent / "notes" / "Docs"

CAP = "Docs/Doyah产品能力规划说明书.md"
SRS = "Docs/Doyah产品需求规格说明书.md"
HLD = "Docs/Doyah产品概要设计说明书.md"
DDS_ANDROID = "Docs/Doyah产品详细设计说明书-Android.md"


def read(rel: str) -> list[str]:
    return (ROOT / rel).read_text(encoding="utf-8").split("\n")


def version(rel: str) -> str:
    m = re.search(r"v(\d+\.\d+\.\d+)", (ROOT / rel).read_text(encoding="utf-8"))
    return m.group(1) if m else "?"


def cut(rel: str, start: str, end: str | None = None) -> str:
    """按标题行裁段：[start, end)。end 为 None 时切到文末。"""
    lines = read(rel)
    s = next(i for i, l in enumerate(lines) if l.startswith(start))
    e = len(lines)
    if end:
        e = next((i for i, l in enumerate(lines[s + 1:], s + 1) if l.startswith(end)), len(lines))
    return "\n".join(lines[s:e]).rstrip() + "\n"


def frame(title: str, src: str, keep: str, drop: str, product_row: str) -> str:
    return f"""# {title}

| 项目 | 内容 |
|---|---|
| 产品 | {product_row} |
| 本册性质 | 分册 —— 自全量四书裁剪，**只裁剪不增删**；条文与编号逐字一致，冲突以全量书为准 |
| 派生自 | `doyah-studio/{src}` **v{version(src)}**（2026-11-01 裁剪） |
| 读者 | Notes 实现侧（安卓 / iOS / 鸿蒙）、验收侧、需求提出者 |
| 优先级 | 需求规格 > 概要设计 > 详细设计 > 现有代码（跨书冲突以全量书为准） |

**收进来的章**：{keep}

**不收的章（留在全量书）**：{drop}

> 口径：全量四书里 Agent / Studio / Notes / Retro 四个功能**写在一起**（PC 端一体），
> 本册只把 Notes 这一支裁出来，**骨架与正文一律照抄全量书**，不改条文。
> 本册没有任何自造内容 —— 连 `[产品特有]` 条款也是先写进全量书、再随裁剪进来；
> 生成器 `doyah-studio/Scripts/gen-notes-fascicles.py`，判据 `check-book-subset.py`（编号 ⊆ + 逐行 ⊆）。

---

"""


def build() -> dict[pathlib.Path, str]:
    out: dict[pathlib.Path, str] = {}

    cap_body = cut(CAP, "## 1.1 ", "## 3.1 ") + "\n" + cut(CAP, "## 5.1 ", "## 6.1 ") + "\n" + cut(CAP, "## 7.1 ")
    out[OUT / "Doyah Notes产品能力规划说明书.md"] = frame(
        "Doyah Notes产品能力规划说明书", CAP,
        "§1 文档分工 / 定位 / 原则 · §2 跨端等价 / 能力复用 / 数据归属 · §5.1 Notes 能力 · §5.2 待办能力 · §5.3 产品面（含 §5.3.3 [产品特有]）· §7.1 明确不做",
        "§3 Agent 执行内核（9 章）· §4 Studio 工作区与数据库 · §6 Retro · 版本流水",
        "**Doyah Notes**（独立产品：笔记 + 待办；移动端三端，安卓为基准端）",
    ) + cap_body

    srs_body = (cut(SRS, "## 1.1 ", "## 3.1 ") + "\n" + cut(SRS, "## 3.5 ", "## 3.6 ") + "\n"
                + cut(SRS, "## 4.1 ", "## 5.1 ") + "\n" + cut(SRS, "## 8.1 ", "## 9.1 "))
    out[OUT / "Doyah Notes产品需求规格说明书.md"] = frame(
        "Doyah Notes产品需求规格说明书", SRS,
        "§1 目的 / 读者 / 术语 / 层次标记 / 编码规范 / 维护约定 / 参考文档 / 平台与环境 / 条目格式 · §2 分工 / 背景 / 目标 / 范围 / 用户 / 运行环境 / 假设 / 合规 · **§3.5 Doyah Notes（26 条：功能 23 + [产品特有] 3）** · §4 非功能（九节）· §8 风险登记 / 待决项",
        "§3.1 共性需求 · §3.2 Agent · §3.3 工作区 · §3.4 数据库 · §3.6 Retro · §5 数据需求 · §6 接口需求 · §7 验收（发布门槛 / 智能体验收）· §9 追溯",
        "**Doyah Notes**（独立产品：笔记 + 待办；移动端三端，安卓为基准端）",
    ) + srs_body

    hld_body = (cut(HLD, "## 0. ", "## 2. ") + "\n" + cut(HLD, "## 5. ", "## 6. ") + "\n"
                + cut(HLD, "## 9. ", "## 10. ") + "\n" + cut(HLD, "## 11. ", "## 13. ") + "\n"
                + cut(HLD, "## 15. ", "## 16. "))
    out[OUT / "Doyah Notes产品概要设计说明书.md"] = frame(
        "Doyah Notes产品概要设计说明书", HLD,
        "§0 文档元信息 · §1 设计范围与边界 · §5 数据契约 · §9 错误处理与兜底 · §11 非功能设计约束 · §12 设计合规判据 · §13 变更与偏离 · **§15 笔记域契约（18 节不变量表，含 §15.18 [产品特有]）**",
        "§2 Agent 执行总则 · §3 组件契约（Studio 面）· §4 接口契约（Studio 面）· §6 状态机 · §7 关键流程 · §8 界面契约（Studio 面）· §10 被拒方案 · §16 Retro · §17–§21（追溯 / Agent 内核 / 补遗 / 全量索引 / 标准对照）",
        "**Doyah Notes**（独立产品：笔记 + 待办；移动端三端，安卓为基准端）",
    ) + hld_body

    dds_lines = read(DDS_ANDROID)
    body = "\n".join(dds_lines[1:]).lstrip("\n")
    out[OUT / "Doyah Notes产品详细设计说明书-Android.md"] = frame(
        "Doyah Notes产品详细设计说明书 · Android", DDS_ANDROID,
        "整本（§0 元信息与追溯矩阵 · §1 基线与禁止项 · §2 分层 · §3 关键契约 9 面 · §4 数据与状态 · §5 界面 · §6 错误 · §7 非功能 · §8 测试与判据 · §9 未实现位点 · §10 偏离处理）",
        "无删章（本端即全量详设的 Android 分册）；PC 端笔记实现在 Studio 全量详设里",
        "**Doyah Notes**（独立产品：笔记 + 待办；本册 = 安卓端，移动端基准端）",
    ) + body

    return out


def main() -> int:
    check = "--check" in sys.argv
    files = build()
    bad = 0
    for path, text in files.items():
        old = path.read_text(encoding="utf-8") if path.exists() else ""
        if old == text:
            print(f"= {path.name}（未变）")
            continue
        bad += 1
        if check:
            print(f"≠ {path.name}（盘上不是最新裁剪）")
        else:
            path.write_text(text, encoding="utf-8")
            print(f"✓ {path.name} 已重裁（{len(text.splitlines())} 行）")
    if check and bad:
        print(f"\n❌ {bad} 本分册落后于全量书 ⇒ 跑 `python3 Scripts/gen-notes-fascicles.py` 重裁")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
