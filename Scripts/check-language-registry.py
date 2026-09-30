#!/usr/bin/env python3
"""语言登记形状：语言知识只在登记文件里 + 登记项/标识/扩展名自洽 + 高亮色走主题令牌。

（FR-EDIT-38 ①②③④ 的机械半边，闭环第 2 项，**项数仍十八** —— 与
`check-core-portability.py` / `check-script-portability.py` 同一项：都是「Core 的形状」）

## 为什么要它

FR-EDIT-38 ① 要的口径是「**新增语言不改核心代码**」：语言定义（扩展名映射 + 关键字 /
类型 / 字面量 / 注释 / 运算符规则集）全部**声明式登记**。这句话如果只写在文档里，
两个后果会照旧发生：

1. 有人图快在词法器里加一句 `language == .html` —— 于是"有哪些语言"这件事又散回核心代码，
   下一个语言得再改一处，而**这不是崩溃、只是变笨**，没人会当场发现；
2. 有人加语言时只加标识、忘了给注释规则或字符串界定符 —— 症状是"打开某个文件一个颜色都没有"，
   同样不报错。

②的覆盖面（Alpha 2 = 常见编程语言前 10）与④（认不出如实纯文本）由
`Tests/CodeLanguageRegistryTests.swift` 逐条量；本判据管的是**形状**：知识与标识分别在
哪个文件、扩展名有没有两个主人、颜色是不是从令牌取的。

## 判据

- **A 形状禁令**：语言的**消费方**文件里不许出现"按语言身份分支"的写法
  （`language == .html` / `case .sql:` …）—— 语言知识只允许住在
  `Core/CodeLanguageDefinitions.swift`。逐处点名 `文件:行号`。
  例外走台账 `Scripts/language-registry-exemptions.json`（默认**空**，每条必须命中、理由不许空）。
- **B 登记自洽**：每条登记项必须给全（`displayName` / `fileExtensions` / `syntax`，
  且 `isCode` 为真者必须有注释规则与字符串界定符）；`TextLanguage` 的标识行与登记项
  **同集合**；一个扩展名 / 文件名只能有一个主人。
- **C 主题令牌**（③）：高亮色走 `SyntaxTone`（`Core/DesignTokens.swift` 定义、编辑器只用
  `Theme.nsColor(SyntaxTone.…)` 取），两个编辑器文件里不许出现裸色值。
- **D 空跑防护**：解析到的登记项数 / 标识行数 / 消费方文件数三条下限，低了即判红
  （正则失配 ⇒ 零命中 ⇒ 假绿，这是这类判据最经典的坏法）。
- **判据自己的证据**：`--self-test`（**7 例**）：夹具一律建在临时目录的副本上，
  写坏 ⇒ 判红且点名、还原 ⇒ 绿，末例核对真仓库逐字节未变。

## 边界（如实登记）

- A 只扫**语言消费方那一族文件**（词法器 / 登记 / 判语言 / 补全 / 两个编辑器 / CLI），
  不是全仓扫描：`Core/` 里有几百个文件，全扫会把"别的事情里恰好出现的 `.go`"当成违规，
  假阳性多了判据就会被绕过。
- A 剥掉注释后再匹配：判据自己的注释里会**引用**反面写法（`language == .html` 这种），
  那是说明书不是代码 —— 不剥注释的话这条判据第一个红在它自己头上。
- 视觉半边（切主题 / 切深浅后高亮真的变了）不在本判据：由设计令牌族
  （`check-design-tokens.py` / `check-design-themes.py` / `check-design-mock-tokens.py`）与
  单测承担，本判据只钉"取色的入口唯一"。

用法：
    python3 Scripts/check-language-registry.py             # 默认扫本仓
    python3 Scripts/check-language-registry.py --root DIR  # 扫 DIR（自检用）
    python3 Scripts/check-language-registry.py --self-test
"""

from __future__ import annotations

import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parent.parent
DEFINITIONS = pathlib.Path("Core/CodeLanguageDefinitions.swift")
LEDGER = pathlib.Path("Scripts/language-registry-exemptions.json")

