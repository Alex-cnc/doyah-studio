#!/usr/bin/env python3
"""面板根固定尺寸 `.frame(width:height:)` 的对齐纪律（队列 L-61，闭环第 9 项）。

为什么需要这条判据（第 41 轮修 L-58 时实测出来的**一类**问题）：
    `PrivilegePanel` 的内容在它自己的 `720×620` 里被**垂直居中**（顶上约 150pt 空白），
    根因是 `.frame(width:height:)` **不写 `alignment:`** ⇒ SwiftUI 取默认 `.center`，
    而那个 `VStack` 里**没有可伸缩高度的子视图** ⇒ 内容整体浮在中间。
    同批抽查另外三块面板不这样（`ServerObjectsPanel` 的 `content` 有
    `.frame(maxHeight: .infinity)`、`DatabaseStatsPanel` 靠 `ScrollView` 撑满）。
    当时所有门禁全绿 —— 「内容在自己尺寸里浮着」这件事**没有任何判据在看**。

判据为什么只能做成「纪律」而不是「真值判断」（先把边界说清，别假装判得住）：
    「有没有可伸缩高度的子视图」**静态查不出来**（SwiftUI 的尺寸协商要看运行期），
    而且**内容撑满时居中与顶对齐视觉等价**（`ServerObjectsPanel` / `DatabaseStatsPanel`）。
    所以本判据判的是 —— **面板根必须把意图写出来**，并且写出**理由**（理由要有盘上锚点）：
      · 路线一 `explicit-alignment`：源码里**显式写** `alignment:`（写什么都没关系，
        包括 `.center` —— 重要的是**下一个人一眼看得见**这是有意选的），登记里记下写了什么；
      · 路线二 `content-stretches`：登记一个 `stretchProbe`，它是**撑满高度的容器**令牌
        （`ScrollView {` / `List(` / `maxHeight: .infinity` … 见台账 `probeVocab`），
        门禁核对它**真的出现在同一个视图类型里**。
    两条路线都走不通的面板根（既没写 `alignment:`、类型里又没有撑满容器）**过不去** ——
    这时唯一的出路是**显式写意图**（写了 `.center` 就等于承认「我就是要居中」，要配理由）。
    这条正是 L-58 那个缺陷下一次会被挡住的地方。

判据（A~F）：
    A 扫描完整性 · 双向对账：`App/Views/**/*.swift` 里每一处「宽高都是数字字面量」的 `.frame`
      恰好一条台账（按 `file` + `symbol` + `frame` 文本 + `count` 对账）；台账里**已不在盘上**
      的条目（陈旧）与盘上**没登记的**（新增）一样判红 —— 一条都不靠人眼。
    B 分类：`width >= panelRootMinWidth`（台账里声明，现为 400）必须是 `panel-root`，
      否则必须是 `ornament`（把 17 处装饰当成面板根、或反过来，都判红）。
    C 面板根必须把意图写出来：`intent` 取自台账 `intentVocab`；`content-stretches` 必须给
      `stretchProbe` 且它在**该类型范围内**真的存在；`explicit-alignment` 必须给 `alignment`
      且**源码那次调用真的带这个值**（登记说写了 `.top`、代码里没有 ⇒ 红）。
    D 理由不许空：每条登录条目必须有非空 `note`（「理由是空的」等于没写理由）。
    E 空跑防护：扫到的文件数 / 命中数 / 面板根数 / 台账条目数各有下限；台账声明的
      `scannedFiles` 与 `totals` 必须与磁盘事实相等（「扫了个寂寞」不许当通过）。
    F 边界如实打印：**只判两个维度都是数字字面量**的固定尺寸；用设计令牌 / 变量给尺寸的
      `.frame(...)`（`Metrics.*` / `Spacing.*` / 局部变量）**不在本判据范围**（它们由闭环
      第 6 项的设计令牌棘轮管），数量每次**显式打印**出来 —— 靠打印区分「没有」与「没扫」。

不判（写进 docstring，免得上床不知道边界）：
    · 不判居中**对不对**（见上：静态查不出可伸缩子视图）；本判据的价值在**棘轮**：
      新加一块面板根必须选一条路线、并把理由留在台账里，而下一次 L-58 那种「没有撑满容器
      还想蒙混过去」的写法两条路线都走不通。
    · 不看**注释里的** `.frame(width:height:)`（`PrivilegePanel` 里那句说明文字就是它）——
      扫描前先剥注释与字符串字面量。
    · `stretchProbe` 用**子串匹配**（在该视图类型的范围内出现即可），不做语法级证明 ——
      它是「理由有盘上锚点」而不是「编译器也这么认为」；所以 `List(` 这种会撞上
      `parseList(` 的写法**不进词表**（第 63 轮实测：探针 v1 就把 `Self.parseList(` 当成了
      `List(`，数据任务面板因此被误判成「有 List」）。
    · 不判 `alignment:` 的值好不好（`.top` / `.leading` / `.center` 都可能对）。

用法：
    python3 Scripts/check-panel-root-frames.py                     # 校验（闸门）
    python3 Scripts/check-panel-root-frames.py --report            # 只看盘上事实与分类
    python3 Scripts/check-panel-root-frames.py --self-test         # 负例自检（临时副本上写坏）
    python3 Scripts/check-panel-root-frames.py --views A --ledger B   # 指定输入（自检用）
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import shutil
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
VIEWS = ROOT / "App" / "Views"
LEDGER = ROOT / "Scripts" / "panel-root-frames.json"

# 扫描范围与门槛
VIEW_GLOB = "*.swift"
MIN_SCANNED_FILES = 40      # 真值 65；下限留余量，但绝不许「一个文件都没扫到」
MIN_FRAMES = 25             # 真值 33
MIN_PANEL_ROOTS = 15        # 真值 21

# 本判据只管**两个维度都是数字字面量**的固定尺寸（允许 `1_060` 这种下划线分隔）
NUMBER = re.compile(r"^[0-9][0-9_]*$")
SYMBOL = re.compile(
    r"^(?:@\w+\s+)*(?:(?:public|private|internal|final)\s+)*(?:struct|class|enum)\s+(\w+)\s*:\s*View\b"
)
FRAME_CALL = re.compile(r"\.frame\(")


def strip_comments_and_strings(text: str) -> str:
    """剥掉行注释 / 块注释 / 字符串与字符字面量的内容，保留换行与长度（行号不变）。

    为什么要剥：`App/Views/PrivilegePanel.swift` 的说明注释里就写着
    `` `.frame(width:height:)` 不写 `alignment` `` —— 不剥的话它会被当成一次调用。
    """
    out: list[str] = []
    i = 0
    n = len(text)
    while i < n:
        two = text[i : i + 2]
        if two == "//":
            while i < n and text[i] != "\n":
                out.append(" ")
                i += 1
            continue
        if two == "/*":
            out.append("  ")
            i += 2
            while i < n and text[i : i + 2] != "*/":
                out.append("\n" if text[i] == "\n" else " ")
                i += 1
            if i < n:
                out.append("  ")
                i += 2
            continue
        if text[i] == "\\":  # 字符串里的转义（`\\"`）不许被当成字符串结尾
            out.append(text[i : i + 2])
            i += 2
            continue
        if text[i] in "\"'":
            quote = text[i]
            out.append(" ")
            i += 1
            while i < n and text[i] != quote:
                if text[i] == "\\":
                    out.append("  ")
                    i += 2
                    continue
                out.append("\n" if text[i] == "\n" else " ")
                i += 1
            if i < n:
                out.append(" ")
                i += 1
            continue
        out.append(text[i])
        i += 1
    return "".join(out)


def frame_calls(text: str) -> list[tuple[int, str]]:
    """返回 [(行号, 调用体), …]；调用体 = `.frame(` 到配对右括号之间的原文。"""
    cleaned = strip_comments_and_strings(text)
    found: list[tuple[int, str]] = []
    for match in FRAME_CALL.finditer(cleaned):
        start = match.end()
        depth = 1
        j = start
        while j < len(cleaned) and depth > 0:
            if cleaned[j] == "(":
                depth += 1
            elif cleaned[j] == ")":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        body = cleaned[start:j]
        line = cleaned.count("\n", 0, match.start()) + 1
        found.append((line, body))
    return found


def split_arguments(body: str) -> list[str]:
    """按顶层逗号切参数（括号内的逗号不算）。"""
    parts: list[str] = []
    depth = 0
    cur = ""
    for char in body:
        if char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        if char == "," and depth == 0:
            parts.append(cur)
            cur = ""
            continue
        cur += char
    parts.append(cur)
    return [p.strip() for p in parts if p.strip()]


def parse_call(body: str) -> dict[str, str]:
    parsed: dict[str, str] = {}
    for argument in split_arguments(body):
        if ":" not in argument:
            continue
        name, _, value = argument.partition(":")
        name = name.strip()
        if name in {"width", "height", "alignment"} and name not in parsed:
            parsed[name] = " ".join(value.split())
    return parsed


class Entry:
    """盘上的一处固定尺寸 frame（或台账里的一条）。"""

    def __init__(self, file: str, symbol: str, width: int, height: int, count: int = 1,
                 alignment: str = "", line: int = 0):
        self.file = file
        self.symbol = symbol
        self.width = width
        self.height = height
        self.count = count
        self.alignment = alignment
        self.line = line

    @property
    def frame(self) -> str:
        return f"width: {self.width}, height: {self.height}"

    @property
    def key(self) -> tuple[str, str, str]:
        return (self.file, self.symbol, self.frame)

    def kind_with(self, min_width: int) -> str:
        return "panel-root" if self.width >= min_width else "ornament"


def scan(views: pathlib.Path, min_width: int) -> tuple[dict[tuple[str, str, str], Entry],
                                                      dict[tuple[str, str, str], Entry],
                                                      int, int, int]:
    """扫盘。返回 (固定尺寸条目, 令牌尺寸条目, 文件数, 固定尺寸命中数, 令牌尺寸命中数)。"""
    entries: dict[tuple[str, str, str], Entry] = {}
    token_entries: dict[tuple[str, str, str], Entry] = {}
    files = sorted(views.rglob(VIEW_GLOB))
    for path in files:
        lines = path.read_text(encoding="utf-8").splitlines()
        decls = [(i, SYMBOL.match(line).group(1)) for i, line in enumerate(lines) if SYMBOL.match(line)]
        for line_number, body in frame_calls("\n".join(lines)):
            parsed = parse_call(body)
            if "width" not in parsed or "height" not in parsed:
                continue
            width_text, height_text = parsed["width"], parsed["height"]
            symbol, start = "?", 0
            for i, name in decls:
                if i <= line_number - 1:
                    symbol, start = name, i
            end = next((i for i, _ in decls if i > start), len(lines))
            relative = path.relative_to(views.parent.parent).as_posix()
            if not (NUMBER.match(width_text) and NUMBER.match(height_text)):
                key = (relative, symbol, f"width: {width_text}, height: {height_text}")
                entry = token_entries.setdefault(key, Entry(relative, symbol, -1, -1, 0, parsed.get("alignment", "")))
                entry.count += 1
                continue
            width = int(width_text.replace("_", ""))
            height = int(height_text.replace("_", ""))
            key = (relative, symbol, f"width: {width}, height: {height}")
            entry = entries.get(key)
            if entry is None:
                entry = Entry(relative, symbol, width, height, 0, parsed.get("alignment", ""), line_number)
                entries[key] = entry
            entry.count += 1
    return entries, token_entries, len(files), sum(e.count for e in entries.values()), \
        sum(e.count for e in token_entries.values())


def symbol_range(views: pathlib.Path, relative: str, symbol: str) -> list[str]:
    path = views.parent.parent / relative
    lines = path.read_text(encoding="utf-8").splitlines()
    start = next((i for i, line in enumerate(lines) if SYMBOL.match(line)
                  and SYMBOL.match(line).group(1) == symbol), None)
    if start is None:
        return []
    end = next((i for i, line in enumerate(lines) if i > start and SYMBOL.match(line)), len(lines))
    return lines[start:end]


def evaluate(views: pathlib.Path, ledger_path: pathlib.Path) -> tuple[list[str], list[str]]:
    problems: list[str] = []
    notes: list[str] = []
    ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
    min_width = ledger.get("panelRootMinWidth")
    if not isinstance(min_width, int):
        problems.append("台账缺 `panelRootMinWidth`（面板根的门槛必须写在台账里，不许散在代码里）")
        return problems, notes
    on_disk, token_frames, file_count, frame_count, token_count = scan(views, min_width)
    roots = [e for e in on_disk.values() if e.kind_with(min_width) == "panel-root"]
    ornaments = [e for e in on_disk.values() if e.kind_with(min_width) == "ornament"]
    root_count = sum(e.count for e in roots)        # 处数（含同一形状出现多次）
    ornament_count = sum(e.count for e in ornaments)

    # E 空跑防护
    if file_count < MIN_SCANNED_FILES:
        problems.append(f"空跑防护：只扫到 {file_count} 个视图文件（下限 {MIN_SCANNED_FILES}）—— 目录挪了或通配失效，不许当通过")
    if frame_count < MIN_FRAMES:
        problems.append(f"空跑防护：只命中 {frame_count} 处固定尺寸 frame（下限 {MIN_FRAMES}）")
    if root_count < MIN_PANEL_ROOTS:
        problems.append(f"空跑防护：只解析到 {root_count} 处面板根（下限 {MIN_PANEL_ROOTS}）")

    declared_files = ledger.get("scannedFiles")
    if declared_files != file_count:
        problems.append(f"台账 `scannedFiles` = {declared_files}，实测 {file_count}（扫描范围变了要同步台账）")
    totals = ledger.get("totals") or {}
    if totals.get("frames") != frame_count:
        problems.append(f"台账 `totals.frames` = {totals.get('frames')}，实测 {frame_count}")
    if totals.get("panelRoots") != root_count:
        problems.append(f"台账 `totals.panelRoots` = {totals.get('panelRoots')}，实测 {root_count}")
    if totals.get("ornaments") != ornament_count:
        problems.append(f"台账 `totals.ornaments` = {totals.get('ornaments')}，实测 {ornament_count}")

    items = ledger.get("items") or []
    if not items:
        problems.append("空跑防护：台账 `items` 为空 —— 一本空账也能全绿的话，这条门禁就是没有")
        return problems, notes
    intents = set((ledger.get("intentVocab") or {}).keys())
    probes = list((ledger.get("probeVocab") or {}).keys())

    registered: dict[tuple[str, str, str], dict] = {}
    for item in items:
        key = (item.get("file", ""), item.get("symbol", ""), item.get("frame", ""))
        if key in registered:
            problems.append(f"台账里 {key[0]} / {key[1]} / {key[2]} 出现两次")
            continue
        registered[key] = item

    # A 双向对账
    for key, entry in sorted(on_disk.items()):
        item = registered.get(key)
        if item is None:
            hint = "（面板根必须选一条路线：显式写 `alignment:` 或在台账里写撑满理由）" \
                if entry.kind_with(min_width) == "panel-root" else ""
            problems.append(
                f"未登记：{entry.file}:{entry.line} {entry.symbol} `.frame({entry.frame})` "
                f"[{entry.kind_with(min_width)}] 不在台账里{hint}"
            )
            continue
        if item.get("count") != entry.count:
            problems.append(
                f"处数不符：{entry.file} {entry.symbol} `.frame({entry.frame})` "
                f"盘上 {entry.count} 处 / 台账 {item.get('count')} 处"
            )
    for key, item in sorted(registered.items()):
        if key not in on_disk:
            problems.append(
                f"陈旧条目：台账里的 {key[0]} / {key[1]} / `{key[2]}` 在盘上已找不到"
                "（改尺寸 / 删调用都要同轮销账，别留陈旧条目）"
            )

    # B~D 逐条判
    for key, entry in sorted(on_disk.items()):
        item = registered.get(key)
        if item is None:
            continue
        where = f"{entry.file}:{entry.line} {entry.symbol}"
        kind = item.get("kind")
        if kind != entry.kind_with(min_width):
            problems.append(
                f"{where}：`{entry.frame}` 的分类是 `{entry.kind_with(min_width)}`，台账写的是 `{kind}`"
                f"（面板根门槛 = width ≥ {min_width}）"
            )
        note = (item.get("note") or "").strip()
        if not note:
            problems.append(f"{where}：台账 `note` 为空 —— 理由不许空（D 条）")
        if entry.kind_with(min_width) == "ornament":
            continue
        intent = item.get("intent")
        if intent not in intents:
            problems.append(
                f"{where}：面板根的 `intent` = {intent!r} 不在台账词表里（{'/'.join(sorted(intents))}）"
            )
            continue
        if intent == "content-stretches":
            probe = item.get("stretchProbe") or ""
            if probe not in probes:
                problems.append(
                    f"{where}：`stretchProbe` = {probe!r} 不在台账 `probeVocab` 里"
                    "（词表外的形状等于自己发明一个理由）"
                )
                continue
            if probe not in "\n".join(symbol_range(views, entry.file, entry.symbol)):
                problems.append(
                    f"{where}：登记为 `content-stretches`，但撑满令牌 {probe!r} "
                    f"在 `{entry.symbol}` 里一处都不出现 —— 理由没有盘上锚点（C 条）"
                )
            if entry.alignment:
                problems.append(
                    f"{where}：源码这次调用已显式写 `alignment: {entry.alignment}`，"
                    "台账却还按 `content-stretches` 登记（意图写出来了就要如实改登记）"
                )
        elif intent == "explicit-alignment":
            declared = (item.get("alignment") or "").strip()
            if not declared:
                problems.append(f"{where}：`explicit-alignment` 必须写清源码里写的是哪个值（`alignment` 字段）")
            elif not entry.alignment:
                problems.append(
                    f"{where}：台账说源码显式写了 `alignment: {declared}`，但盘上这次调用没有 `alignment:`"
                    "（写了才算把意图写出来，删掉即红）"
                )
            elif entry.alignment != declared:
                problems.append(
                    f"{where}：源码写的是 `alignment: {entry.alignment}`，台账记的是 `{declared}`"
                )

    notes.append(
        f"视图文件 {file_count} 个 / 固定尺寸 frame {frame_count} 处（面板根 {root_count} · 装饰 {ornament_count}）"
        f" / 台账 {len(items)} 条"
    )
    routes: dict[str, int] = {}
    for item in items:
        if item.get("kind") == "panel-root":
            routes[item.get("intent", "?")] = routes.get(item.get("intent", "?"), 0) + 1
    if routes:
        notes.append("面板根路线分布：" + " / ".join(f"{k} {routes[k]}" for k in sorted(routes)))
    notes.append(
        f"范围外（如实打印，不算通过）：另有 {token_count} 处 `.frame(...)` 的尺寸取自设计令牌 / 变量"
        f"（{len(token_frames)} 种形状）—— 它们由闭环第 6 项的设计令牌棘轮管，不在本判据范围"
    )
    return problems, notes


def fingerprint(paths: list[pathlib.Path]) -> dict[str, str]:
    return {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths if p.exists()}


def self_test() -> int:
    """负例自检：一律在**临时副本**上写坏，末例核对真仓库逐字节未变。"""
    before = fingerprint([LEDGER, VIEWS / "DatabaseStatsPanel.swift", VIEWS / "PrivilegePanel.swift"])
    cases: list[tuple[str, str]] = []
    with tempfile.TemporaryDirectory(prefix="panel-root-") as tmp:
        tmpdir = pathlib.Path(tmp)
        sandbox = tmpdir / "repo"
        shutil.copytree(VIEWS.parent.parent / "App", sandbox / "App",
                        ignore=shutil.ignore_patterns("*.png", "*.jpg"))
        base_ledger = tmpdir / "panel-root-frames.json"
        shutil.copyfile(LEDGER, base_ledger)
        fixture_views = sandbox / "App" / "Views"

        def fresh() -> tuple[pathlib.Path, pathlib.Path]:
            ledger = tmpdir / "ledger.json"
            shutil.copyfile(base_ledger, ledger)
            return fixture_views, ledger

        def mutate_ledger(led: pathlib.Path, fn) -> None:
            data = json.loads(led.read_text(encoding="utf-8"))
            fn(data)
            led.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

        def restore(relative: str) -> None:
            shutil.copyfile(VIEWS.parent.parent / relative, sandbox / relative)

        def expected(name: str) -> bool:
            return not (name.startswith("前提自检") or name.startswith("末例"))

        def record(name: str, problems: list[str], needle: str = "") -> None:
            red = bool(problems)
            if needle and red:
                red = any(needle in p for p in problems)
            cases.append((name, "红" if red else "绿" if not problems else "红（但不是预期那条）"))

        # 0 前提自检：干净副本必须全绿
        views, led = fresh()
        problems, _ = evaluate(views, led)
        cases.append(("前提自检：干净副本应全绿", "绿" if not problems else f"红：{problems[0]}"))

        # 1 新增未登记的面板根（在既有面板上加一处）
        views, led = fresh()
        target = views / "DiagnosisPanel.swift"
        text = target.read_text(encoding="utf-8")
        target.write_text(text.replace("        .frame(width: 760, height: 700)",
                                       "        .frame(width: 700, height: 600)\n        .frame(width: 760, height: 700)", 1),
                          encoding="utf-8")
        problems, _ = evaluate(views, led)
        record("新增未登记的面板根", problems, "未登记")
        restore("App/Views/DiagnosisPanel.swift")

        # 2 撑满令牌不在该类型里（把理由锚点指到一个不存在的容器）
        views, led = fresh()
        mutate_ledger(led, lambda d: [x.update({"stretchProbe": "maxHeight: .infinity"})
                                      for x in d["items"] if x["file"].endswith("AboutLicenseSheet.swift")])
        problems, _ = evaluate(views, led)
        record("撑满令牌在类型里找不到", problems, "锚点")

        # 3 （登记了 probeVocab 之外的形状）
        views, led = fresh()
        mutate_ledger(led, lambda d: [x.update({"stretchProbe": "// 反正就是撑满"})
                                      for x in d["items"] if x["file"].endswith("LockPanel.swift")])
        problems, _ = evaluate(views, led)
        record("理由形状不在词表里", problems, "probeVocab")

        # 4 台账陈旧（盘上那处 frame 被改名 / 改尺寸）
        views, led = fresh()
        target = views / "LockPanel.swift"
        target.write_text(target.read_text(encoding="utf-8").replace(
            ".frame(width: 760, height: 560)", ".frame(width: 760, height: 570)"), encoding="utf-8")
        problems, _ = evaluate(views, led)
        record("陈旧条目（改尺寸没销账）", problems, "陈旧")
        restore("App/Views/LockPanel.swift")

        # 5 删掉一条台账（盘上那条没人管了）
        views, led = fresh()
        mutate_ledger(led, lambda d: d["items"].pop(
            next(i for i, x in enumerate(d["items"]) if x["file"].endswith("SessionPanel.swift"))))
        problems, _ = evaluate(views, led)
        record("盘上有、台账里没有", problems, "未登记")

        # 6 登记 explicit-alignment，源码里把 alignment 删掉
        views, led = fresh()
        target = views / "PrivilegePanel.swift"
        target.write_text(target.read_text(encoding="utf-8").replace(
            ".frame(width: 720, height: 620, alignment: .top)", ".frame(width: 720, height: 620)"),
            encoding="utf-8")
        problems, _ = evaluate(views, led)
        record("显式对齐被删（但登记还在）", problems, "没有 `alignment:`")
        restore("App/Views/PrivilegePanel.swift")

        # 7 台账谎报写了什么值
        views, led = fresh()
        mutate_ledger(led, lambda d: [x.update({"alignment": ".bottom"})
                                      for x in d["items"] if x["file"].endswith("ImportPanel.swift")])
        problems, _ = evaluate(views, led)
        record("台账与源码写的值不一致", problems, "台账记的是")

        # 8 分类写错（把一处装饰标成面板根）
        views, led = fresh()
        mutate_ledger(led, lambda d: [x.update({"kind": "panel-root", "intent": "content-stretches",
                                                "stretchProbe": "ScrollView {"})
                                      for x in d["items"] if x["file"].endswith("ConnectionListView.swift")])
        problems, _ = evaluate(views, led)
        record("分类写错（装饰当成面板根）", problems, "的分类是")

        # 9 理由写空
        views, led = fresh()
        mutate_ledger(led, lambda d: [x.update({"note": ""})
                                      for x in d["items"] if x["file"].endswith("MCPApprovalPanel.swift")])
        problems, _ = evaluate(views, led)
        record("理由为空", problems, "note")

        # 10 意图词表外的词
        views, led = fresh()
        mutate_ledger(led, lambda d: [x.update({"intent": "looks-fine-to-me"})
                                      for x in d["items"] if x["file"].endswith("SchemaDiffPanel.swift")])
        problems, _ = evaluate(views, led)
        record("意图不在词表里", problems, "intent")

        # 11 处数不符（同一处 frame 在盘上出现两次、台账只记 1）
        views, led = fresh()
        # 锚点**从台账派生**，不写死文件名与那段源码文本：写死的话，实现一搬家这例就变成
        # 「replace 没命中 = 盘上什么都没变 = 判绿」的空转（2026-09-30 实测：对象树行渲染搬进
        # `ObjectTreeRowContent.swift` 之后，本例如实变成了空转，而自检 19 条里它**报绿**）。
        anchor = next(x for x in json.loads(led.read_text(encoding="utf-8"))["items"]
                      if x.get("count") == 1)
        target = sandbox / anchor["file"]
        needle = ".frame(%s)" % anchor["frame"]
        text = target.read_text(encoding="utf-8")
        assert needle in text, "台账条目 %s 的 `%s` 在盘上找不到 —— 本例如需重锚，请连带修正台账" % (
            anchor["file"], needle)
        target.write_text(text.replace(needle, needle + "\n            " + needle, 1),
                          encoding="utf-8")
        problems, _ = evaluate(views, led)
        record("处数与盘上不符", problems, "处数不符")
        restore(anchor["file"])

        # 12 台账声明的扫描事实与磁盘不符
        views, led = fresh()
        mutate_ledger(led, lambda d: d.update({"scannedFiles": 3}))
        problems, _ = evaluate(views, led)
        record("台账 scannedFiles 与实测不符", problems, "scannedFiles")

        # 13 空跑：视图目录被清空
        views, led = fresh()
        empty = tmpdir / "EmptyViews"
        empty.mkdir(exist_ok=True)
        problems, _ = evaluate(empty, led)
        record("空跑：一个视图文件都没有", problems, "空跑")

        # 14 台账条目为空
        views, led = fresh()
        mutate_ledger(led, lambda d: d.update({"items": []}))
        problems, _ = evaluate(views, led)
        record("空跑：台账没有条目", problems, "空跑")

        # 15~17 **L-58 类缺陷下一次会被挡住**：现造一块面板根（700×600，
        #     既没写 `alignment:`、类型里也没有任何撑满容器）—— 三条路线逐个试：
        #     ① 不登记 ⇒ 未登记；② 登记 content-stretches ⇒ 锚点找不到；
        #     ③ 登记 explicit-alignment ⇒ 源码没写。三条全红 = 这一档过不去。
        ghost = views / "GhostPanel.swift"
        ghost.write_text(
            "import SwiftUI\n\n"
            "struct GhostPanel: View {\n"
            "    var body: some View {\n"
            "        VStack(alignment: .leading) {\n"
            "            Text(\"x\")\n"
            "        }\n"
            "        .frame(width: 700, height: 600)\n"
            "    }\n"
            "}\n",
            encoding="utf-8",
        )
        views_ghost, led_ghost = fresh()
        problems, _ = evaluate(views_ghost, led_ghost)
        record("新增面板根（不写 alignment、无撑满容器）未登记", problems, "未登记")

        def add_ghost(d, intent, extra):
            d["items"].append({
                "file": "App/Views/GhostPanel.swift", "symbol": "GhostPanel",
                "frame": "width: 700, height: 600", "count": 1, "kind": "panel-root",
                "intent": intent, "note": "现造的面板根", **extra})

        views_ghost, led_ghost = fresh()
        mutate_ledger(led_ghost, lambda d: add_ghost(d, "content-stretches", {"stretchProbe": "ScrollView {"}))
        problems, _ = evaluate(views_ghost, led_ghost)
        record("同一处登记 content-stretches（类型里没有撑满容器）", problems, "锚点")

        views_ghost, led_ghost = fresh()
        mutate_ledger(led_ghost, lambda d: add_ghost(d, "explicit-alignment", {"alignment": ".center"}))
        problems, _ = evaluate(views_ghost, led_ghost)
        record("同一处登记 explicit-alignment（源码里没写）", problems, "没有 `alignment:`")
        ghost.unlink()

    after = fingerprint([LEDGER, VIEWS / "DatabaseStatsPanel.swift", VIEWS / "PrivilegePanel.swift"])
    cases.append(("末例：真仓库台账与两个抽样视图逐字节未变",
                  "绿" if before == after else "红（被自检改动了）"))

    ok = True
    for name, outcome in cases:
        good = (outcome == "红") if expected(name) else (outcome == "绿")
        ok = ok and good
        print(f"  {'✅' if good else '❌'} {name} → {outcome}")
    passed = sum(1 for n, o in cases if (o == "红") == expected(n))
    print(f"{'✅' if ok else '❌'} 负例自检：{len(cases)} 条中 {passed} 条达到预期")
    return 0 if ok else 1


def report(views: pathlib.Path, ledger_path: pathlib.Path) -> int:
    ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
    min_width = ledger.get("panelRootMinWidth", 400)
    on_disk, token_frames, file_count, frame_count, token_count = scan(views, min_width)
    print(f"视图文件 {file_count} 个 / 固定尺寸 frame {frame_count} 处 / 令牌尺寸 {token_count} 处")
    for key in sorted(on_disk):
        entry = on_disk[key]
        print(f"  [{entry.kind_with(min_width)}] {entry.file}:{entry.line} {entry.symbol} .frame({entry.frame})"
              f" ×{entry.count} alignment={entry.alignment or '（未写）'}")
    for key in sorted(token_frames):
        print(f"  [范围外] {key[0]} {key[1]} `.frame({key[2]})` ×{token_frames[key].count}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--views", default=str(VIEWS))
    parser.add_argument("--ledger", default=str(LEDGER))
    parser.add_argument("--report", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    views = pathlib.Path(args.views)
    ledger = pathlib.Path(args.ledger)
    if args.self_test:
        return self_test()
    if args.report:
        return report(views, ledger)
    problems, notes = evaluate(views, ledger)
    for note in notes:
        print(f"（{note}）")
    if problems:
        print(f"❌ 面板根 frame 对齐纪律不通过（{len(problems)} 处）：")
        for item in problems:
            print(f"   {item}")
        print("\n提示：面板根（width ≥ 台账里的门槛）必须**把意图写出来** —— 要么在源码里显式写 "
              "`alignment:`（路线 `explicit-alignment`，登记里记下写了什么），要么登记 `content-stretches` "
              "并给一个在该视图类型里真的存在的撑满令牌（`probeVocab`）。台账 = "
              "`Scripts/panel-root-frames.json`。")
        return 1
    print("✅ 面板根 frame 对齐纪律通过（每一处固定尺寸都在台账里，面板根的意图都有盘上锚点）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
