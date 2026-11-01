#!/usr/bin/env python3
"""读台账某一行的状态格（给 .agent/plan.yaml 的 done_when 共用）。

用法：python3 Scripts/ledger-row.py FR-STD-DB-RES-001
输出：`<id> <状态>`（状态原样，✅ / 🟡 / ⬜），找不到则退出码 2。
"""
import re, sys, pathlib

LEDGER = pathlib.Path(__file__).resolve().parents[1] / "Docs" / "Doyah产品开发计划任务清单-macOS.md"

def main() -> int:
    if len(sys.argv) != 2:
        print("用法: ledger-row.py <需求编号>", file=sys.stderr)
        return 2
    want = sys.argv[1]
    for line in LEDGER.read_text(encoding="utf-8").splitlines():
        if not re.match(r"\|\s*(FR|AC|NFR)-", line):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if cells[0] == want and len(cells) > 5:
            print(f"{want} {cells[5]}")
            return 0
    print(f"{want} 不在台账里", file=sys.stderr)
    return 2

if __name__ == "__main__":
    raise SystemExit(main())