# 语言消费方那一族（A 档的扫描面）——「谁按语言身份分支过，就是谁把知识从登记表里搬走了」。
CONSUMER_FILES = (
    "Core/CodeLexer.swift",
    "Core/CodeSyntax.swift",
    "Core/TextLanguage.swift",
    "Core/CodeCompletion.swift",
    "App/Views/CodeEditorView.swift",
    "App/Views/SQLEditorView.swift",
    "CLI/main.swift",
)
# C 档：语法色的两个取色点（编辑器）与令牌自己的定义处。
EDITOR_FILES = ("App/Views/CodeEditorView.swift", "App/Views/SQLEditorView.swift")
TOKEN_FILE = "Core/DesignTokens.swift"
TOKEN_ANCHOR = "Theme.nsColor(SyntaxTone."
BARE_COLOR = re.compile(r"NSColor\(\s*(?:calibrated|displayP3|device|sRGB)?\s*[Rr]ed\s*:|0x[0-9A-Fa-f]{6,8}\b")

# 空跑防护下限（本轮实测：18 条登记 / 18 行标识 / 7 个消费方文件）。
FLOOR_DEFINITIONS = 17
FLOOR_IDENTIFIERS = 17
FLOOR_CONSUMERS = 7
FLOOR_EXTENSIONS = 30
FLOOR_ANCHORS = 6

IDENTIFIER_LINE = re.compile(r'static\s+let\s+(\w+)\s*=\s*TextLanguage\(registered:\s*"([^"]+)"\)')
DEFINITION_HEAD = re.compile(r"CodeLanguageDefinition\(\s*\.(\w+)\s*,")
DASH_LINE_COMMENT = re.compile(r"//.*$")
BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.DOTALL)


def strip_comments(text: str) -> str:
    """剥掉注释行 —— 判据自己的说明书里会**引用**反面写法（`language == .html` 是例子），
    那是给人看的，不是代码。"""
    text = BLOCK_COMMENT.sub("", text)
    return "\n".join(DASH_LINE_COMMENT.sub("", line) for line in text.splitlines())


def load_ledger(root: pathlib.Path) -> tuple[list[dict], list[str]]:
    path = root / LEDGER
    if not path.exists():
        return [], []
    entries = json.loads(path.read_text(encoding="utf-8")).get("exempt", [])
    problems = []
    for index, entry in enumerate(entries):
        for field in ("file", "snippet", "reason"):
            if not str(entry.get(field, "")).strip():
                problems.append(f"例外台账第 {index + 1} 条缺 `{field}`（理由不许空）")
    return entries, problems


def identity_patterns(identifier: str) -> tuple[str, ...]:
    escaped = re.escape(identifier)
    return (
        rf"(?:==|!=)\s*\.{escaped}\b",
        rf"\.{escaped}\b\s*(?:==|!=)",
        rf"case\s+\.{escaped}\s*:",
    )


def check_identity_branches(root: pathlib.Path, identifiers: list[str], ledger: list[dict]) -> tuple[list[str], int, int]:
    problems: list[str] = []
    hits = 0
    scanned = 0
    for relative in CONSUMER_FILES:
        path = root / relative
        if not path.exists():
            problems.append(f"缺文件：{relative}（扫描面由本脚本的 CONSUMER_FILES 固定）")
            continue
        scanned += 1
        for number, line in enumerate(strip_comments(path.read_text(encoding="utf-8")).splitlines(), start=1):
            for identifier in identifiers:
                if not any(re.search(pattern, line) for pattern in identity_patterns(identifier)):
                    continue
                hits += 1
                if any(entry["file"] == relative and entry["snippet"] in line for entry in ledger):
                    continue
                problems.append(
                    f"{relative}:{number} 按语言身份分支（`{identifier}`）——"
                    f" 语言知识只允许住在 {DEFINITIONS.as_posix()}，"
                    f"消费方要拿规则请走 `CodeLanguageDefinition`；"
                    f"确有必要时登记 {LEDGER.as_posix()} 并写理由"
                )
    return problems, hits, scanned


