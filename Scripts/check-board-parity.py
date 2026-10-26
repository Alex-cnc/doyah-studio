#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""《任务清单 · 按平台》的派生计数判据（派单 `T-20261014-025` · 人类主人令 2026-10-14）。

为什么有这条判据：`Docs/任务清单-按平台.md` 是**派生视图**（人读的完成度面），真值源 =
《开发计划书》§5 平台等价矩阵（由 `Scripts/gen-platform-parity.py` 机械生成；2026-10-20 从
SRS §10.10 迁来）+ `Docs/平台实现状态.json` + 需求编号索引（`Doyah产品需求规格说明书-需求索引.md`，
macOS 状态在计划书 §3 台账）。派生视图的通病是「真值改了、视图没跟」—— 而它**恰恰是人看的那一面**
（会照着它说「各家完成度多少」）。「矩阵 ↔ 台账」那一对已由 `gen-platform-parity.py --check` 守着，
但「**视图 ↔ 矩阵**」这一对原先零护栏 ⇒ 本判据补上。

判据（全部从真源**逐列重算**，不读本文件的任何结论）：

- **A 一览表（§1）**：每端的 项数 / ✅ / 🟡 / ⬜ 必须等于真源该列的重算值；
- **B 行集合**：§1 的平台行集合必须**恰好**等于真源列集合（缺一行 / 多一行 —— 例如给移动端造行 —— 都判红）；
- **C 完成度**：§1 的百分比必须等于 `round(✅ ÷ (✅ + 🟡 + ⬜) × 100)`；
- **D 逐域表（§2）**：每一格 `✅a / 🟡b / ⬜c` 与「条数」列，必须等于真源该（产品线, 域）该列的重算值；
  行集合也必须**恰好**相等（缺一行 / 多一行都判红）；
- **E 残项（§3）**：macOS ⬜ 与 🟡 的「条数 + 逐域条数 + 编号集合」必须逐条相等（编号集合逐条点名漏/多，
  重复编号也判红）；
- **F 矩阵自身的域标题读数**：只在矩阵区块仍在盘时判（`**域**（N 条。与 macOS 基线一致：… 条）`）；
  区块迁走后**无主体**，此时如实打印「F 跳过」，不假装判过 —— 矩阵自身的漂移由
  `gen-platform-parity.py --check` 守；
- **G 空跑判红**：矩阵区块 / §1 表头与一览行 / §2 表头与数据行 / §3 两个分组的标题行，任一读不到
  ⇒ 判红（不许「零命中 = 通过」）。

真源取法（2026-10-20 矩阵迁版后）：先试 SRS §10.10 的 BEGIN/END 区块；**标记不在盘**时回退到
「用 `gen-platform-parity` 的 `load_rows()` / `load_ledger()` 重算」—— 域码 = 编号**倒数第二段**
（`FR-STD-DB-CONN-001` → `CONN`），域名取 `DOMAIN_LABEL.get(f"FR-{域码}", f"FR-{域码}")`（缺项照原域码，
不编名字）。回退**不是**放松：A / B / C / D / E 一条不减，仍然逐格判红。

口径（与判据同源，写在这里免得下次再猜）：`⚠️` **不是第四种状态**，它是「与该需求的 macOS 基线
不一致」的标记 ⇒ 重算时按 `⬜ ⚠️` → `⬜` 归一；状态取值只有 ✅ / 🟡 / ⬜（SRS §0.4）。

用法：

    python3 Scripts/check-board-parity.py                # 查（rc=0 = 全绿）
    python3 Scripts/check-board-parity.py --self-test    # 判据自己的证据（15 例负例，写坏只在临时目录）
    DOYAH_ROOT=<工程根> python3 Scripts/check-board-parity.py
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import doc_index  # noqa: E402  （派生件位置：.build/derived；缺文件先重生成）

import tempfile

