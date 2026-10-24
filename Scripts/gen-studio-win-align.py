#!/usr/bin/env python3
"""生成 `Docs/平台对齐-Studio-Windows对macOS.md` —— Windows 侧对齐 macOS 开发的逐条索引。

**本件身份：派生视图（非契约）**。真值源只有四处，本脚本**只读**、一字不写：
    ① `Docs/Doyah产品需求规格说明书-需求索引.md` 的编号索引（编号 / 所属域 / 层次）—— 行集合与行序；
    ② 《开发计划书》§3 需求状态台账的「状态」列 —— macOS 基线状态（**唯一来源**；
       2026-10-20 从 SRS §10.1 索引迁来，状态不再写在索引里）；
    ③ `Docs/Doyah产品需求规格说明书-追溯表.md`（「实现位置」列）—— 落点索引
       （2026-10-20 从 SRS §10.2 整体移出）；
    ④ `Docs/平台实现状态.json`（其他平台状态；macOS 不在台账里）。
产出件在 `Docs/` 根、并登记在 `Docs/README.md` 索引里。

**为什么要有它**：三书能给「应该有什么」（FR/NFR + 验收）、「设计怎么做」、「macOS 逐条到没到」
（平台等价矩阵的 macOS 列），给不了**落点索引**（去哪个文件读 macOS 实现）。Windows 侧（`babyhippo`）
对齐时每一条都得自己翻追溯表 —— 派生视图把这一步变成一次查询。
一次性快照必漂移，故由本脚本产出、`--check` 判漂移（闭环第 7 项）。
本件**不含**在飞卡 / 排期 / 剩余工作 —— 那些在工作台账与看板里，不属契约层。

**口径（写死在下面这些函数里，改口径先改本段）**：
    · 行序 = 需求索引的行序，一条需求一行（索引几条 → 几行，一行不少）；
    · `macOS` 列 = 计划书 §3 台账状态列的**首个取值**（✅ / 🟡 / ⬜）；取不到合法取值即判红；
    · `macOS 落点` 列 = 追溯表该条所在行的**反引号片段**（前 3 个 + 「等 N 处」）；
      - 格内转义竖线 `\\|` 按**字面**处理、不当列分隔符（一次性快照正是在这里错了一行）；
      - 同一编号出现在多行时**取最后一行**（后写的行是更准的登记）；
      - 范围行（`FR-STD-DB-CONN-007 ~ 03`）展开到范围内每一条；
      - **无追溯行 ⇒ `—`**；有行但一格反引号都没有 ⇒ `（追溯表有行、未标路径）`
        —— 这两种都不许编落点（「为好看」造出来的落点是本件最坏的失败模式）；
    · `Windows` 列 = 台账 `platforms.windows.overrides`（缺省 `default`）；取值非法即判红。

用法：
    python3 Scripts/gen-studio-win-align.py            # 重写产出件
    python3 Scripts/gen-studio-win-align.py --check    # 只判是否与盘上一致（闭环第 7 项）
    DOYAH_ROOT=<别的工程根> python3 …                   # 换工程根（自检 / 演练用）
"""

from __future__ import annotations

import json
import os
import pathlib
import re
import sys

ROOT = pathlib.Path(os.environ.get("DOYAH_ROOT", "."))
INDEX = ROOT / "Docs/Doyah产品需求规格说明书-需求索引.md"
PLAN = ROOT / "Docs/Doyah产品开发计划书.md"
TRACE = ROOT / "Docs/Doyah产品需求规格说明书-追溯表.md"
STATUS = ROOT / "Docs/平台实现状态.json"
# 2026-10-20：真值源搬迁前的落点（SRS §10.1 索引 / §10.2 追溯表）；现在 SRS 里已无这两节，
# 只用于报错时点名「它搬去哪了」。
LEGACY_SRS = ROOT / "Docs/Doyah产品需求规格说明书.md"
OUT = ROOT / "Docs/平台对齐-Studio-Windows对macOS.md"

