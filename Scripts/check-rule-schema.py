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
# shared-surface：2026-11-10 主人令 —— 两侧共用判据；新增「单向引用」判据（通用条文不得引用项目规范，只能反过来），带正反两例

from __future__ import annotations

import json
import re
import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS = ROOT / "Docs"
SCHEMA = ROOT / "Scripts" / "rule-schema.json"
BASELINE = ROOT / "Scripts" / "rule-schema-baseline.json"

# 单向引用（2026-11-10 人类主人令）：**通用规范条文不许引用项目规范**，只能反过来
# （项目规范可以写「见《通用开发规范》§X」）。理由：通用规范要能整体搬到另一个项目，
# 里面一旦出现「见《项目管理规范》§5」这种指回，搬过去就是悬空引用。
GENERIC_BOOK = "通用开发规范.md"
PROJECT_REF = re.compile(r"《项目管理规范》|项目管理规范\s*§\s*\d")
PROJECT_REF = re.compile(r"《项目管理规范》|项目管理规范\s*§\s*\d")

# 条文点名的脚本必须存在（2026-11-10）：条文里写 `Scripts/xxx.py` 是「判据在哪」的唯一线索，
# 脚本删了而条文没改 ⇒ 判据静默悬空，到有人真去跑才发现。这里把悬空引用当场判红。
SCRIPT_REF = re.compile(r"(?:\./)?Scripts/([A-Za-z0-9_.\-]+\.(?:py|sh))")
SCRIPT_GONE = ("已删", "已移除", "已退场", "归档到", "搬走")   # 明确写了「已经没了」的行不算悬空


def dangling_scripts(text: str, schema: dict) -> list[str]:
    """条文里点名但文件不存在的脚本（空列表 = 没有悬空引用）。"""
    names = set(schema["字段"].keys())
    missing = []
    for title, body in split_clauses(text, names):
        for line in body.split("\n"):
            if any(k in line for k in SCRIPT_GONE):
                continue
            for m in SCRIPT_REF.finditer(line):
                if not (ROOT / "Scripts" / m.group(1)).exists():
                    missing.append(f"{title}⇒Scripts/{m.group(1)}")
    return missing


def project_refs(text: str, schema: dict) -> list[str]:
    """通用规范里引用了项目规范的条文标题（空列表 = 单向干净）。"""
    names = set(schema["字段"].keys())
    return [title for title, body in split_clauses(text, names) if PROJECT_REF.search(body)]
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
    required = [f for f, spec in schema["字段"].items() if spec.get("必填")]  # 「是什么」由首行承载，不在此列
    names = set(schema["字段"].keys())
    total = complete = 0
    problems: list[str] = []
    for title, body in split_clauses(text, names):
        total += 1
        missing = [f for f in required if f"**{f}**" not in body]
        head = body.split("\n")[0]
        head_text = head.split("：", 1)[1].strip() if "：" in head else ""
        # 「是什么」两种合法承载：单列 `- **是什么**：` 一行，或直接写在条文首行标题之后
        if "**是什么**" not in body and len(head_text) < 8:
            missing.insert(0, "是什么（既无独立字段，首行正文也不足 8 字）")
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
        text = path.read_text(encoding="utf-8")
        total, complete, problems = audit(text, schema)
        if name == GENERIC_BOOK:
            for title in project_refs(text, schema):
                bad.append(f"{name}: 条文「{title}」引用了项目规范 —— 只许项目规范引用本件（单向）")
        for miss in dangling_scripts(text, schema):
            bad.append(f"{name}: 条文点名的脚本不存在 —— 「{miss}」（判据悬空，删脚本必须同批改条文）")
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
    print("   覆盖范围：只判条文里**明文写的** `Scripts/<文件名>` 是否存在 —— "
          "`import 模块名`（不带 .py）、跨仓引用、cron / launchd 调用判不了，"
          "那三类靠「挪而不删 + 全量门禁跑一遍」兜（见 Scripts/archive/README.md）")
    return 0


def self_test(schema: dict) -> int:
    good = """- **样例条文**：这条条文的首行正文承载「是什么」，长度必须够八个字
- **是什么**：一句话。
- **不是什么**：边界。
- **判据**：【机判】`true`。
- **负例**：改坏必红。
- **读数口径**：无。
- **归属**：本条文自身。
"""
    miss_negative = good.replace("- **负例**：改坏必红。\n", "")
    no_judge_kind = good.replace("【机判】", "")
    ghost_script = good.replace("- **判据**：【机判】`true`。", "- **判据**：【机判】`Scripts/no-such-gate.py`。")
    cites_project = good.replace("- **读数口径**：无。", "- **读数口径**：见《项目管理规范》§5。")
    generic_ok = good  # 同一条文放进「通用」这一侧，只要不引用项目规范就该绿
    cases = [
        ("六字段齐全", good, True),
        ("缺负例字段", miss_negative, False),
        ("判据没标机判/人判", no_judge_kind, False),
        ("通用条文引用项目规范 ⇒ 判红", cites_project, False),
        ("通用条文不引用项目规范 ⇒ 绿", generic_ok, True),
        ("条文点名不存在的脚本 ⇒ 判红", ghost_script, False),
    ]
    ok = 0
    for name, text, want_pass in cases:
        total, complete, problems = audit(text, schema)
        passed = total == 1 and not problems and not project_refs(text, schema) and not dangling_scripts(text, schema)
        mark = "✓" if passed == want_pass else "✗"
        if passed == want_pass:
            ok += 1
        print(f"  {mark} {name} ⇒ {'绿' if passed else '红'}，应为{'绿' if want_pass else '红'}")
    print(f"自检 {ok}/{len(cases)} 达到预期")
    return 0 if ok == len(cases) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