ROOT = pathlib.Path(os.environ.get("DOYAH_ROOT", "."))
SRS = ROOT / "Docs/Doyah产品需求规格说明书.md"
BOARD = ROOT / "Docs/任务清单-按平台.md"
PARITY = pathlib.Path(__file__).with_name("gen-platform-parity.py")
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
ID_RE = re.compile(r"FR-(?:AGT|STD|NTS|RTR|ALL)-[A-Z]{2,6}-[A-Z]{2,9}-\d{2,3}")   # 两级编号（如 Retro 域的 `FR-RTR-MKT-FEED-001`）必须整串认
BLANK_HEAD_RE = re.compile(r"^- \*\*macOS 的 ⬜（(?P<count>\d+) 条(?P<rest>[^）]*)）\*\*$")
PARTIAL_HEAD_RE = re.compile(r"^- \*\*macOS 的 🟡（(?P<count>\d+) 条(?P<rest>[^）]*)）\*\*$")
GROUP_LINE_RE = re.compile(r"^\s{2}- \*\*(?P<label>.+?)\*\*（(?P<count>\d+) 条）：(?P<ids>.+)$")


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


def plain(cell: str) -> str:
    """去掉反引号与强调，取单元格的**显示文本**（`| `STD` |` 与 `| STD |` 视为同一格）。"""
    return re.sub(r"\s+", " ", cell.replace("`", "").replace("**", "")).strip()


def status_of(raw: str) -> str:
    """把矩阵的一个格归一到状态取值（`⚠️` 是「与基线不一致」的标记，不是状态）。"""
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


# ── 真源 → 矩阵模型 ─────────────────────────────────────────────────────────


def parity_module():
    spec = importlib.util.spec_from_file_location("gen_platform_parity", PARITY)
    if spec is None or spec.loader is None:   # pragma: no cover - 只在文件被删时发生
        raise Problems([f"读不到真源脚本 {PARITY}"])
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def model_from_block(block: str) -> dict:
    """矩阵区块（SRS §10.10 的老形态）→ 模型。区块在盘时走这条（判据 F 有主体）。"""
    lines = block.splitlines()
    platforms: list[str] = []
    rows: list[dict] = []
    groups: list[dict] = []
    current: dict | None = None
    for line in lines:
        stripped = line.strip()
        matched = GROUP_RE.match(stripped)
        if matched:
            current = {"label": matched.group("label"), "count": int(matched.group("count")),
                       "aligned": matched.group("aligned"), "ids": []}
            groups.append(current)
            continue
        if stripped.startswith("| 编号"):
            platforms = cells(stripped)[2:]
            continue
        if not stripped.startswith("| FR-"):
            continue
        row = cells(stripped)
        if len(row) != len(platforms) + 2:
            raise Problems([f"矩阵的 `{row[0]}` 行格数 {len(row)} ≠ 表头口径 {len(platforms) + 2}"])
        status = {name: status_of(value) for name, value in zip(platforms, row[2:])}
        for name, value in status.items():
            if value not in STATUSES:
                raise Problems([f"矩阵的 `{row[0]}` 行 `{name}` 列取值 `{value}` 不在 ✅/🟡/⬜ 里"])
        rows.append({
            "id": row[0],
            "line": row[0].split("-")[1],
            "domain": current["label"] if current else None,
            "status": status,
            "alert": {name for name, value in zip(platforms, row[2:]) if "⚠️" in value},
        })
        if current is not None:
            current["ids"].append(row[0])
    if not platforms or not rows or not groups:
        raise Problems(["矩阵区块读不到表头 / 数据行 / 域标题 ⇒ 空跑判红"])
    return finish_model(platforms, rows, groups, "srs-block")


