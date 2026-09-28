#!/bin/bash
# 证据：命令行的失败输出**真的变成人话**了（开发循环 L-15）。
#
# 为什么要有它：L-15 把 CLI 里 57 处「打给用户看的失败行」统一接到可读化入口
# （`CLI/CLIFailureText.swift`）。改的是**输出**，而输出最容易「改了但没人看得见」——
# 单测跑不到 CLI 的 `print`，文档也证不了「真的打出来了人话」。所以这里跑**真实现场**：
#
#   §1 连接类：诊断路径连不上的端口     → 人话 + 建议 + 错误码 + 原始串
#   §2 机器可读出口（`--json`）          → **原样**保留原串（口径里的显式例外）
#   §3 真 57014：用户表持锁 + 库级 1ms 超时 → 中性归因打到命令行上（可读化链的第二档）
#   §4 连接降级那条路（`mcp serve`）     → 也是人话
#   §5 认不出就原样（本地错误）          → 与改动前**逐字一致**，不套方向结论
#   §6 源码交叉核对：没有裸的英文失败输出（与门禁同一条判据，这里独立算一遍）
#   §7 真 42P01：查一张不存在的表          → **服务端原话**端出来（队列 L-20 ③；以前只剩英文调试串）
#
# **如实登记（没有稳定现场的两条）**：`对象树加载失败`（外层 catch）与 `建库权限探测失败`
# 两条路径**造不出稳定的真现场** —— 它们的查询是单条 syscache 快查询（1ms 超时不可靠地命中），
# 而锁基础目录（pg_database / pg_roles / pg_authid）会先让**建连**失败（实测：10 秒连接超时，
# 走的是连接那条 catch）。它们由闭环第 15 项门禁的**机械对账**覆盖（该处必须经同一个入口，
# 改回去当场报红），实证用同形状的 §1 / §3 两条真现场代表。不造假现场。
#
# 注意（bash 3.2 的多字节坑，见 `Scripts/check-shell-locale-safety.py`）：本文件里变量一律写
# `${变量}` —— 裸写 `$变量` 后面紧跟 CJK 字符会被静默展开成空。
set -uo pipefail

cd "$(dirname "$0")/.."
CLI=".build/debug/DoyahCLI"
source "$(cd "$(dirname "$0")" && pwd)/lib/test-env.sh"
doyah_test_env_summary

PSQL="${DOYAH_TEST_PG_BIN}/psql"
SCRATCH="$(doyah_test_env_scratch_name cli_readability)"
BAD_PORT=59998   # 没人监听：连接类失败的现场
LOCK_PID=""

fail=0
check() { if [ "$2" -eq 0 ]; then echo "  ✅ $1"; else echo "  ❌ $1"; fail=1; fi; }
cleanup() {
    if [ -n "${LOCK_PID}" ]; then kill "${LOCK_PID}" >/dev/null 2>&1; fi
    if [ "${DOYAH_TEST_MODE}" = "local" ]; then
        # 把库级 1ms 超时撤掉（临时库下次会被整个删掉重建，这里只为不给后手留坑）
        "${PSQL}" -h "${DOYAH_TEST_PGHOST}" -p "${DOYAH_TEST_PGPORT}" -U "${DOYAH_TEST_PGUSER}" \
            -d "${DOYAH_TEST_ADMIN_DB}" -c "ALTER DATABASE \"${SCRATCH}\" RESET statement_timeout;" \
            >/dev/null 2>&1
    fi
    doyah_test_env_stop_cluster
}
trap cleanup EXIT

echo ""
echo "== 0) 前置：起真库 + 建一个临时库，并在它上面放一张会被锁住的表"
doyah_test_env_start_cluster
if [ ! -x "${CLI}" ]; then
    echo "❌ 找不到 ${CLI}（先 swift build）"
    exit 78
fi
doyah_test_env_export_connection
"${CLI}" -c "DROP DATABASE IF EXISTS \"${SCRATCH}\" WITH (FORCE);" >/dev/null 2>&1
"${CLI}" -c "CREATE DATABASE \"${SCRATCH}\";" >/dev/null 2>&1
# 表用 psql 建（同一会话里先把自己那条库级超时关掉；本库稍后要设 1ms）
"${PSQL}" -h "${DOYAH_TEST_PGHOST}" -p "${DOYAH_TEST_PGPORT}" -U "${DOYAH_TEST_PGUSER}" -d "${SCRATCH}" -q \
    -c "SET statement_timeout = 0; CREATE TABLE doyah_probe_rowlock (id integer, note text); INSERT INTO doyah_probe_rowlock VALUES (1, 'x');" \
    >/dev/null 2>&1
