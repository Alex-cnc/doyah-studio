#!/usr/bin/env python3
"""`check-language-registry.py` 的**入口证据**（与它自己的 `--self-test` 分工不同）。

为什么两个都要：`--self-test` 走的是脚本内部的函数路径（夹具在临时目录里搭），
而闭环里跑的是**命令行路径**（`python3 Scripts/check-language-registry.py`，带 `--root` 时
由自检用）。两条路都有可能坏，且坏法不同：

- 函数路径坏了 ⇒ 测试里的夹具全过，而闭环里那一次其实什么也没查；
- 命令行路径坏了（参数解析写错、`--root` 不看、退出码没传出来）⇒ 门禁挂得上、跑得动、
  但**判的是错的目录**（这是最坏的一种：绿色是假的）。

所以本脚本只做命令行那一半：真仓库 ⇒ exit 0；临时副本上写坏 ⇒ exit 1（点名到行）；
参数不合法 ⇒ exit 2；末例核对真仓库逐字节未变。

用法：python3 Scripts/test-language-registry-gate.py
"""

from __future__ import annotations

import hashlib
import pathlib
import shutil
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parent.parent
GATE = "Scripts/check-language-registry.py"
WATCHED = (
    "platform/macos/Core/CodeLanguageDefinitions.swift",
    "platform/macos/Core/CodeLexer.swift",
    "platform/macos/App/Views/CodeEditorView.swift",
)
CASES = 4


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run_gate(root: pathlib.Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, GATE, "--root", str(root)],
        cwd=REPO, capture_output=True, text=True, timeout=300,
    )


def main() -> int:
    failures: list[str] = []
    before = {relative: sha(REPO / relative) for relative in WATCHED}

    print("== 例 1：真仓库 ⇒ exit 0 ==")
    result = run_gate(REPO)
    print(result.stdout.strip() or result.stderr.strip())
    if result.returncode != 0:
        failures.append(f"真仓库应当 exit 0，实际 {result.returncode}")
    else:
        print("   ✅ exit 0")

    print("== 例 2：临时副本写坏（消费方出现语言身份分支）⇒ exit 1 并点名 ==")
    scratch = pathlib.Path(tempfile.mkdtemp(prefix="doyah-language-gate-cli-"))
    try:
        for relative in WATCHED + ("platform/macos/Core/CodeSyntax.swift", "platform/macos/Core/TextLanguage.swift",
                                   "platform/macos/Core/CodeCompletion.swift", "platform/macos/App/Views/SQLEditorView.swift",
                                   "platform/macos/CLI/main.swift", "platform/macos/Core/DesignTokens.swift"):
            destination = scratch / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(REPO / relative, destination)
        # 往词法器里塞一句按语言身份分支的写法 —— 正是 FR-EDIT-38 ① 要清掉的形状。
        target = scratch / "platform/macos/Core/CodeLexer.swift"
        text = target.read_text(encoding="utf-8")
        anchor = "    mutating func run() -> [CodeToken] {"
        assert anchor in text, "夹具锚点失效：CodeLexer.swift 里找不到 run() 的签名"
        target.write_text(text.replace(anchor, anchor + "\n        if language == .sql { return [] }"),
                          encoding="utf-8")
        result = run_gate(scratch)
        print(result.stdout.strip() or result.stderr.strip())
        if result.returncode != 1:
            failures.append(f"写坏的副本应当 exit 1，实际 {result.returncode}")
        elif "CodeLexer.swift" not in result.stdout:
            failures.append("判红但没点名到文件（说不出是哪儿坏的判据，等于没判）")
        else:
            print("   ✅ exit 1 且点名 CodeLexer.swift")
    finally:
        shutil.rmtree(scratch, ignore_errors=True)

    print("== 例 3：参数不合法（--root 后面没有目录）⇒ exit 2 ==")
    result = subprocess.run([sys.executable, GATE, "--root"], cwd=REPO,
                            capture_output=True, text=True, timeout=120)
    print(result.stdout.strip() or result.stderr.strip())
    if result.returncode != 2:
        failures.append(f"参数错误应当 exit 2，实际 {result.returncode}")
    else:
        print("   ✅ exit 2")

    print("== 例 4：本脚本没动过真仓库（逐字节） ==")
    after = {relative: sha(REPO / relative) for relative in WATCHED}
    if after != before:
        failures.append("真仓库被改动（夹具一律在临时副本上写坏）")
    else:
        print("   ✅ 三个受检文件 sha256 未变")

    print(f"例数 {CASES} / 通过 {CASES - len(failures)} / 失败 {len(failures)}")
    for failure in failures:
        print(f"   {failure}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
