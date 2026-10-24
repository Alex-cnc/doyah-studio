#!/usr/bin/env python3
"""外观样张 ↔ 产品令牌「同源」门禁（队列 L-79 ㈡，闭环第 6 项）。

存在的理由（真现场）
--------------------
方案 D · 科技蓝的值 2026-09-29 落进了 `Core/DesignTokens.swift`，但**渲染样张的脚本自带一份
调色板** ⇒ 盘上跑的产品是方案 D、盘上出的样张是旧配色，而没有任何门禁会说话。

判据（任一不过即失败）
----------------------
A. **脚本里不许有调色板**（面 = `Scripts/**/*.swift` 全登记）：色值形状全集 = 6/8 位 `0x…`、
   `#RRGGBB[AA]`、浮点分量 `NSColor(…Red:…)`；判定物**先剥注释与字符串**（注释里的形状不再
   假阳，同一串真写成代码仍红）；豁免只认 `EXEMPT_HEX`（交通灯三色）。回归钉子 `FORBIDDEN_SHAPES`
   同样只在代码上判。
B. **必须真的接在真令牌上**：八族（`Surface.` … `Hairline.`）**每族 ≥1** + 总处数 ≥ `MIN_TOKEN_REFS`
   —— 只数总处数会被「只留一族补够处数」糊过去。
C. **渲染入口必须把令牌编进来**：入口里**未注释掉的** `swiftc` 命令行（含 `\` 续行）必须同时含
   `main.swift` + `Core/DesignTokens.swift` + `Core/DesignTheme.swift`。
D. **逐屏复查（机械版）· 双向**：扫描面 = `Package.swift` 各 target 的 `sources:` / `path:`（**现读对账**）；
   ① 不许残留方案 D 之前的旧值（`PRE_D_SWATCHES`）；② 不许**硬写方案 D 真值**（从令牌源现读 119 值）
   而不过令牌 —— 只放行真值源自身（`VALUE_HOME`）与断言位（`ASSERT_DIRS`：测试钉身份值）。
   目录面 / 后缀面 / 文件数 / 真值数四处与 `Scripts/design-mock-baseline.json` 上账。
E. **行为证据（macOS）**：真跑渲染入口 ⇒ 退出码 0、「全部样张自检通过」、张数 ≥ `MIN_SHEETS`、深色
   样张内容底带蓝调（`MIN_BLUE_TINT`）。**跳过时末行不许出现 ✅**（下游只认 `RESULT=` 行）。
F. 空跑防护：产品文件数 / 令牌值数 / 令牌引用处数 / 张数四条下限，任一踩线即红。

判据自己的证据：`--self-test` **31 例**（红/绿成对，夹具一律在临时目录，末例核对真仓文件逐字节未变）。

用法：
    python3 Scripts/check-design-mock-tokens.py              # 校验（闭环第 6 项）
    python3 Scripts/check-design-mock-tokens.py --no-render  # 只跑静态四条（末行 RESULT=SKIPPED）
    python3 Scripts/check-design-mock-tokens.py --self-test  # 门禁自己的证据（**31 例**）
"""

from __future__ import annotations

import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent

PACKAGE = "Package.swift"
MOCK = "Scripts/design-mock.swift"
ENTRY = "Scripts/render-design-mock.sh"
BASELINE = "Scripts/design-mock-baseline.json"

# ---- 台账式常量（每条都带理由；理由为空即红 —— 见 check_exemptions_have_reasons）------------

# 渲染脚本里允许出现的色值字面量：macOS 窗口左上角交通灯，系统外壳色，三色固定、不随主题变。
EXEMPT_HEX = {
    "0xFF5F57": "macOS 窗口交通灯 · 关闭（系统外壳色，不是设计令牌，不随主题变）",
    "0xFEBC2E": "macOS 窗口交通灯 · 最小化（同上）",
    "0x28C840": "macOS 窗口交通灯 · 全屏（同上）",
}

# 方案 D 之前的旧调色板（深色中性灰五档 + 文本三档 + 旧语法六档 + 旧浅色档 + 旧语义色）。
# 逐屏复查① 就是"拿这张清单去产品源码里找残留"。
PRE_D_SWATCHES = {
    "0x141619": "旧深色 window", "0x17191E": "旧深色 sidebar", "0x1F2229": "旧深色 content",
    "0x262A31": "旧深色 panel", "0x2F343C": "旧深色 raised",
    "0xE7E9EE": "旧深色 textPrimary", "0x9AA1AE": "旧深色 textSecondary", "0x6C7380": "旧深色 textTertiary",
    "0xE8E8EC": "旧浅色 window", "0xEDEDF2": "旧浅色 sidebar", "0xF6F6F9": "旧浅色 panel",
    "0x1D1D1F": "旧浅色 textPrimary", "0x6E6E73": "旧浅色 textSecondary", "0x9A9AA0": "旧浅色 textTertiary",
    "0x9BA8FF": "旧语法 keyword", "0x9ED37A": "旧语法 string", "0xE6C07B": "旧语法 number",
    "0x62C6C0": "旧语法 function", "0x8B33C4": "旧浅色语法 keyword", "0x1E7A3C": "旧浅色语法 string",
    "0xA35B00": "旧浅色语法 number", "0x0B6E99": "旧浅色语法 function",
    "0x4CC38A": "旧深色 success", "0x1E9E5A": "旧浅色 success",
    "0xE5534B": "旧深色 danger", "0xD03A32": "旧浅色 danger",
}

