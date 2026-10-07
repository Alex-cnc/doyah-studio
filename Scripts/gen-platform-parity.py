#!/usr/bin/env python3
"""生成《需求规范书》§10.10 的「平台等价矩阵」，并校验 `Docs/平台实现状态.json` 台账。

为什么要机械生成（而不是手写几张表）：
    手写的多平台状态表**必然漂移** —— 一边改了另一边忘了改，而且没人会发现。
    本工程已经有这条纪律（"能力状态不手工维护、一律由状态列派生"），这里把它推到多平台：
    · macOS 状态：取自 §10.1 需求索引（**基线 / 单一事实来源**，不由本脚本维护，
      **也不许在台账里覆盖** —— 两个来源就是两个真相）；
    · 其他平台状态：取自 `Docs/平台实现状态.json` 的 `platforms.<名>.overrides`（默认 ⬜）；
    · 表格由本脚本重写，位置由 §10.10 里的 BEGIN/END 标记夹住。

    **只读指定的两个区段**（索引取 §10.1、摘要取 §3/§4 正文）：否则本脚本会把自己刚写进 §10.10
    的表（同样是多列）当成索引行，于是"生成 → 校验"不一致（自吞自己的输出）。第一次就是这么错的。

2026-09-27（队列 L-26，Windows 开工第一步）三处改动：
    ① **列由台账里的平台表决定**，不再写死两列 —— 加一列的成本必须接近于零，否则
       「Windows 与 macOS 完全一致」这条口径活不过半年（它现在能站住的地方就是这张表 + §10.9，
       见 `Docs/design/Windows-完全一致-口径变更与影响-20260926.md` §5 第 1 步）；
    ② **台账校验**：编号写错 / 状态取值非法 / 平台缺 `label`·`role`·`owner` /
       macOS 混进台账 / `notPlatforms` 缺理由 / 顶层键拼错 —— 当场报红并点名。
       此前这些错**全都静默通过**，症状只是一整列 ⬜（"没人报红"比"报错"危险）；
    ③ `--check` 不再只说"请重跑"：**指出第一处不一致的行号与两侧内容**；
       `--self-test` = 上面这些判据自己的证据（负例在临时目录里写坏，真仓库一个字节不动）。

用法：
    python3 Scripts/gen-platform-parity.py             # 重写表格
    python3 Scripts/gen-platform-parity.py --check     # 只检查是否与现状一致（闭环第 7 项）
    python3 Scripts/gen-platform-parity.py --self-test # 门禁自检（11 例负例）
    DOYAH_ROOT=<别的工程根> python3 …                  # 换工程根（`--self-test` 用）
"""

from __future__ import annotations

import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(os.environ.get("DOYAH_ROOT", "."))
SRS = ROOT / "Docs/需求规范书.md"
STATUS = ROOT / "Docs/平台实现状态.json"
SCRIPT = pathlib.Path(__file__).resolve()

BEGIN = "<!-- BEGIN platform-parity -->"
END = "<!-- END platform-parity -->"
BLOCK_COMMENT_RE = re.compile(r"<!--.*?-->", re.S)

ALLOWED_STATUS = ("✅", "🟡", "⬜")
LEDGER_TOP_KEYS = {"_comment", "default", "platforms", "notPlatforms"}
PLATFORM_KEYS = {"label", "role", "owner", "overrides"}

DOMAIN_LABEL = {
    "FR-CONN": "连接与凭据",
    "FR-EDIT": "SQL 编辑与执行",
    "FR-EXEC": "执行与事务",
    "FR-META": "对象浏览与元数据",
    "FR-RES": "结果集与导出",
    "FR-DATA": "数据编辑与写回",
    "FR-DDL": "表结构与 DDL",
    "FR-DIAG": "性能与诊断",
    "FR-SESS": "会话与服务器管理",
    "FR-IO": "导入导出与备份",
    "FR-DRV": "驱动与方言兼容",
    "FR-BLD": "构建与工具链",
    "FR-CLI": "命令行",
    "FR-AI": "AI 智能体",
    "FR-PLUG": "插件装配（宿主侧）",
}


class LedgerError(Exception):
    """台账不合规（一次把所有问题列全，而不是只报第一个）。"""

    def __init__(self, problems: list[str]) -> None:
        super().__init__("；".join(problems))
        self.problems = problems


