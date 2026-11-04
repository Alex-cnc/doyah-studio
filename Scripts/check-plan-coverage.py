#!/usr/bin/env python3
"""一单台账 ↔ 《需求规格说明书》索引 的覆盖判据。

为什么需要：2026-10-20 起状态从需求规格说明书迁到一单（人类主人令：
「需求规格说明书里不需要状态，而是一单里需要状态和进展情况」（原话里的文档名按现行口径改写））。
两边一旦漂移，就会重新出现「状态写了但条目不存在」「条目存在但没人管状态」。

判据五条：
  A **编号集合相等**：一单 §3 台账的编号集合 == 需求分析 §10.1 索引的编号集合（不多不少）。
  B **状态合法**：台账每一行的状态是 ⬜ / 🟡 / ✅ / ➖ 之一。
  C **需求分析不写状态**：正文（变更记录之前）不出现状态符号。
  D **不许空壳行**：台账每一行的「一句话」不得是 `—` / 空白（覆盖范围 = 台账**全 471 行**，
    含跨仓 `FR-RTR` 行 —— 它们同在这一张表里，空着就是同一类问题）。
  E **§4.2 的条数必须是台账逐行复算的结果**：六个里程碑各自的条数（🟡 / ⬜）、§4.2 头部那句
    「当前未闭 N 条」、`§2 ✅ N` / `§3 🟡 N` / `§4 ⬜ N` 三个小节标题里的条数，全部要等于按
    台账逐行复算的数；未闭行必须**恰好**落在一个里程碑里（无孤儿、无重复归属）。

为什么 E 要有：§4.2 那六个条数是 2026-11-01 手写的，之后每收口一条就只改 §3 台账、不回改本表 ——
2026-11-02 实算「表里合计 46 / 台账未闭 26」差 20 条，而当时**没有任何机器判据拦这件事**，
报数全靠人记得手算。一处拍板落两处、两处只有一个有人改，就是漂移的温床（铁律 11 / 12）。
E 的覆盖范围：只判**条数**与**归属**，不判单个里程碑「该不该叫这个名字」；`FR-RTR` 82 条按
§4.2 覆盖声明排除（跨仓，见 §6）。

为什么 D 要有：`—` 的一句话意味着没有「做成什么样」的标准，这种行翻 ✅ 等于自己给自己判对
（AGENTS.md 红线 3「判『对』的依据不许由被判方提供」）。2026-11-02 实测台账里有 105 行空壳，
其中 24 行状态已是 ✅ —— 那不是完成，那是「没人写过它要做什么」。补齐当天加这条判据守着。

用法：
    python3 Scripts/check-plan-coverage.py
    python3 Scripts/check-plan-coverage.py --self-test   # 判据 E 的反例（在内存里改坏，真仓零改动）
"""

from __future__ import annotations

import pathlib
import re
import sys
from collections import Counter
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import doc_index  # noqa: E402  （派生件位置：.build/derived；缺文件先重生成）


SRS = pathlib.Path("Docs/Doyah产品需求规格说明书.md")
INDEX = doc_index.path()
PLAN = pathlib.Path("Docs/Doyah产品开发计划任务清单-macOS.md")
MARKS = ("⬜", "🟡", "✅", "➖")

