#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""**「语言是传进来的，不是写死的」**的机械门禁（队列 L-47）。

## 它挡的是什么

第 46 轮读图：英文界面（`diagnosis-empty-en`）上界面文案都是英文，**唯独「给模型的资料」
整块是中文**。根因在 `Core/DiagnosisContext.swift` —— 那里有一个文件私有的取值助手把
`language:` **钉死**成 `.simplifiedChinese`：

    private func localizedText(_ key: LKey, _ arguments: CVarArg...) -> String {
        … LocalizedStrings.text(key, language: .simplifiedChinese) …
    }

后果不只是「这一块中文」：语言表里 `diagnosisTarget` / `diagnosisEvidenceHeader` /
`diagnosisFormatConclusion` … 这些键**都有英文译文**，而它们**只被这一处引用**
⇒ **英文译文永远不可达**（死译文）。同族的写法还有 `t(_ key: LKey …)`（AICapture /
AICaptureUltra / License）与 `text(_ key: LKey …)`（MCPToolCatalog）。

**为什么现有门禁全都看不见它**：R-45 的棘轮（`check-core-localization.py`）数的是
「Core 代码里含**汉字**的字符串字面量」—— 这里代码里**一个汉字都没有**（文案早在语言表里）；
`check-effective-language.py` 只扫 `App/`，且只禁「按用户选择取语言」两种写法。
**「把语言写成字面量」这个形状两边都没覆盖。**

## 四条判据

* **A（写死语言的调用点必须逐条登记 + 棘轮）** 扫 `Core/` `App/` `CLI/` `Platform/` 的
  `*.swift`，找出把**字面语言**（`language: .simplifiedChinese` / `.english`）传给本地化
  取值入口的每一处，按**文件**归组：文件必须在台账 `Scripts/literal-language-dispositions.json`
  的 `files` 里登记（带 `maxSites` 与 `reason`）。
  未登记的文件 / 超过登记处数 ⇒ **红**；比登记处数**少** ⇒ 只提示（减少是好事，但不许静默改台账）；
  `maxSites: 0` 是**回归钉** —— 本轮已把语言透传的文件（`Core/DiagnosisContext.swift` /
  `Core/DiagnosisAdvice.swift`）在这里钉成 0，再出现字面语言即红。
* **B（死译文）** 台账 `deadKeys` 逐条登记「有英文译文、却只被写死语言的入口引用」的键
  （它们是**已登记的欠账**，不是放行）。两个方向都判：
  ① 真出现一个**没登记**的死键 ⇒ **红**（这正是本轮要消掉的那一类缺陷，不许再新增）；
  ② 台账里的死键**已经可达**（或键名根本不存在了）⇒ **红**（陈旧 —— 修好了就要销账）。
  死译文的判定把**包装函数**算进去：形如 `func t(_ key: LKey …)` 而函数体里写死语言的
  私有助手，它的每个调用点都算「写死语言」（这正是 `localizedText` 那一类，
  不这么算的话修之前反而「看不见」）。
* **C（本轮修的那一族不许回退：源树判据）** `Core/DiagnosisContext.swift` 的文本出口必须
  **带 `language:` 形参**（`text(language:)` / `promptText(language:)` /
  `boundedPromptText(language:maxCharacters:)` / `makeEvidence(…language:…)`），
  `DiagnosisAdvice.parse` 必须带 `language:`，`App/Views/DiagnosisPanel.swift` 必须把
  `effectiveLanguage` 传下去 —— 只靠 A 挡不住「删掉形参、在函数体里再写死一次」。
  **L-65 第 1 批起**同一判据扩到三处同族出口：`Core/LicenseLoader.swift`（`load` /
  `licenseDecodeFailureHint` / `summary`）、`Core/NoteBody.swift`（`toSpans` / `exportMarkdown`）、
  `Core/TableImport.swift`（`copySupport` / `preferredWriteMode`）。
  **L-65 第 2 批**：`Core/SSHTunnelProcess.swift`（`start(...)` / `describe(language:)`）。
  **L-65 第 3 / 4 批**再扩四族：`Core/AICapture.swift`（`skillNote` / `sqlNote`）、
  `Core/AICaptureUltra.swift`（`diagnosisNote` / `maintenanceNote` / `stateText`）、
  `Core/License.swift`（`features(language:)` / `items(for:language:)`）+
  `Core/LicensePresentation.swift`（`upgradeLines(for:language:)`）、
  `Core/MaintenancePlan.swift`（`review` / `makePlan`）、
  `Core/MCPToolCatalog.swift`（`decision`）+ `Core/MCPSession.swift`（会话属性 `language`
  与 `init(capabilities:language:)`）。
  **同一判据最新加的一条是「调用方也要钉」**：形参留着还不够 —— 展示点不给语言，一样会退回
  「Core 自己选」。所以 `App/AppState.swift`（维护 / 诊断两处捕获）、
  `App/Views/AboutLicenseSheet.swift`（升级页）、`CLI/main.swift`（维护命令 / MCP 会话）
  这些调用点的**实参里必须出现 `language:`**（在第 50 轮实测抓到过：`static let` 那类写法
  改完形参、调用方不传也一样是死译文）。
