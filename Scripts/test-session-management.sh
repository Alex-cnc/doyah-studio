#!/bin/bash
# 验证：服务器会话读取与「取消当前语句」（FR-SESS-01 / FR-SESS-02）+ **非文本类型的值可读**（队列 L-74）。
#
# 为什么用**本机 16.2 实例**而不是 217：这个脚本会真的取消一条正在跑的语句 ——
# 在共享实例上做这件事是不礼貌的（可能中断别人），本机实例上做才是可复现的验收。
#
# **全部在本机档造现场**（2026-09-28 循环 L-63 转正）：原先 §6 是「217（18.6）只读核对」，
# 而 217 的 `pg_hba` 未放行本机 ⇒ 这一段一直停在既定红、从没在这条证据链上跑过。
# 转正后 §6 改成用**另一条不属于本进程的连接**当「别人的会话」（本机 16.2 上造），
# **不再对 18.6 做只读核对**（跨版本 / 真机覆盖见队列 L-09），换来的是本机可复跑。
#
# §7（2026-09-29 循环第 79 轮，L-74）：`client_addr` 那一格印的是控制字符，正是「非文本类型
# 被倒成原始字节」这条缺陷的现场 ⇒ 把那一批类型（inet / cidr / macaddr / bytea / interval /
# time / timetz / bit / point / box / lseg / line / circle / path / polygon / 数组 / range /
# multirange）**逐条与 psql 的文本形态比对**，并断言任何值里都不含控制字符。
set -uo pipefail

cd "$(dirname "$0")/.."
CLI=".build/debug/DoyahCLI"
# 连接信息（本机过渡集群 / 远程专用库）由共用入口决定 —— 三档端口与目录只写在它里面
source "$(cd "$(dirname "$0")" && pwd)/lib/test-env.sh"
doyah_test_env_summary

PGBIN="${DOYAH_TEST_PG_BIN}"
# 数据目录放在**工作区内**（默认档）：早先实测外部数据目录在当前沙箱下起不来
# （could not create lock file "postmaster.pid": Operation not permitted）。
DATADIR="${DOYAH_TEST_LOCAL_DATADIR}"
PORT="${DOYAH_TEST_PGPORT}"
STARTED=0

fail=0
check() { if [ "$2" -eq 0 ]; then echo "  ✅ $1"; else echo "  ❌ $1"; fail=1; fi; }

cleanup() {
    # 收尾：确保没有留下那条长跑语句
    PGPASSWORD="${DOYAH_TEST_PGPASSWORD}" "$PGBIN/psql" -h "${DOYAH_TEST_PGHOST}" -p "${DOYAH_TEST_PGPORT}" -U "${DOYAH_TEST_PGUSER}" -d "${DOYAH_TEST_ADMIN_DB}" -c \
        "SELECT pg_cancel_backend(pid) FROM pg_stat_activity WHERE query LIKE '%pg_sleep%' AND pid <> pg_backend_pid();" \
        >/dev/null 2>&1
    [ "$STARTED" = "1" ] && "$PGBIN/pg_ctl" -D "$DATADIR" stop >/dev/null 2>&1
}
trap cleanup EXIT

echo "== 1) 起本机 16.2 实例（取消语句的验证场地）=="
if [ ! -f "${DATADIR}/PG_VERSION" ]; then
    echo "  · 初始化临时集群 ${DATADIR}"
    mkdir -p "$DATADIR"
    "$PGBIN/initdb" -D "$DATADIR" -U postgres --auth=trust -E UTF8 >/dev/null 2>&1 || { echo "  ❌ initdb 失败"; exit 1; }
fi
if ! "$PGBIN/pg_ctl" -D "$DATADIR" status >/dev/null 2>&1; then
    "$PGBIN/pg_ctl" -D "$DATADIR" -o "-p $PORT -k /tmp" -l /tmp/doyah-session-pg.log start >/dev/null 2>&1
    STARTED=1
    sleep 2
fi
"$PGBIN/pg_ctl" -D "$DATADIR" status >/dev/null 2>&1 && echo "  ✅ 本机实例在跑（端口 ${PORT}）" || { echo "  ❌ 实例没起来"; exit 1; }

