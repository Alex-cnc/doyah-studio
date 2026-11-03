#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""判据：一单 §7.1「智能体剩余 N 条」卡点表 = §3 台账里 `FR-AGT` 未双 ✅ 的号集合。

**为什么要有这条**（2026-11-03 真现场）：§7.1 是 2026-10-27 手抄的一张「谁卡在哪」摘要，
台账才是状态唯一源（铁律 12）。两条 `FR-AGT-LINK-EXT-001` / `-002` 在 2026-11-03 双 ✅ 收口后，
摘要里仍写着「无真 MCP 对端实例 / 装一个真 server 并把配置面点一遍」，另有两条仍写
「`model` 是空串、真端点未配」而该前提已被真调读数证伪 —— 同一件事两个说法，读摘要的人会去办
已经办完的事。**没有任何门禁盖住这张表**（`check-status-gap.py` 只比 §3 两列，
`check-status-consistency.py` 只扫其它文档的状态括注）。

**覆盖声明（铁律 13）**
- 扫的：`Docs/Doyah产品开发计划任务清单-macOS.md` §3 台账全部 `FR-AGT-*` 行（第 6 格实现 / 第 7 格判据），
  加 §7.1 那张表（按表头定位，要求表头同时含「卡点」与「需要人类主人做的一件事」）。
- 判红的：① 表头「剩余 N 条」≠ 表行数；② 表里点了号但该号在台账已双 ✅（收口了没下移）；
  ③ 台账里未双 ✅ 的 `FR-AGT` 号没出现在表里（不写就假装没这回事）；④ 表行的「卡点」格为空。
- 不算的：其它族（`FR-NTS-*` / `NFR-*` / `FR-STD-*` …）的卡点摘要 —— 它们没有 §7.1 这样的单一摘要表，
  本判据不替它们立规矩；「已收口留痕」子表（表头是「收口读数 / 提交」）**按表头跳过**，那里放已闭的号是合法的。
- 覆盖不到：卡点文字的**语义**（写的内容对不对、next_try 会不会过期）——本判据只判号集合与格子的存在，
  措辞与前提的真假仍由每一跳自己量、写进证据。

**空跑防护**：§3 台账行数 < 400 或 §7.1 表行数 < 5 ⇒ 判红（解析不到输入不许当通过）。

**负例（铁律 14）**：`--self-test` 5 例（全绿 / 已收口仍留表 / 表头数不符 / 未闭条目漏登 / 台账行数不足），
前四例凡该红必红、末例按空跑防护判红。

用法：
    python3 Scripts/check-blocker-table.py              # 校验（闸门）
    python3 Scripts/check-blocker-table.py --root <树>  # 夹具仓
    python3 Scripts/check-blocker-table.py --self-test  # 判据自己的证据