def cells(line: str) -> list[str]:
    text = line.strip()
    if text.startswith("|"):
        text = text[1:]
    if text.endswith("|"):
        text = text[:-1]
    return [part.strip() for part in text.split("|")]


def clean(text: str) -> str:
    text = re.sub(r"\*\*(.+?)\*\*", r"\1", text)
    text = text.replace("`", "")
    return re.sub(r"\s+", " ", text).strip()


def extract_block(text: str) -> str | None:
    """取 BEGIN/END 之间的派生区块正文（找不到标记 = None）。"""
    if BEGIN not in text or END not in text:
        return None
    return text.split(BEGIN, 1)[1].split(END, 1)[0]


def normalize_block(block: str) -> str:
    """把派生区块归一成**内容**（供 `--check` 比对）。

    依据 = 提案 0007 建议①（2026-10-07 采纳 · 前门 `T-20261007-013` §三）：§10.10 是本脚本
    重写的**派生区块**，人写进去的 `<!-- contract-change：… -->`、以及注释被摘掉后留下的空白，
    都**不是内容** —— 旧实现逐字节比 ⇒ 对侧一注记即恒红（`G-62` 的根因）。三步：
    ① 摘掉 HTML 注释；② 整行只剩注释 ⇒ 整行丢弃（派生区块里本没有这一行）；
    ③ 行内空白折叠 + 去行尾。只在 BEGIN/END **之间**生效，区块外一字不动。
    """
    out: list[str] = []
    for line in block.splitlines():
        if "<!--" in line:
            line = BLOCK_COMMENT_RE.sub("", line)
            if line.strip() == "":
                continue
        out.append(re.sub(r"[ \t]+", " ", line).rstrip())
    while out and out[0] == "":
        out.pop(0)
    while out and out[-1] == "":
        out.pop()
    return "\n".join(out)


def load_rows() -> list[tuple[str, str, str]]:
    """返回 [(编号, macOS 状态, 需求摘要)]（只读 §10.1 索引与 §3/§4 正文）。"""
    lines = SRS.read_text(encoding="utf-8").splitlines()

    def slice_between(start_marker: str, end_marker: str) -> list[str]:
        try:
            start = next(i for i, line in enumerate(lines) if line.startswith(start_marker))
            end = next(i for i, line in enumerate(lines) if i > start and line.startswith(end_marker))
        except StopIteration:
            return []
        return lines[start:end]

    index_lines = slice_between("### 10.1", "### 10.2")
    body_lines = lines[: next((i for i, line in enumerate(lines) if line.startswith("## 10.")), len(lines))]

    index: dict[str, str] = {}
    summaries: dict[str, str] = {}
    for line in index_lines:
        if not line.startswith("|"):
            continue
        row = cells(line)
        if len(row) == 4 and re.match(r"^FR-", row[0]):
            index[row[0]] = row[3]
    for line in body_lines:
        if not line.startswith("|"):
            continue
        row = cells(line)
        if len(row) >= 6 and re.match(r"^FR-", row[0]) and row[0] not in summaries:
            summaries[row[0]] = clean(row[1])

    return [(key, index[key], summaries.get(key, "")) for key in sorted(index)]


