#!/usr/bin/env python3
"""书/单的版本号纪律（2026-10-26 人类主人令改判）。

新判据（旧「变更记录」体系整体废弃）：
  ① 每本书 / 每份单**头部必须有三段式版本号** `v<冻结段>.<次>.<流水>`，例 `v1.0.430`；
     第三段 = 自该冻结段起第几次改动，**上限 999**（满 999 就该冻结成 `v1.1`，活书转 `v1.1.NNN`）。
  ② **书里不许再有「变更记录」节**，也不许引用 `-变更记录.md` —— 逐轮改了什么由 git 提交历史承载
     （人类主人 2026-10-26：「每次推送都会有 Git 记录……不要把 Git 的修改记录放到活书里」）。
  ③ 待拍板队列的条目号（`Q<数字>`）在《项目管理规范》里唯一。

用法：`python3 Scripts/check-doc-versions.py`（exit 0 = 通过）；`--self-test` 跑成对自检。

判据自己的证据（10 例）：2026-11-10 按实跑登记 —— `--self-test` 里 9 个文件样本（好 / 非三段 / 超上限 /
带变更记录 / 引旧文件 / 999 未冻结 / 998 免检 / 跳段 / 降段）+ 1 个「999 已冻结 ⇒ 绿」，
另有 5 例步进样本（`步进 5/5`）；收尾自己报 `负例 N/N 达到预期`，由
`Scripts/self-test-counts.json` 的 `doc-versions` 族逐行对账（2026-11-02：这段被 2026-10-26 的整段
重写删掉了，台账里还留着旧版本的 28 例 —— 判据看不见「runner 不再报数」这类漂移，现补回）。
"""
# shared-surface：2026-11-10 红#6 收口 —— 两侧共用判据；本轮只把用法行的例数 8 → 10 与实跑对齐（锚点正则不动）
from __future__ import annotations

import json
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
    """首条「版本」行里的版本号（= 文件头的自称版本）。"""
    for line in lines[:HEAD_SCAN_LINES]:
        if "版本" not in line:
            continue
        match = VERSION_ANY.search(line)
        if match:
            return match.group(0)
    return None


def versions_all(lines: list[str]) -> list[str]:
    """文件头区所有「版本」行里出现的版本号（版本历史可能有多条）。"""
    found: list[str] = []
    for line in lines[:HEAD_SCAN_LINES]:
        if "版本" not in line:
            continue
        # 每条只取**第一个**版本号：版本身份是本行的首个版本，
        # 行内后出现的（如「派生自 macOS 详设 v1.0.22」）是引用，不是本文件的版本。
        match = VERSION_ANY.search(line)
        if match:
            found.append(match.group(0))
    return found


def max_version(versions: list[str]) -> str | None:
    def key(v: str) -> tuple[int, ...]:
        return tuple(int(x) for x in VERSION_THREE.fullmatch(v).groups())
    valid = [v for v in versions if VERSION_THREE.fullmatch(v)]
    return max(valid, key=key) if valid else None


def order_problem(lines: list[str]) -> str | None:
    """文件头第一条「版本」必须是最新号；插乱了就判红（否则步进判据会看错基准）。"""
    first, top = header_version(lines), max_version(versions_all(lines))
    if first and top and first != top:
        return f"版本历史乱序：首条写 {first}，最新是 {top}（最新的必须在最前）"
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



def previous_version(path: pathlib.Path) -> str | None:
    """读 HEAD 里同一份文件的版本号（不在 HEAD 里 = 新书，返回 None）。"""
    import subprocess
    try:
        rel = path.relative_to(ROOT).as_posix()
    except ValueError:
        return None
    out = subprocess.run(["git", "show", f"HEAD:{rel}"], cwd=ROOT,
                         capture_output=True, text=True)
    if out.returncode != 0:
        return None
    head_lines = out.stdout.split("\n")
    # 版本历史行可能被插乱：判「有没有前进」要用 HEAD 里的**最大号**，不是第一条
    return max_version(versions_all(head_lines)) or header_version(head_lines)



