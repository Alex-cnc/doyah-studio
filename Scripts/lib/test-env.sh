#!/bin/bash
# 真机验证脚本的**共用连接入口**（开发循环 L-06 起）。
#
# ## 为什么有它
#
# 本工程有 28 个脚本要连**真实 PostgreSQL / MySQL** 才有意义（建表 / 插数据 / 查元数据）。
# 这 28 个脚本原先各自硬编码连接信息 —— 「`~/tools/pgserver` 的二进制路径 + 端口 55433 +
# `127.0.0.1` + `postgres`」这套字面量在 28 个文件里各写一遍。于是 SRS §0.9 定下
# 「**本机只做开发机、需要真实库一律连 217 的专用测试库**」（ADR-32）之后，迁移的代价是
# 28 份手改；而且**改漏一个没人发现** —— 硬编码的字面量和「连上了哪台库」之间没有机械判据。
#
# 这个文件把那套字面量收成**唯一一处**：脚本只声明「我要一个真库」，具体连哪儿由这里决定。
#
# ## 两种模式
#
# | 模式 | 触发条件 | 连哪儿 | 起本机集群 |
# |---|---|---|---|
# | `local`（**过渡态**） | `DOYAH_TEST_PG*` 一个都没给 | 本机临时集群 `127.0.0.1:55433` | 起（脚本自己 initdb/start） |
# | `remote` | `DOYAH_TEST_PGHOST/PGPORT/PGUSER/PGDATABASE` **四项全给** | 217 等远程实例的**专用测试库** | 不起（远程实例常驻） |
#
# **为什么不默认连本地**：默认连本地正是这次要迁掉的东西；但 217 的专用库与账号**还没拿到**
# （SRS §5.3 环境卡点），所以过渡期必须保留本机路径 —— 只是把它做成**显式的一处**
# 而不是 28 处，并且**打印出来**（每个脚本的日志里都能看见这轮连的是谁）。
#
# ## 缺项一律报错，不猜
#
# 只给了一部分 `DOYAH_TEST_PG*`（例如设了 HOST 忘了 USER）时**直接拒绝开工**：
# 半套配置最可能的结局是「静默回落本机」或「拿空口令去连 217」，两种都是把结论建在
# 假的现场上。缺哪项就指名哪项（退出码 **78**）。
#
# ## 安全闸（SRS §0.9 E3 / ADR-32）
#
# 远程模式下**拒绝对业务库开工**：库名命中 `zxvmax`（及其前缀变体）或 `postgres` / `template*`
# 时直接拒绝（退出码 **77**）。这些脚本会建表 / 插数据 / 删表，跑错库就是事故。
#
# ## 远程模式下不许脚本自建库
#
# `doyah_test_env_scratch_db` 在本地模式做 `DROP DATABASE / CREATE DATABASE`（今天的行为），
# 远程模式**拒绝**：迁移第 2 步（改成在 `doyah_test` 内**按前缀建表 / 建 schema** 并清理）
# 是逐脚本的工作，还没做，而「在别人的库里随手建库」不该是过渡期行为（退出码 77 并指路）。
#
# ## 远程模式要脚本自己「报到」（`DOYAH_TEST_SCRIPT_READY_FOR_REMOTE=1`）
#
# 光给齐四项连接信息**不足以**让一个脚本在远程模式下跑起来：这 28 个脚本的**集群生命周期段**
# （`pg_ctl status/start/stop`、`initdb`、按名字建库）还没改（那是迁移第 2 步、逐脚本的活）。
# 不设防的后果是：远程模式下 `DOYAH_TEST_PG_BIN` 是空的，脚本会去执行 `/pg_ctl`，
# 报出一串与真因无关的错 —— 又是一次「假绿 / 假红」的现场。
# 所以远程模式下**没报到的脚本直接被拒**（退出码 78，消息里指路）。这是一个**有意的开关**：
# 谁把生命周期段改完了，谁才在自己头上写 `DOYAH_TEST_SCRIPT_READY_FOR_REMOTE=1`。
#
# ## 本机过渡模式的三档集群（`DOYAH_TEST_LOCAL_PROFILE`）
#
# 28 个脚本原先各自写死端口与数据目录，其实是三份不同的集群（历史上按用途分过档）：
#
# | 档位 | 端口 | 数据目录 | 谁用 |
# |---|---|---|---|
# | `session`（默认） | 55433 | `<工程根>/.build/pgdata-session-test` | 25 个 |
# | `slowquery` | 55434 | `<工程根>/.build/pgdata-slowquery` | `test-slow-queries.sh`（要往自己的 `postgresql.conf` 写 `shared_preload_libraries`） |
# | `querytest` | 55432 | `~/tools/pgdata-querytest` | `test-local-query-path.sh` / `test-backup-restore.sh` |
#
# 三档的端口与目录**只写在下面这一张表里**。脚本要哪一档就在 source 之前写一行
# `DOYAH_TEST_LOCAL_PROFILE=<档位>` —— 这既保住了今天的行为，也让「连的是哪一份集群」可读。
#
# ## 对外变量（source 之后可用）
#
#   DOYAH_TEST_MODE             `local` | `remote`
#   DOYAH_TEST_PGHOST           `127.0.0.1`（local）/ 给定值（remote）
#   DOYAH_TEST_PGPORT           端口（local 默认 55433）
#   DOYAH_TEST_PGUSER           账号（local 默认 postgres）
#   DOYAH_TEST_PGPASSWORD       口令（local 空；local 集群是 trust 认证）
#   DOYAH_TEST_PGDATABASE       库（local 默认 doyah_manual_test）
#   DOYAH_TEST_PGSSLMODE        默认 disable（217 的既有口径）
#   DOYAH_TEST_PG_BIN           本机 PG 二进制目录（remote 下为空 —— 没本机集群可起）
#   DOYAH_TEST_LOCAL_DATADIR    本机集群数据目录（remote 下为空）
#   DOYAH_TEST_ADMIN_DB         建库用的维护库（local 为 postgres；remote 为 nil）
#   DOYAH_TEST_PROBE_PREFIX     临时对象前缀（默认 doyah_probe_）
#   DOYAH_TEST_TABLE_PREFIX     临时表前缀（默认 doyah_probe_）
#
# ## 对外函数
#
#   doyah_test_env_summary                 一行目标摘要（写进脚本日志）
#   doyah_test_env_export_connection       导出 PGHOST/PGPORT/PGUSER/PGPASSWORD/PGSSLMODE
#   doyah_test_env_start_cluster           本地模式 initdb+起集群（起不来即拒绝开工）；远程模式 no-op
#   doyah_test_env_require_port_free       本机档起集群**之前**先看端口在谁手里（⑦C：被占 ⇒ 点名 + 75）
#   doyah_test_env_require_local_cluster   自查「本数据目录自己的实例在跑」（L-189；远程模式 no-op）
#   doyah_test_env_stop_cluster            只关「本函数起的」那一份，且只在本地模式
#   doyah_test_env_scratch_name NAME       -> 加前缀的临时库名
#   doyah_test_env_scratch_db NAME         本地：DROP+CREATE 该库并把 PGDATABASE 指过去；远程：拒绝
#
# ## 可覆盖的开关
#
#   DOYAH_TEST_MODE=local|remote   强制模式（remote 仍需四项齐全；调试与负例用）
#   DOYAH_TEST_LOCAL_PORT          本机集群端口（默认 55433）
#   DOYAH_TEST_LOCAL_DATADIR       本机集群数据目录（默认 <工程根>/.build/pgdata-session-test）
#   DOYAH_TEST_PG_BIN              本机 PG 二进制目录（默认 ~/tools/pgserver/pgserver/pginstall/bin）
#   DOYAH_TEST_LOCAL_DATABASE      本机模式默认库（默认 doyah_manual_test）
#   DOYAH_TEST_PROBE_PREFIX        临时对象前缀
#
# ## 注意（bash 3.2 的多字节坑，见 `Scripts/check-shell-locale-safety.py`）
#
# 本文件里变量一律写 `${变量}`：macOS 自带 bash 3.2 下，裸写 `$变量` 后面紧跟 CJK 字符会把
# 变量**静默展开成空**（脚本照常打勾，只是那一行的值空了）。

