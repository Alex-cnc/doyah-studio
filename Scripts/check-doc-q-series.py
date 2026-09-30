#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""§6「待拍板与待授权」队列的**编号与状态纪律**（队列 L-56）。

**这一节为什么需要判据**（全是真事：第 35 轮登记、第 62 轮落地）：

`Docs/智能体助手-开发spec.md` §6 是**唯一需要需求提出者动脑的地方** —— 每轮探针的
「需用户介入」行直接读它。它的**表格结构**一直合法（列数 / 计数归 `check-doc-tables.py`、
版本号归 `check-doc-versions.py`），但**表格里的编号与状态没人管**，于是三类漂移长期存在：

1. **同号两条** —— `Q28` 同时是「Retro 技术栈」与「本仓与宿主的关系（= Retro `RQ-07`）」，
   两条**不同的问题**共用一个号（让号之前 `grep Q28` 说不清在说哪条）；
2. **没有编号** —— L-41 修列数时给 7~8 行补的占位是 `——`：表格结构合法了，但它们**没有 `Q` 号**，
   无法被引用也无法被对账（`FR-IO-04` / `FR-AI-12` / `.et` / `NFR-COMP-03` / cua-driver 两个授权 /
   本机模型凭据 / 环境类授权（9 项）/ 机器载荷失败原串）；
3. **状态过期** —— `Q19` 早已在 §4 记成「已拍板（2026-09-27）」，§6 却一直挂着「⏳ 待拍板」
   ⇒ **每轮探针都把一条已经解决的事报成「待你拍板」**。同族另有 `Q29`（前提随「拆隔离」作废）、
   `Q34` / `Q35` / `Q36` / `Q40`（都随当日口径关闭）、机器载荷那一条（`v1.92` 已拍板选 ①）。

**三条纪律（第 62 轮定，写在 §6 头部）**：

1. **编号唯一** —— 每个 `Q<号>` 在 §6 只许出现**一次**（关闭行也占号、不再复用）；
   **不许留 `——` 占位**；取号走 `python3 Scripts/next-doc-version.py`（本表 `max+1`），不手抄。
2. **状态只写词表词** —— 状态格**首词**必须是 `⏳ 待拍板` / `⏳ 待确认` / `⏳ 待提供` /
   `⏳ 待授权`（未决）｜`✅`（已决）｜`已随分工转移`（已转出）之一，括注写在首词之后。
3. **与 §4 同源** —— 同一个 Q 号在 §4（决策台账）与 §6 的状态**不许打架**。

**判据**：A 编号可判且唯一｜B 状态词表｜C 关闭行成对（编号划掉 ⇔ 状态首词 `✅` / 已转出）｜
D §4 ↔ §6 同源（Q17~Q23 = Studio 自己维护的号空间；Q1~Q16 属 Notes 的号空间、Q24+ 在 §4 无条目）｜
E 空跑防护（解析到的数据行 / 号数 / 对账对数低于下限即判红 ——「一个号都没解析到」不许当通过）。

**范围与边界（如实登记）**：

- 只判**本机台账** `Docs/智能体助手-开发spec.md` 的 §4 与 §6（三书不含这一节）。
- 该文件在 `.gitignore` 内（随微云备份）⇒ **干净克隆 / 另一平台没有它**：不存在时
  **跳过 + 高声提示**（`exit 0`），`--require-all` 判红 —— 与 `check-doc-tables.py` 同一做法。
- **不判**「§6 该不该有这一条」（那是语义）、**不判**行序与「卡住什么」格的措辞。

用法：

    python3 Scripts/check-doc-q-series.py                 # 本仓
    python3 Scripts/check-doc-q-series.py --root <目录>    # 夹具仓（自测用）
    python3 Scripts/check-doc-q-series.py --require-all    # 文件不在盘上 ⇒ 判红
    python3 Scripts/check-doc-q-series.py --self-test      # 判据自己的证据（8 例 + 末例）