doyah_test_env_export_connection
export PGDATABASE="${DOYAH_TEST_ADMIN_DB}"

echo ""
echo "== 2) 会话查询（代码里那条 pg_stat_activity 查询）在真机上跑得通 =="
QUERY="SELECT pid, usename, datname, client_addr, application_name, state, wait_event_type, wait_event, backend_start, query_start, query
FROM pg_stat_activity
WHERE pid <> pg_backend_pid()
ORDER BY query_start"
OUT="$("$CLI" -c "$QUERY" 2>&1)"
echo "$OUT" | grep -q "pid:INT4\|pid:" && check "查询返回了会话列" 0 || { check "查询返回会话列" 1; echo "$OUT" | head -5; }

echo ""
echo "== 3) 造一条长跑语句，确认它出现在会话列表里 =="
# 后台跑一条 60 秒的 pg_sleep，然后从另一个连接里把它找出来。
PGPASSWORD="${DOYAH_TEST_PGPASSWORD}" "$PGBIN/psql" -h "${DOYAH_TEST_PGHOST}" -p "${DOYAH_TEST_PGPORT}" -U "${DOYAH_TEST_PGUSER}" -d "${DOYAH_TEST_ADMIN_DB}" \
    -c "SELECT pg_sleep(60);" >/dev/null 2>&1 &
SLEEPER=$!
sleep 2
    # **必须限定 state='active'**：`query` 会保留上一条语句文本，
    # 不加这条会找到「已空闲的旧会话」，取消它照样返回 true —— 而真正在跑的那条没被碰（本轮踩到两次）。
FOUND="$("$CLI" -c "SELECT pid, state, query FROM pg_stat_activity WHERE query LIKE '%pg_sleep%' AND state = 'active' AND pid <> pg_backend_pid();" 2>&1)"
PID=$(echo "$FOUND" | awk -F' \\| ' '/^[0-9]+ \|/{print $1}' | tr -d ' ' | head -1)
if [ -n "${PID:-}" ]; then
    check "长跑语句出现在会话列表里（pid ${PID}）" 0
else
    check "长跑语句应出现在会话列表里" 1
    echo "$FOUND" | tail -3
fi

echo ""
echo "== 4) 取消这条语句（代码里那条 pg_cancel_backend 语句）=="
if [ -n "${PID:-}" ]; then
    CANCEL="$("$CLI" -c "SELECT pg_cancel_backend(${PID}) AS cancelled;" 2>&1)"
    echo "$CANCEL" | grep -qE "t$|true" && check "pg_cancel_backend 返回 true（服务端接受了取消）" 0 \
        || { check "取消应返回 true" 1; echo "$CANCEL" | tail -3; }

    sleep 1
    # 被取消的会话：语句结束（state 变 idle）或连接消失，两种都算成功。
    # 判据是 `state = 'active'`：**取消之后 `query` 字段仍保留上一条语句文本**（本轮踩到），只看 query 会把「已空闲」误判成「还在跑」。
    # 取消不是瞬时的：backend 要跑到取消检查点。**轮询等待**比固定 sleep 更可靠，
    # 也避免"其实已经取消了，只是我查得太早"这种假失败（本轮就踩过）。
    STILL=1
    for _ in $(seq 1 20); do
        # 注意：**单列结果的输出没有 ` | ` 分隔符**（就是一行 `0`）。
        # 用「整行都是数字」来取，否则会解析不到而把它误判成"仍在跑"（本轮踩到）。
        STILL="$("$CLI" -c "SELECT count(*) AS n FROM pg_stat_activity WHERE pid = ${PID} AND state = 'active';" 2>&1 | awk '/^[0-9]+$/{print $1}' | head -1)"
        [ "${STILL:-1}" = "0" ] && break
        sleep 0.5
    done
    [ "${STILL:-x}" = "0" ] && check "那条语句确实不再执行（state 已不是 active）" 0 || check "语句应被取消（仍是 active）" 1
    wait "$SLEEPER" 2>/dev/null
