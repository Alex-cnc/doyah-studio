#!/usr/bin/env python3
"""从《Doyah产品需求规格说明书》的表格生成机器视图 `Docs/requirement-index.jsonl`。

口径（2026-10-20 定）：
- 人读 markdown、机读 jsonl，**两者同源**：jsonl 只许由本脚本产出，不许手改。
- 每条需求一行；`criteria` 是判据（①②③…），`not_do` 是该条的下限，`not_do_full` 是本节能力点
  「不是什么」的全文（来自能力书，按节名对齐），`evidence` 留给实现位置（现状为空，由追溯表承接）。
- 漂移检查见 `Scripts/check-req-index.py`。

用法：python3 Scripts/gen-req-index.py [--check]
"""
import json
import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRS = ROOT / "Docs/Doyah产品需求规格说明书.md"
CAP = ROOT / "Docs/Doyah产品能力规划说明书.md"
OUT = ROOT / "Docs/requirement-index.jsonl"
ID = re.compile(r"^(FR|NFR|AC)-[A-Z]{2,6}-[A-Z]{2,6}-[A-Z]{2,8}-\d{2,3}$")


def split_cells(line):
    return re.split(r"(?<!\\)\|", line)


def capability_floors():
    text = CAP.read_text(encoding="utf-8")
    out = {}
    for block in re.split(r"(?m)^### ", text)[1:]:
        head = block.split("\n")[0].strip()
        if not re.match(r"\d+\.\d+\.\d+ ", head):
            continue
        name = head.split(" ", 1)[1].strip()
        m = re.search(r"\*\*不是什么\*\*[：:]\s*(.+?)(?=\n\s*\n|\*\*边界\*\*|\Z)", block, re.S)
        if m:
            out[name] = re.sub(r"\*+", "", re.sub(r"\s+", " ", m.group(1))).strip("；。 ")
    return out


def build():
    """把正文里的*需求行*抽成机器视图。

    **收录口径 = 《需求索引》那份总账**（379 FR + 47 NFR + 12 AC = 438 条），原文写在索引首部：
    「数据需求 FR-STD-ALL-DATA-001~04 见正文 §5、接口需求 FR-STD-ALL-IFACE-001~13 见正文 §6 —— 它们不在这里，不是漏登」。
    所以本脚本也**不收** §5 / §6 —— 那是接口与数据约束（设计层），进概设，不进需求总账；但要**把条数报出来**，
    免得下次又靠人肉发现「怎么对不上」。

    表形状：
      · 6 列 `编号|需求|判据|不做|层次|优先级` —— §3.x/§4.x/§7.x 主体（FR / NFR / AC 都在这种表里）；
      · 2 列 `编号|需求` —— §5.x 数据需求（不入，报数）；
      · 3 列 `编号|接口|要求` —— §6.x 接口需求（不入，报数）；
      · 其余带编号的表（§8.1 风险登记 / §8.2 待决 / 模型字段表）不是需求（不入，报数）。
    """
    floors = capability_floors()
    text = SRS.read_text(encoding="utf-8")
    records, skipped, section, header = [], [], None, None
    for line in text.split("\n"):
        # 节标题：`## 4.1 性能与容量` / `### 3.2.1 循环与工具`（去掉编号留标题）。
        m = re.match(r"^#{2,3} (?:\d+(?:\.\d+)* )?(.+)$", line)
        if m:
            section, header = m.group(1).strip(), None
            continue
        if line.startswith("#"):
            header = None
            continue
        if not line.startswith("|"):
            header = None
            continue
        cells = [c.strip() for c in split_cells(line)[1:-1]]
        if header is None:
            # 表头行：`| 编号 | …`；分隔行（`|---|`）跳过。
            if cells and cells[0] in ("编号", "ID"):
                header = cells
            continue
        if not cells or set("".join(cells)) <= set("-: "):
            continue
        ident = cells[0].strip("* ")
        if not ID.match(ident):
            continue
        n = len(header)
        rec = None
        # 旧版编号：`FR-STD-ALL-DATA-*`（数据需求）/ `FR-STD-ALL-IFACE-*`（接口需求）是**上一版
        # 需求书的编号体系**，人类主人 2026-10-25 明令「DATA 这种需求编号是旧版本的，不要搞混」。
        # 它们正文里可能被改成六列表形状，所以**不能只按表形排除**；按编号前缀硬排除，并记进 skipped 报数。
        if ident.startswith(("FR-STD-ALL-DATA-", "FR-STD-ALL-IFACE-")):
            skipped.append({"id": ident, "section": section, "header": header})
            continue
        if ident.startswith("AC-"):
            # 验收判据（§7.1 发布门槛 / §7.2 智能体验收）：表只有 3~4 列，形状与 FR/NFR 不同，
            # 但**在总账里**（《需求索引》438 = 379 FR + 47 NFR + 12 AC），照收。
            rec = {"req": cells[1], "criteria": cells[2] if n > 2 else "",
                   "not_do": cells[3] if n > 3 else "", "level": "", "priority": ""}
        if n >= 6 and "需求" in header[1]:
            rec = {"req": cells[1], "criteria": cells[2], "not_do": cells[3],
                   "level": cells[4], "priority": cells[5]}
        elif n == 2 and "需求" in header[1]:
            # §5.x 数据需求：按《需求索引》口径**不入总账**（见上），只报数。
            skipped.append({"id": ident, "section": section, "header": header})
            continue
        elif n == 3 and "接口" in header[1]:
            # §6.x 接口需求：同上，不入总账；接口与分层约束的家在概设 §3/§4。
            skipped.append({"id": ident, "section": section, "header": header})
            continue
        if rec is None:
            skipped.append({"id": ident, "section": section, "header": header})
            continue
        rec.update({"id": ident, "section": section,
                    "not_do_full": floors.get(section), "evidence": None})
        # 键顺序固定（jsonl 逐字比对靠它）。
        records.append({k: rec[k] for k in ("id", "req", "criteria", "not_do", "level",
                                            "priority", "section", "not_do_full", "evidence")})
    return records, skipped


