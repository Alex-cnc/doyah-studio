#!/usr/bin/env python3
"""门禁：命令行失败输出的**可读化覆盖面**（开发循环 L-15 起，闭环第 15 项）。

**为什么有它**：CLI 里把失败说给用户看的地方有几十处，原先各写各的 ——
`print("列出表失败：\\(error.localizedDescription)")` 打出来是
`The operation couldn't be completed. (PostgresNIO.PSQLError error 1.)`：
**既不是人话、也没给方向**，而驱动其实说过原因（SQLSTATE / 驱动码），只是没人接。
第 7~8 轮只接上了连接失败 / 查询失败两条主路，剩下 57 处仍是英文调试串。

**为什么必须机械判**：这类退化**没有任何现有门禁看得见** —— 编译过、单测过、文档计数对，
只是「话指错了方向 / 干脆没说」。而且它散在几十个 `catch` 里，靠人盯必然改一处漏一处
（本轮就是一次 57 处的统一改造）。所以判据要盯住**结构**而不是当时那份人名清单：

  ① 扫描 CLI 里每一处「打给用户看的失败输出」（`print(` / `FileHandle.standardError.write(` 且
     出现原始串）：**必须**同一行经由入口 `CLIFailureText.oneLine(`。新增一处裸英文失败输出
     ⇒ 当场报红并指名行号与标签。机器可读出口（`--json` 的 `error` 字段 / `jsonQuoted(...)`）
     按**结构**放行，不靠人写行号。
  ② **反向棘轮**：入口的调用处数不得少于台账写的 `minCallSites`（57）—— 只查「入口存在」的话，
     把调用删回去、或者只写一个不接线的 helper，门禁照样绿（L-04 / L-05 / 第 14 项都栽在
     「判据太松」上）。
  ③ 入口自己的**四档口径**必须在位：连接类 → `describe`、驱动非连接类 → `describeNonConnection`、
     **服务端原话** → `describeServerSide`、认不出 → **原样返回**（不套方向结论）。顺序写反或把兜底
     改成「连接失败」都报红 —— 那正是 R-051（把猜测当结论）。
     **可读化链只许写一份**（`entryPoint.chainOnlyIn`）：CLI 主路里再抄一份 if/else 链 ⇒ 报红
     （「加一档要回来改多处」正是 L-15 收掉的那种写法）。
  ④ **服务端原话不许被丢**（`serverSideMessage`，队列 L-20 ③）：Core 里那一档必须真读
     `serverInfo` 的两格、真经 `readableServerText`、真走语言表（`.serverSideSaid`）；入口必须在
     「认不出就原样返回」**之前**调它（顺序反了 = 这一档永远走不到）；App 侧 `ErrorPresenter` 也要接
     （否则英文译文只被 CLI 的中文语境引用 —— 正是 L-47 刚收掉的死译文形态）。
  ⑤ **原始串不丢**的另一半：`String(reflecting: error)` 的调试转储不得少于台账记的处数
     （删了就只剩人话，排查拿不到原始报文）。
  ⑥ 台账里登记的例外（`--json` 出口）与渠道字段（`plumbing`）**锚点必须还在** —— 陈旧条目报红。
  ⑦ 已登记的**已知缺口**（`knownGaps`）只减不增：门禁把它们打出来（提醒别当没看见），
     条数比台账多就报红。
  ⑧ 证据脚本里的关键断言（正面 + 反向）必须在位。
  ⑨ **渠道字段两半**（`channelHalves`，队列 L-66）：失败原本是**一份值两处消费**
     （既进 JSON 也打到用户眼前），于是「让人话上屏」必然把机器载荷也换成中文。现在两半收在
     `MaintenanceTask.FailureNote`（`raw` / `readable`），判据钉三件事：
     ① **类型两半都在**（`Core/MaintenancePlan.swift` 里 `raw` / `readable` 两个字段 + `case failed(FailureNote)`）；
     ② **生产点各填一半**（界面填 `ErrorPresenter`、命令行填同一个可读化入口 —— 不是另拼一句）；
     ③ **显示点只许取人话那一半**（取了 `.raw` 当场报红），机器载荷里原串字段与新增的人话字段成对在位
     （写坏只会在编译过、单测也过的情况下悄悄退化 —— 单测跑不到 CLI 的 JSON 拼装与 `print`）。
  ⑩ **MCP 工具载荷的「两半」**（`mcpHalves`，队列 L-66 ㈡）：同一条口径落在 MCP 这条渠道上 ——
     载荷形状从前是 `(text, isError)` 这个元组（一个串既给机器又给人）。现在 `finish` 只收
     `MCPToolResult`（`raw` / `readable`），载荷里 `text` = 原串、`textHuman` = 人话 **成对**；
     三处失败（对象树 / 查询 / 写文件）必须都经同一个生产点 `mcpFailure(...)`。
     判据钉四件事：① 类型两半与 `finish` 的形参；② 载荷里两半**不对调**（`"text": .string(human)`
     出现即红）；③ 生产点原串与人话各取一处（原串 = `localizedDescription`、人话 = 同一个可读化入口）；
     ④ **三处失败一处不少**（只查 helper 存在的话，某一处改回单串照样绿）。

**面与注释（样本 67 收口，2026-10-13 · 合册 `T-20261013-027`）** —— 判定物与面各补两条：
① **注释不是代码**：行级判定与棘轮计数一律先 `strip_comments`（字符串感知、等长替换），
注释里的 `print(...)` 不再假阳、注释里的入口记号不再**冒充调用点**（㈠ ㈡）；
② **面与 `Package.swift` 对账**：`outputScan.face` 现读生产 target 的 `path:`，
面内源码与 `outputScan.files` **双向**对账（面内新增文件没登记 ⇒ 红；登记了面外的东西 ⇒ 红）（㈣）；
③ **棘轮余量归零**：`minCallSites` 必须等于真值（少写 = 静默余量 = 台账撒谎）（㈢ / 验收第 7 条）。

用法：
    python3 Scripts/check-cli-failure-readability.py            # 人读结论，失败非零退出
    python3 Scripts/check-cli-failure-readability.py --json     # 机器读
    python3 Scripts/check-cli-failure-readability.py --root <树>  # 负例验证用（临时副本）
"""

