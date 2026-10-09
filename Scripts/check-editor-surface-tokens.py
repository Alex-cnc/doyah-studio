#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""门禁：**编辑面（能编辑多行文本的那一块）的底色与字色只用主题令牌**
（队列 `L-142` 判据 · 内测清单 **甲2**，闭环第 6 项）。

由头 = 需求提出者 2026-09-30 内测原话：「**笔记的正文编辑区背景色明显不符合其他 2 个的配色方案**」
（`dist/Alpha1-内测清单-20260930.md` 甲2）。

**为什么设计令牌棘轮拦不住它**（这正是本条要补的覆盖面缺口）：
`Scripts/check-design-tokens.py` 扫的是**写坏的值**（裸颜色 / 裸字号 / 裸间距）——
而这里的问题是**什么都没写**：`TextEditor` 默认画系统的 `textBackgroundColor`，
于是同一个窗口里出现两种底（工作区是科技蓝、笔记是系统灰）。**门禁绿着、观感不对。**

判据（六组）：
    A **台账双向对账** —— `App/` 下每一处多行编辑面（`TextEditor(` / `NotesRichTextEditor(`）都必须在台账里登记；
      台账里登记的每一份文件也必须在盘上真的还有编辑面（**新加编辑面要登记**，
      不许悄悄多出一个「自己画底色」的编辑面）。
    B **每个编辑面都挂 `.editorSurface()`** —— 且处数棘轮（挂了的处数 == 编辑面的处数）。
    C **唯一出处** —— `func editorSurface()` 只许有一处定义，且必须在
      `App/Views/EditorSurface.swift`；它的函数体必须真的走令牌
      （`scrollContentBackground(.hidden)` + `Theme.surface(.content)` + `Theme.text(.primary)`），
      且**不许**出现裸色 / 系统色 / 字号字面量。
    D **另几个编辑面（AppKit `NSTextView`）** —— 工作区代码编辑器、数据库 SQL 编辑器与笔记正文
      富文本面（`App/Views/NotesRichTextEditor.swift`，片 `WY-1b1`）必须仍是
      「底色 = `Surface.content` / 字色 = `TextTone.primary`」，
      且**不许**退回系统底色（`NSColor.textBackgroundColor`）。
    E **空跑防护** —— 扫描面文件数 / 编辑面处数 / 台账条数三条下限 + 出处文件必须在位。
    F **反面：编辑面不许自己画底色** —— 视图里除了 `.editorSurface()` 之外，
      不许在编辑面的修饰链上写 `background(...)` 或 `scrollContentBackground(...)`。

用法：
    python3 Scripts/check-editor-surface-tokens.py                # 人读结论，失败非零退出
    python3 Scripts/check-editor-surface-tokens.py --json         # 机器读
    python3 Scripts/check-editor-surface-tokens.py --root <树>    # 负例验证用（临时副本）
    python3 Scripts/check-editor-surface-tokens.py --self-test    # 负例自检（临时副本上写坏）

