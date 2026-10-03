#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""门禁：**菜单栏（AppKit 那一层）的每一项都要跟当前界面语言同语**（队列 `L-145` 判据 ·
内测清单 **丙2** 及其**下一层**）。

判据分两代，本文件是第二代（2026-10-02 内测第三批）：

  · 第一代（L-145，第 140 轮）判的是「**顶层标题**不许停在启动语言」—— 由头是
    「语言设置为英文时菜单 Edit/View/Window 里有中文」；
  · 第二代（本代）判的是「**整棵菜单树的每一项**都不许停在启动语言」—— 由头是需求提出者
    2026-10-02 的原话：「中文版中显示菜单里还有 2 个英文菜单：show tab bar 和 show all tabs，
    窗口菜单中有 Fill、Center、Move & Resize、Full Screen Tile 等菜单」。

## 为什么第一代放过了它（这正是本代要补的缺口）

`显示` / `窗口` 里有一批项**不是 SwiftUI 建的**，而是 AppKit 在**菜单被展开的那一刻**才插进
树里的。实测（`DOYAH_MENU_DUMP_OPEN=1` 前后各一份 dump）：不展开时它们**一条都不在**树里，
于是第一代判据（只看「还没点开菜单」的 A 段）**根本枚举不到它们** —— 枚举不到就没判，
而"没判"在观感上等于通过。本代把「展开」写进探针：判据先让 App 自己把每个顶层菜单展开一次，
再判整棵树（C 段）。

## 判的四条（每一档启动两遍：英文→中文 / 中文→英文，走用户真实的语言切换入口）

  ① **表内一致**：认得出的项，现标题必须等于表里该键在目标语言下的文案（`MISMATCH` 为 0，
     且**不信 dump 自述**、判据自己算）；
  ② **表外兜底（语言一致性）**：每一项的**可见标题**都要跟当前界面语言同语 ——
     中文界面下不许出现**没有汉字**的项、英文界面下不许出现**含汉字**的项（豁免只有
     「本来就该两种语言都一样的」那几类：应用显示名 / 语言自身的显示名 / 窗口标题）；
  ③ **未覆盖项如实列出**：认不出又不在豁免里的项**逐条点名**（selector + 标题）并判红 ——
     「认不出」⇒ 自愈不碰它 ⇒ 它一定停在启动语言；本代还把**必检项**（标签页栏 /
     所有标签页 / 填充 / 居中 / 移动与调整大小 / 全屏幕平铺 / 各平铺位 / 窗口标签页那几项）
     逐条列出来：**枚举不到就是「未覆盖」**。必检项分两档 —— **硬族**（AppKit 无条件插进来的：
     平铺那一批 / 全部最小化 / 窗口标签页那一批）缺了**即判红**；**条件族**（随窗口标签页状态浮动
     的「显示标签页栏 / 显示所有标签页」）单档缺了**如实登记为未覆盖**、不判红，但**一轮两档
     一次都没出现**就判红（那种情况只可能是探针没展开 / AppKit 改了写法）；
  ④ **空跑防护 + 形状**：条目数与识别项数下限、五个系统菜单顶层必须在场、坏行判红。

用法：
    python3 Scripts/check-menu-language.py                # 真启动两档 + 判（需要先构建 .app）
    python3 Scripts/check-menu-language.py --json         # 机器读
    python3 Scripts/check-menu-language.py --self-test    # 判据自己的证据（合成 dump，不启动应用）
    python3 Scripts/check-menu-language.py --dump-dir D   # 只判已有 dump（离线复核 / 红绿对照）
    python3 Scripts/check-menu-language.py --app P        # 换一个待判的可执行文件（红绿对照用）

