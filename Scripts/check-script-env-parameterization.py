#!/usr/bin/env python3
"""门禁：连真库的脚本**不许自己写死连接信息**（开发循环 L-06 起，闭环第 13 项）。

**为什么有它**：L-06 之前，本机集群的端口 55433、PG 二进制路径、数据目录、217 的地址与账号
在 32 个脚本里各写一遍（`grep -c 55433 Scripts/*.sh` 就是这份「事实」的分布）。这有两个后果：
迁移到 217 时要手改 32 份、且**改漏一个没人发现**（脚本照样能跑、照样打勾，只是连的是本机）。

**为什么门禁不能自己去 grep 端口**：迁移改完之后 `55433` 就没了 —— 那时 `grep` 返回空，
门禁「永远通过」，而新写的脚本照样可以再写死一次。所以做法反过来：**清单是声明**，
门禁拿判据跟事实对账（见 `Scripts/real-db-scripts.txt` 的头注释）：

  ① 清单里的脚本：存在 + `source` 了 lib + 调了 `doyah_test_env_summary`（在**代码行**上判）；
  ② 面内每份 `.sh`：不许出现连接字面量（新脚本要么用 lib、要么登记进清单）；
  ③ lib **自己**必须持有那三档集群与本机二进制路径的默认值（不许把字面量搬到"没有"里去）；
  ④ 清单与 `Scripts/real-db-evidence-baseline.json` 对账（两份事实不许各说各话；**缺件判红**）；
  ⑤ **旁路**：出现 `DOYAH_TEST_REMOTE_*`（直连 217 的第二条路）必须逐条登记在
     `Scripts/remote-bypass-scripts.json`；登记了却已不再旁路 ⇒ 陈旧报红；理由为空 ⇒ 报红。

**「代码 vs 注释·字符串」**（2026-10-13 合册 `T-20261013-027` · 原单 `T-20261010-057` · 第 19 轮）：
本件此前四条判据是**三种口径**（一条跳整行注释 / 一条走 `code_lines()` / 一条一个字都不跳）⇒
同一份文件里「注释里提过旧端口」与「代码里又写死一次」报的是**同一条话术**（分不出人话与代码）。
现在统一：**注释（整行 + 行尾）与字符串里的提及一律不算命中**，判定物一律先 `strip_comments()`；
字符串里**只保留两类**（它们是真东西，不是「提过一句」）：`${VAR}` / `$VAR` 变量引用，
以及 `://` / `port=` / `host=` 形状的**连接串**。

**面**（同上）：`SCRIPTS.glob("*.sh")` 只扫顶层一层 ⇒ 子目录脚本全在面外（同内容放顶层即判红）。
现在面 = **递归**，且子目录**逐条登记**在 `Scripts/shell-face-subdirs.json`
（登记了却没有 `.sh` ⇒ 死登记判红；`exempt=true` 必须在表里写清理由）。

用法：
    python3 Scripts/check-script-env-parameterization.py            # 人读结论，失败非零退出
    python3 Scripts/check-script-env-parameterization.py --json     # 机器读
"""

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "Scripts"
LIB = SCRIPTS / "lib" / "test-env.sh"
MANIFEST = SCRIPTS / "real-db-scripts.txt"
BASELINE = SCRIPTS / "real-db-evidence-baseline.json"
BYPASS_REGISTRY = SCRIPTS / "remote-bypass-scripts.json"
SUBDIR_REGISTRY = SCRIPTS / "shell-face-subdirs.json"

# 面根数硬下限：防「把顶层脚本搬进子目录 / 改名 ⇒ 面被掏空、零命中 = 通过」
FACE_TOP_FLOOR = 60

# 旁路标记：只有 `DOYAH_TEST_REMOTE_*` 那一族（「只对 217 做只读核对」的第二条路）
BYPASS_TOKEN = "DOYAH_TEST_REMOTE_"

# 连接字面量：谁都不许在 lib 之外写
FORBIDDEN_TOKENS = [
    ("55432", "本机 querytest 档端口"),
    ("55433", "本机 session 档端口"),
    ("55434", "本机 slowquery 档端口"),
    ("tools/pgserver", "本机 PG 二进制路径"),
    ("pgdata-", "本机集群数据目录"),
    ("192.168.5.217", "217 的地址"),
]

