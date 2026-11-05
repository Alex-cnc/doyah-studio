#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""平台详设「派生自 macOS」判据（`check-platform-derivation.py`）。

为什么要这条判据
----------------
人类主人 2026-11-05：「有了 macOS 的详细设计并验证通过了绝大多数条目，其他平台端的详细设计就好做了 ——
参考 macOS 版本的设计，根据平台差异进行调整即可。」

这句话把方法定死成**派生**，不是各端各写一本。派生要能被判：每本平台详设必须
  ① 在头部写明「派生自 macOS 详设 vX」；
  ② 有一节「平台差异登记」，逐条对着 macOS 详设 §3 的每一个函数契约声明处置：
     `沿用` / `差异` / `不适用`（后两者必须给依据）；
  ③ 不得出现「既没声明、也没写」的节 —— 那正是「薄」的来源。

判据声明（覆盖范围，铁律 #13）
------------------------------
扫描：`Docs/Doyah产品详细设计说明书-*.md`（除 macOS 本体）。
读的是：头部 40 行、标题层级 `##`、以及差异登记表里的 `§3.N` 引用。
不读：正文内容是否正确、代码是否真实现（那由各端测试与骨架判据负责）。
⇒ 本条只判「有没有对每一节表态」，判不了「表得对不对」。

负例（铁律 #14）：`--self-test` 造四份临时文档 —— 齐的、缺头部声明的、缺一节的、把「不适用」写成空白的，
四条都必须得到预期的红 / 绿。
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

DOCS = Path(__file__).resolve().parent.parent / "Docs"
BASE = DOCS / "Doyah产品详细设计说明书-macOS.md"
BASE_ANDROID = DOCS / "Doyah产品详细设计说明书-Android.md"

# 基准按「族」定（主人 2026-11-05）：PC 族以 macOS 为基准；移动族以 Android 为基准（安卓已开发完，
# 已完工端不再回头补自己的详设，只当基准本体）。iOS 参考 Android 做详设 —— 不是参考 macOS。
BASELINE = {
    "macOS": None,      # 基准本体
    "Windows": "macOS",
    "Linux": "macOS",
    "Android": None,    # 移动族基准本体（已开发完，不再补）
    "iOS": "Android",
    "HarmonyOS": "Android",
}
SKIP_REASON = {
    "macOS": "基准本体（其余平台的派生源）",
    "Android": "移动族基准本体；端上已开发完（148 个 Kotlin 文件、gate.py 在跑），按主人 2026-11-05 令不再回头补详设",
}
SECTION = re.compile(r"^### (3\.\d+)\b")
PLATFORM = re.compile(r"Doyah产品详细设计说明书-(.+)\.md$")
DERIVE = re.compile(r"派生自[^\n]{0,60}详细设计说明书-(?P<base>[A-Za-z]+)\.md[^\n]{0,20}v(?P<version>\d+\.\d+\.\d+)")
DECLARED = re.compile(r"^\|\s*`?§?(3\.\d+)`?\s*\|(.+)$")


def base_sections(doc: Path) -> list[str]:
    text = doc.read_text(encoding="utf-8")
    return [m.group(1) for m in (SECTION.match(l) for l in text.splitlines()) if m]


DISPOSITIONS = ("沿用", "差异", "不适用", "未定")


def declared(text: str) -> dict[str, tuple[str, str]]:
    """差异登记表里声明的节 → （处置, 依据）。处置只认四个词，别的一律算「没表态」。"""
    found: dict[str, tuple[str, str]] = {}
    for line in text.splitlines():
        m = DECLARED.match(line)
        if not m:
            continue
        cells = [c.strip().strip("`") for c in line.strip().strip("|").split("|")]
        if len(cells) < 2:
            continue
        disposition = cells[1]
        basis = " ".join(cells[2:]).strip() if len(cells) > 2 else ""
        found[m.group(1)] = (disposition, basis)
    return found


def audit(doc: Path, base: list[str]) -> tuple[list[str], dict[str, str], str | None, list[str]]:
    text = doc.read_text(encoding="utf-8")
    head = "\n".join(text.splitlines()[:40])
    m = DERIVE.search(head)
    version = m.group("version") if m else None
    table = declared(text)
    missing = [s for s in base if s not in table]
    weak = []
    for section, (disposition, basis) in table.items():
        if disposition not in DISPOSITIONS:
            weak.append(section)
        elif disposition in ("差异", "不适用") and (not basis or basis in ("—", "-", "无")):
            weak.append(section)
    return missing, table, version, weak