# ---- 退出码 ---------------------------------------------------------------
DOYAH_TEST_EXIT_CONFIG=78   # 配置不全 / 前后矛盾（缺哪项在消息里指名）
DOYAH_TEST_EXIT_REFUSE=77   # 安全拒绝（业务库 / 远程模式下自建库）
DOYAH_TEST_EXIT_NO_CLUSTER=76   # 本机集群起不来（L-189：不用别人的实例取读数）
DOYAH_TEST_EXIT_PORT_BUSY=75   # 本机档端口被**别的实例**占着（起集群必败 ⇒ 停手并点名；⑦C）

# 本文件在 <工程根>/Scripts/lib/ 下 —— 工程根由**本文件位置**推出，不依赖调用方的 cwd
# （有的脚本先 cd 到工程根，有的不 cd；连接信息不该因此变样）。
_doyah_test_project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

# `local` = 本机临时集群（过渡态）；`remote` = 远程专用测试库
DOYAH_TEST_MODE="${DOYAH_TEST_MODE:-}"

# ---- 远程模式的四项必填 ----------------------------------------------------
# 少任何一项都不开工（不猜、不默认连本地）。
_doyah_test_required="DOYAH_TEST_PGHOST DOYAH_TEST_PGPORT DOYAH_TEST_PGUSER DOYAH_TEST_PGDATABASE"
_doyah_test_given=""
_doyah_test_missing=""
for _doyah_test_name in ${_doyah_test_required}; do
    eval "_doyah_test_value=\"\${${_doyah_test_name}:-}\""
    if [ -n "${_doyah_test_value}" ]; then
        _doyah_test_given="${_doyah_test_given} ${_doyah_test_name}=${_doyah_test_value}"
    else
        _doyah_test_missing="${_doyah_test_missing} ${_doyah_test_name}"
    fi