from __future__ import annotations  # macOS 自带 python3 是 3.9，`X | None` 这类注解需要它

import argparse
import json
import re
import sys
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
LEDGER_NAME = "cli-failure-readability.json"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def packaged_target(text: str, target_name: str) -> str | None:
    """`Package.swift` 里某个 target 声明的括号内文本；找不到返回 None。

    为什么要有它（样本 67 的 ㈣）：面从前是台账**写死**的 `files: ["CLI/main.swift"]`，
    与 `Package.swift` 的生产 target（`path: "CLI"`）**无对账** —— 面内新增一份 `.swift`
    里的裸英文失败输出，门禁 rc=0 与基线逐字同（面一漏全漏）。
    """
    needle = f'name: "{target_name}"'
    at = text.find(needle)
    if at < 0:
        return None
    opening = text.rfind("(", 0, at)
    if opening < 0:
        return None
    depth = 0
    for index in range(opening, len(text)):
        if text[index] == "(":
            depth += 1
        elif text[index] == ")":
            depth -= 1
            if depth == 0:
                return text[opening:index + 1]
    return None


def strip_comments(text: str) -> str:
    """行注释 / 块注释 → **等长空格**（字符串感知；行号与列位都不动）。

    为什么必须剥（样本 67 的 ㈠ / ㈡）：判定物从前是**行内原文子串**（`x in line`），
    于是一句注释就能让绿变红（`// print("…\\(error.localizedDescription)")` 与真裸英文**话术逐字相同**），
    反过来注释里的入口记号还能**冒充调用点**（真裸英文 + 行尾注释 `// 应改 CLIFailureText.oneLine(` ⇒ 绿）。
    注释不是代码 —— 「打给用户看的失败输出」与「入口调用点」这两件事只该在**代码**里找。
    **边界如实写**：字符串字面量本身保留（`error.localizedDescription` 出现在插值里是代码）；
    Swift 的多行字符串（三引号）按逐行处理（本件面内无这种写法，真仓 rc=0 佐证）。
    """
    out = []
    index = 0
    length = len(text)
    line_comment = False
    block_depth = 0
    in_string = False
    while index < length:
        char = text[index]
        following = text[index + 1] if index + 1 < length else ""
        if line_comment:
            if char == "\n":
                line_comment = False
                out.append(char)
            else:
                out.append(" ")
            index += 1
            continue
        if block_depth:
            if char == "/" and following == "*":
                block_depth += 1
                out.append("  ")
                index += 2
                continue
            if char == "*" and following == "/":
                block_depth -= 1
                out.append("  ")
                index += 2
                continue
            out.append("\n" if char == "\n" else " ")
            index += 1
            continue
        if in_string:
            if char == "\\" and following:
                out.append(char + following)
                index += 2
                continue
            if char == '"':
                in_string = False
            out.append(char)
            index += 1
            continue
        if char == '"':
            in_string = True
        elif char == "/" and following == "/":
            line_comment = True
            out.append("  ")
            index += 2
            continue
        elif char == "/" and following == "*":
            block_depth = 1
            out.append("  ")
            index += 2
            continue
        out.append(char)
        index += 1
    return "".join(out)


