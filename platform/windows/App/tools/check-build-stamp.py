#!/usr/bin/env python3
# Doyah Studio · Windows 侧 · 构建标识取证脚本（S-073a · 前门裁决 T-20261007-085）
#
# 干什么：起一份真 exe，用 Win32 API 读**它主窗口的标题**，与仓库当前 HEAD 对账，
#         打印 `TITLE=…` / `HEAD=…` / `RESULT: PASS|FAIL`，退出码 0/1。
#
# 为什么要真起窗口而不是查源码：卡面原文要求「出包人实跑取证」——标题是在**运行时**
# 由 `src/lib.rs` 的窗口 setup 设上去的（版本号来自 `CARGO_PKG_VERSION`，提交短号 /
# 构建时刻来自 `build.rs` 注入的 `cargo:rustc-env`）。只有起真进程读真窗口，
# 才能证明「打开包看得出是哪一份构建」这件事真的成立。
#
# 纯 stdlib：`subprocess` 起 exe + `ctypes` 的 `EnumWindows` / `GetWindowTextW` 读标题。
#
# 判据（逐条）：
#   ① 末行 `RESULT: PASS`、退出码 0；
#   ② `TITLE=` 逐字匹配 `^Doyah Studio <版本> · [0-9a-f]{7,} · \d{2}-\d{2} \d{2}:\d{2}$`
#      （`<版本>` 从 `src-tauri/Cargo.toml` 现读 —— 不在本脚本里再写死一处版本号）；
#   ③ `TITLE` 里的短号与 `HEAD=` 行逐字相同；
#   ④ `TITLE` 里的时刻与当前本地时间差 ≤ 30 分钟。
#
# 用法：`python App/tools/check-build-stamp.py`（cwd 随意；脚本按自身位置找仓库根）。
#      可选 `--exe <path>` 显式指定产物；默认依次看 `CARGO_TARGET_DIR` → 仓根 `.build`
#      → 仓根 `.build-cache` → `platform/windows/target`，`debug` / `release` 各取最新一份。

import ctypes
import ctypes.wintypes as wintypes
import datetime
import os
import re
import subprocess
import sys
import time

EXE_NAME = "doyah-studio.exe"
WINDOW_TITLE_TIMEOUT_S = 45.0
TIME_TOLERANCE_MINUTES = 30

user32 = ctypes.windll.user32
EnumWindows = user32.EnumWindows
EnumWindowsProc = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
GetWindowThreadProcessId = user32.GetWindowThreadProcessId
GetWindowTextW = user32.GetWindowTextW
GetWindowTextLengthW = user32.GetWindowTextLengthW
IsWindowVisible = user32.IsWindowVisible
GetWindow = user32.GetWindow
GW_OWNER = 4


def configure_stdout_utf8():
    """判据要原样打印含 `·`（U+00B7）的标题；先把 stdout 钉成 UTF-8，免得 GBK 控制台报编码错。"""
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass


def script_dir():
    return os.path.dirname(os.path.abspath(__file__))


def repo_root():
    """仓库根：先问 git（worktree 里也对），问不到就按脚本位置推（tools→App→windows→platform→根）。"""
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
    for _ in range(5):
        root = os.path.dirname(root)
    return root


