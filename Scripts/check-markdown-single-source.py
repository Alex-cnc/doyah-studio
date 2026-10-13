#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""门禁：**Markdown 解析只有一份，预览只许消费它**（队列 `L-137` 判据 ⑤，闭环第 10 项）。

**为什么有它**：需求提出者 2026-09-30 要「工作区的编辑器还要带 markdown 预览功能」，而这条路线上
有一个**必然的诱惑**：预览要有标题 / 列表 / 表格 / 代码块，最快的做法是再写一套块级解析
（或者引一个第三方渲染库）。一旦那样做，这个仓里就会有两套 Markdown 口径 ——
同一份 `**粗体**` 在笔记里是粗体、在预览里是星号，而且**编译照过、单测照绿**，
没有任何东西看得见（本仓「判据要落在结果状态上」那一族的典型形状）。

所以把「只有一份」变成机械判据：

  ① **行内解析唯一**：`nextMarker`（行内标记扫描器）与 `linkMarker`（链接扫描器）都只许在
     `Plugins/Notes/Sources/NoteBody.swift` 里出现 —— 别处命中即红（那是第二套行内解析的入口）；一处都没有也红
     （扫描面被削过 / 判据空转）。行内标记清单那一个字面量（``["`", "**", "*", "["]``）同理**只许一份**（判的是**集合**：换个函数名、把清单换序，同样是第二份行内解析）。
     链接扫描器是 2026-10-01（第 146 轮，队列 `L-137` 剩余③）补进来的：链接与粗体一样是**笔记侧
     那一份解析**的产物，别处再写一套链接解析就是同一族的病。
  ② **块级模型只有一个产地**：`MarkdownBlock(` 的构造只许在 `Core/MarkdownDocument.swift` ——
     `App/` / `Platform/` / `CLI/` 里出现即红（界面只渲染模型，不许自己造块：
     造块就等于在自己那份里重新决定「什么算标题」）。
  ③ **预览必须真同源**：`Core/MarkdownDocument.swift` 里必须**真的调用**笔记侧那个函数
     （`NoteBodyProjection.parseInline(` 至少 4 处：标题 / 段落 / 表格 / 列表）。
     只写注释说「复用」不算 —— 这条判的是调用点（**注释与字符串抹掉之后再数**）。
  ④ **不引第三方 Markdown**：家规是「不引第三方」（笔记存储引擎当年就是这么定的）。
     `import` 行与依赖声明里不得出现 MarkdownUI / swift-markdown / SwiftyMarkdown /
     MarkdownKit / Ink / Down / cmark 这类标识。
  ⑤ **判据在位（空跑防护）**：扫描面文件数、块构造处数、同源调用处数、解析层用例数四条下限 ——
     把模型掏空、把用例删光、把扫描面削掉，都必须报红而不是「零命中 = 通过」。

  ⑥ **面只许跟声明面**（2026-10-13 合册 `T-20261013-027` · 原单 `T-20261010-062`）：
     扫描面 = `Package.swift` 现读的**生产 target 源码目录** + 解析层用例目录；
     生产 target 的源码目录落在面外 ⇒ 红（面外回流没人管 —— 原单 ㈤ 的 `Tools/LicenseTool`
     就是从这个洞回来的）。

**这条门禁保护的不是代码，是一个口径**：Markdown → 文档模型**只有一处**。
笔记侧是权威源（`Q8` 已拍板不接受第二套解析），工作区预览只是**第二个消费者**。

用法：
    python3 Scripts/check-markdown-single-source.py              # 人读结论，失败非零退出
    python3 Scripts/check-markdown-single-source.py --json       # 机器读
    python3 Scripts/check-markdown-single-source.py --root <树>  # 负例验证用（临时副本）
    python3 Scripts/check-markdown-single-source.py --self-test  # 负例自检（临时副本上写坏）