def call_sites(text: str, forms: list[str]) -> int:
    """入口的**真调用点**处数（剥注释 + 形状带括号与实参）。

    为什么不是 `text.count(form)`（样本 67 的 ㈢）：子串计数把**注释里的记号**也算进去 ——
    删掉 13 行真调用、补 10 行注释 ⇒ 计数照旧「达标」，13 条路径已经退回英文调试串。
    """
    code = strip_comments(text)
    total = 0
    for form in forms:
        total += len(re.findall(r"(?<![\w.])" + re.escape(form) + r"[^)]", code))
    return total


def output_sites(text: str, print_markers: list[str], raw_marker: str, call: str) -> list[tuple[int, str, str]]:
    """每一处「打给用户看的失败输出」：行号 + 原文。

    选行条件是「输出调用 + 原始串**或**入口调用」——**两者都要选**：只看原始串的话，
    已经改好的那些行（`…：\\(CLIFailureText.oneLine(error))`）根本不出现在扫描结果里，
    于是「经入口的输出」恒为 0，门禁看不见自己守的那片地方（写坏一处也只会报「裸英文」，
    而计数与结论都是假的）。
    """
    sites = []
    code_lines = strip_comments(text).splitlines()
    raw_lines = text.splitlines()
    for index, code_line in enumerate(code_lines, start=1):
        if raw_marker not in code_line and call not in code_line:
            continue
        if not any(marker in code_line for marker in print_markers):
            continue
        shown = raw_lines[index - 1].strip() if index <= len(raw_lines) else code_line.strip()
        sites.append((index, shown, code_line))
    return sites


def line_containing(text: str, anchor: str) -> str | None:
    """锚点所在的那一行（锚点写的是行内一段代码，不是整行）。找不到返回 None。

    为什么按「行」判而不是按「文件里有这个串」判：显示点要判的是**这一行取了哪一半**
    （`.raw` 还是 `.readable`）—— 只判「串在不在」的话，「显示点改回原串」这种写坏照样绿。
    """
    if not anchor:
        return None
    first = anchor.splitlines()[0]
    for line in text.splitlines():
        if first in line:
            return line
    return None


def label_of(line: str) -> str:
    """从输出行里抠一个人读的标签（`print("列出表失败：…")` → `列出表失败`）。"""
    match = re.search(r'print\("([^"\\]{2,24})', line)
    if match:
        return match.group(1).rstrip("：:")
    match = re.search(r'Data\(\(?"([^"\\]{2,24})', line)
    if match:
        return match.group(1).rstrip("：:")
    return "(无标签)"