# 逐屏复查的豁免（路径 → 理由）：交互强调色是**另一条轴**（`AccentTheme`，用户可切的那三个），
# 与方案 D 的表面 / 文本 / 语法令牌无关；把它当"漏改"来判红就判错了。
EXEMPT_FILES = {
    "Core/AccentTheme.swift": "交互强调色（AccentTheme）：用户可切的选中条 / 主按钮 / 焦点环，"
                              "与方案 D 的令牌家族是两条轴，颜色本来就不在 D 的值表里",
    "Tests/AccentThemeTests.swift": "同一族的单测钉住那三个强调色的身份值（正是它们该被钉住的地方）",
    "Core/TerminalPalette.swift": "终端 16 色 ANSI 色板 —— 另一条轴（色槽按终端惯例排、对比度门槛有单测），"
                                  "其中与令牌同族的值是**有意同族**（源码注释已写明「与强调色鲸鱼蓝同族」）",
    "Tests/TerminalPaletteTests.swift": "同上：那 16 槽的身份值与对比度门槛正是这里该被钉住的地方",
}

# 判据 B：必须引用到的令牌符号（**八族**，每族 ≥1 是族级下限）。
TOKEN_SYMBOLS = ("Surface.", "TextTone.", "AccentFamily.", "SyntaxTone.", "StatusTone.",
                 "Radius.", "TypeScale.", "Hairline.")

# 判据 A 的回归钉子：这些形态一旦回来，就是"第二份调色板"又长出来了。
FORBIDDEN_SHAPES = ("static func proDark()", "static func nativeLight()", "Theme.hex(",
                    "NativeLight", "ProDark")

MIN_TOKEN_REFS = 34         # 判据 B 总处数下限（实测 34 处 · 棘轮）
MIN_TOKEN_FAMILIES = 8      # 判据 B 族级下限（八族每族 ≥1）
MIN_TOKEN_VALUES = 110      # 判据 D ② 真值源下限（实测 119 值 · 棘轮）
MIN_BLUE_TINT = 20          # 判据 E 蓝调门槛（实测定的：方案 D Δ≈45 ↔ 旧灰 Δ≈11）
MIN_SHEETS = 15             # 判据 E 张数下限（实测 15 张 · 棘轮）
MIN_PRODUCT_FILES = 600     # 判据 F 产品文件数下限（实测 628 · 棘轮另钉基线）

COLOR_HEX = re.compile(r"0x[0-9A-Fa-f]{6,8}\b")
COLOR_HASH = re.compile(r"#[0-9A-Fa-f]{6,8}\b")
# 浮点分量写法（P3）：`NSColor(calibratedRed: 0.078, …)` / `Color(red: …)`
COLOR_FLOAT = re.compile(r"(?:\bNSColor|\bUIColor|\bColor)\s*\(\s*[A-Za-z]*[Rr]ed(?:Component)?\s*:")
# 判据 D ② 只判「**取色上下文**」里的真值 —— 位掩码那种十六进制形状（`seed & 0xFFFFFF`）不是颜色。
COLOR_CONTEXT = re.compile(r"hex\s*:|\b(?:Color|NSColor|UIColor|RGBA?)\s*\(")
SAMPLE_LINE = re.compile(r"取样\s+(深色|浅色)-[^:]*:\s*(.*)")
SAMPLE_ENTRY = re.compile(r"内容\s+#([0-9A-Fa-f]{6})")
PASS_LINE = "全部样张自检通过"
SHEET_LINE = re.compile(r"^写出\s+(.+\.png)", re.M)

# 判据 D ② 的登记：真值住在哪里。真值源自身的字面量**不是**"硬写"，而是真值本身。
VALUE_HOME = {
    "Core/DesignTokens.swift": "设计令牌的角色语义表 —— 方案 D 的真值就住这里（判据 D ② 的真值源）",
    "Core/DesignTheme.swift": "主题值表（L-80 ㈠ 起按主题分组）—— 同样是真值源，不是硬写",
}

# 断言位（判据 D ② 的登记）：测试钉住令牌身份值 = 正是该被钉住的地方（钉错值就红）。
# 只对**新值轴**生效；旧值轴（判据 D ①）不受此表影响，仍全扫。
ASSERT_DIRS = {
    "Tests": "单测钉住令牌身份值（真值出现在断言里是行为，不是漏改）",
    "TestsUISnapshot": "快照 / 端上探针测试同样钉住身份值",
    "TestsPlatform": "平台层测试同上",
}

# 判据 D 的扫描面后缀：这些后缀的文件按源码判（色值字面量 + 注释剥离）。
SCAN_SUFFIXES = (".swift", ".m", ".h", ".mm")

# 面内其余后缀必须在下面显式登记并给理由（否则报红）—— 这就是 P9「调色板搬进 .metal/.json 即出面」的洞。
SKIP_SUFFIX_REASONS = {
    ".png": "位图资源（样张 / 截图）—— 二进制，不可能承载源码色值",
    ".icns": "图标容器（同上）",
    ".xlsx": "测试夹具（XLSX 读写用例的输入）—— 表格数据，不是配色",
    ".entitlements": "签名权益清单 —— 平台配置，不是源码",
    ".md": "说明文档 —— 不参与产品构建（历史行里本来就写旧值）",
    ".json": "清单 / 台账 —— 同上",
    ".jpg": "壁纸位图（`App/Resources/wallpaper-*.jpg`，随包附带）—— 二进制资源，不可能承载源码色值",
}

# 判据 A 的文件面台账：`Scripts/**/*.swift` 每一份都要登记角色（新脚本出现即红）。
SCRIPT_ROLES = {
    "Scripts/design-mock.swift": "样张渲染脚本（判据 A/B/C 的主面 · 真令牌取色）",
    "Scripts/icon-sanity-check.swift": "图标体检（只读产物 PNG，不画 UI 色 ⇒ 不引设计令牌）",
    "Scripts/make-app-icon.swift": "图标生成（产物是图标不是样张）",
    "Scripts/render-store-shot.swift": "商店截图渲染（套系统控件截图，不取设计令牌）",
}

