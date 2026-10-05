#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""插件链两条门禁的**负例验证**（FR-PLUG-01~03 / 06 / 07 + ADR-35）。

为什么要有它：`check-plugin-assembly.py` 与 `check-note-module-isolation.py` 每轮都绿 ——
但"一直是绿的"有两种可能：口径守住了，或者门禁根本拦不住。本脚本把**常见的退化方式**
逐个写坏一遍，断言门禁真的退出码 1 并报出对的原因，然后还原。

每个负例：写坏 → 跑门禁 → 断言（退出码 = 1 且输出含预期原因）→ 还原 → 断言字节回到原样；
收场再断言工作区只剩本轮该改的文件（探针文件必须删掉）。

**为什么不整个接进 `verify-all.sh`**：完整跑法要**临时改真源码**。完整跑按需（改门禁 / 拆笔记模块之后各跑一次）：

    python3 Scripts/test-plugin-assembly-gates.py

**接进闭环的是只读那一半**（2026-09-28 第 65 轮，队列 L-72 ㈠）：

    python3 Scripts/test-plugin-assembly-gates.py --check-anchors

只把每个负例的**夹具锚点**在当前源码里对一遍（不写盘、不跑门禁），退出码 0 = 全部锚点在位。
理由 = 本脚本自己栽过：`platform/macos/Core/AICapture.swift` 的 `sqlNote` 签名于第 50 轮前后改成多行 +
多一个 `tag:` 参数，而这里的 `replace(...)` 锚点还写着单行老签名 ⇒ **脚本每次都在第 3 例崩掉**，
而这个脚本当时**没人跑**（不在闭环里）⇒ 一直没人发现。它的例数与锚点现状登记在
`Scripts/self-test-counts.json`（闭环第 4 项的自检例数台账），每轮由
`Scripts/check-self-test-counts.py` 跑一遍。

