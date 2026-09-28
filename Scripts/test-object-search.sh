#!/bin/bash
# 验证：全库对象搜索（FR-META-12）。
#
# 验五件事：① 跨 schema 的表 / 视图 / 列 / 函数**一次查询**都能搜到；
# ② 列的命中形态是 `表.列`（搜列名能命中）；③ 排序合理（前缀优先）；④ 元数据上限会如实提示；
# ⑤ 对象多的库上单次查询照样取回整库（`--limit` 只在客户端截断）。
#
# **全部在本机档造现场**（2026-09-28 循环 L-63 转正）：原先 §6 是「只读核对 217（18.6）上的既有对象」，
# 而 217 的 `pg_hba` 未放行本机 ⇒ 这一段一直停在既定红、从没在这条证据链上跑过。
# 转正后**不再对 18.6 做只读核对**（跨版本 / 真机覆盖见队列 L-09），换来的是本机可复跑。
set -uo pipefail

cd "$(dirname "$0")/.."
CLI=".build/debug/DoyahCLI"
# 连接信息（本机过渡集群 / 远程专用库）由共用入口决定 —— 三档端口与目录只写在它里面
source "$(cd "$(dirname "$0")" && pwd)/lib/test-env.sh"
doyah_test_env_summary

PGBIN="${DOYAH_TEST_PG_BIN}"
DATADIR="${DOYAH_TEST_LOCAL_DATADIR}"
PORT="${DOYAH_TEST_PGPORT}"
DB="doyah_search_check"
STARTED=0

fail=0
check() { if [ "$2" -eq 0 ]; then echo "  ✅ $1"; else echo "  ❌ $1"; fail=1; fi; }
cleanup() { [ "$STARTED" = "1" ] && "$PGBIN/pg_ctl" -D "$DATADIR" stop >/dev/null 2>&1; }
trap cleanup EXIT

echo "== 0) 起本机实例，造跨 schema 的对象 =="
if [ ! -f "${DATADIR}/PG_VERSION" ]; then
    mkdir -p "$DATADIR"
    "$PGBIN/initdb" -D "$DATADIR" -U postgres --auth=trust -E UTF8 >/dev/null 2>&1
fi
if ! "$PGBIN/pg_ctl" -D "$DATADIR" status >/dev/null 2>&1; then
    "$PGBIN/pg_ctl" -D "$DATADIR" -o "-p ${PORT} -k /tmp" -l /tmp/doyah-search-pg.log start >/dev/null 2>&1
    STARTED=1
    sleep 2
fi
doyah_test_env_export_connection
PGDATABASE="${DOYAH_TEST_ADMIN_DB}" "$CLI" -c "DROP DATABASE IF EXISTS ${DB};" >/dev/null 2>&1
PGDATABASE="${DOYAH_TEST_ADMIN_DB}" "$CLI" -c "CREATE DATABASE ${DB};" >/dev/null 2>&1
export PGDATABASE="$DB"
"$CLI" -c "
CREATE SCHEMA reporting;
CREATE TABLE public.orders (id int primary key, email text, amount numeric(10,2));
CREATE TABLE public.order_items (id int primary key, sku text);
CREATE VIEW reporting.order_summary AS SELECT count(*) AS n FROM public.orders;
CREATE FUNCTION public.order_total(a int, b int) RETURNS int LANGUAGE sql AS \$\$ SELECT a + b \$\$;
CREATE TABLE sales.customer_email (id int, email text);" >/dev/null 2>&1
# sales schema 需要先建
"$CLI" -c "CREATE SCHEMA IF NOT EXISTS sales; CREATE TABLE IF NOT EXISTS sales.customer_email (id int, email text);" >/dev/null 2>&1
[ $? -eq 0 ] && echo "  ✅ 现场已建立（public.orders / order_items / money 视图 / 函数；sales.customer_email）" || { echo "  ❌ 造现场失败"; exit 1; }

echo ""
echo "== 1) 搜表名片段：跨 schema 都能命中 =="
OUT="$("$CLI" search-objects order 2>&1)"
echo "$OUT" | head -8 | sed 's/^/  /'
echo "$OUT" | grep -q "public.order_items" && check "命中 public.order_items" 0 || check "应命中 order_items" 1
echo "$OUT" | grep -q "reporting.order_summary" && check "命中另一个 schema 的视图（跨 schema）" 0 || check "跨 schema 命中" 1
echo "$OUT" | grep -q "public.order_total" && check "命中函数（含签名）" 0 || check "函数命中" 1

echo ""
echo "== 2) 搜列名片段：列的命中形态是 表.列 =="
COL="$("$CLI" search-objects email --kind column 2>&1)"
echo "$COL" | head -6 | sed 's/^/  /'
echo "$COL" | grep -q "orders.email" && check "命中 orders.email" 0 || check "应命中 orders.email" 1
echo "$COL" | grep -q "customer_email.email" && check "命中另一张表的同名列（跨表）" 0 || check "跨表列命中" 1

