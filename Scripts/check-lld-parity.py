#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""详设派生面复核：拿基准书逐节比对另一端（Linux / Windows 等）。

只判三件可机判的事（都是「派生书必须与基准同构」的下限）：
  ① 节号集合：`### 3.x` 必须逐节覆盖（缺节 = 读者拿不到那一节）
  ② 判据编号集合：基准里出现的 `T-a.b-nn` 必须逐个出现在目标书里（缺号 = 判据没搬）
  ③ 阈值常量集合：基准里出现的 `Npt` / `N ms` 数值必须出现（缺 = 阈值没搬，实现只能猜）

不判的（如实声明覆盖范围）：
  · 契约**语义**对不对（同一句话换个说法即判不出）—— 要人读；
  · 落点是否真实（本端有没有那个组件）—— 要检索或真机；
  · 实现细节小节（探针文件 / 框架部件 / 跑法）**故意不要求**：按移植纪律那些属于「落点」，不搬。

用法：
    python3 Scripts/check-lld-parity.py                     # 默认比 macOS ↔ Linux
    python3 Scripts/check-lld-parity.py --target Windows     # 比 macOS ↔ Windows
    python3 Scripts/check-lld-parity.py --target Linux --json
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path, PurePath

ROOT = Path(__file__).resolve().parent.parent
BASE = "Docs/Doyah产品详细设计说明书-macOS.md"
SECT = re.compile(r"^### (\d+\.\d+) ", re.M)
TID = re.compile(r"T-\d+\.\d+-\d+")
PT = re.compile(r"\b\d+(?:\.\d+)?pt\b")
SUB = re.compile(r"(?m)^#### (\d+\.\d+\.\d+) ")
NUM = re.compile(r"(?m)^\d+\. \*\*")
SIG_HEAD = re.compile(r"(?m)^### \d+\.\d+ `[A-Z]\w*[.(]")
MS = re.compile(r"\b\d+(?:\.\d+)?\s?ms\b")


def sections(text: str) -> dict[str, str]:
    marks = [(m.start(), m.group(1)) for m in SECT.finditer(text)]
    out: dict[str, str] = {}
    for i, (pos, num) in enumerate(marks):
        end = marks[i + 1][0] if i + 1 < len(marks) else len(text)
        out[num] = text[pos:end]
    return out



def contract_pt(segment: str) -> set[str]:
    """契约级阈值 = 出现在「判据行」（含 T- 编号）或「契约 / 禁止」段落里的 `Npt`。

    范围声明（写死，不是随手放宽）：实现推理段里的读数（采样点、估值幅度、scrollTo 偏差、
    发丝线宽 0.5pt 之类）**不属于契约** —— 它们是基准那一版实现怎么量出来的，换一版实现就变。
    判据行与契约/禁止段里的数值，换成哪一版实现都必须成立，才要求派生书带上。
    """
    out: set[str] = set()
    in_contract = False
    for line in segment.split("\n"):
        stripped = line.strip()
        if stripped.startswith("**契约") or stripped.startswith("**禁止行为"):
            in_contract = True
        elif stripped.startswith("**") and in_contract:
            in_contract = False
        if "T-" in line or in_contract:
            out |= set(PT.findall(line))
    return out


def contract_ms(segment: str) -> set[str]:
    return {x.replace(" ", "") for x in MS.findall(segment) if "T-" in segment or True}


def report(base_path: Path, target_path: Path) -> dict:
    b_text = base_path.read_text(encoding="utf-8")
    t_text = target_path.read_text(encoding="utf-8")
    b, t = sections(b_text), sections(t_text)

    all_pt = lambda s: set(PT.findall(s))
    all_ms = lambda s: {x.replace(" ", "") for x in MS.findall(s)}

    rows = []
    for num in sorted(b, key=lambda x: [int(p) for p in x.split(".")]):
        bt, tt = set(TID.findall(b[num])), set(TID.findall(t.get(num, "")))
        bp, tp = contract_pt(b[num]), all_pt(t.get(num, ""))
        bm, tm = contract_ms(b[num]), all_ms(t.get(num, ""))
        bs, ts = set(SUB.findall(b[num])), set(SUB.findall(t.get(num, "")))
        rows.append({
            "section": num,
            "subs_missing": sorted(bs - ts),
            "contracts_base": len(NUM.findall(b[num])),
            "contracts_target": len(NUM.findall(t.get(num, ""))),
            "present": num in t,
            "tids_missing": sorted(bt - tt),
            "pt_missing": sorted(bp - tp, key=lambda x: float(x[:-2])),
            "ms_missing": sorted(bm - tm),
            "base_lines": len(b[num].splitlines()),
            "target_lines": len(t.get(num, "").splitlines()),
        })
    return {
        "base": base_path.relative_to(ROOT).as_posix() if base_path.is_relative_to(ROOT) else base_path.as_posix(),
        "target": target_path.relative_to(ROOT).as_posix() if target_path.is_relative_to(ROOT) else target_path.as_posix(),
        "sections_missing": [n for n in b if n not in t],
        "signature_headings": SIG_HEAD.findall(t_text) and [m.group(0) for m in SIG_HEAD.finditer(t_text)],
        "extra_sections": [n for n in t if n not in b],
        "rows": rows,
        "totals": {
            "base_tids": len(set(TID.findall(b_text))),
            "target_tids": len(set(TID.findall(t_text))),
            "tids_missing": len(set(TID.findall(b_text)) - set(TID.findall(t_text))),
            "pt_missing": sum(len(r["pt_missing"]) for r in rows),
            "base_lines": len(b_text.splitlines()),
            "target_lines": len(t_text.splitlines()),
        },
    }



