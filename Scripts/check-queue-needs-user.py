#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""队列里 `needs-user` 行的**点名纪律**（队列 L-150）。

**为什么需要判据**（由头 = `L-10`，真事）：

`L-10` 是第 3 轮把散落各处的拍板项归成一处的**汇总格**。2026-09-30 它被关闭，
但**在那之前**，成员一个个「已决」之后它**变成了空壳** —— 状态格还挂着 `needs-user`，
于是每轮探针都替已经拍过板的事问需求提出者「要不要拍板」。需求提出者当场问：
「`L-10` 是什么，感觉是不是早就拍过版了」。与 `L-65` 同族：
**判据只看状态格，没人负责关格**（`L-65` 是「备注格里一句历史叙述命中 `needs-user`」）。

**口径（四条）**：

1. **点名** —— `needs-user` 行必须在行内点名**至少一个**拍板号（Studio 段 = `Q<号>`；
   Notes / Retro 段 = 该仓提案目录里的 `提案 <编号>`）。不点名、也不写挂起理由
   ⇒ 判红（`L-10` 的旧形态）。
2. **仍未决** —— 点名的号里**至少一个**仍处 `⏳ 待拍板` / `⏳ 待确认` / `⏳ 待提供` /
   `⏳ 待授权`（spec §6）/ `待采纳`·`草案`（提案）⇒ 绿。查得到但**全部**是
   `✅` / 已关闭 / 已随分工转移 / **挂起** ⇒ 判红并指名该行（提示「关格或改成 `done`」）。
3. **挂起 ≠ 待拍板** —— 写的是挂起类情形的行，必须**写出挂起理由**（行内同时含
   「挂起」与 `≠ 待拍板` / `不重复追问` / `不具备条件` 之一）⇒ 视为已交代，不判红。
4. **查无此号** —— 点名的号在来源里找不到 ⇒ 判红（点了不存在的号）。

**判据**：真队列（当前应绿：0 条 `needs-user` 行）+ **空跑防护**（spec §6 数据行 /
号数 / 队列行低于下限即判红 ——「一条都没解析到」不许当通过）+ 负例 `--self-test`
（含 `L-10` 旧文本复刻 / 点名不存在的号 / 悬空格 / 挂起词两路 / 提案来源）。

**范围与边界（如实登记）**：

- 判的是**行**（点名与状态），**不判语义**（那条该不该挂 `needs-user`），也不判措辞。
- 队列文件与 spec 都在 `.gitignore` 内（随微云备份）⇒ 干净克隆 / 另一平台没有：
  **跳过 + 高声提示**（`exit 0`），`--require-all` 判红 —— 与 `check-doc-q-series.py` 同做法。
- Notes / Retro 段的 `Q<号>`**不核**（那是该仓自己的号空间，本判据没有它的来源）——
  逐条登记进随行说明，不当判红（不拿 Studio 的号空间去判别人的行）。
- 提案目录（`../DoyahNotes/Docs/proposals` 等）不在盘上 ⇒ 按「无此来源」处理；
  只有当真的出现点名提案的 `needs-user` 行时才会用到。

用法：

    python3 Scripts/check-queue-needs-user.py                 # 本仓
    python3 Scripts/check-queue-needs-user.py --root <目录>    # 夹具仓（自测用）
    python3 Scripts/check-queue-needs-user.py --require-all    # 文件不在盘上 ⇒ 判红
    python3 Scripts/check-queue-needs-user.py --self-test      # 判据自己的证据（11 例 = 10 条负例 + 末例核对真仓库）

