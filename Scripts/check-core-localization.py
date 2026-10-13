#!/usr/bin/env python3
"""Core 展示文本本地化的**棘轮**（R-45 / FR-DATA-04 / 队列 L-109）。

本脚本管**两条**「展示文本」棘轮，口径一致：**只挡变差，销账即降基线**。

棘轮 A（R-45，原有）——「含汉字」：
    Core 里有一批**直接给用户看**的中文字面量（`LocalizedError` 的描述、拒绝理由、
    单元格摘要…）。它们不经过任何语言表，于是英文界面上会混出中文。R-45 与 FR-DATA-04
    各记了一处，但真正的问题是它**会继续长** —— 每加一个 `LocalizedError` 就多一串。
    · 统计 `Core/**/*.swift`（排除 `Localization.swift` —— 那里是语言表本身）里
      "字符串字面量含汉字"的行数，按「文件数」与「行数」两个口径记账；
    · 比基线更差即失败；想增加就必须**同时**在基线里显式加数字（一次有意识的决定）；
    · 已修的地方要**降基线**（`--update-baseline`），否则棘轮只挡增长、不记进步。

棘轮 B（**队列 L-109**，2026-10-11 开发循环第 487 轮）——「写死的英文展示文案」：
    A 的判据是 `HAN = [\\u4e00-\\u9fff]` ⇒ **只挡「含汉字」的字面量**，于是写死的英文展示
    文案**整个门禁体系里全绿**：第 96 轮修 `L-108` 时实测 `Core/WorkspaceTab.swift` 里
    那句 `"Home"`（中文界面直接印英文）就是这样漏过去的。**那一处已经修了，判据的窄口
    一直在** —— 这一条把洞补上。
    · 扫描面 = `Core/**/*.swift`（与 A 同一表面）；**豁免** = `Localization.swift`
      （语言表本身）+ `CodeLanguageDefinitions.swift`（代码语言的登记表：关键字表 /
      语言名 / 补全项**整表都是技术标识**，与语言表同一性质）。豁免清单逐条登记在台账
      `pathExempt` 里，判据与脚本里的清单**双向对账**（多列少列都报红）。
    · 候选形状（**英文展示文案的窄口**）：一行里去掉注释后，取「真的是两个字界引号之间的」
      字面量（开引号的前一个字符不许是 `'` —— 挡住 `replacingOccurrences(of: "'", with: "''")`
      这种转义串里**被两个引号夹出来的假字面量** `, with: `），满足：含拉丁字母 / 不含汉字 /
      只含 `A-Za-z0-9 空格 , . ' : ; ! ? / + -` / 不含转义与格式与语法记号
      （`\\ % { } < > * _ = # @ $ | & ~ \` [ ] ( )`）/ 剥掉首尾空白后 3 ≤ 长度 ≤ 60，
      且**剥离后是多词短语，或 Title-case 单词**（`^[A-Z][a-z]{2,}$` —— 正是 `"Home"` 那一档）。
    · 判定 = **白名单**（台账 `Scripts/core-localization-english.json`）：
      **白名单之外一律报红**；每条登记项要写 `kind`（为什么它不是展示文案：SQL 方言片段 /
      驱动错误匹配串 / 协议串 / 格式串 …；**确实直达界面而暂时没翻的写 `displayDebt` =
      已登记的欠账，不是放行**），`kind` 只认脚本里那套词表。
    · 白名单**只许缩小**：盘上已经没有的登记项 ⇒ **报红并提示销账**（留着一条死白名单 =
      那个串下次写回来会**静默过关**）。`--update-baseline-english` 只负责把盘上现状
      抄进台账、**不替人分类**：新条目落成 `unclassified`，而 `unclassified` 不在词表内
      ⇒ 仍然红 —— 「加一条白名单」必须是一次有意识的分类决定。

边界（**如实登记，本轮没做的那一半**）：
    · 只扫 `Core/**` —— `App/` / `CLI/` 里写死的英文展示文案**仍漏网**（与棘轮 A 的
      扫描面一致，不是本判据新引入的洞；要覆盖得先有「App 的展示文案一律走语言表」这条
      已成立的纪律，见证据「边界」节）。
    · **全大写的单词不在候选面**（`TSV` / `CSV` / `INSERT` 这类格式名与 SQL 关键字同形；
      只有前后补空格的 SQL 片段如 `" CASCADE"`、`"WHERE "` 剥离后同样落在这一档），
      逐条登记的价值低于噪声 —— 代价如实记在证据里。
    · 只判**字面量**，不判「这个串会不会真的到界面」（后者机器判不了）。登记项的
      `kind` 是人给的分类，判据只判它在不在词表内 —— 分类对不对靠读代码 + 随轮证据。

边界（2026-10-13 合册 `T-20261013-027` 补强 · 原单 `T-20261010-049` / `T-20261010-072`）：
    · **仓根由脚本位置推导**（`ROOT = __file__/../..`）⇒ 从任何 CWD 运行读数一致，
      不再依赖「必须在仓根跑」这个惯例；正常跑会打印「扫描面 N 个 .swift」。
    · **空跑防护**：面里 `.swift` 份数低于 `FLOOR_FILES`（或面整体消失）⇒ **判红**，
      不再打印「0 个文件 / 0 行 ✅ 通过」；基线文件不在盘而面在盘 ⇒ 同样判红
      （旧版按 `{0,0}` 兜底 ⇒ 假绿）。
    · **判定物 = 字符串字面量的实际跨度**：先按 Swift 词法剥掉行注释与块注释
      （块注释可嵌套），再认单行串 / 多行串 `\"\"\"…\"\"\"` / raw 串 `#"…"#`。
      ⇒ 注释里的中文**不算**（旧版把行尾注释与块注释里的中文当展示文案 = 假阳），
      多行串里的中文**算**（旧版逐行正则看不见 = 假绿）。
    · **记账键 = 仓库相对路径**且按 `+=` 累加（旧版键 = 文件基名、赋值不累加 ⇒
      两个同名文件互相覆盖）。
    · **豁免按路径**逐条登记在 `EXEMPT_PATHS`（旧版按基名 ⇒ 任意子目录里的
      `Localization.swift` 静默豁免）。
    · `--update-baseline` 现在必须带 `--force` **与** `--reason "…"`：没有理由的上调
      一律 `rc=2` 拒绝，理由追加进台账 `comment`（旧版一条命令就把新欠账合法化）。
    · **如实登记的不覆盖**（口径可见，不是静默放过）：① 字符集只认汉字
      `\u4e00-\u9fff`，纯 CJK 标点 / 全角符号组成的串**不计**（无法与排版符号区分 ——
      本册登记为**不覆盖**、不设反例）；② 棘轮仍是**聚合**口径、不逐文件 ⇒
      「删 A 文件 3 行 + 在 B 文件加 3 行」读数不可分，该方法靠 `--report` 的逐文件
      行号由人复核；③ 棘轮 B（英文白名单）的判定物仍是**逐行**字面量 + 只剥行首注释
      —— 本册只改棘轮 A，B 面缺口另记。

用法：
    python3 Scripts/check-core-localization.py                    # 闸门：A + B 两条都跑
    python3 Scripts/check-core-localization.py --report                # 按文件列 A 的命中
    python3 Scripts/check-core-localization.py --report-english        # 按 kind 列 B 的命中
    python3 Scripts/check-core-localization.py --update-baseline --force --reason "…"  # 上调 A 的基线（必须给理由）
    python3 Scripts/check-core-localization.py --update-baseline-english  # 抄现状进 B 台账
"""