def check_definitions(root: pathlib.Path) -> tuple[list[str], dict]:
    problems: list[str] = []
    path = root / DEFINITIONS
    text = path.read_text(encoding="utf-8")
    # 只认**登记表数组里面**的条目：`fallback` 常量（兜底定义）也在本文件里，
    # 但它不是一条登记（它只是"取不到定义时给什么"），算进来会变成"重复登记 plainText"。
    marker = "private static let definitions: [CodeLanguageDefinition] = ["
    start = text.find(marker)
    end = text.find("\n    ]", start) if start >= 0 else -1
    if start < 0 or end < 0:
        problems.append(
            f"{DEFINITIONS.as_posix()} 里找不到登记表数组（`{marker}` … `    ]`）——"
            f" 结构变了：本判据靠这段文本定位登记项，找不到就判不了"
        )
        region = text
    else:
        region = text[start + len(marker):end]
    # 整行注释的登记项**不算登记**（`// CodeLanguageDefinition(` 是"注释掉一条登记"，
    # 而那种写法在文本扫描里长得和真登记一模一样 —— 不剥掉，判据就会为一条已注释的登记背书）。
    region = "\n".join(line for line in region.splitlines() if not line.strip().startswith("//"))
    if region.count("isFallback: true") != 1:
        problems.append(
            f"回落值（`isFallback: true`）必须**恰好一条**，实际 {region.count('isFallback: true')} 条"
            f"（两条 = 判语言有两个「认不出」的答案）"
        )
    identifiers = sorted({match.group(2) for match in IDENTIFIER_LINE.finditer(text)})
    heads = list(DEFINITION_HEAD.finditer(region))
    registered: list[str] = []
    extensions: dict[str, str] = {}
    entries: dict[str, str] = {}
    extension_count = 0
    for index, head in enumerate(heads):
        end = heads[index + 1].start() if index + 1 < len(heads) else len(region)
        chunk = region[head.start():end]
        language = head.group(1)
        registered.append(language)
        for field in ("displayName:", "fileExtensions:", "syntax:"):
            if field not in chunk:
                problems.append(f"{DEFINITIONS.as_posix()} 的 `.{language}` 登记项缺 `{field}`")
        if "isCode: false" not in chunk:
            for field in ("comments:", "stringDelimiters:"):
                if field not in chunk:
                    problems.append(
                        f"{DEFINITIONS.as_posix()} 的 `.{language}` 是代码语言却没有 `{field}`"
                        f"（症状：识别了却一个颜色都没有）"
                    )
        for match in re.finditer(r"fileExtensions:\s*\[([^\]]*)\]", chunk, re.DOTALL):
            for file_extension in re.findall(r'"([^"]*)"', match.group(1)):
                extension_count += 1
                owner = extensions.get(file_extension)
                if owner is not None:
                    problems.append(f"扩展名 `.{file_extension}` 同时属于 `{owner}` 与 `{language}`（判语言会随表顺序变）")
                extensions[file_extension] = language
        for match in re.finditer(r"fileNames:\s*\[([^\]]*)\]", chunk, re.DOTALL):
            for file_name in re.findall(r'"([^"]*)"', match.group(1)):
                owner = entries.get(file_name)
                if owner is not None:
                    problems.append(f"文件名 `{file_name}` 同时属于 `{owner}` 与 `{language}`")
                entries[file_name] = language
    if len(set(registered)) != len(registered):
        problems.append(f"{DEFINITIONS.as_posix()} 里有重复登记的语言（{registered}）")
    if set(registered) != set(identifiers):
        problems.append(
            "语言标识与登记项不是同一个集合 ——"
            f" 只在标识里：{sorted(set(identifiers) - set(registered))}；"
            f" 只在登记里：{sorted(set(registered) - set(identifiers))}"
        )
    stats = {
        "definitions": len(registered),
        "identifiers": len(identifiers),
        "extensions": extension_count,
        "languages": registered,
    }
    return problems, stats


