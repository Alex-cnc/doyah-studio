#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""重生成《任务清单 · 按平台》（`PC-BOARD-001`）的 §1 / §2 / §3 —— 从真源，不手写。

为什么要有生成器（而不是让判据一直红着）：
    2026-10-20 状态矩阵从《需求规格说明书》§10.10 迁到《开发计划书》§5、需求索引独立成文
    （`Docs/Doyah产品需求规格说明书-需求索引.md`）之后，本文件的三节仍是按旧矩阵手抄的读数
    （290 项 / macOS 130✅70🟡90⬜ / §2 15 个域），而 `check-board-parity.py` 从真源逐列重算
    ⇒ 第 7 项**持续红**。红得久了只剩两个结局：判据被删，或者人学会忽略它。逐格手跟版也走不通
    （真源一动就得重抄 30 多格 + 149 个编号），所以这里把「抄」这一半也机械掉。

真源（唯一，两处，都由 `Scripts/gen-platform-parity.py` 提供 —— 本脚本不另读任何表）：
    · `load_rows()` → [(编号, macOS 状态, 需求摘要)]（编号集合 = 需求索引；macOS 状态 = 计划书 §3 台账）
    · `load_ledger(known_ids)` → (default, platforms, not_platforms)，每平台带 `label` / `overrides`
    · `DOMAIN_LABEL`：`FR-<域码>` → 中文域名（缺项**照原域码**写，不编域名）

派生口径（写死在这里，判据 `check-board-parity.py` 逐格独立重算同一口径）：
    · 域码 = **编号倒数第二段**（`FR-STD-DB-CONN-001` → `CONN`）；产品线 = 第 2 段（`STD` / `RTR` / `AGT` / `NTS`）；
    · §1 完成度 = `round(✅ ÷ (✅ + 🟡 + ⬜) × 100)`（与判据**同一表达式**，免得 0.5 处两边各取各的）；
    · §2 = **产品线 → 域** 两级：一行 = 一个（产品线, 域码），列 = 四端 + 条数；
    · §3 = macOS 侧残项，**按域分组列编号**（⬜ 逐条编号 / 🟡 同样逐条编号）—— macOS 是基线端，
      「本侧还差哪几条」只有这一处能回答。

只重写 §1 / §2 / §3；§4（判据与维护）与 §5（变更记录）**一字不动**，除了 §5 首行由本脚本追加
一条 v1.5 说明（`--check` 不判 §5，它只是留痕）。

用法：
    python3 Scripts/gen-platform-board.py             # 重写 §1 / §2 / §3
    python3 Scripts/gen-platform-board.py --check     # 只判是否与真源一致（闭环第 7 项）
    python3 Scripts/gen-platform-board.py --self-test # 门禁自检（9 例负例，写坏只在临时目录）
    DOYAH_ROOT=<别的工程根> python3 …                  # 换工程根（`--self-test` 用）
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
BOARD = ROOT / ".build/derived/任务清单-按平台.md"
PARITY = pathlib.Path(__file__).with_name("gen-platform-parity.py")
SCRIPT = pathlib.Path(__file__).resolve()

STATUSES = ("✅", "🟡", "⬜")
BOARD_BEGIN = "<!-- BEGIN board-sections -->"
BOARD_END = "<!-- END board-sections -->"
SECTION_HEAD = re.compile(r"^## (?P<number>[1-5])\. ")
VERSION_ROW = re.compile(r"^\| 版本 \| \*\*v(?P<version>[0-9.]+)\*\* \|$")
VERSION_MARK = "**按真源重生成（项数 290 → 379）**"
VERSION_NOTE = (
    "| v1.5 | 2026-10-20 | **按真源重生成（项数 290 → 379）**：状态矩阵已迁《开发计划书》§5、"
    "需求索引独立成文 ⇒ §1 / §2 / §3 改由新脚本 `Scripts/gen-platform-board.py` 从 "
    "`gen-platform-parity` 的 `load_rows` / `load_ledger` 机械重写（三节由一对 HTML 注释标记夹住、"
    "`--check` 判漂移），手抄这一半就此退役；"
    "判据仍是 `check-board-parity.py`（§1 合计 / §2 逐格 / §3 残项逐条判红，"
    "§10.10 标记不在盘时回退到同一真源重算）。**本文件仍不新增真值。** | 铁皮大河马（`hugehippo` · macOS 侧） |"
)


