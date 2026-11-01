#!/usr/bin/env bash
# 轮次锁：保证「一轮接一轮」时不会有两跳同时在跑。
#
#   Scripts/agent-lock.sh acquire <标签>   # 已有活锁 ⇒ 退出码 3（本轮让路）
#   Scripts/agent-lock.sh release          # 轮末删锁；**下一跳就在删锁之后**
#   Scripts/agent-lock.sh status           # 打印持有者与已持有时长
#
# 判陈旧用「**持有时长**」，不认 pid。
# 为什么：cron 会话里抢锁的是个短命子壳，壳一退 pid 就死，可跳本身还在跑
# （2026-11-01 实测：第二跳 20:03 抢锁、跑 20.5 分钟，壳早退了，按 pid 判会误当陈旧锁，
#  把在跑的一跳当死锁清掉 ⇒ 会双开）。改为 age-based：超过 STALE_MINUTES 分钟才算陈旧。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK="$ROOT/.agent/lock"
STALE_MINUTES="${AGENT_LOCK_STALE_MINUTES:-45}"
cmd="${1:-status}"

age_minutes() {
  local started
  started="$(awk '{print $1}' "$LOCK" 2>/dev/null)"
  [ -n "${started:-}" ] || { echo 999999; return; }
  echo $(( ( $(date +%s) - started ) / 60 ))
}

case "$cmd" in
  acquire)
    tag="${2:-tick}"
    if [ -f "$LOCK" ]; then
      age="$(age_minutes)"
      if [ "$age" -lt "$STALE_MINUTES" ]; then
        echo "锁被持有 ${age} 分钟（超过 ${STALE_MINUTES} 分钟才算陈旧）：$(cat "$LOCK")"
        exit 3
      fi
      echo "接管陈旧锁（已 ${age} 分钟）：$(cat "$LOCK")"
    fi
    echo "$(date +%s) $tag $$" > "$LOCK"
    echo "已持锁：$(cat "$LOCK")（pid 只是记号，陈旧判定看持有时长）"
    ;;
  release)
    rm -f "$LOCK"
    echo "锁已释放"
    ;;
  status)
    if [ -f "$LOCK" ]; then
      echo "$(cat "$LOCK")（已持有 $(age_minutes) 分钟）"
    else
      echo "（无锁）"
    fi
    ;;
  *)
    echo "用法: agent-lock.sh acquire|release|status" >&2; exit 2;;
esac
