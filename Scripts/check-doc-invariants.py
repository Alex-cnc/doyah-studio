#!/usr/bin/env python3
"""人类主人定的文档铁律 —— 逐条变成可跑的断言（2026-10-26 立）。

来历：我（铁皮大河马）多次出现「改了标题就宣布改完」—— 变更记录被并进书里、正文引用没清干净，
靠嘴说"已挪出"。这个脚本的用途只有一个：**声称完成之前，先跑它，把输出贴出来**。

每条铁律 = 一条断言 + 一句人话依据。判红就说明文件状态与人话不符，不许解释成"其实没问题"。

用法：`python3 Scripts/check-doc-invariants.py`（exit 0 才允许说"做完"）
"""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS = ROOT / "Docs"

# 四书一单（Docs 根 17 份）：3 书 + 6 端详设 + 6 端单 + 2 规范
BOOKS_AND_SHEETS = [
    "Doyah产品能力规划说明书.md",
    "Doyah产品需求规格说明书.md",
    "Doyah产品概要设计说明书.md",
    "Doyah产品详细设计说明书-macOS.md",
    "Doyah产品详细设计说明书-Android.md",
    "Doyah产品详细设计说明书-Windows.md",
    "Doyah产品详细设计说明书-Linux.md",
    "Doyah产品详细设计说明书-HarmonyOS.md",
    "Doyah产品详细设计说明书-iOS.md",
    "Doyah产品开发计划任务清单-macOS端.md",
    "Doyah产品开发计划任务清单-Android.md",
    "Doyah产品开发计划任务清单-Windows.md",
    "Doyah产品开发计划任务清单-Linux.md",
    "Doyah产品开发计划任务清单-HarmonyOS.md",
    "Doyah产品开发计划任务清单-iOS.md",
]
RULES_DOCS = ["通用开发规范.md", "项目管理规范.md"]
EXPECTED_ROOT = sorted(BOOKS_AND_SHEETS + RULES_DOCS)


def read(name: str) -> str:
    return (DOCS / name).read_text(encoding="utf-8")


def inv_root_exact() -> list[str]:
    """铁律：`Docs` 根只有四书一单 + 两件规范，共 17 份。"""
    actual = sorted(p.name for p in DOCS.glob("*.md"))
    if actual == EXPECTED_ROOT:
        return []
    extra = [n for n in actual if n not in EXPECTED_ROOT]
    missing = [n for n in EXPECTED_ROOT if n not in actual]
    return [f"Docs 根不是 17 份白名单：多 {extra or '无'} / 少 {missing or '无'}"]


def inv_no_changelog_in_books() -> list[str]:
    """铁律：四书一单里不许出现「变更记录」字样（不是只删标题 —— 正文引用、附录目录都算）。"""
    problems = []
    for name in BOOKS_AND_SHEETS:
        hits = [i for i, line in enumerate(read(name).split("\n"), 1) if "变更记录" in line]
        if hits:
            problems.append(f"{name}: 「变更记录」仍出现 {len(hits)} 处（行 {hits[:5]}）—— 历史看 git，书里不记")
    return problems


def inv_version_in_header() -> list[str]:
    """铁律：版本号只在头部、三段式、第三段 ≤999。"""
    three = re.compile(r"v\d+\.\d+\.(\d+)")
    problems = []
    for name in BOOKS_AND_SHEETS:
        head = "\n".join(read(name).split("\n")[:20])
        match = three.search(head)
        if not match:
            problems.append(f"{name}: 头部 20 行内没有三段式版本号")
        elif int(match.group(1)) > 999:
            problems.append(f"{name}: 第三段 {match.group(1)} 超过 999，该冻结了")
    return problems


def inv_sheet_upstream_same_end() -> list[str]:
    """铁律：各端一单只认同端详设活书。"""
    problems = []
    for name in BOOKS_AND_SHEETS:
        match = re.match(r"Doyah产品开发计划任务清单-(.+)\.md$", name)
        if not match:
            continue
        end = match.group(1)
        head = "\n".join(read(name).split("\n")[:40])
        if end not in head:
            problems.append(f"{name}: 头部 40 行没写同端端名「{end}」")
        if "详细设计说明书" not in head:
            problems.append(f"{name}: 头部没指上游详设")
    return problems


RULES = [
    ("Docs 根 17 份白名单", inv_root_exact),
    ("四书一单里零「变更记录」", inv_no_changelog_in_books),
    ("版本号只在头部且三段式 ≤999", inv_version_in_header),
    ("一单只认同端详设", inv_sheet_upstream_same_end),
]


def main() -> int:
    failed = 0
    print("人类主人定的文档铁律 —— 逐条实测：")
    for title, fn in RULES:
        problems = fn()
        if problems:
            failed += 1
            print(f"  ✗ {title}")
            for item in problems:
                print(f"      · {item}")
        else:
            print(f"  ✓ {title}")
    if failed:
        print(f"\n❌ {failed}/{len(RULES)} 条铁律不成立 —— 现在不许说「做完」")
        return 1
    print(f"\n✅ {len(RULES)} 条铁律全部成立")
    return 0


if __name__ == "__main__":
    sys.exit(main())
