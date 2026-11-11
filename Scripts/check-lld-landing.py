#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""判据：详细设计里写的「本端落点」必须对得上仓里的真实目录，编造的路径不许过。

覆盖范围（只判这三类，别的不判）：
  ① 本书每一节的「**落点**：」行里出现的反引号路径，必须要么**在仓里存在**，
     要么显式标注「待建」（表示本端还没这个文件，是施工目标而不是现状）。
  ② 「本端实现（Linux）」块必须落在本端技术栈的目录里（`Platform/linux/` 或同源前端），
     不许出现 `crates/` / `apps/desktop/` 这种本仓根本不存在的顶层目录。
  ③ 只判路径，不判语义：路径对了不代表设计对，路径错了就是假落点。

判不了（明示）：符号名是否合理、模块拆分是否恰当、代码是否真的会这么写 —— 这三类靠人读。

负例（--self-test 会跑）：造一段用 `crates/agent/src/x.rs` 的假落点 ⇒ 必须判红。
"""
import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOC = ROOT / "Docs/Doyah产品详细设计说明书-Linux.md"

# 本仓根本不存在的顶层目录（写进落点就是编的）
FAKE_ROOTS = ("crates/", "apps/", "src-tauri/src/agent/")
PENDING = ("待建", "待交接", "同源前端")

PATH_RE = re.compile(r"`([A-Za-z0-9_.\-]+/[A-Za-z0-9_./*\-{}]+)`")
SEC_RE = re.compile(r"(?m)^### (3\.\d+) ")


def landing_lines(text: str):
    """产出 (节号, 行号, 行文本)，只取「落点」与「本端实现」段落里的路径行。"""
    cur = None
    for i, line in enumerate(text.splitlines(), 1):
        m = SEC_RE.match(line)
        if m:
            cur = m.group(1)
        if cur and ("**落点**" in line or "**本端实现（Linux）**" in line):
            yield cur, i, line


def check(text: str):
    problems = []
    checked = 0
    for sec, lineno, line in landing_lines(text):
        for path in PATH_RE.findall(line):
            if path.startswith(("Docs/", "Scripts/", "Platform/", "App/", "Core/", "Tests/", "CLI/", "Plugins/")):
                checked += 1
                # 带通配或占位的不判存在性
                if "*" in path or "{" in path:
                    continue
                exists = (ROOT / path).exists()
                if not exists and not any(k in line for k in PENDING):
                    problems.append((sec, lineno, path, "路径不存在，也没标「待建」"))
                elif exists and any(k in line for k in PENDING):
                    # 标了待建就必须真不存在（否则是过期标注）
                    problems.append((sec, lineno, path, "标了「待建」但文件已存在 —— 标注过期"))
            elif path.startswith(FAKE_ROOTS):
                problems.append((sec, lineno, path, "本仓没有这个顶层目录（编造的落点）"))
    return checked, problems


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--doc", default=str(DOC))
    args = ap.parse_args()

    if args.self_test:
        good = ("### 3.1 甲\n\n- **落点**：`Platform/linux/src-tauri/src/main.rs`\n")
        bad = ("### 3.1 甲\n\n- **落点**：`crates/agent/src/shell_session.rs`\n")
        pending = ("### 3.1 甲\n\n- **落点**：`Platform/linux/src-tauri/Core/src/agent/x.rs`（待建）\n")
        cases = [("真实路径 ⇒ 绿", good, 0), ("编造顶层目录 ⇒ 红", bad, 1), ("标待建 ⇒ 绿", pending, 0)]
        fail = 0
        for name, text, want in cases:
            tmp = ROOT / ".build" / "self-test-landing.md"
            tmp.parent.mkdir(parents=True, exist_ok=True)
            tmp.write_text(text, encoding="utf-8")
            n, probs = check(text)
            got = 1 if probs else 0
            ok = "✅" if got == want else "❌"
            fail += 0 if got == want else 1
            print(f"  {ok} {name}（rc={got}，期望 {want}）")
        print(f"自检 {'通过' if not fail else '失败'} {len(cases)-fail}/{len(cases)}")
        return 1 if fail else 0

    text = Path(args.doc).read_text(encoding="utf-8")
    checked, problems = check(text)
    print(f"落点路径 {checked} 处 · 问题 {len(problems)} 处")
    for sec, lineno, path, why in problems:
        print(f"  ❌ §{sec} 第 {lineno} 行 → `{path}`：{why}")
    if problems:
        print("\n处理：把落点改成仓里真实目录，或在该行标「待建」（表示施工目标，不是现状）。")
        return 1
    print("✅ 本端落点全部对得上仓（存在 or 标待建）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
