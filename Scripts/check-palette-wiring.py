#!/usr/bin/env python3
"""命令面板接线校验（FR-EDIT-25）。

存在的理由：
    2026-09-23 的收尾自查里发现 —— `AppState.performPaletteCommand` 给 10 条命令里的
    **9 条设了 `@Published` 标志位，而没有任何视图读它们**。用户在 ⌘K 里选「会话 / 锁 /
    浏览数据 / 表结构 / 切换连接 / 智能体 / 合成数据 / 帮助」，界面**完全没反应**；
    剩下那条（智能体）是**设错了标志位**（设 `isAgentSQLCommandPresented`，界面绑的是
    `isAgentSQLPresented`）。

    这个缺陷对当时已有的 8 项门禁**全部不可见**：编译过、单测过、文档表格过、令牌过、
    平台矩阵过、打包过 —— 因为"命令清单里有这一条"和"这条命令真的能打开东西"之间
    没有任何检查。于是补上这一项。

检查内容（任一不过即失败）：
    1. 命令清单里的每个 id 都要在分派器里被处理 —— 否则那是一条**点了没反应**的命令；
    2. 分派器里的每个 id 都要在命令清单里 —— 否则是漂移（用户看不到，代码里却还在）；
    3. **分派器函数体里每一处赋值**都要**至少被一处代码行读**（扫描面 = `App/**` + `Plugins/**`
       的 `.swift`，分派器自己那份 `AppState.swift` 不算）—— 判定物是**赋值形状的整个集合**，
       不是 `is*=true` 这一种写法：`case "id": <名> = <值>` 同行赋值 / 名字带数字 /
       非 `is` 前缀的状态（如 `notesSearchScope`）一样要有人读；「读」= **剥掉注释与字符串之后**
       的代码行命中（注释里提一次不算读、字符串里提也不算）。**本项就是上面那个缺陷的判据**；
    4. 每条命令的关键词不得为空（否则面板里搜不到它，等于没有这条命令）；
    5. **落点表 ↔ 命令清单双向对账**：行为面探针 `TestsUISnapshot/PaletteWiringProbeTests.swift`
       的落点表（`private static var wiring`）与 `AppCommandCatalog.all()` 必须互相覆盖 ——
       未登记的差集判红并打出差集本身；差集里**已登记**的缺口（`KNOWN_WIRING_GAPS`）逐条要有
       理由与归属，且**登记一旦陈旧（该 id 已不再缺）就判红**（棘轮：补完落点必须同轮销账）；
    6. **解析不到东西就报错**：正则没匹配到命令 / case / 赋值 / 落点表 ⇒ 失败而不是空转通过
       —— "门禁自己失效"比"门禁发现不了"更危险。

读数（每次必打印）：赋值审计**逐名**列出，`is` 前缀与其它状态**分两栏**各给条数；「读」那一栏
注明按**代码行**判定；落点对账给「探针 N 条 ↔ 清单 M 条 · 未登记差集 K 条 · 已登记缺口 J 条」。

**2026-10-14 改（派单 `T-20261010-044` · 合册 `T-20261013-027` 本册表第 29 行 · 样本 48）**：
旧版两重窄化 —— ① 判定物 = `\\b(is[A-Za-z]+)\\s*=\\s*true\\b` 的**字面形状**：名字带数字 / 非 `is`
前缀的状态**整条不可见**（活体：`notesSearchScope` 两档与 `statusMessage` 两处，门禁照旧打印
「17 个标志位都有视图读」）；② 「读」= **整份文件的全文子串**命中 ⇒ 把真读点换成注释里的同名串
照样判绿。本轮按原单建议 ⓐ 全做（判定物改赋值全集 + 「读」剥注释与字符串 + 落点表对账进每轮 +
补 `--self-test`）。

用法：
    python3 Scripts/check-palette-wiring.py             # 校验（闸门）
    python3 Scripts/check-palette-wiring.py --explain   # 打印解析到的清单 / 赋值审计 / 落点对账
    python3 Scripts/check-palette-wiring.py --self-test # 判据自己的证据：`--self-test` **13 例**
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
STATE_REL = "App/AppState.swift"
CATALOG_REL = "App/AppCommandCatalog.swift"
PROBE_REL = "TestsUISnapshot/PaletteWiringProbeTests.swift"
READ_ROOTS = ("App", "Plugins")  # 「读」的扫描面：插件化（概设 §7 P3）之后笔记视图搬进 Plugins/Notes/Views/
DISPATCHER = "func performPaletteCommand"
WIRING_ANCHOR = "var wiring"

ITEM = re.compile(r'item\(\s*"([^"]+)"\s*,\s*\.(\w+)\s*,\s*"([^"]*)"')
CASE = re.compile(r'case\s+"([^"]+)"\s*:')
WIRING = re.compile(r'\(\s*"([^"]+)"\s*,\s*\.')
# 判定物（判据 3）：分派器函数体里「标识符 = 值」的赋值落点 —— 不限 `is` 前缀、不限名字只许字母、
# 不限 `= true` 这一种值。两种排除：`let` / `var` 绑定的名字不是状态赋值；`==` / `!=` / `+=` 不是赋值。
ASSIGN = re.compile(r"(?<![\w.$])([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?!=)")
BINDING = re.compile(r"(?:\blet|\bvar)\s+$")
KEYWORDS = frozenset({"if", "while", "guard", "case", "return", "for", "else", "where", "default", "func"})

# 下限（空跑防护）：面被掏空 / 条数缩水不许「零命中 = 通过」。数字是**当日实测**（2026-10-14），
# 有意变更须同轮跟版（与 `FACE_FLOOR` / `PROBE_FLOOR` 同口径）。
FLAG_FLOOR = 17         # `is` 前缀档（实测 17）
STATE_FLOOR = 2         # 其它状态档（实测 2：notesSearchScope / statusMessage）
ASSIGN_FLOOR = 21       # 赋值落点合计（实测 21 处 = 17 + 2 + 2）
READ_FILES_FLOOR = 142  # 「读」扫描面文件数（实测：App 118 + Plugins 24；不含 AppState.swift）
CATALOG_FLOOR = 39      # 命令清单条数（实测 39）
PROBE_FLOOR = 33        # 落点表条数（实测 33）

# 已登记的落点缺口：命令清单里有、探针落点表里没有的 id（判据 5 的**已登记**那一半）。
_GAP_IDS = ("newNote", "newNotebook", "noteSearchScopeCurrent", "noteSearchScopeAll", "noteFavorites", "noteAllNotes")
_GAP_REASON = (
    "笔记菜单批（`N-UI-4`）：`AppCommandCatalog.all()` 里有这条，而探针落点表"
    "（`TestsUISnapshot/PaletteWiringProbeTests.swift`）**未登记** ⇒ 该探针 "
    "`testEveryCommandHasARegisteredLanding` 已经是红的，而它要 `DOYAH_UI_SNAPSHOT=1`、按 `L-01` "
    "不进每轮门禁 ⇒ **没有每轮判据看得见**（本判据补的就是这一格）。补落点要改 `TestsUISnapshot/**`"
    "（测试面取舍）⇒ 归前门裁；补完必须同轮销掉本条登记（陈旧登记判红）。"
)
KNOWN_WIRING_GAPS = [{"id": gid, "reason": _GAP_REASON, "owner": "bluewhale（前门）"} for gid in _GAP_IDS]


def strip_comments_and_strings(text: str) -> str:
    """剥掉注释与字符串字面量的**内容**（等长替换，行号与缩进不变）。

    与 `check-core-portability.py` / `check-editor-surface-tokens.py` 同口径：判定物必须是**代码行**，
    注释里提一次名字不算「有人读它」，字符串里提也不算。
    """
    out: list[str] = []
    index = 0
    length = len(text)
    in_string = in_line = in_block = False
    while index < length:
        char = text[index]
        if in_line:
            if char == "\n":
                in_line = False
                out.append(char)
            index += 1
            continue
        if in_block:
            if text.startswith("*/", index):
                in_block = False
                index += 2
                continue
            if char == "\n":
                out.append("\n")
            index += 1
            continue
        if in_string:
            if char == "\\":
                index += 2
                continue
            if char == '"':
                in_string = False
                out.append('"')
            index += 1
            continue
        if text.startswith("//", index):
            in_line = True
            index += 2
            continue
        if text.startswith("/*", index):
            in_block = True
            index += 2
            continue
        if char == '"':
            in_string = True
            out.append('"')
            index += 1
            continue
        out.append(char)
        index += 1
    return "".join(out)


def strip_comments(text: str) -> str:
    """只剥注释、**保留**字符串字面量（解析落点表要读 id 字符串）。"""
    out: list[str] = []
    index = 0
    length = len(text)
    in_string = in_line = in_block = False
    while index < length:
        char = text[index]
        if in_line:
            if char == "\n":
                in_line = False
                out.append(char)
            index += 1
            continue
        if in_block:
            if text.startswith("*/", index):
                in_block = False
                index += 2
                continue
            if char == "\n":
                out.append("\n")
            index += 1
            continue
        if in_string:
            out.append(char)
            if char == "\\":
                if index + 1 < length:
                    out.append(text[index + 1])
                index += 2
                continue
            if char == '"':
                in_string = False
            index += 1
            continue
        if text.startswith("//", index):
            in_line = True
            index += 2
            continue
        if text.startswith("/*", index):
            in_block = True
            index += 2
            continue
        if char == '"':
            in_string = True
        out.append(char)
        index += 1
    return "".join(out)


def read_face(root: pathlib.Path) -> list[tuple[str, str]]:
    """「读」的扫描面：`App/**` + `Plugins/**` 的 `.swift`（分派器自己那份不算），返回 (相对路径, 代码)。"""
    face: list[tuple[str, str]] = []
    for name in READ_ROOTS:
        base = root / name
        if not base.exists():
            continue
        for path in sorted(base.rglob("*.swift")):
            if path.name == "AppState.swift":
                continue
            face.append((path.relative_to(root).as_posix(), strip_comments_and_strings(path.read_text(encoding="utf-8"))))
    return face


def command_ids(catalog_text: str) -> list[tuple[str, str, str]]:
    """命令清单：id / 本地化键 / 关键词。"""
    return [(i, key, words) for i, key, words in ITEM.findall(catalog_text)]


def dispatcher_body(state_text: str) -> str | None:
    """分派器函数体（按花括号配平取边界；解析不到 ⇒ None = 空跑防护）。"""
    if DISPATCHER not in state_text:
        return None
    start = state_text.index(DISPATCHER)
    depth = 0
    began = False
    end = start
    for offset, character in enumerate(state_text[start:], start=start):
        if character == "{":
            depth += 1
            began = True
        elif character == "}":
            depth -= 1
            if began and depth == 0:
                end = offset
                break
    return state_text[start:end]


def dispatcher_assignments(state_text: str) -> tuple[str | None, list[tuple[int, str]]]:
    """分派器函数体里的赋值落点（判定物全集）：[(函数体内行号, 状态名)]。"""
    body = dispatcher_body(state_text)
    if body is None:
        return None, []
    code = strip_comments_and_strings(body)
    sites: list[tuple[int, str]] = []
    for line_number, line in enumerate(code.split("\n"), 1):
        for match in ASSIGN.finditer(line):
            name = match.group(1)
            if name in KEYWORDS or BINDING.search(line[: match.start()]):
                continue
            sites.append((line_number, name))
    return body, sites


def code_reads(name: str, face: list[tuple[str, str]]) -> list[str]:
    """哪些文件**在代码行上**提到了这个名字（剥注释与字符串之后、按词边界 —— 不做子串匹配）。"""
    pattern = re.compile(r"(?<!\w)" + re.escape(name) + r"(?!\w)")
    return [rel for rel, code in face if pattern.search(code)]


def _matching_bracket(text: str, start: int) -> int:
    """从 `text[start] == "["` 起找配对的 `]`（感知字符串字面量），找不到返回 -1。"""
    depth = 0
    in_string = False
    index = start
    while index < len(text):
        char = text[index]
        if in_string:
            if char == "\\":
                index += 2
                continue
            if char == '"':
                in_string = False
            index += 1
            continue
        if char == '"':
            in_string = True
        elif char == "[":
            depth += 1
        elif char == "]":
            depth -= 1
            if depth == 0:
                return index
        index += 1
    return -1


def landing_ids(probe_text: str) -> tuple[list[str], list[str]]:
    """探针落点表的 id 清单 + 形状可疑的条目（第二格不是 `.landing` 的）。"""
    anchor = probe_text.find(WIRING_ANCHOR)
    if anchor < 0:
        return [], []
    # 声明里先有一个**类型标注**的 `[(id: String, landing: Landing)]`（不是数组字面量）
    # ⇒ 定位到「`[` + 换行 + `("id"`」那一处，才是落点表的字面量。
    literal = re.search(r"\[\s*\n\s*\(\s*\"", probe_text[anchor:])
    if literal is None:
        return [], []
    start = anchor + literal.start() + literal.group(0).index("[")
    end = _matching_bracket(probe_text, start)
    if end < 0:
        return [], []
    block = strip_comments(probe_text[start : end + 1])
    ids = WIRING.findall(block)
    named = re.findall(r'\(\s*"([^"]+)"\s*,', block)
    odd = [ident for ident in named if ident not in ids]
    return ids, odd


def run_checks(
    catalog_text: str,
    state_text: str,
    face: list[tuple[str, str]],
    probe_text: str,
) -> tuple[list[str], dict]:
    """全部判据跑一遍（纯函数：只吃文本，不吃磁盘 ⇒ `--self-test` 的夹具全是内存里的深拷贝）。"""
    problems: list[str] = []
    readings: dict = {}

    catalog = command_ids(catalog_text)
    body, sites = dispatcher_assignments(state_text)
    probe_ids, odd_entries = landing_ids(probe_text)
    handled = CASE.findall(strip_comments(body)) if body else []

    # 6) 先保证门禁自己没瞎：解析不到就是结构变了，必须报出来
    if not catalog:
        problems.append(f"{CATALOG_REL}: 解析不到任何命令 —— 清单结构变了，请同步本脚本")
    if body is None:
        problems.append(f"{STATE_REL}: 找不到 `{DISPATCHER}` —— 分派器改名了，请同步本脚本")
    elif not handled:
        problems.append(f"{STATE_REL}: 解析不到分派器里的任何 case —— 结构变了，请同步本脚本")
    if not sites and body is not None:
        problems.append(f"{STATE_REL}: 分派器函数体里解析不到任何赋值 —— 结构变了，请同步本脚本")
    if not probe_ids:
        problems.append(f"{PROBE_REL}: 解析不到落点表（`{WIRING_ANCHOR}`）—— 探针结构变了，请同步本脚本")
    if odd_entries:
        problems.append(f"{PROBE_REL}: 落点表有条目第二格不是 `.landing` 形状：{sorted(set(odd_entries))}")

    catalog_ids = [entry[0] for entry in catalog]
    if len(set(catalog_ids)) != len(catalog_ids):
        duplicated = sorted({i for i in catalog_ids if catalog_ids.count(i) > 1})
        problems.append(f"命令清单有重复 id：{duplicated}")

    # 1) 清单里的每条命令都要真的被处理
    for ident, _, _ in catalog:
        if ident not in handled:
            problems.append(f"命令「{ident}」在清单里，但 performPaletteCommand 没有处理它 —— 点了没反应")

    # 2) 处理了，但用户看不到（漂移）
    for ident in handled:
        if ident not in catalog_ids:
            problems.append(f"performPaletteCommand 处理了「{ident}」，但它不在命令清单里（用户看不到这条命令）")

    # 4) 关键词不得为空
    for ident, _, words in catalog:
        if not words.strip():
            problems.append(f"命令「{ident}」没有关键词 —— 在面板里搜不到它")

    # 3) 赋值审计：函数体里每一处赋值都要有人**在代码行上**读
    names: dict[str, list[str]] = {}
    for _, name in sites:
        names.setdefault(name, code_reads(name, face))
    flags = sorted(name for name in names if name.startswith("is"))
    states = sorted(name for name in names if not name.startswith("is"))
    readings["catalog_count"] = len(catalog)
    readings["handled_count"] = len(handled)
    readings["assign_sites"] = len(sites)
    readings["flag_names"] = flags
    readings["state_names"] = states
    readings["reads"] = names
    readings["face_files"] = len(face)
    for name in sorted(names):
        if not names[name]:
            problems.append(
                f"状态 {name} 在分派器里被赋值，但**没有任何视图在代码行上读它**（注释 / 字符串里提过不算）"
                " —— 这条命令点了没反应"
            )
    for label, group, floor in (("`is` 前缀", flags, FLAG_FLOOR), ("其它状态", states, STATE_FLOOR)):
        if len(group) < floor:
            problems.append(f"赋值审计的{label}档只读到 {len(group)} 个名字（下限 {floor}）—— 面被掏空或解析口径变了")
    if len(sites) < ASSIGN_FLOOR:
        problems.append(f"分派器函数体里的赋值只读到 {len(sites)} 处（下限 {ASSIGN_FLOOR}）—— 面被掏空或解析口径变了")
    if len(face) < READ_FILES_FLOOR:
        problems.append(f"「读」的扫描面只读到 {len(face)} 份 .swift（下限 {READ_FILES_FLOOR}）—— 面被掏空不许当通过")

    # 5) 落点表 ↔ 命令清单双向对账（差集判红、登记缺口要有理由、陈旧登记判红）
    if probe_ids:
        missing = [ident for ident in catalog_ids if ident not in probe_ids]
        extra = [ident for ident in probe_ids if ident not in catalog_ids]
        registered = [entry.get("id") for entry in KNOWN_WIRING_GAPS]
        unregistered = [ident for ident in missing if ident not in registered]
        stale = [ident for ident in registered if ident not in missing]
        readings["probe_count"] = len(probe_ids)
        readings["missing"] = missing
        readings["extra"] = extra
        readings["unregistered"] = unregistered
        readings["stale"] = stale
        for ident in unregistered:
            problems.append(
                f"命令「{ident}」在清单里，但探针落点表（{PROBE_REL}）**未登记**它，也不在 `KNOWN_WIRING_GAPS` 里"
                f" —— 行为面那条对账已经是红的，却没有每轮判据看得见（未登记差集 {len(unregistered)} 条：{unregistered}）"
            )
        for ident in extra:
            problems.append(
                f"探针落点表登记了「{ident}」，但它不在命令清单里（漂移：用户看不到这条命令）"
                f"（反向差集 {len(extra)} 条：{extra}）"
            )
        if len(catalog) < CATALOG_FLOOR:
            problems.append(f"命令清单只读到 {len(catalog)} 条（下限 {CATALOG_FLOOR}）—— 面被掏空不许当通过")
        if len(probe_ids) < PROBE_FLOOR:
            problems.append(
                f"落点表只读到 {len(probe_ids)} 条（下限 {PROBE_FLOOR}）—— 面被掏空不许当通过"
                f"（清单里有而它没有的 id：{missing}）"
            )
        for entry in KNOWN_WIRING_GAPS:
            if not str(entry.get("reason", "")).strip() or not str(entry.get("owner", "")).strip():
                problems.append(f"`KNOWN_WIRING_GAPS` 里 {entry.get('id')} 缺理由或归属 —— 登记必须有出处")
        for ident in stale:
            problems.append(f"`KNOWN_WIRING_GAPS` 里 {ident} 的登记已陈旧（它已经不缺了）—— 请同轮销账")

    return problems, readings


def parse_args(argv: list[str]) -> tuple[str, pathlib.Path]:
    """参数面：未知参数 ⇒ 抛 `ValueError`（`main` 里转成 rc=2）。

    旧版没有参数面：`--nonsense` 被静默吞掉、照旧判绿（「门禁自己失效」那一族）。
    """
    mode = "check"
    root = ROOT
    index = 0
    while index < len(argv):
        argument = argv[index]
        if argument == "--explain":
            mode = "explain"
        elif argument == "--self-test":
            mode = "self-test"
        elif argument == "--root":
            index += 1
            if index >= len(argv):
                raise ValueError("--root 后面缺路径")
            root = pathlib.Path(argv[index])
        else:
            raise ValueError(f"未知参数：{argument}")
        index += 1
    return mode, root


def print_readings(readings: dict) -> None:
    """收尾读数：赋值审计**逐名**列出（`is` 前缀与其它状态分两栏、各给条数）+ 落点对账 + 判定口径。"""
    reads = readings.get("reads", {})
    flags = readings.get("flag_names", [])
    states = readings.get("state_names", [])
    print(
        f"   赋值审计 {readings.get('assign_sites', 0)} 处 / {len(flags) + len(states)} 个名字（判定物 = "
        "分派器 `performPaletteCommand` 函数体里的赋值全集，含 `case \"id\": <名> = <值>` 同行赋值）"
    )
    for label, group, floor in (("`is` 前缀", flags, FLAG_FLOOR), ("其它状态", states, STATE_FLOOR)):
        print(f"   {'├' if label == '`is` 前缀' else '└'} {label} {len(group)} 个（下限 {floor}）")
        for name in group:
            users = reads.get(name) or []
            where = "、".join(users) if users else "**无**"
            print(f"        {name:<32} ← 代码行读点 {len(users)} 份：{where}")
    print(
        f"   「读」按**剥注释与字符串后的代码行**判定（扫描面 = {' + '.join(READ_ROOTS)} 的 .swift "
        f"{readings.get('face_files', 0)} 份，下限 {READ_FILES_FLOOR}；分派器自己那份 AppState.swift 不算）"
    )
    if "probe_count" in readings:
        gaps = "、".join(entry["id"] for entry in KNOWN_WIRING_GAPS)
        print(
            f"   落点表对账：探针 {readings['probe_count']} 条 ↔ 清单 {readings.get('catalog_count', 0)} 条 · "
            f"未登记差集 {len(readings['unregistered'])} 条 · 已登记缺口 {len(KNOWN_WIRING_GAPS)} 条（{gaps} · "
            f"归属 {KNOWN_WIRING_GAPS[0]['owner']}，补完须同轮销账）"
        )


def main(argv: list[str] | None = None) -> int:
    arguments = list(sys.argv[1:] if argv is None else argv)
    try:
        mode, root = parse_args(arguments)
    except ValueError as error:
        print(f"参数错误：{error}")
        print("用法：python3 Scripts/check-palette-wiring.py [--explain | --self-test] [--root <路径>]")
        return 2
    if mode == "self-test":
        return self_test()
    catalog_text = (root / CATALOG_REL).read_text(encoding="utf-8")
    state_text = (root / STATE_REL).read_text(encoding="utf-8")
    probe_path = root / PROBE_REL
    probe_text = probe_path.read_text(encoding="utf-8") if probe_path.exists() else ""
    problems, readings = run_checks(catalog_text, state_text, read_face(root), probe_text)
    if mode == "explain":
        body, _ = dispatcher_assignments(state_text)
        handled = CASE.findall(strip_comments(body)) if body else []
        print(f"\n命令清单 {len(command_ids(catalog_text))} 条 / 分派器处理 {len(handled)} 条")
        for ident, key, words in command_ids(catalog_text):
            mark = "✅" if ident in handled else "❌"
            print(f"  {mark} {ident:<24} {key:<30} {words[:38]}")
    if problems:
        print(f"❌ 命令面板接线校验失败（{len(problems)} 处）：")
        for problem in problems:
            print(f"   {problem}")
        print("\n提示：命令清单只管「列出来」，能不能打开东西由分派器与视图绑定决定 —— 两边都要对。")
        return 1
    print(f"✅ 命令面板接线校验通过（命令清单 {readings.get('catalog_count', 0)} 条全部有处理、关键词无空）")
    print_readings(readings)
    return 0


def _drop_line(text: str, needle: str) -> str:
    return "\n".join(line for line in text.split("\n") if needle not in line)


def _insert_before_line(text: str, needle: str, new_line: str) -> str:
    lines = text.split("\n")
    for index, line in enumerate(lines):
        if needle in line:
            lines.insert(index, new_line)
            return "\n".join(lines)
    return text


def self_test() -> int:
    """判据自己的证据：红 / 绿成对。夹具 = 真仓文本的**深拷贝**，改完只在内存里，真仓逐字节未动。"""
    catalog_text = (ROOT / CATALOG_REL).read_text(encoding="utf-8")
    state_text = (ROOT / STATE_REL).read_text(encoding="utf-8")
    probe_text = (ROOT / PROBE_REL).read_text(encoding="utf-8")
    face = read_face(ROOT)
    expectations: list[tuple[str, bool]] = []

    def expect(name, should_be_red, catalog=None, state=None, faces=None, probe=None):
        problems, _ = run_checks(
            catalog_text if catalog is None else catalog,
            state_text if state is None else state,
            face if faces is None else faces,
            probe_text if probe is None else probe,
        )
        got_red = bool(problems)
        ok = got_red == should_be_red
        detail = "" if not problems else f"（报红：{problems[0][:64]}…）"
        expectations.append((f"{'✓' if ok else '✗'} {name}：{'报红' if got_red else '不报红'}{detail}", ok))

    def with_case(extra: str) -> str:
        """往**分派器函数体**里插一条 case（全仓还有别的 `default:` ⇒ 必须按函数体替换）。"""
        body = dispatcher_body(state_text) or ""
        mutated = body.replace("        default:\n", extra + "        default:\n", 1)
        return state_text.replace(body, mutated, 1)

    def raw(rel: str) -> str:
        return (ROOT / rel).read_text(encoding="utf-8")

    def face_with_raw(rel: str, transform) -> list[tuple[str, str]]:
        return [
            (name, strip_comments_and_strings(transform(raw(rel))) if name == rel else code)
            for name, code in face
        ]

    # ① 真仓（应当绿）
    expect("真仓现状（应当不报红）", False)

    # ② 负例①：真读点换成**注释里的同名串**（旧判定物 = 全文子串 ⇒ 绿；新判定物 = 代码行 ⇒ 红）
    target = "isRoutineCandidatesPresented"
    holder = code_reads(target, face)[0]
    mutated_raw = raw(holder).replace(f"$appState.{target}", f"false  // {target}")
    expect(
        f"真读点换成注释同名串（{holder}，应当报红）",
        True,
        faces=face_with_raw(holder, lambda _text: mutated_raw),
    )
    print(
        f"  对照：该夹具里 `{target}` 仍以**子串**形式留在 {holder}（旧判定物会判绿）"
        "⇒ 一红一绿的差别只在「名字落在注释里还是代码里」。"
    )

    # ③④⑤ 负例②：形状不再决定可见性（三种形状都进判定物、都没有读点 ⇒ 逐名报红）
    # 夹具里同时把这条命令接进清单与落点表 ⇒ **只留「没人读」这一个因**（否则先撞上判据 2 的漂移）。
    def planted(command_id: str, case_line: str, landing: str = ".panel(.shortcutHelp)") -> dict:
        return {
            "state": with_case(case_line),
            "catalog": _insert_before_line(
                catalog_text,
                'item("help", .commandHelp,',
                f'            item("{command_id}", .commandHelp, "probe", "probe", .paletteCategoryHelp),',
            ),
            "probe": _insert_before_line(
                probe_text,
                '("notes", .notesEntry)',
                f'            ("{command_id}", {landing}),',
            ),
        }

    expect(
        "注入 `probeS48State = true`（非 `is` 前缀 · 无读点，应当报红）",
        True,
        **planted("probeS48", '        case "probeS48": probeS48State = true\n'),
    )
    expect(
        "注入 `isProbeS48State = true`（名字带数字 · 无读点，应当报红）",
        True,
        **planted("probeS48", '        case "probeS48": isProbeS48State = true\n'),
    )
    expect(
        '注入同行赋值 `case "probeS48Inline": probeS48InlineState = true`（应当报红）',
        True,
        **planted("probeS48Inline", '        case "probeS48Inline": probeS48InlineState = true\n'),
    )

    # ⑥⑦⑧ 负例③：落点表 ↔ 清单双向对账（删一条 / 加一条 / 登记陈旧）
    expect(
        "落点表删掉 `help` 一条（差集里出现未登记 id，应当报红）",
        True,
        probe=_drop_line(probe_text, '("help", .panel(.shortcutHelp))'),
    )
    # 清单里加一条**分派器已处理**、但落点表没登记的命令 ⇒ 只留「落点对账」这一个因
    expect(
        "命令清单加一条 `plantedCommand`（分派器已处理、落点表未登记，应当报红）",
        True,
        catalog=_insert_before_line(
            catalog_text,
            'item("help", .commandHelp,',
            '            item("plantedCommand", .commandHelp, "planted", "planted", .paletteCategoryHelp),',
        ),
        state=with_case('        case "plantedCommand": formatActiveQuery()\n'),
    )
    expect(
        "把已登记缺口 `newNote` 补进落点表（登记陈旧，应当报红）",
        True,
        probe=_insert_before_line(probe_text, '("notes", .notesEntry)', '            ("newNote", .notesEntry),'),
    )

    # ⑨ 负例④：赋值被掏空（cases 还在）⇒ 空跑防护 / 下限判红
    body = dispatcher_body(state_text) or ""
    expect(
        "分派器函数体里的赋值全删（cases 仍在，应当报红）",
        True,
        state=state_text.replace(body, ASSIGN.sub("", body), 1),
    )

    # ⑩ 负例⑤：清单结构变了 ⇒ 解析不到命令，必须判红（不许空转通过）
    expect("命令清单结构变了（`item(` → `entry(`，应当报红）", True, catalog=catalog_text.replace("item(", "entry("))

    # ⑪ 对手臂 A：某视图文件里只加一句**注释**提一个无关名字 ⇒ 不误报（注释不算读、也不产生条目）
    expect(
        "注释里提一个无关名字（应当不报红）",
        False,
        faces=face_with_raw(holder, lambda text: text + "\n// isTotallyUnrelatedPlantedState 只在注释里提一次\n"),
    )

    # ⑫ 对手臂 B：名字带数字的状态**有**代码行读点 ⇒ 不误报（可见性由「有没有人读」决定，不由名字形状决定）
    arm_b = planted("probeS49", '        case "probeS49": isProbeS49State = true\n')
    arm_b["faces"] = face_with_raw(
        "App/Views/MainWindow.swift",
        lambda text: text + "\nfunc __probeS49() { _ = appState.isProbeS49State }\n",
    )
    expect("名字带数字的状态有代码行读点（应当不报红）", False, **arm_b)

    # ⑬ 参数面：未知参数 ⇒ rc=2（旧版静默吞掉、照旧判绿）
    try:
        parse_args(["--nonsense"])
        parameter_ok = False
    except ValueError:
        parameter_ok = True
    expectations.append((f"{'✓' if parameter_ok else '✗'} 未知参数 `--nonsense` ⇒ rc=2：{'是' if parameter_ok else '否'}", parameter_ok))

    print("判据自己的证据（`--self-test` · 夹具 = 真仓文本的深拷贝，改完只在内存里）")
    for line, _ok in expectations:
        print(f"  {line}")
    passed = sum(1 for _line, ok in expectations if ok)
    print(f"负例自检：{len(expectations)} 条中 {passed} 条达到预期")
    return 0 if passed == len(expectations) else 1


if __name__ == "__main__":
    sys.exit(main())