"${PSQL}" -h "${DOYAH_TEST_PGHOST}" -p "${DOYAH_TEST_PGPORT}" -U "${DOYAH_TEST_PGUSER}" -d "${DOYAH_TEST_ADMIN_DB}" -q \
    -c "ALTER DATABASE \"${SCRATCH}\" SET statement_timeout = 1;" >/dev/null 2>&1

echo ""
echo "== 1) 连接类：诊断路径连不上的端口（以前这里只有一句英文调试串）"
OUT1="$(PGHOST=127.0.0.1 PGPORT="${BAD_PORT}" PGUSER=x PGDATABASE=x PGSSLMODE=disable \
    "${CLI}" diagnose --sql "SELECT 1" 2>&1)"
echo "${OUT1}" | grep -q "取证失败：" \
    && check "失败行还在（标签没丢）" 0 || { echo "${OUT1}" | head -5; check "失败行还在" 1; }
echo "${OUT1}" | grep -q "建议：" \
    && check "给了方向（建议）" 0 || check "给了方向（建议）" 1
echo "${OUT1}" | grep -q "错误码：connectionError" \
    && check "带上了错误码（可搜、可上报）" 0 || check "带上了错误码（可搜、可上报）" 1
echo "${OUT1}" | grep -q "（原始信息：" \
    && check "认得出来时原始串也保留（口径第 3 条）" 0 || check "原始串也保留" 1
echo "${OUT1}" | grep -q "取证失败：The operation" \
    && check "不再只剩一句英文调试串（反向断言）" 1 || check "不再只剩一句英文调试串（反向断言）" 0

echo ""
echo "== 2) 机器可读出口（--json）：原样保留原串（口径里的显式例外）"
OUT2="$(PGHOST=127.0.0.1 PGPORT="${BAD_PORT}" PGUSER=x PGDATABASE=x PGSSLMODE=disable \
    "${CLI}" diagnose --sql "SELECT 1" --json 2>&1 | tail -1)"
echo "${OUT2}" | grep -q '"ok":false' \
    && check "JSON 里如实标了失败" 0 || { echo "${OUT2}"; check "JSON 里如实标了失败" 1; }
echo "${OUT2}" | grep -q '"error":"The operation' \
    && check "脚本要消费的原串原样还在（没被套上人话）" 0 || check "原串原样还在" 1
echo "${OUT2}" | grep -q "建议：" \
    && check "JSON 出口不掺人话（反向断言）" 1 || check "JSON 出口不掺人话（反向断言）" 0

echo ""
echo "== 3) 真 57014 现场：用户表被锁 + 库级 1ms 超时（中性归因那一档）"
"${PSQL}" -h "${DOYAH_TEST_PGHOST}" -p "${DOYAH_TEST_PGPORT}" -U "${DOYAH_TEST_PGUSER}" -d "${SCRATCH}" -q \
    -c "SET statement_timeout = 0; BEGIN; LOCK TABLE doyah_probe_rowlock IN ACCESS EXCLUSIVE MODE; SELECT pg_sleep(25);" \
    >/dev/null 2>&1 &
LOCK_PID=$!
sleep 1
OUT3="$(PGHOST=127.0.0.1 PGPORT="${DOYAH_TEST_PGPORT}" PGUSER="${DOYAH_TEST_PGUSER}" \
    PGDATABASE="${SCRATCH}" PGSSLMODE=disable "${CLI}" row --table doyah_probe_rowlock 2>&1)"
kill "${LOCK_PID}" >/dev/null 2>&1
wait "${LOCK_PID}" 2>/dev/null
LOCK_PID=""
echo "${OUT3}" | grep -q "读取行失败：" \
    && check "失败行还在（标签没丢）" 0 || { echo "${OUT3}" | head -5; check "失败行还在" 1; }
echo "${OUT3}" | grep -q "服务端把这次查询取消了" \
    && check "中性归因真的打到了命令行上（说得是取消，不是连接）" 0 || check "中性归因打到命令行上" 1