# --------------------------------------------------------------------------- #
# 判据 E：§4.2 六个里程碑的归属（前缀表）。改这里 = 改口径，必须同批改 §4.2 的「内容」列。
# 覆盖范围 = 台账里**非 FR-RTR** 的未闭行；`FR-RTR` 82 条按 §4.2 覆盖声明排除。
# --------------------------------------------------------------------------- #
MILESTONES: list[tuple[str, tuple[str, ...]]] = [
    # v0.2.0 工作区闭环：编辑面 / 文件 / 导航 / 界面细节 / Web 预览 / 版本控制 / 智能体入口 / DAP
    # （`WS-AI-*` 与 `WS-TOOL-*` 全族归这里：AI-002 许愿模式、TOOL-001 终端都是工作区面）
    ("v0.2.0", ("FR-STD-WS-EDIT-", "FR-STD-WS-FS-", "FR-STD-WS-NAV-", "FR-STD-WS-UI-",
                "FR-STD-WS-WEB-", "FR-STD-WS-VCS-", "FR-STD-WS-AI-", "FR-STD-WS-TOOL-")),
    ("v0.3.0", ("FR-STD-DB-CONN-", "FR-STD-DB-DATA-", "FR-STD-DB-DDL-", "FR-STD-DB-DIAG-",
                "FR-STD-DB-IO-", "FR-STD-DB-META-", "FR-STD-DB-RES-", "FR-STD-DB-SESS-",
                "FR-STD-DB-TASK-", "FR-STD-DB-DRV-009")),
    ("v0.4.0", ("FR-NTS-NOTE-", "FR-NTS-TODO-")),
    ("v0.5.0", ("FR-AGT-TOOL-", "FR-AGT-OPS-OBS-002", "FR-AGT-UX-", "FR-AGT-PLAN-",
                "FR-AGT-LINK-", "FR-AGT-KNOW-MEM-003", "NFR-ALL-GATE-AI-",
                "AC-ALL-GATE-AI-")),
    ("v0.6.0", ("FR-STD-ALL-LIC-00", "FR-STD-WS-LIC-001", "FR-STD-ALL-PLUG-005",
                "FR-STD-ALL-PLUG-008", "NFR-ALL-GATE-PERF-", "NFR-ALL-GATE-COMP-",
                "NFR-ALL-GATE-UI-001", "NFR-ALL-GATE-USE-005", "NFR-ALL-GATE-SEC-008",
                "NFR-ALL-GATE-LANG-001")),
    ("v0.9.0", ("AC-ALL-GATE-REL-00", "NFR-NTS-ALL-DIST-001", "FR-NTS-ALL-PARITY-001",
                "FR-NTS-ALL-LIC-001")),
]

HEADING_COUNTS = (
    # (小节, 标题里那枚符号, 应等于台账里哪一档)
    (r"^## 2\. 已完成（✅ (\d+) 条", "§2 已完成（✅ N 条）", "done"),
    (r"^## 3\. 半成品（🟡 (\d+) 条", "§3 半成品（🟡 N 条）", "wip"),
    (r"^## 4\. 待开发批次（⬜ (\d+) 条", "§4 待开发批次（⬜ N 条）", "todo"),
)


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


def ledger_rows(text: str) -> dict[str, str]:
    """§3 台账：编号 → 状态格（与 plan_rows 同源，但吃文本，供判据 E 在内存里改坏用）。"""
    out: dict[str, str] = {}
    in_table = False
    for line in text.splitlines():
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


def plan_rows() -> dict[str, str]:
    return ledger_rows(PLAN.read_text(encoding="utf-8"))


def mark_of(status: str) -> str:
    """状态格 → 四档（✅ / 🟡 / ⬜ / ➖）；认不出给 `?`（判据 B 会单独点名）。"""
    for m, name in (("✅", "done"), ("🟡", "wip"), ("⬜", "todo"), ("➖", "na")):
        if status.startswith(m):
            return name
    return "?"


def milestone_counts(text: str) -> tuple[dict[str, Counter], Counter, list[str], list[str]]:
    """按前缀表把**非 FR-RTR** 行归堆。

    返回 (每个里程碑的分档计数, 全仓未闭口径的总计数, 没归堆的未闭行, 归了两个堆的行)。
    """
    rows = ledger_rows(text)
    counts = {name: Counter() for name, _ in MILESTONES}
    total: Counter = Counter()
    orphans: list[str] = []
    doubles: list[str] = []
    for rid, status in rows.items():
        mark = mark_of(status)
        if rid.startswith("FR-RTR"):  # 跨仓，§4.2 覆盖声明排除
            continue
        total[mark] += 1
        homes = [name for name, prefixes in MILESTONES if any(rid.startswith(p) for p in prefixes)]
        if mark in ("wip", "todo"):
            if not homes:
                orphans.append(rid)
            elif len(homes) > 1:
                doubles.append(rid)
        for h in homes:
            counts[h][mark] += 1
    return counts, total, orphans, doubles


