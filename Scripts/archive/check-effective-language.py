#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""**「当前语言」只有一个来源**的机械门禁（队列 L-13）。

守的是什么：界面语言有两条路 ——
  ① 全局函数 `L(...)`（走 `LocalizationManager.text`）；
  ② **显式把语言传下去**（Core 那些 `summary(language:)` / `title(language:)` /
     `describe(…, language:)` / `groupedByType(…, language:)`）。

第 13 轮读图抓到的真缺陷就出在第 ② 条：**行详情侧栏在中文界面上写着 `Text · 12 characters`**
—— `RowDetailPanel` 传的是 `LocalizationManager.shared.language`（**用户选择**），而当时渲染用的是
**宿主语言**（中文）。修法是把「当前该用哪种语言」收成一个口子：`LocalizationManager.effectiveLanguage`
（宿主语境优先，其次用户选择）。本门禁把「**不许**再按用户选择取语言」变成机械判据：

  · `App/` 下（除 `App/LocalizationManager.swift` —— 它就是形成这个值的那个文件）**不得**出现
    「按用户选择取语言」的写法 —— 即**接收者**是 `LocalizationManager.shared`、或**任何绑定到它的
    名字**（`let|var x = LocalizationManager.shared`；`@StateObject` / `@ObservedObject` /
    `@EnvironmentObject private var x: LocalizationManager`；`@Environment(LocalizationManager.self)
    private var x`），后接 `.language`；
  · 三个**合法例外**在 `ALLOWED` 里逐条写明理由（都是「问用户选的是哪种语言」或「进程级系统界面」，
    不是「当前渲染语言」）；**例外表也要反向对账**：某个文件里已经没有这种写法了 ⇒ 条目陈旧，红了才删。

为什么不是「看见就一律禁」：上面那三个例外**恰恰是必须**按用户选择走的（系统菜单是进程级的、
根视图的 `.id` 是用户改语言时用来重建视图树的、菜单勾选态问的就是用户选了什么）。

判定物（2026-10-13 合册 `T-20261013-027` · 原单 `T-20261010-051` · 样本 55 收口）：**代码面** ——
  · 先剥注释（行尾 `//`、可嵌套块注释）与字符串字面量（单行串 / 三引号多行串 / raw 串）；
    **字符串插值里的内容是代码**，照常判（真仓 `.id` 那处插值命中仍要点名）。
  · 再把「与点号相邻的空白（含换行）」抹掉 ⇒ 跨行链与 `LocalizationManager .shared .language`
    回到同一个形状。
  · 接收者按类型发现（见上），不再**只**认写死的 `localization`：类型发现是它的超集，
    旧名保留为兜底（接收者在别的文件里声明时不许静默放过）。
  · 空跑防护：面为空（`scanned == 0`）判红（只判「面为空」，不设文件数下限 ⇒ 无跟版负担）。

边界（**如实登记**）：
  · 类型信息靠**文本推断**（无编译器语义）：绑定的名字认不出类型时不进面；跨函数间接传递
    （`f(LocalizationManager.shared)` 之后再取 `.language`）判不出。
  · raw 串的插值写法**不建模**：整个 raw 字面量一律当字符串抹掉（抹多不抹少）。
  · 面仍只有 `App/` 一个根 —— 该事实前门已在 `Scripts/verify-all.sh:257` 登记，本门禁不重复主张。

跑法：

    python3 Scripts/check-effective-language.py          # 接在 verify-all.sh 第 3 项里，每轮跑
    python3 Scripts/test-effective-language-gate.py      # 负例（在临时副本上写坏，不碰仓库）

退出码：0 = 全过；1 = 有判据不成立（打印文件 / 行号 / 原因）；2 = 面不存在（环境坏）。
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent

# 扫哪儿：App/ 下所有 Swift 源文件，**除**语言来源自身的定义文件。
SCAN_ROOT = "App"
DEFINITION_FILE = "App/LocalizationManager.swift"
LANGUAGE_TYPE = "LocalizationManager"

# 「按用户选择取语言」的**接收者** = 类型自身（`LocalizationManager.shared`）+ 每个文件里
# 绑定到它的名字（绑定名现读，不写死 —— 原单 ㈠ 的四形逃逸有三形都是「换了接收者的名字」）。
RECEIVER_SELF = LANGUAGE_TYPE + ".shared"

# 旧口径写死的那个接收者名**保留为兜底**（不是唯一依据）：接收者在**别的文件**里声明时
# （例如新增文件只写用法、属性声明在同一类型的另一个文件/夹具里），类型发现看不到绑定 ——
# 留这个名字是为了「不许静默放过」而不是「只认类型」。类型发现是它的**超集**。
KNOWN_RECEIVER_NAMES = ("localization",)