else
    echo "  ⚠️ 上一步没拿到 pid，跳过取消验证"
    fail=1
fi

echo ""
echo "== 5) 权限如实反馈：取消别人的会话应当得到 false（而不是假装成功）=="
# 用 postgres 之外的普通角色去取消 postgres 的会话：PG 要求同用户或 pg_signal_backend。
PGPASSWORD="${DOYAH_TEST_PGPASSWORD}" "$PGBIN/psql" -h "${DOYAH_TEST_PGHOST}" -p "${DOYAH_TEST_PGPORT}" -U "${DOYAH_TEST_PGUSER}" -d "${DOYAH_TEST_ADMIN_DB}" -c \
    "DO \$\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'doyah_probe') THEN CREATE ROLE doyah_probe LOGIN; END IF; END \$\$;" >/dev/null 2>&1
PGPASSWORD="${DOYAH_TEST_PGPASSWORD}" "$PGBIN/psql" -h "${DOYAH_TEST_PGHOST}" -p "${DOYAH_TEST_PGPORT}" -U "${DOYAH_TEST_PGUSER}" -d "${DOYAH_TEST_ADMIN_DB}" \
    -c "SELECT pg_sleep(30);" >/dev/null 2>&1 &
SLEEPER2=$!
sleep 2
TARGET_PID=$(PGPASSWORD="${DOYAH_TEST_PGPASSWORD}" "$PGBIN/psql" -h 127.0.0.1 -p "$PORT" -U postgres -d postgres -tAc \
    "SELECT pid FROM pg_stat_activity WHERE query LIKE '%pg_sleep%' AND usename = 'postgres' LIMIT 1;" 2>/dev/null | tr -d ' ')
if [ -n "${TARGET_PID:-}" ]; then
    DENIED="$(PGUSER=doyah_probe PGDATABASE="${DOYAH_TEST_ADMIN_DB}" "$CLI" -c "SELECT pg_cancel_backend(${TARGET_PID}) AS cancelled;" 2>&1)"
    DENIED_CODE=$?
    if [ "$DENIED_CODE" -ne 0 ]; then
        echo "$DENIED" | grep -qi "permission denied" && check "权限不足时如实报错（permission denied）" 0 || { check "应报 permission denied" 1; echo "$DENIED" | tail -3; }
    elif echo "$DENIED" | grep -qiE "\| f|false"; then
        check "同级别失败时返回 false（如实反馈）" 0
    else
        check "权限不足不该看起来像成功" 1
        echo "$DENIED" | tail -3
    fi
else
    echo "  ⚠️ 没找到目标会话，跳过该检查"
fi
PGPASSWORD="${DOYAH_TEST_PGPASSWORD}" "$PGBIN/pg_ctl" -D "$DATADIR" stop >/dev/null 2>&1
"$PGBIN/pg_ctl" -D "$DATADIR" -o "-p $PORT -k /tmp" -l /tmp/doyah-session-pg.log start >/dev/null 2>&1
sleep 2
PGPASSWORD="${DOYAH_TEST_PGPASSWORD}" "$PGBIN/psql" -h 127.0.0.1 -p "$PORT" -U postgres -d postgres -c "DROP ROLE IF EXISTS doyah_probe;" >/dev/null 2>&1

echo ""
echo "== 6) 另一条连接（别人的会话）在会话列表里看得见 =="
# **本段原先只读核对 217（18.6）** —— 217 的 `pg_hba` 未放行本机 ⇒ 一直停在既定红。
# 2026-09-28 循环 L-63 转正：改成在本机档造同形状的现场 —— 用一条**不属于本进程**的连接
# （`psql`，带自己的 `application_name`）当「别人的会话」，验的是「会话列表真的看得见别的连接，
# 且库名 / 应用名 / 状态如实」。
PGAPPNAME="doyah_other_session" PGPASSWORD="${DOYAH_TEST_PGPASSWORD}" "${PGBIN}/psql" \
    -h "${DOYAH_TEST_PGHOST}" -p "${DOYAH_TEST_PGPORT}" -U "${DOYAH_TEST_PGUSER}" -d "${DOYAH_TEST_ADMIN_DB}" \
    -c "SELECT pg_sleep(30);" >/dev/null 2>&1 &
