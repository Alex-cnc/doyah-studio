#!/bin/bash
# Doyah Studio · **三模块 alpha 主链复跑器（v0.2 收口主线）**（2026-09-28 起）
#
# ## 为什么有它
# `alpha-main-chain.sh`（v1）只回答「**数据库模块**可以发 alpha 了吗」。需求提出者 2026-09-28 拍板
# 方案 B：**v0.2.0-alpha 覆盖三个模块**（工作区 / 数据库 / 笔记），于是判据也得从「一条链」
# 变成「三条链各自的机器可验部分都全绿」—— 本文件就是那三条链的**统一入口**。
#
# ## 三档（口径与 v1 **逐字一致**，不另立一套）
#   · **本机段（LOCAL）**：能在本机上真跑 ⇒ **任一段非绿 ⇒ alpha 未达**。
#   · **预期红（KNOWN_RED）**：现状就红、原因已登记在 `Scripts/real-db-evidence-baseline.json`
#     ⇒ 只登记，不判 alpha 红绿；**忽然转绿要点名**（该更新基线了）。
#   · **环境段（ENV）**：需 217 / 真实例 / vendor 改动才能跑 ⇒ **alpha 明确不含**，只登记；
#     与仓根 `RELEASE-0.2.0-alpha.md` 的「alpha 明确不含」逐条对应。
#
# ## 两种判定（段自己声明，**不许含糊**）
#   · `assert`（**断言型**）：退出码 0 **且**断言 > 0 才算绿 —— 「exit 0 但断言 0」= 空跑，
#     不许当绿（口径见 `Scripts/count-evidence-assertions.py`）。
#   · `gate`（**门禁型**）：门禁脚本本身不产断言行（输出不以 `  ✅ ` 开头）⇒ 只判退出码；
#     这类段**必须配一个断言型的负例**（`test-*.py`）在旁边，否则「绿」分不清「真没违规」与
#     「扫了个寂寞」—— 本工程的 L-04 / L-05 / 第 14 项都栽在这一条上。
#
# ## 模块与段的来源
#   · **B 数据库**：**委托** `Scripts/alpha-main-chain.sh`（不复制它的 25 段清单 —— 复制出去就要
#     两边各修一次）⇒ 本文件读它的证据文件取三档计数，只把「本机段红 0」当判据。
#   · **A 工作区**：`编辑器 / 多页签 / 结果集 / 导出 / 终端`。其中**结果集与导出**的真库现场就是
#     数据库模块的第 4 / 5 段（同一批脚本）⇒ 本文件把它们登记为**引用段**（写清指向哪一段），
#     **不重跑**：同一条脚本跑两遍只会让耗时翻倍，不会多出证据。
#   · **C 笔记**：装配 + 本地库（数据家 / 迁移 / vendored SQLite）+ 检索（含"零网络出口"）。
#     Linux 端不在本机范围（三书继续出、本侧不实现）。
#
# ## 用法
#   ./Scripts/alpha-main-chain-v0.2.sh                          # 三模块全跑，证据写 .build/alpha-0.2.0/
#   DOYAH_ALPHA_V2_OUT=<目录> ./Scripts/alpha-main-chain-v0.2.sh
#   DOYAH_ALPHA_V2_MODULE=工作区 ./Scripts/alpha-main-chain-v0.2.sh   # 只跑一个模块
#   DOYAH_ALPHA_V2_ONLY=配色 ./Scripts/alpha-main-chain-v0.2.sh       # 只跑名字含关键字的段
#   DOYAH_ALPHA_V2_SKIP_DB=1 ./Scripts/alpha-main-chain-v0.2.sh       # 跳过数据库模块（它自己有 v1）
#
# 注意（bash 3.2 多字节坑，见 `Scripts/check-shell-locale-safety.py`）：变量一律 `${变量}`。

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
ROOT="$(pwd)"
OUT="${DOYAH_ALPHA_V2_OUT:-${ROOT}/.build/alpha-0.2.0}"
MODULE_FILTER="${DOYAH_ALPHA_V2_MODULE:-}"
ONLY="${DOYAH_ALPHA_V2_ONLY:-}"
SKIP_DB="${DOYAH_ALPHA_V2_SKIP_DB:-}"
mkdir -p "${OUT}"
SUMMARY="${OUT}/主链证据.md"
DB_OUT="${OUT}/数据库模块"
mkdir -p "${DB_OUT}"

