#!/bin/bash
# 真机验证：视图 / 函数 DDL 取回与装配（FR-META-13）。
#
# 为什么必须上真机：这段逻辑的价值全在"服务端到底给什么"——
# 定义体是否带结尾分号、同名函数是不是真的多行、装配出来的语句能不能执行，
# 单测都只能模拟。这里用真实 PostgreSQL 走一遍，并**看退出码**。
#
# 2026-09-28（循环 L-62）：本脚本原先**无条件**连 217 的业务库（`zxvmax`），本机跑必红
# （`pg_hba` 未放行），于是 alpha 主链里「视图 / 函数 DDL」这一段**没有本机证据**。
# 现在改走共用入口：本机档 = 本机临时集群 + trust（无口令）；远程档 = 远程专用库。
set -uo pipefail

cd "$(dirname "$0")/.."
CLI=".build/debug/DoyahCLI"

# 本脚本不建库（临时对象全装在自己建的那个 schema 里），但**要先确保实例在跑** ——
# 本机档由共用入口起集群（远程档是 no-op），退出时只关「本脚本起的」那一份。
DOYAH_TEST_SCRIPT_READY_FOR_REMOTE=1
# 连接信息（本机过渡集群 / 远程专用库）由共用入口决定 —— 三档端口与目录只写在它里面
source "$(cd "$(dirname "$0")" && pwd)/lib/test-env.sh"
doyah_test_env_summary

# 连接只走共用入口这一条路。**为什么改**：此前这里是写死 217 的旁路 + 「取密文口令」的第二种
# 取法，于是本脚本**在业务库上建 schema**，而文件头注释自称「只读核对」（名实不符）；
# 共用入口的远程档有安全闸，业务库直接拒绝（SRS §0.9 E3 / ADR-32）。
doyah_test_env_start_cluster
trap 'doyah_test_env_stop_cluster' EXIT
doyah_test_env_export_connection
export PGDATABASE="${DOYAH_TEST_PGDATABASE}"

fail=0
step() { echo ""; echo "== $* =="; }
# 断言写成「  ✅ 」行 —— 这个前缀是**机械计数口径**（`Scripts/count-evidence-assertions.py`），
# alpha 主链靠它判「这一段到底有没有真的断言」（空跑不许当绿）。原先本脚本把勾写在句尾，
# 计数为 0 ⇒ 进主链后被判 ❌（2026-09-28 循环 L-62 实测）。
check() { if [ "$2" -eq 0 ]; then echo "  ✅ $1"; else echo "  ❌ $1"; fail=1; fi; }

# 提取结果列内容：到 "finished:" / "查询执行完成" 之类的日志行就停。
extract_column() {
    awk '/^[a-z_]+:TEXT$/{f=1;next} f&&/^finished:|^查询执行完成|^---/{exit} f{print}'
}

step "0) 造现场（这个 schema / 视图 / 两个同名重载原先**只存在于 217 上**、没写进脚本 ——
   换一台库跑必红，这正是本条要修的另一半）"
FIXTURE="DROP SCHEMA IF EXISTS doyah_ddl_check CASCADE;
CREATE SCHEMA doyah_ddl_check;
CREATE TABLE doyah_ddl_check.t (id integer PRIMARY KEY);
CREATE VIEW doyah_ddl_check.v AS SELECT id FROM doyah_ddl_check.t;
CREATE FUNCTION doyah_ddl_check.f(integer) RETURNS integer AS 'SELECT \$1 + 1' LANGUAGE sql;
CREATE FUNCTION doyah_ddl_check.f(text) RETURNS text AS 'SELECT upper(\$1)' LANGUAGE sql;"
"$CLI" -c "$FIXTURE" > /tmp/ddl-setup.log 2>&1
if [ $? -eq 0 ]; then
    echo "→ 现场已建立（schema + 视图 + 两个同名重载）✅"
else
    echo "→ 建现场失败 ❌"; tail -5 /tmp/ddl-setup.log; exit 1
fi

step "1) 视图定义体（我在代码里生成的那条查询）"
VIEW_BODY="$("$CLI" -c "SELECT pg_get_viewdef('\"doyah_ddl_check\".\"v\"'::regclass, true) AS view_definition" | extract_column)"
echo "$VIEW_BODY"
case "$VIEW_BODY" in
    *';') check "定义体自带结尾分号（装配时必须去掉，否则会生成两条语句）" 0 ;;
    *)    check "定义体自带结尾分号" 1 ;;
esac
if echo "$VIEW_BODY" | grep -q "finished:"; then check "提取没有混入日志行" 1; else check "提取没有混入日志行" 0; fi

step "2) 装配成 CREATE OR REPLACE VIEW 并真的执行（事务内，随后回滚）"
CLEAN="${VIEW_BODY%;}"
STMT="CREATE OR REPLACE VIEW \"doyah_ddl_check\".\"v\" AS
$CLEAN;"
"$CLI" -c "BEGIN; $STMT ROLLBACK;" > /tmp/ddl-view-check.log 2>&1
VIEW_CODE=$?
if [ "$VIEW_CODE" -eq 0 ]; then
    check "装配后的语句被 PostgreSQL 接受（退出码 0）" 0
else
    check "装配后的语句被 PostgreSQL 接受" 1; tail -5 /tmp/ddl-view-check.log
fi

step "3) 函数：两个同名重载都要取到"
FUNC_ROWS="$("$CLI" -c "SELECT pg_get_functiondef(p.oid) AS function_definition FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE p.proname = 'f' AND n.nspname = 'doyah_ddl_check' ORDER BY p.oid" | grep -c "^CREATE OR REPLACE FUNCTION doyah_ddl_check.f")"
echo "取到的重载条数：$FUNC_ROWS"
if [ "$FUNC_ROWS" -eq 2 ]; then
    check "两个同名重载都在结果里（不 LIMIT 1 是必须的）" 0
else
    check "两个同名重载都在结果里" 1
fi

step "4) 不支持 / 无权限时的行为：表不存在时 regclass 转换应报错（由界面转成可读提示）"
"$CLI" -c "SELECT pg_get_viewdef('\"doyah_ddl_check\".\"nope\"'::regclass, true) AS view_definition" > /tmp/ddl-missing.log 2>&1
MISSING_CODE=$?
if [ "$MISSING_CODE" -ne 0 ]; then
    check "表不存在时查询如实报错（退出码 ${MISSING_CODE}），不会被当成空结果而静默失败" 0
    grep -m1 "简要信息\|does not exist" /tmp/ddl-missing.log | head -1
else
    check "表不存在时查询如实报错" 1
fi

step "5) 清理现场"
"$CLI" -c "DROP SCHEMA IF EXISTS doyah_ddl_check CASCADE;" > /tmp/ddl-cleanup.log 2>&1
[ $? -eq 0 ] && echo "→ 已删除 doyah_ddl_check ✅" || { echo "→ 清理失败 ❌"; fail=1; }

echo ""
if [ "$fail" -eq 0 ]; then
    echo "全部通过：视图 / 函数 DDL 在真机 18.6 上取回并装配成功"
else
    echo "有失败项，见上"
fi
exit "$fail"
