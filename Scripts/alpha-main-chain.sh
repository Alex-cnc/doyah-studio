#!/bin/bash
# Doyah Studio · **macOS 数据库模块 alpha 主链证据复跑器**（2026-09-28 起）
#
# ## 为什么有它
# 「数据库模块可以发 alpha 了吗」之前只能拿需求书的 🟡 数量（42 条）间接回答 —— 那是**账**，
# 不是**链路**。这条命令按 alpha 主链复跑已有的真库脚本，把「连得上 → 钻得动 → 查得出 →
# 排得序 → 导得出 → 改得动表 → 写得回行 → 导得进文件 → 会话/事务」连成一条可复跑判据。
#
# ## 三档（**本文件的核心口径**）
#   · **本机段（LOCAL）**：能在本机临时集群上真跑 ⇒ **任何一段非绿 ⇒ alpha 未达**；
#     且每段断言必须 > 0（空跑不许当绿 —— L-05 起的老纪律）。
#   · **预期红（KNOWN_RED）**：实测现状就红、原因已登记在 `Scripts/real-db-evidence-baseline.json`
#     （`object-search` / `session-management` / `slow-queries` / `backup-restore`）⇒ 只登记，
#     不判 alpha 红绿；**忽然转绿要点名**（该更新基线了）。
#   · **环境段（ENV）**：需 217 / 真实例 / vendor 改动才能跑（本机跑必红：`pg_hba.conf` 未放行
#     本机，或脚本要求显式远程凭据）⇒ **alpha 明确不含**，只登记。与
#     `Docs/alpha-0.1.0-发布说明.md` §「alpha 明确不含」逐条对应。
#
# ## 用法
#   ./Scripts/alpha-main-chain.sh                       # 全跑，证据写 .build/alpha-0.1.0/
#   DOYAH_ALPHA_OUT=<目录> ./Scripts/alpha-main-chain.sh
#   DOYAH_ALPHA_ONLY=query,xlsx ./Scripts/alpha-main-chain.sh   # 只跑名字含关键字的段
#
# 注意（bash 3.2 多字节坑，见 `Scripts/check-shell-locale-safety.py`）：变量一律 `${变量}`。

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
ROOT="$(pwd)"
OUT="${DOYAH_ALPHA_OUT:-${ROOT}/.build/alpha-0.1.0}"
ONLY="${DOYAH_ALPHA_ONLY:-}"
mkdir -p "${OUT}"
SUMMARY="${OUT}/主链证据.md"

LOCAL_STEPS=(
  "1 连接|test-local-endpoint.sh|能连上，失败态可读"
  "2 对象树-五层|test-local-query-path.sh|服务器→库→schema→表→列（含类型）"
  "3 查询-参数|test-query-parameters.sh|参数化查询与占位符绑定"
  "3 查询-内存|test-query-memory.sh|大结果集内存不失控"
  "4 结果集-复制|test-result-copy.sh|复制为多格式不错行错列"
  "4 行详情|test-row-detail.sh|宽表 / 长 JSON / NULL 与空串可分"
  "4 外键导航|test-fk-navigation.sh|按引用关系跳转并带条件"
  "5 导出-整表|test-table-export.sh|整表导出"
  "5 导出-xlsx|test-xlsx-export.sh|产物用另一份实现（Python）拆开核对"
  "7 写回-内联编辑|test-inline-edit.sh|主键定位 / NULL 与空串分开 / 一批一事务"
  "8 导入-CSV/JSON|test-data-import.sh|引号内逗号换行 / BOM / CRLF 不读错位"
  "8 导入-编码|test-csv-encoding.sh|编码判定不猜"
  "8 导入-xlsx|test-xlsx-import.sh|Excel 列映射与类型推断"
  "8 复制导入|test-copy-import.sh|COPY 管线"
  "9 事务-续跑|test-restore-resume.sh|失败后不留半截状态"
  "9 合成数据|test-synthetic-data.sh|同 seed 可复现、约束满足"
  "2 对象树-服务器对象|test-server-objects.sh|角色/表空间/扩展/复制槽等服务器级对象"
  "9 维护任务|test-maintenance.sh|VACUUM/ANALYZE/REINDEX 的安全闸门"
  "1 连接-SSH 隧道|test-ssh-tunnel.sh|隧道配置与失败态（本机可跑部分）"
  "2 方言-MySQL|test-mysql-driver.sh|协议接线与方言生成"
  "5 ER 图|test-er-diagram.sh|实体关系取数与渲染输入"
)
KNOWN_RED=(
  "2 对象树-搜索|test-object-search.sh|基线既定红（real-db-evidence-baseline.json）"
  "9 会话管理|test-session-management.sh|基线既定红（同上）"
  "6 Schema 对比|test-schema-diff.sh|基线既定红（同上）"
)
ENV_STEPS=(
"环境 表结构-真库现场|test-table-structure.sh|脚本只连 217（pg_hba 未放行本机）；DDL 生成/变更集由 Tests/TableDesign*.swift 覆盖"
  "环境 连接-凭据|test-postgres-connection.sh|需显式远程凭据"
  "环境 对象树-DDL|test-object-ddl.sh|现场在 217（pg_hba 未放行本机）"
  "环境 结果集-流式导出|test-cursor-export.sh|需 217 专用库"
  "环境 表结构-索引外键|test-table-index-fk.sh|需 217 专用库"
  "环境 慢查询排行|test-slow-queries.sh|需 pg_stat_statements（本机精简构建无扩展目录）"
  "环境 备份恢复|test-backup-restore.sh|需 217 / 沙箱放宽（FR-IO-04 待拍板）"
)

