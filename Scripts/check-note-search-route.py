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

**⑤「结果落地只有一个出口」（队列 `L-89` ㈡ 第 8 条 · 键盘快打竞态，2026-09-29 第 102 轮加）**：
「迟到的查询结果不许覆盖新的」这件事，从前写成了 `searchNotes()` 里 `do` / `catch` **各一句**
（同一个口径抄两遍，改一处漏一处），而且「判断到底在不在」**没有任何东西看得见**。
现在它只有一个出口（`AppState.settleNoteSearch(_:for:)`），于是可以机械判：
  ① 出口在（名字取自台账）、**词比对那一句在出口里**（删掉它 = 迟到结果会覆盖新的，当场报红）；
  ② 两处**落地形状**（`noteSearchState = .library(` / `.unavailable(`）在 `AppState.swift` 里
     各只出现一次，且都在那个出口体内（多一处 = 又开了一个绕开判断的入口）；
  ③ `searchNotes()` 里不许有落地形状，且两条分支（成功 / 失败）都必须经出口；
  ④ 查库那一步（`runSearch`）**不许读搜索框** —— 一次检索属于哪个词由调用方给（词是参数），
     半路上搜索框变成别的词也改不了这一次的归属，于是「迟到」只可能发生在落地那一刻。

**⑥ 判定物与判定面（合册 `T-20261013-027` · 原单 `T-20261010-056` · 样本 60 收口）**：
- **判定物 = 代码**（`code_only` = 先按**等长空格**掩注释、再抹字符串内容）：注释里提过的符号不算调用、
  字符串里的字面量也不算；等长替换 ⇒ 点名的 `文件:行号` 不漂（早先 `re.sub` 删注释，行号会漂）。
- **「词是参数」与界面属性机械对账**：`runSearch()` 不许读**本类的任何属性** —— 属性集合**现读**
  `App/AppState.swift`（类体一层声明）；不再写死 `notesQuery`，改名 / 新增属性都逃不掉。
- **路线枚举认逗号列表**：`case a, b` 里的**每一个**名字都要登记（早先只取第一个 ⇒ 无声加入）。
- **语言表认多行条目**：真仓那 29 条多行条目进面（早先只认单行 ⇒ 既假绿又假红）。
- **面按 `Package.swift` 生产 target 现读**（`path:` / `sources:`），生产目录数有**下限**
  （`PRODUCTION_FACE_FLOOR`）；登记的面外根（`FACE_OUTSIDE_ROOTS`，逐条带理由）也进面 ⇒
  面外回流判红、死登记判红。已知边界：**未登记的根不扫**（新开一块带 `.swift` 的地皮须登记）。

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

