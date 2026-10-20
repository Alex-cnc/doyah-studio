#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""《任务清单 · 按平台》的派生计数判据（派单 `T-20261014-025` · 人类主人令 2026-10-14）。

为什么有这条判据：`Docs/任务清单-按平台.md` 是**派生视图**（人读的完成度面），真值源 =
`Doyah产品需求分析说明书.md` **§10.10 平台等价矩阵**（由 `Scripts/gen-platform-parity.py` 机械生成）+
`Docs/平台实现状态.json`。派生视图的通病是「真值改了、视图没跟」—— 而它**恰恰是人看的那一面**
（会照着它说「各家完成度多少」）。「§10.10 ↔ 台账」那对表已由 `gen-platform-parity.py --check`
守着（闭环第 7 项），但「**视图 ↔ §10.10**」这一对原先零护栏 ⇒ 本判据补上。

判据（全部从 §10.10 **逐列重算**，不读台账、不读 §10.1）：

- **A 一览表（§1）**：每端的 项数 / ✅ / 🟡 / ⬜ 必须等于 §10.10 该列的重算值；
- **B 行集合**：§1 的平台行集合必须**恰好**等于 §10.10 的列集合（缺一行 / 多一行 —— 例如给
  移动端造行 —— 都判红）；
- **C 完成度**：§1 的百分比必须等于 `round(✅ ÷ 项数 × 100)`；
- **D 逐域表（§2）**：每一格 `✅a / 🟡b / ⬜c` 与「条数」列，必须等于 §10.10 该域该列的重算值；
- **E 残项（§3）**：macOS ⬜ 的「条数 + 编号集合」与 macOS 🟡 的「条数 + 逐域分布」必须逐条相等；
- **F §10.10 自身的域标题**：`**域**（N 条。与 macOS 基线一致：… 条）` 里的「条数」与各端
  「与基线一致条数」也重算 —— 它是 §10.10 自己的读数，漂了就一起判红（**macOS 是基线的定义端**，
  域标题里不重复写它 ⇒ 这一档不要求它，见 `BASELINE`）；
- **G 空跑判红**：§10.10 的 BEGIN/END 标记 / 表头行，或本文件的 §1 表头与一览行，任一读不到
  ⇒ 判红（不许「零命中 = 通过」）。

口径（与判据同源，写在这里免得下次再猜）：`⚠️` **不是第四种状态**，它是「与该需求的 macOS 基线
不一致」的标记 ⇒ 重算时按 `⬜ ⚠️` → `⬜` 归一；状态取值只有 ✅ / 🟡 / ⬜（SRS §0.4）。

用法：

    python3 Scripts/check-board-parity.py                # 查（rc=0 = 全绿）
    python3 Scripts/check-board-parity.py --self-test    # 判据自己的证据（15 例负例，写坏只在临时目录）
    DOYAH_ROOT=<工程根> python3 Scripts/check-board-parity.py
