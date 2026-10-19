#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Doyah Studio · Linux 端判据 —— 应用工程骨架 + 领域层边界 + 前端同源。

对应 `Docs/Doyah产品概要设计说明书.md` §8.6.1（技术栈与工程结构）与 §8.6.6（自检与待定项）；派单 `T-20261014-016`。

为什么有这件：§8.6.1 写着「`Core/` 的 `Cargo.toml` **不得依赖 GUI / 平台包** —— 与 Windows 侧
`check-core-boundary` 同形的判据面，随工程落片一起落」。所以本件是 Windows 侧
`Platform/windows/Tools/check-core-boundary.ps1` 的**本端等价物**，并按 Linux 端多两条
（前端同源 / 构建入口形状）。

判据（缺一即判红，**本件没有「跳过」这一档**）：

  A 判据面非空：`src-tauri/Cargo.toml` 在盘上且有 `[package]`；工作区成员含 `Core` / `Cli` /
    `Platform/Linux` 三层的 `Cargo.toml`，每层 `src/` 下至少 1 个 `.rs`；外壳 `src/{lib,main}.rs` 在盘上
  B 依赖面：`Core/Cargo.toml` 的 `dependencies` / `dev-dependencies` / `build-dependencies` /
    `target.*.dependencies` 段里**每个依赖名**都不得命中 GUI / 平台面清单
  C 源码面：`Core/**/*.rs` 不得 `use <GUI/平台 crate>`、不得出现 `<crate>::` 路径、
    不得用平台专有 std（`std::os::unix` / `std::os::windows`）、不得出现 FFI 形状
    （`extern "C"` / `extern "system"` / `#[link(` / `libc::`）；判红一律点名 `文件:行号`
  D 前端同源（§8.6.1「前端与 Windows 侧同源」）：`tauri.conf.json` 的 `build.frontendDist`
    必须解析到**同源面** `Platform/windows/App/dist`，`devUrl` 与 Windows 侧取值一致，
    且盘上**没有**本端自存的 `App/` 或 `dist/`（不许另存一份前端）
  E 构建入口形状：`build.sh` 在盘上、指向 `src-tauri`、含 `cargo tauri build`

逃生门：`core-boundary-allow：理由` —— 只认结构化写法：整行注释（`//` 或 `#` 起头），写在
**被判红那一行的上一行**；理由为空仍判红；放行的行**逐条打印**（放行必须看得见，不许静默豁免）。

自测：固定夹具九例（基线 / 依赖注入 / 源码 crate / FFI 形状 / 空跑 / 逃生门 / 前端另存一份 /
frontendDist 指错 / 末例核对真仓库逐字节未变），夹具一律在临时目录，真仓库只被读。

退出码：0 = 通过 / 1 = 判红（空跑判红，不跳过）

用法：
  python Platform/linux/Tools/check-linux-skeleton.py            # 判本仓
  python Platform/linux/Tools/check-linux-skeleton.py --root <树> # 判指定树（自测夹具用）
  python Platform/linux/Tools/check-linux-skeleton.py --report    # 附带扫描面读数
  python Platform/linux/Tools/check-linux-skeleton.py --self-test # 判据自己的证据（九例）
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]

SRC_TAURI = "Platform/linux/src-tauri"
CORE_DIR = f"{SRC_TAURI}/Core"
LAYER_MEMBERS = ("Core", "Cli", "Platform/Linux")
SAME_SOURCE_FRONTEND = "Platform/windows/App"
SAME_SOURCE_DIST = "Platform/windows/App/dist"

# GUI / 平台面清单（与 Windows 侧 check-core-boundary.ps1 同一份：依赖名按 Cargo 口径归一 —— 小写 + `_` 视同 `-`）
GUI_DEPS = (
    "tauri", "wry", "tao", "winit", "egui", "egui-extras", "slint", "iced",
    "windows", "windows-sys", "windows-targets", "windows-registry", "winapi", "wmi", "winreg",
    "webview2", "webview2-com",
    "gtk", "gtk-sys", "gdk", "gdk-sys", "glib", "glib-sys", "gio", "webkit2gtk",
    "cocoa", "objc", "objc2", "objc2-foundation", "core-graphics", "core-foundation", "core-text",
    "muda", "tray-icon", "rfd", "arboard", "clipboard-win", "clipboard", "keyring", "portable-pty",
    "conpty", "wgpu", "wgpu-hal", "softbuffer", "raw-window-handle", "skia-safe", "femtovg",
    "glazier", "dxgi", "d3d12",
)
GUI_PREFIXES = ("windows-", "winapi-", "gtk", "gdk", "objc", "webkit", "cocoa-", "core-graphics", "d3d", "dxgi", "wgpu-")