OTHER=$!
sleep 2
OTHERS="$("$CLI" -c "${QUERY}" 2>&1)"
printf '%s\n' "${OTHERS}" | grep "doyah_other_session" | head -2 | sed 's/^/  /'
printf '%s\n' "${OTHERS}" | grep -q "doyah_other_session" && check "看得见另一条连接（application_name 原样）" 0 \
    || { check "应看得见另一条连接" 1; printf '%s\n' "${OTHERS}" | head -3 | sed 's/^/  /'; }
printf '%s\n' "${OTHERS}" | grep "doyah_other_session" | grep -q "active" && check "那条会话的状态如实（active）" 0 \
    || check "状态应如实（active）" 1
printf '%s\n' "${OTHERS}" | grep "doyah_other_session" | grep -q "${DOYAH_TEST_ADMIN_DB}" && check "库名如实（${DOYAH_TEST_ADMIN_DB}）" 0 \
    || check "库名应如实（${DOYAH_TEST_ADMIN_DB}）" 1
PGPASSWORD="${DOYAH_TEST_PGPASSWORD}" "${PGBIN}/psql" -h "${DOYAH_TEST_PGHOST}" -p "${DOYAH_TEST_PGPORT}" -U "${DOYAH_TEST_PGUSER}" -d "${DOYAH_TEST_ADMIN_DB}" \
    -c "SELECT pg_cancel_backend(pid) FROM pg_stat_activity WHERE application_name = 'doyah_other_session';" >/dev/null 2>&1
wait "${OTHER}" 2>/dev/null

echo ""
echo "== 7) 非文本类型的值真的可读（队列 L-74）＝ 我们的解码 vs psql 的文本形态 =="
# 为什么这一段长在**会话脚本**里：`client_addr`（inet 列）就是这条缺陷的现场 ——
# 2026-09-28 做 L-63 转正时读原始输出撞见它印的是控制字符。根因：驱动在扩展查询协议下
# 给的是 **binary**，而 `Core/PostgresCellFormatter` 原先只覆盖文本类 / 整型 / 浮点 / 日期时间，
# 其余类型落到 `String(describing: buffer)` —— 用户拿到的是**驱动内部对象的描述**，
# 值里带换行与控制字符，CLI 的表格排版当场被打断（一行值劈成好几行）。
#
# 口径两句话：
#   ① 解出来的文本**对齐 psql**（同一批字面量两边逐条相等，不另立一套）；
#   ② **有意不同的三处，两边都断言** —— 否则「不同」会变成没人管的漂移：
#      · money：binary 里只有「分」，货币符号与千分位由服务端 `lc_monetary` 决定 ⇒ 我们只印数字；
#      · 时间范围的边界：沿用本产品的既有时间写法（ISO 8601），psql 印的是服务端 TimeZone 形态；
#      · 合法 UTF-8 的 bytea：沿用 `FR-DATA-05` 已登记的口径（`\x48656c6c6f` → `Hello`）。
l74_cli_value() {   # <SQL 片段> → 值那一行（CLI 表格里「表头行的下一行」）
    "${CLI}" -c "SELECT ${1} AS v" 2>&1 | awk '/^v:/{getline; print; exit}'
}

l74_psql_value() {  # <SQL 片段> → psql 印的文本形态
    "${PGBIN}/psql" -h "${DOYAH_TEST_PGHOST}" -p "${DOYAH_TEST_PGPORT}" -U "${DOYAH_TEST_PGUSER}" \
        -d "${DOYAH_TEST_ADMIN_DB}" -X -A -t -c "SELECT ${1}" 2>&1 | head -1
}

l74_has_control_char() {   # <字符串> → 含控制字符则打印 1
    if printf '%s' "${1}" | LC_ALL=C grep -q '[[:cntrl:]]'; then
        echo 1
    else
        echo 0
    fi
}

