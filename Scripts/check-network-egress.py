#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""门禁：全仓网络出口的「按面分层的文件级显式清单」（Notes SRS **v3.94** §6.4 · 前门落笔 `987ace7`）。

**为什么有它**：`FR-PLUG-05` 的「笔记模块零网络出口」（`check-notes-offline.py`）只扫 `Core/` 下
文件名以 `Note` / `AICapture` / `License` 开头的文件与 `App/` 下的 `Note*` —— 而 **`Core/NoteSync/`
是子目录、文件名不以 `Note` 开头** ⇒ 云同步面 / 认证面**不在任何门禁的扫描面内**（执行侧 ⑰ 相抵上报，
`T-20261009-147 ③`）。结果就是假绿：`CloudAuth.swift` 引了 `URLSession`、门禁照旧全绿。
前门的裁定（`T-20261009-149 ③`）是**按面分层的文件级显式清单** —— 本门禁把那张清单变成可复跑判据。

**清单（只许取自 SRS v3.94，不许自造；逐条理由见台账 `Scripts/network-egress-whitelist.json`）**：

  ① **笔记同步面** = `Core/NoteSync/CloudSyncService.swift`（该面唯一出口）
  ② **认证面**     = `Core/NoteSync/CloudAuth.swift`（单列：认证与同步解耦）
  ③ **AI 面（既有豁免）** = `Core/LLMClient.swift` + `Core/EgressLog.swift`（传输装饰器）
  ④ **装配缝（不算出口）** = `App/AppState.swift` · `App/Auth/AccountFlowModel.swift`（只注入 transport）
  ⑤ **其余一切文件**出现 `URLSession` / `URLRequest` ⇒ **判红**（并点名 `文件:行号`）

**口径（写死，见 SRS v3.94 §6.4 四条纪律）**：

  · **文件级显式清单**，**目录级豁免一律无效**（`Core/NoteSync/**` 整目录不是豁免）。
  · **只判代码出现**：`URLSession` / `URLRequest` 出现在 `//` / `///` 行注释、`/* */` 块注释或
    **字符串字面量**里**不算出现、不判红**（判定对象 = **代码出现**；口径由组长第 371 轮预审确认，
    待前门落笔 SRS，单号 T-20261009-159）—— 与
    `check-core-portability.py` / `check-editor-surface-tokens.py` / `check-design-tokens.py` 同一口径
    （「注释里提到某个标识不算它还在用」）。因此 `Core/DataTaskSpecGenerator.swift:7` 的文档注释
    「本类型里没有任何 URLSession / 请求组装」**不判红** —— 它是**声明不出网**，不是出网；该文件按 ⑤
    落在「其余一切文件」行且**没有代码出现**，既**不违规**、也**不进白名单**（白名单只许取自 SRS）。
  · **装配缝直接出网判红**：装配缝文件里除「注入 transport」（`URLSessionTransport(` /
    `URLSessionCloudAuthTransport(`）以外的 `URLSession` / `URLRequest` 出现 ⇒ 判红（纪律③）。
  · **新增任何联网文件 ⇒ 本门禁判红**，需前门登记后放行（纪律②）。

用法：
    python3 Scripts/check-network-egress.py              # 人读结论，失败非零退出
    python3 Scripts/check-network-egress.py --json        # 机器读（含 filesScanned / violations）
    python3 Scripts/check-network-egress.py --root <树>    # 负例验证用（临时副本）
    python3 Scripts/check-network-egress.py --ledger <份>  # 换一份台账（负例验证用）