def is_segment_roll(old: str, new: str) -> bool:
    """是不是「冻结后升一段」的形状：vX.Y.NNN → vX.(Y+1).0。"""
    o, n = VERSION_THREE.fullmatch(old), VERSION_THREE.fullmatch(new)
    if not o or not n:
        return False
    om, on, _ = map(int, o.groups())
    nm, nn, nl = map(int, n.groups())
    return (nm, nn, nl) == (om, on + 1, 0)


def step_problem(old: str, new: str) -> str | None:
    """两段版本号之间是否违规（None = 合规）。纯函数，便于自检。"""
    o, n = VERSION_THREE.fullmatch(old), VERSION_THREE.fullmatch(new)
    if not o or not n:
        return None            # 格式问题由 check_doc 报
    om, on, ol = map(int, o.groups())
    nm, nn, nl = map(int, n.groups())
    if (om, on, ol) == (nm, nn, nl):
        return None            # 没升（同批次多次保存）
    if (nm, nn) == (om, on) and nl == ol + 1:
        return None            # 正常末位递增
    if (nm, nn) == (om, on + 1) and nl == 0 and ol == ROLLOVER_AT:
        return None            # 999 满段滚动（冻结件由 check_rollover 管）
    # 手动冻结升段（主人令 betaN ⟷ 冻结 v1.N 四书）：vX.Y.NNN → vX.(Y+1).0，
    # 证据 = 该段已有冻结件（在 check_step 里查盘，纯函数这里只放形状）。
    if (nm, nn, nl) == (om, on + 1, 0):
        return None
    # **主人拍板的回退**：段只升不降是常态纪律；但「撤回一条发布线」由主人定，
    # 登记在 Scripts/doc-version-rollbacks.json（每条带撤销提交、理由、目标段），登记过的降段放行。
    try:
        _p = pathlib.Path(__file__).resolve().parent / "doc-version-rollbacks.json"
        for _e in json.loads(_p.read_text(encoding="utf-8")).get("rollbacks", []):
            if _e.get("from_version") == f"v{om}.{on}.{ol}" and _e.get("to_version") == f"v{nm}.{nn}.{nl}":
                return None
    except Exception:
        pass
    return (f"版本跳跃 `v{om}.{on}.{ol}` → `v{nm}.{nn}.{nl}` —— 活书只许末位 +1"
            f"（到 {ROLLOVER_AT} 冻结后再转下一段），不跳段、不降段")


def check_step(path: pathlib.Path, current: str | None,
               frozen_dir: pathlib.Path | None = None) -> list[str]:
    """活书版本只许「不变」或「末位 +1」；滚动只许 999→下一段 .0。

    为什么加这条（2026-11-05 人类主人两次纠正）：Linux 详设从 v1.0.12 被我直接写成 v2.0.0，
    判据当时只检查「是不是三段式、≤999」，于是一路绿灯 —— 规则写在书里、写在规范里，
    却在真正动笔时没人拦。规矩靠记忆守不住，只能靠判据拦。
    """
    old = previous_version(path)
    if old is None or current is None:
        return []
    try:
        rel = path.relative_to(ROOT).as_posix()
    except ValueError:
        rel = path.name
    # 冻结升段（vX.Y.NNN → vX.(Y+1).0）必须有证据：该段的冻结件在盘上。
    # 没有冻结件就升段 = 跳段，照旧判红。
    if is_segment_roll(old, current):
        if path.name.startswith("Doyah产品开发计划任务清单"):
            return []      # 一单是活件（`check-end-sheets.py` 口径：不拍快照）⇒ 升段不需要冻结件
        seg = ".".join(current.split(".")[:2])          # v1.1
        if not frozen_baselines(frozen_dir or FROZEN_DIR, path.stem, seg):
            return [f"{rel}: 升段到 {seg} 但没有该段冻结件 —— 先跑 "
                    f"`python3 Scripts/freeze-books.py --version {seg}`，再改活书版本；"
                    f"没有冻结件的升段就是跳段"]
        return []
    return [f"{rel}: {msg}"] if (msg := step_problem(old, current)) else []

