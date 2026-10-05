#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""语言表占位符 ↔ 调用点实参的对账门禁（队列 L-46）。

## 它挡的是什么

第 16 轮读图抓到 `待审批（(null)）`：语言表的模板写 `%@`（对象），而调用点传的是
`Int`（`mcpPendingApprovals.count`）—— `String(format:)` 对非对象参数给的就是字面量
`(null)`。**编译过、单测绿、三门禁全过**，只有像素上看得见（与第 12/15 项那两次
「假绿」同一族：没人比较**模板**与**实参**）。

本脚本把这一族变成机械判据。它读两样东西：

* **模板侧**：`platform/macos/Core/Localization.swift` 的 `LocalizedStrings.table`（每个键的中英模板
  → printf 转换符序列）；
* **调用点侧**：`platform/macos/App/` `platform/macos/CLI/` `platform/macos/Core/` 里 `L(.key, 实参…)` 的调用点（配平括号取实参、
  按深度切逗号 —— 实参本身可能含逗号，例：`ErrorPresenter.message(for: error)`）。

## 四条判据

* **A（数字 ⇒ `%@`）** 实参是数字、而该位置的模板转换符是 `%@` ⇒ **红**。
  数字的判定是**保守白名单**（见 `NUMBER_PATTERNS`）：字面整数 / `Int(…)` 之类转换 /
  `.count` · `.rowCount` · `.pageCount` · `.exitCode` · `.next()` / `x ?? 0` /
  `index + 1` / `.timeIntervalSince(` / `.utf8.count`。
  台账里把某个**形状**登记成 `kind=number` 时，该形状也算数字（同一判据的第二半）。
* **A′（文字 ⇒ 数字槽）** 实参是字符串字面量（含插值）、或台账把它的形状登记成
  `kind=text`、而模板在该位置的转换符是 `%d` / `%i` / `%f` ⇒ **红**。
* **B（个数对账）** 实参数 ≠ 该位置模板的占位符数（中英**任一**侧）⇒ **红**。
  第 37 轮就是靠这一条抓到真缺陷：`platform/macos/App/Views/AboutLicenseSheet.swift` 三处
  `L(.licAboutEdition)` 不传实参，而模板是 `当前版本：%@` —— 界面上原样印出
  `%@`（`LocalizationManager.text` 在 `arguments.isEmpty` 时**原样返回模板**）。
* **C / D（类型不明的实参：形状台账 + 棘轮）** 判定不出类型（裸标识符、
  `ErrorPresenter.message(for: error)` 这类调用）的实参**不是白名单放行**：
  ① 它的**形状**必须在 `Scripts/format-argument-dispositions.json` 的 `shapes` 里
  逐条登记（带 `kind` 与理由），未登记 ⇒ **红**（逐条点名 `文件:行号`）；
  ② 每个形状的命中处数不得超登记的 `maxSites`（**棘轮**：只许不增），
  全局未登记总量不得超 `unknownBudget`。
  撤销（命中变少）不判红，只打 `ℹ️` 提示 —— 减少是好事，但不许静默改台账。
* **E（台账不许陈旧）** `exceptions` 里每一条都必须仍对应一处**真存在的**违规，
  `shapes` 里每个形状都必须仍被真实命中 ⇒ 否则**红**（否则台账会变成一份
  「永远绿」的历史垃圾）。**空跑也不许通过**：调用点数为 0、或语言表一个带占位符的
  键都没有 ⇒ **红**（判据取不到输入 = 假绿，本仓库踩过两次）。

## 已知局限（照实写在这里，别让下一个人以为它比实际更严）

* 只查 `L(...)`（App 层用户可见文案的唯一出口）。Core 里 `LocalizedStrings.text(_:language:)`
  不带实参、`String(format:)` 的直调不在本判据内。
* `platform/macos/Tests/` `platform/macos/TestsUISnapshot/` 不在扫描范围：那里有意构造反例（直接调 `String(format:)`）。
* 判定不出类型的实参只被「形状登记 + 棘轮」钉住 —— 形状的 `kind` 写错
  （把真会收 `Int` 的东西登记成 `text`）本门禁**看不见**，这正是 `reason`
  字段要写清「凭哪一行源码判的」的原因。
