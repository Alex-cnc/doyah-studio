"""派生件位置（2026-10-26）：需求编号索引与 jsonl **不再放 `Docs/` 根**。

人类主人的口径只有「四书一单」：`Docs/` 根只许能力规划 / 需求规格 / 概要设计 / 详细设计-macOS
四本书 + 开发计划任务清单。索引是**机械派生件**（2026-10-20 从需求书 §9.1 移出，410 行），
现在落到 `.build/derived/`：由 `Scripts/gen-req-index.py` 从需求书正文重生成，不进版本库。

用法（各门禁脚本统一）：

    import doc_index
    INDEX = doc_index.path()          # 不存在时自动生成一次

为什么要这一层：`.build/` 是构建产物目录、干净克隆里没有 ⇒ 直接写死路径的脚本会「文件不存在」判红，
而判红原因会被人误读成「索引缺失 = 需求丢了」。这里先补生成，缺文件就不再是判据的噪音。
"""
from __future__ import annotations

import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DERIVED = ROOT / ".build" / "derived"
INDEX = DERIVED / "需求索引.md"
JSONL = DERIVED / "requirement-index.jsonl"


def path() -> pathlib.Path:
    """索引 md 的路径；文件不在就先跑一次生成器。"""
    if not INDEX.exists():
        generate()
    return INDEX


def jsonl() -> pathlib.Path:
    if not JSONL.exists():
        generate()
    return JSONL


def generate() -> None:
    script = ROOT / "Scripts" / "gen-req-index.py"
    result = subprocess.run([sys.executable, str(script)], capture_output=True, text=True)
    if result.returncode != 0 or not INDEX.exists():
        raise SystemExit(
            "派生件生成失败：`Scripts/gen-req-index.py` 没能写出 "
            f"{INDEX.relative_to(ROOT)}（{result.stderr.strip()[:300]}）"
        )