done

if [ -z "${DOYAH_TEST_MODE}" ]; then
    if [ -z "${_doyah_test_given}" ]; then
        DOYAH_TEST_MODE="local"
    elif [ -z "${_doyah_test_missing}" ]; then
        DOYAH_TEST_MODE="remote"
    else
        echo "❌ 连接信息只给了一半，拒绝开工（不猜、不默认连本地）。"
        echo "   已给：${_doyah_test_given}"
        echo "   还缺：${_doyah_test_missing}"
        echo "   要么四项全给（远程模式），要么一项都不给（本机过渡模式，端口 55433）。"
        exit "${DOYAH_TEST_EXIT_CONFIG}"
    fi
fi

case "${DOYAH_TEST_MODE}" in
    local|remote) ;;
    *)
        echo "❌ DOYAH_TEST_MODE 只认 local / remote，收到「${DOYAH_TEST_MODE}」。"
        exit "${DOYAH_TEST_EXIT_CONFIG}"
        ;;
esac

# ---- 按模式定连接信息 ------------------------------------------------------
if [ "${DOYAH_TEST_MODE}" = "remote" ]; then
    # remote 模式必须四项齐全（即使是 DOYAH_TEST_MODE=remote 显式指定的）
    if [ -n "${_doyah_test_missing}" ]; then
        echo "❌ DOYAH_TEST_MODE=remote 但连接信息不全，拒绝开工。"
        echo "   还缺：${_doyah_test_missing}"
        exit "${DOYAH_TEST_EXIT_CONFIG}"
    fi

    # 光有连接信息还不够：脚本的集群生命周期段得先改完（迁移第 2 步）。
    # 没报到的脚本在这里被拒，而不是跑出一串与真因无关的 `/pg_ctl: No such file`。
    if [ "${DOYAH_TEST_SCRIPT_READY_FOR_REMOTE:-0}" != "1" ]; then
        echo "❌ 拒绝开工：远程模式下本脚本还没「报到」。"
        echo "   已给齐连接信息：${DOYAH_TEST_PGHOST}:${DOYAH_TEST_PGPORT}/${DOYAH_TEST_PGDATABASE}"
        echo "   但本脚本的**起集群 / 建库 / 停集群**段还是本机过渡模式的写法（迁移第 2 步未做，"
        echo "   见 Docs/design/剩余任务清单.md §四）。直接跑会去执行空的 \`\${DOYAH_TEST_PG_BIN}/pg_ctl\`，"
        echo "   报出一串与真因无关的错 —— 所以这里直接拒绝，不制造假红。"
        echo "   把那段改成「连 ${DOYAH_TEST_PGDATABASE}，按前缀建表并在结束时清理」之后，"
        echo "   在本脚本里写一行 DOYAH_TEST_SCRIPT_READY_FOR_REMOTE=1（放在 source 之前）即视为报到。"
        exit "${DOYAH_TEST_EXIT_CONFIG}"
    fi

    DOYAH_TEST_PGPASSWORD="${DOYAH_TEST_PGPASSWORD:-}"

    # 安全闸：绝不拿会写数据的脚本对业务库开工（SRS §0.9 E3）
    _doyah_test_db_lower="$(printf '%s' "${DOYAH_TEST_PGDATABASE}" | tr '[:upper:]' '[:lower:]')"
    case "${_doyah_test_db_lower}" in
        zxvmax*|postgres|template0|template1)
            echo "❌ 拒绝开工：目标是业务库「${DOYAH_TEST_PGDATABASE}」。"
            echo "   本工程的脚本会建表 / 插数据 / 删表（SRS §0.9 E3、ADR-32），只允许对**专用测试库**开工。"
            echo "   请把 DOYAH_TEST_PGDATABASE 指向 217 上的专用测试库（约定 doyah_test）。"
            exit "${DOYAH_TEST_EXIT_REFUSE}"
            ;;
    esac

    # 远程实例常驻：没有本机集群可起，也没有本机二进制可用
    DOYAH_TEST_PG_BIN=""
    DOYAH_TEST_LOCAL_DATADIR=""
    DOYAH_TEST_ADMIN_DB=""
