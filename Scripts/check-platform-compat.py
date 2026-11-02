#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""门禁：平台矩阵的**配置面与读数**（`NFR-ALL-GATE-COMP-004` / `-005`）。

## 这两行原来为什么判不住

台账两行都写着「🟡（待验证）」，而盘上其实早有一半东西：`project.yml` 写 14.0、
`Package.swift` 写 `.v14`、`build-app.sh` 的 Info.plist 模板写 `LSMinimumSystemVersion 14.0`、
连 `Scripts/test-universal-build.sh` 都在。问题是**没人把它们对在一起**，
也没有任何一份读数说「这台机器上两个切片真的都起来了」——
于是「支持 14 / 15」「支持 Apple Silicon 与 Intel」只是几句声明。

## 本判据判四件事

  A **部署目标只有一个值**（需求原文判据②「三处部署目标一致」）：
    `Package.swift`（包定义）· `project.yml`（工程文件：`deploymentTarget` 与
    `MACOSX_DEPLOYMENT_TARGET`）· `.xcodeproj/project.pbxproj`（生成物，
    `xcodegen` 出来的那份，**每一处**都要一致）· `build-app.sh` 的 Info.plist 模板
    （产物信息 = 权威）。任何一处解析不到 / 与基准不同 ⇒ 判红并点名那一处。
  B **产物信息里带着最低系统版本**（判据③「低于最低版本的机器上安装时给出明确提示」）：
    系统弹那句「需要 macOS 14.0 或更高版本」，唯一依据就是 `LSMinimumSystemVersion`；
    没有这个键 ⇒ 老机器上不会有人告诉你为什么打不开。
  C **架构面真能产**（判据②「通用二进制含两种架构」）：
    `build-app.sh` 认 `arm64` / `x86_64` / `universal` 三档、`universal` 走 `lipo -create`；
    `test-universal-build.sh` 在位且断言两种架构。构建能力是**声明**，真产物由 `--readings` 判。
  D **读数对阈值**（`--readings`，读 `Scripts/measure-platform-matrix.py` 写出的 JSON）：
    两个架构都在产物里、每个切片的 `minos` 都等于部署目标、Info.plist 那个键等于部署目标、
    每个架构都**真启动过并写出启动收据**、x86_64 那一档发生时 Rosetta 真的在翻译态。
    缺一项就报「没有这项读数」，**不当通过**。

## 用法

    python3 Scripts/check-platform-compat.py                     # 静态臂（闭环第 11 项里跑）
    python3 Scripts/check-platform-compat.py --readings .build/platform-matrix.json
    python3 Scripts/check-platform-compat.py --self-test          # 判据自己的证据：`--self-test` 12 例
    python3 Scripts/check-platform-compat.py --root <树>          # 换一棵树跑（自检用）

**边界（如实登记）**：本判据不启动 App、不构建 —— 那两件事由
`Scripts/measure-platform-matrix.py` 与 `Scripts/build-app.sh` 做。
静态臂只证明「四处说的是同一个版本、产物信息带提示键、构建脚本认三档」；
**不证明**这台机器现在跑得动，也不证明真 macOS 14 / 15 与真 Intel 机可用。
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import shutil
import sys
import tempfile

BASE = pathlib.Path(__file__).resolve().parent.parent

TARGET = "14.0"
FILES = {
    "package": "Package.swift",
    "project": "project.yml",
    "pbxproj": "DoyahStudio.xcodeproj/project.pbxproj",
    "build": "Scripts/build-app.sh",
    "universal": "Scripts/test-universal-build.sh",
}

PACKAGE_PATTERN = re.compile(r"\.macOS\(\.v(\d+)(?:_(\d+))?\)")
PROJECT_TARGET_PATTERN = re.compile(r"deploymentTarget:\s*\n\s*macOS:\s*[\"']([0-9.]+)[\"']")
PROJECT_SETTING_PATTERN = re.compile(r"MACOSX_DEPLOYMENT_TARGET:\s*[\"']([0-9.]+)[\"']")
PBXPROJ_PATTERN = re.compile(r"MACOSX_DEPLOYMENT_TARGET\s*=\s*([0-9.]+)\s*;")
PLIST_PATTERN = re.compile(r"<key>LSMinimumSystemVersion</key>\s*\n\s*<string>([0-9.]+)</string>")

MIN_BUILD_CASE_MINUTES = 20   # 空跑防护：构建脚本至少这么多行才像话


