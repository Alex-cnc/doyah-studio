#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从 vendored `sqlite3.h` 里**生成** Swift 常量表（`platform/macos/Core/NoteStorage/SQLiteConstants.swift`）。

**为什么需要这一步（不是洁癖）**：Swift 侧只要大量引用 C 宏常量，SwiftPM 的构建就会把这个
绑定目标判进**显式模块构建**（`-explicit-swift-module-map-file` + `-Xcc -fno-implicit-modules`），
而在这一档下 vendored 的 clang 模块**进不了那张模块表** —— 症状是 `import CSQLite3` 不报错、
但所有声明都「cannot find in scope」。实测对照（第 18 轮，逐条排除）：
  · 同样的目标、同样的依赖，只把 `codeName` 那个 switch 从 37 个 `case SQLITE_*` 缩到 3 个
    ⇒ 导入恢复正常（文件大小已排除：66KB 的填充文件能编）；
  · 因此口径是：**Swift 侧不引用 C 宏**，只调用 C 函数；宏的值从**头文件生成**成 Swift 常量。

值**从头文件读**、不手抄：`#define SQLITE_OK 0` 这类宏就是整数常量，本脚本把它算成 `Int32`，
写成 `internal let`。这样换版本时值会跟着走，而「生成物是否与头文件一致」由**本脚本的 `--check`**
逐字节判（陈旧 / 手改 ⇒ 报红、并指名生成物文件）。

**更正一处错述（L-43，开发循环第 30 轮）**：本文件此前写着「由
`Scripts/check-vendored-sqlite.py` 反向核对」—— **那句话是错的**：台账门禁从来不跑生成器，
它只对账 vendored 引擎自己的哈希 / 宏 / 接线。真正判「生成物是否过期」的只有本脚本的 `--check`，
而它**当时没进闭环** ⇒ 生成物漂移谁都不会报红。本轮接进 `verify-all.sh` **第 18 项**。

用法：
    python3 Scripts/gen-sqlite-constants.py             # 按需生成（内容不变时不写盘）
    python3 Scripts/gen-sqlite-constants.py --check     # 只核对（闭环用，不一致非零退出）
    python3 Scripts/gen-sqlite-constants.py --self-test # 负例自检（门禁自己也要有证据）

**三者的绑定**（生成器 ↔ 生成物 ↔ vendored 头文件版本）登记在 `Scripts/vendored-sqlite.json`
的 `generator` 节点，由 `Scripts/check-vendored-sqlite.py` 逐条对账（台账撒谎 / 接线被删 ⇒ 报红）。

