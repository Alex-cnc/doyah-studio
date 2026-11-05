#!/usr/bin/env python3
"""拦「用户数据 / 凭据 / 内网地址」进仓（PUBLIC 仓，只许代码与关键文档）。

背景：主人 2026-11-05 两次强调 —— GitHub 只装项目代码与关键文档，
用户自己的数据（周报包、文章、笔记、记忆、凭据）不该出现在仓里，更不该被推送。

判据三档：
- ❌ 硬红：用户数据文件路径（周报包 / 笔记库 / 凭据文件 / SQLite 库 / `.dsh` 内容）、真密钥特征
- ⚠️ 提示：内网地址（192.168 / 10. / 172.16–31.）出现在跟踪文件里 —— 不算用户数据，但 PUBLIC 仓不该有
- ✅ 明确豁免：测试夹具目录 `tests/fixtures/**`（合成数据，README 里写明）

用法：
  python3 Scripts/check-no-user-data.py            # 扫跟踪文件
  python3 Scripts/check-no-user-data.py --self-test
退出码：0 = 干净；1 = 有硬红。
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# 硬红路径：用户数据与凭据
FORBIDDEN_PATHS = [
    r"(^|/)geopolitics-weekly/",
    r"(^|/)packages/2026-W\d{2}/",
    r"(^|/)\.dsh/",
    r"(^|/)\.secrets/",
    r"(^|/)credentials\.json$",
    r"\.(sqlite|sqlite3|db|db3|realm)$",
    r"(^|/)(MEMORY|USER)\.md$",
    r"(^|/)memories/",
]

# 硬红内容：真密钥（占位写法带 `...`，不会被命中）
SECRET_PATTERNS = [
    (r"sk-[A-Za-z0-9]{24,}", "疑似真 API 密钥"),
    (r"gh[pousr]_[A-Za-z0-9]{30,}", "疑似 GitHub 令牌"),
    (r"-----BEGIN [A-Z ]*PRIVATE KEY-----", "私钥块"),
]

# 提示：内网地址
LAN = re.compile(r"\b(?:192\.168\.\d{1,3}\.\d{1,3}|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})\b")

EXEMPT_PATH = re.compile(r"(^|/)tests?/fixtures/")


def tracked_files() -> list[str]:
    out = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True)
    return [l for l in out.stdout.splitlines() if l]


def audit(files: list[str]) -> tuple[list[str], list[str]]:
    hard: list[str] = []
    warn: list[str] = []
    for rel in files:
        if EXEMPT_PATH.search(rel):
            continue
        for pat in FORBIDDEN_PATHS:
            if re.search(pat, rel):
                hard.append(f"用户数据/凭据路径：{rel}")
        path = ROOT / rel
        if not path.is_file():
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for pat, why in SECRET_PATTERNS:
            for m in re.finditer(pat, text):
                hard.append(f"{why}：{rel}（{m.group(0)[:12]}…）")
        if LAN.search(text):
            warn.append(f"内网地址：{rel}")
    return hard, warn


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()

    if args.self_test:
        cases = [
            ("packages/2026-W42/report.md", True),
            ("tests/fixtures/retro/2026-W42/report.md", False),
            ("docs/笔记.sqlite", True),
            ("~/.dsh/notes/x.md", True),
            ("Sources/Report.swift", False),
        ]
        bad = []
        for rel, should in cases:
            hit = any(re.search(p, rel) for p in FORBIDDEN_PATHS) and not EXEMPT_PATH.search(rel)
            ok = hit == should
            print(("  ✓ " if ok else "  ✗ ") + f"{rel} → {'红' if hit else '不红'}（应为 {'红' if should else '不红'}）")
            if not ok:
                bad.append(rel)
        secret_case = "let k = \"sk-" + "a" * 30 + "\""
        ok_secret = bool(re.search(SECRET_PATTERNS[0][0], secret_case))
        placeholder = "let k = \"sk-abc...2345\""
        ok_placeholder = not re.search(SECRET_PATTERNS[0][0], placeholder)
        print(("  ✓ " if ok_secret else "  ✗ ") + "真密钥特征命中")
        print(("  ✓ " if ok_placeholder else "  ✗ ") + "占位密钥不误报")
        if not ok_secret:
            bad.append("secret")
        if not ok_placeholder:
            bad.append("placeholder")
        print("自检" + ("通过" if not bad else "失败"))
        return 0 if not bad else 1

    hard, warn = audit(tracked_files())
    for w in warn:
        print("  ⚠️ " + w)
    for h in hard:
        print("  ❌ " + h)
    if hard:
        print(f"\n❌ {len(hard)} 处不该进仓的内容（硬红）；提示 {len(warn)} 处")
        return 1
    print(f"\n✅ 跟踪文件里没有用户数据与凭据；内网地址提示 {len(warn)} 处（不算红，但 PUBLIC 仓建议脱敏）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
