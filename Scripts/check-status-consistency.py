#!/usr/bin/env python3
"""校验 §10.1 索引表的状态列与正文定义行的状态列一致。

为什么需要这个门禁：`Scripts/report-requirements.py` 的盘点**读的是索引表**，
而每轮开发改的是**正文定义行**。两边一旦漂移，盘点就会给出错误结论 ——
本轮就发生过：定义行已改成 ✅，索引行还写着 🟡，于是"完成度"看起来没动。
手抄状态必然漂移，所以这里用脚本钉住。

2026-10-14 修（合册 T-20261013-027 · 原单 T-20261010-032 · 第 400 轮判据面缺口样本 37）：
    ① **扫描面对齐姊妹判据**：跨文档状态括注原先只盖 `Docs/*.md` + `Docs/design/*.md`
       （38 份，去掉 SPEC = 37），而姊妹判据 `check-doc-tables.py` 判据 E / `check-doc-versions.py`
       都按 `Docs/**/*.md`（+ 仓根）取面 —— 于是 `Docs/proposals/` / `Docs/archive/` /
       `Docs/design/` 再深一层 / **仓根 6 件**（`AGENT-SPEC.md` / `README*.md` /
       `RELEASE-*.md` / `THIRD-PARTY-NOTICES.md`）整体在面外：真仓成对实测，同一份
       「状态写错」的文档放在 `Docs/design/` 判红、放在 `Docs/proposals/` **静默放过**。
       现面 = `FACE_GLOBS`（与姊妹判据同形），点名改**仓根相对真路径**（`README.md`）。
    ② **空跑防护**：面内份数低于 `FACE_FLOOR` ⇒ 判红（旧版把面移到空目录也照打 ✅）；
       打印「面内 N 份文档 / 命中 M 处引用」两个读数。**只有份数有下限**：命中数是
       「有人恰好引用了带状态的编号」的产物，会随文档改写合法地归零（那不是覆盖面）。
    ③ `--root <树>` / `--face-floor <N>`（夹具与其它仓用）/ `--self-test`；未知参数按
       argparse 报错（rc=2）—— 旧版根本没有参数面，`--self-test` / `--nonsense` 都静默
       吞掉并打印 ✅ rc=0。
    ④ **边界登记（不改形状）**：`CROSS_DOC_PATTERN` 只认「编号**紧贴**括号 + 括注里只有
       一枚状态符」。**编号与括号之间夹字**（`FR-AI-11 的状态（⬜）`）与**括注里带说明**
       （`FR-AI-11（🟡 待验证）`）**不在本判据范围** —— 放宽会把路线图表里「alpha 不含 ⬜」
       这类语义当状态括注误判（实测规划书 §7 六行），故按原单口径**只改面、不改形状**
       （此处登记，不许继续无声）。
    ⑤ §10.1 索引解析与正文定义行解析的口径**逐字未动**（本轮只动扫描面 + 读数 + 防护）。

判据自己的证据：`--self-test` **12 例**（一律在临时夹具树上写坏，真仓零改动）。

用法：
    python3 Scripts/check-status-consistency.py                     # 校验（闸门）
    python3 Scripts/check-status-consistency.py --self-test          # 判据自己的证据
    python3 Scripts/check-status-consistency.py --root <树>           # 指定仓根（自检用）

退出码：0 = 通过；1 = 判红；2 = 用法错（argparse）。
"""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

# 判据的立足点：**本脚本所在仓**的根（不是 CWD —— 从别的目录跑必须读数一致）
REPO = pathlib.Path(__file__).resolve().parent.parent
SPEC_REL = "Docs/Doyah产品需求说明书.md"
STATUSES = "✅🟡⬜➖"
# 其它文档里「FR-XXX-01（🟡）」这种状态括注，与 §10.1 索引比对（见 cross_document_problems）
CROSS_DOC_PATTERN = re.compile(r"((?:FR|NFR)-[A-Z]+-\d+)[（(]([✅🟡⬜➖])[）)]")
# 跨文档状态括注的扫描面：与姊妹判据同形（check-doc-tables.py 判据 E / check-doc-versions.py）
FACE_GLOBS = ("*.md", "Docs/**/*.md")
# 面内文档数下限（空跑防护）：本仓 2026-10-14 实测 42 份（不含 SPEC）⇒ 只许涨不许跌
FACE_FLOOR = 42


