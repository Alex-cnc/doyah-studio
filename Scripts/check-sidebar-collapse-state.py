#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""门禁：**侧边栏的折叠状态住在 `AppState`，不住在视图里**（队列 L-59 / `FR-STD-DB-CONN-012`）。

**为什么有它**：人工点验批次 1 第 3 条实测为挂 —— 用户原话「第 3 条记不住折叠状态」。
真因不在分组聚合（那是 `Core/ConnectionGrouping.swift` 的纯函数，本来就有单测），而在
**状态活在哪**：`ConnectionListView` 的 `collapsedGroups` 原本是**视图局部 `@State`**，
而这个视图由 `MainWindow.sidebarContent` **按活动栏分支创建** ⇒ 切到「工作区 / 笔记」
再切回来，分支被整个重建、折叠状态当场归零（重开应用同理）。

**当时所有门禁全绿** —— 编译、Core 单测、文档、快照，没有一条看「这个状态该活多久」。
所以修完代码还得把「它必须住在 `AppState`」变成机械判据；否则下一次有人顺手写回视图局部
`@State`，症状要再等人点一遍才会被发现（正是本工程反复栽的那个形状）。

判据（每条都能指名 文件:行号）：
  ① **视图不许自己揣着折叠状态** —— 判定物 =「`@State` + 集合类型 + 折叠语义的名字」
     （词汇面 `collaps|fold|收起|展开|折叠`，不再只认英文 `collapse` 一个词；声明允许折行）
     ＋ **结构那一臂**：任何视图局部集合只要做了 `DisclosureGroup(isExpanded:)` 的绑定源即红
     （名字不在词汇面里也逃不掉）。已有例外逐条登记在 `VIEW_LOCAL_EXEMPTIONS`（只加不减）；
  ② **状态由 `AppState` 持有、默认全展开** —— 声明必须是 `@Published private(set)` 且初值是
     空集合（`[]` 与 `Set()` 等价；声明折两行也算 —— 判定物是「在不在 / 空不空」，不是排版）；
  ③ **写入口唯一** —— 对 `collapsedConnectionGroups` 的**任何**变异（九种集合写法 + 直接赋值）
     只许出现在 `setConnectionGroup(_:collapsed:)` 体内（集合本身是 `private(set)`，所以这是
     **结构性**的，不是靠自觉）；
  ④ **视图的绑定必须经 appState** —— `appState.isConnectionGroupCollapsed(` 与
     `appState.setConnectionGroup(` 都要在；视图里不许再出现**本地**折叠集合的判断
     （`appState.` 是唯一白名单 —— `holder.collapsedGroups` 这种点号访问也判红）；
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

# ③ 判定物：集合的**等价变异写法** —— 不只 `insert` / `remove`（样本 64 实测：其余写法全逃逸）
MUTATION_METHODS = (
    "insert", "remove", "removeAll", "subtract", "formUnion",
    "union", "intersection", "symmetricDifference", "update",
)
MUTATION_PATTERN = rf"{STATE_PROPERTY}\s*\.\s*(?:{'|'.join(MUTATION_METHODS)})\s*\("
ASSIGNMENT_PATTERN = rf"(?<![\w.]){STATE_PROPERTY}\s*(?:[+\-*/%&|^])?=(?!=)"

# ① 判定物：折叠语义的**词汇面**（不再只认英文 `collapse` 一个词）+ 集合类型形状
FOLD_NAME_PATTERN = r"(collaps|fold|收起|展开|折叠)"
COLLECTION_TYPE_PATTERN = r"(?:Set\s*<|\[[^\]]*\])"
WINDOW = 3  # 声明允许折行：从关键字那行起，最多向后拼 3 行（排版不属于判定物）

# 已有例外（**只加不减 · 逐条登记**）：键 = `(相对路径, 属性名)` + 理由；未登记的命中一律判红。
VIEW_LOCAL_EXEMPTIONS = {
    ("App/Views/ObjectTreeView.swift", "expandedIDs"):
        "对象树的展开态（树视图局部持有；该视图不随活动栏分支重建 —— L-59 的由头是 "
        "ConnectionListView 那种按活动栏分支创建的视图）· 登记为已有例外、请前门核归口",
}

APPSTATE_PREFIX = "appState."


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


def declaration_window(lines: list[str], needle: str) -> tuple[int, str] | None:
    """找一条**允许折行**的属性声明：含 `needle` 的首行 + 其后 `WINDOW-1` 行拼成一行。

    判定物是「声明在不在 / 是不是 `private(set)` / 初值空不空」，与**排版**无关 ——
    样本 64 实测：合法的两行声明（`@Published private(set)` 换行再写 `var …`）会被旧判据
    误判成「找不到声明」（假阳）。
    """
    for index, line in enumerate(lines):
        if needle in line:
            start = max(0, index - 1)  # `@Published` 可能与 `var …` 折成两行 ⇒ 向前多取一行
            end = index
            for offset in range(WINDOW):
                if index + offset >= len(lines):
                    break
                end = index + offset
                if "=" in lines[end]:
                    break
            return index + 1, " ".join(part.strip() for part in lines[start : end + 1])
    return None


def view_local_collections(lines: list[tuple[int, str]]) -> list[tuple[int, str]]:
    """视图里「`@State` + 集合类型」的声明（允许折行）⇒ `(行号, 属性名)`。"""
    hits: list[tuple[int, str]] = []
    texts = [text for _number, text in lines]
    for index, text in enumerate(texts):
        if "@State" not in text:
            continue
        window = " ".join(part.strip() for part in texts[index : index + WINDOW])
        match = re.search(rf"\bvar\s+(\w+)\s*:\s*{COLLECTION_TYPE_PATTERN}", window)
        if match:
            hits.append((index + 1, match.group(1)))
    return hits


