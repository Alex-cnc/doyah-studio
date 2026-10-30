#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""需求编号形状判据（`FR|NFR|AC-<产品>-<面>-<域>-<序号>`）。

存在的理由：这件事已经反复犯过 —— 新增需求时凭手感写成 `FR-UI-10` 这种三段短号，
而 L0《Doyah产品需求规格说明书》§1.5 早就定了五段式（产品 / 面 / 域三层编码 + 序号），
每次都要人指出来再返工。所以把它变成**提交那一刻的判据**，而不是靠记性：

  ① 本次**新增**的编号必须完全符合 L0 正则，且产品 / 面 / 域三者都已在 L0 登记；
  ② 老号（三段式）只在「该编号在改动前的同一文件里已经存在」时放行（冻结不迁移）；
  ③ 新编号若用了未登记的域码 —— 判红，并提示「先去 L0 §1.5.5 登记域码」。

用法：
    python3 tools/logic-check/check-req-ids.py                 # 看工作区 + 暂存区相对 HEAD 的新增行
    python3 tools/logic-check/check-req-ids.py --base origin/master
    python3 tools/logic-check/check-req-ids.py --self-test     # 反例：短号必红、五段式必绿

退出码：0 = 通过；1 = 有违反；2 = 用法 / 环境问题（不许静默当通过）。
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys

L0_DEFAULT = os.path.expanduser("~/dev/doyah/lead/studio/Docs/Doyah产品需求规格说明书.md")

FIVE = re.compile(r"^(FR|NFR|AC)-(AGT|STD|NTS|RTR|ALL)-([A-Z]{2,8})-([A-Z]{2,8})-(\d{2,3})$")
CANDIDATE = re.compile(r"(?<![A-Z])((?:FR|NFR|AC)-[A-Z]+(?:-[A-Z]+){0,3}-\d{2,3})")
# 只看「像编号的独立记号」，避免把句子里的 FR-UI 这种家族前缀当成编号
LEGACY = re.compile(r"^(FR|NFR|AC)-[A-Z]+-\d{2,3}$")


def run(cmd, cwd=None) -> str:
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError("命令失败：%s\n%s" % (" ".join(cmd), p.stderr.strip()))
    return p.stdout


def load_registry(l0_path: str):
    """从 L0 需求书解析：产品集合 / 面集合（按产品）/ 域集合（按面）。"""
    text = open(l0_path, encoding="utf-8").read()
    products = set(re.findall(r"^\| `(AGT|STD|NTS|RTR|ALL)` \| ", text, re.M))
    faces = {(p, f) for p, f in re.findall(r"^\| (AGT|STD|NTS|RTR|ALL) \| `([A-Z]{2,8})` \|", text, re.M)}
    domains = {(f, d) for f, d in re.findall(r"^\| (CORE|PLAN|GUARD|KNOW|TOOL|LINK|UX|QUAL|OPS|WS|DB|NOTE|TODO|MKT|RSR|FLOW|REV|ALL|GATE) \| `([A-Z]{2,8})` \|", text, re.M)}
    return products, faces, domains


def added_lines(base: str | None):
    """{文件: [新增行文本]} —— 只取 + 行，忽略 +++ 头。"""
    args = ["git", "diff", "--unified=0"]
    if base:
        args.append(base)
    out = run(args)
    files, cur = {}, None
    for line in out.split("\n"):
        if line.startswith("+++ "):
            path = line[4:].strip()
            cur = None if path == "/dev/null" else path[2:] if path.startswith("b/") else path
            if cur:
                files.setdefault(cur, [])
            continue
        if line.startswith("+") and not line.startswith("+++") and cur:
            files[cur].append(line[1:])
    # 未跟踪文件也纳入（新增文件最容易犯这个错）
    for path in run(["git", "ls-files", "--others", "--exclude-standard"]).split("\n"):
        path = path.strip()
        if path and os.path.isfile(path):
            files.setdefault(path, [])
            try:
                files[path].extend(open(path, encoding="utf-8", errors="ignore").read().split("\n"))
            except OSError:
                pass
    return files


