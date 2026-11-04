#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""只读机械证明（Retro macOS · M0 第 4 片 · 派单卡 `t_66956c06`）。

为什么要有它：`FR-R-13-08` 判据 ③ 是「**只读**：视图内不产生任何写回包的动作」，
`IR-05` 不变量 7 也是「Retro **不写**这个包」。而「约定别写」这种纪律在几百行里迟早失守，
所以把它变成一条**机械检查**：扫视图层 + 领域层的每一行，出现任何**对包的写调用**就判红并点名。

口径（刻意保守，只查真正该干净的那两层）：
  · 扫描范围 = 视图层 `Plugins/Retro/Views/**/*.swift` + 领域层 `Plugins/Retro/Sources/**/*.swift`
    （单测 `Tests/**` 不在内 —— 测试造夹具本来就要落盘）；
  · 禁用记号（逐条）：`createFile` · `write(to:` · `removeItem` · `copyItem` · `createDirectory`
    · `OutputStream` · `.write(`；
  · **不做注释剔除**：命中即报 —— 宁可多报一条让人工复核，不许漏一条（假绿比误报贵得多）；
  · 命中 ⇒ 退出码 1，逐条打印 `文件:行`；0 命中 ⇒ 退出码 0。

**自维护 / 不假绿**：门禁最坏的失效方式是「永远绿」。所以本脚本自带 `--self-test`：
在临时目录里造「有写调用的文件」与「只读的文件」，断言该红的红、该绿的绿 —— 每次跑都在真的跑一遍
（7 例，见 `SELF_TEST_CASES`）。临时目录落在 TMPDIR（本机 = 本 profile 的 scratch），**不碰本仓**。

用法（在仓根执行；本脚本 2026-11-03 随 Retro 的 macOS 实现迁入 Studio 仓）：
    python3 Plugins/Retro/Tools/check-readonly.py            # 只读机械证明（判据 ②）
    python3 Plugins/Retro/Tools/check-readonly.py --self-test # 判据本体自己的负例自检
"""

from __future__ import annotations

import argparse
import pathlib
import re
import shutil
import sys
import tempfile

# `Plugins/Retro/Tools/check-readonly.py` ⇒ parents[0]=Tools · [1]=Retro · [2]=Plugins · [3]=仓根
REPO = pathlib.Path(__file__).resolve().parents[3]

# 逐条对应契约「写回包的动作」的机械形式：落盘 / 改文件 / 删文件 / 建目录 / 流写出。
WRITE_TOKENS = [
    "createFile",
    "write(to:",
    "removeItem",
    "copyItem",
    "createDirectory",
    "OutputStream",
    ".write(",
]

LAYERS = [
    ("视图层", REPO / "Plugins" / "Retro" / "Views"),
    ("领域层", REPO / "Plugins" / "Retro" / "Sources"),
]


def _token_regex(token: str) -> re.Pattern[str]:
    return re.compile(re.escape(token))


PATTERNS = [(token, _token_regex(token)) for token in WRITE_TOKENS]


def scan_file(path: pathlib.Path) -> list[tuple[int, str, str]]:
    """返回 `[(行号, 命中记号, 该行原文)]`；只读文件 ⇒ 空列表。"""
    hits: list[tuple[int, str, str]] = []
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return hits
    for number, line in enumerate(text.splitlines(), start=1):
        for token, pattern in PATTERNS:
            if pattern.search(line):
                hits.append((number, token, line.strip()))
    return hits


def swift_files(directory: pathlib.Path) -> list[pathlib.Path]:
    if not directory.is_dir():
        return []
    return sorted(p for p in directory.rglob("*.swift"))


def run_proof() -> int:
    total_files = 0
    total_hits: list[tuple[pathlib.Path, int, str, str]] = []

    for label, directory in LAYERS:
        files = swift_files(directory)
        total_files += len(files)
        if not directory.is_dir():
            print(f"❌ {label}目录不存在：{directory}")
            return 1
        for path in files:
            for number, token, line in scan_file(path):
                total_hits.append((path, number, token, line))
        print(f"   {label}：{len(files)} 个 .swift 文件")

    if total_hits:
        print(f"❌ 只读机械证明判红：对包目录的写调用 {len(total_hits)} 处（命中即判红，逐条点名）")
        for path, number, token, line in total_hits:
            print(f"   {path.relative_to(REPO)}:{number}  命中「{token}」  {line}")
        return 1

    print(
        "✅ 只读机械证明通过：视图层 + 领域层共 "
        f"{total_files} 个 .swift 文件，写调用 0 命中"
        f"（记号：{' · '.join(WRITE_TOKENS)}）"
    )
    return 0


# MARK: - 自检（造临时文件，断言该红的红、该绿的绿）

SELF_TEST_CASES: list[tuple[str, str | None, list[str]]] = [
    # (用例名, 文件内容（None = 不建文件）, 期望命中的记号列表)
    ("干净的只读文件", 'let url = URL(fileURLWithPath: "a.swift")\nlet exists = FileManager.default.fileExists(atPath: url.path)\n', []),
    ("图片只读读入", "if let image = NSImage(contentsOf: url) { print(image.size) }\n", []),
    ("String 插值里的 write 字样不算（无 .write(）", 'let note = "本层不提供写回入口"\n', []),
    ("写文件（write(to:）", "try Data(body.utf8).write(to: target)\n", ["write(to:", ".write("]),
    ("建目录（createDirectory）", "try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)\n", ["createDirectory"]),
    ("删 / 拷文件", "try FileManager.default.removeItem(at: a)\ntry FileManager.default.copyItem(at: a, to: b)\n", ["removeItem", "copyItem"]),
    ("流写出 / 建文件", "let stream = OutputStream(toFile: path, append: false)\n_ = FileManager.default.createFile(atPath: path, contents: nil)\n", ["OutputStream", "createFile"]),
]


def run_self_test() -> int:
    print(f"== 判据本体自检（{len(SELF_TEST_CASES)} 例）")
    failures = 0
    workspace = tempfile.mkdtemp(prefix="check-readonly-selftest-")
    try:
        for index, (name, body, expected) in enumerate(SELF_TEST_CASES, start=1):
            case_dir = pathlib.Path(workspace) / f"case{index}"
            case_dir.mkdir(parents=True, exist_ok=True)
            if body is not None:
                (case_dir / "Sample.swift").write_text(body, encoding="utf-8")
            hits: list[tuple[int, str, str]] = []
            for path in swift_files(case_dir):
                hits.extend(scan_file(path))
            found = sorted({token for _, token, _ in hits})
            want = sorted(set(expected))
            if found != want:
                failures += 1
                print(f"   ❌ 例 {index}（{name}）：期望命中 {want}，实际 {found}")
            else:
                print(f"   ✅ 例 {index}（{name}）：命中 {found}")
    finally:
        shutil.rmtree(workspace, ignore_errors=True)

    if failures:
        print(f"❌ 自检判红：{failures}/{len(SELF_TEST_CASES)} 例不符")
        return 1
    print(f"✅ 自检通过：{len(SELF_TEST_CASES)}/{len(SELF_TEST_CASES)} 例")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Retro macOS 只读机械证明（FR-R-13-08 判据 ③ / IR-05 不变量 7）")
    parser.add_argument("--self-test", action="store_true", help="跑判据本体的负例自检（不依赖仓库状态）")
    args = parser.parse_args()

    if args.self_test:
        return run_self_test()

    print("== 只读机械证明（视图层 + 领域层：对包目录的写调用 0 命中）")
    return run_proof()


if __name__ == "__main__":
    sys.exit(main())