"""

from __future__ import annotations

import hashlib
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(os.environ.get("DOYAH_ROOT", "."))
SRS = ROOT / "Docs/Doyah产品需求分析说明书.md"
BOARD = ROOT / "Docs/任务清单-按平台.md"
SCRIPT = pathlib.Path(__file__).resolve()

BEGIN = "<!-- BEGIN platform-parity -->"
END = "<!-- END platform-parity -->"
STATUSES = ("✅", "🟡", "⬜")
BASELINE = "macOS"   # 定义基线的那一列：域标题里不重复写它，故判据 F 不要求它
GROUP_RE = re.compile(
    r"^\*\*(?P<label>.+?)\*\*（(?P<count>\d+) 条。与 macOS 基线一致：(?P<aligned>.+?) 条）$"
)
ALIGN_RE = re.compile(r"([^\s/]+)\s*(\d+)")
CELL_RE = re.compile(r"✅\s*(\d+)\s*/\s*🟡\s*(\d+)\s*/\s*⬜\s*(\d+)")
ID_RE = re.compile(r"FR-[A-Z]+-\d+(?:-\d+)?")   # 两级编号（如 Retro 域的 `FR-R-01-01`）必须整串认：
                                                # 旧式 `FR-[A-Z]+-\d+` 会把 `FR-R-01-01` 截成 `FR-R-01`
                                                # ⇒ §3 的编号集合比对既报「漏 74 条」又报「多 15 条 + 重复项」
                                                # （2026-10-14 修 · 由头 = 派单 `T-20261014-025` 的交付件）
BLANK_LINE_RE = re.compile(r"^- \*\*macOS 的 ⬜（(?P<count>\d+) 条）\*\*：(?P<ids>.+)$")
PARTIAL_LINE_RE = re.compile(r"^- \*\*macOS 的 🟡（(?P<count>\d+) 条 · 按域）\*\*：(?P<items>.+)$")


class Problems(Exception):
    """判据读不到该读的东西（= 空跑），一次把所有问题列全。"""

    def __init__(self, items: list[str]) -> None:
        super().__init__("；".join(items))
        self.items = list(items)


def cells(line: str) -> list[str]:
    """按 Markdown 表格切分单元格（与 `gen-platform-parity.py` 同形状）。"""
    text = line.strip()
    if text.startswith("|"):
        text = text[1:]
    if text.endswith("|"):
        text = text[:-1]
    return [part.strip() for part in text.split("|")]


def status_of(raw: str) -> str:
    """把 §10.10 的一个格归一到状态取值（`⚠️` 是「与基线不一致」的标记，不是状态）。"""
    return raw.replace("⚠️", "").strip()


def table_rows(lines: list[str], header_index: int) -> tuple[list[str], list[list[str]]]:
    """从表头行起收表体（`header_index + 1` 恒为分隔行），返回 (表头格, 表体各行)。"""
    header = cells(lines[header_index])
    rows: list[list[str]] = []
    index = header_index + 2
    while index < len(lines) and lines[index].strip().startswith("|"):
        rows.append(cells(lines[index]))
        index += 1
    return header, rows


def parse_matrix() -> dict:
    """读 SRS §10.10 的派生区块：列集合 + 逐行状态 + 逐域读数。读不到即抛 `Problems`。"""
    problems: list[str] = []
    text = SRS.read_text(encoding="utf-8")
    if BEGIN not in text or END not in text:
        raise Problems([f"{SRS} 里找不到 {BEGIN} / {END} 标记（§10.10 的表格位置由它们夹住）"])
    block = text.split(BEGIN, 1)[1].split(END, 1)[0]
    lines = block.splitlines()
    platforms: list[str] = []
    rows: list[dict] = []
    groups: list[dict] = []
    current: dict | None = None
    for line in lines:
        stripped = line.strip()
        matched = GROUP_RE.match(stripped)
        if matched:
            current = {
                "label": matched.group("label"),
                "count": int(matched.group("count")),
                "aligned": matched.group("aligned"),
                "ids": [],
            }
            groups.append(current)
            continue
        if stripped.startswith("| 编号"):
            platforms = cells(stripped)[2:]
            continue
        if not stripped.startswith("| FR-"):
            continue
        row = cells(stripped)
        if len(row) != len(platforms) + 2:
            problems.append(f"§10.10 的 `{row[0]}` 行格数 {len(row)} ≠ 表头口径 {len(platforms) + 2}")
            continue
        status = {name: status_of(value) for name, value in zip(platforms, row[2:])}
        for name, value in status.items():
            if value not in STATUSES:
                problems.append(f"§10.10 的 `{row[0]}` 行 `{name}` 列取值 `{value}` 不在 ✅/🟡/⬜ 里")
        rows.append(
            {
                "id": row[0],
                "domain": current["label"] if current else None,
                "status": status,
                "alert": {name for name, value in zip(platforms, row[2:]) if "⚠️" in value},
            }
        )
        if current is not None:
            current["ids"].append(row[0])
    if not platforms:
        problems.append("§10.10 读不到表头行（`| 编号 | 需求摘要 | … |`）⇒ 空跑判红")
    if not rows:
        problems.append("§10.10 读不到任何 `FR-` 数据行 ⇒ 空跑判红")
    if not groups:
        problems.append("§10.10 读不到域的标题行（`**域**（N 条。与 macOS 基线一致：… 条）`）⇒ 空跑判红")
    if problems:
        raise Problems(problems)
    counts: dict[str, dict[str, int]] = {}
    for name in platforms:
        counts[name] = {status: 0 for status in STATUSES}
        for row in rows:
            counts[name][row["status"][name]] += 1
    domains: dict[str, dict[str, dict[str, int]]] = {}
    for group in groups:
        members = [row for row in rows if row["domain"] == group["label"]]
        domains[group["label"]] = {
            "count": len(members),
            "platforms": {
                name: {status: sum(1 for row in members if row["status"][name] == status)
                       for status in STATUSES}
                for name in platforms
            },
        }
    return {"platforms": platforms, "rows": rows, "groups": groups,
            "counts": counts, "domains": domains}


def parse_board() -> dict:
    """读《任务清单·按平台》的 §1 / §2 / §3 三处机械面。读不到即抛 `Problems`。"""
    problems: list[str] = []
    lines = BOARD.read_text(encoding="utf-8").splitlines()
    overview: tuple[list[str], list[list[str]]] | None = None
    domains: tuple[list[str], list[list[str]]] | None = None
    blank_ids: list[str] = []
    blank_declared: int | None = None
    partial_declared: int | None = None
    partial_items: dict[str, int] = {}
    for index, line in enumerate(lines):
        stripped = line.strip()
        if not stripped.startswith("|"):
            matched = BLANK_LINE_RE.match(stripped)
            if matched:
                blank_declared = int(matched.group("count"))
                blank_ids = ID_RE.findall(matched.group("ids"))
                continue
            matched = PARTIAL_LINE_RE.match(stripped)
            if matched:
                partial_declared = int(matched.group("count"))
                for item in matched.group("items").split(" · "):
                    piece = item.strip().rstrip("。")
                    matched_item = re.match(r"^(?P<name>.+?)\s*(?P<number>\d+)$", piece)
                    if matched_item:
                        partial_items[matched_item.group("name").strip()] = int(matched_item.group("number"))
                continue
            continue
        header = cells(stripped)
        if overview is None and "平台" in header and "项数" in header and "完成度" in header:
            overview = table_rows(lines, index)
            continue
        if domains is None and "域" in header and "条数" in header and len(header) >= 4:
            domains = table_rows(lines, index)
            continue
    if overview is None:
        problems.append("本文件读不到 §1 一览表（表头须含 `平台` / `项数` / `完成度`）⇒ 空跑判红")
    elif not overview[1]:
        problems.append("§1 一览表存在但**一行都没有** ⇒ 空跑判红")
    if domains is None:
        problems.append("本文件读不到 §2 逐域表（表头须含 `域` / `条数`）⇒ 空跑判红")
    elif not domains[1]:
        problems.append("§2 逐域表存在但**一行都没有** ⇒ 空跑判红")
    if blank_declared is None:
        problems.append("本文件读不到 §3 的 macOS ⬜ 行（`- **macOS 的 ⬜（N 条）**：…`）⇒ 空跑判红")
    if partial_declared is None:
        problems.append("本文件读不到 §3 的 macOS 🟡 按域行（`- **macOS 的 🟡（N 条 · 按域）**：…`）⇒ 空跑判红")
    if problems:
        raise Problems(problems)
    return {
        "overview": {"header": overview[0], "rows": overview[1]},
        "domains": {"header": domains[0], "rows": domains[1]},
        "blank_declared": blank_declared,
        "blank_ids": blank_ids,
        "partial_declared": partial_declared,
        "partial_items": partial_items,
    }


def index_of(header: list[str], name: str) -> int | None:
    return header.index(name) if name in header else None


def compare(matrix: dict, board: dict) -> list[str]:
    """判据 A~F：把 §10.10 的重算值与本文件的读数逐处对齐。"""
    problems: list[str] = []
    platforms = matrix["platforms"]
    header = board["overview"]["header"]
    needed = ["平台", "项数", "✅", "🟡", "⬜", "完成度"]
    missing = [name for name in needed if name not in header]
    if missing:
        problems.append(f"§1 表头缺列 {missing}（判据按列名取值，缺一即判红）")
        return problems
    seen: dict[str, list[str]] = {}
    for row in board["overview"]["rows"]:
        if len(row) != len(header):
            problems.append(f"§1 表头 {len(header)} 列、行 {len(row)} 格（`{row[0]}`）⇒ 表格不自洽")
            continue
        seen[row[0]] = row
    for name in platforms:
        if name not in seen:
            problems.append(f"§1 缺 `{name}` 行（§10.10 有这一列 ⇒ 缺行即判红）")
    for name in seen:
        if name not in platforms:
            problems.append(f"§1 多出 `{name}` 行：§10.10 没有这一列（不设列的端不许造行）")
    for name in platforms:
        row = seen.get(name)
        if row is None:
            continue
        expected = matrix["counts"][name]
        total = sum(expected.values())
        for index, status in (("项数", None), ("✅", "✅"), ("🟡", "🟡"), ("⬜", "⬜")):
            cell = row[index_of(header, index)]
            if not cell.isdigit():
                problems.append(f"§1 `{name}` 行 `{index}` 格 `{cell}` 不是整数")
                continue
            actual = int(cell)
            if index == "项数":
                if actual != total:
                    problems.append(f"§1 `{name}` 行 项数 {actual} ≠ §10.10 重算 {total}")
            elif actual != expected[status]:
                problems.append(
                    f"§1 `{name}` 行 {index} {actual} ≠ §10.10 重算 {expected[status]}"
                )
        cell = row[index_of(header, "完成度")]
        matched = re.search(r"(\d+)\s*%", cell)
        if matched is None:
            problems.append(f"§1 `{name}` 行 完成度格 `{cell}` 读不出百分比")
        else:
            want = round(expected["✅"] * 100 / total) if total else 0
            if int(matched.group(1)) != want:
                problems.append(f"§1 `{name}` 行 完成度 {matched.group(1)}% ≠ 重算 {want}%")
    problems.extend(domain_problems(matrix, board))
    problems.extend(remnant_problems(matrix, board))
    problems.extend(alignment_problems(matrix))
    return problems


def domain_problems(matrix: dict, board: dict) -> list[str]:
    problems: list[str] = []
    header = board["domains"]["header"]
    if "域" not in header or "条数" not in header:
        return ["§2 表头缺 `域` / `条数` 列"]
    name_index = index_of(header, "域")
    count_index = index_of(header, "条数")
    column_index = {name: index_of(header, name) for name in matrix["platforms"]}
    absent = [name for name, index in column_index.items() if index is None]
    if absent:
        return [f"§2 表头缺端列 {absent}（§10.10 有这一列）"]
    seen: dict[str, list[str]] = {}
    for row in board["domains"]["rows"]:
        if len(row) != len(header):
            problems.append(f"§2 表头 {len(header)} 列、行 {len(row)} 格（`{row[0]}`）⇒ 表格不自洽")
            continue
        seen[row[0]] = row
    for name in matrix["domains"]:
        if name not in seen:
            problems.append(f"§2 缺 `{name}` 行（§10.10 有这一域）")
    for name in seen:
        if name not in matrix["domains"]:
            problems.append(f"§2 多出 `{name}` 行：§10.10 没有这一域")
    for name, row in seen.items():
        if name not in matrix["domains"]:
            continue
        expected = matrix["domains"][name]
        if row[count_index].isdigit() and int(row[count_index]) != expected["count"]:
            problems.append(
                f"§2 `{name}` 条数 {row[count_index]} ≠ §10.10 重算 {expected['count']}"
            )
        for platform in matrix["platforms"]:
            cell = row[column_index[platform]]
            matched = CELL_RE.search(cell)
            if matched is None:
                problems.append(f"§2 `{name}` 的 `{platform}` 格 `{cell}` 不是 `✅a / 🟡b / ⬜c` 形状")
                continue
            actual = {"✅": int(matched.group(1)), "🟡": int(matched.group(2)), "⬜": int(matched.group(3))}
            for status in STATUSES:
                if actual[status] != expected["platforms"][platform][status]:
                    problems.append(
                        f"§2 `{name}` 的 `{platform}` 格 {status}{actual[status]}"
                        f" ≠ §10.10 重算 {status}{expected['platforms'][platform][status]}"
                    )
    return problems


def remnant_problems(matrix: dict, board: dict) -> list[str]:
    problems: list[str] = []
    blank = [row["id"] for row in matrix["rows"] if row["status"]["macOS"] == "⬜"]
    if board["blank_declared"] != len(blank):
        problems.append(f"§3 macOS ⬜ 声明 {board['blank_declared']} 条 ≠ §10.10 重算 {len(blank)} 条")
    if len(board["blank_ids"]) != len(set(board["blank_ids"])):
        problems.append("§3 macOS ⬜ 编号里有重复项")
    if set(board["blank_ids"]) != set(blank):
        missing = sorted(set(blank) - set(board["blank_ids"]))
        extra = sorted(set(board["blank_ids"]) - set(blank))
        problems.append(f"§3 macOS ⬜ 编号集合与 §10.10 不符（漏 {missing} / 多 {extra}）")
    partial = [row for row in matrix["rows"] if row["status"]["macOS"] == "🟡"]
    if board["partial_declared"] != len(partial):
        problems.append(f"§3 macOS 🟡 声明 {board['partial_declared']} 条 ≠ §10.10 重算 {len(partial)} 条")
    expected: dict[str, int] = {}
    for row in partial:
        expected[row["domain"]] = expected.get(row["domain"], 0) + 1
    for name in sorted(set(expected) | set(board["partial_items"])):
        got = board["partial_items"].get(name)
        want = expected.get(name)
        if got != want:
            problems.append(f"§3 macOS 🟡 的 `{name}` 声明 {got} ≠ §10.10 重算 {want}")
    if sum(board["partial_items"].values()) != board["partial_declared"]:
        problems.append("§3 macOS 🟡 逐域之和 ≠ 同行声明的条数（本文件自己不自洽）")
    return problems


def alignment_problems(matrix: dict) -> list[str]:
    """判据 F：§10.10 域标题里的「条数 / 与 macOS 基线一致条数」也重算（`⚠️` 缺席 = 一致）。"""
    problems: list[str] = []
    for group in matrix["groups"]:
        members = [row for row in matrix["rows"] if row["domain"] == group["label"]]
        if len(members) != group["count"]:
            problems.append(
                f"§10.10 `{group['label']}` 域标题写 {group['count']} 条、表体 {len(members)} 行"
            )
        declared = {label: int(number) for label, number in ALIGN_RE.findall(group["aligned"])}
        for name in matrix["platforms"]:
            if name == BASELINE:
                continue   # macOS 就是基线的定义端 ⇒ 域标题不写「与 macOS 基线一致：macOS N 条」
            if name not in declared:
                problems.append(f"§10.10 `{group['label']}` 域标题缺 `{name}` 的「与基线一致」条数")
                continue
            actual = sum(1 for row in members if name not in row["alert"])
            if declared[name] != actual:
                problems.append(
                    f"§10.10 `{group['label']}` 域标题写 `{name}` 与基线一致 {declared[name]} 条"
                    f" ≠ 重算 {actual} 条"
                )
    return problems


def main() -> int:
    if "--self-test" in sys.argv[1:]:
        return self_test()
    try:
        matrix = parse_matrix()
        board = parse_board()
    except Problems as error:
        print("❌ 《任务清单·按平台》派生计数判据未通过（读不到该读的东西 = 空跑）：")
        for item in error.items:
            print(f"   · {item}")
        return 1
    problems = compare(matrix, board)
    if problems:
        print(f"❌ 《任务清单·按平台》与 SRS §10.10 不一致（{len(problems)} 处）：")
        for item in problems:
            print(f"   · {item}")
        return 1
    print(
        f"✅ 《任务清单·按平台》与 SRS §10.10 逐列一致（{len(matrix['platforms'])} 端 × "
        f"{len(matrix['rows'])} 条需求 · §1 {len(board['overview']['rows'])} 行 / §2 "
        f"{len(board['domains']['rows'])} 域 / §3 macOS ⬜ {len(board['blank_ids'])} 条 · "
        f"macOS 列 {matrix['counts']['macOS']['✅']} ✅）"
    )
    return 0



def digest(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _edit(path: pathlib.Path, old: str, new: str, count: int = 1) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise AssertionError(f"夹具目标 {old!r} 不在 {path}")
    path.write_text(text.replace(old, new, count), encoding="utf-8")


def run_script(root: pathlib.Path, argv: list[str]) -> subprocess.CompletedProcess:
    environment = dict(os.environ, DOYAH_ROOT=str(root))
    return subprocess.run(
        [sys.executable, str(SCRIPT), *argv],
        capture_output=True,
        text=True,
        env=environment,
        cwd=str(root),
    )


def build_cases() -> list[dict]:
    """15 例：14 条负例（各形一处写坏必须判红）+ 1 条未改动的对照绿。"""
    board = pathlib.Path("Docs/任务清单-按平台.md")
    srs = pathlib.Path("Docs/Doyah产品需求分析说明书.md")

    def edit_board(old: str, new: str, count: int = 1):
        def setup(work: pathlib.Path) -> None:
            _edit(work / board, old, new, count)
        return setup

    def edit_srs(old: str, new: str, count: int = 1):
        def setup(work: pathlib.Path) -> None:
            _edit(work / srs, old, new, count)
        return setup

    # 夹具里的数字**一律现读**（不写死）：真值源多一域 / 改一个数，夹具自己跟着走。
    # 2026-10-14 跟版（§10.10 由生成器重写 204 → 278 行）时，写死的旧值让 5 条夹具
    # 「目标串不存在」而**假红**（夹具准备失败）⇒ 改成从盘上现读。
    text = board.read_text(encoding="utf-8") if board.exists() else ""
    mac_row = re.search(r"^\| macOS \|.*$", text, re.M)
    # 按 `|` 切格再取「纯数字格」—— 用正则 `\|\s*(\d+)\s*\|` 会因吃掉定界符而隔一个漏一个（实测只取到 2 个数）。
    mac_cells = [int(c) for c in mac_row.group(0).split("|") if c.strip().isdigit()] if mac_row else []
    assert len(mac_cells) == 4, f"夹具取不到 macOS 一览行的四个数：{mac_cells}"
    mac_pct = re.search(r"\*\*(\d+)%\*\*", mac_row.group(0)).group(1)
    MAC = {"total": mac_cells[0], "done": mac_cells[1], "mid": mac_cells[2], "blank": mac_cells[3]}
    MAC_CELLS = f"| {MAC['total']} | {MAC['done']} | {MAC['mid']} | {MAC['blank']} |"
    MAC_CELLS_DONE_MINUS_1 = f"| {MAC['total']} | {MAC['done'] - 1} | {MAC['mid']} | {MAC['blank']} |"
    MAC_CELLS_TOTAL_MINUS_1 = f"| {MAC['total'] - 1} | {MAC['done']} | {MAC['mid']} | {MAC['blank']} |"
    MAC_BLANK_PCT = f"| {MAC['blank']} | **{mac_pct}%** |"
    MAC_BLANK_DECL = f"- **macOS 的 ⬜（{MAC['blank']} 条）**"

    return [
        {"name": "① 未改动的副本 ⇒ 全绿（对照）", "steps": [([], 0, "逐列一致")]},
        {
            "name": f"② §1 一览的 ✅ 计数写错（macOS {MAC['done']} → {MAC['done'] - 1}）",
            "setup": edit_board(MAC_CELLS, MAC_CELLS_DONE_MINUS_1),
            "steps": [([], 1, f"重算 {MAC['done']}")],
        },
        {
            "name": f"③ §1 完成度与重算不符（{mac_pct}% → 90%）",
            "setup": edit_board(MAC_BLANK_PCT, f"| {MAC['blank']} | **90%** |"),
            "steps": [([], 1, "完成度 90%")],
        },
        {
            "name": f"④ §1 项数写错（{MAC['total']} → {MAC['total'] - 1}）",
            "setup": edit_board(MAC_CELLS, MAC_CELLS_TOTAL_MINUS_1),
            "steps": [([], 1, f"项数 {MAC['total'] - 1}")],
        },
        {
            "name": "⑤ §1 缺一行（Windows 行被改名）",
            "setup": edit_board("| Windows | 对侧 · 黑鳍大肥鲨", "| WinX | 对侧 · 黑鳍大肥鲨"),
            "steps": [([], 1, "缺 `Windows` 行")],
        },
        {
            "name": "⑥ §1 多一行（给移动端造 iOS 行）",
            "setup": edit_board(
                "台账已设列，实现未开工 |",
                f"台账已设列，实现未开工 |\n| iOS | 对侧 | {MAC['total']} | 0 | 0 | {MAC['total']} | **0%** | 造出来的一行 |",
            ),
            "steps": [([], 1, "多出 `iOS` 行")],
        },
        {
            "name": "⑦ §2 逐域表的某一格写错（AI 智能体 macOS 🟡8 → 7）",
            "setup": edit_board("| AI 智能体 | 31 | ✅7 / 🟡8 / ⬜16 |", "| AI 智能体 | 31 | ✅7 / 🟡7 / ⬜16 |"),
            "steps": [([], 1, "§2 `AI 智能体`")],
        },
        {
            "name": "⑧ §2 逐域表的条数写错（AI 智能体 31 → 30）",
            "setup": edit_board("| AI 智能体 | 31 |", "| AI 智能体 | 30 |"),
            "steps": [([], 1, "条数 30")],
        },
        {
            "name": "⑨ §3 macOS ⬜ 的编号被删掉一个（条数不动）",
            "setup": edit_board("、`FR-AI-17`", ""),
            "steps": [([], 1, "编号集合")],
        },
        {
            "name": f"⑩ §3 macOS ⬜ 的声明条数写错（{MAC['blank']} → {MAC['blank'] - 1}）",
            "setup": edit_board(MAC_BLANK_DECL, f"- **macOS 的 ⬜（{MAC['blank'] - 1} 条）**"),
            "steps": [([], 1, f"声明 {MAC['blank'] - 1} 条")],
        },
        {
            "name": "⑪ §3 macOS 🟡 的逐域分布写错（SQL 15 → 14）",
            "setup": edit_board("SQL 编辑与执行 15 ·", "SQL 编辑与执行 14 ·"),
            "steps": [([], 1, "macOS 🟡")],
        },
        {
            "name": "⑫ §10.10 的表头行被删光（空跑不许当通过）",
            "setup": edit_srs("| 编号 | 需求摘要 | macOS | watchOS | Linux | Windows |\n", "", 99),
            "steps": [([], 1, "空跑判红")],
        },
        {
            "name": "⑬ §10.10 的 BEGIN 标记被删（表格位置丢了）",
            "setup": edit_srs(BEGIN, ""),
            "steps": [([], 1, "找不到")],
        },
        {
            "name": "⑭ §10.10 域标题的「与基线一致」条数写错（watchOS 16 → 15）",
            "setup": edit_srs("watchOS 16 / Linux 16 / Windows 16 条）", "watchOS 15 / Linux 16 / Windows 16 条）"),
            "steps": [([], 1, "与基线一致")],
        },
        {
            "name": "⑮ 本文件 §1 的表头被删（空跑不许当通过）",
            "setup": edit_board("| 平台 | 归属 | 项数 | ✅ | 🟡 | ⬜ | 完成度 | 一句话 |\n", ""),
            "steps": [([], 1, "空跑判红")],
        },
    ]


def self_test() -> int:
    if not SRS.exists() or not BOARD.exists():
        print(f"❌ 自检需要真实的 {SRS} 与 {BOARD}")
        return 1
    before = {path: digest(path) for path in (SRS, BOARD)}
    cases = build_cases()
    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="board-parity-selftest-") as tmp:
        base = pathlib.Path(tmp) / "base"
        (base / "Docs").mkdir(parents=True)
        for path in (SRS, BOARD):
            shutil.copy2(path, base / "Docs" / path.name)
        for index, case in enumerate(cases, 1):
            work = pathlib.Path(tmp) / f"case{index:02d}"
            shutil.copytree(base, work)
            setup = case.get("setup")
            if setup is not None:
                try:
                    setup(work)
                except AssertionError as error:
                    failures.append(f"{case['name']}｜夹具准备失败：{error}")
                    continue
            argv, want_rc, want_text = case["steps"][0]
            result = run_script(work, argv)
            combined = f"{result.stdout}\n{result.stderr}"
            if result.returncode != want_rc:
                failures.append(
                    f"{case['name']}｜期望退出码 {want_rc}、实际 {result.returncode}"
                    f"（stdout: {result.stdout.strip()[:200]}）"
                )
                continue
            if want_text and want_text not in combined:
                failures.append(
                    f"{case['name']}｜退出码对，但输出里没有 {want_text!r}"
                    f"（stdout: {result.stdout.strip()[:200]}）"
                )
    after = {path: digest(path) for path in (SRS, BOARD)}
    if before != after:
        failures.append("自检动了真仓库的文件（写坏必须只发生在临时副本上）")
    if failures:
        print(f"❌ 按平台任务清单判据自检未通过（{len(cases)} 例里 {len(failures)} 例不符预期）：")
        for failure in failures:
            print(f"   · {failure}")
        return 1
    print(f"✅ 按平台任务清单判据自检通过（{len(cases)}/{len(cases)}；真仓库两份文件逐字节未变）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
