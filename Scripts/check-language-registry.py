#!/usr/bin/env python3
"""语言登记形状：语言知识只在登记文件里 + 登记项/标识/扩展名自洽 + 高亮色走主题令牌。

（FR-EDIT-38 ①②③④ 的机械半边，闭环第 2 项，**项数仍十八** —— 与
`check-core-portability.py` / `check-script-portability.py` 同一项：都是「Core 的形状」）

## 为什么要它

FR-EDIT-38 ① 要的口径是「**新增语言不改核心代码**」：语言定义（扩展名映射 + 关键字 /
类型 / 字面量 / 注释 / 运算符规则集）全部**声明式登记**。这句话如果只写在文档里，
两个后果会照旧发生：

1. 有人图快在词法器里加一句 `language == .html` —— 于是"有哪些语言"这件事又散回核心代码，
   下一个语言得再改一处，而**这不是崩溃、只是变笨**，没人会当场发现；
2. 有人加语言时只加标识、忘了给注释规则或字符串界定符 —— 症状是"打开某个文件一个颜色都没有"，
   同样不报错。

②的覆盖面（Alpha 2 = 常见编程语言前 10）与④（认不出如实纯文本）由
`Tests/CodeLanguageRegistryTests.swift` 逐条量；本判据管的是**形状**：知识与标识分别在
哪个文件、扩展名有没有两个主人、颜色是不是从令牌取的。

## 判据

- **A 形状禁令**：语言的**消费方**文件里不许出现"按语言身份分支"的写法
  （`language == .html` / `case .sql:` …）—— 语言知识只允许住在
  `Core/CodeLanguageDefinitions.swift`。逐处点名 `文件:行号`。
  例外/同名枚举走台账 `Scripts/language-registry-exemptions.json`（每条必须命中、
  理由不许空；死登记 / 死豁免 / 未登记的枚举一律判红）。
- **A 档的面自维护**（2026-10-14 修 · 原单 `T-20261010-048`）：声明面 `CONSUMER_FILES`
  与**盘上发现面**（`App` / `CLI` / `Core` / `Platform` 下引用 `TextLanguage` /
  `CodeLanguageDefinition` 的生产级 `.swift`）必须**同集合** —— 盘上多一份 ⇒ 判红并点名
  （新增消费者此前永远看不见），声明了盘上没有 ⇒ 死条目判红。
- **A 档的判定物分辨枚举**：命中处先解析**主体类型**（`==` 那一侧的标识符 / `case` 所属
  `switch` 的主体，类型取自同文件的参数与 `let` / `var` 声明）——解析到 `TextLanguage`
  才是身份分支；解析到别的类型（如 `CodeFormatBuiltin` 这一族「同名风格枚举」）只有
  **登记过**才放过；解析不出来按身份分支处理（宁可判红，不静默）。
- **B 登记自洽**：每条登记项必须给全（`displayName` / `fileExtensions` / `syntax`，
  且 `isCode` 为真者必须有注释规则与字符串界定符）；`TextLanguage` 的标识行与登记项
  **同集合**；一个扩展名 / 文件名只能有一个主人。
- **C 主题令牌**（③）：高亮色走 `SyntaxTone`（`Core/DesignTokens.swift` 定义、编辑器只用
  `Theme.nsColor(SyntaxTone.…)` 取），两个编辑器文件里不许出现裸色值。
- **E 默认视图的消费者唯一**（队列 `L-149` 剩余②）：登记表里声明「默认用浏览器打开」
  （`defaultView: .browser`）的语言**恰好**是 HTML；`App/` 下读 `defaultView` 的文件
  **恰好**是台账里那一个（`App/WorkspaceTabsModel.swift`，双向对账），且它必须真的把这一档
  交给浏览器那一侧（交接锚点 `openInBrowserTab`）。多一处 = 又一条自己决定「用什么打开」的路，
  将来往登记表里加类型时会被漏掉一半；一处都不读 = 口径没落地（`.html` 照旧当文本打开）。
- **D 空跑防护**：解析到的登记项数 / 标识行数 / 消费方文件数 / `App/` 文件数几条下限，低了即判红
  （正则失配 ⇒ 零命中 ⇒ 假绿，这是这类判据最经典的坏法）。
- **判据自己的证据**：`--self-test`（**16 例**）：夹具一律建在临时目录的副本上，
  写坏 ⇒ 判红且点名、还原 ⇒ 绿，末例核对真仓库逐字节未变。

## 边界（如实登记）

- A 只扫**语言消费方那一族文件**（发现面：引用语言类型的生产级文件），不是全仓扫描：
  `Core/` 里有几百个文件，全扫会把"别的事情里恰好出现的 `.go`"当成违规，假阳性多了
  判据就会被绕过。面靠**发现 + 双向对账**自维护，不再是一份写死的名单。
- A 的**类型解析是文本级**（不看类型系统）：主体名解析不出类型时**按身份分支判红**
  （fail-closed），不静默。今天本仓的 7 处命中（6 处同名风格枚举 + 1 处真阳）全部解析得出。
- 「同名风格枚举」的登记（`homonymEnums`）是**判据侧台账**，不是产品侧豁免：它只说明
  「这个枚举的 `case .x:` 不是语言身份」，不改变 `CodeFormatBuiltin` 的任何代码。
- A 剥掉注释后再匹配：判据自己的注释里会**引用**反面写法（`language == .html` 这种），
  那是说明书不是代码 —— 不剥注释的话这条判据第一个红在它自己头上。
- 视觉半边（切主题 / 切深浅后高亮真的变了）不在本判据：由设计令牌族
  （`check-design-tokens.py` / `check-design-themes.py` / `check-design-mock-tokens.py`）与
  单测承担，本判据只钉"取色的入口唯一"。

用法：
    python3 Scripts/check-language-registry.py             # 默认扫本仓
    python3 Scripts/check-language-registry.py --root DIR  # 扫 DIR（自检用）
    python3 Scripts/check-language-registry.py --self-test
"""