def main() -> int:
    if "--self-test" in sys.argv:
        return self_test()
    bases = {
        "macOS": base_sections(BASE),
        "Android": base_sections(BASE_ANDROID) if BASE_ANDROID.exists() else [],
    }
    if not bases["macOS"] or not bases["Android"]:
        print("❌ 读不到基准详设的 §3 节清单（基线文件缺失或被改名）")
        return 1
    print(f"基线：macOS §3 共 {len(bases['macOS'])} 节 · Android §3 共 {len(bases['Android'])} 节")
    docs = sorted(p for p in DOCS.glob("Doyah产品详细设计说明书-*.md") if p != BASE)
    bad = 0
    for doc in docs:
        matched = PLATFORM.match(doc.name)
        name = matched.group(1) if matched else doc.stem
        baseline = BASELINE.get(name, "macOS")
        if baseline is None:
            print(f"  ⏭️  {name:10} 跳过 —— {SKIP_REASON.get(name, '基准本体')}")
            continue
        base = bases[baseline]
        missing, table, version, weak = audit(doc, base)
        dm = DERIVE.search("\n".join(doc.read_text(encoding="utf-8").splitlines()[:40]))
        declared_base = dm.group("base") if dm else None
        status = []
        if version is None:
            status.append(f"缺「派生自 {baseline} 详设 vX」声明")
        elif declared_base != baseline:
            status.append(f"声明派生自 {declared_base}，但基准应是 {baseline}")
        if missing:
            status.append(f"未表态 {len(missing)} 节：{'、'.join(missing[:6])}{' …' if len(missing) > 6 else ''}")
        if weak:
            status.append(f"处置列空/过短 {len(weak)} 行")
        if status:
            bad += 1
            print(f"  ❌ {name:10} 基准 {baseline:8} 已表态 {len(table):2}/{len(base)}  —  " + "；".join(status))
        else:
            print(f"  ✅ {name:10} 基准 {baseline:8} 已表态 {len(table):2}/{len(base)}  派生自 v{version}")
    if bad:
        print(f"\n❌ {bad} 本平台详设没做到「逐节表态」。要补的是差异登记表，不是把文档写长。")
        return 1
    print("\n✅ 全部平台详设都写着「派生自 macOS 详设」并逐节表过态")
    return 0


def self_test() -> int:
    import tempfile

    base = ["3.1", "3.2", "3.3"]
    cases = {
        "齐的": ("派生自 `Docs/Doyah产品详细设计说明书-macOS.md` v1.0.22\n\n| macOS 节 | 处置 | 依据 |\n|---|---|---|\n"
              "| `§3.1` | 沿用 | 同源 |\n| `§3.2` | 差异 | WebView2 |\n| `§3.3` | 不适用 | 无此面 |\n"),
        "缺声明": ("没有那行声明\n\n| macOS 节 | 处置 | 依据 |\n|---|---|---|\n"
                "| `§3.1` | 沿用 | x |\n| `§3.2` | 沿用 | x |\n| `§3.3` | 沿用 | x |\n"),
        "缺一节": ("派生自 `Docs/Doyah产品详细设计说明书-macOS.md` v1.0.22\n\n| macOS 节 | 处置 | 依据 |\n|---|---|---|\n"
                "| `§3.1` | 沿用 | x |\n| `§3.2` | 沿用 | x |\n"),
        "处置空白": ("派生自 `Docs/Doyah产品详细设计说明书-macOS.md` v1.0.22\n\n| macOS 节 | 处置 | 依据 |\n|---|---|---|\n"
                  "| `§3.1` | 沿用 | x |\n| `§3.2` | — | x |\n| `§3.3` | 沿用 | x |\n"),
    }
    expect = {"齐的": True, "缺声明": False, "缺一节": False, "处置空白": False}
    ok = True
    with tempfile.TemporaryDirectory() as tmp:
        for name, text in cases.items():
            p = Path(tmp) / "x.md"
            p.write_text(text, encoding="utf-8")
            missing, table, version, weak = audit(p, base)
            green = not missing and version is not None and not weak
            mark = "✅" if green == expect[name] else "❌"
            if green != expect[name]:
                ok = False
            print(f"  {mark} 负例「{name}」：判定 {'绿' if green else '红'}（预期 {'绿' if expect[name] else '红'}）"
                  f" 缺 {len(missing)} 节 · 版本 {version} · 弱行 {len(weak)}")
    print("自检通过" if ok else "自检失败：判据没有按预期判红")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
