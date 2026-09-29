#!/usr/bin/env python3
"""大结果集滚动的**阈值台账**判据（清单 §4 `FR-RES-07` / 队列 `L-89` ㈡ ④）。

为什么需要这条判据
------------------
探针 `TestsUISnapshot/LargeResultScrollProbeTests.swift` 的每一条上界（帧 p50 / 整幅重画 p50 /
行数放大比值 / 内存增量）都**从台账读**（`Scripts/result-scroll-baseline.json`），文件里不写魔数 ——
好处是"容差有来源"，坏处是**把上界改松就等于改判据**：`p50MsLimit` 从 2 改成 2000，探针照样绿。
所以本判据盯的是那份台账本身：

  1. 字段齐备（探针是 `Decodable` 强解，缺字段会红在探针里 —— 这里要**更早**报、并说清缺哪个键）；
  2. 规模对得上清单原文（≥ 1 万行 × 20 列，扫描位置数 ≥ 10）；
  3. **基线是正数**（`measured*`），每条上界对实测基线**至少有 3 倍余量**（不许紧到换台机器就红），
     也不许松到没有意义（各有上限档）；
  4. 理由非空（改阈值必须写明为什么，别只改数字）；
  5. **探针真挂在取证脚本上**：`TestsUISnapshot/` 里每个 `*ProbeTests.swift` 都要出现在
     `Scripts/run-manual-verification-probes.sh` 的 FILTER 里，否则必须在豁免表里写明理由 ——
     第 96 轮实测过「新用例没接进 `--filter` ⇒ 一个都跑不到」，本判据把这句话变成机械检查
     （落地当轮就抓出 `AppearanceAxesProbeTests` 自 2026-09-29 起没有任何脚本跑它）。

跑法：`python3 Scripts/check-result-scroll-ledger.py [--self-test]`
退出码：0 = 全绿；1 = 有红（逐条点名）。

判据自己的证据：`--self-test` **11 例**（红 / 绿成对：真台账绿 / 缺键 / 基线非正数 / 余量不足 /
上界松到超上限档（两处）/ 理由为空 / 规模缩水 / 探针没挂 FILTER / 豁免没写理由 /
末例核对真仓库台账逐字节未变且真跑 0 错）。
"""

from __future__ import annotations

import copy
import hashlib
import json
import pathlib
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
LEDGER_PATH = ROOT / "Scripts" / "result-scroll-baseline.json"
PROBES_SH = ROOT / "Scripts" / "run-manual-verification-probes.sh"
PROBE_DIR = ROOT / "TestsUISnapshot"

# 例外：**必须写明理由**。判据会把每一份例外逐条打印出来 —— 加豁免这件事在输出里看得见。
PROBE_WIRING_EXEMPT = {
    "AppearanceAxesProbeTests": (
        "要写真 UserDefaults（主题 / 深浅档键）：跑完虽逐键还原，但不该塞进无人值守的取证脚本"
        "（会短暂改到使用者正在用的外观偏好）⇒ 人工跑 `DOYAH_UI_SNAPSHOT=1 swift test --filter AppearanceAxesProbeTests`"
    ),
}

# 规模下限 = 清单原文（「查 1 万行 × 20 列，上下滚十几秒」）。
MIN_ROWS = 10_000
MIN_COLUMNS = 20
MIN_SCROLL_STEPS = 10

# 余量下限：上界至少是实测基线的这么多倍（否则换台机器 / 机器一忙就红）。
MIN_HEADROOM = 3.0

# 意义上限：上界不许松到拦不住任何东西（松过这几档，这条判据就是摆设）。
CAPS = {
    "frame.p50MsLimit": 50.0,
    "frame.rasterMsLimit": 500.0,
    "frame.scaleRatioLimit": 20.0,
    "memory.residentLimitMB": 256.0,
}

# 比值判据的分母下限（实测可能快到微秒级，此时比值失去意义）。
MIN_FLOOR_MS = 0.1


def _get(ledger: dict, path: str):
    """按 `a.b.c` 取键；缺键时返回 (None, 说明)。"""
    node = ledger
    for key in path.split("."):
        if not isinstance(node, dict) or key not in node:
            return None, f"台账缺键 `{path}`"
        node = node[key]
    return node, None


