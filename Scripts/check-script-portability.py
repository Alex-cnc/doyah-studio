#!/usr/bin/env python3
"""跨平台可移植性：脚本里不许把「平台相关的路径串」当稳定标识用（闭环第 2 项，项数仍十八）。

## 为什么要它（提案 0005 采纳，开发循环第 91 轮）

`Scripts/*.py` 是**两侧都在跑**的判据（Windows 侧 `platform/windows/Tools/verify-all.ps1` 第 ③ 项就是
`python Scripts/check-doc-tables.py` + `python Scripts/check-doc-versions.py`），而它们内部
把「相对路径」铸成字符串去和**手抄的清单**比对时，用的是 `str(path.relative_to(root))`：

- macOS 上 `str(PosixPath)` 给 `Docs/README.md` —— 清单里正是这么写的，**看不出问题**；
- Windows 上 `str(WindowsPath)` 给 `Docs\\README.md` —— 清单里是正斜杠 ⇒ **集合匹配恒 False**，
  凡命中扫描面的文档**全部判红**，而且只红在「清单匹配」这一步（A/B/C 三档都过）。

对侧 2026-09-29 第 81 轮实测（`windows/Tools/verify-all.ps1`：14 项中跑 13 / 失败 1）：
`check-doc-versions.py` 报 6 份文档「有『变更记录』节却不在受检清单里」、
`check-doc-tables.py` 报 26 处「有表格却不在受检清单里」—— 两份文档**明明在清单里、也确实被查了**。
本侧同类还有第三处（本轮扫出来的）：`check-doc-numbers.py` 的「有判据、没闭环」对账把
`rel` 与 `verify-all.sh` 的正文、台账 `exempt` 的键比对 —— 同样是这个形状。

**两条判据都是对侧在 macOS 上写并验的**，所以这个洞在**写它的那台机器上永远不红**
（`--self-test` 也在 macOS 上跑）—— 这正是本判据存在的理由：
**「只在其中一个平台上才红」的缺陷，必须有跨平台的机械判据去看守。**

## 判据

- **A 形状禁令**：`Scripts/*.py` 的**代码行**（剥注释与字符串字面量后）不许出现
  `str(<…>.relative_to(<…>))` —— 逐处点名 `文件:行号`。正确写法 = `.as_posix()`：
  macOS 上逐字节不变，Windows 上把反斜杠归一成正斜杠（清单、台账键、glob、`verify-all.sh`
  正文都是正斜杠）。
- **B 例外台账**：`Scripts/script-portability-exemptions.json` —— 默认**空**；有例外时每条必须
  写 `file` / `pattern` / `reason`，**必须真的命中**（陈旧豁免判红）、理由不许空。
- **C 空跑防护**：扫描面文件数 / 代码行数 / 三个已知受检脚本必须在面内，三条下限。
- **D 判据自己的证据**：`--self-test`（**8 例**）在临时副本上写坏 ⇒ 判红、还原 ⇒ 绿，
  末例核对真仓库逐字节未变。

## 边界（如实登记）

- 只管**这一种形状**（`str(…relative_to(…))`）。`os.sep` / 手写 `"\\\\"` 拼接等同族写法**不在本判据范围**，
  本轮实测仓内 0 处（`grep` 见开发记录第九十五节）。
- 只管 `Scripts/*.py`（不含子目录、不含 `.sh`）：`Scripts/**/*.sh` 是 macOS 侧入口，
  另一平台跑的是 PowerShell 等价物（`Docs/概要设计.md` §8.3.1 ③）。
- 判的是**标识稳定性**，不是「不许用 `str(Path)`」—— 拼给自己看的显示文案不受限。

用法：
    python3 Scripts/check-script-portability.py            # 默认扫本仓 Scripts/
    python3 Scripts/check-script-portability.py --root DIR # 扫 DIR/Scripts（自检用）
    python3 Scripts/check-script-portability.py --self-test
"""

from __future__ import annotations

import hashlib
import io
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import tokenize

REPO = pathlib.Path(__file__).resolve().parent.parent
LEDGER = pathlib.Path("Scripts/script-portability-exemptions.json")

# 形状：`str(<…>.relative_to(<…>))` —— 括号里不许再有括号（本轮实测 13 处全是这个形状）。
BANNED = re.compile(r"\bstr\s*\(\s*[^()]*\.relative_to\s*\(")
ADVICE = "改用 `….relative_to(…)`.as_posix()`（macOS 上逐字节不变，Windows 上归一成正斜杠）"

