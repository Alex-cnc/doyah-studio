#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""门禁：**编辑面（能编辑多行文本的那一块）的底色与字色只用主题令牌**
（队列 `L-142` 判据 · 内测清单 **甲2**，闭环第 6 项）。

由头 = 需求提出者 2026-09-30 内测原话：「**笔记的正文编辑区背景色明显不符合其他 2 个的配色方案**」
（`dist/Alpha1-内测清单-20260930.md` 甲2）。

**为什么设计令牌棘轮拦不住它**（这正是本条要补的覆盖面缺口）：
`Scripts/check-design-tokens.py` 扫的是**写坏的值**（裸颜色 / 裸字号 / 裸间距）——
而这里的问题是**什么都没写**：`TextEditor` 默认画系统的 `textBackgroundColor`，
于是同一个窗口里出现两种底（工作区是科技蓝、笔记是系统灰）。**门禁绿着、观感不对。**

**2026-10-13 升级（合册 `T-20261013-027` · 原单 `T-20261010-071` · 样本 73）** —— 判定物先说清：
- **判定物一律先剥注释与字符串**（行尾 `//`、整段块注释（含嵌套）、普通 / 多行 / 原始字符串字面量）
  ⇒ 注释里写 `NSColor.textBackgroundColor` 不再当代码（旧版「注释即代码」：一句注释就能把绿判红）；
  块注释**中间行**（不以 `*` 开头）里的 `TextEditor(` 也不再算编辑面（旧版假阳三连）。
- **编辑面标识**从「两种精确字面量」升到**结构性判定**：代码里出现 `大写开头…Editor(` 的调用，
  且名字不是 `TextEditor` / `NotesRichTextEditor` ⇒ 判红点名（旧版：别的字形完全不可见 · 假绿）。
- **判据 C 的「函数体」改用配对花括号切片**（从 `func editorSurface()` 的 `{` 配平到 `}`），
  且在**剥注释后的代码**里找令牌 ⇒「唯一出处被掏空、令牌只留在后半段注释里」不再全绿。
- **禁用令牌里的裸 `#` 收窄**：`#if` / `#available` / `#Preview` 不再假阳；真色值字面量
  （`#colorLiteral` / `#RRGGBB`）仍判红。
- **判据 B/F 的修饰链允许空行**（只以 `}` / 下一个编辑面为界），链长不再限 12 行
  ⇒ 纯排版改动不再假红；B 与 F **共用同一条链**（旧版两条口径：一个按链、一个按文件）。
- **面对账（判据 G）**：扫描面 ↔ `Package.swift` 生产 target 的 `path:` / `sources:` 对账；
  生产面里、扫描面**之外**出现编辑面标识 ⇒ 判红（旧版：面外落点静默）。
- **削面无钉**：`Scripts/editor-surface-baseline.json` 记实测读数（扫描面文件数 / 编辑面处数），
  低于基线 ⇒ 判红（删文件 / 移走视图不许静默）。

判据（七组）：
    A **台账双向对账** —— `App/`（+ 插件视图目录）下每一处多行编辑面都必须在台账里登记；
      台账里登记的每一份文件也必须在盘上真的还有编辑面（**新加编辑面要登记**）。
      **未登记字形**（结构性标识）另行判红点名。
    B **每个编辑面都挂 `.editorSurface()`** —— 且处数棘轮（挂了的处数 == 编辑面的处数）。
    C **唯一出处** —— `func editorSurface()` 只许有一处定义、必须在
      `App/Views/EditorSurface.swift`；**配对花括号切出的函数体**必须真的走令牌
      （`scrollContentBackground(.hidden)` + `Theme.surface(.content)` + `Theme.text(.primary)`），
      且**不许**出现裸色 / 系统色 / 真色值字面量（裸 `#` 已收窄，见上）。
    D **另几个编辑面（AppKit `NSTextView`）** —— 工作区代码编辑器、数据库 SQL 编辑器与笔记正文
      富文本面必须仍是「底色 = `Surface.content` / 字色 = `TextTone.primary`」，
      且**不许**退回系统底色（`NSColor.textBackgroundColor`）。
    E **空跑防护** —— 扫描面文件数 / 编辑面处数 / 台账条数三条下限 + 出处文件必须在位
      + **基线削面判红**（`Scripts/editor-surface-baseline.json`）。
    F **反面：编辑面不许自己画底色** —— 编辑面的修饰链上不许写 `background(...)` /
      `scrollContentBackground(...)`（除唯一出处）。**与 B 共用同一条链**。
    G **面对账** —— 扫描面 ↔ `Package.swift` 生产 target；生产面里、扫描面之外出现编辑面标识 ⇒ 判红。

用法：
    python3 Scripts/check-editor-surface-tokens.py                # 人读结论，失败非零退出
    python3 Scripts/check-editor-surface-tokens.py --json         # 机器读
    python3 Scripts/check-editor-surface-tokens.py --root <树>    # 负例验证用（临时副本）
    python3 Scripts/check-editor-surface-tokens.py --self-test    # 负例自检（临时副本上写坏）