* 注释按字符掩掉（`//` 与 `/* */`），字符串字面量里的内容不动。

## 用法

    python3 Scripts/check-format-arguments.py            # 判红出口码（闭环第 3 项）
    python3 Scripts/check-format-arguments.py --report   # 人读清单（含形状直方图）
    python3 Scripts/check-format-arguments.py --self-test # 门禁自己的证据（9 例）

`--self-test` 的夹具一律写在**临时目录**的合成小仓里（不碰真仓库），末例核对
真仓库三份文件逐字节未变。
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_DEFAULT = HERE.parent

LEDGER_REL = "Scripts/format-argument-dispositions.json"
SCAN_DIRS = ("platform/macos/App", "platform/macos/CLI", "platform/macos/Core")
TABLE_REL = "platform/macos/Core/Localization.swift"

# printf 转换符：可选 位置参数 / 标志 / 宽度 / 精度 / 长度修饰，最后是转换符本身。
SPEC_RE = re.compile(
    r"%(?:(\d+)\$)?[-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|h|ll|l|q|L|z|j|t)?"
    r"([@diouxXfFeEgGscpn%])"
)

# 数字实参的保守白名单（宁可漏、不可错报：错报会让门禁被绕过）。
NUMBER_PATTERNS = [
    re.compile(r"^-?\d+(?:\.\d+)?$"),
    re.compile(r"^\(-?\d+\)$"),
    re.compile(
        r"^(?:Int|Int32|Int64|UInt|UInt8|UInt16|UInt32|UInt64|Double|Float|CGFloat)\("
    ),
    re.compile(
        r"\.(?:count|rowCount|pageCount|columnCount|statementCount|exitCode|batchCount)\s*$"
    ),
    re.compile(r"\.next\(\)\s*$"),
    re.compile(r"\?\?\s*-?\d+(?:\.\d+)?$"),
    re.compile(r"[+\-]\s*\d+\s*\)?$"),
    re.compile(r"\.timeIntervalSince\("),
    re.compile(r"\.utf8\.count\s*$"),
]

NUMERIC_CONVERSIONS = frozenset("diouxXfFeEgG")


# ── 解析小工具 ────────────────────────────────────────────────────────────────


def mask_comments(src: str) -> str:
    """把注释字符换成空格（等长），字符串字面量内容不动。"""
    out = list(src)
    i, n, in_string = 0, len(src), False
    while i < n:
        ch = src[i]
        if in_string:
            if ch == "\\":
                i += 2
                continue
            if ch == '"':
                in_string = False
            i += 1
            continue
        if ch == '"':
            in_string = True
            i += 1
            continue
        if ch == "/" and i + 1 < n and src[i + 1] == "/":
            j = src.find("\n", i)
            j = n if j == -1 else j
            for k in range(i, j):
                out[k] = " "
            i = j
            continue
        if ch == "/" and i + 1 < n and src[i + 1] == "*":
            j = src.find("*/", i + 2)
            j = n if j == -1 else j + 2
            for k in range(i, j):
                if out[k] != "\n":
                    out[k] = " "
            i = j
            continue
        i += 1
    return "".join(out)


def match_bracket(text: str, index: int, open_ch: str = "[", close_ch: str = "]") -> int:
    """`text[index]` 必须是 open_ch，返回配平的 close_ch 下标。"""
    assert text[index] == open_ch, f"期望 {open_ch}，实际 {text[index]!r}"
    depth, i, in_string, n = 0, index, False, len(text)
    while i < n:
        ch = text[i]
        if in_string:
            if ch == "\\":
                i += 2
                continue
            if ch == '"':
                in_string = False
            i += 1
            continue
        if ch == '"':
            in_string = True
        elif ch == open_ch:
            depth += 1
        elif ch == close_ch:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ValueError("括号未配平")