# 绑定发现三形：① `let|var x = LocalizationManager.shared`（含 `@StateObject` / `@ObservedObject`）
# ② `@EnvironmentObject private var x: LocalizationManager`
# ③ `@Environment(LocalizationManager.self) private var x`
BINDING_PATTERNS = (
    re.compile(
        r"\b(?:let|var)\s+([A-Za-z_]\w*)\s*(?:[ \t]*:[^\n=]+)?=[ \t]*"
        + re.escape(RECEIVER_SELF) + r"\b(?!\.)"
    ),
    re.compile(
        r"@EnvironmentObject\s+(?:(?:private|internal|fileprivate|public)\s+)?var\s+"
        r"([A-Za-z_]\w*)[ \t]*:[ \t]*" + LANGUAGE_TYPE + r"\b"
    ),
    re.compile(
        r"@Environment\s*\(\s*" + LANGUAGE_TYPE + r"\.self\s*\)\s*"
        r"(?:(?:private|internal|fileprivate|public)\s+)?var\s+([A-Za-z_]\w*)"
    ),
)

# 合法例外：文件 → 理由。每条都会**反向对账**（文件里没有这种写法了 ⇒ 条目陈旧 ⇒ 红）。
ALLOWED = {
    "App/MainMenuLocalizer.swift": "改的是 AppKit 系统菜单（进程级系统界面）：按用户选择 / 启动语言"
    "改写 NSMenuItem.title，不跟渲染语境（见 LocalizationManager 的注释）。",
    "App/DoyahStudioApp.swift": "根部 `.id(localization.language)`：用户改语言时用它整体重建视图树，"
    "不是拿它当\"当前渲染语言\"。",
    "App/DoyahStudioCommands.swift": "菜单勾选态：问的就是\"用户选的是哪种语言\"。",
}

# 这个口子必须存在（被改名/删掉时，本门禁要当场说清）。
REQUIRED_DECLARATION = "App/LocalizationManager.swift"
REQUIRED_PATTERN = re.compile(r"\bvar\s+effectiveLanguage\s*:\s*AppLanguage\b")


# —— 判定物 ①：剥注释与字符串字面量（等长抹白 ⇒ 行号不动；**插值体是代码**，照常判）


def masked_chars(text: str) -> list[str]:
    """注释与字符串字面量的正文抹成空白（换行保留 ⇒ 行号不移动）。"""
    out = list(text)
    n = len(text)

    def blank(start: int, stop: int) -> None:
        for k in range(start, min(stop, n)):
            if out[k] != "\n":
                out[k] = " "

    def hash_count(at: int) -> int:
        count = 0
        k = at - 1
        while k >= 0 and text[k] == "#":
            count += 1
            k -= 1
        return count

    def skip_string(at: int) -> int:
        """`at` = 开引号；返回闭引号之后的下标。正文抹白，插值体除外。"""
        hashes = hash_count(at)
        raw = hashes > 0
        triple = text.startswith('"' * 3, at)
        terminator = ('"' * 3 if triple else '"') + ("#" * hashes)
        blank(at - hashes, at)
        j = at + (3 if triple else 1)
        while j < n:
            if text.startswith(terminator, j):
                blank(j, j + len(terminator))
                return j + len(terminator)
            if not raw and text[j] == "\\":
                if text[j + 1: j + 2] == "(":
                    blank(j, j + 2)
                    j = skip_interpolation(j + 2)
                    continue
                blank(j, j + 2)
                j += 2
                continue
            blank(j, j + 1)
            j += 1
        return n

    def skip_interpolation(at: int) -> int:
        """`at` = 插值体第一个字符；体是**代码**（不抹）。返回闭括号之后的下标。"""
        depth = 1
        j = at
        while j < n:
            if text[j] == '"':
                j = skip_string(j)
                continue
            if text[j] == "(":
                depth += 1
            elif text[j] == ")":
                depth -= 1
                if depth == 0:
                    blank(j, j + 1)
                    return j + 1
            j += 1
        return n

    i = 0
    while i < n:
        if text.startswith("//", i):
            stop = text.find("\n", i)
            stop = n if stop < 0 else stop
            blank(i, stop)
            i = stop
        elif text.startswith("/*", i):
            depth = 1
            j = i + 2
            while j < n and depth:
                if text.startswith("/*", j):
                    depth += 1
                    j += 2
                elif text.startswith("*/", j):
                    depth -= 1
                    j += 2
                else:
                    j += 1
            blank(i, j)
            i = j
        elif text[i] == '"':
            i = skip_string(i)
        else:
            i += 1
    return out


# —— 判定物 ②：抹掉「与点号相邻的空白（含换行）」⇒ 跨行链 / `LocalizationManager .shared` 归一