判据自己的证据：`--self-test` **25 例**（红 / 绿成对，夹具一律在临时副本上，
末例核对真仓库逐字节未变 + 真仓库实跑绿）。
"""

from __future__ import annotations  # macOS 自带 python3 是 3.9，`X | None` 这类注解需要它

import argparse
import hashlib
import json
import pathlib
import posixpath
import re
import shutil
import sys
import tempfile

BASE = pathlib.Path(__file__).resolve().parent.parent

APP_DIR = "App"
# 扫描面（2026-10-13 · 概设 §7 P3 搬家）：笔记视图物理上在插件目录里，但编的是宿主模块。
SCAN_DIRS = (APP_DIR, "Plugins/Notes/Views")
# 唯一出处：编辑面的底色 / 字色只在这里写一次。
SURFACE_DEFINITION = "App/Views/EditorSurface.swift"
SURFACE_FUNCTION = "func editorSurface()"
SURFACE_MODIFIER = ".editorSurface()"
SURFACE_BODY_TOKENS = (
    "scrollContentBackground(.hidden)",      # 先决条件：不把系统底色让出来，下面那层等于没画
    "background(Theme.surface(.content))",
    "foregroundStyle(Theme.text(.primary))",
)
# 2026-10-13（合册 T-20261013-027 · 原单 T-20261010-071 ㈤）：裸 `#` 收窄。
# 旧版把一个孤零零的 `#` 也当禁用令牌 ⇒ `#if` / `#available` / `#Preview` 一律假阳；
# 收窄后仍判的是**真色值字面量**（真写死值的形态）——见下面两组模式。
SURFACE_BODY_FORBIDDEN = ("NSColor", "Color(", ".system(", "0x")
SURFACE_BODY_FORBIDDEN_PATTERNS = (
    ("#colorLiteral", r"#colorLiteral"),
    ("16 进制色值字面量 #RRGGBB", r"#[0-9A-Fa-f]{6}\b"),
)

# 多行编辑面的标识：SwiftUI 的 `TextEditor`（另几个是 AppKit `NSTextView`，见 APPKIT_SURFACES）。
# **2026-10-09（片 `WY-1b1`）**：笔记正文的编辑面从纯文本 `TextEditor` 换成富文本
# `NotesRichTextEditor`（`NSViewRepresentable` 包 `NotesTextView`）—— 它**仍是一处多行编辑面**，
# 于是加入标识集合（台账仍登记 `NotesPanel.swift`；`.`editorSurface()` 仍挂在它身上，
# 处数棘轮「挂了的处数 == 编辑面处数」保持相等）。这是一次**等量换位**，不是降门槛。
EDITOR_TOKENS = (
    "TextEditor(",
    "NotesRichTextEditor(",
)
# 报错文案里点名用的可读形态（判据口径只用上面的元组）。
EDITOR_TOKENS_LABEL = " 或 ".join(EDITOR_TOKENS)
# **结构性标识（㈢）**：代码里 `大写开头…Editor(` 的调用 —— 任何字形的多行编辑面都要看得见。
# 口径边界（如实登记）：只认「大写开头的类型名 + `Editor` 结尾 + 紧跟 `(`」，
# 且不落在定义行（`struct XEditor:`）上 ⇒ 命中 `MyMultilineEditor(`，
# 不命中 `saveNoteFromEditor(` 这类小写开头的方法调用（实测：真仓生产面 0 处误伤）。
STRUCTURAL_EDITOR_PATTERN = re.compile(r"(?<![\w.])([A-Z][A-Za-z0-9_]*Editor)\s*\(")
STRUCTURAL_KNOWN_NAMES = ("TextEditor", "NotesRichTextEditor")
STRUCTURAL_DEFINITION_PREFIXES = (
    "struct ", "class ", "enum ", "actor ", "protocol ", "extension ", "typealias ", "func ",
)
APPKIT_SURFACES = (
    "App/Views/CodeEditorView.swift",       # 工作区代码编辑器
    "App/Views/SQLEditorView.swift",        # 数据库 SQL 编辑器
    "Plugins/Notes/Views/NotesRichTextEditor.swift",  # 笔记正文富文本面（片 `WY-1b1`）
)
APPKIT_REQUIRED = (
    "backgroundColor = Theme.nsColor(Surface.content)",
    "textColor = Theme.nsColor(TextTone.primary)",
)
APPKIT_FORBIDDEN = "NSColor.textBackgroundColor"

# 台账：`App/` 下带多行编辑面的文件（**双向对账**：新加编辑面必须登记，登记的必须真的还在）。
LEDGER = (
    "App/Views/AgentSQLPanel.swift",      # 智能体 SQL 结果（可编辑回写）
    "App/Views/DataTaskPanel.swift",      # 数据任务 · 定义（FR-AGT-PLAN-PLAN-002）
    "App/Views/DataTaskSpecSheet.swift",  # 数据任务 · 规格输入
    "App/Views/DiagnosisPanel.swift",     # 诊断 · 语句 + 回答（两处）
    "App/Views/MaintenancePanel.swift",   # 维护 · 计划
    "App/Views/MCPServersSheet.swift",    # MCP 服务器 · 环境变量 / 参数（多行文本块，T6.1 补登记）
    "Plugins/Notes/Views/NotesPanel.swift",         # 笔记正文（内测 甲2 的正主）
)

# 面无基线钉（㈧ 削面无钉）：这两条下限**有实测依据**，由基线文件回读核对。
BASELINE_FILE = "Scripts/editor-surface-baseline.json"
PACKAGE_MANIFEST = "Package.swift"
MIN_APP_FILES = 115    # 实测 120（`App/` + `Plugins/Notes/Views` 下的 `.swift`）
MIN_SURFACES = 8       # 实测 8 处多行编辑面（7 处 `TextEditor(` + 1 处 `NotesRichTextEditor(`）
# 面对账（判据 G）时要跳过的目录名（构建产物 / 依赖 / 别的克隆 —— 都不是本仓的生产面）。
EXCLUDED_DIR_NAMES = (".build", ".git", ".swiftpm", ".worktrees", "dist", "node_modules", "Vendor")


def read(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8")


def rel(root: pathlib.Path, path: pathlib.Path) -> str:
    return path.relative_to(root).as_posix()


def normalize(relative: str) -> str:
    """`Package.swift` 里的路径写法归一（`./Core` / `Core/` → `Core`；`./` → `.`）。"""
    normalized = posixpath.normpath(relative)
    if normalized == ".":
        return "."
    return normalized


def is_excluded(relative: str) -> bool:
    return any(part in EXCLUDED_DIR_NAMES for part in pathlib.PurePosixPath(relative).parts)


RAW_HASH = re.compile(r"#+")


def strip_noncode(text: str) -> str:
    """把注释与字符串字面量换成空格（**保留换行、长度与行号**）：判定物只看代码。

    覆盖：行尾 / 整行 `//`、块注释 `/* … */`（Swift 允许**嵌套**）、普通字符串 `"…"`、
    多行字符串 `\"\"\"…\"\"\"`、原始字符串 `#"…"#` / `#\"\"\"…\"\"\"#`。
    这是 2026-10-13 升级的核心（㈠㈡）：旧版只认「行首 `//` / `*` / `/*`」⇒
    行尾注释与块注释中间行里的字面量 / 示例代码都当真命中（假阳三连）。
    """
    characters = list(text)
    length = len(text)

    def blank(start: int, stop: int) -> None:
        for index in range(start, min(stop, length)):
            if characters[index] != "\n":
                characters[index] = " "

    index = 0
    while index < length:
        if text.startswith("//", index):
            stop = text.find("\n", index)
            stop = length if stop < 0 else stop
            blank(index, stop)
            index = stop
            continue
        if text.startswith("/*", index):
            depth = 1
            cursor = index + 2
            while cursor < length and depth > 0:
                if text.startswith("/*", cursor):
                    depth += 1
                    cursor += 2
                elif text.startswith("*/", cursor):
                    depth -= 1
                    cursor += 2
                else:
                    cursor += 1
            blank(index, cursor)
            index = cursor
            continue
        raw = RAW_HASH.match(text, index)
        if raw and index + raw.end() < length and text[index + raw.end()] == '"':
            opening = index + raw.end()
            hashes = raw.group(0)
            if text.startswith('"""', opening):
                stop = text.find('"""' + hashes, opening + 3)
                stop = length if stop < 0 else stop + 3 + len(hashes)
            else:
                stop = text.find('"' + hashes, opening + 1)
                stop = length if stop < 0 else stop + 1 + len(hashes)
            blank(index, stop)
            index = stop
            continue
        if text.startswith('"""', index):
            stop = text.find('"""', index + 3)
            stop = length if stop < 0 else stop + 3
            blank(index, stop)
            index = stop
            continue
        if text[index] == '"':
            cursor = index + 1
            while cursor < length:
                if text[cursor] == "\\":
                    cursor += 2
                    continue
                if text[cursor] == '"':
                    cursor += 1
                    break
                if text[cursor] == "\n":   # 普通字符串不跨行（容错：到行尾为止）
                    break
                cursor += 1
            blank(index, cursor)
            index = cursor
            continue
        index += 1
    return "".join(characters)