def read_string_literal(text: str, index: int) -> tuple[str, int]:
    """`text[index]` 必须是 `"`；返回（原始字面量含引号, 结束下标+1），支持 `"a" + "b"` 拼接。"""
    parts = []
    i = index
    while True:
        assert text[i] == '"', f"期望字符串字面量，实际 {text[i]!r}"
        j, buf, esc = i + 1, [], False
        while j < len(text):
            ch = text[j]
            if esc:
                buf.append(ch)
                esc = False
            elif ch == "\\":
                buf.append(ch)
                esc = True
            elif ch == '"':
                break
            else:
                buf.append(ch)
            j += 1
        parts.append("".join(buf))
        k = j + 1
        while k < len(text) and text[k] in " \n\t":
            k += 1
        if k < len(text) and text[k] == "+":
            k += 1
            while k < len(text) and text[k] in " \n\t":
                k += 1
            i = k
            continue
        return "".join(parts), j + 1


def specifiers(template: str) -> list[str]:
    """模板里的转换符序列（`%%` 不算实参位）。"""
    return [c for c in (m.group(2) for m in SPEC_RE.finditer(template)) if c != "%"]


# ── 模板侧 ───────────────────────────────────────────────────────────────────


def parse_language_table(root: Path) -> dict[str, dict[str, str]]:
    src = (root / TABLE_REL).read_text(encoding="utf-8")
    anchor = src.find("static let table: [LKey: [AppLanguage: String]]")
    if anchor < 0:
        raise ValueError(f"{TABLE_REL} 里找不到 `static let table: [LKey: [AppLanguage: String]]`")
    start = src.index("= [", anchor) + 2
    body = src[start + 1 : match_bracket(src, start)]
    masked = mask_comments(body)
    table: dict[str, dict[str, str]] = {}
    for m in re.finditer(r"\.(\w+)\s*:\s*\[", masked):
        key = m.group(1)
        inner_start = m.end() - 1
        inner = body[inner_start + 1 : match_bracket(body, inner_start)]
        entry: dict[str, str] = {}
        for lang in ("simplifiedChinese", "english"):
            lm = re.search(rf"\.{lang}\s*:\s*", inner)
            if not lm:
                continue
            lit_start = inner.index('"', lm.end())
            entry[lang], _ = read_string_literal(inner, lit_start)
        if entry:
            table[key] = entry
    return table


# ── 调用点侧 ─────────────────────────────────────────────────────────────────


def split_top_level(text: str) -> list[str]:
    out, cur, depth, in_string, esc = [], [], 0, False, False
    for ch in text:
        if esc:
            cur.append(ch)
            esc = False
            continue
        if ch == "\\":
            cur.append(ch)
            esc = True
            continue
        if ch == '"':
            in_string = not in_string
            cur.append(ch)
            continue
        if not in_string:
            if ch in "([{":
                depth += 1
            elif ch in ")]}":
                depth -= 1
            elif ch == "," and depth == 0:
                out.append("".join(cur).strip())
                cur = []
                continue
        cur.append(ch)
    if "".join(cur).strip():
        out.append("".join(cur).strip())
    return out


CALL_RE = re.compile(r"\bL\(\s*\.(\w+)\s*([,)])")


def parse_call_sites(root: Path) -> list[dict]:
    sites: list[dict] = []
    for sub in SCAN_DIRS:
        directory = root / sub
        if not directory.is_dir():
            continue
        for path in sorted(directory.rglob("*.swift")):
            raw = path.read_text(encoding="utf-8")
            masked = mask_comments(raw)
            for m in CALL_RE.finditer(masked):
                open_index = masked.index("(", m.start())
                close_index = match_bracket(masked, open_index, "(", ")")
                parts = split_top_level(raw[open_index + 1 : close_index])
                args = [
                    re.sub(r"^await\s+", "", part).strip()
                    for part in parts[1:]
                    if re.sub(r"^await\s+", "", part).strip()
                ]
                sites.append(
                    {
                        "file": path.relative_to(root).as_posix(),
                        "line": raw[: m.start()].count("\n") + 1,
                        "key": m.group(1),
                        "args": args,
                    }
                )
    return sites


# ── 实参判定 ─────────────────────────────────────────────────────────────────

