#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""`check-literal-language.py`（队列 L-47）的负例自测 —— **在临时副本上写坏，不碰真仓库**。

每个用例都是「改一处 ⇒ 必须判红并点名」，而且**先自检前提**：干净副本必须判绿
（判据在干净树上就报红 ⇒ 后面那些「红」都不算数）。末例核对**真仓库逐字节未变**。

跑法：`python3 Scripts/test-literal-language-gate.py`（接在 verify-all.sh 第 3 项里）。
"""

from __future__ import annotations

import hashlib
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = "Scripts/check-literal-language.py"
LEDGER = "Scripts/literal-language-dispositions.json"
COPY_DIRS = ["Core", "App", "CLI", "Platform", "Scripts"]
WATCH_DIRS = ["Core", "App", "CLI", "Platform", "Scripts", "Tests"]


def digest_tree() -> dict[str, str]:
    result: dict[str, str] = {}
    for name in WATCH_DIRS:
        base = REPO / name
        if not base.exists():
            continue
        for path in sorted(base.rglob("*")):
            if path.is_file():
                rel = path.relative_to(REPO).as_posix()
                result[rel] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def make_copy(root: pathlib.Path) -> pathlib.Path:
    copy = root / "copy"
    copy.mkdir()
    for name in COPY_DIRS:
        shutil.copytree(REPO / name, copy / name)
    return copy


def run(copy: pathlib.Path) -> tuple[int, str]:
    proc = subprocess.run(
        [sys.executable, str(copy / SCRIPT), "--root", str(copy)],
        capture_output=True,
        text=True,
    )
    return proc.returncode, proc.stdout + proc.stderr


def patch(path: pathlib.Path, old: str, new: str, *, required: bool = True) -> bool:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        if required:
            raise SystemExit(f"夹具失效：在 {path} 里找不到要替换的片段\n{old[:120]}")
        return False
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    return True


def main() -> int:
    before = digest_tree()
    failures: list[str] = []
    cases = 0

    with tempfile.TemporaryDirectory(prefix="literal-language-gate-") as tmp:
        root = pathlib.Path(tmp)

        def fresh() -> pathlib.Path:
            for child in root.iterdir():
                shutil.rmtree(child)
            return make_copy(root)

        # 例 0（前提自检）：干净副本必须绿 —— 判据在干净树上就报红，后面的「红」都不算数。
        copy = fresh()
        cases += 1
        rc, out = run(copy)
        if rc != 0:
            failures.append(f"例 0 干净副本应判绿，实测 rc={rc}：\n{out}")

        # 例 1（判据 A · 回归钉）：在已透传的文件里再写死一次语言。
        copy = fresh()
        cases += 1
        patch(
            copy / "platform/macos/Core/DiagnosisContext.swift",
            "lines.append(localizedText(.diagnosisEvidenceHeader, language: language))",
            "lines.append(LocalizedStrings.text(.diagnosisEvidenceHeader, language: .simplifiedChinese))",
        )
        rc, out = run(copy)
        if rc == 0 or "platform/macos/Core/DiagnosisContext.swift" not in out or "A " not in out:
            failures.append(f"例 1（回归钉）应判红并点名 DiagnosisContext.swift，实测 rc={rc}：\n{out}")

        # 例 2（判据 A · 未登记文件）：在台账没登记的文件里写死语言。
        copy = fresh()
        cases += 1
        patch(
            copy / "platform/macos/Core/ObjectTreeGrouping.swift",
            "language: AppLanguage = .simplifiedChinese",
            "language: AppLanguage = AppLanguage.simplifiedChinese  // 写死语言\n    static let injected = LocalizedStrings.text(.objectGroupOther, language: .simplifiedChinese)",
        )
        rc, out = run(copy)
        if rc == 0 or "platform/macos/Core/ObjectTreeGrouping.swift" not in out:
            failures.append(f"例 2（未登记文件）应判红并点名 ObjectTreeGrouping.swift，实测 rc={rc}：\n{out}")

        # 例 3（判据 B ①）：新增一个未登记的死译文。
        copy = fresh()
        cases += 1
        ledger = copy / LEDGER
        data = json.loads(ledger.read_text(encoding="utf-8"))
        data["deadKeys"] = [entry for entry in data["deadKeys"] if entry["key"] != "mcpApprovalDenied"]
        ledger.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        rc, out = run(copy)
        if rc == 0 or "mcpApprovalDenied" not in out or "B " not in out:
            failures.append(f"例 3（新增未登记死译文）应判红并点名该键，实测 rc={rc}：\n{out}")

        # 例 4（判据 B ② · 反向陈旧）：把一个已登记的死键改成语境取值 ⇒ 台账条目陈旧。
        copy = fresh()
        cases += 1
        patch(
            copy / "platform/macos/Core/MCPToolCatalog.swift",
            "return .needsApproval(reason: text(.mcpNeedsApproval, tool.name, language: language))",
            "return .needsApproval(reason: text(.mcpApprovalDenied, tool.name, language: language))",
        )
        rc, out = run(copy)
        if rc == 0 or "mcpApprovalDenied" not in out or "陈旧" not in out:
            failures.append(f"例 4（死键修好后台账陈旧）应判红，实测 rc={rc}：\n{out}")

        # 例 5（判据 C · 源树判据）：把已透传的文本出口的 `language:` 形参去掉。
        copy = fresh()
        cases += 1
        patch(
            copy / "platform/macos/Core/DiagnosisContext.swift",
            "public func promptText(language: AppLanguage) -> String {",
            "public func promptText() -> String { let language = AppLanguage.simplifiedChinese",
        )
        rc, out = run(copy)
        if rc == 0 or " C " not in out.replace("\n", " "):
            failures.append(f"例 5（丢了 language: 形参）应判红且含 C 判据，实测 rc={rc}：\n{out}")

        # 例 6（判据 C · 界面侧）：面板不再把 effectiveLanguage 传下去。
        copy = fresh()
        cases += 1
        patch(
            copy / "platform/macos/App/Views/DiagnosisPanel.swift",
            "language: LocalizationManager.shared.effectiveLanguage",
            "language: LocalizationManager.shared.language",
            required=False,
        )
        rc, out = run(copy)
        if rc == 0 or "DiagnosisPanel.swift" not in out:
            failures.append(f"例 6（面板不传 effectiveLanguage）应判红，实测 rc={rc}：\n{out}")

        # 例 7（判据 D · 不许空跑）：语言表整个消失 ⇒ 判据取不到输入。
        copy = fresh()
        cases += 1
        (copy / "platform/macos/Core/Localization.swift").unlink()
        rc, out = run(copy)
        if rc == 0 or "一个键都没解析到" not in out:
            failures.append(f"例 7（语言表消失 = 空跑）应判红，实测 rc={rc}：\n{out}")

        # 例 8（判据 C · L-65 第 2 批钉的 SSH 隧道族）：把 `describe(language:)` 的形参删掉
        # ——「人话在 Core 里自己拼」那条路一旦回来，英文译文又会变成死键。
        copy = fresh()
        cases += 1
        patch(
            copy / "platform/macos/Core/SSHTunnelProcess.swift",
            "public func describe(language: AppLanguage) -> String {",
            "public func describe() -> String { let language = AppLanguage.simplifiedChinese",
        )
        rc, out = run(copy)
        if rc == 0 or "SSHTunnelProcess.swift" not in out or "C " not in out:
            failures.append(f"例 8（隧道族丢了 language: 形参）应判红且含 C 判据并点名该文件，实测 rc={rc}：\n{out}")

        # 例 9（判据 C · L-65 第 3 批钉的四族）：把维护计划那两个出口的 `language:` 形参删掉
        # ——「删形参、体内再写死」这条路必须当场报红。
        copy = fresh()
        cases += 1
        patch(
            copy / "platform/macos/Core/MaintenancePlan.swift",
            "        databaseType: DatabaseType = .postgresql,\n        language: AppLanguage\n    ) -> MaintenancePlanReview {",
            "        databaseType: DatabaseType = .postgresql\n    ) -> MaintenancePlanReview { let language = AppLanguage.simplifiedChinese",
        )
        rc, out = run(copy)
        if rc == 0 or "platform/macos/Core/MaintenancePlan.swift" not in out or "C " not in out:
            failures.append(f"例 9（维护计划族丢了 language: 形参）应判红且含 C 判据，实测 rc={rc}：\n{out}")

        # 例 10（判据 C · 调用方那一半）：Core 的形参都留着，但**展示点不把语言传下去** ——
        # 语言会从「调用方给的」悄悄变回「Core 自己选的」，必须报红。
        copy = fresh()
        cases += 1
        patch(
            copy / "platform/macos/App/Views/AboutLicenseSheet.swift",
            "                    language: LocalizationManager.shared.effectiveLanguage\n",
            "",
        )
        rc, out = run(copy)
        if rc == 0 or "AboutLicenseSheet.swift" not in out:
            failures.append(f"例 10（升级页不传语言）应判红并点名 AboutLicenseSheet.swift，实测 rc={rc}：\n{out}")

        # 例 11（判据 B · 短名取值助手那条漏判，第 4 批修掉的那条）：本仓库最常见的取值助手是
        # **短名** `t(_ key: LKey …)` / `text(_ key: LKey …)`，而入口识别原先只认带后缀的长名
        # ⇒ 它们背后的键在判据 B 里**完全看不见**。把 `text(` 的语言写回字面量：经它引用的键
        # **必须**被看见并判成未登记的死译文（修之前这一例报不出来）。
        copy = fresh()
        cases += 1
        patch(
            copy / "platform/macos/Core/MaintenancePlan.swift",
            "        return LocalizedStrings.text(key, language: language)",
            "        return LocalizedStrings.text(key, language: .simplifiedChinese)",
        )
        patch(
            copy / "platform/macos/Core/MaintenancePlan.swift",
            "    return LocalizedStrings.format(key, language: language, arguments)",
            "    return LocalizedStrings.format(key, language: .simplifiedChinese, arguments)",
        )
        rc, out = run(copy)
        if rc == 0 or "B " not in out or "maintenanceRefusedReadOnly" not in out:
            failures.append(
                f"例 11（短名助手写死语言 ⇒ 它背后的键必须被判成死译文）应判红并点名 "
                f"maintenanceRefusedReadOnly，实测 rc={rc}：\n{out}"
            )

        # 例 12（判据 C · 负向那条）：**笔记侧不许收语言** —— 把 `defaultTag: String` 换成
        # `language: AppLanguage`（第一版就是这么写的，被闭环第 10 项拦下）⇒ 这里也必须判红。
        copy = fresh()
        cases += 1
        patch(
            copy / "platform/macos/Core/AICapture.swift",
            "        defaultTag: String\n    ) -> NoteDraft {\n        NoteDraft(\n            title: title,\n            body: body,\n            tags: tags ?? [defaultTag],",
            "        language: AppLanguage\n    ) -> NoteDraft {\n        NoteDraft(\n            title: title,\n            body: body,\n            tags: tags ?? [LocalizedStrings.text(.aiNoteTagSkill, language: language)],",
        )
        rc, out = run(copy)
        if rc == 0 or "platform/macos/Core/AICapture.swift" not in out or "笔记侧" not in out:
            failures.append(f"例 12（笔记侧又收语言）应判红并点名 AICapture.swift，实测 rc={rc}：\n{out}")

        # 例 13（判据 C · L-65 第 5 批钉的 MySQL 文案族）：渲染搬进了**新文件**
        # `platform/macos/Core/MySQLWording.swift` —— 把某一句的 `language:` 形参删掉（改成体内自选），
        # 「ADR-25 冻结点的落法」就退回「中文写死在新文件里」，必须当场报红。
        copy = fresh()
        cases += 1
        patch(
            copy / "platform/macos/Core/MySQLWording.swift",
            "public static func copyUnsupported(language: AppLanguage) -> String {",
            "public static func copyUnsupported() -> String { let language = AppLanguage.simplifiedChinese",
        )
        rc, out = run(copy)
        if rc == 0 or "MySQLWording.swift" not in out or "C " not in out:
            failures.append(f"例 13（MySQL 文案族丢了 language: 形参）应判红且含 C 判据，实测 rc={rc}：\n{out}")

        # 例 14（判据 C · 数据库侧那两句人话的**来源**）：工厂的 MySQL 分支不把语言交出去 ——
        # 形参都还在，但连接对象再也拿不到语言 ⇒ 报红点名 `platform/macos/Core/DatabaseService.swift`。
        copy = fresh()
        cases += 1
        patch(
            copy / "platform/macos/Core/DatabaseService.swift",
            "            return MySQLService(config: config, password: password, language: language)",
            "            return MySQLService(config: config, password: password)",
        )
        rc, out = run(copy)
        if rc == 0 or "DatabaseService.swift" not in out or "C " not in out:
            failures.append(f"例 14（工厂不给驱动语言）应判红且含 C 判据，实测 rc={rc}：\n{out}")

        # 例 15（判据 C · 展示点那一半）：界面「测试连接」不发语言（第 5 批新接的调用点）。
        copy = fresh()
        cases += 1
        patch(
            copy / "platform/macos/App/Views/ConnectionFormView.swift",
            "                for: target,\n                password: testPassword,\n                language: LocalizationManager.shared.effectiveLanguage\n            )",
            "                for: target,\n                password: testPassword\n            )",
        )
        rc, out = run(copy)
        if rc == 0 or "ConnectionFormView.swift" not in out or "C " not in out:
            failures.append(f"例 15（测试连接不传语言）应判红且含 C 判据，实测 rc={rc}：\n{out}")

    after = digest_tree()
    cases += 1
    if before != after:
        changed = sorted(set(before) ^ set(after)) or [
            name for name in before if before[name] != after.get(name)
        ]
        failures.append(f"末例：真仓库被动过（逐字节比对不一致）：{changed[:10]}")

    if failures:
        print(f"✗ 语言透传门禁负例自测不通过（{len(failures)}/{cases}）：")
        for item in failures:
            print(f"  · {item}")
        return 1
    print(f"✅ 语言透传门禁负例自测 {cases}/{cases} 通过（真仓库逐字节未变）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