def code_lines(text: str) -> list[str]:
    """剥注释与字符串之后的代码行（行号与原文一一对应）。"""
    return strip_noncode(text).splitlines()


def code_text(text: str) -> str:
    return "\n".join(code_lines(text))


def app_sources(root: pathlib.Path, problems: list[str]) -> dict[str, str]:
    """扫描面 = `App/` **+ 插件目录下的宿主视图**（`Plugins/Notes/Views/`，2026-10-13 · 概设 §7 P3 搬家）。

    笔记那三个视图搬进了插件目录、编的仍是宿主模块 ⇒ 按「`App/` 下每一处多行编辑面都要登记」
    这条口径，它们必须仍在本判据的扫描面里（否则台账会以「文件被搬走」判红）。
    目录不在 / 文件数低于下限 ⇒ 判红（不许悄悄缩面）。
    """
    sources: dict[str, str] = {}
    for relative in SCAN_DIRS:
        base = root / relative
        if not base.is_dir():
            problems.append(f"{relative}/ 不存在 —— 扫描面被削过（空跑不许通过）")
            continue
        sources.update({rel(root, path): read(path) for path in sorted(base.rglob("*.swift"))})
    if len(sources) < MIN_APP_FILES:
        problems.append(
            f"扫描面只有 {len(sources)} 个 `.swift`（下限 {MIN_APP_FILES}）—— 判据扫不到东西，不许通过"
        )
    return sources


def registered_sites(text: str) -> list[int]:
    """登记字形（`TextEditor(` / `NotesRichTextEditor(`）的行号（1 起）。"""
    return [
        number for number, line in enumerate(code_lines(text), 1)
        if any(token in line for token in EDITOR_TOKENS)
    ]


def editor_indicators(text: str) -> list[tuple[int, str]]:
    """该文件里的**全部**编辑面标识（登记字形 + 未登记字形）⇒ (行号, 名字)。

    判据 G（面外落点）用这一支：扫描面**之外**任何字形的编辑面都要看得见 —— 包括
    `TextEditor(` 本身（旧版只认扫描面里的两种字面量，面外落点静默）。
    """
    found: list[tuple[int, str]] = []
    for number, line in enumerate(code_lines(text), 1):
        names = [token[:-1] for token in EDITOR_TOKENS if token in line]
        stripped = line.strip()
        if stripped and not stripped.startswith(STRUCTURAL_DEFINITION_PREFIXES):
            names.extend(match.group(1) for match in STRUCTURAL_EDITOR_PATTERN.finditer(line))
        for name in dict.fromkeys(names):
            found.append((number, name))
    return found


def unregistered_sites(text: str) -> list[tuple[int, str]]:
    """**未登记字形**的编辑面（㈢）：`大写开头…Editor(` 且名字不在登记名单 ⇒ (行号, 名字)。"""
    return [
        (number, name) for number, name in editor_indicators(text)
        if name not in STRUCTURAL_KNOWN_NAMES
    ]


def surface_sites(text: str) -> list[int]:
    """该文件里的**登记字形**编辑面行号（判据 A/B 的处数口径）。"""
    return registered_sites(text)


def modifier_chain(text: str, line_number: int) -> list[tuple[int, str]]:
    """编辑面那一处往下的**修饰链**（(行号, 行)）。

    ㈥：允许空行与注释行（已剥成空白），到 `}` 或下一个编辑面为止，**不再限 12 行**
    ⇒ 纯排版改动（插空行）与长链不再假红。判据 B 与 F **共用这一条链**
    （旧版两条口径：B 按链、F 按 ±12 行窗口）。
    """
    lines = code_lines(text)
    chain: list[tuple[int, str]] = []
    for number in range(line_number + 1, len(lines) + 1):
        line = lines[number - 1]
        if any(token in line for token in EDITOR_TOKENS):
            break
        if line.strip().startswith("}"):
            break
        chain.append((number, line))
    return chain