* **C′（一句话只有一个出处）** `App/AppState.swift` 必须调 `LicenseLoader.summary(`，
  且**不许**再出现 `L(.licenseActive)` —— 许可状态那一句当年因为 Core 写死中文被界面抄了一份，
  而抄的那份**漂移了**（把 `.unreadable` 的原因丢掉）。判据 B 只看语言表看得见可达性，
  看不见「同一句话两个实现」这个形状。
* **D（空跑不许通过）** 语言表一个键都解析不到 / 一个键引用都没有 / 扫描到的 Swift 文件过少
  ⇒ **红**（判据取不到输入 = 假绿，本仓库踩过两次）。

## 已知局限（照实写在这里，别让下一个人以为它比实际更严）

* 只认得**字面**键与**字面**语言。**动态键**（`LocalizedStrings.text(key, …)` 里 `key` 是变量，
  如 `MCPToolCatalog` / `AICapture` 的映射表）看不见 ⇒ 它背后那些键不会被判成死键
  —— 方向是**漏判**（少报），不是误报。
* **短名取值助手这条漏判已于 L-65 第 4 批堵上**（`local_helpers`）：从前 `CALLEE_OK` 只认
  `xxxText` / `xxxCopy` 这类**带后缀的长名**，于是本仓库常见的 `t(_ key: LKey …)` /
  `text(_ key: LKey …)` **既不算「本地化取值入口」也不算引用** —— 它们背后的键在判据 B 里
  完全看不见。实测代价：`mcpNeedsApproval` 明明被 `MCPToolCatalog` 引用过，判据 B 却只看得见
  CLI 那一处（把它算成死键），修好之后也仍然算死键 ⇒ **台账里那条陈旧条目自己不会消失**。
  现在：只要被调方是**本文件里形参含 `LKey` 的函数**，就按取值入口记账（是否「写死语言」仍由
  「实参里有没有字面语言 / 函数体里有没有写死语言」判）。
* 一个键**一处引用都没有**时不判（可能是被动态引用）——同理是漏判。
* `Tests/` `TestsUISnapshot/` 不在扫描范围：那里有意构造中英两种取值。
* 台账 `maxSites` 只判「不许增」，不像 L-46 那样把减少也要求同步登记（减少只打提示）。

跑法：

    python3 Scripts/check-literal-language.py             # 接在 verify-all.sh 第 3 项里，每轮跑
    python3 Scripts/check-literal-language.py --report    # 只报「量到的现状」（做台账时用）
    python3 Scripts/test-literal-language-gate.py         # 负例（在临时副本上写坏，不碰仓库）

退出码：0 = 全过；1 = 有判据不成立（打印文件 / 行号 / 原因）。
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import shutil
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parent.parent
LEDGER = "Scripts/literal-language-dispositions.json"
KEY_TABLE = "Core/Localization.swift"
SCAN_ROOTS = ["Core", "App", "CLI", "Platform"]
MIN_SOURCE_FILES = 80

