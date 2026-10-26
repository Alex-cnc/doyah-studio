#!/usr/bin/env python3
"""v1.0 冻结件 ↔ 活书逐字比对。

为什么要这条：2026-10-25 人类主人拍板「Doyah 产品只有唯一的四书一单」并冻结 v1.0；
2026-10-26 活书被改了、`Docs/frozen/` 没刷，冻结基线当场分叉（差 −19 / −20 / −2 / +97 行），
人类主人原话：「连版本冻结了都能被你搞乱」。所以把「冻结件必须等于活书」写成可跑的判据：
改书的人在提交前跑一次，rc=0 才算没把冻结搞乱；真要动基线，先刷冻结件再提交。

用法：python3 Scripts/check-frozen-sync.py
"""
from __future__ import annotations

import hashlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PAIRS = [
    ("Docs/Doyah产品需求规格说明书.md", "Docs/frozen/Doyah产品需求规格说明书-v1.0-20261025.md"),
    ("Docs/Doyah产品概要设计说明书.md", "Docs/frozen/Doyah产品概要设计说明书-v1.0-20261025.md"),
    ("Docs/Doyah产品能力规划说明书.md", "Docs/frozen/Doyah产品能力规划说明书-v1.0-20261025.md"),
    ("Docs/Doyah产品详细设计说明书-macOS.md", "Docs/frozen/Doyah产品详细设计说明书-macOS-v1.0-20261025.md"),
]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    bad: list[str] = []
    for live_rel, frozen_rel in PAIRS:
        live, frozen = ROOT / live_rel, ROOT / frozen_rel
        if not live.exists():
            bad.append(f"活书不存在：{live_rel}")
            continue
        if not frozen.exists():
            bad.append(f"冻结件不存在：{frozen_rel}（v1.0 基线缺一份 = 冻结不成立）")
            continue
        if digest(live) != digest(frozen):
            l_lines = len(live.read_text(encoding="utf-8").splitlines())
            f_lines = len(frozen.read_text(encoding="utf-8").splitlines())
            bad.append(
                f"冻结件与活书不一致：{frozen_rel.rsplit('/', 1)[-1]}"
                f"（活 {l_lines} 行 / 冻 {f_lines} 行，差 {l_lines - f_lines:+d}）"
                f" ⇒ 要么刷新冻结件（`Docs/frozen/README.md` 记纪律），要么别改活书"
            )
    if bad:
        print(f"✗ v1.0 冻结基线被搞乱（{len(bad)} 处）：")
        for b in bad:
            print("  ·", b)
        return 1
    print(f"✓ v1.0 冻结件与活书逐字一致（{len(PAIRS)} 份，sha256 全等）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