# 空跑防护下限（本轮实测：61 个脚本 / 约 2 万代码行，取下限留余量）。
FLOOR_FILES = 55
FLOOR_CODE_LINES = 12000
# 这三个脚本是「清单比对点」，必须真的在扫描面里（判据的立足点）。
REQUIRED_SCOPE = (
    "check-doc-versions.py",
    "check-doc-tables.py",
    "check-doc-numbers.py",
)


def code_lines(text: str) -> dict[int, str] | None:
    """返回「行号 → 剥掉字符串字面量与注释后的该行内容」。

    为什么要剥：本判据的说明文字、例外台账的 `pattern`、其它脚本里提到这个形状的注释，
    都不该被当成一次真命中（同族口径见 `Scripts/check-panel-root-frames.py`）。
    用 `tokenize` 而不是手写扫描器：三引号 / 转义 / f-string 的边界它替我们判。
    词法坏掉的脚本返回 None（调用方如实报出来，不静默跳过）。
    """
    try:
        tokens = list(tokenize.generate_tokens(io.StringIO(text).readline))
    except (tokenize.TokenError, SyntaxError, IndentationError):
        return None

    lines = text.splitlines(keepends=True)
    offsets = [0]
    for line in lines:
        offsets.append(offsets[-1] + len(line))

    def absolute(row: int, column: int) -> int:
        return offsets[row - 1] + column if 1 <= row <= len(lines) + 1 else offsets[-1]

    characters = list(text)
    for token in tokens:
        if token.type not in (tokenize.STRING, tokenize.COMMENT):
            continue
        start = absolute(*token.start)
        end = absolute(*token.end)
        for index in range(start, min(end, len(characters))):
            if characters[index] != "\n":
                characters[index] = " "

    result: dict[int, str] = {}
    for number, line in enumerate("".join(characters).splitlines(), 1):
        result[number] = line
    return result


def scandals(root: pathlib.Path) -> tuple[list[str], list[str], dict]:
    """返回（红线, 说明/异常, 统计）。"""
    problems: list[str] = []
    notes: list[str] = []
    scripts_dir = root / "Scripts"
    files = sorted(scripts_dir.glob("*.py"))
    stats = {"files": len(files), "codeLines": 0, "unlexable": []}

    names = {path.name for path in files}
    for required in REQUIRED_SCOPE:
        if required not in names:
            problems.append(
                f"{required} 不在扫描面里（`Scripts/*.py`）—— 本判据的立足点是这三个「清单比对点」，"
                f"少了它就没在判这件事"
            )

    for path in files:
        text = path.read_text(encoding="utf-8")
        stripped = code_lines(text)
        if stripped is None:
            stats["unlexable"].append(path.name)
            notes.append(f"⚠️  {path.name} 词法分析失败（语法错误？）—— 本文件未被判过，不是「已通过」")
            continue
        stats["codeLines"] += sum(1 for line in stripped.values() if line.strip())
        for number, line in stripped.items():
            if BANNED.search(line):
                problems.append(
                    f"{path.relative_to(root).as_posix()}:{number}: {line.strip()[:90]}\n"
                    f"      ⇒ 平台相关的路径串被当成标识用 —— {ADVICE}"
                )
    return problems, notes, stats


def exemption_problems(
    root: pathlib.Path, hits: list[tuple[str, int]]
) -> tuple[list[str], list[str], set[tuple[str, int]]]:
    """B 例外台账：默认空；有例外必须逐条登记理由，且**必须真的命中**（陈旧判红）。

    返回（问题, 说明, 被豁免的命中点）—— 被豁免的命中点由 `run()` 从红线里摘出去。
    """
    problems: list[str] = []
    notes: list[str] = []
    exempted: set[tuple[str, int]] = set()
    path = root / LEDGER
    if not path.exists():
        problems.append(f"{LEDGER} 不在盘上（口径必须显式声明：没有例外就写一个空清单 + 理由）")
        return problems, notes, exempted
    try:
        ledger = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        problems.append(f"{LEDGER} 解析失败：{error}")
        return problems, notes, exempted
    entries = ledger.get("exemptions")
    if not isinstance(entries, list):
        problems.append(f"{LEDGER} 的 `exemptions` 必须是数组（没有例外就写 `[]`，`null` 不是「没有」）")
        return problems, notes, exempted
    if not entries:
        notes.append("例外 0 条（口径：这个形状一个都不许有 —— 空清单是**声明**，不是默认值）")
        return problems, notes, exempted

    for index, entry in enumerate(entries, 1):
        if not isinstance(entry, dict):
            problems.append(f"{LEDGER} 第 {index} 条不是对象")
            continue
        name = str(entry.get("file", ""))
        pattern = str(entry.get("pattern", ""))
        reason = str(entry.get("reason", "")).strip()
        if not name or not pattern:
            problems.append(f"{LEDGER} 第 {index} 条缺 `file` / `pattern`")
            continue
        if not reason:
            problems.append(f"{LEDGER} 第 {index} 条（{name}）没写理由 —— 例外要给出「为什么不能用 as_posix」")
            continue
        matched = [(file, line) for file, line in hits if file == name]
        if not matched:
            problems.append(
                f"{LEDGER} 第 {index} 条（{name} / {pattern}）是**陈旧豁免**：盘上这一处已经不在红线里了，销掉它"
            )
            continue
        exempted.update(matched)
        notes.append(f"例外命中：{name} —— {reason}")
    notes.append(f"例外 {len(entries)} 条（命中 {len(exempted)} 处）")
    return problems, notes, exempted