from __future__ import annotations

import bisect
import json
import pathlib
import re
import sys
import time

# 仓根由**脚本位置**推导（`Scripts/<本脚本>`）⇒ 从任何 CWD 运行读数一致、与
# 「必须在仓根跑」这个惯例解耦（合册 T-20261013-027 · 原单 T-20261010-072 ㈠）。
ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC_SELF = pathlib.Path(__file__)
# 扫描面（2026-10-13 · 概设 §7 P3 搬家）：笔记的**自有逻辑**搬到 `Plugins/Notes/Sources/` 之后，
# 这两条纪律（「汉字字面量只降不升」与「写死的英文展示文案要登记」）**跟着代码走** ——
# 棘轮只挡增长 ⇒ 不跟过去就等于「搬一次家把这一族的欠账从账上抹掉」（免费降基线）。
CORE_SOURCE_RELS = ("Core", "Plugins/Notes/Sources")
CORE_SOURCES = tuple(ROOT / rel for rel in CORE_SOURCE_RELS)
CORE = ROOT / "Core"
BASELINE = ROOT / "Scripts/core-localization-baseline.json"
ENGLISH_LEDGER = ROOT / "Scripts/core-localization-english.json"
# 空跑防护（072 ㈠/验收 2）：面里 `.swift` 份数下限。2026-10-13 实测面 = 222 份
# （`Core` 201 + `Plugins/Notes/Sources` 21），留出搬家余量取 180；低即判红。
FLOOR_FILES = 180

# ---- 棘轮 A：含汉字的字面量 -------------------------------------------------
# 豁免按**路径**逐条登记（072 ㈧：旧版按文件基名 ⇒ 任意子目录里的同名文件静默豁免）。
EXEMPT_PATHS = {
    "Core/Localization.swift": "语言表本身（这里就是两语槽位）",
}
HAN = re.compile(r"[\u4e00-\u9fff]")


# ---- 棘轮 B：写死的英文展示文案 ---------------------------------------------
# 豁免：语言表本身 + 代码语言的登记表（整表都是技术标识）。
ENGLISH_PATH_EXEMPT = {
    "Localization.swift": "语言表本身（这里就是两语槽位；汉字棘轮同样豁免它）",
    "CodeLanguageDefinitions.swift": "代码语言的登记表：关键字表 / 语言名 / 补全项 —— 整表都是技术标识，与语言表同一性质；"
                                     "该表里合法的语言显示名（`Plain Text` / `Python`…）是**专名**，按 R-53 同族口径保持协议原文",
}
# 真字面量：开引号的前一个字符必须是「引出引号的字符」（空白 / `(` / `=` / `:` / `,` / `[` …），
# 不能是字母数字或引号类字符 —— 后者会从 `replacingOccurrences(of: "'", with: "''")` 这种
# 转义串里夹出假字面量 `, with: `（前一个字符分别是 `'` / 反引号 / `\n` 里的 `n`）。
ENGLISH_LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')
ENGLISH_LITERAL_BLOCKERS = ("'", '"', "\\", "`")


