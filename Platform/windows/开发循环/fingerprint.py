#!/usr/bin/env python3
"""Windows 开发循环 · 指纹脚本（给 cron 的 monitor 用）

规则（照 autonomous-dev-loop 的「指纹门禁」）：
  · 输出**逐字节稳定**：无时间戳、无随机序、无绝对路径 —— 相同 ⇒ 调度器静默跳（零 token、不唤起模型）
  · 不同 ⇒ 唤醒一轮，并把 diff 注入提示词
  · 唯一允许随时间变化的成分 = **停滞桶**（status=running 且超过 1 小时 ⇒ 每个小时最多再唤醒一次），
    防止「某一轮悄悄挂了、内容再也不变 ⇒ 永远不再被叫醒」

输出五行：head / remote / dirty / lock / state
"""
import json
import os
import subprocess
import sys
import time

REPO = r"D:\dev\doyah\lead\studio"
LOOP_DIR = os.path.join(REPO, "Platform", "windows", "开发循环")
LOCK = os.path.join(LOOP_DIR, ".round.lock")
STATE = os.path.join(LOOP_DIR, "state.json")
STALE_SECONDS = 50 * 60  # 轮次锁超过 50 分钟判陈旧（单轮熔断线 45 分钟 + 余量）
STALL_SECONDS = 60 * 60  # status=running 超过 1 小时判「疑似卡住」，每小时最多唤醒一次


def git(*args: str) -> str:
    try:
        done = subprocess.run(
            ["git", "-C", REPO, *args],
            capture_output=True, text=True, timeout=25,
        )
        return done.stdout.strip()
    except Exception:
        return "ERR"


def lock_state() -> str:
    if not os.path.exists(LOCK):
        return "free"
    try:
        parts = open(LOCK, encoding="utf-8").read().split()
        epoch = int(parts[0])
    except Exception:
        return "stale"
    return "held" if time.time() - epoch <= STALE_SECONDS else "stale"


def state_line() -> str:
    if not os.path.exists(STATE):
        return "none"
    try:
        data = json.load(open(STATE, encoding="utf-8"))
    except Exception:
        return "bad"
    status = str(data.get("status", "?"))
    head = str(data.get("head", "?"))[:7]
    line = "%s/%s" % (status, head)
    # 停滞桶：只有「自称在跑」且超过 1 小时才加一个按小时递增的后缀
    if status == "running":
        try:
            age = time.time() - float(data.get("at", 0))
        except Exception:
            age = 0.0
        if age > STALL_SECONDS:
            line += "@stalled%d" % int(age // STALL_SECONDS)
    return line


def main() -> int:
    if not os.path.isdir(REPO):
        # 仓缺失也要给**稳定**输出（否则每跳都算「变了」）
        print("repo=missing")
        return 0
    print("head=%s" % (git("rev-parse", "--short", "HEAD") or "none"))
    print("remote=%s" % (git("rev-parse", "--short", "origin/master") or "none"))
    print("dirty=%s" % ("1" if git("status", "--porcelain") else "0"))
    print("lock=%s" % lock_state())
    print("state=%s" % state_line())
    return 0


if __name__ == "__main__":
    sys.exit(main())