def run(root: pathlib.Path) -> int:
    problems, notes, stats = scandals(root)
    locations: list[tuple[str, int] | None] = []
    for entry in problems:
        match = re.match(r"^(Scripts/[^:]+):(\d+):", entry)
        locations.append((match.group(1), int(match.group(2))) if match else None)

    exempt_problems, exempt_notes, exempted = exemption_problems(
        root, [location for location in locations if location]
    )
    kept: list[str] = []
    for entry, location in zip(problems, locations):
        if location is not None and location in exempted:
            continue
        kept.append(entry)
    problems = kept
    hits = [location for location in locations if location and location not in exempted]
    problems.extend(exempt_problems)
    notes.extend(exempt_notes)

    # C 空跑防护
    if stats["files"] < FLOOR_FILES:
        problems.append(f"扫描面只有 {stats['files']} 个 .py（下限 {FLOOR_FILES}）—— 空跑防护")
    if stats["codeLines"] < FLOOR_CODE_LINES:
        problems.append(f"扫描面的代码行只有 {stats['codeLines']}（下限 {FLOOR_CODE_LINES}）—— 空跑防护")

    for note in notes:
        print(note)
    print(
        f"ℹ️  扫描面：{stats['files']} 个脚本 / {stats['codeLines']} 代码行；"
        f"形状红线命中 {len(hits)} 处；受检立足点 {'/'.join(REQUIRED_SCOPE)} 在面内"
    )
    if problems:
        print(f"❌ 跨平台可移植性校验失败（{len(problems)} 处）：")
        for entry in problems:
            print(f"   {entry}")
        return 1
    print("✅ 脚本可跨平台：没有把平台相关的路径串当标识用（`Scripts/*.py` 全部）.as_posix()`")
    return 0