# 端点字面量（赋值形态）：账号 / 库名也不许写死（负例里**故意**用的坏值不在此列 ——
# 那些是坏主机名 / 坏端口 / 陌生账号，正是断言的现场）。
# 2026-10-13（合册第 19 轮）：闸门此前只走**清单内**的脚本 ⇒ 清单外写死 `PGUSER=postgres`
# 无人管。现在改成走**面**（顶层 + 未豁免的子目录），与判据 ② 同面。
FORBIDDEN_ASSIGNMENTS = [
    (re.compile(r"PGUSER=(postgres|zxvmax)(?![a-z_])"), "写死的账号（应为 ${DOYAH_TEST_PGUSER}）"),
    (re.compile(r"PGDATABASE=postgres(?![a-z_])"), "写死的维护库（应为 ${DOYAH_TEST_ADMIN_DB}）"),
]

# lib 必须真的持有的事实（正面判据：挡住「把字面量删干净」这条捷径）。
# 只在**代码行**上匹配（整行注释与行尾注释都不算）—— 否则把值改成 0、注释里还留着旧数字，
# 门禁照样绿。**注意：这里不抹字符串** —— lib 里那几档路径本来就写在引号里。
LIB_MUST_HAVE = [
    (re.compile(r"_doyah_test_profile_port=55433"), "session 档端口"),
    (re.compile(r"_doyah_test_profile_port=55434"), "slowquery 档端口"),
    (re.compile(r"_doyah_test_profile_port=55432"), "querytest 档端口"),
    (re.compile(r"pgdata-session-test"), "session 档数据目录"),
    (re.compile(r"pgdata-slowquery"), "slowquery 档数据目录"),
    (re.compile(r"tools/pgserver/pgserver/pginstall/bin"), "本机 PG 二进制默认路径"),
    (re.compile(r"192\.168\.5\.217"), "217 的地址"),
    (re.compile(r"DOYAH_TEST_LOCAL_PROFILE"), "档位开关"),
    (re.compile(r"DOYAH_TEST_EXIT_CONFIG=78"), "配置不全的退出码"),
    (re.compile(r"DOYAH_TEST_EXIT_REFUSE=77"), "安全拒绝的退出码"),
]

# 连接串形状：引号里出现这些 ⇒ 那是**真写死**（不是「提过一句」），照判
CONNINFO_SHAPES = (re.compile(r"://"), re.compile(r"\bport=\d"), re.compile(r"\bhost="))
# 变量引用：引号里的 `${VAR}` / `$VAR` 是真用法（判据 ⑤ 靠它认出「真在用旁路」）
VAR_REF = re.compile(r"\$\{?[A-Za-z_][A-Za-z0-9_]*\}?")


def _strip_comment_line(line):
    """剥掉一行的注释，**等长空格替换**（行号列位都不动）。

    shell 口径：`#` 只有在**词首**才是注释开始（前一个字符是行首 / 空白 / `;` `&` `|` `(`）——
    `${x#y}`、`a#b` 里的 `#` 都不是；引号里的 `#` 也不是。整行注释与行尾注释一并处理。
    """
    quote = None
    index = 0
    chars = list(line)
    while index < len(line):
        character = line[index]
        if quote is None:
            if character in ("'", '"'):
                quote = character
            elif character == "#":
                previous = line[index - 1] if index else " "
                if previous in " \t;&|(":
                    for position in range(index, len(line)):
                        if chars[position] != "\t":
                            chars[position] = " "
                    break
        else:
            if character == "\\" and quote == '"':
                index += 2
                continue
            if character == quote:
                quote = None
        index += 1
    return "".join(chars)


def strip_comments(text):
    """整份文本剥注释（逐行，等长），行号与列位都不动。"""
    return "\n".join(_strip_comment_line(line) for line in text.splitlines())


