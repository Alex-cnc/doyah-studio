#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""变更记录版本号与条目号的机械查重（队列 L-32）。

为什么需要它（全是真事，不是假想）：

1. 2026-09-27 本侧与对侧在概要设计上同取 `v2.35` —— 靠手工 rebase 解冲突；
2. 同一天队列里 `L-25` / `L-26` / `L-41` 各出现两次（拍板分配的条目与循环新开的条目同号）；
3. 本台账（`Docs/智能体助手-开发spec.md`）的变更记录出现 **5 对**同号行（`v1.46` / `v1.45` /
   `v1.28` / `v1.26` / `v1.19`）；
4. 概要设计 §4 的 `P-15` 与 SRS §10.9 的 `P-15` 同号不同物（那一族的跨文档对账归 **L-45**）。

现有门禁全都看不见它：表格列数比的是「列数」、状态一致性比的是「状态位」、平台矩阵比的是
「台账 ↔ 表格」—— **没有一条比「编号与编号」**。撞号一次要花一整轮去手工善后，所以这里把它
变成机器判据。

判据（三类）：

- **A 版本号唯一**：同一份文档的变更记录里，版本号不得重复（表格式 `| **v1.66** |` 与
  引用式 `> **v1.66（日期）**` 两种形状都认）。
- **B 头部版本格可判**：头部「版本 / 当前版本」格的号必须
  ① **出现在**变更记录里（防「凭空写一个号」），且
  ② **等于**变更记录最高号；若该格带**显式标注**（含「基线 / 首版」字样），则标注里必须写出
  当前最高号（形如 `**v3.28（正式版基线；当前 v3.243）**`）—— 标注意义不丢、当前号也能判。
  没有头部格的文档（如 `Docs/开发记录-*.md`）跳过本档，只按 A 判。
- **C 条目号唯一**：队列文件里**定义行**（首格 `| **L-52** |`）的条目号不得重复；
  正文里的引用不算定义，故不计入（否则判据会被引用次数淹没）。
  **定义行的行形状（2026-09-29 第 70 轮，L-77）**：编号格**允许在 `**L-xx**` 后带括注**
  （`| **L-24**（宿主侧仅此一条） | …` —— 括注算同一格，本队列真有一行这么写）⇒ 尾注不影响识别；
  第 70 轮前该行**不匹配 → 被当成「不是定义行」静默跳过**，它的号被谁占了都不会报（实测本机队列
  定义行 **86 → 87**，多的那一条正是 `L-24`；同一个盲点在本机两个循环脚本里已由队列 **L-77** 修掉）。

顺带说明两件「本判据不做」的事（避免下次有人以为查过了）：

- **跨文档编号空间**（`P-*` / `FR-*` 在不同文档里的含义）不在本判据里 —— 归 **L-45**；
- **单调顺序**（变更行必须严格递减）不在本判据里：本台账的引用式记录**本来就不是单调的**
  （历史插行造成 `v1.54` 在 `v1.53` 之前），把顺序判红会造出一堆假红；本判据只判「唯一 + 可判」。

用法：

    python3 Scripts/check-doc-versions.py                # 查全部
    python3 Scripts/check-doc-versions.py --self-test     # 负例（临时目录里写坏，末条核对真仓库未动）
    python3 Scripts/check-doc-versions.py --quiet         # 只打印问题

