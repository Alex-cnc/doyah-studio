#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""门禁：**Markdown 解析只有一份，预览只许消费它**（队列 `L-137` 判据 ⑤，闭环第 10 项）。

**为什么有它**：需求提出者 2026-09-30 要「工作区的编辑器还要带 markdown 预览功能」，而这条路线上
有一个**必然的诱惑**：预览要有标题 / 列表 / 表格 / 代码块，最快的做法是再写一套块级解析
（或者引一个第三方渲染库）。一旦那样做，这个仓里就会有两套 Markdown 口径 ——
同一份 `**粗体**` 在笔记里是粗体、在预览里是星号，而且**编译照过、单测照绿**，
没有任何东西看得见（本仓「判据要落在结果状态上」那一族的典型形状）。

所以把「只有一份」变成机械判据：

  ① **行内解析唯一**：`nextMarker`（行内标记扫描器）与 `linkMarker`（链接扫描器）都只许在
     `Core/NoteBody.swift` 里出现 —— 别处命中即红（那是第二套行内解析的入口）；一处都没有也红
     （扫描面被削过 / 判据空转）。行内标记清单那一个字面量（``["`", "**", "*", "["]``）同理**只许一份**。
     链接扫描器是 2026-10-01（第 146 轮，队列 `L-137` 剩余③）补进来的：链接与粗体一样是**笔记侧
     那一份解析**的产物，别处再写一套链接解析就是同一族的病。
  ② **块级模型只有一个产地**：`MarkdownBlock(` 的构造只许在 `Core/MarkdownDocument.swift` ——
     `App/` / `Platform/` / `CLI/` 里出现即红（界面只渲染模型，不许自己造块：
     造块就等于在自己那份里重新决定「什么算标题」）。
  ③ **预览必须真同源**：`Core/MarkdownDocument.swift` 里必须**真的调用**笔记侧那个函数
     （`NoteBodyProjection.parseInline(` 至少 4 处：标题 / 段落 / 表格 / 列表）。
     只写注释说「复用」不算 —— 这条判的是调用点。
  ④ **不引第三方 Markdown**：家规是「不引第三方」（笔记存储引擎当年就是这么定的）。
     `import` 行与依赖声明里不得出现 MarkdownUI / swift-markdown / SwiftyMarkdown /
     MarkdownKit / Ink / Down / cmark 这类标识。
  ⑤ **判据在位（空跑防护）**：扫描面文件数、块构造处数、同源调用处数、解析层用例数四条下限 ——
     把模型掏空、把用例删光、把扫描面削掉，都必须报红而不是「零命中 = 通过」。

**这条门禁保护的不是代码，是一个口径**：Markdown → 文档模型**只有一处**。
笔记侧是权威源（`Q8` 已拍板不接受第二套解析），工作区预览只是**第二个消费者**。

用法：
    python3 Scripts/check-markdown-single-source.py              # 人读结论，失败非零退出
    python3 Scripts/check-markdown-single-source.py --json       # 机器读
    python3 Scripts/check-markdown-single-source.py --root <树>  # 负例验证用（临时副本）
    python3 Scripts/check-markdown-single-source.py --self-test  # 负例自检（临时副本上写坏）
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

INLINE_OWNER = "Core/NoteBody.swift"
BLOCK_OWNER = "Core/MarkdownDocument.swift"
PARSE_TESTS = "Tests/MarkdownDocumentTests.swift"

INLINE_SCANNER = "nextMarker"
LINK_SCANNER = "linkMarker"
INLINE_MARKER_LIST = '["`", "**", "*", "["]'
BLOCK_CONSTRUCTOR = "MarkdownBlock("
SHARED_INLINE_CALL = "NoteBodyProjection.parseInline("

SCAN_DIRS = ("Core", "App", "Platform", "CLI")
TESTS_DIR = "Tests"
DEPENDENCY_FILES = ("Package.swift", "project.yml")

FORBIDDEN_PACKAGES = (
    "MarkdownUI",
    "swift-markdown",
    "SwiftyMarkdown",
    "MarkdownKit",
    "MarkdownView",
    "Ink",
    "Down",
    "cmark",
)

