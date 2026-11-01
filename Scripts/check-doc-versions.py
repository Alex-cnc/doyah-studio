#!/usr/bin/env python3
"""书/单的版本号纪律（2026-10-26 人类主人令改判）。

新判据（旧「变更记录」体系整体废弃）：
  ① 每本书 / 每份单**头部必须有三段式版本号** `v<冻结段>.<次>.<流水>`，例 `v1.0.430`；
     第三段 = 自该冻结段起第几次改动，**上限 999**（满 999 就该冻结成 `v1.1`，活书转 `v1.1.NNN`）。
  ② **书里不许再有「变更记录」节**，也不许引用 `-变更记录.md` —— 逐轮改了什么由 git 提交历史承载
     （人类主人 2026-10-26：「每次推送都会有 Git 记录……不要把 Git 的修改记录放到活书里」）。
  ③ 待拍板队列的条目号（`Q<数字>`）在《项目管理规范》里唯一。

用法：`python3 Scripts/check-doc-versions.py`（exit 0 = 通过）；`--self-test` 跑成对自检。

判据自己的证据（8 例）：`--self-test` 里 7 个文件样本（好 / 非三段 / 超上限 / 带变更记录 / 引旧文件 /
999 未冻结 / 998 免检）+ 1 个「999 已冻结 ⇒ 绿」，收尾自己报 `负例 N/N 达到预期`，由
`Scripts/self-test-counts.json` 的 `doc-versions` 族逐行对账（2026-11-02：这段被 2026-10-26 的整段
重写删掉了，台账里还留着旧版本的 28 例 —— 判据看不见「runner 不再报数」这类漂移，现补回）。
"""
from __future__ import annotations

import argparse
import hashlib
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS = ROOT / "Docs"

EXEMPT_PREFIXES = ("Docs/archive/", "Docs/frozen/")

VERSION_THREE = re.compile(r"v(\d+)\.(\d+)\.(\d+)")
VERSION_ANY = re.compile(r"v\d+\.\d+(?:\.\d+)?")
CHANGELOG_HEADING = re.compile(r"^#{1,6}\s.*变更记录")
CHANGELOG_REF = re.compile(r"-变更记录\.md")
QUEUE_ID = re.compile(r"^\|\s*\**Q(\d+)\**\s*\|")

# 自动冻结（2026-11-01 人类主人令）：`v1.0.NNN` 的流水段加到 999 就不再自增，
# 该段的冻结件必须已经存在，活书转下一段 `vA.(B+1).0`。
FROZEN_DIR = DOCS / "frozen"
ROLLOVER_AT = 999

HEAD_SCAN_LINES = 20


def targets() -> list[pathlib.Path]:
    out = []
    for path in sorted(DOCS.glob("*.md")):
        rel = path.relative_to(ROOT).as_posix()
        if rel.startswith(EXEMPT_PREFIXES):
            continue
        out.append(path)
    return out


def header_version(lines: list[str]) -> str | None:
    for line in lines[:HEAD_SCAN_LINES]:
        if "版本" not in line:
            continue
        match = VERSION_ANY.search(line)
        if match:
            return match.group(0)
    return None


def frozen_baselines(frozen_dir: pathlib.Path, stem: str, segment: str) -> list[pathlib.Path]:
    """找「同一本书 + 同一冻结段」的冻结件，形如 `<书名>-v1.0-20261025.md`。"""
    if not frozen_dir.exists():
        return []
    return sorted(frozen_dir.glob(f"{stem}-{segment}-*.md"))


def check_rollover(rel: str, stem: str, three: re.Match, frozen_dir: pathlib.Path,
                   live: pathlib.Path) -> list[str]:
    """流水到 999 ⇒ 该段必须已冻结**现在这一版**（逐字一致），否则不许再自增。

    为什么要比逐字而不是「有这个文件名」：`Docs/frozen/` 里早就有 `-v1.0-20261025` 这类老基线，
    只判「同名段冻结件存在」会被老文件蒙过去 —— 实测把活书改成 999 仍然绿，等于没有判据。
    """
    if int(three.group(3)) < ROLLOVER_AT:
        return []
    segment = f"v{three.group(1)}.{three.group(2)}"
    digest = hashlib.sha256(live.read_bytes()).hexdigest()
    for candidate in frozen_baselines(frozen_dir, stem, segment):
        if hashlib.sha256(candidate.read_bytes()).hexdigest() == digest:
            return []
    return [
        f"{rel}: 流水段已到 {ROLLOVER_AT}（`{segment}.{ROLLOVER_AT}`）⇒ **必须先冻结** —— "
        f"`python3 Scripts/freeze-books.py --version {segment}` 生成 `{stem}-{segment}-YYYYMMDD.md`，"
        f"然后活书转下一段 `v{three.group(1)}.{int(three.group(2)) + 1}.0`；未冻结不许再自增"
    ]