from __future__ import annotations

import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parent.parent
DEFINITIONS = pathlib.Path("Core/CodeLanguageDefinitions.swift")
LEDGER = pathlib.Path("Scripts/language-registry-exemptions.json")

# 语言消费方那一族（A 档的扫描面）——「谁按语言身份分支过，就是谁把知识从登记表里搬走了」。
CONSUMER_FILES = (
    "App/Views/CodeEditorView.swift",
    "App/Views/MarkdownPreviewView.swift",
    "App/WorkspaceTabsModel.swift",
    "CLI/main.swift",
    "Core/CodeCompletion.swift",
    "Core/CodeFormatting.swift",
    "Core/CodeLexer.swift",
    "Core/CodeSyntax.swift",
    "Core/MarkdownEditing.swift",
    "Core/TextLanguage.swift",
    "Core/WorkspaceSession.swift",
    "Core/WorkspaceTab.swift",
)
# 发现面（2026-10-14 修 · 原单 T-20261010-048）：这些目录下**引用语言类型**的生产级 `.swift`
# 就是「语言消费方」。声明面必须与它**同集合**（多一份 = 新增消费者没人审；少一份 = 死条目）。
FACE_DIRS = ("App", "CLI", "Core", "Platform")
FACE_TOKEN = re.compile(r"\b(?:TextLanguage|CodeLanguageDefinition)\b")
# C 档：语法色的两个取色点（编辑器）与令牌自己的定义处。
EDITOR_FILES = ("App/Views/CodeEditorView.swift", "App/Views/SQLEditorView.swift")
TOKEN_FILE = "Core/DesignTokens.swift"
TOKEN_ANCHOR = "Theme.nsColor(SyntaxTone."
BARE_COLOR = re.compile(r"NSColor\(\s*(?:calibrated|displayP3|device|sRGB)?\s*[Rr]ed\s*:|0x[0-9A-Fa-f]{6,8}\b")

# E 档：默认视图的**消费者**（队列 `L-149` 剩余②）。
#
# 「这个文件用哪种视图打开」是**登记表里的数据**（`CodeLanguageDefinition.defaultView`），
# 而**读它的地方只许有一处** —— 工作区打开文件那一步。多一处 = 又有一条路自己决定
# 「这个文件用什么打开」，于是 `.svg` / `.pdf` 这类将来进登记表的类型会被漏掉一半；
# 一处都不读 = 口径没落地（登记表里写着 `.browser`，实际还是当文本打开）。
VIEW_CONSUMER_FILES = ("App/WorkspaceTabsModel.swift",)
VIEW_CONSUMER_TOKEN = "defaultView"
VIEW_HANDOFF_ANCHOR = "openInBrowserTab"
VIEW_SOURCE_DIR = "App"
# 数据面：声明「默认用浏览器打开」的语言。今天只有 HTML（`.html` / `.htm` / `.xhtml` 同一条登记）；
# 将来多个类型就把它改成集合，判据的其余部分不用动。
BROWSER_VIEW_LANGUAGE = "html"
# 空跑防护：`App/` 下 `.swift` 的实测条数下限（扫描面被削 ⇒ 假绿）。
FLOOR_APP_FILES = 90

# 空跑防护下限（本轮实测：20 条登记 / 20 行标识 / 12 个消费方文件）。
FLOOR_DEFINITIONS = 17
FLOOR_IDENTIFIERS = 17
FLOOR_CONSUMERS = 12
FLOOR_EXTENSIONS = 30
FLOOR_ANCHORS = 6

IDENTIFIER_LINE = re.compile(r'static\s+let\s+(\w+)\s*=\s*TextLanguage\(registered:\s*"([^"]+)"\)')
DEFINITION_HEAD = re.compile(r"CodeLanguageDefinition\(\s*\.(\w+)\s*,")
DASH_LINE_COMMENT = re.compile(r"//.*$")
BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.DOTALL)