# 唯一渲染脚本面：第二个「引令牌画样张」的脚本出现即红（P11 的洞）。
RENDER_SCRIPTS = {"Scripts/design-mock.swift": "唯一渲染脚本面 —— 引设计令牌画样张的只许这一份"}


class Issue:
    def __init__(self, where: str, reason: str):
        self.where = where
        self.reason = reason

    def __str__(self) -> str:
        return f"{self.where}: {self.reason}"


def normalize(literal: str) -> str:
    """色值字面量归一化：`0x…` 统一成 `0x` + 大写；`#…` 统一成大写（台账键就是这个形状）。"""
    return ("0x" + literal[2:].upper()) if literal.lower().startswith("0x") else literal.upper()


def color_values(segment: str) -> list[str]:
    """一段**代码**里的色值字面量（形状全集：6/8 位 `0x…` 与 `#RRGGBB[AA]`）。"""
    return [normalize(h) for h in COLOR_HEX.findall(segment)] + \
           [normalize(h) for h in COLOR_HASH.findall(segment)]


def strip_shell_comments(text: str) -> str:
    """shell 注释（`#` 到行尾，引号内不算）换成空格 —— 保留换行与行号。

    边界（如实登记）：`${#var}` / `${v#p}` 这类参数展开的 `#` 前面没有空白 ⇒ 不当注释；
    here-doc（`<<EOF`）不解析。本入口不用这两种形态。
    """
    out = []
    for line in text.split("\n"):
        quote, cut = None, len(line)
        for index, char in enumerate(line):
            if quote:
                if char == quote:
                    quote = None
                continue
            if char in "\"'":
                quote = char
                continue
            if char == "#" and (index == 0 or line[index - 1].isspace()):
                cut = index
                break
        out.append(line[:cut])
    return "\n".join(out)

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

# ---------------------------------------------------------------- 判据 D 的面（现读对账）

def package_surfaces(root: pathlib.Path) -> tuple[list[str], list[Issue]]:
    """判据 D 的扫描面 = `Package.swift` 各 target 的 `sources:` / `path:`（**现读**，不写死目录名）。"""
    path = root / PACKAGE
    if not path.exists():
        return [], [Issue(PACKAGE, "Package.swift 不在盘上 —— 扫描面无法对账（不许通过）")]
    text = path.read_text(encoding="utf-8")
    marks = [m.start() for m in re.finditer(r"\.(?:target|executableTarget|testTarget)\(", text)]
    if not marks:
        return [], [Issue(PACKAGE, "Package.swift 里找不到任何 target 块 —— 面为空不许通过")]
    dirs: list[str] = []
    for index, start in enumerate(marks):
        block = text[start: marks[index + 1] if index + 1 < len(marks) else len(text)]
        sources = re.search(r"sources:\s*\[(.*?)\]", block, re.S)
        if sources:
            dirs += [item.strip().strip('"') for item in sources.group(1).split(",") if item.strip()]
            continue
        single = re.search(r'path:\s*"([^"]+)"', block)
        if single:
            dirs.append(single.group(1))
    return sorted(set(dirs)), []


def read_token_values(root: pathlib.Path) -> tuple[set[str], list[Issue]]:
    """判据 D ② 的真值源：从 `VALUE_HOME` 现读方案 D 的真值（值表改了，判据不用改）。"""
    values: set[str] = set()
    issues: list[Issue] = []
    for relative in VALUE_HOME:
        path = root / relative
        if not path.exists():
            issues.append(Issue(relative, "判据 D ② 的真值源不在盘上 —— 真值表为空不许通过"))
            continue
        code = strip_noncode(path.read_text(encoding="utf-8"))
        values |= set(color_values(code))
    if len(values) < MIN_TOKEN_VALUES:
        issues.append(Issue("判据 D ②", f"从真值源现读到 {len(values)} 个色值（下限 {MIN_TOKEN_VALUES}）"
                                         f" —— 真值表被削过，不许通过"))
    return values, issues


def measure_surface(root: pathlib.Path) -> tuple[dict, list[Issue]]:
    """量一遍扫描面：目录 / 后缀 / 源文件数 / 真值数（判据 D 与基线上账共用）。"""
    dirs, issues = package_surfaces(root)
    suffixes: dict[str, int] = {}
    judged: list[str] = []
    missing: list[str] = []
    for directory in dirs:
        base = root / directory
        if not base.exists():
            missing.append(directory)
            continue
        for path in sorted(base.rglob("*")):
            if not path.is_file():
                continue
            suffixes[path.suffix] = suffixes.get(path.suffix, 0) + 1
            if path.suffix in SCAN_SUFFIXES:
                judged.append(path.relative_to(root).as_posix())
    values, value_issues = read_token_values(root)
    issues += value_issues
    return {"dirs": dirs, "suffixes": suffixes, "judged": sorted(judged),
            "scannedFiles": len(judged), "tokenValues": len(values), "missing": missing,
            "values": values}, issues


