#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""语言表占位符 ↔ 调用点实参的对账门禁（队列 L-46）。

## 它挡的是什么

第 16 轮读图抓到 `待审批（(null)）`：语言表的模板写 `%@`（对象），而调用点传的是
`Int`（`mcpPendingApprovals.count`）—— `String(format:)` 对非对象参数给的就是字面量
`(null)`。**编译过、单测绿、三门禁全过**，只有像素上看得见（与第 12/15 项那两次
「假绿」同一族：没人比较**模板**与**实参**）。

本脚本把这一族变成机械判据。它读两样东西：

* **模板侧**：`Core/Localization.swift` 的 `LocalizedStrings.table`（每个键的中英模板
  → printf 转换符序列）；
* **调用点侧**：`App/` `CLI/` `Core/` 里 `L(.key, 实参…)` 的调用点（配平括号取实参、
  按深度切逗号 —— 实参本身可能含逗号，例：`ErrorPresenter.message(for: error)`）。

## 六条判据

* **A（数字 ⇒ `%@`）** 实参是数字、而该位置的模板转换符是 `%@` ⇒ **红**。
  数字的判定是**保守白名单**（见 `NUMBER_PATTERNS`）：字面整数 / `Int(…)` 之类转换 /
  `.count` · `.rowCount` · `.pageCount` · `.exitCode` · `.next()` / `x ?? 0` /
  `index + 1` / `.timeIntervalSince(` / `.utf8.count`。
  台账里把某个**形状**登记成 `kind=number` 时，该形状也算数字（同一判据的第二半）。
* **A′（文字 ⇒ 数字槽）** 实参是字符串字面量（含插值）、或台账把它的形状登记成
  `kind=text`、而模板在该位置的转换符是 `%d` / `%i` / `%f` ⇒ **红**。
* **B（个数对账）** 实参数 ≠ 该位置模板的占位符数（中英**任一**侧）⇒ **红**。
  第 37 轮就是靠这一条抓到真缺陷：`App/Views/AboutLicenseSheet.swift` 三处
  `L(.licAboutEdition)` 不传实参，而模板是 `当前版本：%@` —— 界面上原样印出
  `%@`（`LocalizationManager.text` 在 `arguments.isEmpty` 时**原样返回模板**）。
* **C / D（类型不明的实参：形状台账 + 棘轮）** 判定不出类型（裸标识符、
  `ErrorPresenter.message(for: error)` 这类调用）的实参**不是白名单放行**：
  ① 它的**形状**必须在 `Scripts/format-argument-dispositions.json` 的 `shapes` 里
  逐条登记（带 `kind` 与理由），未登记 ⇒ **红**（逐条点名 `文件:行号`）；
  ② 每个形状的命中处数不得超登记的 `maxSites`（**棘轮**：只许不增），
  全局未登记总量不得超 `unknownBudget`。
  撤销（命中变少）不判红，只打 `ℹ️` 提示 —— 减少是好事，但不许静默改台账。
* **F（扫描面不许写死）** 扫描面由 `Package.swift` 的**生产 target** 声明派生（`path:` /
  `sources:`；测试 target 不进面）—— 生产 target 没声明路径 ⇒ 判红、面里的根盘上不存在 ⇒
  判红、面为空 ⇒ 判红、台账 `faceExempt` 里的根已不是生产 root ⇒ 判红（死豁免）。
  旧实现写死五个目录、与 `Package.swift` 无对账：`Platform/macOS` 与 `Tools/LicenseTool`
  在面外，往里写一处真违规是**静默通过**（成对矩阵 s5/s6）。
* **G（语言列表不许写死、每个键要覆盖全部语言）** 语言列表由 `Core/Localization.swift` 的
  `enum AppLanguage` 派生；某个键少了一种语言（或用了枚举外的语言名）⇒ 判红 ——
  旧实现硬编码两个语言名，加第三语言会**静默漏审**（成对矩阵 s8）。
* **E（台账不许陈旧）** `exceptions` 里每一条都必须仍对应一处**真存在的**违规，
  `shapes` 里每个形状都必须仍被真实命中 ⇒ 否则**红**（否则台账会变成一份
  「永远绿」的历史垃圾）。**空跑也不许通过**：调用点数为 0、或语言表一个带占位符的
  键都没有 ⇒ **红**（判据取不到输入 = 假绿，本仓库踩过两次）。