`--root` 是给 `--self-test` 用的：负例一律在**临时目录**里写坏，绝不碰真仓库。
"""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

HEADER_REL = "platform/macos/Vendor/sqlite3/Sources/CSQLite3/include/sqlite3.h"
# 第 21 轮（L-25 第 2 批）接线：绑定层从 `Docs/design/待接线-SQLiteKit/` 挪进产品源码
# `platform/macos/Core/NoteStorage/`，本脚本跟着挪进 `Scripts/`，路径同步更新。
WRAPPER_REL = "platform/macos/Core/NoteStorage/SQLiteKit.swift"
OUTPUT_REL = "platform/macos/Core/NoteStorage/SQLiteConstants.swift"

# 取哪些常量：正文里用到的那些（按引用扫，不靠人记）——「生成的清单」与「实际用法」不许各说各话。
USE_PATTERN = re.compile(r"\bSQLiteMacro\.([a-z0-9_]+)Macro\b")
DEFINE_PATTERN = re.compile(r"^#\s*define\s+(SQLITE_[A-Z0-9_]+)\s+([^/\n]+?)\s*(?:/\*.*)?$")

HEADER_NOTE = '''// ⚠️ 本文件由 `Scripts/gen-sqlite-constants.py` **生成**，不要手改。
// 重跑生成器即可；「生成物 ↔ 头文件」是否一致由 `python3 Scripts/gen-sqlite-constants.py --check` 判
// —— **已接进 `Scripts/verify-all.sh` 第 18 项**（与 `--self-test` 一起跑；队列 L-43、第 30 轮），
// 生成物被手改一行、或头文件换版后没重生成，闭环当场报红并指名本文件。
//
// 为什么有这份「Swift 侧的常量表」：第 18 轮实测，Swift 侧**大量**引用 C 宏常量会把绑定目标判进
// SwiftPM 的显式模块构建档，而那一档下 vendored 的 clang 模块进不了模块表 —— 症状是
// `import CSQLite3` 不报错、所有声明却「cannot find in scope」。
// 口径因此是：**Swift 只调用 C 函数、不引用 C 宏**，宏的值从头文件生成。
// 第 21 轮接线时 `import CSQLite3` 在 `DoyahCore` 目标里可用（Core 已编译通过、单测跑过）；
// **宏引用的规模阈值本轮未再复测**，所以这条纪律照旧保留。
//
// 值来源：`platform/macos/Vendor/sqlite3/Sources/CSQLite3/include/sqlite3.h`（版本见 `platform/macos/Vendor/sqlite3/PROVENANCE.md`）。

import Foundation

/// SQLite 的 C 宏常量（值从 vendored 头文件生成；只收正文实际用到的那些）。
internal enum SQLiteMacro {
'''


def sources(root: pathlib.Path) -> tuple[pathlib.Path, pathlib.Path, pathlib.Path]:
    """三份文件的位置（`root` 可换 ⇒ 负例能在临时目录里跑）。"""
    return (root / HEADER_REL, root / WRAPPER_REL, root / OUTPUT_REL)


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


def used_macros(wrapper: pathlib.Path) -> list[tuple[str, str]]:
    """正文引用到的常量：返回 `(宏名, Swift 成员名)`，按 Swift 成员名排序。

    只认 `SQLiteMacro.<小写>Macro` 这种引用形状 —— 「生成了什么」与「正文用了什么」
    因此是一份数据（多生成 / 少生成都会被门禁和编译分别抓出来）。

    **形状限制（如实写，免得后来人白试）**：成员名限定 `[a-z0-9_]`（本工程既有成员一律
    `open_readonly` 这种小写 + 下划线）。写成 camelCase 的引用**本函数看不见** ——
    后果不是静默，而是那个常量根本没生成 ⇒ Swift 侧编译报「cannot find in scope」，
    属于当场就响声的那一类（本轮负例夹具一开始就踩在这个形状上，已记在 `_add_unknown_reference`）。
    """
    text = wrapper.read_text(encoding="utf-8")
    members = {member for member in USE_PATTERN.findall(text)}
    pairs = [(f"SQLITE_{member.upper()}", member) for member in members]
    return sorted(pairs, key=lambda pair: pair[1])


def defined_macros(header: pathlib.Path) -> dict[str, int]:
    values: dict[str, int] = {}
    for line in header.read_text(encoding="utf-8").splitlines():
        match = DEFINE_PATTERN.match(line)
        if not match:
            continue
        name, raw = match.group(1), match.group(2)
        value = evaluate(raw)
        if value is not None:
            values[name] = value
    return values


def render(root: pathlib.Path) -> tuple[str, list[str], list[str]]:
    header, wrapper, _ = sources(root)
    macros = defined_macros(header)
    body_lines: list[str] = []
    missing: list[str] = []
    for macro_name, member in used_macros(wrapper):
        if macro_name not in macros:
            missing.append(f"{member}（{macro_name}）")
            continue
        body_lines.append(f"    internal static let {member}Macro: Int32 = {macros[macro_name]}")
    text = HEADER_NOTE + "\n".join(body_lines) + "\n}\n"
    return text, missing, sorted(macros)


def main() -> int:
    parser = argparse.ArgumentParser(description="从 vendored sqlite3.h 生成 Swift 常量表")
    parser.add_argument("--check", action="store_true", help="只核对（闭环用），不一致非零退出")
    parser.add_argument("--self-test", action="store_true", help="负例自检（临时目录里写坏）")
    parser.add_argument("--root", default=str(pathlib.Path(__file__).resolve().parent.parent))
    args = parser.parse_args()
    root = pathlib.Path(args.root).resolve()

    if args.self_test:
        return self_test(root)

    output = sources(root)[2]
    text, missing, _ = render(root)
    if missing:
        print("❌ 头文件里找不到这些宏（名字写错？宏被改名？）：")
        for name in missing:
            print("   " + name)
        return 1
    current = output.read_text(encoding="utf-8") if output.exists() else None
    if args.check:
        if current != text:
            print(f"❌ {output.relative_to(root)} 与头文件生成结果不一致（陈旧或手改过）")
            print("   修法：重跑 `python3 Scripts/gen-sqlite-constants.py`（不要手改生成物）")
            return 1
        print(f"✅ {output.relative_to(root)} 与 vendored 头文件一致")
        return 0
    if current == text:
        print(f"✅ {output.relative_to(root)} 无需更新（内容一致）")
        return 0
    output.write_text(text, encoding="utf-8")
    print(f"✅ 已生成 {output.relative_to(root)}（{len(text.splitlines())} 行）")
    return 0


# ── 负例自检（队列 L-43 ②）────────────────────────────────────────────────────
# 这一族缺陷的共同点：**不会有任何症状**。手改生成物一行、头文件换版忘了重生成，
# 编译照样过、单测照样绿 —— 只有三端行为悄悄不一致。所以「门禁真的会红」这件事本身要有证据。

SELF_TEST_TARGETS = [HEADER_REL, WRAPPER_REL, OUTPUT_REL]


def _tamper_output_one_value(copy: pathlib.Path) -> None:
    """手改生成物一行（把 `okMacro` 的值从 0 改成 1）—— 伪装成「顺手修了一下」。"""
    output = copy / OUTPUT_REL
    text = output.read_text(encoding="utf-8")
    tampered = re.sub(r"^(    internal static let okMacro: Int32 = )0$", r"\g<1>1", text, flags=re.MULTILINE)
    assert tampered != text, "夹具失效：生成物里没有 okMacro 行（成员名改过？）"
    output.write_text(tampered, encoding="utf-8")


def _delete_output(copy: pathlib.Path) -> None:
    (copy / OUTPUT_REL).unlink()


def _tamper_header_value(copy: pathlib.Path) -> None:
    """改头文件里的宏值（`SQLITE_OK 0` → `1`）⇒ 生成物相对头文件已经过期。"""
    header = copy / HEADER_REL
    text = header.read_text(encoding="utf-8")
    tampered = re.sub(r"^#define SQLITE_OK(\s+)0(\s*/\*)", r"#define SQLITE_OK\g<1>1\g<2>", text, flags=re.MULTILINE)
    assert tampered != text, "夹具失效：头文件里没有 `#define SQLITE_OK  0   /* … */` 这一行"
    header.write_text(tampered, encoding="utf-8")


def _drop_used_macro(copy: pathlib.Path) -> None:
    """从头文件删掉一个**正文正在用**的宏 —— 生成器必须报「找不到这些宏」并点名。"""
    header = copy / HEADER_REL
    text = header.read_text(encoding="utf-8")
    tampered = re.sub(r"^#define SQLITE_MISUSE\b.*\n", "", text, flags=re.MULTILINE)
    assert tampered != text, "夹具失效：头文件里没有 `#define SQLITE_MISUSE`"
    header.write_text(tampered, encoding="utf-8")


def _add_unknown_reference(copy: pathlib.Path) -> None:
    """反方向：正文新引用一个头文件里没有的宏（「用了什么」同样是一份数据）。

    成员名必须是小写 + 下划线（`USE_PATTERN` 的形状，见 `used_macros` 的说明）——
    夹具写 camelCase 会连引用都认不出来，这条负例就白跑了（本轮实测踩到过一次）。
    """
    wrapper = copy / WRAPPER_REL
    text = wrapper.read_text(encoding="utf-8")
    wrapper.write_text(text + "\nprivate let __selfProbeOnly = SQLiteMacro.zselfprobeMacro\n", encoding="utf-8")


def self_test(root: pathlib.Path) -> int:
    """每一类篡改都必须让 `--check` 红、且**指名出处**；末例核对真仓库逐字节未变。"""
    print("==> SQLite 常量生成器负例自检")
    before = {
        relative: hashlib.sha256((root / relative).read_bytes()).hexdigest()
        for relative in SELF_TEST_TARGETS
        if (root / relative).exists()
    }

    script = str(pathlib.Path(__file__).resolve())
    cases: list[tuple[str, object | None, bool, str | None]] = [
        # (说明, 篡改函数（None = 原样基线）, 是否应当报红, 输出里必须出现的字样)
        ("基线（原样副本）", None, False, "与 vendored 头文件一致"),
        ("手改生成物一行的值", _tamper_output_one_value, True, "SQLiteConstants.swift"),
        ("生成物文件丢失", _delete_output, True, "SQLiteConstants.swift"),
        ("头文件宏值被改（生成物过期）", _tamper_header_value, True, "SQLiteConstants.swift"),
        ("头文件删掉正文在用的宏", _drop_used_macro, True, "misuse（SQLITE_MISUSE）"),
        ("正文新引用头文件里没有的宏", _add_unknown_reference, True, "zselfprobe（SQLITE_ZSELFPROBE）"),
    ]

    failures: list[str] = []
    for index, (label, mutate, expect_red, expect_text) in enumerate(cases, start=1):
        with tempfile.TemporaryDirectory(prefix="gen-sqlite-constants-selftest-") as tmp:
            copy = pathlib.Path(tmp)
            for relative in SELF_TEST_TARGETS:
                target = copy / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(root / relative, target)
            if mutate is not None:
                mutate(copy)  # type: ignore[operator]
            result = subprocess.run(
                [sys.executable, script, "--root", str(copy), "--check"],
                capture_output=True, text=True,
            )
            output = result.stdout + result.stderr
            went_red = result.returncode != 0
            ok = went_red == expect_red and (expect_text is None or expect_text in output)
            detail = "报红" if went_red else "没报红"
            if expect_red and expect_text and expect_text not in output:
                detail += f"，但输出没指名 `{expect_text}`"
            print(f"   {'✅' if ok else '❌'} 负例 {index}：{label} → {detail}")
            if not ok:
                failures.append(label)

    after = {
        relative: hashlib.sha256((root / relative).read_bytes()).hexdigest()
        for relative in SELF_TEST_TARGETS
        if (root / relative).exists()
    }
    if before != after:
        print("❌ 自检改动了真仓库（夹具没隔离干净）")
        failures.append("真仓库被改动")

    if failures:
        print(f"❌ 有 {len(failures)} 条负例没达到预期：" + "、".join(failures))
        return 1
    print(f"✅ 负例自检通过（{len(cases) - 1} 条篡改全部被抓，真仓库逐字节未变）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