def strip_comments(text: str) -> str:
    """剥掉注释行 —— 判据自己的说明书里会**引用**反面写法（`language == .html` 是例子），
    那是给人看的，不是代码。"""
    text = BLOCK_COMMENT.sub("", text)
    return "\n".join(DASH_LINE_COMMENT.sub("", line) for line in text.splitlines())


def load_ledger(root: pathlib.Path) -> tuple[dict, list[str]]:
    """例外与「同名风格枚举」台账（`Scripts/language-registry-exemptions.json`，2026-10-14 建）。

    文件**必须在盘上**：docstring 一直声明它存在（默认空）⇒ 不在盘 = 说明书在说谎，
    且「确有必要时登记台账」这条路等于不存在。
    """
    path = root / LEDGER
    if not path.exists():
        return {"exempt": [], "homonymEnums": []}, [
            f"{LEDGER.as_posix()} 不在盘上 —— 判据 A 的例外与同名枚举登记全走它"
        ]
    payload = json.loads(path.read_text(encoding="utf-8"))
    exempt = payload.get("exempt", [])
    homonyms = payload.get("homonymEnums", [])
    problems: list[str] = []
    for index, entry in enumerate(exempt):
        for field in ("file", "snippet", "reason"):
            if not str(entry.get(field, "")).strip():
                problems.append(f"例外台账第 {index + 1} 条缺 `{field}`（理由不许空）")
    for index, entry in enumerate(homonyms):
        if not str(entry.get("type", "")).strip():
            problems.append(f"同名枚举台账第 {index + 1} 条缺 `type`")
        elif not str(entry.get("reason", "")).strip():
            problems.append(f"同名枚举台账第 {index + 1} 条（`{entry['type']}`）缺 `reason`")
    return {"exempt": exempt, "homonymEnums": homonyms}, problems


DECLARED_TYPE = re.compile(r"\b([a-z_][A-Za-z0-9_]*)\s*:\s*([A-Z][A-Za-z0-9_]*)\b")


def type_table(text: str) -> dict:
    """同文件里「标识符 → 类型」的**文本级**表（函数参数 + `:` 类型声明）。

    同名出现于多个不同类型 ⇒ 记 `None`（解析不出 ⇒ 按身份分支判红，不猜）。
    """
    seen: dict[str, set] = {}
    for head in re.finditer(r"func\s+\w+\s*\(([^)]*)\)", text, re.DOTALL):
        for name, kind in DECLARED_TYPE.findall(head.group(1)):
            seen.setdefault(name, set()).add(kind)
    for name, kind in DECLARED_TYPE.findall(text):
        seen.setdefault(name, set()).add(kind)
    return {name: (kinds.pop() if len(kinds) == 1 else None) for name, kinds in seen.items()}


def switch_subject(lines: list[str], index: int) -> str | None:
    """命中行所属 `switch` 的主体标识符（向上找最近的 `switch … {`，跳过内层花括号）。"""
    depth = 0
    for cursor in range(index - 1, -1, -1):
        head = re.match(r"^\s*switch\s+(.+?)\s*\{\s*$", lines[cursor])
        if head and depth <= 0:
            names = re.findall(r"[A-Za-z_][A-Za-z0-9_]*", head.group(1))
            return names[-1] if names else None
        depth += lines[cursor].count("}") - lines[cursor].count("{")
        if depth < 0:
            return None
    return None


def discover_consumers(root: pathlib.Path) -> list[str]:
    """盘上发现面：`FACE_DIRS` 下引用语言类型的**生产级** `.swift`。

    `Tests/` 与 `*Tests.swift`（夹具 / 单测可以拿真身份当输入）与登记文件自己
    （知识该住的地方）不算消费者。
    """
    found: list[str] = []
    for directory in FACE_DIRS:
        base = root / directory
        if not base.exists():
            continue
        for path in sorted(base.rglob("*.swift")):
            relative = path.relative_to(root).as_posix()
            if path.name.endswith("Tests.swift") or "/Tests/" in relative or relative == DEFINITIONS.as_posix():
                continue
            if FACE_TOKEN.search(strip_comments(path.read_text(encoding="utf-8"))):
                found.append(relative)
    return sorted(set(found))


def identity_patterns(identifier: str) -> tuple[str, ...]:
    escaped = re.escape(identifier)
    return (
        rf"(?:==|!=)\s*\.{escaped}\b",
        rf"\.{escaped}\b\s*(?:==|!=)",
        rf"case\s+\.{escaped}\s*:",
    )