def _introduces_literal(line: str, start: int) -> bool:
    if start <= 0:
        return True
    previous = line[start - 1]
    return not previous.isalnum() and previous not in ENGLISH_LITERAL_BLOCKERS
ENGLISH_BAD_CHARS = set("\\%{}<>*_=#@$+|&~`[]()")
ENGLISH_ALLOWED_CHARS = re.compile(r"^[A-Za-z0-9 ,.';:!?/+-]+$")
ENGLISH_TITLE_CASE = re.compile(r"^[A-Z][a-z]{2,}$")
ENGLISH_MIN, ENGLISH_MAX = 3, 60

ENGLISH_KINDS = {
    "sql": "SQL 方言片段 / 关键字 / 迁移 SQL —— 拼 SQL 用的，不是展示文案",
    "dbType": "数据库类型名（PG / MySQL 的类型原文）",
    "wireValue": "协议层取值字面量（如 PG 文本表示里的 `Infinity`）",
    "explainField": "PG `EXPLAIN` 输出或 JSON 的字段名 —— 解析用，不是展示文案",
    "driverMessage": "驱动 / 系统错误文本的**匹配子**（`contains` 用）",
    "serverMessageMatch": "服务端错误原文的匹配子 / 归类用",
    "internalErrorDescription": "内部错误描述的**机器载荷**（`LocalizedError` 的技术串；"
                                "人话一律由带 `language:` 的渲染入口给 —— 概要设计 §7「协议入口不许写死语言」）",
    "protocolToken": "协议 / 接口层的固定串（HTTP 头名、认证方案、JSON-RPC 错误文本、"
                     "SSL 模式名、MCP 方法名、剪贴板格式名）",
    "formatPattern": "日期 / 数字格式串",
    "pathName": "路径 / 目录名",
    "assetName": "字体 / 资源名",
    "xmlElementName": "XML 元素 / 属性名（xlsx OOXML）",
    "cliFlag": "命令行开关",
    "parseToken": "解析用户文本时要匹配的关键字（如维护计划里的 `cost: high`）",
    "logOnly": "只进日志",
    "guardrailPattern": "提示注入检测的模式串",
    "productName": "产品 / 品牌专名（按 R-53 同族口径不翻）",
    "sampleValue": "合成数据的样例值",
    "displayDebt": "**已登记的欠账**：确实直达界面、暂时写死英文 —— 不是放行，棘轮只挡变差",
}
ENGLISH_ALLOWED_KINDS = set(ENGLISH_KINDS)
ENGLISH_PENDING_KIND = "unclassified"


def _skip_quote(text: str, start: int) -> int:
    """跳过单行字符串（`text[start] == '"'`）：返回闭引号之后的下标，遇换行即止；\n    串里的 `\\( … )` 插值按括号配平跳过（内层可能是带引号的表达式）。"""
    index = start + 1
    while index < len(text):
        char = text[index]
        if char == "\\":
            if text.startswith("\\(", index):
                index = _skip_interpolation(text, index + 1)
                continue
            index += 2
            continue
        if char == '"':
            return index + 1
        if char == "\n":
            return index
        index += 1
    return index


def _skip_interpolation(text: str, start: int) -> int:
    """跳过 Swift 串插值 `\\( … )`：括号配平，内层按单行串处理。"""
    depth = 0
    index = start
    while index < len(text):
        char = text[index]
        if char == '"':
            index = _skip_quote(text, index)
            continue
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return index + 1
        index += 1
    return index


def literal_spans(text: str) -> list[tuple[int, int]]:
    """按 Swift 词法取**字符串字面量**的跨度（072 ㈡㈢㈣ + 049 ㈠）：
    先剥行注释 `//` 与块注释 `/* … */`（**可嵌套**），再认单行串、多行串
    `\"\"\"…\"\"\"`、raw 串 `#"…"#` / `##\"\"\"…\"\"\"##`；返回 [(start, end)]。"""
    spans: list[tuple[int, int]] = []
    index = 0
    size = len(text)
    while index < size:
        if text.startswith("//", index):
            newline = text.find("\n", index)
            index = size if newline < 0 else newline + 1
            continue
        if text.startswith("/*", index):
            depth = 1
            index += 2
            while index < size and depth:
                if text.startswith("/*", index):
                    depth += 1
                    index += 2
                elif text.startswith("*/", index):
                    depth -= 1
                    index += 2
                else:
                    index += 1
            continue
        hashes = 0
        probe = index
        while probe < size and text[probe] == "#":
            hashes += 1
            probe += 1
        if probe < size and text[probe] == '"':
            multiline = text.startswith('"""', probe)
            if hashes == 0 and not multiline:
                # 单行串：转义与串插值都按 Swift 口径走（`"\\\\"` / `"…… \\(x) …"`）。
                end = _skip_quote(text, probe)
                spans.append((index, end))
                index = max(end, index + 1)
                continue
            opener = 3 if multiline else 1
            closer = '"' * opener + "#" * hashes
            interpolation = "\\" + "#" * hashes + "("
            cursor = probe + opener
            while cursor < size:
                escaped = hashes == 0 and text[cursor - 1:cursor] == "\\"
                if text.startswith(closer, cursor) and not escaped:
                    cursor += len(closer)
                    break
                if text.startswith(interpolation, cursor):
                    cursor = _skip_interpolation(text, cursor + len(interpolation) - 1)
                    continue
                cursor += 1
            spans.append((index, min(cursor, size)))
            index = max(cursor, index + 1)
            continue
        index += 1
    return spans


