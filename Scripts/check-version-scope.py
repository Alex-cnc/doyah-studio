#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""版本范围校验：《开发计划书》§3 台账的「版本 / 版本口径」两列。

为什么要这道判据（2026-10-20 人类主人令）：**"哪个版本做哪些需求"由版本计划说清**，
不需要在需求书正文里逐条写 `[alpha 不含]` 括注。旧做法（`Scripts/check-alpha-fr-dispositions.py`
+ `Scripts/alpha-fr-dispositions.json`）把「本版含不含」散落在需求行内，状态列迁出后
括注丢了一大半、账目与正文对不上 —— 换成单一来源：**台账一行一条需求，`版本` 列写归哪个
版本，`版本口径` 列写为什么**。

口径（四档，别自造）：
    v0.1.0-alpha   当前 alpha 范围            （`版本口径` 一律 `—`）
    v1.0           已确认的 v1.0 交付范围
    v1.1+          之后版本（含原 alpha 不含的条目）
    未排期          还没排（`版本口径` 必须写原因）

判据：
    ① 表在盘、表头是九列（编号…状态原值 / 版本 / 版本口径）
    ② `版本` 只能是上面四档之一（写错字 / 新造一档都判红）
    ③ `v0.1.0-alpha` 行的 `版本口径` 必须是 `—`；其它三档必须写清口径（空 / `—` 都判红）
    ④ 编号唯一、`状态` 首字符在 `✅🟡⬜➖` 里
    ⑤ 空跑防护：台账行数、alpha 条数各有一条下限（取不到输入不许当通过）

用法：
    python3 Scripts/check-version-scope.py                 # 真仓库
    python3 Scripts/check-version-scope.py --root <树>      # 夹具 / 其它仓
    python3 Scripts/check-version-scope.py --self-test      # 判据自己的证据（8 例）
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parent.parent
PLAN_REL = "Docs/Doyah产品开发计划书.md"
LEDGER_START = "## 3 需求状态台账"
LEDGER_STOP = "## 4 "
HEADER = "| 编号 | 一句话 | 领域 | 层次 | 优先级 | 状态 | 状态原值 | 版本 | 版本口径 |"

VERSIONS = ("v0.1.0-alpha", "v1.0", "v1.1+", "未排期")
ALPHA = "v0.1.0-alpha"
STATUSES = "✅🟡⬜➖"
DASH = "—"

FLOOR_ROWS = 400       # 2026-10-20 实测 425
FLOOR_ALPHA = 250      # 2026-10-20 实测 346（alpha 仍是主体；低于这个数多半是版本列被整体改坏）

IDENT = re.compile(r"(?:FR|NFR|AC)(?:-[A-Z0-9]{2,8}){1,3}-\d{2,3}")


def split_row(line: str) -> list[str]:
    body = line.strip()
    if body.startswith("|"):
        body = body[1:]
    if body.endswith("|"):
        body = body[:-1]
    out: list[str] = []
    cur = ""
    i = 0
    while i < len(body):
        ch = body[i]
        if ch == "\\" and i + 1 < len(body) and body[i + 1] == "|":
            cur += "|"
            i += 2
            continue
        if ch == "|":
            out.append(cur)
            cur = ""
            i += 1
            continue
        cur += ch
        i += 1
    out.append(cur)
    return [cell.strip() for cell in out]


def ledger_rows(lines: list[str]) -> list[tuple[int, list[str]]]:
    start = next((i for i, l in enumerate(lines) if l.startswith(LEDGER_START)), None)
    if start is None:
        return []
    stop = next((i for i, l in enumerate(lines[start + 1:], start + 1) if l.startswith(LEDGER_STOP)),
                len(lines))
    rows: list[tuple[int, list[str]]] = []
    for index in range(start, stop):
        if not lines[index].startswith("|"):
            continue
        cells = split_row(lines[index])
        if len(cells) >= 2 and IDENT.fullmatch(cells[0]):
            rows.append((index + 1, cells))
    return rows


def check(lines: list[str], floor_rows: int = FLOOR_ROWS, floor_alpha: int = FLOOR_ALPHA) -> list[str]:
    problems: list[str] = []
    if HEADER not in lines:
        problems.append(f"表头不是九列台账：期望 `{HEADER}`（版本 / 版本口径两列不能少）")
        return problems

    rows = ledger_rows(lines)
    if not rows:
        problems.append("台账一行都没解析到（§3 标题或表头被改坏？）—— 取不到输入不许当通过")
        return problems
    if len(rows) < floor_rows:
        problems.append(f"台账只剩 {len(rows)} 行（下限 {floor_rows}）—— 台账被删 / 解析面被削窄")
    if len(rows) > floor_rows * 1.3:
        problems.append(f"台账有 {len(rows)} 行，比下限 {floor_rows} 多出三成 —— 多半是夹具或切法串行")

    seen: dict[str, int] = {}
    alpha = 0
    for number, cells in rows:
        ident = cells[0]
        if ident in seen:
            problems.append(f"{ident} 在台账里出现两次（第 {seen[ident]} 行与第 {number} 行）")
            continue
        seen[ident] = number
        if len(cells) < 9:
            problems.append(f"{ident}（第 {number} 行）只有 {len(cells)} 列，缺「版本 / 版本口径」")
            continue
        status, version, why = cells[5], cells[7], cells[8]
        if not status or status[0] not in STATUSES:
            problems.append(f"{ident}（第 {number} 行）状态列 `{status}` 不是 ✅🟡⬜➖ 之一")
        if version not in VERSIONS:
            problems.append(f"{ident}（第 {number} 行）版本 `{version}` 不在四档里（{' / '.join(VERSIONS)}）")
            continue
        if version == ALPHA:
            alpha += 1
            if why != DASH:
                problems.append(f"{ident}（第 {number} 行）归 alpha，版本口径该写 `{DASH}`，实际 `{why[:40]}`")
        elif why in ("", DASH):
            problems.append(f"{ident}（第 {number} 行）归 `{version}`，但版本口径空着 —— 为什么不在本版，必须写清")

    if alpha < floor_alpha:
        problems.append(f"归 alpha 的只剩 {alpha} 条（下限 {floor_alpha}）—— 版本列被整体改坏 / 切法失效")
    return problems


