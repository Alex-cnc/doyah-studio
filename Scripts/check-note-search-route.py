#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""门禁：**界面检索走库 + 所走路线如实标注**（队列 L-44，闭环第 10 项）。

**为什么有它**：L-44 之前，界面的笔记检索是**在内存里过滤**已加载的列表
（`AppState.visibleNotes` 直接调 `NoteSearch.match(notes, query:)`）—— 于是「检索走没走库」
这件事**没有任何东西看得见**，而库里那两条路（FTS5/trigram 全文检索、子串兜底）的差别
（「这次是按子串找到的」）也就永远到不了用户眼前，**而代码全绿**。本轮把它改走库之后，
把这四件事变成机械判据：

  ① **唯一生产点**：界面检索只能有一处（`AppState.searchNotes()` 里的
     `NoteLibrary.defaultLibrary().search(`）。0 处 = 悄悄退回内存过滤；多出一处 =
     出现第二条检索路（口径要重新登记）。
  ② **视图不许自己过滤**：`App/Views/` 里出现 `NoteSearch.match(` 即红（点名 文件:行号）——
     「面板各查各的」正是这一族缺陷的复发形状。
  ③ **每条路线都有交代**：`NoteDatabase.SearchResult.Route` 的**每一个** case 都要在台账
     `note-search-route.json` 里登记处置（给文案键，或显式 `nil` 并写明为什么不必说），
     且必须与 `NoteSearchDisclosure.key(for:)` 里的实现**逐条相等** —— 两边不一致即红。
     读不出一条路线 / 台账是空的 ⇒ 红（判据取不到输入 = 假绿，本仓库踩过两次）。
  ④ **文案键真的在语言表里**：登记的键必须①是 `LKey` 的 case、②在 `LocalizedStrings.table`
     里**中英都在且非空**、③真的被生产点引用（死键 = 「交代」只写在文档里）；
     反向：台账里登记的键在语言表里找不到 ⇒ 陈旧报红。

另外把「内存检索」的去向也钉住（L-44 的另一半）：`NoteSearch.match` 不再有界面调用者，
允许的调用者只剩 `Tests/`（语义仍由单测钉着）—— `App/` 里命中即红，`Tests/` 里一处都没有
也报红（那说明判据本身空转了）。

用法：
    python3 Scripts/check-note-search-route.py             # 人读结论，失败非零退出
    python3 Scripts/check-note-search-route.py --json      # 机器读
    python3 Scripts/check-note-search-route.py --root <树>  # 负例验证用（临时副本）