def han_lines(text: str) -> list[int]:
    """文件里「**字符串字面量正文**含汉字」的行号（升序去重）。

    注释里的中文不算（先由 `literal_spans` 剥掉）；多行串按**行列跨度**逐行判定
    —— 三引号块里的中文行因此可见（旧版逐行正则看不见）。"""
    line_starts = [0]
    for match in re.finditer("\n", text):
        line_starts.append(match.end())
    hits: set[int] = set()
    for start, end in literal_spans(text):
        if end <= start:
            continue
        first = bisect.bisect_right(line_starts, start)
        last = bisect.bisect_right(line_starts, max(end - 1, start))
        for number in range(first, last + 1):
            line_start = line_starts[number - 1]
            line_end = line_starts[number] - 1 if number < len(line_starts) else len(text)
            if HAN.search(text[max(start, line_start):min(end, line_end)]):
                hits.add(number)
    return sorted(hits)


def scan() -> tuple[dict[str, int], dict[str, list[int]], int]:
    """返回 (每个文件的命中行数, 每个文件的行号列表, 扫描面 .swift 份数)。

    面键 = **仓库相对路径**（072 ㈣：旧版用文件基名 ⇒ 同名文件互相覆盖、`--report`
    还会把两处行号并成一条），值按 `+=` **累加**。"""
    counts: dict[str, int] = {}
    lines_by_file: dict[str, list[int]] = {}
    scanned = 0
    for path in sorted(p for source in CORE_SOURCES for p in source.rglob("*.swift")):
        rel = path.relative_to(ROOT).as_posix()
        if rel in EXEMPT_PATHS:
            continue
        scanned += 1
        hits = han_lines(path.read_text(encoding="utf-8"))
        if hits:
            counts[rel] = counts.get(rel, 0) + len(hits)
            lines_by_file[rel] = hits
    return counts, lines_by_file, scanned


def english_candidates() -> dict[str, list[str]]:
    """返回 {字面量: ["文件:行", …]} —— 盘上「像写死的英文展示文案」的全部字面量。"""
    found: dict[str, list[str]] = {}
    for path in sorted(p for source in CORE_SOURCES for p in source.rglob("*.swift")):
        if path.name in ENGLISH_PATH_EXEMPT:
            continue
        rel = path.relative_to(ROOT).as_posix()
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            stripped = line.strip()
            if stripped.startswith("//"):
                continue
            for match in ENGLISH_LITERAL.finditer(line):
                if not _introduces_literal(line, match.start()):
                    continue
                literal = match.group(1)
                if not re.search(r"[A-Za-z]", literal):
                    continue
                if HAN.search(literal):
                    continue
                if any(char in ENGLISH_BAD_CHARS for char in literal):
                    continue
                if not ENGLISH_ALLOWED_CHARS.match(literal):
                    continue
                text = literal.strip()
                if not (3 <= len(text) <= ENGLISH_MAX):
                    continue
                if " " not in text and not ENGLISH_TITLE_CASE.match(text):
                    continue
                found.setdefault(text, []).append(f"{rel}:{number}")
    return found


def load_ledger() -> dict:
    if not ENGLISH_LEDGER.exists():
        return {"note": "", "kinds": {}, "pathExempt": {}, "entries": {}}
    return json.loads(ENGLISH_LEDGER.read_text(encoding="utf-8"))


