#!/usr/bin/env python3
"""设计令牌防回潮校验（棘轮式 / ratchet）。

背景：外观改造前 App/ 里量出来这些——显式字号只有 3 个、padding 里 `2` 出现 139 次
并混着 1 / 3 / 6 / 10 / 12 / 20 / 150、颜色是零散的系统色加裸 `Color.orange/.red/.blue`。
这类"看着不精致"的来源不是一次写坏的，而是**一处处加出来的**；
所以约束也必须是逐处生效的，不能只靠一次性的美术活。

做法：**棘轮**（只能变好，不能变坏）。
    1. 本脚本扫描 App/ 下所有 .swift，按规则统计违规数；
    2. 与基线 `Scripts/design-token-baseline.json` 比较：
       任何文件任何规则的违规数**不得高于**基线，总数也不得升高；
    3. 迁移过程中违规自然减少，用 `--update-baseline` 把基线往下拧一格（只允许调低，
       需要放宽时必须显式 `--force`，好让"放宽"这件事在 code review 里看得见）。

规则：
    bare-color    裸颜色 —— **字面色值**（`Color.orange` / `NSColor.systemRed` /
                  `NSColor(calibratedRed:…)` / `Color(red:…)` / `#RRGGBB`）**永远判红**；
                  **系统语义色不算**（见下「语义色白名单」）。
    bare-font     裸字号（.font(.system(size: 14)) / NSFont.systemFont(ofSize: 14)…）
    bare-spacing  裸间距（.padding(6) / VStack(spacing: 3)…）
    bare-radius   裸圆角（cornerRadius: 5）
    bare-textstyle 系统文本样式（.font(.headline) / .font(.caption)…）—— 不在字号刻度上
    bare-foreground 系统语义前景色（.foregroundStyle(.secondary)…）—— 不在色板里

    刻意**不**校验 `Divider()`：菜单里的分隔线用它是正确的，按情况迁移更好；
    而"分隔用发丝线"这条规矩在逐屏替换时按屏落实。

豁免（**逃逸口必须有台账** · 2026-10-13 合册 `T-20261013-027` 收口 · 原单
`T-20261010-019` 样本 27 + `T-20261010-069` 样本 71）：
    行尾注释写 `// token-ok：理由` 可跳过**该行**；文件头 5 行内写
    `// token-ok-file: 理由` 可跳过**整个文件**。两条都要求
    ① 标记**在注释位**（写进字符串字面量的 `token-ok` 不构成豁免 —— 旧版是对整行原文做
    子串判定）；② **理由非空**（旧版只认标记、不判理由）；③ **在豁免台账
    `Scripts/design-token-exemptions.json` 里登记**（未登记 ⇒ 判红）。
    台账里已不在盘上的条目 ⇒ **陈旧判红**（棘轮不许累积陈旧豁免）。行级豁免数进默认读数。
    终端/原生控件那类文件级豁免**必须**是这份台账里的一条，不许悄悄加一行注释就整文件放行。

自检：`--self-test`（18 例，临时副本上写坏，末例核对真仓未变）—— 面下限 / 空面判红 /
    块注释与行尾注释不再误伤（旧版判红）/ 字符串里的 `token-ok` 不豁免（旧版判绿）/
    无理由豁免判红 / 未登记豁免判红 / 已登记该绿 / 台账陈旧判红 / 文件级豁免未登记判红 /
    `Color.clear` 只放行这一枚 token（旧版整行放行）/ 一行多条违规（旧版只判首个匹配）/
    未知参数不许吞 / 仓外 CWD 读数一致。

语义色白名单（2026-10-10 · 派单 `T-20261010-035` ② · 前门裁定 B · `origin: human-owner`）：
    `Scripts/design-token-whitelist.json` **只许登记 `NSColor` 的语义（角色）色** —— 它们
    **随主题自动适配**、不是"硬编码色值"：`.separatorColor` / `.labelColor` / `.secondaryLabelColor` /
    `.controlAccentColor` 等不记 `Theme.nsColor(…)` 那一层就是对的，把它判成裸色是**门禁口径**问题、
    不是产品缺陷（比"立补正片改代码"更对）。
    **判据 ①** 白名单里的每一条都必须落在 `SEMANTIC_COLOR_UNIVERSE`（NSColor 角色色全集）里 ——
    有人往里塞 `orange` / `#FF0000`，白名单校验当场判红。
    **判据 ②（硬边界）** 字面色值一律仍判红：每次运行都真跑反例（`Color(red:…)` / `#RRGGBB` /
    命名色 / `NSColor.systemXxx` / `NSColor(calibratedRed:…)`）证明闸没被放宽成摆设。

用法：
    python3 Scripts/check-design-tokens.py                # 校验（CI / 提交前）
    python3 Scripts/check-design-tokens.py --report       # 只看统计 + 豁免登记
    python3 Scripts/check-design-tokens.py --update-baseline [--force]
    python3 Scripts/check-design-tokens.py --self-test    # 判据自己的证据（18 例）
    python3 Scripts/check-design-tokens.py --root <仓根>  # 自检 / 异机复跑用（缺省 = 脚本所在仓）
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
ROOT_REL = "App"
BASELINE_REL = "Scripts/design-token-baseline.json"
WHITELIST_REL = "Scripts/design-token-whitelist.json"
LEDGER_REL = "Scripts/design-token-exemptions.json"
PACKAGE_REL = "Package.swift"
APP_TARGET = "DoyahStudioApp"

# 空跑防护（面下限）：当轮实测 **117 份 .swift / 代码行 28096**（代码行 = 剥注释与
# 空行之后的行数；2026-10-13 · 原单 `T-20261010-069` ㈢：旧版把 `App/` 改名或搬走之后
# 打印「仍有 0 处待迁移」判绿）。下限取实测值留余量。
FLOOR_FILES = 105
FLOOR_LINES = 25000

SPACING_SCALE = {0, 1, 2, 4, 8, 12, 16, 24, 32}
FONT_SCALE = {11, 12, 13, 15, 17}
RADIUS_SCALE = {1, 4, 6, 8, 10}

# 字面色值（硬边界：**永远判红**，不许进白名单）。
BARE_COLOR = re.compile(
    # 具体色名（橙 / 红 / 蓝…）
    r"\b(?:Color|NSColor)\.(?:orange|red|blue|yellow|green|purple|pink|gray|grey|brown|cyan|indigo|mint|teal)\b"
    r"|\bNSColor\.system(?:Red|Orange|Yellow|Green|Blue|Purple|Pink|Gray|Brown|Teal|Indigo|Mint|Cyan)\b"
    r"|\bNSColor\(calibratedRed:|\bNSColor\(deviceRed:"
    # SwiftUI 直接给分量的写法 + 十六进制字面量（注释行会被扫前跳过，故文档里的色号不误伤）
    r"|\bColor\(red:|\bColor\(white:"
    r"|(?<![0-9A-Za-z_])#[0-9A-Fa-f]{6}(?![0-9A-Za-z])"
)

# `NSColor` 的**语义（角色）色**全集 —— 随主题自动适配，不是"硬编码色值"。
# 白名单文件只许从这个集合里挑（判据 ①）；集合外的一律走字面色值那一档。
SEMANTIC_COLOR_UNIVERSE = frozenset({
    "labelColor", "secondaryLabelColor", "tertiaryLabelColor", "quaternaryLabelColor",
    "placeholderTextColor", "separatorColor", "gridColor",
    "controlAccentColor", "controlTextColor", "disabledControlTextColor",
    "selectedControlTextColor", "selectedTextColor", "selectedTextBackgroundColor",
    "selectedContentBackgroundColor", "unemphasizedSelectedTextColor",
    "unemphasizedSelectedContentBackgroundColor", "keyboardFocusIndicatorColor",
    "controlBackgroundColor", "windowBackgroundColor", "windowFrameTextColor",
    "textBackgroundColor", "headerTextColor", "findHighlightColor", "linkColor",
    "shadowColor",
})
SEMANTIC_COLOR_NAME = re.compile(r"\.([A-Za-z]+Color)\b")

FONT_SIZE = re.compile(
    r"\.system\(size:\s*([0-9.]+)|systemFont\(ofSize:\s*([0-9.]+)|monospacedSystemFont\(ofSize:\s*([0-9.]+)"
    r"|monospacedDigitSystemFont\(ofSize:\s*([0-9.]+)"
)
PADDING = re.compile(r"\.padding\(\s*(?:\.\w+\s*,\s*)?([0-9.]+)\s*\)")
STACK_SPACING = re.compile(r"\b(?:VStack|HStack|LazyVStack|LazyHStack|Grid)\([^)]*spacing:\s*([0-9.]+)")
FRAME_SPACING = re.compile(r"\.padding\(\s*\.\w+\s*,\s*([0-9.]+)\s*\)|\.offset\([^)]*[xy]:\s*([0-9.]+)")
CORNER = re.compile(r"cornerRadius:\s*([0-9.]+)|RoundedRectangle\(cornerRadius:\s*([0-9.]+)")
# 系统文本样式：**不在我们的字号刻度里**（我们的刻度是 11/12/13/15/17 + 等宽档），
# 用了它就会出现"标题比别处大一点点"。`(?<!Theme)` 是为了放过 `Theme.font(.body)`。
BARE_TEXT_STYLE = re.compile(
    r"(?<!Theme)\.font\(\.(?:body|headline|caption2?|callout|subheadline|footnote|largeTitle|title[23]?)\)"
)
# 系统的语义前景色：设计令牌里有对应的 TextTone，混用会让"次要文字"比别处灰一点点。
BARE_FOREGROUND = re.compile(
    r"\.foregroundStyle\(\.(?:secondary|tertiary|quaternary)\)"
    r"|\.foregroundColor\(\.(?:secondaryLabelColor|tertiaryLabelColor)\)"
)
HAIRLINE = re.compile(r"lineWidth:\s*([0-9.]+)|\.frame\(height:\s*0?\.5\b")



def _skip_string(text: str, start: int) -> int:
    """从开引号走到收引号（含 `\\(` 插值与 `\\"` 转义；未收尾则到行尾）。"""
    i, n = start + 1, len(text)
    while i < n:
        char = text[i]
        if char == "\\":
            if text[i + 1:i + 2] == "(":
                depth, i = 1, i + 2
                while i < n and depth:
                    if text[i] == '"':
                        i = _skip_string(text, i)
                        continue
                    depth += 1 if text[i] == "(" else (-1 if text[i] == ")" else 0)
                    i += 1
                continue
            i += 2
            continue
        if char == '"' or char == "\n":
            return i + 1
        i += 1
    return n


def split_code_comment(text: str) -> list[tuple[str, str]]:
    """逐行切出 `(代码, 注释)` —— 判定物只认**代码**那半。

    旧版（原单 `T-20261010-069` ㈣）只在原文上跑正则、只跳「整行以 `//` 开头」⇒
    块注释 `/* 历史：曾用 Color.orange */` 与行尾注释都当代码判红（假阳）；
    而豁免标记又对整行做子串判定 ⇒ 字符串字面量里的 `token-ok` 也算豁免（假绿）。
    字符串字面量（含多行串）里的 `//`、`/*` 不是注释。
    """
    rows: list[tuple[str, str]] = []
    code: list[str] = []
    comment: list[str] = []
    i, n, in_block, in_multiline = 0, len(text), False, False
    while i < n:
        if in_block:
            if text.startswith("*/", i):
                in_block, i = False, i + 2
                comment.append("*/")
                continue
            if text[i] == "\n":
                rows.append(("".join(code), "".join(comment)))
                code, comment = [], []
            else:
                comment.append(text[i])
            i += 1
            continue
        if in_multiline:
            end = text.find('"""', i)
            stop = n if end < 0 else end
            code.append(text[i:stop])
            if end < 0:
                i = n
                continue
            code.append('"""')
            i, in_multiline = end + 3, False
            continue
        if text.startswith('"""', i):
            in_multiline, i = True, i + 3
            continue
        if text[i] == '"':
            end = _skip_string(text, i)
            code.append(text[i:end])
            i = end
            continue
        if text.startswith("//", i):
            end = text.find("\n", i)
            end = n if end < 0 else end
            comment.append(text[i:end])
            i = end
            continue
        if text.startswith("/*", i):
            in_block, i = True, i + 2
            comment.append("/*")
            continue
        if text[i] == "\n":
            rows.append(("".join(code), "".join(comment)))
            code, comment = [], []
            i += 1
            continue
        code.append(text[i])
        i += 1
    if code or comment:
        rows.append(("".join(code), "".join(comment)))
    return rows
