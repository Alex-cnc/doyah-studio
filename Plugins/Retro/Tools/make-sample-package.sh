#!/bin/bash
# DoyahRetro · macOS · 端到端样例包生成脚本（M0 第 5 片 · 派单卡 `t_7530f3d6`）。
#
# 用途：把 `Plugins/Retro/Fixtures/` 下的**端到端样例包 + 负例包**逐字节重建出来。
# （本脚本 2026-11-03 随 Retro 的 macOS 实现从 `DoyahRetro/platform/macos` 迁入 Studio 仓。）
# 为什么要有生成脚本（而不是只提交结果）：样例包里有二进制（2 张 PNG + 1 个本地 `mp4`），
# 二进制在评审里没法逐行看；把「它长什么样、字节从哪来」写死在脚本里，评审就能**复算** ——
#   bash Plugins/Retro/Tools/make-sample-package.sh   ⇒ 产物 sha256 与提交在册值一致。
#
# 硬口径：
#   · **零外部依赖**：只用 `bash` + `base64`（macOS 自带）。三个二进制全部内嵌为 base64 常量
#     —— 不调 `ffmpeg` / `curl` / 不碰网络 ⇒ 同一脚本在任何机器上产出**同一份字节**；
#   · **可自由分发**：三个二进制都是自制小样本（2 张 64×64 PNG + 1 个 1 秒 64×64 H.264+AAC 的
#     `mp4`），不含任何受版权保护的媒体；
#   · **幂等**：固定文件清单，逐个覆盖写；不删目录、不动清单外的任何文件（**无 `rm`**）；
#   · **不碰清单外**：只写 `Fixtures/{sample,negative}/**`。
#
# 用法（仓根执行）：
#   bash Plugins/Retro/Tools/make-sample-package.sh
#
# 产物（与提交在册的 `Fixtures/**` 逐字节一致；sha256 见 `Plugins/Retro/README.md`）：
#   Fixtures/sample/2026-W40/     样例包 = 2 图 + 1 本地 mp4 + 1 外链（外链写在 report.md 里）
#   Fixtures/negative/2026-W41/   负例：白名单外格式 avi / mov ⇒ 占位 + 一条报告
#   Fixtures/negative/2026-W42/   负例：媒体缺失          ⇒ 占位 + 一条报告
#   Fixtures/negative/2026-W43/   负例：路径越界 `../`    ⇒ 拒绝 + 一条报告
#   Fixtures/negative/2026-W44/   负例：**空包**（空目录）
#   Fixtures/negative/2026-W45/   负例：坏 index.json     ⇒ 逐条报告、不崩
#
# 关于 `2026-W44`：git **不跟踪空目录** ⇒ 它只由本脚本 mkdir 出来（本脚本 = 样例包的唯一生成入口）。
# 一个空目录不进 `git status`（不算脏），故重建后仓库仍干净。
#
# 注意（bash 3.2）：本机 `/bin/bash` 是 3.2.57，变量后紧跟中文会被静默吞掉 ⇒ 插值一律写 `${变量}`。

set -euo pipefail

# 目录定位：本脚本在 Plugins/Retro/Tools/ ⇒ 上溯两级 = Plugins/Retro
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
MACOS_DIR="$(cd "${HERE}/.." && pwd -P)"
FIXTURES="${MACOS_DIR}/Fixtures"

# base64 解码落盘：$1 = 目标文件，正文从 stdin 读（base64 忽略换行）。
b64write() {
  mkdir -p "$(dirname "$1")"
  base64 -D > "$1"
}

echo "==> 重建端到端样例包与负例包：${FIXTURES}"

# ───────────── 样例包 `2026-W40`：2 图 + 1 本地 mp4 + 1 外链 ─────────────
mkdir -p "${FIXTURES}/sample/2026-W40/assets"

b64write "${FIXTURES}/sample/2026-W40/assets/trend-01.png" <<'B64'
iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAACXBIWXMAAAABAAAAAQBPJcTWAAAA
Y0lEQVR4nO3PsQkAIQDAQAVbJ7Z37h/C4njITZDMfe74s6UDXjWgNaA1oDWgNaA1oDWgNaA1oDWg
NaA1oDWgNaA1oDWgNaA1oDWgNaA1oDWgNaA1oDWgNaA1oDWgNaA1oDWgfQVQAgx9t3tmAAAAAElF
TkSuQmCC
B64

