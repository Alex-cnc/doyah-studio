#!/usr/bin/env python3
"""终端多会话（页签）的 **Core 侧**判据（队列 L-84 ㈠，闭环第 9 项）。

存在的理由（真现场）
--------------------
需求提出者 2026-09-29 把「底部 terminal 只支持单终端」提为**刚需**，原话：「一个 terminal 在执行
dsh-tui，遇到要执行命令只能去开系统终端，**违背了我这个软件的初衷**」。多会话的坑几乎全在
**顺序与归属**上 —— 新页签插在哪、关掉当前页签谁接管、⌘1…9 落到哪个会话、重命名之后标题怎么
回落、最后一个页签能不能关 —— 而这几件事**不需要真开一个 shell 就能穷举**，所以判据判的是
「这些判断真的在 Core 里、且被单测逐组钉住」，不是「界面上看起来有页签」。

判据（任一不过即失败）
----------------------
A. **Core 模型在位**：`Core/TerminalTabs.swift` 每个 API 锚点在盘上（逐条正则，少一条点名），
   且**五个行为组**（新建 / 关闭 / 切换 / 标题推导 / 关闭确认）各自的方法一个不少。
B. **Core 不出用户可见文案**：该文件的**代码行**里不许出现中文字面量（R-45：人话走语言表）。
C. **文案键中英都在**：页签那一族键逐个在 `Core/Localization.swift` 的语言表里同时有简中与英文
   （少一个 = 英文界面掉回中文）。
D. **单测逐组钉住**：`Tests/TerminalTabsTests.swift` 里五个行为组的用例锚点必须在，且用例总数
   不低于下限（防「测试文件被掏空」）。
E. **口径锚点**：需求提出者的原话场景（一个页签跑 `dsh-tui`、另一个执行命令）在
   `Docs/发布计划.md` 与队列 `L-84` 行里都在（口径被删 = 判据失去依据）。

边界（如实登记）：本判据**不判界面** —— 工具条左侧 tab 头、⌘T/⌘W/⌘1…9、双击重命名、二次确认
弹窗、「已退出」标记那一半在 **㈡（App 接线）** 落，落完把界面锚点并进本判据。真正的行为证据是
`Tests/TerminalTabsTests.swift`（Core 纯逻辑穷举）+ 真人点验（主诉场景：一个页签跑 `dsh-tui`、
另一个执行命令，互不干扰）。

判据自己的证据：`--self-test` **7 例**（红 / 绿成对；夹具一律在临时目录；末例核对真仓库五份文件
逐字节未变）。

用法：
    python3 Scripts/check-terminal-tabs.py              # 校验（闭环第 9 项）
    python3 Scripts/check-terminal-tabs.py --self-test  # 门禁自己的证据（**7 例**）
"""

from __future__ import annotations

import hashlib
import pathlib
import re
import shutil
import sys
import tempfile

MODEL = "Core/TerminalTabs.swift"
TABLE = "Core/Localization.swift"
TESTS = "Tests/TerminalTabsTests.swift"
PLAN = "Docs/发布计划.md"
QUEUE = "Docs/design/开发循环-任务队列.md"

# A：模型锚点。分五组，与 `FR-EDIT-29` 的判据逐条对应 —— 少一组就等于那条判据悬空。
API_ANCHORS = {
    "新建": ["public mutating func newTab"],
    "关闭": ["public func closeDecision", "public mutating func close(id: Int)"],
    "切换": ["public mutating func select(id:", "public mutating func select(numbered",
             "public mutating func selectNext()", "public mutating func selectPrevious()"],
    "标题推导": ["public static func derive(fromExecutablePath", "public static func sanitize(",
                 "public var title: String?", "static let ellipsis"],
    "关闭确认": ["case needsConfirmation", "case canClose", "case lastTab", "case unknownTab",
                 "public var isShellInForeground"],
}

# D：单测锚点（每条一个行为组；用例总数下限）。
TEST_ANCHORS = {
    "新建": "testNewTabInsertsRightOfActiveAndActivatesIt",
    "关闭": "testCloseActiveTabHandsOverToRightNeighbour",
    "切换": "testSelectNextAndPreviousWrapAround",
    "标题推导": "testDeriveTitleStripsLoginShellDash",
    "关闭确认": "testCloseDecisionNeedsConfirmationForRunningProgram",
}
TEST_FLOOR = 24

# C：页签那一族文案键（㈠ 只登记，㈡ 界面直接用）。
KEYS = [
    "terminalTabNew", "terminalTabClose", "terminalTabRename", "terminalTabExited",
    "terminalTabUntitled", "terminalTabCloseConfirmTitle", "terminalTabCloseConfirmMessage",
    "terminalTabCloseConfirmAction",
]

# E：口径锚点（需求提出者的原话场景 —— 判据的立足点）。
PLAN_ANCHOR = r"一个页签跑\s*`?dsh-tui`?[^\n]{0,60}另一个页签执行命令"
QUEUE_ANCHOR = r"\*\*L-84\*\*[^\n]{0,400}tab 头切换"

HAN = re.compile(r"[\u4e00-\u9fff]")
STRING_LITERAL = re.compile(r'"([^"\\]*(?:\\.[^"\\]*)*)"')