echo "${OUT3}" | grep -q "SQLSTATE 57014" \
    && check "把 57014 带出来（可搜、可查文档）" 0 || check "把 57014 带出来" 1
echo "${OUT3}" | grep -q "读取行失败：The operation" \
    && check "不再只剩一句英文调试串（反向断言）" 1 || check "不再只剩一句英文调试串（反向断言）" 0
echo "${OUT3}" | grep -qE "连接数据库失败|确认主机 / 端口 / 库名 / 用户名" \
    && check "不说成「连接失败」那套方向（反向断言）" 1 || check "不说成「连接失败」那套方向（反向断言）" 0

echo ""
echo "== 4) 连接降级那条路（mcp serve：连不上就只说能力降级，也要是人话）"
OUT4="$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}' \
    | PGHOST=127.0.0.1 PGPORT="${BAD_PORT}" PGUSER=x PGDATABASE=x PGSSLMODE=disable "${CLI}" mcp serve 2>&1 >/dev/null)"
echo "${OUT4}" | grep -q "（连接失败，能力降级为仅元数据）：" \
    && check "降级那行还在（标签没丢）" 0 || { echo "${OUT4}" | head -3; check "降级那行还在" 1; }
echo "${OUT4}" | grep -q "建议：" \
    && check "给了方向（建议）" 0 || check "给了方向（建议）" 1
echo "${OUT4}" | grep -q "（连接失败，能力降级为仅元数据）：The operation" \
    && check "不再只剩一句英文调试串（反向断言）" 1 || check "不再只剩一句英文调试串（反向断言）" 0

echo ""
echo "== 5) 认不出就原样：本地错误（文件 / 编解码）与改动前逐字一致，不套方向结论"
MISSING_CSV="/tmp/doyah-cli-readability-nope-$$.csv"
OUT5="$(PGHOST=127.0.0.1 PGPORT="${DOYAH_TEST_PGPORT}" PGUSER="${DOYAH_TEST_PGUSER}" \
    PGDATABASE="${SCRATCH}" PGSSLMODE=disable "${CLI}" import --table doyah_probe_none --file "${MISSING_CSV}" 2>&1)"
echo "${OUT5}" | grep -q "读取文件失败：The file" \
    && check "本地错误照实说（原样 English 文案，逐字不变）" 0 || { echo "${OUT5}" | tail -3; check "本地错误照实说" 1; }
echo "${OUT5}" | grep -qE "读取文件失败：.*(建议：|错误码：)" \
    && check "不给方向结论（认不出就不猜，反向断言）" 1 || check "不给方向结论（认不出就不猜，反向断言）" 0
BAD_JSON="/tmp/doyah-cli-readability-bad-$$.json"
printf 'not json at all' > "${BAD_JSON}"
OUT6="$(PGHOST=127.0.0.1 PGPORT="${DOYAH_TEST_PGPORT}" PGUSER="${DOYAH_TEST_PGUSER}" \
    PGDATABASE="${SCRATCH}" PGSSLMODE=disable "${CLI}" import --table doyah_probe_none --file "${BAD_JSON}" --format json 2>&1)"
echo "${OUT6}" | grep -q "解析失败：The data" \
    && check "解析失败照实说（原样 English 文案，逐字不变）" 0 || check "解析失败照实说" 1
rm -f "${BAD_JSON}"

echo ""
echo "== 6) 交叉核对：源码里没有裸的英文失败输出（与门禁同一条判据，这里独立算一遍）"
BARE_FILE="$PWD/.build/cli-failure-bare-lines.txt"
grep -n "error\.localizedDescription" CLI/main.swift \
    | grep -E "print\(|FileHandle.standardError.write\(" \
    | grep -v "CLIFailureText.oneLine" \
    | grep -v '"ok":false' \
    | grep -v "jsonQuoted" > "${BARE_FILE}"
BARE_COUNT="$(wc -l < "${BARE_FILE}" | tr -d ' ')"
[ "${BARE_COUNT}" = "0" ] \
    && check "打给用户看的失败行都经同一个入口（裸英文 ${BARE_COUNT} 处）" 0 \
    || { echo "    裸的：$(head -3 "${BARE_FILE}")"; check "打给用户看的失败行都经同一个入口" 1; }
