#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""负例：`Scripts/check-note-search-route.py`（界面检索口径门禁）**红得出来吗**。

**为什么单开一个脚本**：门禁绿着只能说明「现在没违规」，**不能**说明它看得见违规 ——
本工程已经栽过三次（L-04「失败只记进没人读的变量」、L-05「断言被删也照绿」、
第 14 项「删掉两处出口里的一处仍能顶数」），所以每条新门禁都配一组负例：
**写坏 → 必须报红 → 点名哪一处**。

这条门禁尤其需要负例：真仓库现在**每一条路都配了文案**、**界面只有一处检索调用**，
「绿」这个结果本身分不清「真的都对」还是「扫了个寂寞」。

**做法**：不改真仓库的文件，把**必要的那几个文件**拷进临时目录，在副本上写坏、
把门禁指过去（`--root`）。跑完断言真仓库一个字节没动。

用法：`python3 Scripts/test-note-search-route.py`
"""

import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GATE = "Scripts/check-note-search-route.py"
LEDGER = "Scripts/note-search-route.json"

# 副本需要的最小文件集（门禁会读：路线枚举 / 映射 / 语言表 / 界面状态 / 视图目录 / 台账 /
# `Package.swift` —— 判据的生产面靠它现读）
TREE_FILES = [
    "Plugins/Notes/Sources/NoteStorage/NoteDatabase.swift",
    "Plugins/Notes/Sources/NoteStorage/NoteSearchDisclosure.swift",
    "Core/Localization.swift",
    "App/AppState.swift",
    "Plugins/Notes/Views/NotesPanel.swift",
    "Tests/NoteTests.swift",
    "Package.swift",
    GATE,
    LEDGER,
]

# 生产面（`Package.swift` 现读得到的生产 target 目录）在副本里也要**真的存在** ——
# 判据会点名「生产目录不存在」，夹具不铺齐就成假红。
PRODUCTION_STUBS = {
    "Core": "夹具：生产面占位（真文件是 `Core/Localization.swift`）",
    "App": "夹具：生产面占位（真文件是 `App/AppState.swift`）",
    "Platform/macOS": "夹具：生产面占位（样本 60 ㈥ 的第二条检索路就落在这一面）",
    "CLI": "夹具：生产面占位",
    "Tools/LicenseTool": "夹具：生产面占位",
    "Plugins/Notes/Sources": "夹具：生产面占位",
    "Plugins/Notes/Views": "夹具：生产面占位（真文件是 `Plugins/Notes/Views/NotesPanel.swift`）",
}
# 登记的面外根（判据要求它存在、且不是生产目录）
OUTSIDE_STUBS = {"Vendor": "夹具：登记的面外根占位"}

passed: list[str] = []
failed: list[str] = []


def record(ok: bool, label: str, detail: str = "") -> None:
    (passed if ok else failed).append(label)
    print(f"  {'✅' if ok else '❌'} {label}" + (f"  —— {detail}" if detail and not ok else ""))


def make_tree() -> Path:
    tree = Path(tempfile.mkdtemp(prefix="doyah-note-search-"))
    for rel in TREE_FILES:
        destination = tree / rel
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / rel, destination)
    for base, why in PRODUCTION_STUBS.items():
        (tree / base).mkdir(parents=True, exist_ok=True)
        (tree / base / "FixtureS60.swift").write_text(f"// {why}\n", encoding="utf-8")
    for base, why in OUTSIDE_STUBS.items():
        (tree / base).mkdir(parents=True, exist_ok=True)
        (tree / base / "PROVENANCE.fixture.md").write_text(f"{why}\n", encoding="utf-8")
    return tree


def append(tree: Path, rel: str, text: str) -> None:
    path = tree / rel
    path.write_text(path.read_text(encoding="utf-8") + text, encoding="utf-8")


def write(tree: Path, rel: str, text: str) -> None:
    path = tree / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")



def run(tree: Path) -> tuple[int, str]:
    result = subprocess.run(
        [sys.executable, GATE, "--root", str(tree)],
        cwd=tree,
        capture_output=True,
        text=True,
    )
    return result.returncode, result.stdout + result.stderr


def edit(tree: Path, rel: str, old: str, new: str, count: int = 1) -> None:
    path = tree / rel
    text = path.read_text(encoding="utf-8")
    assert old in text, f"夹具前提不成立：{rel} 里找不到 {old!r}"
    path.write_text(text.replace(old, new, count), encoding="utf-8")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    print("负例：界面检索口径门禁（Scripts/check-note-search-route.py）")
    before = {rel: digest(ROOT / rel) for rel in TREE_FILES}

    # 0) 基线：未改动的副本必须**绿**（否则下面每一条「红」都没有意义）
    tree = make_tree()
    code, output = run(tree)
    record(code == 0, "基线（未改动的副本）判绿", output.strip()[-400:])

    # 1) 生产点消失（界面退回内存过滤的形状）
    tree = make_tree()
    edit(tree, "App/AppState.swift", "let result = try await NoteLibrary.defaultLibrary().search(trimmed)", "let result = NoteDatabase.SearchResult(route: .substring, notes: [])")
    code, output = run(tree)
    record(code != 0 and "命中 0 处" in output, "界面检索生产点被拿掉 ⇒ 判红", output.strip()[-300:])

    # 2) 多出第二条检索路
    tree = make_tree()
    edit(
        tree,
        "App/AppState.swift",
        "func searchNotes() async {",
        "func searchAgain() async { _ = try? await NoteLibrary.defaultLibrary().search(notesQuery) }\n\n    func searchNotes() async {",
    )
    code, output = run(tree)
    record(code != 0 and "命中" in output, "出现第二条检索路 ⇒ 判红", output.strip()[-300:])

    # 3) 视图自己过滤（点名 文件:行号）
    tree = make_tree()
    edit(
        tree,
        "Plugins/Notes/Views/NotesPanel.swift",
        "        .padding(.vertical, Spacing.s)",
        "        .padding(.vertical, Spacing.s)\n        .onChange(of: appState.notesQuery) { _, _ in _ = NoteSearch.match(appState.notes, query: appState.notesQuery) }",
    )
    code, output = run(tree)
    record(
        code != 0 and "Plugins/Notes/Views/NotesPanel.swift:" in output and "内存过滤" in output,
        "视图里出现内存过滤 ⇒ 判红并点名行号",
        output.strip()[-300:],
    )

    # 4) 实现与台账不一致（把子串路的交代偷偷改成「不必说」）
    tree = make_tree()
    edit(tree, "Plugins/Notes/Sources/NoteStorage/NoteSearchDisclosure.swift", "return .noteSearchSubstring", "return nil")
    code, output = run(tree)
    record(code != 0 and "两边必须逐条相等" in output, "实现改了、台账没跟 ⇒ 判红", output.strip()[-300:])

    # 5) 新增一条路线却没登记（穷尽性被破坏时也要红）
    tree = make_tree()
    edit(
        tree,
        "Plugins/Notes/Sources/NoteStorage/NoteDatabase.swift",
        "            case substring",
        "            case substring\n            /// 夹具：新增一条没登记的路线\n            case scratchRoute",
    )
    code, output = run(tree)
    record(code != 0 and "scratchRoute" in output, "新增路线没登记处置 ⇒ 判红", output.strip()[-300:])

    # 6) 语言表里缺一条中文（键在、文案不在）
    tree = make_tree()
    edit(
        tree,
        "Core/Localization.swift",
        ".noteSearchSubstring: [.simplifiedChinese: \"这次是子串匹配（全文检索需要 3 个字以上，或这一次没命中）\", .english:",
        ".noteSearchSubstring: [.english:",
    )
    code, output = run(tree)
    record(code != 0 and "simplifiedChinese" in output, "语言表缺中文 ⇒ 判红", output.strip()[-300:])

    # 7) 失败那一句成了死键（语言表里有、没人引用）
    tree = make_tree()
    edit(tree, "App/AppState.swift", "return L(.noteSearchUnavailable, failure)", "return failure")
    code, output = run(tree)
    record(code != 0 and "死键" in output, "「检索没跑成」没人引用 ⇒ 判红（死键）", output.strip()[-300:])

    # 8) 空跑防护：路线枚举一条都解析不到
    tree = make_tree()
    edit(tree, "Plugins/Notes/Sources/NoteStorage/NoteDatabase.swift", "public enum Route: String, Equatable, Sendable {", "public enum RouteX: String, Equatable, Sendable {")
    code, output = run(tree)
    record(code != 0 and "空跑不许通过" in output, "解析不到 `Route` 枚举 ⇒ 判红（空跑不许通过）", output.strip()[-300:])

    # 9) 空跑防护：台账 routes 清空
    tree = make_tree()
    ledger_path = tree / LEDGER
    payload = json.loads(ledger_path.read_text(encoding="utf-8"))
    payload["routes"] = []
    ledger_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    code, output = run(tree)
    record(code != 0 and "空跑不许通过" in output, "台账 `routes` 清空 ⇒ 判红（空跑不许通过）", output.strip()[-300:])

    # 10) 唯一落地出口里的词比对被删掉（迟到结果会覆盖新的 —— 「键盘快打」那一行）
    tree = make_tree()
    edit(
        tree,
        "App/AppState.swift",
        "        guard query == notesQuery else { return false }",
        "        _ = query   // 夹具：判断不在了",
    )
    code, output = run(tree)
    record(
        code != 0 and "落地出口里没有" in output,
        "落地出口里的词比对被删 ⇒ 判红（迟到的结果会覆盖新的）",
        output.strip()[-300:],
    )

    # 11) 一条分支绕过唯一出口（catch 那支自己落地）
    tree = make_tree()
    edit(
        tree,
        "App/AppState.swift",
        "            settleNoteSearch(.failure(String(describing: error)), for: query)",
        "            noteSearchState = .unavailable(failure: String(describing: error))",
    )
    code, output = run(tree)
    record(
        code != 0 and ("绕过" in output or "绕开了判断" in output),
        "有一条分支绕过唯一出口 ⇒ 判红（点名哪一处）",
        output.strip()[-300:],
    )

    # 12) 落地形状多出一处（又开了一个绕开判断的入口）
    tree = make_tree()
    edit(
        tree,
        "App/AppState.swift",
        "    func searchNotes() async {",
        "    func searchShortcut() async {\n"
        "        noteSearchState = .library(route: .substring, notes: [])\n"
        "    }\n\n    func searchNotes() async {",
    )
    code, output = run(tree)
    record(
        code != 0 and "绕开了判断" in output,
        "落地形状多出一处（第二个入口）⇒ 判红",
        output.strip()[-300:],
    )

    # 13) 查库那一步又去读搜索框（「这一次是哪个词的」判不动了）
    tree = make_tree()
    edit(
        tree,
        "App/AppState.swift",
        "    func runSearch(_ trimmed: String, for query: String) async {",
        "    func runSearch(_ trimmed: String, for query: String) async {\n"
        "        let query = notesQuery   // 夹具：又去读搜索框",
    )
    code, output = run(tree)
    record(
        code != 0 and "读了本类属性" in output,
        "查库那一步又读搜索框 ⇒ 判红",
        output.strip()[-300:],
    )

    # 15) 新路线写成**逗号列表**也没登记（样本 60 ㈠：早先只取 `case` 后第一个名字 ⇒ 无声加入）
    tree = make_tree()
    edit(tree, "Plugins/Notes/Sources/NoteStorage/NoteDatabase.swift", "            case substring", "            case substring, fuzzy")
    code, output = run(tree)
    record(code != 0 and "fuzzy" in output, "新路线写在 `case a, b` 逗号列表里 ⇒ 判红并点名 `fuzzy`", output.strip()[-300:])

    # 16) 搜索框**改名**后仍被查库那一步读（样本 60 ㈡：早先写死 `notesQuery` ⇒ 改名即失明）
    tree = make_tree()
    edit(tree, "App/AppState.swift", '@Published var notesQuery = ""', '@Published var notesQuery = ""\n    @Published var notesSearchText = ""')
    edit(tree, "App/AppState.swift", "    func runSearch(_ trimmed: String, for query: String) async {", "    func runSearch(_ trimmed: String, for query: String) async {\n        let box = notesSearchText   // 夹具：改名后的搜索框")
    code, output = run(tree)
    record(code != 0 and "notesSearchText" in output, "查库那一步读了改名后的搜索框属性 ⇒ 判红（与界面属性机械对账）", output.strip()[-300:])

    # 17) 假阳 · 块注释里出现内存过滤（样本 60 ㈢ B：早先只剥 `//`）
    tree = make_tree()
    append(tree, "Plugins/Notes/Views/NotesPanel.swift", "\n/* 夹具：这只是说明文字 —— NoteSearch.match( 那一套已废弃 */\n")
    code, output = run(tree)
    record(code == 0, "视图里只有**块注释**提到内存过滤 ⇒ 判绿（假阳已修）", output.strip()[-300:])

    # 18) 假阳 · 字符串字面量里出现内存过滤
    tree = make_tree()
    append(tree, "Plugins/Notes/Views/NotesPanel.swift", '\nprivate let fixtureLegacyNote = "NoteSearch.match( 已废弃"\n')
    code, output = run(tree)
    record(code == 0, "视图里只有**字符串字面量**提到内存过滤 ⇒ 判绿（假阳已修）", output.strip()[-300:])

    # 19) 假绿 · 删掉真引用、只留一行注释提键名（样本 60 ㈣）
    tree = make_tree()
    edit(tree, "App/AppState.swift", "return L(.noteSearchUnavailable, failure)", "return failure   // 夹具：.noteSearchUnavailable 待恢复")
    code, output = run(tree)
    record(code != 0 and "死键" in output, "真引用删了、只留注释提键名 ⇒ 判红（死键 / 注释不算引用）", output.strip()[-300:])

    # 20) 假红 · 受检键改成**多行条目**（样本 60 ㈤：真仓 29 条多行条目早先在面外）
    tree = make_tree()
    localization = tree / "Core/Localization.swift"
    text = localization.read_text(encoding="utf-8")
    single = re.search(r"^\s*\.noteSearchSubstring:\s*\[(.*)\],\s*$", text, re.M)
    assert single, "夹具前提不成立：找不到 .noteSearchSubstring 单行条目"
    chinese = re.search(r'\.simplifiedChinese:\s*"((?:[^"\\]|\\.)*)"', single.group(1))
    english = re.search(r'\.english:\s*"((?:[^"\\]|\\.)*)"', single.group(1))
    assert chinese and english, "夹具前提不成立：条目里中英文案缺一"
    multi = (
        "        .noteSearchSubstring: [\n"
        f'            .simplifiedChinese: "{chinese.group(1)}",\n'
        f'            .english: "{english.group(1)}",\n'
        "        ],"
    )
    localization.write_text(text.replace(single.group(0), multi), encoding="utf-8")
    code, output = run(tree)
    record(code == 0, "受检键写成**多行条目** ⇒ 判绿（假红已修；多行条目进面）", output.strip()[-300:])

    # 21) 面 · 第二条检索路落在 `Platform/macOS`（样本 60 ㈥ C：早先面写死 `App/`）
    tree = make_tree()
    write(tree, "Platform/macOS/FixtureS60Route.swift", '// 夹具：面外的第二条检索路\nfunc fixtureS60Route() async {\n    _ = try? await NoteLibrary.defaultLibrary().search("x")\n}\n')
    code, output = run(tree)
    record(code != 0 and "Platform/macOS/FixtureS60Route.swift" in output, "生产面里 `Platform/macOS` 出现第二条检索路 ⇒ 判红（面按 `Package.swift` 现读）", output.strip()[-300:])

    # 22) 面 · 内存检索在 `Core/` 长出调用（早先只扫 `App/` + `Tests/`）
    tree = make_tree()
    write(tree, "Core/FixtureS60Match.swift", '// 夹具：生产面里的内存检索调用\nlet fixtureS60Match = NoteSearch.match([], query: "")\n')
    code, output = run(tree)
    record(code != 0 and "Core/FixtureS60Match.swift" in output, "`Core/` 里出现内存检索调用 ⇒ 判红（面改生产面）", output.strip()[-300:])

    # 23) 对手臂 · 面内新增一份无关文件不许误报
    tree = make_tree()
    write(tree, "App/Views/FixtureS60Unrelated.swift", "// 夹具：与检索无关的新文件\nlet fixtureS60Unrelated = 1\n")
    code, output = run(tree)
    record(code == 0, "面内新增无关文件 ⇒ 判绿（对手臂：不误报）", output.strip()[-300:])

    # 24) 对手臂 · 逗号列表里的第二个名字**已登记** ⇒ 不误报
    tree = make_tree()
    edit(tree, "Plugins/Notes/Sources/NoteStorage/NoteDatabase.swift", "            case substring", "            case substring, fullText")
    code, output = run(tree)
    record(code == 0, "逗号列表里的名字都已登记 ⇒ 判绿（对手臂：解出第二个名字也不误报）", output.strip()[-300:])

    # 25) 反向臂 · 生产面被缩小（删掉一个生产 target ⇒ 面低于下限）
    tree = make_tree()
    manifest = tree / "Package.swift"
    text = manifest.read_text(encoding="utf-8")
    target = re.search(r'\n\s*\.executableTarget\(\s*\n\s*name: "DoyahCLI".*?path: "CLI"\s*\n\s*\),', text, re.S)
    assert target, "夹具前提不成立：找不到 DoyahCLI target"
    manifest.write_text(text.replace(target.group(0), ""), encoding="utf-8")
    code, output = run(tree)
    record(code != 0 and "生产面只有" in output, "删掉一个生产 target ⇒ 判红（面被缩小 / 低于下限）", output.strip()[-300:])

    # 14) 主仓库一个字节没动
    after = {rel: digest(ROOT / rel) for rel in TREE_FILES}
    record(before == after, "跑完核对真仓库逐字节未变", "被改动的文件：" + "、".join(k for k in before if before[k] != after[k]))

    print(f"\n结果：{len(passed)} 通过 / {len(failed)} 未达预期")
    if failed:
        for label in failed:
            print(f"  ❌ {label}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
