#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""门禁：**内置浏览器页签的归属 = 工作区（文件那一侧），不是数据库 SQL 工作台**
（队列 `L-149` 判据 ③④，闭环第 9 项）。

由头 = 需求提出者 2026-09-30 原话：「浏览器内置到工作区 Tab 页，而不是放到数据库 SQL 查询界面，
**本质上 html 也是一种文件**」（数据库侧是 **SQL 这门语言的工作台**）。第 131 轮把展示层搬了过去，
但**这件事此前没有任何东西看得见** —— 挪回数据库侧、或搬走了没接上，编译照过、单测照绿。

**判定物一律在代码上判**：注释抹成等长空格、字符串**内容**抹掉 —— 一行注释不再冒充落点，
字符串里提过的标识也不算命中（2026-10-13 合册 `T-20261013-027` · 原单 `T-20261010-061`）。
**面 = `App/`**，并与 `Package.swift` **现读**的生产 target 源码目录**双向对账**：面外的生产根
逐条登记理由（理由为空 / 不是生产目录 ⇒ 判红），七个标识在面外出现 ⇒ 判红（面外回流口）。
**SRS 定义行锚点唯一化**：编号列 = `FR-EDIT-34` + 行首形状 `| FR-EDIT-34 | ` + 标题格含
`**内嵌浏览器页签（工作区，完整浏览器）**`，三者齐才认定义行（恰一行：0 行 / >1 行 / 形状变了
都判红并指名行号）；归属格除写「工作区」外还判**反义**形态（`不属工作区` / `非工作区` 都是子串）。
判据 = 一份**双向对账**的允许落点台账（`App/` 下出现下列标识的文件必须登记过，登记的必须真的命中）：
    `browserPages` / `selectedBrowserPage` / `selectedBrowserID` / `browserEngines` /
    `BrowserTabView` / `openBrowserTab` / `browserTabButton`
数据库侧视图 `App/Views/QueryWorkspaceView.swift` 命中即红（它不在台账里，也不会被登记）。
**状态所有者**另判一处（第 135 轮补，队列 `L-149` 剩余①）：浏览器状态必须住在
`App/WorkspaceBrowserModel.swift`（那个类只此一处定义）——
挂回 `AppState` 的 `@Published` 上，引擎每回报一次标题 / 加载中就要重算整个窗口。
另判两处**文档条文**（SRS `FR-EDIT-34` 定义格、概要设计 §3.12「视图契约」行）必须写「工作区」、
不得再钉在「编辑器区」；订正过程留在证据格里，**判据只看条文格**。空跑防护：扫描面文件数 /
台账文件 / 七个标识各自至少一处命中 / 状态所有者类在位。

用法：
    python3 Scripts/check-browser-tab-ownership.py              # 人读结论，失败非零退出
    python3 Scripts/check-browser-tab-ownership.py --json       # 机器读
    python3 Scripts/check-browser-tab-ownership.py --root <树>  # 负例验证用（临时副本）
    python3 Scripts/check-browser-tab-ownership.py --self-test  # 负例自检（临时副本上写坏）
