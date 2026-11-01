#!/usr/bin/env python3
"""四书一单的**层间引用链**普查（只读 · 不入闸）。

为什么要有这一条
----------------
《通用开发规范》§2 把文档体系定成**单向依赖**：

    ① 能力规划（不引下游编号） → ② 需求规格（定义行） → ③ 概要设计 → ④ 详设 → 一单

并且要求「新需求登记一次性落齐派生出口：正文定义行 → 需求索引 → 追溯表 → 平台等价矩阵 → 能力地图，漏一个门禁红」。

but 现有判据只覆盖**成对的点**（一单↔需求书、索引↔一单），没有一条在验**层与层之间的方向**：

- 下游凭空多出一个上游没定义的编号（`FR-STD-WS-HELP-002` 就这么进去过）；
- 上游新定义的编号在下游派生出口漏落（`FR-AGT-KNOW-MEM-006~010` 就这么漏过）。

本脚本是那条链的**普查版**：先只看，不判红，把真实缺口数摆出来。
「普查」与「判据」是两件事：判据必须每条规则配一个必红负例（铁律 #14），
这里还没做，所以它**不许**接进 pre-commit / verify-all。

用法
----
    python3 Scripts/check-doc-chain.py            # 人读报告
    python3 Scripts/check-doc-chain.py --json      # 机器读

覆盖范围（铁律 #13：覆盖不全只许报「未知」，不许报「发现」）
----------------------------------------------------------
本脚本只认**五段式编号**（`<FR|NFR|AC>-<产品码>-<面>-<域>-<三位>`）。
不认：风险号 `R-001`、契约号 `P-xx`、队列号 `Qnn` / `L-nnn`、测试 ID。
某层如果压根不引用需求编号（例如能力书按规矩不许引），报告里写「0 引用（按规矩应为 0）」，
不写成「覆盖到 0 条」——两者意思完全不同。
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# 层序：越靠上越是上游（①不引下游编号，所以它的引用数按规矩应为 0）
LAYERS: list[tuple[str, str, str]] = [
    ("①能力规划", "Docs/Doyah产品能力规划说明书.md", "capability"),
    ("②需求规格", "Docs/Doyah产品需求规格说明书.md", "requirement"),
    ("③概要设计", "Docs/Doyah产品概要设计说明书.md", "design"),
    ("④详细设计", "Docs/Doyah产品详细设计说明书-macOS.md", "detail"),
    ("一单", "Docs/Doyah产品开发计划任务清单-macOS.md", "plan"),
]

# 派生出口（§2 点名的那几个；不在盘上就如实报「未覆盖」）
OUTLETS: list[tuple[str, str]] = [
    ("需求索引", ".build/derived/需求索引.md"),
    ("平台矩阵", ".build/derived/平台矩阵.md"),
    ("按平台清单", ".build/derived/任务清单-按平台.md"),
    ("追溯表", ".build/derived/追溯表.md"),
    ("能力地图", ".build/derived/能力地图.md"),
]

# 编号抽取**放宽到 2~3 位序号**：规范只许三位，但存量里确有两位的（`AC-ALL-GATE-REL-001`）。
# 判据宁可先认出来再按形制点名，也不要因为「形状不符正则」把 15 条当成不存在 ——
# 那正是假阴性：抓不到的东西会被报成「0 条」。形制违规由 R4 单独判。
ID_RE = re.compile(r"\b(?:FR|NFR|AC)-[A-Z]{2,5}(?:-[A-Z0-9]+){1,3}-\d{2,3}\b")
SHAPE_RE = re.compile(r"^(?:FR|NFR|AC)-[A-Z]{2,5}(?:-[A-Z0-9]+){1,3}-\d{3}$")
# 「定义行」= 表格首格就是编号（需求书正文定义行）
DEF_RE = re.compile(r"^\|\s*((?:FR|NFR|AC)-[A-Z]{2,5}(?:-[A-Z0-9]+){1,3}-\d{2,3})\s*\|")

# 各派生出口的**声明口径**（铁律 #13：不清楚口径就报「未知」，不许报「发现」）。
# 每条都要有出处；没有出处的出口一律当「未覆盖」。
OUTLET_RULES: dict[str, dict] = {
    "需求索引": {"exclude_substr": ("-ALL-DATA-", "-ALL-IFACE-"),
                 "source": "gen-req-index.py §render_index 口径 + 需求书 §1.5：数据/接口需求不进总账"},
    "平台矩阵": {"only_prefix": "FR", "exclude_substr": ("-ALL-DATA-", "-ALL-IFACE-"),
                 "source": "gen-platform-parity.py：§5 矩阵只表功能需求，设计层不进"},
    "按平台清单": {"only_prefix": "FR",
                   "source": "gen-platform-board.py 从一单 §3 台账 机械派生（真值源不在盘 ⇒ 见 R5）"},
}


def read(rel: str) -> str | None:
    p = ROOT / rel
    if not p.exists():
        return None
    return p.read_text(encoding="utf-8")


def census() -> dict:
    report: dict = {"layers": {}, "outlets": {}, "rules": {}}
    defined: set[str] = set()
    refs: dict[str, set[str]] = {}

    for label, rel, key in LAYERS:
        text = read(rel)
        if text is None:
            report["layers"][label] = {"file": rel, "status": "missing"}
            continue
        all_ids = set(ID_RE.findall(text))
        defs = {m.group(1) for m in (DEF_RE.match(l) for l in text.splitlines()) if m}
        if key == "requirement":
            defined |= defs
        refs[key] = all_ids
        report["layers"][label] = {
            "file": rel,
            "lines": len(text.splitlines()),
            "ids_mentioned": len(all_ids),
            "definition_rows": len(defs),
        }

    # 规则三：能力书不得出现任何需求编号（§2「不引下游编号」）
    cap = refs.get("capability", set())
    report["rules"]["R3_capability_no_downstream_id"] = {
        "rule": "能力书不得出现任何需求编号（§2「不引下游编号」）",
        "hits": sorted(cap)[:20],
        "count": len(cap),
        "verdict": "绿" if not cap else "红",
    }

    # 规则一：不得凭空 —— 下游引用的编号必须在上游（需求书）定义过
    unexplained: dict[str, list[str]] = {}
    for key, ids in refs.items():
        if key == "capability":
            continue
        orphan = sorted(ids - defined)
        if orphan:
            unexplained[key] = orphan
    report["rules"]["R1_no_invented_id"] = {
        "rule": "下游引用的编号 ⊆ 需求书定义集合（凭空 / 越级 ⇒ 红）",
        "defined_total": len(defined),
        "by_layer": {k: {"count": len(v), "sample": v[:10]} for k, v in unexplained.items()},
        "count": sum(len(v) for v in unexplained.values()),
    }

    # 规则二：不得漏落 —— 上游定义的编号必须在各派生出口出现
    outlet_hits: dict[str, set[str]] = {}
    for label, rel in OUTLETS:
        text = read(rel)
        if text is None:
            report["outlets"][label] = {"file": rel, "status": "未覆盖（派生件不在盘）"}
            continue
        hit = set(ID_RE.findall(text))
        outlet_hits[label] = hit
        # 按该出口的声明口径先算「期望集合」，再比 —— 不按口径算就是假阳性（17 条设计层会天天报红）。
        rule = OUTLET_RULES.get(label, {})
        expected = {x for x in defined if not any(k in x for k in rule.get("exclude_substr", ()))}
        if rule.get("only_prefix"):
            expected = {x for x in expected if x.startswith(rule["only_prefix"] + "-")}
        missing = sorted(expected - hit)
        report["outlets"][label] = {
            "file": rel,
            "ids": len(hit),
            "expected_by_rule": len(expected),
            "rule_source": rule.get("source", "未声明口径 ⇒ 只报「未知」"),
            "missing_of_expected": len(missing),
            "sample_missing": missing[:10],
        }
    per_outlet = {k: v.get("missing_of_expected") for k, v in report["outlets"].items() if "missing_of_expected" in v}
    report["rules"]["R2_no_missing_outlet"] = {
        "rule": "需求书定义的编号必须在该出口**按它自己声明的口径**全部出现",
        "per_outlet_missing": per_outlet,
        "covered_outlets": sorted(outlet_hits),
        "uncovered_outlets": sorted(set(l for l, _ in OUTLETS) - set(outlet_hits)),
        "count": sum(per_outlet.values()) if per_outlet else None,
    }

    # 规则四：编号形制（§2 五段式 · 序号三位）
    bad_shape = sorted(x for x in defined if not SHAPE_RE.match(x))
    report["rules"]["R4_id_shape"] = {
        "rule": "编号必须是五段式且序号三位（§2）",
        "count": len(bad_shape),
        "sample": bad_shape[:20],
    }

    report["defined_total"] = len(defined)
    return report


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    rep = census()

    if args.json:
        print(json.dumps(rep, ensure_ascii=False, indent=2))
        return 0

    print("== 四书一单 · 层间引用链普查（只读，不判红）==")
    print("\n-- 各层规模 --")
    for label, info in rep["layers"].items():
        if info.get("status") == "missing":
            print(f"  {label}: **不在盘**（{info['file']}）")
            continue
        note = "（按 §2 应为 0）" if label.startswith("①") else ""
        print(f"  {label}: {info['lines']} 行 · 提及唯一编号 {info['ids_mentioned']}{note} · 定义行 {info['definition_rows']}")
    print(f"  需求书定义集合合计：**{rep['defined_total']}** 条")

    r1 = rep["rules"]["R1_no_invented_id"]
    print("\n-- 规则一 · 不得凭空（下游引用了需求书没定义的编号）--")
    if not r1["by_layer"]:
        print("  ✅ 0 条")
    for layer, d in r1["by_layer"].items():
        print(f"  {layer}: **{d['count']}** 条 · 例：{', '.join(d['sample'][:5])}")

    r2 = rep["rules"]["R2_no_missing_outlet"]
    print("\n-- 规则二 · 不得漏落（需求书有、派生出口没有）--")
    for label, info in rep["outlets"].items():
        if info.get("status"):
            print(f"  {label}: {info['status']}")
        else:
            print(f"  {label}: 收录 {info['ids']} 个 · 按其口径应收 {info['expected_by_rule']} 个 · 缺 **{info['missing_of_expected']}** 个")
            if info["missing_of_expected"]:
                print(f"      例：{', '.join(info['sample_missing'][:5])}")
    if r2["uncovered_outlets"]:
        print(f"  ⚠️ 未覆盖出口（派生件不在盘 ⇒ 报「未知」，不报「发现」）：{', '.join(r2['uncovered_outlets'])}")

    r3 = rep["rules"]["R3_capability_no_downstream_id"]
    print(f"\n-- 规则三 · 能力书不引下游编号 --\n  {r3['verdict']}：命中 {r3['count']} 处")

    r4 = rep["rules"]["R4_id_shape"]
    print(f"\n-- 规则四 · 编号形制（五段式 · 序号三位）--\n  违规 **{r4['count']}** 条 · 例：{', '.join(r4['sample'][:5])}")

    print("\n口径：只认五段式 `<FR|NFR|AC>-<产品码>-<面>-<域>-<三位>`；不认 R-xxx / P-xx / Qnn / L-nnn。")
    print("本脚本尚未配必红负例 ⇒ **不许**接进 pre-commit / verify-all（铁律 #14）。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