def identity_shape(line: str, identifier: str) -> tuple[str, str] | None:
    """命中形状 + **主体**：`("eq", 另一侧标识符)` / `("case", "")`；不命中 ⇒ `None`。"""
    escaped = re.escape(identifier)
    left = re.search(rf"([A-Za-z_][A-Za-z0-9_]*)\s*(?:==|!=)\s*\.{escaped}\b", line)
    if left:
        return "eq", left.group(1)
    right = re.search(rf"\.{escaped}\b\s*(?:==|!=)\s*([A-Za-z_][A-Za-z0-9_]*)", line)
    if right:
        return "eq", right.group(1)
    if re.search(rf"case\s+\.{escaped}\s*:", line):
        return "case", ""
    return None


def reconcile_face(root: pathlib.Path) -> list[str]:
    """A 档面的**双向对账**：声明面 `CONSUMER_FILES` ↔ 盘上发现面。"""
    problems: list[str] = []
    discovered = set(discover_consumers(root))
    declared = set(CONSUMER_FILES)
    for relative in sorted(discovered - declared):
        problems.append(
            f"{relative} 引用语言类型却不在 A 档声明面里 —— 语言消费者多了一份，"
            f" 而面是一份写死的名单（把这份文件写进 `CONSUMER_FILES`）"
        )
    for relative in sorted(declared - discovered):
        problems.append(
            f"{relative} 在 A 档声明面里，但盘上不再引用语言类型 —— **死条目**"
            f"（面要跟着代码走：删掉这一行；它之前在面内也只是空转）"
        )
    return problems


def check_identity_branches(root: pathlib.Path, identifiers: list[str], ledger: dict) -> tuple[list[str], dict]:
    problems = reconcile_face(root)
    homonym_types = {str(entry["type"]) for entry in ledger["homonymEnums"] if str(entry.get("type", "")).strip()}
    stats = {"judged": 0, "exempt": 0, "homonym": 0, "scanned": 0, "exemptHit": set(), "homonymSeen": set()}
    for relative in CONSUMER_FILES:
        path = root / relative
        if not path.exists():
            problems.append(f"缺文件：{relative}（A 档声明面里的文件不在盘上）")
            continue
        stats["scanned"] += 1
        text = strip_comments(path.read_text(encoding="utf-8"))
        lines = text.splitlines()
        table = type_table(text)
        for number, line in enumerate(lines, start=1):
            for identifier in identifiers:
                shape = identity_shape(line, identifier)
                if shape is None:
                    continue
                kind, operand = shape
                if kind == "case":
                    subject = switch_subject(lines, number - 1)
                    resolved = table.get(subject) if subject else None
                    where = f"`switch {subject}`" if subject else "所属 `switch` 的主体"
                else:
                    subject = operand
                    resolved = table.get(subject)
                    where = f"`{subject}`"
                if resolved != "TextLanguage" and resolved in homonym_types:
                    stats["homonym"] += 1
                    stats["homonymSeen"].add(resolved)
                    continue
                if resolved == "TextLanguage":
                    index = next(
                        (i for i, entry in enumerate(ledger["exempt"])
                         if entry.get("file") == relative and str(entry.get("snippet", "")) in line),
                        None,
                    )
                    if index is not None:
                        stats["exempt"] += 1
                        stats["exemptHit"].add(index)
                        continue
                stats["judged"] += 1
                problems.append(
                    f"{relative}:{number} 按语言身份分支（`{identifier}`）—— {where} 解析到 "
                    f"{resolved or '未知类型'}；语言知识只允许住在 {DEFINITIONS.as_posix()}，"
                    f" 消费方要拿规则请走 `CodeLanguageDefinition`；确有必要时登记 {LEDGER.as_posix()} 并写理由"
                )
    return problems, stats


