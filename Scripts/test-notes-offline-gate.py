#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""负例：`Scripts/check-notes-offline.py`（零网络出口门禁）**红得出来吗**。

**为什么单开一个脚本**：门禁绿着只能说明「现在没违规」，**不能**说明它看得见违规 ——
本工程已经栽过三次（L-04「失败只记进没人读的变量」、L-05「断言被删也照绿」、
第 14 项「删掉两处出口里的一处仍能顶数」），所以每条新门禁都配一组负例：
**写坏 → 必须报红 → 点名哪一处**。

这条门禁尤其需要负例：**真仓库里一条网络调用都扫不出来**（命中 0 处），
也就是说「绿」这个结果本身分不清「真的没有」还是「扫了个寂寞」。

**做法**：不改真仓库的文件，把**必要的那几个文件**拷进临时目录，在副本上写坏、
把门禁指过去（`--root`）。跑完断言真仓库一个字节没动。

用法：`python3 Scripts/test-notes-offline-gate.py`
"""

import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GATE = "Scripts/check-notes-offline.py"
LEDGER = "Scripts/notes-offline-gate.json"

# 副本需要的最小文件集（门禁会读：范围里的源文件、闭环脚本、解耦门禁、台账、负例自己）
TREE_FILES = [
    "Core/Note.swift",
    "Core/NoteBody.swift",
    "Core/License.swift",
    "Core/LicenseLoader.swift",
    "Core/LicensePresentation.swift",
    "Core/LicensePublicKey.swift",
    "Core/LicenseSignature.swift",
    "Core/AICapture.swift",
    "Core/AICaptureUltra.swift",
    # 入库判定（队列 L-134）：在台账范围里，副本必须带上它，否则「干净副本」这一例会因为
    # 「台账写了、盘上没有」而假红（第 127 轮踩过）
    "Core/AICaptureIntake.swift",
    # 队列 `L-97`（第一~四片的结构模型 / 界面半第一片的导航逻辑）：同样在台账范围里，
    # 副本少带一个 ⇒ 「干净副本」这一例会因为「台账写了、盘上没有」而假红（同上一条的坑）
    "Core/Notebook.swift",
    "Core/NoteNavigation.swift",
    "Core/NotebookRemovalPrompt.swift",
    # 队列 `L-97` 界面半第三片（跨笔记本移动）：同上，台账里有它 ⇒ 副本必须带上
    "Core/NotebookMovePrompt.swift",
    # 队列 `L-97` 界面半第四片（新建 / 重命名 / 排序）：同上，台账里有它 ⇒ 副本必须带上
    "Core/NotebookEditPrompt.swift",
    # 队列 `L-97` 界面半第五片（批量多选 + 拖拽）与第六片（跨架移动）：同上，台账里有它 ⇒ 副本必须带上
    "Core/NoteSelectionPrompt.swift",
    "Core/NotebookShelfMovePrompt.swift",
    # 队列 `L-184`（三栏重排的纯逻辑）：同上，台账里有它 ⇒ 副本必须带上
    "Core/NotePresentation.swift",
    # 队列 `N-11` 的 macOS 核心层半（待办任务的模型）：同上，台账里有它 ⇒ 副本必须带上
    "Core/Todo.swift",
    # 队列 `L-100` 清单界面（待办清单的三件纯逻辑）：同上，台账里有它 ⇒ 副本必须带上
    "Core/TodoPresentation.swift",
    # 队列 `L-100` 日历的 Core 半第二片（月 / 周格子 + 日期算术 + 投影）—— 第 186 轮**漏登**、
    # 第 188 轮补：同上，台账里有它 ⇒ 副本必须带上
    "Core/TodoCalendar.swift",
    # 队列 `L-100` 的「与提醒联动」Core 半（第 188 轮）：同上，台账里有它 ⇒ 副本必须带上
    "Core/Reminder.swift",
    # 队列 `L-100` 落法 ④ 的界面半第一片（第 190 轮，提醒的界面判定与文案）：同上，台账里有它 ⇒ 副本必须带上
    "Core/ReminderPresentation.swift",
    # 队列 `L-100` 的组织与检索半（第 191 轮，排序 / 筛选 / 分组 / 视图入口）：同上，台账里有它 ⇒ 副本必须带上
    "Core/TodoSort.swift",
    "Core/TodoQuery.swift",
    "App/Views/NotesPanel.swift",
    "Tests/NoteTests.swift",
    "Tests/NoteBodyTests.swift",
    "Tests/NoteDataBoundaryTests.swift",
    "Tests/AICaptureTests.swift",
    "Scripts/check-note-module-isolation.py",
    "Scripts/verify-all.sh",
    GATE,
    LEDGER,
    "Scripts/test-notes-offline-gate.py",
]

passed: list[str] = []
failed: list[str] = []


def record(ok: bool, label: str, detail: str = "") -> None:
    (passed if ok else failed).append(label)
    print(f"  {'✅' if ok else '❌'} {label}" + (f"  —— {detail}" if detail and not ok else ""))


def make_tree() -> Path:
    tree = Path(tempfile.mkdtemp(prefix="doyah-notes-offline-"))
    for rel in TREE_FILES:
        destination = tree / rel
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / rel, destination)
    return tree


def run_gate(tree: Path) -> tuple[int, str]:
    proc = subprocess.run(
        [sys.executable, str(tree / GATE), "--root", str(tree), "--json"],
        capture_output=True, text=True,
    )
    try:
        data = json.loads(proc.stdout)
        return proc.returncode, "；".join(data.get("problems", []))
    except json.JSONDecodeError:
        return proc.returncode, (proc.stdout + proc.stderr).strip()


def edit(tree: Path, rel: str, transform) -> None:
    path = tree / rel
    path.write_text(transform(path.read_text(encoding="utf-8")), encoding="utf-8")


def edit_ledger(tree: Path, transform) -> None:
    path = tree / LEDGER
    data = json.loads(path.read_text(encoding="utf-8"))
    transform(data)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def case(label: str, mutate, *expects: str) -> None:
    """在**新副本**上写坏 → 门禁必须非零退出，且报出的问题里点到期望的几处。"""
    tree = make_tree()
    mutate(tree)
    code, problems = run_gate(tree)
    ok = code != 0 and all(expect in problems for expect in expects)
    record(ok, label, f"exit={code}；实际报出：{problems[:400]}")
    shutil.rmtree(tree, ignore_errors=True)


def snapshot() -> dict[str, str]:
    return {
        rel: hashlib.sha256((ROOT / rel).read_bytes()).hexdigest()
        for rel in TREE_FILES
    }


def main() -> int:
    before = snapshot()

    print("— 副本本身必须是绿的（否则后面「红了」归因不到写坏上）—")
    tree = make_tree()
    code, problems = run_gate(tree)
    record(code == 0, "干净副本：exit 0", f"exit={code}；{problems[:300]}")
    shutil.rmtree(tree, ignore_errors=True)

    print("— 三条注入通道：调用 / import / 地址字面量 —")
    case(
        "注入调用 `URLSession.shared` → 报红并点名文件与行号",
        lambda tree: edit(
            tree, "Core/Note.swift",
            lambda text: text.replace(
                "public struct Note",
                '// 出网调用示例（负例）\nlet session = URLSession.shared\n\npublic struct Note',
                1,
            ),
        ),
        "Core/Note.swift:", "URLSession",
    )
    case(
        "注入 `import Network` → 报红",
        lambda tree: edit(
            tree, "App/Views/NotesPanel.swift",
            lambda text: text.replace("import SwiftUI", "import Network\nimport SwiftUI", 1),
        ),
        "import Network",
    )
    case(
        "注入 `https://` 地址字面量 → 报红",
        lambda tree: edit(
            tree, "Core/AICapture.swift",
            lambda text: text + '\n// 负例：https://license.example.com/activate\n',
        ),
        "https://",
    )

    print("— 范围声明 ↔ 事实（陈旧 / 漏登 / 缩范围）—")
    case(
        "删掉范围里的文件 → 报红（声明与事实不符）",
        lambda tree: (tree / "App/Views/NotesPanel.swift").unlink(),
        "App/Views/NotesPanel.swift",
    )
    case(
        "新增未登记的笔记源文件 → 报红（漏登一个＝它偷偷不受约束）",
        lambda tree: (tree / "Core/NoteDraft.swift").write_text(
            "import Foundation\n", encoding="utf-8"
        ),
        "Core/NoteDraft.swift",
    )
    case(
        "把范围缩到一个文件 → 报红（范围不是空集：下限 / 层级 / 关键锚点）",
        lambda tree: edit_ledger(
            tree,
            lambda data: data.update({
                "scope": [entry for entry in data["scope"] if entry["path"] == "Core/NoteBody.swift"],
                "scopeBeyondIsolation": [],
            }),
        ),
        "下限",
    )

    print("— 令牌表不许被掏空 —")
    case(
        "从令牌表删掉关键令牌 `URLSession` → 报红",
        lambda tree: edit_ledger(
            tree,
            lambda data: data.update({
                "bannedTokens": [t for t in data["bannedTokens"] if t["token"] != "URLSession"]
            }),
        ),
        "URLSession", "消失",
    )
    case(
        "把令牌的理由掏空 → 报红（说不清为什么禁它）",
        lambda tree: edit_ledger(
            tree,
            lambda data: data["bannedTokens"].__setitem__(
                0, {"token": data["bannedTokens"][0]["token"], "reason": ""}
            ),
        ),
        "没写明理由",
    )

    print("— 例外与超范围登记：两端都要对账 —")
    case(
        "登记一条陈旧例外（锚点在文件里找不到）→ 报红",
        lambda tree: edit_ledger(
            tree,
            lambda data: data.update({
                "exceptions": [{
                    "file": "Core/Note.swift",
                    "anchor": "这行在文件里根本不存在",
                    "reason": "负例：故意登记一条陈旧的例外",
                }]
            }),
        ),
        "陈旧例外要删",
    )
    case(
        "超范围登记（scopeBeyondIsolation）里塞一个不在范围里的文件 → 报红",
        lambda tree: edit_ledger(
            tree,
            lambda data: data["scopeBeyondIsolation"].append({
                "path": "Core/Commands.swift",
                "reason": "负例：往范围外登记塞文件，想绕开与解耦清单的对账",
            }),
        ),
        "不在范围里",
    )

    print("— 接线：门禁必须在闭环里真的被调用 —")
    case(
        "从 verify-all.sh 删掉本门禁的调用 → 报红（存在但没接线＝红不起来）",
        lambda tree: edit(
            tree, "Scripts/verify-all.sh",
            # 注意：`check-notes-offline.py` 在头注释里也出现过一次（说明第 10 项现在跑三个脚本），
            # 所以这里要**全删**而不是只删第一处 —— 只删第一处的话真正的调用还在，门禁照旧绿。
            lambda text: text.replace("check-notes-offline.py", ""),
        ),
        "没有本门禁",
    )

    print("— 末条：真仓库一个字节没动 —")
    after = snapshot()
    changed = [rel for rel in before if before[rel] != after.get(rel)]
    record(not changed, "写坏只发生在副本上，真仓库未被改动", "；".join(changed))

    print(f"\n{len(passed)}/{len(passed) + len(failed)} 项达到预期")
    if failed:
        print("未达到预期的：")
        for label in failed:
            print(f"  · {label}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