ROUTES_FILE = "Plugins/Notes/Sources/NoteStorage/NoteDatabase.swift"
DISCLOSURE_FILE = "Plugins/Notes/Sources/NoteStorage/NoteSearchDisclosure.swift"
LOCALIZATION_FILE = "Core/Localization.swift"
UI_STATE_FILE = "App/AppState.swift"
VIEWS_DIR = "App/Views"
# 扫描面（2026-10-13 · 概设 §7 P3 搬家）：笔记视图搬进插件目录后仍编进宿主模块。
VIEWS_DIRS = (VIEWS_DIR, "Plugins/Notes/Views")
TESTS_DIR = "Tests"
APP_DIR = "App"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def parse_enum_cases(text: str, enum_name: str) -> list[str]:
    """取 `enum <name> … { case a; case b }` 里的 case 名（按出现顺序）。

    **判定物改判「整条 case 行」（样本 60 ㈠）**：早先 `\\bcase\\s+([A-Za-z]\\w*)` 只取 `case`
    后**第一个**名字 ⇒ `case a, b` 这种逗号列表里的新路线从不被审（而门禁自称「每一个 case
    都要登记」）。这里取 `case` 到行尾（先剥注释），按逗号切；只收合法标识符，
    `case .foo:`（映射表的 case 标签，不是枚举声明）跳过。关联值 `case a(Int)` 只取名字。
    """
    match = re.search(rf"enum\s+{re.escape(enum_name)}\b[^{{]*\{{(.*?)\n\s*\}}", text, re.S)
    if not match:
        return []
    body = strip_comments(match.group(1))
    names: list[str] = []
    for line in body.splitlines():
        found = re.match(r"\s*case\s+(.*)$", line)
        if not found:
            continue
        for piece in found.group(1).split(","):
            piece = piece.strip()
            if not piece or piece.startswith("."):
                continue
            name = re.match(r"[A-Za-z][A-Za-z0-9]*", piece)
            if name and name.group(0) not in names:
                names.append(name.group(0))
    return names


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
    """`LocalizedStrings.table` 里每个键 → {语言: 文案}（**单行与多行条目都收**）。

    判据（样本 60 ㈤）：早先整行正则只认单行条目 ⇒ 真仓 **29 条多行条目**从不出现在
    `table` 里（假绿），而把一个受检键改成多行写法反而**假红**（报「缺中文」）。
    这里按 `[ … ]` 配平取块（字符串里的 `]` 不参与配平），块内再抽 `.语言: "…"`。
    """
    result: dict[str, dict[str, str]] = {}
    lines = text.splitlines()
    index = 0
    while index < len(lines):
        head = re.match(r"\s*\.([A-Za-z][A-Za-z0-9_]*)\s*:\s*\[", lines[index])
        if not head:
            index += 1
            continue
        key = head.group(1)
        column_start = head.end()  # 已经吃掉了键头那个 `[` ⇒ 配平从 1 起算
        depth = 1
        in_string = False
        escaped = False
        row = index
        closed = False
        while row < len(lines):
            chunk = lines[row][column_start:] if row == index else lines[row]
            for ch in chunk:
                if escaped:
                    escaped = False
                    continue
                if in_string:
                    if ch == "\\":
                        escaped = True
                    elif ch == '"':
                        in_string = False
                    continue
                if ch == '"':
                    in_string = True
                elif ch == "[":
                    depth += 1
                elif ch == "]":
                    depth -= 1
                    if depth == 0:
                        closed = True
                        break
            if closed:
                break
            row += 1
        if not closed:
            index += 1
            continue
        block = "\n".join(lines[index : row + 1])
        languages: dict[str, str] = {}
        for language in ("simplifiedChinese", "english"):
            found = re.search(rf"\.{language}:\s*\"((?:[^\"\\\\]|\\\\.)*)\"", block)
            if found:
                languages[language] = found.group(1)
        if languages:
            result[key] = languages
        index = row + 1
    return result


def count_occurrences(text: str, snippet: str) -> int:
    """数一个片段在**代码**里出现几次（注释先掩掉 —— 注释里提到某个符号不算调用）。"""
    return code_only(text).count(snippet)


def strip_comments(text: str) -> str:
    """把注释按**等长空格**掩掉（`//` 行注释 + 可嵌套的 `/* … */` 块注释）。

    两处失真一次收掉（样本 60 ㈢）：① 早先只认 `//` ⇒ **块注释**里的符号算调用；
    ② 早先 `re.sub` 把注释**删掉** ⇒ 行号与列位一起漂（判据要点名 `文件:行号`）。
    逐字符扫：`//` 与 `/*` 出现在**字符串字面量**里不算注释（`"https://…"` 天天有）。
    已知边界（写明白，不是漏判）：Swift 三引号多行字符串按逐行配对处理。
    """
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch == '"':
            i += 1
            while i < n and text[i] != '"':
                if text[i] == "\\":
                    i += 1
                i += 1
            i += 1
            continue
        if ch == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                out[i] = " "
                i += 1
            continue
        if ch == "/" and i + 1 < n and text[i + 1] == "*":
            depth = 0
            while i < n:
                if text[i] == "/" and i + 1 < n and text[i + 1] == "*":
                    depth += 1
                    out[i] = out[i + 1] = " "
                    i += 2
                    continue
                if text[i] == "*" and i + 1 < n and text[i + 1] == "/":
                    depth -= 1
                    out[i] = out[i + 1] = " "
                    i += 2
                    if depth == 0:
                        break
                    continue
                if text[i] != "\n":
                    out[i] = " "
                i += 1
            continue
        i += 1
    return "".join(out)


def blank_strings(text: str) -> str:
    """把字符串字面量的**内容**抹成空格（引号与位置都留着）——「字符串里提过某个符号」不是调用。"""
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        if text[i] == '"':
            i += 1
            while i < n and text[i] != '"':
                if text[i] == "\\":
                    if i + 1 < n:
                        out[i] = out[i + 1] = " "
                    i += 2
                    continue
                if text[i] != "\n":
                    out[i] = " "
                i += 1
            i += 1
            continue
        i += 1
    return "".join(out)


