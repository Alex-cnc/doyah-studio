#!/usr/bin/env python3
"""Windows 开发计划生成器（本侧维护面 · 只读三书 + 台账，写本侧计划）

由头（人类主人 2026-10-20）：「本端开发计划需要自己维护，等三书核对完成后你负责更新」。
做法：**计划是派生物** —— 能力条目数与 FR 状态全部现读现算，不手抄；三书一改，重跑即同步。

读：
  · `Docs/Doyah产品能力规划说明书.md`  —— 三级标题 = 能力条目（按章节归属产品面）
  · `Docs/Doyah产品开发计划书.md`        —— §5 平台等价矩阵（FR 行 + 四端状态列）
  · `Docs/平台实现状态.json`             —— 各端台账（Windows 的显式登记）
写：
  · `Platform/windows/开发计划-Windows.md`

用法：
  python Platform/windows/开发循环/gen-win-plan.py            # 写计划
  python Platform/windows/开发循环/gen-win-plan.py --check    # 只比对，漂移则非零退出
"""
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
CAP = os.path.join(ROOT, "Docs", "Doyah产品能力规划说明书.md")
PLAN = os.path.join(ROOT, "Docs", "Doyah产品开发计划书.md")
LEDGER = os.path.join(ROOT, "Docs", "平台实现状态.json")
OUT = os.path.join(ROOT, "Platform", "windows", "开发计划-Windows.md")

# 产品面 → FR 域前缀（本侧口径；细化到「能力条目 ↔ FR 编号」需要前门在能力书里加编号）
# (产品面, FR 域, 是否进 Windows 分母)
# 口径（人类主人 2026-10-20 纠正）：**本侧** = Windows / Linux / 安卓 / 鸿蒙 四版，Doyah Notes 是
# 本侧自己的产品（Android 面，beta1.0 已发）—— 它只是**不跑在 Windows 列上**，不是"非本端产品"。
SURFACES = [
    ("Doyah Agent", ["AI"], True),
    ("Studio · Workspace", ["EDIT"], True),
    ("Studio · Database Client",
     ["CONN", "EXEC", "RES", "META", "DDL", "DATA", "SESS", "DIAG", "IO", "DRV", "PLUG", "BLD", "CLI"], True),
    ("Doyah Retro", ["R"], True),
    ("Doyah Notes（本侧 Android 产品 · 不进 Windows 列）", ["NOTE"], False),
]


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def capability_counts():
    """按章节统计能力条目（三级标题）。"""
    text = read(CAP)
    chapter = ""
    section = ""
    counts = {}
    for line in text.splitlines():
        top = re.match(r"^# (第.章.*)$", line)
        if top:
            chapter = top.group(1)
            section = ""
            continue
        second = re.match(r"^## (\d+\.\d+ .*)$", line)
        if second:
            section = second.group(1)
            counts.setdefault((chapter, section), 0)
            continue
        if re.match(r"^### \d+\.\d+\.\d+ ", line) and section:
            counts[(chapter, section)] += 1
    return counts