TARGET_PLATFORM = "windows"
ALLOWED_STATUS = ("✅", "🟡", "⬜")
ID_RE = re.compile(r"^[A-Z]{2,4}(?:-[A-Z0-9]+){2,5}-\d{2,3}$")   # 5 段两级编号（`FR-RTR-MKT-FEED-001`）必须整串认
RANGE_RE = re.compile(r"^(?P<prefix>[A-Z]{2,4}(?:-[A-Z0-9]+)+)-(?P<low>\d{2,3})\s*~\s*(?P<high>\d{2,3})$")
FULL_RANGE_RE = re.compile(r"^(?P<left>[A-Z]{2,4}(?:-[A-Z0-9]+)+-\d{2,3})\s*~\s*(?P<right>[A-Z]{2,4}(?:-[A-Z0-9]+)+-\d{2,3})$")
SPAN_RE = re.compile(r"`([^`]*)`")
COMMENT_RE = re.compile(r"<!--.*?-->", re.S)
SEPARATOR_RE = re.compile(r"^[:\-\s|]+$")


class SourceError(Exception):
    """真值源不合口径（一次把问题列全，不只报第一个）。"""

    def __init__(self, problems: list[str]) -> None:
        super().__init__("；".join(problems))
        self.problems = problems


def split_row(line: str) -> list[str] | None:
    """把表格行切成格 —— **尊重转义竖线**（`\\|` 是格内字面量，不是列分隔符）。"""
    text = line.strip()
    if not text.startswith("|"):
        return None
    text = text[1:]
    if text.endswith("|"):
        text = text[:-1]
    cells: list[str] = []
    current: list[str] = []
    index = 0
    while index < len(text):
        character = text[index]
        if character == "\\" and index + 1 < len(text) and text[index + 1] == "|":
            current.append("|")
            index += 2
            continue
        if character == "|":
            cells.append("".join(current).strip())
            current = []
            index += 1
            continue
        current.append(character)
        index += 1
    cells.append("".join(current).strip())
    return cells


def first_table(lines: list[str], required: tuple[str, ...], columns: int) -> list[list[str]]:
    """取**第一张**列数匹配、且表头含 `required` 全部分词的表的表体（表头与分隔行丢掉）。

    不给小节标题当锚：真值源搬迁后标题一改，脚本就静默读 0 行 —— 那是「空跑」伪装成「通过」。
    改为「表头必须出现这几个词」，读不到就由调用方判红。
    """
    for index, line in enumerate(lines):
        header = split_row(line)
        if header is None or len(header) != columns:
            continue
        if not all(word in "".join(header) for word in required):
            continue
        body: list[list[str]] = []
        cursor = index + 1
        while cursor < len(lines):
            cells = split_row(lines[cursor])
            if cells is None:
                break
            cursor += 1
            if len(cells) != columns or SEPARATOR_RE.match("".join(cells)):
                continue
            body.append(cells)
        return body
    return []


def status_token(cell: str) -> str:
    """取状态格的**首个取值**（`✅ 89/89（2026…）` → `✅`；`⬜（待落地）` → `⬜`）。"""
    text = COMMENT_RE.sub("", cell).strip()
    return text[:1] if text else ""


def read_lines(path: pathlib.Path, label: str) -> list[str]:
    if not path.exists():
        raise SourceError([f"{path} 不在盘（{label}）"])
    return path.read_text(encoding="utf-8").splitlines()


def load_status() -> dict[str, str]:
    """《开发计划书》§3 需求状态台账 → {编号: 状态}（macOS 基线的唯一来源）。"""
    lines = read_lines(PLAN, "计划书：§3 状态台账")
    rows = first_table(lines, ("编号", "状态"), 9)
    problems: list[str] = []
    status: dict[str, str] = {}
    for cells in rows:
        identifier = cells[0].strip("`").strip()
        if not ID_RE.match(identifier):
            continue
        value = status_token(cells[5])
        if value not in ALLOWED_STATUS:
            problems.append(f"计划书 §3 台账 {identifier} 的状态格取值非法（{cells[5]!r}）")
            continue
        status[identifier] = value
    if not status:
        problems.append("计划书 §3 台账一条状态都没读到（锚点或表格形态变了）")
    if problems:
        raise SourceError(problems)
    return status


