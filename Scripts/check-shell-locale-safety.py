#!/usr/bin/env python3
"""门禁：`Scripts/**/*.sh` 里不得出现「**裸写** `$变量` 后面紧跟非 ASCII 字符」。

**为什么要有这条**（2026-09-26 开发循环 L-05 实测发现）：

本仓库所有 shell 脚本的 Shebang 都是 `#!/bin/bash`，而在 macOS 上那就是 **bash 3.2.57**。
实测（`LC_CTYPE=C.UTF-8`，本机）：

    X=VALUE
    echo "中文：$X）"            →  打印「中文：）」        ← 值被吞掉，`）` 也被切坏
    echo "中文：$X，"            →  打印「中文：，」
    echo "中文：$X中"            →  打印「中文：中」
    echo "中文：${X}）"          →  打印「中文：VALUE）」   ← 花括号安全
    echo "中文：$X ）"           →  打印「中文：VALUE ）」  ← 隔一个空格也安全
    加 `set -u` 后第一行直接 `X?: unbound variable` **中止脚本**

成因：bash 3.2 在多字节字符集下把后一个多字节字符的**首字节**当成了变量名的续接字节
（报错信息里会看到变量名后面粘了一个乱码字节）。

**危险在于它默认不报错**：证据脚本照常 exit 0、照常打勾，只是那一行的值空了 ——
与 L-04 查出的 `verify-all.sh` 假绿同一族：闭环绿着，而证据本身是残的。
所以这条门禁是**机械**的，不靠人记得。

修法：`${X}`（推荐）或让变量后面跟一个 ASCII 字符 / 空格。

**判定物 = 代码面**（合册 `T-20261013-027` · 原单 `T-20261010-055`，2026-10-14 第 42 轮）：
判定物只对**真会被展开的那部分字节**生效（`mask_shell()`）。旧实现只跳「整行 `#` 开头」，
于是四类**根本不会出 bug 的写法**被判红 —— 与样本 59 的实测逐条对齐：

  1. 行内注释 `echo hi  # 中：$X）` —— 注释里的 `$` 不展开；
  2. 单引号字面量 `echo '中：$X）'` —— 单引号内不展开；
  3. 反斜杠转义 —— 写成反斜杠 + `$X` 时那个 `$` 是字面量，不展开；
  4. 引号定界 heredoc 体（`<<'EOF'` / `<<"EOF"` / `<<\\EOF`）—— 体是字面文本。

`mask_shell()` 把这些区域**等长抹白**（换行保留 ⇒ 行号不动；引号状态**跨行**保持，
引号可以跨行 ⇒ 不是「按行猜」）。三种不再抹白的情形是**故意的**：

  - 双引号**不**抹 —— `$` 在双引号里照样展开，照样是判定物；
  - **未定界**的 heredoc（`<<EOF`）**不**抹 —— 体照样展开，照样算判定物；
  - 单引号里出现「类注释」的 `#` 也不抹 —— 那是字面文本里的一部分，本来就在抹白范围。

**空跑防护**（同轮补）：扫描到的 `.sh` 少于 `MIN_SOURCE_FILES` ⇒ **rc=2**（不是 0）。
理由：面被削到 0 也照样打印「✅」——「绿」分不清「真没违规」与「扫了个寂寞」。

已知边界：不做完整 shell 语法解析（不认 `$(( ))` 与反引号里的引号语义）；判定物只按
「裸写变量名 + 紧跟非 ASCII 字节」的字节形状**在代码面上**匹配，所以不会误报
`${X}` / `$X)` / `$X ）`，也不会把上面四类不展开的写法算成命中。

用法：`python3 Scripts/check-shell-locale-safety.py`（在仓库根跑；0 = 通过，1 = 有命中，2 = 面被削）
"""

import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_DIRS = {".build", ".git", "Vendor", "node_modules"}
# 实测 76 份 .sh（HEAD 3712d05）；下限只增不减，取余量 60
MIN_SOURCE_FILES = 60
# 裸写 $name（不是 ${name}）后面紧跟一个非 ASCII 字节 —— 正是 bash 3.2 出事的那一格
BARE_VAR_BEFORE_MULTIBYTE = re.compile(rb"\$(?!\{)([A-Za-z_][A-Za-z0-9_]*)(?=[\x80-\xff])")

CODE = 0    # 会展开 / 会执行
SINGLE = 1  # 单引号段：字面，整段抹白
DOUBLE = 2  # 双引号段：$ 照常展开，只抹引号与转义字符本身

# 「# 起注释」的 shell 口径：行首，或前一个字节是空白 / 分隔符（`$#`、`${X#y}` 不算注释）
COMMENT_LEAD = b" \t;&|()<>"


def _blank(out, start, stop):
    """等长抹白（换行不在范围里 ⇒ 行号不动）。"""
    out[start:stop] = b" " * (stop - start)


