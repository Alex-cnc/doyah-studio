#!/usr/bin/env python3
"""把当前活书冻结成新版本（人类主人 2026-10-26 工作流的第 ④ 步）。

工作流：活书从冻结版复制出来 → 在活书上干活 → 漂移到阈值 → **问人类** → 他同意 → 跑本脚本 →
活书与冻结版重新一致 → 继续干活。

本脚本做四件事，缺一不可：
  1. 逐字复制四本活书 → `Docs/frozen/<书名>-<版本>-<日期>.md`（**旧版本文件保留**，冻结史不覆盖）；
  2. 重写 `Docs/frozen/README.md` 清单（冻结史 + 当前基线 + 行数 + sha256 前 16 + 刷新纪律）；
  3. 跑 `check-frozen-sync.py --strict` 自证（必须 rc=0，否则本次冻结不算成立）；
  4. 打印这次冻结「相对上一版的差异行数」，供回执引用。

用法：
  python3 Scripts/freeze-books.py --version v1.1                    # 关账成 v1.1
  python3 Scripts/freeze-books.py --version v1.1 --date 20261026 --note "17 条旧版编号收口 + 详设三条内核约束"
"""
from __future__ import annotations

import argparse
import datetime as dt
import difflib
import hashlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FROZEN = ROOT / "Docs/frozen"
BOOKS = [
    ("Docs/Doyah产品需求规格说明书.md", "Doyah产品需求规格说明书"),
    ("Docs/Doyah产品概要设计说明书.md", "Doyah产品概要设计说明书"),
    ("Docs/Doyah产品能力规划说明书.md", "Doyah产品能力规划说明书"),
    ("Docs/Doyah产品详细设计说明书-macOS.md", "Doyah产品详细设计说明书-macOS"),
]


def latest(stem: str) -> tuple[Path | None, str]:
    found = []
    for p in FROZEN.glob(f"{stem}-v*-*.md"):
        m = re.fullmatch(rf"{re.escape(stem)}-v(\d+(?:\.\d+)*)-(\d{{8}})\.md", p.name)
        if m:
            found.append((tuple(int(x) for x in m.group(1).split(".")), m.group(2), p))
    if not found:
        return None, ""
    version, date, path = max(found)
    return path, f"v{'.'.join(map(str, version))}-{date}"


def diff_lines(old: Path | None, new: Path) -> tuple[int, int]:
    a = old.read_text(encoding="utf-8").splitlines() if old and old.exists() else []
    b = new.read_text(encoding="utf-8").splitlines()
    sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
    add = sum(j2 - j1 for tag, _i1, _i2, j1, j2 in sm.get_opcodes() if tag in ("insert", "replace"))
    dele = sum(i2 - i1 for tag, i1, i2, _j1, _j2 in sm.get_opcodes() if tag in ("delete", "replace"))
    return add, dele


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True, help="新冻结版本号，如 v1.1")
    ap.add_argument("--date", default=dt.date.today().strftime("%Y%m%d"))
    ap.add_argument("--note", default="", help="这次冻结的内容摘要（写进清单）")
    args = ap.parse_args()

    if not re.fullmatch(r"v\d+(\.\d+)*", args.version):
        print(f"✗ 版本号形状不对：{args.version}（要 vX.Y）")
        return 1

    rows = []
    for live_rel, stem in BOOKS:
        live = ROOT / live_rel
        if not live.exists():
            print(f"✗ 活书不存在：{live_rel}")
            return 1
        old, old_label = latest(stem)
        add, dele = diff_lines(old, live)
        dest = FROZEN / f"{stem}-{args.version}-{args.date}.md"
        data = live.read_bytes()
        dest.write_bytes(data)
        n = data.decode().count("\n")
        rows.append((dest.name, live_rel, n, hashlib.sha256(data).hexdigest()[:16], old_label, add, dele))
        print(f"  冻结 {dest.name}  ← {live_rel} · {n} 行 · 相对 {old_label or '（首版）'} +{add}/−{dele}")

    manifest = ["# 冻结清单（Doyah 产品 · 四书）", "",
        f"> **当前基线：{args.version}（{args.date}）**。活书是从这里复制出来干活的；"
        "漂移变大时由 `Scripts/check-frozen-sync.py` 提示人类「是否冻结成新版本」，他同意才跑 "
        "`Scripts/freeze-books.py`。冻结件是**快照**，不承担版本号唯一/头部版本格纪律（见 "
        "`Scripts/check-doc-versions.py` 的 `COVERAGE_EXEMPT`）。", "",
        f"## {args.version}（{args.date}）— 当前基线", ""]
    if args.note:
        manifest += [f"冻结说明：{args.note}", ""]
    for name, live_rel, n, h, old_label, add, dele in rows:
        manifest.append(f"- `{name}` ← `{live_rel}` · **{n} 行** · sha256 `{h}` · 相对 {old_label or '首版'} +{add}/−{dele} 行")
    manifest += ["",
        "- **纪律**：① 改活书 → 跑 `check-frozen-sync.py`（小差异正常，超阈值才提示冻结）；"
        "② 冻结 = 跑 `freeze-books.py --version vX.Y`，它自动复制 + 重写本清单 + `--strict` 自证；"
        "③ 旧版本文件保留，不覆盖（冻结史即目录列表）。",
        "- **停用副本**：`~/.dsh/projects/DoyahStudio/Docs/` 已于 2026-10-26 停用，不是判据源。",
        ""]
    (FROZEN / "README.md").write_text("\n".join(manifest))
    print(f"清单已重写：Docs/frozen/README.md（基线 {args.version}）")

    rc = subprocess.run([sys.executable, str(ROOT / "Scripts/check-frozen-sync.py"), "--strict"],
                        cwd=ROOT).returncode
    print(f"自证 check-frozen-sync --strict → rc={rc}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
