#!/usr/bin/env python3
"""分册 ⊆ 全量：独立产品仓的四书分册不许出现全量四书里没有的编号。

为什么需要（人类主人 2026-11-01 重申）：
  Agent / Studio / Notes / Retro 四个功能在 PC 端是**同一个产品**，四书写在同一份全量书里（studio 仓）；
  Notes / Retro 是**独立产品**，独立仓里的四书是**从全量书裁剪出来的分册**，只裁剪不增删；
  **唯一例外是任务清单** —— Notes / Retro 各记各的，全量 Studio 仓也有自己那份。

违规的两种形态：
  ① 分册有、全量无  ⇒ **全量漏登**（该补进全量四书，不是分册乱写）
  ② 分册改条文内容  ⇒ 越权（本判据不判内容，靠评审）

覆盖范围（铁律 #13）：只比**五段式**编号（`FR|NFR|AC-<产品码>-<面>-<域>-三位序号`）。
  分册里的旧式编号（如 retro 的 `IR-01`）不计入比较，但会在输出里列成「未换号」——
  这些条目的归属是**未知**，不是「合规」。

判据：rc=0 全量覆盖分册；rc=1 有分册编号在全量里找不到（付清单）。
负例（铁律 #14）：`--self-test` 造一本塞了野编号的分册 ⇒ 必须判红。
"""

from __future__ import annotations

import argparse
import pathlib
import re
import shutil
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent          # studio/
LEAD = ROOT.parent                                            # ~/dev/doyah/lead/
L0_BOOKS = [                       # 编号集合来源（需求书 + 概设；能力书按纪律不引编号）
    ROOT / "Docs/Doyah产品需求规格说明书.md",
    ROOT / "Docs/Doyah产品概要设计说明书.md",
]
# 逐行比对用的**正文池**：四本全量书（能力 / 需求 / 概设 / 详设-Android）都算来源
POOL_BOOKS = L0_BOOKS + [
    ROOT / "Docs/Doyah产品能力规划说明书.md",
    ROOT / "Docs/Doyah产品详细设计说明书-Android.md",
]
# 分册仓：独立产品仓，其 Docs/ 是分册（任务清单除外，本判据不看进度）
FASCICLES = [
    # 只认**正式分册**（2026-11-01 起按主人令从全量四书复制生成的那几本）。
    # Notes 仓里旧的《需求规范书 / 概要设计 / 核心契约》属历史遗留，不在分册之列 —— 它们若被扫进来，
    # 会把实现级条目（RichEditor / hvigorw 之类）当成需求，制造假缺口（见 04e1e1ea）。
    ("Notes",  LEAD / "notes" / "Docs", "Doyah Notes产品*.md"),
    ("Retro",  LEAD / "retro" / "Docs", "Doyah Retro产品*.md"),
]

ID_RE = re.compile(r"(?:FR|NFR|AC)-[A-Z]{2,4}-[A-Z]{2,8}-[A-Z]{2,8}-\d{3}")
# 实现级识别的**弱**启发：定义行里出现控件名 / 构建命令 / 数据层实现 ⇒ 更像实现条目而不是产品需求。
# 只用来分桶提示，不单独判决（可能漏判，故输出里写明「需人核」）。
IMPL_HINTS = re.compile(r"`[^`]+`|RichEditor|hvigorw|gradle|RDB|SQLite|Kotlin|Compose|Room|MMKV|ViewModel|Coroutines?")
LEGACY_RE = re.compile(r"\bIR-\d{1,3}\b")


def collect(paths: list[pathlib.Path], recursive: bool, pattern: str = "*.md") -> set[str]:
    out: set[str] = set()
    for p in paths:
        files = p.rglob(pattern) if recursive else [p]
        for f in files:
            if ".git" in f.parts or not f.exists():
                continue
            try:
                out |= set(ID_RE.findall(f.read_text(encoding="utf-8")))
            except (UnicodeDecodeError, OSError):
                continue
    return out


def defs_of(directory: pathlib.Path) -> dict[str, str]:
    """分册里 `| <编号> | … |` 形式的定义行（用于分桶判断，不参与集合比较）。"""
    out: dict[str, str] = {}
    for f in directory.rglob("*.md"):
        if ".git" in f.parts:
            continue
        try:
            for line in f.read_text(encoding="utf-8").split("\n"):
                m = re.match(r"^\|\s*((?:FR|NFR|AC)-[A-Z]{2,4}-[A-Z]{2,8}-[A-Z]{2,8}-\d{3})\s*\|", line)
                if m:
                    out.setdefault(m.group(1), line)
        except (UnicodeDecodeError, OSError):
            continue
    return out