def matrix_rows():
    """§5 平台等价矩阵 → {FR: 四端状态}（列序：macOS / watchOS / Linux / Windows）。"""
    text = read(PLAN)
    status = re.compile(r"^[✅🟡⬜➖]")
    rows = {}
    for line in text.splitlines():
        if not line.startswith("| FR-"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 6:
            continue
        if all(status.match(cells[-4 + i]) for i in range(4)):
            rows.setdefault(cells[0], cells[-4:])
    return rows


def surface_of(fr_id):
    domain = fr_id.split("-")[1]
    for name, domains, _in_column in SURFACES:
        if domain in domains:
            return name
    return "未归类"


def build():
    caps = capability_counts()
    rows = matrix_rows()
    ledger = json.loads(read(LEDGER))
    overrides = ledger["platforms"]["windows"]["overrides"]

    buckets = {}
    for fr_id, cols in rows.items():
        name = surface_of(fr_id)
        entry = buckets.setdefault(name, {"total": 0, "done": 0, "partial": 0, "todo": 0, "gaps": []})
        mark = cols[3][0]
        entry["total"] += 1
        if mark == "✅":
            entry["done"] += 1
        elif mark == "🟡":
            entry["partial"] += 1
            entry["gaps"].append((fr_id, "🟡 部分"))
        else:
            entry["todo"] += 1
            entry["gaps"].append((fr_id, mark or "⬜"))

    lines = []
    lines.append("# Windows 开发计划（派生件 · 勿手改）")
    lines.append("")
    lines.append("> **这份文件是派生品**：能力条目数与 FR 状态全部由 "
                 "`Platform/windows/开发循环/gen-win-plan.py` 现读现算（来源 = 能力规划说明书 / 开发计划书 §5 / 平台实现状态台账）。")
    lines.append("> 三书或台账一改，重跑生成器即同步；手改会在 `--check` 时被判红。")
    lines.append("")
    in_column = {name for name, _d, flag in SURFACES if flag}
    total = sum(b["total"] for name, b in buckets.items() if name in in_column)
    done = sum(b["done"] for name, b in buckets.items() if name in in_column)
    other_total = sum(b["total"] for name, b in buckets.items() if name not in in_column)
    lines.append("## 1. 总量")
    lines.append("")
    lines.append("| 项 | 值 |")
    lines.append("|---|---:|")
    lines.append("| 平台等价矩阵 FR 行数 | %d |" % total)
    lines.append("| Windows ✅ | %d |" % done)
    lines.append("| **Windows 完成度** | **%d%%** |" % (round(100 * done / total) if total else 0))
    lines.append("| 台账 Windows 显式登记 | %d 条 |" % len(overrides))
    lines.append("| 未进 Windows 列的本侧产品 FR（Doyah Notes） | %d 条（不计入上面的完成度） |" % other_total)
    lines.append("")

    lines.append("## 2. 按产品面（完成度 = ✅ / 该面 FR 数）")
    lines.append("")
    lines.append("| 产品面 | 能力条目 | FR 条数 | ✅ | 🟡 | ⬜ | 完成度 |")
    lines.append("|---|---:|---:|---:|---:|---:|---:|")
    for name, domains, _flag in SURFACES:
        bucket = buckets.get(name)
        if not bucket:
            continue
        cap_count = sum(v for (chapter, section), v in caps.items()
                        if any(prefix in chapter or prefix in section for prefix in [name.split(" ")[-1]]) )
        pct = round(100 * bucket["done"] / bucket["total"]) if bucket["total"] else 0
        lines.append("| %s | %s | %d | %d | %d | %d | **%d%%** |" %
                     (name, cap_count if cap_count else "—", bucket["total"],
                      bucket["done"], bucket["partial"], bucket["todo"], pct))
    lines.append("")

    lines.append("## 3. 批次与顺序（本侧自定）")
    lines.append("")
    lines.append("| 批 | 面 | 缺口 | 说明 |")
    lines.append("|---|---|---:|---|")
    for name in ("Studio · Database Client", "Studio · Workspace", "Doyah Agent", "Doyah Retro"):
        bucket = buckets.get(name)
        if not bucket:
            continue
        lines.append("| — | %s | %d 条 | 见 §4 缺口清单 |" % (name, bucket["total"] - bucket["done"]))
    lines.append("")

    lines.append("## 4. 缺口清单（逐条可追）")
    lines.append("")
    for name, _d, _f in SURFACES:
        bucket = buckets.get(name)
        if not bucket or not bucket["gaps"]:
            continue
        lines.append("### %s（%d 条）" % (name, len(bucket["gaps"])))
        lines.append("")
        for fr_id, mark in bucket["gaps"]:
            lines.append("- `%s` %s" % (fr_id, mark))
        lines.append("")

    lines.append("## 5. 已知口径缺口（不猜，留白并点名）")
    lines.append("")
    lines.append("- **能力条目 ↔ FR 编号没有对应关系**：能力规划说明书的三级标题不带编号，"
                 "本表只能按「产品面 → FR 域」粗对；要逐条判「这条能力做完了没」，需前门在能力书里补编号或映射表。")
    lines.append("- 本节由生成器固定输出，不是漏写。")
    lines.append("")
    return "\n".join(lines)


def main():
    content = build()
    if "--check" in sys.argv:
        if not os.path.exists(OUT):
            print("✗ 计划文件不存在：%s" % OUT)
            return 1
        current = read(OUT)
        if current != content:
            print("✗ 计划与三书/台账不一致，请重跑生成器：%s" % OUT)
            return 1
        print("✅ 计划与三书/台账一致")
        return 0
    with open(OUT, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(content)
    print("✅ 已写出 %s" % OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