def check_colors(root: pathlib.Path) -> tuple[list[str], int]:
    problems: list[str] = []
    anchor_hits = 0
    token_file = root / TOKEN_FILE
    if not token_file.exists() or "public enum SyntaxTone" not in token_file.read_text(encoding="utf-8"):
        problems.append(f"{TOKEN_FILE} 里找不到 `public enum SyntaxTone` —— 高亮色令牌的唯一定义处没了")
    for relative in EDITOR_FILES:
        path = root / relative
        if not path.exists():
            problems.append(f"缺文件：{relative}")
            continue
        for number, line in enumerate(strip_comments(path.read_text(encoding="utf-8")).splitlines(), start=1):
            anchor_hits += line.count(TOKEN_ANCHOR)
            if BARE_COLOR.search(line):
                problems.append(
                    f"{relative}:{number} 出现裸色值 —— 语法色必须走 `{TOKEN_ANCHOR}…`"
                    f"（否则切主题 / 切深浅时高亮不跟着变）"
                )
        if TOKEN_ANCHOR not in strip_comments(path.read_text(encoding="utf-8")):
            problems.append(f"{relative} 里没有取色锚点 `{TOKEN_ANCHOR}`（语法色的入口应当唯一）")
    return problems, anchor_hits


def run(root: pathlib.Path) -> int:
    problems, stats = check_definitions(root)
    ledger, ledger_problems = load_ledger(root)
    branch_problems, branch_hits, consumers = check_identity_branches(root, stats["languages"], ledger)
    color_problems, anchors = check_colors(root)
    problems += ledger_problems + branch_problems + color_problems

    # D 空跑防护：正则失配 ⇒ 零命中 ⇒ 假绿，这是这类判据最经典的坏法。
    if stats["definitions"] < FLOOR_DEFINITIONS:
        problems.append(f"只解析到 {stats['definitions']} 条登记项（下限 {FLOOR_DEFINITIONS}）—— 解析失配还是登记表被掏空？")
    if stats["identifiers"] < FLOOR_IDENTIFIERS:
        problems.append(f"只解析到 {stats['identifiers']} 行语言标识（下限 {FLOOR_IDENTIFIERS}）")
    if stats["extensions"] < FLOOR_EXTENSIONS:
        problems.append(f"只解析到 {stats['extensions']} 条扩展名（下限 {FLOOR_EXTENSIONS}）")
    if consumers < FLOOR_CONSUMERS:
        problems.append(f"只扫到 {consumers} 个语言消费方文件（下限 {FLOOR_CONSUMERS}）—— 扫描面失效")
    if anchors < FLOOR_ANCHORS:
        problems.append(f"只找到 {anchors} 处取色锚点（下限 {FLOOR_ANCHORS}）—— 语法色可能没走主题令牌")

    print(
        f"语言登记表：{stats['definitions']} 种语言 / {stats['extensions']} 条扩展名 / "
        f"消费方 {consumers} 个文件 / 语言身份分支 {branch_hits} 处 / 取色锚点 {anchors} 处"
    )
    if problems:
        print(f"❌ 语言登记形状不通过（{len(problems)} 处）：")
        for problem in problems:
            print(f"   · {problem}")
        return 1
    print(f"✅ 语言登记形状通过：知识只在 {DEFINITIONS.as_posix()}，消费方 0 处身份分支，取色走主题令牌")
    return 0


# ---------------------------------------------------------------------------
# 判据自己的证据


CASES: list[str] = [
    "消费方里出现按语言身份分支（`language == .sql`）",
    "代码语言缺注释规则（`isCode` 为真却删掉 `comments:`）",
    "两个语言抢同一个扩展名",
    "语言标识与登记项不同集合（删掉一行标识）",
    "编辑器里出现裸色值（不再走 `SyntaxTone`）",
    "登记表被掏空（全部登记项删掉）",
    "真仓库：判据 exit 0，且夹具前后真文件逐字节未变",
]
FIXTURE_FILES = CONSUMER_FILES + EDITOR_FILES + (str(DEFINITIONS.as_posix()), TOKEN_FILE)


