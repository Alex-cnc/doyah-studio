#!/usr/bin/env bash
# 把刚打好的 dist 包装到「人真的会点开的地方」（`~/Applications`）。
#
# 为什么单独一条：主人 2026-10-30 报「QQ 扫码配置也没有」—— 查下来是 `~/Applications`
# 里那份包停在 10-27，而每一轮只更新了 `dist/`。打包成功 ≠ 主人看得到。
#
# 行为：出错就退；装之前留有回滚目录；装完打印新旧版本读数，便于核对。
set -euo pipefail

cd "$(dirname "$0")/.."

# 装哪一份：默认仍是 `DoyahStudio-beta1.0.app`（行为不变）；`build-app.sh` 现在把
# **这一次的产物名**当第一个参数传进来（`--label beta1.1` 发的正式版也能直接装上）。
APP_NAME="${1:-DoyahStudio-beta1.0.app}"
SRC="dist/${APP_NAME}"
DEST_ROOT="${DOYAH_INSTALL_DIR:-$HOME/Applications}"
DEST="${DEST_ROOT}/${APP_NAME}"

if [[ ! -d "${SRC}" ]]; then
  echo "错误：找不到 ${SRC}；先跑 Scripts/build-app.sh" >&2
  exit 1
fi

# 变体包（rc / 开发中的包）**不进** `~/Applications`：那里只放主人天天在用的日常版，
# 装一个还没验过的包进去等于把他的工具换掉。装之前再挡一道（构建侧已经挡了）。
case "${APP_NAME}" in
  *-rc*.app | *.rc.app)
    echo "拒绝安装变体包：${APP_NAME}（rc 只留在 dist/ 验 bug，不进 ~/Applications）" >&2
    exit 1
    ;;
esac

mkdir -p "${DEST_ROOT}"

if [[ -d "${DEST}" ]]; then
  STAMP="$(date +%Y%m%d-%H%M%S)"
  BACKUP="${DEST_ROOT}/${APP_NAME%.app}.backup-${STAMP}.app"
  mv "${DEST}" "${BACKUP}"
  echo "旧版本已备份：${BACKUP}"
fi

ditto "${SRC}" "${DEST}"

NEW_BIN="${DEST}/Contents/MacOS/DoyahStudio"
echo "已安装：${DEST}"
echo "二进制：$(shasum -a 256 "${NEW_BIN}" | cut -c1-16) · $(( $(stat -f%z "${NEW_BIN}") / 1024 )) KB · $(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "${NEW_BIN}")"
echo "启动：open \"${DEST}\""
