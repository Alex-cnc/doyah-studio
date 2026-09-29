#!/usr/bin/env python3
"""主题集（配色方案）门禁（队列 L-80 ㈠，闭环第 6 项，与设计令牌棘轮 / 样张同源门禁同项）。

存在的理由（真现场）
--------------------
2026-09-29 需求提出者要求「增加一个 theme 主题选项」，并指出 Linux 版早有**豆芽绿 / 玫瑰金 / 科技蓝**
三选一。于是令牌值从「一套」变成「**三套**」，而这件事有一个单测天然守不住的地方：

    · 单测（`Tests/DesignTokensTests.swift` / `DesignThemeTests.swift`）与新主题
      **用同一份实现**算对比度（`ColorContrast`）。没错，但"判据与被判对象同源"意味着
      —— 如果值表里某一档被改坏、或有人**新加一套表**却漏了某个角色，只会红在同一个实现里；
    · 更要紧的是"**主题名与 Linux 侧对齐**""**待值登记还在**"这两件事**根本不是单测能看的**：
      它们是跨文档的事实（`Docs/design/外观方案-v1.md` §9 的表 / `Docs/发布计划.md` 的待输入表 /
      `Core/Localization.swift` 的双语文案）。

本脚本因此做了两件与单测互补的事：
    ① **独立复算**：用 Python 自己重新实现 WCAG 相对亮度 / 对比度 / 表面距离，
       从 Swift 源里**解析出**三套值，逐条复算门槛（不同语言、不同实现 ⇒ 不是自证）；
    ② **跨文档对账**：主题名 ↔ §9 表 ↔ 双语名；有几个推导主题 ↔ 待值登记行。

判据（任一不过即失败）
----------------------
A. **主题集**：`Core/DesignTheme.swift` 的 `case <名> = "<id>"` 集合与顺序必须等于台账里的三个
   （`tech-blue` / `bean-green` / `rose-gold`），且 `DesignTheme.all` 把三个主题**都**列了出来
   （列漏一个 = 用户选不到它）。
B. **三套值表角色齐全**：每个 `ThemePalette` 块必须含全部 20 个字段（18 个色角色 + 发丝线两参数），
   缺一个即红 —— 缺角色在 Swift 里是编译错误，但"新加一套表时少写一行"这类改动会先在
   **复制粘贴的中间态**里存在；`of(_:)` 的 switch 必须三支齐全（每个主题都取得到值）。
C. **独立复算门槛**（本脚本自己实现，不看 Swift 的实现）：三主题 × 深浅两态逐条判 ——
   正文 ≥4.5 / 强对比 ≥7 且强于正文 / 辅助 ≥3.0 / 禁用比辅助淡且 ≥1.5 / 状态色在两表面 ≥3.0 /
   强调家族按角色 ≥4.5（文字链接）与 ≥3.0（图标线，基准 = 深色对 window、浅色对白）/
   语法六档两两不同且各自过关 / 深色五档明度严格递增 / 浅色 content 最亮 /
   表面之间距离 ≥0.02 / 浅色发丝线比 content 暗。
D. **语法色必须仍挂在家族角色上**：`Core/DesignTokens.swift` 的 `SyntaxTone.color(in:)` 六行映射
   逐行对账（keyword→accentGlow / string→warm / number→teal / function→accent /
   identifier→primary / comment→tertiary）—— 谁把某个语法色改回硬编码，六档就与家族脱钩。
E. **主题名与 Linux 侧对齐 + 待值登记成对**：
   ① `Core/Localization.swift` 里三个主题名键的中文值必须是「科技蓝 / 豆芽绿 / 玫瑰金」，
      且 `Docs/design/外观方案-v1.md` §9 的主题表里三行**同名**（双向覆盖，缺一即红）；
   ② 有推导主题（`isDerivedDraft`）就必须 ① 值表**紧挨着的那段注释**里标着「推导草案」
      （§9.1 的原话）② `Docs/发布计划.md` 的待输入表里登记着「豆芽绿 / 玫瑰金 色值（Linux 侧）」
      那件事 —— 推导值不许**静默变成**实际值。
F. 空跑防护：主题数 / 角色数 / 实测对数 / 文档锚点处数四条下限，任何一条踩线即红。
G. **界面入口（㈡ 加上的那一半）**：值表分组了、运行时也能切了，但**用户手上那个入口**是另一件事
   —— 三个主题里有没有人**选不到**、预览是不是只给一块色卡、推导值有没有在界面上**逐条**标出来、
   以及"加了主题就把原来那个强调色入口删掉"这类**静默收功能**。判据：① 面板必须逐个列出主题集
   （`ForEach(DesignTheme.all)`）且选主题走**唯一写入口** `select(_:)`，且**订阅**了主题管理器
   （否则换了主题这块面板自己不跟着变）；② 主题行必须画出**三个真实场景**（选中行 / 主按钮 / 焦点环）
   且预览画在**该主题自己**的表面上（`palette.content`）＋用**该主题配套**的强调色（`theme.accent`）；
   ③ 推导主题必须**逐条**标注（行里问 `isDerivedDraft` + 画出标记键 + 语言表里有那句中文）；
   ④ `AccentTheme.all` 入口不许消失（FR-EDIT-33 的「强调色可配置」是已交付能力，要收得先改 SRS 与判据）；
   ⑤ 宿主语境覆盖（`beginHostTheme` / `endHostTheme`）**不许写盘**（拍一张快照不许改用户偏好 ——
   语言那条路定过这个口径），而 `select(_:)` **必须**写盘。判点只看**那一段源码切片**，不看整文件
   （否则"别处写过一句"就顶数 —— 第 77 轮自检例 ⑨/⑮ 两次栽在这上面）。

判据自己的证据：`--self-test` **22 例**（21 个红/绿成对 + 末例核对真仓库七份文件逐字节未变；夹具一律在临时目录）。

用法：
    python3 Scripts/check-design-themes.py              # 校验（闭环第 6 项）
    python3 Scripts/check-design-themes.py --self-test  # 门禁自己的证据（22 例）
"""

from __future__ import annotations

import hashlib
import math
import pathlib
import re
import shutil
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent

THEMES_SWIFT = "Core/DesignTheme.swift"
TOKENS_SWIFT = "Core/DesignTokens.swift"
LOCALIZATION_SWIFT = "Core/Localization.swift"
DESIGN_DOC = "Docs/design/外观方案-v1.md"
RELEASE_PLAN = "Docs/发布计划.md"
APPEARANCE_SWIFT = "App/Views/AppearanceSheet.swift"
THEME_MANAGER_SWIFT = "App/DesignThemeManager.swift"

# ---- 台账式常量（每条都带理由；理由为空即红）-------------------------------------------------

# 三个主题的 id 与顺序（= 界面里的顺序；与 Linux 侧同名）。
THEME_IDS = ["tech-blue", "bean-green", "rose-gold"]
THEME_NAMES_ZH = {
    "tech-blue": "科技蓝",
    "bean-green": "豆芽绿",
    "rose-gold": "玫瑰金",
}
# 值表必须有的字段：18 个色角色 + 发丝线两个参数。
COLOR_ROLES = (
    "window", "sidebar", "content", "panel", "raised",
    "textBright", "textPrimary", "textSecondary", "textTertiary", "textDisabled",
    "success", "warning", "danger",
    "accent", "accentGlow", "accentSoft", "accentTeal", "accentWarm",
)
HAIRLINE_FIELDS = ("hairlineLight", "hairlineDarkAlpha")
# 注意：这里的名字是**值表字段名**（`ThemePalette` 的字段），不是枚举 case 名。
WEAK_ROLES = ("textPrimary", "textSecondary")          # 正文：≥4.5
AUX_ROLES = ("textTertiary",)                          # 辅助：≥3.0
LINK_ROLES = ("accentGlow", "accentTeal", "accentWarm")  # 会落到文字 / 链接上：≥4.5
ICON_ROLES = ("accent", "accentSoft")                   # 只做图标线：≥3.0

# 语法六档 → 家族角色（判据 D 的对照表；改这张表要同时改 `Core/DesignTokens.swift` 与文档）。
SYNTAX_BINDING = {
    "keyword": "accentGlow",
    "identifier": "primary",
    "string": "warm",
    "number": "teal",
    "function": "accent",
    "comment": "tertiary",
}

# 门槛（与 `Core/ColorContrast.Threshold` 同值；这里**独立实现**，所以必须各写一份）。
BODY_TEXT = 4.5
STRONG_TEXT = 7.0
LARGE_TEXT = 3.0
COMPONENT = 3.0
SURFACE_SEPARATION = 0.02

MIN_THEMES = 3          # 判据 F：主题数下限
MIN_ROLES = 20          # 判据 F：每套表的字段数下限
MIN_CHECKS = 120        # 判据 F：实测对数下限（3 主题 × 2 态 × 每个角色若干条）

# ---- 判据 G（界面入口）的对照表（每条都带理由）------------------------------------------------
# 主题候选行必须画出的**三个真实场景** —— 缺一个就退化成"只给一块色卡"（用户只能凭想象选）。
# 理由与 `AccentOptionRow` 同源（FR-EDIT-33 原文：选色不该靠想象），但主题要**多一层**：
# 预览得画在该主题**自己**的表面上（见 `THEME_SURFACE_MARKER`）。
SCENE_MARKERS = {
    "选中行": ".fill(tintColor)",
    "主按钮": ".foregroundStyle(.white)",
    "焦点环": ".strokeBorder(accentColor, lineWidth: 1.5)",
}
# 预览的底必须来自**该主题的值表**（不是当前界面的表面）——
# 少了它，"豆芽绿 / 玫瑰金 的底"在界面上一眼都看不到。
THEME_SURFACE_MARKER = "palette.content"
# 「推导草案」这句话在界面上的落点：行里要画出这个键，语言表里要有这句中文原话。
DERIVED_MARKER_KEY = ".appearanceDesignThemeDerived"
DERIVED_LKEY = "appearanceDesignThemeDerived"
MIN_PANEL_LINES = 400   # 判据 G：面板文件行数下限（被掏空即红）
MIN_ROW_CHARS = 1200    # 判据 G：主题行源码字符下限（被掏空即红）
MIN_ENTRY_SITES = 12    # 判据 G：界面入口的判点处数下限（空跑防护）

PALETTE_BLOCK = re.compile(r"public static let (\w+) = ThemePalette\((.*?)\n    \)", re.S)
THEME_CASE = re.compile(r'^\s*case (\w+) = "([a-z-]+)"', re.M)
COLOR_FIELD = re.compile(r"(\w+): ThemeColor\(light: (0x[0-9A-Fa-f]{6}), dark: (0x[0-9A-Fa-f]{6})\)")
HEX_FIELD = re.compile(r"(hairlineLight): (0x[0-9A-Fa-f]{6})")
ALPHA_FIELD = re.compile(r"(hairlineDarkAlpha): ([0-9.]+)")


class Issue:
    def __init__(self, where: str, reason: str):
        self.where = where
        self.reason = reason

    def __str__(self) -> str:
        return f"{self.where}: {self.reason}"


# ---------------------------------------------------------------- WCAG（本脚本自己的实现）

def _linear(value: float) -> float:
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def luminance(hex_value: int) -> float:
    red = ((hex_value >> 16) & 0xFF) / 255
    green = ((hex_value >> 8) & 0xFF) / 255
    blue = (hex_value & 0xFF) / 255
    return 0.2126 * _linear(red) + 0.7152 * _linear(green) + 0.0722 * _linear(blue)


def ratio(lhs: int, rhs: int) -> float:
    a, b = luminance(lhs), luminance(rhs)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)


def distance(lhs: int, rhs: int) -> float:
    parts = []
    for shift in (16, 8, 0):
        parts.append((((lhs >> shift) & 0xFF) - ((rhs >> shift) & 0xFF)) / 255)
    return math.sqrt(sum(part * part for part in parts))


# ---------------------------------------------------------------- 解析