# Foundation / 标准库里「一定是什么」的成员与构造器（写死在这里，理由就是它自己的声明）。
FOUNDATION_MEMBER_KINDS = {
    "localizedDescription": "text",
    "lastPathComponent": "text",
    "path": "text",
    "identifier": "text",
    "uuidString": "text",
    "absoluteString": "text",
    "debugDescription": "text",
}
FOUNDATION_FUNCTION_KINDS = {
    "String": "text",
    "Substring": "text",
    "Character": "text",
    "L": "text",
    "min": "number",
    "max": "number",
    "abs": "number",
}

TYPE_TEXT_RE = re.compile(
    r"^(?:String|Substring|NSString|Character|UUID|URL|Date)\b"
)
TYPE_NUMBER_RE = re.compile(
    r"^(?:Int|Int8|Int16|Int32|Int64|UInt|UInt8|UInt16|UInt32|UInt64"
    r"|Double|Float|CGFloat|TimeInterval)\b"
)


def kind_of_type(type_text: str) -> str:
    t = type_text.strip()
    if TYPE_TEXT_RE.match(t):
        return "text"
    if TYPE_NUMBER_RE.match(t):
        return "number"
    return "unknown"


def pick_kind(kinds: set[str]) -> str:
    """声明冲突时保守返回 unknown（宁可登记，不可错报）。"""
    decisive = {k for k in kinds if k in ("text", "number")}
    return decisive.pop() if len(decisive) == 1 else "unknown"


class Resolver:
    """从仓库自己的声明里解析实参类型：函数返回类型 + `let/var` 与形参的标注类型。

    只认**显式标注**（`-> String` / `: Int`）；解析不出的一律回 `unknown`
    交给台账逐条登记 —— 本层的作用是把「有出处可查的」从「类型不明」里摘出去，
    不是给整张表开一条放行通道。
    """

    def __init__(self, root: Path) -> None:
        self.functions: dict[str, set[str]] = {}
        self.members: dict[str, set[str]] = {}

        for sub in SCAN_DIRS:
            directory = root / sub
            if not directory.is_dir():
                continue
            for path in sorted(directory.rglob("*.swift")):
                src = mask_comments(path.read_text(encoding="utf-8"))
                for m in re.finditer(r"\bfunc\s+(\w+)", src):
                    open_index = src.find("(", m.end())
                    if open_index < 0:
                        continue
                    try:
                        close_index = match_bracket(src, open_index, "(", ")")
                    except ValueError:
                        continue
                    tail = src[close_index + 1 : close_index + 200]
                    rm = re.match(r"\s*(?:async\s+)?(?:throws\s+)?->\s*([^\{;\n]+)", tail)
                    if rm:
                        self.functions.setdefault(m.group(1), set()).add(
                            kind_of_type(rm.group(1))
                        )
                # 只收**全局成员**（`.x` 形态，且要求全仓只有一种决定性的标注类型）。
                # **裸标识符不解析** —— 第 37 轮实测过它的害处：`platform/macos/App/AppState.swift` 里
                # `let duration = String(format: "%.3f", …)`（String）与别处某个
                # `let duration: TimeInterval` 同名，文件级索引会把前者判成数字，
                # 于是 `stateFinished*` 三处**假报红**。裸标识符一律走台账逐条登记
                # （`reason` 里写清「凭哪一行判的」）—— 宁可多登记，不可错报。
                for m in re.finditer(r"\b(?:let|var)\s+(\w+)\s*:\s*([^=\n,)\]\{]+)", src):
                    self.members.setdefault(m.group(1), set()).add(
                        kind_of_type(m.group(2))
                    )

    def resolve(self, text: str, file: str) -> str:  # noqa: ARG002（file 为将来按文件收窄留的位）
        call = re.match(r"^([A-Za-z_][\w.]*)\s*\(", text)
        if call:
            head = call.group(1).split(".")[-1]
            if head in FOUNDATION_FUNCTION_KINDS:
                return FOUNDATION_FUNCTION_KINDS[head]
            return pick_kind(self.functions.get(head, set()))
        if re.match(r"^[\w.?]+$", text) and "." in text:
            member = text.rstrip("?").split(".")[-1]
            if member in FOUNDATION_MEMBER_KINDS:
                return FOUNDATION_MEMBER_KINDS[member]
            return pick_kind(self.members.get(member, set()))
        return "unknown"  # 裸标识符 / 复杂表达式：类型不明 ⇒ 台账登记


