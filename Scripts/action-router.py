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
ACTIONS: dict[str, dict] = {
    "改版本号": {
        "read": ["Docs/通用开发规范.md §3（活书 v1.0.NNN 末位递增，999 冻结）"],
        "checks": [("check-doc-versions.py", []), ("check-doc-versions.py", ["--self-test"])],
    },
    "改四书一单": {
        "read": ["Docs/通用开发规范.md §2 四书一单", "Docs/通用开发规范.md §4 门禁清单"],
        "checks": [
            ("check-doc-tables.py", []),
            ("check-doc-numbers.py", []),
            ("check-doc-invariants.py", []),
            ("check-doc-layout.py", []),
            ("check-plan-coverage.py", []),
            ("gen-req-index.py", ["--check"]),
        ],
    },
    "改平台详设": {
        "read": ["Docs/通用开发规范.md §2 平台详设按基准书移植", "本文件 §0.2 处置表口径"],
        "checks": [
            ("check-platform-derivation.py", []),
            ("check-doc-tables.py", []),
            ("check-doc-layout.py", []),
        ],
    },
    "改判据脚本": {
        "read": ["Docs/通用开发规范.md §1 铁律 13/14/15（覆盖范围 / 必红负例 / 独立验收）"],
        "checks": [("check-doc-numbers.py", [])],
    },
    "改代码": {
        "read": ["AGENTS.md §0 四条红线"],
        "checks": [("__swift_test__", [])],       # 重判据：钩子里不跑
    },
    "加菜单项": {
        "read": ["Core/MenuLocalization.swift（menuKeys 必须同批登记）"],
        "checks": [("__swift_test__", [])],
    },
    "改前端": {
        "read": ["Platform/windows/App/src 的测试约定"],
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
    (r"^Docs/Doyah产品需求规格说明书\.md$", "改四书一单"),
    (r"^Docs/Doyah产品能力规划说明书\.md$", "改四书一单"),
    (r"^Docs/Doyah产品概要设计说明书\.md$", "改四书一单"),
    (r"^Docs/Doyah产品开发计划任务清单", "改四书一单"),
    (r"^Docs/Doyah产品详细设计说明书-", "改平台详设"),
    (r"^Docs/通用开发规范\.md$|^Docs/项目管理规范\.md$", "改四书一单"),
    (r"^Scripts/.*\.py$|^Scripts/.*\.sh$", "改判据脚本"),
    (r"^AGENTS\.md$", "改判据脚本"),
    (r"^Core/MenuLocalization\.swift$|^App/DoyahStudioCommands\.swift$", "加菜单项"),
    (r"\.swift$", "改代码"),
    (r"^Platform/windows/App/src/.*\.(vue|ts)$", "改前端"),
    (r"^App/Resources/|\.secrets|credentials", "动凭据或用户数据"),
]


def actions_for(paths: list[str]) -> list[str]:
    """改动文件 → 命中动作（保序去重）。"""
    import re
    hit: list[str] = []
    for p in paths:
        for pat, act in ROUTES:
            if re.search(pat, p) and act not in hit:
                hit.append(act)
    # 文档改动天然包含「改版本号」的嫌疑：交给 check-doc-versions 自己判（它只在真跳段时红）
    return hit


def staged_paths(base: str | None) -> list[str]:
    args = ["git", "diff", "--cached", "--name-only"]
    if base:
        args = ["git", "diff", "--name-only", base]
    out = subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
    paths = [l for l in out.stdout.splitlines() if l.strip()]
    if not paths:                                   # 没有暂存区改动就看工作区
        out = subprocess.run(["git", "diff", "--name-only", "HEAD"], cwd=ROOT,
                             capture_output=True, text=True)
        paths = [l for l in out.stdout.splitlines() if l.strip()]
    return paths


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
        (["Docs/Doyah产品详细设计说明书-Linux.md"], ["改平台详设"]),
        (["Docs/Doyah产品需求规格说明书.md"], ["改四书一单"]),
        (["Scripts/check-doc-versions.py"], ["改判据脚本"]),
        (["App/DoyahStudioCommands.swift"], ["加菜单项", "改代码"]),
        (["Core/Localization.swift"], ["改代码"]),
        (["Platform/windows/App/src/views/DatabaseView.vue"], ["改前端"]),
        (["Platform/linux/README.md"], []),
    ]
    bad = 0
    for paths, expect in cases:
        got = actions_for(paths)
        ok = got == expect
        print(("  ✓ " if ok else "  ✗ ") + f"{paths[0]} → {got or '（无动作）'}（应 {expect or '（无动作）'}）")
        bad += 0 if ok else 1
    # 负例：清单里的动作都必须有判据，否则「有规则无判据」
    empty = [n for n, a in ACTIONS.items() if not a["checks"]]
    print(("  ✓ " if not empty else "  ✗ ") + f"每个动作都有判据（空判据动作：{empty or '无'}）")
    bad += 0 if not empty else 1
    print(f"自检{'通过' if not bad else '失败'}（{len(cases)+1-bad}/{len(cases)+1}）")
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

    paths = staged_paths(args.base)
    acts = actions_for(paths)
    print(f"本次改动 {len(paths)} 个文件 ⇒ 命中动作：{'、'.join(acts) if acts else '（无需动作）'}")
    if not args.check:
        return 0
    failed = 0
    for act in acts:
        print(f"\n[{act}]")
        for s, extra in ACTIONS[act]["checks"]:
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
