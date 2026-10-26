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
OUT = ROOT / ".build/derived/requirement-index.jsonl"
# 人读那份总账（| 编号 | 所属域 / 章节 | 层次 |）也在这里生成 —— 2026-10-26 起不进 `Docs/` 根：
# 人类主人只认「四书一单」，索引是派生件（由需求书正文重生成），落构建产物目录。
INDEX_MD = ROOT / ".build/derived/需求索引.md"
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


def render_index(records) -> str:
    """把记录渲染成人读索引（列：编号 / 所属域·章节 / 层次）。"""
    # 总账口径（与需求书 §1.5 一致）：数据需求 `§5` 与接口需求 `§6` **不进总账** ——
    # 它们是设计层约束，家在概要设计。jsonl 保留以便门禁对正文，人读索引按此过滤。
    design_layer = ("-ALL-DATA-", "-ALL-IFACE-")
    rows = sorted((r for r in records if not any(k in r["id"] for k in design_layer)),
                  key=lambda r: (r["section"], r["id"]))
    fr = sum(1 for r in rows if r["id"].startswith("FR-"))
    nfr = sum(1 for r in rows if r["id"].startswith("NFR-"))
    ac = sum(1 for r in rows if r["id"].startswith("AC-"))
    head = [
        "# 需求编号索引（派生件 · 请勿手改）",
        "",
        "> 由 `Scripts/gen-req-index.py` 从《Doyah产品需求规格说明书》正文重生成，落在 `.build/derived/`，不进版本库。",
        "> 收录范围与需求书 §1.5 一致：`FR` / `NFR` / `AC` 三类；数据需求（`§5`）与接口需求（`§6`）不在总账，",
        "> 它们的家是概要设计。",
        "",
        f"共 **{len(rows)}** 条（FR {fr} · NFR {nfr} · AC {ac}）。",
        "",
        "| 编号 | 所属域 / 章节 | 层次 |",
        "| --- | --- | --- |",
    ]
    body = [f"| {r['id']} | {r['section']} | {r['level'] or '—'} |" for r in rows]
    return "\n".join(head + body) + "\n"


def main():
    records, skipped = build()
    payload = "\n".join(json.dumps(r, ensure_ascii=False) for r in records) + "\n"
    tally = {}
    for r in skipped:
        tally[r["section"]] = tally.get(r["section"], 0) + 1
    note = "；不入索引（非需求表）：" + "、".join(f"{k} {v} 条" for k, v in sorted(tally.items())) if skipped else ""
    if "--check" in sys.argv:
        if not OUT.exists():
            print(f"✗ 缺少 {OUT.relative_to(ROOT)}")
            return 1
        if OUT.read_text(encoding="utf-8") != payload:
            print("✗ requirement-index.jsonl 与正文不一致 ⇒ 跑 python3 Scripts/gen-req-index.py 重生成")
            return 1
        print(f"✓ requirement-index.jsonl 与正文一致（{len(records)} 条{note}）")
        return 0
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(payload, encoding="utf-8")
    INDEX_MD.write_text(render_index(records), encoding="utf-8")
    print(f"✓ 已生成 {OUT.relative_to(ROOT)} 与 {INDEX_MD.relative_to(ROOT)}：{len(records)} 条{note}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
