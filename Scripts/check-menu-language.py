#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""门禁：**菜单栏（AppKit 那一层）在换语言后不许停在启动语言**（队列 `L-145` 判据 · 内测清单 **丙2**）。

由头 = 需求提出者 2026-09-30 内测原话：「语言设置为英文时菜单 Edit/View/Window 里有中文」，
之后**症状反转**：「中文菜单里有 2 个英文菜单」—— 同一个 bug 的两个方向。

**为什么既有的本地化判据一条都没拦到它**（这正是本条要补的覆盖面缺口）：
`check-core-localization.py` / `check-effective-language.py` / `check-literal-language.py` 扫的都是
**源码/文案表**，而菜单栏的文案是 `NSMenuItem.title` —— **运行期值**：界面快照拍不到它
（菜单不在任何视图里）、单测只验表本身。于是「键都登记了、表也齐全、门禁全绿，菜单栏却是英文」。

判据跑 **两档真启动**（各自最坏的那一面），判的是 `DOYAH_MENU_DUMP` 写出来的**A 段**
（= 还没点开任何菜单时 `NSApp.mainMenu` 的原样 —— 用户看见菜单栏的那一刻就是这个状态）：

    ① 启动英文 → 用真实入口切成中文（`LocalizationManager.setLanguage`）
    ② 启动中文 → 切成英文

每一档要求：
    A **没有任何菜单项停在启动语言** —— dump 里的 `MISMATCH` 必须为 0（这是本判据的主断言）；
    B **认不出的项只在白名单里** —— `MainMenuLocalizer` 认不出的项它一个字节都不改，
      所以「认不出」本身就是「会停在启动语言」的同义词；白名单只有三类（逐条写理由）：
      应用菜单名（专有名词）/ 语言自身的显示名 / 窗口列表项（标题是窗口标题）；
    C **空跑防护** —— 两档 dump 各自：条目数下限、五个系统菜单顶层标题必须在场、
      被识别出来的项数下限 —— 防「dump 没写出来 / 菜单树是空的」也算过；
    D **解析形状** —— 每一行必须是 `DOYAH-MENU-DUMP v1` 的形状，坏行判红（防解析静默失效）。

用法：
    python3 Scripts/check-menu-language.py             # 真启动两档 + 判（需要先构建 .app）
    python3 Scripts/check-menu-language.py --json      # 机器读
    python3 Scripts/check-menu-language.py --self-test # 判据自己的证据（合成 dump，不启动应用）
    python3 Scripts/check-menu-language.py --dump-dir <目录>   # 只判已有 dump（离线复核）

判据自己的证据：`--self-test` **10 例** —— 绿路（合成 + 仓库里留档的一份真 dump）、
六条红路（停启动语言 / 认不出的项没登记 / 缺系统菜单 / 条目数不够 / 坏行 / 段标缺失）、
两条反面对照（同一条 dump 改一个字节就判红、白名单外多一项就判红）。

