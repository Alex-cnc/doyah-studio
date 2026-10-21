#!/usr/bin/env python3
"""从《Doyah产品需求分析说明书》的表格生成机器视图 `Docs/requirement-index.jsonl`。

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
SRS = ROOT / "Docs/Doyah产品需求分析说明书.md"
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
    floors = capability_floors()
    text = SRS.read_text(encoding="utf-8")
    records, section = [], None
    for line in text.split("\n"):
        m = re.match(r"^### (?:\d+\.\d+\.\d+ )?(.+)$", line)
        if m:
            section = m.group(1).strip()
            continue
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in split_cells(line)]
        if len(cells) != 8 or not ID.match(cells[1].strip("* ")):
            continue
        records.append({
            "id": cells[1].strip("* "),
            "req": cells[2],
            "criteria": cells[3],
            "not_do": cells[4],
            "level": cells[5],
            "priority": cells[6],
            "section": section,
            "not_do_full": floors.get(section),
            "evidence": None,
        })
    return records


def main():
    records = build()
    payload = "\n".join(json.dumps(r, ensure_ascii=False) for r in records) + "\n"
    if "--check" in sys.argv:
        if not OUT.exists():
            print(f"✗ 缺少 {OUT.relative_to(ROOT)}")
            return 1
        if OUT.read_text(encoding="utf-8") != payload:
            print("✗ requirement-index.jsonl 与正文不一致 ⇒ 跑 python3 Scripts/gen-req-index.py 重生成")
            return 1
        print(f"✓ requirement-index.jsonl 与正文一致（{len(records)} 条）")
        return 0
    OUT.write_text(payload, encoding="utf-8")
    print(f"✓ 已生成 {OUT.relative_to(ROOT)}：{len(records)} 条")
    return 0


if __name__ == "__main__":
    sys.exit(main())