def numbers(match: re.Match | None) -> list[float]:
    if match is None:
        return []
    return [float(group) for group in match.groups() if group is not None]


CLEAR_TOKEN = re.compile(r"\b(?:Color|NSColor)\.clear\b")


def bare_color_hit(code: str, allowed: frozenset[str]) -> bool:
    """一处裸色 = 字面色值，或**未登记**的系统语义色（白名单里登记过的放行）。

    `Color.clear`（透明常量，不是色值）是**唯一**按 token 放行的写法：旧版
    （原单 `T-20261010-069` ㈡）判的是「整行原文里有没有 `Color.clear`」⇒
    `let a = Color.orange; let b = Color.clear` 整行放行；现在只把这一枚 token 摘掉。
    """
    probe = CLEAR_TOKEN.sub("", code)
    if BARE_COLOR.search(probe):
        return True
    for name in SEMANTIC_COLOR_NAME.findall(probe):
        if name in SEMANTIC_COLOR_UNIVERSE and name not in allowed:
            return True
    return False


def all_values(pattern: re.Pattern, code: str) -> list[float]:
    """**一行里的每一处命中**都要看（旧版用 `.search` 只判首个匹配 ⇒ `.padding(8).padding(6)`
    整行放行、其后违规静默丢失 · 原单 `T-20261010-069` ㈤）。"""
    found: list[float] = []
    for match in pattern.finditer(code):
        found.extend(numbers(match))
    return found