def surface_issues(snapshot: dict, baseline: dict | None) -> list[Issue]:
    """判据 D 的面上账：目录 / 后缀**增减都报红**；文件数与真值数按棘轮（只许涨不许跌）。"""
    issues: list[Issue] = []
    for directory in snapshot["missing"]:
        issues.append(Issue(directory, "扫描面目录不在盘上 —— 面被削过，不许通过"))
    if not baseline:
        issues.append(Issue(BASELINE, f"面对账基线缺失（{BASELINE}）—— 面没有钉，不许通过"))
        return issues
    if snapshot["dirs"] != baseline.get("dirs"):
        issues.append(Issue("判据 D 目录面", f"扫描面目录与基线不一致：现读 {snapshot['dirs']} ↔ "
                                           f"基线 {baseline.get('dirs')} —— 目录增减都要跟版"
                                           f"（改 {BASELINE} 并写明理由）"))
    now_suffixes, base_suffixes = snapshot["suffixes"], baseline.get("suffixes") or {}
    if sorted(now_suffixes) != sorted(base_suffixes):
        extra = sorted(set(now_suffixes) - set(base_suffixes))
        gone = sorted(set(base_suffixes) - set(now_suffixes))
        issues.append(Issue("判据 D 后缀面", f"面内后缀与基线不一致（新增 {extra} / 消失 {gone}）"
                                            f" —— 每种后缀都要在 SCAN_SUFFIXES 或 SKIP_SUFFIX_REASONS 里登记"))
    unknown = sorted(set(now_suffixes) - set(SCAN_SUFFIXES) - set(SKIP_SUFFIX_REASONS))
    if unknown:
        issues.append(Issue("判据 D 后缀面", f"面内出现未登记的后缀 {unknown} —— 要么扫、"
                                            f"要么写进 SKIP_SUFFIX_REASONS 并给理由"))
    if snapshot["scannedFiles"] < baseline.get("scannedFiles", 0):
        issues.append(Issue("判据 D 面", f"只扫到 {snapshot['scannedFiles']} 个产品源文件"
                                        f"（基线 {baseline.get('scannedFiles')}）—— 削面，棘轮只许涨不许跌"))
    if snapshot["tokenValues"] < baseline.get("tokenValues", 0):
        issues.append(Issue("判据 D ②", f"真值源现读 {snapshot['tokenValues']} 个色值"
                                       f"（基线 {baseline.get('tokenValues')}）—— 真值表被削过"))
    return issues


# ---------------------------------------------------------------- 判据 A / B

def palette_scripts(root: pathlib.Path) -> list[str]:
    """判据 A 的文件面：`Scripts/**/*.swift` 全登记（不写死单个文件名 —— P11 的洞）。"""
    return sorted(path.relative_to(root).as_posix() for path in (root / "Scripts").rglob("*.swift"))


def check_palette_scripts(root: pathlib.Path) -> tuple[list[Issue], int, dict[str, int]]:
    issues: list[Issue] = []
    scripts = palette_scripts(root)
    if not scripts:
        issues.append(Issue("Scripts", "Scripts/ 下没有任何 .swift —— 判据面为空不许通过"))
    for relative in scripts:
        if relative not in SCRIPT_ROLES:
            issues.append(Issue(relative, "未登记的脚本 —— `Scripts/**/*.swift` 每一份都要在 "
                                          "SCRIPT_ROLES 里登记角色（新脚本出现即红）"))
    for relative in SCRIPT_ROLES:
        if not (root / relative).exists():
            issues.append(Issue(relative, "SCRIPT_ROLES 里登记的脚本不在盘上 —— 死登记"
                                          "（脚本搬家 / 改名要跟版）"))
    refs: dict[str, int] = {}
    for relative in scripts:
        code = strip_noncode((root / relative).read_text(encoding="utf-8"))
        for lineno, line in enumerate(code.split("\n"), 1):
            for hit in color_values(line):
                if hit in EXEMPT_HEX:
                    continue
                issues.append(Issue(f"{relative}:{lineno}",
                                    f"脚本里出现了色值字面量 {hit} —— 样张必须从 "
                                    f"`Core/DesignTokens.swift` 取色；确属系统外壳色请登记进 "
                                    f"EXEMPT_HEX 并写理由"))
            if COLOR_FLOAT.search(line):
                issues.append(Issue(f"{relative}:{lineno}",
                                    "脚本里出现了浮点分量写法（`…Red:` 那种）—— "
                                    "这是「自带一份调色板」的另一种形状，必须走令牌"))
            for shape in FORBIDDEN_SHAPES:
                if shape in line:
                    issues.append(Issue(f"{relative}:{lineno}",
                                        f"又出现了「第二份调色板」的形态：{shape}"))
        counts = {symbol: code.count(symbol) for symbol in TOKEN_SYMBOLS}
        refs[relative] = sum(counts.values())
        if relative in RENDER_SCRIPTS:
            if refs[relative] < MIN_TOKEN_REFS:
                issues.append(Issue(relative, f"对真令牌的引用只有 {refs[relative]} 处"
                                              f"（下限 {MIN_TOKEN_REFS}）—— 引用被删光就是空跑"))
            empty = [symbol for symbol in TOKEN_SYMBOLS if counts[symbol] < 1]
            if len(TOKEN_SYMBOLS) - len(empty) < MIN_TOKEN_FAMILIES or empty:
                issues.append(Issue(relative, f"令牌引用缺族 {empty} —— 判据 B 是**族级**下限"
                                              f"（八族每族 ≥1），只留一族补够处数是空跑"))
        elif refs[relative] > 0:
            issues.append(Issue(relative, f"这份脚本引用了设计令牌（{refs[relative]} 处）却没登记进 "
                                          f"RENDER_SCRIPTS —— 第二个渲染脚本出现即红"))
    return issues, len(scripts), refs


# ---------------------------------------------------------------- 判据 C（入口）

