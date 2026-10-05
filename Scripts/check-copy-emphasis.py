#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""**「文案即所见」的机械门禁**（队列 L-19）：语言表里不许有 markdown 强调标记，渲染口径只剩纯文本。

守的是什么 —— 第 13 轮读图抓到的真缺陷（`routine-candidates-empty-zh` 上
`**四条判据全满足**才列进候选` 星号**肉眼可见**）：

  · 第 13 轮登记：语言表里带 `**` 的中文槽位 **17 个**（其中 `backupRestoreCommandPreview`
    的 `***` 是**密码掩码**、有意）；
  · 同一批键在不同渲染点走**两种口径** —— `RowDetailPanel.swift` 是
    `Text(LocalizedStringKey(L(...)))`（markdown 生效，**故意**），`RoutineCandidatesPanel.swift`
    是 `Text(L(...))`（`Text(String)` **不解析** markdown ⇒ 星号原样露出）。

**口径为什么定 ②「把标记从文案里去掉」而不是 ①「一律走 markdown」**（第 43 轮取证后拍板）：

  · 17 个键里有 **4 个**（`routineCandidatesHint` 之外还有 `lowerPaneProblemSkipped` /
    `backupRestoreStopped` / `backupRestoreTargetDatabaseHint`）的文案会流进
    **根本没有 markdown 这条路的通道** —— `statusMessage`（`String`，状态栏那一行）、
    `backupRestoreLog`（`[String]`，日志逐行），以及 `Label(L(...), systemImage:)`
    的 `String` 重载；在这些地方 markdown **结构上永远不会生效**；
  · `routineCandidatesHint` **一个键同时被两条路用**（面板里 `Text` + `statusMessage` 拼接）
    ⇒ 选 ① 也修不掉它，只会把「同一个键两处不一样」留在产品里（正是 L-19 要消灭的那类不一致）；
  · 英文侧 17 个键里只有 **4 个**带 `**` —— 中英两份文案本来就不在同一个口径上。
  ⇒ 唯一能覆盖**全部**渲染点的口径是「文案里不写标记」。代价（丢掉粗体强调）如实记在开发记录里。

判据（**双向棘轮**，例外只能靠写明理由留在台账里，不能靠改判据）：

  A 文案层：语言表（`platform/macos/Core/Localization.swift` 的 `LocalizedStrings.table`）每个条目的
    **两种语言**槽位都不许含 `**`（marker 例外键除外）；
  B 渲染层：产品源文件（`platform/macos/App/` `platform/macos/Core/` `platform/macos/CLI/` `Platform/`）里不许再出现 `LocalizedStringKey`
    （口径只剩纯文本一种；例外按文件登记 + 反向对账）；
  C 防静默：解析出的语言表条目数不得低于下限（正则失配、表被掏空 ⇒ 当场报红，而不是「零命中 = 通过」）；
  D 例外两端对账：marker 例外键必须在表里且**仍含**登记的标记形态（`***`）、必须写明理由；
    renderer 例外文件必须存在且**仍在使用** `LocalizedStringKey`（否则陈旧）；例外表不许有没理由的条目；
  E 接线：本门禁与它的负例必须在 `Scripts/verify-all.sh`（闭环第 3 项）里被真的跑到。

跑法：

    python3 Scripts/check-copy-emphasis.py              # 每轮跑（verify-all.sh 第 3 项）
    python3 Scripts/test-copy-emphasis-gate.py          # 负例（只在临时副本上写坏，不碰仓库）

退出码：0 = 全过；1 = 有判据不成立（打印文件 / 行号 / 键名 / 原因）；2 = 环境不对（找不到语言表 / 台账）。
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent

TABLE_FILE = "platform/macos/Core/Localization.swift"
EXEMPTIONS = "Scripts/copy-emphasis-exemptions.json"
VERIFY_ALL = "Scripts/verify-all.sh"
GATE_COMMAND = "python3 Scripts/check-copy-emphasis.py"
SELF_TEST_COMMAND = "python3 Scripts/test-copy-emphasis-gate.py"