**边界（如实登记）**：① 服务子菜单里**别的应用**提供的项跟的是**系统语言**
（`NFR-I18N-03` 口径），不在本判据范围；② 判据判的是 dump 的三段（A 原样 / C 各菜单展开
过一次之后 / B 自愈路之后），**展开走的是用户那条路**（`popUpMenuPositioningItem`），
所以 C 段就是「用户展开菜单那一刻看到的样子」。
"""

from __future__ import annotations  # macOS 自带 python3 是 3.9

import argparse
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import time

BASE = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_APP = BASE / "dist" / "DoyahStudio.app" / "Contents" / "MacOS" / "DoyahStudio"
DEFAULTS_DOMAIN = "studio.doyah.DoyahStudio"
# 绿对照：**修后**那份真 dump（2026-10-02，含展开族与 C 段）
FIXTURE_DUMP = BASE / "Scripts" / "fixtures" / "menu-dump-real-20261003.txt"
# 历史留档（第 140 轮那份：格式同前一代，**没有** C 段与展开族 ⇒ 只作历史，不作绿对照）
LEGACY_FIXTURE = BASE / "Scripts" / "fixtures" / "menu-dump-real-20261001.txt"

SECTION_MARK = "# DOYAH-MENU-DUMP v1"
# 三段的段名（探针按 `A 原样（未展开菜单）` / `C 各菜单展开过一次之后…` / `B …` 写出来）
SECTION_IDS = ("A", "C", "B")

# 两档：启动语言 → 目标语言（用户报的是一个方向，另一个方向是同一个 bug 的另一面）
SCENARIOS = (
    ("switch-en-to-zh", "en", "zh-Hans"),
    ("switch-zh-to-en", "zh-Hans", "en"),
)

# 系统菜单的五个顶层标题键（每一档都必须真的在菜单树里 —— 少一个就是「菜单没建成」）
SYSTEM_TOP_LEVEL_KEYS = (
    "menuSystemFile",
    "menuSystemEdit",
    "menuSystemView",
    "menuSystemWindow",
    "menuSystemHelp",
)

# 「认不出」的豁免：认不出 ⇒ 自愈不碰它 ⇒ 它会停在启动语言。这三类**本来就该**认不出
# （逐条写理由），其余任何认不出的项都要**逐条点名**判红（这就是「未覆盖项如实列出」）。
LANGUAGE_TITLES = ("简体中文", "English")


def whitelist_reason(item, app_name):
    """认不出的项里，允许它认不出的理由；不在豁免里的返回 None。"""
    # ① 语言自身的显示名（`简体中文` / `English`）—— 每种语言用自己的写法，**故意**不跟当前语言走。
    if item.selector == "menuAction:" and item.title in LANGUAGE_TITLES:
        return "语言自身的显示名"
    # ② 应用菜单的标题 = 应用显示名（`CFBundleName`），是**专有名词**，两种语言都一样。
    if item.selector == "submenuAction:" and item.title == app_name:
        return "应用显示名（专有名词）"
    # ③ 窗口列表项：标题就是窗口标题，随活动栏走，不是菜单文案。
    if item.selector == "makeKeyAndOrderFront:":
        return "窗口列表项（标题 = 窗口标题）"
    return None

# 必检的「展开族」：AppKit 在**菜单展开时**才插进树里的项（selector 或标题，逐条点名）。
# 意义 = 「枚举不到就是未覆盖」：探针哪一天不再展开菜单、或 AppKit 改了这批项的写法，
# 本判据必须**判红**（而不是因为"没枚举到"静悄悄放过 —— 那正是内测第三批打回来的那一面）。
def _sel(*selectors):
    return lambda item: item.selector in selectors


def _title(*titles):
    return lambda item: item.title in titles


# 每一项 = (名字, 判据, **是否条件性**)。区别在「枚举不到」怎么算：
#   · 硬族（`conditional=False`）：AppKit 无条件插进来 ⇒ 某一档的 C 段里没有**就判红**；
#   · 条件族（`conditional=True`）：随窗口标签页状态浮动（实测：同一份代码两次真启动，
#     一次插了「显示标签页栏 / 显示所有标签页」一次没插）⇒ 单档缺了**如实登记为未覆盖**、
#     不判红；但**一轮两档一次都没出现**判红（那种情况只可能是探针没展开 / AppKit 改了写法）。
REQUIRED_OPEN_ITEMS = (
    ("显示菜单：标签页栏（`toggleTabBar:`）", _sel("toggleTabBar:"), True),
    ("显示菜单：所有标签页（`toggleTabOverview:`）", _sel("toggleTabOverview:"), True),
    ("窗口菜单：填充 / 居中（`_zoomFill:` / `_zoomCenter:`）", _sel("_zoomFill:", "_zoomCenter:"), False),
    ("窗口菜单：移动与调整大小（子菜单标题，无 selector）", _title("Move & Resize", "移动与调整大小"), False),
    ("窗口菜单：全屏幕平铺（子菜单标题，无 selector）", _title("Full Screen Tile", "全屏幕平铺"), False),
    ("窗口菜单：平铺位（左 / 右 / 上 / 下）",
     _sel("_zoomLeft:", "_zoomRight:", "_zoomTop:", "_zoomBottom:"), False),
    ("窗口菜单：分组标题（二等分 / 四等分 / 排列）",
     _title("Halves", "Quarters", "Arrange", "二等分", "四等分", "排列"), False),
    ("窗口菜单：恢复上一个大小（`_zoomUntile:`）", _sel("_zoomUntile:"), False),
    ("窗口菜单：全部最小化 / 全部缩放", _sel("miniaturizeAll:", "zoomAll:"), False),
    ("窗口菜单：窗口标签页那一族（上一个 / 下一个 / 新窗口 / 合并）",
     _sel("selectPreviousTab:", "selectNextTab:", "moveTabToNewWindow:", "mergeAllWindows:"), False),
)

# 空跑防护下限。A 段（还没展开菜单）与 C 段（展开过之后）各一组 —— C 段条目明显更多
# （2026-10-02 判据实跑实测：A 65 条 / 识别 61 · C 102 条 / 识别 98；条目数随窗口与标签页状态
# 浮动，故下限取实测的 ~80%），防「dump 没写出来 / 菜单树是空的」也算过。
FLOORS = {
    "A": {"items": 50, "recognized": 45},
    "C": {"items": 80, "recognized": 75},
}

HAN = re.compile(r"[\u4e00-\u9fff]")


class Line:
    __slots__ = ("depth", "kind", "selector", "title", "key", "target", "verdict", "submenu_title")

    def __init__(self, depth, kind, selector, title, key, target, verdict, submenu_title=""):
        self.depth = depth
        self.kind = kind
        self.selector = selector
        self.title = title
        self.key = key
        self.target = target
        self.verdict = verdict
        self.submenu_title = submenu_title


def parse_sections(text):
    """把 dump 拆成 `{段名: [Line…]}` + 坏行清单。段名 = 段标里 `— ` 之后第一个词（A / C / B）。"""
    problems, sections, current = [], {}, None
    for line in text.splitlines():
        if line.startswith(SECTION_MARK):
            marker = line[len(SECTION_MARK):].lstrip(" —-").strip()
            current = marker.split(" ")[0] if marker else "?"
            sections.setdefault(current, [])
            continue
        if line.startswith("#") or not line.strip():
            continue
        if current is None:
            problems.append("段标之前就有条目行：%s" % line)
            continue
        parts = line.split("|")
        if len(parts) < 7:
            problems.append("坏行（段数 %d < 7）：%s" % (len(parts), line))
            continue
        try:
            depth = int(parts[0])
        except ValueError:
            problems.append("坏行（深度不是数字）：%s" % line)
            continue
        # 探针把子菜单自己的标题拼在最后一列（`ok submenu=…`）—— 它是菜单树的一部分
        # （顶层项显示的就是它），所以拆出来单独判（见 `judge_section` 的第三条）。
        verdict, submenu_title = parts[6], ""
        if " submenu=" in verdict:
            verdict, submenu_title = verdict.split(" submenu=", 1)
        sections[current].append(
            Line(depth, parts[1], parts[2], parts[3], parts[4], parts[5], verdict, submenu_title.strip())
        )
    if not sections:
        problems.append("dump 里找不到段标 `%s`（探针没写出来 / 格式变了）" % SECTION_MARK)
    return sections, problems


def language_problem(title, language):
    """可见标题的语言是否跟**当前界面语言**同语。返回 None = 同语。"""
    if language == "zh-Hans":
        if HAN.search(title):
            return None
        return "中文界面下这一项没有汉字（疑似英文 / 停在启动语言）"
    if HAN.search(title):
        return "英文界面下这一项含汉字（疑似中文 / 停在启动语言）"
    return None


def app_name_of(sections):
    """应用显示名 = 深度 0 那条项的标题（应用菜单；`submenuAction:`）。"""
    for lines in sections.values():
        for item in lines:
            if item.depth == 0 and item.kind != "separator" and item.title:
                return item.title
    return "?"


def judge_section(section_id, lines, language, app_name):
    """判一段。返回 (problems, stats, items)。"""
    problems = []
    stats = {"items": 0, "recognized": 0, "unrecognized": 0, "mismatch": 0, "uncovered": 0}
    keys_present, items = set(), []
    for item in lines:
        if item.kind == "separator":
            continue
        items.append(item)
        stats["items"] += 1
        exempt = whitelist_reason(item, app_name)
        if item.target != "-":
            stats["recognized"] += 1
            keys_present.add(item.key)
            # ① 表内一致：**判据自己算**（dump 自述与实测不符也判红 —— 否则改坏 dump 就能把红说成绿）。
            if item.target != item.title:
                stats["mismatch"] += 1
                problems.append("[%s] 停在启动语言：`%s`（应得 `%s` / 键 `%s`）"
                                % (section_id, item.title, item.target, item.key))
            elif item.verdict.startswith("MISMATCH"):
                problems.append("[%s] dump 自述与实测不符（自述 MISMATCH、实测一致）：`%s`"
                                % (section_id, item.title))
        else:
            stats["unrecognized"] += 1
            if exempt is None:
                stats["uncovered"] += 1
                problems.append("[%s] 未覆盖项（认不出 ⇒ 自愈不碰它 ⇒ 停在启动语言）：`%s` selector=`%s`"
                                % (section_id, item.title, item.selector))
        # ② 表外兜底：可见标题的语言必须跟当前界面语言同语（豁免 = 上面那三类）。
        if exempt is None:
            problem = language_problem(item.title, language)
            if problem:
                problems.append("[%s] %s：`%s` selector=`%s`"
                                % (section_id, problem, item.title, item.selector))
        # ③（同级的一条）子菜单**自己的标题**也要同语：顶层项在菜单栏上显示的就是它。
        if item.submenu_title and exempt is None:
            problem = language_problem(item.submenu_title, language)
            if problem:
                problems.append("[%s] %s（子菜单自己的标题）：`%s` selector=`%s`"
                                % (section_id, problem, item.submenu_title, item.selector))
    floor = FLOORS.get(section_id)
    if floor:
        if stats["items"] < floor["items"]:
            problems.append("[%s] 空跑防护：条目数 %d < 下限 %d" % (section_id, stats["items"], floor["items"]))
        if stats["recognized"] < floor["recognized"]:
            problems.append("[%s] 空跑防护：识别出来的项 %d < 下限 %d"
                            % (section_id, stats["recognized"], floor["recognized"]))
    if section_id == "A":
        missing = [key for key in SYSTEM_TOP_LEVEL_KEYS if key not in keys_present]
        if missing:
            problems.append("[A] 系统菜单顶层标题不在场：%s（菜单树没建成 ⇒ 这一档不算过）" % " / ".join(missing))
    if section_id == "C":
        notes = []
        coverage = {}
        for label, predicate, conditional in REQUIRED_OPEN_ITEMS:
            present = any(predicate(item) for item in items)
            coverage[label] = present
            if present:
                continue
            if conditional:
                notes.append("未覆盖（如实登记 · 不作通过）：条件性必检项 `%s` 本段没枚举到"
                             "（随窗口标签页状态浮动；一轮两档都没出现则判红）" % label)
            else:
                problems.append("[C] 未覆盖：必检项 `%s` 在本段里**枚举不到**"
                                "（AppKit 没插进来 / 探针没展开 / 写法变了）—— 枚举不到不许默认通过" % label)
        stats["coverage"] = coverage
        stats["notes"] = notes
    return problems, stats, items


def judge_all(dumps, problems):
    """判两档的每一段。返回 (problems, stats)。"""
    stats = {}
    for name, _, language in SCENARIOS:
        text = dumps.get(name)
        if text is None:
            problems.append("档 `%s` 没有 dump" % name)
            continue
        sections, parse_problems = parse_sections(text)
        problems.extend("档 `%s`：%s" % (name, one) for one in parse_problems)
        app_name = app_name_of(sections)
        for section_id in SECTION_IDS:
            lines = sections.get(section_id)
            if lines is None:
                problems.append("档 `%s`：缺 `%s` 段（探针没展开菜单 / 格式变了 ⇒ 这一档判不了）"
                                % (name, section_id))
                continue
            one_problems, one_stats, _ = judge_section(section_id, lines, language, app_name)
            stats["%s/%s" % (name, section_id)] = one_stats
            problems.extend("档 `%s` 段 `%s`：%s" % (name, section_id, one) for one in one_problems)
    if len(dumps) != len(SCENARIOS):
        problems.append("两档没有都跑到（拿到 %d 档）" % len(dumps))
    # 条件族：单档缺 = 如实登记；**两档都没出现** = 判红（那种情况只可能是探针没展开 / 写法变了）。
    seen = {}
    notes = []
    for key, one in stats.items():
        for label, present in (one.get("coverage") or {}).items():
            seen[label] = seen.get(label, False) or present
        for note in (one.get("notes") or []):
            notes.append("%s · %s" % (key, note))
    for label, _, conditional in REQUIRED_OPEN_ITEMS:
        if conditional and not seen.get(label, False):
            # 探针**自报**没展开成 ⇒ 说清那是「探针没跑成」，别让它读起来像产品缺陷
            # （2026-10-03 实测：那种形态的报错长得像「中文界面下还有英文项」）。
            probes_failed = [name for name, text in dumps.items()
                             if (expansion_report(text) or "").startswith("missing")]
            hint = ("**探针没能展开菜单**（%s 自报 `missing=…`）⇒ 这一项这一档判不了；"
                    "已经在收集阶段重试三次，仍未展开成功 —— 先看探针，别先改产品" % " / ".join(probes_failed)) \
                if probes_failed else "（探针没展开菜单 / AppKit 改了写法）"
            problems.append("条件性必检项 `%s` 在这一轮两档**一次都没枚举到** ⇒ 判红%s" % (label, hint))
    stats["notes"] = notes
    return problems, stats


# ---------------------------------------------------------------- 真启动两档

def _defaults(*arguments):
    return subprocess.run(["defaults", *arguments], capture_output=True, text=True)


def expansion_report(dump_text):
    """读 dump 里探针**自报**的展开结论（`# openExpansion=…`）。

    返回 `None` = 这份 dump 没有这一行（旧包 / 合成 dump），调用方按「不知道」处理；
    返回 `ok …` = 展开了；返回 `missing=…` = 探针没能把条件族插进树里 —— **这一档的结论不可用**。
    """
    found = None
    for line in dump_text.splitlines():
        if line.startswith("# openExpansion="):
            found = line.split("=", 1)[1].strip()   # 取**最后**一条：A/B 段不带这行，C 段才是展开结论
    return found


def run_scenario(binary, launch_lang, switch_lang, target, timeout):
    """真启动一档，等 dump 落盘。返回 (ok, 说明)。"""
    environment = dict(os.environ)
    environment["DOYAH_MENU_DUMP"] = str(target)
    # 8 秒：切换语言（第 4 秒）之后留足自愈 + 展开菜单的时间（展开 9 个顶层菜单约 4 秒）。
    environment["DOYAH_MENU_DUMP_DELAY"] = "8"
    environment["DOYAH_MENU_DUMP_SWITCH"] = switch_lang
    # **必须展开菜单**：不展开，`显示` / `窗口` 里那批项根本不在树里（第一代判据的盲区）。
    environment["DOYAH_MENU_DUMP_OPEN"] = "1"
    if target.exists():
        target.unlink()
    process = subprocess.Popen(
        [str(binary), "-AppleLanguages", "(%s)" % launch_lang, "-app.language", launch_lang],
        env=environment,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        deadline = time.time() + timeout
        while time.time() < deadline:
            if target.exists() and target.stat().st_size > 0:
                time.sleep(0.5)   # 落盘可能还没写完（`write(atomically:)` 是换名，不会写一半）
                return True, ""
            if process.poll() is not None and not target.exists():
                return False, "进程提前退出（rc=%s）且没有写出 dump" % process.returncode
            time.sleep(0.5)
        return False, "等了 %d 秒没等到 dump" % timeout
    finally:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()


def collect(scratch, binary, timeout):
    """备份应用偏好 → 跑两档 → 还原。返回 ({档名: dump 文本}, problems)。"""
    backup = scratch / "prefs.plist"
    _defaults("export", DEFAULTS_DOMAIN, str(backup))
    dumps, problems = {}, []
    try:
        for name, launch, switch in SCENARIOS:
            target = scratch / ("%s.txt" % name)
            # 菜单跟踪是**偶发**不收敛的（实测 2026-10-02：同一份包一次 120 秒没写出 dump、下一次秒出；
            # 2026-10-03 又实测到第二形态：dump 出来了、但**菜单没展开成** —— 那一段里
            # `显示标签页栏` / `所有标签页` 一条都不在，`移动与调整大小` 的子菜单标题还停在启动语言，
            # 症状长得像「产品停在英文」。两种形态都**不是产品结论** ⇒ 分开重试、分开报。
            ok, why, text = False, "", ""
            for attempt in range(1, 4):
                ok, why = run_scenario(binary, launch, switch, target, timeout)
                if not ok:
                    continue
                text = target.read_text(encoding="utf-8")
                expansion = expansion_report(text)
                # 「这一档不可用」有两个可观测形态：探针**自报**没展开成；或展开族（那几个条件性项）
                # 在这份 dump 里**整条都不在** —— 后者是上一代包也能看出来的形态。
                # 条件族的判据认的是**选择器**（dump 里写的是 `toggleTabBar:` 这种），不是中文标题。
                family = [label[label.index("`") + 1:label.rindex("`")]
                          for label, _, conditional in REQUIRED_OPEN_ITEMS
                          if conditional and "`" in label]
                if expansion is None or expansion.startswith("ok"):
                    if not family or any(selector in text for selector in family):
                        break
                    why = "这一档的展开族（%s）在 dump 里一条都不在" % "、".join(family)
                else:
                    why = "探针没能展开菜单（自报 `%s`）" % expansion
                ok = False
            if not ok:
                problems.append("档 `%s` 没跑出可用的 dump（三次都没成）：%s" % (name, why))
                continue
            dumps[name] = text
    finally:
        if backup.exists():
            _defaults("import", DEFAULTS_DOMAIN, str(backup))
    return dumps, problems


# ---------------------------------------------------------------- 自检

def _rows_core():
    """A 段的最小真形状（与仓库里那份真 dump 同格式）。"""
    return [
        "0|UNRECOGNIZED|submenuAction:|Doyah Studio|submenuAction:|-|unknown submenu=Doyah Studio",
        "1|system|orderFrontStandardAboutPanel:|关于 Doyah Studio|menuSystemAbout|关于 Doyah Studio|ok",
        "0|title|submenuAction:|文件|menuSystemFile|文件|ok",
        "1|title|menuAction:|新建查询|menuNewQuery|新建查询|ok",
        "0|title|submenuAction:|编辑|menuSystemEdit|编辑|ok",
        "1|system|undo:|撤销|menuSystemUndo|撤销|ok",
        "1|title|submenuAction:|自动填充|menuSystemAutoFill|自动填充|ok",
        "0|title|submenuAction:|显示|menuSystemView|显示|ok",
        "1|title|menuAction:|工作区视图|menuViewWorkspace|工作区视图|ok",
        "0|title|submenuAction:|语言|menuLanguage|语言|ok",
        "1|UNRECOGNIZED|menuAction:|简体中文|menuAction:|-|unknown",
        "1|UNRECOGNIZED|menuAction:|English|menuAction:|-|unknown",
        "0|title|submenuAction:|窗口|menuSystemWindow|窗口|ok",
        "1|system|performMiniaturize:|最小化|menuSystemMinimize|最小化|ok",
        "1|system|performZoom:|缩放|menuSystemZoom|缩放|ok",
        "1|system|arrangeInFront:|全部置于顶层|menuSystemBringAllToFront|全部置于顶层|ok",
        "1|UNRECOGNIZED|makeKeyAndOrderFront:|Doyah Studio - 工作区|makeKeyAndOrderFront:|-|unknown",
        "0|title|submenuAction:|帮助|menuSystemHelp|帮助|ok",
        "1|system|toggleSidebar:|显示/隐藏边栏|menuSystemToggleSidebar|显示/隐藏边栏|ok",
    ]


def _rows_open():
    """**只有展开菜单才会出现**的那一族（C 段相对 A 段多出来的部分 = 本代判据的覆盖面）。"""
    return [
        "1|system|toggleTabBar:|显示标签页栏|menuSystemShowTabBar|显示标签页栏|ok",
        "1|system|toggleTabOverview:|显示所有标签页|menuSystemShowAllTabs|显示所有标签页|ok",
        "1|system|miniaturizeAll:|全部最小化|menuSystemMinimizeAll|全部最小化|ok",
        "1|system|zoomAll:|全部缩放|menuSystemZoomAll|全部缩放|ok",
        "1|system|_zoomFill:|填充|menuSystemFill|填充|ok",
        "1|system|_zoomCenter:|居中|menuSystemCenter|居中|ok",
        "1|system|submenuAction:|移动与调整大小|menuSystemMoveAndResize|移动与调整大小|ok submenu=移动与调整大小",
        "2|system|-|二等分|menuSystemHalves|二等分|ok",
        "2|system|_zoomLeft:|左侧|menuSystemZoomLeft|左侧|ok",
        "2|system|_zoomRight:|右侧|menuSystemZoomRight|右侧|ok",
        "2|system|_zoomTop:|顶部|menuSystemZoomTop|顶部|ok",
        "2|system|_zoomBottom:|底部|menuSystemZoomBottom|底部|ok",
        "2|system|_zoomUntile:|恢复上一个大小|menuSystemReturnToPreviousSize|恢复上一个大小|ok",
        "1|system|submenuAction:|全屏幕平铺|menuSystemFullScreenTile|全屏幕平铺|ok submenu=全屏幕平铺",
        "2|system|_tileLeft:|屏幕左侧|menuSystemTileLeft|屏幕左侧|ok",
        "2|system|_tileRight:|屏幕右侧|menuSystemTileRight|屏幕右侧|ok",
        "1|system|selectPreviousTab:|显示上一个标签页|menuSystemShowPreviousTab|显示上一个标签页|ok",
        "1|system|selectNextTab:|显示下一个标签页|menuSystemShowNextTab|显示下一个标签页|ok",
        "1|system|moveTabToNewWindow:|将标签页移到新窗口|menuSystemMoveTabToNewWindow|将标签页移到新窗口|ok",
        "1|system|mergeAllWindows:|合并所有窗口|menuSystemMergeAllWindows|合并所有窗口|ok",
    ]


def _section(section_id, headline, rows):
    return [SECTION_MARK + " — " + section_id + " " + headline] + rows


def synthetic_dump(mismatch=False, rogue=False, drop_help=False, short=False, bad_line=False, no_mark=False,
                   missing_open=False, submenu_abuse=False, english_in_chinese=False, chinese_in_english=False,
                   drop_c=False, stale_submenu=False, missing_tabs=False):
    """按真 dump 的形状造一份（绿路 = 三档齐全、展开族一条不少）。"""
    filler = [
        "1|title|menuAction:|外观…|menuAppearance|外观…|ok",
        "1|title|menuAction:|连接设置…|menuConnectionSettings|连接设置…|ok",
        "1|title|menuAction:|数据库统计|databaseStatsTitle|数据库统计|ok",
        "1|title|menuAction:|服务器级对象…|menuServerObjects|服务器级对象…|ok",
        "1|title|menuAction:|Schema 对比与同步|schemaDiffTitle|Schema 对比与同步|ok",
        "1|title|menuAction:|ER 图…|menuERDiagram|ER 图…|ok",
    ]
    list_a = _rows_core() + filler * 12
    list_c = list_a + _rows_open()
    if mismatch:
        list_a[2] = "0|title|submenuAction:|File|menuSystemFile|文件|MISMATCH"
        list_c[2] = list_a[2]
    if english_in_chinese:
        # 本判据「表外兜底」那一半：表里**也**写错了（target == title，①判不出来）时，
        # 语言一致性必须抓到它（中文界面上一条没有汉字的项）。
        list_a.append("1|system|someNewAction:|Undo|menuSystemUndo|Undo|ok")
        list_c.append(list_a[-1])
    if chinese_in_english:
        list_a.append("1|system|someNewAction:|文档设置|someNewAction:|文档设置|ok")
        list_c.append(list_a[-1])
    if rogue:
        list_a.append("0|UNRECOGNIZED|someNewSystemItem:|Something|someNewSystemItem:|-|unknown")
        list_c.append(list_a[-1])
    if submenu_abuse:
        list_a.append("1|UNRECOGNIZED|submenuAction:|Something Else|submenuAction:|-|unknown")
        list_c.append(list_a[-1])
    if drop_help:
        list_a = [row for row in list_a if "menuSystemHelp" not in row]
        list_c = [row for row in list_c if "menuSystemHelp" not in row]
    if missing_tabs:
        # 条件族缺项：`显示` 菜单里那两条随窗口标签页状态浮动（实测同一份代码两次真启动一有一无）。
        list_c = [row for row in list_c if "toggleTabBar:" not in row and "toggleTabOverview:" not in row]
    if stale_submenu:
        # 2026-10-02 实测那一条：`移动与调整大小` 的 **item 标题**已经是中文、**子菜单自己的标题**
        # 还停在启动语言（真 dump 里就是 `… |ok submenu=Move & Resize`）。
        list_c = [row.replace("submenu=移动与调整大小", "submenu=Move & Resize") for row in list_c]
    if missing_open:
        list_c = [row for row in list_c if "_zoomFill:" not in row and "_zoomCenter:" not in row]
    if short:
        list_a = list_a[:3]
        list_c = list_c[:3]
    rows = _section("A", "原样（未展开菜单）", list_a)
    if not drop_c:
        rows += _section("C", "各菜单展开过一次之后（含 AppKit 展开时才插进来的项）", list_c)
    rows += _section("B", "展开菜单时那条自愈路之后", list_c)
    text = "\n".join(rows) + "\n# 尾注\n"
    if no_mark:
        text = "\n".join(row for row in rows if not row.startswith(SECTION_MARK)) + "\n"
    if bad_line:
        text = text.replace("\n# 尾注\n", "\n这不是一行合法的 dump\n# 尾注\n")
    return text


# 合成 dump 的英文字面（只为造「英文方向」的绿路 / 红路；真方向的证据是真启动那两档）。
_EN = {
    "Doyah Studio": "Doyah Studio",
    "关于 Doyah Studio": "About Doyah Studio",
    "文件": "File", "新建查询": "New Query", "编辑": "Edit", "撤销": "Undo", "自动填充": "AutoFill",
    "显示": "View", "工作区视图": "Workspace View", "语言": "Language", "窗口": "Window",
    "最小化": "Minimize", "缩放": "Zoom", "全部置于顶层": "Bring All to Front", "帮助": "Help",
    "显示/隐藏边栏": "Toggle Sidebar", "Doyah Studio - 工作区": "Doyah Studio - 工作区",
    "显示标签页栏": "Show Tab Bar", "显示所有标签页": "Show All Tabs", "全部最小化": "Minimize All",
    "全部缩放": "Zoom All", "填充": "Fill", "居中": "Center", "移动与调整大小": "Move & Resize",
    "二等分": "Halves", "左侧": "Left", "右侧": "Right", "顶部": "Top", "底部": "Bottom",
    "恢复上一个大小": "Return to Previous Size", "全屏幕平铺": "Full Screen Tile",
    "屏幕左侧": "Left of Screen", "屏幕右侧": "Right of Screen", "显示上一个标签页": "Show Previous Tab",
    "显示下一个标签页": "Show Next Tab", "将标签页移到新窗口": "Move Tab to New Window",
    "合并所有窗口": "Merge All Windows", "外观…": "Appearance…", "连接设置…": "Connection Settings…",
    "数据库统计": "Database statistics", "服务器级对象…": "Server-level Objects…",
    "Schema 对比与同步": "Schema diff and sync", "ER 图…": "ER Diagram…",
}


def to_english(text):
    """把合成 dump 的标题 / 目标语言两格换成英文写法（造英文方向的红绿路用）。"""
    out = []
    for line in text.splitlines():
        if line.startswith("#") or not line.strip() or "|" not in line:
            out.append(line)
            continue
        parts = line.split("|")
        if len(parts) >= 7:
            parts[3] = _EN.get(parts[3], parts[3])
            if parts[5] != "-":
                parts[5] = _EN.get(parts[5], parts[5])
            # 子菜单自己的标题拼在最后一列（`ok submenu=…`）—— 它也是要判的文案。
            if " submenu=" in parts[6]:
                head, tail = parts[6].split(" submenu=", 1)
                parts[6] = head + " submenu=" + _EN.get(tail, tail)
        out.append("|".join(parts))
    return "\n".join(out) + "\n"


def judge_one_dump(text, language):
    """判一份 dump（自检用：绕开两档那层）。"""
    problems = []
    sections, parse_problems = parse_sections(text)
    problems.extend(parse_problems)
    app_name = app_name_of(sections)
    for section_id in SECTION_IDS:
        lines = sections.get(section_id)
        if lines is None:
            problems.append("缺 `%s` 段" % section_id)
            continue
        one, _, _ = judge_section(section_id, lines, language, app_name)
        problems.extend(one)
    return problems


def self_test() -> int:
    print("== 判据自检（合成 dump，不启动应用）")
    cases = []

    def case(name, text, language, expect_red, needles=()):
        problems = judge_one_dump(text, language)
        ok = (not problems) if not expect_red else bool(problems)
        if expect_red and needles:
            joined = " / ".join(problems)
            ok = ok and all(needle in joined for needle in needles)
        cases.append((name, ok, problems))

    case("① 绿：合成 dump（A/C/B 三档齐全 · 展开族一条不少 · 中文方向）", synthetic_dump(), "zh-Hans", False)
    case("② 绿：同一份的英文方向（英文界面下不许有汉字）", to_english(synthetic_dump()), "en", False)
    case("③ 红：一项停在启动语言（File 应为 文件）", synthetic_dump(mismatch=True), "zh-Hans", True,
         ["停在启动语言"])
    case("④ 红：认不出且没登记（= 会停在启动语言）", synthetic_dump(rogue=True), "zh-Hans", True,
         ["未覆盖项"])
    case("⑤ 红：`submenuAction:` 的豁免被滥用（标题 ≠ 应用显示名）", synthetic_dump(submenu_abuse=True),
         "zh-Hans", True, ["未覆盖项"])
    case("⑥ 红：系统菜单顶层标题缺一个（Help）", synthetic_dump(drop_help=True), "zh-Hans", True,
         ["系统菜单顶层标题不在场"])
    case("⑦ 红：条目数不够（空跑防护）", synthetic_dump(short=True), "zh-Hans", True, ["空跑防护"])
    case("⑧ 红：展开族缺项（枚举不到 ⇒ 未覆盖，不许默认通过）", synthetic_dump(missing_open=True),
         "zh-Hans", True, ["未覆盖：必检项"])
    case("⑨ 红：缺 C 段（探针没展开菜单 ⇒ 这一档判不了）", synthetic_dump(drop_c=True), "zh-Hans", True,
         ["缺 `C` 段"])
    case("⑩ 红：坏行（解析形状）", synthetic_dump(bad_line=True), "zh-Hans", True, ["坏行"])
    case("⑪ 红：没有段标（探针没写出来 / 格式变了）", synthetic_dump(no_mark=True), "zh-Hans", True,
         ["找不到段标"])
    case("⑫ 红：中文方向 —— 表里**也**写错（target == title）时靠语言一致性抓到",
         synthetic_dump(english_in_chinese=True), "zh-Hans", True, ["没有汉字"])
    case("⑬ 红：英文方向 —— 一项含汉字", to_english(synthetic_dump(chinese_in_english=True)), "en", True,
         ["含汉字"])
    case("⑭ 红：只改一个字节（File → 应得 文件）就该判红", synthetic_dump().replace(
        "0|title|submenuAction:|文件|menuSystemFile|文件|ok",
        "0|title|submenuAction:|File|menuSystemFile|文件|ok"), "zh-Hans", True, ["停在启动语言"])
    if FIXTURE_DUMP.exists():
        case("⑮ 绿对照：仓库里留档的**修后**真 dump（2026-10-03 那份 · 含展开族与探针自报）",
             FIXTURE_DUMP.read_text(encoding="utf-8"), "zh-Hans", False)
    else:
        cases.append(("⑮ 绿对照：修后真 dump 留档", False, ["留档文件不存在：%s" % FIXTURE_DUMP]))
    # 历史留档（第 140 轮那份，**没有** C 段与展开族）：本代判据必须判它红 ——
    # 它证明的是「第一代判据为什么放过了这一层」，不是绿对照。
    if LEGACY_FIXTURE.exists():
        case("⑯ 红对照：第 140 轮那份留档 dump（无 C 段 / 无展开族）在本代必须判红",
             LEGACY_FIXTURE.read_text(encoding="utf-8"), "zh-Hans", True, ["缺 `C` 段"])
    else:
        cases.append(("⑯ 红对照：第 140 轮留档 dump", False, ["留档文件不存在：%s" % LEGACY_FIXTURE]))
    case("⑰ 红：子菜单**自己的标题**停在启动语言（item 标题已对 ⇒ 只看 item 抓不到）",
         synthetic_dump(stale_submenu=True), "zh-Hans", True, ["子菜单自己的标题"])

    def all_case(name, dumps, expect_red, needle_problems=(), needle_notes=()):
        problems, stats = judge_all(dict(dumps), [])
        ok = (not problems) if not expect_red else bool(problems)
        if expect_red and needle_problems:
            ok = ok and all(needle in " / ".join(problems) for needle in needle_problems)
        if needle_notes:
            ok = ok and all(needle in " / ".join(stats.get("notes") or []) for needle in needle_notes)
        cases.append((name, ok, problems + (stats.get("notes") or [])))

    # 条件族（标签页栏那一族随窗口状态浮动）在 `judge_all` 那一层判：单档缺 = 如实登记，
    # 两档都没出现 = 判红。用合成 dump 造这两条路。
    all_case("⑱ 绿（如实登记）：条件族只有一档枚举到 —— 缺的那档报「未覆盖」，**不判红**",
             {"switch-en-to-zh": synthetic_dump(missing_tabs=True),
              "switch-zh-to-en": to_english(synthetic_dump())},
             False, needle_notes=("未覆盖（如实登记",))
    all_case("⑲ 红：条件族两档**一次都没枚举到** ⇒ 判红（探针没展开 / AppKit 改了写法）",
             {"switch-en-to-zh": synthetic_dump(missing_tabs=True),
              "switch-zh-to-en": to_english(synthetic_dump(missing_tabs=True))},
             True, needle_problems=("一次都没枚举到",))

    failed = [name for name, ok, _ in cases if not ok]
    for name, ok, problems in cases:
        print("  %s %s" % ("✅" if ok else "❌", name))
        for problem in problems:
            print("      · %s" % problem)
    print("自检 %d 例：%d 通过 / %d 失败" % (len(cases), len(cases) - len(failed), len(failed)))
    return 1 if failed else 0


# ---------------------------------------------------------------- main

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true", help="机器读输出")
    parser.add_argument("--self-test", action="store_true", dest="self_test", help="判据自己的证据")
    parser.add_argument("--dump-dir", dest="dump_dir", default=None, help="只判已有 dump（离线复核 / 红绿对照）")
    parser.add_argument("--app", dest="app", default=None,
                        help="待判的可执行文件（默认 `dist/DoyahStudio.app`；红绿对照时指旧包）")
    parser.add_argument("--timeout", type=int, default=120, help="每档等待 dump 的秒数")
    parser.add_argument("--keep-dumps", dest="keep_dumps", default=None,
                        help="把这一轮的真 dump 留档到这个目录（刷新 fixtures / 红绿对照用）")
    arguments = parser.parse_args()

    if arguments.self_test:
        return self_test()

    binary = pathlib.Path(arguments.app) if arguments.app else DEFAULT_APP
    scratch = pathlib.Path(tempfile.mkdtemp(prefix="doyah-menu-dump-"))
    try:
        if arguments.dump_dir:
            dumps = {}
            for name, _, _ in SCENARIOS:
                candidate = pathlib.Path(arguments.dump_dir) / ("%s.txt" % name)
                if candidate.exists():
                    dumps[name] = candidate.read_text(encoding="utf-8")
            problems, stats = judge_all(dumps, [])
        else:
            if not binary.exists():
                print("❌ 没有可执行文件：%s（先 `./Scripts/build-app.sh`）" % binary)
                return 1
            print("== 真启动两档（约 20 秒一档；每档把 9 个顶层菜单展开一次再 dump）")
            dumps, problems = collect(scratch, binary, arguments.timeout)
            problems, stats = judge_all(dumps, problems)
            # 留档这一轮的真 dump（刷 fixtures / 红绿对照用；判据自己不读它，只写）。
            if arguments.keep_dumps:
                keep = pathlib.Path(arguments.keep_dumps)
                keep.mkdir(parents=True, exist_ok=True)
                for name, text in dumps.items():
                    (keep / ("%s.txt" % name)).write_text(text, encoding="utf-8")
                print("== 真 dump 已留档到 %s" % keep)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)

    if arguments.json:
        print(json.dumps({"problems": problems, "stats": stats}, ensure_ascii=False, indent=2))
    else:
        for name, _, language in SCENARIOS:
            print("  %s（→ %s）" % (name, language))
            for section_id in SECTION_IDS:
                one = stats.get("%s/%s" % (name, section_id))
                print("      %s：%s" % (section_id, "（没有这一段）" if not one else
                      "条目 %d / 识别 %d / 认不出 %d / 停启动语言 %d / 未覆盖 %d"
                      % (one["items"], one["recognized"], one["unrecognized"],
                         one["mismatch"], one["uncovered"])))
        notes = stats.get("notes") or []
        if notes:
            print("  ⚠️ 如实登记（不判红，但也**不算通过**）：")
            for note in notes:
                print("      · %s" % note)
        if problems:
            print("❌ 菜单栏这一层没过（%d 条）：" % len(problems))
            for problem in problems:
                print("   · %s" % problem)
        else:
            print("✅ 两档三段的每一项都跟当前界面语言同语；认不出的项都在豁免里；展开族一条不少")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