def parse_palettes(text: str) -> dict[str, dict]:
    """从 `Core/DesignTheme.swift` 解析出每套值表：{表名: {字段: 值}}。"""
    palettes: dict[str, dict] = {}
    for name, body in PALETTE_BLOCK.findall(text):
        entry: dict = {"_colors": {}, "_hairlineLight": None, "_hairlineAlpha": None}
        for role, light, dark in COLOR_FIELD.findall(body):
            entry["_colors"][role] = (int(light, 16), int(dark, 16))
        for role, value in HEX_FIELD.findall(body):
            entry["_hairlineLight"] = int(value, 16)
        for role, value in ALPHA_FIELD.findall(body):
            entry["_hairlineAlpha"] = float(value)
        id_match = re.search(r"id: \.(\w+)", body)
        entry["_id"] = id_match.group(1) if id_match else None
        palettes[name] = entry
    return palettes


def theme_swift_text(root: pathlib.Path) -> str:
    return (root / THEMES_SWIFT).read_text(encoding="utf-8")


def palette_for(root: pathlib.Path, theme_id: str) -> dict | None:
    """按主题 id 找它对应的值表（通过 `id: .xxx` 与 case 名的映射）。"""
    text = theme_swift_text(root)
    case_names = {name: ident for name, ident in THEME_CASE.findall(text)}
    ident = None
    for name, ident_value in case_names.items():
        if ident_value == theme_id:
            ident = name
            break
    if ident is None:
        return None
    palettes = parse_palettes(text)
    for paletted in palettes.values():
        if paletted["_id"] == ident:
            return paletted
    return None


def theme_ids_in_source(root: pathlib.Path) -> list[str]:
    return [ident for _, ident in THEME_CASE.findall(theme_swift_text(root))]


def _type_slice(text: str, marker: str, closing: str = "\n}") -> str | None:
    """取**一段声明**的源码切片（从 `marker` 到它自己的收尾行）。

    判据 G 要问的是「这一段里有没有画出那三个场景」，就必须只看**这一段**：
    拿整个文件去 `in`，等于"别处写过一句也算"（第 77 轮自检例 ⑨/⑮ 两次栽在这上面）。
    类型（`struct … {`）以列 0 的 `}` 收尾，函数以缩进四格的 `}` 收尾。
    """
    start = text.find(marker)
    if start < 0:
        return None
    end = text.find(closing, start)
    if end < 0:
        return None
    return text[start:end]


# ---------------------------------------------------------------- 判据 A

def check_theme_set(root: pathlib.Path) -> list[Issue]:
    issues: list[Issue] = []
    ids = theme_ids_in_source(root)
    if ids != THEME_IDS:
        issues.append(Issue(THEMES_SWIFT, f"主题集是 {ids}，台账登记的是 {THEME_IDS}"
                                         f" —— 加减主题要同时改台账与三书（§9）"))
    text = theme_swift_text(root)
    all_match = re.search(r"public static let all: \[DesignTheme\] = \[(.*?)\]", text, re.S)
    if not all_match:
        issues.append(Issue(THEMES_SWIFT, "找不到 `DesignTheme.all` —— 判据 A 的前提没了"))
        return issues
    listed = set(re.findall(r"\.(\w+)", all_match.group(1)))
    if len(listed) != len(THEME_IDS):
        issues.append(Issue(THEMES_SWIFT, f"`DesignTheme.all` 只列了 {len(listed)} 个主题"
                                         f"（应为 {len(THEME_IDS)}）—— 漏列的主题用户选不到"))
    of_match = re.search(r"public static func of\(_ theme: DesignTheme\) -> ThemePalette \{(.*?)\n    \}",
                         text, re.S)
    if not of_match:
        issues.append(Issue(THEMES_SWIFT, "找不到 `ThemePalette.of(_:)` —— 判据 A 的前提没了"))
    else:
        branches = set(re.findall(r"case \.(\w+):", of_match.group(1)))
        if len(branches) != len(THEME_IDS):
            issues.append(Issue(THEMES_SWIFT, f"`ThemePalette.of(_:)` 只覆盖 {len(branches)} 个主题"
                                             f"（应为 {len(THEME_IDS)}）—— 少的那一个取不到值"))
    return issues


# ---------------------------------------------------------------- 判据 B

def check_palette_shape(root: pathlib.Path) -> tuple[list[Issue], int]:
    issues: list[Issue] = []
    palettes = parse_palettes(theme_swift_text(root))
    if len(palettes) < MIN_THEMES:
        issues.append(Issue(THEMES_SWIFT, f"只解析到 {len(palettes)} 套值表（下限 {MIN_THEMES}）"
                                         f" —— 解析面被削过或表被删了，不许通过"))
        return issues, 0
    role_total = 0
    for name, palette in palettes.items():
        missing = [role for role in COLOR_ROLES if role not in palette["_colors"]]
        if missing:
            issues.append(Issue(THEMES_SWIFT, f"{name} 少了 {len(missing)} 个色角色：{missing}"
                                             f" —— 角色不齐就是「这一档用了别的主题的颜色」"))
        if palette["_hairlineLight"] is None:
            issues.append(Issue(THEMES_SWIFT, f"{name} 少了发丝线浅色实色"))
        if palette["_hairlineAlpha"] is None:
            issues.append(Issue(THEMES_SWIFT, f"{name} 少了发丝线深色透明度"))
        role_total += len(palette["_colors"]) + (1 if palette["_hairlineLight"] is not None else 0) \
            + (1 if palette["_hairlineAlpha"] is not None else 0)
        if len(palette["_colors"]) < MIN_ROLES - len(HAIRLINE_FIELDS):
            issues.append(Issue(THEMES_SWIFT, f"{name} 的色角色只有 {len(palette['_colors'])} 个"
                                             f"（下限 {MIN_ROLES - len(HAIRLINE_FIELDS)}）"))
    return issues, role_total


# ---------------------------------------------------------------- 判据 C