class BoardError(Exception):
    """读不到该读的东西 / 真源不合口径（一次把问题列全）。"""

    def __init__(self, problems: list[str]) -> None:
        super().__init__("；".join(problems))
        self.problems = list(problems)


def parity():
    """把真源脚本按模块加载（它自己的 ROOT 也取 `DOYAH_ROOT`，与本脚本同根）。"""
    spec = importlib.util.spec_from_file_location("gen_platform_parity", PARITY)
    if spec is None or spec.loader is None:   # pragma: no cover - 只在文件被删时发生
        raise BoardError([f"读不到真源脚本 {PARITY}"])
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# ── 真源 → 模型 ──────────────────────────────────────────────────────────────


def domain_of(identifier: str) -> str:
    """域码 = 编号**倒数第二段**（`FR-STD-DB-CONN-001` → `CONN`）。"""
    return identifier.split("-")[-2]


def line_of(identifier: str) -> str:
    """产品线 = 编号第 2 段（`STD` / `RTR` / `AGT` / `NTS`）。"""
    return identifier.split("-")[1]


def build_model() -> dict:
    """从真源算出 §1 / §2 / §3 要用的全部读数（判据另有一份独立重算，互不复用）。"""
    source = parity()
    try:
        rows = source.load_rows()
        default, platforms, not_platforms = source.load_ledger({identifier for identifier, _, _ in rows})
    except source.LedgerError as error:
        raise BoardError(list(error.problems)) from error
    if not rows:
        raise BoardError(["真源读到 0 条需求 —— 空跑不是通过（需求索引 / 状态台账的锚点变了？）"])

    columns = ["macOS"] + [platform["label"] for platform in platforms]
    status: dict[str, dict[str, str]] = {}
    lines: dict[str, str] = {}
    domains: dict[str, str] = {}
    summaries: dict[str, str] = {}
    for identifier, macos, summary in rows:
        line, code = line_of(identifier), domain_of(identifier)
        lines[identifier] = line
        domains[identifier] = source.DOMAIN_LABEL.get(f"FR-{code}", f"FR-{code}")
        summaries[identifier] = summary
        status[identifier] = {"macOS": macos}
        for platform in platforms:
            status[identifier][platform["label"]] = platform["overrides"].get(identifier, default)

    counts = {
        column: {value: sum(1 for identifier in status if status[identifier][column] == value)
                 for value in STATUSES}
        for column in columns
    }
    return {
        "ids": [identifier for identifier, _, _ in rows],
        "columns": columns,
        "platforms": platforms,
        "not_platforms": not_platforms,
        "default": default,
        "status": status,
        "lines": lines,
        "domains": domains,
        "summaries": summaries,
        "counts": counts,
    }


PL_ORDER = ("STD", "RTR", "AGT", "NTS", "ALL")
PL_LABEL = {
    "AGT": "Agent",
    "STD": "Studio（Workspace + Database Client）",
    "NTS": "Doyah Notes（笔记 + 待办）",
    "RTR": "Doyah Retro（数据 / 研究 / 工作流 / 复盘）",
    "ALL": "跨产品横切",
}


def percent(done: int, total: int) -> int:
    """完成度 —— 表达式与 `check-board-parity.py` 逐字相同（同一份口径，两处取整必须一致）。"""
    return round(done * 100 / total) if total else 0


# ── 三节正文 ────────────────────────────────────────────────────────────────


def group_pairs(model: dict) -> list[tuple[str, str]]:
    """(产品线, 域) 两级的行序：产品线按 PL_ORDER，域按域码字典序。"""
    present = [line for line in PL_ORDER if any(model["lines"][i] == line for i in model["ids"])]
    rest = sorted({model["lines"][i] for i in model["ids"]} - set(present))
    pairs: list[tuple[str, str]] = []
    for line in present + rest:
        members = [i for i in model["ids"] if model["lines"][i] == line]
        for code in sorted({domain_of(i) for i in members}):
            pairs.append((line, code))
    return pairs


