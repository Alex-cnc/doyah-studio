#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从 vendored `sqlite3.h` 里**生成** Swift 常量表（`SQLiteKit/SQLiteConstants.swift`）。

**为什么需要这一步（不是洁癖）**：Swift 侧只要大量引用 C 宏常量，SwiftPM 的构建就会把这个
绑定目标判进**显式模块构建**（`-explicit-swift-module-map-file` + `-Xcc -fno-implicit-modules`），
而在这一档下 vendored 的 clang 模块**进不了那张模块表** —— 症状是 `import CSQLite3` 不报错、
但所有声明都「cannot find in scope」。实测对照（第 18 轮，逐条排除）：
  · 同样的目标、同样的依赖，只把 `codeName` 那个 switch 从 37 个 `case SQLITE_*` 缩到 3 个
    ⇒ 导入恢复正常（文件大小已排除：66KB 的填充文件能编）；
  · 因此口径是：**Swift 侧不引用 C 宏**，只调用 C 函数；宏的值从**头文件生成**成 Swift 常量。

值**从头文件读**、不手抄：`#define SQLITE_OK 0` 这类宏就是整数常量，本脚本把它算成 `Int32`，
写成 `internal let`。这样换版本时值会跟着走，而「生成物是否与头文件一致」由
`Scripts/check-vendored-sqlite.py` 反向核对（陈旧 / 手改 ⇒ 报红）。

用法：
    python3 Scripts/gen-sqlite-constants.py            # 按需生成（内容不变时不写盘）
    python3 Scripts/gen-sqlite-constants.py --check    # 只核对（CI / 门禁用，不一致非零退出）
"""

from __future__ import annotations

import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
HEADER = REPO / "Vendor" / "sqlite3" / "Sources" / "CSQLite3" / "include" / "sqlite3.h"
# 第 21 轮（L-25 第 2 批）接线：绑定层从 `Docs/design/待接线-SQLiteKit/` 挪进产品源码
# `Core/NoteStorage/`，本脚本跟着挪进 `Scripts/`，路径同步更新。
WRAPPER = REPO / "Core" / "NoteStorage" / "SQLiteKit.swift"
OUTPUT = REPO / "Core" / "NoteStorage" / "SQLiteConstants.swift"

# 取哪些常量：正文里用到的那些（按引用扫，不靠人记）——「生成的清单」与「实际用法」不许各说各话。
USE_PATTERN = re.compile(r"\bSQLiteMacro\.([a-z0-9_]+)Macro\b")
DEFINE_PATTERN = re.compile(r"^#\s*define\s+(SQLITE_[A-Z0-9_]+)\s+([^/\n]+?)\s*(?:/\*.*)?$")

HEADER_NOTE = '''// ⚠️ 本文件由 `Scripts/gen-sqlite-constants.py` **生成**，不要手改。
// 重跑生成器即可；「生成物 ↔ 头文件」是否一致由 `python3 Scripts/gen-sqlite-constants.py --check` 判
// （**当前未接进 `verify-all.sh`**，见队列条目 —— 别以为门禁替你看着）。
//
// 为什么有这份「Swift 侧的常量表」：第 18 轮实测，Swift 侧**大量**引用 C 宏常量会把绑定目标判进
// SwiftPM 的显式模块构建档，而那一档下 vendored 的 clang 模块进不了模块表 —— 症状是
// `import CSQLite3` 不报错、所有声明却「cannot find in scope」。
// 口径因此是：**Swift 只调用 C 函数、不引用 C 宏**，宏的值从头文件生成。
// 第 21 轮接线时 `import CSQLite3` 在 `DoyahCore` 目标里可用（Core 已编译通过、单测跑过）；
// **宏引用的规模阈值本轮未再复测**，所以这条纪律照旧保留。
//
// 值来源：`Vendor/sqlite3/Sources/CSQLite3/include/sqlite3.h`（版本见 `Vendor/sqlite3/PROVENANCE.md`）。

import Foundation

/// SQLite 的 C 宏常量（值从 vendored 头文件生成；只收正文实际用到的那些）。
internal enum SQLiteMacro {
'''


def evaluate(expression: str) -> int | None:
    """把 `0` / `(1<<2)` / `0x00000040` 这类整数宏算出来；算不动就返回 None（不猜）。"""
    text = expression.strip()
    # 去掉尾部说明性文本（头文件里有的宏后面跟着 `/* ... */` 或纯文字）
    text = text.split("/*")[0].strip()
    if not re.fullmatch(r"[0-9a-fA-FxX()<>&|+\- ]+", text):
        return None
    try:
        value = eval(text.replace("<<", "<<").replace(">>", ">>"), {"__builtins__": {}}, {})  # noqa: S307
    except Exception:
        return None
    return int(value)


def used_macros() -> list[tuple[str, str]]:
    """正文引用到的常量：返回 `(宏名, Swift 成员名)`，按 Swift 成员名排序。

    只认 `SQLiteMacro.<小写>Macro` 这种引用形状 —— 「生成了什么」与「正文用了什么」
    因此是一份数据（多生成 / 少生成都会被门禁和编译分别抓出来）。
    """
    text = WRAPPER.read_text(encoding="utf-8")
    members = {member for member in USE_PATTERN.findall(text)}
    pairs = [(f"SQLITE_{member.upper()}", member) for member in members]
    return sorted(pairs, key=lambda pair: pair[1])


def defined_macros() -> dict[str, int]:
    values: dict[str, int] = {}
    for line in HEADER.read_text(encoding="utf-8").splitlines():
        match = DEFINE_PATTERN.match(line)
        if not match:
            continue
        name, raw = match.group(1), match.group(2)
        value = evaluate(raw)
        if value is not None:
            values[name] = value
    return values


def render() -> tuple[str, list[str], list[str]]:
    macros = defined_macros()
    body_lines: list[str] = []
    missing: list[str] = []
    for macro_name, member in used_macros():
        if macro_name not in macros:
            missing.append(f"{member}（{macro_name}）")
            continue
        body_lines.append(f"    internal static let {member}Macro: Int32 = {macros[macro_name]}")
    text = HEADER_NOTE + "\n".join(body_lines) + "\n}\n"
    return text, missing, sorted(macros)


def main() -> int:
    check_only = "--check" in sys.argv
    text, missing, _ = render()
    if missing:
        print("❌ 头文件里找不到这些宏（名字写错？宏被改名？）：")
        for name in missing:
            print("   " + name)
        return 1
    current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else None
    if check_only:
        if current != text:
            print(f"❌ {OUTPUT.relative_to(REPO)} 与头文件生成结果不一致（陈旧或手改过）")
            return 1
        print(f"✅ {OUTPUT.relative_to(REPO)} 与 vendored 头文件一致")
        return 0
    if current == text:
        print(f"✅ {OUTPUT.relative_to(REPO)} 无需更新（内容一致）")
        return 0
    OUTPUT.write_text(text, encoding="utf-8")
    print(f"✅ 已生成 {OUTPUT.relative_to(REPO)}（{len(text.splitlines())} 行）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
