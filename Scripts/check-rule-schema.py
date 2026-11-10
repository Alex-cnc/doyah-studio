#!/usr/bin/env python3
"""条文写法判据 —— 规范条文必须带齐六字段（是什么 / 不是什么 / 判据 / 负例 / 读数口径 / 归属）。

依据：Scripts/rule-schema.json（机读权威）+ 《通用开发规范》§4 首段（人读说明）。

覆盖范围（不许含糊）：
- 只验「字段在场」与「判据标了【机判】/【人判】」，**不验内容对不对**。
- 只扫两本规范：《通用开发规范》《项目管理规范》。三书一单的判据行不归本脚本（它们由各书判据行 + 各自脚本管）。
- 存量条文允许暂缺字段（棘轮：数量记在 rule-schema-baseline.json，只许降不许升）。

判红三情形：
1) 条文「缺字段条数」比基线多 ⇒ 红（新条文不许裸奔，旧条文不许倒退）
2) 「六字段齐全条数」比基线少 ⇒ 红（有人把完整条文改回散文）
3) 解析到的条文总数低于基线 ⇒ 红（空跑防护：解析器坏了，不是规范变好了）

负例（--self-test 内固化）：一条缺「负例」字段的条文必须判红。
"""

from __future__ import annotations

import json
import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS = ROOT / "Docs"
SCHEMA = ROOT / "Scripts" / "rule-schema.json"
BASELINE = ROOT / "Scripts" / "rule-schema-baseline.json"
BOOKS = ["Doyah产品需求规格说明书_不做.md"]  # 占位，实际用下面 NORMS
NORMS = ["通用开发规范.md", "项目管理规范.md"]

# 条文起行：`- **标题**：` / `1. **标题**：` / `- **标题**（2016-09-29 定）。`
# 口径：**带「判据」声明的条目**才算条文（没声明判据的是叙述，不是条文）。
CLAUSE_RE = re.compile(r"^(?:-|\d+\.) \*\*(?P<title>[^*]{2,120}?)\*\*(?:（[^）]{0,120}）)?[：:。]?")


def load_schema() -> dict:
    return json.loads(SCHEMA.read_text(encoding="utf-8"))


def fields_of(schema: dict) -> list[str]:
    return list(schema["字段"].keys())


def split_clauses(text: str, field_names: set[str], require_judge: bool = True) -> list[tuple[str, str]]:
    """切条文：返回 [(title, body)]。body = 该条起到下一个条文/标题为止。

    字段行（如 `- **判据**：…`）是条文的组成部分，不是新条文 —— 必须排除，
    否则六字段齐全的条文会被切成 7 条（自检「六字段齐全」曾因此误判红）。
    """
    lines = text.split("\n")
    out: list[tuple[str, str]] = []
    cur_title: str | None = None
    cur: list[str] = []
    for line in lines:
        if line.startswith("#"):
            if cur_title is not None:
                out.append((cur_title, "\n".join(cur)))
                cur_title, cur = None, []
            continue
        m = CLAUSE_RE.match(line)
        if m and m.group("title") in field_names:
            if cur_title is not None:
                cur.append(line)
            continue
        if m:
            if cur_title is not None:
                out.append((cur_title, "\n".join(cur)))
            cur_title, cur = m.group("title"), [line]
            continue
        if cur_title is not None:
            cur.append(line)
    if cur_title is not None:
        out.append((cur_title, "\n".join(cur)))
    if require_judge:
        out = [(t, b) for (t, b) in out if "**判据**" in b or "判据：" in b]
    return out


def audit(text: str, schema: dict) -> tuple[int, int, list[str]]:
    """返回 (总数, 完整数, 问题列表)。问题列表只列「缺了必填字段」的条文。"""
    required = [f for f, spec in schema["字段"].items() if spec.get("必填")]
    names = set(schema["字段"].keys())
    total = complete = 0
    problems: list[str] = []
    for title, body in split_clauses(text, names):
        total += 1
        missing = [f for f in required if f"**{f}**" not in body]
        has_judge = "**判据**" in body
        if has_judge and ("【机判】" not in body and "【人判】" not in body):
            problems.append(f"「{title}」判据没标【机判】还是【人判】")
        if not missing:
            complete += 1
        else:
            problems.append(f"「{title}」缺：{' / '.join(missing)}")
    return total, complete, problems


def main(argv: list[str]) -> int:
    schema = load_schema()
    if "--self-test" in argv:
        return self_test(schema)

    base = json.loads(BASELINE.read_text(encoding="utf-8")) if BASELINE.exists() else {}
    bad: list[str] = []
    rows: list[str] = []
    new_base: dict[str, dict] = {}
    for name in NORMS:
        path = DOCS / name
        total, complete, problems = audit(path.read_text(encoding="utf-8"), schema)
        incomplete = total - complete
        prev = base.get(name, {})
        first_baseline = "--write-baseline" in argv and name not in base
        floor_total = prev.get("总数", 0)
        prev_incomplete = prev.get("缺字段", 0)
        if total < floor_total:
            bad.append(f"{name}: 只解析到 {total} 条条文 < 基线 {floor_total}（空跑防护：解析器坏了或被删条文）")
        if incomplete > prev_incomplete and not first_baseline:
            bad.append(f"{name}: 缺字段条文 {incomplete} 条 > 基线 {prev_incomplete} 条（新条文不许裸奔）")
        if complete < prev.get("完整", 0) and not first_baseline:
            bad.append(f"{name}: 六字段完整 {complete} 条 < 基线 {prev.get('完整', 0)} 条（不许把完整条文改回散文）")
        rows.append(f"  {name}: 条文 {total} 条 · 完整 {complete} · 缺字段 {incomplete}")
        new_base[name] = {"总数": max(total, floor_total), "完整": max(complete, prev.get("完整", 0)),
                          "缺字段": min(incomplete, prev_incomplete) if prev else incomplete}
        for p in problems[:40]:
            rows.append(f"    · {p}")

    print("条文写法判据（六字段）")
    print("\n".join(rows))
    if bad:
        print("❌ 条文写法未通过：")
        for b in bad:
            print("  ·", b)
        return 1
    if "--write-baseline" in argv:
        BASELINE.write_text(json.dumps(new_base, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"基线已写：{BASELINE.name}")
    print("✅ 条文写法通过（缺字段只许降不许升）")
    return 0


def self_test(schema: dict) -> int:
    good = """- **样例条文**：示例
- **是什么**：一句话。
- **不是什么**：边界。
- **判据**：【机判】`true`。
- **负例**：改坏必红。
- **读数口径**：无。
- **归属**：本条文自身。
"""
    miss_negative = good.replace("- **负例**：改坏必红。\n", "")
    no_judge_kind = good.replace("【机判】", "")
    cases = [
        ("六字段齐全", good, True),
        ("缺负例字段", miss_negative, False),
        ("判据没标机判/人判", no_judge_kind, False),
    ]
    ok = 0
    for name, text, want_pass in cases:
        total, complete, problems = audit(text, schema)
        passed = total == 1 and not problems
        mark = "✓" if passed == want_pass else "✗"
        if passed == want_pass:
            ok += 1
        print(f"  {mark} {name} ⇒ {'绿' if passed else '红'}，应为{'绿' if want_pass else '红'}")
    print(f"自检 {ok}/{len(cases)} 达到预期")
    return 0 if ok == len(cases) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
