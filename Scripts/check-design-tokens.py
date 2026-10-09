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

豁免：行尾加 `// token-ok` 注释即可跳过该行（必须在注释里写明理由）。

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
    python3 Scripts/check-design-tokens.py --report       # 只看统计
    python3 Scripts/check-design-tokens.py --update-baseline
"""

from __future__ import annotations

import json
import pathlib
import re
import sys

ROOT = pathlib.Path("App")
BASELINE = pathlib.Path("Scripts/design-token-baseline.json")
WHITELIST = pathlib.Path("Scripts/design-token-whitelist.json")

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


def numbers(match: re.Match | None) -> list[float]:
    if match is None:
        return []
    return [float(group) for group in match.groups() if group is not None]


def bare_color_hit(raw: str, allowed: frozenset[str]) -> bool:
    """一处裸色 = 字面色值，或**未登记**的系统语义色（白名单里登记过的放行）。"""
    if BARE_COLOR.search(raw) and "Color.clear" not in raw:
        return True
    for name in SEMANTIC_COLOR_NAME.findall(raw):
        if name in SEMANTIC_COLOR_UNIVERSE and name not in allowed:
            return True
    return False


def scan_file(path: pathlib.Path, allowed: frozenset[str]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.startswith("//") or line.startswith("///") or line.startswith("*"):
            continue
        if "token-ok" in raw:
            continue

        def bump(rule: str) -> None:
            counts[rule] = counts.get(rule, 0) + 1

        if bare_color_hit(raw, allowed):
            bump("bare-color")

        if any(value not in FONT_SCALE for value in numbers(FONT_SIZE.search(raw)) if value):
            bump("bare-font")

        spacing_hits = numbers(PADDING.search(raw)) + numbers(STACK_SPACING.search(raw))
        if any(value not in SPACING_SCALE for value in spacing_hits):
            bump("bare-spacing")

        if any(value not in RADIUS_SCALE for value in numbers(CORNER.search(raw))):
            bump("bare-radius")

        if BARE_TEXT_STYLE.search(raw):
            bump("bare-textstyle")

        if BARE_FOREGROUND.search(raw):
            bump("bare-foreground")

    return counts


EXEMPT_MARKER = "token-ok-file:"


def exempt_reason(path: pathlib.Path) -> str | None:
    """整文件豁免：文件头 5 行内写 `// token-ok-file: 理由`。

    逃逸口必须**可见**：豁免文件会在 --report 里单独列出，
    免得"加一行注释就悄悄无视规矩"变成常规操作。
    """
    head = path.read_text(encoding="utf-8").splitlines()[:5]
    for line in head:
        if EXEMPT_MARKER in line:
            return line.split(EXEMPT_MARKER, 1)[1].strip()
    return None


def scan(allowed: frozenset[str]) -> tuple[dict[str, dict[str, int]], dict[str, str]]:
    result: dict[str, dict[str, int]] = {}
    exempt: dict[str, str] = {}
    for path in sorted(ROOT.rglob("*.swift")):
        reason = exempt_reason(path)
        if reason is not None:
            exempt[str(path)] = reason
            continue
        counts = scan_file(path, allowed)
        if counts:
            result[str(path)] = counts
    return result, exempt


def totals(scan_result: dict[str, dict[str, int]]) -> dict[str, int]:
    total: dict[str, int] = {}
    for counts in scan_result.values():
        for rule, value in counts.items():
            total[rule] = total.get(rule, 0) + value
    return total


def load_baseline() -> dict:
    if not BASELINE.exists():
        return {"files": {}, "totals": {}}
    return json.loads(BASELINE.read_text(encoding="utf-8"))


NEGATIVE_SAMPLES = (
    "let c = Color.orange",
    "let c = NSColor.systemRed",
    "let c = NSColor(calibratedRed: 0.1, green: 0.2, blue: 0.3, alpha: 1)",
    "let c = Color(red: 0.1, green: 0.2, blue: 0.3)",
    'let c = Color(hex: "#FF00FF")',
)


def load_whitelist() -> tuple[frozenset[str], list[str]]:
    """读语义色白名单 + 校验「只许语义色」（判据 ①）。返回 (白名单, 问题列表)。"""
    if not WHITELIST.exists():
        return frozenset(), [f"语义色白名单文件不存在：{WHITELIST}"]
    try:
        data = json.loads(WHITELIST.read_text(encoding="utf-8"))
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
    for name in sorted(SEMANTIC_COLOR_UNIVERSE - allowed):
        sample = f"let c = NSColor.{name}"
        if not bare_color_hit(sample, allowed):
            problems.append(f"未登记的系统语义色没被判裸色：{sample}")
    return problems


def main() -> int:
    arguments = set(sys.argv[1:])
    allowed, whitelist_problems = load_whitelist()
    gate_problems = list(whitelist_problems)
    if not gate_problems:
        gate_problems += self_check(allowed)
    if gate_problems:
        print("❌ 设计令牌门禁自检失败（判据 ① 白名单只许语义色 / 判据 ② 字面量反例仍判红）：")
        for problem in gate_problems:
            print("   " + problem)
        return 1

    current, exempt = scan(allowed)
    current_totals = totals(current)
    baseline = load_baseline()

    if "--report" in arguments:
        print("当前违规统计（App/）：")
        for rule in sorted(current_totals):
            print(f"  {rule:<14} {current_totals[rule]:>5}")
        print(f"语义色白名单：{len(allowed)} 个（仅语义色校验通过；字面量反例 {len(NEGATIVE_SAMPLES)} 例仍判红）")
        worst = sorted(current.items(), key=lambda item: -sum(item[1].values()))[:8]
        if exempt:
            print("整文件豁免（终端语义一类，不属于界面令牌）：")
            for path, reason in exempt.items():
                print(f"       {path} — {reason}")
        print("最集中的文件：")
        for path, counts in worst:
            print(f"  {sum(counts.values()):>4}  {path}  {counts}")
        return 0

    if "--update-baseline" in arguments:
        # 首次建立基线：允许直接写入（此后只能往下拧）
        if not BASELINE.exists():
            BASELINE.write_text(
                json.dumps(
                    {"comment": "设计令牌棘轮基线：违规数只能降不能升（--update-baseline 下调）",
                     "files": current, "totals": current_totals},
                    ensure_ascii=False, indent=2, sort_keys=True,
                ) + "\n",
                encoding="utf-8",
            )
            print(f"✅ 首次建立基线：{sum(current_totals.values())} 处待迁移 {current_totals}")
            return 0
        old_totals = baseline.get("totals", {})
        relaxed = {
            rule: value for rule, value in current_totals.items()
            if value > old_totals.get(rule, 0)
        }
        if relaxed and "--force" not in arguments:
            print("❌ 这些规则比基线更差了，拒绝写入（如确要放宽请加 --force，让它在 review 里可见）：")
            for rule, value in relaxed.items():
                print(f"   {rule}: {old_totals.get(rule, 0)} → {value}")
            return 1
        BASELINE.write_text(
            json.dumps(
                {"comment": "设计令牌棘轮基线：违规数只能降不能升（--update-baseline 下调）",
                 "files": current, "totals": current_totals},
                ensure_ascii=False, indent=2, sort_keys=True,
            ) + "\n",
            encoding="utf-8",
        )
        print(f"✅ 基线已更新：{sum(current_totals.values())} 处待迁移")
        return 0

    # 校验
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

    if problems:
        print(f"❌ 设计令牌校验失败（{len(problems)} 处比基线更差）：")
        for problem in problems:
            print("   " + problem)
        print("   提示：能改就用令牌；确实要保留原样时在行尾加 `// token-ok` 并写明理由。")
        return 1

    remaining = sum(current_totals.values())
    exempt_note = f"，另有 {len(exempt)} 个豁免文件" if exempt else ""
    print(f"✅ 令牌校验通过（未比基线更差；仍有 {remaining} 处待迁移：{current_totals}{exempt_note}）")
    print(f"   语义色白名单 {len(allowed)} 个（判据 ① 仅语义色 · 通过；字面量反例 {len(NEGATIVE_SAMPLES)} 例仍判红 · 判据 ② 通过）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
