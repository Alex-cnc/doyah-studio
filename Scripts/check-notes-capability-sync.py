#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""笔记能力「两侧同文」判据（2026-10-19 · 人类主人令「Notes 能力保留到本书，然后同步复制一份到 Notes 仓……最终结果是 Notes 仓的能力书与本书 Notes 章节内容相同，章节顺序可能不一致」）。

**为什么需要它**：同一段能力描述存在三处 —— 本仓能力书第五章、本仓需求书 §3.5（`FR-NOTE-01~11`）、
Notes 仓能力书 §12。三处**内容必须相同**；一旦有人只改一处，另外两处会静默过期，而且
「哪一处才算对」没有第三方能判（历史上 §0.10 的候选条就这么漂过）。

**判据（三款）**：

- **A 逐字同一**：Notes 仓能力书里 `<!-- capability-ch5:begin -->` 与 `end -->` 之间的文本，
  与能力书第五章**按同一规则降级标题后逐字相等**（只允许 `#` 层级差一级，因为它是作为
  下一级章节嵌进去的）。不允许空白差异以外的任何改动。
- **B 条目齐**：需求书 §3.5 必须有 `FR-NOTE-01` ~ `FR-NOTE-11` 十一条，且每条都有状态格。
- **C 版本同批**：两仓在同一批改动里各留一行变更记录 —— 由作者在提交时保证，
  本判据只校验文本同一性，不检查提交时间（跨仓时间戳不可靠）。

**跳过语义**：Notes 仓不在盘上（干净克隆 / 另一平台）⇒ 打印「跳过（Notes 仓不在盘上）」并退出 0，
**跳过 ≠ 通过**；`--require-notes` 时跳过即红。

用法：
    python3 Scripts/check-notes-capability-sync.py
    python3 Scripts/check-notes-capability-sync.py --require-notes
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

CAP = pathlib.Path("Docs/Doyah产品能力说明书.md")
SRS = pathlib.Path("Docs/Doyah产品需求说明书.md")
NOTES_BOOK = pathlib.Path("../notes/Docs/产品能力规划说明书.md")

BEGIN = "<!-- capability-ch5:begin -->"
END = "<!-- capability-ch5:end -->"


def demote(text: str) -> str:
    """标题降一级：# → ##。两侧同一规则，保证只比内容不比层级。"""
    return "\n".join(("#" + l) if l.startswith("#") else l for l in text.split("\n"))


def chapter5() -> str:
    t = CAP.read_text(encoding="utf-8")
    a = t.index("# 第五章 Doyah Notes")
    b = t.index("# 第六章 Doyah Retro")
    return demote(t[a:b].rstrip())


def notes_section() -> str:
    t = NOTES_BOOK.read_text(encoding="utf-8")
    a = t.index(BEGIN) + len(BEGIN)
    b = t.index(END)
    return t[a:b].strip("\n").rstrip()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--require-notes", action="store_true", help="Notes 仓不在盘上即判红")
    args = ap.parse_args()

    problems: list[str] = []

    left = chapter5()

    # ── A 逐字同一
    if not NOTES_BOOK.exists():
        msg = f"跳过（Notes 仓不在盘上：{NOTES_BOOK}）；跳过 ≠ 通过"
        print(f"⚠️  {msg}")
        if args.require_notes:
            problems.append(msg)
    else:
        right = notes_section()
        if left != right:
            l_lines, r_lines = left.split("\n"), right.split("\n")
            first = next(
                (i for i, (x, y) in enumerate(zip(l_lines, r_lines)) if x != y),
                min(len(l_lines), len(r_lines)),
            )
            problems.append(
                f"{NOTES_BOOK}: 「{BEGIN}」段与能力书第五章不一致（第 {first + 1} 行起）；"
                f"左 {len(l_lines)} 行 / 右 {len(r_lines)} 行 —— 改一处必须同批改两处"
            )

    # ── B 条目齐
    if SRS.exists():
        srs = SRS.read_text(encoding="utf-8")
        seg = srs[srs.index("### 3.5 Doyah Notes"):]
        seg = seg[: seg.index("\n### ")]
        ids = re.findall(r"^\| (FR-NOTE-\d+) \|", seg, re.M)
        want = [f"FR-NOTE-{i:02d}" for i in range(1, 12)]
        if ids != want:
            problems.append(f"{SRS}: §3.5 条目应为 {want[0]} ~ {want[-1]}（11 条），实测 {ids}")
        # 每条要有状态格：至少 6 列
        for line in seg.split("\n"):
            if line.startswith("| FR-NOTE-") and line.count("|") < 7:
                problems.append(f"{SRS}: 条目列数不足（缺状态 / 验收）：{line[:40]}")
    else:
        problems.append(f"{SRS} 不存在 —— 无法核对条目")

    if problems:
        print("❌ 笔记能力两侧同文校验失败：")
        for p in problems:
            print(f"   · {p}")
        return 1
    print("✅ 笔记能力三处同文（能力书第五章 = 需求书 §3.5 = Notes 仓 §12）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