def line_gaps(fascicle: pathlib.Path, pool: set[str]) -> list[str]:
    """分册**正文**逐行必须出现在全量书里（头部元信息块除外）。

    为什么要这条：分册只继承、不自造。第一版分册我自造过一行「[产品特有] 落点」说明——
    编号集合判据看不见它（不带编号），但它违反了「分册除任务清单外全部继承自全量」。
    允许的差异只有：H1 标题 + 元信息表 + 「收进来/不收的章」清单 + 分隔线（即首个 `---` 之前的部分）。
    """
    text = fascicle.read_text(encoding="utf-8")
    body = text.split("\n---\n", 1)[1] if "\n---\n" in text else text
    return [l.rstrip() for l in body.split("\n") if l.strip() and l.rstrip() not in pool]


def legacy_ids(directory: pathlib.Path) -> set[str]:
    out: set[str] = set()
    for f in directory.rglob("*.md"):
        if ".git" in f.parts:
            continue
        try:
            out |= set(LEGACY_RE.findall(f.read_text(encoding="utf-8")))
        except (UnicodeDecodeError, OSError):
            continue
    return out


def run(l0_books: list[pathlib.Path], fascicles: list[tuple[str, pathlib.Path, str]], quiet: bool = False,
        pool_books: list[pathlib.Path] | None = None) -> int:
    missing_files = [b for b in l0_books if not b.exists()]
    if missing_files:
        def _short(m: pathlib.Path) -> str:
            try:
                return m.relative_to(ROOT).as_posix()
            except ValueError:
                return m.name
        print("❌ 全量四书不在盘上：" + ", ".join(_short(m) for m in missing_files))
        return 1
    l0 = collect(l0_books, recursive=False)
    if not quiet:
        print(f"全量四书（{len(l0_books)} 本）编号：{len(l0)} 个")

    bad: dict[str, list[str]] = {}
    linebad: dict[str, list[str]] = {}
    for name, directory, pattern in fascicles:
        if not directory.exists():
            if not quiet:
                print(f"ℹ️ {name} 分册目录不在盘上（{directory}）⇒ 本条对 {name} 报「未知」，不报「通过」")
            continue
        ids = collect([directory], recursive=True, pattern=pattern)
        pool: set[str] = set()
        for b in (pool_books if pool_books is not None else POOL_BOOKS):
            pool |= {l.rstrip() for l in b.read_text(encoding="utf-8").split("\n")}
        for fac in sorted(directory.glob(pattern)):
            if "任务清单" in fac.name:
                continue
            lg = line_gaps(fac, pool)
            if lg:
                print(f'      ⚠️ {fac.name}: 正文有 {len(lg)} 行不在全量书里（分册不许自造内容）')
                for l in lg[:3]:
                    print(f'         {l[:90]}')
                linebad[name] = linebad.get(name, []) + lg
        gap = sorted(ids - l0)
        legacy = legacy_ids(directory)
        if not quiet:
            line = f"  · {name}: 分册 {len(ids)} 个编号 · 全量没有 {len(gap)} 个"
            if legacy:
                line += f" · 另有旧式编号 {len(legacy)} 个（未换号，归属未知）"
            print(line)
        if gap:
            bad[name] = gap
            d = defs_of(directory)
            impl = [i for i in gap if i in d and IMPL_HINTS.search(d[i])]
            rest = [i for i in gap if i not in impl]
            if not quiet:
                print(f"      · 其中定义行含控件/构建/数据层标识（实现级嫌疑）：{len(impl)} 条")
                print(f"      · 其余（疑似功能级漏登，需人核）：{len(rest)} 条")

    if linebad:
        print("\n❌ 分册正文有全量书里不存在的行（分册只继承、不自造）：")
        for name, lg in linebad.items():
            print(f"  [{name}] {len(lg)} 行")
            for l in lg[:5]:
                print(f"     {l[:100]}")
        print("\n处理：这些是分册自造的内容 ⇒ ① 要么删掉；② 要么先写进全量书对应章（标 [产品特有] 并注明来源），再重新裁剪。")

    if bad:
        print("\n⚠️ 分册有、全量无 —— 不是同一类问题，分两桶看：")
        for name, gap in bad.items():
            d = defs_of(next(x for n, x, _p in fascicles if n == name))
            impl = [i for i in gap if i in d and IMPL_HINTS.search(d[i])]
            rest = [i for i in gap if i not in impl]
            print(f"  [{name}] 共 {len(gap)} 条")
            print(f"    ① 实现条目嫌疑 {len(impl)} 条（控件选型 / 构建命令 / 数据层实现）"
                  f"⇒ **不该进需求层**；它们用了 `FR-/NFR-/AC-` 五段式，才被当成需求，"
                  f"应改用用例号或契约条款号，或在分册里标成实现条目")
            if impl:
                print(f"       {', '.join(impl[:6])}{' …' if len(impl) > 6 else ''}")
            print(f"    ② 疑似功能级漏登 {len(rest)} 条（含 UI 微条目，如「加粗（B）」—— 粒度是否该上收由人判）")
            if rest:
                print(f"       {', '.join(rest[:6])}{' …' if len(rest) > 6 else ''}")
        print("\n处理顺序：先判 ① 改名归位（机械，不动条文），再逐条判 ② 哪些是全量书该有的产品级需求。")
        print("⚠️ 覆盖声明：② 的归类靠「定义行是否含控件/构建标识」的弱启发，会漏判 ⇒ 只作分桶提示，判决靠人核。")
    if bad or linebad:
        return 1
    print("\n✅ 分册 ⊆ 全量：分册里没有全量四书未登记的编号")
    return 0