while IFS= read -r l74_expr; do
    [ -z "${l74_expr}" ] && continue
    l74_ours="$(l74_cli_value "${l74_expr}")"
    l74_theirs="$(l74_psql_value "${l74_expr}")"
    if [ -n "${l74_ours}" ] && [ "${l74_ours}" = "${l74_theirs}" ]; then
        check "逐条相等：${l74_expr} → ${l74_ours}" 0
    else
        check "逐条相等：${l74_expr}（psql=${l74_theirs}｜我们=${l74_ours}）" 1
    fi
    [ "$(l74_has_control_char "${l74_ours}")" = "0" ] && check "值里无控制字符：${l74_expr}" 0 \
        || check "值里不该含控制字符：${l74_expr}" 1
done <<'L74_SAME'
inet '127.0.0.1'
inet '192.168.5.223/24'
inet '::1'
inet '::ffff:1.2.3.4'
inet '2001:db8::1/64'
cidr '10.0.0.0/8'
cidr '1.2.3.4/32'
macaddr '08:00:2b:01:02:03'
macaddr8 '08:00:2b:01:02:03:04:05'
bytea '\xfffe01'
interval '1 year 2 mons 3 days 04:05:06.5'
interval '-13 mons'
interval '-1 day 01:00:00'
interval '25 hours'
interval '0'
time '12:34:56.789'
time '24:00:00'
timetz '12:34:56+08'
timetz '08:00:00-04'
bit(5) '10101'
varbit '101'
point '(1.5,2.5)'
box '(1,2),(3,4)'
lseg '[(1,2),(3,4)]'
line '{2,-1,0}'
circle '<(1,2),3>'
path '[(1,2),(3,4)]'
path '((1,2),(3,4))'
polygon '((1,2),(3,4),(5,6))'
ARRAY[1,2,3]::int4[]
ARRAY[1,NULL,3]::int4[]
ARRAY[[1,2],[3,4]]::int4[]
'{}'::int4[]
ARRAY['a b','c,d','e'||chr(34)||'f','NULL','']::text[]
ARRAY[inet '10.0.0.1/24']
ARRAY['\xfffe'::bytea]
int4range(1,10)
int4range(NULL,5,'[]')
'empty'::int4range
int4multirange(int4range(1,3),int4range(5,7))
L74_SAME

while IFS='|' read -r l74_expr l74_expect_ours l74_expect_theirs; do
    [ -z "${l74_expr}" ] && continue
    l74_ours="$(l74_cli_value "${l74_expr}")"
    l74_theirs="$(l74_psql_value "${l74_expr}")"
    [ "${l74_ours}" = "${l74_expect_ours}" ] && check "有意不同｜我们：${l74_expr} → ${l74_ours}" 0 \
        || check "有意不同｜我们应是「${l74_expect_ours}」，实测「${l74_ours}」（${l74_expr}）" 1
    [ "${l74_theirs}" = "${l74_expect_theirs}" ] && check "有意不同｜psql：${l74_expr} → ${l74_theirs}" 0 \
        || check "有意不同｜psql 应是「${l74_expect_theirs}」，实测「${l74_theirs}」（${l74_expr}）" 1
done <<'L74_BOUNDARY'
money '1234.56'|1234.56|$1,234.56
bytea '\x48656c6c6f'|Hello|\x48656c6c6f
daterange('2026-01-01','2026-02-01')|[2026-01-01T00:00:00Z,2026-02-01T00:00:00Z)|[2026-01-01,2026-02-01)
tstzrange('2026-01-01+08','2026-02-01+08')|[2025-12-31T16:00:00Z,2026-01-31T16:00:00Z)|["2026-01-01 00:00:00+08","2026-02-01 00:00:00+08")
L74_BOUNDARY

echo ""
if [ "$fail" -eq 0 ]; then
    echo "通过：会话读取与取消语句在本机 16.2 上验证成立（权限不足时如实报 permission denied；别人的会话如实可见；非文本类型的值逐条与 psql 相等）"
else
    echo "有失败项，见上"
fi
exit "$fail"
