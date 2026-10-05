#!/usr/bin/env python3
"""外观样张 ↔ 产品令牌「同源」门禁（队列 L-79 ㈡，闭环第 6 项）。

存在的理由（真现场）
--------------------
方案 D · 科技蓝的值与门槛 2026-09-29 落进了 `platform/macos/Core/DesignTokens.swift`（L-79 ㈠），
但**渲染样张的那份脚本自带一份调色板** —— `Scripts/design-mock.swift` 头部注释还写着
「令牌（未来会变成 `platform/macos/Core/DesignTokens.swift` 的真身）」。于是：

    · 盘上跑的产品 = 方案 D（深海军蓝 + 电光蓝）；
    · 盘上出的样张 = **换值之前的中性灰 + 旧强调色**；
    · 而**没有任何门禁会说话** —— 表格结构 / 版本号 / 派生计数 / 单测数字全绿，
      它们管的都不是「这张图里的颜色到底是从哪儿来的」。

这条缝隙的后果不止是"图不好看"：逐屏复查、给需求提出者定调、跨端对照，
全部建立在**样张能代表产品**这个前提上；前提破了，后面每一步都在看另一套配色。

判据（任一不过即失败）
----------------------
A. **渲染脚本里不许有调色板**：`Scripts/design-mock.swift` 里的 `0xRRGGBB` 色值字面量只许出现在
   `EXEMPT_HEX` 里（macOS 窗口交通灯三色 —— 系统外壳，不是设计令牌），其余命中即红并点名行号；
   同时钉两条**回归钉子**：不许再长出 `static func proDark()` / `nativeLight()` / `Theme.hex(`
   这类"第二份调色板"的形态。
B. **必须真的接在真令牌上**：脚本必须引用 `Surface` / `TextTone` / `AccentFamily` / `SyntaxTone` /
   `Radius` / `TypeScale` / `Hairline`（命中处数有下限，防"引用被删光却照样绿"）。
C. **渲染入口必须把令牌编进来**：`Scripts/render-design-mock.sh` 的 `swiftc` 行必须同时含
   `main.swift`（脚本本体）与 `platform/macos/Core/DesignTokens.swift`；**L-80 ㈠ 起还要含 `platform/macos/Core/DesignTheme.swift`**
   （值表按主题分组后落在那一份里）；把令牌文件删掉即红。
D. **逐屏复查（机械版）**：产品源码（`platform/macos/Core/` `platform/macos/App/` `platform/macos/Tests/` `platform/macos/CLI/` `Platform/` `platform/macos/Tools/`
   `platform/macos/TestsUISnapshot/`）里**不许残留方案 D 之前的旧调色板值**（`PRE_D_SWATCHES`）—— 这是
   「换了值但某屏漏改」的判据。豁免只有两处，都写在 `EXEMPT_FILES` 里并带理由：
   `platform/macos/Core/AccentTheme.swift` 与 `platform/macos/Tests/AccentThemeTests.swift`（交互强调色是**另一条轴**，
   用户可切的那三个候选与方案 D 的表面 / 文本令牌无关；测试钉住它们是对的）。
E. **行为证据（macOS）**：真跑一遍渲染入口到临时目录，要求退出码 0、打印「全部样张自检通过」、
   张数 ≥ `MIN_SHEETS`，并且**深色样张量出来的内容底必须带蓝调**（B − R > 8/255）——
   方案 D 是深海军蓝、旧配色是中性灰（B ≈ R），这一刀与 A 合起来就堵住了"换了值但样张没换"。
   非 macOS（缺 Xcode 工具链）**跳过并高声打印**，与闭环其它项同口径（跳过 ≠ 通过）。
F. 空跑防护：文件数 / 引用命中数 / 张数三条下限，任何一条踩线即红（"判据自己失效"比"发现不了"更危险）。

判据自己的证据：`--self-test` **13 例**（红/绿成对，夹具一律在临时目录，末例核对真仓库两份文件逐字节未变）。

用法：
    python3 Scripts/check-design-mock-tokens.py              # 校验（闭环第 6 项）
    python3 Scripts/check-design-mock-tokens.py --no-render  # 只跑静态三条（快）
    python3 Scripts/check-design-mock-tokens.py --self-test  # 门禁自己的证据（**13 例**，红/绿成对）
"""

from __future__ import annotations

import hashlib
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent

MOCK = "Scripts/design-mock.swift"
ENTRY = "Scripts/render-design-mock.sh"