def self_test() -> int:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="book-subset-"))
    cases = []
    try:
        # 底座：全量书含一条编号；分册只含同一条 ⇒ 绿
        (tmp / "Docs").mkdir()
        (tmp / "Docs/l0.md").write_text("| FR-NTS-NOTE-CAPTURE-001 | x |\n", encoding="utf-8")
        ok_fas = tmp / "ok" / "Docs"; ok_fas.mkdir(parents=True)
        (tmp / "Docs/l0.md").write_text("| FR-NTS-NOTE-CAPTURE-001 | x |\n\n见 FR-NTS-NOTE-CAPTURE-001\n", encoding="utf-8")
        (ok_fas / "a.md").write_text("# 分册\n\n---\n\n见 FR-NTS-NOTE-CAPTURE-001\n", encoding="utf-8")
        # 负例：分册塞一条全量没有的 ⇒ 必须红
        bad_fas = tmp / "bad" / "Docs"; bad_fas.mkdir(parents=True)
        (bad_fas / "a.md").write_text("见 FR-NTS-NOTE-CAPTURE-001 与 FR-NTS-ALL-HOME-999\n", encoding="utf-8")

        import io, contextlib
        def rc_of(fas):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                r = run([tmp / "Docs/l0.md"], [("X", fas, "*.md")], quiet=True, pool_books=[tmp / "Docs/l0.md"])
            return r, buf.getvalue()

        r_ok, _ = rc_of(ok_fas)
        r_bad, out_bad = rc_of(bad_fas)
        cases.append(("分册 ⊆ 全量 ⇒ 绿", r_ok == 0))
        cases.append(("分册塞野编号 ⇒ 红", r_bad == 1 and "FR-NTS-ALL-HOME-999" in out_bad))
        cases.append(("全量书缺文件 ⇒ 红", run([tmp / "Docs/nope.md"], [("X", ok_fas, "*.md")], quiet=True) == 1))
        # 负例：分册正文自造一行不在全量书里 ⇒ 必须红（编号判据看不见它）
        (ok_fas / "a.md").write_text("见 FR-NTS-NOTE-CAPTURE-001\n\n---\n\n这条是分册自造的，全量书里没有\n", encoding="utf-8")
        r_line, out_line = rc_of(ok_fas)
        cases.append(("分册正文自造一行 ⇒ 红", r_line == 1 and "不在全量书里" in out_line))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print("自测：")
    for name, ok in cases:
        print(f"  {'✓' if ok else '✗'} {name}")
    passed = sum(1 for _, ok in cases if ok)
    print(f"自测：{passed}/{len(cases)} 例通过")
    return 0 if passed == len(cases) else 1


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    return run(L0_BOOKS, FASCICLES)


if __name__ == "__main__":
    sys.exit(main())
