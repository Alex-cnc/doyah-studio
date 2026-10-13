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
     `Scripts/run-manual-verification-probes.sh` 的 `FILTER=` 清单里，否则必须在豁免表里写明理由 ——
     第 96 轮实测过「新用例没接进 `--filter` ⇒ 一个都跑不到」，本判据把这句话变成机械检查
     （落地当轮就抓出 `AppearanceAxesProbeTests` 自 2026-09-29 起没有任何脚本跑它）。
     **2026-10-14 收口**（合册 `T-20261013-027` · 原单 `T-20261010-034`）：判定物由
     「整份脚本的**全文**子串命中」改成 **`FILTER="…"` 赋值行**，并加**反向**校验（清单成员必须在
     盘上有对应文件 ⇒ 僵尸条目判红）、`FILTER=` 行解析不到 ⇒ 判红（空跑防护）、清单条数与
     盘上份数两条**下限读数** —— 旧实现只要探针名在脚本头部注释里被提过一次就判绿（那句注释逐条
     列了几乎所有探针名 ⇒ 「写了用例却没接进 `--filter`」那个坑原封不动）。

跑法：`python3 Scripts/check-result-scroll-ledger.py [--self-test]`
退出码：0 = 全绿；1 = 有红（逐条点名）。

判据自己的证据：`--self-test` **18 例**（红 / 绿成对：真台账绿 / 缺键 / 基线非正数 / 余量不足 /
上界松到超上限档（两处）/ 理由为空 / 规模缩水 / 名只从 `FILTER=` 删掉而注释仍逐条提 ⇒ 必红 /
新探针只写进注释、不进 `FILTER` ⇒ 必红 / `FILTER=` 有僵尸条目 ⇒ 必红 /
`FILTER=` 赋值行消失 ⇒ 必红 / 面被掏空 ⇒ 必红 / 零提及负对照 / 豁免没写理由 /
注释里提无关名字不误报 / 未知参数 rc=2 / 末例核对真仓库台账逐字节未变且真跑 0 错）。
"""

from __future__ import annotations

import copy
import hashlib
import json
import pathlib
import re
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


# `FILTER="…"` 赋值行 —— 判定物**就是这一行**，不是整份脚本的全文（见自检第 ⑨/⑩ 例）。
FILTER_RE = re.compile(r'^FILTER="([^"]*)"', re.M)

# 面下限（空跑防护）：低于即判红 —— 防「面被掏空 ⇒ 零命中 = 通过」。
# 2026-10-14 实测：TestsUISnapshot/*ProbeTests.swift 40 份 / FILTER= 成员 39 条（豁免 1 份）。
# 清单条数不另设下限：面完整时「正向逐份点名」已经保证清单至少 39 条（少一条就点那条的名字）。
PROBE_FLOOR = 40


def filter_members(probes_text: str) -> tuple[list[str] | None, str | None]:
    """取 `FILTER="…"` 清单（判定物 = **赋值行**）。返回 (成员表, 错因)。

    2026-10-14 收口（合册 `T-20261013-027` · 原单 `T-20261010-034`）：旧实现把判定物写成
    **整份脚本的全文**，而 `run-manual-verification-probes.sh` 的头部注释逐条列了几乎所有探针名
    ⇒ 名字只要在注释里被提过一次就判绿（「写了用例却没接进 `--filter`」那个坑原封不动）。
    现在只认赋值行，并要求**恰好一处**（多处 = 判定物不唯一）。
    """
    matches = FILTER_RE.findall(probes_text)
    if not matches:
        return None, (
            "取证脚本里找不到 `FILTER=\"…\"` 赋值行 ⇒ 判定物没了（空跑防护："
            "不许把「清单消失」当成「全都挂上了」判绿）"
        )
    if len(matches) > 1:
        return None, f"取证脚本里有 {len(matches)} 处 `FILTER=\"…\"` 赋值行 ⇒ 判定物不唯一（要求恰好一处）"
    return [item.strip() for item in matches[0].split("|") if item.strip()], None


def wiring_errors(probes_text: str, probe_files: list[str]) -> list[str]:
    """探针必须**真挂在 `FILTER=` 清单里**（第 96 轮那族的坑：写了用例却没接进 `--filter`，
    一个都跑不到）。两向都判，且都点名到具体名字：

      · 正向：盘上每份 `*ProbeTests.swift` 都得是 `FILTER=` 的成员（豁免表里的除外）；
      · 反向：`FILTER=` 的每个成员都得在盘上有对应文件（僵尸条目 = 名字留了、文件没了）。
    """
    errors: list[str] = []

    # 面下限：面被掏空时不许「零命中 = 通过」。
    if len(probe_files) < PROBE_FLOOR:
        errors.append(
            f"TestsUISnapshot/ 里只数到 {len(probe_files)} 份 `*ProbeTests.swift`（下限 {PROBE_FLOOR}）"
            f" ⇒ 判定面被掏空（空跑防护：面没了不许当全绿）"
        )
        return errors

    members, error = filter_members(probes_text)
    if error:
        return errors + [error]

    member_set = set(members)
    on_disk = {name[: -len(".swift")] for name in probe_files}

    for name in probe_files:
        stem = name[: -len(".swift")]
        if stem in PROBE_WIRING_EXEMPT:
            continue
        if stem not in member_set:
            errors.append(
                f"探针 TestsUISnapshot/{name} 没挂在 Scripts/run-manual-verification-probes.sh 的 "
                f"`FILTER=` 清单里 —— 「写了用例却没接进 `--filter`」= 一个都跑不到"
                f"（光在注释里被提到不算）；要么接进 FILTER，要么在 PROBE_WIRING_EXEMPT 里写明理由"
            )

    for stem in sorted(member_set - on_disk):
        errors.append(
            f"`FILTER=` 里的 `{stem}` 在 TestsUISnapshot/ 里没有对应文件（僵尸条目）"
            f" ⇒ 要么删掉这条，要么把文件补回来（清单与盘面必须双向对得上）"
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
    unknown = [item for item in argv if item != "--self-test"]
    if unknown:
        print(f"未知参数：{' '.join(unknown)}（用法：`--self-test`）⇒ 不静默吞掉参数，rc=2")
        return 2
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
    members, _why = filter_members(probes_text)
    reading = f"{len(members)} 条" if members is not None else "解析不到"
    print(
        f"   取证脚本挂载：FILTER= 清单 {reading} / 盘上 {len(files)} 份探针"
        f"（面下限 {PROBE_FLOOR}），豁免 {len(PROBE_WIRING_EXEMPT)} 份"
    )
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

    base_members = filter_members(probes_text)[0]

    def with_filter(text: str, members: list[str]) -> str:
        return FILTER_RE.sub('FILTER="' + "|".join(members) + '"', text, count=1)

    # ⑨ 名只从 `FILTER=` 赋值行删掉、注释仍逐条提它 ⇒ 必红（旧实现判绿 = 假绿，原单 B 档）。
    expect(
        "名只从 FILTER= 删掉、注释仍提（应当红）",
        True,
        copy.deepcopy(ledger),
        text=with_filter(probes_text, [m for m in base_members if m != "LargeResultScrollProbeTests"]),
    )

    # ⑩ 新增探针的文件名**只写进注释**、不进 FILTER ⇒ 必红（原单 B2 档 / 第 96 轮那类事故的形状）。
    expect(
        "新探针只写进注释、不进 FILTER（应当红）",
        True,
        copy.deepcopy(ledger),
        text=probes_text + "\n# TestsUISnapshot/PlantedNewProbeTests.swift 判 …（只写在注释里）\n",
        names=files + ["PlantedNewProbeTests.swift"],
    )

    # ⑪ 反向：`FILTER=` 里多出一个盘上没有的名字（僵尸条目）⇒ 必红（旧实现不查这一向）。
    expect(
        "FILTER= 有盘上没有的僵尸条目（应当红）",
        True,
        copy.deepcopy(ledger),
        text=with_filter(probes_text, base_members + ["ZombieProbeTests"]),
    )

    # ⑫ `FILTER=` 赋值行整个消失 ⇒ 必红（空跑防护：判定物没了不许当全绿）。
    expect(
        "FILTER= 赋值行消失（应当红）",
        True,
        copy.deepcopy(ledger),
        text="\n".join(l for l in probes_text.splitlines() if not l.startswith('FILTER="')) + "\n",
    )

    # ⑬ 面被掏空（盘上只剩 1 份探针）⇒ 必红（旧实现照旧按「剩下的那份都在全文里」判绿）。
    expect("面被掏空（盘上只剩 1 份）（应当红）", True, copy.deepcopy(ledger), names=files[:1])

    # ⑭ 负对照：全文零提及（旧实现的真红面）—— 新旧两版都必须红。
    expect(
        "全文零提及（应当红）",
        True,
        copy.deepcopy(ledger),
        text=probes_text.replace("LargeResultScrollProbeTests", "SomeOtherProbeTests"),
    )

    # ⑮ 豁免没有理由。旧 ⑩
    global PROBE_WIRING_EXEMPT
    original_exempt = PROBE_WIRING_EXEMPT
    PROBE_WIRING_EXEMPT = {"AppearanceAxesProbeTests": "短"}
    expect("豁免没写理由（应当红）", True, copy.deepcopy(ledger))
    PROBE_WIRING_EXEMPT = original_exempt

    # ⑯ 对手臂：注释里提一个与探针无关的名字（不在盘上、也不在 FILTER）⇒ 不许误报。
    expect(
        "注释里提无关名字（不许误报）",
        False,
        copy.deepcopy(ledger),
        text=probes_text + "\n# 顺带提一个跟探针无关的名字 FooProbeTests（既不在盘上、也不在 FILTER）\n",
    )

    # ⑰ 参数面：未知参数不许静默吞掉（旧实现把 `--nonsense` 当没看见、照旧判绿）。
    code = main(["--nonsense"])
    expectations.append((f"{'✓' if code == 2 else '✗'} 未知参数 ⇒ rc=2（实得 {code}）", code == 2))
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
