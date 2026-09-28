#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""门禁：**侧边栏的折叠状态住在 `AppState`，不住在视图里**（队列 L-59 / `FR-CONN-15`）。

**为什么有它**：人工点验批次 1 第 3 条实测为挂 —— 用户原话「第 3 条记不住折叠状态」。
真因不在分组聚合（那是 `Core/ConnectionGrouping.swift` 的纯函数，本来就有单测），而在
**状态活在哪**：`ConnectionListView` 的 `collapsedGroups` 原本是**视图局部 `@State`**，
而这个视图由 `MainWindow.sidebarContent` **按活动栏分支创建** ⇒ 切到「工作区 / 笔记」
再切回来，分支被整个重建、折叠状态当场归零（重开应用同理）。

**当时所有门禁全绿** —— 编译、Core 单测、文档、快照，没有一条看「这个状态该活多久」。
所以修完代码还得把「它必须住在 `AppState`」变成机械判据；否则下一次有人顺手写回视图局部
`@State`，症状要再等人点一遍才会被发现（正是本工程反复栽的那个形状）。

判据（每条都能指名 文件:行号）：
  ① **视图不许自己揣着折叠状态** —— `App/Views/` 里出现「`@State` 且名字含 collapse」即红；
  ② **状态由 `AppState` 持有、默认全展开** —— 声明行必须是 `@Published private(set)` 且初值是
     空集合（一进来就把组都收起来，会让人以为连接没了）；
  ③ **写入口唯一** —— 对 `collapsedConnectionGroups` 的 `insert` / `remove` 只许出现在
     `setConnectionGroup(_:collapsed:)` 体内（集合本身是 `private(set)`，所以这是**结构性**的，
     不是靠自觉）；
  ④ **视图的绑定必须经 appState** —— `appState.isConnectionGroupCollapsed(` 与
     `appState.setConnectionGroup(` 都要在；视图里不许再出现**本地**折叠集合的判断；
  ⑤ **未分组那一段不许有折叠** —— 它是兜底容器（折起来等于把没归类的连接藏了）：
     `sectionView` 的 `isUngrouped` 分支里出现 `DisclosureGroup` 即红；
  ⑥ **空跑防护** —— 三个文件必须在、该解析出来的东西解析不出来即红（本仓库踩过两次
     「判据取不到输入 = 假绿」）。

**行为那一半在 `TestsUISnapshot/UISnapshotSidebarStateTests.swift`**（离屏渲染真视图树 + 逐字节
比较：「切活动栏再切回来，画出来的像素必须与折叠那一遍相同」）。按 L-01 的纪律那条不进每轮门禁
（要 `DOYAH_UI_SNAPSHOT=1`，离屏渲染不该进每轮门禁）⇒ 两条判据是**两层**：
这里每轮判「状态住在哪」，那里判「重建前后画出来一样」。

用法：
    python3 Scripts/check-sidebar-collapse-state.py            # 人读结论，失败非零退出
    python3 Scripts/check-sidebar-collapse-state.py --json     # 机器读
    python3 Scripts/check-sidebar-collapse-state.py --root <树> # 负例验证用（临时副本）