def check_thresholds(root: pathlib.Path) -> tuple[list[Issue], int]:
    issues: list[Issue] = []
    checks = 0
    for theme_id in THEME_IDS:
        palette = palette_for(root, theme_id)
        if palette is None:
            issues.append(Issue(THEMES_SWIFT, f"主题 {theme_id} 找不到对应的值表"))
            continue
        colors = palette["_colors"]
        hairline_light = palette["_hairlineLight"]
        hairline_alpha = palette["_hairlineAlpha"]
        if hairline_light is None or hairline_alpha is None:
            issues.append(Issue(THEMES_SWIFT, f"{theme_id} 的发丝线参数不全，无法复算"))
            continue
        for is_dark in (True, False):
            state = "深色" if is_dark else "浅色"
            index = 1 if is_dark else 0

            def c(role: str) -> int:
                return colors[role][index]

            content = c("content")

            def judge(label: str, value: float, floor: float, extra_fail: bool = False) -> None:
                nonlocal checks
                checks += 1
                if value < floor or extra_fail:
                    issues.append(Issue(
                        f"{THEMES_SWIFT} ({theme_id}/{state})",
                        f"{label} 实测 {value:.2f}，门槛 {floor}"
                    ))

            for role in WEAK_ROLES:
                judge(f"正文 {role}", ratio(c(role), content), BODY_TEXT)
            for role in AUX_ROLES:
                judge(f"辅助 {role}", ratio(c(role), content), LARGE_TEXT)
            bright_ratio = ratio(c("textBright"), content)
            judge("强对比 textBright", bright_ratio, STRONG_TEXT)
            checks += 1
            if bright_ratio <= ratio(c("textPrimary"), content):
                issues.append(Issue(f"{THEMES_SWIFT} ({theme_id}/{state})",
                                    "textBright 不比 textPrimary 强 —— bright 这个名字就没有意义"))
            disabled_ratio = ratio(c("textDisabled"), content)
            checks += 1
            if disabled_ratio >= ratio(c("textTertiary"), content):
                issues.append(Issue(f"{THEMES_SWIFT} ({theme_id}/{state})",
                                    f"禁用态 {disabled_ratio:.2f} 不淡于辅助色"
                                    f" {ratio(c('textTertiary'), content):.2f}"))
            judge("禁用态下限", disabled_ratio, 1.5)

            # 表面：距离 + 顺序
            for role in ("sidebar", "panel", "window"):
                checks += 1
                if distance(content, c(role)) < SURFACE_SEPARATION:
                    issues.append(Issue(f"{THEMES_SWIFT} ({theme_id}/{state})",
                                        f"内容区与 {role} 太接近（距离 {distance(content, c(role)):.3f}，"
                                        f"门槛 {SURFACE_SEPARATION}）"))
            order = ["window", "sidebar", "content", "panel", "raised"]
            luminances = [luminance(c(role)) for role in order]
            checks += 1
            if is_dark:
                for previous, current, a, b in zip(luminances, luminances[1:], order, order[1:]):
                    if not current > previous:
                        issues.append(Issue(f"{THEMES_SWIFT} ({theme_id}/深色)",
                                            f"{b} 不比 {a} 亮（深色靠明度递增表达层次）"))
                        break
            else:
                for role, value in zip(order, luminances):
                    if role != "content" and value > luminances[order.index("content")]:
                        issues.append(Issue(f"{THEMES_SWIFT} ({theme_id}/浅色)",
                                            f"{role} 比 content 还亮（浅色不变式）"))
                        break

            # 状态色
            for role in ("success", "warning", "danger"):
                for background in ("content", "panel"):
                    judge(f"状态 {role} on {background}", ratio(c(role), c(background)), COMPONENT)

            # 强调家族（基准 = 深色对 window、浅色对白）
            base = c("window") if is_dark else 0xFFFFFF
            for role in LINK_ROLES:
                judge(f"强调家族 {role}（文字 / 链接）", ratio(c(role), base), BODY_TEXT)
            for role in ICON_ROLES:
                judge(f"强调家族 {role}（图标线）", ratio(c(role), base), COMPONENT)

            # 语法六档（按角色取家族值）
            syntax_values = {
                "keyword": c("accentGlow"), "identifier": c("textPrimary"), "string": c("accentWarm"),
                "number": c("accentTeal"), "function": c("accent"), "comment": c("textTertiary"),
            }
            checks += 1
            if len(set(syntax_values.values())) != len(syntax_values):
                issues.append(Issue(f"{THEMES_SWIFT} ({theme_id}/{state})", "语法六档有重复值"))
            for role, value in syntax_values.items():
                floor = LARGE_TEXT if role == "comment" else BODY_TEXT
                judge(f"语法 {role}", ratio(value, content), floor)

            # 发丝线
            checks += 1
            if not is_dark:
                if luminance(hairline_light) >= luminance(content):
                    issues.append(Issue(f"{THEMES_SWIFT} ({theme_id}/浅色)",
                                        "浅色发丝线不比 content 暗（白的线在白底上等于没有）"))
            checks += 1
            if not 0.05 <= hairline_alpha <= 0.20:
                issues.append(Issue(f"{THEMES_SWIFT} ({theme_id})",
                                    f"深色发丝线透明度 {hairline_alpha} 不在 0.05~0.20 的区间里"))
    return issues, checks


# ---------------------------------------------------------------- 判据 D

def check_syntax_binding(root: pathlib.Path) -> list[Issue]:
    issues: list[Issue] = []
    text = (root / TOKENS_SWIFT).read_text(encoding="utf-8")
    block = re.search(r"public func color\(in theme: DesignTheme\) -> ThemeColor \{\n        switch self \{\n(.*?)\n        \}",
                      text, re.S)
    lines = re.findall(r"case \.(\w+): return (\w+)\.(\w+)\.color\(in: theme\)", text)
    mapping = {tone: role for tone, family, role in lines}
    for tone, role in SYNTAX_BINDING.items():
        if mapping.get(tone) != role:
            issues.append(Issue(TOKENS_SWIFT,
                                f"语法 {tone} 应挂 {role}，实测 {mapping.get(tone)}"
                                f" —— 六档与家族脱钩就是留了一个孤立的语法色"))
    if block is None:
        issues.append(Issue(TOKENS_SWIFT, "语法六档的映射块找不到（判据 D 的前提没了）"))
    return issues


# ---------------------------------------------------------------- 判据 E