def check_doc(path: pathlib.Path, frozen_dir: pathlib.Path | None = None) -> list[str]:
    try:
        rel = path.relative_to(ROOT).as_posix()
    except ValueError:  # 自检用临时文件，不在仓内
        rel = path.name
    lines = path.read_text(encoding="utf-8").split("\n")
    problems: list[str] = []

    # 版本历史可能有多条（活书头部逐轮追加）：步进对比两侧一律取**最大号**，
    # 否则头部旧行排在前面时会把「没动过」误判成降段。
    version = max_version(versions_all(lines)) or header_version(lines)
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
            problems.extend(check_step(path, version, frozen_dir))
            disorder = order_problem(lines)
            if disorder:
                problems.append(f"{rel}: {disorder}")

    for index, line in enumerate(lines, 1):
        if CHANGELOG_HEADING.match(line):
            problems.append(
                f"{rel}:{index} 出现「变更记录」节 —— 书里不许记变更历史（逐轮改了什么看 git 提交）"
            )
        elif CHANGELOG_REF.search(line):
            problems.append(
                f"{rel}:{index} 引用 `-变更记录.md` —— 该体系已废弃（版本号升在头部，历史看 git）"
            )
    # 「文档版本：」行必须等于头部最新版本（2026-11-09 补：Linux 详设曾出现
    # 头 v1.3.0 / 文档版本 v1.2.1 / 仍引用已并入需求书的能力规划书 v1.0.266 —— 三个号互不相干）
    # 只认元信息行（`- 文档版本：vX` 或表行 `| 文档版本 | vX |`），不认正文里提到「文档版本：」的条文
    row = next((ln for ln in lines if re.match(r"^(?:- |\|\s*)文档版本[：:]", ln.strip())), None)
    if row is not None and version is not None:
        found = re.search(r"文档版本：\*{0,2}(v\d+\.\d+\.\d+)", row)
        if found is None:
            problems.append(f"{rel}: 「文档版本」行读不出三段式版本号")
        elif found.group(1) != version:
            problems.append(
                f"{rel}: 「文档版本：{found.group(1)}」与头部最新版本 {version} 不一致 "
                f"—— 正文改动必须同步这一行（判据：本脚本）"
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
        # 文档版本行与头部一致 ⇒ 绿；不一致 ⇒ 红（Linux 详设那次事故的负例）
        "文版行一致": ("| 版本 | **v1.0.6** |\n\n- 文档版本：v1.0.6（正文改动同步）\n", True),
        "文版行漂移": ("| 版本 | **v1.0.6** |\n\n- 文档版本：v1.0.5（忘了改）\n", False),
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
        # 版本步进规则（2026-11-05 加）：活书只许末位 +1，跳段 / 降段必红。
        # 为什么单列一组：这组不依赖临时文件，只测纯函数 step_problem —— 它守的是
        # 「Linux 详设从 v1.0.12 被我写成 v2.0.0、而当时判据全绿」那次真实踩坑。
        step_cases = [
            ("v1.0.12", "v1.0.13", False, "正常末位递增"),
            ("v1.0.12", "v2.0.0", True, "跳主版本（真实踩坑）"),
            ("v1.0.12", "v1.0.12", False, "同批次未升"),
            ("v1.0.999", "v1.1.0", False, "999 满段滚动"),
            ("v1.0.13", "v1.0.11", True, "降段"),
        ]
        step_ok = 0
        for old, new, should_red, why in step_cases:
            red = step_problem(old, new) is not None
            good = red == should_red
            step_ok += 1 if good else 0
            if not good:
                ok = False
            print(f"  {'✓' if good else '✗'} 步进 {old} → {new}（{why}）⇒ {'红' if red else '绿'}，应为 {'红' if should_red else '绿'}")
        print(f"步进 {step_ok}/{len(step_cases)} 达到预期")

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
