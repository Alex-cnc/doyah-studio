#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""待拍板台账覆盖度判据（队列 `L-130` ②）。

**为什么需要它**：需求提出者 2026-09-30 问「怎么还有需要拍板的，上次 19 条没覆盖吗？」——
待决项散在四处（Studio spec §6 / Studio 队列 / Notes 四书 / Retro 需求书 §9.2），
而**唯一汇总处**是 `Docs/design/待拍板台账-三仓.md`（本机台账、`.gitignore` 排除）。
汇总处本身没人对账 ⇒ 它一漂，需求提出者读到的就是「已经决掉的还在等」或
「还开着的没人告诉他」。本判据是台账的**覆盖度对账**（不是台账条目的业务判定）。

**三类红（判据本体）**：

- **R1 台账漏登记 / 台账与原书打架** —— 面内原书的**未决**号（§6 状态格首词 `⏳`、队列
  `needs-user` 行点名的号）必须在台账**有登记**（任一数据行的编号格里出现），**且那一行的结论格
  是 `⏳`**；只有号、结论格却写成已决 ⇒ 红（两级都判：前者 = 漏登记，后者 = 汇总处与原书打架）。
  **例外（挂起 ≠ 待拍板，与 `check-queue-needs-user.py` 同口径）**：台账写明理由的挂起行
  （「挂起 / 不具备条件 / 不再追问 / 已随分工转移」）允许不是 `⏳` —— 真现场 = `Q52`。
  真现场（本判据落地当天抓到）：`Q56` / `Q57` / `Q60` / `Q62` 四条 `⏳ 待拍板` 从未进台账，
  而台账快照写着「仍开着 2 条」。
- **R2 台账陈旧** —— 台账里挂 `⏳` 的行，它的**首个编号**必须在面内原书里仍是未决
  （`Q` 号 ⇒ 在 §6 且仍 `⏳`；`L` 号 ⇒ 在队列且状态非 `done`），否则红
  （原书已决 / 已关闭，台账却还在替它问需求提出者）。
- **R3 空壳行** —— 台账挂 `⏳` 的行**一个可解析编号都没有** ⇒ 红（点名不到东西，
  对账与引用都落空）。

**面与边界（如实登记，不假装覆盖比实际宽）**：

- 本版**接入面** = `Docs/Doyah开发规范.md` §6（Studio 的 `Q` 号空间）
  + `Docs/design/开发循环-任务队列.md`（`needs-user` 行）+ 台账自身。
- **面外** = 台账里**落点格**指向 Notes / Retro 书（`核心契约` / `需求书` / `规划书` / `§9.2`）
  的行 —— 本版**只计数、不判定**（它们的原书在别的仓，尚未接入；计数会打印在收尾行上，
  不静默）。
- 台账不在盘上（干净克隆 / 别仓）⇒ **跳过并高声提示**，`--require-all` 判红。
  **跳过 ≠ 通过**：收尾行会写明 `SKIP`。