退出码：0 = 通过；1 = 判红；2 = 用法错 / 自检不过。
"""

from __future__ import annotations

import argparse
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LEDGER_REL = "Docs/Doyah产品开发计划任务清单-macOS.md"
LEDGER_FLOOR = 400
TABLE_FLOOR = 5

HEADING_RE = re.compile(r"^###\s*7\.1\s*智能体剩余\s*(\d+)\s*条")
AGT_RE = re.compile(r"^\|\s*`?(FR-AGT-[A-Z0-9-]+)`?\s*\|")
LEDGER_ID_RE = re.compile(r"^\|\s*`?(FR|NFR|AC)-[A-Z0-9]+-")


def cells(line: str) -> list[str]:
    return [c.strip() for c in line.strip().strip("|").split("|")]


def parse_ledger(text: str) -> list[list[str]]:
    rows: list[list[str]] = []
    inside = False
    for line in text.split("\n"):
        if line.startswith("## 3"):
            inside = True
            continue
        if inside and line.startswith("## "):
            break
        if inside and LEDGER_ID_RE.match(line):
            rows.append(cells(line))
    return rows


def parse_digest(text: str) -> tuple[int | None, list[tuple[str, str]]]:
    """返回 (表头声明的条数, [(号, 卡点格)])。"""
    lines = text.split("\n")
    heading: int | None = None
    start = -1
    for i, line in enumerate(lines):
        m = HEADING_RE.match(line)
        if m:
            heading = int(m.group(1))
            start = i
            break
    if start < 0:
        return None, []
    rows: list[tuple[str, str]] = []
    in_table = False
    for line in lines[start:]:
        if line.startswith("|"):
            head = cells(line)
            is_digest = any("卡点" in c for c in head) and any("需要人类主人" in c for c in head)
            if is_digest:
                in_table = True
                continue
            if not in_table:
                continue
            if all(set(c) <= set("-: ") for c in head):
                continue
            m = AGT_RE.match(line)
            if m:
                row = cells(line)
                rows.append((m.group(1), row[3] if len(row) > 3 else ""))
            continue
        if in_table and line.strip() == "":
            continue
        if in_table and not line.startswith("|"):
            in_table = False
    return heading, rows


def scan(root: Path, ledger_floor: int = LEDGER_FLOOR,
         table_floor: int = TABLE_FLOOR) -> tuple[list[str], dict[str, int | None]]:
    ledger = root / LEDGER_REL
    if not ledger.exists():
        return [f"[输入] 找不到 {LEDGER_REL}"], {}
    text = ledger.read_text(encoding="utf-8")
    rows = parse_ledger(text)
    stats: dict[str, int | None] = {"ledger_rows": len(rows)}
    problems: list[str] = []
    if len(rows) < ledger_floor:
        problems.append(f"[空跑防护] §3 台账只解析到 {len(rows)} 行、下限 {ledger_floor}")
    open_agt: list[str] = []
    for row in rows:
        if len(row) < 7 or not row[0].startswith("FR-AGT"):
            continue
        if not (row[5].startswith("✅") and row[6].startswith("✅")):
            open_agt.append(row[0])
    heading, digest = parse_digest(text)
    stats["heading"] = heading
    stats["digest_rows"] = len(digest)
    stats["open_agt"] = len(open_agt)
    if heading is None:
        problems.append("[§7.1] 找不到「### 7.1 智能体剩余 N 条」这一节")
        return problems, stats
    if len(digest) < table_floor:
        problems.append(f"[空跑防护] §7.1 卡点表只解析到 {len(digest)} 行、下限 {table_floor}")
    if heading != len(digest):
        problems.append(f"[表头] 写「剩余 {heading} 条」，表里 {len(digest)} 行")
    listed = [rid for rid, _ in digest]
    dupes = sorted({r for r in listed if listed.count(r) > 1})
    if dupes:
        problems.append(f"[重复] 卡点表里同一号出现多次：{'、'.join(dupes)}")
    closed = set(r[0] for r in rows if len(r) > 6 and r[5].startswith("✅") and r[6].startswith("✅"))
    still = [r for r in listed if r in closed]
    if still:
        problems.append(f"[已收口仍留表] 这些号在 §3 已双 ✅：{'、'.join(still)}（移到「已收口留痕」）")
    missing = [r for r in open_agt if r not in listed]
    if missing:
        problems.append(f"[漏登] §3 未双 ✅ 但卡点表里没有：{'、'.join(missing)}")
    empty = [rid for rid, why in digest if not why]
    if empty:
        problems.append(f"[空格] 卡点格为空：{'、'.join(empty)}")
    return problems, stats


def self_test() -> int:
    ledger_row = "| {id} | 名 | 3.2 | 域 | 中 | {impl} | {crit} | v1.1+ | 口径 |"
    green = "\n".join(
        [
            "# 单",
            "## 3. 需求状态台账",
            "| 编号 | 需求 | 模块 | 域 | 优先级 | 实现 | 判据 | 版本 | 版本口径 |",
            "|---|---|---|---|---|---|---|---|---|",
            ledger_row.format(id="FR-AGT-A-001", impl="✅", crit="✅"),
            ledger_row.format(id="FR-AGT-B-002", impl="🟡", crit="🟡"),
            ledger_row.format(id="FR-AGT-C-003", impl="🟡", crit="✅"),
            ledger_row.format(id="FR-NTS-D-004", impl="🟡", crit="🟡"),
            "## 7. 阻塞",
            "### 7.1 智能体剩余 2 条：卡点与需要人类主人做的一件事（夹具）",
            "| 全号 | 一句话 | 现状 | 卡点 | 需要人类主人做的一件事 |",
            "|---|---|---|---|---|",
            "| `FR-AGT-B-002` | 甲 | 在盘 | 缺人工点验 | 点一次 |",
            "| `FR-AGT-C-003` | 乙 | 在盘 | 缺读数 | 给一条读数 |",
            "",
            "**已收口留痕**",
            "",
            "| 全号 | 一句话 | 收口读数 | 提交 |",
            "|---|---|---|---|",
            "| `FR-AGT-A-001` | 丙 | 3 例全绿 | abc123 |",
        ]
    )
    cases: list[tuple[str, str, int]] = []
    cases.append(("全绿", green, 0))
    cases.append(("已收口仍留表", green.replace("剩余 2 条", "剩余 3 条").replace(
        "| `FR-AGT-C-003` | 乙 | 在盘 | 缺读数 | 给一条读数 |",
        "| `FR-AGT-C-003` | 乙 | 在盘 | 缺读数 | 给一条读数 |\n| `FR-AGT-A-001` | 丙 | 在盘 | 已闭 | 无 |",
    ), 1))
    cases.append(("表头数不符", green.replace("剩余 2 条", "剩余 4 条"), 1))
    cases.append(("未闭漏登", green.replace(
        "| `FR-AGT-C-003` | 乙 | 在盘 | 缺读数 | 给一条读数 |", ""), 1))
    cases.append(("台账行数不足（空跑防护）", green, 1))
    failures = 0
    for index, (name, text, expect) in enumerate(cases, 1):
        tmp = Path(tempfile.mkdtemp(prefix="doyah-blocker-table-"))
        doc = tmp / LEDGER_REL
        doc.parent.mkdir(parents=True, exist_ok=True)
        doc.write_text(text, encoding="utf-8")
        # 前四例用 0 下限（夹具行数本来就少）；末例用真下限，验空跑防护真会红
        floors = (LEDGER_FLOOR, TABLE_FLOOR) if index == 5 else (0, 0)
        problems, _stats = scan(tmp, *floors)
        got = 1 if problems else 0
        ok = got == expect
        print(f"{'✅' if ok else '❌'} 例 {index} {name}：期望 rc={expect}，实得 {'红' if got else '绿'}"
              + ("" if ok else f"（问题 {problems[:2]}）"))
        failures += 0 if ok else 1
    print(f"自测通过（{len(cases) - failures}/{len(cases)} 例）" if not failures
          else f"自测失败（{failures}/{len(cases)} 例不过）")
    return 0 if not failures else 2


def main() -> int:
    parser = argparse.ArgumentParser(description="§7.1 卡点表 ↔ §3 台账号集合对账")
    parser.add_argument("--root", default=str(ROOT))
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    problems, stats = scan(Path(args.root))
    label = f"§3 台账 {stats.get('ledger_rows')} 行 / FR-AGT 未双 ✅ {stats.get('open_agt')} 条 / 卡点表 {stats.get('digest_rows')} 行 / 表头「剩余 {stats.get('heading')} 条」"
    if problems:
        for p in problems:
            print(f"❌ {p}")
        print(f"❌ §7.1 卡点表与台账不一致（{label}）")
        return 1
    print(f"✅ §7.1 卡点表 = 台账未闭集合（{label}）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