# 空跑防护下限（实测值写在括号里；低于下限 ⇒ 判红，防「扫描面被削掉 ⇒ 零命中 = 通过」）
MIN_SCANNED_FILES = 200          # 实测 449（Core 180 / App 102 / Platform 5 / CLI 2 / Tests 160）
MIN_BLOCK_CONSTRUCTIONS = 6      # 实测 9（标题 / 分隔线 / 代码块 / 引用 / 段落 / 表格 / 三种列表）
MIN_SHARED_INLINE_CALLS = 4      # 实测 7（标题 / 段落 / 表格表头 / 表格行 / 三种列表条目）
MIN_PARSE_TESTS = 15             # 实测 21


def read(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8")


def rel(root: pathlib.Path, path: pathlib.Path) -> str:
    return path.relative_to(root).as_posix()


def swift_sources(root: pathlib.Path, problems: list[str]) -> dict[str, str]:
    """扫描面：实现层四个目录 + `Tests/` 的全部 `.swift`。**目录不在 ⇒ 判红**（不许悄悄缩面）。"""
    sources: dict[str, str] = {}
    for dirname in SCAN_DIRS + (TESTS_DIR,):
        base = root / dirname
        if not base.is_dir():
            problems.append(f"{dirname}/ 不存在 —— 扫描面被削过（空跑不许通过）")
            continue
        for path in sorted(base.rglob("*.swift")):
            sources[rel(root, path)] = read(path)
    return sources


def count(text: str, needle: str) -> int:
    return text.count(needle)


def check(root: pathlib.Path) -> tuple[list[str], list[str]]:
    problems: list[str] = []
    notes: list[str] = []
    sources = swift_sources(root, problems)

    if len(sources) < MIN_SCANNED_FILES:
        problems.append(
            f"扫描面只有 {len(sources)} 个 `.swift`（下限 {MIN_SCANNED_FILES}）—— 判据扫不到东西，不许通过"
        )

    # ① 行内解析唯一（两条：**定义**只有一处且在本仓笔记侧；**名字**不许出现在别处）
    definition = re.compile(rf"func\s+{INLINE_SCANNER}\s*\(")
    definition_owners = sorted(name for name, text in sources.items() if definition.search(text))
    if definition_owners != [INLINE_OWNER]:
        problems.append(
            f"`{INLINE_SCANNER}` 的**定义**必须是且只是 `{INLINE_OWNER}` 里的一处，"
            f"实测 {definition_owners or '一处都没有'} —— 一处都没有 = 扫描面被削过 / 判据空转"
        )
    if [name for name in sorted(sources) if name != INLINE_OWNER and INLINE_SCANNER in sources[name]]:
        # 名字出现在别处 = 有人在别处调用或重写了行内扫描 → 第二套解析的入口
        problems.append(
            f"`{INLINE_SCANNER}` 的名字出现在 `{INLINE_OWNER}` 以外的地方："
            f"{[name for name in sorted(sources) if name != INLINE_OWNER and INLINE_SCANNER in sources[name]]}"
            " —— 行内解析只许有一处，别处出现即红"
        )
    if definition_owners == [INLINE_OWNER] and not problems:
        notes.append(f"行内标记扫描器 `{INLINE_SCANNER}`：唯一定义在 `{INLINE_OWNER}`，名字不出本文件")
    # ①b **链接扫描器同理**（2026-10-01 第 146 轮补，队列 `L-137` 剩余③）：定义唯一 + 名字不出本文件。
    link_definition = re.compile(rf"func\s+{LINK_SCANNER}\s*\(")
    link_definition_owners = sorted(name for name, text in sources.items() if link_definition.search(text))
    if link_definition_owners != [INLINE_OWNER]:
        problems.append(
            f"`{LINK_SCANNER}` 的**定义**必须是且只是 `{INLINE_OWNER}` 里的一处，"
            f"实测 {link_definition_owners or '一处都没有'} —— 链接目标的生产只许一处（一处都没有 = 判据空转）"
        )
    stray_link_scanners = [
        name for name in sorted(sources) if name != INLINE_OWNER and LINK_SCANNER in sources[name]
    ]
    if stray_link_scanners:
        problems.append(
            f"`{LINK_SCANNER}` 的名字出现在 `{INLINE_OWNER}` 以外的地方：{stray_link_scanners}"
            " —— 链接解析只许有一处，别处出现即红（链接与粗体同一条口径）"
        )
    if link_definition_owners == [INLINE_OWNER] and not stray_link_scanners:
        notes.append(f"链接扫描器 `{LINK_SCANNER}`：唯一定义在 `{INLINE_OWNER}`，名字不出本文件")

    marker_list_owners = sorted(name for name, text in sources.items() if INLINE_MARKER_LIST in text)
    if marker_list_owners != [INLINE_OWNER]:
        problems.append(
            f"行内标记清单 `{INLINE_MARKER_LIST}` 只许在 `{INLINE_OWNER}` 里出现一次，"
            f"实测落点 {marker_list_owners or '什么都没有'}"
        )

    # ② 块级模型只有一个产地
    block_owners = sorted(name for name, text in sources.items() if BLOCK_CONSTRUCTOR in text)
    stray_blocks = [name for name in block_owners if name != BLOCK_OWNER]
    if stray_blocks:
        problems.append(
            f"{', '.join(stray_blocks)}：自己构造了 `{BLOCK_CONSTRUCTOR}` —— "
            "块级模型只许由契约层产出，界面 / 平台层只许渲染"
        )
    if BLOCK_OWNER not in block_owners:
        problems.append(f"`{BLOCK_OWNER}` 不存在或没有再构造任何块 —— 模型被掏空 / 判据空转")
    else:
        constructions = count(sources[BLOCK_OWNER], BLOCK_CONSTRUCTOR)
        if constructions < MIN_BLOCK_CONSTRUCTIONS:
            problems.append(
                f"`{BLOCK_OWNER}` 只构造了 {constructions} 处块（下限 {MIN_BLOCK_CONSTRUCTIONS}）—— 模型被掏空"
            )
        else:
            notes.append(f"块级模型唯一产地 `{BLOCK_OWNER}`：{constructions} 处构造")

    # ③ 预览必须真同源（判的是调用点，不是注释）
    if BLOCK_OWNER not in sources:
        problems.append(f"`{BLOCK_OWNER}` 不在扫描面里 —— 同源判据无从谈起")
    else:
        shared_calls = count(sources[BLOCK_OWNER], SHARED_INLINE_CALL)
        if shared_calls < MIN_SHARED_INLINE_CALLS:
            problems.append(
                f"`{BLOCK_OWNER}` 里只有 {shared_calls} 处调用 `{SHARED_INLINE_CALL}`（下限 "
                f"{MIN_SHARED_INLINE_CALLS}）—— 「复用笔记侧解析」只活在注释里"
            )
        else:
            notes.append(f"同源调用：`{BLOCK_OWNER}` 调 `{SHARED_INLINE_CALL}` {shared_calls} 处")

    # ④ 不引第三方 Markdown
    for name in sorted(sources):
        text = sources[name]
        for line_number, line in enumerate(text.splitlines(), 1):
            match = re.match(r"\s*import\s+(?:struct\s+|class\s+|enum\s+|func\s+)?(\w+)", line)
            if not match:
                continue
            module = match.group(1)
            for package in FORBIDDEN_PACKAGES:
                if module.lower() == package.lower().replace("-", ""):
                    problems.append(f"{name}:{line_number}: `import {module}` —— 家规不引第三方 Markdown 解析")
    for name in DEPENDENCY_FILES:
        path = root / name
        if not path.exists():
            continue
        for line_number, line in enumerate(read(path).splitlines(), 1):
            lowered = line.lower()
            if ".package(" not in lowered and "url:" not in lowered:
                continue
            for package in FORBIDDEN_PACKAGES:
                # 词边界匹配：`down` 不许命中 `download`、`ink` 不许命中 `link`（依赖行里这两种词很常见）。
                token = package.lower()
                if re.search(rf"(?<![a-z0-9]){re.escape(token)}(?![a-z0-9])", lowered) or \
                        re.search(rf"(?<![a-z0-9]){re.escape(token.replace('-', ''))}(?![a-z0-9])", lowered):
                    problems.append(
                        f"{name}:{line_number}: 依赖里出现 Markdown 解析库 `{package}` —— 家规不引第三方"
                    )

    # ⑤ 判据在位（空跑防护的另一半：解析层用例必须存在且不是壳）
    tests_path = root / PARSE_TESTS
    if not tests_path.exists():
        problems.append(f"`{PARSE_TESTS}` 不在 —— 块级模型没有任何单测钉着")
    else:
        tests_text = read(tests_path)
        case_count = len(re.findall(r"\n\s*func test", tests_text))
        if case_count < MIN_PARSE_TESTS:
            problems.append(f"`{PARSE_TESTS}` 只有 {case_count} 个用例（下限 {MIN_PARSE_TESTS}）—— 用例被删过")
        else:
            notes.append(f"解析层用例：`{PARSE_TESTS}` {case_count} 个")
        if SHARED_INLINE_CALL not in tests_text:
            problems.append(
                f"`{PARSE_TESTS}` 里没有一条「与笔记侧同一函数」的断言 —— 同源口径没人钉住"
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
        print(f"\n❌ Markdown 单一口径门禁未通过（{len(problems)} 项）：")
        for problem in problems:
            print(f"   - {problem}")
        return 1
    print(
        "\n✅ Markdown 解析只有一份：行内扫描器与链接扫描器都唯一（笔记侧）· 块级模型唯一产地（契约层）· "
        "预览真的调用同一个行内函数 · 无第三方 Markdown 解析库 · 判据面在位"
    )
    return 0


# ── 负例自检 ────────────────────────────────────────────────────────────────
#
# 纪律：一律在**临时副本**上写坏，末例核对真仓库逐字节未变。
# 每个负例都要问一句「这条改动如果真发生了，判据会不会当场报红」——
# 报不出来的话，这门禁就只是文档。

WATCHED = (
    INLINE_OWNER,
    BLOCK_OWNER,
    PARSE_TESTS,
    "Package.swift",
    "project.yml",
    "Core/AppError.swift",   # 随便挑一个无关文件：证明「无关文件改了不误报」
)


def _sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _fixture(destination: pathlib.Path, root: pathlib.Path) -> pathlib.Path:
    """把扫描面（四个实现目录 + Tests + 依赖清单）复制成一份临时副本。"""
    for dirname in SCAN_DIRS + (TESTS_DIR,):
        source = root / dirname
        if not source.is_dir():
            continue
        target = destination / dirname
        target.mkdir(parents=True, exist_ok=True)
        for path in sorted(source.rglob("*.swift")):
            relative = path.relative_to(source)
            (target / relative).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target / relative)
    for name in DEPENDENCY_FILES:
        source = root / name
        if source.exists():
            shutil.copy2(source, destination / name)
    return destination


def _patch(path: pathlib.Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise AssertionError(f"夹具写坏失败：`{old}` 不在 {path.name} 里")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def self_test(root: pathlib.Path) -> int:
    before = {name: _sha(root / name) for name in WATCHED if (root / name).exists()}
    cases: list[tuple[str, bool]] = []   # (名字, 期望报红)
    with tempfile.TemporaryDirectory(prefix="doyah-md-single-") as tmp:
        workspace = pathlib.Path(tmp)

        def fresh(name: str) -> pathlib.Path:
            return _fixture(workspace / name, root)

        # ① 绿：真仓库的副本，判据必须全过
        green = fresh("green")
        green_problems, _ = check(green)
        cases.append(("绿对照：真仓库副本应全过", not green_problems))

        # ② 红：预览侧又写了一份行内扫描器（这一族缺陷的标准形状）
        duplicate = fresh("inline-duplicate")
        (duplicate / "App/Views").mkdir(parents=True, exist_ok=True)
        (duplicate / "App/Views/MarkdownPreview.swift").write_text(
            "import Foundation\n\n/// 预览自己扫行内标记（本门禁必须抓住它）\n"
            "func scan(text: String) -> Bool { text.contains(\"**\") }\n"
            "private func nextMarker(in text: Substring) -> Int? { nil }\n",
            encoding="utf-8",
        )
        cases.append(("行内扫描器出现第二份", bool(check(duplicate)[0])))

        # ③ 红：行内扫描器被掏空（定义没了 ⇒ 判据空转，也必须红）
        hollow_inline = fresh("inline-hollow")
        _patch(hollow_inline / INLINE_OWNER, "    private static func nextMarker(in text: Substring)",
               "    private static func removedMarker(in text: Substring)")
        cases.append(("行内扫描器定义被删", bool(check(hollow_inline)[0])))

        # ④ 红：界面自己造块（绕过契约层）
        stray = fresh("block-stray")
        (stray / "App/Views").mkdir(parents=True, exist_ok=True)
        (stray / "App/Views/MarkdownPreview.swift").write_text(
            "import Foundation\n\nfunc makeBlock() -> MarkdownBlock { MarkdownBlock(kind: .thematicBreak, sourceLine: 1) }\n",
            encoding="utf-8",
        )
        cases.append(("界面自己构造块", bool(check(stray)[0])))

        # ⑤ 红：块级模型被掏空
        hollow_block = fresh("block-hollow")
        text = (hollow_block / BLOCK_OWNER).read_text(encoding="utf-8")
        text = re.sub(r"MarkdownBlock\(kind:", "MarkdownBlockX(kind:", text)
        text = text.replace("\u3000", "")   # 只是让 diff 更明显，不改变语义
        (hollow_block / BLOCK_OWNER).write_text(text, encoding="utf-8")
        cases.append(("块级模型被掏空", bool(check(hollow_block)[0])))

        # ⑥ 红：同源调用被删（预览不再复用笔记侧的行内函数）
        unsourced = fresh("shared-calls")
        text = (unsourced / BLOCK_OWNER).read_text(encoding="utf-8")
        text = text.replace(SHARED_INLINE_CALL, "Self.localInline(")
        (unsourced / BLOCK_OWNER).write_text(text, encoding="utf-8")
        cases.append(("同源调用被删", bool(check(unsourced)[0])))

        # ⑦ 红：引入第三方 Markdown 库（import 行）
        third_party = fresh("third-party-import")
        _patch(third_party / "Core/AppError.swift", "import Foundation", "import Foundation\nimport MarkdownUI")
        cases.append(("引入第三方 Markdown 库（import）", bool(check(third_party)[0])))

        # ⑧ 红：依赖清单里加第三方 Markdown 包
        third_party_dep = fresh("third-party-dependency")
        text = (third_party_dep / "Package.swift").read_text(encoding="utf-8")
        text = text.replace(
            "        .package(path: \"Vendor/sqlite3\"),",
            "        .package(path: \"Vendor/sqlite3\"),\n"
            "        .package(url: \"https://github.com/gonzalezreal/swift-markdown-ui\", from: \"2.0.0\"),",
            1,
        )
        (third_party_dep / "Package.swift").write_text(text, encoding="utf-8")
        cases.append(("依赖清单里加第三方 Markdown 包", bool(check(third_party_dep)[0])))

        # ⑨ 红：解析层用例被删
        no_tests = fresh("no-tests")
        (no_tests / PARSE_TESTS).unlink()
        cases.append(("解析层用例文件被删", bool(check(no_tests)[0])))

        # ⑩ 红：用例被掏空成壳（文件在、一个用例都没有）
        hollow_tests = fresh("hollow-tests")
        text = (hollow_tests / PARSE_TESTS).read_text(encoding="utf-8")
        text = re.sub(r"\n\s*func test", "\n    func removed", text)
        (hollow_tests / PARSE_TESTS).write_text(text, encoding="utf-8")
        cases.append(("解析层用例被掏空", bool(check(hollow_tests)[0])))

        # ⑪ 红：扫描面被削掉（目录整个没了）
        no_scan = fresh("no-scan")
        shutil.rmtree(no_scan / "Platform")
        cases.append(("扫描面被削掉", bool(check(no_scan)[0])))

        # ②b 红：**链接扫描器**出现第二份（2026-10-01 第 146 轮补 —— 与 ② 同一族的形状）
        duplicate_link = fresh("link-duplicate")
        (duplicate_link / "App/Views").mkdir(parents=True, exist_ok=True)
        (duplicate_link / "App/Views/MarkdownPreview.swift").write_text(
            "import Foundation\n\n/// 预览自己扫链接目标（本门禁必须抓住它）\n"
            "private func linkMarker(in text: Substring) -> Int? { nil }\n",
            encoding="utf-8",
        )
        cases.append(("链接扫描器出现第二份", bool(check(duplicate_link)[0])))

        # 末例：真仓库逐字节未变 + 真仓库实跑绿
        after = {name: _sha(root / name) for name in WATCHED if (root / name).exists()}
        untouched = after == before
        real_problems, _ = check(root)
        cases.append(("末例：真仓库逐字节未变且实跑绿", untouched and not real_problems))

    passed_cases = 0
    for name, ok in cases:
        print(f"{'✅' if ok else '❌'} {name}")
        passed_cases += 1 if ok else 0
    ok = passed_cases == len(cases)
    print(f"{'✅' if ok else '❌'} 负例自检：{len(cases)} 条中 {passed_cases} 条达到预期")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