def milestone_problems(text: str) -> list[str]:
    """判据 E：§4.2 的条数与归属 == 台账逐行复算。"""
    counts, total, orphans, doubles = milestone_counts(text)
    problems: list[str] = []
    if orphans:
        problems.append(
            f"未闭行没归任何里程碑（{len(orphans)} 条）：{orphans[:6]}"
            f"{' …' if len(orphans) > 6 else ''} —— §4.2 的「内容」列要收它，或改归属口径（MILESTONES）"
        )
    if doubles:
        problems.append(f"同一条归了两个里程碑（{len(doubles)} 条）：{doubles[:6]} —— 前缀表有重叠")

    want_total = (total["wip"] + total["todo"], total["wip"], total["todo"])

    seen: set[str] = set()
    for line in text.splitlines():
        m = re.match(r"^\|\s*\*\*(v0\.\d+\.\d+)\*\*\s*\|", line)
        if not m:
            continue
        row = cells(line)
        name = m.group(1)
        if len(row) < 3:
            problems.append(f"§4.2 {name} 那行少列（读不到条数格）")
            continue
        parsed = re.match(r"^\*\*(\d+)\*\*\s*[（(]\s*(\d+)\s*/\s*(\d+)\s*[）)]", row[2])
        if not parsed:
            problems.append(
                f"§4.2 {name} 的条数格读不出来（须写成 `**N**（🟡 a / ⬜ b）`）：{row[2][:36]}"
            )
            continue
        seen.add(name)
        if name == "v1.0.0":
            continue  # 正式发布那一行写的是 0（无新增能力），不按未闭算
        got = (int(parsed.group(1)), int(parsed.group(2)), int(parsed.group(3)))
        c = counts.get(name)
        if c is None:
            problems.append(f"§4.2 有 {name} 行，但判据里没有这个里程碑的前缀表")
            continue
        exp = (c["wip"] + c["todo"], c["wip"], c["todo"])
        if got != exp:
            problems.append(
                f"§4.2 {name} 条数写 {got[0]}（{got[1]} / {got[2]}），台账逐行复算是 "
                f"{exp[0]}（{exp[1]} / {exp[2]}）"
            )
    for name, _ in MILESTONES:
        if name not in seen:
            problems.append(f"§4.2 缺 {name} 那一行（或这行的形状变了，判不到条数）")
    table_sum = sum(counts[n]["wip"] + counts[n]["todo"] for n in counts)
    if table_sum != want_total[0]:
        problems.append(
            f"§4.2 六个里程碑条数合计 {table_sum}，台账未闭（非 FR-RTR）是 {want_total[0]} —— "
            f"差 {abs(table_sum - want_total[0])} 条"
        )

    head = re.search(r"当前未闭\s*\*\*(\d+) 条\*\*（🟡 (\d+) 半成品 \+ ⬜ (\d+) 未开始", text)
    if not head:
        problems.append("§4.2 头部那句「当前未闭 **N 条**（🟡 a 半成品 + ⬜ b 未开始…」读不出来")
    else:
        got_h = (int(head.group(1)), int(head.group(2)), int(head.group(3)))
        if got_h != want_total:
            problems.append(
                f"§4.2 头部写未闭 {got_h[0]} 条（🟡 {got_h[1]} + ⬜ {got_h[2]}），"
                f"台账逐行复算是 {want_total[0]}（🟡 {want_total[1]} + ⬜ {want_total[2]}）"
            )

    for pattern, label, key in HEADING_COUNTS:
        m = re.search(pattern, text, re.M)
        if not m:
            problems.append(f"{label} 那行标题读不出来（形状变了？）")
            continue
        got_n = int(m.group(1))
        if got_n != total[key]:
            problems.append(f"{label} 写 {got_n}，台账逐行复算是 {total[key]}")
    return problems


