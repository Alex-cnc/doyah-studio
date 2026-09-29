#!/bin/bash
set -euo pipefail

# 「待人工验收清单」B 类条目的 **App 内探针**（队列 L-89 —— 把「需要你点一下」变成「机器判得住」）。
#
#   ./Scripts/run-manual-verification-probes.sh                     # 两遍：普通构建 + 沙箱标记
#   ./Scripts/run-manual-verification-probes.sh --filter 用例名片段   # 只跑某一部分（仍跑两遍）
#
# ## 为什么跑**两遍**
#
# 清单里 `FR-CONN-18 沙箱告知` 那一行判的是「**沙箱构建**下界面必须多出一句说明（并给出非沙箱构建的命令）」，
# 而「是不是沙箱」的依据是进程环境变量 `APP_SANDBOX_CONTAINER_ID`（沙箱进程自带标记）——
# **一个进程只能是一面**。两遍合起来才把「环境 → 界面」这条对应关系判完整：
#
#   · 普通那遍：该说明**不许**出现；
#   · 沙箱标记那遍：该说明**必须**出现，且与普通那遍相比**只多它这一句**。
#
# 逐句断言（中英各判一次）写在 `TestsUISnapshot/ManualVerificationProbeTests.swift` 里；
# 本脚本负责把两遍串起来，并**跨清单再判一次** —— 防「两遍其实跑的是同一面」（那种情况下
# 每遍自己都绿，而「环境决定界面」这件事根本没被验过）。
#
# ## 第二批（队列 L-89 ㈡，第 92 轮）：命令面板接线
#
# `TestsUISnapshot/PaletteWiringProbeTests.swift` 判的是清单里 `FR-EDIT-25` 那一句人话
# 「**每个命令都真的打开了对应面板（不是点了没反应）**」—— 静态判据
# （`Scripts/check-palette-wiring.py`：清单 id ↔ 分派器 case ↔ 标志位有没有视图读）判不住这件事，
# 所以它拿真 `AppState` 把**每一条命令都点一遍**、断言登记在案的**落点**确实发生
# （面板标志位 / 新页签 / 编辑器命令 / 状态栏说法 / 页签上的可读错误），
# 落点表与命令清单**双向对账**（新增命令没登记落点 ⇒ 判红）。
# 它不渲染界面、也不连库，跟着本脚本跑两遍（两遍都应当绿）。
#
# ## 第三批（队列 L-89 ㈡ ②，第 93 轮）：主题与字体
#
# `TestsUISnapshot/AppearanceFontProbeTests.swift` 判清单 §2 `FR-EDIT-26` 的三条人话：
# 手输一个已装的等宽族 ⇒ 生效且「当前使用」拼写正确（③）、手输非等宽 ⇒ **明确提示它不是等宽**
# 而不是静默回落（④）、SQL 预览的字形跟着字体走（⑤）。
# 造态走 `FontManager.beginHostPreference(_:)`（宿主语境覆盖，**不落盘**，与主题 / 语言同构）。
# ⑤ 是**像素**判据：面板用 `.defaultScrollAnchor(.bottom)` 渲染，于是字体那一段（默认在折线以下）
# 第一次进得了快照；判的是 SQL 预览那一行的**取样带**（`UISnapshot.band`）——
# 换族必须变、同族重跑必须逐像素相同、上方只多一句提示时必须不变。
#
# ## 第四批（队列 L-92 ㈡①，第 95 轮）：终端 `⌃C`
#
# `TestsUISnapshot/TerminalInterruptProbeTests.swift` 判的是「**非沙箱包（现在的默认与交付口径）
# 里 `⌃C` 能不能打断 `sleep 30`**」—— 清单 §0.3 第 3 条原先**要人点**，改默认非沙箱之后
# 变成机器判得住：往 PTY 喂一个 `0x03` 字节，看前台进程（`tcgetpgrp`）是否真的让开，
# 并要求它在 8 秒内发生（`⌃C` 没送到的话 `sleep` 会占满 30 秒 ⇒ 探针自己红）。
# 它用真 `TerminalPane` + 真 `forkpty` 会话；两遍都跑（沙箱标记只影响界面文案，不影响这条）。
# 边界：**没有**做「同一探针在沙箱里必红」的 A/B（见该文件头注释）。
#
# ## 第五批（队列 L-89 ㈡ ③，第 96 轮）：终端多会话页签那一行
#
# `TestsUISnapshot/TerminalTabsProbeTests.swift` 新加的三个用例判的是清单 §1 `FR-EDIT-29`
# 多会话那一行的**版面**与**落点**（前三个用例是它原有的「真开 shell 的独立性与退出 / 确认链路」）：
#   ① 版面：渲染**真工具条**（`LowerPaneTabStrip` —— 从 `LowerPaneView` 抽出来的独立视图，
#      抽出来就是为了能单独离屏渲染：整块面板一渲染会真开 shell），页签 1 个 → 3 个时
#      **左半必须变、右四分之一逐像素不变** —— 这就是「页签头在左侧、右侧按钮位置不动」的像素版；
#   ② 右侧那排按钮按**面板状态**齐备（终端 / 问题 / 折叠态三态：该有的有、**不该有的不许有**）；
#   ③ `⌘1…9` / `⌘⇧[ ⌘⇧]` / 双击改名落到**对的会话**，且**改名不动那条 PTY**（前台进程不许换人）。
# 它跟着本脚本跑两遍（沙箱标记只影响界面文案，不影响这三条）。
#
# ## 第六批（队列 L-89 ㈡ ④，第 97 轮）：大结果集滚动
#
# `TestsUISnapshot/LargeResultScrollProbeTests.swift` 判清单 §4 `FR-RES-07` 那一行
# 「查 1 万行 × 20 列，上下滚十几秒 ⇒ 不卡、内存不飙」里**能变成机器判据的那部分**：
# ① 虚拟化（物化行视图数只跟可见区域有关，1 万行与 10 万行必须同量级）；
# ② 滚动每一帧画面都在变（位置动了画面没动 = 卡死）且单帧 p50 在上界内；
# ③ 单帧成本不随总行数放大（比值判据，机器无关）；④ 重复同一轮操作常驻内存不再增长。
# 阈值全部读 `Scripts/result-scroll-baseline.json`（唯一来源，由
# `Scripts/check-result-scroll-ledger.py` 看着），文件里不写魔数。
# 它跟着本脚本跑两遍（沙箱标记只影响界面文案，不影响这四条）。
#
# ## 第七批（队列 L-89 ㈡ ⑤，第 99 轮）：跨库浏览
#
# `TestsUISnapshot/CrossDatabaseBrowseProbeTests.swift` 判清单 §5 `FR-META-10` 那一行
# 「展开非当前库的节点（对象树 / 服务器选择器）」→ 过 =「**按需建连**；失败时**给可读原因**」。
# 判据观测的是**服务端**：被测那条走真 `AppState`（与界面同一条路），另一条连接查
# `pg_stat_activity`，两条各打 `application_name` 标记 ⇒「本进程往哪个库开了几条后端」是
# 服务端的事实，不是我们自己的计数器。三条：① 只展开服务器节点 ⇒ 非当前库后端 **0**（不全量预连）；
# ② 展开非当前库的库 / schema 两级 ⇒ 该库后端恰好 **1** 条、子树里是**它自己的表**、重展开仍 1 条；
# ③ 展开不存在的库 ⇒ `ErrorPresenter.message(for:)`（对象树显示失败的唯一收口点）是人话 + 给方向，
# 而原始串确实是 `PSQLError(...)`（反向对照，防判据空转）。
# **这一批要真集群**（`Scripts/lib/test-env.sh` 的本机档；下面会起库、建两个带标记表的临时库），
# 并且**证据文件会被核对** —— 探针跳过 / 没挂上时文件不存在 ⇒ 本脚本判红（跳过 ≠ 通过）。
#
# ## 纪律
#
# · 与快照同源：要真渲染视图树、要几分钟 ⇒ **不进** `verify-all.sh`（每轮门禁不跑取证）；
# · 产物落 `.build/`（已在 `.gitignore`）：快照是**证据**，不是交付物；
# · 只读用户数据：笔记 / 外发日志指到每轮清空的临时目录（与 `make-ui-snapshots.sh` 同款），
#   探针不写用户偏好、不连任何数据库。
#
# 退出码：0 = 两遍都绿且跨清单判定成立；非 0 = 某一遍红或跨清单判定不成立。

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SWIFT="${DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
SCRATCH="${ROOT}/.build"
CACHE="${ROOT}/.build-cache"
OUT_BASE="${SCRATCH}/manual-verification-probes"
OUT_PLAIN="${OUT_BASE}/plain"
OUT_SANDBOX="${OUT_BASE}/sandbox"
SANDBOX_MARK="com.doyah.manual-verification-probe"

