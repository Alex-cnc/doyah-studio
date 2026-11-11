#!/usr/bin/env python3
"""动作路由：一份最小清单，定义有限个动作，每个动作对应「必读什么 + 必跑什么」。

主人 2026-11-05 的口径：
  「应该有总入口，总入口维护最小清单，清单里定义几个有限动作：无论 Agent 做什么操作都会触发，
   然后找到对应的操作，去读取该操作对应的规则。」

它解决的问题：规则散在规范、书内 §7、技能里，靠会话记忆守不住（今天连续踩了三次）。
做法：把「动作 → 规则 + 判据」做成一张可执行的表，谁都能查、钩子也能跑。

## 三层触发（诚实边界）

1. **可执行入口（本文件）**：`--list` 看清单；`--for <动作>` 查该动作要读什么、要跑什么；
   `--changed` 按本次改动推断动作；`--check` 直接跑对应判据。
2. **硬钩子（不依赖记忆）**：`.git/hooks/pre-commit` 在提交时自动跑 `--changed --check --fast`，
   改了文档就跑文档门禁，改了判据就跑判据自检，动了版本号就跑步进规则。
3. **不可捕获的部分**：只读浏览、思考、查资料这些动作 **没有钩子可挂**，只能靠调用方（Agent）
   在开工时主动跑 `--for`。所以「无论做什么都触发」在仓内只能做到「一切**写操作**都触发」。

用法：
  python3 Scripts/action-router.py --list
  python3 Scripts/action-router.py --for 改平台详设
  python3 Scripts/action-router.py --changed            # 看本次改动命中哪些动作
  python3 Scripts/action-router.py --changed --check     # 真跑（--fast 只跑轻判据）
  python3 Scripts/action-router.py --self-test
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PY = sys.executable or "python3"

# ── 最小清单：动作是有限闭集，新增动作必须同时给出判据（否则等于没规则）──
# 口径（2026-11-05 主人纠）：三书一单 = 需求规格 + 概要设计 + 详细设计（平台多本）+ 任务清单（2026-11-09 能力规划书并入需求规格书），
# 平台详设是「四书」里的详细设计，**不是另一个动作**；版本步进也是改文档的副产品，不单列。
ACTIONS: dict[str, dict] = {
    "改文档": {
        "read": [
            "AGENTS.md §0 四条红线",
            "Docs/通用开发规范.md §2 三书一单 · §3 版本纪律 · §4 门禁清单",
            "Docs/通用开发规范.md §2「平台详设按基准书移植」（动平台详设时）",
        ],
        "checks": [
            ("check-doc-versions.py", []),
            ("check-doc-tables.py", []),
            ("check-doc-numbers.py", []),
            ("check-doc-invariants.py", []),
            ("check-rule-schema.py", []),
            ("check-doc-layout.py", []),
            ("check-plan-coverage.py", []),
            ("check-agents-index.py", []),
            ("check-platform-derivation.py", ["--changed"]),
            ("gen-req-index.py", ["--check"]),
        ],
    },
    "改判据脚本": {
        "read": ["Docs/通用开发规范.md §1 铁律 13/14/15（覆盖范围 / 必红负例 / 独立验收层）"],
        "checks": [("check-doc-numbers.py", [])],
    },
    "改代码": {
        "read": [
            "AGENTS.md §0 四条红线",
            "新增菜单项时必须同批登记 Core/MenuLocalization.swift 的 menuKeys，并跑全量 swift test（禁只跑 --filter）",
        ],
        "checks": [("__swift_test__", [])],
    },
    "改前端": {
        "read": ["Platform/windows/App/src 的测试约定（视图要带 mount 用例）"],
        "checks": [("__npm_test__", [])],
    },
    "动凭据或用户数据": {
        "read": ["AGENTS.md §4（PUBLIC 仓：凭据、内网地址、个人内容不进仓）"],
        "checks": [("check-no-user-data.py", [])],
    },
    "推送": {
        "read": ["AGENTS.md §0 四条红线（说完成必须附命令输出）"],
        "checks": [("__verify_all__", [])],
    },
}

HEAVY = {"__swift_test__", "__npm_test__", "__verify_all__"}

# ── 改动路径 → 动作（判据：一条改动可命中多个动作，宁多勿漏）──
ROUTES: list[tuple[str, str]] = [
    (r"^Docs/.*\.md$", "改文档"),
    (r"^AGENTS\.md$|^Docs/通用开发规范\.md$|^Docs/项目管理规范\.md$", "改文档"),
    (r"^Scripts/.*\.(py|sh)$|^Scripts/hooks/", "改判据脚本"),
    (r"\.swift$", "改代码"),
    (r"^Platform/windows/App/src/.*\.(vue|ts)$", "改前端"),
    (r"^App/Resources/|\.secrets|credentials", "动凭据或用户数据"),
]


def _unquote(path: str) -> str:
    """把 git 的 quoted path（"Docs/\344\272\247..."）解回 UTF-8。"""
    if not (path.startswith('"') and path.endswith('"')):
        return path
    body = path[1:-1].encode("latin-1", "backslashreplace").decode("unicode_escape")
    return body.encode("latin-1", "ignore").decode("utf-8", "ignore") or path


def actions_for(paths: list[str]) -> list[str]:
    """改动文件 → 命中动作（保序去重）。"""
    import re
    paths = [_unquote(p) for p in paths]
    hit: list[str] = []
    for p in paths:
        for pat, act in ROUTES:
            if re.search(pat, p) and act not in hit:
                hit.append(act)
    # 文档改动天然包含「改版本号」的嫌疑：交给 check-doc-versions 自己判（它只在真跳段时红）
    return hit


def parse_porcelain(raw: str) -> list[str]:
    """`git status --porcelain -z` 的输出 → 路径列表（暂存 + 未暂存 + 未跟踪，改名取新名）。

    为什么不用 `git diff --cached`：2026-11-10 实测的洞 —— 只要暂存区**有任何**改动，
    原实现就再也不看工作区，于是「暂存两个脚本 + 未暂存整本文档」这种最常见的混合改动
    只推断出「改判据脚本」，文档那 10 条必跑判据一条都没跑（注入重复 Q37 仍 rc=0）。
    """
    parts = [x for x in raw.split("\0") if x]
    out: list[str] = []
    skip_next = False
    for part in parts:
        if skip_next:                      # 改名条目：下一段是旧路径，丢掉
            skip_next = False
            continue
        if len(part) < 4:
            continue
        status, path = part[:2], part[3:]
        out.append(_unquote(path))
        if status[0] in ("R", "C") or status[1] in ("R", "C"):
            skip_next = True
    return out


def changed_paths(base: str | None) -> list[str]:
    """本次改动涉及的全部路径：暂存 ∪ 未暂存 ∪ 未跟踪（`base` 给了就只算与该提交的差）。

    `-c core.quotepath=false` 与 `-z`：中文文件名否则会被转义成 `"Docs/Doyah\\344..."`，
    路由正则全部落空 —— 本仓绝大多数文档都是中文名，这个坑会让总入口对它们完全不触发。
    """
    common = ["git", "-c", "core.quotepath=false"]
    if base:
        out = subprocess.run(common + ["diff", "--name-only", base], cwd=ROOT, capture_output=True, text=True)
        tracked = [_unquote(l) for l in out.stdout.splitlines() if l.strip()]
        u = subprocess.run(common + ["ls-files", "--others", "--exclude-standard", "-z"],
                           cwd=ROOT, capture_output=True, text=True)
        untracked = [_unquote(x) for x in u.stdout.split("\0") if x]
        return list(dict.fromkeys(tracked + untracked))
    out = subprocess.run(common + ["status", "--porcelain", "-z", "--untracked-files=all"],
                         cwd=ROOT, capture_output=True, text=True)
    return list(dict.fromkeys(parse_porcelain(out.stdout)))


def run_check(script: str, extra: list[str], fast: bool) -> tuple[bool, str]:
    if script in HEAVY:
        if fast:
            return True, f"⏭️  {script}（重判据，提交钩子不跑；推送前手动跑）"
        cmd = {"__swift_test__": ["swift", "test"],
               "__npm_test__": ["npm", "--prefix", "Platform/windows/App", "test"],
               "__verify_all__": ["bash", "Scripts/verify-all.sh"]}[script]
        out = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
        return out.returncode == 0, f"{'✅' if out.returncode == 0 else '❌'} {' '.join(cmd)}"
    cmd = [PY, f"Scripts/{script}", *extra]
    out = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    ok = out.returncode == 0
    tail = (out.stdout or out.stderr).strip().splitlines()
    detail = tail[-1][:110] if tail else ""
    return ok, f"{'✅' if ok else '❌'} {script} {' '.join(extra)} {detail}".strip()


def self_test() -> int:
    cases = [
        (["Docs/Doyah产品详细设计说明书-Linux.md"], ["改文档"]),
        (["Docs/Doyah产品需求规格说明书.md"], ["改文档"]),
        (["AGENTS.md"], ["改文档"]),
        (["Scripts/check-doc-versions.py"], ["改判据脚本"]),
        (["App/DoyahStudioCommands.swift"], ["改代码"]),
        (["Platform/windows/App/src/views/DatabaseView.vue"], ["改前端"]),
        (["Platform/linux/README.md"], []),
        (['"Docs/Doyah\\344\\272\\247\\345\\223\\201\\350\\257\\246\\346\\230\\216.md"'], ["改文档"]),
    ]
    bad = 0
    for paths, expect in cases:
        got = actions_for(paths)
        ok = got == expect
        print(("  ✓ " if ok else "  ✗ ") + f"{paths[0]} → {got or '（无动作）'}（应 {expect or '（无动作）'}）")
        bad += 0 if ok else 1
    # 本次修的洞：只改暂存区时不能丢工作区改动。用固定串验解析（不依赖真仓库状态）
    probe = ("M  Scripts/check-doc-versions.py\0"
             " M Docs/通用开发规范.md\0"
             "R  Scripts/doc_index.py\0Scripts/archive/doc_index.py\0"
             "?? Docs/new-note.md\0")
    parsed = parse_porcelain(probe)
    expect_paths = ["Scripts/check-doc-versions.py", "Docs/通用开发规范.md",
                    "Scripts/doc_index.py", "Docs/new-note.md"]
    ok = parsed == expect_paths
    print(("  ✓ " if ok else "  ✗ ") + f"porcelain 解析（暂存+未暂存+改名+未跟踪）→ {parsed}")
    bad += 0 if ok else 1
    mixed = actions_for(["Scripts/check-doc-versions.py", "Docs/通用开发规范.md"])
    ok = sorted(mixed) == sorted(["改文档", "改判据脚本"])   # 顺序随 ROUTES，判定只看集合
    print(("  ✓ " if ok else "  ✗ ") + f"脚本+文档混合改动 → {mixed}（应两个动作都命中）")
    bad += 0 if ok else 1
    # 负例：清单里的动作都必须有判据，否则「有规则无判据」
    empty = [n for n, a in ACTIONS.items() if not a["checks"]]
    print(("  ✓ " if not empty else "  ✗ ") + f"每个动作都有判据（空判据动作：{empty or '无'}）")
    bad += 0 if not empty else 1
    total = len(cases) + 3
    print(f"自检{'通过' if not bad else '失败'}（{total-bad}/{total}）")
    return 0 if not bad else 1


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="打印最小清单")
    ap.add_argument("--for", dest="action", help="查某个动作要读什么、要跑什么")
    ap.add_argument("--changed", action="store_true", help="按本次改动推断命中动作")
    ap.add_argument("--check", action="store_true", help="跑对应判据")
    ap.add_argument("--fast", action="store_true", help="只跑轻判据（提交钩子用）")
    ap.add_argument("--base", help="与某个基线比较（默认暂存区，其次工作区）")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()

    if args.self_test:
        return self_test()

    if args.list or not (args.action or args.changed):
        print("动作清单（有限闭集；新增动作必须同时给判据）\n")
        for name, spec in ACTIONS.items():
            heavy = "（重判据）" if any(s in HEAVY for s, _ in spec["checks"]) else ""
            print(f"· {name}{heavy}")
            for r in spec["read"]:
                print(f"    必读：{r}")
            for s, extra in spec["checks"]:
                print(f"    必跑：{s} {' '.join(extra)}".rstrip())
        return 0

    if args.action:
        spec = ACTIONS.get(args.action)
        if not spec:
            print(f"未知动作：{args.action}（可用：{'、'.join(ACTIONS)}）")
            return 2
        print(f"动作：{args.action}")
        for r in spec["read"]:
            print(f"  必读：{r}")
        for s, extra in spec["checks"]:
            print(f"  必跑：{s} {' '.join(extra)}".rstrip())
        return 0

    paths = changed_paths(args.base)
    acts = actions_for(paths)
    print(f"本次改动 {len(paths)} 个文件 ⇒ 命中动作：{'、'.join(acts) if acts else '（无需动作）'}")
    if not args.check:
        return 0
    if len(acts) > 1:
        print(f"（改动同时落在 {len(acts)} 个动作上 ⇒ 每个动作的必跑判据**都要**跑；"
              f"同一脚本只跑一次）")
    failed = 0
    seen: set[tuple[str, tuple[str, ...]]] = set()
    for act in acts:
        print(f"\n[{act}]")
        for s, extra in ACTIONS[act]["checks"]:
            key = (s, tuple(extra))
            if key in seen:
                print(f"  ⏭️  {s}（本批已跑过，不重复）")
                continue
            seen.add(key)
            ok, msg = run_check(s, extra, args.fast)
            print("  " + msg)
            if not ok:
                failed += 1
    if failed:
        print(f"\n❌ {failed} 条判据未通过 —— 先修，别提交")
        return 1
    print("\n✅ 动作对应的判据全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