b64write "${FIXTURES}/sample/2026-W40/assets/trend-02.png" <<'B64'
iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAACXBIWXMAAAABAAAAAQBPJcTWAAAA
Y0lEQVR4nO3PwQnAIADAQAVxZVd1nA7h4yjkJkjmPXv82dIBrxrQGtAa0BrQGtAa0BrQGtAa0BrQ
GtAa0BrQGtAa0BrQGtAa0BrQGtAa0BrQGtAa0BrQGtAa0BrQGtAa0BrQPmiQAlOjvB0HAAAAAElF
TkSuQmCC
B64

b64write "${FIXTURES}/sample/2026-W40/assets/clip.mp4" <<'B64'
AAAAIGZ0eXBpc29tAAACAGlzb21pc28yYXZjMW1wNDEAAAXsbW9vdgAAAGxtdmhkAAAAAAAAAAAA
AAAAAACsRAAArEQAAQAAAQAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAA
AABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAwAAApp0cmFrAAAAXHRraGQAAAADAAAA
AAAAAAAAAAABAAAAAAAArEQAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAA
AAAAAAAAAABAAAAAAEAAAABAAAAAAAAkZWR0cwAAABxlbHN0AAAAAAAAAAEAAKxEAAAAAAABAAAA
AAISbWRpYQAAACBtZGhkAAAAAAAAAAAAAAAAAAAoAAAAKABVxAAAAAAALWhkbHIAAAAAAAAAAHZp
ZGUAAAAAAAAAAAAAAABWaWRlb0hhbmRsZXIAAAABvW1pbmYAAAAUdm1oZAAAAAEAAAAAAAAAAAAA
ACRkaW5mAAAAHGRyZWYAAAAAAAAAAQAAAAx1cmwgAAAAAQAAAX1zdGJsAAAAuXN0c2QAAAAAAAAA
AQAAAKlhdmMxAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAEAAQABIAAAASAAAAAAAAAABDExhdmMg
bGlieDI2NAAAAAAAAAAAAAAAAAAAAAAAAAAAGP//AAAAL2F2Y0MBQsAK/+EAF2dCwArZBCbARAAA
AwAEAAADAFA8SJkgAQAFaMuDyyAAAAAQcGFzcAAAAAEAAAABAAAAFGJ0cnQAAAAAAAAXIAAAAAAA
AAAYc3R0cwAAAAAAAAABAAAACgAABAAAAAAUc3RzcwAAAAAAAAABAAAAAQAAABxzdHNjAAAAAAAA
AAEAAAABAAAAAQAAAAEAAAA8c3RzegAAAAAAAAAAAAAACgAAAooAAAAKAAAACgAAAAoAAAAKAAAA
CgAAAAoAAAAKAAAACgAAAAoAAAA4c3RjbwAAAAAAAAAKAAAGIAAACL4AAAjYAAAI8gAACRAAAAkq
AAAJRAAACWIAAAl8AAAJlgAAAqF0cmFrAAAAXHRraGQAAAADAAAAAAAAAAAAAAACAAAAAAAArAAA
AAAAAAAAAAAAAAEBAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAA
AAAAAAAkZWR0cwAAABxlbHN0AAAAAAAAAAEAAKwAAAAEAAABAAAAAAIZbWRpYQAAACBtZGhkAAAA
AAAAAAAAAAAAAACsRAAAsABVxAAAAAAALWhkbHIAAAAAAAAAAHNvdW4AAAAAAAAAAAAAAABTb3Vu
ZEhhbmRsZXIAAAABxG1pbmYAAAAQc21oZAAAAAAAAAAAAAAAJGRpbmYAAAAcZHJlZgAAAAAAAAAB
AAAADHVybCAAAAABAAABiHN0YmwAAAB+c3RzZAAAAAAAAAABAAAAbm1wNGEAAAAAAAAAAQAAAAAA
AAAAAAEAEAAAAACsRAAAAAAANmVzZHMAAAAAA4CAgCUAAgAEgICAF0AVAAAAAAB9AAAABWIFgICA
BRIIVuUABoCAgAECAAAAFGJ0cnQAAAAAAAB9AAAABWIAAAAYc3R0cwAAAAAAAAABAAAALAAABAAA
AABkc3RzYwAAAAAAAAAHAAAAAQAAAAEAAAABAAAAAgAAAAUAAAABAAAAAwAAAAQAAAABAAAABQAA
AAUAAAABAAAABgAAAAQAAAABAAAACAAAAAUAAAABAAAACQAAAAQAAAABAAAAFHN0c3oAAAAAAAAA
BAAAACwAAAA8c3RjbwAAAAAAAAALAAAGHAAACKoAAAjIAAAI4gAACPwAAAkaAAAJNAAACU4AAAls
AAAJhgAACaAAAAAac2dwZAEAAAByb2xsAAAAAgAAAAH//wAAABxzYmdwAAAAAHJvbGwAAAABAAAA
LAAAAAEAAAA9dWR0YQAAADVtZXRhAAAAAAAAACFoZGxyAAAAAAAAAABtZGlyYXBwbAAAAAAAAAAA
AAAAAAhpbHN0AAAACGZyZWUAAAOcbWRhdAEYIAcAAAJjBgX//1/cRem95tlIt5Ys2CDZI+7veDI2
NCAtIGNvcmUgMTY1IC0gSC4yNjQvTVBFRy00IEFWQyBjb2RlYyAtIENvcHlsZWZ0IDIwMDMtMjAy
NSAtIGh0dHA6Ly93d3cudmlkZW9sYW4ub3JnL3gyNjQuaHRtbCAtIG9wdGlvbnM6IGNhYmFjPTAg
cmVmPTMgZGVibG9jaz0xOjA6MCBhbmFseXNlPTB4MToweDExMSBtZT1oZXggc3VibWU9NyBwc3k9
MSBwc3lfcmQ9MS4wMDowLjAwIG1peGVkX3JlZj0xIG1lX3JhbmdlPTE2IGNocm9tYV9tZT0xIHRy
ZWxsaXM9MSA4eDhkY3Q9MCBjcW09MCBkZWFkem9uZT0yMSwxMSBmYXN0X3Bza2lwPTEgY2hyb21h
X3FwX29mZnNldD0tMiB0aHJlYWRzPTIgbG9va2FoZWFkX3RocmVhZHM9MSBzbGljZWRfdGhyZWFk
cz0wIG5yPTAgZGVjaW1hdGU9MSBpbnRlcmxhY2VkPTAgYmx1cmF5X2NvbXBhdD0wIGNvbnN0cmFp
bmVkX2ludHJhPTAgYmZyYW1lcz0wIHdlaWdodHA9MCBrZXlpbnQ9MjUwIGtleWludF9taW49MTAg
c2NlbmVjdXQ9NDAgaW50cmFfcmVmcmVzaD0wIHJjX2xvb2thaGVhZD00MCByYz1jcmYgbWJ0cmVl
PTEgY3JmPTIzLjAgcWNvbXA9MC42MCBxcG1pbj0wIHFwbWF4PTY5IHFwc3RlcD00IGlwX3JhdGlv
PTEuNDAgYXE9MToxLjAwAIAAAAAfZYiED/EYoAAk0xwABDmjgACSbJycnXXXXXXXXXXXXgEYIAcB
GCAHARggBwEYIAcBGCAHAAAABkGaOB/hGAEYIAcBGCAHARggBwEYIAcAAAAGQZpUB/hGARggBwEY
IAcBGCAHARggBwAAAAZBmmA/wjABGCAHARggBwEYIAcBGCAHARggBwAAAAZBmoA/wjABGCAHARgg
BwEYIAcBGCAHAAAABkGaoD/CMAEYIAcBGCAHARggBwEYIAcAAAAGQZrAP8IwARggBwEYIAcBGCAH
ARggBwEYIAcAAAAGQZrgP8IwARggBwEYIAcBGCAHARggBwAAAAZBmwA7wjABGCAHARggBwEYIAcB
GCAHAAAABkGbIDfCMAEYIAcBGCAHARggBwEYIAc=
B64