"""

from __future__ import annotations  # macOS 自带 python3 是 3.9，`str | None` 这类注解需要它

import argparse
import json
import re
import sys
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent

STATE_FILE = "App/AppState.swift"
VIEW_FILE = "App/Views/ConnectionListView.swift"
VIEWS_DIR = "App/Views"

STATE_PROPERTY = "collapsedConnectionGroups"
STATE_WRITER = "func setConnectionGroup("
STATE_READER = "func isConnectionGroupCollapsed("
VIEW_READ_SNIPPET = "appState.isConnectionGroupCollapsed("
VIEW_WRITE_SNIPPET = "appState.setConnectionGroup("
UNGROUPED_GUARD = "if section.isUngrouped {"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def code_lines(text: str) -> list[tuple[int, str]]:
    """按行返回**去掉注释**的代码（行号保留）。

    为什么要去注释：本轮新写的注释里就会出现 `collapsedConnectionGroups` / `@State` 这些词
    （讲清「为什么搬到 AppState」），照原样扫会把解释文字当违规 —— 门禁只能判**代码**。
    已知局限：字符串字面量里的 `//` 会被误伤，本门禁找的都是标识符形状，不会出现在字符串里。
    """
    without_block = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)
    return [(number, re.sub(r"//.*$", "", line)) for number, line in enumerate(without_block.splitlines(), 1)]


def strip_comments(text: str) -> str:
    """整份文本去注释（保留行数：块注释按原换行数补空行）。"""
    return "\n".join(line for _number, line in code_lines(text))


def function_body(text: str, signature: str) -> str | None:
    """取一个函数（含其嵌套作用域）的函数体 —— 按花括号配对，从签名那行往后数。"""
    start = text.find(signature)
    if start < 0:
        return None
    opening = text.find("{", start)
    if opening < 0:
        return None
    depth = 0
    for index in range(opening, len(text)):
        character = text[index]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return text[opening : index + 1]
    return None


def check(root: Path) -> tuple[list[str], list[str]]:
    problems: list[str] = []
    notes: list[str] = []

    needed = [STATE_FILE, VIEW_FILE]
    missing = [rel for rel in needed if not (root / rel).exists()]
    if missing:
        return [f"判据输入缺失：{'、'.join(missing)}（空跑不许通过）"], notes

    state_text = read(root / STATE_FILE)
    view_text = read(root / VIEW_FILE)
    state_code = strip_comments(state_text)
    view_code = strip_comments(view_text)

    # ⑥ 空跑防护：该解析出来的先确认解析得到
    if STATE_WRITER not in state_code or STATE_READER not in state_code:
        problems.append(
            f"{STATE_FILE}：`{STATE_WRITER}…)` / `{STATE_READER}…)` 不在（判据取不到输入，空跑不许通过）"
        )
    if "private func sectionView(" not in view_code or UNGROUPED_GUARD not in view_code:
        problems.append(
            f"{VIEW_FILE}：`sectionView` 或 `{UNGROUPED_GUARD}` 不在（判据取不到输入，空跑不许通过）"
        )
    if problems:
        return problems, notes

    # ① 视图不许自己揣着折叠状态（本次缺陷的形状本体）
    views = sorted((root / VIEWS_DIR).rglob("*.swift"))
    if not views:
        return [f"{VIEWS_DIR} 下一个源文件都没有 —— 判据取不到输入（空跑不许通过）"], notes
    for path in views:
        for number, line in code_lines(read(path)):
            if "@State" in line and re.search(r"collapse", line, re.I):
                problems.append(
                    f"{path.relative_to(root)}:{number}：视图里出现 `@State` 折叠状态 —— "
                    "折叠状态必须住在 `AppState`（视图由活动栏分支创建，会被整个重建 ⇒ 状态归零）"
                )
    notes.append(f"{VIEWS_DIR}：{len(views)} 个源文件里没有视图局部的折叠状态")

    # ② 状态由 AppState 持有、默认全展开
    declaration = None
    for line in state_code.splitlines():
        if STATE_PROPERTY in line and "@Published" in line:
            declaration = line
            break
    if declaration is None:
        problems.append(
            f"{STATE_FILE}：找不到 `@Published … {STATE_PROPERTY}` 的声明 —— "
            "折叠状态没有活人管（第 ③ 条也就无从谈起）"
        )
    else:
        if "private(set)" not in declaration:
            problems.append(
                f"{STATE_FILE}：`{STATE_PROPERTY}` 不是 `private(set)` —— "
                f"写入口就不止 `{STATE_WRITER}…)` 一个了（口径分叉就是这么来的）"
            )
        if "=[]" not in declaration.replace(" ", ""):
            problems.append(
                f"{STATE_FILE}：`{STATE_PROPERTY}` 的初值不是空集合 —— "
                "默认必须全部展开（一进来就把组都收起来，会让人以为连接没了）"
            )
        if "private(set)" in declaration and "=[]" in declaration.replace(" ", ""):
            notes.append(f"折叠状态：`@Published private(set) var {STATE_PROPERTY}: Set<String> = []`")

    # ③ 写入口唯一：insert / remove 只许在 `setConnectionGroup` 体内
    mutations = re.findall(rf"{STATE_PROPERTY}\s*\.\s*(insert|remove)\s*\(", state_code)
    body = function_body(state_code, STATE_WRITER)
    inside = 0
    if body is not None:
        inside = len(re.findall(rf"{STATE_PROPERTY}\s*\.\s*(insert|remove)\s*\(", body))
    if not mutations:
        problems.append(
            f"{STATE_FILE}：`{STATE_WRITER}…)` 里一处 `{STATE_PROPERTY}.insert/remove` 都没有 —— "
            "写入口是空的（判据取不到输入，空跑不许通过）"
        )
    elif inside != len(mutations):
        problems.append(
            f"{STATE_FILE}：对 `{STATE_PROPERTY}` 的增删共 {len(mutations)} 处，"
            f"其中只有 {inside} 处在 `{STATE_WRITER}…)` 体内 —— "
            "写入口必须唯一（集合是 `private(set)`，别处碰它就只能靠自觉）"
        )
    else:
        notes.append(f"写入口唯一：`{STATE_WRITER}…)` 体内 {inside} 处增删，别处 0 处")

    # ④ 视图的绑定必须经 appState，且不许再有本地集合判断
    for snippet, why in (
        (VIEW_READ_SNIPPET, "读折叠状态"),
        (VIEW_WRITE_SNIPPET, "写折叠状态"),
    ):
        if snippet not in view_code:
            problems.append(
                f"{VIEW_FILE}：{why}没走 `{snippet}…)` —— 视图与 `AppState` 的接线断了"
                "（接线一断，状态就是视图局部的，症状与 L-59 同款）"
            )
    for number, line in code_lines(view_text):
        if re.search(r"(?<![.\w])collapsedGroups\b", line):
            problems.append(
                f"{VIEW_FILE}:{number}：视图里还有**本地**折叠集合 `collapsedGroups` —— "
                "它就是 `@State` 那版的残留形状"
            )

    # ⑤ 未分组那一段不许有折叠（兜底容器：折起来等于把没归类的连接藏了）
    branch = uongrouped_branch(view_code)
    if branch is None:
        problems.append(
            f"{VIEW_FILE}：`{UNGROUPED_GUARD}` 与配套的 `}} else {{` 配对不上 —— "
            "判据取不到输入（空跑不许通过）"
        )
    else:
        start_line, end_line, body_text = branch
        if "DisclosureGroup" in body_text:
            problems.append(
                f"{VIEW_FILE}:{start_line}-{end_line}：未分组那一段出现了 `DisclosureGroup` —— "
                "它是兜底容器，设计上不给折叠（折起来等于把没归类的连接藏了）"
            )
        else:
            notes.append(f"未分组那一段（:{start_line}-{end_line}）不给折叠，与设计口径一致")

    return problems, notes


def uongrouped_branch(view_code: str) -> tuple[int, int, str] | None:
    """取 `if section.isUngrouped { … } else {` 里**前一个分支**的行号范围与正文。

    为什么按 `} else {` 找而不是数花括号：`} else {` 这一行里 `{` 与 `}` 各一个、
    净变化为 0，纯数括号会把 else 那一支也吞进来（第一版就是这么误报的 —— 它把
    else 分支里的 `DisclosureGroup` 当成了「未分组那一段出现了折叠」）。
    """
    lines = view_code.splitlines()
    start = next((index for index, line in enumerate(lines) if line.strip() == UNGROUPED_GUARD), None)
    if start is None:
        return None
    depth = 1  # 已进入 `if … {`
    for index in range(start + 1, len(lines)):
        line = lines[index]
        if depth == 1 and re.match(r"\s*\}\s*else\s*\{", line):
            body = "\n".join(lines[start + 1 : index])
            return start + 1, index + 1, body
        depth += line.count("{") - line.count("}")
        if depth <= 0:
            return None  # 没有 else 分支（形状变了 ⇒ 判据取不到输入，交给调用方报红）
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true", help="机器读")
    parser.add_argument("--root", default=str(BASE), help="仓库根（负例验证用）")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    problems, notes = check(root)

    if args.json:
        print(json.dumps({"problems": problems, "notes": notes}, ensure_ascii=False, indent=2))
    else:
        for note in notes:
            print(f"  ℹ️ {note}")
        if problems:
            print(f"\n❌ 折叠状态归属门禁未通过（{len(problems)} 项）：")
            for problem in problems:
                print(f"   - {problem}")
        else:
            print(
                "\n✅ 侧边栏折叠状态：判据全过（住在 AppState / 写入口唯一 / 默认全展开 / "
                "视图经 appState 接线 / 未分组不给折叠）"
            )
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
