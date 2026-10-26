"""端级对账：**每一份「详细设计说明书-<端>」都必须有且只有一份「开发计划任务清单-<端>」**。

人类主人 2026-10-26 令原话：「任务清单和详细设计与平台有关，一一对应」。
本门禁把这条令做成机械判据，防止再出现「产品级总单 / 少一端 / 端名对不上」：

判据：
  A. 对每个 `Docs/Doyah产品详细设计说明书-<端>.md`（端 ∈ {macOS, Windows, Linux, Android, HarmonyOS, iOS}），
     必须存在 `Docs/Doyah产品开发计划任务清单-<端>端.md`（macOS/iOS/Linux 的写法见下表）；
  B. 不存在没有详设支撑的端级清单（孤本）；
  C. 不存在产品级总单（`Docs/Doyah产品开发计划任务清单.md` 这类不带端名的文件）；
  D. 每份端级清单都要有「变更记录」节。
"""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS = ROOT / "Docs"

# 详设里的端名 → 清单文件名里的端名（显式表，不做字符串猜测）
SHEET_NAME = {
    "macOS": "macOS端",
    "Windows": "Windows端",
    "Linux": "Linux端",
    "Android": "安卓端",
    "HarmonyOS": "HarmonyOS端",
    "iOS": "iOS端",
}

DESIGN = re.compile(r"^Doyah产品详细设计说明书-(?P<end>[A-Za-z]+)\.md$")
SHEET = re.compile(r"^Doyah产品开发计划任务清单-(?P<end>.+?)\.md$")


def check() -> list[str]:
    problems: list[str] = []
    designs = {}
    for path in sorted(DOCS.glob("Doyah产品详细设计说明书-*.md")):
        m = DESIGN.match(path.name)
        if m:
            designs[m.group("end")] = path

    sheets = {}
    for path in sorted(DOCS.glob("Doyah产品开发计划任务清单-*.md")):
        m = SHEET.match(path.name)
        if m:
            sheets[m.group("end")] = path

    for end, design in designs.items():
        expected = SHEET_NAME.get(end)
        if expected is None:
            problems.append(f"{design.name}: 端名 `{end}` 不在登记表里 —— 新增端时同步补 `Scripts/check-end-sheets.py` 的 SHEET_NAME")
            continue
        if expected not in sheets:
            problems.append(f"缺端级清单：{design.name} ⇒ 应有 `Docs/Doyah产品开发计划任务清单-{expected}.md`")
    for name, path in sheets.items():
        if name not in SHEET_NAME.values():
            problems.append(f"{path.name}: 没有对应的详设（端名 `{name}` 不在登记表里）")
    # C：不带端名的产品级总单
    for path in DOCS.glob("Doyah产品开发计划任务清单.md"):
        problems.append(f"{path.name}: 产品级总单已按令删除，不许再出现（任务清单必须带端名）")
    # D：变更记录节
    for path in sheets.values():
        if "## " not in path.read_text(encoding="utf-8"):
            problems.append(f"{path.name}: 缺「变更记录」节")
        elif not re.search(r"^## .*变更记录", path.read_text(encoding="utf-8"), re.M):
            problems.append(f"{path.name}: 缺「变更记录」节")
    return problems


def main() -> int:
    problems = check()
    if problems:
        print(f"❌ 端级对账失败（{len(problems)} 处）：")
        for p in problems:
            print(f"   · {p}")
        return 1
    ends = sorted(DESIGN.match(p.name).group("end") for p in DOCS.glob("Doyah产品详细设计说明书-*.md") if DESIGN.match(p.name))
    print(f"✅ 端级一一对应：{len(ends)} 端（{' / '.join(SHEET_NAME[e] for e in ends)}）各一份任务清单，无孤本、无产品级总单")
    return 0


if __name__ == "__main__":
    sys.exit(main())
