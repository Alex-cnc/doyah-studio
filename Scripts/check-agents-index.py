#!/usr/bin/env python3
"""AGENTS.md 与《通用开发规范》的一致性判据。

为什么需要它：AGENTS.md 只是**索引**（每条铁律一行 + 触发器），正文只有一份在
Docs/通用开发规范.md。索引最大的风险不是不写，而是**写了之后正文改了、索引没跟上** ——
那样后来接手的人会照着过期的一页干活。这个脚本只干一件事：把两边的铁律条数与编号对上。

判据（铁律 #13 覆盖范围）：
  * 扫：Docs/通用开发规范.md 的 §1 铁律（行首 `N. **标题**` 形态）
        AGENTS.md 的「## 1 铁律目录」小节（行首 `N. `）
  * 不扫：规范 §2 之后各节、项目管理规范、任何别的仓的 AGENTS.md
  * 覆盖不全（文件缺失 / 小节缺失）⇒ 只报「未知」，不报「发现」

铁律 #14：自带 `--self-test`，用一份**故意改错**的样本证明它真会红。
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RULES = ROOT / "Docs" / "通用开发规范.md"
INDEX = ROOT / "AGENTS.md"

RULE_LINE = re.compile(r"^(\d+)\.\s+\*\*(.+?)\*\*", re.M)
INDEX_LINE = re.compile(r"^(\d+)\.\s+(.+)$", re.M)
INDEX_HEADING = "## 1 铁律目录"
TRIGGER_HEADING = "## 2 什么时候必须回去读全文"


def load_rules(path: Path) -> list[tuple[int, str]]:
    text = path.read_text(encoding="utf-8")
    head, _, tail = text.partition("## 2 ")
    body = head or text
    return [(int(n), title) for n, title in RULE_LINE.findall(body)]


def load_index(path: Path) -> list[tuple[int, str]]:
    text = path.read_text(encoding="utf-8")
    start = text.find(INDEX_HEADING)
    if start < 0:
        return []
    section = text[start + len(INDEX_HEADING):]
    stop = section.find("\n## ")
    if stop >= 0:
        section = section[:stop]
    return [(int(n), line.strip()) for n, line in INDEX_LINE.findall(section)]


def normalise(text: str) -> str:
    """只留汉字与字母，用来比对「同一条」而不是逐字相同。"""
    return re.sub(r"[^\u4e00-\u9fffA-Za-z]", "", text)


def check(rules_path: Path, index_path: Path) -> tuple[int, dict]:
    # 报告里的路径是**标识**不是本机路径 ⇒ 统一 as_posix()（Windows 上不出现反斜杠，macOS 上逐字节不变）。
    sources = [rules_path.relative_to(ROOT).as_posix() if rules_path.is_relative_to(ROOT) else rules_path.as_posix(),
               index_path.relative_to(ROOT).as_posix() if index_path.is_relative_to(ROOT) else index_path.as_posix()]
    report: dict = {"sources": sources, "uncovered": [], "problems": []}

    if not rules_path.exists() or not index_path.exists():
        report["uncovered"] = [p for p in sources if not Path(p).exists()] or sources
        report["status"] = "unknown"
        return 0, report

    rules = load_rules(rules_path)
    index = load_index(index_path)
    index_text = index_path.read_text(encoding="utf-8")

    if not rules:
        report["uncovered"] = [sources[0] + "（没解析出任何 `N. **标题**` 铁律行）"]
        report["status"] = "unknown"
        return 0, report
    if not index:
        report["problems"].append(f"AGENTS.md 里找不到「{INDEX_HEADING}」小节或其中没有编号条目")
    if TRIGGER_HEADING not in index_text:
        report["problems"].append(f"AGENTS.md 缺触发器小节「{TRIGGER_HEADING}」—— 只有目录没有「何时读正文」等于没写")

    rule_numbers = [n for n, _ in rules]
    index_numbers = [n for n, _ in index]
    if rule_numbers != list(range(1, len(rule_numbers) + 1)):
        report["problems"].append(f"规范里的铁律编号不连续：{rule_numbers}")
    if index_numbers and index_numbers != rule_numbers:
        missing = sorted(set(rule_numbers) - set(index_numbers))
        extra = sorted(set(index_numbers) - set(rule_numbers))
        detail = []
        if missing:
            detail.append(f"索引缺第 {missing} 条")
        if extra:
            detail.append(f"索引多出第 {extra} 条（正文没有）")
        if not detail:
            detail.append(f"编号顺序不一致：正文 {rule_numbers} / 索引 {index_numbers}")
        report["problems"].append("；".join(detail))

    by_number = {n: line for n, line in index}
    for number, title in rules:
        line = by_number.get(number)
        if line is None:
            continue
        keyword = normalise(title)[:4]
        if keyword and keyword not in normalise(line):
            report["problems"].append(f"第 {number} 条对不上：正文「{title[:16]}…」索引「{line[:20]}…」")

    report["rules"] = len(rules)
    report["index"] = len(index)
    report["status"] = "red" if report["problems"] else "green"
    return (1 if report["problems"] else 0), report


def self_test() -> int:
    """铁律 #14：负例必须判红，正例必须判绿。"""
    failures: list[str] = []
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "Docs").mkdir()
        shutil.copy(RULES, root / "Docs" / "通用开发规范.md")
        shutil.copy(INDEX, root / "AGENTS.md")

        global ROOT
        saved_root = ROOT
        try:
            ROOT = root
            code, rep = check(root / "Docs" / "通用开发规范.md", root / "AGENTS.md")
            if code != 0:
                failures.append(f"正例没通过：{rep['problems']}")

            # 负例 1：索引里删掉一条铁律 ⇒ 必须红
            text = (root / "AGENTS.md").read_text(encoding="utf-8")
            mutated = re.sub(r"(?m)^5\. .*\n", "", text, count=1)
            (root / "AGENTS.md").write_text(mutated, encoding="utf-8")
            code, rep = check(root / "Docs" / "通用开发规范.md", root / "AGENTS.md")
            if code == 0:
                failures.append("负例 1（索引少一条）没判红")
            (root / "AGENTS.md").write_text(text, encoding="utf-8")

            # 负例 2：删掉触发器小节 ⇒ 必须红
            (root / "AGENTS.md").write_text(
                text.replace(TRIGGER_HEADING, "## 2 随便写点什么"), encoding="utf-8")
            code, rep = check(root / "Docs" / "通用开发规范.md", root / "AGENTS.md")
            if code == 0:
                failures.append("负例 2（缺触发器小节）没判红")
            (root / "AGENTS.md").write_text(text, encoding="utf-8")

            # 负例 3：正文新增第 16 条、索引没跟 ⇒ 必须红
            rules_text = (root / "Docs" / "通用开发规范.md").read_text(encoding="utf-8")
            (root / "Docs" / "通用开发规范.md").write_text(
                rules_text.replace("\n## 2 四书一单", "\n16. **新加的第16条**：索引没跟上时这条要红。\n\n## 2 四书一单", 1),
                encoding="utf-8")
            code, rep = check(root / "Docs" / "通用开发规范.md", root / "AGENTS.md")
            if code == 0:
                failures.append("负例 3（正文多一条、索引没跟）没判红")
        finally:
            ROOT = saved_root

    for line in failures:
        print(f"❌ 自测失败：{line}")
    if failures:
        return 1
    print("✓ 自测通过：正例绿，三个负例全红")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        return self_test()

    code, report = check(RULES, INDEX)
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return code

    if report.get("status") == "unknown":
        print("未知：覆盖不全，无法判定（" + "、".join(report["uncovered"]) + "）")
        return code
    if code == 0:
        print(f"✓ AGENTS.md 索引与规范一致（{report['rules']} 条铁律，索引 {report['index']} 条，触发器小节在位）")
        return 0
    for problem in report["problems"]:
        print(f"❌ {problem}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