退出码：0 = 全绿（或按口径跳过）；1 = 有判红项（逐条点名 `文件:行号`）。
"""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import re
import shutil
import sys
import tempfile

SPEC_REL = "Docs/智能体助手-开发spec.md"

H2 = re.compile(r"^##\s")
SEC6_HEAD = re.compile(r"^##\s*6[\.、]")
SEC4_HEAD = re.compile(r"^##\s*4[\.、]")
SEPARATOR_CELL = re.compile(r"^:?-{2,}:?$")
Q_IN_CELL = re.compile(r"Q(\d+)")
Q_CELL_ONLY = re.compile(r"^\s*~{0,2}\*{0,2}Q(\d+)\*{0,2}~{0,2}\s*$")
# §4 记「已经不再问」的词（只对 Q17~Q23 那一族用）
SEC4_CLOSED_HINT = re.compile(r"已关闭|已拍板|已定|✅")
# 状态格首词词表：未决 / 已决 / 已转出
STATUS_WORDS = ("⏳ 待拍板", "⏳ 待确认", "⏳ 待提供", "⏳ 待授权", "✅", "已随分工转移")
STRUCK = "~~"
# 空跑下限（第 62 轮实测：数据行 34 / Q 号 34 / §4 对账 3 对）—— 调低会放走「文件被截断」
MIN_ROWS = 30
MIN_QNUMBERS = 30
MIN_PARITY = 3


def split_row(line: str) -> list[str]:
    """按未转义的 `|` 切分单元格（Markdown 里的 `\\|` 是字面竖线）。"""
    text = line.strip()
    if text.startswith("|"):
        text = text[1:]
    if text.endswith("|") and not text.endswith("\\|"):
        text = text[:-1]

    cells: list[str] = []
    current: list[str] = []
    escaped = False
    for character in text:
        if escaped:
            current.append(character)
            escaped = False
            continue
        if character == "\\":
            escaped = True
            current.append(character)
            continue
        if character == "|":
            cells.append("".join(current))
            current = []
            continue
        current.append(character)
    cells.append("".join(current))
    return cells


def plain(cell: str) -> str:
    """去掉强调 / 划掉记号与首尾空白，便于比对首词。"""
    return cell.replace("**", "").replace(STRUCK, "").strip()


def section_lines(lines: list[str], head_re: re.Pattern[str]) -> list[tuple[int, str]]:
    """取某个 `## N.` 小节的正文行（行号从 1 起算）。"""
    start = None
    for index, line in enumerate(lines):
        if head_re.match(line):
            start = index + 1
            break
    if start is None:
        return []
    collected: list[tuple[int, str]] = []
    for index in range(start, len(lines)):
        if H2.match(lines[index]):
            break
        collected.append((index + 1, lines[index]))
    return collected


def table_rows(section: list[tuple[int, str]]) -> list[tuple[int, list[str]]]:
    """小节里的表格数据行（跳过表头与分隔行）。"""
    rows: list[tuple[int, list[str]]] = []
    for number, line in section:
        if not line.strip().startswith("|"):
            continue
        cells = split_row(line)
        if cells and all(SEPARATOR_CELL.match(cell.strip()) for cell in cells if cell.strip()):
            continue
        if any("编号" in cell for cell in cells) and any("问题" in cell for cell in cells):
            continue
        rows.append((number, cells))
    return rows


def status_closed(status: str) -> bool:
    return status.startswith("✅") or status.startswith("已随分工转移")


def check(root: pathlib.Path) -> tuple[list[str], list[str], dict[str, int]]:
    """返回 (判红项, 随行说明, 计数)。"""
    problems: list[str] = []
    notes: list[str] = []
    counts = {"rows": 0, "numbers": 0, "closed": 0, "parity": 0}

    spec = root / SPEC_REL
    if not spec.exists():
        return problems, ["⚠️ 跳过：%s 不在盘上（干净克隆 / 另一平台）" % SPEC_REL], counts

    lines = spec.read_text().splitlines()
    sec6 = section_lines(lines, SEC6_HEAD)
    sec4 = section_lines(lines, SEC4_HEAD)
    if not sec6 or not sec4:
        problems.append("%s：解析不到 §4 或 §6 小节（空跑防护 —— 小节标题被改 / 被删，"
                        "本判据不该静默通过）" % SPEC_REL)
        return problems, notes, counts

    # ---- §6：编号可判且唯一 + 状态词表 + 关闭行成对 ----
    rows = table_rows(sec6)
    counts["rows"] = len(rows)
    seen: dict[int, int] = {}
    sec6_status: dict[int, tuple[str, int]] = {}

    for number, cells in rows:
        if len(cells) < 3:
            problems.append("%s:%d 行只有 %d 格（§6 表头 4 列：编号 / 问题 / 状态 / 卡住什么）"
                            % (SPEC_REL, number, len(cells)))
            continue
        number_cell, status_cell = cells[0], cells[2]
        status = plain(status_cell)
        match = Q_IN_CELL.search(plain(number_cell))

        if match is None:
            problems.append("%s:%d 编号格没有 `Q<号>`（`——` 是 L-41 修列数时的占位，不算取号；"
                            "取号走 `Scripts/next-doc-version.py`）" % (SPEC_REL, number))
        else:
            qnumber = int(match.group(1))
            counts["numbers"] += 1
            if qnumber in seen:
                problems.append("%s:%d `Q%d` 在本节第二次出现（首见 :%d）—— 编号必须唯一，"
                                "后到者按 L-32 口径让号（`Scripts/next-doc-version.py`）"
                                % (SPEC_REL, number, qnumber, seen[qnumber]))
            else:
                seen[qnumber] = number
            sec6_status[qnumber] = (status, number)

        if not any(status.startswith(word) for word in STATUS_WORDS):
            problems.append("%s:%d 状态格首词 `%s` 不在词表内（⏳ 待拍板 / ⏳ 待确认 / ⏳ 待提供 / "
                            "⏳ 待授权 / ✅ / 已随分工转移）" % (SPEC_REL, number, status[:26]))

        is_struck = STRUCK in number_cell
        if is_struck and not status_closed(status):
            problems.append("%s:%d 编号已划掉（`~~…~~`）但状态仍是 `%s` —— 划掉就意味着已决，"
                            "状态首词应是 `✅` / `已随分工转移`" % (SPEC_REL, number, status[:26]))
        if status_closed(status) and not is_struck and "✅" not in number_cell:
            problems.append("%s:%d 状态已判 `%s`，但编号格既没划掉也没有 `✅` —— 关闭行要么写 "
                            "`~~**Q%s …**~~`，要么在编号格写 `✅`"
                            % (SPEC_REL, number, status[:26],
                               match.group(1) if match else "?"))
        if status_closed(status):
            counts["closed"] += 1

    # ---- §4 同源（Q17~Q23 = Studio 自己维护的号空间）----
    sec4_closed: dict[int, int] = {}
    sec4_open: dict[int, int] = {}
    context = ""
    for number, line in sec4:
        stripped = line.strip()
        if not stripped.startswith("|"):
            # 记住最近一条非表格正文（小节标题 / 说明行）：它决定下面这张表是什么表
            if stripped and stripped != "---":
                context = stripped
            continue
        cells = split_row(line)
        if cells and all(SEPARATOR_CELL.match(cell.strip()) for cell in cells if cell.strip()):
            continue
        if any("编号" in cell for cell in cells) and any("问题" in cell for cell in cells):
            continue
        if not cells:
            continue
        match = Q_CELL_ONLY.match(cells[0])
        if match is None:
            continue
        qnumber = int(match.group(1))
        if not 17 <= qnumber <= 23:
            continue  # Q1~Q16 属 Notes 号空间；Q24+ 在 §4 没有条目
        closed = STRUCK in cells[0] or any(SEC4_CLOSED_HINT.search(cell) for cell in cells)
        # 落在「拍板 / 追加 / 关闭」小节下的表，只有「已拍板」这一种含义（如 §4.4.1 本轮拍板）
        if not closed and ("拍板" in context or "追加" in context or "关闭" in context):
            closed = True
        if closed:
            sec4_closed[qnumber] = number
        else:
            sec4_open[qnumber] = number

    for qnumber, line4 in sec4_closed.items():
        if qnumber not in sec6_status:
            continue
        counts["parity"] += 1
        status, line6 = sec6_status[qnumber]
        if not status_closed(status):
            problems.append("%s:%d `Q%d` 在 §4 已记「已关闭 / 已拍板 / 已定」（`§4:%d`），"
                            "§6 却还挂着 `%s` —— 两处状态必须同源（真现场：Q19 因此每轮被探针"
                            "报成待拍板项）" % (SPEC_REL, line6, qnumber, line4, status[:26]))
    for qnumber, line4 in sec4_open.items():
        if qnumber not in sec6_status:
            continue
        counts["parity"] += 1
        status, line6 = sec6_status[qnumber]
        if status_closed(status):
            problems.append("%s:%d `Q%d` 在 §4 仍是「待拍板」（`§4:%d`），§6 却已判 `%s` —— "
                            "两处状态必须同源"
                            % (SPEC_REL, line6, qnumber, line4, status[:26]))

    # ---- 空跑防护 ----
    if counts["rows"] < MIN_ROWS:
        problems.append("%s：§6 只解析到 %d 个数据行（下限 %d）—— 文件被截断或表结构改过了"
                        % (SPEC_REL, counts["rows"], MIN_ROWS))
    if counts["numbers"] < MIN_QNUMBERS:
        problems.append("%s：§6 只解析到 %d 个 `Q<号>`（下限 %d）—— 编号被删光也算红"
                        % (SPEC_REL, counts["numbers"], MIN_QNUMBERS))
    if counts["parity"] < MIN_PARITY:
        problems.append("%s：§4 ↔ §6 只对账到 %d 对（下限 %d）—— 要么 §4 被改没了，"
                        "要么两侧已不成体系" % (SPEC_REL, counts["parity"], MIN_PARITY))

    notes.append("ℹ️ 受检：§6 数据行 %d / `Q` 号 %d / 关闭行 %d / §4 同源对账 %d 对"
                 % (counts["rows"], counts["numbers"], counts["closed"], counts["parity"]))
    return problems, notes, counts


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class Case:
    """一条负例：在临时副本上做若干处替换，要求判据报红并点名 expect。"""

    def __init__(self, name: str, edits: list[tuple[str, str]], expect: str) -> None:
        self.name = name
        self.edits = edits
        self.expect = expect


def self_test_cases() -> list[Case]:
    return [
        Case("同号两条（Q47 的行改成 Q48，与 PG 版本那条撞号）",
             [("| **Q47** ✅ | **WPS 专有格式", "| **Q48** ✅ | **WPS 专有格式")],
             "编号必须唯一"),
        Case("编号格退回 `——` 占位（L-41 的临时形态）",
             [("| **Q46** ✅ | **FR-AI-12", "| —— ✅ | **FR-AI-12")],
             "编号格没有"),
        Case("状态首词写词表外的 `⬜`",
             [("| ⏳ **待提供（2026-09-30 需求提出者：「先挂起",
               "| ⬜ **待提供（2026-09-30 需求提出者：「先挂起")],
             "不在词表内"),
        Case("关闭行（编号划掉）却写回 `⏳ 待拍板`",
             [("| ✅ 已关闭 | —— |", "| ⏳ 待拍板 | —— |")],
             "编号已划掉"),
        Case("状态判 ✅ 而编号没划掉也没 ✅",
             [("| ⏳ **待提供（2026-09-30 需求提出者：「先挂起",
               "| ✅ 已决（夹具）**待提供（2026-09-30 需求提出者：「先挂起")],
             "既没划掉也没有"),
        Case("§4 已拍板而 §6 仍挂待拍板（Q19 复发）",
             [("| ~~**Q19**~~ | **Windows 版排在哪个里程碑** |",
               "| **Q19** | **Windows 版排在哪个里程碑** |"),
              ("✅ 已关闭（2026-09-27 需求提出者拍板", "⏳ 待拍板（2026-09-27 需求提出者拍板")],
             "两处状态必须同源"),
        Case("§6 小节标题被改（解析不到 ⇒ 不许静默通过）",
             [("## 6. 待拍板与待授权（需求提出者的输入队列）",
               "## 六. 待拍板与待授权（需求提出者的输入队列）")],
             "空跑防护"),
    ]


def run_self_test() -> int:
    """负例：一律在临时副本上写坏；末例核对真仓库逐字节未变。"""
    repo = pathlib.Path(__file__).resolve().parent.parent
    spec = repo / SPEC_REL
    if not spec.exists():
        print("⚠️ 自测需要 %s（本机台账）—— 干净克隆上跳过" % SPEC_REL)
        return 0

    original = spec.read_text()
    before = sha256(spec)
    cases = self_test_cases()
    failures = 0

    for index, case in enumerate(cases, start=1):
        text = original
        missing = [old for old, _ in case.edits if old not in text]
        if missing:
            print("❌ 例 %d 失效（夹具锚点不在真仓库里）：%s" % (index, case.name))
            print("   锚点：%s" % missing[0][:90])
            failures += 1
            continue
        ununique = [old for old, _ in case.edits if text.count(old) != 1]
        if ununique:
            print("❌ 例 %d 夹具锚点不唯一（%d 处）：%s" % (index, text.count(ununique[0]), case.name))
            print("   锚点：%s" % ununique[0][:90])
            failures += 1
            continue
        for old, new in case.edits:
            text = text.replace(old, new, 1)

        with tempfile.TemporaryDirectory() as tmp:
            fixture = pathlib.Path(tmp)
            (fixture / "Docs").mkdir(parents=True)
            (fixture / SPEC_REL).write_text(text)
            problems, _, _ = check(fixture)

        if any(case.expect in problem for problem in problems):
            print("✅ 例 %d 报红并点名「%s」：%s" % (index, case.expect, case.name))
        else:
            print("❌ 例 %d 没报红/没点名「%s」：%s" % (index, case.expect, case.name))
            for problem in problems[:4]:
                print("     %s" % problem)
            failures += 1

    if sha256(spec) != before:
        print("❌ 末例：真仓库文件被改动（自测只能写临时副本）")
        failures += 1
    else:
        print("✅ 末例：真仓库 %s 逐字节未变（sha256 %s…）" % (SPEC_REL, before[:16]))

    print("自测：%d/%d 例符合预期" % (len(cases) + 1 - failures, len(cases) + 1))
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description="§6 待拍板队列的编号与状态纪律（队列 L-56）")
    parser.add_argument("--root", default=None, help="仓库根（默认 = 脚本的上一级目录）")
    parser.add_argument("--require-all", action="store_true",
                        help="本机台账不在盘上也判红（干净克隆上别加）")
    parser.add_argument("--self-test", action="store_true", help="跑判据自己的负例")
    parser.add_argument("--quiet", action="store_true", help="只打印问题")
    args = parser.parse_args()

    if args.self_test:
        return run_self_test()

    root = pathlib.Path(args.root).resolve() if args.root else pathlib.Path(__file__).resolve().parent.parent
    problems, notes, counts = check(root)
    skipped = any("跳过" in note for note in notes)

    if not args.quiet:
        for note in notes:
            print(note)
    if skipped and args.require_all:
        print("❌ %s 不在盘上，而 --require-all 要求它在" % SPEC_REL)
        return 1
    if problems:
        for problem in problems:
            print("❌ %s" % problem)
        return 1
    if not skipped:
        print("✅ §6 编号与状态纪律通过（数据行 %d / `Q` 号 %d / 关闭行 %d / §4 同源 %d 对）"
              % (counts["rows"], counts["numbers"], counts["closed"], counts["parity"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