def render_overview(model: dict) -> str:
    columns = model["columns"]
    labels = " / ".join(columns)
    out = [
        "## 1. 一览（机械计数 · 派生自《开发计划书》§5 平台等价矩阵的四列）",
        "",
        f"共 **{len(model['ids'])}** 条功能需求（逐端同一个分母）· 端：{labels}。",
        "",
        "| 平台 | 归属 | 项数 | ✅ | 🟡 | ⬜ | 完成度 | 一句话 |",
        "|---|---|---:|---:|---:|---:|---:|---|",
    ]
    for column in columns:
        counts = model["counts"][column]
        total = sum(counts.values())
        if column == "macOS":
            owner = "本侧（**基线 = 唯一事实源**）"
            note = "参考端读数；还差哪几条见 §3"
        else:
            platform = next(item for item in model["platforms"] if item["label"] == column)
            # 台账里的维护者字段带沿革注记（「—— 2026-10-15 人类主人拍板…」）；表里只留人，注记归台账
            owner = platform["owner"].split("——")[0].strip() or platform["owner"]
            aligned = sum(1 for identifier in model["ids"] if model["status"][identifier][column]
                          == model["status"][identifier]["macOS"])
            note = (f"台账 `overrides` 显式 {len(platform['overrides'])} 条 · "
                    f"与 macOS 基线一致 {aligned} 条 · 其余按 `{model['default']}` 记")
        out.append(
            f"| {column} | {owner} | {total} | {counts['✅']} | {counts['🟡']} | {counts['⬜']} | "
            f"**{percent(counts['✅'], total)}%** | {note} |"
        )
    out.extend([
        "",
        "> 完成度 = ✅ ÷（✅ + 🟡 + ⬜），四舍五入到整数个百分点。",
    ])
    for platform in model["platforms"]:
        out.append(f"> **{platform['label']}** 列口径：{platform['role']}")
    for platform in model["not_platforms"]:
        out.append(f"> **{platform['label']}不设行**：{platform['why']}")
    out.extend([
        "> 一格一个读数：`⬜` 是「未开工 / 未落地」，不是失败；`🟡` 是「已实现、待点验或待续做」。",
        "> 逐域读法见 §2；macOS 侧「还差哪几条」见 §3。**本表由 `Scripts/gen-platform-board.py` 重写**，"
        "勿手改计数。",
        "",
    ])
    return "\n".join(out)


def render_domains(model: dict) -> str:
    columns = model["columns"]
    legend = " · ".join(f"`{line}` = {PL_LABEL.get(line, line)}" for line in PL_ORDER
                        if any(model["lines"][i] == line for i in model["ids"]))
    out = [
        "## 2. 逐域 × 逐端（产品线 → 域 两级 · 同一份真源的另一种切法）",
        "",
        "每格 = `✅ / 🟡 / ⬜`，逐格是矩阵读数；`条数` = 该（产品线, 域）在矩阵里占的行数。",
        "",
        f"> 产品线：{legend}",
        "",
        "| 产品线 | 域码 | 域 | 条数 | " + " | ".join(columns) + " |",
        "|---|---|---|---:|" + "---|" * len(columns),
    ]
    for line, code in group_pairs(model):
        members = [i for i in model["ids"] if model["lines"][i] == line and domain_of(i) == code]
        cells = []
        for column in columns:
            counts = {value: sum(1 for i in members if model["status"][i][column] == value)
                      for value in STATUSES}
            cells.append(f"✅{counts['✅']} / 🟡{counts['🟡']} / ⬜{counts['⬜']}")
        out.append(
            f"| {line} | `{code}` | {model['domains'][members[0]]} | {len(members)} | "
            + " | ".join(cells) + " |"
        )
    out.extend([
        "",
        f"> 合计 **{len(group_pairs(model))}** 个（产品线, 域）组合、"
        f"**{len({domain_of(i) for i in model['ids']})}** 个域码、**{len(model['ids'])}** 条需求 —— "
        "三者对不上就是生成器坏了。",
        "",
    ])
    return "\n".join(out)


def render_remnants(model: dict) -> str:
    out = [
        "## 3. macOS 侧的残项（本侧要交的那一列 · 按域分组）",
        "",
        "> 只列 macOS 列（基线端）。每组的 `N 条` 必须等于该组编号个数；编号集合与矩阵逐条相等",
        "> （`check-board-parity.py` 判据 E 逐条判红）。",
        "",
    ]
    for status in ("⬜", "🟡"):
        members = [i for i in model["ids"] if model["status"][i]["macOS"] == status]
        name = "未开工 / 未落地" if status == "⬜" else "已实现、待点验或待续做"
        out.append(f"- **macOS 的 {status}（{len(members)} 条 · 按域 · {name}）**")
        by_domain: dict[str, list[str]] = {}
        for identifier in members:
            by_domain.setdefault(model["domains"][identifier], []).append(identifier)
        for label in sorted(by_domain, key=lambda text: (-len(by_domain[text]), text)):
            ids = by_domain[label]
            out.append(f"  - **{label}**（{len(ids)} 条）：" + "、".join(f"`{i}`" for i in ids))
        if not members:
            out.append("  - （本列没有残项）")
        out.append("")
    out.extend([
        "> 要开工哪一条，改的是真值源（`Docs/平台实现状态.json` 的 `overrides` / 《开发计划书》§3 状态台账）"
        "⇒ 跑 `python3 Scripts/gen-platform-parity.py` 重写 §5 矩阵 ⇒ 跑 "
        "`python3 Scripts/gen-platform-board.py` 重写本节。",
        "",
    ])
    return "\n".join(out)