def carries_modifier(text: str, line_number: int) -> bool:
    return any(SURFACE_MODIFIER in line for _, line in modifier_chain(text, line_number))


def paired_body(code: str, start: int) -> str | None:
    """从 `start`（函数签名首现位置）起，靠**花括号配平**取函数体（判据 C 的口径）。

    ⚠️ 必须在**剥注释 / 剥字符串**后的文本上算配平 —— 否则注释里的 `{` / `}` 会把区间截歪；
    旧版 `definition.split(SURFACE_FUNCTION, 1)[1]` 取的是「定义首现到文件尾」⇒
    函数体可以被掏空成 `self`、令牌只留在后半段注释里，判据全绿（假绿）。
    """
    opening = code.find("{", start)
    if opening < 0:
        return None
    depth = 0
    for index in range(opening, len(code)):
        if code[index] == "{":
            depth += 1
        elif code[index] == "}":
            depth -= 1
            if depth == 0:
                return code[opening + 1:index]
    return None


def forbidden_in_body(body: str) -> list[str]:
    """函数体里的禁用令牌（收窄后的口径）：裸色 / 系统色 / 色值字面量。"""
    hits = [token for token in SURFACE_BODY_FORBIDDEN if token in body]
    for label, pattern in SURFACE_BODY_FORBIDDEN_PATTERNS:
        if re.search(pattern, body):
            hits.append(label)
    return hits


# ── 判据 G：扫描面 ↔ `Package.swift` 生产 target 的对账 ────────────────────────
TARGET_PATTERN = re.compile(r"\.(target|executableTarget|testTarget)\s*\(")


def paren_block(code: str, opening: int) -> int | None:
    """配平圆括号：返回配对 `)` 的下标（在**剥注释 / 剥字符串**后的文本上算）。"""
    depth = 0
    for index in range(opening, len(code)):
        if code[index] == "(":
            depth += 1
        elif code[index] == ")":
            depth -= 1
            if depth == 0:
                return index
    return None


def swiftpm_targets(root: pathlib.Path, problems: list[str]) -> list[dict]:
    """读 `Package.swift` 的 target 面（种类 / 名字 / path / sources）。

    缺清单 ⇒ 判红：面无法与生产 target 对账（扫描面可能早已悄悄缩过）。
    取值用**原文**（剥注释那版把字符串挖空了），配平用**剥注释那版**（行号与下标对齐）。
    """
    manifest = root / PACKAGE_MANIFEST
    if not manifest.exists():
        problems.append(
            f"仓根没有 `{PACKAGE_MANIFEST}` —— 生产 target 面无法与扫描面对账（扫描面可能悄悄缩过）"
        )
        return []
    raw = read(manifest)
    code = strip_noncode(raw)
    targets: list[dict] = []
    for match in TARGET_PATTERN.finditer(code):
        stop = paren_block(code, match.end() - 1)
        if stop is None:
            continue
        block = raw[match.end() - 1:stop + 1]
        name = re.search(r'name\s*:\s*"([^"]+)"', block)
        path = re.search(r'path\s*:\s*"([^"]+)"', block)
        sources = re.search(r"sources\s*:\s*\[([^\]]*)\]", block)
        targets.append({
            "kind": match.group(1),
            "name": name.group(1) if name else "?",
            "path": path.group(1) if path else ".",
            "sources": re.findall(r'"([^"]+)"', sources.group(1)) if sources else [],
        })
    return targets


def production_dirs(targets: list[dict]) -> list[str]:
    """生产面（非测试 target）= `sources:` 展开（相对 `path:`）；无 `sources:` 则取 `path:`。"""
    directories: list[str] = []
    for target in targets:
        if target["kind"] == "testTarget":
            continue
        base = target["path"]
        if target["sources"]:
            directories.extend(normalize(posixpath.join(base, source)) for source in target["sources"])
        else:
            directories.append(normalize(base))
    return sorted(set(directories))


def covers(directory: str, relative: str) -> bool:
    """`directory` 是否覆盖 `relative`（相等 / 包含；`.` 覆盖一切）。"""
    if directory == ".":
        return True
    return relative == directory or relative.startswith(directory + "/")


def overlaps_scan(directory: str) -> bool:
    return any(covers(directory, scan) or covers(scan, directory) for scan in SCAN_DIRS)


def load_baseline(root: pathlib.Path, problems: list[str]) -> dict:
    """面无基线钉（㈧）：读数（扫描面文件数 / 编辑面处数）记在基线文件里，掉到基线之下即判红。"""
    path = root / BASELINE_FILE
    if not path.exists():
        problems.append(
            f"`{BASELINE_FILE}` 不在盘上 —— 面无基线钉（删文件 / 移走视图不许静默；"
            "改法 = 如实更新该文件里的实测读数并在提交信息里写明）"
        )
        return {}
    try:
        data = json.loads(read(path))
    except Exception as error:      # noqa: BLE001 —— 台账读不动也算判红（不许静默）
        problems.append(f"`{BASELINE_FILE}` 读不动（{error}）—— 基线钉失效")
        return {}
    if not isinstance(data, dict):
        problems.append(f"`{BASELINE_FILE}` 的形状不对（要一个对象）")
        return {}
    return data