def check_entry(root: pathlib.Path) -> list[Issue]:
    path = root / ENTRY
    if not path.exists():
        return [Issue(ENTRY, "渲染入口不存在（判据面为空 ⇒ 不许通过）")]
    lines = strip_shell_comments(path.read_text(encoding="utf-8")).split("\n")
    start, region = None, []
    for index, line in enumerate(lines):
        if re.search(r"\bswiftc\b", line):
            start, region = index, [line]
            while region[-1].rstrip().endswith("\\") and index + len(region) < len(lines):
                region.append(lines[index + len(region)])
            break
    if start is None:
        return [Issue(ENTRY, "找不到**未注释掉的** `swiftc` 命令行 —— 把编译命令注释掉等于入口不再"
                             "编译任何东西，那时仍报绿就是假绿（判据 C 的前提没了）")]
    command = "\n".join(region)
    wanted = (
        ("main.swift", "入口没有把渲染脚本当 `main.swift` 编译（swiftc 只在文件名叫 main.swift 时"
                       "才允许顶层代码）"),
        ("Core/DesignTokens.swift", "编译命令里没有 `Core/DesignTokens.swift` —— 那样样张就回到"
                                   "「自带一份调色板」的老路"),
        ("Core/DesignTheme.swift", "编译命令里没有 `Core/DesignTheme.swift`（主题值表）—— 样张会"
                                  "退化成「默认主题之外什么都不认」"),
    )
    issues: list[Issue] = []
    for needle, why in wanted:
        if needle not in command:
            issues.append(Issue(f"{ENTRY}:{start + 1}",
                                f"swiftc 命令行（第 {start + 1} 行起）里找不到 `{needle}`：{why}"))
    return issues


# ---------------------------------------------------------------- 判据 D（逐屏复查 · 双向）

def check_product_sources(root: pathlib.Path, judged: list[str],
                          new_values: set[str]) -> tuple[list[Issue], int]:
    issues: list[Issue] = []
    for relative in judged:
        if relative in EXEMPT_FILES:
            continue
        code = strip_noncode((root / relative).read_text(encoding="utf-8", errors="ignore"))
        assertion_site = any(relative.startswith(directory + "/") for directory in ASSERT_DIRS)
        for lineno, line in enumerate(code.split("\n"), 1):
            for hit in color_values(line):
                if hit in PRE_D_SWATCHES:
                    issues.append(Issue(f"{relative}:{lineno}",
                                        f"残留方案 D 之前的旧调色板值 {hit}"
                                        f"（{PRE_D_SWATCHES[hit]}）—— 这一屏漏改了"))
                elif (hit in new_values and relative not in VALUE_HOME
                      and not assertion_site and COLOR_CONTEXT.search(line)):
                    issues.append(Issue(f"{relative}:{lineno}",
                                        f"硬写方案 D 真值 {hit} 而不过令牌 —— 产品代码的色值必须来自 "
                                        f"`Core/DesignTokens.swift`（真值源自身与断言位 "
                                        f"{sorted(ASSERT_DIRS)} 除外）"))
    return issues, len(judged)


# ---------------------------------------------------------------- 判据 E（行为证据）

def assess_render_output(output: str) -> list[Issue]:
    issues: list[Issue] = []
    if PASS_LINE not in output:
        issues.append(Issue("render", "渲染收尾行里没有「全部样张自检通过」—— 样张自检未跑或未过"))
    sheets = SHEET_LINE.findall(output)
    if len(sheets) < MIN_SHEETS:
        issues.append(Issue("render", f"本轮只写出 {len(sheets)} 张样张（下限 {MIN_SHEETS}）"))
    dark_content = None
    for kind, rest in SAMPLE_LINE.findall(output):
        match = SAMPLE_ENTRY.search(rest)
        if kind == "深色" and match and dark_content is None:
            dark_content = match.group(1)
    if dark_content is None:
        issues.append(Issue("render", "输出里找不到深色样张的「内容」取样值 —— 判据读不到东西就不许通过"))
    else:
        red, blue = int(dark_content[0:2], 16), int(dark_content[4:6], 16)
        if blue - red <= MIN_BLUE_TINT:
            issues.append(Issue("render",
                                f"深色样张的内容底 {dark_content} 不够蓝（B−R = {blue - red}/255 ≤ "
                                f"{MIN_BLUE_TINT}）—— 方案 D 是深海军蓝（实测 Δ≈45）、旧中性灰 Δ≈11，"
                                f"这是「换了值但样张还是旧配色」的现场"))
    return issues


def run_render(root: pathlib.Path) -> tuple[list[Issue], str]:
    entry = root / ENTRY
    with tempfile.TemporaryDirectory(prefix="doyah-mock-") as tmp:
        proc = subprocess.run(["/bin/bash", str(entry), tmp], cwd=str(root),
                              capture_output=True, text=True)
        output = (proc.stdout or "") + (proc.stderr or "")
        issues = assess_render_output(output)
        if proc.returncode != 0:
            issues.insert(0, Issue("render", f"渲染入口退出码 {proc.returncode}（要求 0）"))
    return issues, output


# ---------------------------------------------------------------- 台账理由 / 基线 / 判词

def check_exemptions_have_reasons() -> list[Issue]:
    issues: list[Issue] = []
    tables = ((EXEMPT_HEX, "EXEMPT_HEX"), (EXEMPT_FILES, "EXEMPT_FILES"),
              (PRE_D_SWATCHES, "PRE_D_SWATCHES"), (VALUE_HOME, "VALUE_HOME"),
              (ASSERT_DIRS, "ASSERT_DIRS"), (SKIP_SUFFIX_REASONS, "SKIP_SUFFIX_REASONS"),
              (SCRIPT_ROLES, "SCRIPT_ROLES"), (RENDER_SCRIPTS, "RENDER_SCRIPTS"))
    for table, name in tables:
        for key, reason in table.items():
            if not reason or not reason.strip():
                issues.append(Issue(name, f"{key} 的理由是空的 —— 台账必须写明理由，"
                                          f"否则就是把判据关掉"))
    return issues