"""

from __future__ import annotations  # macOS 自带 python3 是 3.9，`X | None` 这类注解需要它

import argparse
import json
import re
import sys
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
LEDGER_DEFAULT = "Scripts/note-search-route.json"

ROUTES_FILE = "Core/NoteStorage/NoteDatabase.swift"
DISCLOSURE_FILE = "Core/NoteStorage/NoteSearchDisclosure.swift"
LOCALIZATION_FILE = "Core/Localization.swift"
UI_STATE_FILE = "App/AppState.swift"
VIEWS_DIR = "App/Views"
TESTS_DIR = "Tests"
APP_DIR = "App"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def parse_enum_cases(text: str, enum_name: str) -> list[str]:
    """取 `enum <name> … { case a; case b }` 里的 case 名（按出现顺序）。"""
    match = re.search(rf"enum\s+{re.escape(enum_name)}\b[^{{]*\{{(.*?)\n\s*\}}", text, re.S)
    if not match:
        return []
    body = re.sub(r"//[^\n]*", "", match.group(1))
    return re.findall(r"\bcase\s+([A-Za-z][A-Za-z0-9]*)", body)


def parse_disclosure_map(text: str) -> dict[str, str | None]:
    """`NoteSearchDisclosure.key(for:)` 的路线 → 键映射（`nil` 记成 None）。"""
    match = re.search(r"func\s+key\s*\(for route.*?\n    \}", text, re.S)
    if not match:
        return {}
    body = re.sub(r"//[^\n]*", "", match.group(0))
    result: dict[str, str | None] = {}
    for case, block in re.findall(r"case\s+\.([A-Za-z][A-Za-z0-9]*)\s*:(.*?)(?=case\s+\.|\Z)", body, re.S):
        returned = re.search(r"return\s+(?:\.([A-Za-z][A-Za-z0-9]*)|nil)", block)
        if not returned:
            result[case] = "__missing__"
            continue
        result[case] = returned.group(1)  # None 表示 `return nil`
    return result


def parse_lkey_cases(text: str) -> set[str]:
    return set(parse_enum_cases(text, "LKey"))


def parse_table_keys(text: str) -> dict[str, dict[str, str]]:
    """`LocalizedStrings.table` 里每个键 → {语言: 文案}（只收单行条目）。"""
    result: dict[str, dict[str, str]] = {}
    for line in text.splitlines():
        match = re.match(r"\s*\.([A-Za-z][A-Za-z0-9_]*):\s*\[(.*)\],\s*$", line)
        if not match:
            continue
        key, payload = match.group(1), match.group(2)
        languages: dict[str, str] = {}
        for language in ("simplifiedChinese", "english"):
            found = re.search(rf"\.{language}:\s*\"((?:[^\"\\\\]|\\\\.)*)\"", payload)
            if found:
                languages[language] = found.group(1)
        if languages:
            result[key] = languages
    return result


def count_occurrences(text: str, snippet: str) -> int:
    """数一个片段在**代码**里出现几次（注释先掩掉 —— 注释里提到某个符号不算调用）。"""
    return strip_comments(text).count(snippet)


def strip_comments(text: str) -> str:
    """把 `//` 行注释与 `/* … */` 块注释按字符掩掉（字符串字面量里的 `//` 会被误伤，
    这是已知局限：本门禁找的都是**调用形状**，不会出现在字符串里）。"""
    without_block = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", without_block)


def check(root: Path, ledger_path: Path | None) -> tuple[list[str], list[str]]:
    problems: list[str] = []
    notes: list[str] = []

    ledger_file = ledger_path or (root / LEDGER_DEFAULT)
    if not ledger_file.exists():
        return [f"台账不存在：{ledger_file}"], notes
    ledger = json.loads(read(ledger_file))

    needed = [ROUTES_FILE, DISCLOSURE_FILE, LOCALIZATION_FILE, UI_STATE_FILE]
    missing = [rel for rel in needed if not (root / rel).exists()]
    if missing:
        return [f"判据输入缺失：{'、'.join(missing)}（空跑不许通过）"], notes

    routes = parse_enum_cases(read(root / ROUTES_FILE), "Route")
    if not routes:
        return [f"解析不到 {ROUTES_FILE} 的 `Route` 枚举 —— 判据取不到输入（空跑不许通过）"], notes

    disclosure = parse_disclosure_map(read(root / DISCLOSURE_FILE))
    if not disclosure:
        problems.append(f"解析不到 {DISCLOSURE_FILE} 的 `key(for:)` 映射（空跑不许通过）")

    lkey_cases = parse_lkey_cases(read(root / LOCALIZATION_FILE))
    table = parse_table_keys(read(root / LOCALIZATION_FILE))
    if not lkey_cases or not table:
        problems.append(f"解析不到 {LOCALIZATION_FILE} 的 `LKey` / 语言表 —— 判据取不到输入")

    # ① 唯一生产点
    call_site = ledger.get("uiCallSite") or {}
    snippet = call_site.get("snippet") or ""
    if not snippet:
        problems.append("台账 `uiCallSite.snippet` 为空（判据没得查）")
    else:
        ui_text = read(root / UI_STATE_FILE)
        found = count_occurrences(ui_text, snippet)
        allowed = int(call_site.get("maxSites", 1))
        if found != allowed:
            problems.append(
                f"{call_site.get('file', UI_STATE_FILE)}：界面检索生产点 `{snippet}` 命中 {found} 处，"
                f"台账登记 {allowed} 处 —— 0 处说明悄悄退回内存过滤，多出来说明出现了第二条检索路"
            )
        else:
            notes.append(f"界面检索生产点：{found} 处（{call_site.get('file', UI_STATE_FILE)}）")
        # 生产点只许在声明的那一个文件里（`App/` 其余地方不许再开一条路）
        for path in sorted((root / APP_DIR).rglob("*.swift")):
            if path.name == Path(call_site.get("file", UI_STATE_FILE)).name:
                continue
            hits = count_occurrences(read(path), snippet)
            if hits:
                problems.append(
                    f"{path.relative_to(root)}：App/ 里另有一条界面检索路（`{snippet}` × {hits}）—— "
                    "口径要重新登记（唯一生产点是刻意的）"
                )

    # ② 视图不许自己过滤
    forbidden = ledger.get("viewForbidden") or {}
    pattern = forbidden.get("snippet") or ""
    if not pattern:
        problems.append("台账 `viewForbidden.snippet` 为空（判据没得查）")
    else:
        views = sorted((root / VIEWS_DIR).rglob("*.swift"))
        if not views:
            problems.append(f"{VIEWS_DIR} 下一个源文件都没有 —— 判据取不到输入（空跑不许通过）")
        hits = 0
        for path in views:
            for number, line in enumerate(read(path).splitlines(), start=1):
                if pattern in re.sub(r"//.*$", "", line):
                    hits += 1
                    problems.append(
                        f"{path.relative_to(root)}:{number}：视图里出现内存过滤 `{pattern}` —— "
                        "界面检索必须走库（`NoteLibrary.search`）"
                    )
        if hits == 0:
            notes.append(f"{VIEWS_DIR}：{len(views)} 个源文件里没有内存过滤调用")

    # ③ 路线 ↔ 台账 ↔ 实现 三方一致
    declared = {entry.get("route"): entry for entry in (ledger.get("routes") or []) if entry.get("route")}
    if not declared:
        problems.append("台账 `routes` 是空的 —— 判据没得查（空跑不许通过）")
    for route in routes:
        if route not in declared:
            problems.append(f"路线 `{route}` 没有登记处置（新增一条路线必须逐条写明怎么交代）")
            continue
        if route not in disclosure:
            problems.append(f"路线 `{route}` 在 `NoteSearchDisclosure.key(for:)` 里没有 `case`（穷尽性被破坏？）")
            continue
        wanted = declared[route].get("disclosure")
        actual = disclosure[route]
        if actual == "__missing__":
            problems.append(f"路线 `{route}` 的 `case` 里既没有 `return .键` 也没有 `return nil`")
            continue
        if (wanted or None) != actual:
            problems.append(
                f"路线 `{route}`：台账登记 `{wanted}`，实现返回 `{actual}` —— 两边必须逐条相等"
            )
    for route in declared:
        if route not in routes:
            problems.append(f"台账里的路线 `{route}` 在 `Route` 枚举里已经不存在 —— 陈旧条目，请删掉")

    # ④ 文案键：在 LKey 里、中英都在、真的被生产点引用
    keys: list[tuple[str, str]] = []
    for route, entry in declared.items():
        if entry.get("disclosure"):
            keys.append((entry["disclosure"], f"路线 `{route}` 的交代"))
    failure = ledger.get("failure") or {}
    if not failure.get("key"):
        problems.append("台账 `failure.key` 为空（「检索没跑成」那一句没人管）")
    else:
        keys.append((failure["key"], "检索失败那一句"))

    disclosure_text = read(root / DISCLOSURE_FILE)
    ui_text = read(root / UI_STATE_FILE)
    for key, why in keys:
        if key not in lkey_cases:
            problems.append(f"{why}：`LKey` 里没有 `case {key}`")
            continue
        languages = table.get(key) or {}
        for language in ("simplifiedChinese", "english"):
            if not languages.get(language):
                problems.append(f"{why}：语言表里 `{key}` 缺 {language}（中英都要在）")
        # 生产点引用：交代键由映射引用、失败那句由界面引用
        referenced = f".{key}" in disclosure_text or f".{key}" in ui_text
        if not referenced:
            problems.append(f"{why}：`{key}` 在 `NoteSearchDisclosure` 与 `App/` 里都没有调用点 —— 死键")
        notes.append(f"文案键 `{key}`：{why}")

    # 内存检索的去向（L-44 的另一半）
    legacy = ledger.get("inMemoryMatcher") or {}
    symbol = legacy.get("symbol") or ""
    if not symbol:
        problems.append("台账 `inMemoryMatcher.symbol` 为空（内存检索的去向没人管）")
    else:
        app_hits = sum(count_occurrences(read(p), symbol) for p in (root / APP_DIR).rglob("*.swift"))
        if app_hits:
            problems.append(f"`{symbol}` 在 `App/` 里还有 {app_hits} 处调用 —— 界面又回到内存过滤了")
        test_hits = sum(count_occurrences(read(p), symbol) for p in (root / TESTS_DIR).rglob("*.swift"))
        if not test_hits:
            problems.append(f"`{symbol}` 在 `Tests/` 里一处调用都没有 —— 语义没人钉住（判据空转）")
        if not app_hits and test_hits:
            notes.append(f"内存检索 `{symbol}`：App/ 0 处、Tests/ {test_hits} 处（只作参考实现留档）")

    return problems, notes


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true", help="机器读")
    parser.add_argument("--root", default=str(BASE), help="仓库根（负例验证用）")
    parser.add_argument("--ledger", default=None, help="台账路径（负例验证用）")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    ledger_path = Path(args.ledger).resolve() if args.ledger else None
    problems, notes = check(root, ledger_path)

    if args.json:
        print(json.dumps({"problems": problems, "notes": notes}, ensure_ascii=False, indent=2))
    else:
        for note in notes:
            print(f"  ℹ️ {note}")
        if problems:
            print(f"\n❌ 界面检索口径门禁未通过（{len(problems)} 项）：")
            for problem in problems:
                print(f"   - {problem}")
        else:
            print("\n✅ 界面检索走库 + 路线如实标注：判据全过（唯一生产点 / 视图无内存过滤 / "
                  "路线逐条有交代 / 文案键在位）")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
