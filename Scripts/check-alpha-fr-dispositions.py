#!/usr/bin/env python3
"""alpha 范围账：SRS 里 FR 🟡 的逐条判定（队列 L-69 条件 ③）。

为什么需要这条判据：
    `v0.2.0-alpha` 的口径是「**不等人工点验** —— 机器可验的部分推到全绿，其余显式标注
    `[alpha 不含]`」（spec v1.99 拍板；与 `v0.1.0-alpha` 那次逐字一致）。但「哪条 🟡 属
    alpha 范围、哪条不含、为什么」此前**只写在人的脑子里**：v0.1.0-alpha 给 6 条环境项
    手加了标记，此后谁新增一条 🟡、谁销掉一条标记、谁把标记挪到别的格，机器都不说话 ——
    于是发布说明「**明确不做什么**」那一节会与文档事实脱节（说得清做了什么，说不清
    没做什么）。本脚本把「判定」落成台账 + 双向判据，让这本账**可复跑**。

判据（A~E）：
    A 台账 ↔ SRS **双向**对账：每一条 FR 🟡 恰好一条台账项；台账里不得留下「已不再是 🟡」
      的条目（陈旧条目报红）—— 一条都不能靠人眼对。
    B 台账声明的标记（`**[alpha 不含]**（原因）`）必须**逐字**出现在该条目的定义行里；
      反向：定义行里带 `[alpha 不含]` 的 FR 必须在台账里、且文本逐字相等
      （手写一个标记绕不过对账；把标记写在状态格还是证据格不限 —— 现存 6 条两种都有）。
    C 原因档必须取自台账 `reasonBranches` 的键（词表外的档位报红，防止「档位越来越多、
      最后没人知道每档什么意思」）。
    D 每条至少一个**存在的**证据指针：`path` 必须真的在磁盘上、或给一条 `command`
      （「补证据」不是写个脚本名就算）。
    E 空跑防护：解析到的 FR 🟡 少于下限 / 台账为空 / 一条定义行都解析不到 ⇒ 判红
      （「扫了个寂寞」不许当通过）。

口径复用：定义行的切法**照抄** `check-status-consistency.py`（只扫 §1~§9 正文，FR 行 ≥5 格，
状态格 = 第 4 格起第一个以状态符号开头的格），不另立一套 —— 两张门禁对同一份文档的
「哪一行是定义行」必须给出同一个答案。

用法：
    python3 Scripts/check-alpha-fr-dispositions.py                     # 校验（闸门）
    python3 Scripts/check-alpha-fr-dispositions.py --self-test         # 负例自检（临时副本上写坏）
    python3 Scripts/check-alpha-fr-dispositions.py --requirements P --ledger L   # 指定输入（自检用）
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import shutil
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRS = ROOT / "Docs" / "需求规范书.md"
LEDGER = ROOT / "Scripts" / "alpha-fr-dispositions.json"
STATUSES = "✅🟡⬜➖"
EXCLUSION_TOKEN = "[alpha 不含]"
# 解析到的 FR 🟡 少于这个数就不许算通过（真值是 52；留一点余量，但绝不许「一条都没解析到」）
MIN_YELLOW = 40
REQUIREMENT_ID = re.compile(r"FR-[A-Z]+-\d+")


def split_cells(line: str) -> list[str]:
    """按**未转义**的竖线切格（`\\|` 还原成格内字面竖线）—— 与 check-doc-tables.py 同口径。"""
    body = line.strip()
    if body.startswith("|"):
        body = body[1:]
    if body.endswith("|"):
        body = body[:-1]
    out: list[str] = []
    cur = ""
    i = 0
    while i < len(body):
        c = body[i]
        if c == "\\" and i + 1 < len(body) and body[i + 1] == "|":
            cur += "|"
            i += 2
            continue
        if c == "|":
            out.append(cur)
            cur = ""
            i += 1
            continue
        cur += c
        i += 1
    out.append(cur)
    return out


def yellow_rows(path: pathlib.Path) -> dict[str, tuple[int, str]]:
    """返回 {FR 编号: (行号, 整行)}，只含**正文定义行**里状态为 🟡 的条目。

    范围切法与 `check-status-consistency.py` 一致：只扫 `## 10.` 之前。
    """
    lines = path.read_text(encoding="utf-8").split("\n")
    body_end = next((i for i, l in enumerate(lines) if l.startswith("## 10.")), len(lines))
    rows: dict[str, tuple[int, str]] = {}
    for index, line in enumerate(lines[:body_end], start=1):
        cells = [c.strip() for c in split_cells(line)]
        if len(cells) < 5 or not REQUIREMENT_ID.fullmatch(cells[0]):
            continue
        status = next((c for c in cells[3:6] if c and c[0] in STATUSES), None)
        if status is None or status[0] != "🟡":
            continue
        rows.setdefault(cells[0], (index, line))
    return rows


def load_ledger(path: pathlib.Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def evaluate(requirements: pathlib.Path, ledger_path: pathlib.Path) -> tuple[list[str], list[str]]:
    """返回 (问题列表, 提示列表)。问题非空即判红。"""
    problems: list[str] = []
    notes: list[str] = []
    rows = yellow_rows(requirements)
    if len(rows) < MIN_YELLOW:
        problems.append(
            f"空跑防护：只解析到 {len(rows)} 条 FR 🟡（下限 {MIN_YELLOW}）—— "
            "要么需求文档的正文定义行被挪走了，要么切法失效；不许当通过"
        )
    ledger = load_ledger(ledger_path)
    items = ledger.get("items", [])
    branches = ledger.get("reasonBranches", {})
    if not isinstance(items, list):
        problems.append("台账 `items` 不是数组")
        return problems, notes
    if not items:
        problems.append("空跑防护：台账 `items` 为空 —— 一本空账也能全绿的话，这条门禁就是没有")
        return problems, notes

    by_id: dict[str, dict] = {}
    for item in items:
        ident = item.get("id", "")
        if ident in by_id:
            problems.append(f"台账里 {ident} 出现两次")
            continue
        by_id[ident] = item

    # A：双向对账
    for ident in sorted(rows):
        if ident not in by_id:
            problems.append(f"{ident}（第 {rows[ident][0]} 行）是 FR 🟡，但台账里没有它的判定条目")
    for ident in sorted(by_id):
        if ident not in rows:
            problems.append(f"台账里的 {ident} 已不是 FR 🟡（修好了要销账，不能留陈旧条目）")

    # B~D：逐条判
    marker_seen: set[str] = set()
    for ident in sorted(by_id):
        item = by_id[ident]
        if ident not in rows:
            continue
        line_number, line = rows[ident]

        # B 正向：台账声明的标记必须在行里逐字出现
        marker = item.get("marker", "")
        if EXCLUSION_TOKEN not in marker:
            problems.append(f"{ident}：台账的 marker 里没有 `{EXCLUSION_TOKEN}`（判定必须显式写出来）")
        elif marker not in line:
            problems.append(
                f"{ident}（第 {line_number} 行）：台账声明的标记未逐字出现在定义行里"
                f"（台账 = {marker!r}）"
            )
        else:
            marker_seen.add(ident)

        # C：原因档必须在词表内
        reason = item.get("reason", "")
        if reason not in branches:
            problems.append(f"{ident}：原因档 {reason!r} 不在台账词表里（{', '.join(sorted(branches))}）")

        # D：至少一个存在的证据指针
        evidence = item.get("evidence") or []
        if not evidence:
            problems.append(f"{ident}：没有任何证据指针（判定要么给可复跑证据，要么给 `[alpha 不含]` 的理由 —— 理由是原因档，证据不能空）")
            continue
        for entry in evidence:
            if not isinstance(entry, dict) or not (entry.get("path") or entry.get("command")):
                problems.append(f"{ident}：证据指针既没有 `path` 也没有 `command`：{entry!r}")
                continue
            target = entry.get("path")
            if target and not (ROOT / target).exists():
                problems.append(f"{ident}：证据指针指向的文件不存在：{target}")

    # B 反向：文档里带标记的 FR 必须在台账里（防止手写标记绕开对账）
    for ident in sorted(rows):
        line_number, line = rows[ident]
        if EXCLUSION_TOKEN in line and ident not in by_id:
            problems.append(f"{ident}（第 {line_number} 行）行内有 `{EXCLUSION_TOKEN}`，但台账里没有这一条")

    notes.append(
        f"FR 🟡 {len(rows)} 条 / 台账 {len(items)} 条 / 标记逐字对上 {len(marker_seen)} 条 / "
        f"原因档 {len(branches)} 类"
    )
    if not problems:
        counts: dict[str, int] = {}
        for item in items:
            counts[item.get("reason", "?")] = counts.get(item.get("reason", "?"), 0) + 1
        detail = " / ".join(f"{k} {counts[k]}" for k in sorted(counts))
        notes.append("档位分布：" + detail)
    return problems, notes


def fingerprint(paths: list[pathlib.Path]) -> dict[str, str]:
    return {
        str(p): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in paths
        if p.exists()
    }


def self_test() -> int:
    """负例自检：一律在**临时副本**上写坏，末例核对真仓库逐字节未变。"""
    before = fingerprint([SRS, LEDGER])
    cases: list[tuple[str, str]] = []
    with tempfile.TemporaryDirectory(prefix="alpha-fr-") as tmp:
        tmpdir = pathlib.Path(tmp)
        base_srs = tmpdir / "需求规范书.md"
        base_ledger = tmpdir / "alpha-fr-dispositions.json"
        shutil.copyfile(SRS, base_srs)
        shutil.copyfile(LEDGER, base_ledger)

        def fresh() -> tuple[pathlib.Path, pathlib.Path]:
            srs = tmpdir / "srs.md"
            led = tmpdir / "ledger.json"
            shutil.copyfile(base_srs, srs)
            shutil.copyfile(base_ledger, led)
            return srs, led

        def mutate_ledger(led: pathlib.Path, fn) -> None:
            data = json.loads(led.read_text(encoding="utf-8"))
            fn(data)
            led.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

        # 0 前提自检：干净副本必须全绿（否则下面每一例的红都说明不了什么）
        srs, led = fresh()
        problems, _ = evaluate(srs, led)
        cases.append(("前提自检：干净副本应全绿", "绿" if not problems else f"红：{problems[0]}"))

        # 1 台账少一条 ⇒ 那条 🟡 没账
        srs, led = fresh()
        mutate_ledger(led, lambda d: d["items"].__delitem__(
            next(i for i, x in enumerate(d["items"]) if x["id"] == "FR-RES-10")))
        problems, _ = evaluate(srs, led)
        cases.append(("漏一条：台账删掉 FR-RES-10", "红" if any("FR-RES-10" in p for p in problems) else "绿（漏判）"))

        # 2 台账多一条（拿一条已 ✅ 的条目充数）⇒ 陈旧条目
        srs, led = fresh()
        mutate_ledger(led, lambda d: d["items"].append({
            "id": "FR-DRV-09", "domain": "3.10 驱动与方言兼容", "reason": "environment",
            "reasonText": "x", "marker": "**[alpha 不含]**（x）",
            "markerPreExisting": True, "evidence": [{"path": "Scripts/verify-all.sh"}]}))
        problems, _ = evaluate(srs, led)
        cases.append(("多一条：台账塞进不再 🟡 的 FR-DRV-09", "红" if any("FR-DRV-09" in p for p in problems) else "绿（漏判）"))

        # 3 台账的标记文本与行内不一致
        srs, led = fresh()
        def change_marker(d):
            for x in d["items"]:
                if x["id"] == "FR-EDIT-36":
                    x["reasonText"] = "文案改了但行里没改"
                    x["marker"] = "**[alpha 不含]**（文案改了但行里没改）"
        mutate_ledger(led, change_marker)
        problems, _ = evaluate(srs, led)
        cases.append(("台账与行内标记不一致", "红" if any("FR-EDIT-36" in p for p in problems) else "绿（漏判）"))

        # 4 行内的标记被删掉（文档侧偷偷销账）
        srs, led = fresh()
        text = srs.read_text(encoding="utf-8")
        text = text.replace(" **[alpha 不含]**（界面点击待人工点验）", "", 1)
        srs.write_text(text, encoding="utf-8")
        problems, _ = evaluate(srs, led)
        cases.append(("行内标记被删", "红" if any("未逐字出现" in p or "没有它的判定条目" in p for p in problems) else "绿（漏判）"))

        # 5 原因档写成词表外的词
        srs, led = fresh()
        mutate_ledger(led, lambda d: [x.update({"reason": "whatever"}) for x in d["items"] if x["id"] == "FR-SESS-01"])
        problems, _ = evaluate(srs, led)
        cases.append(("原因档不在词表", "红" if any("FR-SESS-01" in p for p in problems) else "绿（漏判）"))

        # 6 证据指针指向不存在的文件
        srs, led = fresh()
        mutate_ledger(led, lambda d: [x.update({"evidence": [{"path": "Scripts/no-such-script.sh"}]})
                                      for x in d["items"] if x["id"] == "FR-META-15"])
        problems, _ = evaluate(srs, led)
        cases.append(("证据指针文件不存在", "红" if any("FR-META-15" in p for p in problems) else "绿（漏判）"))

        # 7 证据为空
        srs, led = fresh()
        mutate_ledger(led, lambda d: [x.update({"evidence": []}) for x in d["items"] if x["id"] == "FR-DDL-03"])
        problems, _ = evaluate(srs, led)
        cases.append(("证据为空", "红" if any("FR-DDL-03" in p for p in problems) else "绿（漏判）"))

        # 8 台账为空（空跑）
        srs, led = fresh()
        mutate_ledger(led, lambda d: d.update({"items": []}))
        problems, _ = evaluate(srs, led)
        cases.append(("台账为空（空跑）", "红" if problems else "绿（漏判）"))

        # 9 需求文档里一条定义行都解析不到（空跑）
        srs, led = fresh()
        srs.write_text("# 空文档\n", encoding="utf-8")
        problems, _ = evaluate(srs, led)
        cases.append(("正文定义行全部消失（空跑）", "红" if any("空跑" in p for p in problems) else "绿（漏判）"))

    after = fingerprint([SRS, LEDGER])
    unchanged = before == after
    cases.append(("末例：真仓库两份文件逐字节未变", "绿" if unchanged else "红（被自检改动了）"))

    ok = True
    for name, outcome in cases:
        expected_red = not name.startswith("前提自检") and not name.startswith("末例")
        good = (outcome == "红") if expected_red else (outcome == "绿")
        ok = ok and good
        print(f"  {'✅' if good else '❌'} {name} → {outcome}")
    print(f"{'✅' if ok else '❌'} 负例自检：{len(cases)} 条中 {sum(1 for n, o in cases if (o == '红') == (not n.startswith('前提自检') and not n.startswith('末例')))} 条达到预期")
    return 0 if ok else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--requirements", default=str(SRS))
    parser.add_argument("--ledger", default=str(LEDGER))
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    problems, notes = evaluate(pathlib.Path(args.requirements), pathlib.Path(args.ledger))
    for note in notes:
        print(f"（{note}）")
    if problems:
        print(f"❌ alpha 范围账不通过（{len(problems)} 处）：")
        for item in problems:
            print(f"   {item}")
        print("\n提示：判定要点 —— 能机器验的补证据（脚本 + 可复跑）；不能机器验的逐条标 "
              "`[alpha 不含]`（状态格仍 🟡 不改 ✅）。台账 = `Scripts/alpha-fr-dispositions.json`。")
        return 1
    print("✅ alpha 范围账通过（FR 🟡 逐条有判定：证据指针存在 或 `[alpha 不含]` 已标注）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