def scan_file(path: pathlib.Path, allowed: frozenset[str]) -> dict:
    """→ {"counts": {规则: 数}, "exempt": [行号], "noReason": [行号], "codeLines": n}"""
    counts: dict[str, int] = {}
    exempt: list[int] = []
    no_reason: list[int] = []
    code_lines = 0
    for number, (raw, comment) in enumerate(split_code_comment(path.read_text(encoding="utf-8")), 1):
        mark = EXEMPT_MARKER if EXEMPT_MARKER in comment else (LINE_EXEMPT if LINE_EXEMPT in comment else None)
        if mark is not None:
            if comment.split(mark, 1)[1].strip(" ：:，,.-—"):  # 旧版不判理由（空理由也放行）
                exempt.append(number)
            else:
                no_reason.append(number)
            continue
        code = raw.strip()
        if not code:
            continue
        code_lines += 1

        def bump(rule: str) -> None:
            counts[rule] = counts.get(rule, 0) + 1

        if bare_color_hit(code, allowed):
            bump("bare-color")
        if any(value not in FONT_SCALE for value in all_values(FONT_SIZE, code) if value):
            bump("bare-font")
        spacing = all_values(PADDING, code) + all_values(STACK_SPACING, code)
        if any(value not in SPACING_SCALE for value in spacing):
            bump("bare-spacing")
        if any(value not in RADIUS_SCALE for value in all_values(CORNER, code)):
            bump("bare-radius")
        if BARE_TEXT_STYLE.search(code):
            bump("bare-textstyle")
        if BARE_FOREGROUND.search(code):
            bump("bare-foreground")
    return {"counts": counts, "exempt": exempt, "noReason": no_reason, "codeLines": code_lines}


EXEMPT_MARKER = "token-ok-file:"
LINE_EXEMPT = "token-ok"