def run(root: pathlib.Path, floor_rows: int, floor_alpha: int) -> int:
    plan = root / PLAN_REL
    if not plan.is_file():
        print(f"❌ 找不到《开发计划书》：{PLAN_REL}（仓根 {root}）")
        return 1
    lines = plan.read_text(encoding="utf-8").split("\n")
    problems = check(lines, floor_rows, floor_alpha)

    rows = ledger_rows(lines)
    counters: dict[str, int] = {}
    for _, cells in rows:
        if len(cells) >= 9:
            counters[cells[7]] = counters.get(cells[7], 0) + 1
    dist = " · ".join(f"{k} {counters[k]}" for k in VERSIONS if k in counters)

    if problems:
        print(f"❌ 版本范围校验失败（{len(problems)} 处）：")
        for item in problems:
            print(f"   {item}")
        return 1
    print(f"✅ 版本范围校验通过（台账 {len(rows)} 条：{dist}）")
    return 0


# ---------------------------------------------------------------- 自检

FIXTURE_OK = """# 开发计划书（夹具）

## 3 需求状态台账

| 编号 | 一句话 | 领域 | 层次 | 优先级 | 状态 | 状态原值 | 版本 | 版本口径 |
|---|---|---|---|---|---|---|---|---|
| FR-AGT-LINK-CHAN-001 | 甲 | 3.2 Agent | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-AGT-UX-CONV-001 | 乙 | 3.2 Agent | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 端点未接 |
| FR-AGT-UX-CONV-005 | 丙 | 3.2 Agent | 常用增强 | 中 | 🟡 | 🟡 | 未排期 | 等排期 |

## 4 里程碑
"""


def replace_once(text: str, old: str, new: str) -> str:
    assert text.count(old) == 1, old
    return text.replace(old, new)


def run_self_test() -> int:
    cases: list[tuple[str, str, bool]] = []   # (名字, 说明, 是否应绿)

    def judge(text: str, floor_rows: int = 3, floor_alpha: int = 1) -> list[str]:
        return check(text.split("\n"), floor_rows, floor_alpha)

    cases.append(("干净夹具 ⇒ 绿", "两档版本各一行、口径齐全", not judge(FIXTURE_OK)))
    cases.append(("版本写错字 ⇒ 红", "`v1.2` 不在四档里",
                  any("不在四档里" in p for p in judge(
                      replace_once(FIXTURE_OK, "| v1.1+ | 端点未接 |", "| v1.2 | 端点未接 |")))))
    cases.append(("alpha 行写了口径 ⇒ 红", "归 alpha 的版本口径必须是 —",
                  any("该写 `—`" in p for p in judge(
                      replace_once(FIXTURE_OK, "v0.1.0-alpha | — |", "v0.1.0-alpha | 顺手带的 |")))))
    cases.append(("非 alpha 行列口径空 ⇒ 红", "`v1.1+` 却写 —",
                  any("版本口径空着" in p for p in judge(
                      replace_once(FIXTURE_OK, "| v1.1+ | 端点未接 |", "| v1.1+ | — |")))))
    cases.append(("编号重复 ⇒ 红", "同一编号两行",
                  any("出现两次" in p for p in judge(
                      replace_once(FIXTURE_OK, "| FR-AGT-UX-CONV-005 |", "| FR-AGT-UX-CONV-001 |")))))
    cases.append(("表头少两列 ⇒ 红", "版本 / 版本口径被删",
                  any("表头不是九列台账" in p for p in judge(
                      replace_once(FIXTURE_OK, HEADER, "| 编号 | 一句话 | 领域 | 层次 | 优先级 | 状态 | 状态原值 |")))))
    cases.append(("行数低于下限 ⇒ 红", "空跑防护",
                  any("下限" in p for p in judge(FIXTURE_OK, floor_rows=100, floor_alpha=1))))
    cases.append(("alpha 条数低于下限 ⇒ 红", "版本列被整体改坏",
                  any("归 alpha 的只剩" in p for p in judge(FIXTURE_OK, floor_rows=3, floor_alpha=99))))

    failures = 0
    for name, note, green in cases:
        ok = green
        print(f"{'✅' if ok else '❌'} {name} —— {note}")
        if not ok:
            failures += 1
    print(f"\n判据自检：{len(cases)} 条中 {len(cases) - failures} 条达到预期")
    return 0 if failures == 0 else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="版本范围校验（台账 `版本` / `版本口径` 两列）")
    parser.add_argument("--root", help="仓根（默认 = 本脚本所在仓）")
    parser.add_argument("--floor-rows", type=int, default=FLOOR_ROWS, help="台账行数下限")
    parser.add_argument("--floor-alpha", type=int, default=FLOOR_ALPHA, help="alpha 条数下限")
    parser.add_argument("--self-test", action="store_true", help="判据自己的证据")
    args = parser.parse_args()
    if args.self_test:
        return run_self_test()
    root = pathlib.Path(args.root).expanduser().resolve() if args.root else REPO
    return run(root, args.floor_rows, args.floor_alpha)


if __name__ == "__main__":
    sys.exit(main())