def _lines(content):
    start = 0
    while start <= len(content):
        end = content.find(b"\n", start)
        if end == -1:
            yield start, content[start:]
            return
        yield start, content[start:end]
        start = end + 1


def _comment_here(line, index):
    """`#` 在这个位置起注释吗（shell 口径：行首，或前一个字节是空白 / 分隔符）。"""
    if index == 0:
        return True
    return line[index - 1:index] in (b" ", b"\t", b";", b"&", b"|", b"(", b")", b"<", b">")


def _heredoc_operator(line, index):
    """`line[index:]` 是 heredoc 操作符时返回「结束下标 / 定界词 / 是否引号定界」，否则 None。"""
    if not line.startswith(b"<<", index) or line.startswith(b"<<<", index):
        return None
    cursor = index + 2
    if line.startswith(b"-", cursor):
        cursor += 1
    while cursor < len(line) and line[cursor:cursor + 1] in (b" ", b"\t"):
        cursor += 1
    if cursor >= len(line):
        return None
    head = line[cursor:cursor + 1]
    if head in (b"'", b'"'):
        closer = line.find(head, cursor + 1)
        if closer == -1 or closer == cursor + 1:
            return None
        return closer + 1, line[cursor + 1:closer], True
    match = re.match(rb"\\?[A-Za-z_][A-Za-z0-9_]*", line[cursor:])
    if not match:
        return None  # 只认「字母 / 下划线开头的词」当定界词 —— `$((1<<2))` 这类不误判
    token = match.group(0)
    return cursor + len(token), token.lstrip(b"\\"), token.startswith(b"\\")


def mask_shell(content):
    """把「不会展开的字节」等长抹白，只留真会展开的代码面（换行保留 ⇒ 行号不动）。"""
    out = bytearray(content)
    state = CODE
    pending = []  # 待收体的 heredoc：[(定界词, 是否引号定界)]
    for start, line in _lines(content):
        if pending:
            word, quoted = pending[0]
            if line.strip() == word:
                pending.pop(0)
                continue
            if quoted:
                _blank(out, start, start + len(line))
            continue
        index = 0
        while index < len(line):
            char = line[index:index + 1]
            if state == SINGLE:
                _blank(out, start + index, start + index + 1)
                if char == b"'":
                    state = CODE
                index += 1
                continue
            if char == b"\\":
                if index + 1 < len(line):
                    _blank(out, start + index + 1, start + index + 2)
                index += 2
                continue
            if char == b"'":
                _blank(out, start + index, start + index + 1)
                state = SINGLE
                index += 1
                continue
            if char == b'"':
                _blank(out, start + index, start + index + 1)
                state = CODE if state == DOUBLE else DOUBLE
                index += 1
                continue
            if char == b"#" and state == CODE and _comment_here(line, index):
                _blank(out, start + index, start + len(line))
                break
            if state == CODE and line.startswith(b"<<", index):
                found = _heredoc_operator(line, index)
                if found:
                    index, word, quoted = found
                    pending.append((word, quoted))
                    continue
            index += 1
    return bytes(out)


def scan(paths):
    hits = []
    for path in paths:
        with open(path, "rb") as handle:
            content = handle.read()
        original = content.split(b"\n")
        masked = mask_shell(content).split(b"\n")
        for number, line in enumerate(masked, 1):
            for match in BARE_VAR_BEFORE_MULTIBYTE.finditer(line):
                hits.append((
                    os.path.relpath(path, ROOT),
                    number,
                    "$" + match.group(1).decode("utf-8", "replace"),
                    original[number - 1].decode("utf-8", "replace").strip(),
                ))
    return hits


def main():
    paths = [
        p for p in sorted(glob.glob(os.path.join(ROOT, "**", "*.sh"), recursive=True))
        if not any(f"/{d}/" in p for d in SKIP_DIRS)
    ]
    if len(paths) < MIN_SOURCE_FILES:
        print(f"❌ 只扫到 {len(paths)} 个 .sh（下限 {MIN_SOURCE_FILES}）"
              " —— 扫描根写错 / 脚本被搬走了？面被削时不许当通过。")
        return 2
    hits = scan(paths)
    print(f"扫描 {len(paths)} 个 .sh（bash 3.2 多字节变量名坑）")
    if not hits:
        print("✅ 无「裸写 $变量 + 紧跟非 ASCII 字符」—— 证据脚本不会静默丢值")
        return 0
    print(f"❌ 命中 {len(hits)} 处（变量会展开成空，配 set -u 直接报 unbound variable 中止脚本）：")
    for path, number, token, line in hits:
        print(f"  {path}:{number}  [{token}]  {line}")
    print()
    print("修法：改成 ${变量}（花括号），或让变量后面跟一个 ASCII 字符 / 空格。")
    return 1


if __name__ == "__main__":
    sys.exit(main())