def load_baseline(root: pathlib.Path) -> tuple[dict | None, list[Issue]]:
    path = root / BASELINE
    if not path.exists():
        return None, [Issue(BASELINE, "面对账基线不在盘上 —— 面没有钉（先落基线再判）")]
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return None, [Issue(BASELINE, f"面对账基线读不出来：{exc}")]
    if not isinstance(data, dict):
        return None, [Issue(BASELINE, "面对账基线的形状不对（要一个对象）")]
    return data, []


def verdict_lines(issues: list[Issue], render_skipped: bool) -> list[str]:
    """末两行 = 机械可识别的判词：**跳过不许打 ✅**（E 的跳过不是通过）。"""
    if issues:
        return [f"❌ {len(issues)} 处未过（上面逐条点名）", "RESULT=FAIL"]
    if render_skipped:
        return ["⏭ 静态四条绿，但判据 E 跳过 —— **本轮不算通过**（跳过 ≠ 通过）", "RESULT=SKIPPED"]
    return ["✅ 样张与产品同源：脚本无自带调色板 / 入口接真令牌（编译命令未注释）/ "
            "产品源码无旧值残留也无真值硬写 / 样张深色底带蓝调", "RESULT=PASS"]

# ---------------------------------------------------------------- 自检

def _sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _static_report(root: pathlib.Path, baseline: dict | None) -> tuple[list[Issue], dict, int, dict]:
    """静态四条（A/B + C + D）各判一遍 —— main 与自检共用同一条路径，读数可比。"""
    issues = check_exemptions_have_reasons()
    palette_issues, scripts, refs = check_palette_scripts(root)
    issues += palette_issues
    issues += check_entry(root)
    snapshot, measure_issues = measure_surface(root)
    issues += measure_issues
    issues += surface_issues(snapshot, snapshot if baseline is None else baseline)
    product_issues, _ = check_product_sources(root, snapshot["judged"], snapshot["values"])
    issues += product_issues
    return issues, snapshot, scripts, refs


