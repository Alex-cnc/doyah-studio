#!/usr/bin/env python3
"""「空数据时按钮到底怎么表现」的门禁（队列 L-50）。

## 这一项在守什么

产品里有三种**并存**的处理方式，从前没有任何门禁看着它们：

| 形状 | 例子 | 用户看到 |
|---|---|---|
| **灰着** | 外发日志的「清空」`​.disabled(appState.egressEntries.isEmpty)` | 一眼看出"现在没事可做" |
| **可点 + 给一句理由** | 外发日志的「导出」`​guard … else { egressError = L(.egressExportEmpty) }` | 点得到，并被告知为什么 |
| **静默无反应**（缺陷） | 笔记编辑器的「保存」（2026-09-26 读图抓到） | 按钮满色可点，点下去**什么都不发生** ⇒ 用户以为按钮坏了 |

前两种都是**有意**的（导出那一档尤其：命令行旁边写了"这条是有意设计，不是缺陷"）；
第三种是**没人看着**那一档 —— 它不是"设计选择"，而是"视图侧忘了写处置"。

## 判据（四条，机械可查）

A **双向对账**：`App/AppState.swift` 里每条「内容为空」守卫（条件里出现 `isEmpty`，
或引用了台账登记的**判据属性**）必须逐条登记；台账里的条目若已不在源码里 ⇒ **陈旧判红**。
   ⇒ 新增一处"空就早退"当场被问："这一处是灰着、给理由，还是够不着按钮？"

B **`view-disabled` 的判据必须唯一出处**（L-50 的修法形状）：判据属性全局只定义一次；
  `AppState` 里那条守卫必须**用**这个属性；指定视图里必须真的 `.disabled(` 它；
  **谓词体引用的存储属性不许再出现在视图文件里** —— 两处各写一遍正是 L-50 的病根。

C **`view-disabled-local`**（判据属性住在视图里，如 `SaveQuerySheet.trimmedName`）：
  登记的字面锚点必须还在那个视图文件里（锚点陈旧 = 处置被删）。

D **`explain`**：守卫体里必须真的有一句给用户的话（`= L(…)` / `= ErrorPresenter…` /
  `throw …` / 赋值给 `*Message`、`*Error`）。挂了"给理由"的名、体里却只 `return` ⇒ 红。

E **空跑防护**：扫到 0 条守卫、台账 0 条、`App/Views/` 一个文件都没有、点名的视图不存在 ⇒ 红。

## 做不到什么（如实写）

`form = "internal"` 那一档是**人判登记 + 理由必填**，门禁不判它的语义：区分"按钮的前置条件"
与"函数内部的解析早退"（如 `erDiagram` 里逐行取列名）需要语义判断 —— 假装判住比不判更糟。
这一档的门禁价值在于**棘轮**：每新增一处空守卫都必须被有意识地归类一次。

## 用法

    python3 Scripts/check-empty-action-buttons.py                     # 判据（真仓库）
    python3 Scripts/check-empty-action-buttons.py --self-test         # 负例（只在临时副本上写坏）
    python3 Scripts/check-empty-action-buttons.py --dump-keys         # 只打印扫到的守卫键

台账：`Scripts/empty-action-button-dispositions.json`
负例：`Scripts/test-empty-action-buttons.py`（11 例）
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parent.parent
STATE_FILE = "App/AppState.swift"
VIEW_DIR = "App/Views"
LEDGER_PATH = "Scripts/empty-action-button-dispositions.json"

FORMS = ("view-disabled", "view-disabled-local", "explain", "internal")

FUNC_RE = re.compile(r"^\s*(?:@\w+\s+)*(?:private\s+|static\s+|public\s+|internal\s+)*func\s+(\w+)")
GUARD_RE = re.compile(r"^\s*guard\b(?P<cond>.*?)\belse\b(?P<rest>.*)$")

# 「给用户一句人话」的机械形状：本地化取值 / 可读化入口 / 抛出（错误会被人接住）/ 赋给消息类属性。
MESSAGE_ASSIGN_RE = re.compile(
    r"(=\s*L\(|=\s*ErrorPresenter|=\s*CLIFailureText|=\s*LocalizationManager"
    r"|\bthrow\b"
    r"|\b(?:statusMessage|errorMessage|failureReason)\s*="
    r"|\b\w*(?:Message|Error|Notice)\s*=\s*\S)"
)


def norm_condition(text: str) -> str:
    """守卫条件的归一化：压空白 + 去掉尾部残留的 `{`。

    台账与源码各写一遍这个条件串，归一化口径必须**只有一处**（这个函数）——
    否则门禁自己就会因为空格差异误报（L-59 第 58 轮踩过一次，见 AGENT-SPEC §9）。
    """
    collapsed = re.sub(r"\s+", " ", text).strip()
    collapsed = collapsed.rstrip("{").strip()
    return collapsed


@dataclass
class Sighting:
    """源码里扫到的一处「内容为空」守卫。"""

    func: str
    line: int
    condition: str
    body: str

    @property
    def key(self) -> tuple[str, str]:
        return (self.func, self.condition)


def _func_owner(lines: list[str], index: int) -> str:
    owner = ""
    for i in range(index + 1):
        match = FUNC_RE.match(lines[i])
        if match:
            owner = match.group(1)
    return owner


def _guard_block(lines: list[str], index: int, max_lines: int = 10) -> str:
    chunk: list[str] = []
    depth = 0
    started = False
    for i in range(index, min(index + max_lines, len(lines))):
        line = lines[i]
        chunk.append(line.strip())
        depth += line.count("{") - line.count("}")
        if "{" in line:
            started = True
        if started and depth <= 0:
            break
    return "\n".join(chunk)


def scan_guards(repo: Path, predicates: set[str]) -> list[Sighting]:
    """扫 `App/AppState.swift`：条件含 `isEmpty`，或引用了登记的判据属性。

    只认**单行到 `else`** 的守卫（行内 `else`）—— 多行条件不覆盖，这是有意的窄口径：
    宽口径要么靠括号配对（脆）、要么靠语法树（本工程没有 Swift 解析器）。
    """
    path = repo / STATE_FILE
    lines = path.read_text(encoding="utf-8").split("\n")
    sightings: list[Sighting] = []
    for i, line in enumerate(lines):
        stripped = line.strip()
        if not stripped.startswith("guard"):
            continue
        match = GUARD_RE.match(line)
        if not match:
            continue
        condition = norm_condition(match.group("cond"))
        if not condition:
            continue
        interesting = "isEmpty" in condition or any(
            re.search(r"\b" + re.escape(name) + r"\b", condition) for name in predicates
        )
        if not interesting:
            continue
        sightings.append(
            Sighting(
                func=_func_owner(lines, i),
                line=i + 1,
                condition=condition,
                body=_guard_block(lines, i),
            )
        )
    return sightings


def view_files(repo: Path) -> list[Path]:
    return sorted((repo / VIEW_DIR).rglob("*.swift"))


class Checker:
    def __init__(self, repo: Path) -> None:
        self.repo = repo
        self.errors: list[str] = []
        self.notes: list[str] = []
        self.ledger = self._load_ledger()
        self.entries: list[dict] = list(self.ledger.get("entries", []))
        self.predicates = {
            entry["predicate"] for entry in self.entries if entry.get("predicate")
        }
        self.sightings = scan_guards(repo, self.predicates) if self.ledger else []

    def _load_ledger(self) -> dict:
        path = self.repo / LEDGER_PATH
        if not path.exists():
            return {}
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            self.errors.append(f"台账 `{LEDGER_PATH}` 不是合法 JSON：{exc}")
            return {}

    # ---------- A 双向对账 ----------

    def check_registry(self) -> None:
        if not self.ledger:
            return
        scanned = {sighting.key for sighting in self.sightings}
        registered = {
            (entry.get("func", ""), norm_condition(entry.get("guard", ""))) for entry in self.entries
        }
        missing = sorted(scanned - registered)
        for func, condition in missing:
            line = next(s.line for s in self.sightings if s.key == (func, condition))
            self.errors.append(
                f"未登记的空守卫：`{STATE_FILE}:{line}` `{func}` 的 `guard {condition}` "
                "—— 是灰着、给理由，还是够不着按钮？逐条登记进台账"
            )
        stale = sorted(registered - scanned)
        for func, condition in stale:
            self.errors.append(
                f"台账里有陈旧条目：`{func}` 的 `guard {condition}` 在 `{STATE_FILE}` 里已经找不到"
                "（改形状或销账都要动台账，别让它烂在原地）"
            )
        self.notes.append(f"守卫 {len(scanned)} 条 / 台账 {len(registered)} 条")

    # ---------- B / C / D 逐条处置 ----------

    def check_entry(self, entry: dict) -> None:
        func = entry.get("func", "")
        condition = norm_condition(entry.get("guard", ""))
        form = entry.get("form", "")
        if form not in FORMS:
            self.errors.append(f"`{func}` 的 form `{form}` 不在词表 {FORMS}")
            return
        if not entry.get("reason"):
            self.errors.append(f"`{func}`（{form}）必须写理由 —— 处置没理由就只是一句声明")
        sighting = next((s for s in self.sightings if s.key == (func, condition)), None)

        if form == "explain":
            if sighting and not MESSAGE_ASSIGN_RE.search(sighting.body):
                self.errors.append(
                    f"`{func}` 登记为「可点 + 给一句理由」，但那句守卫体里没有给用户的话"
                    f"（`{STATE_FILE}:{sighting.line}`）—— 要么补话，要么改登记"
                )
            return

        if form == "internal":
            return

        view_rel = entry.get("view", "")
        if not view_rel:
            self.errors.append(f"`{func}`（{form}）没写 `view`")
            return
        view_path = self.repo / view_rel
        if not view_path.exists():
            self.errors.append(f"`{func}` 点名的视图不存在：`{view_rel}`")
            return
        view_text = view_path.read_text(encoding="utf-8")

        if form == "view-disabled-local":
            anchor = entry.get("anchor", "")
            if not anchor:
                self.errors.append(f"`{func}`（view-disabled-local）没写 `anchor`")
            elif anchor not in view_text:
                self.errors.append(
                    f"`{func}` 的字面锚点 `{anchor}` 已不在 `{view_rel}` 里"
                    "—— 视图侧的处置被删了（这就是这一档要判住的东西）"
                )
            return

        # form == view-disabled
        predicate = entry.get("predicate", "")
        if not predicate:
            self.errors.append(f"`{func}`（view-disabled）没写 `predicate`")
            return
        definitions = self._predicate_definitions(predicate)
        if len(definitions) != 1:
            where = "、".join(f"`{p}:{n}`" for p, n in definitions) or "一处都没有"
            self.errors.append(
                f"判据属性 `{predicate}` 必须**只定义一次**，实测 {len(definitions)} 处（{where}）"
                "—— 唯一出处是这一档的全部意义"
            )
        if sighting and not re.search(r"\b" + re.escape(predicate) + r"\b", sighting.condition):
            self.errors.append(
                f"`{func}` 的守卫没有走判据属性 `{predicate}`（`{STATE_FILE}:{sighting.line}` "
                f"`guard {sighting.condition}`）—— 守卫与 `.disabled` 必须同一条判断"
            )
        if predicate not in view_text:
            self.errors.append(f"`{view_rel}` 里没有引用判据属性 `{predicate}`（视图侧处置丢了）")
        elif not re.search(r"disabled\([^)]*\b" + re.escape(predicate) + r"\b", view_text):
            self.errors.append(
                f"`{view_rel}` 引用了 `{predicate}`，但没有把它接进 `.disabled(...)`"
            )
        for property_name in self._predicate_properties(predicate):
            if re.search(re.escape(property_name) + r"[^\n]{0,80}?\.isEmpty", view_text):
                self.errors.append(
                    f"`{view_rel}` 在**重新推导**判据（`{property_name}` 后面又跟了 `.isEmpty`）"
                    f"—— 判据 `{predicate}` 是唯一出处，L-50 的病根就是两处各写一遍"
                )

    def _predicate_definitions(self, predicate: str) -> list[tuple[str, int]]:
        pattern = re.compile(r"^\s*(?:private\s+|internal\s+|public\s+)?(?:var|let|func)\s+"
                             + re.escape(predicate) + r"\b")
        hits: list[tuple[str, int]] = []
        for path in [self.repo / STATE_FILE] + [p for p in view_files(self.repo)]:
            if not path.exists():
                continue
            for i, line in enumerate(path.read_text(encoding="utf-8").split("\n")):
                if pattern.match(line):
                    hits.append((path.relative_to(self.repo).as_posix(), i + 1))
        return hits

    def _predicate_properties(self, predicate: str) -> list[str]:
        """判据体里引用到的存储属性名（用来挡「视图再写一遍」）。"""
        path = self.repo / STATE_FILE
        if not path.exists():
            return []
        lines = path.read_text(encoding="utf-8").split("\n")
        start = None
        for i, line in enumerate(lines):
            if re.match(r"^\s*(?:private\s+)?var\s+" + re.escape(predicate) + r"\b", line):
                start = i
                break
        if start is None:
            return []
        body: list[str] = []
        depth = 0
        started = False
        for line in lines[start:start + 12]:
            body.append(line)
            depth += line.count("{") - line.count("}")
            if "{" in line:
                started = True
            if started and depth <= 0:
                break
        text = "\n".join(body)
        names = set(re.findall(r"\b(note\w+|notes\w+)\b", text))
        return sorted(n for n in names if n != predicate)

    # ---------- E 空跑防护 ----------

    def check_not_empty(self) -> None:
        if not self.ledger:
            return
        if not self.entries:
            self.errors.append("台账里一条处置都没有 —— 空台账不是「都合规」")
        if not self.sightings:
            self.errors.append(
                f"在 `{STATE_FILE}` 里一条「内容为空」守卫都没扫到 —— 判据在空跑"
                "（真扫不出来说明解析口径先坏了）"
            )
        if not view_files(self.repo):
            self.errors.append(f"`{VIEW_DIR}` 下一个 `.swift` 都没有 —— 判据在空跑")

    def run(self) -> int:
        if not self.ledger and not self.errors:
            self.errors.append(f"台账 `{LEDGER_PATH}` 不存在")
        self.check_not_empty()
        self.check_registry()
        for entry in self.entries:
            self.check_entry(entry)
        for msg in self.notes:
            print(f"   · {msg}")
        if self.errors:
            print("❌ 空数据按钮的处置对账不通过：")
            for msg in self.errors:
                print(f"   · {msg}")
            return 1
        print(
            f"✅ 空数据按钮处置逐条对账通过（守卫 {len(self.sightings)} 条 / 台账 {len(self.entries)} 条 / "
            f"视图 {len(view_files(self.repo))} 个文件）"
        )
        return 0


def dump_keys(repo: Path) -> int:
    ledger = json.loads((repo / LEDGER_PATH).read_text(encoding="utf-8"))
    predicates = {e["predicate"] for e in ledger.get("entries", []) if e.get("predicate")}
    for sighting in scan_guards(repo, predicates):
        print(f"{sighting.func}\t{sighting.condition}")
    return 0


# --------------------------------------------------------------------------
# 负例：一律在**临时副本**上写坏（真仓库只读；末例核对逐字节未变）
# --------------------------------------------------------------------------


def _fixture(repo: Path, dest: Path) -> None:
    """最小夹具仓：判据只读 `App/`、台账与脚本本身（整仓 16 GB，不能整份拷 ——
    第 59 轮第一版就是这么写的，11 例负例跑到超时）。"""
    dest.mkdir(parents=True, exist_ok=True)
    shutil.copytree(repo / "App", dest / "App", ignore=shutil.ignore_patterns(".build"))
    (dest / "Scripts").mkdir(exist_ok=True)
    shutil.copy2(repo / LEDGER_PATH, dest / LEDGER_PATH)
    shutil.copy2(repo / "Scripts" / "check-empty-action-buttons.py",
                 dest / "Scripts" / "check-empty-action-buttons.py")


def _snapshot(repo: Path) -> dict[str, str]:
    import hashlib

    out: dict[str, str] = {}
    for rel in (STATE_FILE, LEDGER_PATH, "App/Views/NotesPanel.swift", "App/Views/SaveQuerySheet.swift"):
        path = repo / rel
        if path.exists():
            out[rel] = hashlib.sha256(path.read_bytes()).hexdigest()
    return out


def self_test(repo: Path) -> int:
    before = _snapshot(repo)
    failures: list[str] = []
    cases: list[tuple[str, Callable[[Path], "str | None"]]] = []

    def case(label):
        def decorator(fn):
            cases.append((label, fn))
            return fn
        return decorator

    def rewrite(path: Path, old: str, new: str, required: bool = True) -> bool:
        text = path.read_text(encoding="utf-8")
        if old not in text:
            if required:
                raise AssertionError(f"夹具前提不成立：`{path.name}` 里找不到 {old!r}")
            return False
        path.write_text(text.replace(old, new, 1), encoding="utf-8")
        return True

    @case("前提自检：干净副本基线必须绿")
    def _baseline(tmp: Path) -> str | None:
        rc = Checker(tmp).run()
        return None if rc == 0 else f"干净副本竟然判红（rc={rc}）"

    @case("视图侧处置被删（去掉 .disabled）")
    def _drop_disabled(tmp: Path) -> str | None:
        rewrite(tmp / "App/Views/NotesPanel.swift",
                ".disabled(!appState.noteEditorHasContent)", "")
        return None if Checker(tmp).run() == 1 else "视图丢了 .disabled，门禁没说话"

    @case("守卫改回裸判断（判据不再是唯一出处）")
    def _raw_guard(tmp: Path) -> str | None:
        rewrite(tmp / STATE_FILE,
                "guard noteEditorHasContent else { return }",
                "guard !noteEditorTitle.isEmpty || !noteEditorBody.isEmpty else { return }")
        return None if Checker(tmp).run() == 1 else "回到「两处各写一遍」的老形状，门禁没说话"

    @case("新增一处未登记的空守卫（棘轮）")
    def _new_silent_guard(tmp: Path) -> str | None:
        rewrite(tmp / STATE_FILE,
                "    func searchNotes() async {",
                "    func clearNotesQueryAndReload() async {\n"
                "        guard !notesQuery.isEmpty else { return }\n"
                "    }\n\n    func searchNotes() async {")
        return None if Checker(tmp).run() == 1 else "新加的静默空守卫没被登记，门禁没说话"

    @case("台账里的处置改成 explain 但体里没有话")
    def _fake_explain(tmp: Path) -> str | None:
        rewrite(tmp / LEDGER_PATH, '"form": "view-disabled"', '"form": "explain"', required=False)
        text = (tmp / LEDGER_PATH).read_text(encoding="utf-8")
        payload = json.loads(text)
        for entry in payload["entries"]:
            if entry.get("predicate") == "noteEditorHasContent":
                entry["form"] = "explain"
        (tmp / LEDGER_PATH).write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        return None if Checker(tmp).run() == 1 else "挂着「给理由」的名、体里只有 return，门禁没说话"

    @case("explain 的守卫体被改成静默 return")
    def _silenced_explain(tmp: Path) -> str | None:
        rewrite(tmp / STATE_FILE,
                "            egressError = L(.egressExportEmpty)\n            return false",
                "            return false")
        return None if Checker(tmp).run() == 1 else "「给理由」的那句人话被删了，门禁没说话"

    @case("视图本地锚点被删（SaveQuerySheet 不再灰着）")
    def _drop_local_anchor(tmp: Path) -> str | None:
        rewrite(tmp / "App/Views/SaveQuerySheet.swift", ".disabled(trimmedName.isEmpty)", "")
        return None if Checker(tmp).run() == 1 else "视图本地处置被删，门禁没说话"

    @case("判据属性出现第二处定义")
    def _duplicate_predicate(tmp: Path) -> str | None:
        rewrite(tmp / "App/Views/NotesPanel.swift",
                "struct NotesEditorView: View {",
                "struct NotesEditorView: View {\n    var noteEditorHasContent: Bool { true }")
        return None if Checker(tmp).run() == 1 else "判据出现两处定义，门禁没说话"

    @case("视图重新推导判据（唯一出处被破）")
    def _view_recomputes(tmp: Path) -> str | None:
        rewrite(tmp / "App/Views/NotesPanel.swift",
                "    var body: some View {",
                "    private var hasContentAgain: Bool {\n"
                "        !appState.noteEditorTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty\n"
                "    }\n\n    var body: some View {")
        return None if Checker(tmp).run() == 1 else "视图又自己算了一遍判据，门禁没说话"

    @case("台账里留一条不存在的守卫（陈旧）")
    def _stale_entry(tmp: Path) -> str | None:
        payload = json.loads((tmp / LEDGER_PATH).read_text(encoding="utf-8"))
        payload["entries"].append({
            "func": "ghostAction", "guard": "!ghost.isEmpty", "form": "explain",
            "reason": "负例：这条在源码里不存在",
        })
        (tmp / LEDGER_PATH).write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        return None if Checker(tmp).run() == 1 else "台账有陈旧条目，门禁没说话"

    @case("台账写坏")
    def _broken_ledger(tmp: Path) -> str | None:
        (tmp / LEDGER_PATH).write_text("{ 这不是 JSON", encoding="utf-8")
        return None if Checker(tmp).run() == 1 else "台账写坏了，门禁没说话"

    passed = 0
    for label, fn in cases:
        with tempfile.TemporaryDirectory(prefix="l50-selftest-") as raw:
            tmp = Path(raw) / "repo"
            _fixture(repo, tmp)
            try:
                problem = fn(tmp)
            except AssertionError as exc:
                problem = str(exc)
            if problem is None:
                passed += 1
                print(f"   ✅ {label}")
            else:
                failures.append(f"{label}：{problem}")
                print(f"   ❌ {label}：{problem}")

    after = _snapshot(repo)
    if before != after:
        failures.append("自测改动了真仓库（逐字节比对不一致）")
        print("   ❌ 自测改动了真仓库")
    else:
        print("   ✅ 末例：真仓库逐字节未变")

    print(f"负例：{passed}/{len(cases)} 通过；真仓库未变：{'是' if before == after else '否'}")
    if failures:
        print("❌ 负例未全过：")
        for item in failures:
            print(f"   · {item}")
        return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default=str(ROOT))
    parser.add_argument("--self-test", action="store_true", dest="self_test")
    parser.add_argument("--dump-keys", action="store_true", dest="dump_keys")
    args = parser.parse_args()
    repo = Path(args.repo).resolve()
    if args.dump_keys:
        return dump_keys(repo)
    if args.self_test:
        return self_test(repo)
    return Checker(repo).run()


if __name__ == "__main__":
    sys.exit(main())