def exempt_reason(path: pathlib.Path) -> str | None:
    """整文件豁免：文件头 5 行内写 `// token-ok-file: 理由`（**理由非空**才算数）。

    逃逸口必须**可见**：豁免文件在默认读数与 `--report` 里都会列出，
    免得「加一行注释就悄悄无视规矩」变成常规操作。
    """
    for line in path.read_text(encoding="utf-8").splitlines()[:5]:
        if EXEMPT_MARKER not in line:
            continue
        for code, comment in split_code_comment(line):
            if EXEMPT_MARKER in comment:
                reason = comment.split(EXEMPT_MARKER, 1)[1].strip(" ：:，,.-—")
                return reason or None
        return None
    return None


def load_ledger(path: pathlib.Path) -> tuple[dict, list[str]]:
    """豁免台账（原单 `T-20261010-019` ⓐ：逃逸口必须有台账，不许长在被审源码里无人管）。

    形状：`{"lines": [{"file","line","reason"}], "files": [{"file","reason"}]}`。
    缺盘 / 非法 JSON / 条目缺字段 / 理由为空 / 重复登记 ⇒ 判红（空跑防护）。
    """
    problems: list[str] = []
    if not path.exists():
        return {"lines": [], "files": []}, [f"豁免台账不存在：{path}（逃逸口必须有台账）"]
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        return {"lines": [], "files": []}, [f"豁免台账不是合法 JSON：{error}"]
    ledger: dict = {"lines": [], "files": []}
    seen: set[tuple] = set()
    for key, line_field in (("lines", True), ("files", False)):
        entries = data.get(key)
        if not isinstance(entries, list):
            problems.append(f"豁免台账的 {key} 缺失或不是列表")
            continue
        for entry in entries:
            if not isinstance(entry, dict) or not isinstance(entry.get("file"), str):
                problems.append(f"豁免台账 {key} 条目形状不对：{entry!r}")
                continue
            reason = entry.get("reason")
            if not isinstance(reason, str) or not reason.strip():
                problems.append(f"豁免台账 {key} 条目没写理由：{entry!r}")
                continue
            if line_field:
                number = entry.get("line")
                if not isinstance(number, int) or number <= 0:
                    problems.append(f"豁免台账 lines 条目缺行号：{entry!r}")
                    continue
                identity = (entry["file"], number)
            else:
                identity = (entry["file"],)
            if identity in seen:
                problems.append(f"豁免台账重复登记：{identity}")
                continue
            seen.add(identity)
            ledger[key].append(dict(entry))
    return ledger, problems
def totals(scan_result: dict[str, dict[str, int]]) -> dict[str, int]:
    total: dict[str, int] = {}
    for counts in scan_result.values():
        for rule, value in counts.items():
            total[rule] = total.get(rule, 0) + value
    return total


def scan(root: pathlib.Path, allowed: frozenset[str]) -> dict:
    counts: dict[str, dict[str, int]] = {}
    exempt_files: dict[str, str] = {}
    exempt_lines: dict[str, list[int]] = {}
    no_reason: list[tuple[str, int]] = []
    files = code_lines = 0
    for path in sorted((root / ROOT_REL).rglob("*.swift")):
        relative = path.relative_to(root).as_posix()
        reason = exempt_reason(path)
        if reason is not None:
            exempt_files[relative] = reason
            continue
        files += 1
        result = scan_file(path, allowed)
        code_lines += result["codeLines"]
        if result["counts"]:
            counts[relative] = result["counts"]
        if result["exempt"]:
            exempt_lines[relative] = result["exempt"]
        no_reason += [(relative, number) for number in result["noReason"]]
    return {"counts": counts, "exemptFiles": exempt_files, "exemptLines": exempt_lines,
            "noReason": no_reason, "files": files, "codeLines": code_lines}


def app_target_sources(root: pathlib.Path) -> list[str] | None:
    """`Package.swift` 里 `DoyahStudioApp` 声明的源码目录 —— 门禁面**与工程声明对账**
    （原单 `T-20261010-069` ㈢：面无下限、也不对账 ⇒ 面被改窄没人说话）。"""
    path = root / PACKAGE_REL
    if not path.exists():
        return None
    found = re.search(
        r'name:\s*"' + re.escape(APP_TARGET) + r'".*?sources:\s*\[([^\]]*)\]',
        path.read_text(encoding="utf-8"), re.S,
    )
    if not found:
        return None
    return re.findall(r'"([^"]+)"', found.group(1))


def surface_problems(root: pathlib.Path, files: int, code_lines: int) -> list[str]:
    problems: list[str] = []
    if not (root / ROOT_REL).is_dir():
        problems.append(f"扫描面不存在：{ROOT_REL}/（面被砍到底不许静默通过）")
    if files < FLOOR_FILES:
        problems.append(f"扫描面只有 {files} 个 .swift（下限 {FLOOR_FILES}）—— `{ROOT_REL}/` 被改名或搬家了吗？")
    if code_lines < FLOOR_LINES:
        problems.append(f"扫描面的代码行只有 {code_lines}（下限 {FLOOR_LINES}）")
    declared = app_target_sources(root)
    if declared is None:
        problems.append(f"`{PACKAGE_REL}` 里找不到 `{APP_TARGET}` 的 `sources:` 列表（面无法与工程声明对账）")
        return problems
    if ROOT_REL not in declared:
        problems.append(f"`{APP_TARGET}` 的 sources 里没有 `{ROOT_REL}`：{declared}")
    for item in declared:
        if not (root / item).exists():
            problems.append(f"`{APP_TARGET}` 声明的源目录不在盘上：{item}")
    return problems