class Issue:
    def __init__(self, where: str, reason: str) -> None:
        self.where = where
        self.reason = reason

    def __str__(self) -> str:  # pragma: no cover - 只为打印
        return f"❌ {self.where}：{self.reason}"


def _read(root: pathlib.Path, relative: str) -> str:
    path = root / relative
    return path.read_text(encoding="utf-8") if path.is_file() else ""


def code_lines(text: str) -> list[tuple[int, str]]:
    """只留代码行（`//` 注释不算 —— 注释里必然有中文）。"""
    return [(number, line) for number, line in enumerate(text.splitlines(), 1)
            if not line.strip().startswith("//")]


def check_model(root: pathlib.Path) -> tuple[list[Issue], int]:
    """A + B：模型 API 锚点 + 「Core 不出用户可见文案」。"""
    issues: list[Issue] = []
    model = _read(root, MODEL)
    if not model.strip():
        return [Issue(MODEL, "模型文件不在盘上（判据取不到输入，不许当通过）")], 0
    sites = 0
    for group, anchors in API_ANCHORS.items():
        for anchor in anchors:
            if anchor not in model:
                issues.append(Issue(f"{MODEL}[{group}]", f"缺 API 锚点 `{anchor}`"))
            else:
                sites += 1
    for number, line in code_lines(model):
        for literal in STRING_LITERAL.findall(line):
            if HAN.search(literal):
                issues.append(Issue(
                    f"{MODEL}:{number}",
                    f"代码行里有中文字面量「{literal}」—— Core 只出逻辑，人话走语言表（R-45）",
                ))
                break
    return issues, sites


def check_keys(root: pathlib.Path) -> tuple[list[Issue], int]:
    """C：页签那一族键在语言表里中英都在。"""
    issues: list[Issue] = []
    table = _read(root, TABLE)
    if not table.strip():
        return [Issue(TABLE, "语言表不在盘上")], 0
    complete = 0
    for key in KEYS:
        site = re.search(r"\." + re.escape(key) + r":\s*\[(.*?)\]", table)
        if site is None:
            issues.append(Issue(TABLE, f"语言表里没有 `.{key}`"))
            continue
        body = site.group(1)
        missing = [name for name, token in (("简中", ".simplifiedChinese"), ("英文", ".english"))
                   if token not in body]
        if missing:
            issues.append(Issue(f"{TABLE}::.{key}", f"缺{'/'.join(missing)}译文（英文界面会掉回中文）"))
        else:
            complete += 1
    return issues, complete


def check_tests(root: pathlib.Path) -> tuple[list[Issue], int]:
    """D：五个行为组各自的用例锚点 + 用例总数下限。"""
    issues: list[Issue] = []
    tests = _read(root, TESTS)
    if not tests.strip():
        return [Issue(TESTS, "单测文件不在盘上（判据取不到输入，不许当通过）")], 0
    for group, anchor in TEST_ANCHORS.items():
        if anchor not in tests:
            issues.append(Issue(f"{TESTS}[{group}]", f"缺用例锚点 `{anchor}`（这一组的判据悬空了）"))
    count = len(re.findall(r"func test", tests))
    if count < TEST_FLOOR:
        issues.append(Issue(TESTS, f"用例只有 {count} 个、下限 {TEST_FLOOR} —— 测试被掏空了"))
    return issues, count


def check_docs(root: pathlib.Path) -> tuple[list[Issue], int]:
    """E：口径锚点（需求提出者的原话场景 —— 判据的立足点）。"""
    issues: list[Issue] = []
    hits = 0
    for relative, pattern, note in (
        (PLAN, PLAN_ANCHOR, "发布计划的验收场景表"),
        (QUEUE, QUEUE_ANCHOR, "队列 L-84 行的需求原话"),
    ):
        text = _read(root, relative)
        if not text.strip():
            issues.append(Issue(relative, "文档不在盘上"))
            continue
        if re.search(pattern, text):
            hits += 1
        else:
            issues.append(Issue(relative, f"{note}里的口径被删了（判据失去立足点）"))
    return issues, hits


def run(root: pathlib.Path) -> tuple[list[Issue], dict[str, int]]:
    issues: list[Issue] = []
    stats: dict[str, int] = {}

    model_issues, api_sites = check_model(root)
    issues += model_issues
    stats["apiSites"] = api_sites

    key_issues, complete_keys = check_keys(root)
    issues += key_issues
    stats["keys"] = complete_keys

    test_issues, tests = check_tests(root)
    issues += test_issues
    stats["tests"] = tests

    doc_issues, doc_hits = check_docs(root)
    issues += doc_issues
    stats["docHits"] = doc_hits

    # F：空跑防护 —— 「判据自己失效」比「发现不了」更危险。
    expected_api = sum(len(group) for group in API_ANCHORS.values())
    if stats["apiSites"] < expected_api:
        issues.append(Issue("空跑防护", f"API 锚点只命中 {stats['apiSites']}/{expected_api} 处"))
    if stats["keys"] < len(KEYS):
        issues.append(Issue("空跑防护", f"文案键只有 {stats['keys']}/{len(KEYS)} 个中英齐"))
    if stats["docHits"] < 2:
        issues.append(Issue("空跑防护", f"口径锚点只命中 {stats['docHits']}/2 处"))
    return issues, stats