def run_self_test() -> int:
    """判据自己的证据（8 例）：一律在临时副本上写坏，末例核对真仓库逐字节未变。"""
    failures: list[str] = []
    total = 0
    scratch = pathlib.Path(tempfile.mkdtemp(prefix="doyah-script-portability-"))
    repository = pathlib.Path(__file__).resolve().parent.parent
    before = {
        path.relative_to(repository).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted((repository / "Scripts").glob("*.py"))
    }

    def run_at(where: pathlib.Path) -> tuple[int, str]:
        completed = subprocess.run(
            [sys.executable, str(repository / "Scripts/check-script-portability.py"), "--root", str(where)],
            cwd=str(where),
            capture_output=True,
            text=True,
        )
        return completed.returncode, completed.stdout + completed.stderr

    def case(description: str, check) -> None:
        nonlocal total
        total += 1
        problem = check()
        if problem:
            failures.append(f"例 {total} 失败：{description} —— {problem}")

    try:
        clone = scratch / "clone"
        shutil.copytree(repository / "Scripts", clone / "Scripts")

        # 例 1：干净副本 ⇒ exit 0
        case("干净副本应 exit 0", lambda: None if run_at(clone)[0] == 0 else f"rc={run_at(clone)[0]}")

        # 例 2：写坏一处（`as_posix()` 退回 `str(...)`）⇒ 判红并点名 file:line
        target = clone / "Scripts/check-doc-versions.py"
        original = target.read_text(encoding="utf-8")
        broken = original.replace(
            "        relative = identity_text(path.relative_to(root))",
            "        relative = str(path.relative_to(root))",
            1,
        )
        if broken == original:
            failures.append("例 2 准备失败：夹具锚点（`.as_posix()` 那一行）已不在盘上，请同步本自检")
        else:
            target.write_text(broken, encoding="utf-8")

            def check_written():
                code, output = run_at(clone)
                if code == 0:
                    return "写坏一处仍 exit 0 —— 判据是空的"
                if "check-doc-versions.py:" not in output:
                    return f"报红了但没点名文件与行号\n{output}"
                return None

            case("写坏一处 ⇒ 判红且点名", check_written)

        # 例 3：还原 ⇒ 复绿（逐字节与副本原稿一致）
        target.write_text(original, encoding="utf-8")

        def check_restored():
            code, output = run_at(clone)
            return None if code == 0 else f"还原后仍 rc={code}\n{output}"

        case("还原后复绿", check_restored)

        # 例 4：新增一个带该形状的文件 ⇒ 判红
        extra = clone / "Scripts/check-fixture-broken.py"
        extra.write_text("import pathlib\n\ndef rel(root, path):\n    return str(path.relative_to(root))\n", encoding="utf-8")

        def check_extra():
            code, output = run_at(clone)
            if code == 0:
                return "带该形状的新文件仍 exit 0"
            if "check-fixture-broken.py:4" not in output:
                return f"没点名新文件的行号\n{output}"
            return None

        case("新增带该形状的文件 ⇒ 判红且点名行号", check_extra)
        extra.unlink()

        # 例 5：例外台账缺理由 ⇒ 判红；例 6：陈旧豁免 ⇒ 判红；例 7：合法命中 ⇒ 绿且打印例外
        ledger = clone / "Scripts/script-portability-exemptions.json"
        target.write_text(broken, encoding="utf-8")

        status = {"code": -1, "output": ""}

        def with_ledger(entry: dict) -> str:
            ledger.write_text(json.dumps({"exemptions": [entry]}, ensure_ascii=False), encoding="utf-8")
            status["code"], status["output"] = run_at(clone)
            return status["output"]

        output = with_ledger({"file": "Scripts/check-doc-versions.py", "pattern": "as_posix", "reason": ""})
        case("例外没写理由 ⇒ 判红", lambda: None if "没写理由" in output else f"没报「没写理由」\n{output}")

        output = with_ledger({"file": "Scripts/check-literal-language.py", "pattern": "as_posix", "reason": "随便写的"})
        case("陈旧豁免 ⇒ 判红", lambda: None if "陈旧豁免" in output else f"没报陈旧豁免\n{output}")

        output = with_ledger({"file": "Scripts/check-doc-versions.py", "pattern": "as_posix", "reason": "夹具：验证例外路径本身"})
        case(
            "合法例外 ⇒ 绿且打印例外条目",
            lambda: None
            if status["code"] == 0 and "例外命中：Scripts/check-doc-versions.py" in output
            else f"例外路径没走通（rc={status['code']}）\n{output}",
        )
        ledger.unlink()
        target.write_text(original, encoding="utf-8")

        # 例 8：空跑防护 —— 把扫描面砍到底 ⇒ 判红
        pruned = scratch / "pruned"
        (pruned / "Scripts").mkdir(parents=True)
        for name in REQUIRED_SCOPE:
            shutil.copy(clone / "Scripts" / name, pruned / "Scripts" / name)
        (pruned / "Scripts/script-portability-exemptions.json").write_text(
            json.dumps({"exemptions": []}), encoding="utf-8"
        )

        def check_pruned():
            code, output = run_at(pruned)
            if code == 0:
                return "扫描面只剩 3 个脚本仍 exit 0 —— 空跑防护没起作用"
            if "空跑防护" not in output:
                return f"判红了但不是空跑防护那一条\n{output}"
            return None

        case("扫描面被砍 ⇒ 空跑防护判红", check_pruned)

        # 末例：真仓库逐字节未变 + 真仓库实跑绿
        after = {
            path.relative_to(repository).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted((repository / "Scripts").glob("*.py"))
        }
        case(
            "真仓库未被夹具改动",
            lambda: None if before == after else f"有文件被改：{sorted(set(before) ^ set(after))}",
        )
        case("真仓库实跑仍绿", lambda: None if run(  # noqa: E501 —— 末例顺带确认判据自身可跑
            repository
        ) == 0 else "真仓库 rc≠0")
    finally:
        shutil.rmtree(scratch, ignore_errors=True)

    print(f"自检：例数 8 / 通过 {8 - len(failures)} / 失败 {len(failures)}")
    for failure in failures:
        print(f"   {failure}")
    return 1 if failures else 0


def main() -> int:
    arguments = sys.argv[1:]
    if "--self-test" in arguments:
        return run_self_test()
    root = REPO
    if "--root" in arguments:
        index = arguments.index("--root")
        if index + 1 >= len(arguments):
            print("❌ --root 后面要跟一个目录")
            return 2
        root = pathlib.Path(arguments[index + 1]).resolve()
        if not (root / "Scripts").is_dir():
            print(f"❌ {root}/Scripts 不存在")
            return 2
    return run(root)


if __name__ == "__main__":
    sys.exit(main())