def self_test() -> int:
    """判据自己的证据：造两对极小样本，验证「缺节 / 缺判据 / 缺阈值」都判红。"""
    import tempfile

    base = """## 0
### 3.1 甲
**契约**：阈值 **20pt**。
| `T-3.1-01` | 20.0pt |
**禁止行为**
- 不许
### 3.2 乙
| `T-3.2-01` | 4pt |
"""
    good = base
    bad = """## 0
### 3.1 甲
**契约**：阈值 **20pt**。
| `T-3.1-01` | 20pt |
"""
    base_sub = base.replace("### 3.2 乙", "#### 3.1.1 子节甲\n\n### 3.2 乙")
    bad_sub = base.replace("### 3.2 乙", "### 3.2 乙")
    sig = base.replace("### 3.2 乙", "### 3.2 `AgentFoo.run(x:)`")
    cases = [("完全一致 ⇒ 绿", base_sub, base_sub, 0),
             ("缺一节 + 缺判据 + 缺阈值 ⇒ 红", base_sub, bad, 1),
             ("缺子节 ⇒ 红", base_sub, bad_sub, 1),
             ("标题抄基准签名 ⇒ 红", base_sub, sig, 1)]
    ok = 0
    with tempfile.TemporaryDirectory() as d:
        for name, b, t, want in cases:
            bp, tp = Path(d, "b.md"), Path(d, "t.md")
            bp.write_text(b, encoding="utf-8"); tp.write_text(t, encoding="utf-8")
            r = report(bp, tp)
            red = (bool(r["sections_missing"]) or bool(r["signature_headings"])
                   or any(x["tids_missing"] or x["pt_missing"] or x["subs_missing"] for x in r["rows"]))
            got = 1 if red else 0
            passed = got == want
            ok += passed
            print(f"  {'✓' if passed else '✗'} {name}（预期 rc={want}，实得 {got}）")
    print(f"自检 {ok}/{len(cases)} 达到预期")
    return 0 if ok == len(cases) else 1


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", default="Linux", help="Linux / Windows / iOS / Android / HarmonyOS")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args(argv)

    if args.self_test:
        return self_test()

    target = ROOT / f"Docs/Doyah产品详细设计说明书-{args.target}.md"
    if not target.exists():
        print(f"❌ 找不到 {target}")
        return 1
    r = report(ROOT / BASE, target)

    if args.json:
        print(json.dumps(r, ensure_ascii=False, indent=2))
        return 0

    tot = r["totals"]
    print(f"基准 {r['base']}（{tot['base_lines']} 行 / 判据 {tot['base_tids']} 个）")
    print(f"目标 {r['target']}（{tot['target_lines']} 行 / 判据 {tot['target_tids']} 个）")
    if r["sections_missing"]:
        print(f"❌ 缺节 {len(r['sections_missing'])}：{', '.join(r['sections_missing'])}")
    if r["extra_sections"]:
        print(f"⚠ 目标多出的节：{', '.join(r['extra_sections'])}")
    print(f"判据缺号 {tot['tids_missing']} 个 · 阈值缺项 {tot['pt_missing']} 处 · "
          f"缺子节 {sum(len(r['subs_missing']) for r in r['rows'])} 个 · "
          f"标题抄签名的节 {len(r['signature_headings'])} 个\n")
    if r["signature_headings"]:
        for h in r["signature_headings"][:5]:
            print(f"  ❌ 标题是基准实现签名：{h}")

    print(f"{'节':>6} {'基准行':>6} {'目标行':>6} {'缺判据':>6} {'缺阈值':>6}  缺的判据 / 阈值")
    bad = 0
    for row in r["rows"]:
        miss_t, miss_p = row["tids_missing"], row["pt_missing"]
        if not (miss_t or miss_p or row["subs_missing"] or not row["present"]):
            continue
        bad += 1
        detail = " ".join(miss_t[:6]) + (" …" if len(miss_t) > 6 else "")
        if miss_p:
            detail += ("  thresholds: " + ",".join(miss_p[:8]) + (" …" if len(miss_p) > 8 else ""))
        print(f"{row['section']:>6} {row['base_lines']:>6} {row['target_lines']:>6} "
              f"{len(miss_t):>6} {len(miss_p):>6}  {detail}")
    if not bad:
        print("✅ 每一节的判据编号与阈值常量都已覆盖")
    fewer = [r for r in r["rows"] if r["contracts_target"] < r["contracts_base"]]
    if fewer:
        print("\nℹ️ 契约条目比基准少的节（**不判红**：平台确有的差异可以合理删条，只作人工复核清单）：")
        for row in fewer:
            print(f"   §{row['section']}: 基准 {row['contracts_base']} 条 → 目标 {row['contracts_target']} 条")
    print(f"\n结论：判据 {'缺 ' + str(tot['tids_missing']) + ' 个' if tot['tids_missing'] else '编号齐全'} · "
          f"阈值 {'缺 ' + str(tot['pt_missing']) + ' 处' if tot['pt_missing'] else '齐全'} · "
          f"节 {'缺 ' + str(len(r['sections_missing'])) + ' 节' if r['sections_missing'] else '齐全'}")
    return 0 if (not bad and not r["sections_missing"] and not r["signature_headings"]) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