退出码：0 = 全绿；1 = 有撞号 / 头部不可判（逐条打印 `文件:行号`）。
"""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import re
import shutil
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent

# 带「变更记录 + 头部版本格」的文档：True = 必须存在（三书），False = 在盘上才查。
VERSION_DOCS = [
    ("Docs/需求规范书.md", True),
    ("Docs/产品能力规划说明书.md", True),
    ("Docs/概要设计.md", True),
    ("Docs/智能体助手-开发spec.md", False),
    ("Docs/测试用例.md", False),
    ("Docs/兼容性矩阵.md", False),
    ("Docs/发布方案.md", False),
    ("Docs/手工验收运行手册.md", False),
]
DEV_RECORD_GLOB = "Docs/开发记录-*.md"
QUEUE_FILE = "Docs/design/开发循环-任务队列.md"

TABLE_ROW = re.compile(r"^\|\s*\*{0,2}(v\d+\.\d+)\*{0,2}\s*\|")
QUOTE_ROW = re.compile(r"^>\s*\*\*(v\d+\.\d+)")
HEAD_TABLE = re.compile(r"^\|\s*(?:当前版本|版本)\s*\|(.+?)\|\s*$")
HEAD_QUOTE = re.compile(r"^>\s*\*\*版本\*\*\s*(v\d+\.\d+)")
ID_DEF = re.compile(r"^\|\s*\*{0,2}([LNR]-\d+)\*{0,2}[^|]*\|")
BASELINE_HINTS = ("基线", "首版")
HEAD_SCAN_LINES = 25


def version_key(token: str) -> tuple[int, int]:
    major, minor = token[1:].split(".")
    return (int(major), int(minor))


def change_rows(lines: list[str]) -> list[tuple[int, str]]:
    rows: list[tuple[int, str]] = []
    for index, line in enumerate(lines, 1):
        match = TABLE_ROW.match(line) or QUOTE_ROW.match(line)
        if match:
            rows.append((index, match.group(1)))
    return rows


def head_cell(lines: list[str]) -> tuple[int, str] | None:
    for index, line in enumerate(lines[:HEAD_SCAN_LINES], 1):
        match = HEAD_TABLE.match(line)
        if match:
            return index, match.group(1).strip()
        match = HEAD_QUOTE.match(line)
        if match:
            return index, match.group(1)
    return None


def check_doc(relative: str, root: pathlib.Path) -> tuple[list[str], str]:
    """返回 (问题列表, 摘要)。"""
    path = root / relative
    lines = path.read_text(encoding="utf-8").splitlines()
    problems: list[str] = []
    rows = change_rows(lines)

    seen: dict[str, list[int]] = {}
    for index, token in rows:
        seen.setdefault(token, []).append(index)
    for token, indexes in sorted(seen.items(), key=lambda item: version_key(item[0])):
        if len(indexes) > 1:
            places = ", ".join(f":{i}" for i in indexes)
            problems.append(f"{relative}{places} 版本号 {token} 出现 {len(indexes)} 次（变更记录里必须唯一）")

    head = head_cell(lines)
    has_section = any(line.lstrip().startswith("#") and "变更记录" in line for line in lines)
    if not rows:
        if head and has_section:
            problems.append(f"{relative}:{head[0]} 有头部版本格 {head[1]}、也有变更记录节，但一节变更行都没有")
        return problems, "无变更记录（跳过）"
    maximum = max((token for _, token in rows), key=version_key)

    if head is None:
        return problems, f"变更 {len(rows)} 行 / 最高 {maximum} / 无头部版本格"

    index, cell = head
    tokens = re.findall(r"v\d+\.\d+", cell)
    if not tokens:
        problems.append(f"{relative}:{index} 头部版本格里读不出版本号（原文：{cell}）")
        return problems, f"变更 {len(rows)} 行 / 最高 {maximum} / 头部不可判"

    stated = tokens[0]
    if stated not in seen:
        problems.append(f"{relative}:{index} 头部版本 {stated} 在变更记录里找不到（凭空写的号）")
    elif stated != maximum:
        annotated = any(hint in cell for hint in BASELINE_HINTS)
        if not (annotated and maximum in cell):
            problems.append(
                f"{relative}:{index} 头部版本 {stated} ≠ 变更记录最高 {maximum}"
                f"，且该格既没有「基线 / 首版」标注、标注里也没写出 {maximum}"
                f"（原文：{cell}）"
            )
    return problems, f"变更 {len(rows)} 行 / 最高 {maximum} / 头部 {stated}"


def check_queue(relative: str, root: pathlib.Path) -> tuple[list[str], str]:
    path = root / relative
    lines = path.read_text(encoding="utf-8").splitlines()
    problems: list[str] = []
    definitions: dict[str, list[int]] = {}
    for index, line in enumerate(lines, 1):
        match = ID_DEF.match(line)
        if match:
            definitions.setdefault(match.group(1), []).append(index)
    for token, indexes in sorted(definitions.items()):
        if len(indexes) > 1:
            places = ", ".join(f":{i}" for i in indexes)
            problems.append(
                f"{relative}{places} 条目号 {token} 被 {len(indexes)} 条定义行占用"
                f"（取号 = `python3 Scripts/next-doc-version.py` 的同族纪律：队列取号用 max+1）"
            )
    return problems, f"定义行 {len(definitions)} 个条目号"


def collect_targets(root: pathlib.Path) -> list[tuple[str, bool]]:
    targets = list(VERSION_DOCS)
    for path in sorted(root.glob(DEV_RECORD_GLOB)):
        targets.append((str(path.relative_to(root)), False))
    return targets


def run(root: pathlib.Path, quiet: bool) -> int:
    problems: list[str] = []
    for relative, required in collect_targets(root):
        path = root / relative
        if not path.exists():
            if required:
                problems.append(f"{relative} 不在盘上（该文档必须存在）")
            elif not quiet:
                print(f"⚠️  {relative} 不在盘上，跳过（**不是「已通过」**）")
            continue
        found, summary = check_doc(relative, root)
        problems.extend(found)
        if not quiet:
            mark = "❌" if found else "✅"
            print(f"{mark} {relative} —— {summary}")

    queue = root / QUEUE_FILE
    if queue.exists():
        found, summary = check_queue(QUEUE_FILE, root)
        problems.extend(found)
        if not quiet:
            print(f"{'❌' if found else '✅'} {QUEUE_FILE} —— {summary}")
    elif not quiet:
        print(f"⚠️  {QUEUE_FILE} 不在盘上，跳过条目号查重（**不是「已通过」**）")

    if problems:
        print("")
        for problem in problems:
            print(f"❌ {problem}")
        return 1
    if not quiet:
        print("\n✅ 变更记录版本号唯一、头部版本可判、队列条目号唯一")
    return 0


# --------------------------------------------------------------------------- 负例

GOOD_DOC = """# 样例文档