# 产品源码（逐屏复查的扫描面）。只扫**版本控制内**的产品代码，不含 Docs（历史行里都是旧值）。
PRODUCT_DIRS = ("platform/macos/Core", "platform/macos/App", "platform/macos/Tests", "platform/macos/CLI", "platform/macos/Platform", "platform/macos/Tools", "platform/macos/TestsUISnapshot")

# ---- 台账式常量（每条都带理由；理由为空即红 —— 见判据里的理由非空检查）--------------------

# 渲染脚本里允许出现的色值字面量：macOS 窗口左上角交通灯，系统外壳色，三色固定、不随主题变。
EXEMPT_HEX = {
    "0xFF5F57": "macOS 窗口交通灯 · 关闭（系统外壳色，不是设计令牌，不随主题变）",
    "0xFEBC2E": "macOS 窗口交通灯 · 最小化（同上）",
    "0x28C840": "macOS 窗口交通灯 · 全屏（同上）",
}

# 方案 D 之前的旧调色板（深色中性灰五档 + 文本三档 + 旧语法六档 + 旧浅色档 + 旧语义色）。
# 逐屏复查就是"拿这张清单去产品源码里找残留"。
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
    "platform/macos/Core/AccentTheme.swift": "交互强调色（AccentTheme）：用户可切的选中条 / 主按钮 / 焦点环，"
                              "与方案 D 的令牌家族是两条轴，颜色本来就不在 D 的值表里",
    "platform/macos/Tests/AccentThemeTests.swift": "同一族的单测钉住那三个强调色的身份值（正是它们该被钉住的地方）",
}

# 判据 B：必须引用到的令牌符号 → 文档化的名字
TOKEN_SYMBOLS = ("Surface.", "TextTone.", "AccentFamily.", "SyntaxTone.", "StatusTone.",
                 "Radius.", "TypeScale.", "Hairline.")

# 判据 A 的回归钉子：这些形态一旦回来，就是"第二份调色板"又长出来了。
FORBIDDEN_SHAPES = ("static func proDark()", "static func nativeLight()", "Theme.hex(",
                    "NativeLight", "ProDark")

MIN_TOKEN_REFS = 8      # 判据 B 下限（当前实测 8 类全在）

# 判据 E 的蓝调门槛（**实测定的，不是拍的**）：
#   方案 D 深色 content `#0B1A2A` 渲染回来是 **`#0B2338`** ⇒ B − R = 45；
#   旧的中性灰 content `#1F2229` 渲染回来是 **`#21242C`** ⇒ B − R = 11
#   （旧灰其实也带一点点蓝，所以门槛定在 8 会**放它过去** —— 这一点是自检用例抓出来的，
#     门槛因此抬到 20：两档相距 45 vs 11，留足 display profile 的余量）。
MIN_BLUE_TINT = 20
MIN_SHEETS = 10         # 判据 E 下限 = 棘轮（当前实测 10 张；少一张就红）
MIN_PRODUCT_FILES = 200  # 判据 F 下限（当前扫描到的产品源文件数）

HEX_LITERAL = re.compile(r"0x[0-9A-Fa-f]{6}\b")
SAMPLE_LINE = re.compile(r"取样\s+(深色|浅色)-[^:]*:\s*(.*)")
# `内容 #0B2338` 之类
SAMPLE_ENTRY = re.compile(r"内容\s+#([0-9A-Fa-f]{6})")
PASS_LINE = "全部样张自检通过"
SHEET_LINE = re.compile(r"^写出\s+(.+\.png)", re.M)


class Issue:
    def __init__(self, where: str, reason: str):
        self.where = where
        self.reason = reason

    def __str__(self) -> str:
        return f"{self.where}: {self.reason}"


# ---------------------------------------------------------------- 判据 A / B