def check(root: Path, ledger_path: Path | None = None) -> tuple[list[str], list[str]]:
    problems: list[str] = []
    notes: list[str] = []

    ledger_file = ledger_path or (root / "Scripts" / LEDGER_NAME)
    if not ledger_file.exists():
        return [f"找不到台账：{ledger_file}"], notes
    try:
        ledger = json.loads(ledger_file.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        return [f"台账不是合法 JSON：{error}"], notes

    entry = ledger.get("entryPoint") or {}
    scan = ledger.get("outputScan") or {}
    helper_rel = entry.get("file", "")
    helper_path = root / helper_rel
    if not entry.get("call") or not helper_rel:
        return ["台账缺 `entryPoint.file` / `entryPoint.call`"], notes
    if not helper_path.exists():
        problems.append(f"台账指向的入口文件不存在：{helper_rel}")
        return problems, notes

    scan_files = scan.get("files") or []
    print_markers = scan.get("printMarkers") or []
    raw_marker = scan.get("rawMarker") or ""
    json_markers = scan.get("jsonExemptMarkers") or []
    if not scan_files or not print_markers or not raw_marker or not json_markers:
        return ["台账 `outputScan` 不完整（要有 files / printMarkers / rawMarker / jsonExemptMarkers）"], notes

    # ---- ⓪ 面与 `Package.swift` 对账（样本 67 的 ㈣） --------------------------
    face_spec = scan.get("face") or {}
    if not face_spec.get("packageFile") or not face_spec.get("target"):
        problems.append(
            "台账缺 `outputScan.face`（面与 `Package.swift` 的生产 target 对账）—— 面写死单文件时，"
            "面内新增的源码文件里的失败输出**门禁看不见**（样本 67 的 P4：新增 `CLI/Extra67.swift` "
            "内含一处裸英文失败输出，改前 rc=0 与基线逐字同）"
        )
    else:
        package_path = root / face_spec["packageFile"]
        if not package_path.exists():
            problems.append(f"面对账：{face_spec['packageFile']} 不存在（面无法现读）")
        else:
            block = packaged_target(read(package_path), face_spec["target"])
            if block is None:
                problems.append(
                    f"面对账：{face_spec['packageFile']} 里找不到 target `{face_spec['target']}` —— "
                    "目标改名 / 删掉时面会静默清空"
                )
            else:
                found = re.search(r'path:\s*"([^"]+)"', block)
                if not found:
                    problems.append(f"面对账：target `{face_spec['target']}` 没写 `path:`（面从哪来不明）")
                else:
                    face_dir = root / found.group(1)
                    face = sorted(item.relative_to(root).as_posix() for item in face_dir.rglob("*.swift")) if face_dir.is_dir() else []
                    if not face:
                        problems.append(
                            f"面对账：target `{face_spec['target']}` 的目录 `{found.group(1)}` 下没有 `.swift`"
                            "（空面 = 判据守的是空气）"
                        )
                    else:
                        unregistered = [rel for rel in face if rel not in scan_files]
                        outside = [rel for rel in scan_files if rel not in face]
                        if unregistered:
                            problems.append(
                                f"面对账：面（`{face_spec['packageFile']}` 的 target `{face_spec['target']}` · 目录 `{found.group(1)}`）"
                                f"里有 {len(unregistered)} 份源码没被台账 `outputScan.files` 登记："
                                + "、".join(unregistered)
                                + " —— 面写死时这些文件里的失败输出**门禁看不见**（改完要同步台账）"
                            )
                        if outside:
                            problems.append(
                                "面对账：台账 `outputScan.files` 登记了**面外**的东西："
                                + "、".join(outside)
                                + " —— 面与 `Package.swift` 不一致（登记错了，或者目标换了）"
                            )
                        if not unregistered and not outside:
                            notes.append(
                                f"面与 `{face_spec['packageFile']}` 对账一致（target `{face_spec['target']}` · "
                                f"目录 `{found.group(1)}` · {len(face)} 份 `.swift`）"
                            )

    call = entry["call"]
    alternates = entry.get("callAlternates") or []
    entry_forms = [call] + [alt for alt in alternates if isinstance(alt, str) and alt]

    # ---- ① 每一处用户可见失败输出都必须经由入口 ------------------------------
    bare: list[str] = []
    via_entry = 0
    json_exempt = 0
    for rel in scan_files:
        path = root / rel
        if not path.exists():
            problems.append(f"扫描目标不存在：{rel}")
            continue
        for line_no, line, code_line in output_sites(read(path), print_markers, raw_marker, call):
            # 判定一律在**剥掉注释的代码行**上做（样本 67 的 ㈠ ㈡）：注释里的记号既不算输出、
            # 也不算「经了入口」—— 展示给人的仍取原始行（看到的就是开发者屏幕上那一行）。
            if any(marker in code_line for marker in json_markers):
                json_exempt += 1
                continue
            if any(form in code_line for form in entry_forms):
                via_entry += 1
                continue
            bare.append(f"{rel}:{line_no}（{label_of(line)}）")
    if bare:
        problems.append(
            "还有**裸的英文失败输出**（打给用户看、却没经过可读化入口）："
            + "、".join(bare)
            + f" —— 改成 `{call}error)`：驱动报的原因（SQLSTATE / 驱动码）就在手里，"
            "直接打 `localizedDescription` 等于把 `The operation couldn't be completed…` 丢给用户"
        )
    notes.append(f"经入口的输出 {via_entry} 处；按结构放行的机器可读出口 {json_exempt} 处")

    # ---- ② 反向棘轮：入口真的在接线（处数只增不减） --------------------------
    helper_text = strip_comments(read(helper_path))
    cli_text = "\n".join(read(root / rel) for rel in scan_files if (root / rel).exists())
    cli_code = strip_comments(cli_text)
    # 子串计数换成**真调用点计数**（剥注释 + 形状带括号与实参）：注释里的记号不再充数
    # （样本 67 的 ㈢：删 13 行真调用 + 补 10 行注释 ⇒ 旧写法读「正好达标」）。
    actual_calls = call_sites(cli_text, entry_forms)
    minimum = entry.get("minCallSites")
    if not isinstance(minimum, int) or minimum < 1:
        problems.append(
            f"台账没写 `entryPoint.minCallSites`（入口至少该有几处调用）—— 只登记「有这个入口」的话，"
            "把调用删回去（或只留一个不接线的 helper）仍能骗过门禁"
        )
    elif actual_calls < minimum:
        problems.append(
            f"入口只剩 {actual_calls} 处调用（{' / '.join(entry_forms)}），台账要求至少 {minimum} 处 —— "
            "少掉的路径已经退回英文调试串（这就是本条要挡的那件事）"
        )
    elif actual_calls > minimum:
        problems.append(
            f"入口调用 **{actual_calls}** 处、台账下限只写 {minimum} 处 —— {actual_calls - minimum} 处"
            "**静默余量**：有人删掉这么多真调用、给注释里补几个记号，棘轮照样绿（下限要跟真值，"
            "少写就是台账撒谎）。真值 = 剥注释后的真调用点处数（样本 67 的 ㈢ / 验收第 7 条）"
        )
    else:
        notes.append(
            f"入口调用 {actual_calls} 处（台账下限 {minimum} = 真值，余量 0；记法 {' / '.join(entry_forms)}）"
        )

    # ---- ③ 入口自己的四档口径必须在位 ---------------------------------------
    contract = entry.get("contract") or []
    if not contract:
        problems.append("台账没写 `entryPoint.contract`（入口该守哪几条口径）—— 没有判据可对账")
    for item in contract:
        step = item.get("step", "")
        why = (item.get("why") or "").strip()
        if not step:
            problems.append("台账 `entryPoint.contract` 里有空条目")
            continue
        if len(why) < 8:
            problems.append(f"入口口径 `{step}`：没写明为什么（理由太短）")
        if step not in helper_text:
            problems.append(
                f"入口口径 `{step}` 在 {helper_rel} 里找不到 —— "
                "口径被改了或删了（这一条守的是「认得出就给方向、认不出就不猜」）"
            )

    # ---- ③b 可读化链只写一份（加一档只改入口） --------------------------------
    chain_function = entry.get("chainFunction", "")
    chain_only_in = entry.get("chainOnlyIn", "")
    if not chain_function or not chain_only_in:
        problems.append(
            "台账缺 `entryPoint.chainFunction` / `chainOnlyIn`（「可读化链只写一份」没有判据可对账）"
        )
    else:
        chain_path = root / chain_only_in
        if not chain_path.exists():
            problems.append(f"可读化链的归属文件不存在：{chain_only_in}")
        elif chain_function not in read(chain_path):
            problems.append(f"可读化链没落在 {chain_only_in} 的 `{chain_function}` 里")
        for rel in scan_files:
            if rel == chain_only_in or not (root / rel).exists():
                continue
            text = strip_comments(read(root / rel))
            for token in ("ConnectionFailure.describeNonConnection(", "ConnectionFailure.describeServerSide("):
                if token in text:
                    problems.append(
                        f"{rel} 里又抄了一份可读化链（`{token}`）—— 口径只许写在 {chain_only_in}："
                        "散在多处时「加一档」要回来改每一处，漏一处就是一处退化（L-15 收掉的就是这种写法）"
                    )

    # ---- ④ 服务端原话不许被丢（队列 L-20 ③） ----------------------------------
    server_side = ledger.get("serverSideMessage") or {}
    if not server_side:
        problems.append(
            "台账缺 `serverSideMessage`（「服务端原话不许被丢」这一档没有判据可对账）—— "
            "那一档一旦被摘，带 SQLSTATE 的查询类错误又会只剩一句英文调试串"
        )
    else:
        core_rel = server_side.get("coreFile", "")
        core_path = root / core_rel if core_rel else None
        if not core_rel or core_path is None or not core_path.exists():
            problems.append(f"服务端原话：台账指向的 Core 文件不存在（{core_rel}）")
        else:
            core_text = read(core_path)
            definition = server_side.get("definition", "")
            if not definition or definition not in core_text:
                problems.append(
                    f"服务端原话：{core_rel} 里找不到那一档（`{definition}`）—— 摘掉就等于服务端原话又被丢"
                )
            for token in server_side.get("coreRequires") or []:
                if token not in core_text:
                    problems.append(
                        f"服务端原话：{core_rel} 里找不到 `{token}` —— 这一档被削了"
                        "（不读 serverInfo 的两格 / 不经可读化 / 不走语言表，任一条都会让它退化）"
                    )
        entry_file = server_side.get("entryFile", "")
        entry_call = server_side.get("entryCall", "")
        fallback = server_side.get("beforeFallback", "")
        entry_path = root / entry_file if entry_file else None
        if not entry_file or entry_path is None or not entry_path.exists():
            problems.append(f"服务端原话：台账指向的入口不存在（{entry_file}）")
        else:
            entry_text = read(entry_path)
            if entry_call not in entry_text:
                problems.append(f"服务端原话：{entry_file} 里没调 `{entry_call}` —— 链里那一档被摘了")
            elif fallback and entry_text.find(entry_call) > entry_text.find(fallback):
                problems.append(
                    f"服务端原话：`{entry_call}` 排在「{fallback}」**之后** —— 顺序反了这一档永远走不到"
                )
        for rel in server_side.get("otherCallers") or []:
            path = root / rel
            if not path.exists():
                problems.append(f"服务端原话：台账登记的调用方 {rel} 不存在（登记陈了）")
            elif entry_call not in read(path):
                problems.append(
                    f"服务端原话：{rel} 没接这一档 —— 界面在查询类错误上又会退回反射转储，"
                    "而且这一档的英文译文只被 CLI 的中文语境引用（L-47 刚收掉的死译文形态）"
                )

    # ---- ⑤ 调试转储不得被删 ---------------------------------------------------
    dump = ledger.get("debugDumps") or {}
    dump_marker = dump.get("marker", "")
    dump_min = dump.get("minCount")
    if not dump_marker or not isinstance(dump_min, int):
        problems.append("台账缺 `debugDumps.marker` / `debugDumps.minCount`")
    else:
        found = cli_code.count(dump_marker)
        if found < dump_min:
            problems.append(
                f"调试转储 `{dump_marker}` 只剩 {found} 处，台账要求至少 {dump_min} 处 —— "
                "原始串的另一半被删了（只剩人话时，排查拿不到原始报文）"
            )
        else:
            notes.append(f"调试转储 {found} 处（台账下限 {dump_min}）")

    # ---- ⑥ 例外与渠道字段的锚点必须还在（陈旧条目报红） ----------------------
    for kind, items in (("例外", ledger.get("exemptions") or []), ("渠道字段", ledger.get("plumbing") or [])):
        for item in items:
            anchor = item.get("anchor", "")
            why = (item.get("why") or "").strip()
            expected = item.get("count")
            if not anchor:
                problems.append(f"{kind}：有一条没写 `anchor`")
                continue
            if len(why) < 8:
                problems.append(f"{kind} {anchor[:40]}…：没写明理由")
            found = cli_code.count(anchor)
            if found == 0:
                problems.append(
                    f"{kind}：台账登记的锚点在 CLI 里找不到了（陈旧条目要删）—— `{anchor[:60]}`"
                )
            elif isinstance(expected, int) and found != expected:
                problems.append(
                    f"{kind}：`{anchor[:60]}` 实际 {found} 处、台账写 {expected} 处 —— "
                    "处数对不上说明代码变了（多了要登记、少了要确认不是被误删）"
                )

    # ---- ⑦ 已知缺口只减不增 ---------------------------------------------------
    gaps = ledger.get("knownGaps") or []
    notes.append(f"已登记缺口 {len(gaps)} 条（只减不增）")
    for gap in gaps:
        if len((gap or "").strip()) < 12:
            problems.append(f"已知缺口条目太短、等于没登记：{gap!r}")

    # ---- ⑨ 渠道字段两半（队列 L-66 口径 ①） -----------------------------------
    halves = ledger.get("channelHalves") or {}
    if not halves:
        problems.append(
            "台账缺 `channelHalves`（「渠道字段两半」没有判据可对账）—— 这个字段一次写入、两处消费："
            "谁把显示点改回 `.raw`、或把 JSON 里的人话字段摘掉，编译过、Core 单测也过，"
            "只有逐处对账看得见（第 52 轮落地 L-66 拍板口径 ①）"
        )
    else:
        type_spec = halves.get("type") or {}
        type_rel = type_spec.get("file", "")
        type_path = root / type_rel if type_rel else None
        if not type_rel or type_path is None or not type_path.exists():
            problems.append(f"渠道字段两半：台账指向的类型文件不存在（{type_rel}）")
        else:
            type_text = read(type_path)
            for token in type_spec.get("requires") or []:
                if token not in type_text:
                    problems.append(
                        f"渠道字段两半：{type_rel} 里找不到 `{token}` —— 两半被并回一份、"
                        "或失败态不再带值时，「取哪一半」就退回调用点自己记得"
                    )

        for item in halves.get("producers") or []:
            rel = item.get("file", "")
            anchor = item.get("anchor", "")
            raw_token = item.get("rawToken", "")
            path = root / rel if rel else None
            if not rel or path is None or not path.exists():
                problems.append(f"渠道字段两半：生产点台账指向的文件不存在（{rel}）")
                continue
            text = read(path)
            if not anchor or anchor not in text:
                problems.append(
                    f"渠道字段两半：{rel} 里找不到生产点 `{anchor[:60]}` —— **人话那一半没人填**"
                    "（显示点就只能拿到原串）"
                )
            if not raw_token or raw_token not in text:
                problems.append(
                    f"渠道字段两半：{rel} 里找不到原串那一半（`{raw_token[:44]}`）—— "
                    "原串必须**一字不变**地进机器载荷（可搜、可上报）"
                )

        for item in halves.get("displaySites") or []:
            rel = item.get("file", "")
            template = item.get("template", "")
            allowed = item.get("allowed") or []
            path = root / rel if rel else None
            if not rel or path is None or not path.exists():
                problems.append(f"渠道字段两半：显示点台账指向的文件不存在（{rel}）")
                continue
            if not template or not allowed:
                problems.append(f"渠道字段两半：{rel} 的显示点缺 `template` / `allowed`（没有判据可对账）")
                continue
            if "{half}" not in template:
                problems.append(
                    f"渠道字段两半：{rel} 的显示点模板里没有 `{{half}}` 占位符 —— 那样判不出"
                    "「这一行取的是哪一半」（判据就退化成「串在不在」）"
                )
                continue
            # 模板 → 「前缀 + 后缀」两段字面量（**不用正则**）：这一行的写法里全是 `\(` / `.`
            # 这类需要在 JSON 里写四层转义的字符，第 52 轮实测「台账写正则」会写错一层变成
            # 「门禁自己抛异常」；拆成两段字面量既读得懂、也不给转义留犯错空间。
            prefix, _, suffix = template.partition("{half}")
            text = read(path)
            hits = [line for line in text.splitlines() if prefix in line and suffix in line]
            if not hits:
                problems.append(
                    f"渠道字段两半：{rel} 里找不到显示点（形状变了或那处显示没了）—— 判据是 "
                    f"`{template[:70]}`，改了形状要同步台账，否则这条判据守的是空气"
                )
                continue
            if len(hits) > 1:
                problems.append(
                    f"渠道字段两半：{rel} 里同一个显示点模板匹配到 {len(hits)} 行 —— 判据分不清是哪一处"
                    f"（`{template[:70]}`）"
                )
                continue
            line = hits[0]
            tail = line.split(prefix, 1)[1]
            used = re.match(r"(?:\w+\.)*(\w+)", tail)
            hit = used.group(1) if used else ""
            allowed_text = " / ".join("." + half for half in allowed)
            if hit not in allowed:
                if hit == "raw":
                    problems.append(
                        f"渠道字段两半：{rel} 的显示点**又取回原串那一半**（`.raw`）—— "
                        f"口径 ① 是「原串给机器、人话给人」，这一处只许取 {allowed_text}"
                        f"（`{line.strip()[:96]}`）"
                    )
                else:
                    problems.append(
                        f"渠道字段两半：{rel} 的显示点取了 `.{hit}`（不在允许的两半里）—— "
                        f"这一处只许取 {allowed_text}（`{line.strip()[:96]}`）"
                    )

        for item in halves.get("machineSites") or []:
            rel = item.get("file", "")
            anchor = item.get("anchor", "")
            path = root / rel if rel else None
            if not rel or path is None or not path.exists():
                problems.append(f"渠道字段两半：机器载荷台账指向的文件不存在（{rel}）")
                continue
            if not anchor or anchor not in read(path):
                problems.append(
                    f"渠道字段两半：{rel} 里找不到机器载荷字段 `{anchor[:60]}` —— "
                    "原串字段与人话字段必须成对（摘掉人话字段 = 口径 ① 只落了一半；"
                    "摘掉原串字段 = 可搜可上报的锚点没了）"
                )

    # ---- ⑩ MCP 工具载荷的「两半」（队列 L-66 ㈡） ------------------------------
    mcp = ledger.get("mcpHalves") or {}
    if not mcp:
        problems.append(
            "台账缺 `mcpHalves`（MCP 载荷的「两半」没有判据可对账）—— 这个载荷也是一次写入、"
            "两处消费（MCP 客户端里的程序与人）：谁把 `textHuman` 摘掉、或把 `text` 改成人话，"
            "编译过、Core 单测也过（第 54 轮落地 L-66 ㈡）"
        )
    else:
        for key in ("type", "payload", "producer", "sites"):
            if not (mcp.get(key) or {}):
                problems.append(f"MCP 载荷两半：台账缺 `{key}`（没有判据可对账）")

        for key in ("type", "payload"):
            spec = mcp.get(key) or {}
            rel = spec.get("file", "")
            path = root / rel if rel else None
            if not rel or path is None or not path.exists():
                problems.append(f"MCP 载荷两半：台账 `{key}` 指向的文件不存在（{rel}）")
                continue
            text = read(path)
            for token in spec.get("requires") or []:
                if token not in text:
                    problems.append(
                        f"MCP 载荷两半：{rel} 里找不到 `{token}` —— 两半被并回一份、"
                        "或载荷里少了一个字段，「取哪一半」就退回调用点自己记得"
                    )
            for token in spec.get("forbidden") or []:
                if token in text:
                    problems.append(
                        f"MCP 载荷两半：{rel} 里出现了 `{token}` —— **原串被换成了人话**"
                        "（口径 ① 是「原串给机器、人话另给字段」，不是「把原串换成中文」）"
                    )
        payload = mcp.get("payload") or {}
        if payload.get("anchor") and payload["file"]:
            path = root / payload["file"]
            if path.exists() and payload["anchor"] not in read(path):
                problems.append(
                    f"MCP 载荷两半：{payload['file']} 里找不到载荷字段 `{payload['anchor'][:60]}` —— "
                    "**人话那一半必须真的出现在机器载荷里**（否则界面 / MCP 客户端想展示也没有可展示的）"
                )

        producer = mcp.get("producer") or {}
        producer_file = producer.get("file", "")
        producer_path = root / producer_file if producer_file else None
        if not producer_file or producer_path is None or not producer_path.exists():
            problems.append(f"MCP 载荷两半：生产点台账指向的文件不存在（{producer_file}）")
        else:
            text = read(producer_path)
            if producer.get("anchor") and producer["anchor"] not in text:
                problems.append(
                    f"MCP 载荷两半：{producer_file} 里找不到生产点 "
                    f"`{producer.get('anchor', '')[:60]}` —— 三处失败必须走同一个生产点"
                )
            if producer.get("rawToken") and producer["rawToken"] not in text:
                problems.append(
                    f"MCP 载荷两半：{producer_file} 里找不到原串那一半"
                    f"（`{producer.get('rawToken', '')[:44]}`）—— 原串必须**一字不变**地进机器载荷"
                )
            if producer.get("readableToken") and producer["readableToken"] not in text:
                problems.append(
                    f"MCP 载荷两半：{producer_file} 里找不到人话那一半"
                    f"（`{producer.get('readableToken', '')[:44]}`）—— 人话必须经同一个可读化入口"
                )

        sites = mcp.get("sites") or {}
        sites_file = sites.get("file", "")
        sites_path = root / sites_file if sites_file else None
        if not sites_file or sites_path is None or not sites_path.exists():
            problems.append(f"MCP 载荷两半：调用点台账指向的文件不存在（{sites_file}）")
        else:
            anchor = sites.get("anchor", "")
            expected = sites.get("count")
            found = read(sites_path).count(anchor) if anchor else 0
            if not anchor:
                problems.append("MCP 载荷两半：`sites` 没写 `anchor`（判据守的是空气）")
            elif found == 0:
                problems.append(
                    f"MCP 载荷两半：{sites_file} 里一个失败生产点都找不到（`{anchor}`）—— "
                    "那条路的失败又只剩原串、没有另一半"
                )
            elif isinstance(expected, int) and found != expected:
                problems.append(
                    f"MCP 载荷两半：失败生产点实际 {found} 处、台账写 {expected} 处 —— "
                    "少一处就是那条路的失败退回单串（多一处要登记）"
                )

    # ---- ⑪ 证据脚本里的关键断言必须在位 -------------------------------------
    for marker in ledger.get("evidence") or []:
        path = root / marker.get("file", "")
        if not path.exists():
            problems.append(f"证据：{marker.get('file')} 不存在（台账说它该在）")
            continue
        if marker.get("contains") and marker["contains"] not in read(path):
            problems.append(
                f"证据：{marker.get('file')} 里找不到 `{marker['contains']}` —— 台账登记的断言不在位"
            )

    return problems, notes


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--root", default=None, help="换一棵树（负例验证用）")
    parser.add_argument("--ledger", default=None, help="换一份台账（负例验证用）")
    args = parser.parse_args()

    root = Path(args.root).resolve() if args.root else BASE
    ledger = Path(args.ledger).resolve() if args.ledger else None
    problems, notes = check(root, ledger)

    if args.json:
        print(json.dumps({"ok": not problems, "problems": problems, "notes": notes}, ensure_ascii=False, indent=2))
        return 1 if problems else 0

    for note in notes:
        print(f"  · {note}")
    if problems:
        print(f"\n❌ {len(problems)} 处不合规：")
        for problem in problems:
            print(f"  · {problem}")
        return 1
    print(
        "\n✅ 命令行的失败输出一律经可读化入口（认得出给方向、认不出原样）；机器可读出口按结构放行；"
        "原始串仍保留在调试转储里；例外与渠道字段的锚点都在位。"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
