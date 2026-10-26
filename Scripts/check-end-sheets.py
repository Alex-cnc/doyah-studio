"""端级对账：**任务清单只给正在开发的端建**（人类主人 2026-10-26 令：只有 macOS 端与 Android 端）。

判据：
  A. 允许存在的端清单 = `{macOS端, 安卓端}`；出现别的端清单（iOS / Windows / Linux / HarmonyOS …）即判红；
  B. 每份存在的端清单必须有同名详设兜着（`Docs/Doyah产品详细设计说明书-<端>.md`）；
  C. 不存在不带端名的产品级总单（`Docs/Doyah产品开发计划任务清单.md`）；
  D. 每份端清单要有「变更记录」节；
  E. 跨端视图（平台矩阵 / 按平台清单 / 需求索引）只能是 `.build/derived/` 下的派生件，不许放 `Docs/`。

「详设有、清单没有」不算错：Windows / Linux / HarmonyOS / iOS 有详设但当前没有开发主体，
真开工时把端名加进 ALLOWED_SHEETS 并建清单即可。
"""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS = ROOT / "Docs"
DERIVED = ROOT / ".build" / "derived"

# 允许存在的端清单（键 = 清单文件名里的端名，值 = 详设文件名里的端名）
ALLOWED_SHEETS = {
    "macOS端": "macOS",
    # 2026-10-26 人类主人令：留小河马新建并维护的 `-Android.md`；旧 `-安卓端.md` 已归档。
    "Android": "Android",
}

# 判据 H：`Docs/` 根只许「四书 + 一单 + 工程规范」。任何别的书/清单/索引/记录/发布说明都不许待在根上。
BOOK_PATTERNS = [
    r"^Doyah产品能力规划说明书(-变更记录)?\.md$",
    r"^Doyah产品需求规格说明书(-变更记录|-追溯表)?\.md$",
    r"^Doyah产品概要设计说明书(-变更记录)?\.md$",
    # 详设按端一一对应（每端一份，端名与 `ALLOWED_SHEETS` 的规范端名一致）
    r"^Doyah产品详细设计说明书-(macOS|Android|Windows|Linux|HarmonyOS|iOS)\.md$",
]
SHEET_PATTERN = r"^Doyah产品开发计划任务清单-(%s)\.md$" % "|".join(ALLOWED_SHEETS)
# 工程规范：写「怎么做活」的，不是产品书；人类主人 2026-10-26 口径里只留这两份 + 一份模板 + README
ENGINEERING_DOCS = {
    "README.md",
    "Doyah开发规范.md",
    "模板-详细设计说明书-Studio.md",
}

SHEET = re.compile(r"^Doyah产品开发计划任务清单-(?P<end>.+?)\.md$")