def model_from_source() -> dict:
    """回退路径：`load_rows()` + `load_ledger()` 重算（矩阵区块不在盘时的唯一真源）。"""
    source = parity_module()
    try:
        loaded = source.load_rows()
        default, platforms, _ = source.load_ledger({identifier for identifier, _, _ in loaded})
    except source.LedgerError as error:
        raise Problems([f"真源台账不合规：{problem}" for problem in error.problems]) from error
    if not loaded:
        raise Problems(["`load_rows()` 读到 0 条需求 ⇒ 空跑判红（需求索引 / 状态台账的锚点变了？）"])
    columns = [BASELINE] + [platform["label"] for platform in platforms]
    rows: list[dict] = []
    for identifier, macos, _ in loaded:
        code = identifier.split("-")[-2]
        status = {BASELINE: macos}
        alert: set[str] = set()
        for platform in platforms:
            value = platform["overrides"].get(identifier, default)
            status[platform["label"]] = value
            if value != macos:
                alert.add(platform["label"])
        rows.append({
            "id": identifier,
            "line": identifier.split("-")[1],
            "domain": source.DOMAIN_LABEL.get(f"FR-{code}", f"FR-{code}"),
            "status": status,
            "alert": alert,
        })
    groups: list[dict] = []
    seen: dict[tuple[str, str], dict] = {}
    for row in rows:
        key = (row["line"], row["domain"])
        if key not in seen:
            seen[key] = {"label": row["domain"], "line": row["line"], "count": 0, "aligned": None, "ids": []}
            groups.append(seen[key])
        seen[key]["count"] += 1
        seen[key]["ids"].append(row["id"])
    return finish_model(columns, rows, groups, "recomputed")


def finish_model(platforms: list[str], rows: list[dict], groups: list[dict], source: str) -> dict:
    counts: dict[str, dict[str, int]] = {}
    for name in platforms:
        counts[name] = {status: 0 for status in STATUSES}
        for row in rows:
            counts[name][row["status"][name]] += 1
    domains: dict[tuple[str, str], dict] = {}
    for group in groups:
        members = [row for row in rows if row["domain"] == group["label"]
                   and (group.get("line") in (None, row["line"]))]
        domains[(group.get("line") or "", group["label"])] = {
            "count": len(members),
            "platforms": {
                name: {status: sum(1 for row in members if row["status"][name] == status)
                       for status in STATUSES}
                for name in platforms
            },
            "ids": [row["id"] for row in members],
        }
    return {"source": source, "platforms": platforms, "rows": rows, "groups": groups,
            "counts": counts, "domains": domains}


def parse_matrix() -> dict:
    """先读 SRS §10.10 区块；标记不在盘（2026-10-20 迁到《开发计划书》§5）⇒ 回退到真源重算。"""
    text = SRS.read_text(encoding="utf-8")
    if BEGIN in text and END in text:
        return model_from_block(text.split(BEGIN, 1)[1].split(END, 1)[0])
    return model_from_source()


# ── 本文件的三处机械面 ─────────────────────────────────────────────────────


def parse_board() -> dict:
    """读《任务清单·按平台》的 §1 / §2 / §3 三处机械面。读不到即抛 `Problems`。"""
    problems: list[str] = []
    lines = BOARD.read_text(encoding="utf-8").splitlines()
    overview: tuple[list[str], list[list[str]]] | None = None
    domains: tuple[list[str], list[list[str]]] | None = None
    remnants: dict[str, dict] = {}
    current: str | None = None
    for index, line in enumerate(lines):
        stripped = line.strip()
        if not stripped.startswith("|"):
            for status, head in (("⬜", BLANK_HEAD_RE), ("🟡", PARTIAL_HEAD_RE)):
                matched = head.match(stripped)
                if matched:
                    current = status
                    remnants[status] = {"declared": int(matched.group("count")),
                                        "groups": {}, "ids": []}
                    break
            else:
                matched = GROUP_LINE_RE.match(line)
                if matched and current is not None:
                    ids = ID_RE.findall(matched.group("ids"))
                    remnants[current]["groups"][matched.group("label")] = {
                        "declared": int(matched.group("count")), "ids": ids}
                    remnants[current]["ids"].extend(ids)
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
    for status in ("⬜", "🟡"):
        if status not in remnants:
            problems.append(f"本文件读不到 §3 的 macOS {status} 分组标题行 ⇒ 空跑判红")
        elif not remnants[status]["groups"]:
            problems.append(f"§3 的 macOS {status} 分组存在但**一条编号都没有** ⇒ 空跑判红")
    if problems:
        raise Problems(problems)
    return {
        "overview": {"header": overview[0], "rows": overview[1]},
        "domains": {"header": domains[0], "rows": domains[1]},
        "remnants": remnants,
    }


def index_of(header: list[str], name: str) -> int | None:
    return header.index(name) if name in header else None