# ---------------------------------------------------------------- 段清单（模块 × 档）
# 格式：`名字|脚本|模式|判定要点`；模式 = assert（退出码 0 且断言 > 0）| gate（只判退出码）
#
# A 工作区（编辑器 / 多页签 / 结果集 / 导出 / 终端）
WS_LOCAL=(
  "编辑器-语言层|test-workspace-editor.sh|assert|着色 / 补全 / 行号列：进去的是哪种语言、出来的token 对不对（FR-EDIT-36）"
  "终端-输入编码|test-terminal-modes.sh|assert|鼠标上报 / DECCKM / DA1·DSR 应答逐条核对（FR-EDIT-29）"
  "终端-配色|test-terminal-palette.sh|assert|两套色板 + WCAG 门槛：单测与脚本各算一遍，同结论才算成立（FR-EDIT-29）"
  "终端-配色门禁|check-terminal-palette.py|gate|配色不达标即红（与上一条互为红 / 绿成对）"
  "命令面板-接线|check-palette-wiring.py|gate|设了标志位必须有人读（FR-EDIT-25 的老毛病）"
)
# 引用段：工作区模块要的「结果集 / 导出」的真库现场就在数据库模块里，登记指向、不重跑。
WS_REF=(
  "结果集-复制|引用：数据库模块「4 结果集-复制」段（test-result-copy.sh）"
  "导出-整表|引用：数据库模块「5 导出-整表」段（test-table-export.sh）"
  "导出-xlsx|引用：数据库模块「5 导出-xlsx」段（test-xlsx-export.sh）"
)
WS_KR=()
WS_ENV=()

# C 笔记（装配 + 本地库 + 检索）
NOTE_LOCAL=(
  "装配-解耦门禁|check-note-module-isolation.py|gate|笔记侧文件不许依赖数据库 / Ultra 侧类型（FR-PLUG-07）"
  "装配-装配链门禁|check-plugin-assembly.py|gate|同进程 / 单一判据 / 单向上下文（FR-PLUG-01~03 / 06）"
  "本地库-数据家与迁移|test-note-data-boundary.sh|assert|默认位置在工程数据家之外 / 迁移留备份 / 坏文件绝不覆盖（FR-PLUG-04）"
  "本地库-vendored SQLite|check-vendored-sqlite.py|gate|存储引擎换本地 SQLite：台账对账 + 现编现跑自证（FR-PLUG-08 / Q23）"
  "检索-界面走库口径|check-note-search-route.py|gate|唯一生产点 / 视图无内存过滤 / 走的哪条路如实标注"
  "检索-口径负例|test-note-search-route.py|assert|上一条门禁**红得出来**（写坏必报红并点名）"
  "检索-零网络出口|check-notes-offline.py|gate|笔记侧不许有任何出网入口（本地离线）"
  "检索-零网络负例|test-notes-offline-gate.py|assert|上一条门禁**红得出来**"
)
NOTE_KR=()
NOTE_ENV=()

GROUP_SKIPPED=()

printf '\033[1m▶︎ 三模块 alpha 主链（v0.2）· 口径与 v1 逐字一致：本机段判红绿 / 预期红与环境段只登记\033[0m\n'

pick() { # pick <段名> ⇒ 0=要跑 1=跳过
  if [ -n "${ONLY}" ]; then case "$1" in *"${ONLY}"*) return 0 ;; *) return 1 ;; esac; fi
  return 0
}