def escape_problems(scanned: dict, ledger: dict) -> list[str]:
    """逃逸口对账（原单 `T-20261010-019` ⓐ）：未登记 ⇒ 判红；台账陈旧 ⇒ 判红。"""
    problems: list[str] = []
    registered_lines = {(entry["file"], entry["line"]) for entry in ledger["lines"]}
    registered_files = {entry["file"] for entry in ledger["files"]}
    for path, numbers_ in sorted(scanned["exemptLines"].items()):
        for number in numbers_:
            if (path, number) not in registered_lines:
                problems.append(f"未登记的行级豁免：{path}:{number}（逃逸口必须进 {LEDGER_REL}）")
    for path, number in scanned["noReason"]:
        problems.append(f"豁免没写理由：{path}:{number}（写法 `// {LINE_EXEMPT}：理由`）")
    for path in sorted(scanned["exemptFiles"]):
        if path not in registered_files:
            problems.append(f"未登记的文件级豁免：{path}（逃逸口必须进 {LEDGER_REL}）")
    for entry in ledger["lines"]:
        if entry["line"] not in scanned["exemptLines"].get(entry["file"], []):
            problems.append(f"豁免台账陈旧：{entry['file']}:{entry['line']} 盘上已无该标记")
    for entry in ledger["files"]:
        if entry["file"] not in scanned["exemptFiles"]:
            problems.append(f"豁免台账陈旧：{entry['file']} 盘上已无文件级标记")
    return problems


def write_baseline(path: pathlib.Path, files: dict, totals_: dict) -> None:
    path.write_text(
        json.dumps(
            {"comment": "设计令牌棘轮基线：违规数只能降不能升（--update-baseline 下调）",
             "files": files, "totals": totals_},
            ensure_ascii=False, indent=2, sort_keys=True,
        ) + "\n",
        encoding="utf-8",
    )
def load_baseline(path: pathlib.Path) -> dict:
    if not path.exists():
        return {"files": {}, "totals": {}}
    return json.loads(path.read_text(encoding="utf-8"))


NEGATIVE_SAMPLES = (
    "let c = Color.orange",
    "let c = NSColor.systemRed",
    "let c = NSColor(calibratedRed: 0.1, green: 0.2, blue: 0.3, alpha: 1)",
    "let c = Color(red: 0.1, green: 0.2, blue: 0.3)",
    'let c = Color(hex: "#FF00FF")',
)
def load_whitelist(path: pathlib.Path) -> tuple[frozenset[str], list[str]]:
    """读语义色白名单 + 校验「只许语义色」（判据 ①）。返回 (白名单, 问题列表)。"""
    if not path.exists():
        return frozenset(), [f"语义色白名单文件不存在：{path}"]
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        return frozenset(), [f"语义色白名单不是合法 JSON：{error}"]
    entries = data.get("semanticColors")
    if not isinstance(entries, list) or not entries:
        return frozenset(), ["语义色白名单的 semanticColors 缺失或为空（空跑防护）"]
    problems: list[str] = []
    allowed: set[str] = set()
    for entry in entries:
        if not isinstance(entry, str):
            problems.append(f"白名单条目不是字符串：{entry!r}")
        elif entry not in SEMANTIC_COLOR_UNIVERSE:
            problems.append(f"白名单里出现**非语义色**：{entry}（只许 NSColor 角色色）")
        elif entry in allowed:
            problems.append(f"白名单条目重复：{entry}")
        else:
            allowed.add(entry)
    return frozenset(allowed), problems
def self_check(allowed: frozenset[str]) -> list[str]:
    """判据 ②：字面量反例必须仍判红；白名单里的放行、未登记的系统语义色仍判红。"""
    problems: list[str] = []
    for sample in NEGATIVE_SAMPLES:
        if not bare_color_hit(sample, allowed):
            problems.append(f"反例没被拦下（闸被放宽）：{sample}")
    for name in sorted(allowed):
        sample = f"let c = Color(nsColor: .{name})"
        if bare_color_hit(sample, allowed):
            problems.append(f"白名单里的语义色仍被判裸色：{sample}")
    # 2026-10-13（原单 `T-20261010-069` ㈥）：旧版这段跑的是
    # `SEMANTIC_COLOR_UNIVERSE - allowed` 的差集 —— 白名单写满 25/25 时**零次迭代**，
    # 而循环体对「未登记的系统语义色」构造的样本恰好也被判红 ⇒ 断言恒为 False，
    # 于是「未登记的系统语义色仍判红」这条**两头都没人守**。改成在**全集**上跑：
    # 白名单里的一律放行、白名单外的一律判红，25 条一条不少。
    for name in sorted(SEMANTIC_COLOR_UNIVERSE):
        negative = f"let c = NSColor.{name}"
        hit = bare_color_hit(negative, allowed)
        if name in allowed and hit:
            problems.append(f"白名单里的语义色仍被判裸色：{negative}")
        if name not in allowed and not hit:
            problems.append(f"未登记的系统语义色没被判裸色：{negative}")
    return problems


FLAGS = {"--report", "--update-baseline", "--force", "--self-test"}