def check() -> list[str]:
    problems: list[str] = []
    sheets: dict[str, pathlib.Path] = {}
    for path in sorted(DOCS.glob("Doyah产品开发计划任务清单-*.md")):
        m = SHEET.match(path.name)
        if m:
            sheets[m.group("end")] = path

    seen_ends: dict[str, str] = {}
    for end, path in sheets.items():
        canonical = ALLOWED_SHEETS.get(end)
        if canonical is None:
            continue
        if canonical in seen_ends:
            problems.append(
                f"{path.name} 与 {seen_ends[canonical]} 是**同一个端的两份清单**（{canonical}）"
                "—— 清单每端只留一份活件；留哪一份、删哪一份要人类主人拍板，脚本不替他决定")
        else:
            seen_ends[canonical] = path.name

    for end, path in sheets.items():
        if end not in ALLOWED_SHEETS:
            problems.append(
                f"{path.name}: 不属于允许的端（只许 {' / '.join(ALLOWED_SHEETS)}）"
                "—— 其他端还没开工，不建清单；真要开工时把端名加进 ALLOWED_SHEETS")
            continue
        design = DOCS / f"Doyah产品详细设计说明书-{ALLOWED_SHEETS[end]}.md"
        if not design.exists():
            problems.append(f"{path.name}: 找不到兜底的详设 {design.name}")

    for end in ALLOWED_SHEETS:
        if end not in sheets:
            problems.append(f"缺端清单：应有 `Docs/Doyah产品开发计划任务清单-{end}.md`")

    # I. 各端的一单**只认同端详设活书**（人类主人 2026-10-26 令）
    #    —— 不许引别人的详设，也不许把冻结件当上游；活书 = 不带版本号的那份。
    all_ends = sorted(set(ALLOWED_SHEETS.values()))
    for end, path in sheets.items():
        canonical = ALLOWED_SHEETS.get(end)
        if canonical is None:
            continue
        live = DOCS / f"Doyah产品详细设计说明书-{canonical}.md"
        if not live.exists():
            problems.append(f"{path.name}: 同端详设活书缺失（应有 `Docs/{live.name}`，不许拿冻结件顶）")
        head = "\n".join(path.read_text(encoding="utf-8").splitlines()[:40])
        if canonical not in head:
            problems.append(f"{path.name}: 头部没有指向同端详设（缺 `{canonical}`）—— 一单只认同端详设活书版")
        for other in all_ends:
            if other == canonical:
                continue
            if f"详细设计说明书-{other}" in head or f"详细设计说明书 · {other}" in head:
                problems.append(f"{path.name}: 头部引了**别端**的详设（{other}）—— 各端一单只认同端详设活书版")
        if re.search(r"-v\d+\.\d+-\d{8}\.md", head):
            problems.append(f"{path.name}: 头部把**冻结件**当上游 —— 一单跟的是同端详设**活书**，不是冻结快照")

    # H. 根目录只许四书 + 一单 + 工程规范（人类主人 2026-10-26 令「以后任何开发侧都只有四书一单」）
    allowed = re.compile("|".join(BOOK_PATTERNS + [SHEET_PATTERN]))
    for path in sorted(DOCS.glob("*.md")):
        if path.name in ENGINEERING_DOCS or allowed.match(path.name):
            continue
        problems.append(
            f"Docs/{path.name}: 不在「四书一单」范围内 —— 开发侧只留四书（能力 / 需求 / 概要 / 详设-<端>）"
            "与一单（任务清单-<端>，每端一份）；过程件一律进 Docs/archive/")

    if (DOCS / "Doyah产品开发计划任务清单.md").exists():
        problems.append("Docs/Doyah产品开发计划任务清单.md: 产品级总单已按令删除，不许再出现（清单必须带端名）")

    for path in sheets.values():
        if not re.search(r"^## .*变更记录", path.read_text(encoding="utf-8"), re.M):
            problems.append(f"{path.name}: 缺「变更记录」节")

    for stray in ("平台矩阵.md", "任务清单-按平台.md", "需求索引.md"):
        if (DOCS / stray).exists():
            problems.append(f"Docs/{stray}: 跨端视图/派生件不许放 Docs/，应落 .build/derived/")
    for need in ("平台矩阵.md", "任务清单-按平台.md"):
        if not (DERIVED / need).exists():
            print(f"ℹ️  派生件 {need} 未生成（跑 gen-platform-parity.py / gen-platform-board.py 即可）")

    # F：任务清单永远只有一份活件 —— 不许做版本快照（人类主人 2026-10-26 令）
    for path in list(DOCS.glob("Doyah产品开发计划任务清单-*.md")) + list((DOCS / "frozen").glob("*任务清单*.md")):
        if re.search(r"-v\d+(?:\.\d+)*-\d{8}\.md$", path.name):
            problems.append(f"{path.relative_to(ROOT)}: 任务清单不做版本快照 —— 四书才冻结，清单一律是活件")

    # G：四书 v1.0 冻结齐四份（活书在 Docs/，冻结件在 Docs/frozen/）
    FOUR_BOOKS = ("能力规划说明书", "需求规格说明书", "概要设计说明书", "详细设计说明书-macOS")
    frozen = sorted(p.name for p in (DOCS / "frozen").glob("*-v*-*.md"))
    for book in FOUR_BOOKS:
        if not any(book in name for name in frozen):
            problems.append(f"Docs/frozen/ 缺《{book}》的冻结快照（四书都可冻结，任务清单不冻）")
    return problems


def main() -> int:
    problems = check()
    if problems:
        print(f"❌ 端级对账失败（{len(problems)} 处）：")
        for p in problems:
            print(f"   · {p}")
        return 1
    print("✅ 端级对账通过：任务清单只有 macOS 端 + Android 端（小河马维护），各有一份详设兜底；"
          "无孤本、无产品级总单、无跨端视图混进 Docs/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