## 已知局限（照实写在这里，别让下一个人以为它比实际更严）

* 只查 `L(...)`（App 层用户可见文案的唯一出口）。Core 里 `LocalizedStrings.text(_:language:)`
  不带实参、`String(format:)` 的直调不在本判据内。
* `Tests/` `TestsUISnapshot/` 不在扫描范围：那里有意构造反例（直接调 `String(format:)`）。
* 判定不出类型的实参只被「形状登记 + 棘轮」钉住 —— 形状的 `kind` 写错
  （把真会收 `Int` 的东西登记成 `text`）本门禁**看不见**，这正是 `reason`
  字段要写清「凭哪一行源码判的」的原因。
* 注释按字符掩掉（`//` 与 `/* */`），字符串字面量里的内容不动；**实参也从掩过的文本切**
  （旧实现从原文切 ⇒ 实参里的注释把逗号带进来，`documented` 的假红根因，见 s4）。
* 模板侧槽位：带位置索引（`%2$@`）按索引归位、`*` 宽度/精度各占一个槽；`%1$*2$d` 这种
  「`*` 自带位置索引」不认（真仓 0 处）。
* 面由 `Package.swift` **生产 target** 派生；`Tests/` `TestsUISnapshot/` `TestsPlatform/`
  （测试 target）与 `Vendor/`（独立包）不在面内。

## 用法

    python3 Scripts/check-format-arguments.py            # 判红出口码（闭环第 3 项）
    python3 Scripts/check-format-arguments.py --report   # 人读清单（含形状直方图）
    python3 Scripts/check-format-arguments.py --self-test # 门禁自己的证据（14 例）

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
# **扫描面不写死**：由 `Package.swift` 的生产 target 声明派生（原单 `T-20261010-053` ㈢）。
# 旧实现写死元组，且与 `Package.swift` 无任何对账 ⇒ `Platform/macOS` 与 `Tools/LicenseTool`
# 两个生产 root 长期在面外，往里写一处真违规是**静默通过**（成对矩阵 s5）。
PACKAGE_REL = "Package.swift"
TABLE_REL = "Core/Localization.swift"