else
    # 本机过渡模式：三档集群的端口与数据目录**只写在这张表里**（原先散在 28 个文件里）
    case "${DOYAH_TEST_LOCAL_PROFILE:-session}" in
        session)
            _doyah_test_profile_port=55433
            _doyah_test_profile_datadir="${_doyah_test_project_root}/.build/pgdata-session-test"
            ;;
        slowquery)
            _doyah_test_profile_port=55434
            _doyah_test_profile_datadir="${_doyah_test_project_root}/.build/pgdata-slowquery"
            ;;
        querytest)
            _doyah_test_profile_port=55432
            _doyah_test_profile_datadir="${HOME}/tools/pgdata-querytest"
            ;;
        *)
            echo "❌ DOYAH_TEST_LOCAL_PROFILE 只认 session / slowquery / querytest，收到「${DOYAH_TEST_LOCAL_PROFILE}」。"
            exit "${DOYAH_TEST_EXIT_CONFIG}"
            ;;
    esac

    DOYAH_TEST_PGHOST="127.0.0.1"
    # 旧名 TEST_PGPORT / PGSERVER_DATADIR 仍认（有几个脚本的注释里对外承诺过这两个开关）
    DOYAH_TEST_PGPORT="${DOYAH_TEST_LOCAL_PORT:-${TEST_PGPORT:-${_doyah_test_profile_port}}}"
    DOYAH_TEST_PGUSER="${DOYAH_TEST_LOCAL_USER:-postgres}"
    DOYAH_TEST_PGPASSWORD=""
    DOYAH_TEST_PGDATABASE="${DOYAH_TEST_LOCAL_DATABASE:-doyah_manual_test}"
    DOYAH_TEST_PG_BIN="${DOYAH_TEST_PG_BIN:-${HOME}/tools/pgserver/pgserver/pginstall/bin}"
    DOYAH_TEST_LOCAL_DATADIR="${DOYAH_TEST_LOCAL_DATADIR:-${PGSERVER_DATADIR:-${_doyah_test_profile_datadir}}}"
    DOYAH_TEST_ADMIN_DB="postgres"
fi

DOYAH_TEST_PGSSLMODE="${DOYAH_TEST_PGSSLMODE:-disable}"
DOYAH_TEST_PROBE_PREFIX="${DOYAH_TEST_PROBE_PREFIX:-doyah_probe_}"
DOYAH_TEST_TABLE_PREFIX="${DOYAH_TEST_TABLE_PREFIX:-doyah_probe_}"

