#!/usr/bin/env python3
"""平台详设按基准书「移植」（不是重写，也不是只写差异索引）。

主人 2026-11-05 的口径：
  能力同、需求同、概设同 ⇒ 详设的内容本来就是同一份，不同的只有平台落点。
  所以出新平台详设 = 拿基准书整体移植 + 就地改平台落点，章节与节号一一对齐，读起来是完整契约。

本脚本做三件事：
  1. 逐条替换平台词（基准确的名词 → 目标平台名词），每条替换都记账；
  2. 替换后仍残留基准平台词的段落标 `<!-- PORT-REVIEW -->`，交给人工就地改（脚本判不了语义）；
  3. 按配置输出 §0.2「逐节处置」表（沿用 / 差异 / 不适用），供 check-platform-derivation.py 判。

用法：
  python3 Scripts/port-platform-lld.py --target Linux --out /tmp/linux-port.md
  python3 Scripts/port-platform-lld.py --self-test
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "Docs"
BASE = {"Windows": "macOS", "Linux": "macOS", "iOS": "Android", "HarmonyOS": "Android"}

# 基准平台的「记号」：出现这些词说明该行还没改成本端说法
BASE_TOKENS = {
    "macOS": ["Keychain", "AppState", "DatabaseService", "@MainActor", "SwiftUI", "AppKit",
              "swift test", "⌘", "~/Library", ".app", "AgentApprovalGate", "NSOpenPanel", "NSVisualEffectView"],
    "Android": ["Kotlin", "ViewModel", "Compose", "Gradle", "JUnit", "logcat", "Koin", "Navigation"],
}

# 替换表：macOS 基准 → Linux
MACOS_TO_LINUX = [
    # 路径级先换（顺序敏感：长的在前）
    ("Platform/macOS/Keychain/SecretStore.swift", "Platform/linux/src/secrets.rs"),
    ("Platform/macOS/", "Platform/linux/"),
    ("Core/SecretStore.swift", "Platform/linux/src/secrets.rs"),
    ("DatabaseService", "doyah_studio_db"),
    ("AgentApprovalGate", "agent::Approval"),
    ("AppState", "ShellState"),
    ("Keychain", "SecretStore（系统密钥环）"),
    ("@MainActor", "阻塞线程池"),
    ("SwiftUI", "Vue 3（Tauri 2 + WebKitGTK）"),
    ("AppKit", "GTK"),
    ("swift test", "cargo test"),
    ("~/Library/Application Support", "$XDG_DATA_HOME"),
    ("⌘⇧P", "Ctrl+Shift+P"),
    ("⌘S", "Ctrl+S"),
    ("⌘K", "Ctrl+K"),
    ("⌘W", "Ctrl+W"),
    ("⌘", "Ctrl+"),
    ("`.app`", "`deb` / `AppImage`"),
    (".app", "deb / AppImage"),
    ("Swift", "Rust"),
]

# 替换表：Android 基准 → iOS
ANDROID_TO_IOS = [
    ("Kotlin", "Swift"),
    ("ViewModel", "ObservableObject"),
    ("Jetpack Compose", "SwiftUI"),
    ("Compose", "SwiftUI"),
    ("Gradle", "Xcode / SwiftPM"),
    ("JUnit", "XCTest"),
    ("logcat", "os_log"),
    ("Koin", "构造函数注入"),
    ("Navigation", "NavigationStack"),
]

TABLES = {"Linux": MACOS_TO_LINUX, "iOS": ANDROID_TO_IOS, "Windows": MACOS_TO_LINUX,
          "HarmonyOS": ANDROID_TO_IOS}

# 逐节处置：目标平台 → {节号: (处置, 依据)}
DISPOSITION = {
    "Linux": {
        "3.1": ("沿用", "连接建立；只有凭据入口换成 SecretStore（见 §0.3 第 1 条）"),
        "3.2": ("差异", "连接清单落 XDG 配置区"),
        "3.3": ("沿用", "执行与多结果集，语义同基准"),
        "3.4": ("沿用", "取消，语义同基准"),
        "3.5": ("沿用", "执行安全，本端不另立口径"),
        "3.6": ("差异", "基准是 Swift 审批闸，本端用同源 agent::Approval"),
        "3.7": ("沿用", "元数据，树渲染复用同源组件"),
        "3.8": ("沿用", "行浏览与编辑口径不变"),
        "3.9": ("差异", "编辑状态在 ShellState，不在 AppState"),
        "3.10": ("沿用", "结构脚本，预览闸与删库确认不变"),
        "3.11": ("差异", "导出，文件对话框换 GTK"),
        "3.12": ("差异", "导入，同上；估算取不到写「未接」"),
        "3.13": ("差异", "会话监控，终止前多一道二次确认"),
        "3.14": ("沿用", "上下文装配与注入防护同源"),
        "3.15": ("差异", "工具面只有 read_file / write_file"),
        "3.16": ("不适用", "同源无 Plan Rows 解析"),
        "3.17": ("不适用", "同源无命令执行器"),
        "3.18": ("不适用", "同源无代码执行器"),
        "3.19": ("不适用", "同源无工具目录检索"),
        "3.20": ("不适用", "同源无并行编排"),
        "3.21": ("不适用", "同源无压缩准入"),
        "3.22": ("不适用", "同源无工具注册表"),
        "3.23": ("不适用", "同源无生命周期钩子"),
        "3.24": ("不适用", "两端均未建记忆账本"),
        "3.25": ("不适用", "本端不做 IM 通道"),
        "3.26": ("差异", "只允许工作区内相对路径，不提供授权一次"),
        "3.27": ("不适用", "同源无联网工具"),
        "3.28": ("不适用", "Platform 内无 DAP 核心"),
        "3.29": ("差异", "对话区由同源前端提供，口径未接"),
        "3.30": ("不适用", "无委派能力"),
    }
}


def sections(text: str, level: str = "###") -> dict[str, tuple[int, int]]:
    """返回 {节号: (起行, 止行)}，节号形如 3.1。"""
    lines = text.split("\n")
    pat = re.compile(r"^### (3\.\d+)\b")
    marks = [(i, m.group(1)) for i, l in enumerate(lines) if (m := pat.match(l))]
    out = {}
    for k, (i, num) in enumerate(marks):
        end = marks[k + 1][0] if k + 1 < len(marks) else len(lines)
        out[num] = (i, end)
    return out


def load_map(target: str) -> dict:
    p = ROOT / "Scripts" / "platform-port-maps" / f"{target.lower()}.json"
    if p.exists():
        return json.loads(p.read_text(encoding="utf-8"))
    return {"path_rules": [], "prose_rules": TABLES.get(target, [])}


def port(base_text: str, target: str) -> tuple[str, dict]:
    spec = load_map(target)
    counts: dict[str, int] = {}
    text = base_text
    for pat, dst in spec.get("path_rules", []):
        text, n = re.subn(pat, dst, text)
        if n:
            counts[pat] = n
    for pat, dst in spec.get("prose_rules", []):
        n = text.count(pat)
        if n:
            text = text.replace(pat, dst)
            counts[pat] = n
    # 残留基准平台词 → 标人工复核
    tokens = BASE_TOKENS[BASE[target]]
    review = []
    lines = text.split("\n")
    for i, l in enumerate(lines):
        hits = [t for t in tokens if re.search(r"(?<![A-Za-z0-9])" + re.escape(t) + r"(?![A-Za-z0-9])", l)]
        if hits:
            review.append((i + 1, hits, l.strip()[:80]))
    return text, {"replacements": counts, "review": review}


def disposition_table(target: str) -> str:
    rows = DISPOSITION.get(target, {})
    head = "| 基准节 | 处置 | 依据 / 本端落点 |\n|---|---|---|\n"
    body = "\n".join(f"| `§{k}` | {v[0]} | {v[1]} |" for k, v in sorted(rows.items(), key=lambda x: [int(p) for p in x[0].split(".")]))
    return head + body + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", choices=sorted(BASE))
    ap.add_argument("--out", type=Path)
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()

    if args.self_test:
        mac = (DOCS / "Doyah产品详细设计说明书-macOS.md").read_text(encoding="utf-8")
        out, info = port(mac, "Linux")
        checks = [
            ("替换记账非空", bool(info["replacements"])),
            ("Keychain 已换掉", "Keychain" not in out),
            ("AppState 已换掉", "AppState" not in out),
            ("节数守恒", len(sections(out)) == len(sections(mac))),
            ("负例：未替换的基准词必被标出",
             bool(port("这里只剩 NSOpenPanel 残留", "Linux")[1]["review"])),
        ]
        bad = [n for n, ok in checks if not ok]
        for n, ok in checks:
            print(("  ✓ " if ok else "  ✗ ") + n)
        print("自检" + ("通过" if not bad else "失败：" + "、".join(bad)))
        return 0 if not bad else 1

    if not args.target or not args.out:
        ap.error("需要 --target 与 --out")
    base = BASE[args.target]
    src = DOCS / f"Doyah产品详细设计说明书-{base}.md"
    text = src.read_text(encoding="utf-8")
    out, info = port(text, args.target)
    args.out.write_text(out, encoding="utf-8")
    print(f"基准：{src.name}")
    print(f"替换：{sum(info['replacements'].values())} 处 / {len(info['replacements'])} 条规则")
    for k, v in sorted(info["replacements"].items(), key=lambda x: -x[1]):
        print(f"  {k:28s}{v:4d}")
    print(f"待人工就地改：{len(info['review'])} 行")
    for ln, hits, text_ in info["review"][:20]:
        print(f"  L{ln}: {'/'.join(hits)}  {text_}")
    print(f"已写：{args.out}")
    print("下一步：① 逐条改 PORT-REVIEW 行；② 换头（派生自 / 版本）；③ 插 §0.2 处置表；④ 过门禁")
    print(json.dumps({"review": len(info["review"])}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