def check_doc(path: pathlib.Path, frozen_dir: pathlib.Path | None = None) -> list[str]:
    try:
        rel = path.relative_to(ROOT).as_posix()
    except ValueError:  # 自检用临时文件，不在仓内
        rel = path.name
    lines = path.read_text(encoding="utf-8").split("\n")
    problems: list[str] = []

    version = header_version(lines)
    if version is None:
        problems.append(f"{rel}: 头部 {HEAD_SCAN_LINES} 行内读不出版本号（应为 `v1.0.NNN`）")
    else:
        three = VERSION_THREE.fullmatch(version)
        if not three:
            problems.append(
                f"{rel}: 版本号 `{version}` 不是三段式 —— 应写成 `v<冻结段>.<次>.<流水>`（例 `v1.0.430`）"
            )
        elif not (0 <= int(three.group(3)) <= ROLLOVER_AT):
            problems.append(
                f"{rel}: 第三段 `{three.group(3)}` 超出上限 {ROLLOVER_AT} —— 到 999 就不再自增，"
                f"冻结该段后活书转 `vA.(B+1).0`"
            )
        else:
            problems.extend(check_rollover(rel, path.stem, three, frozen_dir or FROZEN_DIR, path))

    for index, line in enumerate(lines, 1):
        if CHANGELOG_HEADING.match(line):
            problems.append(
                f"{rel}:{index} 出现「变更记录」节 —— 书里不许记变更历史（逐轮改了什么看 git 提交）"
            )
        elif CHANGELOG_REF.search(line):
            problems.append(
                f"{rel}:{index} 引用 `-变更记录.md` —— 该体系已废弃（版本号升在头部，历史看 git）"
            )
    return problems


def check_queue(path: pathlib.Path) -> list[str]:
    rel = path.relative_to(ROOT).as_posix()
    if not path.exists():
        return [f"{rel}: 待拍板队列文件不存在 ⇒ 不可判"]
    seen: dict[str, list[int]] = {}
    for index, line in enumerate(path.read_text(encoding="utf-8").split("\n"), 1):
        match = QUEUE_ID.match(line)
        if match:
            seen.setdefault(match.group(1), []).append(index)
    problems = []
    for token, places in sorted(seen.items(), key=lambda kv: int(kv[0])):
        if len(places) > 1:
            spots = ", ".join(f":{i}" for i in places)
            problems.append(f"{rel}{spots} 条目号 Q{token} 被 {len(places)} 条占用（取号 = max+1）")
    return problems


def run(quiet: bool = False) -> int:
    problems: list[str] = []
    files = targets()
    for path in files:
        problems.extend(check_doc(path))
    problems.extend(check_queue(DOCS / "项目管理规范.md"))

    if problems:
        print(f"❌ 版本纪律未通过（{len(problems)} 处 / 受检 {len(files)} 份）：")
        for item in problems:
            print(f"   · {item}")
        return 1
    if not quiet:
        print(f"✅ 版本纪律通过：{len(files)} 份书/单头部均为三段式 `vX.Y.NNN`（≤999），书内无变更记录节")
    return 0


def self_test() -> int:
    import tempfile

    cases = {
        "好": ("| 版本 | **v1.0.12**（2026-10-26 改动） |\n\n正文\n", True),
        "非三段": ("| 版本 | **v3.429**（2026-10-26） |\n\n正文\n", False),
        "超上限": ("| 版本 | **v1.0.1000** |\n\n正文\n", False),
        "带变更记录": ("| 版本 | **v1.0.3** |\n\n## 11. 变更记录\n\n| v | d |\n", False),
        "引旧文件": ("| 版本 | **v1.0.4** |\n\n见《X-变更记录.md》。\n", False),
    }
    ok = True
    with tempfile.TemporaryDirectory() as tmp:
        frozen = pathlib.Path(tmp) / "frozen"
        frozen.mkdir()
        rollover_cases = {
            # 999 且没有该段冻结件 ⇒ 红（到 999 必须冻结）
            "999未冻结": ("| 版本 | **v1.0.999** |\n\n正文\n", False),
            # 998 不受该规则约束
            "998": ("| 版本 | **v1.0.998** |\n\n正文\n", True),
        }
        cases.update(rollover_cases)
        # 补一例：999 且冻结件在 ⇒ 绿
        path999 = pathlib.Path(tmp) / "有件.md"
        path999.write_text("| 版本 | **v1.0.999** |\n\n正文\n", encoding="utf-8")
        (frozen / "有件-v1.0-20261101.md").write_bytes(path999.read_bytes())
        with_art = check_doc(path999, frozen_dir=frozen)
        mark = "✓" if not with_art else "✗"
        if with_art:
            ok = False
        print(f"  {mark} 样本「999已冻结」：{'绿' if not with_art else '红'}")

        for name, (body, should_pass) in cases.items():
            path = pathlib.Path(tmp) / f"{name}.md"
            path.write_text(body, encoding="utf-8")
            found = check_doc(path, frozen_dir=frozen)
            passed = not found
            mark = "✓" if passed == should_pass else "✗"
            if passed != should_pass:
                ok = False
            detail = "" if passed else f" ← {found[0][:70]}"
            print(f"  {mark} 样本「{name}」：{'绿' if passed else '红'}{detail}")
    total = len(cases) + 1          # + 「999已冻结」
    # 例数必须**自己报出来**并且是计数的（2026-11-02）：`Scripts/self-test-counts.json` 的
    # `countRegex` 读的是这一行 —— 2026-10-26 废止「变更记录」时 self_test 被整段重写，尾巴只剩
    # 一句「自检通过」，台账里那 28 例（旧版本累积值）从此没人对得上，而判据**看不见**这件事。
    print(f"负例 {total}/{total} 达到预期" if ok else f"负例 0/{total} 达到预期（有失败）")
    print("自检通过" if ok else "自检失败")
    return 0 if ok else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="书/单版本号纪律（三段式，历史交给 git）")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    return run(quiet=args.quiet)


if __name__ == "__main__":
    sys.exit(main())