def self_test() -> int:
    """判据 E 自己的证据：在**内存里**把文本改坏，逐例必须判红（真仓零改动）。"""
    text = PLAN.read_text(encoding="utf-8")
    rows = ledger_rows(text)
    unclosed = [r for r, s in rows.items() if mark_of(s) in ("wip", "todo") and not r.startswith("FR-RTR")]
    closed = [r for r, s in rows.items() if mark_of(s) == "done" and not r.startswith("FR-RTR")]

    def set_status(src: str, rid: str, mark: str) -> str:
        out = []
        for line in src.split("\n"):
            if line.startswith(f"| {rid} |"):
                c = cells(line)
                c[5] = mark
                line = "| " + " | ".join(c) + " |"
            out.append(line)
        return "\n".join(out)

    results: list[tuple[str, bool, str]] = []

    base = milestone_problems(text)
    results.append(("现状应无问题", base == [], "；".join(base[:2])))

    if unclosed:
        victim = unclosed[0]
        got = milestone_problems(set_status(text, victim, "✅"))
        results.append((f"把未闭行 {victim} 改成 ✅（少一条）⇒ 必红",
                        any("条数写" in p or "合计" in p or "头部" in p or "写 " in p for p in got),
                        "；".join(got[:2])))
    if closed:
        victim = closed[0]
        got = milestone_problems(set_status(text, victim, "⬜"))
        results.append((f"把已闭行 {victim} 改成 ⬜（多一条）⇒ 必红",
                        bool(got), "；".join(got[:2])))

    orphan_row = "| FR-ZZZ-GATE-001 | 判据 E 的负例：一条没归任何里程碑的未闭行 | 9.9 测试 | — | — | ⬜ | ⬜ | v1.0 | 测试 |"
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if line.startswith("| FR-RTR-"):
            lines.insert(i, orphan_row)
            break
    else:
        lines.append(orphan_row)
    got = milestone_problems("\n".join(lines))
    results.append(("插一条没归堆的未闭行（孤儿）⇒ 必红", any("没归任何里程碑" in p for p in got),
                    "；".join(p for p in got if "没归任何里程碑" in p)[:160]))

    got = milestone_problems(text.replace("当前未闭 **", "当前未闭 **1", 1)
                             if "当前未闭 **" in text else text)
    results.append(("把 §4.2 头部总数改大一位 ⇒ 必红", any("头部写未闭" in p for p in got),
                    "；".join(p for p in got if "头部" in p)[:160]))

    bad = milestone_problems(re.sub(r"(## 3\. 半成品（🟡 )(\d+)", r"\g<1>999", text, count=1))
    results.append(("把 §3 标题的 🟡 条数改成 999 ⇒ 必红", any("§3 半成品" in p for p in bad),
                    "；".join(p for p in bad if "§3" in p)[:160]))

    failed = 0
    for desc, ok, detail in results:
        print(f"{'✅' if ok else '❌'} {desc}" + ("" if ok else f" —— 实读：{detail or '（没判红）'}"))
        failed += 0 if ok else 1
    print(f"\n判据 E 自检 {len(results) - failed}/{len(results)} 通过")
    return 0 if failed == 0 else 1


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

    text = PLAN.read_text(encoding="utf-8")
    counts, total, orphans, doubles = milestone_counts(text)
    ms = milestone_problems(text)
    problems.extend(ms)

    print(
        "— 需求分析索引 %d 条 · 一单台账 %d 条 · 空壳 %d 行" % (len(a), len(b), len(shells))
    )
    print(
        "— 台账逐行复算（非 FR-RTR）：✅ %d · 🟡 %d · ⬜ %d · ➖ %d · 未闭 %d · 未闭未归堆 %d"
        % (total["done"], total["wip"], total["todo"], total["na"],
           total["wip"] + total["todo"], len(orphans))
    )
    print(
        "— §4.2 六个里程碑："
        + " · ".join(
            f"{n} {counts[n]['wip'] + counts[n]['todo']}（{counts[n]['wip']} / {counts[n]['todo']}）"
            for n, _ in MILESTONES
        )
    )

    if problems:
        print("\n❌ 计划覆盖校验失败：")
        for p in problems:
            print(f"   · {p}")
        return 1
    print("\n✅ 台账与索引一一对应；无空壳行；需求规格说明书正文无状态符号；§4.2 条数与台账逐行复算一致")
    return 0


if __name__ == "__main__":
    if "--self-test" in sys.argv[1:]:
        sys.exit(self_test())
    sys.exit(main())