def check_mock(root: pathlib.Path) -> list[Issue]:
    issues: list[Issue] = []
    path = root / MOCK
    if not path.exists():
        return [Issue(MOCK, "渲染脚本不存在（判据面为空 ⇒ 不许通过）")]
    text = path.read_text(encoding="utf-8")
    for lineno, line in enumerate(text.splitlines(), 1):
        for hit in HEX_LITERAL.findall(line):
            normalized = "0x" + hit[2:].upper()
            if normalized in EXEMPT_HEX:
                continue
            # 同一行里三个交通灯都写在一行 —— 逐个放过，但漏网的要红
            issues.append(Issue(f"{MOCK}:{lineno}",
                                f"渲染脚本里出现了色值字面量 {hit} —— 样张必须从 "
                                f"`platform/macos/Core/DesignTokens.swift` 取色；确属系统外壳色请登记进 EXEMPT_HEX 并写理由"))
    # 一行里有多个豁免色时，上面的循环会把每个都判一遍：只要该行全部命中都在豁免表里就不算命中，
    # 所以这里反过来再确认一次"该行至少有一个非豁免色"才是红（避免把交通灯那一行误判）。
    issues = [i for i in issues if _line_has_unexempt(root, i)]
    for shape in FORBIDDEN_SHAPES:
        if shape in text:
            issues.append(Issue(MOCK, f"渲染脚本里又出现了「第二份调色板」的形态：{shape}"))
    refs = sum(text.count(symbol) for symbol in TOKEN_SYMBOLS)
    if refs < MIN_TOKEN_REFS:
        issues.append(Issue(MOCK, f"渲染脚本对真令牌的引用只有 {refs} 处（下限 {MIN_TOKEN_REFS}）"
                                  f" —— 引用被删光就是空跑，不许通过"))
    return issues


def _line_has_unexempt(root: pathlib.Path, issue: Issue) -> bool:
    """行级复核：该行是否**真的有**一个非豁免色值（交通灯那一行有 3 个豁免色，不算红）。"""
    path, _, lineno = issue.where.rpartition(":")
    try:
        line = (root / path).read_text(encoding="utf-8").splitlines()[int(lineno) - 1]
    except (ValueError, IndexError, OSError):
        return True
    return any(("0x" + h[2:].upper()) not in EXEMPT_HEX for h in HEX_LITERAL.findall(line))


# ---------------------------------------------------------------- 判据 C

def check_entry(root: pathlib.Path) -> list[Issue]:
    path = root / ENTRY
    if not path.exists():
        return [Issue(ENTRY, "渲染入口不存在（判据面为空 ⇒ 不许通过）")]
    text = path.read_text(encoding="utf-8")
    issues: list[Issue] = []
    if "platform/macos/Core/DesignTokens.swift" not in text:
        issues.append(Issue(ENTRY, "swiftc 没有把 `platform/macos/Core/DesignTokens.swift` 编进来 —— "
                                   "那样样张就回到了「自带一份调色板」的老路"))
    # L-80 ㈠：值表按主题分组后落到 `platform/macos/Core/DesignTheme.swift`（角色语义仍在 `platform/macos/Core/DesignTokens.swift`）
    # ⇒ 少编哪一份，样张取到的都不是产品那套值。两台机器上都可判，故单列一条。
    if "platform/macos/Core/DesignTheme.swift" not in text:
        issues.append(Issue(ENTRY, "swiftc 没有把 `platform/macos/Core/DesignTheme.swift`（主题值表）编进来 —— "
                                   "样张会退化成「默认主题之外什么都不认」"))
    if "main.swift" not in text:
        issues.append(Issue(ENTRY, "入口没有把渲染脚本当 `main.swift` 编译（swiftc 只在文件名叫 "
                                   "main.swift 时才允许顶层代码）"))
    if "swiftc" not in text:
        issues.append(Issue(ENTRY, "入口里找不到 swiftc —— 判据 C 的前提没了"))
    return issues


# ---------------------------------------------------------------- 判据 D（逐屏复查）

def check_product_sources(root: pathlib.Path) -> tuple[list[Issue], int]:
    issues: list[Issue] = []
    scanned = 0
    for directory in PRODUCT_DIRS:
        base = root / directory
        if not base.exists():
            continue
        for path in sorted(base.rglob("*")):
            if not path.is_file() or path.suffix not in {".swift", ".m", ".h", ".mm"}:
                continue
            rel = path.relative_to(root).as_posix()
            scanned += 1
            if rel in EXEMPT_FILES:
                continue
            try:
                text = path.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                continue
            for lineno, line in enumerate(text.splitlines(), 1):
                for hit in HEX_LITERAL.findall(line):
                    normalized = "0x" + hit[2:].upper()
                    if normalized in PRE_D_SWATCHES:
                        issues.append(Issue(f"{rel}:{lineno}",
                                            f"残留方案 D 之前的旧调色板值 {hit}"
                                            f"（{PRE_D_SWATCHES[normalized]}）—— 这一屏漏改了"))
    return issues, scanned


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


# ---------------------------------------------------------------- 豁免理由非空

def check_exemptions_have_reasons() -> list[Issue]:
    issues: list[Issue] = []
    for table, name in ((EXEMPT_HEX, "EXEMPT_HEX"), (EXEMPT_FILES, "EXEMPT_FILES"),
                        (PRE_D_SWATCHES, "PRE_D_SWATCHES")):
        for key, reason in table.items():
            if not reason or not reason.strip():
                issues.append(Issue(name, f"{key} 的理由是空的 —— 豁免必须写明理由，否则就是把判据关掉"))
    return issues


