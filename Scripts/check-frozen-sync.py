#!/usr/bin/env python3
"""活书 ↔ 最新冻结版的漂移报告（人类主人 2026-10-26 定的工作流）。

工作流（逐字对应他的说法）：
  ① **活书是从冻结版复制出来的**（两份起点相同）；
  ② 在活书上干活，差异会自然长大；
  ③ 差异**较大**时 → 判据变红，提示他「要不要冻结成新版本」；
  ④ 他同意 ⇒ 跑 `Scripts/freeze-books.py --version vX.Y`（活书 → 新冻结版）；
  ⑤ 活书与冻结版重新一致，继续干活。

所以本脚本的 rc 语义：
  rc=0  基线齐，且没有一本书超过阈值 ⇒ **静默继续**（小差异是正常的）
  rc=1  有书超过阈值 ⇒ **决策点**：该问人类「冻结到新版本吗」（不是错误，是到点了）
  rc=1  基线缺失/不可读 ⇒ 真问题（冻结版是判据源，缺了就无从判断）
  `--strict`：任何差异即 rc=1（只在**刚冻结完**时自证用）

用法：
  python3 Scripts/check-frozen-sync.py                 # 日常：看漂移、不到点就绿
  python3 Scripts/check-frozen-sync.py --strict        # 冻结后自证：必须逐字相同
  python3 Scripts/check-frozen-sync.py --threshold 60  # 改阈值（行）
"""
from __future__ import annotations

import argparse
import difflib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FROZEN = Path("Docs/frozen")
# 活书 → 冻结件文件名前缀（版本与日期从文件名里解析）
BOOKS = [
    ("Docs/Doyah产品需求规格说明书.md", "Doyah产品需求规格说明书"),
    ("Docs/Doyah产品概要设计说明书.md", "Doyah产品概要设计说明书"),
    ("Docs/Doyah产品能力规划说明书.md", "Doyah产品能力规划说明书"),
    ("Docs/Doyah产品详细设计说明书-macOS.md", "Doyah产品详细设计说明书-macOS"),
]
DEFAULT_THRESHOLD = 40  # 行；超过就该问人类「冻结不冻结」


def latest_frozen(stem: str) -> tuple[Path | None, str]:
    """取该书**版本号最高**的冻结件（同版本按日期取后一个）。"""
    found: list[tuple[tuple[int, ...], str, Path]] = []
    for p in (ROOT / FROZEN).glob(f"{stem}-v*-*.md"):
        m = re.fullmatch(rf"{re.escape(stem)}-v(\d+(?:\.\d+)*)-(\d{{8}})\.md", p.name)
        if not m:
            continue
        version = tuple(int(x) for x in m.group(1).split("."))
        found.append((version, m.group(2), p))
    if not found:
        return None, ""
    version, date, path = max(found)
    return path, f"v{'.'.join(map(str, version))}（{date}）"


def drift(frozen: Path, live: Path) -> tuple[int, int, int]:
    a = frozen.read_text(encoding="utf-8").splitlines()
    b = live.read_text(encoding="utf-8").splitlines()
    sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
    added = sum(j2 - j1 for tag, _i1, _i2, j1, j2 in sm.get_opcodes() if tag in ("insert", "replace"))
    removed = sum(i2 - i1 for tag, i1, i2, _j1, _j2 in sm.get_opcodes() if tag in ("delete", "replace"))
    return added, removed, added + removed


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--strict", action="store_true", help="任何差异即判红（冻结后自证用）")
    ap.add_argument("--threshold", type=int, default=DEFAULT_THRESHOLD, help="漂移多少行算『较大』")
    args = ap.parse_args()

    problems: list[str] = []
    over: list[str] = []
    print(f"活书 ↔ 最新冻结版（阈值 {args.threshold} 行{ ' · strict' if args.strict else '' }）")
    for live_rel, stem in BOOKS:
        live = ROOT / live_rel
        frozen, label = latest_frozen(stem)
        if not live.exists():
            problems.append(f"活书不存在：{live_rel}")
            continue
        if frozen is None:
            problems.append(f"{stem}：没有任何冻结件（基线缺失 ⇒ 无从判断，先建基线）")
            continue
        added, removed, total = drift(frozen, live)
        if total == 0:
            print(f"  · {stem:26s} 与 {label} **一致**（0 行差异）")
            continue
        flag = "超阈值 ⇒ 该问『冻结到新版本吗』" if total > args.threshold else "小差异 ⇒ 继续工作"
        print(f"  · {stem:26s} 与 {label} 差 {total} 行（+{added} / −{removed}）· {flag}")
        if args.strict or total > args.threshold:
            over.append(f"{stem}（差 {total} 行 vs {label}）")

    if problems:
        print(f"✗ 冻结基线不可用（{len(problems)} 处）：")
        for p in problems:
            print("  ·", p)
        return 1
    if over:
        print(f"\n⚠ 决策点（{len(over)} 本）：{'、'.join(over)}")
        if args.strict:
            print("  strict：冻结件必须与活书逐字一致 ⇒ 判红（跑 `Scripts/freeze-books.py` 冻结成新版本）")
        else:
            print("  按工作流：问人类主人「冻结到新版本吗」；同意则 `python3 Scripts/freeze-books.py --version vX.Y`")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