def parse_args(argv: list[str]) -> tuple[str | None, set[str], list[str]]:
    """→ (root 覆盖, 已知开关, 未知参数)。

    未知参数**不许吞**（原单 `T-20261010-069` 三：旧版只认三个参数，`--bogus` 照跑真仓）。
    """
    root: str | None = None
    flags: set[str] = set()
    unknown: list[str] = []
    index = 0
    while index < len(argv):
        item = argv[index]
        if item == "--root":
            if index + 1 >= len(argv):
                unknown.append("--root（缺值）")
            else:
                root = argv[index + 1]
                index += 1
        elif item in FLAGS:
            flags.add(item)
        else:
            unknown.append(item)
        index += 1
    return root, flags, unknown


def main() -> int:
    root_arg, flags, unknown = parse_args(sys.argv[1:])
    if unknown:
        print("❌ 未知参数（不许静默吞掉）：" + " ".join(unknown))
        print("   用法：check-design-tokens.py [--report] [--update-baseline [--force]] [--self-test] [--root PATH]")
        return 2
    if "--self-test" in flags:
        return self_test()
    root = pathlib.Path(root_arg).resolve() if root_arg else REPO

    allowed, whitelist_problems = load_whitelist(root / WHITELIST_REL)
    gate_problems = list(whitelist_problems)
    if not gate_problems:
        gate_problems += self_check(allowed)
    if gate_problems:
        print("❌ 设计令牌门禁自检失败（判据 ① 白名单只许语义色 / 判据 ② 字面量反例仍判红）：")
        for problem in gate_problems:
            print("   " + problem)
        return 1

    ledger, ledger_problems = load_ledger(root / LEDGER_REL)
    scanned = scan(root, allowed)
    current, exempt_files = scanned["counts"], scanned["exemptFiles"]
    current_totals = totals(current)
    baseline_path = root / BASELINE_REL
    baseline = load_baseline(baseline_path)
    surface = surface_problems(root, scanned["files"], scanned["codeLines"])
    escapes = escape_problems(scanned, ledger)
    line_count = sum(len(numbers_) for numbers_ in scanned["exemptLines"].values())
    readout = (
        f"扫描面 {scanned['files']} 份 .swift（代码行 {scanned['codeLines']}；下限 {FLOOR_FILES}/{FLOOR_LINES}）· "
        f"行级豁免 {line_count} 处（台账 {len(ledger['lines'])} 条）· "
        f"文件级豁免 {len(exempt_files)} 个（台账 {len(ledger['files'])} 条）"
    )

    if "--report" in flags:
        print(f"当前违规统计（{ROOT_REL}/）：")
        for rule in sorted(current_totals):
            print(f"  {rule:<14} {current_totals[rule]:>5}")
        print(f"语义色白名单：{len(allowed)} 个（仅语义色校验通过；字面量反例 {len(NEGATIVE_SAMPLES)} 例仍判红）")
        for path, numbers_ in sorted(scanned["exemptLines"].items()):
            for number in numbers_:
                print(f"  行级豁免 {path}:{number}")
        for path, reason in exempt_files.items():
            print(f"  文件级豁免 {path} — {reason}")
        print("最集中的文件：")
        for path, counts in sorted(current.items(), key=lambda item: -sum(item[1].values()))[:8]:
            print(f"  {sum(counts.values()):>4}  {path}  {counts}")
        print(readout)
        if surface or ledger_problems or escapes:
            for problem in surface + ledger_problems + escapes:
                print("❌ " + problem)
            return 1
        return 0

    if "--update-baseline" in flags:
        if not baseline_path.exists():
            write_baseline(baseline_path, current, current_totals)
            print(f"✅ 首次建立基线：{sum(current_totals.values())} 处待迁移 {current_totals}")
            return 0
        old_totals = baseline.get("totals", {})
        worse = [
            f"合计 {rule}: {old_totals.get(rule, 0)} → {value}"
            for rule, value in current_totals.items() if value > old_totals.get(rule, 0)
        ]
        # 逐文件也要卡：旧版只比**规则合计** ⇒ 一处收紧、另一处放松即可把
        # 逐文件棘轮平移洗白（原单 `T-20261010-069` 三「棘轮可洗白」）。
        for path, counts in current.items():
            budget = baseline.get("files", {}).get(path, {})
            for rule, value in counts.items():
                if value > budget.get(rule, 0):
                    worse.append(f"{path}: {rule} {budget.get(rule, 0)} → {value}")
        if worse and "--force" not in flags:
            print("❌ 这些地方比基线更差了，拒绝写入（如确要放宽请加 --force，让它在 review 里可见）：")
            for line in worse:
                print("   " + line)
            return 1
        write_baseline(baseline_path, current, current_totals)
        print(f"✅ 基线已更新：{sum(current_totals.values())} 处待迁移")
        return 0

    problems: list[str] = []
    for path, counts in current.items():
        budget = baseline.get("files", {}).get(path, {})
        for rule, value in counts.items():
            if value > budget.get(rule, 0):
                problems.append(f"{path}: {rule} {budget.get(rule, 0)} → {value}")
    for rule, value in current_totals.items():
        budget = baseline.get("totals", {}).get(rule, 0)
        if value > budget:
            problems.append(f"合计 {rule} {budget} → {value}")

    problems = surface + ledger_problems + escapes + problems
    if problems:
        print(f"❌ 设计令牌校验失败（{len(problems)} 处）：")
        for problem in problems:
            print("   " + problem)
        print(f"   提示：能改就用令牌；确实要保留原样时在行尾写 `// {LINE_EXEMPT}：理由` 并登记进 {LEDGER_REL}。")
        print("   " + readout)
        return 1

    print(f"✅ 令牌校验通过（未比基线更差；仍有 {sum(current_totals.values())} 处待迁移：{current_totals}）")
    print(f"   语义色白名单 {len(allowed)} 个（判据 ① 仅语义色 · 通过；"
          f"字面量反例 {len(NEGATIVE_SAMPLES)} 例仍判红 · 判据 ② 通过）")
    print("   " + readout)
    return 0