def check_names_and_pending(root: pathlib.Path) -> tuple[list[Issue], int]:
    issues: list[Issue] = []
    sites = 0
    localization = (root / LOCALIZATION_SWIFT).read_text(encoding="utf-8")
    for theme_id, chinese in THEME_NAMES_ZH.items():
        key = "designTheme" + "".join(part.capitalize() for part in theme_id.split("-"))
        match = re.search(rf"\.{key}: \[\.simplifiedChinese: \"([^\"]+)\"", localization)
        sites += 1
        if not match:
            issues.append(Issue(LOCALIZATION_SWIFT, f"找不到主题名键 .{key} 的中文条目"))
        elif match.group(1) != chinese:
            issues.append(Issue(LOCALIZATION_SWIFT,
                                f"主题名 {theme_id} 的中文是「{match.group(1)}」，应为「{chinese}」"
                                f" —— 三个名字是 Linux 侧给的名，不许改"))
    doc = (root / DESIGN_DOC).read_text(encoding="utf-8") if (root / DESIGN_DOC).exists() else ""
    for chinese in THEME_NAMES_ZH.values():
        sites += 1
        # 严格认**主题表里的那一行**（`| 序号 | 主题名 | …`）：正文别处提到这个名字不算
        # —— 否则"表被改坏了、正文还提过"就会静默放过（本判据的自检例 ⑨ 就是这么抓出来的）。
        if not re.search(rf"^\|\s*\d+\s*\|\s*{re.escape(chinese)}\s*\|", doc, re.M):
            issues.append(Issue(DESIGN_DOC, f"§9 的主题表里找不到「{chinese}」这一行"
                                            f" —— 名对齐是判据 E 的一半"))
    # 推导主题 ↔ 待值登记（成对）：有推导主题就必须 ① 值表旁标着「推导」② 发布计划还登记着那件待值
    theme_text = theme_swift_text(root)
    derived = [theme_id for theme_id in THEME_IDS if theme_id != "tech-blue"]
    release = (root / RELEASE_PLAN).read_text(encoding="utf-8") if (root / RELEASE_PLAN).exists() else ""
    for theme_id in derived:
        palette_name = "".join(
            part if index == 0 else part.capitalize() for index, part in enumerate(theme_id.split("-"))
        )
        marker = f"public static let {palette_name} = ThemePalette("
        position = theme_text.find(marker)
        sites += 1
        if position < 0:
            issues.append(Issue(THEMES_SWIFT, f"找不到主题 {theme_id} 的值表（{palette_name}）"))
            continue
        # 认**紧挨着声明的那一段注释块**（抬头文件注释里到处都写着"推导"，
        # 拿它当证据等于没判 —— 本判据的自检例 ⑮ 就是这么抓出来的）。
        header_lines: list[str] = []
        for line in reversed(theme_text[:position].splitlines()):
            if line.strip().startswith("//") or not line.strip():
                header_lines.append(line)
            else:
                break
        preamble = "\n".join(header_lines)
        # 标记词取 §9.1 的原话「推导草案」：只认"推导"两个字太松 —— 紧挨着的说明段里
        # 本来就会写"推导口径"，那样抹掉标记行也照样绿（自检例 ⑮ 的另一半就这么抓出来的）。
        if "推导草案" not in preamble:
            issues.append(Issue(THEMES_SWIFT,
                                f"{palette_name} 的值表旁没有「推导草案」标记 —— "
                                f"待值期间推导值必须逐块标出来（不许当实际值卖）"))
        sites += 1
        if not re.search(r"豆芽绿 / 玫瑰金 色值（Linux 侧）", release):
            issues.append(Issue(RELEASE_PLAN,
                                "有推导主题（推导值），但发布计划的待输入表里没有登记那件待值"
                                " —— 推导值不许静默变成实际值"))
    return issues, sites


# ---------------------------------------------------------------- 判据 G