class Report:
    """一处失败一行话，最后吐一句总结。**点名到文件**，不写「配置不一致」了事。"""

    def __init__(self) -> None:
        self.problems: list[str] = []
        self.notes: list[str] = []
        self.checked = 0

    def fail(self, message: str) -> None:
        self.problems.append(message)

    def note(self, message: str) -> None:
        self.notes.append(message)

    def print(self) -> None:
        for line in self.notes:
            print("  · %s" % line)
        for line in self.problems:
            print("  ✗ %s" % line)


def read(root: pathlib.Path, key: str):
    path = root / FILES[key]
    if not path.exists():
        return None
    return path.read_text(encoding="utf-8")


def check_deployment_target(root: pathlib.Path, report: Report) -> None:
    """A：四处部署目标必须是同一个值（解析不到也算红 —— 判据不许因为「没读到」而放行）。"""
    # 包定义
    package = read(root, "package")
    if package is None:
        report.fail("缺 %s（包定义读不到，部署目标无从对账）" % FILES["package"])
    else:
        matches = PACKAGE_PATTERN.findall(package)
        if not matches:
            report.fail("%s 里解析不到 `.macOS(.vNN)` 平台声明" % FILES["package"])
        else:
            values = {"%s.%s" % (major, minor or "0") for major, minor in matches}
            report.checked += 1
            if values != {TARGET}:
                report.fail("%s 的部署目标 = %s，应为 %s" % (FILES["package"], "、".join(sorted(values)), TARGET))

    # 工程文件（源）：deploymentTarget 与 MACOSX_DEPLOYMENT_TARGET 两处都要在
    project = read(root, "project")
    if project is None:
        report.fail("缺 %s（工程文件读不到）" % FILES["project"])
    else:
        found = PROJECT_TARGET_PATTERN.findall(project)
        if not found:
            report.fail("%s 里解析不到 `deploymentTarget: macOS: \"NN.N\"`" % FILES["project"])
        else:
            report.checked += 1
            for value in found:
                if value != TARGET:
                    report.fail("%s 的 deploymentTarget.macOS = %s，应为 %s" % (FILES["project"], value, TARGET))
        settings = PROJECT_SETTING_PATTERN.findall(project)
        if not settings:
            report.fail("%s 里解析不到 `MACOSX_DEPLOYMENT_TARGET`" % FILES["project"])
        else:
            report.checked += 1
            for value in settings:
                if value != TARGET:
                    report.fail("%s 的 MACOSX_DEPLOYMENT_TARGET = %s，应为 %s"
                                % (FILES["project"], value, TARGET))

    # 工程文件（生成物）：每一处都要一致 —— 只对一处等于纵容其余几处漂
    pbxproj = read(root, "pbxproj")
    if pbxproj is None:
        report.fail("缺 %s（生成物读不到；生成物过期与手改都该在这里露头）" % FILES["pbxproj"])
    else:
        values = PBXPROJ_PATTERN.findall(pbxproj)
        if not values:
            report.fail("%s 里一处 `MACOSX_DEPLOYMENT_TARGET` 都没有" % FILES["pbxproj"])
        else:
            report.checked += 1
            wrong = sorted({value for value in values if value != TARGET})
            if wrong:
                report.fail("%s 有 %d 处 MACOSX_DEPLOYMENT_TARGET 是 %s（应为 %s）"
                            % (FILES["pbxproj"], len(values), "、".join(wrong), TARGET))
            else:
                report.note("%s：%d 处 MACOSX_DEPLOYMENT_TARGET 全是 %s" % (FILES["pbxproj"], len(values), TARGET))

    # 产物信息：构建脚本里的 Info.plist 模板 = 权威
    build = read(root, "build")
    if build is None:
        report.fail("缺 %s（打包脚本读不到）" % FILES["build"])
    else:
        matches = PLIST_PATTERN.findall(build)
        if not matches:
            report.fail("%s 的 Info.plist 模板里没有 `LSMinimumSystemVersion`（老机器上不会有任何提示）"
                        % FILES["build"])
        else:
            report.checked += 1
            for value in matches:
                if value != TARGET:
                    report.fail("%s 的 LSMinimumSystemVersion = %s，应为 %s" % (FILES["build"], value, TARGET))