# 判据 B 扫哪儿：产品源文件（测试与脚本不在内 —— 测试里出现的是断言字符串，不是界面渲染点）。
RENDER_DIRS = ("platform/macos/App", "platform/macos/Core", "platform/macos/CLI", "platform/macos/Platform")

# 判据 A 的标记：markdown 强调用的一对星号。
MARKER = "**"

# 判据 C 的下限：本轮实测语言表条目 **1591** 条；取 1500 留余量（低于此值先怀疑正则失配，而不是"表变小了"）。
MIN_TABLE_ENTRIES = 1500

ENTRY = re.compile(
    r'^\s*\.(?P<key>[A-Za-z0-9_]+):\s*\[(?P<body>\.simplifiedChinese:\s*"(?P<zh>.*?)",\s*'
    r'\.english:\s*"(?P<en>.*?)")\]\s*,?\s*$',
    re.M | re.S,
)


def read_entries(root: pathlib.Path):
    """解析语言表 → [(键, 行号, zh, en)]。行号按条目起始行计，报错时能直接点过去。"""
    table = root / TABLE_FILE
    if not table.exists():
        return None, f"找不到语言表 {TABLE_FILE}"
    text = table.read_text(encoding="utf-8")
    entries = []
    for match in ENTRY.finditer(text):
        line = text.count("\n", 0, match.start()) + 1
        entries.append((match.group("key"), line, match.group("zh"), match.group("en")))
    return entries, None


def scan_render_sites(root: pathlib.Path):
    """判据 B：产品源文件里出现 `LocalizedStringKey` 的地方（跳过整行注释）。"""
    hits: dict[str, list[int]] = {}
    for directory in RENDER_DIRS:
        base = root / directory
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*.swift")):
            relative = path.relative_to(root).as_posix()
            for index, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
                stripped = raw.strip()
                if not stripped or stripped.startswith("//"):
                    continue
                if "LocalizedStringKey" in raw:
                    hits.setdefault(relative, []).append(index)
    return hits


def load_exemptions(root: pathlib.Path):
    path = root / EXEMPTIONS
    if not path.exists():
        return None, f"找不到例外台账 {EXEMPTIONS}"
    try:
        return json.loads(path.read_text(encoding="utf-8")), None
    except json.JSONDecodeError as error:
        return None, f"{EXEMPTIONS} 不是合法 JSON：{error}"