# ---- 217 那侧的**只读**核对段 ---------------------------------------------
#
# 有几个脚本只对 217 做只读核对（数对象、看 DDL、比表结构），不建表也不建库 —— 它们的连接信息
# 与上面那两条模式无关，历史上一直写死在这里。**如实登记**：这些脚本连的是**业务库 `zxvmax`**
# （用业务账号），属 SRS §0.9 E3 定下「只碰专用测试库」**之前**的写法；专用账号到位后应改指
# `doyah_test`。本轮只把字面量收到这一处，不改指向（改指向要有账号才验得了）。
DOYAH_TEST_REMOTE_HOST="${DOYAH_TEST_REMOTE_HOST:-192.168.5.217}"
DOYAH_TEST_REMOTE_PORT="${DOYAH_TEST_REMOTE_PORT:-5432}"
DOYAH_TEST_REMOTE_USER="${DOYAH_TEST_REMOTE_USER:-zxvmax}"
DOYAH_TEST_REMOTE_DATABASE="${DOYAH_TEST_REMOTE_DATABASE:-zxvmax}"

# 谁起的集群谁关（脚本之间不能互相关：前一个脚本把后来的那份集群关掉，后来的会一脸懵）
DOYAH_TEST_CLUSTER_STARTED_BY_US="${DOYAH_TEST_CLUSTER_STARTED_BY_US:-0}"

# ---- 函数 ------------------------------------------------------------------

# 一行目标摘要。**每个脚本都该打印它**：日志里能看见这轮连的是谁，
# 「结论是在哪台库上取的」不该靠回忆（E5：连不上/没账号时要说实话）。
doyah_test_env_summary() {
    if [ "${DOYAH_TEST_MODE}" = "remote" ]; then
        echo "  · 真库目标：${DOYAH_TEST_PGHOST}:${DOYAH_TEST_PGPORT}/${DOYAH_TEST_PGDATABASE}（用户 ${DOYAH_TEST_PGUSER}）—— 远程实例，常驻，不起本机集群"
    else
        echo "  · 真库目标：${DOYAH_TEST_PGHOST}:${DOYAH_TEST_PGPORT}/${DOYAH_TEST_PGDATABASE}（用户 ${DOYAH_TEST_PGUSER}）—— **本机临时集群（过渡态）**"
    fi
}

# 导出 CLI / psql 都认的那组标准变量。库名不在这里导（各脚本自定临时库）。
doyah_test_env_export_connection() {
    export PGHOST="${DOYAH_TEST_PGHOST}"
    export PGPORT="${DOYAH_TEST_PGPORT}"
    export PGUSER="${DOYAH_TEST_PGUSER}"
    export PGPASSWORD="${DOYAH_TEST_PGPASSWORD}"
    export PGSSLMODE="${DOYAH_TEST_PGSSLMODE}"
}

# 起集群之前先问一句：本机档这个端口在谁手里（⑦C · 人类主人 2026-10-13 裁定 C）。
#
# 为什么要（真缺陷）：本机档三档端口是**固定**的（见上面的档位表），而同机常有**别的克隆**的
# 测试集群常驻占着同一个端口（实测 2026-10-06 14:01 起 55433 被别的克隆的 postmaster
# `pid 36043` 占住、已跑数日）⇒ 那时 `pg_ctl start` 必败，而失败只写进
# `/tmp/doyah-test-env-pg.log`：脚本侧看到的是**非零退出、有时一行输出都没有** ——
# 现场看起来像「判据自己坏了」，真因却是**别人的集群占着端口**。
# 所以这里把占者的 pid / 命令行 / 数据目录**点名**打出来，并以退出码 75 停手。
#
# 判据（成对自检 = `Scripts/test-script-env-gates.py` 的 B-15 / B-16）：
#   端口被别的实例占着 ⇒ **出声** + `rc=75`；端口空闲 ⇒ **静默**（一行都不多打）。
doyah_test_env_require_port_free() {
    if [ "${DOYAH_TEST_MODE}" = "remote" ]; then
        return 0
    fi
    local port="${1:-${DOYAH_TEST_PGPORT}}"
    # 我们自己的实例在跑 ⇒ 端口当然是我们占的，不报
    if [ -n "${DOYAH_TEST_PG_BIN}" ] && [ -x "${DOYAH_TEST_PG_BIN}/pg_ctl" ] &&
        "${DOYAH_TEST_PG_BIN}/pg_ctl" -D "${DOYAH_TEST_LOCAL_DATADIR}" status >/dev/null 2>&1; then
        return 0
    fi
    local _doyah_test_holder
    _doyah_test_holder="$(lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null | awk 'NR > 1 { print $2; exit }')"
    if [ -z "${_doyah_test_holder}" ]; then
        return 0
    fi
    local _doyah_test_holder_cmd _doyah_test_holder_args
    _doyah_test_holder_cmd="$(ps -p "${_doyah_test_holder}" -o comm= 2>/dev/null || true)"
    _doyah_test_holder_args="$(ps -p "${_doyah_test_holder}" -o args= 2>/dev/null || true)"
    echo "  ❌ 起不了本机测试集群：端口 ${port} 已被**别的实例**占着（⑦C）—— 本脚本停手，不是判据失败。"
    echo "     · 占端口的进程：${_doyah_test_holder_cmd}（pid ${_doyah_test_holder}）"
    echo "     · 它的命令行：${_doyah_test_holder_args}"
    echo "     · 本脚本要用的数据目录：${DOYAH_TEST_LOCAL_DATADIR}"
    echo "     · 处置（三选一）：① 停掉那个实例（多为别的克隆遗留的常驻测试集群）后重跑；"
    echo "                      ② 换端口：DOYAH_TEST_LOCAL_PORT=<空闲端口>；"
    echo "                      ③ 连远程专用库：给齐 DOYAH_TEST_PGHOST/PGPORT/PGUSER/PGDATABASE。"
    exit "${DOYAH_TEST_EXIT_PORT_BUSY}"
}