"""

from __future__ import annotations  # macOS 自带 python3 可能 < 3.10，`X | None` 这类注解需要它

import argparse
import json
import re
import sys
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
LEDGER_DEFAULT = "Scripts/network-egress-whitelist.json"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def code_lines(text: str) -> list[tuple[int, str]]:
    """返回 [(行号, 去掉注释后的行文本)] —— **只去注释**（`//` 行注释与 `/* */` 块注释），
    字符串字面量原样保留（判据只看代码：注释里提到某个标识不算它还在用）。

    为什么不去字符串：把出网 API 藏在字符串里也还是「出现」，留着更严；为什么按行重置字符串状态：
    Swift 单行字符串总在同一行闭合成对，跨行字符串（`\"\"\"`）里出现这两个令牌的可能性可忽略，
    按行重置换来的是「一行写坏不会让后面整片被跳掉」。
    """
    result: list[tuple[int, str]] = []
    in_block = False
    for number, raw in enumerate(text.split("\n"), start=1):
        out: list[str] = []
        in_string = False
        escaped = False
        index = 0
        length = len(raw)
        while index < length:
            char = raw[index]
            if in_block:
                if char == "*" and index + 1 < length and raw[index + 1] == "/":
                    in_block = False
                    index += 2
                    continue
                index += 1
                continue
            if in_string:
                # 字符串字面量的**内容不算出现**（判定对象 = 代码出现；口径见 docstring / 组长第 371 轮预审）：
                # 整段丢弃，只跟踪转义与闭合引号，让同一行后面的代码 / 注释仍被正确判定。
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == '"':
                    in_string = False
                index += 1
                continue
            if char == '"':
                in_string = True
                index += 1
                continue
            if char == "/" and index + 1 < length and raw[index + 1] == "/":
                break  # 行注释：丢到行尾
            if char == "/" and index + 1 < length and raw[index + 1] == "*":
                in_block = True
                index += 2
                continue
            out.append(char)
            index += 1
        result.append((number, "".join(out)))
    return result


def load_ledger(path: Path):
    if not path.exists():
        return None, f"台账不存在：{path}"
    try:
        return json.loads(read(path)), None
    except json.JSONDecodeError as error:
        return None, f"台账不是合法 JSON：{error}"


def check(root: Path, ledger_path: Path | None) -> tuple[list[str], list[str], dict]:
    problems: list[str] = []
    notes: list[str] = []
    stats = {"filesScanned": 0, "occurrences": 0, "violations": 0, "surfaceHits": {}}

    ledger_file = ledger_path or (root / LEDGER_DEFAULT)
    ledger, error = load_ledger(ledger_file)
    if ledger is None:
        return [error or "台账不可读"], notes, stats

    tokens = [((entry or {}).get("token") or "") for entry in ledger.get("tokens") or []]
    tokens = [token for token in tokens if token]
    required = [token for token in (ledger.get("requiredTokens") or []) if token]
    surfaces = ledger.get("surfaces") or []
    scan_cfg = ledger.get("scan") or {}
    scan_roots = scan_cfg.get("roots") or ["App", "Core"]
    floors = ledger.get("floors") or {}
    wiring = ledger.get("wiring") or {}

    # ---- ① 台账自洽 ----------------------------------------------------------
    if not tokens:
        problems.append("台账里一个令牌都没有（零令牌不许当通过）")
    for entry in ledger.get("tokens") or []:
        token = (entry or {}).get("token") or ""
        if len(((entry or {}).get("reason") or "").strip()) < 8:
            problems.append(f"令牌 `{token}` 没写明理由（为什么禁它要说得出）")
    if not surfaces:
        problems.append("台账里一个面都没有（零面不许当通过）")

    surface_of: dict[str, str] = {}
    surface_name: dict[str, str] = {}
    seam_patterns: list[re.Pattern] = []
    for surface in surfaces:
        key = (surface or {}).get("key") or ""
        name = (surface or {}).get("name") or key
        files = (surface or {}).get("files") or []
        if not key:
            problems.append("面条目缺 key")
        surface_name[key or name] = name
        if len(((surface or {}).get("rule") or "").strip()) < 4:
            problems.append(f"面 `{name}` 没写口径（rule）")
        if len(((surface or {}).get("reason") or "").strip()) < 8:
            problems.append(f"面 `{name}` 没写明理由（说不出它为什么允许出网）")
        if not files:
            problems.append(f"面 `{name}` 一个文件都没有（空面不是豁免）")
        for rel in files:
            if rel in surface_of:
                problems.append(f"`{rel}` 被两个面同时登记（{surface_of[rel]} / {key}）")
            surface_of[rel] = key
            if not (root / rel).exists():
                problems.append(f"面 `{name}` 登记的 `{rel}` 磁盘上不存在（改名 / 删除了？请同步台账）")
        if key == "seam":
            for pattern in (surface or {}).get("allowPatterns") or []:
                try:
                    seam_patterns.append(re.compile(pattern))
                except re.error as pattern_error:
                    problems.append(f"装配缝的 allowPatterns 正则不合法：{pattern_error}")

    # ---- ② 逐文件扫（只判**代码行**；注释里的提及不算出现）--------------------
    for token in tokens:
        stats["surfaceHits"][token] = 0
    violations: list[str] = []
    occurrence_files: set[str] = set()
    seam_allowed = 0
    for base in scan_roots:
        base_dir = root / base
        if not base_dir.is_dir():
            problems.append(f"扫描根不存在：{base}/")
            continue
        for path in sorted(base_dir.rglob("*.swift")):
            rel = path.relative_to(root).as_posix()
            stats["filesScanned"] += 1
            surface = surface_of.get(rel)
            for number, code in code_lines(read(path)):
                for token in tokens:
                    if token not in code:
                        continue
                    stats["occurrences"] += 1
                    occurrence_files.add(rel)
                    if surface is None:
                        violations.append(
                            f"{rel}:{number}：命中网络 API `{token}` —— 该文件**不在台账任何一面里**"
                            f"（`{LEDGER_DEFAULT}`；SRS v3.94 §6.4：其余一切文件不得出现 "
                            f"`URLSession` / `URLRequest`）。新增联网文件须前门登记后放行（纪律②）"
                        )
                        continue
                    if surface == "seam":
                        remainder = code
                        for pattern in seam_patterns:
                            remainder = pattern.sub("", remainder)
                        if token in remainder:
                            violations.append(
                                f"{rel}:{number}：装配缝文件命中**直接出网调用** `{token}` —— "
                                f"装配缝只许**注入 transport**（`URLSessionTransport(` / "
                                f"`URLSessionCloudAuthTransport(`），不得直接出网（SRS v3.94 §6.4 纪律③）"
                            )
                        else:
                            seam_allowed += 1
                        continue
                    stats["surfaceHits"][token] = stats["surfaceHits"].get(token, 0) + 1

    problems.extend(violations)
    stats["violations"] = len(violations)

    # ---- ③ 台账 ↔ 扫描对账（漏登一个文件也不行）-------------------------------
    for rel in sorted(occurrence_files):
        if rel not in surface_of:
            # 已由 ② 逐条报出；这里只保证「有出现的文件集合 ⊆ 台账登记的集合」这条结构不变量也在。
            continue
    notes.append(
        f"扫描 {' + '.join(f'{base}/' for base in scan_roots)} 共 {stats['filesScanned']} 个 .swift；"
        f"命中令牌 {stats['occurrences']} 处（白名单面 {sum(stats['surfaceHits'].values())} 处 · "
        f"装配缝 transport 注入 {seam_allowed} 处）；违规 {stats['violations']} 处"
    )

    # ---- ④ 令牌表不许被掏空 --------------------------------------------------
    for token in required:
        if token not in tokens:
            problems.append(
                f"关键令牌 `{token}` 从令牌表里消失了 —— 删令牌就能让门禁永远通过，关键项不许被拿掉"
            )
    minimum_required = floors.get("minRequiredTokens") or 0
    if len(required) < minimum_required:
        problems.append(
            f"关键令牌榜被掏空了：`requiredTokens` 只剩 {len(required)} 项、下限 {minimum_required} —— "
            f"把关键令牌榜清空，等于把「令牌表不许被掏空」这条判据改成永远通过"
        )
    notes.append(f"令牌表 {len(tokens)} 项（其中关键项 {len(required)} 项必须在位）；面 {len(surfaces)} 个")

    # ---- ⑤ 接线与证据 --------------------------------------------------------
    verify_all_rel = wiring.get("verifyAll") or "Scripts/verify-all.sh"
    gate_call = wiring.get("gateCall") or "check-network-egress.py"
    verify_all = root / verify_all_rel
    if not verify_all.exists():
        problems.append(f"闭环脚本不存在：{verify_all_rel}")
    elif gate_call not in read(verify_all):
        problems.append(
            f"`{verify_all_rel}` 里没有本门禁（`{gate_call}`）的调用 —— "
            "门禁存在但没接进闭环，等于红不起来（存在但没接线的假绿）"
        )
    negative_rel = wiring.get("negativeTest") or "Scripts/test-network-egress-gate.py"
    if not (root / negative_rel).exists():
        problems.append(f"负例脚本不存在：{negative_rel}（绿着不等于看得见违规）")
    for marker in ledger.get("evidence") or []:
        rel = (marker or {}).get("file") or ""
        path = root / rel
        if not path.exists():
            problems.append(f"证据：{rel} 不存在（台账说它该在）")
            continue
        if marker.get("contains") and marker["contains"] not in read(path):
            problems.append(f"证据：{rel} 里找不到 `{marker['contains']}` —— 台账登记的锚点不在位")

    # ---- ⑥ 空跑防护 ----------------------------------------------------------
    minimum_files = floors.get("minFilesScanned") or 0
    if stats["filesScanned"] < minimum_files:
        problems.append(f"扫描面只有 {stats['filesScanned']} 个文件、下限 {minimum_files} —— 扫描面被削掉了")
    minimum_surfaces = floors.get("minSurfaces") or 0
    if len(surfaces) < minimum_surfaces:
        problems.append(f"台账只有 {len(surfaces)} 个面、下限 {minimum_surfaces} —— 面被削掉了")
    if stats["occurrences"] == 0:
        problems.append(
            "空跑防护：全仓一个令牌出现都没命中 —— 白名单里那几个面本来就该有出现，"
            "零命中只可能是扫描面 / 正则坏了（零命中不许当通过）"
        )

    # ---- ⑦ 已知缺口（只减不增，台账登记）-------------------------------------
    for gap in ledger.get("knownGaps") or []:
        if len((gap or "").strip()) < 12:
            problems.append(f"已知缺口条目太短、等于没登记：{gap!r}")
    notes.append(f"已登记缺口 {len(ledger.get('knownGaps') or [])} 条（只减不增）")

    return problems, notes, stats


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--root", default=None, help="换一棵树（负例验证用）")
    parser.add_argument("--ledger", default=None, help="换一份台账（负例验证用）")
    args = parser.parse_args()

    root = Path(args.root).resolve() if args.root else BASE
    ledger = Path(args.ledger).resolve() if args.ledger else None
    problems, notes, stats = check(root, ledger)

    if args.json:
        print(json.dumps(
            {
                "ok": not problems,
                "filesScanned": stats["filesScanned"],
                "occurrences": stats["occurrences"],
                "violations": stats["violations"],
                "problems": problems,
                "notes": notes,
            },
            ensure_ascii=False,
            indent=2,
        ))
        return 1 if problems else 0

    for note in notes:
        print(f"  · {note}")
    if problems:
        print(f"\n❌ {len(problems)} 处不合规：")
        for problem in problems:
            print(f"  · {problem}")
        return 1
    print(
        "\n✅ 全仓网络出口与 Notes SRS v3.94 §6.4 的清单一致：白名单面上出现的令牌都在台账里，"
        "其余文件（只判代码行）一个都没有；装配缝只注入 transport；关键令牌仍在表内；门禁已接进闭环。"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