def snapshot(root: pathlib.Path) -> dict:
    table = {}
    for relative in FIXTURE_FILES:
        path = root / relative
        table[relative] = hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else "missing"
    return table


def build_fixture(source: pathlib.Path, target: pathlib.Path) -> None:
    for relative in FIXTURE_FILES:
        destination = target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / relative, destination)


def mutate(root: pathlib.Path, relative: str, old: str, new: str, count: int = 1) -> None:
    path = root / relative
    text = path.read_text(encoding="utf-8")
    assert old in text, f"夹具锚点失效：{relative} 里找不到 {old!r}"
    path.write_text(text.replace(old, new, count), encoding="utf-8")


def run_self_test() -> int:
    failures: list[str] = []
    before = snapshot(REPO)
    scratch = pathlib.Path(tempfile.mkdtemp(prefix="doyah-language-registry-"))
    try:
        def fresh() -> pathlib.Path:
            target = scratch / f"case{len(failures)}{len(list(scratch.iterdir()))}"
            build_fixture(REPO, target)
            return target

        def expect_red(name: str, mutate_case) -> None:
            target = fresh()
            mutate_case(target)
            code = run(target)
            if code == 0:
                failures.append(f"例「{name}」应判红，实际 exit 0")
            print(f"   例「{name}」⇒ exit {code}")

        def expect_green(name: str) -> None:
            target = fresh()
            code = run(target)
            if code != 0:
                failures.append(f"例「{name}」应判绿，实际 exit {code}")
            print(f"   例「{name}」⇒ exit {code}")

        expect_green("干净的夹具本身必须判绿（否则后面的红都不可信）")
        expect_red(CASES[0], lambda t: mutate(t, "Core/CodeLexer.swift", "        while index < text.endIndex {",
                                              "        if language == .sql { return [] }\n        while index < text.endIndex {"))
        # CodeLexer 里没有 `language` 变量了：夹具注入的是身份判断的**形状**，判据看的就是形状。
        expect_red(CASES[1], lambda t: mutate(t, str(DEFINITIONS.as_posix()), 'comments: [CodeCommentStyle(block: "<!--", "-->")],', ""))
        expect_red(CASES[2], lambda t: mutate(t, str(DEFINITIONS.as_posix()), 'fileExtensions: ["go"],', 'fileExtensions: ["go", "js"],'))
        expect_red(CASES[3], lambda t: mutate(t, str(DEFINITIONS.as_posix()), '    public static let go = TextLanguage(registered: "go")\n', ""))
        expect_red(CASES[4], lambda t: mutate(t, "App/Views/CodeEditorView.swift",
                                              "Theme.nsColor(SyntaxTone.keyword)",
                                              "NSColor(red: 1, green: 0, blue: 0, alpha: 1)"))
        expect_red(CASES[5], lambda t: mutate(t, str(DEFINITIONS.as_posix()), "        CodeLanguageDefinition(\n", "        // CodeLanguageDefinition(\n", 999))
        if snapshot(REPO) != before:
            failures.append("自检改动了真仓库（夹具必须只在临时副本上写坏）")
    finally:
        shutil.rmtree(scratch, ignore_errors=True)

    print(f"自检：例数 {len(CASES)} / 通过 {len(CASES) - len(failures)} / 失败 {len(failures)}")
    for failure in failures:
        print(f"   {failure}")
    return 1 if failures else 0


def main() -> int:
    arguments = sys.argv[1:]
    if "--self-test" in arguments:
        return run_self_test()
    root = REPO
    if "--root" in arguments:
        index = arguments.index("--root")
        if index + 1 >= len(arguments):
            print("❌ --root 后面要跟一个目录")
            return 2
        root = pathlib.Path(arguments[index + 1]).resolve()
        if not (root / DEFINITIONS).exists():
            print(f"❌ {root}/{DEFINITIONS.as_posix()} 不存在")
            return 2
    return run(root)


if __name__ == "__main__":
    sys.exit(main())