REQUIRED_KEYS = (
    "note", "measuredOn", "measuredBy", "smallRows", "largeRows", "columns", "scrollSteps",
    "frame.floorMs", "frame.p50MsLimit", "frame.rasterMsLimit", "frame.scaleRatioLimit",
    "frame.measuredSmallP50Ms", "frame.measuredLargeP50Ms",
    "frame.measuredRasterSmallP50Ms", "frame.measuredRasterLargeP50Ms", "frame.rationale",
    "memory.residentLimitMB", "memory.measuredDeltaMB", "memory.rationale",
)


def ledger_errors(ledger: dict) -> list[str]:
    errors: list[str] = []

    for path in REQUIRED_KEYS:
        _, error = _get(ledger, path)
        if error:
            errors.append(error)
    if errors:
        # 缺键就不再往下算：下面的比较会连锁报红，噪音大于信息。
        return errors

    frame, memory = ledger["frame"], ledger["memory"]

    if ledger["smallRows"] < MIN_ROWS:
        errors.append(f"smallRows = {ledger['smallRows']} < {MIN_ROWS}（清单原文就是 1 万行，别把被判的规模悄悄改小）")
    if ledger["largeRows"] <= ledger["smallRows"]:
        errors.append(f"largeRows = {ledger['largeRows']} 不比 smallRows 大 ⇒ 比值判据没有对照档")
    if ledger["columns"] < MIN_COLUMNS:
        errors.append(f"columns = {ledger['columns']} < {MIN_COLUMNS}（清单原文是 20 列）")
    if ledger["scrollSteps"] < MIN_SCROLL_STEPS:
        errors.append(f"scrollSteps = {ledger['scrollSteps']} < {MIN_SCROLL_STEPS}（位置太少 ⇒ 中位数不说明问题）")

    # 基线：必须是**测出来的正数**（0 / 负数 / nan 都是"没量过"）。
    baselines = {
        "frame.measuredSmallP50Ms": frame["measuredSmallP50Ms"],
        "frame.measuredLargeP50Ms": frame["measuredLargeP50Ms"],
        "frame.measuredRasterSmallP50Ms": frame["measuredRasterSmallP50Ms"],
        "frame.measuredRasterLargeP50Ms": frame["measuredRasterLargeP50Ms"],
    }
    for name, value in baselines.items():
        if not isinstance(value, (int, float)) or value <= 0:
            errors.append(f"基线 {name} = {value!r} ⇒ 不是量出来的正数（容差就没有来源了）")
    delta = memory["measuredDeltaMB"]
    if not isinstance(delta, (int, float)) or delta < 0:
        errors.append(f"memory.measuredDeltaMB = {delta!r} ⇒ 内存增量基线是负数/非数")

    # 余量：上界至少是实测基线的 MIN_HEADROOM 倍。
    p50_base = max(frame["measuredSmallP50Ms"], frame["measuredLargeP50Ms"], 0.5)
    if frame["p50MsLimit"] < MIN_HEADROOM * p50_base:
        errors.append(
            f"frame.p50MsLimit = {frame['p50MsLimit']} < {MIN_HEADROOM} × 基线 {p50_base} ⇒ 余量不足"
            f"（换台机器或机器一忙就红，成了一条抖动的判据）"
        )
    raster_base = max(frame["measuredRasterSmallP50Ms"], frame["measuredRasterLargeP50Ms"])
    if frame["rasterMsLimit"] < MIN_HEADROOM * raster_base:
        errors.append(f"frame.rasterMsLimit = {frame['rasterMsLimit']} < {MIN_HEADROOM} × 基线 {raster_base} ⇒ 余量不足")
    if memory["residentLimitMB"] < MIN_HEADROOM * max(delta, 4.0):
        errors.append(
            f"memory.residentLimitMB = {memory['residentLimitMB']} < {MIN_HEADROOM} × max(基线 {delta}, 4 MB) ⇒ 余量不足"
        )

    # 意义上限：松过这几档，判据就是摆设。
    for path, cap in sorted(CAPS.items()):
        value, _ = _get(ledger, path)
        if value > cap:
            errors.append(f"{path} = {value} > {cap} ⇒ 上界松到拦不住任何东西（这条判据成了摆设）")

    if frame["scaleRatioLimit"] < 1.2:
        errors.append(f"frame.scaleRatioLimit = {frame['scaleRatioLimit']} < 1.2 ⇒ 比值判据的容忍度小到只能是噪声")
    if not (MIN_FLOOR_MS <= frame["floorMs"] <= frame["rasterMsLimit"]):
        errors.append(
            f"frame.floorMs = {frame['floorMs']} 不在 [{MIN_FLOOR_MS}, rasterMsLimit={frame['rasterMsLimit']}] 内"
            f" ⇒ 比值判据的分母下限没意义"
        )

    # 理由：改数字必须说明为什么。
    for key, value in (("frame.rationale", frame["rationale"]), ("memory.rationale", memory["rationale"])):
        if not isinstance(value, str) or len(value.strip()) < 20:
            errors.append(f"{key} 太短/为空 ⇒ 阈值改动没有理由（只改数字不算）")

    return errors


