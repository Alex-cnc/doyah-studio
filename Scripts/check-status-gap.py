#!/usr/bin/env python3
"""判据：台账里「实现已 ✅ 但判据没跟上」的行必须为 0。

为什么要有这条（2026-11-02）：
v0.4.0 收口时，`FR-NTS-NOTE-FORMAT-001` 等 8 条判据格还空着（⬜），但 checkpoint 里写的是
「队列 13/14 已收口」—— 因为收口读的是**实现列**。同一件事在两列里各说各话，
最晚到 v1.0.0 门前才会以「总数对不上」的形态爆出来。这条判据把这种格间矛盾当场顶出来。

**覆盖声明（铁律 13）**
- 扫的：`Docs/Doyah产品开发计划任务清单-macOS.md` §3 台账**全部行**（`FR-` / `NFR-` / `AC-` 开头），
  逐行比「实现列」（第 6 格）与「判据列」（第 7 格）。
- 判红的：`实现 ✅` 且 `判据` 是 `⬜` 或 `🟡`。
- 不算的：`判据` 为 `—`（不适用）—— 单独计数并打印，不判红；
  `FR-RTR-*`（Retro 仓的跨仓条目）—— 不计，属覆盖外；
  反向情形（实现未绿而判据绿）—— **本判据不管**，由 `check-status-consistency.py` 覆盖。
- 覆盖不到：判据格写着 `✅` 但实际没有可跑用例的情况。本判据只查**格子形状**，
  不查「✅ 是否名副其实」—— 那是每条自己的证据文件与 `verify-all.sh` 的活。

**负例（铁律 14）**：`--self-test` 用四个夹具：全绿 / 一条实现✅判据⬜ / 一条实现✅判据🟡 /
判据为 `—`。前两个必须判红、第三必红、第四必须不红。自检不过就以 rc=2 退出。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LEDGER = ROOT / "Docs" / "Doyah产品开发计划任务清单-macOS.md"

ID_RE = re.compile(r"^(FR|NFR|AC)-[A-Z0-9]+-")


def scan(text: str) -> tuple[list[tuple[str, str, str]], list[str], int]:
    """返回 (缺口行, 不适用行, 扫过的行数)。

    缺口行 = (编号, 模块, 判据格原文)；不适用行 = 编号列表（判据是 `—`）。
    """
    rows: list[list[str]] = []
    inside = False
    for line in text.split("\n"):
        if line.startswith("## 3"):
            inside = True
            continue
        if inside and line.startswith("## "):
            break
        if not inside or not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.split("|")][1:-1]
        if len(cells) < 7 or not ID_RE.match(cells[0]):
            continue
        rows.append(cells)

    gaps: list[tuple[str, str, str]] = []
    na: list[str] = []
    scanned = 0
    for c in rows:
        rid, module, impl, judge = c[0], c[2], c[5], c[6]
        if "FR-RTR-" in rid:          # 跨仓条目，覆盖外
            continue
        scanned += 1
        if judge.startswith("—"):
            na.append(rid)
            continue
        if impl.startswith("✅") and not judge.startswith("✅"):
            gaps.append((rid, module, judge[:6] or "（空）"))
    return gaps, na, scanned


def load() -> str:
    if not LEDGER.exists():
        print(f"✗ 找不到台账：{LEDGER}")
        sys.exit(2)
    return LEDGER.read_text(encoding="utf-8")


# ── 自检夹具（负例必须判红）───────────────────────────────────────────────
FIXTURE_HEAD = "## 3 需求状态台账\n\n| 编号 | 一句话 | 模块 | 层次 | 优先级 | 实现 | 判据 | 版本 | 版本口径 |\n|---|---|---|---|---|---|---|---|---|\n"
FIXTURE_GREEN = FIXTURE_HEAD + "| FR-AAA-XX-YY-001 | a | m | l | p | ✅ | ✅ | v0.1.0-alpha | — |\n"
FIXTURE_GAP_BLANK = FIXTURE_HEAD + "| FR-AAA-XX-YY-001 | a | m | l | p | ✅ | ⬜ | v0.1.0-alpha | — |\n"
FIXTURE_GAP_HALF = FIXTURE_HEAD + "| FR-AAA-XX-YY-001 | a | m | l | p | ✅ | 🟡 | v0.1.0-alpha | — |\n"
FIXTURE_NA = FIXTURE_HEAD + "| FR-AAA-XX-YY-001 | a | m | l | p | ✅ | — | v0.1.0-alpha | — |\n"


def self_test() -> int:
    cases = [
        ("全绿", FIXTURE_GREEN, 0),
        ("实现✅ 判据⬜ 必红", FIXTURE_GAP_BLANK, 1),
        ("实现✅ 判据🟡 必红", FIXTURE_GAP_HALF, 1),
        ("判据为 — 不算缺口", FIXTURE_NA, 0),
    ]
    ok = True
    for name, text, want in cases:
        gaps, _, _ = scan(text)
        got = len(gaps)
        mark = "✓" if got == want else "✗"
        if got != want:
            ok = False
        print(f"  {mark} {name}：期望 {want} 条缺口，实得 {got}")
    print("✅ 自检通过（4 例）" if ok else "✗ 自检失败：判据本身的判断不可信")
    return 0 if ok else 2


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return self_test()

    gaps, na, scanned = scan(load())
    print(f"扫描面：台账 §3 全部行，跳过 `FR-RTR-*` ⇒ 实扫 {scanned} 行"
          f"（判据为 `—` 的 {len(na)} 行按不适用计数，不判红）")
    if not gaps:
        print("✅ 无「实现 ✅ 判据未跟上」的行")
        return 0
    print(f"❌ 有 {len(gaps)} 行实现已 ✅、判据还没跟上：")
    for rid, module, judge in gaps:
        print(f"   {rid:28} 判据 {judge:4} · {module}")
    print("   —— 补判据 = 点名本仓已有测试 + 跑一次读数；不许把实现列当收口标准。")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