# printf 转换符：可选 位置参数 / 标志 / 宽度 / 精度 / 长度修饰，最后是转换符本身。
SPEC_SLOT_RE = re.compile(
    r"%(?:(\d+)\$)?[-+ #0]*(\d+|\*)?(?:\.(\d+|\*))?(?:hh|h|ll|l|q|L|z|j|t)?"
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
    """模板的**实参槽位序列** —— 每个槽收一个实参（`%%` 不是槽）。

    * 带**位置索引**的转换符（`%2$@`）按索引归位（1-based），不带索引的按出现序补位：
      旧实现只按出现序 ⇒ 同一条模板上「对的判红、错的判绿」（原单 `T-20261010-053` ㈠）。
    * `*` 宽度 / 精度**各占一个实参槽**（记 `"*"`，那个实参是 `Int`）：旧实现把 `*` 整个
      丢掉 ⇒ `%-*d` 的正确调用被报「实参数 ≠ 占位符数」。
    * 补位留下的空洞记 `"?"`（类型未知：不参与槽位交叉检查，只保证计数对得上）。
    * `%1$*2$d` 这类「`*` 自带位置索引」的写法**不认**（真仓 0 处），如实登记在局限里。
    """
    slots: list[str | None] = []
    cursor = 0
    for m in SPEC_SLOT_RE.finditer(template):
        conversion = m.group(4)
        if conversion == "%":
            continue
        stars = [g for g in (m.group(2), m.group(3)) if g == "*"]
        index = m.group(1)
        start = int(index) - 1 if index is not None else cursor
        for offset in range(len(stars)):
            while len(slots) <= start + offset:
                slots.append(None)
            slots[start + offset] = "*"
        last = start + len(stars)
        while len(slots) <= last:
            slots.append(None)
        slots[last] = conversion
        cursor = last + 1
    return [slot if slot is not None else "?" for slot in slots]


def production_face(root: Path) -> tuple[list[str], list[str], list[str]]:
    """从 `Package.swift` 的**生产 target** 声明派生扫描面（原单 `T-20261010-053` ㈢）。

    返回（面 · 未声明 `path:`/`sources:` 的生产 target 名 · 测试 target 名）。
    测试 target（`DoyahCoreTests` / `DoyahUISnapshotTests` / `DoyahPlatformTests`）**不进面**：
    那里有意构造反例（直接调 `String(format:)`）。老的写死元组把 `Platform/macOS` 与
    `Tools/LicenseTool` 两个生产 root 留在面外，且没有任何判据发现 ⇒ 往里写一处真违规是静默通过。
    """
    src = mask_comments((root / PACKAGE_REL).read_text(encoding="utf-8"))
    face: list[str] = []
    undeclared: list[str] = []
    tests: list[str] = []
    for m in re.finditer(r"\.(\w*[Tt]arget)\s*\(", src):
        kind = m.group(1)
        open_index = src.index("(", m.end() - 1)
        block = src[open_index + 1 : match_bracket(src, open_index, "(", ")")]
        fields: dict[str, str] = {}
        for piece in split_top_level(block):
            label, _, value = piece.partition(":")
            fields.setdefault(label.strip(), value.strip())
        name = fields.get("name", "?").strip('"')
        if kind == "testTarget":
            tests.append(name)
            continue
        path = fields.get("path", "")
        sources = fields.get("sources", "")
        if not path and not sources:
            undeclared.append(name or kind)
            continue
        base = path.strip().strip('"') or "."
        items = re.findall(r'"([^"]*)"', sources) if sources else [""]
        for item in items:
            rel = (Path(base) / item).as_posix() if item else base
            if rel.startswith("./"):
                rel = rel[2:]
            if rel and rel not in face:
                face.append(rel)
    return face, undeclared, tests


def parse_language_cases(root: Path) -> list[str]:
    """`enum AppLanguage` 的各例（语言列表**不写死** —— 旧实现硬编码两个语言名）。"""
    src = mask_comments((root / TABLE_REL).read_text(encoding="utf-8"))
    m = re.search(r"\benum\s+AppLanguage\b[^{]*\{", src)
    if not m:
        return []
    open_index = src.index("{", m.start())
    body = src[open_index + 1 : match_bracket(src, open_index, "{", "}")]
    return re.findall(r"^[ \t]*case[ \t]+(\w+)", body, re.M)


def parse_entry_languages(root: Path) -> dict[str, list[str]]:
    """每个键**实际写了哪些语言**（按顶层逗号切 ⇒ 模板字符串里的 `.x:` 不会被当语言键）。"""
    src = (root / TABLE_REL).read_text(encoding="utf-8")
    anchor = src.find("static let table: [LKey: [AppLanguage: String]]")
    if anchor < 0:
        return {}
    start = src.index("= [", anchor) + 2
    body = src[start + 1 : match_bracket(src, start)]
    masked = mask_comments(body)
    out: dict[str, list[str]] = {}
    for m in re.finditer(r"\.(\w+)\s*:\s*\[", masked):
        inner_start = m.end() - 1
        inner = body[inner_start + 1 : match_bracket(body, inner_start)]
        langs: list[str] = []
        for piece in split_top_level(mask_comments(inner)):
            label = re.match(r"^\s*(?:AppLanguage\s*)?\.(\w+)\s*:", piece)
            if label and label.group(1) not in langs:
                langs.append(label.group(1))
        out[m.group(1)] = langs
    return out


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


def parse_call_sites(root: Path, face: list[str]) -> list[dict]:
    sites: list[dict] = []
    for sub in face:
        directory = root / sub
        if not directory.is_dir():
            continue
        for path in sorted(directory.rglob("*.swift")):
            raw = path.read_text(encoding="utf-8")
            masked = mask_comments(raw)
            for m in CALL_RE.finditer(masked):
                open_index = masked.index("(", m.start())
                close_index = match_bracket(masked, open_index, "(", ")")
                # 实参从 **masked** 切（原单 `T-20261010-053` ㈡）：从 raw 切会把注释原文
                # 带进实参，而 `split_top_level` 只认字符串、不认注释 ⇒
                # `L(.k, /* 一,二 */ "x")` 被切成 2 个实参（假红 5 条）。
                # 字符串字面量内容在 masked 里**原样保留**（模板侧早就这么做了）。
                parts = split_top_level(masked[open_index + 1 : close_index])
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

    def __init__(self, root: Path, face: list[str]) -> None:
        self.functions: dict[str, set[str]] = {}
        self.members: dict[str, set[str]] = {}

        for sub in face:
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
                # **裸标识符不解析** —— 第 37 轮实测过它的害处：`App/AppState.swift` 里
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
    ledger = load_ledger(root)
    face, undeclared, test_targets = production_face(root)
    exempt = {e["root"]: e for e in ledger.get("faceExempt", [])}
    scan_face = [r for r in face if r not in exempt]
    languages = parse_language_cases(root)
    entry_languages = parse_entry_languages(root)
    sites = parse_call_sites(root, scan_face)
    resolver = Resolver(root, scan_face)
    scanned_files = sum(
        len(list((root / rel).rglob("*.swift"))) for rel in scan_face if (root / rel).is_dir()
    )

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

    # F：扫描面（必须能从 Package.swift 机械派生）+ faceExempt 三条棘轮
    for root_rel in exempt:
        if root_rel not in face:
            errors.append(
                f"❌ [F] 面豁免陈旧：{LEDGER_REL} 的 faceExempt 登记了 `{root_rel}`，"
                f"但 {PACKAGE_REL} 里没有这个生产 root —— 请删除该条"
            )
    for name in undeclared:
        errors.append(
            f"❌ [F] 生产 target `{name}` 既没声明 `path:` 也没声明 `sources:` ⇒ "
            f"它的源根进不了扫描面（面必须能从 {PACKAGE_REL} 机械派生）"
        )
    if not scan_face:
        errors.append(
            f"❌ [F] 扫描面为空（{PACKAGE_REL} 一个生产源根都派生不出来）—— 空跑不是通过"
        )
    for root_rel in scan_face:
        if not (root / root_rel).is_dir():
            errors.append(
                f"❌ [F] 扫描面里的根 `{root_rel}` 在盘上不存在（{PACKAGE_REL} 生产 target 声明了它）"
            )
    # G：语言列表（由 `enum AppLanguage` 派生）+ 每个键都要覆盖全部语言
    if len(languages) < 2:
        errors.append(
            f"❌ [G] 从 {TABLE_REL} 的 `enum AppLanguage` 只解析出 {len(languages)} 个语言"
            f"（{languages}）—— 判据取不到输入（不是通过）"
        )
    for key_name, langs in entry_languages.items():
        missing = [lang for lang in languages if lang not in langs]
        if missing:
            errors.append(
                f"❌ [G] 语言表键 `{key_name}` 缺语言 {missing}"
                f"（`enum AppLanguage` 有 {len(languages)} 个各例）—— 那种语言下会回落到别的模板"
            )
        extra = [lang for lang in langs if lang not in languages]
        if extra:
            errors.append(
                f"❌ [G] 语言表键 `{key_name}` 有 `enum AppLanguage` 之外的语言 {extra}"
            )
    if not sites:
        errors.append(f"❌ 一个 `L(...)` 调用点都没扫到（扫描面 {scan_face}）—— 空跑不是通过")
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
                if conv == "?":
                    continue  # 位置参数留下的空洞：类型未知 ⇒ 不参与槽位交叉检查
                if kind == "number" and conv == "@":
                    flagged("A", key, file, line, f"{language} 模板第 {index + 1} 位是 `%@`，实参是数字 ⇒ 界面印 `(null)`")
                if kind == "text" and conv == "*":
                    flagged("A′", key, file, line, f"{language} 模板第 {index + 1} 位是 `*`（宽度/精度取自实参），实参是字符串 ⇒ 数字槽收字符串")
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
        "face": scan_face,
        "test_targets": test_targets,
        "scanned_files": scanned_files,
        "languages": languages,
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
    print(
        f"扫描面 {len(result['face'])} 个源根（{PACKAGE_REL} 生产 target 派生 · "
        f"测试 target {len(result['test_targets'])} 个不进面）：{result['scanned_files']} 份 .swift"
    )
    print(f"语言 {len(result['languages'])} 个（`enum AppLanguage` 派生）：{result['languages']}")
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

public enum AppLanguage: String, CaseIterable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"
}