def wiring_errors(probes_text: str, probe_files: list[str]) -> list[str]:
    """探针必须真挂在取证脚本上（第 96 轮那族的坑：写了用例却没接进 `--filter`）。"""
    errors: list[str] = []

    for name in probe_files:
        stem = name[: -len(".swift")]
        if stem in PROBE_WIRING_EXEMPT:
            continue
        if stem not in probes_text:
            errors.append(
                f"探针 TestsUISnapshot/{name} 没挂在 Scripts/run-manual-verification-probes.sh 上 —— "
                f"「写了用例却没接进 `--filter`」= 一个都跑不到；要么接进 FILTER，要么在 PROBE_WIRING_EXEMPT 里写明理由"
            )

    for stem, reason in PROBE_WIRING_EXEMPT.items():
        if f"{stem}.swift" not in probe_files:
            errors.append(f"豁免表里的 `{stem}` 已经不在 TestsUISnapshot/ 了 ⇒ 删掉这条豁免（别留僵尸豁免）")
        if len(reason.strip()) < 12:
            errors.append(f"豁免 `{stem}` 没有写明理由 ⇒ 例外必须可解释")

    return errors


def load_ledger() -> dict:
    return json.loads(LEDGER_PATH.read_text(encoding="utf-8"))


def probe_files() -> list[str]:
    return sorted(path.name for path in PROBE_DIR.glob("*ProbeTests.swift"))


def run_checks(ledger: dict, probes_text: str, files: list[str]) -> list[str]:
    return ledger_errors(ledger) + wiring_errors(probes_text, files)


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return self_test()

    ledger = load_ledger()
    probes_text = PROBES_SH.read_text(encoding="utf-8")
    files = probe_files()
    errors = run_checks(ledger, probes_text, files)

    frame, memory = ledger["frame"], ledger["memory"]
    print(f"📋 大结果集滚动的阈值台账：{LEDGER_PATH.relative_to(ROOT)}")
    print(
        f"   规模：{ledger['smallRows']} / {ledger['largeRows']} 行 × {ledger['columns']} 列，"
        f"{ledger['scrollSteps']} 个滚动位置（{ledger['measuredOn']} 实测）"
    )
    print(
        f"   帧（脏区重画）p50 上界 {frame['p50MsLimit']} ms"
        f"（基线 {frame['measuredSmallP50Ms']} / {frame['measuredLargeP50Ms']} ms）"
    )
    print(
        f"   整幅重画 p50 上界 {frame['rasterMsLimit']} ms"
        f"（基线 {frame['measuredRasterSmallP50Ms']} / {frame['measuredRasterLargeP50Ms']} ms）"
    )
    print(
        f"   行数放大比值上限 {frame['scaleRatioLimit']}×（分母下限 {frame['floorMs']} ms）｜"
        f"常驻内存增量上限 {memory['residentLimitMB']} MB（基线 {memory['measuredDeltaMB']} MB）"
    )
    print(f"   取证脚本挂载：{len(files)} 份探针，豁免 {len(PROBE_WIRING_EXEMPT)} 份")
    for stem in sorted(PROBE_WIRING_EXEMPT):
        print(f"     · 豁免 {stem}：{PROBE_WIRING_EXEMPT[stem]}")

    if errors:
        for item in errors:
            print(f"✗ {item}")
        return 1
    print("✓ 台账自洽：上界都有来源（实测基线）且留足余量、规模对得上清单原文、探针都挂在取证脚本上（豁免写明理由）")
    return 0