def check(root: pathlib.Path) -> tuple[list[str], list[str]]:
    problems: list[str] = []
    notes: list[str] = []
    sources = app_sources(root, problems)
    baseline = load_baseline(root, problems)

    # ── A 台账双向对账（+ 未登记字形）───────────────────────────────────────
    # 唯一出处文件自己不算「编辑面」（它只定义写法；用法示例写在注释里，剥注释后也不数）。
    on_disk = {
        name: surface_sites(text) for name, text in sources.items()
        if name != SURFACE_DEFINITION and surface_sites(text)
    }
    for name in LEDGER:
        if name not in sources:
            problems.append(f"台账登记的编辑面 `{name}` 不在扫描面里 —— 文件被搬走 / 改名（台账陈旧）")
        elif name not in on_disk:
            problems.append(
                f"台账登记的编辑面 `{name}` 里找不到 `{EDITOR_TOKENS_LABEL}` —— 编辑面被搬走（台账陈旧）"
            )
    for name in sorted(on_disk):
        if name not in LEDGER:
            where = ", ".join(str(number) for number in on_disk[name])
            problems.append(
                f"`{name}`:{where} 出现 `{EDITOR_TOKENS_LABEL}` —— 这是个**没登记**的编辑面"
                "（新加编辑面要登记进本判据的台账，并挂 `.editorSurface()`）"
            )
    # ㈢ 未登记字形：任何字形的多行编辑面都必须看得见（旧版只认两种精确字面量 ⇒ 别的字形假绿）。
    for name, text in sorted(sources.items()):
        for number, identifier in unregistered_sites(text):
            problems.append(
                f"`{name}`:{number} 出现编辑面标识 `{identifier}(` —— 这不是本判据登记的两种字形"
                f"（`{EDITOR_TOKENS_LABEL}`）：它要么登记进台账并挂 `{SURFACE_MODIFIER}`，"
                "要么改名成登记字形（旧版这种字形完全看不见）"
            )

    # ── B 每个编辑面都挂 `.editorSurface()` + 处数棘轮 ──────────────────────
    sites = 0
    wired = 0
    for name, numbers in sorted(on_disk.items()):
        text = sources[name]
        for number in numbers:
            sites += 1
            if carries_modifier(text, number):
                wired += 1
            else:
                problems.append(
                    f"`{name}`:{number} 的 `{EDITOR_TOKENS_LABEL}` 没挂 `{SURFACE_MODIFIER}`"
                    " —— 它会画系统底色（`textBackgroundColor`），与另两个编辑面对不上（内测 甲2）"
                )
    modifier_count = sum(
        sum(1 for line in code_lines(text) if SURFACE_MODIFIER in line) for text in sources.values()
    )
    if modifier_count != sites:
        problems.append(
            f"`.editorSurface()` 用了 {modifier_count} 处，编辑面 {sites} 处 —— 两边的处数必须相等"
            "（多出来的是挂到了非编辑面上，少了的在上面逐处点名）"
        )
    if sites < MIN_SURFACES:
        problems.append(f"编辑面只有 {sites} 处（下限 {MIN_SURFACES}）—— 判据空转，不许通过")
    else:
        notes.append(f"编辑面 {sites} 处，全部挂了 `.editorSurface()`（台账 {len(LEDGER)} 份文件）")

    # ── C 唯一出处（配对花括号取函数体 + 收窄后的禁用令牌）──────────────────
    if SURFACE_DEFINITION not in sources:
        problems.append(f"`{SURFACE_DEFINITION}` 不在扫描面里 —— 编辑面底色的唯一出处不见了")
    else:
        definition = sources[SURFACE_DEFINITION]
        code = strip_noncode(definition)
        start = code.find(SURFACE_FUNCTION)
        if start < 0:
            problems.append(f"`{SURFACE_DEFINITION}` 里找不到 `{SURFACE_FUNCTION}` —— 出处被改名 / 被掏空")
        else:
            body = paired_body(code, start)
            if body is None:
                problems.append(
                    f"`{SURFACE_DEFINITION}` 的 `{SURFACE_FUNCTION}` 花括号不配平 —— 取不到函数体"
                    "（出处必须是一个正常闭合的函数）"
                )
            else:
                missing = [token for token in SURFACE_BODY_TOKENS if token not in body]
                forbidden = forbidden_in_body(body)
                for token in missing:
                    problems.append(
                        f"`{SURFACE_DEFINITION}` 的**函数体里**缺 `{token}`"
                        "（口径写歪了 —— 令牌被删 / 被搬到注释或函数外都不算在位）"
                    )
                for token in forbidden:
                    problems.append(
                        f"`{SURFACE_DEFINITION}` 的函数体里出现 `{token}` —— 出处自己写死值 / 走系统色"
                        "（令牌口径：底色 `Surface.content` / 字色 `TextTone.primary`）"
                    )
                if not missing and not forbidden:
                    notes.append(
                        f"唯一出处 = `{SURFACE_DEFINITION}`（配对函数体里三个令牌全在，无裸值）"
                    )
    for name, text in sorted(sources.items()):
        if name != SURFACE_DEFINITION and SURFACE_FUNCTION in strip_noncode(text):
            problems.append(f"`{name}` 里也定义了 `{SURFACE_FUNCTION}` —— 编辑面底色只能有一处出处")

    # ── D 另几个编辑面（AppKit）─────────────────────────────────────────────
    for name in APPKIT_SURFACES:
        if name not in sources:
            problems.append(f"`{name}` 不在扫描面里 —— 这个编辑面的底色判据悬空了")
            continue
        text = code_text(sources[name])
        for token in APPKIT_REQUIRED:
            if token not in text:
                problems.append(f"`{name}` 里找不到 `{token}` —— 这个编辑面不再走令牌（与另两个对不上）")
        if APPKIT_FORBIDDEN in text:
            problems.append(f"`{name}` 里出现 `{APPKIT_FORBIDDEN}` —— 编辑面退回系统底色（内测 甲2 的原病）")
    if all(name in sources for name in APPKIT_SURFACES) and not any(
        APPKIT_FORBIDDEN in code_text(sources[name]) for name in APPKIT_SURFACES
    ):
        notes.append("AppKit 三个编辑面：底色 `Surface.content` / 字色 `TextTone.primary` 在位")

    # ── F 编辑面不许自己画底色（与 B 共用同一条链）───────────────────────────
    for name, numbers in sorted(on_disk.items()):
        text = sources[name]
        for number in numbers:
            for offset, line in modifier_chain(text, number):
                stripped = line.strip()
                if ".background(" in stripped or "scrollContentBackground(" in stripped:
                    problems.append(
                        f"`{name}`:{offset} 在编辑面的修饰链上写 `{stripped}`"
                        " —— 底色只许由 `.editorSurface()` 给（唯一出处）"
                    )

    # ── G 面对账：扫描面 ↔ `Package.swift` 生产 target；面外标识判红 ──────────
    targets = swiftpm_targets(root, problems)
    directories = production_dirs(targets)
    test_dirs = [target["path"] for target in targets if target["kind"] == "testTarget"]
    for scan in SCAN_DIRS:
        if not any(covers(directory, scan) for directory in directories):
            problems.append(
                f"扫描面 `{scan}/` 不在任何生产 target 的面里（`{PACKAGE_MANIFEST}` 对不上）"
                " —— 面与 target 必须对账，不许各说各话"
            )
    outside = 0
    for directory in directories:
        if overlaps_scan(directory):
            continue
        base = root / directory
        if not base.is_dir():
            problems.append(f"生产 target 的面 `{directory}` 不在盘上 —— 这个目录整个消失了（空跑）")
            continue
        for path in sorted(base.rglob("*.swift")):
            relative = rel(root, path)
            if is_excluded(relative) or any(covers(test, relative) for test in test_dirs):
                continue
            for number, identifier in editor_indicators(read(path)):
                problems.append(
                    f"`{relative}`:{number} 出现编辑面标识 `{identifier}(` —— 它在扫描面"
                    f"（{ ' + '.join(SCAN_DIRS) }）**之外**：编辑面底色的口径只在这两个面里判，"
                    "面外落点不许静默（真要放就把它纳入扫描面并登记台账）"
                )
                outside += 1
    if not outside and directories:
        notes.append(
            f"生产 target 面 {len(directories)} 个（与扫描面对账通过：面外无编辑面标识）"
        )

    # ── E 空跑防护 / 削面无钉 ───────────────────────────────────────────────
    if baseline:
        floor_files = int(baseline.get("files", 0))
        floor_surfaces = int(baseline.get("surfaces", 0))
        if len(sources) < floor_files:
            problems.append(
                f"扫描面 {len(sources)} 个 `.swift` < 基线 {floor_files} —— 面被削过"
                f"（删文件 / 移走视图都要如实更新 `{BASELINE_FILE}`，不许静默缩面）"
            )
        if sites < floor_surfaces:
            problems.append(
                f"编辑面 {sites} 处 < 基线 {floor_surfaces} —— 编辑面被削过（同上）"
            )

    notes.append(f"扫描面 App/ {len(sources)} 个 `.swift`；台账 {len(LEDGER)} 份文件")
    return problems, notes


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true", help="机器读")
    parser.add_argument("--root", default=str(BASE), help="仓库根（负例验证用）")
    parser.add_argument("--self-test", action="store_true", dest="self_test", help="负例自检")
    args = parser.parse_args()

    root = pathlib.Path(args.root).resolve()
    if args.self_test:
        return self_test(root)

    problems, notes = check(root)
    if args.json:
        print(json.dumps({"problems": problems, "notes": notes}, ensure_ascii=False, indent=2))
        return 1 if problems else 0

    for note in notes:
        print(f"  ℹ️ {note}")
    if problems:
        print(f"\n❌ 编辑面底色 / 字色门禁未通过（{len(problems)} 项）：")
        for problem in problems:
            print(f"   - {problem}")
        return 1
    print(
        "\n✅ 编辑面的底色与字色只用主题令牌：每处多行编辑面都挂 `.editorSurface()` · "
        f"唯一出处 = `{SURFACE_DEFINITION}`（`Surface.content` / `TextTone.primary`）· "
        "AppKit 三个编辑面仍是令牌色 · 台账双向对账通过 · 面与生产 target 对账通过 · 判据面在位"
    )
    return 0


