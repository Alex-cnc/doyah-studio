#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""取号的**唯一来源**：变更记录版本号 `max+1`，队列条目号 `max+1`（队列 L-32 第 ② 项）。

**别再手抄版本号。** 硬编码取号在本工程撞过三次：本侧与对侧同取 `v2.35`（概要设计，手工
rebase 解冲突）、当天队列里 `L-25` / `L-26` 各出现两次、本轮 `P-15` 跨文档同号不同物。
只要有一个循环 / 助理实例活着，「当前最大号是多少」就是**别人随时会改的**事实 —— 取号必须问
盘上的文件，不能问记忆。

用法：

    python3 Scripts/next-doc-version.py                     # 三书 + 本台账各报下一号
    python3 Scripts/next-doc-version.py Docs/概要设计.md     # 指定文档
    python3 Scripts/next-doc-version.py --ids L             # 队列里下一个 L-xx 条目号
    python3 Scripts/next-doc-version.py --ids N --ids R      # 多个前缀（可重复）
    python3 Scripts/next-doc-version.py --json               # 机器可读

注意：版本号**按文档自己的系列**取（概要设计是 `v2.x`、需求规范书是 `v3.x`、本台账是 `v1.x`），
跨系列取 max 会给出一个比当前小的号（对错系列取 max 正是 Notes 规划书踩过的坑）。
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

DEFAULT_DOCS = [
    "Docs/需求规范书.md",
    "Docs/产品能力规划说明书.md",
    "Docs/概要设计.md",
    "Docs/智能体助手-开发spec.md",
]
QUEUE_FILE = "Docs/design/开发循环-任务队列.md"

VERSION_ROW = re.compile(r"^\|\s*\*{0,2}(v\d+\.\d+)\*{0,2}\s*\|")
VERSION_QUOTE = re.compile(r"^>\s*\*\*(v\d+\.\d+)")
ID_DEF = re.compile(r"^\|\s*\*{0,2}([LNR]-\d+)\*{0,2}\s*\|")


def version_key(token: str) -> tuple[int, int]:
    major, minor = token[1:].split(".")
    return (int(major), int(minor))


def next_version(root: pathlib.Path, relative: str) -> str:
    lines = (root / relative).read_text(encoding="utf-8").splitlines()
    tokens = [
        match.group(1)
        for line in lines
        for match in (VERSION_ROW.match(line) or VERSION_QUOTE.match(line),)
        if match
    ]
    if not tokens:
        raise SystemExit(f"❌ {relative} 里找不到任何变更记录版本号（取号无从下手）")
    major = max(major for major, _ in (version_key(token) for token in tokens))
    minor = max(minor for token_major, minor in (version_key(token) for token in tokens)
                if token_major == major)
    return f"v{major}.{minor + 1}"


def next_ids(root: pathlib.Path, prefixes: list[str], queue: str | None = None) -> dict[str, str]:
    """只在**定义行**（首格 `| **L-52** |`）上取号 —— 正文里的引用与风险编号（如 `R-60`）不是条目号。"""
    target = pathlib.Path(queue) if queue else root / QUEUE_FILE
    lines = target.read_text(encoding="utf-8").splitlines()
    defined: dict[str, list[str]] = {}
    for line in lines:
        match = ID_DEF.match(line)
        if match:
            token = match.group(1)
            defined.setdefault(token.split("-")[0], []).append(token.split("-")[1])
    result: dict[str, str] = {}
    for prefix in prefixes:
        digits = defined.get(prefix, [])
        if not digits:
            raise SystemExit(f"❌ {target} 里找不到 {prefix}- 开头的**定义行**条目号")
        width = max(2, max(len(value) for value in digits))
        result[prefix] = f"{prefix}-{max(int(value) for value in digits) + 1:0{width}d}"
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="取号的唯一来源（max+1）")
    parser.add_argument("docs", nargs="*", help="文档路径（默认三书 + 本台账）")
    parser.add_argument("--ids", action="append", default=[], help="队列条目号前缀，如 L / N / R")
    parser.add_argument("--queue", default=None, help="队列文件（默认跨仓单一队列）")
    parser.add_argument("--json", action="store_true", help="机器可读输出")
    parser.add_argument("--root", default=None, help="仓库根（默认 = 脚本的上一级目录）")
    args = parser.parse_args()
    root = pathlib.Path(args.root).resolve() if args.root else ROOT

    versions: dict[str, str] = {}
    for relative in (args.docs or DEFAULT_DOCS):
        versions[relative] = next_version(root, relative)
    ids = next_ids(root, args.ids, args.queue) if args.ids else {}
    payload: dict[str, dict[str, str]] = {"versions": versions, "ids": ids}

    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 0
    for relative, token in versions.items():
        print(f"{token}   ←  {relative}")
    for prefix, token in ids.items():
        print(f"{token}   ←  队列条目号（前缀 {prefix}）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