def self_test() -> int:
    """红 / 绿成对：每条规则都要有一条能打到它的负例。夹具 = 真台账的深拷贝，改完只在内存里。"""
    ledger = load_ledger()
    probes_text = PROBES_SH.read_text(encoding="utf-8")
    files = probe_files()
    digest_before = hashlib.sha256(LEDGER_PATH.read_bytes()).hexdigest()

    expectations: list[tuple[str, bool]] = []

    def expect(name: str, should_be_red: bool, ledger_fixture: dict, text: str = probes_text, names=None) -> None:
        errors = run_checks(ledger_fixture, text, files if names is None else names)
        got_red = bool(errors)
        ok = got_red == should_be_red
        detail = "" if not errors else f"（报红：{errors[0][:60]}…）"
        expectations.append((f"{'✓' if ok else '✗'} {name}：{'报红' if got_red else '不报红'}{detail}", ok))

    # ① 真台账必须绿。
    expect("真台账（应当绿）", False, copy.deepcopy(ledger))

    # ② 缺键（探针是强解，缺键必须在这里就更早报出来）。
    fixture = copy.deepcopy(ledger)
    del fixture["frame"]["rasterMsLimit"]
    expect("缺 `frame.rasterMsLimit`（应当红）", True, fixture)

    # ③ 基线不是正数（0 = 没量过 ⇒ 容差没有来源）。
    fixture = copy.deepcopy(ledger)
    fixture["frame"]["measuredLargeP50Ms"] = 0
    expect("基线实测值 0（应当红）", True, fixture)

    # ④ 上界余量不足（等于实测值 ⇒ 换台机器就红）。
    fixture = copy.deepcopy(ledger)
    fixture["frame"]["p50MsLimit"] = fixture["frame"]["measuredSmallP50Ms"]
    expect("帧 p50 上界没有余量（应当红）", True, fixture)

    # ⑤ 上界太紧：整幅重画上界放到判据拦不住的松度。
    fixture = copy.deepcopy(ledger)
    fixture["frame"]["rasterMsLimit"] = 1200.0
    expect("整幅重画上界松到超上限档（应当红）", True, fixture)

    # ⑥ 内存上界太松。
    fixture = copy.deepcopy(ledger)
    fixture["memory"]["residentLimitMB"] = 1024.0
    expect("内存上界松到超上限档（应当红）", True, fixture)

    # ⑦ 理由为空（只改数字不算）。
    fixture = copy.deepcopy(ledger)
    fixture["frame"]["rationale"] = ""
    expect("帧上界没有理由（应当红）", True, fixture)

    # ⑧ 规模缩水（把被判的规模悄悄改小，判据就轻了）。
    fixture = copy.deepcopy(ledger)
    fixture["smallRows"] = 100
    expect("规模缩到 100 行（应当红）", True, fixture)

    # ⑨ 探针没挂在取证脚本上（第 96 轮那族的坑）。
    expect(
        "探针没挂进 FILTER（应当红）",
        True,
        copy.deepcopy(ledger),
        text=probes_text.replace("LargeResultScrollProbeTests", "SomeOtherProbeTests"),
    )

    # ⑩ 豁免没有理由。
    global PROBE_WIRING_EXEMPT
    original_exempt = PROBE_WIRING_EXEMPT
    PROBE_WIRING_EXEMPT = {"AppearanceAxesProbeTests": "短"}
    expect("豁免没写理由（应当红）", True, copy.deepcopy(ledger))
    PROBE_WIRING_EXEMPT = original_exempt

    # ⑪ 自检不许改真仓库：末例核对台账逐字节未变 + 真跑一遍仍是 0 错。
    digest_after = hashlib.sha256(LEDGER_PATH.read_bytes()).hexdigest()
    ok = digest_before == digest_after and not run_checks(load_ledger(), probes_text, files)
    expectations.append((f"{'✓' if ok else '✗'} 真仓库台账逐字节未变且真跑 0 错（{digest_before[:12]}…）", ok))

    # 打印放在**全部造完之后**，并且迭代快照：第 59 条那个坑（迭代中往列表追加 ⇒ 打印没完没了）不能重演。
    for index, (line, _) in enumerate(list(expectations), start=1):
        print(f"  {index:02d} {line}")

    failed = [line for line, ok in expectations if not ok]
    print(f"自检：{len(expectations)} 例，{len(expectations) - len(failed)} 例符合预期，{len(failed)} 例不符合")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