# 把字面语言传下去的形状。
LITERAL = re.compile(r"language:\s*\.(simplifiedChinese|english)\b")
# 语言表定义行：`.keyName: [.simplifiedChinese: "…", .english: "…"],`
KEY_DEF = re.compile(r"^\s*\.([A-Za-z][A-Za-z0-9_]*):\s*\[\.simplifiedChinese:")
# 本地化取值入口的形状：`L(` / `LocalizedStrings.text|format(` / `xxxText(` / `xxxCopy(`（含包装函数）。
CALLEE_OK = re.compile(
    r"^(L|LocalizedStrings\.(text|format)|[A-Za-z_][A-Za-z0-9_.]*[Tt]ext|[A-Za-z_][A-Za-z0-9_.]*[Cc]opy)$"
)
# 包装函数的形状：形参里有 `LKey`。
TAKES_KEY = re.compile(r"\bLKey\b")
FUNC_DECL = re.compile(r"\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")


def read(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8")


def line_of(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


def line_text_of(text: str, index: int) -> str:
    start = text.rfind("\n", 0, index) + 1
    end = text.find("\n", index)
    return text[start:end if end != -1 else len(text)].strip()


def balanced(text: str, open_index: int) -> int | None:
    """`open_index` 是 `(` 的位置；返回配对 `)` 的位置。"""
    depth = 0
    i = open_index
    while i < len(text):
        c = text[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return None


def enclosing_call(text: str, index: int) -> tuple[int, int] | None:
    """从 `index` 处向左找最近的未配对 `(`，连同被调名一起返回 (start, end)。"""
    depth = 0
    i = index
    while i >= 0:
        c = text[i]
        if c == ")":
            depth += 1
        elif c == "(":
            if depth == 0:
                break
            depth -= 1
        i -= 1
    else:
        return None
    if i < 0:
        return None
    end = balanced(text, i)
    if end is None:
        return None
    k = i - 1
    while k >= 0 and (text[k].isalnum() or text[k] in "._"):
        k -= 1
    return (k + 1, end)


def brace_span(text: str, open_index: int) -> int | None:
    depth = 0
    i = open_index
    while i < len(text):
        c = text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return None


def key_table(root: pathlib.Path) -> dict[str, dict]:
    """语言表：键 → {line, hasEnglish}。"""
    table: dict[str, dict] = {}
    path = root / KEY_TABLE
    if not path.exists():
        return table
    for number, line in enumerate(read(path).splitlines(), 1):
        m = KEY_DEF.match(line)
        if m:
            table[m.group(1)] = {"line": number, "hasEnglish": ".english:" in line}
    return table


def source_files(root: pathlib.Path) -> list[pathlib.Path]:
    files: list[pathlib.Path] = []
    for scan_root in SCAN_ROOTS:
        base = root / scan_root
        if base.exists():
            files.extend(sorted(base.rglob("*.swift")))
    return files


def literal_sites(rel: str, text: str) -> list[dict]:
    sites = []
    for m in LITERAL.finditer(text):
        sites.append({"file": rel, "line": line_of(text, m.start()), "text": line_text_of(text, m.start())})
    return sites


def local_helpers(text: str) -> set[str]:
    """本文件里**取本地化文案的本地函数**名字（形参里有 `LKey`）。

    为什么需要它：本仓库的取值助手常起短名（`t(_ key: LKey …)` / `text(_ key: LKey …)`），
    而 `CALLEE_OK` 认的是 `xxxText` / `xxxCopy` 这类**带后缀的长名** —— 于是这些短名助手
    一度**既不算「本地化取值入口」也不算引用**，它们背后的键在判据 B 里**完全看不见**
    （第 4 批实测：`mcpNeedsApproval` 明明有了英文会话这条可达路径，却仍被算作死键）。
    判据 B 的方向是**漏判**（少报），这里把这条漏判堵上。
    """
    names: set[str] = set()
    for m in FUNC_DECL.finditer(text):
        paren_open = m.end() - 1
        paren_close = balanced(text, paren_open)
        if paren_close is None:
            continue
        if TAKES_KEY.search(text[paren_open:paren_close]):
            names.add(m.group(1))
    return names


def wrapper_names(text: str) -> set[str]:
    """文件私有的「写死语言取值助手」：形参里有 `LKey`、函数体里出现字面语言。"""
    names: set[str] = set()
    for m in FUNC_DECL.finditer(text):
        paren_open = m.end() - 1
        paren_close = balanced(text, paren_open)
        if paren_close is None:
            continue
        params = text[paren_open:paren_close]
        if not TAKES_KEY.search(params):
            continue
        brace = text.find("{", paren_close)
        if brace == -1:
            continue
        body_end = brace_span(text, brace)
        if body_end is None:
            continue
        if LITERAL.search(text[brace:body_end]):
            names.add(m.group(1))
    return names


def key_references(rel: str, text: str, keys: dict[str, dict], wrappers: set[str]) -> list[dict]:
    helpers = local_helpers(text)
    refs: list[dict] = []
    for m in re.finditer(r"\.([A-Za-z][A-Za-z0-9_]*)\b", text):
        name = m.group(1)
        if name not in keys:
            continue
        if rel == KEY_TABLE:  # 语言表里的定义行不算引用
            continue
        call = enclosing_call(text, m.start())
        if call is None:
            continue
        segment = text[call[0]:call[1] + 1]
        callee = segment.split("(", 1)[0].strip()
        # 认两种取值入口：带后缀的长名（`LocalizedStrings.text` / `xxxText` / `xxxCopy`），
        # 以及**本文件里形参含 `LKey` 的本地函数**（`t(` / `text(` 这类短名，见 `local_helpers`）。
        if not CALLEE_OK.match(callee) and callee not in helpers:
            continue
        # 写死语言：调用点自带字面语言，或经过一个「函数体里写死语言」的文件私有助手。
        literal = bool(LITERAL.search(segment)) or callee in wrappers
        refs.append({"key": name, "file": rel, "line": line_of(text, m.start()), "literal": literal})
    return refs


def scan(root: pathlib.Path) -> dict:
    keys = key_table(root)
    files = source_files(root)
    sites: list[dict] = []
    refs: list[dict] = []
    for path in files:
        rel = path.relative_to(root).as_posix()
        text = read(path)
        sites.extend(literal_sites(rel, text))
        refs.extend(key_references(rel, text, keys, wrapper_names(text)))
    return {"keys": keys, "files": files, "sites": sites, "refs": refs}


def load_ledger(root: pathlib.Path) -> dict:
    path = root / LEDGER
    if not path.exists():
        print(f"✗ 台账不存在：{LEDGER}")
        sys.exit(1)
    return json.loads(read(path))


def check(root: pathlib.Path, report_only: bool = False) -> int:
    data = scan(root)
    keys, files, sites, refs = data["keys"], data["files"], data["sites"], data["refs"]

    if report_only:
        per_file: dict[str, int] = {}
        for site in sites:
            per_file[site["file"]] = per_file.get(site["file"], 0) + 1
        print(f"语言表键 {len(keys)} 个（带英文译文 {sum(1 for v in keys.values() if v['hasEnglish'])} 个）")
        print(f"扫描 Swift 文件 {len(files)} 个；写死语言的调用点 {len(sites)} 处")
        for name, count in sorted(per_file.items(), key=lambda kv: (-kv[1], kv[0])):
            print(f"  {count:>3}  {name}")
        dead = {}
        by_key: dict[str, list[dict]] = {}
        for ref in refs:
            by_key.setdefault(ref["key"], []).append(ref)
        for name, occ in sorted(by_key.items()):
            if not keys[name]["hasEnglish"]:
                continue
            if all(o["literal"] for o in occ):
                dead[name] = occ
        print(f"死译文（有英文译文、引用全在写死语言的入口上）：{len(dead)} 个键")
        for name, occ in sorted(dead.items()):
            where = ", ".join(f"{o['file']}:{o['line']}" for o in occ[:3])
            print(f"  .{name}  →  {where}")
        return 0

    ledger = load_ledger(root)
    failures: list[str] = []

    # 判据 D：不许空跑
    if not keys:
        failures.append(f"语言表一个键都没解析到（{KEY_TABLE}）—— 判据取不到输入，不许当通过")
    if len(files) < MIN_SOURCE_FILES:
        failures.append(f"只扫到 {len(files)} 个 Swift 文件（少于 {MIN_SOURCE_FILES}）—— 扫描根写错了吧")
    if not refs:
        failures.append("一个键引用都没有 —— 判据取不到输入，不许当通过")

    # 判据 A：写死语言的调用点逐条登记（按文件归组 + 棘轮）
    measured: dict[str, list[dict]] = {}
    for site in sites:
        measured.setdefault(site["file"], []).append(site)
    registered = {entry["file"]: entry for entry in ledger.get("files", [])}
    for name, occ in sorted(measured.items()):
        entry = registered.get(name)
        if entry is None:
            failures.append(
                f"A 未登记的写死语言调用点：{name}（{len(occ)} 处，首个在 {occ[0]['line']} 行：{occ[0]['text']}）"
                f" ⇒ 要么把语言透传，要么在台账 {LEDGER} 里登记 maxSites 与理由"
            )
            continue
        if len(occ) > entry.get("maxSites", 0):
            failures.append(
                f"A 写死语言调用点增多：{name} 实测 {len(occ)} 处 > 台账 maxSites {entry.get('maxSites')}"
                f"（第 {occ[0]['line']} 行起：{occ[0]['text']}）"
            )
    for name, entry in sorted(registered.items()):
        if name not in measured:
            if entry.get("maxSites", 0) > 0:
                failures.append(
                    f"A 台账条目陈旧：{name} 登记了 maxSites {entry.get('maxSites')}，但实测 0 处 ⇒ 把它销掉或改成 0（回归钉）"
                )
            continue
        if len(measured[name]) < entry.get("maxSites", 0):
            print(
                f"ℹ️ {name} 的写死语言调用点由 {entry.get('maxSites')} 处减到 {len(measured[name])} 处"
                f" —— 减少是好事；请顺手把台账 maxSites 调小（不判红）"
            )

    # 判据 B：死译文（双向对账）
    by_key: dict[str, list[dict]] = {}
    for ref in refs:
        by_key.setdefault(ref["key"], []).append(ref)
    measured_dead: dict[str, list[dict]] = {}
    for name, occ in by_key.items():
        if not keys[name]["hasEnglish"]:
            continue
        if all(o["literal"] for o in occ):
            measured_dead[name] = occ
    registered_dead = {entry["key"]: entry for entry in ledger.get("deadKeys", [])}
    for name, occ in sorted(measured_dead.items()):
        if name not in registered_dead:
            where = "、".join(f"{o['file']}:{o['line']}" for o in occ[:3])
            failures.append(
                f"B 新增死译文：.{name} 有英文译文却只被写死语言的入口引用（{where}）"
                f" ⇒ 把语言透传，或在台账 deadKeys 里登记理由（已登记的欠账）"
            )
    for name, entry in sorted(registered_dead.items()):
        if name not in keys:
            failures.append(f"B 台账陈旧：deadKey .{name} 在语言表里已不存在")
        elif name not in measured_dead:
            failures.append(
                f"B 台账陈旧：deadKey .{name} 现在已经可达（或不再被引用）⇒ 修好了就销账，别留成永远绿的历史"
            )

    # 判据 C：本轮修的那一族不许回退（源树判据）
    #
    # 队列 L-65 第 1 批（2026-09-28 第 48 轮）把范围从 DiagnosisContext 一族扩到
    # 许可 / 笔记正文 / 导入三处 —— 「删掉 `language:` 形参、在函数体里再写死一次」
    # 只靠判据 A 挡不住（A 量的是「写死语言的调用点」，形参被删后**调用点也不写死了**，
    # 而语言会从别的路径漏进来）。所以这三处的文本出口一律在这里钉形参。
    pinned_params = {
        "Core/DiagnosisContext.swift": [
            r"func\s+text\(language:",
            r"func\s+promptText\(language:",
            r"func\s+boundedPromptText\(language:",
            r"func\s+makeEvidence\([\s\S]{0,400}?language:\s*AppLanguage",
        ],
        "Core/DiagnosisAdvice.swift": [r"func\s+parse\([\s\S]{0,300}?language:\s*AppLanguage"],
        "Core/LicenseLoader.swift": [
            r"func\s+load\([\s\S]{0,400}?language:\s*AppLanguage",
            r"func\s+licenseDecodeFailureHint\(language:\s*AppLanguage",
            r"func\s+summary\([\s\S]{0,200}?language:\s*AppLanguage",
        ],
        "Core/NoteBody.swift": [
            r"func\s+toSpans\([^)]*language:\s*AppLanguage",
            r"func\s+exportMarkdown\([^)]*language:\s*AppLanguage",
        ],
        "Core/TableImport.swift": [
            r"func\s+copySupport\([^)]*language:\s*AppLanguage",
            r"func\s+preferredWriteMode\([^)]*language:\s*AppLanguage",
        ],
        # L-65 第 2 批（2026-09-28 第 49 轮）：SSH 隧道那族 —— 失败文案的出入口都钉在这里。
        # `describe(language:)` 是**人话的唯一出处**（`.portInUse` 只带端口号，语言只能从外面给），
        # `start(...)` 必须收 `language:`；删掉任何一个都会让语言又变成「Core 自己选」。
        "Core/SSHTunnelProcess.swift": [
            r"func\s+start\([^)]*language:\s*AppLanguage",
            r"func\s+describe\(language:\s*AppLanguage",
        ],
        # L-65 第 3 批（2026-09-28 第 50 轮）：**四族一起钉** —— AI 捕获（Ultra 侧两个出口 +
        # `stateText`）、许可展示（`static let` → 函数）、维护计划的审阅理由、MCP 会话。
        # **笔记侧（`Core/AICapture.swift`）例外**：它钉的不是 `language:` 而是**不许收语言**
        # —— 见文件末尾那段「笔记侧只收文本与标识」的负向判据。
        "Core/AICaptureUltra.swift": [
            r"func\s+diagnosisNote\([\s\S]{0,500}?language:\s*AppLanguage",
            r"func\s+maintenanceNote\([\s\S]{0,500}?language:\s*AppLanguage",
            r"func\s+stateText\([^)]*language:\s*AppLanguage",
        ],
        "Core/License.swift": [
            r"func\s+features\(language:\s*AppLanguage",
            r"func\s+items\([^)]*language:\s*AppLanguage",
        ],
        "Core/LicensePresentation.swift": [
            r"func\s+upgradeLines\([\s\S]{0,300}?language:\s*AppLanguage",
        ],
        "Core/MaintenancePlan.swift": [
            r"func\s+review\([\s\S]{0,400}?language:\s*AppLanguage",
            r"func\s+makePlan\([\s\S]{0,300}?language:\s*AppLanguage",
        ],
        "Core/MCPToolCatalog.swift": [
            r"func\s+decision\([\s\S]{0,600}?language:\s*AppLanguage",
        ],
        "Core/MCPSession.swift": [
            r"public\s+let\s+language:\s*AppLanguage",
            r"init\([\s\S]{0,200}?language:\s*AppLanguage",
        ],
    }
    for rel, patterns in pinned_params.items():
        path = root / rel
        if not path.exists():
            failures.append(f"C 文件消失：{rel}")
            continue
        text = read(path)
        for pattern in patterns:
            if not re.search(pattern, text):
                failures.append(f"C {rel} 的文本出口丢了 `language:` 形参（匹配不到：{pattern}）")
    # 判据 C（L-65 第 3/4 批）：**调用方必须把语言传下去** —— 形参留着还不够，展示点不给语言
    # 一样会退回「Core 自己选」。这里逐处找调用、在它的实参里找 `language:`。
    call_sites = {
        "App/AppState.swift": [
            "MaintenancePlanner.makePlan(",
            "AICapture.maintenanceNote(",
            "AICapture.diagnosisNote(",
        ],
        "App/Views/AboutLicenseSheet.swift": ["LicensePresentation.upgradeLines("],
        "CLI/main.swift": ["MaintenancePlanner.makePlan(", "MCPServerSession(capabilities:"],
    }
    for rel, needles in sorted(call_sites.items()):
        path = root / rel
        if not path.exists():
            failures.append(f"C 文件消失：{rel}")
            continue
        text = read(path)
        for needle in needles:
            start = text.find(needle)
            if start == -1:
                failures.append(f"C {rel} 里找不到调用点 {needle}（改名了？）")
                continue
            paren = text.find("(", start)
            end = balanced(text, paren) if paren != -1 else None
            if end is None:
                failures.append(f"C {rel} 的 {needle} 实参括号不配对 —— 判据取不到输入")
                continue
            if "language:" not in text[paren:end]:
                failures.append(
                    f"C {rel} 的 {needle} 没把语言传下去 —— Core 里那族又会退回「自己选语言」"
                )

    # 判据 C（L-65 第 3 批 · **负向的那一条**）：**笔记侧不许收语言**。
    #
    # `Core/AICapture.swift` 是笔记侧文件（要在「只有笔记」的构建里独立存在），它只许收
    # **文本与标识** —— `Scripts/check-plugin-assembly.py` 判据 03 用类型白名单把这条契约钉住。
    # 第一版把 `language: AppLanguage` 当形参加进 `skillNote`，被闭环第 10 项当场拦下。
    # 这里再钉一条负向判据，免得日后「为了省一次渲染」又把语言塞回笔记侧（那样笔记侧就会
    # 替宿主选语言，正是本判据要销掉的形状）。
    note_side = root / "Core/AICapture.swift"
    if not note_side.exists():
        failures.append("C 文件消失：Core/AICapture.swift")
    else:
        note_text = read(note_side)
        # **只看代码**：注释里会写到这条口径本身（「第一版把 `language: AppLanguage` 当形参…」），
        # 把注释算进去等于判据自己踩自己。行尾注释一律剥掉再判。
        note_code = "\n".join(line.split("//")[0] for line in note_text.splitlines())
        if re.search(r"language:\s*AppLanguage", note_code) or LITERAL.search(note_code):
            failures.append(
                "C Core/AICapture.swift 又收起了语言（`language:` 形参或字面语言）—— "
                "笔记侧只收文本与标识，语言由宿主渲染好再进来（FR-PLUG-03）"
            )
        for pattern, what in (
            (r"func\s+skillNote\([\s\S]{0,500}?defaultTag:\s*String", "skillNote(defaultTag:)"),
            (r"func\s+sqlNote\([\s\S]{0,400}?tag:\s*String", "sqlNote(tag:)"),
        ):
            if not re.search(pattern, note_text):
                failures.append(f"C Core/AICapture.swift 的出口不再收「渲染好的标签文本」（{what}）")

    panel = root / "App/Views/DiagnosisPanel.swift"
    if not panel.exists():
        failures.append("C 文件消失：App/Views/DiagnosisPanel.swift")
    elif "effectiveLanguage" not in read(panel):
        failures.append("C App/Views/DiagnosisPanel.swift 没把 effectiveLanguage 传下去（界面语言又会与提示词脱钩）")

    # C′ **「一句话只有一个出处」**（队列 L-65 收掉的那处重复实现）：许可状态那一句
    # 曾经在界面里被抄过一份（因为 Core 那份写死中文），而抄的那一份**会漂移** ——
    # 实测它已经把 `.unreadable` 的**原因丢掉**了。这里钉死：界面必须调 Core 那一份。
    app_state = root / "App/AppState.swift"
    if not app_state.exists():
        failures.append("C 文件消失：App/AppState.swift")
    else:
        text = read(app_state)
        if "LicenseLoader.summary(" not in text:
            failures.append("C App/AppState.swift 没有调 `LicenseLoader.summary(` —— 界面又自己抄了一份许可文案")
        if "L(.licenseActive)" in text:
            failures.append(
                "C App/AppState.swift 又出现 `L(.licenseActive)` —— 许可状态那一句应当只有 "
                "`LicenseLoader.summary(for:language:)` 一个出处（抄一份必然漂移）"
            )

    if failures:
        print(f"✗ 语言透传门禁不通过（{len(failures)} 条）：")
        for item in failures:
            print(f"  · {item}")
        return 1
    print(
        f"✅ 语言透传门禁通过：扫描 {len(files)} 个 Swift 文件；写死语言调用点 {len(sites)} 处"
        f"（登记 {len(registered)} 个文件）；死译文（已登记欠账）{len(registered_dead)} 个键"
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="「语言是传进来的，不是写死的」门禁（队列 L-47）")
    parser.add_argument("--report", action="store_true", help="只报量到的现状（做台账时用）")
    parser.add_argument("--root", default=None, help=argparse.SUPPRESS)
    args = parser.parse_args()
    root = pathlib.Path(args.root) if args.root else REPO
    return check(root, report_only=args.report)


if __name__ == "__main__":
    sys.exit(main())