def check_architecture_surface(root: pathlib.Path, report: Report) -> None:
    """C：构建脚本认三档架构、universal 真走 lipo；跨架构取证脚本在位。"""
    build = read(root, "build")
    if build is None:
        report.fail("缺 %s（架构面无处可判）" % FILES["build"])
        return
    if len(build.splitlines()) < MIN_BUILD_CASE_MINUTES:
        report.fail("%s 只有 %d 行 ⇒ 扫描面疑似被砍（空跑防护）"
                    % (FILES["build"], len(build.splitlines())))
    # **认 case 分派臂，不认子串**：脚本头部注释里早就写着 `DOYAH_ARCH=universal`，
    # 按子串判的话把分派臂删掉仍然全绿（本判据第一版就这样，被自检例 7 当场抓住）。
    if "case \"${DOYAH_ARCH}\" in" not in build:
        report.fail("%s 里没有 `case \"${DOYAH_ARCH}\" in` 分派块" % FILES["build"])
    for arm, label in ((r"^\s{2}arm64\|x86_64\)", "arm64|x86_64)"),
                       (r"^\s{2}universal\)", "universal)")):
        if re.search(arm, build, flags=re.MULTILINE) is None:
            report.fail("%s 里没有 `%s` 这一条分派臂（DOYAH_ARCH 少了这一档）" % (FILES["build"], label))
    if "lipo -create" not in build:
        report.fail("%s 里没有 `lipo -create` ⇒ universal 只是标签，不是真合成" % FILES["build"])
    if "MACOSX_DEPLOYMENT_TARGET" in build:
        report.fail("%s 自己写了 MACOSX_DEPLOYMENT_TARGET（部署目标该只有 Package.swift / project.yml 两处源）"
                    % FILES["build"])

    universal = read(root, "universal")
    if universal is None:
        report.fail("缺 %s（跨架构构造没有取证脚本）" % FILES["universal"])
        return
    report.checked += 1
    if "lipo -info" not in universal:
        report.fail("%s 不用 `lipo -info` 判产物架构" % FILES["universal"])
    # 同样认**断言本身**（`grep -q "x86_64"`），不认注释里的架构名 —— 名字在注释里到处都是，
    # 按子串判等于给「把断言删掉」留了一条全绿的路（自检例 8 抓的就是这个）。
    if ('grep -q "arm64"' % ()) not in universal:
        report.fail("%s 没有 `grep -q \"arm64\"` 这条断言" % FILES["universal"])
    # universal 那一档的关键是**同一行里两个架构都要断言**（只断言一个 = 单架构也能过）
    if re.search(r'grep -q "arm64"[^\n]*grep -q "x86_64"', universal) is None:
        report.fail("%s 的 universal 档没有同时断言 arm64 与 x86_64" % FILES["universal"])
    if 'grep -q "fat file"' not in universal:
        report.fail("%s 没断言产物是 fat（universal）文件" % FILES["universal"])
    if "DOYAH_ARCH=universal" not in universal:
        report.fail("%s 没覆盖 `DOYAH_ARCH=universal` 那一档" % FILES["universal"])


def check_readings(path: pathlib.Path, report: Report) -> None:
    """D：读数对阈值。缺一项就报缺，**不当通过**。"""
    if not path.exists():
        report.fail("没有读数文件：%s（先 `DOYAH_ARCH=universal ./Scripts/build-app.sh` "
                    "再 `python3 Scripts/measure-platform-matrix.py --json-out %s`）" % (path, path))
        return
    try:
        readings = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        report.fail("读数文件不是合法 JSON（%s）：%s" % (error, path))
        return

    if readings.get("kind") != "platform-matrix":
        report.fail("读数文件的 kind = %r，不是 platform-matrix（拿错文件了？）" % readings.get("kind"))
        return

    archs = readings.get("archs") or []
    for arch in ("arm64", "x86_64"):
        if arch not in archs:
            report.fail("产物架构里没有 %s（实际：%s）" % (arch, archs or "空"))
    report.checked += 1

    slices = {item.get("arch"): item for item in (readings.get("slices") or [])}
    for arch in ("arm64", "x86_64"):
        slice_reading = slices.get(arch)
        if not slice_reading:
            report.fail("%s 切片没有读数（不知道它自己的 minos）" % arch)
            continue
        if slice_reading.get("minos") != TARGET:
            report.fail("%s 切片的 minos = %r，应为 %s" % (arch, slice_reading.get("minos"), TARGET))
    report.checked += 1

    if readings.get("plistMinimum") != TARGET:
        report.fail("产物 Info.plist 的 LSMinimumSystemVersion = %r，应为 %s"
                    % (readings.get("plistMinimum"), TARGET))
    report.checked += 1

    launches = {item.get("arch"): item for item in (readings.get("launches") or [])}
    for arch in ("arm64", "x86_64"):
        launch = launches.get(arch)
        if not launch:
            report.fail("%s 没有启动读数（没起过 ≠ 起得来）" % arch)
            continue
        runs = launch.get("runs") or []
        good = [item for item in runs if item.get("ok") and isinstance(item.get("elapsedMs"), (int, float))]
        if not runs:
            report.fail("%s 的启动读数是空的" % arch)
        elif len(good) != len(runs):
            reasons = "；".join(str(item.get("error")) for item in runs if not item.get("ok"))
            report.fail("%s 有 %d/%d 遍没写出启动收据：%s" % (arch, len(runs) - len(good), len(runs), reasons))
        elif any(item["elapsedMs"] <= 0 for item in good):
            report.fail("%s 的收据 elapsedMs ≤ 0（收据不可信）" % arch)
    report.checked += 1

    rosetta = readings.get("rosetta") or {}
    if rosetta.get("hostArch") == "arm64":
        if rosetta.get("available") is not True:
            report.fail("x86_64 那一档发生时 Rosetta 不在翻译态（proc_translated=%r）⇒ "
                        "「老架构能跑」这句话没证据" % rosetta.get("procTranslated"))
        else:
            report.note("Rosetta 翻译态：proc_translated=%s" % rosetta.get("procTranslated"))
    else:
        report.fail("读数不是在 arm64 宿主上取的（hostArch=%r）—— 本判据的口径只认本机"
                    % rosetta.get("hostArch"))

    measured_on = readings.get("measuredOn")
    if not measured_on:
        report.fail("读数没写 measuredOn（不知道是哪天量的）")