# ── 负例自检 ────────────────────────────────────────────────────────────────
#
# 纪律：一律在**临时副本**上写坏，末例核对真仓库逐字节未变。
# 每个负例都要问一句「这条改动如果真发生了，判据会不会当场报红」——
# 报不出来，这门禁就只是文档。

WATCHED = (
    SURFACE_DEFINITION,
    "Plugins/Notes/Views/NotesPanel.swift",
    "App/Views/MaintenancePanel.swift",
    "App/Views/CodeEditorView.swift",
    "App/Views/SQLEditorView.swift",
    "App/Views/AppearanceSheet.swift",   # 无关文件：证明「改别的不会误报」
    BASELINE_FILE,
    PACKAGE_MANIFEST,
)


def _sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _fixture(destination: pathlib.Path, root: pathlib.Path) -> pathlib.Path:
    """把**判据面**复制成一份临时副本。

    除了扫描面目录（带文件），还要：① 判据要读的清单 / 基线（`Package.swift`、
    `Scripts/editor-surface-baseline.json`）；② 生产 target 的**面外目录**（建**空的** ——
    判据 G 要能看见「目录在盘上、里面没东西」，这样「面外落点」那条负例才成立）。
    """
    for relative in SCAN_DIRS:
        source = root / relative
        if not source.is_dir():
            continue
        for path in sorted(source.rglob("*")):
            if not path.is_file():
                continue
            target = destination / relative / path.relative_to(source)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
    for relative in (PACKAGE_MANIFEST, BASELINE_FILE):
        source = root / relative
        if source.is_file():
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    for directory in production_dirs(swiftpm_targets(root, [])):
        if overlaps_scan(directory):
            continue
        (destination / directory).mkdir(parents=True, exist_ok=True)
    return destination


