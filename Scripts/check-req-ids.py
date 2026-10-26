#!/usr/bin/env python3
"""需求编号三方对账：正文定义域 ↔ 需求索引 ↔ 计划书台账。

为什么需要它：`check-req-index` 比「正文 ↔ jsonl」、`check-plan-coverage` 比「台账 ↔ 索引」，
两份**派生件**互比永远绿；正文这一侧没人比 —— 实测正文有、索引无 78 条，索引有、正文无 0 条，
而四道门禁全绿。

口径（写死，避免每次临场判）：
  · **正文定义域 = 第 3 章（功能需求）+ 第 4 章（非功能需求）+ 第 7 章（验收标准）**的表格行；
  · **第 5 章数据需求 / 第 6 章接口需求 另账**（`FR-STD-ALL-DATA-*` / `FR-STD-ALL-IFACE-*`），不进索引与台账；
  · **第 8 章风险与待决**同一编号会在「风险登记」与「待决项」两张表各出现一次，属刻意，不进定义域；
  · 台账只认「行首就是编号」的表格行，正文里的「承接 `FR-NOTE-27`」这类引用不算台账行。

用法：check-req-ids.py [--srs 需求书.md] [--index 索引.md] [--plan 计划书.md] [--list]
"""
import argparse, re, sys, pathlib, collections

ID = re.compile(r"(?:FR|NFR|AC)-(?:[A-Z0-9]{2,8}-){1,3}\d{2,3}")
DEF_CH = {"3", "4", "7"}


def rows_of(path):
    text = pathlib.Path(path).read_text(encoding="utf-8")
    chap = None
    out = []
    for i, l in enumerate(text.split("\n")):
        m = re.match(r"^# 第([一二三四五六七八九十]+)章", l)
        if m:
            cn = "一二三四五六七八九"
            v = m.group(1)
            chap = str(cn.index(v) + 1) if v in cn else ("10" if v == "十" else None)
            continue
        if re.match(r"^# 附录", l):
            chap = None
        if l.startswith("|"):
            mid = ID.search(l)
            if mid:
                out.append((i + 1, chap, mid.group(0), l))
    return out


def ids_in(path):
    return set(ID.findall(pathlib.Path(path).read_text(encoding="utf-8")))


def plan_rows(path):
    s = set()
    for l in pathlib.Path(path).read_text(encoding="utf-8").split("\n"):
        if re.match(r"^\|\s*\*{0,2}(?:FR|NFR|AC)-", l):
            m = ID.search(l)
            if m:
                s.add(m.group(0))
    return s


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--srs", default="Docs/Doyah产品需求规格说明书.md")
    ap.add_argument("--index", default="Docs/Doyah产品需求规格说明书-需求索引.md")
    ap.add_argument("--plan", default="Docs/Doyah产品开发计划任务清单.md")
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()
    rows = rows_of(a.srs)
    body = [(n, c, i) for n, c, i, _ in rows if c in DEF_CH]
    inside = [(n, c, i) for n, c, i, _ in rows if c not in DEF_CH]
    defs = [i for _, _, i in body]
    cnt = collections.Counter(defs)
    dup = {k: v for k, v in cnt.items() if v > 1}
    idx, plan = ids_in(a.index), plan_rows(a.plan)
    S, I, P = set(defs), idx & set(defs) | (idx - set(d for _, _, d in inside)), plan

    print(f"正文定义域（第 3/4/7 章）{len(defs)} 行 / {len(set(defs))} 个唯一编号")
    print(f"索引 {len(idx)} · 台账 {len(plan)} · 定义域外（§5/§6/§8）{len({d for _,_,d in inside})} 个")
    bad = 0
    if dup:
        bad += 1
        print(f"❌ 定义域内重复编号 {len(dup)}: {sorted(dup)}")
    miss_idx = sorted(set(defs) - idx)
    if miss_idx:
        bad += 1
        print(f"❌ 正文有、索引无 {len(miss_idx)}: {miss_idx[:12]}")
    extra_idx = sorted(idx - set(defs))
    if extra_idx:
        print(f"ℹ️ 索引有、定义域无 {len(extra_idx)}: {extra_idx[:6]}（§5/§6 另账的条目允许出现在这里）")
    miss_plan = sorted(set(defs) & idx - plan)
    if miss_plan:
        bad += 1
        print(f"❌ 索引有、台账无 {len(miss_plan)}: {miss_plan[:12]}")
    extra_plan = sorted(plan - set(defs))
    if extra_plan:
        bad += 1
        print(f"❌ 台账有、定义域无 {len(extra_plan)}: {extra_plan[:12]}")
    if bad == 0:
        print("✓ 三方对账一致（正文定义域 = 索引 ⊆ 台账）")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
