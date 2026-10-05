#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""负例：`Scripts/check-sidebar-collapse-state.py`（折叠状态归属门禁）**红得出来吗**。

**为什么单开一个脚本**：门禁绿着只能说明「现在没违规」，**不能**说明它看得见违规 ——
本工程已经栽过四次（L-04「失败只记进没人读的变量」、L-05「断言被删也照绿」、
第 14 项「删掉两处出口里的一处仍能顶数」、L-53「解析口径看不见含竖线的行」），
所以每条新门禁都配一组负例：**写坏 → 必须报红 → 点名哪一处**。

这条门禁尤其需要负例：真仓库现在「状态住在 AppState、写入口唯一、视图只是接线」，
「绿」这个结果本身分不清「真的都对」还是「扫了个寂寞」。

**做法**：不改真仓库的文件 —— 把必要的两个文件拷进临时目录，在副本上写坏、
把门禁指过去（`--root`）。跑完断言真仓库一个字节没动。

用法：`python3 Scripts/test-sidebar-collapse-state.py`
"""

import hashlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GATE = "Scripts/check-sidebar-collapse-state.py"

# 副本需要的最小文件集（门禁会读：AppState / 该视图 / 视图目录下其余文件）
TREE_FILES = [
    "platform/macos/App/AppState.swift",
    "platform/macos/App/Views/ConnectionListView.swift",
    GATE,
]

STATE = "platform/macos/App/AppState.swift"
VIEW = "platform/macos/App/Views/ConnectionListView.swift"

DECLARATION = "    @Published private(set) var collapsedConnectionGroups: Set<String> = []"
WRITER = "    func setConnectionGroup(_ group: String, collapsed: Bool) {"
READER = "    func isConnectionGroupCollapsed(_ group: String) -> Bool {"
LOCAL_DECL = "    @State private var pendingDeletion: ConnectionConfig?\n"
BINDING_GET = "                get: { !appState.isConnectionGroupCollapsed(section.id) },"
BINDING_SET = "                set: { expanded in appState.setConnectionGroup(section.id, collapsed: !expanded) }"
VIEW_STATE_CHECK = "        if section.isUngrouped {"

passed: list[str] = []
failed: list[str] = []


def record(ok: bool, label: str, detail: str = "") -> None:
    (passed if ok else failed).append(label)
    print(f"  {'✅' if ok else '❌'} {label}" + (f"  —— {detail}" if detail and not ok else ""))


def make_tree() -> Path:
    tree = Path(tempfile.mkdtemp(prefix="doyah-collapse-state-"))
    for rel in TREE_FILES:
        destination = tree / rel
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / rel, destination)
    return tree


def run(tree: Path) -> tuple[int, str]:
    result = subprocess.run(
        [sys.executable, GATE, "--root", str(tree)],
        cwd=tree,
        capture_output=True,
        text=True,
    )
    return result.returncode, result.stdout + result.stderr


def edit(tree: Path, rel: str, old: str, new: str, count: int = 1) -> None:
    path = tree / rel
    text = path.read_text(encoding="utf-8")
    assert old in text, f"夹具前提不成立：{rel} 里找不到 {old!r}"
    path.write_text(text.replace(old, new, count), encoding="utf-8")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    print("负例：折叠状态归属门禁（Scripts/check-sidebar-collapse-state.py）")
    before = {rel: digest(ROOT / rel) for rel in TREE_FILES}

    # 0) 基线：未改动的副本必须**绿**（否则下面每一条「红」都没有意义）
    tree = make_tree()
    code, output = run(tree)
    record(code == 0, "基线（未改动的副本）判绿", output.strip()[-400:])

    # 1) 视图局部 @State 回来了 —— 本次缺陷的形状本体，必须点名文件:行号
    tree = make_tree()
    edit(tree, VIEW, LOCAL_DECL, LOCAL_DECL + "\n    @State private var collapsedGroups: Set<String> = []\n")
    code, output = run(tree)
    record(
        code != 0 and f"{VIEW}:" in output and "必须住在 `AppState`" in output,
        "视图里出现 `@State` 折叠状态 ⇒ 判红并点名行号",
        output.strip()[-300:],
    )

    # 2) 视图的接线断了（折叠判断改回读本地状态）—— 症状与 L-59 同款
    tree = make_tree()
    edit(tree, VIEW, BINDING_GET, "                get: { !collapsedGroups.contains(section.id) },")
    edit(
        tree,
        VIEW,
        BINDING_SET,
        "                set: { expanded in\n"
        "                    if expanded { collapsedGroups.remove(section.id) } else { collapsedGroups.insert(section.id) }\n"
        "                }",
    )
    code, output = run(tree)
    record(
        code != 0 and "接线断了" in output and "本地**折叠集合" in output,
        "折叠绑定不走 appState（改回本地集合）⇒ 判红",
        output.strip()[-300:],
    )

    # 3) 写入口成了空壳（函数还在，但一处增删都没有）
    tree = make_tree()
    edit(
        tree,
        STATE,
        "        if collapsed {\n"
        "            collapsedConnectionGroups.insert(group)\n"
        "        } else {\n"
        "            collapsedConnectionGroups.remove(group)\n"
        "        }",
        "        _ = collapsed",
    )
    code, output = run(tree)
    record(
        code != 0 and "写入口是空的" in output,
        "`setConnectionGroup` 成了空壳 ⇒ 判红（空跑不许通过）",
        output.strip()[-300:],
    )

    # 4) 出现第二个写入口（在 `setConnectionGroup` 之外直接改集合）
    tree = make_tree()
    edit(
        tree,
        STATE,
        READER,
        '    func collapseEverything() {\n        collapsedConnectionGroups.insert("生产环境")\n    }\n\n' + READER,
    )
    code, output = run(tree)
    record(
        code != 0 and "写入口必须唯一" in output,
        "`setConnectionGroup` 之外还有一个写入口 ⇒ 判红（写入口不唯一）",
        output.strip()[-300:],
    )

    # 5) 集合改成可写（绕过唯一写入口）
    tree = make_tree()
    edit(tree, STATE, DECLARATION, "    @Published var collapsedConnectionGroups: Set<String> = []")
    code, output = run(tree)
    record(
        code != 0 and "不是 `private(set)`" in output,
        "集合不是 `private(set)` ⇒ 判红（写入口就不止一个了）",
        output.strip()[-300:],
    )

    # 6) 默认收起（初值预置一个组）
    tree = make_tree()
    edit(tree, STATE, DECLARATION, '    @Published private(set) var collapsedConnectionGroups: Set<String> = ["生产环境"]')
    code, output = run(tree)
    record(
        code != 0 and "初值不是空集合" in output,
        "初值预置了组（默认收起）⇒ 判红（一进来就收起会让人以为连接没了）",
        output.strip()[-300:],
    )

    # 7) 未分组那一段被加了折叠（兜底容器：折起来等于把没归类的连接藏了）
    tree = make_tree()
    edit(
        tree,
        VIEW,
        VIEW_STATE_CHECK + "\n            Text(title)",
        VIEW_STATE_CHECK + "\n            DisclosureGroup(title) {\n                rows(section)\n            }\n            Text(title)",
    )
    code, output = run(tree)
    record(
        code != 0 and "未分组那一段出现了 `DisclosureGroup`" in output,
        "未分组那一段加了折叠 ⇒ 判红",
        output.strip()[-300:],
    )

    # 8) 空跑防护：状态文件不在
    tree = make_tree()
    (tree / STATE).unlink()
    code, output = run(tree)
    record(
        code != 0 and "判据输入缺失" in output,
        "`platform/macos/App/AppState.swift` 不在 ⇒ 判红（空跑不许通过）",
        output.strip()[-300:],
    )

    # 9) 空跑防护：视图形状变了（`sectionView` 改名 ⇒ 分支解析不到）
    tree = make_tree()
    edit(tree, VIEW, "    private func sectionView(", "    private func sectionViewRenamed(")
    code, output = run(tree)
    record(
        code != 0 and "空跑不许通过" in output,
        "`sectionView` 改名（判据取不到输入）⇒ 判红",
        output.strip()[-300:],
    )

    # 10) 主仓库一个字节没动
    after = {rel: digest(ROOT / rel) for rel in TREE_FILES}
    record(
        before == after,
        "跑完核对真仓库逐字节未变",
        "被改动的文件：" + "、".join(key for key in before if before[key] != after[key]),
    )

    print(f"\n结果：{len(passed)} 通过 / {len(failed)} 未达预期")
    if failed:
        for label in failed:
            print(f"  ❌ {label}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
