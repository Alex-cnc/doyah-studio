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

STATUTE_LINE = re.compile(r"^第\s*([一二三四五六七八九十百千零〇0-9]+)\s*条\s*[【\[]\s*([^】\]]+?)\s*[】\]]", re.M)
INDEX_LINE = re.compile(r"^-\s*第\s*([一二三四五六七八九十百千零〇0-9]+)\s*条\s*[·・]\s*(.+)$", re.M)
INDEX_HEADING = "## 1 红线与基本原则（条号对照）"
TRIGGER_HEADING = "## 2 什么时候必须回去读全文"


CN = "零一二三四五六七八九"


def cn_to_num(s: str) -> int:
    s = s.strip()
    if s.isdigit():
        return int(s)
    unit = {"千": 1000, "百": 100, "十": 10}
    total = section = last = 0
    for ch in s:
        if ch in CN:
            last = CN.index(ch)
            section = last
        elif ch in unit:
            section = (last or 1) * unit[ch]
            total += section
            last = 0
    return total + last


def load_rules(path: Path) -> list[tuple[int, str]]:
    """正文侧：全书 `第N条【标题】`（重建后唯一形态）。"""
    text = path.read_text(encoding="utf-8")
    return [(cn_to_num(n), title.strip()) for n, title in STATUTE_LINE.findall(text)]


def load_globals(path: Path) -> set[int]:
    """正文里归属环节 = 全局的那些条号（元规则章 + Agent 纪律章 + 附则）。"""
    text = path.read_text(encoding="utf-8")
    nums: set[int] = set()
    cur = None
    for line in text.split("\n"):
        m = STATUTE_LINE.match(line)
        if m:
            cur = cn_to_num(m.group(1))
            continue
        if cur is not None and re.match(r"^(?:（[一二三四五六七八九十]+）|- )\*\*归属环节\*\*[：:]\s*全局", line.strip()):
            nums.add(cur)
            cur = None
    return nums


def load_index(path: Path) -> list[tuple[int, str]]:
    text = path.read_text(encoding="utf-8")
    start = text.find(INDEX_HEADING)
    if start < 0:
        return []
    section = text[start + len(INDEX_HEADING):]
    stop = section.find("\n## ")
    if stop >= 0:
        section = section[:stop]
    return [(cn_to_num(n), line.strip()) for n, line in INDEX_LINE.findall(section)]


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
    rule_numbers = [n for n, _ in sorted(rules)]
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

    index_numbers = [n for n, _ in index]
    if not rule_numbers:
        report["uncovered"] = [sources[0] + "（没解析出任何 `第N条【标题】`）"]
        report["status"] = "unknown"
        return 0, report
    globals_ = load_globals(rules_path)
    if not globals_:
        report["uncovered"] = [sources[0] + "（没解析出任何「归属环节：全局」的条文）"]
        report["status"] = "unknown"
        return 0, report
    missing = sorted(globals_ - set(index_numbers))
    extra = sorted(set(index_numbers) - globals_)
    if missing:
        report["problems"].append(f"AGENTS.md 条号表缺第 {missing} 条 —— 归属环节为「全局」的条文必须进这张表")
    if extra:
        report["problems"].append(f"AGENTS.md 条号表多出第 {extra} 条 —— 正文没有这条，或它不是「全局」条文")
    if index_numbers != sorted(set(index_numbers)):
        report["problems"].append("AGENTS.md 条号表没按条号升序或存在重号")

    book = {n: title for n, title in rules}
    for number, line in index:
        title = book.get(number)
        if title is None:
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
            mutated = re.sub(r"(?m)^- 第七条 .*\n", "", text, count=1)
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
                rules_text.rstrip("\n") + "\n\n第123条【新加的全局条】\n（一）**是什么**：这条故意不被索引收，判据必须红。\n（二）**归属环节**：全局\n",
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
        print(f"✓ AGENTS.md 索引与规范一致（{report['rules']} 条条文，索引 {report['index']} 条，触发器小节在位）")
        return 0
    for problem in report["problems"]:
        print(f"❌ {problem}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
