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

    表形状不止一种（这是补漏的由来）：
      · 8 列 `编号|需求|判据|不做|层次|优先级|…` —— §3.x 功能需求（主体）；
      · 2 列 `编号|需求` —— §5.x 数据需求；
      · 3 列 `编号|接口|要求` —— §6.x 接口需求。
    其余带编号的表**不是需求**（§8.1 风险登记用 `NFR-ALL-GATE-RISK-*` 编号、§5 模型字段表），
    一律不进索引，但要**把条数报出来** —— 不然下次又靠人肉发现漏收。
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
        if n >= 6 and "需求" in header[1]:
            rec = {"req": cells[1], "criteria": cells[2], "not_do": cells[3],
                   "level": cells[4], "priority": cells[5]}
        elif n == 2 and "需求" in header[1]:
            # §5.x：只有编号 + 需求，判据/层次/优先级在这一章确实没有。
            rec = {"req": cells[1], "criteria": "", "not_do": "",
                   "level": "", "priority": ""}
        elif n == 3 and "接口" in header[1]:
            # §6.x：接口名 + 要求；接口名并进需求文本，免得丢主语。
            rec = {"req": f"`{cells[1]}` —— {cells[2]}", "criteria": "", "not_do": "",
                   "level": "", "priority": ""}
        if rec is None:
            skipped.append({"id": ident, "section": section, "header": header})
            continue
        rec.update({"id": ident, "section": section,
                    "not_do_full": floors.get(section), "evidence": None})
        # 键顺序固定（jsonl 逐字比对靠它）。
        records.append({k: rec[k] for k in ("id", "req", "criteria", "not_do", "level",
                                            "priority", "section", "not_do_full", "evidence")})
    return records, skipped


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
    OUT.write_text(payload, encoding="utf-8")
    print(f"✓ 已生成 {OUT.relative_to(ROOT)}：{len(records)} 条{note}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