**边界（如实登记）**：这条判据**不判**「服务子菜单里别的应用提供的项」——
那类项由系统在用时创建、跟的是**系统语言**（口径写在 `NFR-I18N-03`，非本判据范围）。
"""

from __future__ import annotations  # macOS 自带 python3 是 3.9

import argparse
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time

BASE = pathlib.Path(__file__).resolve().parent.parent
APP_BINARY = BASE / "dist" / "DoyahStudio.app" / "Contents" / "MacOS" / "DoyahStudio"
DEFAULTS_DOMAIN = "studio.doyah.DoyahStudio"
FIXTURE_DUMP = BASE / "Scripts" / "fixtures" / "menu-dump-real-20261001.txt"

SECTION_MARK = "# DOYAH-MENU-DUMP v1"

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

# 「认不出」的白名单：认不出 ⇒ `MainMenuLocalizer` 不碰它 ⇒ 它会停在启动语言。
# 这三类**本来就该**认不出（逐条写理由），多出一类就是真缺口。
UNRECOGNIZED_ALLOWED = {
    # ① 应用菜单的标题 = 应用显示名（`CFBundleName`），是**专有名词**，两种语言都一样。
    "submenuAction:",
    # ② 语言自身的显示名（`简体中文` / `English`）—— 每种语言用自己的写法，**故意**不跟当前语言走。
    "menuAction:",
    # ③ 窗口列表项：标题就是窗口标题，随活动栏走（`Doyah Studio - 工作区`），不是菜单文案。
    "makeKeyAndOrderFront:",
}

# 空跑防护下限（实测两档：条目 82 / 识别项 78）
FLOOR_LINES = 60
FLOOR_RECOGNIZED = 50


class Line:
    __slots__ = ("depth", "kind", "selector", "title", "key", "target", "verdict", "submenu")

    def __init__(self, depth: int, kind: str, selector: str, title: str, key: str, target: str, verdict: str):
        self.depth = depth
        self.kind = kind
        self.selector = selector
        self.title = title
        self.key = key
        self.target = target
        self.verdict = verdict


def parse_section_a(text: str):
    """取出 **A 段**（未展开菜单的原样）并逐行解析。返回 (header_lines, items, problems)。"""
    problems = []
    lines = text.splitlines()
    start = None
    for index, line in enumerate(lines):
        if line.startswith(SECTION_MARK):
            start = index
            break
    if start is None:
        return [], [], ["dump 里找不到段标 `%s`（探针没写出来 / 格式变了）" % SECTION_MARK]
    header = []
    items = []
    for line in lines[start:]:
        if line.startswith(SECTION_MARK):
            header.append(line)
            continue
        if line.startswith("# "):
            if items:
                break  # 尾注（统计行）—— 段落结束
            header.append(line)
            continue
        parts = line.split("|")
        if len(parts) < 7:
            problems.append("坏行（段数 %d < 7）：%s" % (len(parts), line))
            continue
        depth, kind, selector, title, key, target, verdict = parts[:7]
        try:
            depth_value = int(depth)
        except ValueError:
            problems.append("坏行（深度不是数字）：%s" % line)
            continue
        items.append(Line(depth_value, kind, selector, title, key, target, verdict))
    if not items:
        problems.append("A 段里一条菜单项都没有")
    return header, items, problems


def judge_one(name: str, text: str):
    """判一档 dump。返回 (problems, stats)。"""
    problems = []
    header, items, parse_problems = parse_section_a(text)
    problems.extend(parse_problems)
    stats = {"items": len(items), "recognized": 0, "unrecognized": 0, "mismatch": 0}

    keys_present = set()
    for item in items:
        if item.kind == "separator":
            continue
        # **不信 dump 自述**：`MISMATCH` 这个结论由判据自己算（`目标语言 ≠ 现标题`），
        # 自述与实测不一致也要判红（否则改坏 dump 就能把红的说成绿的）。
        self_reported = item.verdict.startswith("MISMATCH")
        really_mismatched = item.target != "-" and item.target != item.title
        if really_mismatched:
            stats["mismatch"] += 1
            problems.append("停在启动语言：`%s`（应得 `%s` / 键 `%s`）" % (item.title, item.target, item.key))
        elif self_reported:
            problems.append("dump 自述与实测不符（自述 MISMATCH，实测一致）：`%s`" % item.title)
        if item.kind == "UNRECOGNIZED":
            stats["unrecognized"] += 1
            if item.selector not in UNRECOGNIZED_ALLOWED:
                problems.append(
                    "认不出的项没登记（意味着它会停在启动语言）：`%s` selector=`%s`"
                    % (item.title, item.selector)
                )
        else:
            stats["recognized"] += 1
            keys_present.add(item.key)

    missing = [key for key in SYSTEM_TOP_LEVEL_KEYS if key not in keys_present]
    if missing:
        problems.append("系统菜单顶层标题不在场：%s（菜单树没建成 ⇒ 这一档不算过）" % " / ".join(missing))
    if stats["items"] < FLOOR_LINES:
        problems.append("空跑防护：条目数 %d < 下限 %d" % (stats["items"], FLOOR_LINES))
    if stats["recognized"] < FLOOR_RECOGNIZED:
        problems.append("空跑防护：识别出来的项 %d < 下限 %d" % (stats["recognized"], FLOOR_RECOGNIZED))
    return problems, stats


# ---------------------------------------------------------------- 真启动两档

def _defaults(*arguments):
    return subprocess.run(["defaults", *arguments], capture_output=True, text=True)


def run_scenario(binary: pathlib.Path, launch_lang: str, switch_lang: str, target: pathlib.Path, timeout: int):
    """真启动一档，等 dump 落盘。返回 (ok, 说明)。"""
    environment = dict(os.environ)
    environment["DOYAH_MENU_DUMP"] = str(target)
    environment["DOYAH_MENU_DUMP_DELAY"] = "6"
    environment["DOYAH_MENU_DUMP_SWITCH"] = switch_lang
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


def collect(scratch: pathlib.Path, timeout: int):
    """备份应用偏好 → 跑两档 → 还原。返回 {档名: dump 文本}。"""
    backup = scratch / "prefs.plist"
    _defaults("export", DEFAULTS_DOMAIN, str(backup))
    dumps = {}
    problems = []
    try:
        for name, launch, switch in SCENARIOS:
            target = scratch / ("%s.txt" % name)
            ok, why = run_scenario(APP_BINARY, launch, switch, target, timeout)
            if not ok:
                problems.append("档 `%s` 没跑出 dump：%s" % (name, why))
                continue
            dumps[name] = target.read_text(encoding="utf-8")
    finally:
        if backup.exists():
            _defaults("import", DEFAULTS_DOMAIN, str(backup))
    return dumps, problems


# ---------------------------------------------------------------- 自检

def synthetic_dump(mismatch: bool = False, rogue_unrecognized: bool = False, drop_help: bool = False,
                   short: bool = False, bad_line: bool = False, no_mark: bool = False) -> str:
    """按真 dump 的形状造一份（绿路 = 与真仓库那份等价的最小集）。"""
    rows = [
        "0|UNRECOGNIZED|submenuAction:|Doyah Studio|submenuAction:|-|unknown",
        "1|system|orderFrontStandardAboutPanel:|关于 Doyah Studio|menuSystemAbout|关于 Doyah Studio|ok",
        "0|title|submenuAction:|文件|menuSystemFile|文件|ok",
        "1|title|menuAction:|新建查询|menuNewQuery|新建查询|ok",
        "0|title|submenuAction:|编辑|menuSystemEdit|编辑|ok",
        "1|system|undo:|撤销|menuSystemUndo|撤销|ok",
        "0|title|submenuAction:|显示|menuSystemView|显示|ok",
        "1|title|menuAction:|工作区视图|menuViewWorkspace|工作区视图|ok",
        "0|title|submenuAction:|语言|menuLanguage|语言|ok",
        "1|UNRECOGNIZED|menuAction:|简体中文|menuAction:|-|unknown",
        "1|UNRECOGNIZED|menuAction:|English|menuAction:|-|unknown",
        "0|title|submenuAction:|窗口|menuSystemWindow|窗口|ok",
        "1|UNRECOGNIZED|makeKeyAndOrderFront:|Doyah Studio - 工作区|makeKeyAndOrderFront:|-|unknown",
        "0|title|submenuAction:|帮助|menuSystemHelp|帮助|ok",
    ]
    if mismatch:
        rows[2] = "0|title|submenuAction:|File|menuSystemFile|文件|MISMATCH"
    if rogue_unrecognized:
        rows.append("0|UNRECOGNIZED|someNewSystemItem:|Something|someNewSystemItem:|-|unknown")
    if drop_help:
        rows = [row for row in rows if "menuSystemHelp" not in row]
    if bad_line:
        rows.append("这不是一行合法的 dump")
    if no_mark:
        return "\n".join(rows) + "\n"
    header = (
        SECTION_MARK + " — A 原样（未展开菜单）\n"
        "# lang=zh-Hans appKitLaunchLocalizations=en appleLanguages=en\n"
    )
    # 条目数下限靠重复一份「自有菜单项」凑到 FLOOR_LINES 之上（形状与真 dump 一致）；
    # 要造「条目数不够」的红例时在补齐**之后**再截断（顺序反了就造不出那个红例 —— 自检当场抓到过）。
    filler = [
        "1|title|menuAction:|外观…|menuAppearance|外观…|ok",
        "1|title|menuAction:|连接设置…|menuConnectionSettings|连接设置…|ok",
        "1|title|menuAction:|数据库统计|databaseStatsTitle|数据库统计|ok",
        "1|title|menuAction:|服务器级对象…|menuServerObjects|服务器级对象…|ok",
        "1|title|menuAction:|Schema 对比与同步|schemaDiffTitle|Schema 对比与同步|ok",
        "1|title|menuAction:|ER 图…|menuERDiagram|ER 图…|ok",
    ]
    while len(rows) < FLOOR_LINES + 2:
        rows.extend(filler)
    if short:
        rows = rows[:3]
    return header + "\n".join(rows) + "\n# 尾注\n"


def self_test() -> int:
    print("== 判据自检（合成 dump，不启动应用）")
    cases = []

    def case(name, text, expect_red, needles=()):
        problems, stats = judge_one("case", text)
        ok = (not problems) if not expect_red else bool(problems)
        if expect_red and needles:
            joined = " / ".join(problems)
            ok = ok and all(needle in joined for needle in needles)
        cases.append((name, ok, problems))

    case("① 绿：合成 dump（认不出的三项都在白名单里）", synthetic_dump(), False)
    case("② 红：有一项停在启动语言（File 应为 文件）", synthetic_dump(mismatch=True), True,
         ["停在启动语言"])
    case("③ 红：认不出且没登记的 selector（= 会停在启动语言）", synthetic_dump(rogue_unrecognized=True), True,
         ["认不出的项没登记"])
    case("④ 红：系统菜单顶层标题缺一个（Help）", synthetic_dump(drop_help=True), True,
         ["系统菜单顶层标题不在场"])
    case("⑤ 红：条目数不够（空跑防护）", synthetic_dump(short=True), True, ["空跑防护"])
    case("⑥ 红：坏行（解析形状）", synthetic_dump(bad_line=True), True, ["坏行"])
    case("⑦ 红：没有段标（探针没写出来 / 格式变了）", synthetic_dump(no_mark=True), True, ["找不到段标"])
    case("⑧ 红：只改一个字节（File → 应得 文件）就该判红", synthetic_dump().replace(
        "0|title|submenuAction:|文件|menuSystemFile|文件|ok",
        "0|title|submenuAction:|File|menuSystemFile|文件|ok"), True, ["停在启动语言"])
    if FIXTURE_DUMP.exists():
        case("⑨ 绿对照：仓库里留档的那份真 dump（第 140 轮实测）",
             FIXTURE_DUMP.read_text(encoding="utf-8"), False)
    else:
        cases.append(("⑨ 绿对照：真 dump 留档", False, ["留档文件不存在：%s" % FIXTURE_DUMP]))
    case("⑩ 红：真 dump 的形状 + 白名单外多一项", synthetic_dump(rogue_unrecognized=True), True,
         ["认不出的项没登记"])

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
    parser.add_argument("--dump-dir", dest="dump_dir", default=None, help="只判已有 dump（离线复核）")
    parser.add_argument("--timeout", type=int, default=60, help="每档等待 dump 的秒数")
    arguments = parser.parse_args()

    if arguments.self_test:
        return self_test()

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
            if not APP_BINARY.exists():
                print("❌ 没有可执行的应用包：%s（先 `./Scripts/build-app.sh`）" % APP_BINARY)
                return 1
            print("== 真启动两档（各约 10 秒）")
            dumps, problems = collect(scratch, arguments.timeout)
            problems, stats = judge_all(dumps, problems)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)

    if arguments.json:
        print(json.dumps({"problems": problems, "stats": stats}, ensure_ascii=False, indent=2))
    else:
        for name, _, _ in SCENARIOS:
            one = stats.get(name)
            print("  %s：%s" % (name, "（没有 dump）" if not one else
                                "条目 %d / 识别 %d / 认不出 %d / 停启动语言 %d"
                                % (one["items"], one["recognized"], one["unrecognized"], one["mismatch"])))
        if problems:
            print("❌ 菜单栏这一层没过（%d 条）：" % len(problems))
            for problem in problems:
                print("   · %s" % problem)
        else:
            print("✅ 两档都：菜单栏没有一项停在启动语言；认不出的项都在白名单（应用名 / 语言显示名 / 窗口标题）")
    return 1 if problems else 0


def judge_all(dumps, problems):
    stats = {}
    for name, _, _ in SCENARIOS:
        text = dumps.get(name)
        if text is None:
            problems.append("档 `%s` 没有 dump" % name)
            continue
        one_problems, one_stats = judge_one(name, text)
        stats[name] = one_stats
        problems.extend("档 `%s`：%s" % (name, problem) for problem in one_problems)
    if len(dumps) != len(SCENARIOS):
        problems.append("两档没有都跑到（拿到 %d 档）" % len(dumps))
    return problems, stats


if __name__ == "__main__":
    sys.exit(main())