def render_sections(model: dict) -> str:
    return "\n".join([render_overview(model), render_domains(model), render_remnants(model)])


# ── 与文件拼接 ──────────────────────────────────────────────────────────────


def split_board(text: str) -> tuple[str, str, str]:
    """把整篇切成 (§1 之前, §1/§2/§3 正文, §4 起) —— 找不到 §1 或 §4 即抛（空跑判红）。"""
    lines = text.splitlines(keepends=True)
    heads = {}
    for index, line in enumerate(lines):
        matched = SECTION_HEAD.match(line)
        if matched:
            heads.setdefault(int(matched.group("number")), index)
    missing = [number for number in (1, 4) if number not in heads]
    if missing:
        raise BoardError([
            f"{BOARD} 里找不到 `## {number}. ` 小节标题（三节的边界由 §1 起、§4 止夹住）"
            for number in missing
        ])
    start, stop = heads[1], heads[4]
    if start >= stop:
        raise BoardError([f"{BOARD} 的 §1 / §4 小节顺序错乱（§1 在第 {start + 1} 行、§4 在第 {stop + 1} 行）"])
    head = "".join(lines[:start])
    tail = "".join(lines[stop:])
    return head, "".join(lines[start:stop]), tail


def compose(model: dict, text: str) -> str:
    """把三节重写进整篇（旧的外壳标记先摘掉，否则会套娃）。"""
    stripped = text.replace(f"{BOARD_BEGIN}\n", "", 1).replace(f"{BOARD_END}\n", "", 1)
    head, _, tail = split_board(stripped)
    body = f"{BOARD_BEGIN}\n{render_sections(model)}{BOARD_END}\n\n"
    return f"{head}{body}{tail}"


def bump_version(text: str) -> str:
    """头部版本格 v1.4 → v1.5，并在 §5 变更记录首行前插一条 v1.5 说明（幂等）。"""
    if VERSION_MARK in text:
        return text
    lines = text.splitlines()
    for index, line in enumerate(lines):
        matched = VERSION_ROW.match(line.strip())
        if matched:
            lines[index] = f"| 版本 | **v1.5** |"
            break
    else:
        raise BoardError([f"{BOARD} 头部找不到 `| 版本 | **vX.Y** |` 格（变更记录要与它同号）"])
    for index, line in enumerate(lines):
        if re.match(r"^\|\s*版本\s*\|\s*日期\s*\|", line):
            lines.insert(index + 2, VERSION_NOTE)
            break
    else:
        raise BoardError([f"{BOARD} §5 变更记录表头读不到（v1.5 无处置）"])
    return "\n".join(lines) + "\n"


def first_differences(current: str, updated: str, limit: int = 4) -> list[tuple[int, str, str]]:
    old, new = current.splitlines(), updated.splitlines()
    out: list[tuple[int, str, str]] = []
    for index in range(max(len(old), len(new))):
        left = old[index] if index < len(old) else "<缺行>"
        right = new[index] if index < len(new) else "<多余>"
        if left != right:
            out.append((index + 1, left, right))
            if len(out) >= limit:
                break
    return out