run_segment() { # run_segment <模块> <档> <spec…> ⇒ 输出表格行
  local module="$1" tier="$2"; shift 2
  local spec name rest script mode point log code count mark
  for spec in "$@"; do
    name="${spec%%|*}"; rest="${spec#*|}"
    script="${rest%%|*}"; rest="${rest#*|}"
    mode="${rest%%|*}"; point="${rest#*|}"
    pick "${name}" || continue
    log="${OUT}/$(printf '%s' "${module}_${name}" | tr ' /' '__').log"
    if [ ! -f "${ROOT}/Scripts/${script}" ]; then
      printf '· %s（%s）脚本不存在，**判红**（清单里有、仓里没有 ⇒ 不许当作通过）\n' "${name}" "${script}" >&2
      LOCAL_RED_COUNT=$((LOCAL_RED_COUNT + 1))
      LOCAL_RED_NAMES="${LOCAL_RED_NAMES}${name}(脚本不存在) "
      printf '\n| %s | %s | %s | ❌ 脚本不存在（清单与实际不符） | %s |' "${module}" "${tier}" "$(printf '`%s`' "${script}")" "${point}"
      continue
    fi
    case "${script}" in
      *.py) ( cd "${ROOT}" && python3 "Scripts/${script}" ) >"${log}" 2>&1 ;;
      *)    ( cd "${ROOT}" && bash "Scripts/${script}" ) >"${log}" 2>&1 ;;
    esac
    code=$?
    count="$(python3 "${ROOT}/Scripts/count-evidence-assertions.py" "${log}" 2>/dev/null \
             | head -1 | grep -oE '断言 [0-9]+ 项' | grep -oE '[0-9]+' | head -1)"
    [ -z "${count}" ] && count=0
    if [ "${mode}" = "gate" ]; then
      if [ "${code}" -eq 0 ]; then mark="✅"; else mark="❌"; fi
      printf '%s %-22s 门禁 退出码 %s\n' "${mark}" "${name}" "${code}" >&2
      printf '\n| %s | %s | %s | %s 退出码 %s（门禁型：只判退出码） | %s |' \
        "${module}" "${tier}" "$(printf '`%s`' "${script}")" "${mark}" "${code}" "${point}"
    else
      if [ "${code}" -eq 0 ] && [ "${count}" -gt 0 ]; then mark="✅"; else mark="❌"; fi
      printf '%s %-22s 退出码 %s 断言 %s\n' "${mark}" "${name}" "${code}" "${count}" >&2
      printf '\n| %s | %s | %s | %s 退出码 %s / 断言 %s | %s |' \
        "${module}" "${tier}" "$(printf '`%s`' "${script}")" "${mark}" "${code}" "${count}" "${point}"
    fi
  done
}

# 计数器**不能在 run_segment 里累加**：那些调用都写在 `$( … )` 命令替换里 ⇒ 子 shell，改的是副本。
# 所以一律**从已生成的表格行里数**（行文本就是事实，不会与计数脱钩）。

LOCAL_RED_COUNT=0
LOCAL_RED_NAMES=""
LOCAL_TOTAL=0

# ---------------------------------------------------------------- B 数据库模块（委托 v1）
DB_ROWS=""
DB_VERDICT="（跳过）"
DB_COUNTS="（本轮跳过，未取子证据）"
DB_LOCAL_TOTAL=0
DB_LOCAL_RED=0
if [ -n "${SKIP_DB}" ]; then
  printf '▶︎ B 数据库模块：按 DOYAH_ALPHA_V2_SKIP_DB 跳过\n' >&2
else
  printf '▶︎ B 数据库模块：委托 Scripts/alpha-main-chain.sh（它自己持有 25 段清单）\n' >&2
  if pick "数据库模块"; then
    DOYAH_ALPHA_OUT="${DB_OUT}" bash "${ROOT}/Scripts/alpha-main-chain.sh" >"${OUT}/数据库模块.log" 2>&1
    db_code=$?
    db_summary="${DB_OUT}/主链证据.md"
    if [ -f "${db_summary}" ]; then
      db_local_ok="$(awk '/^## 一、本机段/{f=1;next} /^## /{f=0} f && /\| ✅ /' "${db_summary}" | wc -l | tr -d ' ')"
      db_local_red="$(awk '/^## 一、本机段/{f=1;next} /^## /{f=0} f && /\| ❌ /' "${db_summary}" | wc -l | tr -d ' ')"
      # 一号表（本机段）的行数 = 表头「段 | 脚本 | 结果 | 判定要点」之后、下一个二级标题之前
      db_local_rows="$(awk '/^## 一、本机段/{f=1;next} /^## /{f=0} f && /^\| / && !/^\| *段 *\|/ && !/^\| *---/' "${db_summary}" | wc -l | tr -d ' ')"
      db_red_rows="$(awk '/^## 二、预期红/{f=1;next} /^## /{f=0} f && /^\| / && !/^\| *段 *\|/ && !/^\| *---/' "${db_summary}" | wc -l | tr -d ' ')"
      db_env_rows="$(awk '/^## 三、环境段/{f=1;next} /^## /{f=0} f && /^\| / && !/^\| *段 *\|/ && !/^\| *---/' "${db_summary}" | wc -l | tr -d ' ')"
      if [ "${db_code}" -eq 0 ]; then DB_VERDICT="✅ 本机段全绿"; else DB_VERDICT="❌ 本机段有红"; fi
      DB_COUNTS="本机段 ${db_local_rows} 段（绿 ${db_local_ok} / 红 ${db_local_red}）· 预期红 ${db_red_rows} 段 · 环境段 ${db_env_rows} 段"
      DB_ROWS="$(awk -F'|' '/^## 一、本机段/{f=1;next} /^## /{f=0} f && /^\| / && !/^\| *段 *\|/ && !/^\| *---/ {printf "\n| 数据库（%s） | 本机段 | %s | %s | %s |", $2, $3, $4, $5}' "${db_summary}")"
      DB_LOCAL_TOTAL="${db_local_rows}"
      DB_LOCAL_RED="${db_local_red}"
    else
      DB_VERDICT="❌ 取不到子证据文件（${db_summary}）"
      DB_COUNTS="（无）"
      DB_LOCAL_TOTAL=0
      DB_LOCAL_RED=1
    fi
  fi