def check_definitions(root: pathlib.Path) -> tuple[list[str], dict]:
    problems: list[str] = []
    path = root / DEFINITIONS
    text = path.read_text(encoding="utf-8")
    # 只认**登记表数组里面**的条目：`fallback` 常量（兜底定义）也在本文件里，
    # 但它不是一条登记（它只是"取不到定义时给什么"），算进来会变成"重复登记 plainText"。
    marker = "private static let definitions: [CodeLanguageDefinition] = ["
    start = text.find(marker)
    end = text.find("\n    ]", start) if start >= 0 else -1
    if start < 0 or end < 0:
        problems.append(
            f"{DEFINITIONS.as_posix()} 里找不到登记表数组（`{marker}` … `    ]`）——"
            f" 结构变了：本判据靠这段文本定位登记项，找不到就判不了"
        )
        region = text
    else:
        region = text[start + len(marker):end]
    # 整行注释的登记项**不算登记**（`// CodeLanguageDefinition(` 是"注释掉一条登记"，
    # 而那种写法在文本扫描里长得和真登记一模一样 —— 不剥掉，判据就会为一条已注释的登记背书）。
    region = "\n".join(line for line in region.splitlines() if not line.strip().startswith("//"))
    if region.count("isFallback: true") != 1:
        problems.append(
            f"回落值（`isFallback: true`）必须**恰好一条**，实际 {region.count('isFallback: true')} 条"
            f"（两条 = 判语言有两个「认不出」的答案）"
        )
    identifiers = sorted({match.group(2) for match in IDENTIFIER_LINE.finditer(text)})
    heads = list(DEFINITION_HEAD.finditer(region))
    registered: list[str] = []
    browser_views: list[str] = []
    extensions: dict[str, str] = {}
    entries: dict[str, str] = {}
    extension_count = 0
    for index, head in enumerate(heads):
        end = heads[index + 1].start() if index + 1 < len(heads) else len(region)
        chunk = region[head.start():end]
        language = head.group(1)
        registered.append(language)
        # E 档：这一条登记声明了「默认用浏览器打开」吗（形状 = `defaultView: .browser`）。
        if "defaultView: .browser" in chunk:
            browser_views.append(language)
        for field in ("displayName:", "fileExtensions:", "syntax:"):
            if field not in chunk:
                problems.append(f"{DEFINITIONS.as_posix()} 的 `.{language}` 登记项缺 `{field}`")
        if "isCode: false" not in chunk:
            for field in ("comments:", "stringDelimiters:"):
                if field not in chunk:
                    problems.append(
                        f"{DEFINITIONS.as_posix()} 的 `.{language}` 是代码语言却没有 `{field}`"
                        f"（症状：识别了却一个颜色都没有）"
                    )
        for match in re.finditer(r"fileExtensions:\s*\[([^\]]*)\]", chunk, re.DOTALL):
            for file_extension in re.findall(r'"([^"]*)"', match.group(1)):
                extension_count += 1
                owner = extensions.get(file_extension)
                if owner is not None:
                    problems.append(f"扩展名 `.{file_extension}` 同时属于 `{owner}` 与 `{language}`（判语言会随表顺序变）")
                extensions[file_extension] = language
        for match in re.finditer(r"fileNames:\s*\[([^\]]*)\]", chunk, re.DOTALL):
            for file_name in re.findall(r'"([^"]*)"', match.group(1)):
                owner = entries.get(file_name)
                if owner is not None:
                    problems.append(f"文件名 `{file_name}` 同时属于 `{owner}` 与 `{language}`")
                entries[file_name] = language
    if len(set(registered)) != len(registered):
        problems.append(f"{DEFINITIONS.as_posix()} 里有重复登记的语言（{registered}）")
    if set(registered) != set(identifiers):
        problems.append(
            "语言标识与登记项不是同一个集合 ——"
            f" 只在标识里：{sorted(set(identifiers) - set(registered))}；"
            f" 只在登记里：{sorted(set(registered) - set(identifiers))}"
        )
    stats = {
        "definitions": len(registered),
        "identifiers": len(identifiers),
        "extensions": extension_count,
        "languages": registered,
        "browserViews": browser_views,
    }
    return problems, stats


def check_colors(root: pathlib.Path) -> tuple[list[str], int]:
    problems: list[str] = []
    anchor_hits = 0
    token_file = root / TOKEN_FILE
    if not token_file.exists() or "public enum SyntaxTone" not in token_file.read_text(encoding="utf-8"):
        problems.append(f"{TOKEN_FILE} 里找不到 `public enum SyntaxTone` —— 高亮色令牌的唯一定义处没了")
    for relative in EDITOR_FILES:
        path = root / relative
        if not path.exists():
            problems.append(f"缺文件：{relative}")
            continue
        for number, line in enumerate(strip_comments(path.read_text(encoding="utf-8")).splitlines(), start=1):
            anchor_hits += line.count(TOKEN_ANCHOR)
            if BARE_COLOR.search(line):
                problems.append(
                    f"{relative}:{number} 出现裸色值 —— 语法色必须走 `{TOKEN_ANCHOR}…`"
                    f"（否则切主题 / 切深浅时高亮不跟着变）"
                )
        if TOKEN_ANCHOR not in strip_comments(path.read_text(encoding="utf-8")):
            problems.append(f"{relative} 里没有取色锚点 `{TOKEN_ANCHOR}`（语法色的入口应当唯一）")
    return problems, anchor_hits