def digest(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


# ── 自检：判据自己的证据 ────────────────────────────────────────────────────


def _must(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def _edit_board(old: str, new: str, count: int = 1):
    def setup(root: pathlib.Path) -> None:
        path = root / ".build/derived/任务清单-按平台.md"
        text = path.read_text(encoding="utf-8")
        if old not in text:
            raise AssertionError(f"夹具目标 {old!r} 不在看板里")
        path.write_text(text.replace(old, new, count), encoding="utf-8")

    return setup


def _flip_ledger(setting: str):
    def setup(root: pathlib.Path) -> None:
        path = root / "Docs/平台实现状态.json"
        payload = json.loads(path.read_text(encoding="utf-8"))
        platform = next(iter(payload["platforms"]))
        payload["platforms"][platform].setdefault("overrides", {})["FR-STD-DB-CONN-001"] = setting
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    return setup


def build_cases() -> list[dict]:
    def drop_section(root: pathlib.Path) -> None:
        path = root / ".build/derived/任务清单-按平台.md"
        lines = [line for line in path.read_text(encoding="utf-8").splitlines(keepends=True)
                 if not line.startswith("## 4. ")]
        path.write_text("".join(lines), encoding="utf-8")

    def blank_section_two(root: pathlib.Path) -> None:
        path = root / ".build/derived/任务清单-按平台.md"
        text = path.read_text(encoding="utf-8")
        start = text.index("## 2. ")
        stop = text.index("## 3. ")
        path.write_text(text[:start] + "## 2. 逐域 × 逐端（被人挖空了）\n\n" + text[stop:], encoding="utf-8")

    return [
        {"name": "① 基线：生成一次后 --check 必须一致", "steps": [([], 0, "已重写"), (["--check"], 0, "一致")]},
        {
            "name": "② §1 的一格被手改 ⇒ --check 报红",
            "setup": _edit_board("| 379 |", "| 378 |"),
            "steps": [(["--check"], 1, "不一致")],
        },
        {
            "name": "③ §1 多造一行（移动端不设列，不许造行）⇒ --check 报红",
            "setup": _edit_board(
                "|---|---|---:|---:|---:|---:|---:|---|",
                "|---|---|---:|---:|---:|---:|---:|---|\n| iOS | 对侧 | 379 | 0 | 0 | 379 | **0%** | 造出来的 |",
            ),
            "steps": [(["--check"], 1, "不一致")],
        },
        {
            "name": "④ §2 的（产品线, 域）行被手改 ⇒ --check 报红",
            "setup": _edit_board("| `EDIT` | SQL 编辑与执行 |", "| `EDIT` | SQL 执行 |"),
            "steps": [(["--check"], 1, "不一致")],
        },
        {
            "name": "⑤ §2 的产品线列被抹 ⇒ --check 报红（两级表少一级）",
            "setup": _edit_board("| STD |", "| 　 |"),
            "steps": [(["--check"], 1, "不一致")],
        },
        {
            "name": "⑥ §3 的编号被删一个（条数不动）⇒ --check 报红",
            "setup": _edit_board("、`FR-STD-", "、`FR-XXX-", 1),
            "steps": [(["--check"], 1, "不一致")],
        },
        {
            "name": "⑦ 真源台账翻一格 ⇒ 看板没重生成即报红（派生方向）",
            "setup": _flip_ledger("✅"),
            "steps": [(["--check"], 1, "不一致")],
        },
        {
            "name": "⑧ §4 标题被删 ⇒ 报红并点名文件（三节边界丢了，不许静默）",
            "setup": drop_section,
            "steps": [(["--check"], 1, "找不到")],
        },
        {
            "name": "⑨ §2 被挖空 ⇒ 重生成后 --check 一致（证明它是被重写而不是被跳过）",
            "setup": blank_section_two,
            "steps": [([], 0, "已重写"), (["--check"], 0, "一致")],
            "inspect": lambda root: _must(
                "| STD |" in (root / ".build/derived/任务清单-按平台.md").read_text(encoding="utf-8"),
                "重生成没有把 §2 的（产品线, 域）行写回来",
            ),
        },
    ]


def run_script(root: pathlib.Path, argv: list[str]) -> subprocess.CompletedProcess:
    environment = dict(os.environ, DOYAH_ROOT=str(root))
    return subprocess.run([sys.executable, str(SCRIPT), *argv], capture_output=True, text=True,
                          env=environment, cwd=str(root))


def self_test() -> int:
    needed = [BOARD, ROOT / "Docs/Doyah产品需求规格说明书.md",
              doc_index.path(),
              ROOT / "Docs/Doyah产品开发计划任务清单-macOS端.md", ROOT / "Docs/平台实现状态.json"]
    absent = [str(path) for path in needed if not path.exists()]
    if absent:
        print(f"❌ 自检需要真实的真源与看板，缺：{absent}")
        return 1
    before = {path: digest(path) for path in needed}
    cases = build_cases()
    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="board-gen-selftest-") as tmp:
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
            broken = False
            for argv, want_rc, want_text in case["steps"]:
                result = run_script(work, argv)
                combined = f"{result.stdout}\n{result.stderr}"
                if result.returncode != want_rc:
                    failures.append(
                        f"{case['name']}｜{' '.join(argv) or '(重生成)'} 期望退出码 {want_rc}、"
                        f"实际 {result.returncode}（stdout: {result.stdout.strip()[:200]}）"
                    )
                    broken = True
                    break
                if want_text and want_text not in combined:
                    failures.append(
                        f"{case['name']}｜{' '.join(argv) or '(重生成)'} 退出码对，但输出里没有 "
                        f"{want_text!r}（stdout: {result.stdout.strip()[:200]}）"
                    )
                    broken = True
                    break
            if broken:
                continue
            inspect = case.get("inspect")
            if inspect is not None:
                try:
                    inspect(work)
                except AssertionError as error:
                    failures.append(f"{case['name']}｜{error}")
    after = {path: digest(path) for path in needed}
    if before != after:
        failures.append("自检动了真仓库的文件（写坏必须只发生在临时副本上）")
    if failures:
        print(f"❌ 按平台看板生成器自检未通过（{len(cases)} 例里 {len(failures)} 例不符预期）：")
        for failure in failures:
            print(f"   · {failure}")
        return 1
    print(f"✅ 按平台看板生成器自检通过（{len(cases)}/{len(cases)}；真仓库四份真源 + 看板逐字节未变）")
    return 0


# ── 入口 ───────────────────────────────────────────────────────────────────


def main() -> int:
    arguments = set(sys.argv[1:])
    unknown = arguments - {"--check", "--self-test"}
    if unknown:
        print(f"❌ 不认的参数：{' '.join(sorted(unknown))}（只支持 --check / --self-test）")
        return 2
    if "--self-test" in arguments:
        return self_test()
    if not BOARD.exists():
        print(f"❌ {BOARD} 不在盘（派生视图没有落点，无从生成）")
        return 1
    try:
        model = build_model()
        current = BOARD.read_text(encoding="utf-8")
        updated = compose(model, current)
    except BoardError as error:
        print(f"❌ 按平台看板生成失败（{len(error.problems)} 处）：")
        for problem in error.problems:
            print(f"   · {problem}")
        return 1

    pairs = group_pairs(model)
    detail = (f"{len(model['ids'])} 条需求 · {len(model['columns'])} 端 · "
              f"{len(pairs)} 个（产品线, 域）· macOS {model['counts']['macOS']['✅']}✅"
              f"/{model['counts']['macOS']['🟡']}🟡/{model['counts']['macOS']['⬜']}⬜")
    if "--check" in arguments:
        if normalize(current) == normalize(updated):
            print(f"✅ 《任务清单·按平台》§1/§2/§3 与真源重算一致（{detail}）")
            return 0
        print("❌ 《任务清单·按平台》§1/§2/§3 与真源不一致（真源改了而看板没重生成）：")
        old_block = current.split(BOARD_BEGIN, 1)[-1].split(BOARD_END, 1)[0]
        new_block = updated.split(BOARD_BEGIN, 1)[-1].split(BOARD_END, 1)[0]
        for line_number, left, right in first_differences(old_block.strip(), new_block.strip()):
            print(f"   §1-3 第 {line_number} 行  现状：{left[:110]}")
            print(f"   §1-3 第 {line_number} 行  应为：{right[:110]}")
        print("   请运行 python3 Scripts/gen-platform-board.py 重写")
        return 1

    final = bump_version(updated)
    if final != current:
        BOARD.write_text(final, encoding="utf-8")
    print(f"✅ 已重写《任务清单·按平台》§1/§2/§3（{detail}）")
    return 0


def normalize(text: str) -> str:
    """比对口径：只看 §1~§3 这三节（§4 / §5 与头部的散文不属本脚本的判据面）。

    按小节标题切，**不按外壳标记切** —— 头部与 §5 的说明文字里也会提到那对标记，
    按标记切会把散文当成派生区块（实测：切出来只剩「` / `」5 个字符，于是恒绿）。
    """
    stripped = text.replace(f"{BOARD_BEGIN}\n", "", 1).replace(f"{BOARD_END}\n", "", 1)
    try:
        _, body, _ = split_board(stripped)
    except BoardError:
        body = stripped
    return "\n".join(line.rstrip() for line in body.strip().splitlines() if line.strip())


if __name__ == "__main__":
    raise SystemExit(main())