def compare(matrix: dict, board: dict) -> list[str]:
    """判据 A~F：把真源的重算值与本文件的读数逐处对齐。"""
    problems: list[str] = []
    problems.extend(overview_problems(matrix, board))
    problems.extend(domain_problems(matrix, board))
    problems.extend(remnant_problems(matrix, board))
    if matrix["source"] == "srs-block":
        problems.extend(alignment_problems(matrix))
    return problems


def overview_problems(matrix: dict, board: dict) -> list[str]:
    problems: list[str] = []
    platforms = matrix["platforms"]
    header = board["overview"]["header"]
    needed = ["平台", "项数", "✅", "🟡", "⬜", "完成度"]
    missing = [name for name in needed if name not in header]
    if missing:
        return [f"§1 表头缺列 {missing}（判据按列名取值，缺一即判红）"]
    seen: dict[str, list[str]] = {}
    for row in board["overview"]["rows"]:
        if len(row) != len(header):
            problems.append(f"§1 表头 {len(header)} 列、行 {len(row)} 格（`{row[0]}`）⇒ 表格不自洽")
            continue
        seen[plain(row[0])] = row
    for name in platforms:
        if name not in seen:
            problems.append(f"§1 缺 `{name}` 行（真源有这一列 ⇒ 缺行即判红）")
    for name in seen:
        if name not in platforms:
            problems.append(f"§1 多出 `{name}` 行：真源没有这一列（不设列的端不许造行）")
    for name in platforms:
        row = seen.get(name)
        if row is None:
            continue
        expected = matrix["counts"][name]
        total = sum(expected.values())
        for column, status in (("项数", None), ("✅", "✅"), ("🟡", "🟡"), ("⬜", "⬜")):
            cell = row[index_of(header, column)]
            if not cell.isdigit():
                problems.append(f"§1 `{name}` 行 `{column}` 格 `{cell}` 不是整数")
                continue
            actual = int(cell)
            if status is None:
                if actual != total:
                    problems.append(f"§1 `{name}` 行 项数 {actual} ≠ 真源重算 {total}")
            elif actual != expected[status]:
                problems.append(f"§1 `{name}` 行 {column} {actual} ≠ 真源重算 {expected[status]}")
        cell = row[index_of(header, "完成度")]
        matched = re.search(r"(\d+)\s*%", cell)
        if matched is None:
            problems.append(f"§1 `{name}` 行 完成度格 `{cell}` 读不出百分比")
        else:
            want = round(expected["✅"] * 100 / total) if total else 0
            if int(matched.group(1)) != want:
                problems.append(f"§1 `{name}` 行 完成度 {matched.group(1)}% ≠ 重算 {want}%")
    return problems


def board_domain_keys(board: dict) -> tuple[dict[tuple[str, str], list[str]], list[str]]:
    """§2 的行 → (产品线, 域) → 整行。缺 `产品线` 列时退化成 (\"\", 域)。"""
    problems: list[str] = []
    header = board["domains"]["header"]
    name_index = index_of(header, "域")
    line_index = index_of(header, "产品线")
    keys: dict[tuple[str, str], list[str]] = {}
    for row in board["domains"]["rows"]:
        if len(row) != len(header):
            problems.append(f"§2 表头 {len(header)} 列、行 {len(row)} 格（`{row[0]}`）⇒ 表格不自洽")
            continue
        label = plain(row[name_index])
        line = plain(row[line_index]) if line_index is not None else ""
        key = (line, label)
        if key in keys:
            problems.append(f"§2 `{line}/{label}` 出现两次（同一（产品线, 域）只能一行）")
        keys[key] = row
    return keys, problems