def section(lines: list[str], start_marker: str, end_marker: str) -> list[str]:
    start = next(i for i, l in enumerate(lines) if l.startswith(start_marker))
    end = next(i for i, l in enumerate(lines) if i > start and l.startswith(end_marker))
    return lines[start:end]


def face_files(root: pathlib.Path) -> list[pathlib.Path]:
    """跨文档状态括注的扫描面：仓根 `*.md` + `Docs/**/*.md`（递归、去重、正斜杠排序）。"""
    found = {p for glob in FACE_GLOBS for p in root.glob(glob) if p.is_file()}
    return sorted(found, key=lambda p: p.as_posix())


def parse_index(lines: list[str]) -> dict[str, tuple[str, int]]:
    """§10.1 索引表：| ID | 域 | 优先级 | 状态 |（口径与旧版逐字一致）。"""
    index: dict[str, tuple[str, int]] = {}
    for offset, line in enumerate(section(lines, "### 10.1", "### 10.2")):
        fields = [f.strip() for f in line.strip().strip("|").split("|")]
        if len(fields) != 4 or not re.fullmatch(r"(FR|NFR|AC)-[A-Z]+-\d+", fields[0]):
            continue
        # 与正文一致：状态按**首字符**判定，允许 `🟡（待验证）` 这类带括号的写法。
        if not fields[3] or fields[3][0] not in STATUSES:
            continue
        index[fields[0]] = (fields[3][0], offset)
    return index


def parse_defined(lines: list[str]) -> dict[str, tuple[str, int]]:
    """正文定义行（**只扫 §1~§9 的正文，不扫 §10 附录**；口径与旧版逐字一致）。

    FR 行 6 列：| ID | 描述 | 优先级 | 复杂度 | 状态 | 证据 |
    NFR 行 5 列：| ID | 描述 | 优先级 | 状态 | 证据 |   （NFR 没有"复杂度"）
    因此状态位置不固定：从第 4 列起找**第一个以状态符号开头**的列。
    """
    body_end = next((i for i, l in enumerate(lines) if l.startswith("## 10.")), len(lines))
    defined: dict[str, tuple[str, int]] = {}
    for number, line in enumerate(lines[:body_end], start=1):
        fields = [f.strip() for f in line.strip().strip("|").split("|")]
        if len(fields) < 5 or not re.fullmatch(r"(FR|NFR)-[A-Z]+-\d+", fields[0]):
            continue
        status = next((f for f in fields[3:6] if f and f[0] in STATUSES), None)
        if status is None:
            continue
        defined[fields[0]] = (status[0], number)
    return defined


def cross_document_problems(root: pathlib.Path, index: dict[str, tuple[str, int]],
                            face_floor: int = FACE_FLOOR) -> list[str]:
    """非本文件的文档里写「编号（状态标记）」时，必须与 §10.1 索引一致。

    为什么补这条：状态是单一事实来源（§10.1 索引），本文件的正文定义行已有门禁钉住，
    但其它文档（规划书 / 发布方案 / 设计说明…）会**随手括注一个旧状态** —— 2026-09-26
    实测抓到两处（规划书 §4.2 里 FR-AI-03 / FR-AI-11 仍写 ⬜，而 SRS 早已是 🟡），
    这类括注会让人以为"还没做"。要引用**历史**状态时改写措辞（例如「曾是 ⬜」而不要
    写成 `（⬜）`），否则本门禁会拦。

    面（2026-10-14 修 · 原单 `T-20261010-032`）：`FACE_GLOBS` = `*.md` + `Docs/**/*.md`，
    与姊妹判据同形；`SPEC_REL` 本身不参与比对（它是真值源）。面内份数低于 `face_floor`
    ⇒ 判红（空跑防护 —— 旧版面搬到空目录也照打印 ✅）。
    """
    problems: list[str] = []
    spec = (root / SPEC_REL).resolve()
    targets = [p for p in face_files(root) if p.resolve() != spec]
    scanned = 0
    for path in targets:
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            for identifier, mark in CROSS_DOC_PATTERN.findall(line):
                expected = index.get(identifier)
                if expected is None:
                    continue
                scanned += 1
                if expected[0] != mark:
                    problems.append(
                        f"{path.relative_to(root).as_posix()}:{number}: {identifier} 括注 {mark}，"
                        f"而 §10.1 索引为 {expected[0]}"
                    )
    print(f"（跨文档状态括注：面内 {len(targets)} 份文档 / 命中 {scanned} 处引用）")
    if len(targets) < face_floor:
        problems.append(
            f"跨文档状态括注的扫描面只剩 {len(targets)} 份文档（下限 {face_floor}）"
            f" —— 面被削窄 / 目录缺失，空跑不许当通过"
        )
    return problems