def classify(arg: str, resolver: Resolver | None = None, file: str = "") -> str:
    text = arg.strip()
    if text.startswith('"'):
        return "text"
    for pattern in NUMBER_PATTERNS:
        if pattern.search(text):
            return "number"
    if resolver is not None:
        resolved = resolver.resolve(text, file)
        if resolved != "unknown":
            return resolved
    return "unknown"


def shape_of(arg: str) -> str:
    text = re.sub(r"^await\s+", "", arg).strip()
    call = re.match(r"^([A-Za-z_][\w.]*)\s*\(", text)
    if call:
        return f"{call.group(1)}(…)"
    if re.match(r"^[\w.]+$", text):
        return f".{text.split('.')[-1]}" if "." in text else f"<{text}>"
    if text.startswith("(") or text.startswith("[") or text.startswith("{"):
        return text.split("(")[0][:24] or "?"
    return re.sub(r"\s+", " ", text)[:32]


# ── 判定 ─────────────────────────────────────────────────────────────────────


def load_ledger(root: Path) -> dict:
    path = root / LEDGER_REL
    if not path.exists():
        raise ValueError(f"台账缺失：{LEDGER_REL}")
    return json.loads(path.read_text(encoding="utf-8"))


def evaluate(root: Path) -> dict:
    table = parse_language_table(root)
    sites = parse_call_sites(root)
    ledger = load_ledger(root)
    resolver = Resolver(root)

    spec_keys = {k: {lang: specifiers(t) for lang, t in v.items()} for k, v in table.items()}
    spec_keys = {k: v for k, v in spec_keys.items() if any(v.values())}

    shapes = {s["shape"]: s for s in ledger.get("shapes", [])}
    exceptions = {
        (e["judgement"], e["key"], e["site"]): e for e in ledger.get("exceptions", [])
    }

    errors: list[str] = []
    notes: list[str] = []
    hits: dict[str, int] = {name: 0 for name in shapes}
    seen_exceptions: set[tuple[str, str, str]] = set()
    unknown_total = 0
    checked = 0
    shape_counter: dict[str, int] = {}
    per_judgement: dict[str, list[str]] = {"A": [], "A′": [], "B": []}

    if not sites:
        errors.append(f"❌ 一个 `L(...)` 调用点都没扫到（扫描目录 {list(SCAN_DIRS)}）—— 空跑不是通过")
    if not spec_keys:
        errors.append("❌ 语言表里一个带占位符的键都没解析到 —— 判据取不到输入（不是通过）")

    def flagged(judgement: str, key: str, file: str, line: int, message: str) -> None:
        site = f"{file}:{line}"
        token = (judgement, key, site)
        seen_exceptions.add(token)
        per_judgement[judgement].append(f"{site}  L(.{key})  {message}")
        if token not in exceptions:
            errors.append(f"❌ [{judgement}] {site}  L(.{key})  {message}")

    for site in sites:
        key = site["key"]
        if key not in spec_keys:
            continue
        checked += 1
        file, line, args = site["file"], site["line"], site["args"]
        kinds = []
        for arg in args:
            kind = classify(arg, resolver, file)
            if kind == "unknown":
                shape = shape_of(arg)
                shape_counter[shape] = shape_counter.get(shape, 0) + 1
                unknown_total += 1
                entry = shapes.get(shape)
                if entry is None:
                    errors.append(
                        f"❌ [C] {file}:{line}  L(.{key})  未登记的类型不明实参 "
                        f"「{arg}」⇒ 形状 `{shape}` 不在 {LEDGER_REL} 的 shapes 里"
                    )
                    kinds.append("unknown")
                    continue
                hits[shape] += 1
                kind = entry["kind"]
                if kind not in ("text", "number", "unverified"):
                    errors.append(f"❌ [E] 台账形状 `{shape}` 的 kind 非法：{kind!r}")
                    kind = "unknown"
                elif kind == "unverified":
                    # 已登记但**无机械依据**：不参与槽位交叉检查（判据 A/A′ 只认
                    # 有出处的 kind），只被形状与处数棘轮钉住。台账 reason 里写清是哪种。
                    kind = "unknown"
            kinds.append(kind)

        for language, specs in spec_keys[key].items():
            if len(args) != len(specs):
                flagged(
                    "B",
                    key,
                    file,
                    line,
                    f"实参 {len(args)} 个，而 {language} 模板有 {len(specs)} 个占位符"
                    f"（{specs}）—— 界面会印出字面量 `%@` 之类的模板原文",
                )
        for index, kind in enumerate(kinds):
            if kind == "unknown":
                continue
            for language, specs in spec_keys[key].items():
                if index >= len(specs):
                    continue
                conv = specs[index]
                if kind == "number" and conv == "@":
                    flagged("A", key, file, line, f"{language} 模板第 {index + 1} 位是 `%@`，实参是数字 ⇒ 界面印 `(null)`")
                if kind == "text" and conv in "diouxXfFeEgG":
                    flagged("A′", key, file, line, f"{language} 模板第 {index + 1} 位是 `%{conv}`，实参是字符串 ⇒ 数字槽收字符串")

    # D：棘轮
    live_shapes = {name for name, count in hits.items() if count}
    for name, entry in shapes.items():
        count = hits.get(name, 0)
        if count > entry.get("maxSites", 0):
            errors.append(
                f"❌ [D] 形状 `{name}` 命中 {count} 处，超登记上限 {entry.get('maxSites')} —— "
                f"新增的类型不明实参必须逐条登记（{LEDGER_REL}）"
            )
        if count < entry.get("maxSites", 0):
            notes.append(
                f"ℹ️ 形状 `{name}` 命中从 {entry.get('maxSites')} 降到 {count}（好事）—— "
                f"请顺手把台账的 maxSites 改成 {count}"
            )
    if unknown_total > ledger.get("unknownBudget", 0):
        errors.append(
            f"❌ [D] 类型不明实参共 {unknown_total} 处，超预算 {ledger.get('unknownBudget')}"
        )
    # E：台账双向对账（例外必须仍对应真违规 / 形状必须仍被命中）
    for token, item in exceptions.items():
        if token not in seen_exceptions:
            errors.append(
                f"❌ [E] 例外陈旧：台账登记了 [{item['judgement']}] {item['site']} L(.{item['key']})，"
                f"但它现在不违规（或调用点已挪走）—— 请更新或删除该条"
            )
    for name in shapes:
        if name not in live_shapes:
            errors.append(f"❌ [E] 形状陈旧：台账登记的形状 `{name}` 现在一处都不命中 —— 请删除")

    return {
        "table_keys": len(table),
        "spec_keys": len(spec_keys),
        "call_sites_with_spec": checked,
        "call_sites_total": len(sites),
        "unknown_total": unknown_total,
        "unknown_budget": ledger.get("unknownBudget", 0),
        "errors": errors,
        "notes": notes,
        "hits": hits,
        "shape_counter": shape_counter,
        "shapes": shapes,
        "per_judgement": per_judgement,
    }