退出码：0 = 全绿（或按口径跳过）；1 = 有判红项（逐条点名 `文件:行号`）。
"""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import re
import sys
import tempfile

QUEUE_REL = "Docs/design/开发循环-任务队列.md"
SPEC_REL = "Docs/智能体助手-开发spec.md"
# 小节名 → 条目号前缀（与 doyah-loop-watch.py / doyah-loop-status.py 同源）
SECTION_PREFIX = {"Studio 队列": "L", "Notes 队列": "N", "Retro 队列": "R"}
# 本仓提案目录里「还没裁」的状态词（其余 = 已结）
PENDING_PROPOSALS = ("草案", "待采纳")
# Notes / Retro 段从哪个兄弟仓取提案目录
SIBLING_REPOS = {"Notes 队列": "DoyahNotes", "Retro 队列": "DoyahRetro"}

STATUS_WORDS = ("todo", "doing", "done", "blocked", "needs-user")
PENDING_WORDS = ("⏳ 待拍板", "⏳ 待确认", "⏳ 待提供", "⏳ 待授权")
SUSPEND_WORD = "挂起"
SUSPEND_REASONS = ("≠ 待拍板", "不重复追问", "不具备条件")
# 空跑防护下限（低于即判红：「一个都没解析到」不许当通过）
FLOORS = {"specRows": 20, "specNumbers": 20, "queueRows": 120}
H2 = re.compile(r"^##\s+")
H2_SIX = re.compile(r"^##\s*6\.\s*待拍板")
H2_SECTION = re.compile(r"^##\s+(.*队列.*)$")
SEPARATOR_CELL = re.compile(r"^:?-{2,}:?$")
# 编号格：容许 `~~` 划掉与紧跟其后的括注（队列 L-77 定的行形状：`| ~~**L-27**~~（…）` /
# `| **L-24**（**宿主侧仅此一条**；…）` 都是合法行）
ROW_RE = re.compile(r"^\|\s*(?:~~)?\s*\*\*([LNR])-(\d+)\*\*(?:~~)?")
Q_REF = re.compile(r"`?Q(\d+)`?")
PROPOSAL_REF = re.compile(r"提案\s*`?(\d{3,4})`?")
STORED = "~~"


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
    """去掉强调 / 划掉记号与首尾空白。"""
    return cell.replace("**", "").replace(STORED, "").strip()


def first_word(cell: str) -> str:
    """状态格的**首词**（`**done**（…）` ⇒ `done`；`needs-user（…）` ⇒ `needs-user`）。"""
    match = re.match(r"^([a-z][a-z\-]*)", plain(cell))
    return match.group(1) if match else ""


def resolve_status(cells: list[str]) -> str | None:
    """状态列：先认口径位（第 5 格 / 倒数第 2 格），认不出再从右往左找状态词。"""
    for index in (4, len(cells) - 2):
        if 0 <= index < len(cells):
            token = first_word(cells[index])
            if token in STATUS_WORDS:
                return token
    for cell in reversed(cells):
        token = first_word(cell)
        if token in STATUS_WORDS:
            return token
    return None


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
        stripped = line.strip()
        if not stripped.startswith("|"):
            continue
        cells = split_row(stripped)
        if cells and all(SEPARATOR_CELL.match(cell.strip()) for cell in cells if cell.strip()):
            continue
        if any("编号" in cell for cell in cells) and any("状态" in cell for cell in cells):
            continue
        rows.append((number, cells))
    return rows


def section_key(section: str) -> str | None:
    """小节标题 → 口径键（抗「全名」与「仓键」两种写法 —— 与两个循环脚本同源）。"""
    for key in SECTION_PREFIX:
        if section.startswith(key):
            return key
    return None


def scan_queue(path: pathlib.Path) -> tuple[list[tuple[str, int, list[str], str | None]], list[str]]:
    """队列行：`(小节, 行号, 单元格, 状态词)` + 形状异常逐条点名。"""
    rows: list[tuple[str, int, list[str], str | None]] = []
    weird: list[str] = []
    section = ""
    for number, line in enumerate(path.read_text(encoding="utf-8").split("\n"), start=1):
        stripped = line.strip()
        head = H2_SECTION.match(stripped)
        if head:
            section = head.group(1)
            continue
        if not stripped.startswith("|"):
            continue
        if not re.search(r"\*\*[LNR]-\d+\*\*", stripped):
            continue
        row = ROW_RE.match(stripped)
        if not row:
            weird.append("%s:%d 形状认不出（编号格不是行首 `| **X-nn**`）" % (QUEUE_REL, number))
            continue
        expected = SECTION_PREFIX.get(section_key(section) or "")
        if expected and row.group(1) != expected:
            weird.append("%s:%d 条目号前缀 `%s` 与小节「%s」不符（`section?`）"
                         % (QUEUE_REL, number, row.group(1), section))
        cells = split_row(stripped)
        status = resolve_status(cells)
        if status is None:
            weird.append("%s:%d 状态词不在词表内（`status?`）" % (QUEUE_REL, number))
        rows.append((section, number, cells, status))
    return rows, weird


def spec_q_state(path: pathlib.Path) -> tuple[set[int], set[int], set[int], dict[str, int], str | None]:
    """spec §6：返回 (仍待拍板的号, 已挂起的号, 全部号, 计数, 跳过说明)。"""
    counts = {"specRows": 0, "specNumbers": 0}
    if not path.exists():
        return set(), set(), set(), counts, "⚠️ %s 不在盘上（本机台账，随微云备份）—— 跳过" % SPEC_REL
    lines = path.read_text(encoding="utf-8").split("\n")
    section = section_lines(lines, H2_SIX)
    if not section:
        return set(), set(), set(), counts, None
    pending: set[int] = set()
    suspended: set[int] = set()
    known: set[int] = set()
    for _, cells in table_rows(section):
        if len(cells) < 3:
            continue
        counts["specRows"] += 1
        match = re.search(r"Q(\d+)", plain(cells[0]))
        if not match:
            continue
        counts["specNumbers"] += 1
        number = int(match.group(1))
        known.add(number)
        status = plain(cells[2])
        if SUSPEND_WORD in status:
            suspended.add(number)
            continue
        if any(status.startswith(word) for word in PENDING_WORDS):
            pending.add(number)
    return pending, suspended, known, counts, None


def proposal_state(root: pathlib.Path) -> tuple[dict[str, set[str]], dict[str, set[str] | None], dict[str, int]]:
    """兄弟仓提案目录：`仓 → 仍未裁的提案号` + `仓 → 盘上全部提案号`。目录不在盘上 = 无此来源。"""
    pending: dict[str, set[str]] = {}
    known: dict[str, set[str]] = {}
    counts = {"pendingProposals": 0}
    for repo in sorted(set(SIBLING_REPOS.values())):
        folder = root.parent / repo / "Docs/proposals"
        found: set[str] = set()
        seen: set[str] | None = None
        if folder.is_dir():
            seen = set()
            for path in sorted(folder.glob("[0-9]*.md")):
                seen.add(path.name.split("-")[0])
                match = re.search(r"^\|\s*状态\s*\|\s*\**([^|*]+?)\**\s*\|",
                                  path.read_text(encoding="utf-8"), re.M)
                if match and match.group(1).strip() in PENDING_PROPOSALS:
                    found.add(path.name.split("-")[0])
        pending[repo] = found
        known[repo] = seen
    counts["pendingProposals"] = sum(
        0 if value is None else len(value) for value in known.values())
    return pending, known, counts


def judge(section: str, cells: list[str], q_state: dict[str, set[int]],
          pending_props: dict[str, set[str]], known_props: dict[str, set[str] | None],
          notes: list[str]) -> str | None:
    """判一条 `needs-user` 行；绿返回 None，红返回理由（不含行号）。"""
    text = " | ".join(cells)
    numbers = sorted({int(item) for item in Q_REF.findall(text)})
    proposals = sorted({item for item in PROPOSAL_REF.findall(text)})
    suspended_ok = SUSPEND_WORD in text and any(reason in text for reason in SUSPEND_REASONS)

    key = section_key(section)
    if key in SIBLING_REPOS:
        if numbers:
            notes.append("· Notes/Retro 段的 `Q%d` 不核（该仓自己的号空间，本判据无来源）"
                         % numbers[0])
        repo = SIBLING_REPOS[key]
        if known_props.get(repo) is None:
            notes.append("· %s 提案目录不在盘上 —— 本段的 `needs-user` 行不判（无来源）" % repo)
            return None
        live = [item for item in proposals if item in pending_props.get(repo, set())]
        if live:
            return None
        unknown_props = [item for item in proposals if item not in known_props.get(repo, set())]
        if unknown_props:
            return "点名了 %s 提案目录里找不到的号：%s" % (
                repo, "、".join("`%s`" % item for item in unknown_props))
    else:
        pending_q, suspended_q, known_q = q_state["pending"], q_state["suspended"], q_state["known"]
        live = [item for item in numbers if item in pending_q]
        if live:
            return None
        unknown = [item for item in numbers if item not in known_q]
        if unknown:
            return "点名了 spec §6 里找不到的号：%s" % "、".join("`Q%d`" % item for item in unknown)

    if not numbers and not proposals:
        if suspended_ok:
            return None
        return ("空壳格：既没点名拍板号（`Q<号>` / `提案 <编号>`），也没写挂起理由"
                "（行内须同时含「挂起」与 %s 之一）—— 要么关格（改成 `done`）要么点名"
                % " / ".join(SUSPEND_REASONS))
    if suspended_ok:
        return None
    states = ["`Q%d`（%s）" % (item, "挂起 ≠ 待拍板" if item in q_state["suspended"] else "已决 / 已关闭")
              for item in numbers]
    states += ["提案 `%s`（已采纳 / 已结）" % item for item in proposals]
    return ("点名对象**全部已决 / 挂起**（%s）—— 空壳汇总格，关格或把状态格改成 `done`"
            % "、".join(states))



def check(root: pathlib.Path) -> tuple[list[str], list[str], dict[str, int]]:
    """返回 (判红项, 随行说明, 计数)。"""
    problems: list[str] = []
    notes: list[str] = []
    counts = {"specRows": 0, "specNumbers": 0, "queueRows": 0, "needsUser": 0,
              "pendingQ": 0, "suspendedQ": 0, "pendingProposals": 0}
    queue = root / QUEUE_REL
    pending_q, suspended_q, known_q, spec_counts, skip = spec_q_state(root / SPEC_REL)
    counts.update(spec_counts)
    q_state = {"pending": pending_q, "suspended": suspended_q, "known": known_q}
    pending_props, known_props, prop_counts = proposal_state(root)
    counts["pendingQ"] = len(pending_q)
    counts["suspendedQ"] = len(suspended_q)
    counts.update(prop_counts)

    if skip or not queue.exists():
        notes.append(skip or ("⚠️ %s 不在盘上（本机台账，随微云备份）—— 跳过" % QUEUE_REL))
        return problems, notes, counts

    rows, weird = scan_queue(queue)
    counts["queueRows"] = len(rows)
    problems.extend(weird)
    for section, number, cells, status in rows:
        if status != "needs-user":
            continue
        counts["needsUser"] += 1
        reason = judge(section, cells, q_state, pending_props, known_props, notes)
        if reason:
            problems.append("%s:%d %s" % (QUEUE_REL, number, reason))

    for key, floor in FLOORS.items():
        if counts[key] < floor:
            problems.append("空跑防护：`%s` 只解析到 %d，低于下限 %d —— "
                            "「一个都没解析到」不许当通过" % (key, counts[key], floor))
    return problems, notes, counts


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


STUDIO_HEAD = "## Studio 队列（大河马侧 · macOS/Apple）"
NOTES_HEAD = "## Notes 队列（大河马侧 · Apple/iOS）"


def row_after(head: str, row: str) -> tuple[str, str, str]:
    return ("queue", head + "\n", head + "\n" + row + "\n")


class Case:
    """一条负例：在临时副本上做若干处替换（可另加文件），要求判据报红并点名 expect。"""

    def __init__(self, name: str, edits: list[tuple[str, str, str]], expect: str = "",
                 green: bool = False, extra: list[tuple[str, str]] | None = None) -> None:
        self.name = name
        self.edits = edits
        self.expect = expect
        self.green = green
        self.extra = extra or []


def self_test_cases() -> list[Case]:
    return [
        Case("`L-10` 旧文本复刻：汇总格成员全已决 / 挂起，却仍挂 `needs-user`",
             [row_after(STUDIO_HEAD,
                        "| **L-900** | **需拍板类（汇总格）**：成员 = Q22 · Q45 · Q46 · Q47 · "
                        "Q48 · Q49 · Q50 · Q52 · Q42 · Q43 | 决策 | —— | **needs-user** | "
                        "逐条去向（夹具） |")],
             "全部已决 / 挂起"),
        Case("点名一个仍 `⏳ 待拍板` 的号（`Q56`）⇒ 应当绿",
             [row_after(STUDIO_HEAD,
                        "| **L-901** | **夹具**：皮肤那个 `FR` 号要不要正式号 | 决策 | —— | "
                        "**needs-user** | 点名 `Q56`（spec §6 仍 ⏳ 待拍板） |")],
             green=True),
        Case("不点名、也不写挂起理由 ⇒ 空壳格",
             [row_after(STUDIO_HEAD,
                        "| **L-902** | **夹具**：一条空壳汇总格 | 决策 | —— | **needs-user** | "
                        "成员都处理完了（夹具） |")],
             "空壳格"),
        Case("写清挂起理由（挂起 `≠ 待拍板` / 不重复追问）⇒ 应当绿",
             [row_after(STUDIO_HEAD,
                        "| **L-903** | **夹具**：环境类授权 | 决策 | —— | **needs-user** | "
                        "本条挂起（「先挂起，不具备条件」）—— 挂起 ≠ 待拍板，不重复追问 |")],
             green=True),
        Case("点名一个 spec §6 里没有的号（`Q99`）",
             [row_after(STUDIO_HEAD,
                        "| **L-904** | **夹具** | 决策 | —— | **needs-user** | 点名 `Q99` |")],
             "找不到的号"),
        Case("状态格写作词表外的 `needs_user`（形状 `status?`）",
             [row_after(STUDIO_HEAD,
                        "| **L-905** | **夹具** | 决策 | —— | **needs_user** | 点名 `Q56` |")],
             "状态词不在词表内"),
        Case("条目号前缀与本小节不符（`Notes` 段里塞一条 `L-` 行）",
             [row_after(NOTES_HEAD,
                        "| **L-906** | **夹具** | 决策 | —— | **needs-user** | 点名 `Q56` |")],
             "不符"),
        Case("`Notes` 段点名一个仍 `待采纳` 的提案（`0010`）⇒ 应当绿",
             [row_after(NOTES_HEAD,
                        "| **N-900** | **夹具** | 决策 | —— | **needs-user** | 点名 提案 0010 |")],
             green=True,
             extra=[("DoyahNotes/Docs/proposals/0010-夹具.md",
                     "| 字段 | 值 |\n| --- | --- |\n| 状态 | **待采纳** |\n")]),
        Case("同一个提案已采纳（`已采纳`）⇒ 空壳格点名该行",
             [row_after(NOTES_HEAD,
                        "| **N-901** | **夹具** | 决策 | —— | **needs-user** | 点名 提案 0010 |")],
             "全部已决 / 挂起",
             extra=[("DoyahNotes/Docs/proposals/0010-夹具.md",
                     "| 字段 | 值 |\n| --- | --- |\n| 状态 | **已采纳** |\n")]),
        Case("spec §6 小节标题被改（解析不到 ⇒ 空跑防护必须判红）",
             [("spec", "## 6. 待拍板与待授权（需求提出者的输入队列）",
               "## 六. 待拍板与待授权（需求提出者的输入队列）")],
             "空跑防护"),
    ]


def run_self_test() -> int:
    """负例：一律在临时副本上写坏；末例核对真仓库两份台账逐字节未变。"""
    repo = pathlib.Path(__file__).resolve().parent.parent
    queue, spec = repo / QUEUE_REL, repo / SPEC_REL
    if not queue.exists() or not spec.exists():
        print("⚠️ 自测需要 %s 与 %s（本机台账）—— 干净克隆上跳过" % (QUEUE_REL, SPEC_REL))
        return 0

    queue_text, spec_text = queue.read_text(encoding="utf-8"), spec.read_text(encoding="utf-8")
    before = (sha256(queue), sha256(spec))
    cases = self_test_cases()
    failures = 0

    for index, case in enumerate(cases, start=1):
        broken: tuple[str, str] | None = None
        current = {"queue": queue_text, "spec": spec_text}
        for target, old, new in case.edits:
            text = current[target]
            if old not in text:
                broken = ("锚点不在真仓库里", old)
                break
            if text.count(old) != 1:
                broken = ("夹具锚点不唯一（%d 处）" % text.count(old), old)
                break
            current[target] = text.replace(old, new, 1)
        if broken:
            print("❌ 例 %d 夹具失效（%s）：%s" % (index, broken[0], case.name))
            print("   锚点：%s" % broken[1][:90])
            failures += 1
            continue

        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp) / "Studio"
            (root / "Docs/design").mkdir(parents=True)
            (root / QUEUE_REL).write_text(current["queue"], encoding="utf-8")
            (root / SPEC_REL).write_text(current["spec"], encoding="utf-8")
            for rel, content in case.extra:
                path = pathlib.Path(tmp) / rel
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content, encoding="utf-8")
            problems, _, _ = check(root)

        if case.green:
            if problems:
                print("❌ 例 %d 不该报红却报红：%s" % (index, case.name))
                for problem in problems[:3]:
                    print("     %s" % problem)
                failures += 1
            else:
                print("✅ 例 %d 全绿（应当绿）：%s" % (index, case.name))
        elif any(case.expect in problem for problem in problems):
            print("✅ 例 %d 报红并点名「%s」：%s" % (index, case.expect, case.name))
        else:
            print("❌ 例 %d 没报红/没点名「%s」：%s" % (index, case.expect, case.name))
            for problem in problems[:3]:
                print("     %s" % problem)
            failures += 1

    if (sha256(queue), sha256(spec)) != before:
        print("❌ 末例：真仓库台账被改动（自测只能写临时副本）")
        failures += 1
    else:
        print("✅ 末例：真仓库两份台账逐字节未变（`%s` %s… / `%s` %s…）"
              % (QUEUE_REL, before[0][:16], SPEC_REL, before[1][:16]))

    print("自测：%d/%d 例符合预期" % (len(cases) + 1 - failures, len(cases) + 1))
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description="队列 `needs-user` 行的点名纪律（队列 L-150）")
    parser.add_argument("--root", default=None, help="仓库根（默认 = 脚本的上一级目录）")
    parser.add_argument("--require-all", action="store_true",
                        help="本机台账不在盘上也判红（干净克隆上别加）")
    parser.add_argument("--self-test", action="store_true", help="跑判据自己的负例")
    parser.add_argument("--quiet", action="store_true", help="只打印问题")
    args = parser.parse_args()

    if args.self_test:
        return run_self_test()

    root = pathlib.Path(args.root).resolve() if args.root \
        else pathlib.Path(__file__).resolve().parent.parent
    problems, notes, counts = check(root)
    skipped = any("跳过" in note for note in notes)

    if not args.quiet:
        for note in notes:
            print(note)
    if skipped and args.require_all:
        print("❌ 本机台账不在盘上，而 `--require-all` 要求它在")
        return 1
    if problems:
        for problem in problems:
            print("❌ %s" % problem)
        return 1
    if not skipped:
        print("✅ `needs-user` 点名纪律通过（`needs-user` 行 %d / spec §6 数据行 %d · 号 %d "
              "（待拍板 %d · 挂起 %d）/ 队列行 %d / 待裁提案 %d）"
              % (counts["needsUser"], counts["specRows"], counts["specNumbers"],
                 counts["pendingQ"], counts["suspendedQ"], counts["queueRows"],
                 counts["pendingProposals"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
