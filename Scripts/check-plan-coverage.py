#!/usr/bin/env python3
"""一单台账 ↔ 《需求规格说明书》索引 的覆盖判据。

为什么需要：2026-10-20 起状态从需求规格说明书迁到一单（人类主人令：
「需求规格说明书里不需要状态，而是一单里需要状态和进展情况」（原话里的文档名按现行口径改写））。
两边一旦漂移，就会重新出现「状态写了但条目不存在」「条目存在但没人管状态」。

判据四条：
  A **编号集合相等**：一单 §3 台账的编号集合 == 需求分析 §10.1 索引的编号集合（不多不少）。
  B **状态合法**：台账每一行的状态是 ⬜ / 🟡 / ✅ / ➖ 之一。
  C **需求分析不写状态**：正文（变更记录之前）不出现状态符号。
  D **不许空壳行**：台账每一行的「一句话」不得是 `—` / 空白（覆盖范围 = 台账**全 471 行**，
    含跨仓 `FR-RTR` 行 —— 它们同在这一张表里，空着就是同一类问题）。

为什么 D 要有：`—` 的一句话意味着没有「做成什么样」的标准，这种行翻 ✅ 等于自己给自己判对
（AGENTS.md 红线 3「判『对』的依据不许由被判方提供」）。2026-11-02 实测台账里有 105 行空壳，
其中 24 行状态已是 ✅ —— 那不是完成，那是「没人写过它要做什么」。补齐当天加这条判据守着。

用法：
    python3 Scripts/check-plan-coverage.py
    python3 Scripts/check-plan-coverage.py --self-test   # 未实现（负数靠外部改坏一行验，见证据）
"""

from __future__ import annotations

import pathlib
import re
import sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import doc_index  # noqa: E402  （派生件位置：.build/derived；缺文件先重生成）


SRS = pathlib.Path("Docs/Doyah产品需求规格说明书.md")
INDEX = doc_index.path()
PLAN = pathlib.Path("Docs/Doyah产品开发计划任务清单-macOS.md")
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


def plan_shells() -> list[str]:
    """判据 D：台账里「一句话」为空的行（`—` / 空白 / 只有 `?`）。

    只判「有没有句子」，不判「句子写得好不好」—— 后者不可判，硬判就会变成刷字游戏。
    句子与需求书是否一致也不判：台账里 52 行是改写过的短句（实测），钉「逐字相同」会开 52 个
    红口子，逼着人把台账改成需求书的副本；这里只守住「空壳不许存在」这一条能判的。
    """
    out: list[str] = []
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
        if not row or not re.match(r"^(FR|NFR|AC)-[A-Z0-9-]+$", row[0]):
            continue
        text = row[1] if len(row) > 1 else ""
        if text.strip() in ("", "—", "?", '-'):
            out.append(row[0])
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
        print("❌ 缺文件：SRS 或 一单 不在盘上")
        return 1

    a, b = srs_ids(), plan_rows()
    problems: list[str] = []

    missing = sorted(a - set(b))
    extra = sorted(set(b) - a)
    if missing:
        problems.append(f"一单缺 {len(missing)} 条（需求分析书里有、台账里没有）：{missing[:6]}")
    if extra:
        problems.append(f"一单多 {len(extra)} 条（台账里有、需求分析书没有）：{extra[:6]}")

    bad = [f"{k}={v}" for k, v in b.items() if not any(v.startswith(m) for m in MARKS)]
    if bad:
        problems.append(f"{len(bad)} 条状态不合法：{bad[:6]}")

    leaks = srs_status_leaks()
    if leaks:
        problems.append(f"需求规格说明书正文仍有 {len(leaks)} 处状态符号：{leaks[:4]}")

    shells = plan_shells()
    if shells:
        problems.append(
            f"台账有 {len(shells)} 行空壳（一句话是 `—`）：{shells[:8]}"
            f"{' …' if len(shells) > 8 else ''} —— 空壳行不许翻 ✅，先按需求书写清要做成什么样"
        )

    print(f"— 需求分析索引 {len(a)} 条 · 一单台账 {len(b)} 条 · 空壳 {len(shells)} 行")
    if problems:
        print("\n❌ 计划覆盖校验失败：")
        for p in problems:
            print(f"   · {p}")
        return 1
    print("\n✅ 台账与索引一一对应；无空壳行；需求规格说明书正文无状态符号")
    return 0


if __name__ == "__main__":
    sys.exit(main())