def check_english() -> tuple[list[str], str]:
    """棘轮 B。返回 (问题列表, 一行读数)。"""
    ledger = load_ledger()
    entries = ledger.get("entries") or {}
    on_disk = english_candidates()
    problems: list[str] = []

    declared_kinds = set((ledger.get("kinds") or {}).keys())
    if declared_kinds != ENGLISH_ALLOWED_KINDS:
        problems.append(
            f"[台账] `kinds` 与脚本里的词表不一致：台账独有 {sorted(declared_kinds - ENGLISH_ALLOWED_KINDS)} / "
            f"脚本独有 {sorted(ENGLISH_ALLOWED_KINDS - declared_kinds)}"
        )
    declared_exempt = set((ledger.get("pathExempt") or {}).keys())
    if declared_exempt != set(ENGLISH_PATH_EXEMPT):
        problems.append(
            f"[台账] `pathExempt` 与脚本里的豁免清单不一致：台账独有 {sorted(declared_exempt - set(ENGLISH_PATH_EXEMPT))} / "
            f"脚本独有 {sorted(set(ENGLISH_PATH_EXEMPT) - declared_exempt)}"
        )

    for literal, entry in sorted(entries.items()):
        kind = (entry or {}).get("kind")
        if kind == ENGLISH_PENDING_KIND or kind not in ENGLISH_ALLOWED_KINDS:
            problems.append(
                f"[未分类] `{literal}` 的 kind = `{kind}` 不在词表内 —— "
                f"白名单的每一条都要有人给一个词表里的分类（{ENGLISH_PENDING_KIND} = 抄现状还没分类）"
            )
    fresh = sorted(set(on_disk) - set(entries))
    for literal in fresh:
        problems.append(
            f"[新增] `{literal}` 是写死的英文展示文案，不在白名单里（首处 {on_disk[literal][0]}）—— "
            f"要么改走语言表，要么说明它为什么不是展示文案、用 --update-baseline-english 登记后**给它分类**"
        )
    stale = sorted(set(entries) - set(on_disk))
    for literal in stale:
        problems.append(
            f"[陈旧] 白名单里的 `{literal}` 盘上已经没有了 —— 请销账（--update-baseline-english），"
            f"留着一条死白名单等于那个串下次写回来会静默过关"
        )

    by_kind: dict[str, int] = {}
    for entry in entries.values():
        kind = (entry or {}).get("kind") or "?"
        by_kind[kind] = by_kind.get(kind, 0) + 1
    summary = "，".join(f"{kind} {count}" for kind, count in sorted(by_kind.items()))

    if problems:
        return problems, (
            f"❌ Core 写死的英文展示文案（棘轮 B · 队列 L-109）：{len(problems)} 项 —— "
            f"白名单 {len(entries)} 条 / 盘上候选 {len(on_disk)} 条"
        )
    return [], (
        f"✅ Core 写死的英文展示文案（棘轮 B · 队列 L-109）：白名单外 0 条、陈旧 0 条"
        f"（白名单 {len(entries)} 条 = 盘上候选 {len(on_disk)} 条；{summary}；"
        f"豁免文件 {len(ENGLISH_PATH_EXEMPT)} 个、其名逐条登记在台账里）"
    )


def write_english_ledger() -> int:
    """抄现状进台账：已有条目保留原 kind，新条目落成 unclassified（仍需人分类）。"""
    ledger = load_ledger()
    entries = ledger.get("entries") or {}
    on_disk = english_candidates()
    merged: dict[str, dict] = {}
    for literal in sorted(on_disk):
        entry = dict(entries.get(literal) or {})
        entry["kind"] = entry.get("kind") or ENGLISH_PENDING_KIND
        entry.setdefault("sites", on_disk[literal][:3])
        merged[literal] = entry
    pending = sum(1 for entry in merged.values() if entry["kind"] == ENGLISH_PENDING_KIND)
    document = {
        "note": (
            "「Core 里写死的英文展示文案」白名单 + 棘轮（队列 L-109）。判据与用法见 "
            "Scripts/check-core-localization.py 头部（棘轮 B）。口径：**白名单之外一律报红；"
            "白名单只许缩小**（盘上已经没有的条目要销账，留着 = 那个串下次写回来会静默过关）。"
            "每条的 kind 只认脚本里那套词表；`unclassified` = 抄现状还没分类，**不在词表内 ⇒ 判红** "
            "—— 「加一条白名单」必须是一次有意识的分类决定，本文件的 --update-baseline-english "
            "只抄现状、不替人分类。`displayDebt` = 确实直达界面、暂时写死英文的**已登记欠账**"
            "（不是放行）。"
        ),
        "kinds": ENGLISH_KINDS,
        "pathExempt": ENGLISH_PATH_EXEMPT,
        "entries": merged,
    }
    ENGLISH_LEDGER.write_text(
        json.dumps(document, ensure_ascii=False, indent=2, sort_keys=False) + "\n", encoding="utf-8"
    )
    print(
        f"✅ 英文白名单台账已按盘上现状重写：{len(merged)} 条"
        f"（其中待分类 {pending} 条 —— 待分类不在词表内，闸门仍会红，请逐条给 kind）"
    )
    return 0