判据自己的证据：`--self-test` **13 例**（红 / 绿成对，夹具一律在临时副本上，
末例核对真仓库逐字节未变 + 真仓库实跑绿）。
"""

from __future__ import annotations  # macOS 自带 python3 是 3.9，`X | None` 这类注解需要它

import argparse
import hashlib
import json
import pathlib
import shutil
import sys
import tempfile

BASE = pathlib.Path(__file__).resolve().parent.parent

APP_DIR = "App"
# 唯一出处：编辑面的底色 / 字色只在这里写一次。
SURFACE_DEFINITION = "App/Views/EditorSurface.swift"
SURFACE_FUNCTION = "func editorSurface()"
SURFACE_MODIFIER = ".editorSurface()"
SURFACE_BODY_TOKENS = (
    "scrollContentBackground(.hidden)",      # 先决条件：不把系统底色让出来，下面那层等于没画
    "background(Theme.surface(.content))",
    "foregroundStyle(Theme.text(.primary))",
)
SURFACE_BODY_FORBIDDEN = ("NSColor", "Color(", ".system(", "0x", "#")

# 多行编辑面的标识：SwiftUI 的 `TextEditor`（另几个是 AppKit `NSTextView`，见 APPKIT_SURFACES）。
# **2026-10-09（片 `WY-1b1`）**：笔记正文的编辑面从纯文本 `TextEditor` 换成富文本
# `NotesRichTextEditor`（`NSViewRepresentable` 包 `NotesTextView`）—— 它**仍是一处多行编辑面**，
# 于是加入标识集合（台账仍登记 `NotesPanel.swift`；`.`editorSurface()` 仍挂在它身上，
# 处数棘轮「挂了的处数 == 编辑面处数」保持相等）。这是一次**等量换位**，不是降门槛：
# `MIN_SURFACES` 一字未动。
EDITOR_TOKENS = (
    "TextEditor(",
    "NotesRichTextEditor(",
)
# 报错文案里点名用的可读形态（判据口径只用上面的元组）。
EDITOR_TOKENS_LABEL = " 或 ".join(EDITOR_TOKENS)
APPKIT_SURFACES = (
    "App/Views/CodeEditorView.swift",       # 工作区代码编辑器
    "App/Views/SQLEditorView.swift",        # 数据库 SQL 编辑器
    "App/Views/NotesRichTextEditor.swift",  # 笔记正文富文本面（片 `WY-1b1`）
)
APPKIT_REQUIRED = (
    "backgroundColor = Theme.nsColor(Surface.content)",
    "textColor = Theme.nsColor(TextTone.primary)",
)
APPKIT_FORBIDDEN = "NSColor.textBackgroundColor"

# 台账：`App/` 下带多行编辑面的文件（**双向对账**：新加编辑面必须登记，登记的必须真的还在）。
LEDGER = (
    "App/Views/AgentSQLPanel.swift",      # 智能体 SQL 结果（可编辑回写）
    "App/Views/DataTaskPanel.swift",      # 数据任务 · 定义（FR-AI-05）
    "App/Views/DataTaskSpecSheet.swift",  # 数据任务 · 规格输入
    "App/Views/DiagnosisPanel.swift",     # 诊断 · 语句 + 回答（两处）
    "App/Views/MaintenancePanel.swift",   # 维护 · 计划
    "App/Views/NotesPanel.swift",         # 笔记正文（内测 甲2 的正主）
)

MIN_APP_FILES = 90     # 实测 105（`App/` 下 `.swift`）
MIN_SURFACES = 7       # 实测 7 处多行编辑面（6 处 `TextEditor(` + 1 处 `NotesRichTextEditor(`，台账 6 份文件里）


def read(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8")


def rel(root: pathlib.Path, path: pathlib.Path) -> str:
    return path.relative_to(root).as_posix()


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


def is_comment(line: str) -> bool:
    """注释行（`//` / `///`）—— 出处文件的**用法示例**写在注释里，不能被当成真的编辑面。"""
    stripped = line.strip()
    return stripped.startswith("//") or stripped.startswith("*") or stripped.startswith("/*")


def surface_sites(text: str) -> list[int]:
    """多行编辑面的行号（从 1 起）。注释行不算（示例代码不是编辑面）。"""
    return [
        number for number, line in enumerate(text.splitlines(), 1)
        if any(token in line for token in EDITOR_TOKENS) and not is_comment(line)
    ]


def modifier_uses(text: str) -> int:
    """`.editorSurface()` 的**代码处数**（注释里的用法示例不算）。"""
    return sum(1 for line in text.splitlines() if SURFACE_MODIFIER in line and not is_comment(line))


def code_text(text: str) -> str:
    """剔掉注释行之后的源码（判据只看**代码**：注释里提到某个标识不算它还在用）。"""
    return "\n".join(line for line in text.splitlines() if not is_comment(line))


def carries_modifier(text: str, line_number: int) -> bool:
    """编辑面那一处**挂没挂** `.editorSurface()`：顺着修饰链往下看（到下一个编辑面 / 块尾为止）。"""
    lines = text.splitlines()
    for line in lines[line_number:min(line_number + 12, len(lines))]:
        if is_comment(line):
            continue
        if SURFACE_MODIFIER in line:
            return True
        stripped = line.strip()
        if any(token in line for token in EDITOR_TOKENS) or stripped.startswith("}") or stripped == "":
            return False
    return False


def check(root: pathlib.Path) -> tuple[list[str], list[str]]:
    problems: list[str] = []
    notes: list[str] = []
    sources = app_sources(root, problems)

    # ── A 台账双向对账 ──────────────────────────────────────────────────────
    # 唯一出处文件自己不算「编辑面」（它只定义写法；用法示例写在注释里，`surface_sites` 也不数注释行）。
    on_disk = {
        name: surface_sites(text) for name, text in sources.items()
        if name != SURFACE_DEFINITION and surface_sites(text)
    }
    for name in LEDGER:
        if name not in sources:
            problems.append(f"台账登记的编辑面 `{name}` 不在扫描面里 —— 文件被搬走 / 改名（台账陈旧）")
        elif name not in on_disk:
            problems.append(
                f"台账登记的编辑面 `{name}` 里找不到 `{EDITOR_TOKENS_LABEL}` —— 编辑面被搬走（台账陈旧）"
            )
    for name in sorted(on_disk):
        if name not in LEDGER:
            where = ", ".join(str(number) for number in on_disk[name])
            problems.append(
                f"`{name}`:{where} 出现 `{EDITOR_TOKENS_LABEL}` —— 这是个**没登记**的编辑面"
                "（新加编辑面要登记进本判据的台账，并挂 `.editorSurface()`）"
            )

    # ── B 每个编辑面都挂 `.editorSurface()` + 处数棘轮 ──────────────────────
    sites = 0
    wired = 0
    for name, numbers in sorted(on_disk.items()):
        text = sources[name]
        for number in numbers:
            sites += 1
            if carries_modifier(text, number):
                wired += 1
            else:
                problems.append(
                    f"`{name}`:{number} 的 `{EDITOR_TOKENS_LABEL}` 没挂 `{SURFACE_MODIFIER}`"
                    " —— 它会画系统底色（`textBackgroundColor`），与另两个编辑面对不上（内测 甲2）"
                )
    modifier_count = sum(modifier_uses(text) for text in sources.values())
    if modifier_count != sites:
        problems.append(
            f"`.editorSurface()` 用了 {modifier_count} 处，编辑面 {sites} 处 —— 两边的处数必须相等"
            "（多出来的是挂到了非编辑面上，少了的在上面逐处点名）"
        )
    if sites < MIN_SURFACES:
        problems.append(f"编辑面只有 {sites} 处（下限 {MIN_SURFACES}）—— 判据空转，不许通过")
    else:
        notes.append(f"编辑面 {sites} 处，全部挂了 `.editorSurface()`（台账 {len(LEDGER)} 份文件）")

    # ── C 唯一出处 ─────────────────────────────────────────────────────────
    if SURFACE_DEFINITION not in sources:
        problems.append(f"`{SURFACE_DEFINITION}` 不在扫描面里 —— 编辑面底色的唯一出处不见了")
    else:
        definition = sources[SURFACE_DEFINITION]
        if SURFACE_FUNCTION not in definition:
            problems.append(f"`{SURFACE_DEFINITION}` 里找不到 `{SURFACE_FUNCTION}` —— 出处被改名 / 被掏空")
        else:
            body = definition.split(SURFACE_FUNCTION, 1)[1]
            for token in SURFACE_BODY_TOKENS:
                if token not in body:
                    problems.append(f"`{SURFACE_DEFINITION}` 的函数体里缺 `{token}`（口径写歪了）")
            for token in SURFACE_BODY_FORBIDDEN:
                if token in body:
                    problems.append(
                        f"`{SURFACE_DEFINITION}` 的函数体里出现 `{token}` —— 出处自己写死值 / 走系统色"
                        "（令牌口径：底色 `Surface.content` / 字色 `TextTone.primary`）"
                    )
            else:
                notes.append(f"唯一出处 = `{SURFACE_DEFINITION}`（函数体三个令牌全在，无裸值）")
    for name, text in sorted(sources.items()):
        if name != SURFACE_DEFINITION and SURFACE_FUNCTION in text:
            problems.append(f"`{name}` 里也定义了 `{SURFACE_FUNCTION}` —— 编辑面底色只能有一处出处")

    # ── D 另两个编辑面（AppKit）─────────────────────────────────────────────
    for name in APPKIT_SURFACES:
        if name not in sources:
            problems.append(f"`{name}` 不在扫描面里 —— 这个编辑面的底色判据悬空了")
            continue
        text = code_text(sources[name])
        for token in APPKIT_REQUIRED:
            if token not in text:
                problems.append(f"`{name}` 里找不到 `{token}` —— 这个编辑面不再走令牌（与另两个对不上）")
        if APPKIT_FORBIDDEN in text:
            problems.append(f"`{name}` 里出现 `{APPKIT_FORBIDDEN}` —— 编辑面退回系统底色（内测 甲2 的原病）")
    if all(name in sources for name in APPKIT_SURFACES) and not any(
        APPKIT_FORBIDDEN in code_text(sources[name]) for name in APPKIT_SURFACES
    ):
        notes.append("AppKit 三个编辑面：底色 `Surface.content` / 字色 `TextTone.primary` 在位")

    # ── F 编辑面不许自己画底色（除唯一出处外）───────────────────────────────
    for name, numbers in sorted(on_disk.items()):
        text = sources[name]
        for number in numbers:
            chain = text.splitlines()[number:number + 12]
            for offset, line in enumerate(chain, 1):
                stripped = line.strip()
                if stripped.startswith("}"):
                    break
                if is_comment(line):
                    continue
                if ".background(" in stripped or "scrollContentBackground(" in stripped:
                    problems.append(
                        f"`{name}`:{number + offset} 在编辑面的修饰链上写 `{stripped}`"
                        " —— 底色只许由 `.editorSurface()` 给（唯一出处）"
                    )

    notes.append(f"扫描面 App/ {len(sources)} 个 `.swift`；台账 {len(LEDGER)} 份文件")
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
        print(f"\n❌ 编辑面底色 / 字色门禁未通过（{len(problems)} 项）：")
        for problem in problems:
            print(f"   - {problem}")
        return 1
    print(
        "\n✅ 编辑面的底色与字色只用主题令牌：每处多行编辑面都挂 `.editorSurface()` · "
        f"唯一出处 = `{SURFACE_DEFINITION}`（`Surface.content` / `TextTone.primary`）· "
        "AppKit 三个编辑面仍是令牌色 · 台账双向对账通过 · 判据面在位"
    )
    return 0


# ── 负例自检 ────────────────────────────────────────────────────────────────
#
# 纪律：一律在**临时副本**上写坏，末例核对真仓库逐字节未变。
# 每个负例都要问一句「这条改动如果真发生了，判据会不会当场报红」——
# 报不出来，这门禁就只是文档。

WATCHED = (
    SURFACE_DEFINITION,
    "App/Views/NotesPanel.swift",
    "App/Views/MaintenancePanel.swift",
    "App/Views/CodeEditorView.swift",
    "App/Views/SQLEditorView.swift",
    "App/Views/AppearanceSheet.swift",   # 无关文件：证明「改别的不会误报」
)


def _sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _fixture(destination: pathlib.Path, root: pathlib.Path) -> pathlib.Path:
    """把扫描面（`App/` 全部 `.swift`）复制成一份临时副本。"""
    source = root / APP_DIR
    for path in sorted(source.rglob("*")):
        if not path.is_file():
            continue
        target = destination / APP_DIR / path.relative_to(source)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
    return destination


def _patch(path: pathlib.Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise AssertionError(f"夹具写坏失败：`{old}` 不在 {path.name} 里")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def self_test(root: pathlib.Path) -> int:
    before = {name: _sha(root / name) for name in WATCHED if (root / name).exists()}
    cases: list[tuple[str, bool]] = []   # (名字, 期望报红)
    with tempfile.TemporaryDirectory(prefix="doyah-editor-surface-") as tmp:
        workspace = pathlib.Path(tmp)

        def fresh(name: str) -> pathlib.Path:
            return _fixture(workspace / name, root)

        # ① 绿：真仓库的副本，判据必须全过
        green = fresh("green")
        cases.append(("绿对照：真仓库副本应全过", not check(green)[0]))

        # ② 红：笔记正文那一处退回去（内测 甲2 的原病：编辑面画系统底色）
        unwired = fresh("notes-unwired")
        _patch(
            unwired / "App/Views/NotesPanel.swift",
            "                .editorSurface()\n",
            "",
        )
        cases.append(("笔记正文的编辑面退回系统底色", bool(check(unwired)[0])))

        # ③ 红：新加一个**没登记**的编辑面
        new_surface = fresh("new-surface")
        _patch(
            new_surface / "App/Views/AppearanceSheet.swift",
            "    var body: some View {",
            "    var body: some View {\n        TextEditor(text: .constant(\"\"))",
        )
        cases.append(("新加未登记的编辑面", bool(check(new_surface)[0])))

        # ④ 红：台账登记的文件里编辑面被搬走（陈旧台账）
        stale = fresh("stale-ledger")
        _patch(
            stale / "App/Views/MaintenancePanel.swift",
            "            TextEditor(text: $appState.maintenancePlanText)\n",
            "            Text(\"搬走了\")\n",
        )
        cases.append(("台账登记的编辑面被搬走", bool(check(stale)[0])))

        # ⑤ 红：唯一出处被改名
        renamed = fresh("renamed")
        _patch(
            renamed / SURFACE_DEFINITION,
            SURFACE_FUNCTION,
            "func editorSurfaceRenamed()",
        )
        cases.append(("唯一出处被改名", bool(check(renamed)[0])))

        # ⑥ 红：第二处定义（绕开唯一出处）
        duplicate = fresh("duplicate")
        _patch(
            duplicate / "App/Views/AppearanceSheet.swift",
            "    var body: some View {",
            "    func editorSurface() -> some View { self }\n\n    var body: some View {",
        )
        cases.append(("第二处定义 .editorSurface()", bool(check(duplicate)[0])))

        # ⑦ 红：出处自己写死裸色
        bare = fresh("bare-color")
        _patch(
            bare / SURFACE_DEFINITION,
            ".background(Theme.surface(.content))",
            ".background(Color.gray)",
        )
        cases.append(("出处里把底色换成裸色", bool(check(bare)[0])))

        # ⑧ 红：出处把系统底色那层让位那一步删掉（画了等于没画）
        no_hidden = fresh("no-hidden")
        _patch(
            no_hidden / SURFACE_DEFINITION,
            "            .scrollContentBackground(.hidden)\n",
            "",
        )
        cases.append(("出处缺 scrollContentBackground(.hidden)", bool(check(no_hidden)[0])))

        # ⑨⑩ 红：AppKit 那两个编辑面不再走令牌 / 退回系统底色
        appkit = fresh("appkit-notoken")
        _patch(
            appkit / "App/Views/SQLEditorView.swift",
            "        textView.backgroundColor = Theme.nsColor(Surface.content)",
            "        textView.backgroundColor = NSColor.textBackgroundColor",
        )
        cases.append(("SQL 编辑器退回系统底色", bool(check(appkit)[0])))

        workspace_editor = fresh("workspace-editor-notoken")
        _patch(
            workspace_editor / "App/Views/CodeEditorView.swift",
            "        textView.textColor = Theme.nsColor(TextTone.primary)",
            "        textView.textColor = .labelColor",
        )
        cases.append(("工作区编辑器字色不再走令牌", bool(check(workspace_editor)[0])))

        # ⑪ 红：编辑面自己画底色（绕开唯一出处）
        self_paint = fresh("self-paint")
        _patch(
            self_paint / "App/Views/NotesPanel.swift",
            "                .editorSurface()\n",
            "                .editorSurface()\n                .background(Color.orange)\n",
        )
        cases.append(("编辑面自己再画一层底色", bool(check(self_paint)[0])))

        # ⑫ 绿：无关文件改动不误报 + 末例
        unrelated = fresh("unrelated")
        _patch(unrelated / "App/Views/AppearanceSheet.swift", "import SwiftUI", "import SwiftUI\n// 无关改动")
        cases.append(("绿对照：无关文件改动不误报", not check(unrelated)[0]))

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