def check_ui_entry(root: pathlib.Path) -> tuple[list[Issue], int]:
    """界面入口：主题真的能被选到、每主题三个真实场景、推导值如实标注、强调色入口不许消失。"""
    issues: list[Issue] = []
    sites = 0
    panel_path = root / APPEARANCE_SWIFT
    if not panel_path.exists():
        return [Issue(APPEARANCE_SWIFT, "「外观」面板文件不存在 —— 主题入口无处落地")], sites
    panel = panel_path.read_text(encoding="utf-8")
    line_count = len(panel.splitlines())
    sites += 1
    if line_count < MIN_PANEL_LINES:
        issues.append(Issue(APPEARANCE_SWIFT, f"面板只有 {line_count} 行（下限 {MIN_PANEL_LINES}）"
                                              f" —— 扫描面被削过，不许通过"))

    # ① 入口：主题集必须被**逐个列出**（用户在面板上选得到），且选中走 `select(_:)`
    #    —— 「换主题」这件事只有一个写入口，界面不许自己往 UserDefaults 里写。
    sites += 1
    if "ForEach(DesignTheme.all)" not in panel:
        issues.append(Issue(APPEARANCE_SWIFT, "面板里没有逐个列出主题集（`ForEach(DesignTheme.all)`）"
                                              " —— 三个主题里就有人选不到"))
    sites += 1
    if not re.search(r"designTheme\.select\(|DesignThemeManager\.shared\.select\(", panel):
        issues.append(Issue(APPEARANCE_SWIFT, "面板里没有走 `select(_:)` 的选主题调用点"
                                              " —— 换主题的唯一写入口在 `DesignThemeManager`（持久化也归它）"))
    sites += 1
    if "@ObservedObject" not in panel or "DesignThemeManager.shared" not in panel:
        issues.append(Issue(APPEARANCE_SWIFT, "面板没有订阅主题管理器 ⇒ 换了主题这块面板自己不跟着变"
                                              "（其它面板会因根视图重建而变，它是唯一漏网的那块）"))

    # ② 主题行：三个**真实场景**必须画在**该主题自己的表面**上
    row = _type_slice(panel, "struct DesignThemeOptionRow")
    sites += 1
    if row is None:
        issues.append(Issue(APPEARANCE_SWIFT, "找不到主题候选行（`struct DesignThemeOptionRow`）"
                                              " —— 主题列表画不出来"))
    else:
        if len(row) < MIN_ROW_CHARS:
            issues.append(Issue(APPEARANCE_SWIFT, f"主题行只有 {len(row)} 字符（下限 {MIN_ROW_CHARS}）"
                                                  f" —— 行被掏空，不许通过"))
        for label, marker in SCENE_MARKERS.items():
            sites += 1
            if marker not in row:
                issues.append(Issue(APPEARANCE_SWIFT,
                                    f"主题行里没有「{label}」这个真实场景（缺标记 `{marker}`）"
                                    f" —— 只给一块色卡，用户只能凭想象"))
        sites += 1
        if THEME_SURFACE_MARKER not in row:
            issues.append(Issue(APPEARANCE_SWIFT,
                                f"主题行的预览没有画在**该主题自己的表面**上（缺 `{THEME_SURFACE_MARKER}`）"
                                f" —— 那样看到的还是当前界面的底，换主题等于没预览"))
        sites += 1
        if not re.search(r"theme\.accent", row):
            issues.append(Issue(APPEARANCE_SWIFT, "主题行的三个场景没有用**该主题配套**的强调色"
                                                  "（`theme.accent`）—— 预览会拿当前主题的色去画别人的场景"))
        # ③ 推导值：逐条标注（不许把推导值当实际值卖）
        sites += 2
        if "isDerivedDraft" not in row:
            issues.append(Issue(APPEARANCE_SWIFT, "主题行没有问 `isDerivedDraft`"
                                                  " —— 待值的主题混在列表里、用户看不出来"))
        if DERIVED_MARKER_KEY not in row:
            issues.append(Issue(APPEARANCE_SWIFT, f"主题行没有画出推导标记（缺 `{DERIVED_MARKER_KEY}`）"))
        localization = (root / LOCALIZATION_SWIFT).read_text(encoding="utf-8")
        sites += 1
        if not re.search(rf"\.{DERIVED_LKEY}: \[\.simplifiedChinese: \"推导草案\"", localization):
            issues.append(Issue(LOCALIZATION_SWIFT, f"语言表里没有 `.{DERIVED_LKEY}` 的中文条目「推导草案」"
                                                    f" —— 界面上那句话无处可取"))

    # ④ 强调色入口不许**静默**消失（FR-EDIT-33 原文的「强调色可配置」是已交付能力）
    sites += 1
    if "AccentTheme.all" not in panel:
        issues.append(Issue(APPEARANCE_SWIFT, "面板不再逐个列出强调色（`AccentTheme.all`）"
                                              " —— 加了主题不等于可以删掉已交付的「强调色可配置」；"
                                              "真要收掉，得先改 SRS 与判据、并把理由写进台账"))

    # ⑤ 宿主覆盖（快照用）不落盘：拍一张图不许改用户偏好
    manager_path = root / THEME_MANAGER_SWIFT
    sites += 1
    if not manager_path.exists():
        issues.append(Issue(THEME_MANAGER_SWIFT, "主题运行时对象不存在"))
    else:
        manager = manager_path.read_text(encoding="utf-8")
        sites += 2
        if "func beginHostTheme(" not in manager or "func endHostTheme(" not in manager:
            issues.append(Issue(THEME_MANAGER_SWIFT, "没有宿主语境的进入 / 退出接口"
                                                    "（`beginHostTheme` / `endHostTheme`）—— 快照只能靠改用户偏好"))
        body = _type_slice(manager, "func beginHostTheme(", closing="\n    }") or ""
        sites += 1
        if "UserDefaults" in body:
            issues.append(Issue(THEME_MANAGER_SWIFT, "宿主语境覆盖里写了 `UserDefaults`"
                                                    " —— 拍一张快照就把用户的偏好改了（语言那条路定过这个口径）"))
        sites += 1
        if "UserDefaults.standard.set" not in manager:
            issues.append(Issue(THEME_MANAGER_SWIFT, "选主题没有落盘 （缺 `UserDefaults.standard.set`）"
                                                    " —— 重启就丢"))
    return issues, sites


# ---------------------------------------------------------------- 自检

def _sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _fixture(base: pathlib.Path) -> pathlib.Path:
    """把判据要看的七份文件复制到临时目录（夹具一律在临时目录里写坏）。"""
    for relative in (THEMES_SWIFT, TOKENS_SWIFT, LOCALIZATION_SWIFT, DESIGN_DOC, RELEASE_PLAN,
                     APPEARANCE_SWIFT, THEME_MANAGER_SWIFT):
        target = base / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(ROOT / relative, target)
    return base