# 默认两族都跑：`ManualVerificationProbeTests`（B 类 ㈠：隧道表单 / SSL 收窄 / 沙箱告知）
# + `PaletteWiringProbeTests`（㈡：命令面板接线）
# + `AppearanceFontProbeTests`（㈡：主题与字体 —— 手输族之后界面说的话 + SQL 预览的字形）。
# + `TerminalInterruptProbeTests`（L-92 ㈡①：终端 `⌃C` 打断前台 `sleep 30` —— 非沙箱包的作业控制）。
# `--filter` 传的是**正则**，所以这里用 `|` 连接。
FILTER="ManualVerificationProbeTests|PaletteWiringProbeTests|AppearanceFontProbeTests|TerminalInterruptProbeTests|TerminalTabsProbeTests|LargeResultScrollProbeTests|CrossDatabaseBrowseProbeTests"
while [ $# -gt 0 ]; do
    case "$1" in
        --filter) FILTER="${2:-}"; shift 2 ;;
        *) echo "未知参数：$1（支持 --filter <片段>）"; exit 2 ;;
    esac
done

export DEVELOPER_DIR
export CLANG_MODULE_CACHE_PATH="${SCRATCH}/clang-module-cache"
export SWIFT_MODULE_CACHE_PATH="${SCRATCH}/swift-module-cache"
export DOYAH_UI_SNAPSHOT=1