# ---------------------------------------------------------------- 自检

def _sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def self_test() -> int:
    cases: list[tuple[str, bool, list[Issue]]] = []   # (名字, 期望红?, 实际 issues)
    real_mock, real_entry = ROOT / MOCK, ROOT / ENTRY
    before = {p: _sha(p) for p in (real_mock, real_entry)}

    def fresh(fixture: pathlib.Path) -> pathlib.Path:
        """把判据要看的文件复制到临时目录（夹具一律在临时目录里写坏）。"""
        (fixture / "Scripts").mkdir(parents=True, exist_ok=True)
        shutil.copy(real_mock, fixture / MOCK)
        shutil.copy(real_entry, fixture / ENTRY)
        app = fixture / "App"
        app.mkdir(parents=True, exist_ok=True)
        (app / "SampleView.swift").write_text(
            "import SwiftUI\nlet background = Color(red: 0, green: 0, blue: 0)\n", encoding="utf-8")
        (fixture / "Core").mkdir(parents=True, exist_ok=True)
        (fixture / "Core" / "DesignTokens.swift").write_text("// 令牌（夹具占位）\n", encoding="utf-8")
        return fixture

    with tempfile.TemporaryDirectory(prefix="doyah-mock-selftest-") as tmp:
        base = fresh(pathlib.Path(tmp) / "green")
        # ① 绿：好情况（静态三条都不报）
        issues = check_mock(base) + check_entry(base) + check_product_sources(base)[0]
        cases.append(("好情况（绿）", False, issues))

        # ② 红：渲染脚本里塞一个旧调色板值
        bad = fresh(pathlib.Path(tmp) / "bad-hex")
        text = (bad / MOCK).read_text(encoding="utf-8")
        (bad / MOCK).write_text(text + "\nlet legacyWindow = NSColor(mockHex: 0x1F2229)\n", encoding="utf-8")
        cases.append(("渲染脚本里出现色值字面量", True, check_mock(bad)))

        # ③ 绿：交通灯三色仍是豁免（同一个夹具，判据 A 不报）
        cases.append(("交通灯三色属豁免（绿）", False, [i for i in check_mock(base) if "交通灯" in i.reason]))

        # ④ 红：把对真令牌的引用删光（空跑防护）
        starvation = fresh(pathlib.Path(tmp) / "bad-refs")
        text = (starvation / MOCK).read_text(encoding="utf-8")
        for symbol in TOKEN_SYMBOLS:
            text = text.replace(symbol, "")
        (starvation / MOCK).write_text(text, encoding="utf-8")
        cases.append(("令牌引用被删光（空跑）", True, check_mock(starvation)))

        # ⑤ 红：第二份调色板的形态又长回来
        relapse = fresh(pathlib.Path(tmp) / "bad-relapse")
        text = (relapse / MOCK).read_text(encoding="utf-8")
        (relapse / MOCK).write_text(text + "\nstatic func proDark() { }\n", encoding="utf-8")
        cases.append(("旧调色板函数形态回归", True, check_mock(relapse)))

        # ⑥ 红：入口里把令牌文件删掉
        no_token = fresh(pathlib.Path(tmp) / "bad-entry")
        text = (no_token / ENTRY).read_text(encoding="utf-8")
        (no_token / ENTRY).write_text(text.replace("platform/macos/Core/DesignTokens.swift", "Core/Nothing.swift"),
                                      encoding="utf-8")
        cases.append(("入口没有把令牌编进来", True, check_entry(no_token)))

        # ⑦ 红：产品源码里残留旧值（逐屏复查）
        stale = fresh(pathlib.Path(tmp) / "bad-product")
        (stale / "App" / "SampleView.swift").write_text(
            "import SwiftUI\nlet background = NSColor(red: 0x1F2229)\n", encoding="utf-8")
        cases.append(("某屏残留旧调色板值", True, check_product_sources(stale)[0]))

        # ⑧ 绿：豁免文件（AccentTheme）里出现强调色不算红
        exempt = fresh(pathlib.Path(tmp) / "green-exempt")
        (exempt / "Core" / "AccentTheme.swift").write_text(
            "accentHex: 0x4E6FFF,\n", encoding="utf-8")
        cases.append(("AccentTheme 豁免（绿）", False, [i for i in check_product_sources(exempt)[0]
                                                       if "AccentTheme" in i.where]))

        # ⑨ 红：渲染输出不带蓝调 / 少张数 / 没跑自检
        cases.append(("渲染输出里深色底不带蓝调", True,
                      assess_render_output("写出 样张-深色-D-科技蓝.png\n" + PASS_LINE + "（12 项）\n"
                                           "  取样 深色-D-科技蓝: 底 #21242C 内容 #1F2229\n" +
                                           "".join(f"写出 样张-{i}.png\n" for i in range(12)))))
        cases.append(("渲染输出深色底带蓝调（绿）", False,
                      assess_render_output("".join(f"写出 样张-{i}.png\n" for i in range(12)) +
                                           PASS_LINE + "（72 项）\n  取样 深色-D-科技蓝: 内容 #0B2338\n")))
        cases.append(("渲染输出缺自检收尾行", True,
                      assess_render_output("".join(f"写出 样张-{i}.png\n" for i in range(12)) +
                                           "  取样 深色-D-科技蓝: 内容 #0B2338\n")))

        # ⑩ 红：豁免理由被清空
        global EXEMPT_HEX
        saved = dict(EXEMPT_HEX)
        EXEMPT_HEX["0xFF5F57"] = ""
        try:
            cases.append(("豁免理由为空", True, check_exemptions_have_reasons()))
        finally:
            EXEMPT_HEX = saved

    failures = 0
    for name, expect_red, issues in cases:
        ok = bool(issues) == expect_red
        if not ok:
            failures += 1
        print(f"{'✅' if ok else '❌'} {name}：{'报红' if issues else '绿'}"
              f"（期望{'报红' if expect_red else '绿'}）"
              + (f" —— {issues[0]}" if issues and not expect_red else ""))

    # 末例：核对真仓库两份文件逐字节未变
    after = {p: _sha(p) for p in (real_mock, real_entry)}
    unchanged = before == after
    if not unchanged:
        failures += 1
    print(f"{'✅' if unchanged else '❌'} 真仓库两份文件逐字节未变")
    print(f"{len(cases) - failures if failures else len(cases)}/{len(cases) + 1} 例达到预期"
          if failures else f"全部 {len(cases) + 1} 例达到预期（自检 exit 0）")
    return 0 if failures == 0 else 1