def blank_strings(text):
    """把引号里的字面量抹成空格（等长），**只保留两类**：

    ① `${VAR}` / `$VAR` 变量引用 —— shell 里那是真用法；
    ② 连接串形状（`://` / `port=` / `host=`）—— 那是真写死。

    其余（`echo "端口 55433 见文档"` 这种「提过一句」）一律抹掉 ⇒ 不再与真写死同一条话术。
    """
    chars = list(text)
    index = 0
    while index < len(text):
        if text[index] in ("'", '"'):
            quote = text[index]
            cursor = index + 1
            while cursor < len(text):
                if quote == '"' and text[cursor] == "\\":
                    cursor += 2
                    continue
                if text[cursor] == quote:
                    break
                cursor += 1
            region = text[index + 1:cursor]
            if not any(shape.search(region) for shape in CONNINFO_SHAPES):
                kept = set()
                for match in VAR_REF.finditer(region):
                    kept.update(range(match.start(), match.end()))
                for offset in range(len(region)):
                    if offset not in kept and chars[index + 1 + offset] != "\t":
                        chars[index + 1 + offset] = " "
            index = cursor + 1
            continue
        index += 1
    return "".join(chars)


def code_only(text):
    """只要「代码行」：剥注释，**保留字符串**（判「source 了 lib / 打了摘要」要看命令字面量）。"""
    return strip_comments(text)


def judged_lines(text):
    """判定物：剥注释 + 抹字符串（保留变量引用与连接串）后的逐行 —— 与原文行号对齐。"""
    return blank_strings(strip_comments(text)).splitlines()


def shell_face():
    """面 = `Scripts/` 下**全部** `.sh`（**递归**）。返回 (顶层脚本, {子目录相对路径: [文件]})。"""
    top = sorted(SCRIPTS.glob("*.sh"))
    subdirectories = {}
    for path in sorted(SCRIPTS.rglob("*.sh")):
        relative = path.relative_to(SCRIPTS)
        if len(relative.parts) > 1:
            directory = relative.parent.as_posix()
            subdirectories.setdefault(directory, []).append(path)
    return top, subdirectories


