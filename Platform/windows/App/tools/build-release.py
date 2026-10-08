#!/usr/bin/env python3
"""构建 / 出包入口（S-073e · 首选面）——先把**徽标值**写进环境，再跑 release 构建。

为什么要有它
============
窗口标题里的「提交短号 · 构建时刻」原先只由 `src-tauri/build.rs` 自己现算，而
build.rs 会不会重跑、由 **cargo 的增量判断**说了算。只改 `App/tools/**`（不在 build.rs
原先声明的输入面 `build.rs` / `src` 里）时 cargo 不重跑 build.rs ⇒ 徽标滞留在旧短号上
（S-073e 的由头，已复现）。

本脚本在**每次构建时**把当前 `git rev-parse --short HEAD` 与本地时刻写进
`DOYAH_BUILD_HEAD` / `DOYAH_BUILD_TIME`（子进程 cargo 继承），`build.rs` **优先采用**
它们 ⇒ 徽标值由出包脚本写入，不再依赖 build.rs 现算。
`build.rs` 侧另有 `rerun-if-changed` 补面作**兜底**：不经过本脚本、直接 `cargo build`
时，输入面一变也会重跑 build.rs 刷新徽标。

口径与 `Tools/build.ps1` 一致：构建命令 = 工作区 release + `custom-protocol` 特性
（Tauri 2 编译期把 `frontendDist` 嵌进产物；不带该特性编出来的是 dev 形态）。
本脚本**不替代** `Tools/build.ps1`，只是它外面的一层薄壳（补徽标值）。

用法
====
    # 先在 App 下装好前端依赖并产出 dist（与 Tools/build.ps1 同口径；缺前端产物时
    # Tauri 编译期嵌不到资源）：
    #   cd platform/windows/App && npm install && npm run build
    python platform/windows/App/tools/build-release.py

退出码 = cargo 的退出码（0 = 产物已产出）。
"""

import datetime
import os
import subprocess
import sys

FEATURES = "doyah-studio-shell/custom-protocol"


def script_dir() -> str:
    return os.path.dirname(os.path.abspath(__file__))


def repo_root() -> str:
    """仓根：先问 git（worktree 里也对），问不到就按脚本位置推（tools→App→windows→platform→根）。"""
    here = script_dir()
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=here, capture_output=True, timeout=30,
        )
        if out.returncode == 0:
            top = out.stdout.decode("utf-8", "replace").strip()
            if top and os.path.isdir(top):
                return os.path.abspath(top)
    except Exception:
        pass
    root = here
    for _ in range(5):  # tools → App → windows → platform(与根同层) → 根
        root = os.path.dirname(root)
    return root


def short_head(root: str) -> str:
    """`git rev-parse --short HEAD`（与判据脚本对账用的同一条命令）；取不到 ⇒ `unknown`。"""
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            cwd=root, capture_output=True, timeout=30,
        )
        if out.returncode == 0:
            return out.stdout.decode("utf-8", "replace").strip() or "unknown"
    except Exception:
        pass
    return "unknown"


def stamp_time() -> str:
    """构建时刻（本机本地时间，`MM-dd HH:mm`）——与 build.rs 的 `unknown` 口径一致。"""
    return datetime.datetime.now().strftime("%m-%d %H:%M")


def main(argv) -> int:
    root = repo_root()
    windows = os.path.join(root, "platform", "windows")
    head = short_head(root)
    stamp = stamp_time()

    env = dict(os.environ)
    env["DOYAH_BUILD_HEAD"] = head
    env["DOYAH_BUILD_TIME"] = stamp
    env["RUSTUP_AUTO_INSTALL"] = "0"

    print(f"[S-073e] 徽标（写入环境，build.rs 直接采用）：HEAD={head} TIME={stamp}")
    cmd = ["cargo", "build", "--release", "--workspace", "--features", FEATURES]
    print(f"[S-073e] $ {' '.join(cmd)}   (cwd={windows})")
    return subprocess.call(cmd, cwd=windows, env=env)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