# 与用户真实数据解耦：笔记 / 统一外发日志指到每轮清空的临时目录。
PROBE_DATA="${SCRATCH}/manual-verification-probe-data"
rm -rf "${PROBE_DATA}"
mkdir -p "${PROBE_DATA}/notes" "${PROBE_DATA}/egress"
export DOYAH_NOTES_DIR="${PROBE_DATA}/notes"
export DOYAH_EGRESS_LOG_DIR="${PROBE_DATA}/egress"

mkdir -p "${CACHE}" "${SCRATCH}" "${CLANG_MODULE_CACHE_PATH}" "${SWIFT_MODULE_CACHE_PATH}"
cd "${ROOT}"

# ---- 跨库浏览那一批要的**真库**（第七批）------------------------------------
#
# 判据观测的是**服务端**（`pg_stat_activity`），所以要有真集群。连接信息不在这里手抄 ——
# 走 `Scripts/lib/test-env.sh`（真库目标的唯一来源）：本机档会起集群，库名带 `doyah_probe_` 前缀，
# 两个临时库各建一张**独有**的标记表 ——「跨库展开列出来的是不是它自己的表」才判得动。
source "${ROOT}/Scripts/lib/test-env.sh"
doyah_test_env_start_cluster
echo
echo "==> 跨库浏览判据的真库目标"
doyah_test_env_summary

PROBE_PG_CURRENT="$(doyah_test_env_scratch_name crossdb_main)"
PROBE_PG_OTHER="$(doyah_test_env_scratch_name crossdb_side)"
PROBE_PG_MISSING="$(doyah_test_env_scratch_name crossdb_missing)"
PROBE_MARKER_CURRENT="crossdb_marker_main"
PROBE_MARKER_OTHER="crossdb_marker_side"

probe_psql() {  # $1 = 库；$2 = SQL（只跑一条；出错即停）
    "${DOYAH_TEST_PG_BIN}/psql" -h "${DOYAH_TEST_PGHOST}" -p "${DOYAH_TEST_PGPORT}" \
        -U "${DOYAH_TEST_PGUSER}" -d "$1" -q -v ON_ERROR_STOP=1 -c "$2" >/dev/null
}

# 建两个临时库（DROP + CREATE，幂等）+ 各自的标记表；第三个库**故意不建**（判失败态用）。
doyah_test_env_scratch_db crossdb_main >/dev/null
probe_psql "${PROBE_PG_CURRENT}" "CREATE TABLE ${PROBE_MARKER_CURRENT}(id int);"
doyah_test_env_scratch_db crossdb_side >/dev/null
probe_psql "${PROBE_PG_OTHER}" "CREATE TABLE ${PROBE_MARKER_OTHER}(id int);"
"${DOYAH_TEST_PG_BIN}/psql" -h "${DOYAH_TEST_PGHOST}" -p "${DOYAH_TEST_PGPORT}" \
    -U "${DOYAH_TEST_PGUSER}" -d "${DOYAH_TEST_ADMIN_DB}" -q \
    -c "DROP DATABASE IF EXISTS \"${PROBE_PG_MISSING}\" WITH (FORCE);" >/dev/null 2>&1