fi

# ---------------------------------------------------------------- A 工作区模块
WS_ROWS=""
WS_REF_ROWS=""
if [ -z "${MODULE_FILTER}" ] || [ "${MODULE_FILTER}" = "工作区" ]; then
  printf '▶︎ A 工作区模块（编辑器 / 多页签 / 结果集 / 导出 / 终端）\n' >&2
  WS_ROWS="$(run_segment "工作区" "本机段" "${WS_LOCAL[@]}")"
  WS_ROWS="${WS_ROWS}$(run_segment "工作区" "预期红" ${WS_KR[@]+"${WS_KR[@]}"})"
  WS_ROWS="${WS_ROWS}$(run_segment "工作区" "环境段" ${WS_ENV[@]+"${WS_ENV[@]}"})"
  for spec in "${WS_REF[@]}"; do
    pick "${spec%%|*}" || continue
    WS_REF_ROWS="${WS_REF_ROWS}"$'\n'"| 工作区 | 引用段 | ${spec#*|} | ➖ 不重跑（同一批脚本） | 结果集与导出在数据库模块里已有真库现场，重复跑只费时间不多证据 |"
  done
else
  printf '· A 工作区模块：按 DOYAH_ALPHA_V2_MODULE 过滤，跳过\n' >&2
fi

# ---------------------------------------------------------------- C 笔记模块
NOTE_ROWS=""
if [ -z "${MODULE_FILTER}" ] || [ "${MODULE_FILTER}" = "笔记" ]; then
  printf '▶︎ C 笔记模块（装配 + 本地库 + 检索；Linux 端不在本机范围）\n' >&2
  NOTE_ROWS="$(run_segment "笔记" "本机段" "${NOTE_LOCAL[@]}")"
  NOTE_ROWS="${NOTE_ROWS}$(run_segment "笔记" "预期红" ${NOTE_KR[@]+"${NOTE_KR[@]}"})"
  NOTE_ROWS="${NOTE_ROWS}$(run_segment "笔记" "环境段" ${NOTE_ENV[@]+"${NOTE_ENV[@]}"})"
else
  printf '· C 笔记模块：按 DOYAH_ALPHA_V2_MODULE 过滤，跳过\n' >&2
fi

# ---------------------------------------------------------------- 计数（从表格行里数，不靠子 shell 里的计数器）
ALL_LOCAL_ROWS="$(printf '%s\n%s\n' "${WS_ROWS}" "${NOTE_ROWS}" | grep '| 本机段 |' || true)"
LOCAL_TOTAL="$(printf '%s' "${ALL_LOCAL_ROWS}" | grep -c . || true)"
LOCAL_RED_COUNT="$(printf '%s' "${ALL_LOCAL_ROWS}" | grep -c '❌' || true)"
LOCAL_RED_NAMES="$(printf '%s' "${ALL_LOCAL_ROWS}" | grep '❌' | awk -F'|' '{print $4}' | tr -d ' `' | tr '\n' ' ')"
LOCAL_TOTAL=$((LOCAL_TOTAL + DB_LOCAL_TOTAL))
LOCAL_RED_COUNT=$((LOCAL_RED_COUNT + DB_LOCAL_RED))
if [ "${DB_LOCAL_RED}" -gt 0 ]; then
  LOCAL_RED_NAMES="${LOCAL_RED_NAMES}数据库模块(本机段红 ${DB_LOCAL_RED}) "
fi