def load_index(status: dict[str, str]) -> tuple[list[tuple[str, str, str, str]], int, int]:
    """需求索引 → ([(编号, 所属域, 层次, 状态值)], NFR 条数, AC 条数)，保持索引行序。

    **只收 `FR` 类**：平台差异（台账 `overrides` 与平台等价矩阵）的判定面就是功能需求；
    `NFR` / `AC` 不分平台、也不在矩阵里 ⇒ 进本表只会在 Windows 列造出一片「未做」的假读数。
    两者的条数如实印在产出件头部（不假装它们不存在）。
    """
    lines = read_lines(INDEX, "需求索引：编号 / 所属域 / 层次")
    rows = first_table(lines, ("编号", "所属域", "层次"), 3)
    problems: list[str] = []
    index: list[tuple[str, str, str, str]] = []
    seen: set[str] = set()
    others = {"NFR": 0, "AC": 0}
    for cells in rows:
        identifier = cells[0].strip("`").strip()
        if identifier == "编号" or not ID_RE.match(identifier):
            continue
        if identifier in seen:
            problems.append(f"需求索引里 {identifier} 出现两次（编号必须唯一）")
            continue
        seen.add(identifier)
        if identifier not in status:
            problems.append(f"需求索引有 {identifier}，而计划书 §3 台账没有它的状态（两处必须一一对应）")
            continue
        prefix = identifier.split("-")[0]
        if prefix != "FR":
            others[prefix] = others.get(prefix, 0) + 1
            continue
        index.append((identifier, cells[1], cells[2], status[identifier]))
    if not index:
        problems.append("需求索引一条都没读到（锚点或表格形态变了）")
    extra = sorted(set(status) - seen)
    if extra:
        problems.append(f"计划书 §3 台账有 {len(extra)} 条不在需求索引里（如 {extra[:3]}）")
    if problems:
        raise SourceError(problems)
    return index, others.get("NFR", 0), others.get("AC", 0)


def expand(requirement: str) -> list[str] | None:
    """追溯行 → 编号列表（单条 / 范围两种写法都认；`None` = 这一行不对应单条需求）。

    范围有两种写法（实测都在盘上）：`FR-STD-DB-CONN-001 ~ 007`（右侧只给序号）与
    `NFR-ALL-GATE-RISK-018 ~ NFR-ALL-GATE-RISK-021`（右侧整条写全）。
    """
    if ID_RE.match(requirement):
        return [requirement]
    first = FULL_RANGE_RE.match(requirement)
    if first:
        left, right = first.group("left"), first.group("right")
        if left.rsplit("-", 1)[0] != right.rsplit("-", 1)[0]:
            return None
        requirement = f"{left} ~ {right.rsplit('-', 1)[1]}"
    matched = RANGE_RE.match(requirement)
    if not matched:
        return None
    prefix, low, high = matched.group("prefix"), int(matched.group("low")), int(matched.group("high"))
    width = len(matched.group("low"))
    step = 1 if high >= low else -1
    return [f"{prefix}-{number:0{width}d}" for number in range(low, high + step, step)]


def load_trace(known: set[str]) -> tuple[dict[str, str], int, int]:
    """追溯表 → {编号: 实现位置格}；**后写覆盖先写**。

    返回（映射, 非编号行数, 索引外引用数）——「非编号行」= 分组行 / 决定行（`NFR-PERF / COMP`、
    `NFR-ALL-GATE-RISK-018 ~ NFR-ALL-GATE-RISK-021` 等），它们不对应单条需求 ⇒ 不进逐条索引
    （数量如实印在产出件头部，不假装它们不存在）。
    """
    lines = read_lines(TRACE, "追溯表：实现位置")
    rows = first_table(lines, ("需求", "实现位置"), 3)
    trace: dict[str, str] = {}
    non_identifier = 0
    out_of_index = 0
    problems: list[str] = []
    for cells in rows:
        requirement = cells[0].strip()
        if requirement == "需求":
            continue
        plain_text = requirement.replace("`", "").replace(" ", "")
        identifiers = expand(plain_text)
        if identifiers is None:
            non_identifier += 1
            continue
        for identifier in identifiers:
            if identifier not in known:
                # 追溯表的范围行常比索引宽（`FR-STD-WS-UI-005 ~ 27` 而索引里只到 011），
                # 另有一批编号按 SRS 的分工**不进索引**（数据需求 `FR-STD-ALL-DATA-*` 在 §5、
                # 接口需求 `FR-STD-ALL-IFACE-*` 在 §6）。这些不影响本件（本件只给索引里的条目配落点）
                # ⇒ **如实计数、印在头部**，不编落点、也不当成红。
                out_of_index += 1
                continue
            trace[identifier] = cells[1]
    if problems:
        raise SourceError(problems)
    return trace, non_identifier, out_of_index