def _patch(path: pathlib.Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise AssertionError(f"夹具写坏失败：`{old}` 不在 {path.name} 里")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def _write(path: pathlib.Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def _append(path: pathlib.Path, text: str) -> None:
    _write(path, path.read_text(encoding="utf-8") + text)


def _messages(root: pathlib.Path) -> list[str]:
    return check(root)[0]


def _names(root: pathlib.Path, needle: str) -> bool:
    """报红并且**点名**（合册口径：反例要判红 + 指名，不许只红不说哪里）。"""
    return any(needle in message for message in _messages(root))


def self_test(root: pathlib.Path) -> int:
    before = {name: _sha(root / name) for name in WATCHED if (root / name).exists()}
    cases: list[tuple[str, bool]] = []   # (名字, 期望成立)
    with tempfile.TemporaryDirectory(prefix="doyah-editor-surface-") as tmp:
        workspace = pathlib.Path(tmp)

        def fresh(name: str) -> pathlib.Path:
            return _fixture(workspace / name, root)

        # ① 绿：真仓库的副本，判据必须全过
        green = fresh("green")
        cases.append(("绿对照：真仓库副本应全过", not _messages(green)))

        # ② 红：笔记正文那一处退回去（内测 甲2 的原病：编辑面画系统底色）
        unwired = fresh("notes-unwired")
        _patch(
            unwired / "Plugins/Notes/Views/NotesPanel.swift",
            "                .editorSurface()\n",
            "",
        )
        cases.append(("笔记正文的编辑面退回系统底色", bool(_messages(unwired))))

        # ③ 红：新加一个**没登记**的编辑面
        new_surface = fresh("new-surface")
        _patch(
            new_surface / "App/Views/AppearanceSheet.swift",
            "    var body: some View {",
            "    var body: some View {\n        TextEditor(text: .constant(\"\"))",
        )
        cases.append(("新加未登记的编辑面", bool(_messages(new_surface))))

        # ④ 红：台账登记的文件里编辑面被搬走（陈旧台账）
        stale = fresh("stale-ledger")
        _patch(
            stale / "App/Views/MaintenancePanel.swift",
            "            TextEditor(text: $appState.maintenancePlanText)\n",
            "            Text(\"搬走了\")\n",
        )
        cases.append(("台账登记的编辑面被搬走", bool(_messages(stale))))

        # ⑤ 红：唯一出处被改名
        renamed = fresh("renamed")
        _patch(
            renamed / SURFACE_DEFINITION,
            SURFACE_FUNCTION,
            "func editorSurfaceRenamed()",
        )
        cases.append(("唯一出处被改名", bool(_messages(renamed))))

        # ⑥ 红：第二处定义（绕开唯一出处）
        duplicate = fresh("duplicate")
        _patch(
            duplicate / "App/Views/AppearanceSheet.swift",
            "    var body: some View {",
            "    func editorSurface() -> some View { self }\n\n    var body: some View {",
        )
        cases.append(("第二处定义 .editorSurface()", bool(_messages(duplicate))))

        # ⑦ 红：出处自己写死裸色
        bare = fresh("bare-color")
        _patch(
            bare / SURFACE_DEFINITION,
            ".background(Theme.surface(.content))",
            ".background(Color.gray)",
        )
        cases.append(("出处里把底色换成裸色", bool(_messages(bare))))

        # ⑧ 红：出处把系统底色那层让位那一步删掉（画了等于没画）
        no_hidden = fresh("no-hidden")
        _patch(
            no_hidden / SURFACE_DEFINITION,
            "            .scrollContentBackground(.hidden)\n",
            "",
        )
        cases.append(("出处缺 scrollContentBackground(.hidden)", bool(_messages(no_hidden))))

        # ⑨⑩ 红：AppKit 那两个编辑面不再走令牌 / 退回系统底色
        appkit = fresh("appkit-notoken")
        _patch(
            appkit / "App/Views/SQLEditorView.swift",
            "        textView.backgroundColor = Theme.nsColor(Surface.content)",
            "        textView.backgroundColor = NSColor.textBackgroundColor",
        )
        cases.append(("SQL 编辑器退回系统底色", bool(_messages(appkit))))

        workspace_editor = fresh("workspace-editor-notoken")
        _patch(
            workspace_editor / "App/Views/CodeEditorView.swift",
            "        textView.textColor = Theme.nsColor(TextTone.primary)",
            "        textView.textColor = .labelColor",
        )
        cases.append(("工作区编辑器字色不再走令牌", bool(_messages(workspace_editor))))

        # ⑪ 红：编辑面自己画底色（绕开唯一出处）
        self_paint = fresh("self-paint")
        _patch(
            self_paint / "Plugins/Notes/Views/NotesPanel.swift",
            "                .editorSurface()\n",
            "                .editorSurface()\n                .background(Color.orange)\n",
        )
        cases.append(("编辑面自己再画一层底色", bool(_messages(self_paint))))

        # ⑫ 绿：无关文件改动不误报 + 末例
        unrelated = fresh("unrelated")
        _patch(unrelated / "App/Views/AppearanceSheet.swift", "import SwiftUI", "import SwiftUI\n// 无关改动")
        cases.append(("绿对照：无关文件改动不误报", not _messages(unrelated)))

        # ⑬ 末例：真仓库逐字节未变 + 真仓库实跑绿
        after = {name: _sha(root / name) for name in WATCHED if (root / name).exists()}
        untouched = after == before
        real_problems, _ = check(root)
        cases.append(("末例：真仓库逐字节未变且实跑绿", untouched and not real_problems))

        # ⑭⑮ ㈠ 行尾注释不当代码（绿）／同一处真写代码（红，话术不变）
        tail_comment = fresh("tail-comment")
        _append(
            tail_comment / "App/Views/CodeEditorView.swift",
            "let p73 = 0 // legacy: textView.backgroundColor = NSColor.textBackgroundColor\n",
        )
        cases.append((
            "㈠ 行尾注释里的禁用令牌不判红",
            not _messages(tail_comment),
        ))

        tail_code = fresh("tail-code")
        _append(
            tail_code / "App/Views/CodeEditorView.swift",
            "let p73b = 0; textView.backgroundColor = NSColor.textBackgroundColor\n",
        )
        cases.append((
            "㈠ 对照臂：同一处真写代码仍判红并点名",
            _names(tail_code, APPKIT_FORBIDDEN),
        ))

        # ⑯ ㈡ 块注释**中间行**里的 `TextEditor(`（绿：不再算编辑面）
        block_comment = fresh("block-comment")
        _append(
            block_comment / "App/Views/AppearanceSheet.swift",
            "/*\nTextEditor(text: .constant(\"\"))\n*/\n",
        )
        cases.append((
            "㈡ 块注释中间行里的 TextEditor( 不算编辑面",
            not _messages(block_comment),
        ))

        # ⑰ ㈢ 未登记字形的多行编辑面（红 + 点名标识）
        exotic = fresh("exotic-editor")
        _write(
            exotic / "App/Views/Extra73.swift",
            "import SwiftUI\n\nstruct Extra73: View {\n"
            "    var body: some View {\n"
            "        MyMultilineEditor(text: .constant(\"\"))\n"
            "            .editorSurface()\n"
            "    }\n}\n",
        )
        cases.append((
            "㈢ 未登记字形的编辑面判红并点名",
            _names(exotic, "MyMultilineEditor("),
        ))

        # ⑱ ㈤ 定义之后追加 `#if` / `#available` / `#Preview`（绿：不再假阳）
        hash_syntax = fresh("hash-syntax")
        _patch(
            hash_syntax / SURFACE_DEFINITION,
            "            .foregroundStyle(Theme.text(.primary))\n",
            "            .foregroundStyle(Theme.text(.primary))\n"
            "#if os(macOS)\n"
            "            .opacity(1)\n"
            "#endif\n",
        )
        _append(
            hash_syntax / SURFACE_DEFINITION,
            "\n@available(macOS 14, *)\n#Preview {\n    EmptyView()\n}\n",
        )
        cases.append((
            "㈤ 函数体内 #if 与文件尾 #Preview 不判红",
            not _messages(hash_syntax),
        ))

        # ⑲ ㈣ 函数体被掏空、令牌只留在后半段注释里（红 + 点名缺哪个令牌）
        hollow = fresh("hollow-body")
        _patch(
            hollow / SURFACE_DEFINITION,
            "            .scrollContentBackground(.hidden)\n"
            "            .background(Theme.surface(.content))\n"
            "            .foregroundStyle(Theme.text(.primary))\n",
            "            .padding(0)\n",
        )
        _append(
            hollow / SURFACE_DEFINITION,
            "\n// 口径备忘（示例，不是代码）：\n"
            "//   .scrollContentBackground(.hidden)\n"
            "//   .background(Theme.surface(.content))\n"
            "//   .foregroundStyle(Theme.text(.primary))\n",
        )
        cases.append((
            "㈣ 函数体掏空（令牌只在注释里）判红并点名",
            _names(hollow, "函数体里**缺 `scrollContentBackground(.hidden)`"),
        ))

        # ⑳ ㈤ 对照臂：函数体里真出现 `.system(` 裸色（红）
        system_color = fresh("system-color")
        _patch(
            system_color / SURFACE_DEFINITION,
            ".background(Theme.surface(.content))",
            ".background(Color.system(.gray))",
        )
        cases.append((
            "㈤ 对照臂：函数体里真写 Color( / .system( 仍判红",
            _names(system_color, "`.system(`"),
        ))

        # ㉑ ㈥ 编辑面与 `.editorSurface()` 之间插空行（绿）
        blank_line = fresh("blank-line")
        _patch(
            blank_line / "Plugins/Notes/Views/NotesPanel.swift",
            "                )\n                    .font(Theme.font(.mono))\n",
            "                )\n\n                    .font(Theme.font(.mono))\n",
        )
        cases.append((
            "㈥ 修饰链里插空行不判红",
            not _messages(blank_line),
        ))

        # ㉒ ㈥ 修饰链超 12 行（绿：链长不再截断）
        long_chain = fresh("long-chain")
        _patch(
            long_chain / "Plugins/Notes/Views/NotesPanel.swift",
            "                )\n                    .font(Theme.font(.mono))\n",
            "                )\n" + "\n" * 14 + "                    .font(Theme.font(.mono))\n",
        )
        cases.append((
            "㈥ 修饰链超 12 行不判红",
            not _messages(long_chain),
        ))

        # ㉓ ㈦ 生产面里、扫描面之外的编辑面落点（红 + 点名文件）
        outside = fresh("outside-scan")
        _write(
            outside / "Platform/macOS/Extra73.swift",
            "import SwiftUI\n\nstruct Extra73: View {\n"
            "    var body: some View {\n"
            "        TextEditor(text: .constant(\"\"))\n"
            "    }\n}\n",
        )
        cases.append((
            "㈦ 扫描面之外的编辑面落点判红并点名",
            _names(outside, "Platform/macOS/Extra73.swift"),
        ))

        # ㉔ ㈧ 削面无钉：删掉扫描面里一份文件（红 + 点名基线）
        cut = fresh("cut-surface")
        # 先把**夹具自己**的基线钉在夹具当前读数上，再删一份 —— 这一例只判「删了就红」，
        # 不受真仓文件数变化影响（真仓基线是棘轮，别轮次会让真仓读数长过基线 ⇒ 旧写法会假绿）。
        measured = sum(1 for directory in SCAN_DIRS for _ in (cut / directory).rglob("*.swift"))
        (cut / BASELINE_FILE).write_text(
            json.dumps({"files": measured, "surfaces": 0,
                        "note": "自检夹具：这一例只判「删文件 ⇒ 红」那一轴"}, ensure_ascii=False),
            encoding="utf-8")
        (cut / "App/Views/AppearanceSheet.swift").unlink()
        cases.append((
            "㈧ 扫描面被削（删文件）判红并点名基线",
            _names(cut, BASELINE_FILE),
        ))

        # ㉕ ㈦/E 扫描面目录整个不见了（红：空跑防护）
        no_dir = fresh("no-scan-dir")
        shutil.rmtree(no_dir / APP_DIR)
        cases.append((
            "扫描面目录不存在判红（空跑防护）",
            _names(no_dir, f"{APP_DIR}/ 不存在"),
        ))

    passed = 0
    for name, ok in cases:
        print(f"{'✅' if ok else '❌'} {name}")
        passed += 1 if ok else 0
    ok = passed == len(cases)
    print(f"{'✅' if ok else '❌'} 负例自检：{len(cases)} 条中 {passed} 条达到预期")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