def domain_problems(matrix: dict, board: dict) -> list[str]:
    problems: list[str] = []
    header = board["domains"]["header"]
    if "域" not in header or "条数" not in header:
        return ["§2 表头缺 `域` / `条数` 列"]
    count_index = index_of(header, "条数")
    column_index = {name: index_of(header, name) for name in matrix["platforms"]}
    absent = [name for name, index in column_index.items() if index is None]
    if absent:
        return [f"§2 表头缺端列 {absent}（真源有这一列）"]
    seen, shape = board_domain_keys(board)
    problems.extend(shape)
    two_level = index_of(header, "产品线") is not None
    wanted = set(matrix["domains"])
    if not two_level:
        wanted = {("", key[1]) for key in wanted}
        collapsed = {}
        for line, label in matrix["domains"]:
            if ("", label) in collapsed:
                problems.append(f"§2 缺 `产品线` 列，而 `{label}` 跨了多条产品线 ⇒ 无法定位是哪一域")
            collapsed[("", label)] = True
    for key in sorted(wanted):
        if key not in seen:
            problems.append(f"§2 缺 `{key[0]}/{key[1]}` 行（真源有这一域）")
    for key in seen:
        if key not in wanted:
            problems.append(f"§2 多出 `{key[0]}/{key[1]}` 行：真源没有这一（产品线, 域）")
    for (line, label), row in seen.items():
        key = (line, label) if two_level else ("", label)
        expected = matrix["domains"].get(key)
        if expected is None:
            continue
        name = f"{line}/{label}" if line else label
        if row[count_index].isdigit() and int(row[count_index]) != expected["count"]:
            problems.append(f"§2 `{name}` 条数 {row[count_index]} ≠ 真源重算 {expected['count']}")
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
                        f" ≠ 真源重算 {status}{expected['platforms'][platform][status]}"
                    )
    return problems


def remnant_problems(matrix: dict, board: dict) -> list[str]:
    """判据 E：§3 的两个分组 —— 声明条数、逐域条数、编号集合，逐条相等。"""
    problems: list[str] = []
    for status, name in (("⬜", "⬜"), ("🟡", "🟡")):
        declared = board["remnants"][status]
        expected_ids = [row["id"] for row in matrix["rows"] if row["status"]["macOS"] == status]
        if declared["declared"] != len(expected_ids):
            problems.append(f"§3 macOS {name} 声明 {declared['declared']} 条 ≠ 真源重算 {len(expected_ids)} 条")
        if len(declared["ids"]) != len(set(declared["ids"])):
            problems.append(f"§3 macOS {name} 编号里有重复项")
        if set(declared["ids"]) != set(expected_ids):
            missing = sorted(set(expected_ids) - set(declared["ids"]))
            extra = sorted(set(declared["ids"]) - set(expected_ids))
            problems.append(f"§3 macOS {name} 编号集合与真源不符（漏 {missing} / 多 {extra}）")
        per_domain: dict[str, list[str]] = {}
        for row in matrix["rows"]:
            if row["status"]["macOS"] == status:
                per_domain.setdefault(row["domain"], []).append(row["id"])
        for label in sorted(set(per_domain) | set(declared["groups"])):
            got = declared["groups"].get(label)
            want = per_domain.get(label)
            if got is None:
                problems.append(f"§3 macOS {name} 少一域 `{label}`（真源重算 {len(want)} 条）")
                continue
            if want is None:
                problems.append(f"§3 macOS {name} 多一域 `{label}`（真源该域 {name} 为 0 条）")
                continue
            if got["declared"] != len(want):
                problems.append(
                    f"§3 macOS {name} 的 `{label}` 声明 {got['declared']} 条 ≠ 真源重算 {len(want)} 条"
                )
            if set(got["ids"]) != set(want):
                problems.append(
                    f"§3 macOS {name} 的 `{label}` 编号集合与真源不符"
                    f"（漏 {sorted(set(want) - set(got['ids']))} / 多 {sorted(set(got['ids']) - set(want))}）"
                )
        total_groups = sum(group["declared"] for group in declared["groups"].values())
        if total_groups != declared["declared"]:
            problems.append(
                f"§3 macOS {name} 逐域之和 {total_groups} ≠ 同行声明的条数 {declared['declared']}"
                "（本文件自己不自洽）"
            )
    return problems