def print_report(result: dict) -> None:
    print("=" * 100)
    print(
        f"语言表键 {result['table_keys']}；带占位符的键 {result['spec_keys']}；"
        f"带占位符键的调用点 {result['call_sites_with_spec']}（总调用点 {result['call_sites_total']}）"
    )
    print(
        f"类型不明实参 {result['unknown_total']} 处（预算 {result['unknown_budget']}）；"
        f"已登记形状 {len(result['shapes'])} 个"
    )
    for judgement, rows in result["per_judgement"].items():
        print(f"判据 {judgement}：{len(rows)} 处")
        for row in rows:
            print("   ", row)
    print("-" * 100)
    print("形状直方图（类型不明的实参按形状聚合；`max` = 台账登记的上限）：")
    for name, count in sorted(result["shape_counter"].items(), key=lambda kv: (-kv[1], kv[0])):
        entry = result["shapes"].get(name, {})
        print(
            f"   {count:>4} / max {entry.get('maxSites', 0):<4} "
            f"kind={entry.get('kind', '未登记'):<8} {name}"
        )
    print("-" * 100)
    for note in result["notes"]:
        print(note)
    for error in result["errors"]:
        print(error)
    print("=" * 100)
    if result["errors"]:
        print(f"❌ 语言表占位符 ↔ 调用点实参对账**未通过**（{len(result['errors'])} 条）")
    else:
        print("✅ 语言表占位符 ↔ 调用点实参对账通过")