echo ""
echo "== 3) 排序：前缀优先于中间子串 =="
ORDER="$("$CLI" search-objects order 2>&1 | grep -E "^\s+(table|view|column|function)" | head -2)"
echo "$ORDER" | sed 's/^/  /'
echo "$ORDER" | head -1 | grep -qE "order_items|orders|order_summary" && check "前两位都是 order 开头的对象（前缀优先）" 0 || check "前缀优先" 1

echo ""
echo "== 4) 限定 schema 只搜那个 schema =="
SCOPED="$("$CLI" search-objects order --schema reporting 2>&1)"
echo "$SCOPED" | head -4 | sed 's/^/  /'
echo "$SCOPED" | grep -q "public.order_items" && check "限定 reporting 时不该出现 public 的对象" 1 || check "限定 schema 生效（没有 public 的对象）" 0

echo ""
echo "== 5) 搜不到时退出码非零（脚本可判定）=="
"$CLI" search-objects zzzz_nothing_zzzz >/dev/null 2>&1
NONE_CODE=$?
[ "$NONE_CODE" -ne 0 ] && check "无命中返回非零（${NONE_CODE}）" 0 || check "无命中应返回非零" 1

echo ""
echo "== 6) 对象多的库上，单次元数据查询照样跑得通（现场放大到 300 张表）=="
# **本段原先只读核对 217（18.6）** —— 217 的 `pg_hba` 未放行本机 ⇒ 一直停在既定红。
# 2026-09-28 循环 L-63 转正：改成在本机档造同形状的现场，把「对象数量」这一维**真的放大**
# （300 张表 + 600 列）—— 验的是「一次元数据查询取回整个库、不因对象多而失败、也不悄悄截断」。
BULK_SQL=""
for _i in $(seq -w 0 299); do
    BULK_SQL="${BULK_SQL}CREATE TABLE IF NOT EXISTS public.bulk_${_i} (id int, payload text);"
done
"$CLI" -c "${BULK_SQL}" >/dev/null 2>&1
BULK_N="$("$CLI" -c "SELECT count(*) AS n FROM information_schema.tables WHERE table_schema = 'public' AND table_name LIKE 'bulk\\_%';" 2>&1 | awk '/^[0-9]+$/{print $1}' | head -1)"
[ "${BULK_N:-0}" = "300" ] && check "现场放大到 300 张表（另加 600 列）" 0 \
    || { check "应造出 300 张表" 1; echo "  实得：${BULK_N:-空}"; }

BIG="$("$CLI" search-objects bulk_ 2>&1)"
TOTAL=$(printf '%s\n' "${BIG}" | sed -n 's/^在 \([0-9][0-9]*\) 个对象里搜.*/\1/p' | head -1)
# 900 = 300 张表 + 每张 2 列：**一次查询**要能把整库取回来（元数据上限是 10000 行，够不着）。
if [ "${TOTAL:-0}" -ge 900 ] 2>/dev/null; then
    check "单次元数据查询取回整个库（在 ${TOTAL} 个对象里搜，≥ 900）" 0
else
    check "单次查询应取回整个库（≥ 900 个对象）" 1
    echo "  实得：${TOTAL:-空}"
    printf '%s\n' "${BIG}" | head -3 | sed 's/^/  /'
fi
printf '%s\n' "${BIG}" | grep -q "元数据已达" && check "300 张表不该触发元数据上限提示" 1 \
    || check "没到元数据上限，未出现「已达上限」提示" 0

FIVE="$("$CLI" search-objects bulk_ --limit 5 2>&1)"
FIVE_N=$(printf '%s\n' "${FIVE}" | grep -c $'\t')
[ "${FIVE_N:-0}" = "5" ] && check "--limit 5 只列 5 条（截断在客户端）" 0 \
    || { check "--limit 5 应只列 5 条" 1; echo "  实得：${FIVE_N:-空} 条"; }
printf '%s\n' "${FIVE}" | grep -q "命中 5 条" && check "摘要如实报「命中 5 条」（不是 900）" 0 \
    || { check "摘要应报命中 5 条" 1; printf '%s\n' "${FIVE}" | head -1 | sed 's/^/  /'; }

echo ""
echo "== 7) 清理现场 =="
unset PGHOST PGPORT PGUSER PGPASSWORD PGSSLMODE
doyah_test_env_export_connection
PGDATABASE="${DOYAH_TEST_ADMIN_DB}" "$CLI" -c "DROP DATABASE IF EXISTS ${DB};" >/dev/null 2>&1
echo "  ✅ 已删除临时库 ${DB}"

echo ""
if [ "$fail" -eq 0 ]; then
    echo "通过：全库对象搜索一次查询跨 schema 命中表 / 视图 / 列 / 函数，排序与 schema 限定都正确"
else
    echo "有失败项，见上"
fi
exit "$fail"