def evaluate(root: pathlib.Path, readings: pathlib.Path | None = None) -> Report:
    report = Report()
    check_deployment_target(root, report)
    check_architecture_surface(root, report)
    if readings is not None:
        check_readings(readings, report)
    if report.checked == 0:
        report.fail("一条检查都没真的跑起来（空跑防护）")
    return report


# ------------------------------------------------------------------ 自检

def copy_fixture(source: pathlib.Path, target: pathlib.Path) -> None:
    for relative in FILES.values():
        origin = source / relative
        if not origin.exists():
            continue
        destination = target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(origin, destination)


def mutate(root: pathlib.Path, relative: str, old: str, new: str, expect_red: bool, label: str) -> bool:
    path = root / relative
    original = path.read_text(encoding="utf-8")
    if old not in original:
        print("  ✗ 自检 %s：夹具里找不到要改的那一句（%s）" % (label, old))
        return False
    path.write_text(original.replace(old, new, 1), encoding="utf-8")
    report = evaluate(root)
    red = bool(report.problems)
    path.write_text(original, encoding="utf-8")
    ok = red == expect_red
    print("  %s 自检 %s：%s" % ("✓" if ok else "✗", label,
                               "判红（如预期）" if red else "判绿（如预期）"))
    if not ok:
        print("     期望 %s；实际 problems=%s" % ("红" if expect_red else "绿", report.problems))
    return ok


def readings_fixture(kind="platform-matrix", drop_arch=None, bad_minos=None, no_receipt_arch=None):
    readings = {
        "kind": kind,
        "measuredOn": "2026-11-02",
        "archs": ["arm64", "x86_64"],
        "slices": [
            {"arch": "arm64", "minos": bad_minos if bad_minos and bad_minos["arch"] == "arm64" else "14.0",
             "platform": "MACOS"},
            {"arch": "x86_64", "minos": bad_minos if bad_minos and bad_minos["arch"] == "x86_64" else "14.0",
             "platform": "MACOS"},
        ],
        "plistMinimum": "14.0",
        "launches": [
            {"arch": "arm64", "mode": "native",
             "runs": [{"ok": no_receipt_arch != "arm64", "elapsedMs": 300 if no_receipt_arch != "arm64" else None}],
             "ok": no_receipt_arch != "arm64"},
            {"arch": "x86_64", "mode": "rosetta",
             "runs": [{"ok": no_receipt_arch != "x86_64", "elapsedMs": 460 if no_receipt_arch != "x86_64" else None}],
             "ok": no_receipt_arch != "x86_64"},
        ],
        "rosetta": {"hostArch": "arm64", "available": True, "procTranslated": "1"},
    }
    if drop_arch:
        readings["archs"] = [arch for arch in readings["archs"] if arch != drop_arch]
    return readings