# 「完整判定」才敢说三模块全绿：过滤掉任一模块（含跳过数据库）都只是**部分**判定，如实写出来。
COMPLETE=1
INCOMPLETE_WHY=""
if [ -n "${SKIP_DB}" ]; then COMPLETE=0; INCOMPLETE_WHY="按 DOYAH_ALPHA_V2_SKIP_DB 跳过了数据库模块"; fi
if [ -n "${MODULE_FILTER}" ]; then
  COMPLETE=0
  if [ -n "${INCOMPLETE_WHY}" ]; then INCOMPLETE_WHY="${INCOMPLETE_WHY}；且按 DOYAH_ALPHA_V2_MODULE 只跑了「${MODULE_FILTER}」模块"; else INCOMPLETE_WHY="按 DOYAH_ALPHA_V2_MODULE 只跑了「${MODULE_FILTER}」模块"; fi
fi
if [ -n "${ONLY}" ]; then COMPLETE=0; INCOMPLETE_WHY="${INCOMPLETE_WHY}；且按 DOYAH_ALPHA_V2_ONLY 只跑了名字含「${ONLY}」的段"; fi
[ -z "${INCOMPLETE_WHY}" ] && INCOMPLETE_WHY="不完整"

# ---------------------------------------------------------------- 证据落盘
{
  printf '# Doyah Studio · 三模块 alpha 主链证据（`v0.2.0-alpha` 判据）\n\n'
  printf -- '- 生成时间：%s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
  printf -- '- 主机：%s（macOS %s）\n' "$(uname -m)" "$(sw_vers -productVersion)"
  printf -- '- 入口：`./Scripts/alpha-main-chain-v0.2.sh`（三模块合一；数据库模块委托 `Scripts/alpha-main-chain.sh`）\n'
  printf -- '- 判据：**三个模块的本机段都红 0 ⇒ alpha 功能面达成**；预期红与环境段只登记（口径见脚本头部注释）\n'
  printf -- '- 三档口径与 v1 逐字一致；`gate` 段只判退出码、`assert` 段要求「退出码 0 且断言 > 0」\n\n'
  printf '## A 工作区模块（编辑器 / 多页签 / 结果集 / 导出 / 终端）\n\n| 模块 | 档 | 脚本 | 结果 | 判定要点 |\n| --- | --- | --- | --- | --- |%s%s\n\n' \
    "${WS_ROWS}" "${WS_REF_ROWS}"
  printf '## B 数据库模块（委托 `Scripts/alpha-main-chain.sh`）\n\n'
  printf -- '- 子证据：`%s`\n' "${DB_OUT}/主链证据.md"
  printf -- '- 三档计数：%s\n' "${DB_COUNTS}"
  printf -- '- 结论：**%s**\n\n' "${DB_VERDICT}"
  printf '| 模块 | 档 | 脚本 | 结果 | 判定要点 |\n| --- | --- | --- | --- | --- |%s\n\n' "${DB_ROWS}"
  printf '## C 笔记模块（装配 + 本地库 + 检索；Linux 端不在本机范围）\n\n| 模块 | 档 | 脚本 | 结果 | 判定要点 |\n| --- | --- | --- | --- | --- |%s\n\n' "${NOTE_ROWS}"
  printf '## 结论\n\n'
  if [ "${LOCAL_RED_COUNT}" -eq 0 ] && [ "${COMPLETE}" -eq 1 ]; then
    printf '**本机段共 %s 段 / 红 0 ⇒ 三模块 alpha 功能面达成**（预期红与环境段逐条登记，见上）。\n' "${LOCAL_TOTAL}"
  elif [ "${LOCAL_RED_COUNT}" -eq 0 ]; then
    printf '**本轮不是完整判定**（%s）：本机段共 %s 段 / 红 0 —— 只能说**跑过的模块**全绿；\n' "${INCOMPLETE_WHY}" "${LOCAL_TOTAL}"
    printf '三模块合判必须跑完整入口（不带 `DOYAH_ALPHA_V2_MODULE` / `DOYAH_ALPHA_V2_SKIP_DB`）。\n'
  else
    printf '**本机段红 %s 段 ⇒ alpha 未达**：%s（见对应日志与上表）。\n' "${LOCAL_RED_COUNT}" "${LOCAL_RED_NAMES}"
  fi
} >"${SUMMARY}"

printf '\n证据文件：%s\n本机段段数：%s · 红：%s\n' "${SUMMARY}" "${LOCAL_TOTAL}" "${LOCAL_RED_COUNT}"
[ "${LOCAL_RED_COUNT}" -eq 0 ]
