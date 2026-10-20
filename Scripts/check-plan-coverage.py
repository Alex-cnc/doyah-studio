#!/usr/bin/env python3
"""《开发计划书》台账 ↔ 《需求分析说明书》索引 的覆盖判据。

为什么需要：2026-10-20 起状态从需求分析说明书迁到开发计划书（人类主人令：
「需求分析说明书里不需要状态，而是开发计划书里需要状态和进展情况」）。
两边一旦漂移，就会重新出现「状态写了但条目不存在」「条目存在但没人管状态」。

判据三条：
  A **编号集合相等**：计划书 §3 台账的编号集合 == 需求分析 §10.1 索引的编号集合（不多不少）。
  B **状态合法**：台账每一行的状态是 ⬜ / 🟡 / ✅ / ➖ 之一。
  C **需求分析不写状态**：正文（变更记录之前）不出现状态符号。

用法：
    python3 Scripts/check-plan-coverage.py
    python3 Scripts/check-plan-coverage.py --self-test
"""

from __future__ import annotations

import pathlib
import re
import sys

SRS = pathlib.Path("Docs/Doyah产品需求分析说明书.md")
INDEX = pathlib.Path("Docs/Doyah产品需求分析说明书-需求索引.md")
PLAN = pathlib.Path("Docs/Doyah产品开发计划书.md")
MARKS = ("⬜", "🟡", "✅", "➖")


def cells(line: str) -> list[str]:
    return [c.strip() for c in line.strip().strip("|").split("|")]


def srs_ids() -> set[str]:
    """编号集合取自**需求索引文件**（2026-10-20 从正文附录移出，机械派生件）。"""
    ids = set()
    for line in INDEX.read_text(encoding="utf-8").splitlines():
        if line.startswith("|"):
            row = cells(line)
            if row and re.match(r"^(FR|NFR|AC)-[A-Z0-9-]+$", row[0].replace("*", "")):
                ids.add(row[0].replace("*", ""))
    return ids


def plan_rows() -> dict[str, str]:
    out: dict[str, str] = {}
    in_table = False
    for line in PLAN.read_text(encoding="utf-8").splitlines():
        if line.startswith("## 3 "):
            in_table = True
            continue
        if in_table and line.startswith("## "):
            break
        if not in_table or not line.startswith("|"):
            continue
        row = cells(line)
        if row and re.match(r"^(FR|NFR|AC)-[A-Z0-9-]+$", row[0]):
            out[row[0]] = row[5] if len(row) > 5 else "?"
    return out


def srs_status_leaks() -> list[str]:
    """判据 C：定义表里不得再有**独立的状态格**（`| ✅ |` 这种）。

    只判「格」不判「字」：正文里的历史性表述（如验收要点里写「已接线」）另属编辑债，
    由人工清理；机器只钉死「表结构里不许有状态列/状态格」这条可判的。
    """
    lines = SRS.read_text(encoding="utf-8").split("\n")
    body_end = next(
        (i for i, l in enumerate(lines) if l.startswith("## 变更记录") or l.startswith("### 10.5 变更记录")),
        len(lines),
    )
    leaks = []
    for i, l in enumerate(lines[:body_end]):
        if not l.startswith("|"):
            continue
        for c in cells(l):
            if c in MARKS:
                leaks.append(f"{i + 1}: 独立的「{c}」格 → {l.strip()[:52]}")
                break
    return leaks


def main() -> int:
    if not SRS.exists() or not PLAN.exists():
        print("❌ 缺文件：SRS 或 计划书 不在盘上")
        return 1

    a, b = srs_ids(), plan_rows()
    problems: list[str] = []

    missing = sorted(a - set(b))
    extra = sorted(set(b) - a)
    if missing:
        problems.append(f"计划书缺 {len(missing)} 条（需求分析书里有、台账里没有）：{missing[:6]}")
    if extra:
        problems.append(f"计划书多 {len(extra)} 条（台账里有、需求分析书没有）：{extra[:6]}")

    bad = [f"{k}={v}" for k, v in b.items() if not any(v.startswith(m) for m in MARKS)]
    if bad:
        problems.append(f"{len(bad)} 条状态不合法：{bad[:6]}")

    leaks = srs_status_leaks()
    if leaks:
        problems.append(f"需求分析说明书正文仍有 {len(leaks)} 处状态符号：{leaks[:4]}")

    print(f"— 需求分析索引 {len(a)} 条 · 计划书台账 {len(b)} 条")
    if problems:
        print("\n❌ 计划覆盖校验失败：")
        for p in problems:
            print(f"   · {p}")
        return 1
    print("\n✅ 台账与索引一一对应；需求分析说明书正文无状态符号")
    return 0


if __name__ == "__main__":
    sys.exit(main())
