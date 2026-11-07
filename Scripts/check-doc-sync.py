#!/usr/bin/env python3
"""待补文档清单：最近 N 个提交里「碰了代码、没碰文档」的那些（**只报告，不拦截**）。

## 为什么要有它

主人 2026-11-07 的原话：

> 「前门等所有改动记得要同步到详细设计里去，别事情干完了又不同步四书」

「记得」是人的事，靠自觉就会漏 —— 这个脚本把「漏」变成一条**可读的清单**：
最近 N 个提交里，凡改了 `App/**` 或 `Core/**`（界面与契约层）却**一个 `Docs/**` 文件都没碰**的，
逐条列出来，顺带写出它碰了哪几个代码文件。

## 为什么只报告不拦截

「改了代码」不等于「改了契约性行为」：修一个错别字、调一个内部常量、补一条注释，都不该逼着人
去动四书。硬拦的话只有两种结局：要么被 `--no-verify` 绕过去（比没有更坏：判据成了摆设），
要么把真实改动切碎成「代码一个提交、文档一个提交」（`check-doc-sync` 反而看不出来）。

所以口径是：**列出来，让人看一眼**。真正的纪律写在详设 §3.38：凡改**契约性行为**，必须
**同批**改详设；提交前跑这一条。

## 用法

    python3 Scripts/check-doc-sync.py                 # 最近 12 个提交
    python3 Scripts/check-doc-sync.py --limit 30      # 最近 30 个
    python3 Scripts/check-doc-sync.py --self-test     # 负例（临时仓库里造两种提交，判它认不认得出）

输出永远 exit 0（提示级）。`--require-clean` 才会在有未同步提交时 exit 1（给想当门禁用的场合留个口子，
本仓闭环**不**用它）。

## 口径（写死，改口径先改本节）

- 代码面 = `App/`、`Core/` 两个前缀（界面与契约层；平台适配层 `Platform/` 与文档无关，不计）；
- 文档面 = `Docs/` 前缀；
- 合并提交（`--no-merges`）不计：merge 的「改了哪些文件」是它带进来那一堆提交的并集，
  一条 merge 会把十几条历史重新算一遍；
- 改名按新路径算（`--find-renames`）；
- 统计的是**提交**，不是文件 —— 一个提交里碰了 8 个代码文件也只算一条待补。
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

CODE_ROOTS = ("App/", "Core/")
DOC_ROOT = "Docs/"
DEFAULT_LIMIT = 12


def run_git(repo: str, *args: str) -> str:
    out = subprocess.run(
        ["git", "-C", repo, *args],
        capture_output=True,
        text=True,
        check=False,
    )
    if out.returncode != 0:
        raise SystemExit(f"[check-doc-sync] git {' '.join(args)} 失败：{out.stderr.strip()}")
    return out.stdout


def commits(repo: str, limit: int) -> list[dict]:
    """最近 `limit` 个非合并提交（新的在前）。"""
    raw = run_git(
        repo,
        "log",
        "--no-merges",
        f"-n{limit}",
        "--format=%H%x1f%h%x1f%ad%x1f%s",
        "--date=short",
    )
    rows: list[dict] = []
    for line in raw.splitlines():
        if not line.strip():
            continue
        sha, short, date, subject = line.split("\x1f", 3)
        rows.append({"sha": sha, "short": short, "date": date, "subject": subject})
    return rows


def changed_files(repo: str, sha: str) -> list[str]:
    """这一次提交碰过的路径（**NUL 分隔**）。

    为什么不用按行切：中文文件名会被 git 按 `core.quotepath` 转义成
    `"Docs/Doyah\344\272\247..."`（带引号 + 八进制），按行读再 `startswith("Docs/")`
    一条都命中不了 —— 实测过一次：本仓库的文档全是中文名，于是**每个提交都被判成「没碰文档」**。
    `-z` 输出的是原始字节，一个路径一个 `\0`，与引号规则无关。
    """
    raw = run_git(repo, "show", "--name-only", "--format=", "--find-renames", "-z", sha)
    return [path for path in raw.split("\0") if path.strip()]


def classify(files: list[str]) -> dict:
    code = [f for f in files if f.startswith(CODE_ROOTS)]
    docs = [f for f in files if f.startswith(DOC_ROOT)]
    return {"code": code, "docs": docs, "missing": bool(code) and not docs}


def audit(repo: str, limit: int, as_json: bool = False) -> list[dict]:
    rows: list[dict] = []
    for commit in commits(repo, limit):
        info = classify(changed_files(repo, commit["sha"]))
        rows.append({**commit, **info})
    if as_json:
        print(json.dumps(rows, ensure_ascii=False, indent=2))
    return rows


def report(rows: list[dict], limit: int) -> int:
    pending = [row for row in rows if row["missing"]]
    code_touched = [row for row in rows if row["code"]]

    print(f"==> 待补文档：最近 {len(rows)} 个提交（--limit {limit}）里"
          f"「碰了 App/ 或 Core/、没碰 Docs/」的提交")
    if not code_touched:
        print("    最近这些提交一个都没碰 App/ 或 Core/ ⇒ 本项无话可说")
        return 0
    if not pending:
        print(f"    碰了代码的 {len(code_touched)} 个提交全都同批碰了 Docs/ ⇒ 无待补 ✅")
        return 0

    for row in pending:
        shown = ", ".join(row["code"][:4])
        more = "" if len(row["code"]) <= 4 else f" 等 {len(row['code'])} 个文件"
        print(f"    {row['short']}  {row['date']}  {row['subject']}")
        print(f"        代码：{shown}{more}")

    print(f"    共 {len(code_touched)} 个提交碰了代码，其中 {len(pending)} 个没碰文档")
    print("    ⚠ 提示级：本项不拦截。凡改**契约性行为**必须同批改详设（§3.38），"
          "提交前跑 Scripts/check-doc-sync.py")
    return len(pending)


def self_test() -> int:
    """负例 + 正例：临时仓库里造两种提交，判它认不认得出「漏文档」。"""
    failures: list[str] = []
    tmp = tempfile.mkdtemp(prefix="check-doc-sync-")
    try:
        repo = os.path.join(tmp, "repo")
        os.makedirs(repo, exist_ok=True)
        env = {
            **os.environ,
            "GIT_AUTHOR_NAME": "gate",
            "GIT_AUTHOR_EMAIL": "gate@example.com",
            "GIT_COMMITTER_NAME": "gate",
            "GIT_COMMITTER_EMAIL": "gate@example.com",
        }

        def git(*args: str) -> None:
            subprocess.run(["git", "-C", repo, *args], check=True, capture_output=True, env=env)

        def write(rel: str, text: str) -> None:
            path = os.path.join(repo, rel)
            os.makedirs(os.path.dirname(path) or repo, exist_ok=True)
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(text)

        git("init", "-q")
        git("config", "user.email", "gate@example.com")
        git("config", "user.name", "gate")

        # 例 0：初始提交只带文档（让后面的「代码提交」不带 Docs/，判据才有分母）；
        # **其中一份是中文文件名** —— 中文路径会被 git 转义，按行解析就会把「改了文档」漏成「没改」。
        write("Docs/a.md", "# a\n")
        write("Docs/中文文档.md", "# 文档\n")
        git("add", "-A")
        git("commit", "-q", "-m", "初始文档")

        # 例 1：碰代码不碰文档 ⇒ 必须被判「待补」
        write("App/Views/A.swift", "// 1\n")
        git("add", "-A")
        git("commit", "-q", "-m", "代码改了、文档没改")
        # 例 2：代码 + 文档同批 ⇒ 不算待补（文档是**中文名**那份，锁住 NUL 分隔那条口径）
        write("App/Views/A.swift", "// 2\n")
        write("Docs/中文文档.md", "# 文档 2\n")
        git("add", "-A")
        git("commit", "-q", "-m", "代码与文档同批")
        # 例 3：只碰文档 ⇒ 不是待补（也不是「碰了代码」）
        write("Docs/b.md", "# b\n")
        git("add", "-A")
        git("commit", "-q", "-m", "只改文档")
        # 例 4：Core 也是代码面
        write("Core/B.swift", "// 1\n")
        git("add", "-A")
        git("commit", "-q", "-m", "Core 改了、文档没改")

        rows = audit(repo, 10)
        pending = [(row["subject"], row["code"]) for row in rows if row["missing"]]
        subjects = [row["subject"] for row in rows]

        if "代码改了、文档没改" not in [p[0] for p in pending]:
            failures.append(f"例 1 未判出（pending={pending}）")
        if "Core 改了、文档没改" not in [p[0] for p in pending]:
            failures.append(f"例 4 未判出（pending={pending}）")
        if "代码与文档同批" in [p[0] for p in pending]:
            failures.append("例 2 被误判成待补（同批改了 Docs/）")
        if "只改文档" in [p[0] for p in pending]:
            failures.append("例 3 被误判成待补（它没碰代码）")
        if len(pending) != 2:
            failures.append(f"待补条数 {len(pending)} ≠ 2（{subjects}）")

        # 例 5：--limit 生效（只取最近 2 个 ⇒ 只剩 Core 那条 + 只改文档那条）
        limited = audit(repo, 2)
        if len(limited) != 2:
            failures.append(f"--limit 2 取到 {len(limited)} 条")

        for index, why in enumerate(failures, start=1):
            print(f"✗ 例 {index}：{why}")
        if failures:
            print(f"check-doc-sync 自检：{len(failures)} 例失败")
            return 1
        print("✓ check-doc-sync 自检 5 例通过（代码未同步文档 / Core 也算代码面 / 同批改文档不误判 / 只改文档不误判 / --limit 生效）")
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="待补文档清单（只报告不拦截）")
    parser.add_argument("--limit", type=int, default=DEFAULT_LIMIT, help=f"看最近几个提交（默认 {DEFAULT_LIMIT}）")
    parser.add_argument("--repo", default=".", help="仓库根（默认当前目录）")
    parser.add_argument("--json", action="store_true", help="输出 JSON（机器读）")
    parser.add_argument("--require-clean", action="store_true", help="有待补提交时 exit 1（默认永远 exit 0）")
    parser.add_argument("--self-test", action="store_true", help="跑 5 个负例/正例")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()

    repo = os.path.abspath(args.repo)
    rows = audit(repo, max(1, args.limit), as_json=args.json)
    if args.json:
        return 0
    pending = report(rows, max(1, args.limit))
    if args.require_clean and pending:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