def run(root: pathlib.Path, face_floor: int = FACE_FLOOR) -> int:
    spec = root / SPEC_REL
    if not spec.is_file():
        print(f"❌ 找不到需求规范书：{SPEC_REL}（仓根 {root}）")
        return 1
    lines = spec.read_text(encoding="utf-8").split("\n")
    index = parse_index(lines)
    defined = parse_defined(lines)

    problems: list[str] = []
    for ident, (status, line_number) in sorted(defined.items()):
        if ident not in index:
            problems.append(f"定义行 {ident}（第 {line_number} 行）在 §10.1 索引表里找不到")
            continue
        index_status = index[ident][0]
        # 允许索引记"主状态"、定义行带括号补充：🟡（UI 已接，待人工验证）算 🟡。
        if index_status != status[0]:
            problems.append(
                f"{ident}: 定义行（第 {line_number} 行）为 {status}，"
                f"而 §10.1 索引表为 {index_status}"
            )

    # AC（验收标准）的正文在 §5，用的是另一种表格式，不在这里比对；
    # 只对 FR / NFR 要求"索引表里每一条都能找到定义行"。
    missing = [
        ident for ident in index
        if ident not in defined and ident.split("-")[0] in ("FR", "NFR")
    ]
    if missing:
        problems.append(f"索引表里有 {len(missing)} 条 FR/NFR 在正文找不到定义行：{', '.join(sorted(missing)[:5])}…")

    problems.extend(cross_document_problems(root, index, face_floor))

    if problems:
        print(f"❌ 状态一致性校验失败（{len(problems)} 处）：")
        for item in problems:
            print(f"   {item}")
        print("\n提示：改需求状态时要**同时**改正文定义行与 §10.1 索引表（盘点读的是索引表）；"
              "其它文档里的状态括注也要跟着改。")
        return 1

    print(f"✅ 状态一致性校验通过（索引表 {len(index)} 条 / 正文定义行 {len(defined)} 条，状态一致）")
    return 0


FIXTURE_SPEC = """# 需求规范书（夹具）

## 1. 正文

| ID | 描述 | 优先级 | 复杂度 | 状态 | 证据 |
|---|---|---|---|---|---|
| FR-AI-11 | 夹具条目 | P0 | 低 | 🟡 | - |

## 10. 附录

### 10.1 索引

| ID | 域 | 优先级 | 状态 |
|---|---|---|---|
| FR-AI-11 | AI | P0 | 🟡 |

### 10.2 其它
"""


OLD_CODE_MARKER = "FACE_FLOOR"


def _old_code_text() -> "str | None":
    """取"上一版"判据源码：从历史里找第一份**不含本轮新标记**的版本。

    原先这里写的是 `git show HEAD^:…` —— 那在**下一笔提交**（任何一笔，包括别人的）之后
    就会指到已经改好的版本 ⇒ 这个"旧码对照臂"自己变成假红（实测：HEAD^ 含新版时 12 例里
    例 5 判红）。按内容认版本才跟着历史走。
    """
    listed = subprocess.run(["git", "log", "--format=%H", "-n", "8", "--",
                             "Scripts/check-status-consistency.py"], cwd=str(REPO),
                            capture_output=True, text=True)
    if listed.returncode != 0:
        return None
    for sha in listed.stdout.split():
        shown = subprocess.run(["git", "show", f"{sha}:Scripts/check-status-consistency.py"],
                               cwd=str(REPO), capture_output=True, text=True)
        if shown.returncode == 0 and OLD_CODE_MARKER not in shown.stdout:
            return shown.stdout
    return None