def is_local_collapsed_groups(line: str) -> bool:
    """**本地** `collapsedGroups` 吗（旧物带点号豁免 ⇒ `holder.collapsedGroups` 逃逸）。"""
    for match in re.finditer(r"\bcollapsedGroups\b", line):
        if not line[: match.start()].endswith(APPSTATE_PREFIX):
            return True
    return False


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
        rel = path.relative_to(root).as_posix()
        view_lines = code_lines(read(path))
        local = view_local_collections(view_lines)
        declared = False
        for number, name in local:
            if not re.search(FOLD_NAME_PATTERN, name, re.I):
                continue
            declared = True
            if (rel, name) in VIEW_LOCAL_EXEMPTIONS:
                continue
            problems.append(
                f"{rel}:{number}：视图里出现 `@State` 折叠状态 `{name}` —— "
                "折叠状态必须住在 `AppState`（视图由活动栏分支创建，会被整个重建 ⇒ 状态归零）；"
                "已有例外逐条登记在 `VIEW_LOCAL_EXEMPTIONS`，未登记不许豁免"
            )
        # 结构那一臂：**任何**视图局部集合只要做了 `DisclosureGroup(isExpanded:)` 的绑定源就判红
        # （名字不在词汇面里也逃不掉 —— 展开态的寿命由「谁需要它活着」决定，不看它叫什么）
        if not declared and any("DisclosureGroup(" in text for _number, text in view_lines):
            names = {name for _number, name in local}
            for number, line in view_lines:
                if "isExpanded:" not in line:
                    continue
                for name in sorted(names):
                    if re.search(rf"\b{name}\b", line):
                        problems.append(
                            f"{rel}:{number}：视图局部集合 `{name}` 是 "
                            "`DisclosureGroup(isExpanded:)` 的绑定源 —— 展开态须住进 `AppState`"
                        )
                        break
    notes.append(f"{VIEWS_DIR}：{len(views)} 个源文件里没有视图局部的折叠状态")

    # ② 状态由 AppState 持有、默认全展开（判定物允许折行；空初值 `[]` 与 `Set()` 等价）
    located = declaration_window(state_code.splitlines(), STATE_PROPERTY)
    if located is None:
        problems.append(
            f"{STATE_FILE}：找不到 `@Published … {STATE_PROPERTY}` 的声明 —— "
            "折叠状态没有活人管（第 ③ 条也就无从谈起）"
        )
    else:
        declaration_line, declaration = located
        if "@Published" not in declaration:
            problems.append(
                f"{STATE_FILE}:{declaration_line}：`{STATE_PROPERTY}` 不在 `@Published` 上 —— "
                "折叠状态不可观察（视图不会跟着重画）"
            )
        if "private(set)" not in declaration:
            problems.append(
                f"{STATE_FILE}：`{STATE_PROPERTY}` 不是 `private(set)` —— "
                f"写入口就不止 `{STATE_WRITER}…)` 一个了（口径分叉就是这么来的）"
            )
        empty = re.search(rf"=\s*(\[\]|Set\s*(?:<[^>]*>)?\s*\(\s*\))", declaration)
        if empty is None:
            problems.append(
                f"{STATE_FILE}：`{STATE_PROPERTY}` 的初值不是空集合 —— "
                "默认必须全部展开（一进来就把组都收起来，会让人以为连接没了）"
            )
        if "@Published" in declaration and "private(set)" in declaration and empty:
            notes.append(f"折叠状态：`@Published private(set) var {STATE_PROPERTY}: Set<String> = []`")

    # ③ 写入口唯一：对集合的**任何**变异（九种集合写法 + 直接赋值）只许在 `setConnectionGroup` 体内
    state_lines = state_code.splitlines()

    def is_mutation(text: str) -> bool:
        """这一行在变异那个集合吗（`insert` / `remove` / `removeAll` / `subtract` /
        `formUnion` / `union` / `intersection` / `symmetricDifference` / `update` + 直接赋值）。"""
        return bool(re.search(MUTATION_PATTERN, text) or re.search(ASSIGNMENT_PATTERN, text))

    mutations = [number for number, text in enumerate(state_lines, 1) if is_mutation(text)]
    body = function_body(state_code, STATE_WRITER)
    writer_line = next(
        (number for number, text in enumerate(state_lines, 1) if STATE_WRITER in text), None
    )
    body_span: set[int] = set()
    if body is not None and writer_line is not None:
        body_span = set(range(writer_line, writer_line + len(body.splitlines())))
    inside = [number for number in mutations if number in body_span]
    if not mutations:
        problems.append(
            f"{STATE_FILE}：`{STATE_WRITER}…)` 里一处 `{STATE_PROPERTY}.insert/remove` 都没有 —— "
            "写入口是空的（判据取不到输入，空跑不许通过）"
        )
    elif len(inside) != len(mutations):
        outside = [number for number in mutations if number not in body_span]
        problems.append(
            f"{STATE_FILE}：对 `{STATE_PROPERTY}` 的变异共 {len(mutations)} 处，"
            f"其中只有 {len(inside)} 处在 `{STATE_WRITER}…)` 体内 —— "
            "写入口必须唯一（集合是 `private(set)`，别处碰它就只能靠自觉）；"
            f"体外行号 {outside}"
        )
    else:
        notes.append(f"写入口唯一：`{STATE_WRITER}…)` 体内 {len(inside)} 处增删，别处 0 处")

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
        if is_local_collapsed_groups(line):
            problems.append(
                f"{VIEW_FILE}:{number}：视图里还有**本地**折叠集合 `collapsedGroups` —— "
                "它就是 `@State` 那版的残留形状（只有经 `appState.` 的点号访问才允许）"
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