def read_expected_version(root):
    """版本号只从 `src-tauri/Cargo.toml` 的 `[package]` 段现读 —— 此处**不写死** `0.3.0`。"""
    cargo = os.path.join(root, "platform", "windows", "App", "src-tauri", "Cargo.toml")
    try:
        with open(cargo, "r", encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return None
    in_package = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("["):
            in_package = stripped == "[package]"
            continue
        if in_package:
            match = re.match(r'^version\s*=\s*"([^"]+)"', stripped)
            if match:
                return match.group(1)
    return None


def find_exe(root, explicit=None):
    """产物候选：显式参数 > `CARGO_TARGET_DIR` > 仓根 `.build` / `.build-cache` > `platform/windows/target`。"""
    if explicit:
        return os.path.abspath(explicit) if os.path.isfile(explicit) else None
    roots = []
    env_target = os.environ.get("CARGO_TARGET_DIR")
    if env_target:
        roots.append(env_target)
    roots.append(os.path.join(root, ".build"))
    roots.append(os.path.join(root, ".build-cache"))
    roots.append(os.path.join(root, "platform", "windows", "target"))
    candidates = []
    for base in roots:
        for profile in ("debug", "release"):
            path = os.path.join(base, profile, EXE_NAME)
            if os.path.isfile(path):
                candidates.append(path)
    if not candidates:
        return None
    # 最新的一份（构建刚产出的是它；debug / release 同时在盘上时按 mtime 决）。
    return max(candidates, key=lambda p: os.path.getmtime(p))


def window_title_of_pid(pid):
    """该进程的可见顶层窗口标题；多个就取第一个有字的（主窗口）。"""
    found = []

    def callback(hwnd, _lparam):
        try:
            owner_pid = wintypes.DWORD(0)
            GetWindowThreadProcessId(hwnd, ctypes.byref(owner_pid))
            if owner_pid.value != pid:
                return True
            if not IsWindowVisible(hwnd):
                return True
            length = GetWindowTextLengthW(hwnd)
            if length <= 0:
                return True
            buffer = ctypes.create_unicode_buffer(length + 1)
            GetWindowTextW(hwnd, buffer, length + 1)
            title = buffer.value
            if title:
                is_top_level = GetWindow(hwnd, GW_OWNER) in (0, None)
                found.append((is_top_level, title))
        except Exception:
            return True
        return True

    EnumWindows(EnumWindowsProc(callback), 0)
    if not found:
        return None
    for top_level, title in found:
        if top_level:
            return title
    return found[0][1]


def spawn_and_read_title(exe, expected):
    """起 exe，轮询它主窗口标题，**直到标题符合期望形状**为止。

    为什么要「等到形状对上」而不是「读到第一个有字的标题就收工」：窗口是先按
    `tauri.conf.json` 的 `title`（= `Doyah Studio`）建出来、再在 `setup` 里被改成带
    构建标识的标题（实测约 1.5 秒）；读太早只会读到建窗时的初始标题。判据要的是
    **稳定态**的那一份，所以这里一直轮询到形状对上。

    读到期望标题 ⇒ `(title, None)`；超时 ⇒ `(最后一次读到的标题或 None, 说明)`。
    """
    started = time.monotonic()
    process = subprocess.Popen([exe], cwd=os.path.dirname(exe))
    last = None
    deadline = started + WINDOW_TITLE_TIMEOUT_S
    try:
        while time.monotonic() < deadline:
            if process.poll() is not None:
                return last, "进程在读到期望标题之前就退出了（退出码 %s）" % process.returncode
            title = window_title_of_pid(process.pid)
            if title:
                last = title
                if expected(title):
                    return title, None
            time.sleep(0.2)
        note = "%.0f 秒内窗口标题没变成期望形状" % WINDOW_TITLE_TIMEOUT_S
        if last is not None:
            note += "（最后一次读到：%s）" % last
        return last, note
    finally:
        # 连 WebView2 的子进程一起收掉，别留后台残留。
        try:
            subprocess.run(
                ["taskkill", "/F", "/T", "/PID", str(process.pid)],
                capture_output=True, timeout=30,
            )
        except Exception:
            try:
                process.kill()
            except Exception:
                pass


def git_head(root):
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            cwd=root, capture_output=True, timeout=30,
        )
        if out.returncode == 0:
            return out.stdout.decode("utf-8", "replace").strip()
    except Exception:
        pass
    return None