def load_ledger(known_ids: set[str]) -> tuple[str, list[dict], list[dict]]:
    """读并校验台账。任何一处不合规都当场列出（`LedgerError`）。"""
    if not STATUS.exists():
        raise LedgerError([f"{STATUS} 不存在（平台状态没有登记处，等价矩阵就无从判定）"])
    try:
        payload = json.loads(STATUS.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise LedgerError([f"{STATUS} 不是合法 JSON：{error}"]) from error
    if not isinstance(payload, dict):
        raise LedgerError([f"{STATUS} 顶层必须是对象"])

    problems: list[str] = []
    unknown_top = sorted(set(payload) - LEDGER_TOP_KEYS)
    if unknown_top:
        problems.append(
            f"未知的顶层键 {unknown_top}（认识的只有 {sorted(LEDGER_TOP_KEYS)}）—— 键名拼错会让整块配置静默失效"
        )

    default = payload.get("default", "⬜")
    if default not in ALLOWED_STATUS:
        problems.append(f"default 取值非法：{default!r}（只认 {list(ALLOWED_STATUS)}）")

    raw_platforms = payload.get("platforms")
    if not isinstance(raw_platforms, dict) or not raw_platforms:
        problems.append("platforms 必须是「至少一个平台」的对象 —— 没有平台就没有矩阵")
        raw_platforms = {}

    platforms: list[dict] = []
    for name, entry in raw_platforms.items():
        if not re.fullmatch(r"[a-z][a-z0-9_-]*", name):
            problems.append(f"平台名 {name!r} 不合规（小写字母开头，只用小写字母 / 数字 / `_` / `-`）")
            continue
        if name == "macos":
            problems.append(
                "macOS 不许进台账：它是基线，状态来自 §10.1 索引 —— 两个来源就是两个真相（要改 macOS 状态就去改需求条目）"
            )
            continue
        if not isinstance(entry, dict):
            problems.append(f"platforms.{name} 必须是对象")
            continue
        unknown = sorted(set(entry) - PLATFORM_KEYS)
        if unknown:
            problems.append(f"platforms.{name} 有多余键 {unknown}（认识的只有 {sorted(PLATFORM_KEYS)}）")
        for field in ("label", "role", "owner"):
            value = entry.get(field)
            if not isinstance(value, str) or not value.strip():
                problems.append(
                    f"platforms.{name}.{field} 缺失或为空 —— 表头要写清这列是谁在维护、什么口径"
                )
        overrides = entry.get("overrides", {})
        if not isinstance(overrides, dict):
            problems.append(f"platforms.{name}.overrides 必须是对象（编号 → 状态）")
            overrides = {}
        accepted: dict[str, str] = {}
        for identifier, status in overrides.items():
            if identifier not in known_ids:
                problems.append(
                    f"platforms.{name}.overrides 里的编号 {identifier} 在 §10.1 索引里不存在"
                    "（编号写错 = 这条状态静默丢掉、表上仍是一列 ⬜）"
                )
                continue
            if status not in ALLOWED_STATUS:
                problems.append(
                    f"platforms.{name}.overrides[{identifier}] 取值非法：{status!r}（只认 {list(ALLOWED_STATUS)}）"
                )
                continue
            accepted[identifier] = status
        platforms.append(
            {
                "name": name,
                "label": entry.get("label", name),
                "role": entry.get("role", ""),
                "owner": entry.get("owner", ""),
                "overrides": accepted,
            }
        )

    raw_not = payload.get("notPlatforms", {})
    if not isinstance(raw_not, dict):
        problems.append("notPlatforms 必须是对象")
        raw_not = {}
    not_platforms: list[dict] = []
    for name, entry in raw_not.items():
        if name in raw_platforms:
            problems.append(f"{name} 同时出现在 platforms 与 notPlatforms —— 自相矛盾")
            continue
        if not isinstance(entry, dict) or not str(entry.get("why", "")).strip():
            problems.append(
                f"notPlatforms.{name}.why 必须写明非空理由 —— 不设列的理由要能被后人读懂，"
                "否则它迟早被当成漏掉的一列补上"
            )
            continue
        not_platforms.append({"name": name, "label": entry.get("label", name), "why": entry["why"]})

    if problems:
        raise LedgerError(problems)
    return default, platforms, not_platforms


def render(
    rows: list[tuple[str, str, str]],
    platforms: list[dict],
    default: str,
    not_platforms: list[dict],
) -> str:
    def group_of(identifier: str) -> str:
        parts = identifier.split("-")
        return "-".join(parts[:2])

    order: list[str] = []
    for identifier, _, _ in rows:
        group = group_of(identifier)
        if group not in order:
            order.append(group)

    labels = " / ".join(platform["label"] for platform in platforms)
    out: list[str] = []
    out.append(
        f"> 共 {len(rows)} 条功能需求。**macOS** 状态取自 §10.1 索引（**基线，唯一来源**，不由本脚本维护）。"
    )
    for platform in platforms:
        out.append(
            f"> **{platform['label']}** 状态取自 `Docs/平台实现状态.json` → "
            f"`platforms.{platform['name']}.overrides`（{platform['role']}；维护者：{platform['owner']}）。"
        )
    out.append(f"> 未在台账里逐条登记的，一律按 `{default}` 记。")
    out.append(
        "> `⚠️` = 与该需求的 macOS 基线不一致（**未在 §10.9 登记的平台差异一律视为「必须一致」**，见 §0.8 R2）。"
    )
    out.append(f"> 平台列：{labels}（表由 `Scripts/gen-platform-parity.py` 重写，`--check` 判定漂移）。")
    for platform in not_platforms:
        out.append(f"> **{platform['label']}不设列**：{platform['why']}")
    out.append("")
    for group in order:
        members = [(i, mac, text) for i, mac, text in rows if group_of(i) == group]
        aligned = " / ".join(
            f"{platform['label']} "
            + str(sum(1 for i, mac, _ in members if platform["overrides"].get(i, default) == mac))
            for platform in platforms
        )
        out.append(f"**{DOMAIN_LABEL.get(group, group)}**（{len(members)} 条。与 macOS 基线一致：{aligned} 条）")
        out.append("")
        header = " | ".join(["编号", "需求摘要", "macOS"] + [platform["label"] for platform in platforms])
        out.append(f"| {header} |")
        out.append("|" + "---|" * (3 + len(platforms)))
        for identifier, mac, text in members:
            row = [identifier, text[:52] + ("…" if len(text) > 52 else ""), mac]
            for platform in platforms:
                status = platform["overrides"].get(identifier, default)
                row.append(status if status == mac else f"{status} ⚠️")
            out.append("| " + " | ".join(row) + " |")
        out.append("")
    return "\n".join(out).rstrip() + "\n"


def rebuild(rows: list[tuple[str, str, str]], platforms: list[dict], default: str, not_platforms: list[dict]) -> str:
    """返回把 §10.10 标记区间替换成最新表格后的整篇文档文本（找不到标记则抛错）。"""
    text = SRS.read_text(encoding="utf-8")
    if BEGIN not in text or END not in text:
        raise LedgerError([f"{SRS} 里找不到 {BEGIN} / {END} 标记（表格位置由它们夹住）"])
    table = render(rows, platforms, default, not_platforms)
    head, rest = text.split(BEGIN, 1)
    _, tail = rest.split(END, 1)
    return f"{head}{BEGIN}\n{table}{END}{tail}"


def first_differences(current: str, updated: str, limit: int = 3) -> list[tuple[int, str, str]]:
    old = current.splitlines()
    new = updated.splitlines()
    out: list[tuple[int, str, str]] = []
    for index in range(max(len(old), len(new))):
        left = old[index] if index < len(old) else "<缺行>"
        right = new[index] if index < len(new) else "<缺行>"
        if left != right:
            out.append((index + 1, left, right))
            if len(out) >= limit:
                break
    return out


def digest(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


# ── 自检：判据自己的证据 ──────────────────────────────────────────────────────

def _ledger_edit(mutator) -> object:
    def setup(root: pathlib.Path) -> None:
        path = root / "Docs/平台实现状态.json"
        payload = json.loads(path.read_text(encoding="utf-8"))
        mutator(payload)
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    return setup


def _must(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def build_cases() -> list[dict]:
    def set_windows(payload: dict) -> None:
        payload["platforms"]["windows"]["overrides"]["FR-CONN-01"] = "✅"

    def typo_id(payload: dict) -> None:
        payload["platforms"]["windows"]["overrides"]["FR-CONN-999"] = "✅"

    def bad_status(payload: dict) -> None:
        payload["platforms"]["windows"]["overrides"]["FR-CONN-01"] = "🟢"

    def drop_owner(payload: dict) -> None:
        payload["platforms"]["windows"].pop("owner")

    def add_macos(payload: dict) -> None:
        payload["platforms"]["macos"] = {
            "label": "macOS",
            "role": "基线",
            "owner": "大河马",
            "overrides": {},
        }

    def empty_why(payload: dict) -> None:
        payload["notPlatforms"]["mobile"]["why"] = "   "

    def typo_top_key(payload: dict) -> None:
        payload["platform"] = payload.pop("platforms")

    def drop_column(root: pathlib.Path) -> None:
        """只改 §10.10 标记区间里的表（正文定义行不是本门禁的判据面）。"""
        path = root / "Docs/需求规范书.md"
        text = path.read_text(encoding="utf-8")
        head, rest = text.split(BEGIN, 1)
        block, tail = rest.split(END, 1)
        lines = block.splitlines()
        for index, line in enumerate(lines):
            if line.startswith("| FR-"):
                kept = line.strip().strip("|").split("|")[:-1]
                lines[index] = "|" + "|".join(kept) + "|"
                break
        else:
            raise AssertionError("§10.10 表里没有 FR 行，改坏无从下手")
        path.write_text(f"{head}{BEGIN}\n" + "\n".join(lines) + f"{END}{tail}", encoding="utf-8")

    def drop_marker(root: pathlib.Path) -> None:
        path = root / "Docs/需求规范书.md"
        path.write_text(path.read_text(encoding="utf-8").replace(BEGIN, "", 1), encoding="utf-8")

    def windows_snapshot(root: pathlib.Path) -> None:
        """正向：台账里的 ✅ 必须真的到表上，且分域计数跟着走。"""
        text = (root / "Docs/需求规范书.md").read_text(encoding="utf-8")
        block = text.split(BEGIN, 1)[1].split(END, 1)[0]
        row = re.search(r"^\| FR-CONN-01 \|.*$", block, re.MULTILINE)
        if row is None:
            raise AssertionError("§10.10 表里找不到 FR-CONN-01 行")
        row_cells = [cell.strip() for cell in row.group(0).strip().strip("|").split("|")]
        _must(len(row_cells) == 5, f"FR-CONN-01 行不是 5 列：{row_cells}")
        _must(row_cells[-1] == "✅", f"Windows 列没吃到台账里的 ✅：{row_cells[-1]!r}")
        mac = row_cells[2]
        expected = 1 if mac == "✅" else 0
        header = re.search(r"^\*\*连接与凭据\*\*（.*$", block, re.MULTILINE)
        if header is None:
            raise AssertionError("找不到「连接与凭据」分域行")
        _must(
            f"Windows {expected} 条" in header.group(0),
            f"分域对齐计数没跟上（macOS 基线 {mac} ⇒ 期望 Windows {expected} 条）：{header.group(0)}",
        )
        _must("移动端（鸿蒙 / 安卓 / iOS）不设列" in text, "移动端不设列的理由没写进表头说明")
        _must("| 编号 | 需求摘要 | macOS | Linux | Windows |" in block, "表头没出现三平台列")
        odd = [line for line in block.splitlines() if line.startswith("| FR-") and line.count("|") != 6]
        _must(not odd, f"§10.10 里有列数不齐的行：{odd[:2]}")

    return [
        {
            "name": "① 基线：生成一次后 --check 必须一致",
            "steps": [(["gen"], 0, "已重写 §10.10"), (["--check"], 0, "一致")],
        },
        {
            "name": "② 台账改了没重生成 ⇒ --check 报红并指出行号",
            "setup": _ledger_edit(set_windows),
            "steps": [(["--check"], 1, "不一致")],
        },
        {
            "name": "③ 重生成后 Windows 状态到表上 + 计数与列数自洽",
            "setup": _ledger_edit(set_windows),
            "steps": [(["gen"], 0, "Windows 1 条")],
            "inspect": windows_snapshot,
        },
        {
            "name": "④ 台账编号写错 ⇒ 点名报红（旧版静默成 ⬜）",
            "setup": _ledger_edit(typo_id),
            "steps": [(["gen"], 1, "FR-CONN-999")],
        },
        {
            "name": "⑤ 状态取值非法 ⇒ 点名报红",
            "setup": _ledger_edit(bad_status),
            "steps": [(["gen"], 1, "🟢")],
        },
        {
            "name": "⑥ 平台缺 owner ⇒ 报红（表头要写清维护者）",
            "setup": _ledger_edit(drop_owner),
            "steps": [(["gen"], 1, "owner")],
        },
        {
            "name": "⑦ macOS 混进台账 ⇒ 报红（不许两个真相）",
            "setup": _ledger_edit(add_macos),
            "steps": [(["gen"], 1, "macOS 不许进台账")],
        },
        {
            "name": "⑧ notPlatforms 缺理由 ⇒ 报红",
            "setup": _ledger_edit(empty_why),
            "steps": [(["gen"], 1, "why")],
        },
        {
            "name": "⑨ 顶层键拼错 ⇒ 报红（否则整块平台静默消失）",
            "setup": _ledger_edit(typo_top_key),
            "steps": [(["gen"], 1, "未知的顶层键")],
        },
        {
            "name": "⑩ 表被手工改坏（少一列）⇒ --check 报红",
            "setup": drop_column,
            "steps": [(["--check"], 1, "不一致")],
        },
        {
            "name": "⑪ 标记被删 ⇒ 报红并点名文件",
            "setup": drop_marker,
            "steps": [(["--check"], 1, "找不到")],
        },
    ]


def run_script(root: pathlib.Path, argv: list[str]) -> subprocess.CompletedProcess:
    environment = dict(os.environ, DOYAH_ROOT=str(root))
    return subprocess.run(
        [sys.executable, str(SCRIPT), *argv],
        capture_output=True,
        text=True,
        env=environment,
        cwd=str(root),
    )


def self_test() -> int:
    if not SRS.exists() or not STATUS.exists():
        print(f"❌ 自检需要真实的 {SRS} 与 {STATUS}")
        return 1
    before = {path: digest(path) for path in (SRS, STATUS)}

    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="parity-selftest-") as tmp:
        base = pathlib.Path(tmp) / "base"
        (base / "Docs").mkdir(parents=True)
        for path in (SRS, STATUS):
            shutil.copy2(path, base / "Docs" / path.name)

        cases = build_cases()
        for index, case in enumerate(cases, 1):
            work = pathlib.Path(tmp) / f"case{index:02d}"
            shutil.copytree(base, work)
            setup = case.get("setup")
            if setup is not None:
                setup(work)
            for argv, want_rc, want_text in case["steps"]:
                result = run_script(work, argv)
                combined = f"{result.stdout}\n{result.stderr}"
                if result.returncode != want_rc:
                    failures.append(
                        f"{case['name']}｜{' '.join(argv)} 期望退出码 {want_rc}、实际 {result.returncode}"
                        f"（stdout: {result.stdout.strip()[:200]}）"
                    )
                    break
                if want_text and want_text not in combined:
                    failures.append(
                        f"{case['name']}｜{' '.join(argv)} 退出码对，但输出里没有 {want_text!r}"
                        f"（stdout: {result.stdout.strip()[:200]}）"
                    )
                    break
            else:
                inspect = case.get("inspect")
                if inspect is not None:
                    try:
                        inspect(work)
                    except AssertionError as error:
                        failures.append(f"{case['name']}｜{error}")

    after = {path: digest(path) for path in (SRS, STATUS)}
    if before != after:
        failures.append("自检动了真仓库的文件（写坏必须只发生在临时副本上）")

    if failures:
        print(f"❌ 平台等价矩阵门禁自检未通过（{len(build_cases())} 例里 {len(failures)} 例不符预期）：")
        for failure in failures:
            print(f"   · {failure}")
        return 1
    print(f"✅ 平台等价矩阵门禁自检通过（{len(build_cases())}/{len(build_cases())}；真仓库两份文件逐字节未变）")
    return 0


def main() -> int:
    arguments = set(sys.argv[1:])
    if "--self-test" in arguments:
        return self_test()

    check_only = "--check" in arguments

    try:
        rows = load_rows()
        known_ids = {identifier for identifier, _, _ in rows}
        default, platforms, not_platforms = load_ledger(known_ids)
        updated = rebuild(rows, platforms, default, not_platforms)
    except LedgerError as error:
        print(f"❌ 平台等价矩阵台账不合规（{len(error.problems)} 处）：")
        for problem in error.problems:
            print(f"   · {problem}")
        print(f"   台账：{STATUS}")
        return 1

    if check_only:
        current = SRS.read_text(encoding="utf-8")
        if updated == current:
            print(f"✅ 平台等价矩阵与现状一致（{len(rows)} 条；平台列 {len(platforms) + 1}）")
            return 0
        current_block = extract_block(current)
        updated_block = extract_block(updated)
        if (
            current_block is not None
            and updated_block is not None
            and normalize_block(current_block) == normalize_block(updated_block)
        ):
            print(
                f"✅ 平台等价矩阵与现状一致（{len(rows)} 条；平台列 {len(platforms) + 1}；"
                "区块内 HTML 注释与注释残留空白按提案 0007 建议① 归一后无实质差异）"
            )
            return 0
        print("❌ 平台等价矩阵与现状不一致：")
        for line_number, left, right in first_differences(current, updated):
            print(f"   :{line_number}  现状：{left[:120]}")
            print(f"   :{line_number}  应为：{right[:120]}")
        print("   请运行 python3 Scripts/gen-platform-parity.py 重写")
        return 1

    SRS.write_text(updated, encoding="utf-8")
    detail = "、".join(f"{platform['label']} {len(platform['overrides'])} 条" for platform in platforms)
    print(
        f"✅ 已重写 §10.10 平台等价矩阵（{len(rows)} 条；"
        f"平台列 {'/'.join(platform['label'] for platform in platforms)}；台账显式状态 {detail}）"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