def _patch(path: pathlib.Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    assert old in text, f"夹具锚点失效：{old[:60]}"
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def self_test() -> int:
    cases: list[tuple[str, bool, list[Issue]]] = []
    watched = (THEMES_SWIFT, TOKENS_SWIFT, LOCALIZATION_SWIFT, DESIGN_DOC, RELEASE_PLAN,
               APPEARANCE_SWIFT, THEME_MANAGER_SWIFT)
    before = {name: _sha(ROOT / name) for name in watched}

    def static_issues(fixture: pathlib.Path) -> list[Issue]:
        issues = check_theme_set(fixture)
        issues += check_palette_shape(fixture)[0]
        issues += check_thresholds(fixture)[0]
        issues += check_syntax_binding(fixture)
        issues += check_names_and_pending(fixture)[0]
        issues += check_ui_entry(fixture)[0]
        return issues

    with tempfile.TemporaryDirectory(prefix="doyah-themes-selftest-") as tmp:
        base = _fixture(pathlib.Path(tmp) / "green")
        # ① 绿：好情况
        cases.append(("好情况（绿）", False, static_issues(base)))

        # ② 红：少一个色角色（复制粘贴新主题时漏一行）
        missing = _fixture(pathlib.Path(tmp) / "bad-missing-role")
        _patch(missing / THEMES_SWIFT, "        textDisabled: ThemeColor(light: 0xA9C3B1, dark: 0x3E6B4E),\n", "")
        cases.append(("值表少一个色角色", True, check_palette_shape(missing)[0]))

        # ③ 红：正文被改成几乎与底同色（低对比）
        low = _fixture(pathlib.Path(tmp) / "bad-contrast")
        _patch(low / THEMES_SWIFT,
               "textPrimary: ThemeColor(light: 0x12301E, dark: 0xC6D9CB)",
               "textPrimary: ThemeColor(light: 0x12301E, dark: 0x112218)")
        cases.append(("正文对比度不足", True, check_thresholds(low)[0]))

        # ④ 红：window 与 content 同色（表面分不开）
        same = _fixture(pathlib.Path(tmp) / "bad-surface")
        _patch(same / THEMES_SWIFT,
               "window: ThemeColor(light: 0xF2F8F3, dark: 0x04120A)",
               "window: ThemeColor(light: 0xFFFFFF, dark: 0x0F2418)")
        cases.append(("window 与 content 同色", True, check_thresholds(same)[0]))

        # ⑤ 红：深色五档明度不递增
        flat = _fixture(pathlib.Path(tmp) / "bad-order")
        _patch(flat / THEMES_SWIFT,
               "content: ThemeColor(light: 0xFFFFFF, dark: 0x0F2418)",
               "content: ThemeColor(light: 0xFFFFFF, dark: 0x081109)")
        cases.append(("深色五档明度不递增", True, check_thresholds(flat)[0]))

        # ⑥ 红：强调家族某档掉到图标线以下（并且语法 keyword 跟着掉）
        weak_accent = _fixture(pathlib.Path(tmp) / "bad-accent")
        _patch(weak_accent / THEMES_SWIFT,
               "accentGlow: ThemeColor(light: 0x1B7A4A, dark: 0xA8E6BB)",
               "accentGlow: ThemeColor(light: 0x1B7A4A, dark: 0x1D2A1D)")
        cases.append(("强调家族掉到门槛以下", True, check_thresholds(weak_accent)[0]))

        # ⑦ 红：浅色发丝线不比 content 暗
        hairline = _fixture(pathlib.Path(tmp) / "bad-hairline")
        _patch(hairline / THEMES_SWIFT, "hairlineLight: 0xD5E3D9,", "hairlineLight: 0xFFFFFF,")
        cases.append(("浅色发丝线不比 content 暗", True, check_thresholds(hairline)[0]))

        # ⑧ 红：主题名与 Linux 侧的名对不上
        renamed = _fixture(pathlib.Path(tmp) / "bad-name")
        _patch(renamed / LOCALIZATION_SWIFT,
               '.designThemeBeanGreen: [.simplifiedChinese: "豆芽绿"',
               '.designThemeBeanGreen: [.simplifiedChinese: "嫩芽绿"')
        cases.append(("主题名与 Linux 侧不一致", True, check_names_and_pending(renamed)[0]))

        # ⑨ 红：§9 的主题表少一行（文档没跟上）
        doc_short = _fixture(pathlib.Path(tmp) / "bad-doc")
        _patch(doc_short / DESIGN_DOC, "| 3 | 玫瑰金 |", "| 3 | 晚霞红 |")
        cases.append(("§9 主题表与枚举对不上", True, check_names_and_pending(doc_short)[0]))

        # ⑩ 红：待值登记被删（推导值静默当实际值）
        no_pending = _fixture(pathlib.Path(tmp) / "bad-pending")
        _patch(no_pending / RELEASE_PLAN, "豆芽绿 / 玫瑰金 色值（Linux 侧）", "（已到位）")
        cases.append(("待值登记被删", True, check_names_and_pending(no_pending)[0]))

        # ⑪ 红：语法色与家族脱钩（keyword 改回硬编码色）
        unhooked = _fixture(pathlib.Path(tmp) / "bad-syntax")
        _patch(unhooked / TOKENS_SWIFT,
               "case .keyword: return AccentFamily.accentGlow.color(in: theme)",
               "case .keyword: return ThemeColor(light: 0x9BA8FF, dark: 0x9BA8FF)")
        cases.append(("语法色与家族脱钩", True, check_syntax_binding(unhooked)))

        # ⑫ 红：空跑防护 —— 主题集被掏空
        hollow = _fixture(pathlib.Path(tmp) / "bad-empty")
        text = (hollow / THEMES_SWIFT).read_text(encoding="utf-8")
        text = re.sub(r'^\s*case \w+ = "[a-z-]+"$', "", text, flags=re.M)
        (hollow / THEMES_SWIFT).write_text(text, encoding="utf-8")
        cases.append(("主题集被掏空（空跑）", True, check_theme_set(hollow)))

        # ⑮ 红：推导标注被抹掉（把推导值当实际值卖）
        unmarked = _fixture(pathlib.Path(tmp) / "bad-derived")
        _patch(unmarked / THEMES_SWIFT,
               "    // MARK: 豆芽绿（**推导草案** —— Linux 侧实际色值到位后整表替换，不留两套）",
               "    // MARK: 豆芽绿")
        cases.append(("推导标注被抹掉", True, check_names_and_pending(unmarked)[0]))

        # ⑬ 红：`.all` 漏列一个主题
        short_all = _fixture(pathlib.Path(tmp) / "bad-all")
        _patch(short_all / THEMES_SWIFT,
               "public static let all: [DesignTheme] = [.techBlue, .beanGreen, .roseGold]",
               "public static let all: [DesignTheme] = [.techBlue, .beanGreen]")
        cases.append(("`.all` 漏列主题", True, check_theme_set(short_all)))

        # ⑭ 红：空跑防护 —— 值表被删光
        no_palette = _fixture(pathlib.Path(tmp) / "bad-nopalette")
        text = (no_palette / THEMES_SWIFT).read_text(encoding="utf-8")
        text = re.sub(r"public static let \w+ = ThemePalette\(.*?\n    \)", "", text, flags=re.S)
        (no_palette / THEMES_SWIFT).write_text(text, encoding="utf-8")
        cases.append(("值表被删光（空跑）", True, check_palette_shape(no_palette)[0]))

        # ⑯ 红：面板不再逐个列出主题集（有人选不到）
        no_entry = _fixture(pathlib.Path(tmp) / "bad-entry")
        _patch(no_entry / APPEARANCE_SWIFT,
               "ForEach(DesignTheme.all) { candidate in",
               "ForEach(DesignTheme.all.prefix(1)) { candidate in")
        cases.append(("面板不再列出主题集", True, check_ui_entry(no_entry)[0]))

        # ⑰ 红：主题行少一个真实场景（只给一块色卡 —— 界面退化成"凭想象选"）
        weak_row = _fixture(pathlib.Path(tmp) / "bad-row-scene")
        _patch(weak_row / APPEARANCE_SWIFT,
               "白字（该主题配套的压暗档）\n            Text(L(theme.nameKey).prefix(2))\n"
               "                .font(Theme.font(.caption))\n                .foregroundStyle(.white)",
               "白字（该主题配套的压暗档，场景被删）\n            Text(L(theme.nameKey).prefix(2))\n"
               "                .font(Theme.font(.caption))\n                .foregroundStyle(.primary)")
        cases.append(("主题行少一个真实场景", True, check_ui_entry(weak_row)[0]))

        # ⑱ 红：推导主题在界面上不再标注（推导值当实际值卖）
        unlabeled = _fixture(pathlib.Path(tmp) / "bad-label")
        _patch(unlabeled / APPEARANCE_SWIFT, "if theme.isDerivedDraft {", "if false {")
        cases.append(("推导主题在界面上不标注", True, check_ui_entry(unlabeled)[0]))

        # ⑲ 红：加了主题就把已交付的「强调色可配置」删掉（静默收功能）
        accent_gone = _fixture(pathlib.Path(tmp) / "bad-accent-entry")
        _patch(accent_gone / APPEARANCE_SWIFT,
               "ForEach(AccentTheme.all) { theme in", "ForEach([]) { theme in")
        cases.append(("强调色入口被静默删除", True, check_ui_entry(accent_gone)[0]))

        # ⑳ 红：宿主语境的覆盖写了盘（拍一张快照就改了用户的偏好）
        persists = _fixture(pathlib.Path(tmp) / "bad-host-persist")
        _patch(persists / THEME_MANAGER_SWIFT,
               "    func beginHostTheme(_ theme: DesignTheme) -> DesignTheme? {\n        let previous = hostOverride",
               "    func beginHostTheme(_ theme: DesignTheme) -> DesignTheme? {\n"
               "        UserDefaults.standard.set(theme.id, forKey: DesignTheme.Storage.key)\n"
               "        let previous = hostOverride")
        cases.append(("宿主语境覆盖写了盘", True, check_ui_entry(persists)[0]))

        # ㉑ 红：主题行整块被删（空跑）
        no_row = _fixture(pathlib.Path(tmp) / "bad-no-row")
        _patch(no_row / APPEARANCE_SWIFT,
               "private struct DesignThemeOptionRow: View {",
               "private struct ThemeRowPlaceholder: View {")
        cases.append(("主题行整块被删（空跑）", True, check_ui_entry(no_row)[0]))

    failures = 0
    for name, expect_red, issues in cases:
        ok = bool(issues) == expect_red
        if not ok:
            failures += 1
        print(f"{'✅' if ok else '❌'} {name}：{'报红' if issues else '绿'}"
              f"（期望{'报红' if expect_red else '绿'}）"
              + (f" —— {issues[0]}" if issues and not expect_red else ""))

    after = {name: _sha(ROOT / name) for name in watched}
    unchanged = before == after
    if not unchanged:
        failures += 1
    print(f"{'✅' if unchanged else '❌'} 真仓库七份文件逐字节未变")
    total = len(cases) + 1
    print(f"自测通过（{total} 例）" if failures == 0 else f"自测失败：{failures}/{total} 例不符")
    return 0 if failures == 0 else 1


# ---------------------------------------------------------------- 主流程

def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return self_test()

    issues: list[Issue] = []
    issues += check_theme_set(ROOT)
    shape_issues, role_total = check_palette_shape(ROOT)
    issues += shape_issues
    threshold_issues, checks = check_thresholds(ROOT)
    issues += threshold_issues
    issues += check_syntax_binding(ROOT)
    name_issues, sites = check_names_and_pending(ROOT)
    issues += name_issues
    entry_issues, entry_sites = check_ui_entry(ROOT)
    issues += entry_issues

    print("==> 主题集（配色方案，队列 L-80 ㈠ ㈡）")
    print(f"    ① 主题集：{len(theme_ids_in_source(ROOT))} 个（台账 {len(THEME_IDS)} 个：{', '.join(THEME_IDS)}）")
    print(f"    ② 值表角色：{role_total} 个字段（下限 {MIN_ROLES * MIN_THEMES}）")
    print(f"    ③ 独立复算：{checks} 条门槛（下限 {MIN_CHECKS}；本脚本自己实现 WCAG，与 Swift 单测互补）")
    print(f"    ④ 语法六档 ↔ 家族角色：{len(SYNTAX_BINDING)} 条映射对账")
    print(f"    ⑤ 名对齐 / 待值登记：{sites} 处文档落点")
    print(f"    ⑥ 界面入口：{entry_sites} 处落点（主题列表 / 三个真实场景 / 推导逐条标注 /"
          f" 强调色入口 / 宿主覆盖不落盘）")

    if len(theme_ids_in_source(ROOT)) < MIN_THEMES:
        issues.append(Issue(THEMES_SWIFT, f"主题数 {len(theme_ids_in_source(ROOT))} < 下限 {MIN_THEMES}"))
    if role_total < MIN_ROLES * MIN_THEMES:
        issues.append(Issue(THEMES_SWIFT, f"值表字段合计 {role_total} < 下限 {MIN_ROLES * MIN_THEMES}"
                                         f" —— 扫描面被削过，不许通过"))
    if checks < MIN_CHECKS:
        issues.append(Issue("复算", f"只跑了 {checks} 条门槛（下限 {MIN_CHECKS}）—— 空跑不许通过"))
    if entry_sites < MIN_ENTRY_SITES:
        issues.append(Issue(APPEARANCE_SWIFT, f"界面入口只判了 {entry_sites} 处（下限 {MIN_ENTRY_SITES}）"
                                             f" —— 扫描面被削过，不许通过"))

    if issues:
        print(f"\n❌ {len(issues)} 处未过：")
        for issue in issues:
            print(f"   · {issue}")
        return 1
    print("\n✅ 主题集三选一：三套值表角色齐全、逐主题 × 深浅两态过门槛、名与 Linux 侧对齐、待值登记在位；"
          "界面入口（主题列表 + 每主题三个真实场景 + 推导逐条标注）已接上")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
