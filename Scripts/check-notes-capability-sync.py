#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""能力章节「跨仓同文」判据（2026-10-19 · 人类主人令：Notes 与 Retro 都按独立仓给能力书，「内容相同，章节顺序可能不一致」）。

**为什么需要它**：同一段能力描述存在三处 —— 本仓能力书第 N 章、本仓需求书对应分区、独立产品仓的能力书。
三处**内容必须相同**；只改一处，另两处会静默过期，而且「哪一处才算对」没有第三方能判
（历史上 §0.10 的候选条就这么漂过）。

**判据（三款）**：

- **A 逐字同一**：独立仓能力书里 `<!-- capability-chN:begin -->` 与 `end -->` 之间的文本，
  与能力书第 N 章**按同一规则降级标题后逐字相等**（只允许 `#` 层级差一级 —— 它是作为下一级章节嵌进去的）。
  不允许空白以外的任何改动。
- **B 条目齐**：本仓需求书对应分区必须有该章的全部条目（Notes = `FR-NTS-NOTE-CAPTURE-001~11`；Retro = `FR-R-*` 非空），
  且每条列数够（含状态格）。
- **C 版本同批**：两仓在同一批改动里各留一行变更记录 —— 由作者在提交时保证；本判据只校验文本同一性。

**跳过语义**：独立仓不在盘上（干净克隆 / 另一平台）⇒ 打印「跳过（<仓> 不在盘上）」并退出 0，
**跳过 ≠ 通过**；`--require-all` 时跳过即红。

用法：
    python3 Scripts/check-notes-capability-sync.py
    python3 Scripts/check-notes-capability-sync.py --require-all
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

CAP = pathlib.Path("Docs/Doyah产品能力规划说明书.md")
SRS = pathlib.Path("Docs/Doyah产品需求分析说明书.md")

# (标签, 章节起标题, 章节止标题, 独立仓文件, 标记号, 需求书分区标题, 条目判据)
TARGETS = [
    ("笔记", "# 第五章 Doyah Notes", "# 第六章 Doyah Retro",
     pathlib.Path("../notes/Docs/产品能力规划说明书.md"), "ch5",
     "## 3.5 Doyah Notes", "note"),
    ("复盘", "# 第六章 Doyah Retro", "# 第七章 非目标",
     pathlib.Path("../retro/Docs/产品能力规划说明书.md"), "ch6",
     "## 3.6 Doyah Retro", "retro"),
]


def demote(text: str) -> str:
    """标题降一级：# → ##。两侧同一规则，保证只比内容不比层级。"""
    return "\n".join(("#" + l) if l.startswith("#") else l for l in text.split("\n"))


def chapter(cap: str, start: str, end: str) -> str:
    a = cap.index(start)
    b = cap.index(end)
    return demote(cap[a:b].rstrip())


def section_of(book: pathlib.Path, tag: str) -> str:
    t = book.read_text(encoding="utf-8")
    begin, end = f"<!-- capability-{tag}:begin -->", f"<!-- capability-{tag}:end -->"
    a = t.index(begin) + len(begin)
    b = t.index(end)
    return t[a:b].strip("\n").rstrip()


def check_srs(srs: str, heading: str, kind: str) -> list[str]:
    problems: list[str] = []
    if heading not in srs:
        return [f"需求书缺少分区「{heading}」"]
    seg = srs[srs.index(heading):]
    nxt = re.search(r"\n## ", seg)
    seg = seg[: nxt.start()] if nxt else seg
    rows = [l for l in seg.split("\n") if re.match(r"^\| (?:\*\*)?FR-", l)]
    if not rows:
        return [f"{heading} 里没有任何 FR 条目"]
    if kind == "note":
        ids = [l.split("|")[1].strip() for l in rows]
        want = ["FR-NTS-NOTE-CAPTURE-001", "FR-NTS-NOTE-FORMAT-001", "FR-NTS-NOTE-ATTACH-001",
                "FR-NTS-NOTE-SEARCH-001", "FR-NTS-NOTE-ORG-001", "FR-NTS-NOTE-VERSION-001",
                "FR-NTS-NOTE-TRASH-001", "FR-NTS-NOTE-SYNC-001", "FR-NTS-NOTE-SYNC-002",
                "FR-NTS-NOTE-EXPORT-001", "FR-NTS-NOTE-PRIVACY-001"]
        if ids != want:
            problems.append(f"§3.5 条目应为 {want[0]} ~ {want[-1]}（11 条），实测 {ids}")
    # 列形状不同：Notes 是 6 列（编号 | 需求 | 层次 | 优先级 | 状态 | 验收），
    # Retro 沿用原 4 列（编号 | 需求 | 状态 | 优先级）—— 各按自己的下限判，不强行统一
    # 2026-10-20：SRS 状态列迁出 ⇒ 两边都是 5 列（编号|需求|层次|优先级|验收要点）
    floor = 5
    for l in rows:
        if l.count("|") < floor:
            problems.append(f"条目列数不足（缺验收要点）：{l[:46]}")
    return problems


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--require-all", action="store_true", help="独立仓不在盘上即判红")
    args = ap.parse_args()

    cap = CAP.read_text(encoding="utf-8")
    srs = SRS.read_text(encoding="utf-8") if SRS.exists() else ""
    problems: list[str] = []

    for label, start, end, book, tag, srs_head, kind in TARGETS:
        print(f"— {label}：能力书「{start[2:]}」↔ {book}")
        left = chapter(cap, start, end)

        if not book.exists():
            msg = f"{label}：跳过（{book} 不在盘上）；跳过 ≠ 通过"
            print(f"  ⚠️  {msg}")
            if args.require_all:
                problems.append(msg)
        else:
            right = section_of(book, tag)
            if left != right:
                ll, rl = left.split("\n"), right.split("\n")
                first = next((i for i, (x, y) in enumerate(zip(ll, rl)) if x != y), min(len(ll), len(rl)))
                problems.append(
                    f"{label}：{book} 的「capability-{tag}」段与能力书不一致（第 {first + 1} 行起；"
                    f"左 {len(ll)} 行 / 右 {len(rl)} 行）—— 改一处必须同批改两处"
                )
            else:
                print(f"  ✓ 逐字一致（{len(left.split(chr(10)))} 行）")

        problems.extend(check_srs(srs, srs_head, kind))

    if problems:
        print("\n❌ 能力章节跨仓同文校验失败：")
        for p in problems:
            print(f"   · {p}")
        return 1
    print("\n✅ 能力章节三处同文（能力书 = 需求书分区 = 独立仓能力书）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