export DOYAH_PROBE_PGHOST="${DOYAH_TEST_PGHOST}"
export DOYAH_PROBE_PGPORT="${DOYAH_TEST_PGPORT}"
export DOYAH_PROBE_PGUSER="${DOYAH_TEST_PGUSER}"
export DOYAH_PROBE_PGCURRENT="${PROBE_PG_CURRENT}"
export DOYAH_PROBE_PGOTHER="${PROBE_PG_OTHER}"
export DOYAH_PROBE_PGMISSING="${PROBE_PG_MISSING}"
export DOYAH_PROBE_PGMARKER_CURRENT="${PROBE_MARKER_CURRENT}"
export DOYAH_PROBE_PGMARKER_OTHER="${PROBE_MARKER_OTHER}"
echo "  · 跨库探针：当前库 ${PROBE_PG_CURRENT}（有 ${PROBE_MARKER_CURRENT}）"
echo "              非当前库 ${PROBE_PG_OTHER}（有 ${PROBE_MARKER_OTHER}）｜不存在的库 ${PROBE_PG_MISSING}"

run_pass() {  # $1 = 输出目录；$2 = 该遍要设的 APP_SANDBOX_CONTAINER_ID（空 = 不设）
    local out="$1" mark="$2" label="$3"
    rm -rf "${out}"
    mkdir -p "${out}"
    echo
    echo "==> ${label}（快照目录 ${out}）"
    if [ -n "${mark}" ]; then
        APP_SANDBOX_CONTAINER_ID="${mark}" DOYAH_SNAPSHOT_DIR="${out}" "${SWIFT}" test \
            --disable-sandbox \
            --package-path . \
            --cache-path "${CACHE}" \
            --scratch-path "${SCRATCH}" \
            --manifest-cache local \
            -Xswiftc -disable-sandbox \
            --filter "${FILTER}"
    else
        DOYAH_SNAPSHOT_DIR="${out}" "${SWIFT}" test \
            --disable-sandbox \
            --package-path . \
            --cache-path "${CACHE}" \
            --scratch-path "${SCRATCH}" \
            --manifest-cache local \
            -Xswiftc -disable-sandbox \
            --filter "${FILTER}"
    fi
}

run_pass "${OUT_PLAIN}" "" "第一遍：普通构建（不设沙箱标记）"
run_pass "${OUT_SANDBOX}" "${SANDBOX_MARK}" "第二遍：带沙箱标记 APP_SANDBOX_CONTAINER_ID=${SANDBOX_MARK}"

echo
echo "==> 跨清单判定：环境（沙箱标记）确实改变了界面"
python3 - "${OUT_PLAIN}/manifest.json" "${OUT_SANDBOX}/manifest.json" <<'PY'
import json
import sys

plain_path, sandbox_path = sys.argv[1], sys.argv[2]


def load(path):
    with open(path, encoding="utf-8") as handle:
        payload = json.load(handle)
    return {item["name"]: set(item["localizedStrings"]) for item in payload["snapshots"]}


plain, sandbox = load(plain_path), load(sandbox_path)

if set(plain) != set(sandbox):
    print(f"✗ 两遍产出的快照集合不同：{sorted(set(plain) ^ set(sandbox))}")
    sys.exit(1)

# 这一组图判的是「沙箱构建多一句说明」：逐张比，沙箱那遍必须**恰好多一句**，
# 且那一句里必须点出 ssh 与沙箱（否则只是"多了一行别的字"）。
target = "manual-check-ssh-sandbox-notice"
if f"{target}-zh" not in sandbox:
    print(f"✗ 清单里没有 {target}-zh —— 探针没跑（检查 --filter / DOYAH_UI_SNAPSHOT）")
    sys.exit(1)