"""

from __future__ import annotations  # macOS 自带 python3 是 3.9，`X | None` 这类注解需要它

import argparse
import hashlib
import json
import pathlib
import re
import shutil
import sys
import tempfile

BASE = pathlib.Path(__file__).resolve().parent.parent

APP_DIR = "App"
# **状态所有者**（队列 `L-149` 剩余①，2026-10-01 第 135 轮搬的家）：浏览器页签的
# 页签集 / 选中 / 引擎缓存 / 导航动作全在这个文件里 —— 它**不是** `AppState`
# （挂在那里时引擎每回报一次标题 / 加载中都要重算整个窗口；同族的病见 `QueryEditorBuffer`）。
STATE_OWNER = "App/WorkspaceBrowserModel.swift"
STATE_OWNER_CLASS = "final class WorkspaceBrowserModel: ObservableObject"
VIEW_DEFINITION = "App/Views/BrowserTabView.swift"
DB_SIDE_VIEW = "App/Views/QueryWorkspaceView.swift"
WORKSPACE_VIEWS = ("App/Views/WorkspaceTabStrip.swift", "App/Views/WorkspaceAreaView.swift")

# 台账：标识 → 允许出现它的文件（`App/` 下，除下面那处豁免）。两个方向都要对账。
LEDGER = {
    "browserPages": {STATE_OWNER, "App/Views/WorkspaceTabStrip.swift"},
    "selectedBrowserPage": {STATE_OWNER, "App/Views/WorkspaceAreaView.swift"},
    "selectedBrowserID": {STATE_OWNER, "App/Views/WorkspaceTabStrip.swift"},
    "browserEngines": {STATE_OWNER},
    "BrowserTabView": {"App/Views/WorkspaceAreaView.swift"},
    "openBrowserTab": {STATE_OWNER, "App/DoyahStudioCommands.swift"},
    "browserTabButton": {"App/Views/WorkspaceTabStrip.swift"},
}
EXEMPT = {
    VIEW_DEFINITION: "浏览器视图自己的定义处（只被工作区内容区渲染）",
}

SRS = "Docs/需求规范书.md"
HLD = "Docs/概要设计.md"
SRS_ENTRY = "FR-EDIT-34"
SRS_ENTRY_TITLE = "内嵌浏览器页签"
HLD_CONTRACT_LINE = "**视图契约**"
OWNED_WORD = "工作区"
FORBIDDEN_WORD = "编辑器区"

MIN_APP_FILES = 90    # 实测 119（`App/` 下 `.swift`）—— 原写 104 已陈旧（2026-10-13 订正）
PACKAGE = "Package.swift"
SRS_TITLE_BOLD = "**内嵌浏览器页签（工作区，完整浏览器）**"
# 面 = `App/`（本判据的落点台账就在这一层）。`Package.swift` **现读**出来的其余生产
# target 源码目录必须逐条登记理由（理由为空 / 不是生产目录 ⇒ 判红）；登记了的根也会被扫，
# 七个标识在面外出现即红（原单 ㈤ 的面外回流口）。
FACE_ROOTS_REGISTERED = {
    "Core": "生产 target 源码目录（浏览器状态机 / 页签模型那一层）—— 台账只登记 `App/` 展示层",
    "Plugins/Notes/Sources": "插件生产源码（笔记插件那一层）—— 同上",
    "Platform/macOS": "生产 target 源码目录（`WKWebView` 引擎那一层）—— 同上",
    "CLI": "生产 target 源码目录（命令行入口）—— 同上",
    "Tools/LicenseTool": "生产 target 源码目录（授权工具）—— 同上",
    "Plugins/Notes/Views": "插件生产视图（笔记插件那一层）—— 同上",
}
# 归属格的**反义**形态：`（不属工作区）` / `（非工作区）` 都是「工作区」的子串，判据不能只判子串。
NEGATED_OWNED = re.compile(r"(不属|不属于|不是|不在|不归|非)(于|是|属|在|归)?" + OWNED_WORD)


def read(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8")


def rel(root: pathlib.Path, path: pathlib.Path) -> str:
    return path.relative_to(root).as_posix()


def strip_comments(text: str) -> str:
    """注释抹成**等长空格**（字符串感知 / 块注释可嵌套）⇒ 行号与列位都不动。

    为什么自己扫：Swift 里 `"// 不是注释"` 是字符串、`/* /* 嵌套 */ */` 合法，一行正则两面都判错。
    """
    out: list[str] = []
    index, length = 0, len(text)
    in_line, depth, in_string, escaped = False, 0, False, False
    while index < length:
        char = text[index]
        following = text[index + 1] if index + 1 < length else ""
        if in_line:
            out.append("\n" if char == "\n" else " ")
            in_line = char != "\n"
        elif depth:
            if char == "*" and following == "/":
                depth -= 1
                out.append("  ")
                index += 2
                continue
            if char == "/" and following == "*":
                depth += 1
                out.append("  ")
                index += 2
                continue
            out.append("\n" if char == "\n" else " ")
        elif in_string:
            out.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
        elif char == '"':
            in_string = True
            out.append(char)
        elif char == "/" and following == "/":
            in_line = True
            out.append("  ")
            index += 2
            continue
        elif char == "/" and following == "*":
            depth = 1
            out.append("  ")
            index += 2
            continue
        else:
            out.append(char)
        index += 1
    return "".join(out)


def blank_strings(text: str) -> str:
    """字符串字面量的**内容**抹成等长空格（引号本身留着）—— 字符串里提过的标识不算落点。"""
    out: list[str] = []
    index, length = 0, len(text)
    in_string, escaped = False, False
    while index < length:
        char = text[index]
        if in_string:
            if char == "\n":
                out.append("\n")
            elif escaped:
                out.append(" ")
                escaped = False
            elif char == "\\":
                out.append(" ")
                escaped = True
            elif char == '"':
                out.append('"')
                in_string = False
            else:
                out.append(" ")
        elif char == '"':
            in_string = True
            out.append('"')
        else:
            out.append(char)
        index += 1
    return "".join(out)


def _blocks(text: str, opener: str) -> list[str]:
    """取 `opener` 起的那一整段（按括号配对走）。"""
    found: list[str] = []
    index = 0
    while True:
        at = text.find(opener, index)
        if at < 0:
            return found
        depth = 0
        for position in range(at + len(opener) - 1, len(text)):
            char = text[position]
            if char in "([":
                depth += 1
            elif char in ")]":
                depth -= 1
                if depth == 0:
                    found.append(text[at:position + 1])
                    index = position + 1
                    break
        else:
            return found


def package_production_dirs(root: pathlib.Path) -> list[str] | None:
    """包清单**现读**生产 target 的源码目录（面 = 声明面，不是判据手抄的清单）。"""
    path = root / PACKAGE
    if not path.exists():
        return None
    code = strip_comments(read(path))
    directories: list[str] = []
    for opener in (".target(", ".executableTarget("):
        for block in _blocks(code, opener):
            name = re.search(r'name:\s*"([^"]+)"', block)
            if not name:
                continue
            base = re.search(r'path:\s*"([^"]+)"', block)
            sources = re.search(r"sources:\s*\[([^\]]*)\]", block)
            prefix = "" if base is None or base.group(1) == "." else base.group(1) + "/"
            if sources:
                items = [prefix + item.strip().strip('"')
                         for item in sources.group(1).split(",") if item.strip()]
            elif base is not None and base.group(1) != ".":
                items = [base.group(1)]
            else:
                items = [name.group(1)]
            for item in items:
                if item not in directories:
                    directories.append(item)
    return directories


def out_of_face_sources(root: pathlib.Path) -> dict[str, str]:
    """面外生产根（登记在 `FACE_ROOTS_REGISTERED`）下的全部 `.swift`。"""
    sources: dict[str, str] = {}
    for dirname in sorted(FACE_ROOTS_REGISTERED):
        base = root / dirname
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*.swift")):
            sources[rel(root, path)] = read(path)
    return sources


def lines_of(rows: list[tuple[int, str]]) -> str:
    return "、".join(str(number) for number, _ in rows) or "无"


def cells(line: str) -> list[str]:
    """GFM 表格行 → 单元格（去首尾竖线）：`|FR-EDIT-34 |…` 与 `| FR-EDIT-34 |…` 都认得出编号列。"""
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def app_sources(root: pathlib.Path, problems: list[str]) -> dict[str, str]:
    """扫描面 = `App/` 下全部 `.swift`。目录不在 / 文件数低于下限 ⇒ 判红（不许悄悄缩面）。"""
    base = root / APP_DIR
    if not base.is_dir():
        problems.append("App/ 不存在 —— 扫描面被削过（空跑不许通过）")
        return {}
    sources = {rel(root, path): read(path) for path in sorted(base.rglob("*.swift"))}
    if len(sources) < MIN_APP_FILES:
        problems.append(
            f"App/ 扫描面只有 {len(sources)} 个 `.swift`（下限 {MIN_APP_FILES}）—— 判据扫不到东西，不许通过"
        )
    return sources


def hits(sources: dict[str, str], token: str) -> dict[str, list[int]]:
    """标识在哪些文件、哪些行命中（行号从 1 起）。"""
    found: dict[str, list[int]] = {}
    for name, text in sources.items():
        lines = [number for number, line in enumerate(text.splitlines(), 1) if token in line]
        if lines:
            found[name] = lines
    return found


def check(root: pathlib.Path) -> tuple[list[str], list[str]]:
    problems: list[str] = []
    notes: list[str] = []
    sources = app_sources(root, problems)
    # **判定物一律在代码上判**（原单 ㈠ 假绿 / ㈡ 假阳的根）：
    # `code` = 注释抹成等长空格；`bare` = 再把字符串内容抹掉（字符串里提过的标识不算落点）。
    code = {name: strip_comments(text) for name, text in sources.items()}
    bare = {name: blank_strings(text) for name, text in code.items()}

    # ①b 状态所有者：浏览器状态必须住在工作区模型里，而那个类**只此一处**定义
    if STATE_OWNER not in sources:
        problems.append(f"`{STATE_OWNER}` 不在扫描面里 —— 浏览器页签的状态所有者不见了（判据悬空）")
    elif STATE_OWNER_CLASS not in code[STATE_OWNER]:
        problems.append(
            f"`{STATE_OWNER}` 里找不到 `{STATE_OWNER_CLASS}` —— 状态所有者被改名 / 被掏空"
        )
    else:
        notes.append(f"状态所有者 = `{STATE_OWNER}`（`{STATE_OWNER_CLASS}`）")
    for name, text in code.items():
        if name != STATE_OWNER and STATE_OWNER_CLASS in text:
            problems.append(f"`{name}` 里也声明了 `{STATE_OWNER_CLASS}` —— 状态所有者只能有一处")

    # ② 双向对账：允许落点 ⊆ 台账，台账 ⊆ 允许落点
    for token, allowed in sorted(LEDGER.items()):
        found = hits(bare, token)
        for name in sorted(allowed):
            if name not in found:
                problems.append(
                    f"`{name}` 已经没有 `{token}` 的引用了 —— 台账登记了这个落点，盘上却没有（搬走了没接上？）"
                )
        for name in sorted(found):
            if name in allowed or name in EXEMPT:
                continue
            where = ", ".join(str(number) for number in found[name])
            problems.append(
                f"`{name}`:{where} 出现 `{token}` —— 浏览器页签的落点没登记进本判据的台账"
                "（数据库侧视图就是这条口径的反面：它不该有浏览器）"
            )
        if not found:
            problems.append(f"`{token}` 在整个 App/ 里一处都没有 —— 判据空转（标识被删光 / 扫描面被削）")
        elif found.keys() <= (set(allowed) | set(EXEMPT)):
            notes.append(f"{token}：落点 {len(found)} 个文件，全部在台账内")

    # ③ 文档条文：归属 = 工作区（只判**条文格**，订正过程可以写在证据格里）
    srs = root / SRS
    if not srs.exists():
        problems.append(f"`{SRS}` 不在 —— 条文侧无从判起")
    else:
        numbered = [(number, line)
                    for number, line in enumerate(read(srs).splitlines(), 1)
                    if cells(line) and cells(line)[0] == SRS_ENTRY]
        definition_rows = [(number, line) for number, line in numbered
                           if line.startswith(f"| {SRS_ENTRY} |") and SRS_TITLE_BOLD in line]
        near_miss = [(number, line) for number, line in numbered
                     if SRS_TITLE_BOLD in line and (number, line) not in definition_rows]
        if not definition_rows:
            problems.append(
                f"`{SRS}` 里找不到 `{SRS_ENTRY}` 的**定义行**（编号列 = `{SRS_ENTRY}` 且标题格含"
                f" `{SRS_TITLE_BOLD}` 的那一行）—— 空跑：定义行被删 / 标题被改名 / 行首形状不再规范"
                f"；与 `{SRS_ENTRY}` 有关的表格行：{lines_of(numbered)}"
            )
        elif len(definition_rows) > 1:
            problems.append(
                f"`{SRS}` 里 `{SRS_ENTRY}` 的定义行只能有一处，实测 {len(definition_rows)} 处"
                f"（行号 {lines_of(definition_rows)}）—— 定义行锚点不唯一 ⇒ 判据会判到别的行上"
            )
        for number, _ in near_miss:
            problems.append(
                f"`{SRS}` 第 {number} 行的行首形状不再是 `| {SRS_ENTRY} | `—— 定义行只认规范形状，"
                "形状变了不许静默转判别的行"
            )
        if len(definition_rows) == 1:
            row_cells = cells(definition_rows[0][1])
            definition = row_cells[1] if len(row_cells) > 1 else ""
            if OWNED_WORD not in definition:
                problems.append(
                    f"`{SRS}` 的 `{SRS_ENTRY}` 条文没写「{OWNED_WORD}」—— 归属没落进条文（浏览器属文件那一侧）"
                )
            negated = NEGATED_OWNED.search(re.sub(r"[*`\s]", "", definition))
            if negated:
                problems.append(
                    f"`{SRS}` 的 `{SRS_ENTRY}` 条文的归属格是**反义**形态（「{negated.group(0)}」）——"
                    f" 「{OWNED_WORD}」在那儿只是个子串，归属没落进条文"
                )
            if FORBIDDEN_WORD in definition:
                problems.append(
                    f"`{SRS}` 的 `{SRS_ENTRY}` 条文仍把浏览器钉在「{FORBIDDEN_WORD}」—— 那是数据库 SQL 工作台"
                )
            elif OWNED_WORD in definition and not negated:
                notes.append(f"{SRS} `{SRS_ENTRY}` 条文：归属 =「{OWNED_WORD}」，且不再出现「{FORBIDDEN_WORD}」")

    hld = root / HLD
    if not hld.exists():
        problems.append(f"`{HLD}` 不在 —— 契约侧无从判起")
    else:
        contract_lines = [line for line in read(hld).splitlines() if HLD_CONTRACT_LINE in line]
        if not contract_lines:
            problems.append(
                f"`{HLD}` 里找不到「{HLD_CONTRACT_LINE}」那一行 —— 空跑：契约行被删 / 被改写"
            )
        else:
            line = contract_lines[0]
            if OWNED_WORD not in line:
                problems.append(f"`{HLD}` §3.12 的「{HLD_CONTRACT_LINE}」行没写「{OWNED_WORD}」")
            if FORBIDDEN_WORD in line:
                problems.append(f"`{HLD}` §3.12 的「{HLD_CONTRACT_LINE}」行仍写着「{FORBIDDEN_WORD}」")
            elif OWNED_WORD in line:
                notes.append(f"{HLD} §3.12 视图契约行：归属 =「{OWNED_WORD}」")

    # ④ 空跑防护的另一半：数据库侧视图与工作区两侧都必须在扫描面里（消失 = 判据悬空）
    if DB_SIDE_VIEW not in sources:
        problems.append(f"`{DB_SIDE_VIEW}` 不在扫描面里 —— 「数据库侧不许有浏览器」这条判据悬空了")
    for name in WORKSPACE_VIEWS:
        if name not in sources:
            problems.append(f"`{name}` 不在扫描面里 —— 工作区侧的落点不见了")
    if not (set(EXEMPT) & set(sources)):
        problems.append("两处豁免文件一个都不在扫描面里 —— 台账与盘上对不上")
    # ⓪ 面与 `Package.swift` 现读对账（原单 ㈤：面外生产根 = 唯一的静默回流口）
    production = package_production_dirs(root)
    strays: list[str] = []
    if production is None:
        problems.append(f"`{PACKAGE}` 不在盘上 / 读不出 target —— 面对账没有输入，不许当通过")
    else:
        outside = [directory for directory in production
                   if directory != APP_DIR and directory not in FACE_ROOTS_REGISTERED]
        if outside:
            problems.append(
                f"生产 target 的源码目录落在判据面外：{outside} —— 面外回流没人管"
                "（该根要么进面、要么在 `FACE_ROOTS_REGISTERED` 里登记理由）"
            )
        for registered, reason in sorted(FACE_ROOTS_REGISTERED.items()):
            if registered not in production:
                problems.append(
                    f"登记的面外根 `{registered}` 不是 `{PACKAGE}` 的生产 target 源码目录 —— 死登记"
                )
            elif not reason.strip():
                problems.append(f"登记的面外根 `{registered}` **理由为空** —— 空理由不是理由")
        for name, text in out_of_face_sources(root).items():
            judged = blank_strings(strip_comments(text))
            for token in sorted(LEDGER):
                for number, line in enumerate(judged.splitlines(), 1):
                    if token in line:
                        strays.append(f"{name}:{number}")
                        problems.append(
                            f"`{name}`:{number} 出现 `{token}` —— **面外回流**：那是生产 target 的源码目录、"
                            "不在本判据的落点台账面上（七个标识只许出现在 `App/` 的台账落点里）"
                        )
    notes.append(
        f"面与 `{PACKAGE}` 对账一致：生产 target 源码目录 {len(production or [])} 个 · "
        f"面 = `{APP_DIR}/`（1 根）+ 登记的面外根 {len(FACE_ROOTS_REGISTERED)} 个 · 面外命中 {len(strays)} 处"
    )
    notes.append(
        f"扫描面 App/ {len(sources)} 个 `.swift`；台账 {len(LEDGER)} 个标识 / {len(EXEMPT)} 处豁免"
    )
    return problems, notes


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true", help="机器读")
    parser.add_argument("--root", default=str(BASE), help="仓库根（负例验证用）")
    parser.add_argument("--self-test", action="store_true", dest="self_test", help="负例自检")
    args = parser.parse_args()

    root = pathlib.Path(args.root).resolve()
    if args.self_test:
        return self_test(root)

    problems, notes = check(root)
    if args.json:
        print(json.dumps({"problems": problems, "notes": notes}, ensure_ascii=False, indent=2))
        return 1 if problems else 0

    for note in notes:
        print(f"  ℹ️ {note}")
    if problems:
        print(f"\n❌ 浏览器页签归属门禁未通过（{len(problems)} 项）：")
        for problem in problems:
            print(f"   - {problem}")
        return 1
    print(
        "\n✅ 内置浏览器页签归属 = 工作区：状态所有者 = `App/WorkspaceBrowserModel.swift`（只此一处）· "
        "落点全部在台账内（数据库侧零命中）· 台账逐条真的命中 · "
        f"SRS `{SRS_ENTRY}` 与概要设计 §3.12 条文已写「{OWNED_WORD}」· 判据面在位"
    )
    return 0


# ── 负例自检 ────────────────────────────────────────────────────────────────
#
# 纪律：一律在**临时副本**上写坏，末例核对真仓库逐字节未变。
# 每个负例都要问一句「这条改动如果真发生了，判据会不会当场报红」——
# 报不出来，这门禁就只是文档。

WATCHED = (STATE_OWNER, VIEW_DEFINITION, DB_SIDE_VIEW) + WORKSPACE_VIEWS + (
    "App/DoyahStudioCommands.swift",
    "App/Views/AppearanceSheet.swift",   # 无关文件：证明「改别的不会误报」
    SRS,
    HLD,
)


def _sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _fixture(destination: pathlib.Path, root: pathlib.Path) -> pathlib.Path:
    """副本 = `App/` 全部 `.swift` + 面外生产根（只 `.swift`）+ 包清单 + 两份文档。"""
    for dirname in (APP_DIR, "Docs") + tuple(sorted(FACE_ROOTS_REGISTERED)):
        source = root / dirname
        if not source.is_dir():
            continue
        for path in sorted(source.rglob("*")):
            if not path.is_file():
                continue
            if dirname == "Docs" and path.name not in (pathlib.Path(SRS).name, pathlib.Path(HLD).name):
                continue
            if dirname not in (APP_DIR, "Docs") and path.suffix != ".swift":
                continue
            relative = path.relative_to(source)
            target = destination / dirname / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
    if (root / PACKAGE).exists():
        shutil.copy2(root / PACKAGE, destination / PACKAGE)
    return destination


def _rewrite(path: pathlib.Path, old: str, new: str) -> None:
    """把 `old` **全部**替换成 `new`（`_patch` 只换第一处）。"""
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise AssertionError(f"夹具写坏失败：`{old}` 不在 {path.name} 里")
    path.write_text(text.replace(old, new), encoding="utf-8")


def _append(path: pathlib.Path, line: str) -> None:
    path.write_text(path.read_text(encoding="utf-8") + line + "\n", encoding="utf-8")


def _patch(path: pathlib.Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise AssertionError(f"夹具写坏失败：`{old}` 不在 {path.name} 里")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def self_test(root: pathlib.Path) -> int:
    before = {name: _sha(root / name) for name in WATCHED if (root / name).exists()}
    cases: list[tuple[str, bool]] = []   # (名字, 期望报红)
    with tempfile.TemporaryDirectory(prefix="doyah-browser-ownership-") as tmp:
        workspace = pathlib.Path(tmp)

        def fresh(name: str) -> pathlib.Path:
            return _fixture(workspace / name, root)

        # ① 绿：真仓库的副本，判据必须全过
        green = fresh("green")
        cases.append(("绿对照：真仓库副本应全过", not check(green)[0]))

        # ②③ 红：数据库侧视图又把浏览器接回去（这条口径的标准反例）
        db_state = fresh("db-side-state")
        _patch(
            db_state / DB_SIDE_VIEW,
            "    var body: some View {",
            "    var body: some View {\n        let _drift = appState.browserPages.count",
        )
        cases.append(("数据库侧读 browserPages", bool(check(db_state)[0])))

        db_view = fresh("db-side-view")
        _patch(
            db_view / DB_SIDE_VIEW,
            "    var body: some View {",
            "    var body: some View {\n        let _drift = BrowserTabView(page: BrowserPage())",
        )
        cases.append(("数据库侧渲染 BrowserTabView", bool(check(db_view)[0])))

        # ④⑤ 红：搬到工作区却没接上（台账登记了、盘上没有）
        strip = fresh("strip-unwired")
        _patch(strip / WORKSPACE_VIEWS[0], "ForEach(browser.browserPages)", "ForEach(browser.hiddenBrowserPages)")
        cases.append(("工作区页签条不再引用 browserPages", bool(check(strip)[0])))

        area = fresh("area-unwired")
        _patch(area / WORKSPACE_VIEWS[1], "BrowserTabView(page: page)", "Color.clear")
        cases.append(("工作区内容区不再渲染 BrowserTabView", bool(check(area)[0])))

        # ⑤b 红：状态被搬回 `AppState`（`L-149` 剩余① 正是要它**不**住在那儿）
        state_back = fresh("state-back-in-appstate")
        _patch(
            state_back / "App/AppState.swift",
            "final class AppState: ObservableObject {",
            "final class AppState: ObservableObject {\n    @Published var browserPages: [BrowserPage] = []",
        )
        cases.append(("浏览器状态被写回 AppState", bool(check(state_back)[0])))

        # ⑤c 红：数据库侧又读浏览器选中态（`selectedBrowserID` 同在这份台账里）
        db_selection = fresh("db-side-selection")
        _patch(
            db_selection / DB_SIDE_VIEW,
            "    var body: some View {",
            "    var body: some View {\n        let _drift = appState.selectedBrowserID",
        )
        cases.append(("数据库侧读 selectedBrowserID", bool(check(db_selection)[0])))

        # ⑤d 红：状态所有者被改名 / 被掏空
        owner_gone = fresh("owner-renamed")
        _patch(
            owner_gone / STATE_OWNER,
            STATE_OWNER_CLASS,
            "final class WorkspaceBrowserModelRenamed: ObservableObject",
        )
        cases.append(("状态所有者类被改名", bool(check(owner_gone)[0])))

        # ⑥⑦ 红：文档条文又把浏览器钉回数据库侧
        srs_back = fresh("srs-back")
        srs_text = read(srs_back / SRS)
        rows = [line for line in srs_text.splitlines() if line.startswith(f"| {SRS_ENTRY} |") and SRS_ENTRY_TITLE in line]
        _patch(srs_back / SRS, rows[0], rows[0].replace("在**工作区**新增", "在**编辑器区**新增", 1))
        cases.append((f"{SRS} 条文改回「{FORBIDDEN_WORD}」", bool(check(srs_back)[0])))

        hld_back = fresh("hld-back")
        hld_text = read(hld_back / HLD)
        line = [item for item in hld_text.splitlines() if HLD_CONTRACT_LINE in item][0]
        _patch(hld_back / HLD, line, line.replace(OWNED_WORD, FORBIDDEN_WORD, 1))
        cases.append((f"{HLD} 视图契约行改回「{FORBIDDEN_WORD}」", bool(check(hld_back)[0])))

        # ②③ 假绿 / 对照：注释充当落点（原单 ㈠ 的 P1 / P1′）
        commented = fresh("area-renamed-with-comment")
        _rewrite(commented / WORKSPACE_VIEWS[1], "selectedBrowserPage", "keptBrowserPage")
        _append(commented / WORKSPACE_VIEWS[1], "// selectedBrowserPage 归工作区")
        cases.append((
            "假绿 · 工作区内容区把真用法改名、只留一行注释 ⇒ 判红（旧版 rc=0）",
            bool(check(commented)[0]),
        ))

        renamed_only = fresh("area-renamed-silent")
        _rewrite(renamed_only / WORKSPACE_VIEWS[1], "selectedBrowserPage", "keptBrowserPage")
        cases.append((
            "对照 · 同样改名、不留注释 ⇒ 仍判红（不许削软）",
            bool(check(renamed_only)[0]),
        ))

        # ④⑤ 假阳：注释 / 字符串字面量被当成落点（原单 ㈡ 的 P2 / P3）
        db_comment = fresh("db-side-comment")
        _append(db_comment / DB_SIDE_VIEW, "// 浏览器（browserPages）归工作区，本视图零命中")
        cases.append((
            "假阳 · 数据库侧视图加一行注释提 browserPages ⇒ 判绿（旧版 rc=1）",
            not check(db_comment)[0],
        ))

        db_string = fresh("db-side-string")
        _patch(db_string / DB_SIDE_VIEW, "    var body: some View {",
               '    var body: some View {\n        let _s = "BrowserTabView"')
        cases.append((
            "假阳 · 同视图加字符串字面量 `\"BrowserTabView\"` ⇒ 判绿（旧版 rc=1）",
            not check(db_string)[0],
        ))

        # ⑥⑦⑧⑨ 假绿：定义行锚点唯一化（整行删 / 标题改名 / 行首形状 / 归属格反义）
        definition_line = [line for line in read(root / SRS).splitlines()
                           if line.startswith(f"| {SRS_ENTRY} |") and SRS_TITLE_BOLD in line][0]

        dropped = fresh("srs-definition-dropped")
        (dropped / SRS).write_text(
            "\n".join(item for item in read(dropped / SRS).splitlines() if item != definition_line),
            encoding="utf-8",
        )
        cases.append((
            "假绿 · SRS 定义行整行删掉 ⇒ 判红且点名「定义行」（旧版转判摘要行 rc=0）",
            any("定义行" in problem for problem in check(dropped)[0]),
        ))

        retitled = fresh("srs-title-renamed")
        _patch(retitled / SRS, definition_line,
               definition_line.replace(SRS_TITLE_BOLD, "**内嵌 browser 页签（工作区，完整浏览器）**", 1))
        cases.append((
            "假绿 · SRS 定义行标题改名 ⇒ 判红且点名「定义行」（旧版 rc=0）",
            any("定义行" in problem for problem in check(retitled)[0]),
        ))

        reshaped = fresh("srs-row-shape")
        _patch(reshaped / SRS, definition_line,
               definition_line.replace(f"| {SRS_ENTRY} |", f"|{SRS_ENTRY} |", 1))
        cases.append((
            "假绿 · SRS 定义行行首形状改成 `|FR-EDIT-34 |` ⇒ 判红且点名「行首形状」",
            any("行首形状" in problem for problem in check(reshaped)[0]),
        ))

        negated_owned = fresh("srs-negated-owned")
        _patch(negated_owned / SRS, definition_line,
               definition_line.replace("在**工作区**新增", "在**不属工作区**新增", 1))
        cases.append((
            "假绿 · SRS 归属格写成反义（不属工作区）⇒ 判红且点名「反义」",
            any("反义" in problem for problem in check(negated_owned)[0]),
        ))

        # ⑩ 假绿：面外回流（生产 target 的源码目录不在判据的落点台账面上）
        outside = fresh("out-of-face-token")
        probe = outside / "Platform/macOS/ProbeS61.swift"
        probe.parent.mkdir(parents=True, exist_ok=True)
        probe.write_text("let probe = browserPages\n", encoding="utf-8")
        cases.append((
            "假绿 · 标识落 Platform/macOS（登记的生产根、非判据面）⇒ 判红且点名「面外回流」",
            any("面外回流" in problem for problem in check(outside)[0]),
        ))

        new_target = fresh("new-production-root")
        _patch(new_target / PACKAGE, "    targets: [\n",
               '    targets: [\n        .target(name: "Widgets61", path: "Widgets/Extra"),\n')
        cases.append((
            "假绿 · `Package.swift` 新增生产 target 落面外 ⇒ 判红且点名「落在判据面外」",
            any("落在判据面外" in problem for problem in check(new_target)[0]),
        ))

        brand_new = fresh("brand-new-inside")
        (brand_new / APP_DIR / "Views" / "BrandNew61.swift").write_text("import SwiftUI\n", encoding="utf-8")
        cases.append((
            "对手臂 · 面内正常新增一份无关 `.swift` ⇒ 判绿（不误报）",
            not check(brand_new)[0],
        ))

        # ⑧⑨⑩⑪ 红/绿：空跑防护与「不误报」两头都要钉住
        no_srs_row = fresh("no-srs-row")
        (no_srs_row / SRS).write_text(
            "\n".join(item for item in read(no_srs_row / SRS).splitlines() if not item.startswith(f"| {SRS_ENTRY} |")),
            encoding="utf-8",
        )
        cases.append((f"{SRS} 的 `{SRS_ENTRY}` 条文被删", bool(check(no_srs_row)[0])))

        no_strip = fresh("no-strip")
        (no_strip / WORKSPACE_VIEWS[0]).unlink()
        cases.append(("工作区页签条文件被删", bool(check(no_strip)[0])))

        no_hld_line = fresh("no-hld-line")
        (no_hld_line / HLD).write_text(
            "\n".join(item for item in read(no_hld_line / HLD).splitlines() if HLD_CONTRACT_LINE not in item),
            encoding="utf-8",
        )
        cases.append((f"{HLD} 视图契约行被删", bool(check(no_hld_line)[0])))

        unrelated = fresh("unrelated")
        _patch(unrelated / "App/Views/AppearanceSheet.swift", "import SwiftUI", "import SwiftUI\n// 无关改动")
        cases.append(("绿对照：无关文件改动不误报", not check(unrelated)[0]))

        # 末例：真仓库逐字节未变 + 真仓库实跑绿
        after = {name: _sha(root / name) for name in WATCHED if (root / name).exists()}
        untouched = after == before
        real_problems, _ = check(root)
        cases.append(("末例：真仓库逐字节未变且实跑绿", untouched and not real_problems))

    passed = 0
    for name, ok in cases:
        print(f"{'✅' if ok else '❌'} {name}")
        passed += 1 if ok else 0
    ok = passed == len(cases)
    print(f"{'✅' if ok else '❌'} 负例自检：{len(cases)} 条中 {passed} 条达到预期")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