def alignment_problems(matrix: dict) -> list[str]:
    """判据 F：矩阵域标题里的「条数 / 与基线一致条数」也重算（`⚠️` 缺席 = 一致）。"""
    problems: list[str] = []
    for group in matrix["groups"]:
        members = [row for row in matrix["rows"] if row["domain"] == group["label"]]
        if len(members) != group["count"]:
            problems.append(f"矩阵 `{group['label']}` 域标题写 {group['count']} 条、表体 {len(members)} 行")
        declared = {label: int(number) for label, number in ALIGN_RE.findall(group["aligned"] or "")}
        for name in matrix["platforms"]:
            if name == BASELINE:
                continue   # macOS 就是基线的定义端 ⇒ 域标题不写「与 macOS 基线一致：macOS N 条」
            if name not in declared:
                problems.append(f"矩阵 `{group['label']}` 域标题缺 `{name}` 的「与基线一致」条数")
                continue
            actual = sum(1 for row in members if name not in row["alert"])
            if declared[name] != actual:
                problems.append(
                    f"矩阵 `{group['label']}` 域标题写 `{name}` 与基线一致 {declared[name]} 条"
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
    if matrix["source"] == "recomputed":
        print("ℹ️ 判据源：SRS §10.10 标记不在盘（2026-10-20 已迁《开发计划书》§5）⇒ 按 "
              "`gen-platform-parity` 的 `load_rows()` / `load_ledger()` **回退**重算；判据 A/B/C/D/E 一条不减，"
              "判据 F 无主体（矩阵自身漂移由 `gen-platform-parity.py --check` 守）")
    if problems:
        print(f"❌ 《任务清单·按平台》与真源不一致（{len(problems)} 处）：")
        for item in problems:
            print(f"   · {item}")
        return 1
    print(
        f"✅ 《任务清单·按平台》与真源逐列一致（{len(matrix['platforms'])} 端 × "
        f"{len(matrix['rows'])} 条需求 · §1 {len(board['overview']['rows'])} 行 / §2 "
        f"{len(board['domains']['rows'])} 行（产品线 × 域）/ §3 macOS ⬜ "
        f"{len(board['remnants']['⬜']['ids'])} 条 + 🟡 {len(board['remnants']['🟡']['ids'])} 条 · "
        f"macOS 列 {matrix['counts']['macOS']['✅']} ✅）"
    )
    return 0


# ── 自检：判据自己的证据 ────────────────────────────────────────────────────


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
    srs = pathlib.Path("Docs/Doyah产品需求规格说明书.md")

    def edit_board(old: str, new: str, count: int = 1):
        def setup(work: pathlib.Path) -> None:
            _edit(work / board, old, new, count)
        return setup

    def edit_srs(old: str, new: str, count: int = 1):
        def setup(work: pathlib.Path) -> None:
            _edit(work / srs, old, new, count)
        return setup

    def flip_ledger(identifier: str, status: str):
        """给台账里第一个平台写一条 overrides（真源翻一格，看板就该报红）。"""
        def setup(work: pathlib.Path) -> None:
            path = work / "Docs/平台实现状态.json"
            payload = json.loads(path.read_text(encoding="utf-8"))
            platform = next(iter(payload["platforms"]))
            payload["platforms"][platform].setdefault("overrides", {})[identifier] = status
            path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return setup

    def wipe_status_ledger(work: pathlib.Path) -> None:
        """《开发计划书》§3 状态台账的标题改坏 ⇒ 回退路径读到 0 条，必须判红（不许零命中=通过）。"""
        _edit(work / "Docs/Doyah产品开发计划任务清单.md", "## 3 需求状态台账", "## 3x 需求状态台账")

    # 夹具里的数字**一律现读**（不写死）：真值源多一域 / 改一个数，夹具自己跟着走。
    text = board.read_text(encoding="utf-8") if board.exists() else ""
    mac_row = re.search(r"^\| macOS \|.*$", text, re.M)
    assert mac_row is not None, "夹具取不到 macOS 一览行（§1 的形态变了？）"
    mac_cells = [int(cell) for cell in mac_row.group(0).split("|") if cell.strip().isdigit()]
    assert len(mac_cells) == 4, f"夹具取不到 macOS 一览行的四个数：{mac_cells}"
    mac_pct = re.search(r"\*\*(\d+)%\*\*", mac_row.group(0)).group(1)
    MAC = {"total": mac_cells[0], "done": mac_cells[1], "mid": mac_cells[2], "blank": mac_cells[3]}
    MAC_CELLS = f"| {MAC['total']} | {MAC['done']} | {MAC['mid']} | {MAC['blank']} |"
    MAC_CELLS_DONE_MINUS_1 = f"| {MAC['total']} | {MAC['done'] - 1} | {MAC['mid']} | {MAC['blank']} |"
    MAC_CELLS_TOTAL_MINUS_1 = f"| {MAC['total'] - 1} | {MAC['done']} | {MAC['mid']} | {MAC['blank']} |"
    MAC_BLANK_PCT = f"| {MAC['blank']} | **{mac_pct}%** |"
    MAC_BLANK_DECL = f"- **macOS 的 ⬜（{MAC['blank']} 条"
    # §2 的一整行现读（第一行 = 某产品线的第一个域）
    domain_line = re.search(r"^\| (?:STD|RTR|AGT|NTS|ALL) \|.*$", text, re.M)
    assert domain_line is not None, "夹具取不到 §2 的数据行"
    DOMAIN_ROW = domain_line.group(0)
    DOMAIN_ROW_CELLS = cells(DOMAIN_ROW)
    DOMAIN_KEY = f"{plain(DOMAIN_ROW_CELLS[0])}/{plain(DOMAIN_ROW_CELLS[2])}"
    DOMAIN_COUNT = DOMAIN_ROW_CELLS[3]
    # §3 的一个域分组（⬜ 段的第一个域 + 🟡 段的第一个域，两段各取一条）
    def first_group_after(marker: str) -> re.Match:
        start = text.index(marker)
        found = re.search(r"^\s{2}- \*\*(?P<label>[^*]+)\*\*（(?P<count>\d+) 条）：.*$", text[start:], re.M)
        assert found is not None, f"夹具取不到 §3「{marker[:24]}…」之后的域分组行"
        return found

    group_line = first_group_after("- **macOS 的 ⬜（")
    GROUP_LABEL, GROUP_COUNT = group_line.group("label"), int(group_line.group("count"))
    first_id = ID_RE.search(group_line.group(0)).group(0)
    partial_group = first_group_after("- **macOS 的 🟡（")
    PARTIAL_LABEL, PARTIAL_COUNT = partial_group.group("label"), int(partial_group.group("count"))
    PARTIAL_PREFIX = f"  - **{PARTIAL_LABEL}**（{PARTIAL_COUNT} 条）："
    partial_decl = re.search(r"^- \*\*macOS 的 🟡（(?P<count>\d+) 条.*$", text, re.M)
    assert partial_decl is not None, "夹具取不到 §3 的 🟡 分组标题"
    PARTIAL_DECL = partial_decl.group(0)
    # §2 首行的 macOS 格（现读 ✅ 个数，改一格不靠写死）
    first_cell = CELL_RE.search(DOMAIN_ROW_CELLS[4])
    assert first_cell is not None, f"§2 首行的 macOS 格不是 `✅a / 🟡b / ⬜c`：{DOMAIN_ROW_CELLS[4]}"
    DOMAIN_DONE = int(first_cell.group(1))

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
            "setup": edit_board("| Windows |", "| WinX |"),
            "steps": [([], 1, "缺 `Windows` 行")],
        },
        {
            "name": "⑥ §1 多一行（给移动端造 iOS 行）",
            "setup": edit_board(
                "|---|---|---:|---:|---:|---:|---:|---|",
                "|---|---|---:|---:|---:|---:|---:|---|\n"
                f"| iOS | 对侧 | {MAC['total']} | 0 | 0 | {MAC['total']} | **0%** | 造出来的一行 |",
            ),
            "steps": [([], 1, "多出 `iOS` 行")],
        },
        {
            "name": f"⑦ §2 逐域表的某一格写错（{DOMAIN_KEY} 的 macOS 格 ✅{DOMAIN_DONE} → {DOMAIN_DONE + 1}）",
            "setup": edit_board(
                f"| {DOMAIN_COUNT} | ✅{DOMAIN_DONE} /",
                f"| {DOMAIN_COUNT} | ✅{DOMAIN_DONE + 1} /",
            ),
            "steps": [([], 1, "§2 `")],
        },
        {
            "name": "⑧ §2 逐域表的条数写错（首行条数 +1）",
            "setup": edit_board(
                f"| {plain(DOMAIN_ROW_CELLS[2])} | {DOMAIN_COUNT} | ✅",
                f"| {plain(DOMAIN_ROW_CELLS[2])} | {int(DOMAIN_COUNT) + 1} | ✅",
            ),
            "steps": [([], 1, "条数")],
        },
        {
            "name": f"⑨ §3 macOS ⬜ 的编号被删掉一个（`{first_id}`）",
            "setup": edit_board(f"`{first_id}`、", ""),
            "steps": [([], 1, "编号集合")],
        },
        {
            "name": f"⑩ §3 macOS ⬜ 的声明条数写错（{MAC['blank']} → {MAC['blank'] - 1}）",
            "setup": edit_board(MAC_BLANK_DECL, f"- **macOS 的 ⬜（{MAC['blank'] - 1} 条"),
            "steps": [([], 1, f"声明 {MAC['blank'] - 1} 条")],
        },
        {
            "name": f"⑪ §3 macOS 🟡 的逐域条数写错（{PARTIAL_LABEL} {PARTIAL_COUNT} → {PARTIAL_COUNT - 1}）",
            "setup": edit_board(PARTIAL_PREFIX, f"  - **{PARTIAL_LABEL}**（{PARTIAL_COUNT - 1} 条）："),
            "steps": [([], 1, "macOS 🟡")],
        },
        {
            "name": "⑫ §3 macOS 🟡 的分组标题行被删（空跑不许当通过）",
            "setup": edit_board(PARTIAL_DECL + "\n", ""),
            "steps": [([], 1, "空跑判红")],
        },
        {
            "name": "⑬ 真源状态台账读不到（§3 标题改坏）⇒ 回退路径判红，零命中不许当通过",
            "setup": wipe_status_ledger,
            "steps": [([], 1, "空跑")],
        },
        {
            "name": "⑭ 真源台账翻一格（CONN-001 → ✅）⇒ 看板没跟版即判红（派生方向）",
            "setup": flip_ledger("FR-STD-DB-CONN-001", "✅"),
            "steps": [([], 1, "§1")],
        },
        {
            "name": "⑮ 本文件 §1 的表头被删（空跑不许当通过）",
            "setup": edit_board("| 平台 | 归属 | 项数 | ✅ | 🟡 | ⬜ | 完成度 | 一句话 |\n", ""),
            "steps": [([], 1, "空跑判红")],
        },
    ]