def self_test() -> int:
    """判据自己的证据：在**临时副本**上把每条口径各弄坏一次，要求当场报红；
    末例核对真仓库逐字节未变（「判据写完不对已知改动报红，等于没有」）。"""
    import hashlib
    import shutil
    import subprocess
    import tempfile

    watched = [ENGLISH_LEDGER, BASELINE, SRC_SELF] + [
        CORE / "WorkspaceTab.swift",
        ROOT / "Plugins/Notes/Sources/Note.swift",
    ]
    before = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in watched}

    root = pathlib.Path(tempfile.mkdtemp(prefix="core-loc-selftest-"))
    pristine = pathlib.Path(tempfile.mkdtemp(prefix="core-loc-pristine-"))
    for rel in CORE_SOURCE_RELS:
        shutil.copytree(ROOT / rel, pristine / rel)
        shutil.copytree(ROOT / rel, root / rel)
    (root / "Scripts").mkdir()
    for name in (SRC_SELF.name, ENGLISH_LEDGER.name, BASELINE.name):
        shutil.copy(ROOT / "Scripts" / name, root / "Scripts" / name)
    ledger_path = root / "Scripts" / ENGLISH_LEDGER.name
    original_ledger = ledger_path.read_text(encoding="utf-8")
    def run(args: tuple[str, ...] = ()) -> tuple[int, str]:
        done = subprocess.run([sys.executable, "Scripts/" + SRC_SELF.name, *args],
                              cwd=root, capture_output=True, text=True)
        return done.returncode, done.stdout + done.stderr

    # 先让**临时副本**的基线按副本实测对齐（真仓基线可能落后于本次口径改动；
    # 不对齐则后面每一条「相对基线 +N」的断言都在跟一份过期的数字比对）。
    align_rc, align_output = run(("--update-baseline", "--force", "--reason", "自检环境对齐（临时副本实测）"))
    if align_rc != 0:
        print("❌ 自检环境对齐失败：临时副本上的 `--update-baseline --force` 未 rc=0 ——")
        print("   " + align_output.strip().replace("\n", "\n   "))
        shutil.rmtree(root, ignore_errors=True)
        shutil.rmtree(pristine, ignore_errors=True)
        return 1
    baseline_value = json.loads((root / "Scripts" / BASELINE.name).read_text(encoding="utf-8"))["baseline"]
    floor_lines = baseline_value["lines"]
    floor_files = baseline_value["files"]

    def restore_face() -> None:
        """每个例跑完把扫描面与台账复原（例与例之间不许互相污染）。"""
        for rel in CORE_SOURCE_RELS:
            target = root / rel
            if target.exists():
                shutil.rmtree(target)
            shutil.copytree(pristine / rel, target)
        for stray in (root / "CoreX",):
            if stray.exists():
                shutil.rmtree(stray)
        ledger_path.write_text(original_ledger, encoding="utf-8")

    results: list[tuple[str, bool, str]] = []

    def case(title: str, expect_rc: int, markers, mutate, args: tuple[str, ...] = (), absent=()) -> None:
        wanted = (markers,) if isinstance(markers, str) else tuple(markers)
        unwanted = (absent,) if isinstance(absent, str) else tuple(absent)
        mutate()
        rc, output = run(args)
        hit = all(marker in output for marker in wanted)
        leaked = [marker for marker in unwanted if marker in output]
        ok = rc == expect_rc and hit and not leaked
        results.append((title, ok, f"rc={rc}（要求 {expect_rc}）｜该出现 {hit}｜不该出现 {len(leaked)} 条"))
        restore_face()

    def probe(rel: str, body: str):
        def mutate() -> None:
            path = root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(body, encoding="utf-8")
        return mutate

    def edit_ledger(change):
        def mutate() -> None:
            document = json.loads(original_ledger)
            change(document)
            ledger_path.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return mutate

    multi_body = (
        'enum SelfTestMulti {\n'
        '    static let note = """\n'
        '    备份工具版本低于服务器：请换用同主版本的客户端工具。\n'
        '    """\n'
        '}\n'
    )
    single_body = (
        'enum SelfTestSingle {\n'
        '    static let note = "备份工具版本低于服务器：请换用同主版本的客户端工具。"\n'
        '}\n'
    )
    dup_body = (
        'enum SelfTestDup {\n'
        '    static let first = "保存失败"\n'
        '    static let second = "读取失败"\n'
        '}\n'
    )

    case("① 多行串里的中文文案**计入**（旧版逐行正则看不见 = 假绿）", 0,
         ["Core/__SelfTestMulti.swift"], probe("Core/__SelfTestMulti.swift", multi_body),
         args=("--report",))
    case("② 多行串新增 ⇒ 闸门判红、行数读数 +1", 1,
         [f"行数 {floor_lines} → {floor_lines + 1}"],
         probe("Core/__SelfTestMulti.swift", multi_body))
    case("③ 单行串对照仍判红（回归：现有唯一的红线不许失效）", 1,
         [f"行数 {floor_lines} → {floor_lines + 1}"],
         probe("Core/__SelfTestSingle.swift", single_body))
    case("④ 行尾注释里的中文串**不算**（旧版假阳）", 0, [],
         probe("Core/__SelfTestTail.swift", 'enum SelfTestTail {\n    static let tail = 1 // 备注 "中文注释"\n}\n'),
         args=("--report",), absent=["Core/__SelfTestTail.swift"])
    case("⑤ 块注释里的中文串**不算**（单行块 + 多行块各一）", 0, [],
         probe("Core/__SelfTestBlock.swift",
               'enum SelfTestBlock {\n    /* 历史：曾用 "中文提示" */\n    /*\n     旧文案：\n     "保存失败，请重试。"\n     */\n    static let value = 1\n}\n'),
         args=("--report",), absent=["Core/__SelfTestBlock.swift"])
    case("⑥ 同名不同目录两文件 ⇒ 行数不丢（各 2 行 = 合计 +4）", 0,
         [f"{floor_files + 2} 个文件 / {floor_lines + 4} 行",
          "Core/__SelfTestDup.swift", "Core/SubSelfTest/__SelfTestDup.swift"],
         lambda: (probe("Core/__SelfTestDup.swift", dup_body)(),
                  probe("Core/SubSelfTest/__SelfTestDup.swift", dup_body)()),
         args=("--report",))
    case("⑦ `Core/<新目录>/Localization.swift` 里的中文**在面内**（豁免按路径，不再按基名）", 0,
         ["Core/SubSelfTest/Localization.swift"],
         probe("Core/SubSelfTest/Localization.swift", 'enum Localization {\n    static let title = "标题"\n}\n'),
         args=("--report",))
    case("⑧ 真语言表 `Core/Localization.swift` 按**路径**豁免（不出现在报告里）", 0, [], lambda: None,
         args=("--report",), absent=["Core/Localization.swift"])
    case("⑨ 扫描面空 / `Core` 改名 `CoreX` ⇒ 判红（空跑防护）", 1, ["空跑防护"],
         lambda: shutil.move(str(root / "Core"), str(root / "CoreX")))
    case("⑩ 扫描面整体搬走（`Core` + `Plugins`）⇒ 判红（下限兜底）", 1, ["空跑防护"],
         lambda: (shutil.rmtree(root / "Core"), shutil.rmtree(root / "Plugins")))
    case("⑪ 未知参数 ⇒ rc=2 拒绝（不静默吞参）", 2, ["未知参数"], lambda: None, args=("--nonsense",))

    case("⑫ 新增 Title-case 展示名（`\"Home\"` = L-109 的原始症状）⇒ 红", 1, "[新增] `Home`",
         probe("Core/__SelfTestProbe.swift", 'enum SelfTestProbe {\n    static let title = "Home"\n}\n'))
    case("⑬ 新增多词英文展示文案 ⇒ 红", 1, "[新增] `Untitled Document`",
         probe("Core/__SelfTestProbe.swift", 'enum SelfTestProbe {\n    static let title = "Untitled Document"\n}\n'))
    case("⑭ 盘上少了白名单条目 ⇒ 红（陈旧 / 要销账）", 1, "[陈旧]",
         edit_ledger(lambda doc: doc["entries"].update({"Ghost Label": {"kind": "sql"}})))
    case("⑮ 白名单条目没分类（kind=unclassified）⇒ 红", 1, "[未分类]",
         edit_ledger(lambda doc: doc["entries"]["Node Type"].update({"kind": "unclassified"})))
    case("⑯ 豁免清单与脚本对不上 ⇒ 红", 1, "`pathExempt`",
         edit_ledger(lambda doc: doc["pathExempt"].pop("CodeLanguageDefinitions.swift")))
    case("⑰ 对照组：没有坏东西 ⇒ 绿", 0, "白名单外 0 条、陈旧 0 条", lambda: None)

    shutil.rmtree(root, ignore_errors=True)
    shutil.rmtree(pristine, ignore_errors=True)
    after = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in watched}
    untouched = before == after

    for title, ok, note in results:
        print(f"{'✅' if ok else '❌'} {title}  {note}")
    print(f"{'✅' if untouched else '❌'} 真仓库逐字节未变（{len(watched)} 份：判据 / 两份台账 / 两个 Core 源文件）")
    passed = sum(1 for _, ok, _ in results if ok)
    print(f"—— Core 展示文本棘轮（A+B）判据自检：{len(results)} 条中 {passed} 条达到预期"
          f"（另 1 条真仓库未变）")
    if SRC_SELF.exists() and (passed != len(results) or not untouched):
        return 1
    return 0