def check_default_view_consumers(root: pathlib.Path, browser_views: list[str]) -> tuple[list[str], int, int]:
    """E 档：`defaultView` 这一档数据的**双向对账**（台账 ⊆ 盘上、盘上 ⊆ 台账）。

    三个方向都要成立：
      ① 登记表里声明 `.browser` 的语言**恰好**是 `VIEW_CONSUMER_FILES` 之外的那一份数据
         （今天 = `html`）—— 声明没了 = 口径被删（`.html` 又当文本打开）；
      ② `App/` 下读 `defaultView` 的文件**恰好**是台账里那一个（双向）；
      ③ 那一个文件必须真的把这一档**接出去**（`openInBrowserTab` 交接锚点）。

    为什么钉在 `App/` 全量扫描上：这一档的坏法不是崩溃，而是「有人图快在别处写
    `if 扩展名 == \"html\"`」—— 那正是 `FR-EDIT-38` ① 要清掉的形状，且症状要等下一种
    浏览器视图类型进登记表才暴露。
    """
    problems: list[str] = []
    sources = sorted((root / VIEW_SOURCE_DIR).rglob("*.swift")) if (root / VIEW_SOURCE_DIR).exists() else []
    if not sources:
        return [f"{VIEW_SOURCE_DIR}/ 不存在 —— 扫描面被削过（空跑不许通过）"], 0, 0
    found: dict[str, list[int]] = {}
    for path in sources:
        relative = path.relative_to(root).as_posix()
        for number, line in enumerate(strip_comments(path.read_text(encoding="utf-8")).splitlines(), start=1):
            if VIEW_CONSUMER_TOKEN in line:
                found.setdefault(relative, []).append(number)
    allowed = set(VIEW_CONSUMER_FILES)
    for relative in sorted(set(found) - allowed):
        where = "、".join(f"{VIEW_CONSUMER_TOKEN}@{number}" for number in found[relative][:3])
        problems.append(
            f"{relative} 也在读 `{VIEW_CONSUMER_TOKEN}`（{where}）—— "
            f"「这个文件用哪种视图打开」只允许有一处消费者（{sorted(allowed)}）："
            f" 多一处就是又一条自己决定「用什么打开」的路（登记表里新增类型时会被漏掉一半）"
        )
    for relative in sorted(allowed - set(found)):
        problems.append(
            f"{relative} 里没有 `{VIEW_CONSUMER_TOKEN}` —— 台账登记的消费者没接上："
            f" 登记表里声明了「默认用浏览器打开」的类型会照旧当文本打开"
        )
    for relative in sorted(allowed & set(found)):
        text = strip_comments((root / relative).read_text(encoding="utf-8"))
        if VIEW_HANDOFF_ANCHOR not in text:
            problems.append(
                f"{relative} 读了 `{VIEW_CONSUMER_TOKEN}` 却没有交接锚点 `{VIEW_HANDOFF_ANCHOR}` ——"
                f" 判了却是白判（那一档没交给浏览器那一侧）"
            )
    if len(sources) < FLOOR_APP_FILES:
        problems.append(
            f"{VIEW_SOURCE_DIR}/ 下只扫到 {len(sources)} 个 `.swift`（下限 {FLOOR_APP_FILES}）——"
            f" 判据扫不到东西，不许通过"
        )
    return problems, len(sources), len(found)


def ledger_ratchets(ledger: dict, branch: dict) -> list[str]:
    """死登记棘轮：台账里登了、盘上一次都没命中 ⇒ 判红（豁免与同名枚举两本都一样）。"""
    problems: list[str] = []
    for index, entry in enumerate(ledger["exempt"]):
        if index not in branch["exemptHit"]:
            problems.append(
                f"例外台账第 {index + 1} 条（`{entry.get('file', '')}` / `{entry.get('snippet', '')}`）"
                f" 在盘上没有命中 —— **死豁免**（那处身份分支已被改写或删掉，登记要跟着收回）"
            )
    for entry in ledger["homonymEnums"]:
        kind = str(entry.get("type", "")).strip()
        if kind and kind not in branch["homonymSeen"]:
            problems.append(
                f"同名枚举台账登记的 `{kind}` 一次都没被解析到 —— **死登记**（它已不在任何命中处）"
            )
    return problems