def main() -> int:
    parser = argparse.ArgumentParser(description="文案即所见：语言表无 `**`、渲染口径唯一（L-19）")
    parser.add_argument("--root", default=str(REPO), help="扫描哪个仓库根（负例验证用）")
    args = parser.parse_args()
    root = pathlib.Path(args.root)

    problems: list[str] = []

    entries, error = read_entries(root)
    if entries is None:
        print(f"❌ {error}（根目录：{root}）")
        return 2

    exemptions, error = load_exemptions(root)
    if exemptions is None:
        print(f"❌ {error}（根目录：{root}）")
        return 2

    marker_exemptions = {item["key"]: item for item in exemptions.get("markerExemptions", [])}
    renderer_exemptions = {item["file"]: item for item in exemptions.get("rendererExemptions", [])}
    for item in exemptions.get("markerExemptions", []) + exemptions.get("rendererExemptions", []):
        if not str(item.get("reason", "")).strip():
            problems.append(f"{EXEMPTIONS}：例外条目 `{item.get('key') or item.get('file')}` 没有写理由")

    # ── 判据 C：防静默（表被掏空 / 正则失配时不许"零命中 = 通过"）────────────────
    if len(entries) < MIN_TABLE_ENTRIES:
        problems.append(
            f"{TABLE_FILE}：只解析出 {len(entries)} 条语言表条目（下限 {MIN_TABLE_ENTRIES}）——"
            f" 先把正则与表的形状对上，再谈判据 A"
        )

    # ── 判据 A：文案层不许有标记（两种语言都扫）────────────────────────────────
    keyed = {key: (line, zh, en) for key, line, zh, en in entries}
    marker_hits: list[str] = []
    for key, line, zh, en in entries:
        for language, value in (("zh", zh), ("en", en)):
            if MARKER not in value:
                continue
            if key in marker_exemptions:
                continue
            marker_hits.append(f"{TABLE_FILE}:{line} [. {key}]（{language}）{value.strip()[:90]}")
            problems.append(
                f"{TABLE_FILE}:{line}：键 `{key}` 的 {language} 槽位里有 markdown 强调标记 `{MARKER}` —— "
                f"口径 ② 是「文案即所见」，标记会照字面显示在纯文本渲染点上"
            )

    # ── 判据 D：marker 例外两端对账 ────────────────────────────────────────────
    for key, item in sorted(marker_exemptions.items()):
        marker = item.get("marker", "")
        if key not in keyed:
            problems.append(f"{EXEMPTIONS}：marker 例外 `{key}` 在语言表里不存在（陈旧条目）")
        elif marker and marker not in (keyed[key][1] + keyed[key][2]):
            problems.append(
                f"{EXEMPTIONS}：marker 例外 `{key}` 登记的形态 `{marker}` 已不在这条文案里 —— 条目陈旧，请删掉"
            )

    # ── 判据 B：渲染层口径唯一 ────────────────────────────────────────────────
    render_hits = scan_render_sites(root)
    for relative, lines in sorted(render_hits.items()):
        if relative in renderer_exemptions:
            continue
        problems.append(
            f"{relative}:{','.join(str(line) for line in lines)}：出现 `LocalizedStringKey` —— "
            f"口径 ② 下渲染点一律走 `Text(L(...))`（纯文本）；确需保留的按文件写进 {EXEMPTIONS}"
        )

    # 反向对账：登记了例外，却已经不用了 ⇒ 陈旧
    for relative, item in sorted(renderer_exemptions.items()):
        if not (root / relative).exists():
            problems.append(f"{EXEMPTIONS}：renderer 例外 `{relative}` 这个文件不存在")
        elif relative not in render_hits:
            problems.append(
                f"{EXEMPTIONS}：renderer 例外 `{relative}` 条目陈旧 —— 这个文件里已经没有 `LocalizedStringKey` 了"
            )

    # ── 判据 E：接线（门禁与它的负例必须在闭环里真的跑到）────────────────────────
    verify_all = root / VERIFY_ALL
    if not verify_all.exists():
        problems.append(f"找不到 {VERIFY_ALL} —— 判据 E 无从下手")
    else:
        script = verify_all.read_text(encoding="utf-8")
        for command in (GATE_COMMAND, SELF_TEST_COMMAND):
            if command not in script:
                problems.append(f"{VERIFY_ALL} 里没有 `{command}` —— 本门禁没接进闭环（有判据、没闭环）")

    # ── 打印 ─────────────────────────────────────────────────────────────────
    print("🅰 文案层：语言表里的 markdown 强调标记 `**`")
    print(f"   · 扫到语言表条目 {len(entries)} 条（下限 {MIN_TABLE_ENTRIES}）")
    print(f"   · 命中 `{MARKER}` 且未登记的键：{len(marker_hits)} 个")
    for hit in marker_hits:
        print(f"     - {hit}")
    print(f"   · 已登记标记例外：{len(marker_exemptions)} 条 —— " + ("、".join(sorted(marker_exemptions)) or "（无）"))
    print("🅱 渲染层：`LocalizedStringKey`（口径只剩一种）")
    if render_hits:
        for relative, lines in sorted(render_hits.items()):
            marks = "（已登记例外）" if relative in renderer_exemptions else ""
            print(f"   · {relative}{marks}:{','.join(str(line) for line in lines)}")
    else:
        print("   · 产品源文件里 0 处（platform/macos/App/ platform/macos/Core/ platform/macos/CLI/ Platform/）")

    if problems:
        print(f"\n❌ 文案口径门禁未通过（{len(problems)} 项）：")
        for problem in problems:
            print(f"   - {problem}")
        return 1

    print("✅ 文案口径门禁通过：语言表无标记、渲染点只剩纯文本一种口径")
    return 0


if __name__ == "__main__":
    sys.exit(main())