# 本地模式：数据目录没初始化就 initdb，实例没跑就起；远程模式：什么都不做。
# **起不来就拒绝开工**：起实例之后必须自查「本数据目录自己的实例真在跑」（L-189）。
doyah_test_env_start_cluster() {
    if [ "${DOYAH_TEST_MODE}" = "remote" ]; then
        return 0
    fi
    if [ -z "${DOYAH_TEST_PG_BIN}" ] || [ ! -x "${DOYAH_TEST_PG_BIN}/pg_ctl" ]; then
        echo "❌ 找不到本机 PostgreSQL 二进制：${DOYAH_TEST_PG_BIN}/pg_ctl"
        echo "   本机过渡模式需要它；或改用远程模式（给齐 DOYAH_TEST_PGHOST/PGPORT/PGUSER/PGDATABASE）。"
        exit "${DOYAH_TEST_EXIT_CONFIG}"
    fi
    doyah_test_env_require_port_free
    if [ ! -f "${DOYAH_TEST_LOCAL_DATADIR}/PG_VERSION" ]; then
        mkdir -p "${DOYAH_TEST_LOCAL_DATADIR}" || exit "${DOYAH_TEST_EXIT_CONFIG}"
        "${DOYAH_TEST_PG_BIN}/initdb" -D "${DOYAH_TEST_LOCAL_DATADIR}" -U "${DOYAH_TEST_PGUSER}" \
            --auth=trust -E UTF8 >/dev/null 2>&1
    fi
    if ! "${DOYAH_TEST_PG_BIN}/pg_ctl" -D "${DOYAH_TEST_LOCAL_DATADIR}" status >/dev/null 2>&1; then
        "${DOYAH_TEST_PG_BIN}/pg_ctl" -D "${DOYAH_TEST_LOCAL_DATADIR}" \
            -o "-p ${DOYAH_TEST_PGPORT} -k /tmp" -l /tmp/doyah-test-env-pg.log start >/dev/null 2>&1
        DOYAH_TEST_CLUSTER_STARTED_BY_US="1"
        sleep 2
        doyah_test_env_require_local_cluster
    fi
    return 0
}