def self_test() -> int:
    """判据自己的证据（18 例 · 原单 `T-20261010-069` 的缺口的成对证据）。

    一律在**临时副本**上写坏（`--root` 指过去），末例核对真仓库逐字节未变。
    """
    failures: list[str] = []
    total = 0
    scratch = pathlib.Path(tempfile.mkdtemp(prefix="doyah-design-tokens-"))
    script_before = hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest()
    watch = [BASELINE_REL, WHITELIST_REL, LEDGER_REL]
    before = {name: hashlib.sha256((REPO / name).read_bytes()).hexdigest() for name in watch}
    base = scratch / "base"
    shutil.copytree(REPO / ROOT_REL, base / ROOT_REL)
    shutil.copy2(REPO / PACKAGE_REL, base / PACKAGE_REL)
    for item in app_target_sources(REPO) or []:
        (base / item).mkdir(parents=True, exist_ok=True)
    for name in watch:
        (base / pathlib.Path(name).parent).mkdir(parents=True, exist_ok=True)
        shutil.copy2(REPO / name, base / name)

    def invoke(root, cwd=None, extra=()):
        command = [sys.executable, str(pathlib.Path(__file__).resolve())]
        if root is not None:
            command += ["--root", str(root)]
        command += list(extra)
        done = subprocess.run(command, cwd=str(cwd or REPO), capture_output=True, text=True)
        return done.returncode, done.stdout + done.stderr

    def fixture(name: str) -> pathlib.Path:
        where = scratch / name
        shutil.copytree(base, where)
        return where

    def probe(where: pathlib.Path, body: str, rel: str = "App/Probe.swift") -> None:
        path = where / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(body, encoding="utf-8")

    def ledger_of(where: pathlib.Path) -> dict:
        return json.loads((where / LEDGER_REL).read_text(encoding="utf-8"))

    def write_ledger(where: pathlib.Path, data: dict) -> None:
        (where / LEDGER_REL).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    def red(where: pathlib.Path, needle: str) -> str | None:
        code, output = invoke(where, where)
        if code == 0:
            return "仍 rc=0（该判红）"
        if needle not in output:
            return f"判红了但不是命中的那一条（缺 {needle!r}）\n{output[-500:]}"
        return None

    def green(where: pathlib.Path) -> str | None:
        code, output = invoke(where, where)
        if code != 0:
            return f"该绿却判红（rc={code}）\n{output[-500:]}"
        return None

    def case(description: str, check) -> None:
        nonlocal total
        total += 1
        problem = check()
        if problem:
            failures.append(f"例 {total} 失败：{description} —— {problem}")

    # 例 1：真仓正例 —— rc=0 + 扫描面读数 + 豁免计数
    def check_positive():
        code, output = invoke(None, REPO)
        if code != 0:
            return f"真仓实跑不是绿（rc={code}）\n{output[-400:]}"
        if "令牌校验通过" not in output or "扫描面" not in output:
            return "没打印「通过 + 扫描面读数」"
        return None
    case("真仓正例：rc=0 + 扫描面读数 + 豁免计数", check_positive)

    # 例 2：面整体消失 ⇒ 判红（旧版 rc=0「仍有 0 处待迁移」）
    def check_empty_face():
        where = fixture("empty-face")
        shutil.rmtree(where / ROOT_REL)
        return red(where, "扫描面不存在")
    case("`App/` 整体消失 ⇒ 判红（旧版 rc=0）", check_empty_face)

    # 例 3：面被砍到底 ⇒ 判红
    def check_floor():
        where = fixture("floor")
        paths = sorted((where / ROOT_REL).rglob("*.swift"))
        for path in paths[1:]:
            path.unlink()
        return red(where, f"下限 {FLOOR_FILES}")
    case(f"扫描面只剩 1 份 .swift ⇒ 判红（下限 {FLOOR_FILES}）", check_floor)

    # 例 4：块注释里的色号不再误伤（旧版判红）
    def check_block_comment():
        where = fixture("block-comment")
        probe(where, "// Probe.swift\nlet note = 1\n/* 历史：曾用 Color.orange 与 .font(.headline) */\n")
        return green(where)
    case("块注释里的 `Color.orange` ⇒ 该绿（旧版判红）", check_block_comment)

    # 例 5：行尾注释里的色号不再误伤（旧版判红）
    def check_line_comment():
        where = fixture("line-comment")
        probe(where, "// Probe.swift\nlet note = 1  // 参考 Color.orange 的旧写法\n")
        return green(where)
    case("行尾注释里的 `Color.orange` ⇒ 该绿（旧版判红）", check_line_comment)

    # 例 6：真违规仍判红（对照）
    def check_real_violation():
        where = fixture("real-violation")
        probe(where, "// Probe.swift\nlet tint = Color.orange\n")
        return red(where, "bare-color")
    case("真裸色 `Color.orange` ⇒ 判红（对照）", check_real_violation)

    # 例 7：字符串字面量里的 `token-ok` 不构成豁免（旧版判绿）
    def check_string_token():
        where = fixture("string-token")
        probe(where, '// Probe.swift\nlet v = Text("token-ok").padding(.horizontal, 7)\n')
        return red(where, "bare-spacing")
    case("字符串里的 `token-ok` 不豁免 ⇒ 判红（旧版 rc=0）", check_string_token)

    # 例 8：注释位 `token-ok` 没写理由 ⇒ 判红（旧版判绿）
    def check_no_reason():
        where = fixture("no-reason")
        probe(where, "// Probe.swift\nlet pad = 1  // token-ok\n")
        return red(where, "豁免没写理由")
    case("注释位 `// token-ok` 没写理由 ⇒ 判红（旧版 rc=0）", check_no_reason)

    # 例 9：有理由但未登记台账 ⇒ 判红
    def check_unregistered():
        where = fixture("unregistered")
        probe(where, "// Probe.swift\nlet pad = 1  // token-ok：探针占位\n")
        return red(where, "未登记的行级豁免")
    case("行级豁免带理由但未登记台账 ⇒ 判红", check_unregistered)

    # 例 10：登记进台账 ⇒ 该绿
    def check_registered():
        where = fixture("registered")
        probe(where, "// Probe.swift\nlet pad = 1  // token-ok：探针占位\n")
        data = ledger_of(where)
        data["lines"].append({"file": "App/Probe.swift", "line": 2, "reason": "探针占位"})
        write_ledger(where, data)
        return green(where)
    case("同一豁免登记进台账 ⇒ 该绿", check_registered)

    # 例 11：台账陈旧 ⇒ 判红
    def check_stale():
        where = fixture("stale")
        data = ledger_of(where)
        data["lines"].append({"file": "App/Ghost.swift", "line": 3, "reason": "已删除的旧豁免"})
        write_ledger(where, data)
        return red(where, "豁免台账陈旧")
    case("台账里有一条盘上已不存在的豁免 ⇒ 判红（陈旧）", check_stale)

    # 例 12：文件级豁免未登记 ⇒ 判红（旧版整文件静默放行）
    def check_file_exempt():
        where = fixture("file-exempt")
        probe(where, "// token-ok-file: 探针整文件豁免\nlet tint = Color.orange\n")
        return red(where, "未登记的文件级豁免")
    case("`// token-ok-file:` 未登记 ⇒ 判红（旧版判绿）", check_file_exempt)

    # 例 13：`Color.clear` 不再整行放行（旧版 rc=0）
    def check_clear_masking():
        where = fixture("clear-masking")
        probe(where, "// Probe.swift\nlet a = Color.orange; let b = Color.clear\n")
        return red(where, "bare-color")
    case("同行既 `Color.orange` 又 `Color.clear` ⇒ 判红（旧版 rc=0）", check_clear_masking)

    # 例 14：`Color.clear` 单独用 ⇒ 该绿（对照）
    def check_clear_alone():
        where = fixture("clear-alone")
        probe(where, "// Probe.swift\nlet b = Color.clear\n")
        return green(where)
    case("单独 `Color.clear` ⇒ 该绿（对照）", check_clear_alone)

    # 例 15：一行两处命中，第二处也要判（旧版只判首个匹配）
    def check_two_hits():
        where = fixture("two-hits")
        probe(where, "// Probe.swift\nlet v = Text(\"x\").padding(8).padding(6)\n")
        return red(where, "bare-spacing")
    case("同行第二处 `.padding(6)` 也判 ⇒ 判红（旧版 rc=0）", check_two_hits)

    # 例 16：未知参数不许吞（旧版照跑真仓）
    def check_unknown_arg():
        code, output = invoke(None, REPO, ("--bogus",))
        if code != 2:
            return f"`--bogus` 没被判 rc=2（rc={code}）"
        if "未知参数" not in output:
            return "没说「未知参数」"
        return None
    case("未知参数 `--bogus` ⇒ rc=2（旧版照跑真仓）", check_unknown_arg)

    # 例 17：仓外 CWD 读数一致（面按脚本位置锚定）
    def check_outside_cwd():
        code, output = invoke(None, pathlib.Path(tempfile.gettempdir()))
        if code != 0 or "扫描面" not in output:
            return f"仓外 CWD 跑不出读数（rc={code}）\n{output[-400:]}"
        return None
    case("从仓外 CWD 跑 ⇒ 读数一致（面按脚本位置锚定）", check_outside_cwd)

    # 例 18：真仓库逐字节未变
    def check_untouched():
        if hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest() != script_before:
            return "判据脚本自己变了"
        for name in watch:
            if hashlib.sha256((REPO / name).read_bytes()).hexdigest() != before[name]:
                return f"真仓库的 {name} 变了"
        if not sorted((REPO / ROOT_REL).rglob("*.swift")):
            return "真仓扫描面为空"
        return None
    case("末例：真仓库逐字节未变（脚本 + 基线 + 白名单 + 台账）", check_untouched)

    shutil.rmtree(scratch, ignore_errors=True)
    print(f"判据自检：{total} 条中 {total - len(failures)} 条达到预期")
    for failure in failures:
        print("   ❌ " + failure)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