public enum LocalizedStrings {
    static let table: [LKey: [AppLanguage: String]] = [
        .greet: [.simplifiedChinese: "你好 %@，共 %d 条", .english: "Hi %@, %d rows"],
        .rows: [.simplifiedChinese: "共 %d 行", .english: "%d rows"],
        .plain: [.simplifiedChinese: "纯文本", .english: "plain"],
        .label: [.simplifiedChinese: "当前版本：%@", .english: "Current edition: %@"],
        .pos: [.simplifiedChinese: "%2$@ 与 %1$d", .english: "%2$@ and %1$d"],
        .star: [.simplifiedChinese: "%-*d 行", .english: "%-*d rows"],
    ]
}
'''

# 夹具的 `Package.swift`：扫描面现在**从这里派生**（真仓同款 —— 生产 target 的
# `path:` / `sources:`）。测试 target 不进面。
FIXTURE_PACKAGE = '''// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Fixture",
    targets: [
        .target(name: "FixtureCore", path: ".", sources: ["Core"]),
        .executableTarget(name: "FixtureApp", path: ".", sources: ["App"]),
        .testTarget(name: "FixtureTests", path: "Tests"),
    ]
)
'''

# 面完备性臂：声明一个**新的**生产 root（`Platform`），违规写在那里。
FIXTURE_PACKAGE_PLATFORM = FIXTURE_PACKAGE.replace(
    '        .testTarget(name: "FixtureTests", path: "Tests"),',
    '        .testTarget(name: "FixtureTests", path: "Tests"),\n'
    '        .target(name: "FixturePlatform", path: "Platform"),',
)
FIXTURE_PROBE_PLATFORM = "import Foundation\n\nlet p = L(.greet, 1, 2)\n"

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


def write_fixture_tree(
    base: Path,
    fixture_source: str,
    ledger: dict | None = None,
    package_text: str | None = None,
    extra_files: dict[str, str] | None = None,
) -> Path:
    root = base / "repo"
    (root / "Core").mkdir(parents=True, exist_ok=True)
    (root / "App").mkdir(parents=True, exist_ok=True)
    (root / "Scripts").mkdir(parents=True, exist_ok=True)
    (root / PACKAGE_REL).write_text(package_text or FIXTURE_PACKAGE, encoding="utf-8")
    for rel, text in (extra_files or {}).items():
        target = root / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")
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
        (
            "位置参数归位 · 正确调用（`%2$@ 与 %1$d`：数字喂 %d、文字喂 %@）⇒ 判绿",
            FIXTURE_OK + 'let f = L(.pos, 42, "文字")\n',
            None,
            True,
            "",
        ),
        (
            "位置参数归位 · 错序调用（文字喂 %d、数字喂 %@）⇒ 判红",
            FIXTURE_OK + 'let f = L(.pos, "文字", 42)\n',
            None,
            False,
            "App/Fixture.swift:11",
        ),
        (
            "`*` 宽度各占一个实参槽（`%-*d` + `L(.star, 3, 42)`）⇒ 判绿",
            FIXTURE_OK + "let f = L(.star, 3, 42)\n",
            None,
            True,
            "",
        ),
        (
            "实参里的注释不带进实参（`L(.rows, /* 一,二 */ count)`）⇒ 判绿",
            FIXTURE_OK.replace("L(.rows, count)", "L(.rows, /* 一,二 */ count)"),
            None,
            True,
            "",
        ),
        (
            "面完备性：Package.swift 新增生产 root + 该 root 下的违规 ⇒ 判红",
            FIXTURE_OK,
            None,
            False,
            "Platform/Probe.swift:3",
            (FIXTURE_PACKAGE_PLATFORM, {"Platform/Probe.swift": FIXTURE_PROBE_PLATFORM}),
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
        for index, case in enumerate(cases, start=1):
            title, source, ledger, expect_ok, expect_text = case[:5]
            package_text, extra_files = case[5] if len(case) > 5 else (None, None)
            root = write_fixture_tree(
                tmp / f"case{index}", source, ledger, package_text, extra_files
            )
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
        last = len(cases) + 1
        print(
            f"  {'✅' if unchanged else '❌'} 例 {last}：末例核对真仓库 {len(before)} 份文件逐字节未变"
        )
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