def load_platform() -> tuple[str, dict[str, str]]:
    """台账 → (缺省状态, windows 的 overrides)。"""
    if not STATUS.exists():
        raise SourceError([f"{STATUS} 不在盘"])
    payload = json.loads(STATUS.read_text(encoding="utf-8"))
    default = payload.get("default", "⬜")
    platforms = payload.get("platforms", {})
    if TARGET_PLATFORM not in platforms:
        raise SourceError([f"{STATUS} 里没有 `platforms.{TARGET_PLATFORM}`（本件要的那一列没有来源）"])
    entry = platforms[TARGET_PLATFORM]
    problems: list[str] = []
    for key in ("label", "role", "owner"):
        if not str(entry.get(key, "")).strip():
            problems.append(f"台账 `platforms.{TARGET_PLATFORM}.{key}` 为空（列头要写清这列是谁的）")
    overrides = entry.get("overrides", {})
    if not isinstance(overrides, dict):
        problems.append(f"台账 `platforms.{TARGET_PLATFORM}.overrides` 必须是对象")
        overrides = {}
    for identifier, value in overrides.items():
        if not ID_RE.match(identifier):
            problems.append(f"台账 overrides 的编号 {identifier!r} 形状不对")
        if value not in ALLOWED_STATUS:
            problems.append(f"台账 overrides[{identifier}] 取值非法（{value!r}）")
    if problems:
        raise SourceError(problems)
    if default not in ALLOWED_STATUS:
        raise SourceError([f"台账 default 取值非法（{default!r}）"])
    return default, {key: value for key, value in overrides.items()}


def landing(cell: str | None) -> str | None:
    """追溯表的「实现位置」格 → 落点列文本（`None` = 这格没法给落点）。"""
    if cell is None:
        return None
    spans = [span.replace("|", "\\|").strip() for span in SPAN_RE.findall(cell)]
    spans = [span for span in spans if span]
    if not spans:
        return None
    shown = "、".join(f"`{span}`" for span in spans[:3])
    if len(spans) > 3:
        shown += f" 等 {len(spans)} 处"
    return shown