def minutes_from_now(stamp):
    """`MM-dd HH:mm`（本地）与此刻的分钟差绝对值；跨年时取最接近的一年。"""
    match = re.match(r"^(\d{2})-(\d{2}) (\d{2}):(\d{2})$", stamp)
    if not match:
        return None
    month, day, hour, minute = (int(g) for g in match.groups())
    now = datetime.datetime.now()
    best = None
    for year in (now.year - 1, now.year, now.year + 1):
        try:
            moment = datetime.datetime(year, month, day, hour, minute)
        except ValueError:
            continue
        delta = abs((now - moment).total_seconds()) / 60.0
        best = delta if best is None else min(best, delta)
    return best


def main(argv):
    configure_stdout_utf8()
    explicit = None
    if "--exe" in argv:
        at = argv.index("--exe")
        if at + 1 >= len(argv):
            print("RESULT: FAIL")
            print("REASON: --exe 后面要跟一个产物路径")
            return 1
        explicit = argv[at + 1]

    root = repo_root()
    expected_version = read_expected_version(root)
    head = git_head(root)
    exe = find_exe(root, explicit)

    # 期望形状的标题（版本号从 Cargo.toml 现读；读不到就退回「只对形状」）。
    if expected_version is not None:
        title_pattern = (
            r"^Doyah Studio %s · ([0-9a-f]{7,}) · (\d{2}-\d{2} \d{2}:\d{2})$"
            % re.escape(expected_version)
        )
    else:
        title_pattern = r"^Doyah Studio \S+ · ([0-9a-f]{7,}) · (\d{2}-\d{2} \d{2}:\d{2})$"
    title_regex = re.compile(title_pattern)

    problems = []

    if expected_version is None:
        problems.append("读不到 src-tauri/Cargo.toml 里的版本号（找不到文件或 [package].version）")
    if head is None:
        problems.append("git rev-parse --short HEAD 取不到（不在 git 工作树里？）")
    if exe is None:
        problems.append("找不到 %s（看过 CARGO_TARGET_DIR / .build / .build-cache / platform/windows/target 的 debug 与 release）" % EXE_NAME)

    title = None
    title_note = None
    if exe is not None:
        print("EXE=%s" % exe)
        title, title_note = spawn_and_read_title(
            exe, lambda candidate: title_regex.match(candidate) is not None
        )
        if title is None:
            problems.append("起窗读标题失败：%s" % title_note)
        elif title_note is not None:
            problems.append(title_note)

    # 打印读数（`TITLE=` 行原样）
    print("TITLE=%s" % (title if title is not None else "<未读到>"))
    print("HEAD=%s" % (head if head is not None else "<未取到>"))

    head_in_title = None
    stamp_in_title = None
    if title is not None:
        match = title_regex.match(title)
        if match is None:
            if expected_version is not None:
                problems.append(
                    "TITLE 与期望形状不符（期望 `Doyah Studio %s · <7+ 位十六进制短号> · MM-dd HH:mm`）：%s"
                    % (expected_version, title)
                )
            else:
                problems.append("TITLE 与期望形状不符：%s" % title)
        else:
            head_in_title, stamp_in_title = match.group(1), match.group(2)

    if head_in_title is not None and head is not None and head_in_title != head:
        problems.append("TITLE 里的短号（%s）与 HEAD（%s）不一致" % (head_in_title, head))

    if stamp_in_title is not None:
        delta = minutes_from_now(stamp_in_title)
        if delta is None:
            problems.append("TITLE 里的时刻解析不了：%s" % stamp_in_title)
        elif delta > TIME_TOLERANCE_MINUTES:
            problems.append(
                "TITLE 里的时刻（%s）与此刻相差约 %.0f 分钟，超过 %d 分钟容差"
                % (stamp_in_title, delta, TIME_TOLERANCE_MINUTES)
            )
    elif title is not None:
        problems.append("TITLE 里取不到构建时刻")

    if problems:
        result = "FAIL"
        print("REASON=%s" % "；".join(problems))
    else:
        result = "PASS"
    print("RESULT: %s" % result)
    return 0 if result == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