def self_test() -> int:
    root_source = BASE
    scratch = pathlib.Path(tempfile.mkdtemp(prefix="doyah-platform-compat-", dir=str(BASE / ".build")))
    ok = True
    try:
        fixture = scratch / "pristine"
        fixture.mkdir()
        copy_fixture(root_source, fixture)

        # 例 1：控制组 —— 干净夹具必须**绿**（否则后面每一条判红都不作数）
        pristine = evaluate(fixture)
        print("  例 1（控制组：干净夹具）%s" % ("✓ 绿" if not pristine.problems else "✗ 红：%s" % pristine.problems))
        ok = ok and not pristine.problems

        # 例 2：包定义降一档
        ok &= mutate(fixture, FILES["package"], ".macOS(.v14)", ".macOS(.v13)", True, "例 2（Package.swift .v13）")
        # 例 3：工程文件 deploymentTarget
        ok &= mutate(fixture, FILES["project"], 'macOS: "14.0"', 'macOS: "13.0"', True, "例 3（project.yml deploymentTarget）")
        # 例 4：生成物里只有一处漂
        pbx = (fixture / FILES["pbxproj"]).read_text(encoding="utf-8")
        first = PBXPROJ_PATTERN.search(pbx)
        if first is None:
            print("  ✗ 自检 例 4：pbxproj 里没有 MACOSX_DEPLOYMENT_TARGET（夹具坏了）")
            ok = False
        else:
            ok &= mutate(fixture, FILES["pbxproj"], first.group(0), "MACOSX_DEPLOYMENT_TARGET = 13.0;",
                         True, "例 4（pbxproj 一处漂到 13.0）")
        # 例 5：产物信息的最低版本被改松
        ok &= mutate(fixture, FILES["build"],
                     "<key>LSMinimumSystemVersion</key>\n    <string>14.0</string>",
                     "<key>LSMinimumSystemVersion</key>\n    <string>12.0</string>",
                     True, "例 5（Info.plist 模板 12.0）")
        # 例 6：最低版本键被摘掉（老机器上不再有任何提示）
        ok &= mutate(fixture, FILES["build"],
                     "<key>LSMinimumSystemVersion</key>\n    <string>14.0</string>",
                     "", True, "例 6（摘掉 LSMinimumSystemVersion）")
        # 例 7：universal 那一档被删（只剩单架构）
        ok &= mutate(fixture, FILES["build"], "  universal)", "  universal-removed)", True,
                     "例 7（build-app.sh 没有 universal 档）")
        # 例 8：跨架构取证脚本的断言被掏空
        ok &= mutate(fixture, FILES["universal"],
                     'grep -q "arm64" && echo "$REPORT" | grep -q "x86_64" \\',
                     'grep -q "arm64" \\', True,
                     "例 8（universal 档只剩 arm64 断言）")

        # 例 9–12：读数面
        readings_dir = scratch / "readings"
        readings_dir.mkdir()

        def judge(payload, label, expect_red):
            path = readings_dir / (label.replace(" ", "_") + ".json")
            path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
            report = evaluate(fixture, path)
            red = bool(report.problems)
            good = red == expect_red
            print("  %s 自检 %s：%s" % ("✓" if good else "✗", label, "判红（如预期）" if red else "判绿（如预期）"))
            if not good:
                print("     实际 problems=%s" % report.problems)
            return good

        ok &= judge(readings_fixture(), "例 9（读数齐全 ⇒ 绿）", False)
        ok &= judge(readings_fixture(drop_arch="x86_64"), "例 10（产物缺 x86_64）", True)
        ok &= judge(readings_fixture(bad_minos={"arch": "arm64", "minos": "15.0"}), "例 11（arm64 切片 minos 15.0）", True)
        ok &= judge(readings_fixture(no_receipt_arch="x86_64"), "例 12（x86_64 没写出收据）", True)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)

    print("自检：%s" % ("12 例全过" if ok else "有失败项，见上"))
    return 0 if ok else 1


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="平台矩阵门禁（NFR-ALL-GATE-COMP-004/005）")
    parser.add_argument("--root", default=str(BASE), help="仓根（自检用）")
    parser.add_argument("--readings", default=None, help="measure-platform-matrix.py 写出的 JSON")
    parser.add_argument("--self-test", action="store_true", help="跑判据自己的证据")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()

    root = pathlib.Path(args.root)
    readings = pathlib.Path(args.readings) if args.readings else None
    report = evaluate(root, readings)
    report.print()
    if report.problems:
        print("✗ 平台矩阵门禁：%d 处问题（检查 %d 面）" % (len(report.problems), report.checked))
        return 1
    print("✅ 平台矩阵门禁通过：部署目标 %s 四处一致 · 产物信息带最低版本键 · 构建脚本认三档架构 · 检查 %d 面"
          % (TARGET, report.checked))
    return 0


if __name__ == "__main__":
    sys.exit(main())