def render(
    index: list[tuple[str, str, str, str]],
    others: tuple[int, int],
    trace: dict[str, str],
    default: str,
    overrides: dict[str, str],
    non_identifier_rows: int,
    out_of_index: int,
) -> str:
    rows: list[tuple[str, str, str, str, str, str]] = []
    for identifier, domain, layer, macos in index:
        cell = trace.get(identifier)
        if cell is None:
            target = "—"
        else:
            target = landing(cell) or "（追溯表有行、未标路径）"
        rows.append((identifier, domain, layer, macos, target, overrides.get(identifier, default)))

    with_target = sum(1 for row in rows if not row[4].startswith("—") and "未标路径" not in row[4])
    without_target = sum(1 for row in rows if "未标路径" in row[4])
    without_row = sum(1 for row in rows if row[4] == "—")
    explicit = f"{len(overrides)} 条" if overrides else "0 条"

    out: list[str] = []
    out.append("# Doyah Studio · Windows 对 macOS 对齐件")
    out.append("")
    out.append(
        "> **本件身份：派生视图（非契约）** —— 真值源 = `Docs/Doyah产品需求规格说明书-需求索引.md`（编号 / 域 / 层次）"
        "+ 《开发计划书》§3（macOS 状态）+ `Docs/Doyah产品需求规格说明书-追溯表.md`（落点）"
        "+ `Docs/平台实现状态.json`（其他平台状态）。"
    )
    out.append(
        "> **两处不一致时以三书为准**。**不要手工编辑本表** —— 改了必漂移：本件由 "
        "`Scripts/gen-studio-win-align.py` 产出，`--check` 在闭环第 7 项判漂移。"
    )
    out.append(">")
    out.append(
        "> **用途**：`babyhippo`（Windows / Harmony 侧）对齐 macOS 版 Doyah Studio 开发进度时的**逐条索引** —— "
        "每行 = 一条需求 → 所属域 → 层次 → macOS 状态 → **macOS 落点（去这里读实现）** → Windows 现状。"
    )
    out.append(">")
    out.append(
        f"> **统计**：需求 **{len(rows)}** 条 · 有落点 **{with_target}** 条 · 追溯表有行未标路径 "
        f"**{without_target}** 条 · 无追溯行（落点列 `—`）**{without_row}** 条 · 台账 Windows "
        f"`overrides` **{explicit}**（缺失一律按 `{default}` 记 —— 整列 `{default}` = Windows Studio 未开工）。"
    )
    out.append(
        f"> 本表只列 **`FR` 类**（{len(rows)} 条 = 平台差异的判定面）；需求索引里另有 **NFR {others[0]}** 条 / "
        f"**AC {others[1]}** 条不进本表 —— 它们不分平台，也不在平台等价矩阵里，进表只会在 `Windows` 列造出一片假 `⬜`。"
    )
    out.append(
        f"> 追溯表里另有 **{non_identifier_rows}** 行不是需求编号（分组行 / 决定行，如 `NFR-PERF / COMP`），"
        f"以及 **{out_of_index}** 行指向索引外的编号（范围行外沿 / 按 SRS 分工不进索引的 `FR-STD-ALL-DATA-*`"
        "（§5）与 `FR-STD-ALL-IFACE-*`（§6））—— 都不对应本索引里的单条需求 ⇒ 不进本表、不编落点。"
    )
    out.append(">")
    out.append(
        "> **口径**：`macOS` 列 = 计划书 §3 台账状态格的**第一个取值**；`macOS 落点` = 追溯表该条所在行的"
        "**反引号片段**（前 3 个 + 「等 N 处」；同一编号出现在多行时取**最后一行**；范围行展开到每一条）。"
        "**无追溯行写 `—`、有行未标路径写「（追溯表有行、未标路径）」—— 两种都不编落点**。"
    )
    out.append(
        "> `Windows` 列 = 台账**原值**（不带矩阵里的 ⚠️ 差异标记：等价判定在矩阵，本件只给落点索引）。"
    )
    out.append(">")
    out.append(
        "> **与派单仓一次性快照的差异（1 行，如实登记）**：`DoyahDispatch` 的 "
        "`docs/平台对齐-Studio-Windows对macOS.md`（2026-10-14 前门一次性快照）把 `FR-STD-ALL-PLUG-004` 记成 `—` —— "
        "该条的追溯格内有**转义竖线**（`CLI/main.swift`（`notes path\\|legacy-path\\|migrate`）），"
        "快照按裸 `|` 切格 ⇒ 整行错位、落点读不出来。本脚本按字面处理转义竖线 ⇒ 该条落点读得出来，"
        "故两处数目不同（快照 173 / 17 / **72**，本件 "
        f"{with_target} / {without_target} / **{without_row}**；合计均 {len(rows)}）。**以本件为准**（它可复跑）。"
    )
    out.append("")
    out.append("| 编号 | 域 | 类别 | macOS | macOS 落点 | Windows |")
    out.append("|---|---|---|---|---|---|")
    for identifier, domain, layer, macos, target, windows in rows:
        out.append(f"| {identifier} | {domain} | {layer} | {macos} | {target} | {windows} |")
    out.append("")
    return "\n".join(out)


def main() -> int:
    arguments = [argument for argument in sys.argv[1:] if argument != "--check"]
    if arguments:
        print(f"❌ 不认的参数：{' '.join(arguments)}（只支持 --check）")
        return 2
    try:
        status = load_status()
        index, nfr_rows, ac_rows = load_index(status)
        trace, non_identifier_rows, out_of_index = load_trace({row[0] for row in index})
        default, overrides = load_platform()
    except SourceError as error:
        print(f"❌ 真值源不合口径（{len(error.problems)} 处）：")
        for problem in error.problems:
            print(f"   · {problem}")
        return 1
    updated = render(index, (nfr_rows, ac_rows), trace, default, overrides,
                     non_identifier_rows, out_of_index)

    if "--check" in sys.argv[1:]:
        current = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
        if current == updated:
            print(f"✅ Windows 对齐件与现状一致（{len(index)} 条需求；落点 {OUT.relative_to(ROOT)}）")
            return 0
        print("❌ Windows 对齐件与现状不一致（真值源改了而产出件没重跑）：")
        old = current.splitlines()
        new = updated.splitlines()
        shown = 0
        for number in range(max(len(old), len(new))):
            left = old[number] if number < len(old) else "（缺）"
            right = new[number] if number < len(new) else "（多余）"
            if left != right:
                print(f"   :{number + 1}  现状：{left[:110]}")
                print(f"   :{number + 1}  应为：{right[:110]}")
                shown += 1
                if shown >= 3:
                    break
        print("   请运行 python3 Scripts/gen-studio-win-align.py 重写")
        return 1

    OUT.write_text(updated, encoding="utf-8")
    print(f"✅ 已重写 {OUT.relative_to(ROOT)}（{len(index)} 条需求；{OUT.name}）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