def run_self_test() -> int:
    """判据自己的证据：夹具树上一律真跑，真仓零改动、末例核对逐字节未变。"""
    script = pathlib.Path(__file__).resolve()
    before = hashlib.sha256(script.read_bytes()).hexdigest()
    scratch = pathlib.Path(tempfile.mkdtemp(prefix="csc-selftest-"))
    total = 0
    failures: list[str] = []

    def invoke(where, extra=(), cwd=None):
        command = [sys.executable, str(script)]
        if where is not None:
            command += ["--root", str(where)]
        command += list(extra)
        completed = subprocess.run(command, cwd=str(cwd or scratch), capture_output=True, text=True)
        return completed.returncode, completed.stdout + completed.stderr

    def fixture(name: str) -> pathlib.Path:
        where = scratch / name
        for sub in ("Docs/design", "Docs/proposals", "Docs/archive", "Scripts"):
            (where / sub).mkdir(parents=True, exist_ok=True)
        (where / SPEC_REL).write_text(FIXTURE_SPEC, encoding="utf-8")
        return where

    def write(where: pathlib.Path, rel: str, text: str) -> None:
        target = where / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")

    def red(where, extra=(), needle=""):
        code, output = invoke(where, extra)
        if code == 0:
            return f"仍 rc=0（该判红）\\n{output[-300:]}"
        if needle and needle not in output:
            return f"判红了但没点名 {needle!r}\\n{output[-300:]}"
        return None

    def green(where, extra=()):
        code, output = invoke(where, extra)
        if code != 0:
            return f"该绿却判红（rc={code}）\\n{output[-400:]}"
        return None

    def case(description: str, check) -> None:
        nonlocal total
        total += 1
        problem = check()
        if problem:
            failures.append(f"例 {total} 失败：{description} —— {problem}")

    # 例 1：真仓正例 —— rc=0 + 打印两个读数（面内份数 / 命中处数）
    def check_positive():
        code, output = invoke(None)
        if code != 0:
            return f"真仓实跑不是绿（rc={code}）\\n{output[-400:]}"
        if "面内" not in output or "命中" not in output:
            return f"没打扫描面读数\\n{output[-300:]}"
        return None
    case("真仓正例：rc=0 + 打印「面内 N 份文档 / 命中 M 处引用」", check_positive)

    # 例 2：负例（新的面）—— Docs/proposals/ 里的错括注必须判红并点名
    def check_proposals():
        where = fixture("proposals")
        write(where, "Docs/proposals/planted.md", "正文\n\nFR-AI-11（⬜）还没做\n")
        return red(where, ("--face-floor", "1"), "Docs/proposals/planted.md:3")
    case("Docs/proposals/ 里 `FR-AI-11（⬜）` ⇒ 判红并点名真路径（旧版 rc=0）", check_proposals)

    # 例 3：旧面本就覆盖到的位置照旧判红（回归不许丢）
    def check_design():
        where = fixture("design")
        write(where, "Docs/design/planted.md", "正文\n\nFR-AI-11（⬜）还没做\n")
        return red(where, ("--face-floor", "1"), "Docs/design/planted.md:3")
    case("Docs/design/ 里的同一负例 ⇒ 照旧判红（旧面内的位置回归）", check_design)

    # 例 4：承重臂 —— 仓根件（旧版整体在面外）现判红，且点名字面是仓根相对真路径
    def check_root_doc():
        where = fixture("root-doc")
        write(where, "README.md", "正文\n\nFR-AI-11（⬜）还没做\n")
        problem = red(where, ("--face-floor", "1"), "README.md:3")
        if problem:
            return problem
        code, output = invoke(where, ("--face-floor", "1"))
        if "Docs/Docs" in output:
            return "点名串不是仓根相对路径（出现 Docs/Docs）"
        return None
    case("仓根 `README.md` 里的同一负例 ⇒ 判红且点名 `README.md:3`（旧版 rc=0）", check_root_doc)

    # 例 5：旧码对照 —— 同一夹具（负例在 Docs/proposals/）旧码 rc=0（假绿现场）
    def check_old_code():
        where = fixture("old-code")
        write(where, "Docs/proposals/planted.md", "正文\n\nFR-AI-11（⬜）还没做\n")
        text = _old_code_text()
        if text is None:
            return "取不到旧码（git 历史里没有不含本轮标记的版本）"
        (where / "Scripts" / "check-status-consistency.py").write_text(text, encoding="utf-8")
        completed = subprocess.run([sys.executable, str(where / "Scripts" / "check-status-consistency.py")],
                                   cwd=str(where), capture_output=True, text=True)
        if completed.returncode != 0:
            return f"旧码不是假绿（rc={completed.returncode}）——对照臂不成立"
        return None
    case("旧码对照：同一负例（面外位置）旧码 rc=0（假绿现场）", check_old_code)

    # 例 6：负对照 —— archive / 第三方件里没有该形状 ⇒ 不许地毯式判红
    def check_negative_control():
        where = fixture("negative")
        write(where, "Docs/archive/z.md", "历史快照\n\nFR-AI-11 已实现（无括注）\n")
        write(where, "Docs/design/store/q.md", "目录说明\n")
        write(where, "THIRD-PARTY-NOTICES.md", "第三方许可\n")
        write(where, "README.en.md", "English readme\n")
        return green(where, ("--face-floor", "4"))
    case("负对照：archive / 仓根其它件内不含该形状 ⇒ rc=0（不地毯式判红）", check_negative_control)

    # 例 7：空跑防护 —— 面低于下限 ⇒ 判红（旧版把面移到空目录照打 ✅）
    def check_floor_red():
        where = fixture("floor-red")
        write(where, "README.md", "正文\n")
        write(where, "Docs/proposals/p.md", "正文\n")
        return red(where, ("--face-floor", "5"), "扫描面只剩 2 份文档")
    case("空跑防护：面内 2 份 < 下限 5 ⇒ 判红并点名下限量", check_floor_red)

    # 例 8：面恰好等于下限 ⇒ 绿（棘轮不许误伤）
    def check_floor_equal():
        where = fixture("floor-equal")
        write(where, "README.md", "正文\n")
        write(where, "Docs/proposals/p.md", "正文\n")
        return green(where, ("--face-floor", "2"))
    case("面内份数恰好等于下限 ⇒ rc=0（不误伤）", check_floor_equal)

    # 例 9：真值源自身不参与比对 —— SPEC 里写旧括注不算（旧口径逐字保留）
    def check_spec_excluded():
        where = fixture("spec-excluded")
        (where / SPEC_REL).write_text(FIXTURE_SPEC + "\n引用：FR-AI-11（⬜）\n", encoding="utf-8")
        write(where, "Docs/proposals/p.md", "正文\n")
        return green(where, ("--face-floor", "1"))
    case("SPEC 自身不参与跨文档比对（真值源）⇒ rc=0", check_spec_excluded)

    # 例 10：未知参数按 argparse 报错（旧版静默吞掉并 rc=0）
    def check_unknown_arg():
        where = fixture("unknown-arg")
        code, _ = invoke(where, ("--nonsense",))
        if code != 2:
            return f"未知参数没有 rc=2（rc={code}）"
        return None
    case("未知参数 ⇒ rc=2（旧版静默吞掉、rc=0）", check_unknown_arg)

    # 例 11：不给 `--face-floor` 时用默认下限（本仓实测值）⇒ 夹具小面判红
    def check_default_floor():
        where = fixture("default-floor")
        write(where, "README.md", "正文\n")
        return red(where, (), "下限")
    case("不带 `--face-floor` 用默认下限 ⇒ 小面判红（默认值不是摆设）", check_default_floor)

    # 例 12：真仓逐字节未变 + 真仓实跑 rc=0
    def check_repository_untouched():
        if hashlib.sha256(script.read_bytes()).hexdigest() != before:
            return "自检改动了真仓库的脚本"
        code, output = invoke(None)
        if code != 0:
            return f"真仓实跑不是绿（rc={code}）"
        return None
    case("真仓逐字节未变 + 真仓实跑 rc=0", check_repository_untouched)

    shutil.rmtree(scratch, ignore_errors=True)
    for failure in failures:
        print(f"   ❌ {failure}")
    print(f"判据自检：{total} 条中 {total - len(failures)} 条达到预期")
    return 0 if not failures else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="状态一致性校验（Scripts/check-status-consistency.py）")
    parser.add_argument("--root", default=None, help="仓根（默认 = 本脚本所在仓）")
    parser.add_argument("--face-floor", type=int, default=None, help="面内文档数下限（默认 = 本仓实测值）")
    parser.add_argument("--self-test", action="store_true", help="判据自己的证据（临时夹具树上写坏）")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if args.self_test:
        return run_self_test()
    root = pathlib.Path(args.root).expanduser().resolve() if args.root else REPO
    floor = FACE_FLOOR if args.face_floor is None else args.face_floor
    return run(root, floor)


if __name__ == "__main__":
    raise SystemExit(main())