KNOWN_FLAGS = (
    "--report",
    "--report-english",
    "--update-baseline",
    "--update-baseline-english",
    "--self-test",
    "--force",  # 只与 --update-baseline 连用（原单 072 ㈦：上升必须有意识）
)


def _reason(argv: list[str]) -> str:
    """取 `--reason "…"` / `--reason=…` 的值（空 = 没给）。"""
    for index, item in enumerate(argv):
        if item == "--reason" and index + 1 < len(argv):
            return argv[index + 1].strip()
        if item.startswith("--reason="):
            return item.split("=", 1)[1].strip()
    return ""


def _unknown_args(argv: list[str]) -> list[str]:
    """挑出不认识的参数（`--reason` 吃掉它后面那个值）。"""
    unknown: list[str] = []
    skip = False
    for item in argv:
        if skip:
            skip = False
            continue
        if item == "--reason":
            skip = True
            continue
        if item.startswith("--reason=") or item in KNOWN_FLAGS:
            continue
        unknown.append(item)
    return unknown


def main() -> int:
    argv = sys.argv[1:]
    unknown = _unknown_args(argv)
    if unknown:
        print(f"❌ 未知参数 {unknown}：本判据只认 "
              f"{[item for item in KNOWN_FLAGS if item != '--force']} 与 `--reason \"…\"` ——"
              f" 不静默吞参（旧版 `--bogus` / `--help` 都照跑正判，见原单 T-20261010-072 三）。")
        return 2
    if "--self-test" in argv:
        return self_test()
    for name in ("--update-baseline-english", "--report-english"):
        if name in argv:
            if name == "--update-baseline-english":
                return write_english_ledger()
            on_disk = english_candidates()
            ledger = load_ledger()
            entries = ledger.get("entries") or {}
            by_kind: dict[str, list[str]] = {}
            for literal in sorted(on_disk):
                kind = (entries.get(literal) or {}).get("kind") or ENGLISH_PENDING_KIND
                by_kind.setdefault(kind, []).append(literal)
            for kind in sorted(by_kind):
                print(f"— {kind}（{len(by_kind[kind])} 条）")
                for literal in by_kind[kind]:
                    print(f"    {literal!r}   {on_disk[literal][0]}")
            print(f"合计：{len(on_disk)} 个候选字面量")
            return 0

    counts, lines_by_file, scanned = scan()
    current = {"files": len(counts), "lines": sum(counts.values())}

    if "--update-baseline" in argv:
        if "--force" not in argv:
            print("❌ `--update-baseline` 需要显式 `--force`：旧版一条命令就把新欠账合法化"
                  "（原单 T-20261010-072 ㈦）。请写 `--update-baseline --force --reason \"…\"`。")
            return 2
        reason = _reason(argv)
        if not reason:
            print("❌ `--update-baseline --force` 还缺 `--reason \"…\"`：上调要有人给的理由，"
                  "理由会追加进台账 comment。")
            return 2
        previous = json.loads(BASELINE.read_text(encoding="utf-8")) if BASELINE.exists() else {}
        old = previous.get("baseline") or {}
        comment = previous.get("comment") or (
            "Core 展示文本本地化棘轮基线：Core 里「字符串字面量含汉字」的文件数与行数只能降不能升。"
        )
        comment += (f"\n\n**本次上调（{time.strftime('%Y-%m-%d')} · `--force` + 理由）：{reason}**"
                    f" —— 新基线 {current['files']} 个文件 / {current['lines']} 行"
                    f"（旧 {old.get('files', '?')} / {old.get('lines', '?')}）。")
        BASELINE.write_text(
            json.dumps({"comment": comment, "baseline": current},
                       ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        print(f"✅ 基线已更新（含理由）：{current['files']} 个文件 / {current['lines']} 行")
        print(f"   口径：含多行串 `\"\"\"…\"\"\"` 与 raw 串；注释不计；"
              f"面 = {' + '.join(CORE_SOURCE_RELS)}")
        return 0

    if "--report" in argv:
        for name, count in sorted(counts.items(), key=lambda item: (-item[1], item[0])):
            print(f"{count:>4}  {name}  行号 {lines_by_file[name][:6]}{' …' if count > 6 else ''}")
        print(f"合计：{current['files']} 个文件 / {current['lines']} 行（扫描面 {scanned} 个 .swift）")
        return 0

    baseline = (
        json.loads(BASELINE.read_text(encoding="utf-8"))["baseline"]
        if BASELINE.exists()
        else {"files": 0, "lines": 0}
    )
    face = " + ".join(CORE_SOURCE_RELS)
    print(f"扫描面 {scanned} 个 .swift（{face}；下限 {FLOOR_FILES}）")
    problems_a: list[str] = []
    if scanned < FLOOR_FILES:
        problems_a.append(
            f"❌ 本地化棘轮**无法进行**（空跑防护）：扫描面只有 {scanned} 个 .swift"
            f"（下限 {FLOOR_FILES}）—— `Core/` 被改名或搬家了吗？面被砍到底不许静默通过。"
        )
    elif not BASELINE.exists():
        problems_a.append(
            "❌ 本地化棘轮**无法进行**：基线文件 `Scripts/core-localization-baseline.json` 不在盘，"
            f"而扫描面有 {scanned} 个 .swift —— 按 0/0 兜底会假绿（原单 T-20261010-072 ㈠）。"
        )
    else:
        if current["files"] > baseline["files"]:
            problems_a.append(f"文件数 {baseline['files']} → {current['files']}")
        if current["lines"] > baseline["lines"]:
            problems_a.append(f"行数 {baseline['lines']} → {current['lines']}")

    problems_b, line_b = check_english()

    if problems_a:
        print(f"❌ Core 展示文本本地化棘轮失败（{len(problems_a)} 项）：")
        for problem in problems_a:
            print("   " + problem)
        print("   提示：新写的用户可见文案请走 `LocalizedStrings.text(_:language:)`（Core 的语言表），")
        print("         把语言作为参数传进来（默认中文，界面传当前语言）；确有必要保留字面量时，")
        print("         请先在 `Scripts/core-localization-baseline.json` 里显式加数字并说明原因")
        print("         （棘轮 A 的上调一律走 `--update-baseline --force --reason \"…\"`）。")
    else:
        print(
            f"✅ Core 展示文本本地化棘轮通过（{current['files']} 个文件 / {current['lines']} 行；"
            f"基线 {baseline['files']} / {baseline['lines']}）"
        )

    print(line_b)
    if problems_b:
        for problem in problems_b:
            print("   " + problem)
        print("   提示：这两条棘轮的口径是「**只挡变差**」—— 棘轮 B 的白名单 = "
              "`Scripts/core-localization-english.json`（豁免文件与每条的分类理由都在里面）。")

    return 1 if (problems_a or problems_b) else 0


if __name__ == "__main__":
    raise SystemExit(main())