def face_registry(problems):
    """面登记表：子目录里有 `.sh` ⇒ 必须逐条登记（要豁免就写理由）；登记了却没有 ⇒ 死登记判红。"""
    registered = {}
    if not SUBDIR_REGISTRY.exists():
        problems.append(f"找不到面登记表 {SUBDIR_REGISTRY.name}（面要拿它对账：Scripts/ 下哪些子目录有 .sh、为什么）")
        return registered
    try:
        data = json.loads(SUBDIR_REGISTRY.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        problems.append(f"面登记表 {SUBDIR_REGISTRY.name} 不是合法 JSON：{error}")
        return registered
    entries = data.get("entries", [])
    if not isinstance(entries, list):
        problems.append(f"面登记表 {SUBDIR_REGISTRY.name} 的 entries 不是列表")
        return registered
    for entry in entries:
        directory = str(entry.get("dir", "")).strip().strip("/")
        reason = str(entry.get("reason", "")).strip()
        if not directory:
            problems.append("面登记表里有一条没写 dir")
            continue
        if not reason:
            problems.append(f"面登记表 {directory} 没写理由（reason 空）—— 面外是要解释的")
        registered[directory] = bool(entry.get("exempt", False))
    return registered


def load_manifest():
    """清单 -> (名字列表, 分组字典)。`# [组名]` 行开一个新组。"""
    names, groups, group = [], {}, None
    for line in MANIFEST.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        marker = re.match(r"^#\s*\[(\w[\w-]*)\]$", stripped)
        if marker:
            group = marker.group(1)
            continue
        if stripped.startswith("#"):
            continue
        names.append(stripped)
        groups.setdefault(group or "未分组", []).append(stripped)
    return names, groups


def check():
    problems = []
    notes = []
    lib_code = code_only(LIB.read_text(encoding="utf-8")).splitlines()

    # ---- ③ lib 必须持有那些事实（先查这个：否则 ① ② 都可能是「删干净」骗过去的）----
    for pattern, what in LIB_MUST_HAVE:
        if not any(pattern.search(line) for line in lib_code):
            problems.append(f"lib 里找不到 {what}（{pattern.pattern}）—— 连接信息不能搬去「没有」的地方")

    names, groups = load_manifest()
    if not names:
        problems.append("清单里一条脚本都没有")

    # ---- 面：递归 + 子目录逐条登记 ----
    top, subdirectories = shell_face()
    if len(top) < FACE_TOP_FLOOR:
        problems.append(f"面里的顶层 .sh 只有 {len(top)} 份（硬下限 {FACE_TOP_FLOOR}）—— 面像被掏空了，先核清 Scripts/ 顶层")
    registered = face_registry(problems)
    face = list(top)
    exempt = []
    for directory, files in sorted(subdirectories.items()):
        if directory not in registered:
            problems.append(
                f"Scripts/{directory}/ 里有 .sh（{len(files)} 份）却没登记在 {SUBDIR_REGISTRY.name} 里 —— "
                f"面要完整：子目录要么进面，要么逐条写清为什么不算")
            face.extend(files)
        elif registered[directory]:
            exempt.append(directory)
        else:
            face.extend(files)
    for directory in sorted(registered):
        if not subdirectories.get(directory):
            problems.append(
                f"面登记表登记了 {directory}，但 Scripts/{directory}/ 下没有 .sh —— 死登记要销账"
                f"（陈旧登记与漏登记一样会让人误判面）")

    declared = set(names)

    # ---- ① 清单里的脚本（判定物 = 剥注释后的代码行，字符串保留）----
    for name in names:
        path = SCRIPTS / f"{name}.sh"
        if not path.exists():
            problems.append(f"清单登记了 {name}，但 Scripts/{name}.sh 不存在")
            continue
        code = code_only(path.read_text(encoding="utf-8"))
        if 'source "$(cd "$(dirname "$0")" && pwd)/lib/test-env.sh"' not in code:
            problems.append(f"{name}.sh 没有 source Scripts/lib/test-env.sh（连接信息应只有一处出处）")
        if "doyah_test_env_summary" not in code:
            problems.append(f"{name}.sh 没有打印目标摘要（doyah_test_env_summary）—— 日志里看不出连的是谁")

    # ---- ② 连接字面量：**面内每份** .sh 都不许写（清单里的也要查 ——
    #         迁移最容易出事的正是"清单里那个脚本漏改了一处"）----
    for path in sorted(face):
        relative = path.relative_to(SCRIPTS).as_posix()
        in_manifest = path.parent == SCRIPTS and path.stem in declared
        for index, line in enumerate(judged_lines(path.read_text(encoding="utf-8")), 1):
            for token, what in FORBIDDEN_TOKENS:
                if token not in line:
                    continue
                if in_manifest:
                    problems.append(
                        f"{relative}:{index} 出现 {what}（{token}）—— 清单里的脚本一律从 "
                        f"Scripts/lib/test-env.sh 取值（三档与 217 的地址只写在它里面）")
                else:
                    problems.append(
                        f"{relative}:{index} 出现 {what}（{token}）但不在 Scripts/real-db-scripts.txt 里 —— "
                        f"要么改用 Scripts/lib/test-env.sh，要么登记进清单并 source 它")

    # ---- 账号 / 库名闸门：与判据 ② **同面**（此前只走清单内 ⇒ 清单外写死账号无人管）----
    for path in sorted(face):
        relative = path.relative_to(SCRIPTS).as_posix()
        for index, line in enumerate(judged_lines(path.read_text(encoding="utf-8")), 1):
            for pattern, what in FORBIDDEN_ASSIGNMENTS:
                if pattern.search(line):
                    problems.append(f"{relative}:{index} 有{what} → {line.strip()[:80]}")

    # ---- ④ 清单 ↔ 证据基线（**缺件判红**：此前无 else ⇒ 删掉基线即 rc=0）----
    if not BASELINE.exists():
        problems.append(
            f"找不到证据基线 {BASELINE.name}（判据 ④ 要拿它跟清单对账：清单里的脚本必须"
            f"「在基线里跑过」或「按环境跳过」，缺了这一件对账就被无声关掉）")
    else:
        data = json.loads(BASELINE.read_text(encoding="utf-8"))
        baseline_names = {e["script"].split("/")[-1][:-3] for e in data.get("entries", [])}
        skipped_names = {e["script"].split("/")[-1][:-3] for e in data.get("skippedDueToEnvironment", [])}
        missing = baseline_names - declared
        if missing:
            problems.append("证据基线里跑这些脚本，但清单里没有它们：" + "、".join(sorted(missing)))
        extra_skipped = skipped_names - declared
        if extra_skipped:
            notes.append("基线里按环境跳过、且未进清单（属正常）：" + "、".join(sorted(extra_skipped)))
        unaccounted = declared - baseline_names - skipped_names
        if unaccounted:
            problems.append("清单里的这些脚本既不在证据基线里、也没登记为环境跳过："
                            + "、".join(sorted(unaccounted)))

    # ---- ⑤ 旁路 217（`DOYAH_TEST_REMOTE_*`）必须登记在册（判定物 = 剥注释 + 抹字符串，
    #         但 `${DOYAH_TEST_REMOTE_*}` 变量引用照留 ⇒ 真在用旁路仍认得出）----
    registered_bypass = []
    if BYPASS_REGISTRY.exists():
        try:
            registry = json.loads(BYPASS_REGISTRY.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            problems.append(f"旁路台账 {BYPASS_REGISTRY.name} 不是合法 JSON：{error}")
            registry = {}
        entries = registry.get("entries", [])
        if not isinstance(entries, list):
            problems.append(f"旁路台账 {BYPASS_REGISTRY.name} 的 entries 不是列表")
            entries = []
        for entry in entries:
            script = str(entry.get("script", "")).strip()
            reason = str(entry.get("reason", "")).strip()
            if not script:
                problems.append("旁路台账里有一条没写 script")
                continue
            registered_bypass.append(script)
            if not reason:
                problems.append(f"旁路台账 {script} 没写理由（reason 空）—— 旁路是要解释的")
    else:
        problems.append(f"找不到旁路台账 {BYPASS_REGISTRY.name}（判据 ⑤ 要拿它跟事实对账）")

    bypassing = []
    for path in sorted(face):
        for index, line in enumerate(judged_lines(path.read_text(encoding="utf-8")), 1):
            if BYPASS_TOKEN in line:
                bypassing.append(path.name)
                if path.name not in registered_bypass:
                    problems.append(
                        f"{path.name}:{index} 用了旁路 {BYPASS_TOKEN}*（直接连 217）却没登记在 "
                        f"{BYPASS_REGISTRY.name} 里 —— 旁路要么改走共用入口，要么逐条写清理由"
                    )
                break
    for script in registered_bypass:
        if script not in bypassing:
            problems.append(
                f"旁路台账登记了 {script}，但它已经不再旁路（{BYPASS_TOKEN}*）—— 改走正路后要销账；"
                f"陈旧登记与漏登记一样会让人误判现状"
            )
    notes.append(f"旁路 217 的脚本 {len(bypassing)} 个（逐条登记理由）：{'、'.join(bypassing) or '无'}")
    notes.append(f"面：顶层 {len(top)} 份 + 面内子目录 {len(face) - len(top)} 份"
                 f"（登记在册、豁免在面外：{'、'.join(exempt) or '无'}）")

    face_info = {
        "top": len(top),
        "inFace": len(face),
        "exempt": exempt,
        "subdirectories": {name: len(files) for name, files in sorted(subdirectories.items())},
    }
    return problems, notes, names, groups, bypassing, registered_bypass, face_info


def main():
    parser = argparse.ArgumentParser(description="连真库的脚本不许写死连接信息")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    problems, notes, names, groups, bypassing, registered, face_info = check()

    if args.json:
        print(json.dumps({
            "ok": not problems,
            "problems": problems,
            "notes": notes,
            "declared": names,
            "groups": groups,
            "bypassing": bypassing,
            "registeredBypass": registered,
            "face": face_info,
        }, ensure_ascii=False, indent=2))
        return 1 if problems else 0

    print(f"清单 Scripts/real-db-scripts.txt：{len(names)} 个脚本", end="")
    if groups:
        detail = "、".join(f"{g} {len(v)}" for g, v in groups.items())
        print(f"（{detail}）")
    else:
        print()
    for name in notes:
        print(f"  · {name}")

    if problems:
        print(f"\n❌ {len(problems)} 处不合规：")
        for problem in problems:
            print(f"  · {problem}")
        return 1
    print("\n✅ 连真库的脚本一律从 Scripts/lib/test-env.sh 取连接信息，清单与证据基线对得上。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