def run(root: pathlib.Path) -> int:
    problems, stats = check_definitions(root)
    ledger, ledger_problems = load_ledger(root)
    branch_problems, branch = check_identity_branches(root, stats["languages"], ledger)
    branch_problems += ledger_ratchets(ledger, branch)
    color_problems, anchors = check_colors(root)
    view_problems, app_files, view_consumers = check_default_view_consumers(root, stats["browserViews"])
    problems += ledger_problems + branch_problems + color_problems + view_problems

    # E 档的数据面：声明「默认用浏览器打开」的语言**恰好**是 `BROWSER_VIEW_LANGUAGE`。
    # 零条 = 这一档口径被删（`.html` 又当文本打开）；多一条 = 有人往登记表里加了类型却没接消费者。
    if stats["browserViews"] != [BROWSER_VIEW_LANGUAGE]:
        problems.append(
            f"声明「默认用浏览器打开」（`defaultView: .browser`）的语言必须是 "
            f"[{BROWSER_VIEW_LANGUAGE!r}]，实际 {stats['browserViews']} ——"
            f" 少了是口径被删、多了是接了没有消费者的类型"
        )

    # D 空跑防护：正则失配 ⇒ 零命中 ⇒ 假绿，这是这类判据最经典的坏法。
    if stats["definitions"] < FLOOR_DEFINITIONS:
        problems.append(f"只解析到 {stats['definitions']} 条登记项（下限 {FLOOR_DEFINITIONS}）—— 解析失配还是登记表被掏空？")
    if stats["identifiers"] < FLOOR_IDENTIFIERS:
        problems.append(f"只解析到 {stats['identifiers']} 行语言标识（下限 {FLOOR_IDENTIFIERS}）")
    if stats["extensions"] < FLOOR_EXTENSIONS:
        problems.append(f"只解析到 {stats['extensions']} 条扩展名（下限 {FLOOR_EXTENSIONS}）")
    if branch["scanned"] < FLOOR_CONSUMERS:
        problems.append(f"只扫到 {branch['scanned']} 个语言消费方文件（下限 {FLOOR_CONSUMERS}）—— 扫描面失效")
    if anchors < FLOOR_ANCHORS:
        problems.append(f"只找到 {anchors} 处取色锚点（下限 {FLOOR_ANCHORS}）—— 语法色可能没走主题令牌")

    print(
        f"语言登记表：{stats['definitions']} 种语言 / {stats['extensions']} 条扩展名 / "
        f"A 档面 {len(CONSUMER_FILES)} 份（盘上发现 {len(discover_consumers(root))} 份，双向对账）/ "
        f"语言身份分支 {branch['judged']} 处（同名枚举命中 {branch['homonym']} 处 · 豁免 {branch['exempt']} 处）/ "
        f"取色锚点 {anchors} 处 / "
        f"默认视图消费者 {view_consumers} 个文件（扫 App {app_files} 个 .swift，浏览器档 {stats['browserViews']}）"
    )
    if problems:
        print(f"❌ 语言登记形状不通过（{len(problems)} 处）：")
        for problem in problems:
            print(f"   · {problem}")
        return 1
    print(
        f"✅ 语言登记形状通过：知识只在 {DEFINITIONS.as_posix()}，消费方 {branch['judged']} 处身份分支，取色走主题令牌，"
        f"默认视图只有一处消费者（{VIEW_CONSUMER_FILES[0]}）"
    )
    return 0


# ---------------------------------------------------------------------------
# 判据自己的证据


CASES: list[str] = [
    "消费方里出现按语言身份分支（`language == .sql`）",
    "代码语言缺注释规则（`isCode` 为真却删掉 `comments:`）",
    "两个语言抢同一个扩展名",
    "语言标识与登记项不同集合（删掉一行标识）",
    "编辑器里出现裸色值（不再走 `SyntaxTone`）",
    "登记表被掏空（全部登记项删掉）",
    "登记表里没人声明「默认用浏览器打开」（口径被删）",
    "别处也在读 `defaultView`（第二个消费者）",
    "唯一消费者没把浏览器那一档接出去（交接锚点没了）",
    "唯一消费者改成写死扩展名（不再问登记表）",
    "真仓库：判据 exit 0，且夹具前后真文件逐字节未变",
    "A 档面外多了一份消费者（新文件引用语言类型，声明面没登记）",
    "A 档面里的死条目（那份文件不再引用语言类型）",
    "同名枚举未登记（命中处解析到的枚举不在 `homonymEnums` 台账里）",
    "死豁免（台账登记的那处身份分支已不在盘上）",
    "例外与同名枚举台账文件整个不在盘上（豁免路径不存在）",
]
FIXTURE_FILES = CONSUMER_FILES + EDITOR_FILES + (
    str(DEFINITIONS.as_posix()),
    LEDGER.as_posix(),
    TOKEN_FILE,
    # E 档的唯一消费者：自检会改它，所以也要进「真仓库逐字节未变」的对照
    VIEW_CONSUMER_FILES[0],
)
STR_LEDGER = LEDGER.as_posix()
# E 档要扫**整个 `App/`**（「别处也在读」这件事只能靠全量扫描发现）⇒ 夹具得把目录一起搬。
FIXTURE_TREES = (VIEW_SOURCE_DIR,)


def snapshot(root: pathlib.Path) -> dict:
    table = {}
    for relative in FIXTURE_FILES:
        path = root / relative
        table[relative] = hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else "missing"
    return table


def build_fixture(source: pathlib.Path, target: pathlib.Path) -> None:
    for relative in FIXTURE_FILES:
        destination = target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / relative, destination)
    # E 档扫整个目录（「别处也在读」只能靠全量扫描发现）⇒ 把 `App/` 整棵搬过去。
    for tree in FIXTURE_TREES:
        shutil.copytree(source / tree, target / tree, dirs_exist_ok=True)


def mutate(root: pathlib.Path, relative: str, old: str, new: str, count: int = 1) -> None:
    path = root / relative
    text = path.read_text(encoding="utf-8")
    assert old in text, f"夹具锚点失效：{relative} 里找不到 {old!r}"
    path.write_text(text.replace(old, new, count), encoding="utf-8")