**退出码**：0 = 绿或按约定跳过 / 1 = 有红或空跑防护触发 / 2 = 用法错。
"""

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = ROOT / "Docs" / "智能体助手-开发规范.md"
QUEUE = ROOT / "Docs" / "design" / "开发循环-任务队列.md"
LEDGER = ROOT / "Docs" / "design" / "待拍板台账-三仓.md"

PEND_PREFIX = "\u23f3"          # ⏳
HANG_WORDS = ("挂起", "不具备条件", "不再追问", "不重复追问", "已随分工转移")
CLOSED_WORD = "已随分工转移"
NUM_TOKENS = re.compile(r"Q\d+|L-\d+|N-\d+|R-\d+|RQ-\d+|\u00a7[\d.]+-\d+")
OUTSIDE_HINT = re.compile(r"Notes|Retro|核心契约|需求书|规划书|9\.2")

# 空跑防护下限（测得值见收尾行；取值留余量，只为挡「一个号都没解析到」）
MIN_SPEC_ROWS = 20
MIN_LEDGER_ROWS = 8


def cells(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]


def norm_state(cell):
    """状态格归一：剥掉加粗星号与前导空白，取首词。"""
    return re.sub(r"^[\s*]+", "", cell or "")


def parse_spec6(lines):
    """→ {Q号: (是否未决, 状态格原文)}；只认 §6 那一节里的数据行。"""
    start = end = None
    for i, l in enumerate(lines):
        if start is None and re.match(r"^#{2,3}\s*6\.\s", l):
            start = i
        elif start is not None and i > start and re.match(r"^#{2}\s+\d+\.\s", l):
            end = i
            break
    if start is None:
        return {}
    out = {}
    for l in lines[start:end or len(lines)]:
        if not l.startswith("|"):
            continue
        c = cells(l)
        if len(c) < 3:
            continue
        m = re.search(r"Q(\d+)", c[0])
        if not m:
            continue
        out["Q" + m.group(1)] = (norm_state(c[2]).startswith(PEND_PREFIX), c[2])
    return out


def parse_queue(lines):
    """→ [(条目号, [点名的拍板号…])]；needs-user 行才进面。"""
    out = []
    for l in lines:
        if not l.startswith("|"):
            continue
        c = cells(l)
        if len(c) < 6:
            continue
        st = c[4].strip("*` ")
        if st != "needs-user":
            continue
        toks = [t for t in NUM_TOKENS.findall(" ".join(c)) if t.startswith(("Q", "L-", "提案"))]
        out.append((c[0].strip("* "), sorted(set(toks))))
    return out


def parse_ledger(lines):
    """→ (行列表, 全部编号集, 面外行数)。行 = dict(no, toks, pending, where)。"""
    rows, all_toks, outside = [], set(), 0
    for l in lines:
        if not l.startswith("|"):
            continue
        c = cells(l)
        if len(c) < 5 or re.fullmatch(r"[-: ]+", c[0]) or c[0] in ("#", "编号"):
            continue
        toks = NUM_TOKENS.findall(c[1])
        pending = PEND_PREFIX in c[3]
        rows.append({"no": c[0], "toks": toks, "pending": pending, "where": c[4], "concl": c[3]})
        all_toks.update(toks)
        if OUTSIDE_HINT.search(c[4]):
            outside += 1
    return rows, all_toks, outside


def check(spec_lines, queue_lines, ledger_lines, ledger_present=True):
    """→ (problems, stats)。problems = [(类别, 文案)]。"""
    problems = []
    spec6 = parse_spec6(spec_lines)
    pending_q = sorted([n for n, v in spec6.items() if v[0]], key=lambda x: int(x[1:]))
    queue_hits = parse_queue(queue_lines)

    if not ledger_present:
        return [("SKIP", "台账不在盘上（Docs/design/待拍板台账-三仓.md）—— 本判据跳过，"
                         "跳过 ≠ 通过")], {"spec_rows": len(spec6), "pending": len(pending_q)}

    rows, all_toks, outside = parse_ledger(ledger_lines)

    # 空跑防护：解析不到东西不许当通过
    if len(spec6) < MIN_SPEC_ROWS:
        problems.append(("E", f"空跑防护：§6 只解析到 {len(spec6)} 条数据行（下限 {MIN_SPEC_ROWS}）"
                              "—— 表格结构被改坏或扫描面失效，不许当通过"))
    if len(rows) < MIN_LEDGER_ROWS:
        problems.append(("E", f"空跑防护：台账只解析到 {len(rows)} 条数据行（下限 {MIN_LEDGER_ROWS}）"
                              "—— 台账结构被改坏，不许当通过"))

    # R1 台账漏登记（两级：完全没有这个号 / 有这个号但结论格不是 ⏳ ⇒ 台账与原书打架）
    pend_map = {}
    for r in rows:
        for t in r["toks"]:
            pend_map.setdefault(t, []).append(r["pending"])

    def r1(tag, where):
        flags = pend_map.get(tag)
        if flags is None:
            problems.append(("R1", f"台账漏登记：{where} 里 `{tag}` 仍是未决，台账任何一行都没有它"))
        elif not any(flags):
            hits = [r for r in rows if tag in r["toks"]]
            # 挂起 ≠ 待拍板（与 `check-queue-needs-user.py` 同口径）：台账写明理由的挂起行
            # 允许结论格不是 ⏳ —— 那正是「本条不再追问」的记法（真现场 = `Q52`）。
            if all(any(w in r["concl"] for w in HANG_WORDS) for r in hits):
                return
            nums = [r["no"] for r in hits]
            problems.append(("R1", f"台账与原书打架：{where} 里 `{tag}` 仍是未决，"
                                   f"而台账第 {'/'.join(nums)} 行的结论格不是 {PEND_PREFIX}（读起来像已决）"))

    for n in pending_q:
        r1(n, "spec §6")
    for qid, toks in queue_hits:
        for t in toks:
            r1(t, f"队列 `{qid}`（needs-user）")

    # R2 台账陈旧 + R3 空壳行
    for r in rows:
        if not r["pending"]:
            continue
        if not r["toks"]:
            problems.append(("R3", f"空壳行：台账第 {r['no']} 行挂 {PEND_PREFIX} 却没写可解析编号"
                                   "（对账与引用都落空）"))
            continue
        first = r["toks"][0]
        if first.startswith("Q"):
            if first not in spec6:
                problems.append(("R2", f"台账陈旧：第 {r['no']} 行挂 {PEND_PREFIX} 的 `{first}` 不在 §6 表里"))
            elif not spec6[first][0]:
                problems.append(("R2", f"台账陈旧：第 {r['no']} 行挂 {PEND_PREFIX}，但 §6 里 `{first}` 已非未决"
                                       f"（状态格 = {norm_state(spec6[first][1])[:24]}）"))
        elif first.startswith("L-"):
            hit = [l for l in queue_lines if l.startswith("|") and first in l and "| **" + first in l]
            if not hit:
                problems.append(("R2", f"台账陈旧：第 {r['no']} 行挂 {PEND_PREFIX} 的 `{first}` 不在队列里"))
            else:
                st = cells(hit[0])[4].strip("*` ") if len(cells(hit[0])) >= 6 else ""
                if st == "done":
                    problems.append(("R2", f"台账陈旧：第 {r['no']} 行挂 {PEND_PREFIX}，但队列 `{first}` 已 done"))

    stats = {"spec_rows": len(spec6), "pending": len(pending_q), "ledger_rows": len(rows),
             "ledger_pending": len([r for r in rows if r["pending"]]), "outside": outside,
             "hang": len([n for n in pending_q
                          if pend_map.get(n) is not None and not any(pend_map[n])
                          and all(any(w in r["concl"] for w in HANG_WORDS)
                                  for r in rows if n in r["toks"])])}
    return problems, stats


# ---------------------------------------------------------------- self-test
def _fx_spec(pending=("Q56", "Q57", "Q60", "Q62")):
    head = ["## 6. 待拍板与待授权（需求提出者的输入队列）", "| 编号 | 问题 | 状态 | 卡住什么 |",
            "|---|---|---|---|"]
    rows = []
    for n in range(1, 17):
        rows.append(f"| ~~**Q{n}**~~ | 问题{n} | \u2705 已关闭 | \u2014\u2014 |")
    for n in list(range(50, 56)) + list(range(57, 60)) + [61, 63, 64]:
        rows.append(f"| **Q{n}** | 问题{n} | \u2705 **已决** | \u2014\u2014 |")
    for n in pending:
        rows.append(f"| **Q{n}** | 问题{n} | \u23f3 待拍板 | 卡住什么{n} |")
    return head + rows + ["## 7. \u4e0b\u4e00\u8282", "正文"]


def _fx_ledger(pending_qs, empties=()):
    head = ["# 待拍板台账（三仓统一）", "| # | 编号 | 事项 | 结论 | 落点 |", "|---|---|---|---|---|"]
    rows = [f"| 1 | `Q1` | 事项 | \u2705 已决 | spec \u00a76 行 |"]
    for i, n in enumerate(pending_qs, 2):
        rows.append(f"| {i} | `{n}` | 事项 | \u23f3 待拍板 | spec \u00a76 行 |")
    for i, e in enumerate(empties, 20):
        rows.append(f"| {i} | {e} | 事项 | \u23f3 待拍板 | \u672c\u8868 |")
    for i in range(30, 36):
        rows.append(f"| {i} | `Q2` | 事项{i} | \u2705 已决 | Notes \u9700\u6c42\u4e66 |")
    return head + rows


def self_test():
    cases = []
    full = ["Q56", "Q57", "Q60", "Q62"]

    def run(spec, ledger, present=True, queue=None):
        return check(spec, queue or [], ledger, present)

    # 1 正例（绿对照）
    p, _ = run(_fx_spec(), _fx_ledger(full))
    cases.append(("例1 正例：未决四条都在台账", p == [], p))
    # 2 R1 漏登记
    p, _ = run(_fx_spec(), _fx_ledger(["Q56", "Q57", "Q60"]))
    cases.append(("例2 R1：台账漏 Q62", any(c == "R1" and "Q62" in t for c, t in p), p))
    # 2b R1 打架（号在台账里，但结论格写成已决）—— 反例判红第一版没抓住，补的这一例
    led_diff = [l for l in _fx_ledger(full) if "`Q62`" not in l]
    led_diff.append("| 41 | `Q62` | 事项 | \u2705 已决 | spec \u00a76 \u884c |")
    p, _ = run(_fx_spec(), led_diff)
    cases.append(("例2b R1：台账把未决号写成已决", any(c == "R1" and "Q62" in t for c, t in p), p))
    # 2c 挂起 ≠ 待拍板（正例）：台账把未决号记成「已挂起 + 理由」⇒ 不判红（真现场 = Q52）
    led_hang = [l for l in _fx_ledger(full) if "`Q62`" not in l]
    led_hang.append("| 41 | `Q62` | 事项 | \u2705 **\u300c\u5148\u6302\u8d77\uff0c\u4e0d\u5177\u5907\u6761\u4ef6\u300d\u21d2 \u6302\u8d77\uff0c\u4e0d\u518d\u8ffd\u95ee** | spec \u00a76 \u884c |")
    p, _ = run(_fx_spec(), led_hang)
    cases.append(("例2c 挂起：台账写明理由的挂起不判红", p == [], p))
    p, _ = run(_fx_spec(), _fx_ledger(full) + ["| 40 | `Q1` | 事项 | \u23f3 待拍板 | spec \u00a76 \u884c |"])
    cases.append(("例3 R2：已决号仍挂 ⏳", any(c == "R2" and "Q1" in t for c, t in p), p))
    # 4 R3 空壳行
    p, _ = run(_fx_spec(), _fx_ledger(full, empties=("\u2014\u2014",)))
    cases.append(("例4 R3：⏳ 行无编号", any(c == "R3" for c, t in p), p))
    # 5 空跑防护
    p, _ = run(_fx_spec()[:5], _fx_ledger(full))
    cases.append(("例5 E：§6 解析不到行", any(c == "E" for c, t in p), p))
    # 6 台账缺文件 ⇒ 跳过
    p, _ = run(_fx_spec(), [], present=False)
    cases.append(("例6 SKIP：台账不在盘上", len(p) == 1 and p[0][0] == "SKIP", p))
    # 7 真实仓库（若台账在盘上）必须绿
    if LEDGER.exists():
        probs, st = check(SPEC.read_text(encoding="utf-8").splitlines(),
                          QUEUE.read_text(encoding="utf-8").splitlines(),
                          LEDGER.read_text(encoding="utf-8").splitlines(), True)
        cases.append((f"例7 真仓库真内容 rc 应为 0（面内 {st['spec_rows']} 行 / 未决 {st['pending']} / "
                      f"台账 {st['ledger_rows']} 行）", probs == [], probs))
    else:
        cases.append(("例7 真仓库（台账不在盘上 ⇒ 按跳过）", True, []))

    failed = [c for c, ok, _ in cases if not ok]
    for name, ok, p in cases:
        print(("  \u2705 " if ok else "  \u274c ") + name)
        if not ok:
            for c, t in p[:6]:
                print(f"       [{c}] {t}")
    print(f"待拍板台账覆盖度判据 --self-test：{len(cases) - len(failed)} 例通过 / {len(failed)} 例失败")
    return 1 if failed else 0


def main():
    ap = argparse.ArgumentParser(description="待拍板台账覆盖度判据（队列 L-130 ②）")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--require-all", action="store_true", help="本机台账缺席时判红而不是跳过")
    a = ap.parse_args()
    if a.self_test:
        return self_test()

    present = LEDGER.exists()
    if not present and not a.require_all:
        print("== \u5f85\u62cd\u677f\u53f0\u8d26\u8986\u76d6\u5ea6\uff08\u961f\u5217 L-130 \u2461\uff09==")
        print(f"SKIP \u53f0\u8d26\u4e0d\u5728\u76d8\u4e0a\uff08{LEDGER.relative_to(ROOT)}\uff09\u2014\u2014 "
              "\u8df3\u8fc7 \u2260 \u901a\u8fc7\uff1b\u52a0 --require-all \u5224\u7ea2")
        return 0

    probs, st = check(SPEC.read_text(encoding="utf-8").splitlines(),
                      QUEUE.read_text(encoding="utf-8").splitlines(),
                      LEDGER.read_text(encoding="utf-8").splitlines(), present)
    print("== \u5f85\u62cd\u677f\u53f0\u8d26\u8986\u76d6\u5ea6\uff08\u961f\u5217 L-130 \u2461\uff09==")
    for c, t in probs:
        print(f"[{c}] {t}")
    tail = (f"面内 §6 {st.get('spec_rows', 0)} 行 / 未决 {st.get('pending', 0)}（其中挂起类 {st.get('hang', 0)}）· "
            f"台账 {st.get('ledger_rows', 0)} 行（挂 \u23f3 {st.get('ledger_pending', 0)}）· "
            f"面外未接入 {st.get('outside', 0)} 行（Notes/Retro \u4e66\uff0c\u672c\u7248\u53ea\u8ba1\u6570\uff09")
    if probs:
        print(f"\u274c 待拍板台账覆盖度：{len(probs)} 处问题 \u00b7 {tail}")
        return 1
    print(f"\u2705 待拍板台账覆盖度：台账与面内原书一致 \u00b7 {tail}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
