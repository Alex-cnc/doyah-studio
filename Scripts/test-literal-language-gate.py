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
                rel = str(path.relative_to(REPO))
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
            copy / "Core/DiagnosisContext.swift",
            "lines.append(localizedText(.diagnosisEvidenceHeader, language: language))",
            "lines.append(LocalizedStrings.text(.diagnosisEvidenceHeader, language: .simplifiedChinese))",
        )
        rc, out = run(copy)
        if rc == 0 or "Core/DiagnosisContext.swift" not in out or "A " not in out:
            failures.append(f"例 1（回归钉）应判红并点名 DiagnosisContext.swift，实测 rc={rc}：\n{out}")

        # 例 2（判据 A · 未登记文件）：在台账没登记的文件里写死语言。
        copy = fresh()
        cases += 1
        patch(
            copy / "Core/ObjectTreeGrouping.swift",
            "language: AppLanguage = .simplifiedChinese",
            "language: AppLanguage = AppLanguage.simplifiedChinese  // 写死语言\n    static let injected = LocalizedStrings.text(.objectGroupOther, language: .simplifiedChinese)",
        )
        rc, out = run(copy)
        if rc == 0 or "Core/ObjectTreeGrouping.swift" not in out:
            failures.append(f"例 2（未登记文件）应判红并点名 ObjectTreeGrouping.swift，实测 rc={rc}：\n{out}")

        # 例 3（判据 B ①）：新增一个未登记的死译文。
        copy = fresh()
        cases += 1
        ledger = copy / LEDGER
        data = json.loads(ledger.read_text(encoding="utf-8"))
        data["deadKeys"] = [entry for entry in data["deadKeys"] if entry["key"] != "mysqlCopyUnsupported"]
        ledger.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        rc, out = run(copy)
        if rc == 0 or "mysqlCopyUnsupported" not in out or "B " not in out:
            failures.append(f"例 3（新增未登记死译文）应判红并点名该键，实测 rc={rc}：\n{out}")

        # 例 4（判据 B ② · 反向陈旧）：把一个已登记的死键改成语境取值 ⇒ 台账条目陈旧。
        copy = fresh()
        cases += 1
        patch(
            copy / "Core/MySQLService.swift",
            "LocalizedStrings.text(.mysqlCopyUnsupported, language: .simplifiedChinese)",
            "LocalizedStrings.text(.mysqlCopyUnsupported, language: AppLanguage.simplifiedChinese)",
        )
        rc, out = run(copy)
        if rc == 0 or "mysqlCopyUnsupported" not in out or "陈旧" not in out:
            failures.append(f"例 4（死键修好后台账陈旧）应判红，实测 rc={rc}：\n{out}")

        # 例 5（判据 C · 源树判据）：把已透传的文本出口的 `language:` 形参去掉。
        copy = fresh()
        cases += 1
        patch(
            copy / "Core/DiagnosisContext.swift",
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
            copy / "App/Views/DiagnosisPanel.swift",
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
        (copy / "Core/Localization.swift").unlink()
        rc, out = run(copy)
        if rc == 0 or "一个键都没解析到" not in out:
            failures.append(f"例 7（语言表消失 = 空跑）应判红，实测 rc={rc}：\n{out}")

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