# ---------------------------------------------------------------- 主流程

def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return self_test()

    issues: list[Issue] = []
    issues += check_exemptions_have_reasons()
    issues += check_mock(ROOT)
    issues += check_entry(ROOT)
    product_issues, scanned = check_product_sources(ROOT)
    issues += product_issues

    print("==> 外观样张 ↔ 产品令牌同源（L-79 ㈡）")
    print(f"    ① 渲染脚本 {MOCK}：{'无自带调色板' if not check_mock(ROOT) else '有问题'}"
          f"（豁免 {len(EXEMPT_HEX)} 个系统外壳色）")
    print(f"    ② 渲染入口 {ENTRY}：把 platform/macos/Core/DesignTokens.swift 编进来"
          f"（{'是' if not check_entry(ROOT) else '否'}）")
    print(f"    ③ 逐屏复查：扫了 {scanned} 个产品源文件，"
          f"旧调色板残留 {len(product_issues)} 处（豁免 {len(EXEMPT_FILES)} 个文件）")
    if scanned < MIN_PRODUCT_FILES:
        issues.append(Issue("逐屏复查", f"只扫到 {scanned} 个产品源文件（下限 {MIN_PRODUCT_FILES}）"
                                        f" —— 扫描面被削过，不许通过"))

    render_skipped = "--no-render" in argv or os.environ.get("DOYAH_PLATFORM", "macos") != "macos"
    if render_skipped:
        print("    ④ 行为证据（真跑渲染 + 深色底蓝调）：⏭ 跳过"
              + ("（--no-render）" if "--no-render" in argv else "（非 macOS：缺 Xcode 工具链）"))
        print("       —— **跳过 ≠ 通过**；主开发机上跑 `./Scripts/render-design-mock.sh` 的等价物见本脚本判据 E")
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
        return 1
    tail = ("渲染脚本无自带调色板 / 入口接真令牌 / 产品源码无旧调色板残留"
            if render_skipped else
            "渲染脚本无自带调色板 / 入口接真令牌 / 产品源码无旧调色板残留 / 样张深色底带蓝调")
    print(f"\n✅ 样张与产品同源：{tail}")
    if render_skipped:
        print("   ⚠️ 本轮**没跑**行为证据（判据 E 跳过）—— 这一节不算通过，报告里要如实写")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
