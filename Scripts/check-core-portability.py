#!/usr/bin/env python3
"""Core 平台中立性闸门：Core 里不得出现任何平台专属依赖。

存在的理由（实测，2026-09-23）：
    问「换到 Linux 会不会报错」时，先看的是 `/Users/<用户名>` 这类绝对路径 —— 结果它们是
    **注入参数的测试、注释和文档**，纯字符串，换平台毫无影响。真正会挂的是 Core 里的
    三处 macOS 专属依赖：

      1. `Core/KeychainHelper.swift`          —— `import Security`（钥匙串实现）
      2. `Core/AgentConfigurationStore.swift` —— `import Security`（同上）
      3. `Core/SecureDirectoryAccess.swift`   —— macOS-only 的 Foundation 书签 API
      4. `Core/AppError.swift`                —— `OSStatus`（Darwin 类型）

    Linux 上没有这些模块/类型，Core 会**直接编译不过**。已把它们移到 `Platform/macOS/`
    平台模块（Core 只留协议），本脚本负责让它不再回潮。

口径：
    · 只管 `<根>/Core/**/*.swift` —— 平台模块与 App 本来就该写平台实现，不在此列；
    · **判定物 = 剥掉注释后的代码**（2026-10-13 起）：字符串字面量与注释里的字样不算出现
      （与 `Scripts/verify-all.sh` 第 5 项注释、`check-editor-surface-tokens.py` 同一口径）；
    · 确有必要时在该行加 `// portability-ok: 理由` 显式豁免 —— **注释位**才算；字符串字面量
      里的同名字样不构成豁免（旧判定是裸子串，`import Security; let note = "portability-ok"`
      曾判绿）；
    · **空跑防护**（2026-10-13 补）：扫描面文件数 / 代码行数两条下限 + 读数行。判据取不到输入
      （`Core/` 不在根上 / 面被砍到底）时**判红**，不许打「✅ 通过」—— 现场实测：从没有
      `Core/` 的目录用绝对路径跑，旧版打印「✅ …校验通过」且 `rc=0`（零文件被扫 = 假绿）；
    · **根不是 CWD**：根 = 本脚本所在仓（`__file__` 推导），`--root <树>` 可覆盖。

用法：
    python3 Scripts/check-core-portability.py              # 校验（闸门）
    python3 Scripts/check-core-portability.py --report     # 列出命中 + 扫描面读数
    python3 Scripts/check-core-portability.py --root <树>  # 指定仓根（自检在临时副本上用）
    python3 Scripts/check-core-portability.py --self-test  # 判据自己的证据（9 例 · 临时副本写坏）
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

# 判据的立足点：**本脚本所在仓**的根（不是 CWD —— 从别的目录跑必须读数一致）。
REPO = pathlib.Path(__file__).resolve().parent.parent
EXEMPT_MARK = "portability-ok"

# 空跑防护下限（2026-10-13 实测：`Core/**/*.swift` = 200 份 / 47330 代码行 ⇒ 取下限留余量）。
FLOOR_FILES = 150
FLOOR_CODE_LINES = 30000

RULES: dict[str, str] = {
    "平台专属模块 import（Linux 上没有这个模块，编译直接失败）":
        r"^\s*(?:@preconcurrency\s+)?import\s+(AppKit|SwiftUI|Security|Cocoa|CoreGraphics|Combine|Darwin|Glibc|XCTest|Metal|CoreData)\b",
    "Darwin / Security 类型与常量":
        r"\b(OSStatus|CFDictionary|CFTypeRef|CFString|CFArray|SecItem[A-Za-z]*|kSec[A-Za-z]+|errSec[A-Za-z]+)\b",
    "macOS 专属的 AppKit 类型":
        r"\b(NSView|NSWindow|NSColor|NSFont|NSImage|NSPasteboard|NSSavePanel|NSOpenPanel|NSTableView|NSTextView|NSApplication)\b",
    "macOS 专属的 Foundation API（安全作用域书签 / 沙箱授权）":
        r"(withSecurityScope|resolvingBookmarkData|startAccessingSecurityScopedResource|stopAccessingSecurityScopedResource|bookmarkData\(\s*options)",
    "平台条件编译（Core 里不该有「这台机器是哪个平台」的判断）":
        r"#if\s+(os\(|canImport\((Darwin|Security|AppKit|SwiftUI|Cocoa)\))",
    "硬编码绝对路径":
        r"\"/(Users|Applications|Library|System|opt/|usr/local)/",
}

STRING_LITERAL = re.compile(r'"(?:[^"\\]|\\.)*"')


def split_code_comment(line: str) -> tuple[str, str]:
    """按「剥掉字符串字面量后的第一个 `//`」切出 (代码, 注释)。

    为什么先剥字符串：豁免令牌只认**注释位**。`import Security; let note = "portability-ok"`
    里的字样落在字符串字面量里（不在注释里）⇒ **不构成豁免**（旧判定是裸子串，那一行曾判绿）。
    """
    scrubbed = STRING_LITERAL.sub('""', line)
    index = scrubbed.find("//")
    if index < 0:
        return line, ""
    return line[:index], line[index:]


def scan(root: pathlib.Path) -> tuple[list[tuple[str, str, int, str, str]], dict[str, int]]:
    """返回 ([(规则, 相对路径, 行号, 命中文本, 整行)], 扫描面读数)。"""
    core = root / "Core"
    files = sorted(core.rglob("*.swift")) if core.is_dir() else []
    findings: list[tuple[str, str, int, str, str]] = []
    code_lines = 0
    for path in files:
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            code, comment = split_code_comment(line)
            if code.strip():
                code_lines += 1
            if EXEMPT_MARK in comment:
                continue        # 豁免只认注释位（理由写在注释里）
            for label, pattern in RULES.items():
                for match in re.finditer(pattern, code):
                    findings.append(
                        (label, path.relative_to(root).as_posix(), number, match.group(0), line.strip())
                    )
    return findings, {"files": len(files), "codeLines": code_lines}


def scan_problems(stats: dict[str, int]) -> list[str]:
    """空跑防护：取不到输入（或扫描面被砍）时必须判红。"""
    problems: list[str] = []
    if stats["files"] < FLOOR_FILES:
        problems.append(f"扫描面只有 {stats['files']} 个 .swift（下限 {FLOOR_FILES}）")
    if stats["codeLines"] < FLOOR_CODE_LINES:
        problems.append(f"扫描面的代码行只有 {stats['codeLines']}（下限 {FLOOR_CODE_LINES}）")
    return problems


def run(root: pathlib.Path, report: bool) -> int:
    findings, stats = scan(root)
    readout = f"扫描面 {stats['files']} 个 .swift（代码行 {stats['codeLines']}）"
    if report:
        for label, path, number, hit, line in findings:
            print(f"{path}:{number}  [{label}] → {hit}")
            print(f"    {line[:120]}")
        print(readout)
        print(f"合计 {len(findings)} 处")
        return 0

    problems = scan_problems(stats)
    if problems:
        print("❌ Core 平台中立性校验**无法进行**（空跑防护）：" + "；".join(problems))
        print("   判据取不到输入时不许判绿 —— 请从本仓根跑，或用 `--root <树>` 指定仓根。")
        return 1
    if not findings:
        print(f"✅ Core 平台中立性校验通过（无平台专属依赖 —— 换平台不会编译失败）；{readout}")
        return 0

    print(f"❌ Core 平台中立性校验失败：{len(findings)} 处平台专属依赖")
    for label, path, number, hit, line in findings:
        print(f"   {path}:{number}  [{label}] → {hit}")
    print("   修法：协议留在 Core，实现移到 Platform/macOS/；确有必要时加 // portability-ok: 理由。")
    return 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Core 平台中立性闸门（Scripts/check-core-portability.py）")
    parser.add_argument("--root", default=None, help="仓根（默认 = 本脚本所在仓）")
    parser.add_argument("--report", action="store_true", help="列出命中 + 扫描面读数（不判红）")
    parser.add_argument("--self-test", action="store_true", help="判据自己的证据（临时副本上写坏）")
    return parser


SCRIPT = REPO / "Scripts/check-core-portability.py"
SUBJECT = "Core/AppError.swift"      # 自检夹具一律改这一份（它在扫描面里）


def run_self_test() -> int:
    """判据自己的证据（9 例）：一律在临时副本上写坏，末例核对真仓库逐字节未变。"""
    failures: list[str] = []
    total = 0
    scratch = pathlib.Path(tempfile.mkdtemp(prefix="doyah-core-portability-"))
    before = hashlib.sha256(SCRIPT.read_bytes()).hexdigest()

    def invoke(root: pathlib.Path | None, cwd: pathlib.Path, extra: tuple[str, ...] = ()) -> tuple[int, str]:
        command = [sys.executable, str(SCRIPT)]
        if root is not None:
            command += ["--root", str(root)]
        command += list(extra)
        completed = subprocess.run(command, cwd=str(cwd), capture_output=True, text=True)
        return completed.returncode, completed.stdout + completed.stderr

    def clone(name: str) -> pathlib.Path:
        where = scratch / name
        where.mkdir(parents=True)
        shutil.copytree(REPO / "Core", where / "Core")
        return where

    def append_line(where: pathlib.Path, text: str) -> None:
        target = where / SUBJECT
        target.write_text(target.read_text(encoding="utf-8") + "\n" + text + "\n", encoding="utf-8")

    def case(description: str, check) -> None:
        nonlocal total
        total += 1
        problem = check()
        if problem:
            failures.append(f"例 {total} 失败：{description} —— {problem}")

    # 例 1：真违规 ⇒ 判红并点名
    def check_violation():
        where = clone("violation")
        append_line(where, "import Security")
        code, output = invoke(where, where)
        if code == 0:
            return "真违规仍 rc=0"
        if f"{SUBJECT}:" not in output:
            return f"判红了但没点名 {SUBJECT}\n{output}"
        return None
    case("Core 里真写 `import Security` ⇒ 判红并点名", check_violation)

    # 例 2：字符串字面量里的令牌**不豁免**（旧判定是裸子串 ⇒ 这一行曾判绿）
    def check_string_token():
        where = clone("string-token")
        append_line(where, 'import Security; let note = "portability-ok"')
        code, output = invoke(where, where)
        if code == 0:
            return "字符串字面量里的 portability-ok 把真违规顶掉了（豁免仍是裸子串）"
        if f"{SUBJECT}:" not in output:
            return f"判红了但没点名 {SUBJECT}\n{output}"
        return None
    case("字符串字面量里的 `portability-ok` 不构成豁免 ⇒ 仍判红", check_string_token)

    # 例 3：注释位豁免**该绿**
    def check_comment_exemption():
        where = clone("comment-exempt")
        append_line(where, "import Security // portability-ok: 该文件是平台实现的唯一入口")
        code, output = invoke(where, where)
        if code != 0:
            return f"注释位豁免没走通（rc={code}）\n{output}"
        return None
    case("注释位 `// portability-ok: 理由` ⇒ 该行豁免（rc=0）", check_comment_exemption)

    # 例 4：注释里的平台字样**不算出现**（剥注释口径，与 verify-all 第 5 项同源）
    def check_comment_only():
        where = clone("comment-only")
        append_line(where, "// 历史：这里曾 import Security")
        code, output = invoke(where, where, ("--report",))
        if code != 0:
            return f"`--report` 都判红了（rc={code}）\n{output}"
        if "合计 0 处" not in output:
            return f"注释里的字样被当成出现（该 0 处）\n{output}"
        return None
    case("纯注释里的 `import Security` 不算出现（剥注释口径）⇒ 0 处", check_comment_only)

    # 例 5：`Core/` 不在根上 ⇒ 空跑防护判红（旧版打印「✅ 通过」rc=0）
    def check_missing_core():
        where = scratch / "no-core"
        where.mkdir()
        code, output = invoke(where, where)
        if code == 0:
            return "没有 `Core/` 仍 rc=0 —— 空跑防护没起作用"
        if "空跑防护" not in output:
            return f"判红了但不是空跑防护那一条\n{output}"
        return None
    case("`Core/` 不在根上（或改名）⇒ 空跑防护判红", check_missing_core)

    # 例 6：扫描面被砍到底 ⇒ 空跑防护判红
    def check_pruned():
        where = clone("pruned")
        files = sorted((where / "Core").rglob("*.swift"))
        for path in files[3:]:
            path.unlink()
        code, output = invoke(where, where)
        if code == 0:
            return "扫描面只剩 3 份仍 rc=0 —— 空跑防护没起作用"
        if "空跑防护" not in output:
            return f"判红了但不是空跑防护那一条\n{output}"
        return None
    case("扫描面被砍到底（只剩 3 份）⇒ 空跑防护判红", check_pruned)

    # 例 7：未知参数不再被静默吞掉（旧实现：`--self-test` / `--nonsense` 都走正常扫描 ⇒ 「✅ 通过」）
    def check_unknown_arg():
        code, output = invoke(None, REPO, ("--nonsense",))
        if code == 0:
            return "未知参数仍 rc=0（静默吞掉）"
        return None
    case("未知参数 ⇒ rc≠0（不再静默吞掉）", check_unknown_arg)

    # 例 8：从仓根之外的 CWD 跑（不给 `--root`）⇒ 读数与仓根一致（根按 `__file__` 推导）
    def check_foreign_cwd():
        code, output = invoke(None, pathlib.Path(tempfile.gettempdir()))
        if code != 0:
            return f"从仓外 CWD 跑判红了（rc={code}）\n{output}"
        expected = len(sorted((REPO / "Core").rglob("*.swift")))
        if f"扫描面 {expected} 个 .swift" not in output:
            return f"读数没打扫描面文件数（该 {expected}）\n{output}"
        return None
    case("从仓根之外的 CWD 跑 ⇒ 读数与仓根一致", check_foreign_cwd)

    # 例 9：真仓库逐字节未变 + 真仓实跑绿
    def check_repository_untouched():
        if hashlib.sha256(SCRIPT.read_bytes()).hexdigest() != before:
            return "自检改动了真仓库的脚本"
        code, output = invoke(None, REPO)
        if code != 0:
            return f"真仓实跑不是绿（rc={code}）\n{output}"
        return None
    case("真仓库逐字节未变 + 真仓实跑 rc=0", check_repository_untouched)

    shutil.rmtree(scratch, ignore_errors=True)
    for failure in failures:
        print(f"   ❌ {failure}")
    print(f"判据自检：{total} 条中 {total - len(failures)} 条达到预期")
    return 0 if not failures else 1


def main() -> int:
    args = build_parser().parse_args()
    if args.self_test:
        return run_self_test()
    root = pathlib.Path(args.root).expanduser().resolve() if args.root else REPO
    return run(root, args.report)


if __name__ == "__main__":
    raise SystemExit(main())