def existing_ids(path: str, base: str | None):
    """改动前该文件里已存在的编号（用来放行冻结的老号）。"""
    ref = base or "HEAD"
    try:
        text = run(["git", "show", "%s:%s" % (ref, path)])
    except RuntimeError:
        return set()
    return set(CANDIDATE.findall(text))


def check(files, products, faces, domains, base):
    problems, checked = [], 0
    for path, lines in sorted(files.items()):
        # 只看文档树：需求编号是文档里的东西；`.agent/`、笔记证据、代码注释里的老号引用不在此列
        if not path.endswith(".md") or "/Docs/" not in "/" + path:
            continue
        before = existing_ids(path, base)
        for line in lines:
            for rid in CANDIDATE.findall(line):
                checked += 1
                m = FIVE.match(rid)
                if m:
                    _, product, face, domain, _serial = m.groups()
                    if product not in products:
                        problems.append((path, rid, "产品码 `%s` 未在 L0 §1.5.3 登记" % product))
                    elif product != "ALL" and (product, face) not in faces:
                        problems.append((path, rid, "面码 `%s/%s` 未在 L0 §1.5.4 登记" % (product, face)))
                    elif product != "ALL" and (face, domain) not in domains and (face != "GATE" and (face, domain) not in domains):
                        problems.append((path, rid, "域码 `%s` 未在 L0 §1.5.5 登记（先去登记，再分配编号）" % domain))
                    continue
                if LEGACY.match(rid) and rid in before:
                    continue  # 冻结的老号：改动前就有，放行
                problems.append((path, rid, "不是 L0 五段式 `<类型>-<产品>-<面>-<域>-<序号>`（新增编号必须五段式）"))
    return checked, problems


def main() -> int:
    ap = argparse.ArgumentParser(description="需求编号形状判据")
    ap.add_argument("--base", help="对照基线（缺省 = 工作区相对 HEAD）")
    ap.add_argument("--l0", default=os.environ.get("DOYAH_L0_SRS", L0_DEFAULT))
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()

    if args.self_test:
        products = {"AGT", "STD", "NTS", "RTR", "ALL"}
        faces = {("NTS", "NOTE"), ("STD", "WS")}
        domains = {("NOTE", "SET"), ("NOTE", "CAPTURE"), ("WS", "UI")}
        good = ["| FR-NTS-NOTE-SET-001 | 设置页 |"]

        def one(line):
            return ["| FR-UI-10 | 设置页 |"] if line is None else [line]

        checked_ok, p_ok = check({"a.md": good}, products, faces, domains, None)
        checked_bad, p_bad = check({"a.md": ["+ | FR-UI-10 | 新需求 |"]}, products, faces, domains, None)
        checked_dom, p_dom = check({"a.md": ["| FR-NTS-NOTE-NOPE-001 | x |"]}, products, faces, domains, None)
        cases = [
            ("五段式且已登记 ⇒ 绿", checked_ok == 1 and not p_ok),
            ("三段短号新增 ⇒ 红", checked_bad >= 1 and p_bad),
            ("未登记域码 ⇒ 红", p_dom),
        ]
        bad = 0
        for name, ok in cases:
            print(("  ✓ " if ok else "  ✗ ") + name)
            bad += 0 if ok else 1
        print("自测：%d/%d 例通过" % (len(cases) - bad, len(cases)))
        return 0 if bad == 0 else 1

    if not os.path.exists(args.l0):
        print("✗ 找不到 L0 需求书（%s）；用 --l0 或 DOYAH_L0_SRS 指定" % args.l0)
        return 2
    products, faces, domains = load_registry(args.l0)

    files = added_lines(args.base)
    checked, problems = check(files, products, faces, domains, args.base)
    if problems:
        print("✗ 新增的需求编号不合 L0 §1.5 编码规范：")
        for path, rid, why in problems:
            print("   %s → %s：%s" % (path, rid, why))
        print("处理：① 按 `<类型>-<产品>-<面>-<域>-<序号>` 改名；② 域码未登记时先改 L0 §1.5.5，再分配编号。")
        return 1
    print("✓ 需求编号形状合规（扫过 %d 个编号 / %d 个文件）" % (checked, len(files)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
