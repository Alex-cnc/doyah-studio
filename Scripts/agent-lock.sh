#!/usr/bin/env bash
# 轮次锁：保证「一轮接一轮」时不会有两跳同时在跑。
#
#   Scripts/agent-lock.sh acquire <标签>   # 拿到锁写自己的 pid；已被活着的进程持有 ⇒ 退出码 3
#   Scripts/agent-lock.sh release          # 轮末删锁（**下一跳的点火就在删锁之后**）
#   Scripts/agent-lock.sh status           # 打印持有者；空 = 无人持有
#
# 锁文件放 .agent/lock，内容是「pid 标签 时间」。持有者进程已死 ⇒ 视为陈旧锁，自动接管。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK="$ROOT/.agent/lock"
cmd="${1:-status}"

alive() { kill -0 "$1" 2>/dev/null; }

case "$cmd" in
  acquire)
    tag="${2:-tick}"
    if [ -f "$LOCK" ]; then
      read -r pid rest < "$LOCK" || true
      if [ -n "${pid:-}" ] && alive "$pid"; then
        echo "锁被别人持有：$(cat "$LOCK")"
        exit 3
      fi
      echo "接管陈旧锁：$(cat "$LOCK")"
    fi
    echo "$$ $tag $(date '+%Y-%m-%d %H:%M:%S')" > "$LOCK"
    echo "已持锁：$(cat "$LOCK")"
    ;;
  release)
    rm -f "$LOCK"
    echo "锁已释放"
    ;;
  status)
    [ -f "$LOCK" ] && cat "$LOCK" || echo "（无锁）"
    ;;
  *)
    echo "用法: agent-lock.sh acquire|release|status" >&2; exit 2;;
esac