def self_test() -> int:
    needed = [SRS, BOARD, ROOT / "Docs/平台实现状态.json",
              doc_index.path(),
              ROOT / "Docs/Doyah产品开发计划任务清单.md"]
    absent = [str(path) for path in needed if not path.exists()]
    if absent:
        print(f"❌ 自检需要真实的真源与看板，缺：{absent}")
        return 1
    before = {path: digest(path) for path in needed}
    cases = build_cases()
    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="board-parity-selftest-") as tmp:
        base = pathlib.Path(tmp) / "base"
        (base / "Docs").mkdir(parents=True)
        for path in needed:
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
                    f"（stdout: {result.stdout.strip()[:240]}）"
                )
                continue
            if want_text and want_text not in combined:
                failures.append(
                    f"{case['name']}｜退出码对，但输出里没有 {want_text!r}"
                    f"（stdout: {result.stdout.strip()[:240]}）"
                )
    after = {path: digest(path) for path in needed}
    if before != after:
        failures.append("自检动了真仓库的文件（写坏必须只发生在临时副本上）")
    if failures:
        print(f"❌ 按平台任务清单判据自检未通过（{len(cases)} 例里 {len(failures)} 例不符预期）：")
        for failure in failures:
            print(f"   · {failure}")
        return 1
    print(f"✅ 按平台任务清单判据自检通过（{len(cases)}/{len(cases)}；真仓库五份文件逐字节未变）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