def regen_ledger(srs_text: str, plan_path):
    """**台账降级为机器产物**（人类主人 2026-10-25：「我只希望有四书一单存在」，选 B）。

    计划书里那张「需求 × 状态」大表不再手写：行由需求书生成（编号 / 摘要 / 章节），
    状态与里程碑**从上一次生成的表里按编号继承**（没写过的默认 `⬜ / — / v0.3.0 / 未实现`）。
    ⇒ 以后新增需求只动需求书 + 一单，第三处永远不会漂。
    """
    plan = plan_path.read_text(encoding="utf-8")
    rows = {}
    for line in plan.split("\n"):
        m = re.match(r"\| ((?:FR|NFR|AC)-[A-Z0-9-]+) \|", line)
        if not m:
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) >= 9:
            rows[m.group(1)] = cells
    out = []
    for line in srs_text.split("\n"):
        m = re.match(r"\| (FR-[A-Z0-9-]+) \| ([^|]+) \|", line)
        if not m:
            continue
        rid, summary = m.group(1), m.group(2).strip()
        # 第 5/6 章**另账**（`FR-STD-ALL-DATA-*` / `FR-STD-ALL-IFACE-*`），不进台账
        if rid.startswith("FR-STD-ALL-DATA-") or rid.startswith("FR-STD-ALL-IFACE-"):
            continue
        short = re.sub(r"\*\*", "", summary)[:60]
        prev = rows.get(rid)
        if prev:
            prev = list(prev)
            prev[1] = short
            out.append("| " + " | ".join(prev) + " |")
        else:
            out.append(f"| {rid} | {short} | — | 基线必备 | 中 | ⬜ | — | v0.3.0 | 未实现 |")
    # `AC-*` 一类不在需求书表格里（另有出处），原样保留旧行，不许因为“重生成”把它们丢掉
    kept = {re.match(r"\| ([A-Z0-9-]+) \|", r).group(1) for r in out}
    for rid, cells in rows.items():
        if rid not in kept:
            out.append("| " + " | ".join(cells) + " |")
    if not out:
        return 0
    lines = plan.split("\n")
    idx = [i for i, l in enumerate(lines) if re.match(r"\| (?:FR|NFR|AC)-[A-Z0-9-]+ \|", l)]
    lines[idx[0]:idx[-1] + 1] = out
    plan_path.write_text("\n".join(lines), encoding="utf-8")
    return len(out)


def main():
    records, skipped = build()
    payload = "\n".join(json.dumps(r, ensure_ascii=False) for r in records) + "\n"
    tally = {}
    for r in skipped:
        tally[r["section"]] = tally.get(r["section"], 0) + 1
    note = "；不入索引（非需求表）：" + "、".join(f"{k} {v} 条" for k, v in sorted(tally.items())) if skipped else ""
    if "--ledger" in sys.argv:
        import pathlib as _pl
        n = regen_ledger(SRS.read_text(encoding="utf-8"), ROOT / "Docs/Doyah产品开发计划书.md")
        print(f"✓ 台账已按需求书重生成：{n} 行（机器产物，勿手改）")

    if "--check" in sys.argv:
        if not OUT.exists():
            print(f"✗ 缺少 {OUT.relative_to(ROOT)}")
            return 1
        if OUT.read_text(encoding="utf-8") != payload:
            print("✗ requirement-index.jsonl 与正文不一致 ⇒ 跑 python3 Scripts/gen-req-index.py 重生成")
            return 1
        print(f"✓ requirement-index.jsonl 与正文一致（{len(records)} 条{note}）")
        return 0
    OUT.write_text(payload, encoding="utf-8")
    print(f"✓ 已生成 {OUT.relative_to(ROOT)}：{len(records)} 条{note}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