def run_self_test() -> int:
    failures: list[str] = []
    before = snapshot(REPO)
    scratch = pathlib.Path(tempfile.mkdtemp(prefix="doyah-language-registry-"))
    try:
        def fresh() -> pathlib.Path:
            target = scratch / f"case{len(failures)}{len(list(scratch.iterdir()))}"
            build_fixture(REPO, target)
            return target

        def expect_red(name: str, mutate_case) -> None:
            target = fresh()
            mutate_case(target)
            code = run(target)
            if code == 0:
                failures.append(f"例「{name}」应判红，实际 exit 0")
            print(f"   例「{name}」⇒ exit {code}")

        def expect_green(name: str) -> None:
            target = fresh()
            code = run(target)
            if code != 0:
                failures.append(f"例「{name}」应判绿，实际 exit {code}")
            print(f"   例「{name}」⇒ exit {code}")

        expect_green("干净的夹具本身必须判绿（否则后面的红都不可信）")
        expect_red(CASES[0], lambda t: mutate(t, "Core/CodeLexer.swift", "        while index < text.endIndex {",
                                              "        if language == .sql { return [] }\n        while index < text.endIndex {"))
        # CodeLexer 里没有 `language` 变量了：夹具注入的是身份判断的**形状**，判据看的就是形状。
        expect_red(CASES[1], lambda t: mutate(t, str(DEFINITIONS.as_posix()), 'comments: [CodeCommentStyle(block: "<!--", "-->")],', ""))
        expect_red(CASES[2], lambda t: mutate(t, str(DEFINITIONS.as_posix()), 'fileExtensions: ["go"],', 'fileExtensions: ["go", "js"],'))
        expect_red(CASES[3], lambda t: mutate(t, str(DEFINITIONS.as_posix()), '    public static let go = TextLanguage(registered: "go")\n', ""))
        expect_red(CASES[4], lambda t: mutate(t, "App/Views/CodeEditorView.swift",
                                              "Theme.nsColor(SyntaxTone.keyword)",
                                              "NSColor(red: 1, green: 0, blue: 0, alpha: 1)"))
        expect_red(CASES[5], lambda t: mutate(t, str(DEFINITIONS.as_posix()), "        CodeLanguageDefinition(\n", "        // CodeLanguageDefinition(\n", 999))
        # E 档（默认视图的消费者，4 例）
        expect_red(CASES[6], lambda t: mutate(t, str(DEFINITIONS.as_posix()),
                                              "            defaultView: .browser\n",
                                              "            defaultView: .editor\n"))
        expect_red(CASES[7], lambda t: mutate(t, "App/AppState.swift",
                                              "import DoyahCore",
                                              "import DoyahCore\n"
                                              "// 判据夹具：第二个消费者\n"
                                              "let _fixtureView = CodeLanguageRegistry.defaultView(forPath: \"a.html\")"))
        expect_red(CASES[8], lambda t: mutate(t, VIEW_CONSUMER_FILES[0],
                                              VIEW_HANDOFF_ANCHOR,
                                              "browserHandoffHook", 999))
        expect_red(CASES[9], lambda t: mutate(t, VIEW_CONSUMER_FILES[0],
                                              "if CodeLanguageRegistry." + VIEW_CONSUMER_TOKEN + "(forPath: path) == .browser",
                                              'if path.hasSuffix(".html")'))
        # A 档的面与判定物（2026-10-14 修 · 原单 T-20261010-048）
        expect_red(CASES[11], lambda t: (t / "Core/PlantedSurfaceConsumer.swift").write_text(
            "import Foundation\n\nfunc plantedSurface(_ language: TextLanguage) -> Bool { language == .sql }\n",
            encoding="utf-8"))
        expect_red(CASES[12], lambda t: mutate(t, "Core/WorkspaceTab.swift", "TextLanguage", "PlantedSurfaceType", 999))
        expect_red(CASES[13], lambda t: mutate(t, STR_LEDGER, '"type": "CodeFormatBuiltin"', '"type": "PlantedStyleEnum"'))
        expect_red(CASES[14], lambda t: mutate(t, STR_LEDGER, '"snippet": "language == .markdown"', '"snippet": "language == .markdownX"'))
        expect_red(CASES[15], lambda t: (t / STR_LEDGER).unlink())
        if snapshot(REPO) != before:
            failures.append("自检改动了真仓库（夹具必须只在临时副本上写坏）")
    finally:
        shutil.rmtree(scratch, ignore_errors=True)

    print(f"自检：例数 {len(CASES)} / 通过 {len(CASES) - len(failures)} / 失败 {len(failures)}")
    for failure in failures:
        print(f"   {failure}")
    return 1 if failures else 0


def main() -> int:
    arguments = sys.argv[1:]
    if "--self-test" in arguments:
        return run_self_test()
    root = REPO
    if "--root" in arguments:
        index = arguments.index("--root")
        if index + 1 >= len(arguments):
            print("❌ --root 后面要跟一个目录")
            return 2
        root = pathlib.Path(arguments[index + 1]).resolve()
        if not (root / DEFINITIONS).exists():
            print(f"❌ {root}/{DEFINITIONS.as_posix()} 不存在")
            return 2
    return run(root)


if __name__ == "__main__":
    sys.exit(main())