| 项目 | 内容 |
|---|---|
| 版本 | **v1.2** |

## 变更记录 [开放]

| 版本 | 日期 | 内容 | 作者 |
|---|---|---|---|
| **v1.2** | 2026-01-02 | 第二条 | 甲 |
| **v1.1** | 2026-01-01 | 第一条 | 甲 |
"""

QUOTE_DOC = """# 引用式台账

> **版本** v1.2 ｜（本格与最新变更行同步）

> **v1.2（2026-01-02）**：第二条。
> **v1.1（2026-01-01）**：第一条。
"""

GOOD_QUEUE = """# 队列

| 编号 | 任务 | 状态 |
|---|---|---|
| **L-02** | 第二条 | todo |
| **L-01** | 第一条 | done |
"""

CASES = [
    ("好文档（头部 = 最高，唯一）", GOOD_DOC, None, [], 0),
    ("引用式好台账", QUOTE_DOC, None, [], 0),
    ("重复版本号", GOOD_DOC.replace("| **v1.1** | 2026-01-01", "| **v1.2** | 2026-01-01"), None, ["v1.2"], 1),
    ("头部号在记录里找不到",
     GOOD_DOC.replace("| 版本 | **v1.2** |", "| 版本 | **v9.9** |"), None, ["找不到"], 1),
    ("头部号 ≠ 最高且无标注",
     GOOD_DOC.replace("| 版本 | **v1.2** |", "| 版本 | **v1.1** |"), None, ["≠ 变更记录最高"], 1),
    ("头部号 ≠ 最高但有基线标注且写出当前号",
     GOOD_DOC.replace("| 版本 | **v1.2** |", "| 版本 | **v1.1**（正式版基线；当前 v1.2） |"), None, [], 0),
    ("头部号 ≠ 最高、标注里没写当前号",
     GOOD_DOC.replace("| 版本 | **v1.2** |", "| 版本 | **v1.1**（正式版基线） |"), None, ["没写出"], 1),
    ("有头部格却找不到变更记录行",
     GOOD_DOC.replace("| **v1.2** | 2026-01-02 | 第二条 | 甲 |\n| **v1.1** | 2026-01-01 | 第一条 | 甲 |\n", ""),
     None, ["一节变更行都没有"], 1),
    ("队列条目号重复",
     GOOD_QUEUE,
     "# 队列\n\n| 编号 | 任务 | 状态 |\n|---|---|---|\n| **L-02** | 第二条 | todo |\n| **L-02** | 与上一条撞号 | todo |\n",
     ["L-02"], 1),
    ("队列引用不算定义（同一号在正文里出现多次）",
     GOOD_QUEUE + "\n> 参见 `L-01` 与 **L-01** 的处理方式，另见 L-01。\n", None, [], 0),
    ("队列定义行带括注也算定义行（同号 ⇒ 判红）—— 第 70 轮 L-77 的回归例",
     GOOD_QUEUE,
     "# 队列\n\n| 编号 | 任务 | 状态 |\n|---|---|---|\n"
     "| **L-02**（宿主侧仅此一条） | 第二条 | todo |\n"
     "| **L-02**（另一条） | 与上一条撞号 | todo |\n",
     ["L-02"], 1),
]


def self_test() -> int:
    real_root = pathlib.Path(__file__).resolve().parent.parent
    before = {}
    for relative, _ in collect_targets(real_root):
        path = real_root / relative
        if path.exists():
            before[relative] = hashlib.sha256(path.read_bytes()).hexdigest()

    failures = 0
    for name, doc, queue, expect, expected_code in CASES:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "Docs").mkdir()
            (root / "Docs" / "样例.md").write_text(doc, encoding="utf-8")
            if queue:
                (root / "Docs" / "design").mkdir()
                (root / "Docs" / "design" / "开发循环-任务队列.md").write_text(queue, encoding="utf-8")
            if doc.lstrip().startswith(">"):
                problems, _ = check_doc("Docs/样例.md", root)
            else:
                problems, _ = check_doc("Docs/样例.md", root)
            text = "\n".join(problems)
            qproblems: list[str] = []
            if queue:
                qproblems, _ = check_queue("Docs/design/开发循环-任务队列.md", root)
                qtext = "\n".join(qproblems)
                # 队列用例：文档半边必须干净，断言只打在队列半边（判据不同，不能混着判）
                hit = (not problems) and all(fragment in qtext for fragment in expect)
            else:
                hit = all(fragment in text for fragment in expect) if expect else not problems
            code = 1 if (problems or (queue and qproblems)) else 0
            ok = hit and code == expected_code
            print(f"{'✅' if ok else '❌'} 负例 {name}（期望退出码 {expected_code}，实得 {code}"
                  f"{'' if hit else ' / 报出的原因与期望不符'}）")
            if not ok:
                failures += 1
                print(f"     报出：{text or '（无）'}")
                if queue:
                    print(f"     队列：{qtext or '（无）'}")

    after = {}
    for relative, _ in collect_targets(real_root):
        path = real_root / relative
        if path.exists():
            after[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
    if before != after:
        print("❌ 负例跑完真仓库的文档被改动了（不合格）")
        failures += 1
    else:
        print(f"✅ 负例全程只在临时目录里写坏，真仓库 {len(before)} 份文档逐字节未变")

    print(f"\n{'✅' if not failures else '❌'} 负例 {len(CASES) - failures}/{len(CASES)} 达到预期")
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description="变更记录版本号与条目号查重（L-32）")
    parser.add_argument("--root", default=None, help="仓库根（默认 = 脚本的上一级目录）")
    parser.add_argument("--quiet", action="store_true", help="只打印问题")
    parser.add_argument("--self-test", action="store_true", help="跑负例（临时目录里写坏）")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    root = pathlib.Path(args.root).resolve() if args.root else ROOT
    return run(root, args.quiet)


if __name__ == "__main__":
    sys.exit(main())