FIXTURE_FILES = [MODEL, TABLE, TESTS, PLAN, QUEUE]


def _digests(root: pathlib.Path) -> dict[str, str]:
    return {relative: hashlib.sha256((root / relative).read_bytes()).hexdigest()
            for relative in FIXTURE_FILES}


def _fixture(base: pathlib.Path) -> pathlib.Path:
    """把判据盯着的五份文件原样拷进临时目录（**只在副本上写坏**）。"""
    temp = pathlib.Path(tempfile.mkdtemp(prefix="terminal-tabs-selftest-"))
    for relative in FIXTURE_FILES:
        target = temp / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(base / relative, target)
    return temp


def _rewrite(path: pathlib.Path, old: str, new: str) -> bool:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        return False
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    return True


def self_test(root: pathlib.Path) -> int:
    results: list[tuple[bool, str, str]] = []

    def record(ok: bool, label: str, detail: str = "") -> None:
        results.append((ok, label, detail))

    before = _digests(root)

    # 例 1（绿路 · 基线）：真仓库现在必须是通过的 —— 连绿路都不绿，下面几条谈不上有意义。
    issues, _ = run(root)
    record(not issues, "例 1（绿路基线）真仓库判据通过",
           "；".join(str(issue) for issue in issues[:3]))

    # 例 2（A · 红路）：拿掉一个 API 锚点 ⇒ 点名报红。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / MODEL, "public mutating func select(numbered", "public mutating func selectNumbered")
    issues, _ = run(with_fixture)
    record(any("select(numbered" in str(issue) for issue in issues),
           "例 2（A）API 锚点被拿掉 ⇒ 报红并点名", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 3（B · 红路）：Core 代码行里塞一句中文字面量 ⇒ 报红。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / MODEL, "public enum TerminalTabTitle {", 'public enum TerminalTabTitle {\n    static let bad = "终端"')
    issues, _ = run(with_fixture)
    record(any("中文字面量" in str(issue) for issue in issues),
           "例 3（B）Core 代码行出现中文字面量 ⇒ 报红", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 4（C · 红路）：语言表里删掉英文译文 ⇒ 报红（英文界面会掉回中文）。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / TABLE, '.terminalTabExited: [.simplifiedChinese: "已退出", .english: "Exited"]',
             '.terminalTabExited: [.simplifiedChinese: "已退出"]')
    issues, _ = run(with_fixture)
    record(any("缺英文" in str(issue) for issue in issues),
           "例 4（C）语言表缺英文译文 ⇒ 报红", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 5（D · 红路）：单测里一个行为组的锚点被改名 ⇒ 报红。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / TESTS, "func testDeriveTitleStripsLoginShellDash", "func testTitleDerivation")
    issues, _ = run(with_fixture)
    record(any("testDeriveTitleStripsLoginShellDash" in str(issue) for issue in issues),
           "例 5（D）行为组的用例锚点被改名 ⇒ 报红", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 6（E · 红路）：口径被删（队列 L-84 行里的需求原话被改写）⇒ 报红。
    with_fixture = _fixture(root)
    _rewrite(with_fixture / QUEUE, "tab 头切换", "页签切换")
    issues, _ = run(with_fixture)
    record(any("口径被删" in str(issue) for issue in issues),
           "例 6（E）队列里的需求原话被改写 ⇒ 报红", "；".join(str(issue) for issue in issues[:3]))
    shutil.rmtree(with_fixture, ignore_errors=True)

    # 例 7（反过来核一遍）：所有写坏都发生在副本上 —— 真仓库五份文件必须逐字节未变。
    after = _digests(root)
    record(before == after, "例 7 真仓库五份文件逐字节未变",
           "；".join(f"{name} 变了" for name in after if before[name] != after[name]))

    for ok, label, detail in results:
        print(f"{'✅' if ok else '❌'} {label}" + (f" —— {detail}" if detail and not ok else ""))
    failed = [label for ok, label, _ in results if not ok]
    if failed:
        print(f"❌ 自测失败：{len(failed)}/{len(results)} 例（{failed[0]} …）")
        return 1
    print(f"自测通过（{len(results)} 例）")
    return 0


def main(argv: list[str]) -> int:
    root = pathlib.Path(__file__).resolve().parent.parent
    if "--root" in argv:
        root = pathlib.Path(argv[argv.index("--root") + 1]).resolve()
    if "--self-test" in argv:
        return self_test(root)

    issues, stats = run(root)
    if issues:
        for issue in issues:
            print(issue)
        print(f"❌ 终端多会话（页签）Core 侧判据不通过：{len(issues)} 条")
        return 1
    print(
        "✅ 终端多会话（页签）Core 侧判据通过："
        f"API 锚点 {stats['apiSites']} 处 / 文案键 {stats['keys']} 个（中英齐）"
        f" / 单测 {stats['tests']} 例 / 口径锚点 {stats['docHits']} 处"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