# ── 自检夹具 ─────────────────────────────────────────────────────────────────

FIXTURE_TABLE = '''import Foundation

public enum LocalizedStrings {
    static let table: [LKey: [AppLanguage: String]] = [
        .greet: [.simplifiedChinese: "你好 %@，共 %d 条", .english: "Hi %@, %d rows"],
        .rows: [.simplifiedChinese: "共 %d 行", .english: "%d rows"],
        .plain: [.simplifiedChinese: "纯文本", .english: "plain"],
        .label: [.simplifiedChinese: "当前版本：%@", .english: "Current edition: %@"],
    ]
}
'''

FIXTURE_OK = """import Foundation

func render(name: String, count: Int) -> String {
    let a = L(.greet, name, count)
    let b = L(.rows, count)
    let c = L(.plain)
    let d = L(.label)
    let e = items.map { L(.rows, $0) }
    return a + b + c + d
}
"""

FIXTURE_LEDGER = {
    "note": "夹具台账",
    "version": 1,
    "unknownBudget": 4,
    "shapes": [
        {
            "shape": "<name>",
            "kind": "text",
            "maxSites": 1,
            "reason": "夹具：裸标识符 `name`（真仓库同款一律走台账登记）",
        },
        {
            "shape": "<count>",
            "kind": "number",
            "maxSites": 2,
            "reason": "夹具：裸标识符 `count`",
        },
        {
            "shape": "$0",
            "kind": "number",
            "maxSites": 1,
            "reason": "夹具：闭包形参 `$0`",
        },
    ],
    "exceptions": [
        {
            "judgement": "B",
            "key": "label",
            "site": "App/Fixture.swift:7",
            "reason": "夹具：标签与值分开渲染，模板本不该带 %@（真仓库同款见 AboutLicenseSheet）",
        }
    ],
}


def write_fixture_tree(base: Path, fixture_source: str, ledger: dict | None = None) -> Path:
    root = base / "repo"
    (root / "Core").mkdir(parents=True, exist_ok=True)
    (root / "App").mkdir(parents=True, exist_ok=True)
    (root / "Scripts").mkdir(parents=True, exist_ok=True)
    (root / TABLE_REL).write_text(FIXTURE_TABLE, encoding="utf-8")
    (root / "App/Fixture.swift").write_text(fixture_source, encoding="utf-8")
    payload = FIXTURE_LEDGER if ledger is None else ledger
    (root / LEDGER_REL).write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return root