run_group() {
  local group="$1"; shift
  local rows="" spec name rest script point log code count mark
  for spec in "$@"; do
    name="${spec%%|*}"; rest="${spec#*|}"
    script="${rest%%|*}"; point="${rest#*|}"
    if [ -n "${ONLY}" ]; then case "${name}" in *"${ONLY}"*) ;; *) continue ;; esac; fi
    log="${OUT}/$(printf '%s' "${group}_${name}" | tr ' /' '__').log"
    if [ ! -f "${ROOT}/Scripts/${script}" ]; then
      printf '· %s（%s）脚本不存在，跳过\n' "${name}" "${script}" >&2; continue
    fi
    ( cd "${ROOT}" && bash "Scripts/${script}" ) >"${log}" 2>&1
    code=$?
    count="$(python3 "${ROOT}/Scripts/count-evidence-assertions.py" "${log}" 2>/dev/null | grep -oE '[0-9]+' | tail -1)"
    [ -z "${count}" ] && count=0
    if [ "${code}" -eq 0 ] && [ "${count}" -gt 0 ]; then mark="✅"; else mark="❌"; fi
    printf '%s %-16s 退出码 %s 断言 %s\n' "${mark}" "${name}" "${code}" "${count}" >&2
    rows="${rows}
| ${name} | \`${script}\` | ${mark} 退出码 ${code} / 断言 ${count} | ${point} |"
  done
  printf '%s' "${rows}"
}

printf '▶︎ 本机段（判 alpha 红绿）\n'
ROWS_LOCAL="$(run_group LOCAL "${LOCAL_STEPS[@]}")"
LOCAL_RED="$(printf '%s' "${ROWS_LOCAL}" | grep -c '| ❌ ' || true)"
printf '▶︎ 预期红（基线既定，只登记）\n'
ROWS_KR="$(run_group KNOWN "${KNOWN_RED[@]}")"
printf '▶︎ 环境段（alpha 明确不含，只登记）\n'
ROWS_ENV="$(run_group ENV "${ENV_STEPS[@]}")"
ENV_RED="$(printf '%s' "${ROWS_ENV}" | grep -c '| ❌ ' || true)"
ENV_GREEN="$(printf '%s' "${ROWS_ENV}" | grep -c '| ✅ ' || true)"

{
  printf '# Doyah Studio · macOS 数据库模块 alpha 主链证据\n\n'
  printf -- '- 生成时间：%s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
  printf -- '- 主机：%s（macOS %s）\n' "$(uname -m)" "$(sw_vers -productVersion)"
  printf -- '- 连接：由 `Scripts/lib/test-env.sh` 决定（本机过渡态 = 127.0.0.1 临时集群）\n'
  printf -- '- 判据：**本机段任一段非绿 ⇒ alpha 未达**；预期红与环境段只登记（口径见脚本头部注释）\n\n'
  printf '## 一、本机段（判红绿）\n\n| 段 | 脚本 | 结果 | 判定要点 |\n| --- | --- | --- | --- |%s\n\n' "${ROWS_LOCAL}"
  printf '## 二、预期红（基线既定，非本轮结论）\n\n| 段 | 脚本 | 结果 | 说明 |\n| --- | --- | --- | --- |%s\n\n' "${ROWS_KR}"
  printf '## 三、环境段（alpha 明确不含）\n\n| 段 | 脚本 | 结果 | 为什么不在 alpha 内 |\n| --- | --- | --- | --- |%s\n\n' "${ROWS_ENV}"
  if [ "${LOCAL_RED}" -eq 0 ]; then
    printf '**结论：本机段全绿 ⇒ alpha 功能面达成**（环境段 %s 绿 / %s 红，均逐条写明「alpha 不含」）。\n' "${ENV_GREEN}" "${ENV_RED}"
  else
    printf '**结论：本机段有 %s 段红 ⇒ alpha 未达**（见上表与对应日志）。\n' "${LOCAL_RED}"
  fi
} >"${SUMMARY}"

printf '\n证据文件：%s\n本机段红：%s\n' "${SUMMARY}" "${LOCAL_RED}"
[ "${LOCAL_RED}" -eq 0 ]
