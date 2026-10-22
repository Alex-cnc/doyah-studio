#!/usr/bin/env python3
"""界面设计节自检 —— 判《概要设计说明书》第九章某端的「界面设计」是否够格。

用法:
    python3 Scripts/check-ui-design-section.py --platform windows
    python3 Scripts/check-ui-design-section.py --platform macos --doc Docs/Doyah产品概要设计说明书.md

判什么（见 Docs/规范/界面设计节-写作规范.md）:
  1. 八项必需主题各有一个小节（窗口模型 / 区域骨架 / 构件与尺寸 / 命令与键位 /
     六态 / 主题与外观 / 与第七章对应 / 已知缺口）
  2. 节内每张表格都有「依据」列
  3. 节内无进度符号（⬜ 🟡 ✅）
  4. 节内无「旧本」「原 §」
  5. 文中出现的 Metrics/Spacing/Radius/Overlay.* 在 Core/DesignTokens.swift 里存在
  6. 文中出现的 AppShortcut.* 在 App/ShortcutCatalog.swift 里存在
  7. 文中出现的 FR-/NFR-/AC- 编号在需求规格书里存在

退出码: 0 全过 / 1 有失败 / 2 参数或文件问题
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOC = ROOT / "Docs" / "Doyah产品概要设计说明书.md"
SRS_GLOB = "Doyah产品需求规格说明书.md"
TOKENS = ROOT / "Core" / "DesignTokens.swift"
SHORTCUTS = ROOT / "App" / "ShortcutCatalog.swift"

SECTION = {"macos": "9.1", "windows": "9.2", "linux": "9.3", "ios": "9.4"}

# 主题 -> 小节标题里应出现的关键词（任一命中即算）
# profile：full = 有独立界面的端（macOS / Windows）；reuse = 复用他端前端（Linux）；
#          target = 尚无代码的目标形态（iOS）。三档要求的主题集不同，见规范 §2。
THEMES = {
    "窗口模型": ("窗口模型", "窗口与导航", "窗口"),
    "区域骨架与伸缩": ("区域骨架", "伸缩次序", "区域划分", "骨架"),
    "构件与尺寸": ("构件与尺寸", "尺寸", "构件"),
    "命令与键位": ("命令与键位", "键位", "命令"),
    "六态": ("六态", "状态表现", "状态"),
    "主题与外观": ("主题", "外观"),
    "与第七章对应": ("对应关系", "对应表", "与第七章"),
    "已知缺口": ("缺口", "待定"),
}
PROFILE = {
    "macos": "full",
    "windows": "full",
    "linux": "reuse",
    "ios": "target",
}
REQUIRED_BY_PROFILE = {
    "full": list(THEMES),
    "reuse": ["窗口模型", "命令与键位", "六态", "与第七章对应", "已知缺口"],
    "target": ["窗口模型", "六态", "与第七章对应", "已知缺口"],
}

PROGRESS = ("⬜", "🟡", "✅")
STALE = ("旧本", "原 §")


def fail(msg: str) -> None:
    print(f"❌ {msg}")


def ok(msg: str) -> None:
    print(f"✅ {msg}")


def slice_section(text: str, number: str) -> tuple[str, int] | None:
    """取 `## <number> ...` 到下一个同级 `## ` 之间的正文。"""
    pattern = re.compile(rf"^## {re.escape(number)} .*$", re.M)
    m = pattern.search(text)
    if not m:
        return None
    start = m.end()
    nxt = re.compile(r"^## ", re.M).search(text, start)
    end = nxt.start() if nxt else len(text)
    return text[start:end], text.count("\n", 0, start) + 1


def subsections(body: str) -> list[str]:
    return re.findall(r"^### (.+)$", body, re.M)


def tables(body: str) -> list[list[str]]:
    """返回每张表的表头单元格列表。"""
    out, lines = [], body.split("\n")
    for i, line in enumerate(lines):
        if line.strip().startswith("|") and i + 1 < len(lines) and re.match(r"^\s*\|[\s:|-]+\|\s*$", lines[i + 1]):
            out.append([c.strip() for c in line.strip().strip("|").split("|")])
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--platform", required=True, choices=sorted(SECTION))
    ap.add_argument("--doc", default=str(DOC))
    args = ap.parse_args()

    doc = Path(args.doc)
    for needed in (doc, TOKENS, SHORTCUTS):
        if not needed.exists():
            print(f"文件不存在: {needed}")
            return 2
    srs = sorted((doc.parent).glob(SRS_GLOB))
    if not srs:
        print(f"找不到需求规格书（{SRS_GLOB}）")
        return 2

    text = doc.read_text(encoding="utf-8")
    number = SECTION[args.platform]
    got = slice_section(text, number)
    if got is None:
        fail(f"找不到 `## {number}` 节")
        return 1
    body, line0 = got

    failures = 0

    profile = PROFILE[args.platform]

    # 1 主题（按 profile）
    titles = subsections(body)
    need = REQUIRED_BY_PROFILE[profile]
    missing = [t for t in need if not any(k in s for s in titles for k in THEMES[t])]
    if missing:
        failures += 1
        fail(f"缺主题小节：{'、'.join(missing)}（profile={profile}，当前 {len(titles)} 个 `###` 小节，起始行 {line0}）")
    else:
        ok(f"主题齐（profile={profile}，{len(titles)} 个 `###` 小节）")

    # 2 表格「依据」列：事实表必须；纯规格表（尺寸/六态/键位）不强制 ⇒ 记为提示
    ts = tables(body)
    bad_tables = [h for h in ts if not any("依据" in c for c in h)]
    if profile == "target":
        # 目标形态端没有代码可指：改要求正文写明「这是目标形态、不是现状」
        if "目标形态" not in body:
            failures += 1
            fail("profile=target 但正文未写明「目标形态」（没有代码可指，必须声明不是现状）")
        else:
            ok("目标形态已声明（无代码端免「依据」列）")
    elif bad_tables and len(bad_tables) == len(ts) and ts:
        failures += 1
        fail(f"节内 {len(ts)} 张表**一张都没有**「依据」列 —— 至少事实类表格要能指到代码")
    elif bad_tables:
        print(f"· 提示：{len(bad_tables)}/{len(ts)} 张表无「依据」列（纯规格表可不带；事实表必须带）")
        ok(f"表格检查通过（{len(ts)} 张，{len(ts) - len(bad_tables)} 张带依据）")
    else:
        ok(f"表格均带「依据」列（{len(ts)} 张）")

    # 3 进度符号
    hits = [(s, body.count(s)) for s in PROGRESS if s in body]
    if hits:
        failures += 1
        fail("出现进度符号：" + "、".join(f"{s}×{n}" for s, n in hits))
    else:
        ok("无进度符号")

    # 4 旧版引用
    hits = [s for s in STALE if s in body]
    if hits:
        failures += 1
        fail("出现旧版引用：" + "、".join(hits))
    else:
        ok("无「旧本 / 原 §」引用")

    # 5/6 标识符存在性
    token_src = TOKENS.read_text(encoding="utf-8")
    used = sorted({m for m in re.findall(r"\b(?:Metrics|Spacing|Radius|Overlay)\.([A-Za-z_][A-Za-z0-9_]*)", body)})
    ghosts = [u for u in used if not re.search(rf"\b{re.escape(u)}\b", token_src)]
    if ghosts:
        failures += 1
        fail("令牌表里不存在：" + "、".join(ghosts))
    else:
        ok(f"引用的令牌全部存在（{len(used)} 个）")

    sc_src = SHORTCUTS.read_text(encoding="utf-8")
    used_sc = sorted(set(re.findall(r"AppShortcut\.([A-Za-z_][A-Za-z0-9_]*)", body)))
    ghosts = [u for u in used_sc if not re.search(rf"case {re.escape(u)}\b", sc_src)]
    if ghosts:
        failures += 1
        fail("AppShortcut 里不存在：" + "、".join(ghosts))
    else:
        ok(f"引用的快捷键 case 全部存在（{len(used_sc)} 个）")

    # 7 需求编号存在性
    srs_text = "\n".join(p.read_text(encoding="utf-8") for p in srs)
    ids = sorted(set(re.findall(r"\b(?:FR|NFR|AC)-[A-Z0-9]+(?:-[A-Z0-9]+)+-\d{2,3}\b", body)))
    ghosts = [i for i in ids if i not in srs_text]
    if ghosts:
        failures += 1
        fail("需求书里不存在：" + "、".join(ghosts[:8]) + ("…" if len(ghosts) > 8 else ""))
    else:
        ok(f"引用的需求编号全部存在（{len(ids)} 个）")

    print()
    if failures:
        print(f"✗ §{number}（{args.platform}）未通过：{failures} 项失败 —— 规范见 Docs/规范/界面设计节-写作规范.md")
        return 1
    print(f"✓ §{number}（{args.platform}）界面设计节通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