cat > "${FIXTURES}/sample/2026-W40/index.json" <<'JSON'
{
  "id": "2026-W40",
  "title": "国际趋势分析周报 · 2026-W40",
  "published": "2026-10-05",
  "summary": "端到端样例包：2 图 + 1 本地 mp4 + 1 外链（R-05）。",
  "cover": "assets/trend-01.png",
  "media_count": 3
}
JSON

cat > "${FIXTURES}/sample/2026-W40/report.md" <<'MD'
# 国际趋势分析周报 · 2026-W40

端到端样例包：**2 图 + 1 本地 `mp4` + 1 外链**（媒体条目 = 独占一行的 `![alt](引用)`）。

## 一、趋势图（图片内联）

![趋势图一](assets/trend-01.png)

![趋势图二](assets/trend-02.png)

## 二、本地视频（本机内联可播）

![本地视频](assets/clip.mp4)

## 三、外链视频（交系统默认处理）

![外链视频](https://example.com/doyah/weekly/clip.mp4)
MD

# ───────────── 负例 `2026-W41`：白名单外格式 avi / mov ─────────────
mkdir -p "${FIXTURES}/negative/2026-W41/assets"
printf '%s\n' 'DoyahRetro 样例：白名单外的 avi 存根（文件确实在盘上，格式门仍判占位 —— 格式门在碰盘之前）。' \
  > "${FIXTURES}/negative/2026-W41/assets/raw.avi"
printf '%s\n' 'DoyahRetro 样例：白名单外的 mov 存根（同上）。' \
  > "${FIXTURES}/negative/2026-W41/assets/raw.mov"

cat > "${FIXTURES}/negative/2026-W41/index.json" <<'JSON'
{
  "id": "2026-W41",
  "title": "负例 W41 · 白名单外格式",
  "published": "2026-10-12",
  "summary": "avi / mov 不在白名单 ⇒ 原位占位 + 一条报告。",
  "media_count": 2
}
JSON

cat > "${FIXTURES}/negative/2026-W41/report.md" <<'MD'
# 负例 · 白名单外格式（avi / mov）

文件确实在盘上（`assets/raw.avi` / `assets/raw.mov`），但格式不在白名单 ⇒ **原位占位 + 一条报告**。

![avi 样本](assets/raw.avi)

![mov 样本](assets/raw.mov)
MD

# ───────────── 负例 `2026-W42`：媒体缺失 ─────────────
mkdir -p "${FIXTURES}/negative/2026-W42"
cat > "${FIXTURES}/negative/2026-W42/index.json" <<'JSON'
{
  "id": "2026-W42",
  "title": "负例 W42 · 媒体缺失",
  "published": "2026-10-19",
  "summary": "白名单内格式、但盘上没有这个文件 ⇒ 原位占位 + 一条报告。",
  "media_count": 1
}
JSON

cat > "${FIXTURES}/negative/2026-W42/report.md" <<'MD'
# 负例 · 媒体缺失

引用是白名单内的 `png`，但 `assets/nope.png` **不在盘上** ⇒ 原位占位 + 一条报告（不静默）。

![缺失的图](assets/nope.png)
MD

# ───────────── 负例 `2026-W43`：路径越界 `../` ─────────────
mkdir -p "${FIXTURES}/negative/2026-W43"
cat > "${FIXTURES}/negative/2026-W43/index.json" <<'JSON'
{
  "id": "2026-W43",
  "title": "负例 W43 · 路径越界",
  "published": "2026-10-26",
  "summary": "引用含 `..` ⇒ 拒绝并原位占位 + 一条报告。",
  "media_count": 1
}
JSON

cat > "${FIXTURES}/negative/2026-W43/report.md" <<'MD'
# 负例 · 路径越界（`../`）

引用含 `..` ⇒ **拒绝**并原位占位 + 一条报告（`IR-05` 不变量 3：媒体只许包内相对路径）。

![越界引用](../outside.png)
MD

# ───────────── 负例 `2026-W44`：空包（空目录；git 不跟踪 ⇒ 只由本脚本建）─────────────
mkdir -p "${FIXTURES}/negative/2026-W44"

# ───────────── 负例 `2026-W45`：坏 index.json ─────────────
mkdir -p "${FIXTURES}/negative/2026-W45"
cat > "${FIXTURES}/negative/2026-W45/index.json" <<'JSON'
{ "id": "2026-W45", 这不是合法 JSON —— 缺引号与逗号
JSON

cat > "${FIXTURES}/negative/2026-W45/report.md" <<'MD'
# 负例 · 坏 index.json

本目录的 `index.json` 不是合法 JSON ⇒ 扫描器**逐条报告**（`invalidJSON`）且**不崩**，其余目录照常解析。
MD

echo "==> 产物 sha256（与提交在册值逐字节对账）："
for _f in \
  "${FIXTURES}/sample/2026-W40/assets/trend-01.png" \
  "${FIXTURES}/sample/2026-W40/assets/trend-02.png" \
  "${FIXTURES}/sample/2026-W40/assets/clip.mp4" \
  "${FIXTURES}/negative/2026-W41/assets/raw.avi" \
  "${FIXTURES}/negative/2026-W41/assets/raw.mov"; do
  printf '    %s  %s\n' "$(shasum -a 256 "${_f}" | cut -d' ' -f1)" "${_f#"${MACOS_DIR}/"}"
done
echo "✅ 样例包重建完成。"