退出码 0 = 全部负例达到预期（门禁真的会红）／全部夹具锚点在位（`--check-anchors`）。
"""
import pathlib
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
ASSEMBLY = "Scripts/check-plugin-assembly.py"
ISOLATION = "Scripts/check-note-module-isolation.py"

# `--check-anchors`：**只读那一半**（接进闭环，见文件头）。只核对每个负例的夹具锚点还在不在
# 当前源码里 —— 不写盘、不跑门禁、不动工作区。写坏那一半仍按需手工跑。
ANCHOR_ONLY = "--check-anchors" in sys.argv

EXPECTED_WORKTREE = {
    "platform/macos/Core/AICapture.swift",
    "platform/macos/Core/AICaptureUltra.swift",
    "Scripts/check-note-module-isolation.py",
    "Scripts/check-plugin-assembly.py",
    "Scripts/test-plugin-assembly-gates.py",
}

results = []
failures = []


def run(script):
    proc = subprocess.run([sys.executable, script], cwd=REPO, capture_output=True, text=True)
    return proc.returncode, proc.stdout + proc.stderr


def case(name, relative, transform, script, expect_code, expect_text):
    path = REPO / relative
    existed = path.exists()
    original = path.read_text(encoding="utf-8") if existed else ""
    if ANCHOR_ONLY:
        # 文件不存在也可能是**故意的**（「新源文件没进门禁清单」那一例就是要新建一个探针文件）
        # ⇒ 不把「文件不在」当锚点失效；transform 拿到的就是空串，照常比「改动是否真的生效」。
        try:
            produced = transform(original)
        except AssertionError as error:
            failures.append(f"{name}: 夹具锚点不在位 —— {error}")
            results.append((name, False, "锚点不在位"))
            return
        ok = produced != original
        results.append((name, ok, "锚点在位" if ok else "锚点在但改动没生效"))
        if not ok:
            failures.append(f"{name}: 锚点在位、但 transform 返回原文（改动没生效）")
        return
    try:
        new_text = transform(original)
        assert new_text != original, f"{name}: 修改没有生效（文本没变）"
        path.write_text(new_text, encoding="utf-8")
        code, output = run(script)
        ok = (code == expect_code) and (expect_text in output)
        detail = "退出码 %d（期望 %d）" % (code, expect_code)
        if expect_text not in output:
            detail += "；输出里没有 %r" % expect_text
        results.append((name, ok, detail))
        if not ok:
            failures.append(f"{name}: {detail}\n{output}")
    finally:
        if existed:
            path.write_text(original, encoding="utf-8")
            if path.read_text(encoding="utf-8") != original:
                failures.append(f"{name}: 还原失败！{relative}")
        elif path.exists():
            path.unlink()


def add(snippet):
    def transform(text):
        return text + "\n" + snippet + "\n"
    return transform


def replace(old, new):
    def transform(text):
        assert old in text, f"找不到待替换的片段：{old}"
        return text.replace(old, new, 1)
    return transform


# ---- 装配链门禁的负例 -------------------------------------------------------
case("FR-PLUG-02 视图层自己过滤 allCases", "platform/macos/App/Views/ActivityBarView.swift",
     add('private func __negativeProbe() { _ = ActivityBarItem.allCases }'),
     ASSEMBLY, 1, "视图层自己过滤 allCases")

case("ADR-35 绕过 resolveSelection 直接赋值", "platform/macos/App/AppState.swift",
     add('extension AppState { func __negativeProbeSet() { selectedActivityItem = .notes } }'),
     ASSEMBLY, 1, "没过 resolveSelection")

case("ADR-35 selectedActivityItem 不再是 private(set)", "platform/macos/App/AppState.swift",
     replace("@Published private(set) var selectedActivityItem", "@Published var selectedActivityItem"),
     ASSEMBLY, 1, "不再是 private(set)")

case("FR-PLUG-06 能力位少一位（笔记没进一套许可）", "platform/macos/Core/License.swift",
     replace("static let all: LicenseCapabilities = [.workspaces, .database, .notes]",
             "static let all: LicenseCapabilities = [.workspaces, .database]"),
     ASSEMBLY, 1, "不再是三个能力位")

case("FR-PLUG-03 笔记侧入口混进非文本参数", "platform/macos/Core/AICapture.swift",
     replace("        tag: String\n    ) -> NoteDraft {",
             "        tag: String,\n        extra: [String: Any] = [:]\n    ) -> NoteDraft {"),
     ASSEMBLY, 1, "不在白名单")

# ---- 解耦门禁的负例 ---------------------------------------------------------
case("FR-PLUG-07 笔记源文件引用 Ultra 侧类型", "platform/macos/Core/AICapture.swift",
     add("func __negativeProbe(_ context: DiagnosisContext) {}"),
     ISOLATION, 1, "引用了 DiagnosisContext")

case("FR-PLUG-07 新笔记源文件没进门禁清单", "Core/NoteNegativeProbe.swift",
     lambda _: "import Foundation\n\nstruct __NegativeProbe: Sendable { let id: String }\n",
     ISOLATION, 1, "没进本脚本的清单")

# ---- 收场：探针文件、工作区都要干净 -----------------------------------------
probe = REPO / "Core/NoteNegativeProbe.swift"
if ANCHOR_ONLY:
    # 只读那一半：一个字节都没写 ⇒ 不需要探针清理与工作区核对。
    print("=== 夹具锚点核对（只读，不写盘）===")
    for name, ok, detail in results:
        print(("  PASS  " if ok else "  FAIL  ") + name + (f"  [{detail}]" if detail and not ok else ""))
    print()
    if failures:
        print(f"❌ {len(failures)}/{len(results)} 个负例的夹具锚点不在位：")
        for item in failures:
            print("----\n" + item)
        print("   —— 锚点不在位 = 这个负例**根本跑不起来**（对已知改动不会报红）。")
        sys.exit(1)
    print(f"✅ 全部 {len(results)} 个负例的夹具锚点都在位（--check-anchors）")
    sys.exit(0)

if probe.exists():
    probe.unlink()
    results.append(("探针文件已删除 Core/NoteNegativeProbe.swift", True, ""))

status = subprocess.run(["git", "status", "--porcelain"], cwd=REPO, capture_output=True, text=True).stdout
unexpected = [line[3:] for line in status.splitlines() if line[3:] not in EXPECTED_WORKTREE]
results.append(("工作区只剩本轮该改的文件", not unexpected,
                "多余改动：%s" % unexpected if unexpected else ""))

print("=== 负例验证 ===")
for name, ok, detail in results:
    print(("  PASS  " if ok else "  FAIL  ") + name + (f"  [{detail}]" if detail and not ok else ""))
print()
if failures:
    print(f"❌ {len(failures)} 个负例没达到预期：")
    for item in failures:
        print("----\n" + item)
    sys.exit(1)
print(f"✅ 全部 {len(results)} 个负例达到预期（门禁真的会红，改动已还原）")