"""

from __future__ import annotations  # macOS 自带 python3 是 3.9，`X | None` 这类注解需要它

import argparse
import hashlib
import json
import pathlib
import re
import shutil
import sys
import tempfile

BASE = pathlib.Path(__file__).resolve().parent.parent

INLINE_OWNER = "Plugins/Notes/Sources/NoteBody.swift"
BLOCK_OWNER = "Core/MarkdownDocument.swift"
PARSE_TESTS = "Tests/MarkdownDocumentTests.swift"

INLINE_SCANNER = "nextMarker"
LINK_SCANNER = "linkMarker"
INLINE_MARKER_LIST = '["`", "**", "*", "["]'
BLOCK_CONSTRUCTOR = "MarkdownBlock("
SHARED_INLINE_CALL = "NoteBodyProjection.parseInline("
BLOCK_CALL = re.compile(r"\bMarkdownBlock\s*\(")
SHARED_CALL = re.compile(r"\bNoteBodyProjection\.parseInline\s*\(")

# **面**（扫描面）= 生产 target 的源码目录（`Package.swift` **现读**，见 `package_targets`）
# + 解析层用例目录。2026-10-13（合册 `T-20261013-027` · 原单 `T-20261010-062`）改了两处：
#   · `Platform` → `Platform/macOS`（真正的 target 目录；对侧的 watchos / windows 源码
#     不再混进「macOS 产品面」—— 与 `-068` 那一族同口径）；
#   · **补上 `Tools/LicenseTool`** —— 它是唯一一个面外生产根，原单 ㈤ 的 P6 就是从那个洞回流的。
PACKAGE = "Package.swift"
FACE_TARGETS = ("DoyahCore", "DoyahPlatform", "DoyahCLI", "doyah-license-tool", "DoyahStudioApp")
TESTS_DIR = "Tests"
# 面里允许出现、但**不是**生产 target 源码目录的根（登记 + 理由；理由为空 ⇒ 判红）
FACE_ROOTS_REGISTERED = {
    TESTS_DIR: "解析层用例面（testTarget `DoyahCoreTests` 的 `path:`）",
}
SCAN_DIRS = ("Core", "App", "Platform/macOS", "CLI",
             "Plugins/Notes/Sources", "Plugins/Notes/Views", "Tools/LicenseTool")
DEPENDENCY_FILES = ("Package.swift", "project.yml")


FORBIDDEN_PACKAGES = (
    "MarkdownUI",
    "swift-markdown",
    "SwiftyMarkdown",
    "MarkdownKit",
    "MarkdownView",
    "Ink",
    "Down",
    "cmark",
)

# 空跑防护下限（**实测值**写在括号里；低于下限 ⇒ 判红，防「扫描面被削掉 ⇒ 零命中 = 通过」）
# 2026-10-13 订正（原单 ㈥ 登记的三处陈旧读数）：449/7/21 → 今日实测。
MIN_SCANNED_FILES = 200          # 实测 585（Core 214 / App 119 / Platform/macOS 5 / CLI 4 /
                                 #   Plugins/Notes/Sources 21 / Plugins/Notes/Views 3 /
                                 #   Tools/LicenseTool 1 / Tests 218）
MIN_BLOCK_CONSTRUCTIONS = 6      # 实测 9（标题 / 分隔线 / 代码块 / 引用 / 段落 / 表格 / 三种列表）
MIN_SHARED_INLINE_CALLS = 4      # 实测 6（标题 / 段落 / 表格表头 / 表格行 / 三种列表条目）—— 剥注释后的**真调用点**
MIN_PARSE_TESTS = 36             # 实测 36（棘轮余量归零：原写 15 ⇒ 21 例可被空壳静默抽空，原单 ㈣）
MIN_ASSERTED_TESTS = 36          # 同一条的下半：**非空且带断言**的用例数（`func testStub() {}` 不算用例）


def strip_comments(text: str) -> str:
    """把注释抹成**等长空格**（字符串感知、支持块注释嵌套）。

    为什么自己扫而不是上正则：Swift 里 `"// 不是注释"` 是字符串、`/* /* 嵌套 */ */` 合法，
    一行正则两面都会判错。等长替换的额外好处是**下标可比**（行号与列位都不动）。
    字符串字面量**按原样保留** —— 本判据的判定物里就有字符串里的记号
    （行内标记清单 `["`", "**", "*", "["]`），抹掉字符串就看不出它是哪一份。
    """
    out: list[str] = []
    index = 0
    length = len(text)
    in_line = False
    depth = 0
    in_string = False
    escaped = False
    while index < length:
        char = text[index]
        following = text[index + 1] if index + 1 < length else ""
        if in_line:
            out.append("\n" if char == "\n" else " ")
            in_line = char != "\n"
        elif depth > 0:
            if char == "*" and following == "/":
                depth -= 1
                out.append("  ")
                index += 2
                continue
            if char == "/" and following == "*":
                depth += 1
                out.append("  ")
                index += 2
                continue
            out.append("\n" if char == "\n" else " ")
        elif in_string:
            out.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
        elif char == '"':
            in_string = True
            out.append(char)
        elif char == "/" and following == "/":
            in_line = True
            out.append("  ")
            index += 2
            continue
        elif char == "/" and following == "*":
            depth = 1
            out.append("  ")
            index += 2
            continue
        else:
            out.append(char)
        index += 1
    return "".join(out)


def blank_strings(text: str) -> str:
    """把字符串字面量的**内容**抹成等长空格（引号本身留着）。

    用途 = 「名字不出本文件」与「真调用点」两条：一句 `print("nextMarker 是我")`
    不是第二套解析，一行注释里的 `NoteBodyProjection.parseInline(` 也不是调用点
    （原单 ㈠ 的假阳 / ㈢ 的假绿都长在这里）。等长 ⇒ 行号仍与原文件一一对应。
    """
    out: list[str] = []
    index = 0
    length = len(text)
    in_string = False
    escaped = False
    while index < length:
        char = text[index]
        if in_string:
            if char == "\n":
                out.append("\n")
            elif escaped:
                out.append(" ")
                escaped = False
            elif char == "\\":
                out.append(" ")
                escaped = True
            elif char == '"':
                out.append('"')
                in_string = False
            else:
                out.append(" ")
        elif char == '"':
            in_string = True
            out.append('"')
        else:
            out.append(char)
        index += 1
    return "".join(out)


MARKER_TOKENS = ("`", "**", "*", "[")
_STRING_RUN = re.compile(r'"(?:[^"\\\n]|\\.)*"(?:\s*,\s*"(?:[^"\\\n]|\\.)*")+')


def marker_token_count(text: str) -> int:
    """这段代码里**最像行内标记清单**的一处字符串序列认得出几个记号。

    为什么按「相邻字符串序列」而不是按 `[...]`：清单本身写成
    `["`", "**", "*", "["]` —— 里面那个 `"["` 会让按方括号配对的扫法当场断掉
    （原单 ㈣ 的现场就是「换个函数名 + 把清单换序」；清单换序后精确字面量不再命中，
    所以这条判的是**集合**：认得出 ≥3 个记号就是第二份行内标记清单）。
    """
    best = 0
    for match in _STRING_RUN.finditer(text):
        elements = re.findall(r'"((?:[^"\\\n]|\\.)*)"', match.group(0))
        best = max(best, sum(1 for element in elements if element in MARKER_TOKENS))
    return best


def _test_bodies(text: str) -> list[tuple[str, str]]:
    """`func testXxx(` 及其函数体（花括号配对、字符串感知 —— 显示名里的括号不算）。"""
    found: list[tuple[str, str]] = []
    for match in re.finditer(r"func\s+(test\w+)\s*\(", text):
        start = text.find("{", match.end())
        if start < 0:
            continue
        depth = 0
        in_string = False
        escaped = False
        index = start
        while index < len(text):
            char = text[index]
            if in_string:
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == '"':
                    in_string = False
            elif char == '"':
                in_string = True
            elif char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    break
            index += 1
        found.append((match.group(1), text[start:index + 1]))
    return found


def _blocks(text: str, opener: str) -> list[str]:
    """取 `opener` 起的那一整段（**按括号配对走、字符串里的括号不算**）。"""
    found: list[str] = []
    index = 0
    while True:
        at = text.find(opener, index)
        if at < 0:
            return found
        index = at + len(opener)
        depth = 0
        in_string = False
        escaped = False
        for position in range(at + len(opener) - 1, len(text)):
            char = text[position]
            if in_string:
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == '"':
                    in_string = False
                continue
            if char == '"':
                in_string = True
            elif char in "([":
                depth += 1
            elif char in ")]":
                depth -= 1
                if depth == 0:
                    found.append(text[at:position + 1])
                    index = position + 1
                    break
        else:
            return found


def package_test_targets(root: pathlib.Path) -> set[str]:
    """包清单里用 `.testTarget(` 声明的 target 名（只有它们归「测试面」那条登记）。"""
    path = root / PACKAGE
    if not path.exists():
        return set()
    code = strip_comments(path.read_text(encoding="utf-8"))
    names: set[str] = set()
    for block in _blocks(code, ".testTarget("):
        name = re.search(r'name:\s*"([^"]+)"', block)
        if name:
            names.add(name.group(1))
    return names


def package_targets(root: pathlib.Path) -> dict[str, list[str]] | None:
    """包清单**现读**每个 target 的源码目录（面 = 声明面，不是判据手抄的清单）。"""
    path = root / PACKAGE
    if not path.exists():
        return None
    code = strip_comments(path.read_text(encoding="utf-8"))
    targets: dict[str, list[str]] = {}
    for opener in (".target(", ".executableTarget(", ".testTarget("):
        for block in _blocks(code, opener):
            name = re.search(r'name:\s*"([^"]+)"', block)
            if not name:
                continue
            base = re.search(r'path:\s*"([^"]+)"', block)
            sources = re.search(r"sources:\s*\[([^\]]*)\]", block)
            prefix = "" if base is None or base.group(1) == "." else base.group(1) + "/"
            if sources:
                dirs = [prefix + item.strip().strip('"')
                        for item in sources.group(1).split(",") if item.strip()]
            elif base is not None and base.group(1) != ".":
                dirs = [base.group(1)]
            else:
                dirs = [name.group(1)]
            targets.setdefault(name.group(1), []).extend(dirs)
    return targets


def read(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8")


def rel(root: pathlib.Path, path: pathlib.Path) -> str:
    return path.relative_to(root).as_posix()


def swift_sources(root: pathlib.Path, problems: list[str]) -> dict[str, str]:
    """扫描面：实现层四个目录 + `Tests/` 的全部 `.swift`。**目录不在 ⇒ 判红**（不许悄悄缩面）。"""
    sources: dict[str, str] = {}
    for dirname in SCAN_DIRS + (TESTS_DIR,):
        base = root / dirname
        if not base.is_dir():
            problems.append(f"{dirname}/ 不存在 —— 扫描面被削过（空跑不许通过）")
            continue
        for path in sorted(base.rglob("*.swift")):
            sources[rel(root, path)] = read(path)
    return sources


def count(text: str, needle: str) -> int:
    return text.count(needle)


def check(root: pathlib.Path) -> tuple[list[str], list[str]]:
    problems: list[str] = []
    notes: list[str] = []
    sources = swift_sources(root, problems)
    # **判定物一律在代码上判**：注释抹成等长空格（原单 ㈠ 假阳 / ㈢ 假绿的根）。
    # 字符串**内容**抹掉的那一层（`bare`）只给「名字不出本文件」与「真调用点」两条用 ——
    # 行内标记清单那类判定物本身写在字符串里，抹掉就看不出它是哪一份（见 `MARKER_TOKENS`）。
    code = {name: strip_comments(text) for name, text in sources.items()}
    bare = {name: blank_strings(text) for name, text in code.items()}

    if len(sources) < MIN_SCANNED_FILES:
        problems.append(
            f"扫描面只有 {len(sources)} 个 `.swift`（下限 {MIN_SCANNED_FILES}）—— 判据扫不到东西，不许通过"
        )

    # ⓪ 面与 `Package.swift` 现读对账（原单 ㈤：面外生产根 = 唯一的静默回流口）
    targets = package_targets(root)
    production: list[str] = []
    if targets is None:
        problems.append(f"`{PACKAGE}` 不在盘上 / 读不出 target —— 面对账没有输入，不许当通过")
    else:
        test_targets = package_test_targets(root)
        for name in FACE_TARGETS:
            if name not in targets:
                problems.append(f"面里点名的 target 在包清单里找不到：`{name}`")
        for name, directories in sorted(targets.items()):
            if name in test_targets:
                continue          # 测试面归 `TESTS_DIR` 那条登记，不算生产面
            for directory in directories:
                if directory not in production:
                    production.append(directory)
        outside = [directory for directory in production
                   if not any(directory == scan or directory.startswith(scan + "/")
                              for scan in SCAN_DIRS)]
        if outside:
            problems.append(
                f"生产 target 的源码目录落在判据面外：{outside} —— 面外回流没人管"
                "（该根要么进 SCAN_DIRS、要么登记理由）"
            )
        unknown = [scan for scan in SCAN_DIRS
                   if not any(directory == scan or directory.startswith(scan + "/")
                              for directory in production)]
        if unknown:
            problems.append(f"判据面里有既不是生产 target 源码目录、又没登记理由的根：{unknown}")
        for registered, reason in FACE_ROOTS_REGISTERED.items():
            if registered not in SCAN_DIRS and registered != TESTS_DIR:
                problems.append(f"登记的面外根 `{registered}` 根本不在扫描面上 —— 死登记")
            elif not reason.strip():
                problems.append(f"登记的面外根 `{registered}` **理由为空** —— 空理由不是理由")
        notes.append(
            f"面与 `{PACKAGE}` 对账一致：生产 target 源码目录 {len(production)} 个 · "
            f"判据面 {len(SCAN_DIRS) + len(FACE_ROOTS_REGISTERED)} 根 · 扫到 {len(sources)} 份 `.swift`"
        )

    # ① 行内解析唯一（两条：**定义**只有一处且在本仓笔记侧；**名字**不许出现在别处）
    definition = re.compile(rf"func\s+{INLINE_SCANNER}\s*\(")
    definition_owners = sorted(name for name, text in code.items() if definition.search(text))
    stray_inline = [name for name in sorted(bare)
                    if name != INLINE_OWNER and re.search(rf"\b{INLINE_SCANNER}\b", bare[name])]
    if definition_owners != [INLINE_OWNER]:
        problems.append(
            f"`{INLINE_SCANNER}` 的**定义**必须是且只是 `{INLINE_OWNER}` 里的一处，"
            f"实测 {definition_owners or '一处都没有'} —— 一处都没有 = 扫描面被削过 / 判据空转"
        )
    if stray_inline:
        # 名字出现在别处 = 有人在别处调用或重写了行内扫描 → 第二套解析的入口
        problems.append(
            f"`{INLINE_SCANNER}` 的名字出现在 `{INLINE_OWNER}` 以外的地方：{stray_inline}"
            " —— 行内解析只许有一处，别处出现即红"
        )
    if definition_owners == [INLINE_OWNER] and not stray_inline:
        notes.append(f"行内标记扫描器 `{INLINE_SCANNER}`：唯一定义在 `{INLINE_OWNER}`，名字不出本文件")
    # ①b **链接扫描器同理**（2026-10-01 第 146 轮补，队列 `L-137` 剩余③）：定义唯一 + 名字不出本文件。
    link_definition = re.compile(rf"func\s+{LINK_SCANNER}\s*\(")
    link_definition_owners = sorted(name for name, text in code.items() if link_definition.search(text))
    if link_definition_owners != [INLINE_OWNER]:
        problems.append(
            f"`{LINK_SCANNER}` 的**定义**必须是且只是 `{INLINE_OWNER}` 里的一处，"
            f"实测 {link_definition_owners or '一处都没有'} —— 链接目标的生产只许一处（一处都没有 = 判据空转）"
        )
    stray_link_scanners = [
        name for name in sorted(bare)
        if name != INLINE_OWNER and re.search(rf"\b{LINK_SCANNER}\b", bare[name])
    ]
    if stray_link_scanners:
        problems.append(
            f"`{LINK_SCANNER}` 的名字出现在 `{INLINE_OWNER}` 以外的地方：{stray_link_scanners}"
            " —— 链接解析只许有一处，别处出现即红（链接与粗体同一条口径）"
        )
    if link_definition_owners == [INLINE_OWNER] and not stray_link_scanners:
        notes.append(f"链接扫描器 `{LINK_SCANNER}`：唯一定义在 `{INLINE_OWNER}`，名字不出本文件")

    marker_list_owners = sorted(name for name, text in code.items() if INLINE_MARKER_LIST in text)
    if marker_list_owners != [INLINE_OWNER]:
        problems.append(
            f"行内标记清单 `{INLINE_MARKER_LIST}` 只许在 `{INLINE_OWNER}` 里出现一次，"
            f"实测落点 {marker_list_owners or '什么都没有'}"
        )
    stray_marker_lists = [name for name in sorted(code)
                          if name != INLINE_OWNER and marker_token_count(code[name]) >= 3]
    if stray_marker_lists:
        problems.append(
            f"{stray_marker_lists}：别处又写了一份行内标记**集合** —— 判的是集合不是那串字面量："
            "换个函数名、把清单换序同样是第二套解析（原单 ㈡ / ㈣）"
        )
    if marker_token_count(code.get(INLINE_OWNER, "")) < 3:
        problems.append(
            f"`{INLINE_OWNER}` 里的行内标记清单认不出记号（<3）—— 清单被搬走 / 判据空转"
        )

    # ② 块级模型只有一个产地（**名字与括号之间的空白无关** —— 原单 ㈡ 的形状逃逸）
    block_owners = sorted(name for name, text in code.items() if BLOCK_CALL.search(text))
    stray_blocks = [name for name in block_owners if name != BLOCK_OWNER]
    if stray_blocks:
        problems.append(
            f"{', '.join(stray_blocks)}：自己构造了 `{BLOCK_CONSTRUCTOR}` —— "
            "块级模型只许由契约层产出，界面 / 平台层只许渲染"
        )
    if BLOCK_OWNER not in block_owners:
        problems.append(f"`{BLOCK_OWNER}` 不存在或没有再构造任何块 —— 模型被掏空 / 判据空转")
    else:
        constructions = len(BLOCK_CALL.findall(code[BLOCK_OWNER]))
        if constructions < MIN_BLOCK_CONSTRUCTIONS:
            problems.append(
                f"`{BLOCK_OWNER}` 只构造了 {constructions} 处块（下限 {MIN_BLOCK_CONSTRUCTIONS}）—— 模型被掏空"
            )
        else:
            notes.append(f"块级模型唯一产地 `{BLOCK_OWNER}`：{constructions} 处构造")

    # ③ 预览必须真同源（判的是**调用点** —— 注释与字符串里的字面量不算，原单 ㈢）
    if BLOCK_OWNER not in bare:
        problems.append(f"`{BLOCK_OWNER}` 不在扫描面里 —— 同源判据无从谈起")
    else:
        shared_calls = len(SHARED_CALL.findall(bare[BLOCK_OWNER]))
        if shared_calls < MIN_SHARED_INLINE_CALLS:
            problems.append(
                f"`{BLOCK_OWNER}` 里只有 {shared_calls} 处调用 `{SHARED_INLINE_CALL}`（下限 "
                f"{MIN_SHARED_INLINE_CALLS}）—— 「复用笔记侧解析」只活在注释里"
            )
        else:
            notes.append(f"同源调用：`{BLOCK_OWNER}` 调 `{SHARED_INLINE_CALL}` {shared_calls} 处")

    # ④ 不引第三方 Markdown
    for name in sorted(sources):
        text = sources[name]
        for line_number, line in enumerate(text.splitlines(), 1):
            match = re.match(r"\s*import\s+(?:struct\s+|class\s+|enum\s+|func\s+)?(\w+)", line)
            if not match:
                continue
            module = match.group(1)
            for package in FORBIDDEN_PACKAGES:
                if module.lower() == package.lower().replace("-", ""):
                    problems.append(f"{name}:{line_number}: `import {module}` —— 家规不引第三方 Markdown 解析")
    for name in DEPENDENCY_FILES:
        path = root / name
        if not path.exists():
            continue
        for line_number, line in enumerate(read(path).splitlines(), 1):
            lowered = line.lower()
            if ".package(" not in lowered and "url:" not in lowered:
                continue
            for package in FORBIDDEN_PACKAGES:
                # 词边界匹配：`down` 不许命中 `download`、`ink` 不许命中 `link`（依赖行里这两种词很常见）。
                token = package.lower()
                if re.search(rf"(?<![a-z0-9]){re.escape(token)}(?![a-z0-9])", lowered) or \
                        re.search(rf"(?<![a-z0-9]){re.escape(token.replace('-', ''))}(?![a-z0-9])", lowered):
                    problems.append(
                        f"{name}:{line_number}: 依赖里出现 Markdown 解析库 `{package}` —— 家规不引第三方"
                    )

    # ⑤ 判据在位（空跑防护的另一半：解析层用例必须存在、且**非空带断言** —— 原单 ㈣）
    tests_path = root / PARSE_TESTS
    if not tests_path.exists():
        problems.append(f"`{PARSE_TESTS}` 不在 —— 块级模型没有任何单测钉着")
    else:
        tests_code = strip_comments(read(tests_path))
        bodies = _test_bodies(tests_code)
        case_count = len(bodies)
        asserted = [name for name, body in bodies
                    if body.strip("{} \n\t") and re.search(r"XCTAssert|#expect|#require", body)]
        if case_count < MIN_PARSE_TESTS:
            problems.append(f"`{PARSE_TESTS}` 只有 {case_count} 个用例（下限 {MIN_PARSE_TESTS}）—— 用例被删过")
        elif len(asserted) < MIN_ASSERTED_TESTS:
            problems.append(
                f"`{PARSE_TESTS}` 的 {case_count} 个用例里只有 {len(asserted)} 个**非空且带断言**"
                f"（下限 {MIN_ASSERTED_TESTS}）—— 空壳用例不算用例（原单 ㈣：40 个空壳 `func testStubN`）"
            )
        else:
            notes.append(f"解析层用例：`{PARSE_TESTS}` {case_count} 个")
        if SHARED_INLINE_CALL not in tests_code:
            problems.append(
                f"`{PARSE_TESTS}` 里没有一条「与笔记侧同一函数」的断言 —— 同源口径没人钉住"
            )

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
        print(f"\n❌ Markdown 单一口径门禁未通过（{len(problems)} 项）：")
        for problem in problems:
            print(f"   - {problem}")
        return 1
    print(
        "\n✅ Markdown 解析只有一份：行内扫描器与链接扫描器都唯一（笔记侧）· 块级模型唯一产地（契约层）· "
        "预览真的调用同一个行内函数 · 无第三方 Markdown 解析库 · 判据面在位"
    )
    return 0


# ── 负例自检 ────────────────────────────────────────────────────────────────
#
# 纪律：一律在**临时副本**上写坏，末例核对真仓库逐字节未变。
# 每个负例都要问一句「这条改动如果真发生了，判据会不会当场报红」——
# 报不出来的话，这门禁就只是文档。

WATCHED = (
    INLINE_OWNER,
    BLOCK_OWNER,
    PARSE_TESTS,
    "Package.swift",
    "project.yml",
    "Tools/LicenseTool/main.swift",
    "Core/AppError.swift",   # 随便挑一个无关文件：证明「无关文件改了不误报」
)


def _sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _fixture(destination: pathlib.Path, root: pathlib.Path) -> pathlib.Path:
    """把扫描面（四个实现目录 + Tests + 依赖清单）复制成一份临时副本。"""
    for dirname in SCAN_DIRS + (TESTS_DIR,):
        source = root / dirname
        if not source.is_dir():
            continue
        target = destination / dirname
        target.mkdir(parents=True, exist_ok=True)
        for path in sorted(source.rglob("*.swift")):
            relative = path.relative_to(source)
            (target / relative).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target / relative)
    for name in DEPENDENCY_FILES:
        source = root / name
        if source.exists():
            shutil.copy2(source, destination / name)
    return destination


def _patch(path: pathlib.Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise AssertionError(f"夹具写坏失败：`{old}` 不在 {path.name} 里")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def self_test(root: pathlib.Path) -> int:
    before = {name: _sha(root / name) for name in WATCHED if (root / name).exists()}
    cases: list[tuple[str, bool]] = []   # (名字, 期望报红)
    with tempfile.TemporaryDirectory(prefix="doyah-md-single-") as tmp:
        workspace = pathlib.Path(tmp)

        def fresh(name: str) -> pathlib.Path:
            return _fixture(workspace / name, root)

        # ① 绿：真仓库的副本，判据必须全过
        green = fresh("green")
        green_problems, _ = check(green)
        cases.append(("绿对照：真仓库副本应全过", not green_problems))

        # ② 红：预览侧又写了一份行内扫描器（这一族缺陷的标准形状）
        duplicate = fresh("inline-duplicate")
        (duplicate / "App/Views").mkdir(parents=True, exist_ok=True)
        (duplicate / "App/Views/MarkdownPreview.swift").write_text(
            "import Foundation\n\n/// 预览自己扫行内标记（本门禁必须抓住它）\n"
            "func scan(text: String) -> Bool { text.contains(\"**\") }\n"
            "private func nextMarker(in text: Substring) -> Int? { nil }\n",
            encoding="utf-8",
        )
        cases.append(("行内扫描器出现第二份", bool(check(duplicate)[0])))

        # ③ 红：行内扫描器被掏空（定义没了 ⇒ 判据空转，也必须红）
        hollow_inline = fresh("inline-hollow")
        _patch(hollow_inline / INLINE_OWNER, "    private static func nextMarker(in text: Substring)",
               "    private static func removedMarker(in text: Substring)")
        cases.append(("行内扫描器定义被删", bool(check(hollow_inline)[0])))

        # ④ 红：界面自己造块（绕过契约层）
        stray = fresh("block-stray")
        (stray / "App/Views").mkdir(parents=True, exist_ok=True)
        (stray / "App/Views/MarkdownPreview.swift").write_text(
            "import Foundation\n\nfunc makeBlock() -> MarkdownBlock { MarkdownBlock(kind: .thematicBreak, sourceLine: 1) }\n",
            encoding="utf-8",
        )
        cases.append(("界面自己构造块", bool(check(stray)[0])))

        # ⑤ 红：块级模型被掏空
        hollow_block = fresh("block-hollow")
        text = (hollow_block / BLOCK_OWNER).read_text(encoding="utf-8")
        text = re.sub(r"MarkdownBlock\(kind:", "MarkdownBlockX(kind:", text)
        # 这里曾有一句「把全角空格删掉」的 replace（注释写「让 diff 更明显」）—— L-119 扫出它是
        # **空转注入**：`Core/MarkdownDocument.swift` 里全角空格 0 处，那次改写一个字节都没动，
        # 而本例照样报绿。装饰性动作不算证据：承重的是上一行的 rename，已删（行为逐字不变）。
        (hollow_block / BLOCK_OWNER).write_text(text, encoding="utf-8")
        cases.append(("块级模型被掏空", bool(check(hollow_block)[0])))

        # ⑥ 红：同源调用被删（预览不再复用笔记侧的行内函数）
        unsourced = fresh("shared-calls")
        text = (unsourced / BLOCK_OWNER).read_text(encoding="utf-8")
        text = text.replace(SHARED_INLINE_CALL, "Self.localInline(")
        (unsourced / BLOCK_OWNER).write_text(text, encoding="utf-8")
        cases.append(("同源调用被删", bool(check(unsourced)[0])))

        # ⑦ 红：引入第三方 Markdown 库（import 行）
        third_party = fresh("third-party-import")
        _patch(third_party / "Core/AppError.swift", "import Foundation", "import Foundation\nimport MarkdownUI")
        cases.append(("引入第三方 Markdown 库（import）", bool(check(third_party)[0])))

        # ⑧ 红：依赖清单里加第三方 Markdown 包
        third_party_dep = fresh("third-party-dependency")
        text = (third_party_dep / "Package.swift").read_text(encoding="utf-8")
        text = text.replace(
            "        .package(path: \"Vendor/sqlite3\"),",
            "        .package(path: \"Vendor/sqlite3\"),\n"
            "        .package(url: \"https://github.com/gonzalezreal/swift-markdown-ui\", from: \"2.0.0\"),",
            1,
        )
        (third_party_dep / "Package.swift").write_text(text, encoding="utf-8")
        cases.append(("依赖清单里加第三方 Markdown 包", bool(check(third_party_dep)[0])))

        # ⑨ 红：解析层用例被删
        no_tests = fresh("no-tests")
        (no_tests / PARSE_TESTS).unlink()
        cases.append(("解析层用例文件被删", bool(check(no_tests)[0])))

        # ⑩ 红：用例被掏空成壳（文件在、一个用例都没有）
        hollow_tests = fresh("hollow-tests")
        text = (hollow_tests / PARSE_TESTS).read_text(encoding="utf-8")
        text = re.sub(r"\n\s*func test", "\n    func removed", text)
        (hollow_tests / PARSE_TESTS).write_text(text, encoding="utf-8")
        cases.append(("解析层用例被掏空", bool(check(hollow_tests)[0])))

        # ⑪ 红：扫描面被削掉（目录整个没了）
        no_scan = fresh("no-scan")
        shutil.rmtree(no_scan / "Platform/macOS")
        cases.append(("扫描面被削掉", bool(check(no_scan)[0])))

        # ②b 红：**链接扫描器**出现第二份（2026-10-01 第 146 轮补 —— 与 ② 同一族的形状）
        duplicate_link = fresh("link-duplicate")
        (duplicate_link / "App/Views").mkdir(parents=True, exist_ok=True)
        (duplicate_link / "App/Views/MarkdownPreview.swift").write_text(
            "import Foundation\n\n/// 预览自己扫链接目标（本门禁必须抓住它）\n"
            "private func linkMarker(in text: Substring) -> Int? { nil }\n",
            encoding="utf-8",
        )
        cases.append(("链接扫描器出现第二份", bool(check(duplicate_link)[0])))


        # ── 2026-10-13（合册 `T-20261013-027` · 原单 `T-20261010-062`）补的十一例 ──

        # ⑫ 红：**注释充当调用点**（原单 ㈢ 现场：6 处真调用全改名 + 4 行注释含该字面量 ⇒ 旧版 rc=0 判绿）
        comment_only = fresh("comment-only-calls")
        text = (comment_only / BLOCK_OWNER).read_text(encoding="utf-8")
        text = text.replace(SHARED_INLINE_CALL, "Self.localInline(")
        text += "\n// 预览侧复用笔记侧解析：NoteBodyProjection.parseInline(\n" * 4
        (comment_only / BLOCK_OWNER).write_text(text, encoding="utf-8")
        cases.append(("注释充当同源调用点（旧版判绿）",
                      any("只活在注释里" in problem for problem in check(comment_only)[0])))

        # ⑬ 绿（对手臂）：别处一句**注释**提扫描器名字 —— 不许假阳（原单 ㈠ 现场：旧版 rc=1）
        comment_name = fresh("comment-name")
        text = (comment_name / BLOCK_OWNER).read_text(encoding="utf-8")
        (comment_name / BLOCK_OWNER).write_text(
            text + "\n// 预览侧复用笔记侧的 nextMarker / linkMarker（仅注释，不是实现）\n",
            encoding="utf-8")
        cases.append(("别处注释提名字不假阳（旧版判红）", not check(comment_name)[0]))

        # ⑭ 绿（对手臂）：名字只出现在**字符串**里（`print("nextMarker")`）
        string_name = fresh("string-name")
        text = (string_name / BLOCK_OWNER).read_text(encoding="utf-8")
        (string_name / BLOCK_OWNER).write_text(
            text + '\nfunc debug66() { print("nextMarker / linkMarker") }\n', encoding="utf-8")
        cases.append(("字符串里提名字不假阳", not check(string_name)[0]))

        # ⑮ 红：**异名第二套行内解析**（原单 ㈡：换个函数名 + 清单换序 ⇒ 旧版 rc=0 与基线逐字同）
        renamed = fresh("renamed-inline")
        (renamed / "App/Views").mkdir(parents=True, exist_ok=True)
        (renamed / "App/Views/InlineAgain66.swift").write_text(
            'import Foundation\n\nfunc scanInline(_ text: String) -> Int {\n'
            '    let markers = ["**", "*", "`", "["]\n'
            '    return markers.count\n}\n',
            encoding="utf-8")
        cases.append(("异名 + 清单换序的第二套解析（旧版判绿）", bool(check(renamed)[0])))

        # ⑯ 红：**形状逃逸** `MarkdownBlock (`（名字与括号之间一个空格，Swift 合法 —— 原单 ㈡）
        spaced = fresh("spaced-block")
        (spaced / "App/Views").mkdir(parents=True, exist_ok=True)
        (spaced / "App/Views/SpacedBlock66.swift").write_text(
            "import Foundation\n\nfunc make66() -> MarkdownBlock { MarkdownBlock (kind: .thematicBreak, sourceLine: 1) }\n",
            encoding="utf-8")
        cases.append(("同名 + 括号间空格的造块（旧版判绿）", bool(check(spaced)[0])))

        # ⑰ 红：**用例壳**（原单 ㈣：40 个空壳 + 一行注释提同名 ⇒ 旧版 rc=0 且 notes 打「40 个」）
        stubs = fresh("stub-cases")
        (stubs / PARSE_TESTS).write_text(
            "import XCTest\n// 与 NoteBodyProjection.parseInline( 同源\n"
            + "".join(f"    func testStub{number}() {{}}\n" for number in range(40)),
            encoding="utf-8")
        cases.append(("用例换成 40 个空壳（旧版判绿）",
                      any("非空且带断言" in problem for problem in check(stubs)[0])))

        # ⑱ 红：**面外回流**（原单 ㈤：面外那个生产根同时犯判据 ② 与 ④）
        license_tool = fresh("license-tool")
        _patch(license_tool / "Tools/LicenseTool/main.swift", "import Foundation",
               "import Foundation\nimport MarkdownUI\n\nfunc stray66() -> MarkdownBlock {\n"
               "    MarkdownBlock(kind: .thematicBreak, sourceLine: 1)\n}")
        cases.append(("面外生产根回流（旧版判绿）", bool(check(license_tool)[0])))

        # ㉑ 红（另一只臂）：同一根上只犯判据 ②（证明面内每一条都判，不是只有 import 那条）
        license_block = fresh("license-tool-block")
        _patch(license_block / "Tools/LicenseTool/main.swift", "import Foundation",
               "import Foundation\n\nfunc strayBlock66() -> MarkdownBlock "
               "{ MarkdownBlock(kind: .thematicBreak, sourceLine: 1) }")
        cases.append(("面外生产根自己造块", bool(check(license_block)[0])))

        # ⑲ 红：**面只许跟声明面** —— 包清单新增一个生产 target，其源码目录落在面外
        new_target = fresh("new-target")
        text = (new_target / PACKAGE).read_text(encoding="utf-8")
        text = text.replace(
            "        .testTarget(",
            '        .target(\n            name: "Widgets66",\n            path: "Widgets/Extra"\n        ),\n'
            "        .testTarget(",
            1,
        )
        (new_target / PACKAGE).write_text(text, encoding="utf-8")
        cases.append(("包清单新增 target 落在面外（旧版判绿）",
                      any("落在判据面外" in problem for problem in check(new_target)[0])))

        # ⑳ 绿（对手臂）：面内**正常新增**一份无关 `.swift` —— 不误伤开发
        normal_add = fresh("normal-add")
        (normal_add / "App/Views").mkdir(parents=True, exist_ok=True)
        (normal_add / "App/Views/BrandNew66.swift").write_text(
            "import Foundation\n\nstruct BrandNew66 { let value = 1 }\n", encoding="utf-8")
        cases.append(("面内正常新增一份 .swift 不误伤", not check(normal_add)[0]))

        # ㉒ 绿（对手臂）：清单只写在**注释**里 —— 剥注释后不假阳
        comment_list = fresh("comment-list")
        (comment_list / "App/Views").mkdir(parents=True, exist_ok=True)
        (comment_list / "App/Views/CommentList66.swift").write_text(
            'import Foundation\n\n// 旧清单 ["`", "**", "*", "["] —— 只有注释，不是第二份解析\n'
            "let commentList66 = 1\n",
            encoding="utf-8")
        cases.append(("清单只写在注释里不假阳", not check(comment_list)[0]))

        # 末例：真仓库逐字节未变 + 真仓库实跑绿
        after = {name: _sha(root / name) for name in WATCHED if (root / name).exists()}
        untouched = after == before
        real_problems, _ = check(root)
        cases.append(("末例：真仓库逐字节未变且实跑绿", untouched and not real_problems))

    passed_cases = 0
    for name, ok in cases:
        print(f"{'✅' if ok else '❌'} {name}")
        passed_cases += 1 if ok else 0
    ok = passed_cases == len(cases)
    print(f"{'✅' if ok else '❌'} 负例自检：{len(cases)} 条中 {passed_cases} 条达到预期")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