def self_test() -> int:
    cases: list[tuple[str, bool, list[Issue]]] = []
    real_paths = [ROOT / MOCK, ROOT / ENTRY, ROOT / BASELINE]
    before = {path: _sha(path) for path in real_paths if path.exists()}
    fixture_package = """// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Fixture",
    targets: [
        .target(name: "DoyahCore", path: "Core"),
        .executableTarget(name: "DoyahStudioApp", path: "App"),
        .testTarget(name: "DoyahCoreTests", path: "Tests"),
        .testTarget(name: "DoyahPlatformTests", path: "TestsPlatform"),
    ]
)
"""

    with tempfile.TemporaryDirectory(prefix="doyah-mock-selftest-") as tmp:
        def fresh(name: str) -> pathlib.Path:
            """夹具一律在临时目录：真仓两份令牌与渲染脚本 / 入口都拷一份进去。"""
            fixture = pathlib.Path(tmp) / name
            (fixture / "Scripts").mkdir(parents=True, exist_ok=True)
            for source in sorted((ROOT / "Scripts").glob("*.swift")):
                shutil.copy(source, fixture / "Scripts" / source.name)
            shutil.copy(ROOT / ENTRY, fixture / ENTRY)
            for relative in VALUE_HOME:
                target = fixture / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy(ROOT / relative, target)
            for directory in ("App", "Tests", "TestsPlatform"):
                (fixture / directory).mkdir(exist_ok=True)
            (fixture / "App" / "SampleView.swift").write_text(
                "import SwiftUI\nlet background = Surface.window\n", encoding="utf-8")
            (fixture / PACKAGE).write_text(fixture_package, encoding="utf-8")
            return fixture

        base = fresh("green")
        cases.append(("① 好情况（静态四条全绿）", False, _static_report(base, None)[0]))

        def palette_of(fixture: pathlib.Path) -> list[Issue]:
            return check_palette_scripts(fixture)[0]

        def append(path: pathlib.Path, extra: str) -> None:
            path.write_text(path.read_text(encoding="utf-8") + extra, encoding="utf-8")

        bad = fresh("bad-hex")
        append(bad / MOCK, "\nlet legacyWindow = NSColor(mockHex: 0x1F2229)\n")
        cases.append(("② 脚本里色值字面量（真写成代码）", True, palette_of(bad)))

        comment = fresh("green-comment")
        append(comment / MOCK, "\n// 历史：旧深色 window 0x141619（仅注释说明，已废弃）\n")
        cases.append(("③ 对照臂：同一串在注释里（绿）", False, palette_of(comment)))

        shape = fresh("green-comment-shape")
        append(shape / MOCK, "\n// 曾经有过 static func proDark() { }（已删，形态记在这里）\n")
        cases.append(("④ 注释里的「第二份调色板」形态（绿）", False, palette_of(shape)))

        hex8 = fresh("bad-hex8")
        append(hex8 / MOCK, "\nlet deep = NSColor(mockHex8: 0x141619FF)\n")
        cases.append(("⑤ 8 位色值 0x…FF（旧版隐形）", True, palette_of(hex8)))

        floaty = fresh("bad-float")
        append(floaty / MOCK, "\nlet raw = NSColor(calibratedRed: 0.078, green: 0.086, blue: 0.098, alpha: 1)\n")
        cases.append(("⑥ 浮点分量写法（P3）", True, palette_of(floaty)))

        family = fresh("bad-family")
        text = (family / MOCK).read_text(encoding="utf-8")
        for symbol in TOKEN_SYMBOLS:
            text = text.replace(symbol, "")
        text += "\n" + "\n".join(f"let a{index} = Surface.window" for index in range(40)) + "\n"
        (family / MOCK).write_text(text, encoding="utf-8")
        cases.append(("⑦ 只留一族令牌补够处数（族级下限）", True, palette_of(family)))

        starved = fresh("bad-refs")
        text = (starved / MOCK).read_text(encoding="utf-8")
        for symbol in TOKEN_SYMBOLS:
            text = text.replace(symbol, "")
        (starved / MOCK).write_text(text, encoding="utf-8")
        cases.append(("⑧ 令牌引用被删光（空跑）", True, palette_of(starved)))

        relapse = fresh("bad-relapse")
        append(relapse / MOCK, "\nstatic func proDark() { }\n")
        cases.append(("⑨ 旧调色板函数形态真写回代码", True, palette_of(relapse)))

        commented = fresh("bad-entry-comment")
        entry_text = (commented / ENTRY).read_text(encoding="utf-8")
        (commented / ENTRY).write_text(entry_text.replace("xcrun swiftc", "# xcrun swiftc"),
                                       encoding="utf-8")
        cases.append(("⑩ 入口把真 swiftc 行注释掉（文件清单仍在）", True, check_entry(commented)))

        blocked = fresh("bad-entry-block")
        entry_text = (blocked / ENTRY).read_text(encoding="utf-8")
        lines = ["# " + line if ("${BUILD}/" in line or "${ROOT}/Core/" in line) else line
                 for line in entry_text.split("\n")]
        (blocked / ENTRY).write_text("\n".join(lines), encoding="utf-8")
        cases.append(("⑪ 入口整段编译命令注释掉", True, check_entry(blocked)))

        missing_token = fresh("bad-entry-token")
        entry_text = (missing_token / ENTRY).read_text(encoding="utf-8")
        (missing_token / ENTRY).write_text(
            entry_text.replace("Core/DesignTokens.swift", "Core/Nothing.swift"), encoding="utf-8")
        cases.append(("⑫ 命令行里少了 DesignTokens.swift", True, check_entry(missing_token)))

        missing_theme = fresh("bad-entry-theme")
        entry_text = (missing_theme / ENTRY).read_text(encoding="utf-8")
        (missing_theme / ENTRY).write_text(
            entry_text.replace("Core/DesignTheme.swift", "Core/Nothing.swift"), encoding="utf-8")
        cases.append(("⑬ 命令行里少了 DesignTheme.swift", True, check_entry(missing_theme)))

        hardcoded = fresh("bad-newvalue")
        (hardcoded / "App" / "Probe.swift").write_text(
            "import AppKit\nlet deepContent = NSColor(mockHex: 0x0B1A2A)\n", encoding="utf-8")
        cases.append(("⑭ 产品源码硬写方案 D 真值（App/）", True, _static_report(hardcoded, None)[0]))

        bytoken = fresh("green-tokenref")
        (bytoken / "App" / "Probe2.swift").write_text(
            "import SwiftUI\nlet deepContent = Surface.content\n", encoding="utf-8")
        cases.append(("⑮ 对照臂：同一处走令牌（绿）", False, _static_report(bytoken, None)[0]))

        platform = fresh("bad-platform")
        (platform / "TestsPlatform" / "Probe.swift").write_text(
            "let legacy = 0x141619\n", encoding="utf-8")
        cases.append(("⑯ TestsPlatform 面内在扫（旧值 ⇒ 红）", True, _static_report(platform, None)[0]))

        pinned = fresh("green-assert")
        (pinned / "Tests" / "Probe.swift").write_text(
            "let identity = 0x0B1A2A\n", encoding="utf-8")
        cases.append(("⑰ 断言位（Tests/）钉住真值（绿）", False, _static_report(pinned, None)[0]))

        metal = fresh("bad-metal")
        (metal / "App" / "Probe.metal").write_text("// 0x141619\n", encoding="utf-8")
        cases.append(("⑱ 面内未登记后缀 .metal", True, _static_report(metal, None)[0]))

        unregistered = fresh("bad-script")
        (unregistered / "Scripts" / "probe.second-mock.swift").write_text(
            "let palette = 0x141619\n", encoding="utf-8")
        cases.append(("⑲ Scripts/ 下未登记的第二个脚本", True, _static_report(unregistered, None)[0]))

        snapshot = _static_report(base, None)[1]
        shaved = dict(snapshot, scannedFiles=snapshot["scannedFiles"] + 1)
        cases.append(("⑳ 基线与现读不一致（削面）", True, surface_issues(snapshot, shaved)))

        ghost = dict(snapshot, dirs=sorted(snapshot["dirs"] + ["Ghost"]))
        cases.append(("㉑ 基线含不在盘上的面目录", True, surface_issues(snapshot, ghost)))

        exempt = fresh("green-exempt")
        (exempt / "Core" / "AccentTheme.swift").write_text("accentHex: 0x4E6FFF,\n", encoding="utf-8")
        cases.append(("㉒ AccentTheme 豁免（绿）", False, _static_report(exempt, None)[0]))

        mask = fresh("green-mask")
        (mask / "App" / "Mask.swift").write_text(
            "var seed: UInt64 = 1\nlet low = Double((seed >> 33) & 0xFFFFFF) / Double(0xFFFFFF)\n",
            encoding="utf-8")
        cases.append(("㉓ 位掩码的十六进制形状（不是取色 ⇒ 绿）", False, _static_report(mask, None)[0]))

        axis = fresh("green-terminal-axis")
        (axis / "Core" / "TerminalPalette.swift").write_text(
            "let cursor = RGB(hex: 0x6E8BFF)\n", encoding="utf-8")
        cases.append(("㉔ 终端色板（另一条轴登记豁免 ⇒ 绿）", False, _static_report(axis, None)[0]))

        cases.append(("㉕ 渲染输出里深色底不带蓝调", True,
                      assess_render_output("写出 样张-深色-D-科技蓝.png\n" + PASS_LINE + "（12 项）\n"
                                           "  取样 深色-D-科技蓝: 底 #21242C 内容 #1F2229\n" +
                                           "".join(f"写出 样张-{i}.png\n" for i in range(16)))))
        cases.append(("㉖ 渲染输出深色底带蓝调（绿）", False,
                      assess_render_output("".join(f"写出 样张-{i}.png\n" for i in range(16)) +
                                           PASS_LINE + "（72 项）\n  取样 深色-D-科技蓝: 内容 #0B2338\n")))
        cases.append(("㉗ 渲染输出缺自检收尾行", True,
                      assess_render_output("".join(f"写出 样张-{i}.png\n" for i in range(16)) +
                                           "  取样 深色-D-科技蓝: 内容 #0B2338\n")))

        verdict = verdict_lines([], True)
        skipped_ok = "✅" not in "\n".join(verdict) and verdict[-1] == "RESULT=SKIPPED"
        cases.append(("㉘ 判据 E 跳过时末行不许出现 ✅", False,
                      [] if skipped_ok else [Issue("verdict", "跳过时末行出现了 ✅ 或缺 RESULT=SKIPPED")]))

        global EXEMPT_HEX
        saved = dict(EXEMPT_HEX)
        EXEMPT_HEX["0xFF5F57"] = ""
        try:
            cases.append(("㉙ 台账理由为空", True, check_exemptions_have_reasons()))
        finally:
            EXEMPT_HEX = saved

        cases.append(("㉚ 面对账基线不在盘上", True, load_baseline(base)[1]))

    failures = 0
    for name, expect_red, issues_of_case in cases:
        ok = bool(issues_of_case) == expect_red
        if not ok:
            failures += 1
        print(f"{'✅' if ok else '❌'} {name}：{'报红' if issues_of_case else '绿'}"
              f"（期望{'报红' if expect_red else '绿'}）"
              + (f" —— {issues_of_case[0]}" if issues_of_case and not expect_red else ""))

    after = {path: _sha(path) for path in real_paths if path.exists()}
    unchanged = before == after
    if not unchanged:
        failures += 1
    print(f"{'✅' if unchanged else '❌'} 真仓库三份文件（渲染脚本 / 入口 / 基线）逐字节未变")
    total = len(cases) + 1
    if failures:
        print(f"{total - failures}/{total} 例达到预期")
    else:
        print(f"全部 {total} 例达到预期（自检 exit 0）")
    return 0 if failures == 0 else 1