SOURCE_RULES = (
    ("use GUI / 平台 crate", r"^\s*(?:pub\s+)?use\s+(?:{alt})(?:\b|::)"),
    ("GUI / 平台 crate 路径", r"(?:^|[^A-Za-z0-9_-])({alt})::"),
    ("extern crate GUI / 平台 crate", r"^\s*extern\s+crate\s+(?:{alt})\b"),
    ("平台专有 std（std::os::unix / std::os::windows）", r"std::os::(?:unix|windows)\b"),
    ("FFI：extern \"C\" / extern \"system\"", r"extern\s+\"(?:C|system)\""),
    ("FFI：#[link(...)]", r"#\s*\[\s*link\s*\("),
    ("FFI：libc::", r"\blibc::"),
)


def normalize_dep_name(name: str) -> str:
    return name.lower().replace("_", "-")


def is_gui_dependency(name: str) -> bool:
    normalized = normalize_dep_name(name)
    if normalized in GUI_DEPS:
        return True
    return any(normalized.startswith(prefix) for prefix in GUI_PREFIXES)


def escape_reason(line: str):
    """返回 None = 这一行没有逃生门；'' = 有但理由为空（仍判红）；其它 = 理由。"""
    match = re.match(r"^(?://+|#)\s*core-boundary-allow\s*[：:]\s*(.*)$", line.strip())
    return None if not match else match.group(1).strip()


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def cargo_dependencies(text: str):
    """产出 (行号, 依赖名)；只认依赖段里的行。"""
    out = []
    section = ""
    for index, raw in enumerate(text.splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        header = re.match(r"^\[(.+)\]$", line)
        if header:
            section = header.group(1).strip().lower()
            continue
        is_dep_section = section in ("dependencies", "dev-dependencies", "build-dependencies") or section.endswith(".dependencies")
        if not is_dep_section:
            continue
        match = re.match(r'^"?([A-Za-z0-9_\-]+)"?\s*=', line)
        if match:
            out.append((index, match.group(1)))
    return out


def scan_text_lines(path: Path, root: Path, compiled_rules):
    """对单个 .rs 文件跑 C 条规则 → (problems, allowed)。"""
    problems, allowed = [], []
    relative = path.relative_to(root).as_posix()
    lines = read_text(path).splitlines()
    for index, line in enumerate(lines):
        trimmed = line.strip()
        if not trimmed or trimmed.startswith("//"):
            continue  # 纯注释行不扫：文档注释里提 crate 名不算依赖
        for label, pattern in compiled_rules:
            if not pattern.search(line):
                continue
            text = f"{relative}:{index + 1} 出现 {label} ⇒ GUI / 平台依赖不得进入领域层（平台能力只允许在 Platform/Linux/）"
            reason = escape_reason(lines[index - 1]) if index > 0 else None
            if reason is None:
                problems.append(text)
            elif reason == "":
                problems.append(text + "（逃生门理由为空 ⇒ 仍判红）")
            else:
                allowed.append(f"{relative}:{index + 1} {label}（core-boundary-allow：{reason}）")
    return problems, allowed


def check_workspace(root: Path):
    """A 条：判据面非空 + 三层齐 + 每层有 .rs。→ (problems, allowed, facts)"""
    problems = []
    facts = {"members": 0, "rs_files": 0}
    manifest = root / SRC_TAURI / "Cargo.toml"
    if not manifest.is_file():
        problems.append(f"判据面不存在：{SRC_TAURI}/Cargo.toml 不在盘上（工程已在盘上，判据无从下手 ⇒ 空跑判红，不跳过）")
        return problems, [], facts
    text = read_text(manifest)
    if not re.search(r"(?m)^\s*\[package\]", text):
        problems.append(f"{SRC_TAURI}/Cargo.toml 里解析不到 [package] 段 ⇒ 判据面异常（空跑不许通过）")
        return problems, [], facts
    members = []
    match = re.search(r"(?ms)^\[workspace\].*?members\s*=\s*\[(.*?)\]", text)
    if match:
        members = [m.strip().strip('"').strip("'") for m in match.group(1).split(",") if m.strip()]
    facts["members"] = len(members)
    for layer in LAYER_MEMBERS:
        if layer not in members:
            problems.append(f"{SRC_TAURI}/Cargo.toml 的 [workspace] members 里缺 `{layer}`（§8.6.1 的三层结构）")
        layer_dir = root / SRC_TAURI / layer
        layer_manifest = layer_dir / "Cargo.toml"
        if not layer_manifest.is_file():
            problems.append(f"层不在盘上：{SRC_TAURI}/{layer}/Cargo.toml")
            continue
        if not re.search(r"(?m)^\s*\[package\]", read_text(layer_manifest)):
            problems.append(f"{SRC_TAURI}/{layer}/Cargo.toml 里解析不到 [package] 段")
        sources = sorted(layer_dir.rglob("*.rs"))
        if not sources:
            problems.append(f"{SRC_TAURI}/{layer} 下找不到任何 .rs ⇒ 判据面为空（空跑不许通过）")
        facts["rs_files"] += len(sources)
    for entry in ("src/lib.rs", "src/main.rs"):
        if not (root / SRC_TAURI / entry).is_file():
            problems.append(f"外壳入口不在盘上：{SRC_TAURI}/{entry}")
    if (root / SRC_TAURI / "src").is_dir():
        facts["rs_files"] += len(sorted((root / SRC_TAURI / "src").rglob("*.rs")))
    return problems, [], facts


def check_core_boundary(root: Path):
    """B + C 条：领域层依赖面与源码面。"""
    problems, allowed = [], []
    facts = {"deps": 0, "core_rs": 0}
    core_dir = root / CORE_DIR
    manifest = core_dir / "Cargo.toml"
    if not manifest.is_file():
        problems.append(f"判据面不存在：{CORE_DIR}/Cargo.toml 不在盘上（空跑判红，不跳过）")
        return problems, allowed, facts
    lines = read_text(manifest).splitlines()
    saw_dep_section = False
    section = ""
    for index, raw in enumerate(lines, start=1):
        line = raw.strip()
        if line.startswith("["):
            section = line.strip("[]").strip().lower()
            if section in ("dependencies", "dev-dependencies", "build-dependencies") or section.endswith(".dependencies"):
                saw_dep_section = True
    for lineno, name in cargo_dependencies(read_text(manifest)):
        facts["deps"] += 1
        if not is_gui_dependency(name):
            continue
        text = f"{CORE_DIR}/Cargo.toml:{lineno} 依赖面命中 GUI / 平台 crate：{name}"
        reason = escape_reason(lines[lineno - 2]) if lineno >= 2 else None
        if reason is None:
            problems.append(text)
        elif reason == "":
            problems.append(text + "（逃生门理由为空 ⇒ 仍判红）")
        else:
            allowed.append(f"{CORE_DIR}/Cargo.toml:{lineno} {name}（core-boundary-allow：{reason}）")
    if not saw_dep_section:
        problems.append(f"{CORE_DIR}/Cargo.toml 里找不到任何依赖段（[dependencies] 一类）⇒ 判据读不到依赖面（空跑不许通过）")

    alt = "|".join(dep.replace("-", "[-_]") for dep in GUI_DEPS)
    compiled = [(label, re.compile(pattern.replace("{alt}", alt))) for label, pattern in SOURCE_RULES]
    sources = sorted(core_dir.rglob("*.rs"))
    facts["core_rs"] = len(sources)
    if not sources:
        problems.append(f"{CORE_DIR} 下找不到任何 .rs ⇒ 判据面为空（空跑不许通过）")
    for source in sources:
        file_problems, file_allowed = scan_text_lines(source, root, compiled)
        problems.extend(file_problems)
        allowed.extend(file_allowed)
    return problems, allowed, facts


def check_frontend_reuse(root: Path):
    """D 条：前端同源（指向同源面 + 本端不另存一份）。→ (problems, allowed, facts)"""
    problems = []
    facts = {"frontend_dist": "-", "dev_url": "-"}
    config_path = root / SRC_TAURI / "tauri.conf.json"
    if not config_path.is_file():
        problems.append(f"判据面不存在：{SRC_TAURI}/tauri.conf.json 不在盘上（空跑判红，不跳过）")
        return problems, [], facts
    try:
        config = json.loads(read_text(config_path))
    except json.JSONDecodeError as error:
        problems.append(f"{SRC_TAURI}/tauri.conf.json 解析失败：{error}")
        return problems, [], facts
    build = config.get("build", {})
    dist_raw = str(build.get("frontendDist", "")).strip()
    facts["frontend_dist"] = dist_raw or "-"
    if not dist_raw:
        problems.append(f"{SRC_TAURI}/tauri.conf.json 缺 build.frontendDist（同源面指向不明）")
    else:
        resolved = os.path.normcase(os.path.normpath(str(config_path.parent / dist_raw)))
        expected = os.path.normcase(os.path.normpath(str(root / SAME_SOURCE_DIST)))
        if resolved != expected:
            problems.append(
                f"{SRC_TAURI}/tauri.conf.json 的 frontendDist=`{dist_raw}` 解析到 {resolved} "
                f"≠ 同源面 {expected}（§8.6.1：前端与 Windows 侧同一套源码 ⇒ 必须指过去）"
            )
    dev_url = str(build.get("devUrl", "")).strip()
    facts["dev_url"] = dev_url or "-"
    if not dev_url:
        problems.append(f"{SRC_TAURI}/tauri.conf.json 缺 build.devUrl（同源前端在开发形态下也要指同一套）")
    windows_config = root / SAME_SOURCE_FRONTEND / "src-tauri/tauri.conf.json"
    if windows_config.is_file():
        try:
            windows_build = json.loads(read_text(windows_config)).get("build", {})
            windows_dev_url = str(windows_build.get("devUrl", "")).strip()
            if dev_url and windows_dev_url and dev_url != windows_dev_url:
                problems.append(
                    f"devUrl 与同源面不一致：本端 `{dev_url}` / Windows 侧 `{windows_dev_url}` "
                    f"（同一套前端 ⇒ 同一台开发服务器）"
                )
        except json.JSONDecodeError:
            pass
    for local_copy in ("App", "src-tauri/dist", "dist"):
        if (root / "Platform/linux" / local_copy).exists():
            problems.append(
                f"Platform/linux/{local_copy} 在盘上 ⇒ 本端自存了前端面（§8.6.1：前端不另存一份，界面 = {SAME_SOURCE_FRONTEND}）"
            )
    return problems, [], facts


def check_build_entry(root: Path):
    """E 条：构建入口形状（一条命令可复跑）。→ (problems, allowed, facts)"""
    problems = []
    script = root / "Platform/linux/build.sh"
    if not script.is_file():
        problems.append("Platform/linux/build.sh 不在盘上（§8.6.2 的构建入口）")
        return problems, [], {}
    text = read_text(script)
    if "src-tauri" not in text:
        problems.append("Platform/linux/build.sh 里找不到 `src-tauri` ⇒ 构建入口没指向应用工程")
    if "cargo tauri build" not in text:
        problems.append("Platform/linux/build.sh 里找不到 `cargo tauri build` ⇒ 构建入口没接真构建")
    if "--deps" not in text:
        problems.append("Platform/linux/build.sh 里找不到 `--deps` ⇒ 依赖探测档丢了")
    return problems, [], {}


def run_checks(root: Path):
    problems, allowed = [], []
    facts = {}
    for checker in (check_workspace, check_core_boundary, check_frontend_reuse, check_build_entry):
        checker_problems, checker_allowed, checker_facts = checker(root)
        problems.extend(checker_problems)
        allowed.extend(checker_allowed)
        facts.update(checker_facts)
    return problems, allowed, facts


def tree_hash(directory: Path) -> str:
    digest = hashlib.sha256()
    if not directory.exists():
        return ""
    items = sorted(path for path in directory.rglob("*") if path.is_file())
    for path in items:
        digest.update(path.relative_to(directory).as_posix().encode("utf-8"))
        digest.update(b":")
        digest.update(hashlib.sha256(path.read_bytes()).hexdigest().encode("ascii"))
        digest.update(b"\n")
    return digest.hexdigest()


# ── 自测夹具（一律在临时目录；真仓库只被读）────────────────────────────────

FIXTURE_CARGO_ROOT = """[workspace]
resolver = "2"
members = ["Core", "Cli", "Platform/Linux"]

[package]
name = "fixture-shell"
version = "0.0.0"
edition = "2021"

[[bin]]
name = "fixture"
path = "src/main.rs"

[dependencies]
fixture-core = { path = "Core" }
tauri = { version = "2", features = [] }
"""

FIXTURE_CARGO_LIB = """[package]
name = "fixture-core"
version = "0.0.0"
edition = "2021"

[lib]
path = "src/lib.rs"

[dependencies]
"""

FIXTURE_CORE_LIB = """pub fn add(a: i64, b: i64) -> i64 {
    a + b
}
"""

FIXTURE_LOWER_MANIFEST = """[package]
name = "fixture-lower"
version = "0.0.0"
edition = "2021"
"""

FIXTURE_TAURI_CONF = {
    "build": {
        "beforeBuildCommand": "npm --prefix ../../windows/App run build",
        "devUrl": "http://localhost:5274",
        "frontendDist": "../../windows/App/dist",
    }
}


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def make_fixture(root: Path, core_lib: str = FIXTURE_CORE_LIB, core_deps: str = "") -> None:
    write(root / f"{SRC_TAURI}/Cargo.toml", FIXTURE_CARGO_ROOT)
    write(root / f"{SRC_TAURI}/src/lib.rs", "pub fn run() {}\n")
    write(root / f"{SRC_TAURI}/src/main.rs", "fn main() {}\n")
    write(root / f"{SRC_TAURI}/Core/Cargo.toml", FIXTURE_CARGO_LIB + core_deps)
    write(root / f"{CORE_DIR}/src/lib.rs", core_lib)
    write(root / f"{SRC_TAURI}/Cli/Cargo.toml", FIXTURE_LOWER_MANIFEST)
    write(root / f"{SRC_TAURI}/Cli/src/main.rs", "fn main() {}\n")
    write(root / f"{SRC_TAURI}/Platform/Linux/Cargo.toml", FIXTURE_LOWER_MANIFEST)
    write(root / f"{SRC_TAURI}/Platform/Linux/src/lib.rs", "pub fn probe() {}\n")
    write(root / f"{SRC_TAURI}/tauri.conf.json", json.dumps(FIXTURE_TAURI_CONF, indent=2))
    write(root / f"{SAME_SOURCE_FRONTEND}/src-tauri/tauri.conf.json", json.dumps(FIXTURE_TAURI_CONF, indent=2))
    write(root / "Platform/linux/build.sh", "#!/usr/bin/env bash\n# src-tauri\ncargo tauri build\n--deps\n")


def self_test(tmp: Path) -> int:
    total = 0
    passed = 0
    failed = 0
    real_tree = REPO / "Platform/linux"
    before = tree_hash(real_tree)

    def case(name: str, ok: bool, detail: str = "") -> None:
        nonlocal total, passed, failed
        total += 1
        if ok:
            passed += 1
            print(f"  ✅ 自测 {total}/9 {name}")
        else:
            failed += 1
            print(f"  ❌ 自测 {total}/9 {name}：{detail}")

    # 例 1：基线 ⇒ 0 判红
    base = tmp / "case1"
    make_fixture(base)
    problems, allowed, facts = run_checks(base)
    case("基线", not problems and facts.get("deps") == 0 and (facts.get("core_rs") or 0) >= 1,
         f"判红 {len(problems)} 条：{problems}")

    # 例 2：依赖面注入 tauri ⇒ 判红并点名
    case2 = tmp / "case2"
    make_fixture(case2, core_deps='tauri = "2"\n')
    problems, _, _ = run_checks(case2)
    case("依赖注入", any("tauri" in p for p in problems), f"判红 {len(problems)} 条")

    # 例 3：源码 use GUI crate ⇒ 判红并点名 文件:行号
    case3 = tmp / "case3"
    make_fixture(case3, core_lib="use tauri::App;\n")
    problems, _, _ = run_checks(case3)
    case("源码 crate 名", any("lib.rs:1" in p for p in problems), f"判红 {len(problems)} 条")

    # 例 4：FFI 形状 ⇒ 判红
    case4 = tmp / "case4"
    make_fixture(case4, core_lib='extern "C" {\n    fn probe();\n}\n')
    problems, _, _ = run_checks(case4)
    case("FFI 形状", any("FFI" in p for p in problems), f"判红 {len(problems)} 条")

    # 例 5：空跑（夹具里没有 src-tauri）⇒ 判红（不是跳过、不是通过）
    case5 = tmp / "case5"
    case5.mkdir(parents=True, exist_ok=True)
    problems, _, _ = run_checks(case5)
    case("空跑", any("判据面不存在" in p for p in problems), f"判红 {len(problems)} 条")

    # 例 6：逃生门（上一行整行注释 + 理由非空）⇒ 通过 + 1 条放行
    case6 = tmp / "case6"
    make_fixture(case6, core_lib="// core-boundary-allow：自测夹具，验证逃生门本身\nuse tauri::App;\n")
    problems, allowed, _ = run_checks(case6)
    case("逃生门", not problems and len(allowed) >= 1, f"判红 {len(problems)} 条 / 放行 {len(allowed)} 条")

    # 例 7：本端自存一份前端 ⇒ 判红（同源被破）
    case7 = tmp / "case7"
    make_fixture(case7)
    write(case7 / "Platform/linux/App/index.html", "<!doctype html>\n")
    problems, _, _ = run_checks(case7)
    case("前端另存一份", any("不另存一份" in p for p in problems), f"判红 {len(problems)} 条")

    # 例 8：frontendDist 指回本目录 ⇒ 判红
    case8 = tmp / "case8"
    make_fixture(case8)
    broken = json.loads(json.dumps(FIXTURE_TAURI_CONF))
    broken["build"]["frontendDist"] = "../dist"
    write(case8 / f"{SRC_TAURI}/tauri.conf.json", json.dumps(broken, indent=2))
    problems, _, _ = run_checks(case8)
    case("frontendDist 指错", any("frontendDist" in p for p in problems), f"判红 {len(problems)} 条")

    # 例 9（末例）：真仓库 Platform/linux 逐字节未变
    after = tree_hash(real_tree)
    case("末例：真仓库未被夹具碰过", before != "" and before == after,
         f"自测前后真仓库 Platform/linux 树指纹 {before[:12]} → {after[:12]}")

    print(f"   自测：{passed}/{total} 例通过")
    return failed


def main() -> int:
    parser = argparse.ArgumentParser(description="Doyah Studio · Linux 端判据（骨架 / 领域层边界 / 前端同源）")
    parser.add_argument("--root", default=str(REPO), help="被判定的树（缺省 = 本仓根）")
    parser.add_argument("--report", action="store_true", help="附带扫描面读数")
    parser.add_argument("--self-test", action="store_true", help="判据自己的证据（九例）")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    print(f"== Linux 端判据（骨架 / 领域层边界 / 前端同源）（{root}）==")

    problems, allowed, facts = run_checks(root)
    if allowed:
        print("   放行的行（逃生门 core-boundary-allow，逐条列出）：")
        for item in allowed:
            print(f"     · {item}")
    if problems:
        for item in problems:
            print(f"  ❌ {item}")
    else:
        print(
            "  ✅ 骨架 / 边界 / 同源三条干净"
            f"（工作区成员 {facts.get('members', 0)} 层 · Core 依赖 {facts.get('deps', 0)} 条"
            f" / 源文件 {facts.get('core_rs', 0)} 个 · 前端同源 = {facts.get('frontend_dist', '-')}）"
        )
    if args.report:
        print("   ── 扫描面读数")
        print(f"     工作区成员：{facts.get('members', 0)}")
        print(f"     各层 .rs 合计：{facts.get('rs_files', 0)}（Core {facts.get('core_rs', 0)}）")
        print(f"     Core 依赖条数：{facts.get('deps', 0)}")
        print(f"     同源指向：frontendDist={facts.get('frontend_dist', '-')} · devUrl={facts.get('dev_url', '-')}")

    self_failed = 0
    if args.self_test:
        print("  ── 自测（固定夹具，临时目录）")
        tmp = Path(tempfile.mkdtemp(prefix="doyah-linux-skeleton-selftest-"))
        try:
            self_failed = self_test(tmp)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    if problems or self_failed:
        print("RESULT: FAIL (exit 1)")
        return 1
    print("RESULT: PASS (exit 0)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