ENTRY_CALLS="$(grep -cE "CLIFailureText\.(oneLine|block)\(" CLI/main.swift | tr -d ' ')"
[ "${ENTRY_CALLS}" -ge 57 ] \
    && check "入口真的在接线（${ENTRY_CALLS} 处 ≥ 57，反向棘轮）" 0 \
    || check "入口真的在接线（只剩 ${ENTRY_CALLS} 处）" 1
grep -q "ConnectionFailure.describeNonConnection" CLI/CLIFailureText.swift \
    && check "入口里中性归因那一档在位" 0 || check "入口里中性归因那一档在位" 1
grep -q "CLIFailureText\.\(describeNonConnection\|describeServerSide\)(" CLI/main.swift \
    && { check "可读化链只写一份（主路里没再抄一份 if/else 链）" 1; grep -n "describeNonConnection\|describeServerSide" CLI/main.swift; } \
    || check "可读化链只写一份（主路里没再抄一份 if/else 链）" 0

echo ""
echo "== 7) 查询类错误（真 42P01）：服务端说过的原话不许被丢掉（队列 L-20 ③）"
# 为什么要有这一节：`describe`（连接类）与 `describeNonConnection`（驱动非连接类）**都有意不接**
# 查询类错误（那是调用方自己的路 —— 把「表不存在」说成「连不上」会把排查带偏），于是以前这一路
# 只剩 `简要信息：The operation couldn't be completed. (PostgresNIO.PSQLError error 1.)`，
# 而服务端明明说清了 `relation "…" does not exist`。第 47 轮把**服务端原话**接成链的第三档。
MISSING_TABLE="doyah_probe_missing_$$"
OUT7="$(PGHOST=127.0.0.1 PGPORT="${DOYAH_TEST_PGPORT}" PGUSER="${DOYAH_TEST_PGUSER}" \
    PGDATABASE="${SCRATCH}" PGSSLMODE=disable "${CLI}" -c "SELECT * FROM ${MISSING_TABLE}" 2>&1)"
echo "${OUT7}" | grep -q "查询失败" \
    && check "失败行还在（标签没丢）" 0 || { echo "${OUT7}" | head -5; check "失败行还在" 1; }
echo "${OUT7}" | grep -q "^服务端说：" \
    && check "服务端原话打头（不是反射转储打头）" 0 || { echo "${OUT7}" | head -5; check "服务端原话打头" 1; }
echo "${OUT7}" | grep -q "SQLSTATE 42P01" \
    && check "带上了 SQLSTATE（可搜、可查文档）" 0 || check "带上了 SQLSTATE" 1
echo "${OUT7}" | grep -q "${MISSING_TABLE}" \
    && check "原话里带着对象名（照抄就能核对）" 0 || check "原话里带着对象名" 1
# 服务端消息按**服务端自己的语言**来（本机集群是英文 does not exist，中文集群是「不存在」）——
# 绑死一种措辞等于把这条断言挂到集群的 lc_messages 上。
echo "${OUT7}" | grep -qE "does not exist|不存在" \
    && check "服务端原话真的端出来了（按服务端的语言）" 0 || check "服务端原话真的端出来了（按服务端的语言）" 1
echo "${OUT7}" | grep -q "调试详情" && echo "${OUT7}" | grep -q "PSQLError" \
    && check "原始串仍然保留（信息不丢）" 0 || check "原始串仍然保留（信息不丢）" 1
echo "${OUT7}" | grep -q "建议：" \
    && check "不给方向结论（这一档只端原话，反向断言）" 1 || check "不给方向结论（这一档只端原话，反向断言）" 0
echo "${OUT7}" | grep -qE "连接数据库失败|确认主机 / 端口 / 库名 / 用户名" \
    && check "不套「连接失败」那套方向（反向断言）" 1 || check "不套「连接失败」那套方向（反向断言）" 0
echo "${OUT7}" | grep -q "简要信息：The operation" \
    && check "不再只剩一句英文调试串（反向断言）" 1 || check "不再只剩一句英文调试串（反向断言）" 0

echo ""
echo "== 8) 渠道字段两半：维护任务失败时，机器载荷保原串、人话打给人看（队列 L-66 口径 ①）"
# 为什么要有这一节：这条口径的**两半**落在两个地方 —— JSON 的 `failureReason` / `detail`
# （原串，一字不变、可搜可上报）与命令行那行 `❌ … 失败：…`（人话）。Core 单测跑不到 CLI 的
# JSON 拼装与 `print`，所以现场要真跑一遍：造一条**注定失败**的维护任务（查一张不存在的表
# ⇒ 服务端 42P01），分别用 `--json` 与不带 `--json` 跑。
# 注意：这里连的是**默认测试库**（不是本脚本 §0 那个设了 1ms statement_timeout 的库）——
# 那一档是给 §3 造 57014 用的，会把这一节的失败原因抢成「查询被取消」。
MAINTAIN_PLAN="$(mktemp -t doyah-maintain-plan)"
MISSING_MAINTAIN="doyah_probe_maint_missing_$$"
{
    echo "task: custom | 查一张不存在的表（故意失败） | sql: SELECT * FROM ${MISSING_MAINTAIN}"
} > "${MAINTAIN_PLAN}"
MAINTAIN_ENV="PGHOST=127.0.0.1 PGPORT=${DOYAH_TEST_PGPORT} PGUSER=${DOYAH_TEST_PGUSER} PGDATABASE=${DOYAH_TEST_PGDATABASE} PGSSLMODE=disable"
OUT8="$(env ${MAINTAIN_ENV} "${CLI}" maintain --plan "${MAINTAIN_PLAN}" --approve all --execute 2>&1)"
OUT8J="$(env ${MAINTAIN_ENV} "${CLI}" maintain --plan "${MAINTAIN_PLAN}" --approve all --execute --json 2>&1)"
rm -f "${MAINTAIN_PLAN}"
# 人话打头（从前这一行印的是 `The operation couldn't be completed…`）
echo "${OUT8}" | grep -q "❌ m1 失败：服务端说：" \
    && check "命令行那行**以人话打头**（服务端原话）" 0 \
    || { echo "${OUT8}" | grep "失败" | head -3; check "命令行那行以人话打头" 1; }
# 反向：**不再是**「原串当失败说明」那个形状（这正是本条要修的那件事）
echo "${OUT8}" | grep -q "❌ m1 失败：The operation" \
    && check "命令行那行不再以原串当失败说明（反向断言）" 1 \
    || check "命令行那行不再以原串当失败说明（反向断言）" 0
# 口径第 4 条（L-15）不变：认得出来时原串作为**可追溯的尾巴**保留
echo "${OUT8}" | grep -q "（原始信息：" \
    && check "原串作为可追溯的尾巴保留（口径第 4 条）" 0 || check "原串作为可追溯的尾巴保留" 1
echo "${OUT8}" | grep -q "计划（1 条）" \
    && check "同一份计划里失败态那一格也是人话（不走另一条路）" 0 || check "计划里失败态那一格" 1
# JSON 两半成对：原串一字不变 + 新增人话字段（界面 / MCP 客户端可选展示）
echo "${OUT8J}" | grep -q '"failureReason":"The operation' \
    && check "JSON 的 failureReason 是**一字不变的原串**" 0 \
    || { echo "${OUT8J}" | head -c 400; check "JSON 的 failureReason 是原串" 1; }
echo "${OUT8J}" | grep -q '"failureReasonHuman":"服务端说：' \
    && check "JSON 新增人话字段 failureReasonHuman" 0 || check "JSON 新增人话字段 failureReasonHuman" 1
echo "${OUT8J}" | grep -q '"detail":"The operation' \
    && check "JSON 的 detail 仍是原串（没被换成中文）" 0 || check "JSON 的 detail 仍是原串" 1
echo "${OUT8J}" | grep -q '"detailHuman":"服务端说：' \
    && check "JSON 的 detailHuman 是人话（新增字段）" 0 || check "JSON 的 detailHuman 是人话" 1
echo "${OUT8J}" | grep -q "${MISSING_MAINTAIN}" \
    && check "两侧都带着对象名（可核对，不是泛泛一句）" 0 || check "两侧都带着对象名" 1
echo "${OUT8J}" | grep -q "SQLSTATE 42P01" \
    && check "人话里带着 SQLSTATE（可搜的锚点还在）" 0 || check "人话里带着 SQLSTATE" 1

echo ""
if [ "${fail}" -eq 0 ]; then
    echo "全部通过：认得出就给方向（人话 + 建议 + 错误码）、认得出来时原始串仍保留、"
    echo "认不出就原样（本地错误逐字不变）；机器可读出口按口径保留原串。"
else
    echo "有失败项，见上"
fi
exit "${fail}"