# ---------------------------------------------------------------- 主流程

KNOWN_ARGS = ("--no-render", "--self-test")


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return self_test()
    unknown = [arg for arg in argv if arg not in KNOWN_ARGS]
    if unknown:
        print(f"❌ 未知参数 {unknown} —— 参数面要显式（旧版照跑 rc=0）")
        print("RESULT=FAIL")
        return 2

    baseline, issues = load_baseline(ROOT)
    static_issues, snapshot, scripts, refs = _static_report(ROOT, baseline)
    issues += static_issues
    print("==> 外观样张 ↔ 产品令牌同源（L-79 ㈡）")
    print(f"    ① 脚本面：`Scripts/**/*.swift` 登记 {len(SCRIPT_ROLES)} 份、在盘 {scripts} 份；"
          f"渲染脚本令牌引用 {refs.get(MOCK, 0)} 处（八族 · 下限 {MIN_TOKEN_REFS}）"
          f"（豁免 {len(EXEMPT_HEX)} 个系统外壳色）")
    print(f"    ② 渲染入口 {ENTRY}：未注释的 swiftc 命令行含 main.swift + 两份令牌"
          f"（{'是' if not check_entry(ROOT) else '否'}）")
    print(f"    ③ 逐屏复查：{len(snapshot['dirs'])} 个 target 面 / 扫了 {snapshot['scannedFiles']} "
          f"个产品源文件 / 真值源 {snapshot['tokenValues']} 值"
          f"（豁免 {len(EXEMPT_FILES)} 个文件 + 断言位 {len(ASSERT_DIRS)} 个目录）")
    if snapshot["scannedFiles"] < MIN_PRODUCT_FILES:
        issues.append(Issue("逐屏复查", f"只扫到 {snapshot['scannedFiles']} 个产品源文件"
                                       f"（下限 {MIN_PRODUCT_FILES}）—— 扫描面被削过，不许通过"))

    render_skipped = "--no-render" in argv or os.environ.get("DOYAH_PLATFORM", "macos") != "macos"
    if render_skipped:
        print("    ④ 行为证据（真跑渲染 + 深色底蓝调）：⏭ 跳过"
              + ("（--no-render）" if "--no-render" in argv else "（非 macOS：缺 Xcode 工具链）"))
        print("       —— **跳过 ≠ 通过**：末行只出 RESULT=SKIPPED，不出现 ✅")
    else:
        render_issues, output = run_render(ROOT)
        issues += render_issues
        sheets = len(SHEET_LINE.findall(output))
        print(f"    ④ 行为证据：渲染 {sheets} 张样张、自检"
              f"{'通过' if not render_issues else '未过'}，深色底蓝调已判"
              f"（{'绿' if not render_issues else '红'}）")

    if issues:
        print(f"\n❌ {len(issues)} 处未过：")
        for issue in issues:
            print(f"   · {issue}")
    for line in verdict_lines(issues, render_skipped):
        print(line)
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