failures = []
for suffix in ("-zh", "-en"):
    name = f"{target}{suffix}"
    extra = sandbox[name] - plain[name]
    missing = plain[name] - sandbox[name]
    if len(extra) != 1:
        failures.append(f"{name}：沙箱那遍应当**恰好多 1 句**，实际多 {len(extra)} 句 {sorted(extra)}")
        continue
    only = next(iter(extra))
    if "ssh" not in only:
        failures.append(f"{name}：多出来的那句没有点明 ssh：「{only}」")
    if missing:
        failures.append(f"{name}：普通那遍多出了 {sorted(missing)}（说明判据方向反了）")

if failures:
    for item in failures:
        print(f"✗ {item}")
    sys.exit(1)

print("✓ 两遍产出成对；沙箱那一遍逐语言恰好多一句 ssh 沙箱说明；普通那一遍没有它")
print(f"✓ 本轮产出的快照：{len(sandbox)} 张（两遍各一份）")
PY

echo
echo "==> 跨库浏览那条：两遍都**真跑过**了吗（跳过 ≠ 通过）"
python3 - "${OUT_PLAIN}" "${OUT_SANDBOX}" <<'PY'
import json
import os
import sys

CASES = {
    "serverNodeListing": [
        ("currentBackends", 1),
        ("otherBackends", 0),
    ],
    "crossDatabaseOnDemand": [
        ("otherBackendsAfterListingDatabase", 1),
        ("otherBackendsAfterSchema", 1),
        ("otherBackendsAfterRepeat", 1),
        ("otherTableMarkerSeen", True),
        ("currentMarkerLeakedIntoOther", False),
    ],
    "missingDatabaseReadable": [
        ("rawIsDriverDump", True),
    ],
}


def load(directory, case):
    path = os.path.join(directory, f"cross-database-evidence-{case}.json")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


failures = []
for directory in sys.argv[1:]:
    for case, expectations in CASES.items():
        payload = load(directory, case)
        if payload is None:
            failures.append(
                f"{os.path.basename(directory)}：没有 {case} 的证据文件 —— 探针没真跑（跳过不算通过）"
            )
            continue
        for key, expected in expectations:
            actual = payload.get(key)
            if actual != expected:
                failures.append(f"{os.path.basename(directory)}/{case}：{key} 期望 {expected}、实测 {actual}")
        if "databasesWithBackends" in payload and payload["databasesWithBackends"] != [payload["currentDatabase"]]:
            failures.append(
                f"{os.path.basename(directory)}/{case}：展开服务器节点后连过的库不止当前库："
                f"{payload['databasesWithBackends']}"
            )
        shown = payload.get("shownMessage")
        if shown is not None and ("PSQLError(" in shown or "serverInfo:" in shown):
            failures.append(f"{os.path.basename(directory)}/{case}：界面那句话里出现了驱动转储：{shown!r}")

if failures:
    for item in failures:
        print(f"✗ {item}")
    sys.exit(1)
print("✓ 两遍都真跑过：非当前库按需恰好 1 条 / 展开前 0 条 / 子树来自那个库 / 失败给可读原因")
PY

echo
echo "==> 完成：证据在 ${OUT_BASE}/（每张图另有中英两份，逐张断言见 ManualVerificationProbeTests）"
echo "    「待人工验收清单」里被机器化的行：§10.6 隧道表单字段显隐 / §10.6 沙箱告知 / §10.7 R-53 SSL 收窄说明"
echo "    ＋ §2 FR-EDIT-25 命令面板接线（PaletteWiringProbeTests：每条命令点一遍、断言落点）"
echo "    ＋ §2 FR-EDIT-26 主题与字体（AppearanceFontProbeTests：手输族的三档说法 + SQL 预览取样带）"
echo "    ＋ §0.3 第 3 条 终端 ⌃C（TerminalInterruptProbeTests：喂 0x03 看前台 sleep 让不让开）"
echo "    ＋ §1 FR-EDIT-29 多会话那一行的版面与落点（TerminalTabsProbeTests 后三个用例：左半变 / 右四分之一逐像素不变、"
echo "       右侧按钮按状态齐备、⌘1…9 与 ⌘⇧[ ⌘⇧] 与改名落到对的会话）"
echo "    ＋ §4 FR-RES-07 大结果集滚动（LargeResultScrollProbeTests：虚拟化 / 帧在变 / 单帧成本不随总行数放大 / 内存不飙）"
echo "    ＋ §5 FR-META-10 跨库浏览（CrossDatabaseBrowseProbeTests：按需建连 / 子树来自那个库 / 失败给可读原因）"