def logical_code(text: str) -> tuple[str, list[int]]:
    """返回（压平后的代码面, 每个字符对应的原行号）。"""
    masked = masked_chars(text)
    line_of: list[int] = []
    line = 1
    for char in text:
        line_of.append(line)
        if char == "\n":
            line += 1
    chars: list[str] = []
    lines: list[int] = []
    i = 0
    n = len(masked)
    while i < n:
        char = masked[i]
        if char in " \t\n":
            j = i
            while j < n and masked[j] in " \t\n":
                j += 1
            previous = chars[-1] if chars else ""
            following = masked[j] if j < n else ""
            if previous == "." or following == ".":
                i = j
                continue
        chars.append(char)
        lines.append(line_of[i])
        i += 1
    return "".join(chars), lines


# —— 判定物 ③：接收者按类型发现（不是写死 `localization` 两个字面名）


def receivers(code: str) -> list[str]:
    """本文件里「按用户选择取语言」的接收者：类型自身 + 绑定到它的名字。"""
    names = {RECEIVER_SELF, *KNOWN_RECEIVER_NAMES}
    for pattern in BINDING_PATTERNS:
        for match in pattern.finditer(code):
            names.add(match.group(1))
    return sorted(names)


def forbidden_hits(code: str, lines: list[int], names: list[str]) -> list[tuple[int, str]]:
    """返回 [(行号, `接收者.language`)]，按出现顺序、同处去重。"""
    alternation = "|".join(re.escape(name) for name in names)
    pattern = re.compile(r"(?:" + alternation + r")\.language\b")
    hits: list[tuple[int, str]] = []
    for match in pattern.finditer(code):
        hit = (lines[match.start()], match.group(0))
        if hit not in hits:
            hits.append(hit)
    return hits


def main() -> int:
    parser = argparse.ArgumentParser(description="「当前语言」只有一个来源（L-13）")
    parser.add_argument("--root", default=str(REPO), help="扫描哪个仓库根（负例验证用）")
    args = parser.parse_args()
    root = pathlib.Path(args.root)

    problems: list[str] = []
    hits: dict[str, list[str]] = {}

    app = root / SCAN_ROOT
    if not app.is_dir():
        print(f"❌ 找不到 {SCAN_ROOT}/（根目录：{root}）")
        return 2

    scanned = 0
    for path in sorted(app.rglob("*.swift")):
        relative = path.relative_to(root).as_posix()
        if relative == DEFINITION_FILE:
            continue
        scanned += 1
        code, lines = logical_code(path.read_text(encoding="utf-8"))
        for line_number, label in forbidden_hits(code, lines, receivers(code)):
            hits.setdefault(relative, []).append(f"{line_number}:{label}")
            if relative not in ALLOWED:
                problems.append(
                    f"{relative}:{line_number} 用了 `{label}` 当作\"当前语言\" —— "
                    f"请改用 `LocalizationManager.shared.effectiveLanguage`（宿主语境优先）"
                )

    # 空跑防护：面为空 ⇒ 判红（只判「面为空」，不设文件数下限）
    if scanned == 0:
        problems.append(f"{SCAN_ROOT}/ 下没扫到任何 .swift（除定义文件）—— 面为空，判据无意义")

    # 例外表反向对账：条目还在，但那种写法已经不在了 ⇒ 陈旧
    for relative, reason in ALLOWED.items():
        if not (root / relative).exists():
            problems.append(f"例外表里的文件不存在：{relative}（理由：{reason}）")
        elif relative not in hits:
            problems.append(
                f"{relative}：例外条目陈旧 —— 这个文件里已经没有按用户选择取语言的写法了，"
                f"请从 ALLOWED 里删掉它"
            )

    # 口子本身必须在（按代码面判 ⇒ 注释里写一句声明不算）
    declaration = root / REQUIRED_DECLARATION
    declared = False
    if declaration.exists():
        declared = bool(
            REQUIRED_PATTERN.search(logical_code(declaration.read_text(encoding="utf-8"))[0])
        )
    if not declared:
        problems.append(
            f"{REQUIRED_DECLARATION}：找不到 `var effectiveLanguage: AppLanguage` —— "
            f"本门禁守的那个口子被改名或删掉了"
        )

    print("🌐 语言来源：App/ 下按用户选择取语言的地方")
    print(
        f"   （扫描面 {scanned} 个 .swift · 判定物 = 代码面：剥注释与字符串字面量、"
        f"插值体算代码、点号两侧空白（含换行）归一）"
    )
    for relative in sorted(hits):
        marks = "（合法例外）" if relative in ALLOWED else ""
        print(f"   · {relative}{marks}：{len(hits[relative])} 处 —— {'、'.join(hits[relative])}")

    if problems:
        print(f"\n❌ 语言来源门禁未通过（{len(problems)} 项）：")
        for problem in problems:
            print(f"   - {problem}")
        return 1

    print("✅ 语言来源门禁通过：除例外（系统菜单 / 根视图重建 / 菜单勾选态）外，一律走 effectiveLanguage")
    return 0


if __name__ == "__main__":
    sys.exit(main())