def code_only(text: str) -> str:
    """判定物 = **代码**（注释与字符串内容都不算）—— 这一族缺口（样本 55/56/58/59/60）的共同修法。"""
    return blank_strings(strip_comments(text))


def function_body(text: str, name: str) -> str | None:
    """取 `func <name>…` 的函数体（按花括号配平，含最外层那对）。

    为什么不用正则：`func` 后面可能跟泛型 / 默认值 / `async throws`，而体内又有嵌套闭包 ——
    配平比正则稳。已知局限：字符串字面量里的花括号会被当成真括号（本文件找的两个函数体内
    没有这种字面量；真出现了会当场判红而不是静默通过）。
    """
    if not name:
        return None
    match = re.search(rf"func\s+{re.escape(name)}\s*[(<]", text)
    if not match:
        return None
    start = text.find("{", match.end())
    if start < 0:
        return None
    depth = 0
    for index in range(start, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[start : index + 1]
    return None


# 生产面（样本 60 ㈥）：`Package.swift` 现读到的生产目录数**不得低于此数** —— 一行改动
# （删个 target / 换个 `path:`）就能把面缩小，报个数让「缩面」当场显形。当日实测 = 7 个
# （Core / Plugins/Notes/Sources / Platform/macOS / CLI / Tools/LicenseTool / App /
# Plugins/Notes/Views）；真实减面（合并 target）须同步这一处常数。
PRODUCTION_FACE_FLOOR = 7

# 登记的面外根（含 `.swift` 但不是生产 target 源码目录）：逐条给理由。登记根不存在 /
# 理由为空 / 其实是生产目录 ⇒ 判红（死登记不许留）。列在这里的根**也进判定面**。
FACE_OUTSIDE_ROOTS = {
    "Tests": "测试面（`testTarget path: \"Tests\"`）—— 内存检索的语义由它钉住（台账 allowedCallers）",
    "Vendor": "vendored C/SQLite 面（`Vendor/sqlite3/Package.swift`）—— 不是本仓生产 Swift",
}


def package_production_dirs(root: Path) -> list[str]:
    """**现读** `Package.swift`：生产 target（`.target(` / `.executableTarget(`）的源码目录。

    判据（样本 60 ㈥）：早先面写死 `APP_DIR = "App"` ⇒ 第二条检索路放进 `Platform/macOS`
    也 rc=0（包内五个生产 target 只覆盖一个）。这里现读：`path:` 给目录，`path: "."` +
    `sources:` 给目录清单（本仓 = `["App", "Plugins/Notes/Views"]`）。`.testTarget(` /
    `.plugin(` 不算生产面（测试面另按台账 `allowedCallers` 判）。
    """
    manifest = root / "Package.swift"
    if not manifest.exists():
        return []
    text = strip_comments(read(manifest))
    dirs: set[str] = set()
    for block in re.findall(r"\.(?:executableTarget|target)\s*\((.*?)\n\s*\)\s*,", text, re.S):
        path = re.search(r'path:\s*"([^"]*)"', block)
        sources = re.search(r"sources:\s*\[([^\]]*)\]", block)
        clean_path = path.group(1) if path else "."
        if sources:
            roots = re.findall(r'"([^"]+)"', sources.group(1))
            dirs.update(roots if clean_path == "." else [clean_path])
        elif clean_path != ".":
            dirs.add(clean_path)
    return sorted(d for d in dirs if d and d != ".")


def face_roots(production: list[str]) -> list[tuple[str, str]]:
    """判定面 = 生产面（现读 `Package.swift`）+ 登记的面外根（逐条带理由）。"""
    return [(base, "生产面") for base in production] + [
        (base, "登记的面外根") for base in sorted(FACE_OUTSIDE_ROOTS)
    ]


SWIFT_KEYWORDS = {
    "do", "let", "var", "try", "await", "async", "throws", "throw", "if", "else", "guard",
    "for", "in", "case", "switch", "return", "self", "Self", "nil", "true", "false", "func",
    "catch", "where", "as", "is", "while", "break", "continue", "defer", "some", "any",
    "static", "private", "public", "internal", "fileprivate", "final", "class", "struct",
    "enum", "extension", "init", "deinit", "subscript", "set", "get", "operator", "typealias",
    "import", "override", "mutating", "nonmutating", "lazy", "weak", "unowned", "repeat",
    "default", "fallthrough", "associativity", "precedencegroup", "convenience", "required",
}


def app_state_property_names(text: str) -> set[str]:
    """`AppState` 里声明的**类属性**名（现读）。

    判据（样本 60 ㈡）：早先写死字面 `notesQuery` ⇒ 属性改名（`notesSearchText`）当场失明。
    这里不挑「搜索框是哪个名字」（那还要写死一个问题），改成现读本类属性集合：
    **查库那一步不许读本类的任何属性**（一次检索属于哪个词只能由参数给）。
    只收**类体一层**的声明（缩进恰 4 空格）—— 函数体里的局部量缩进更深，不算属性面。
    """
    names: set[str] = set()
    pattern = re.compile(
        r"^ {4}(?:@Published[^\n]*?[\s(])?(?:private\s+)?(?:\(set\)\s+)?(?:var|let)\s+([A-Za-z_][A-Za-z0-9_]*)"
    )
    for line in text.splitlines():
        found = pattern.match(line)
        if found:
            names.add(found.group(1))
    return names


def function_params(text: str, name: str) -> set[str]:
    """函数签名里的参数名（`func f(_ trimmed: String, for query: String)` → {trimmed, query}）。"""
    match = re.search(rf"func\s+{re.escape(name)}\s*\(([^)]*)\)", text)
    if not match:
        return set()
    return {piece for piece in re.findall(r"([A-Za-z_][A-Za-z0-9_]*)\s*:", match.group(1))}


def referenced_property_names(body: str, properties: set[str], params: set[str]) -> list[str]:
    """函数体里读到的**本类属性**（参数 / 体内局部量 / 关键字 / 被调用的名字都不算）。"""
    allowed = set(params) | set(SWIFT_KEYWORDS)
    allowed |= set(re.findall(r"\b(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)", body))
    found: list[str] = []
    for match in re.finditer(r"(?<![.\w])([A-Za-z_][A-Za-z0-9_]*)", body):
        name = match.group(1)
        if name in allowed or name in found:
            continue
        if body[match.end() : match.end() + 1] == "(":  # 被调用的名字（`String(describing:)`）不是属性读
            continue
        if name in properties:
            found.append(name)
    return found


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

    # ① 唯一生产点（面按 `Package.swift` 生产 target 现读对账 —— 样本 60 ㈥）
    call_site = ledger.get("uiCallSite") or {}
    snippet = call_site.get("snippet") or ""
    production = package_production_dirs(root)
    if len(production) < PRODUCTION_FACE_FLOOR:
        problems.append(
            f"生产面只有 {len(production)} 个目录（下限 {PRODUCTION_FACE_FLOOR}）—— "
            "面被缩小了或 `Package.swift` 读不出来（判据面不许一行改动就变窄）"
        )
    for base in production:
        if not (root / base).is_dir():
            problems.append(f"生产目录不存在：{base}（判据取不到输入，空跑不许通过）")
    if not snippet:
        problems.append("台账 `uiCallSite.snippet` 为空（判据没得查）")
    else:
        declared_file = call_site.get("file", UI_STATE_FILE)
        inside_face = any(
            declared_file == base or declared_file.startswith(base + "/") for base in production
        )
        if not inside_face:
            problems.append(
                f"台账登记的生产点 `{declared_file}` 不在生产面内（面 = {'、'.join(production)}）"
            )
        allowed = int(call_site.get("maxSites", 1))
        inside = count_occurrences(read(root / declared_file), snippet) if (root / declared_file).exists() else 0
        if inside != allowed:
            problems.append(
                f"{declared_file}：界面检索生产点 `{snippet}` 命中 {inside} 处，"
                f"台账登记 {allowed} 处 —— 0 处说明悄悄退回内存过滤，多出来说明出现了第二条检索路"
            )
        else:
            notes.append(f"界面检索生产点：{inside} 处（{declared_file}）")
        # 生产面里除了声明的那一份，别处（含面外登记根）都不许再开一条路
        elsewhere: list[str] = []
        for base, kind in face_roots(production):
            for path in sorted((root / base).rglob("*.swift")):
                relative = (path.relative_to(root)).as_posix()
                if relative == declared_file:
                    continue
                hits = count_occurrences(read(path), snippet)
                if hits:
                    elsewhere.append(f"{relative}（{hits} 处 · {kind}）")
        if elsewhere:
            problems.append(
                f"生产面（{'、'.join(production)}）里另有界面检索路：{'、'.join(elsewhere)} —— "
                "口径要重新登记（唯一生产点是刻意的）"
            )
        notes.append(f"生产面（现读 `Package.swift`）：{len(production)} 个目录 = {'、'.join(production)}")

    # ② 视图不许自己过滤（判定物 = **代码**：注释与字符串字面量都不算 —— 样本 60 ㈢）
    forbidden = ledger.get("viewForbidden") or {}
    pattern = forbidden.get("snippet") or ""
    if not pattern:
        problems.append("台账 `viewForbidden.snippet` 为空（判据没得查）")
    else:
        # 扫描面含插件目录（2026-10-13 · 概设 §7 P3 搬家）：笔记那三个视图物理上搬进
        # `Plugins/Notes/Views/`（仍编进宿主模块）—— 只扫 `App/Views` 会让本条**零覆盖而全绿**。
        views = sorted(p for base in VIEWS_DIRS for p in (root / base).rglob("*.swift"))
        if not views:
            problems.append(f"{'、'.join(VIEWS_DIRS)} 下一个源文件都没有 —— 判据取不到输入（空跑不许通过）")
        hits = 0
        for path in views:
            for number, line in enumerate(code_only(read(path)).splitlines(), start=1):
                if pattern in line:
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

    disclosure_code = code_only(read(root / DISCLOSURE_FILE))
    ui_code = code_only(read(root / UI_STATE_FILE))
    for key, why in keys:
        if key not in lkey_cases:
            problems.append(f"{why}：`LKey` 里没有 `case {key}`")
            continue
        languages = table.get(key) or {}
        for language in ("simplifiedChinese", "english"):
            if not languages.get(language):
                problems.append(f"{why}：语言表里 `{key}` 缺 {language}（中英都要在）")
        # 生产点引用：交代键由映射引用、失败那句由界面引用
        referenced = f".{key}" in disclosure_code or f".{key}" in ui_code
        if not referenced:
            problems.append(f"{why}：`{key}` 在 `NoteSearchDisclosure` 与 `App/` 里都没有调用点 —— 死键")
        notes.append(f"文案键 `{key}`：{why}")

    # ⑤ 结果落地只有一个出口（队列 L-89 ㈡ 第 8 条）：判断在位 / 落地只此一处 / 两条分支都走它 /
    #    查库那一步不读搜索框。
    landing = ledger.get("searchLanding") or {}
    if not landing:
        problems.append("台账 `searchLanding` 缺了一节（结果落地的唯一出口没人管）")
    else:
        ui_source = code_only(read(root / UI_STATE_FILE))
        exit_body = function_body(ui_source, landing.get("exit", ""))
        if exit_body is None:
            problems.append(
                f"{UI_STATE_FILE}：找不到落地出口 `{landing.get('exit')}` —— 0 处说明这条口径没有出口，"
                "多出来一处说明落地又散开了"
            )
        else:
            guard_snippet = landing.get("guard") or ""
            if not guard_snippet:
                problems.append("台账 `searchLanding.guard` 为空（判据没得查）")
            elif guard_snippet not in exit_body:
                problems.append(
                    f"{UI_STATE_FILE}：落地出口里没有 `{guard_snippet}` —— "
                    "判断不在，迟到的结果会覆盖新的（这就是「键盘快打」那一行要防的事）"
                )
            else:
                notes.append(f"落地出口里的词比对在位：`{guard_snippet}`")
            shapes: list[str] = []
            for snippet in landing.get("assignments") or []:
                if not snippet:
                    problems.append("台账 `searchLanding.assignments` 里有空条目（判据没得查）")
                    continue
                total = count_occurrences(ui_source, snippet)
                inside = exit_body.count(snippet)
                shapes.append(f"{snippet}×{total}")
                if total == 0:
                    problems.append(
                        f"{UI_STATE_FILE}：找不到落地形状 `{snippet}` —— 记法变了要同步台账"
                    )
                elif total != inside:
                    problems.append(
                        f"{UI_STATE_FILE}：落地形状 `{snippet}` 命中 {total} 处、其中 {inside} 处在出口体内 —— "
                        "多出来的那些绕开了判断（迟到的结果可以从那里落地）"
                    )
            if shapes:
                notes.append("落地形状：" + " / ".join(shapes))
            caller = landing.get("caller") or ""
            holder = function_body(ui_source, caller)
            if not caller or holder is None:
                problems.append(f"{UI_STATE_FILE}：找不到调用方 `{caller}`（空跑不许通过）")
            else:
                for name in landing.get("branches") or []:
                    if name not in holder:
                        problems.append(
                            f"{UI_STATE_FILE}：`{caller}()` 里没有 `{name}` —— "
                            "有一条分支绕过了唯一出口"
                        )
                for snippet in landing.get("assignments") or []:
                    if snippet in holder:
                        problems.append(
                            f"{UI_STATE_FILE}：`{caller}()` 里自己做了落地（`{snippet}`）—— "
                            "判断与落地必须都只在出口那一个地方"
                        )
            searcher = landing.get("searcher") or ""
            search_body = function_body(ui_source, searcher)
            if not searcher or search_body is None:
                problems.append(f"{UI_STATE_FILE}：找不到查库那一步 `{searcher}`（空跑不许通过）")
            else:
                # 「词是参数」的判定物（样本 60 ㈡）：**不许读本类的任何属性** —— 属性集合
                # 现读 `AppState.swift`（不写死 `notesQuery`，改名 / 新增属性都逃不掉）。
                properties = app_state_property_names(read(root / UI_STATE_FILE))
                if not properties:
                    problems.append(
                        f"{UI_STATE_FILE}：解析不到任何类属性声明 —— 判据取不到输入（空跑不许通过）"
                    )
                else:
                    read_properties = referenced_property_names(
                        search_body, properties, function_params(ui_source, searcher)
                    )
                    if read_properties:
                        problems.append(
                            f"{UI_STATE_FILE}：`{searcher}()` 读了本类属性 {'、'.join(read_properties)}"
                            " —— 一次检索属于哪个词必须由调用方给定（词是参数），"
                            "否则「这一次是哪个词的」在落地时就没法判"
                        )
                    else:
                        notes.append(f"查库那一步 `{searcher}()` 不读搜索框（词是参数）")

            entry = landing.get("entry") or ""
            entry_body = function_body(ui_source, entry)
            if not entry or entry_body is None:
                problems.append(f"{UI_STATE_FILE}：找不到入口 `{entry}`（空跑不许通过）")
            elif f"{searcher}(" not in entry_body:
                problems.append(
                    f"{UI_STATE_FILE}：`{entry}()` 没有走查库那一步（`{searcher}`）—— 生产路径断了"
                )
            else:
                notes.append(f"入口 `{entry}()` → 查库 `{searcher}()` → 出口 `{landing.get('exit')}()` 接通")

    # 内存检索的去向（L-44 的另一半）：面 = 生产面（现读 `Package.swift`）+ 登记的面外根
    legacy = ledger.get("inMemoryMatcher") or {}
    symbol = legacy.get("symbol") or ""
    if not symbol:
        problems.append("台账 `inMemoryMatcher.symbol` 为空（内存检索的去向没人管）")
    else:
        for base in sorted(FACE_OUTSIDE_ROOTS):
            if not (root / base).is_dir():
                problems.append(f"登记的面外根不存在：{base} —— 死登记，请删掉或改名")
            elif base in production:
                problems.append(f"登记的面外根 {base} 其实是生产目录 —— 登记与 `Package.swift` 打架")
        allowed_callers = [caller.rstrip("/") for caller in (legacy.get("allowedCallers") or [])]
        stray: list[str] = []
        for base, kind in face_roots(production):
            for path in sorted((root / base).rglob("*.swift")):
                relative = (path.relative_to(root)).as_posix()
                if any(relative == caller or relative.startswith(caller + "/") for caller in allowed_callers):
                    continue
                hits = count_occurrences(read(path), symbol)
                if hits:
                    stray.append(f"{relative}（{hits} 处 · {kind}）")
        if stray:
            problems.append(
                f"`{symbol}` 在台账允许的面外长出调用：{'、'.join(stray)} —— 界面又回到内存过滤了"
            )
        allowed_hits = sum(
            count_occurrences(read(path), symbol)
            for caller in allowed_callers
            for path in sorted((root / caller).rglob("*.swift"))
            if (root / caller).is_dir()
        )
        if not allowed_hits:
            problems.append(
                f"`{symbol}` 在台账允许的 {'、'.join(allowed_callers)} 里一处调用都没有 —— "
                "语义没人钉住（判据空转）"
            )
        if allowed_hits and not stray:
            notes.append(
                f"内存检索 `{symbol}`：允许面（{'、'.join(allowed_callers)}）{allowed_hits} 处、"
                "别处 0 处（只作参考实现留档）"
            )

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
                  "路线逐条有交代 / 文案键在位 / 结果落地只有一个出口）")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