# 自查「**本数据目录自己的**实例在跑吗」—— 起实例之后必须调用它（L-189）。
#
# 为什么需要：`pg_ctl start` 失败时若没人看它，脚本会继续用 `127.0.0.1:<端口>` 连库，而同机
# 常有**别的克隆**的集群占着同一个端口（实测：那个实例已跑了 5 天 6 小时）⇒ 脚本读到的是
# **别人的数据目录**、断言照旧全绿 —— 假绿。而「结论是在哪个库上取的」正是本文件存在的理由。
# 实测：8 个真库脚本里 7 个犯过这一条（`test-inline-edit` / `test-schema-diff` /
# `test-data-import` / `test-copy-import` / `test-csv-encoding` / `test-table-structure` /
# `test-table-index-fk`），只有 `test-session-management.sh` 自查。
#
# 判据（场景注入）：端口被别的实例占着时，每个脚本必须**非零退出**并点名「自建实例没起来」。
doyah_test_env_require_local_cluster() {
    if [ "${DOYAH_TEST_MODE}" = "remote" ]; then
        return 0
    fi
    local datadir="${1:-${DOYAH_TEST_LOCAL_DATADIR}}"
    local port="${2:-${DOYAH_TEST_PGPORT}}"
    local logfile="${3:-/tmp/doyah-test-env-pg.log}"
    if "${DOYAH_TEST_PG_BIN}/pg_ctl" -D "${datadir}" status >/dev/null 2>&1; then
        return 0
    fi
    echo "  ❌ 自建实例没起来（L-189）—— 本脚本停手，不用别人的实例取读数。"
    echo "     · 数据目录：${datadir}"
    echo "     · 端口：${port}"
    echo "     · 启库日志：${logfile}"
    echo "     · 谁占着这个端口：lsof -nP -iTCP:${port} -sTCP:LISTEN"
    echo "     · 处置：停掉占端口的实例（多为别的克隆遗留的测试集群）后重跑本脚本。"
    exit "${DOYAH_TEST_EXIT_NO_CLUSTER}"
}

# 只关「我们起的」那一份，且只在本地模式。
doyah_test_env_stop_cluster() {
    if [ "${DOYAH_TEST_MODE}" = "remote" ]; then
        return 0
    fi
    [ "${DOYAH_TEST_CLUSTER_STARTED_BY_US}" = "1" ] || return 0
    "${DOYAH_TEST_PG_BIN}/pg_ctl" -D "${DOYAH_TEST_LOCAL_DATADIR}" stop >/dev/null 2>&1
    return 0
}

# 临时对象名统一加前缀：脚本建的表 / 库不许和真业务对象撞名，也便于一次清干净。
doyah_test_env_scratch_name() {
    printf '%s%s' "${DOYAH_TEST_PROBE_PREFIX}" "${1}"
}

# 本地模式：DROP + CREATE 一个临时库并把 PGDATABASE 指过去（今天 28 个脚本的行为）。
# 远程模式：**拒绝** —— 在别人的库里随手建库不是过渡期该做的事，迁移第 2 步还没做。
doyah_test_env_scratch_db() {
    if [ "${DOYAH_TEST_MODE}" = "remote" ]; then
        echo "❌ 拒绝开工：远程模式下脚本不许自建库。"
        echo "   本脚本要建的是临时库「$(doyah_test_env_scratch_name "${1}")」，而远程实例上建库属于对别人服务器的写操作。"
        echo "   迁移第 2 步（改成在 ${DOYAH_TEST_PGDATABASE} 内按前缀建表 / 建 schema 并在结束时清理）尚未完成，"
        echo "   见 Docs/design/剩余任务清单.md §四。在它做完之前，本脚本只能在连接信息留空时跑（本机过渡模式）。"
        exit "${DOYAH_TEST_EXIT_REFUSE}"
    fi
    doyah_test_env_export_connection
    "${DOYAH_TEST_PG_BIN}/psql" -h "${DOYAH_TEST_PGHOST}" -p "${DOYAH_TEST_PGPORT}" \
        -U "${DOYAH_TEST_PGUSER}" -d "${DOYAH_TEST_ADMIN_DB}" \
        -c "DROP DATABASE IF EXISTS \"$(doyah_test_env_scratch_name "${1}")\" WITH (FORCE);" >/dev/null 2>&1
    "${DOYAH_TEST_PG_BIN}/psql" -h "${DOYAH_TEST_PGHOST}" -p "${DOYAH_TEST_PGPORT}" \
        -U "${DOYAH_TEST_PGUSER}" -d "${DOYAH_TEST_ADMIN_DB}" \
        -c "CREATE DATABASE \"$(doyah_test_env_scratch_name "${1}")\";" >/dev/null 2>&1
    DOYAH_TEST_PGDATABASE="$(doyah_test_env_scratch_name "${1}")"
    export PGDATABASE="${DOYAH_TEST_PGDATABASE}"
    return 0
}

unset _doyah_test_name _doyah_test_value _doyah_test_required
unset _doyah_test_given _doyah_test_missing _doyah_test_db_lower _doyah_test_project_root
unset _doyah_test_profile_port _doyah_test_profile_datadir