def run_self_test() -> int:
    """每个用例：造合成小仓 → 跑 evaluate → 断言退出码（与报出的原因）。"""
    cases: list[tuple[str, str, dict | None, bool, str]] = [
        ("绿例：合规最小仓", FIXTURE_OK, None, True, ""),
        (
            "A 数字实参落在 %@ 槽",
            FIXTURE_OK.replace("L(.greet, name, count)", "L(.greet, items.count, count)"),
            None,
            False,
            "App/Fixture.swift:4",
        ),
        (
            "A′ 字符串字面量落在 %d 槽",
            FIXTURE_OK.replace("L(.rows, count)", 'L(.rows, "x")'),
            None,
            False,
            "App/Fixture.swift:5",
        ),
        (
            "B 实参数 ≠ 占位符数",
            FIXTURE_OK.replace("L(.plain)", "L(.rows)"),
            None,
            False,
            "App/Fixture.swift:6",
        ),
        (
            "C 未登记的类型不明实参（形状不在台账里）",
            FIXTURE_OK.replace("L(.greet, name, count)", "L(.greet, mystery, count)"),
            None,
            False,
            "未登记的类型不明实参",
        ),
        (
            "D 棘轮：形状命中数超上限",
            FIXTURE_OK + "let f = items.map { L(.rows, $0) }\n",
            None,
            False,
            "超登记上限",
        ),
        (
            "E 例外陈旧（登记的违规已不存在）",
            FIXTURE_OK,
            {
                **FIXTURE_LEDGER,
                "exceptions": [
                    {
                        "judgement": "A",
                        "key": "greet",
                        "site": "App/Fixture.swift:99",
                        "reason": "夹具：故意陈旧",
                    }
                ],
            },
            False,
            "例外陈旧",
        ),
        (
            "空跑不许通过（语言表一个带占位符的键都没有）",
            FIXTURE_OK,
            {
                "note": "夹具台账",
                "version": 1,
                "unknownBudget": 9,
                "shapes": [
                    {"shape": "<name>", "kind": "text", "maxSites": 9, "reason": "夹具"}
                ],
                "exceptions": [],
            },
            False,
            "",
        ),
    ]

    real_files = [REPO_DEFAULT / TABLE_REL, REPO_DEFAULT / "Scripts/verify-all.sh"]
    before = {
        str(p): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in real_files
        if p.exists()
    }

    failures = 0
    tmp = Path(tempfile.mkdtemp(prefix="l46-selftest-"))
    try:
        for index, (title, source, ledger, expect_ok, expect_text) in enumerate(cases, start=1):
            root = write_fixture_tree(tmp / f"case{index}", source, ledger)
            if index == 8:
                # 第 8 例：把语言表里的占位符全删掉 ⇒ 判据取不到输入，必须报红
                (root / TABLE_REL).write_text(
                    FIXTURE_TABLE.replace("%@", "").replace("%d", ""), encoding="utf-8"
                )
            try:
                result = evaluate(root)
                ok = not result["errors"]
                message = " | ".join(result["errors"])
            except Exception as exc:  # noqa: BLE001
                ok, message = False, f"异常：{exc!r}"
            verdict = "✅" if ok == expect_ok else "❌"
            if ok != expect_ok or (expect_text and expect_text not in message):
                verdict = "❌"
            if verdict == "❌":
                failures += 1
            print(f"  {verdict} 例 {index}：{title}（期望 {'通过' if expect_ok else '报红'}，"
                  f"实际 {'通过' if ok else '报红'}）")
            if verdict == "❌":
                print(f"        实际输出：{message[:400]}")
        after = {
            str(p): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in real_files
            if p.exists()
        }
        unchanged = before == after
        print(f"  {'✅' if unchanged else '❌'} 例 9：末例核对真仓库 {len(before)} 份文件逐字节未变")
        if not unchanged:
            failures += 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    total = len(cases) + 1
    if failures:
        print(f"❌ 自检 {total - failures}/{total} 通过")
        return 1
    print(f"✅ 自检 {total}/{total} 全过")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="语言表占位符 ↔ 调用点实参对账门禁（L-46）")
    parser.add_argument("--root", default=str(REPO_DEFAULT))
    parser.add_argument("--report", action="store_true", help="打印全量清单（人读）")
    parser.add_argument("--self-test", action="store_true", help="跑门禁自己的负例集")
    args = parser.parse_args()

    if args.self_test:
        return run_self_test()

    root = Path(args.root).resolve()
    if not (root / TABLE_REL).exists() or not (root / LEDGER_REL).exists():
        print(f"❌ 在 {root} 找不到 {TABLE_REL} 或 {LEDGER_REL}")
        return 2
    try:
        result = evaluate(root)
    except Exception as exc:  # noqa: BLE001
        print(f"❌ 解析失败（不是「通过」）：{exc!r}")
        return 2
    if args.report:
        print_report(result)
    else:
        for error in result["errors"]:
            print(error)
        if result["errors"]:
            print(f"❌ 语言表占位符 ↔ 调用点实参对账未通过（{len(result['errors'])} 条；"
                  f"`--report` 看全量清单）")
            return 1
        print(f"✅ 语言表占位符 ↔ 调用点实参对账通过（带占位符键的调用点 "
              f"{result['call_sites_with_spec']} 处；类型不明实参 {result['unknown_total']} 处"
              f"已在台账逐条登记形状）")
    return 1 if result["errors"] else 0


if __name__ == "__main__":
    sys.exit(main())
