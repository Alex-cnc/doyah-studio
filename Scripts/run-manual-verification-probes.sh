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

FILTER="ManualVerificationProbeTests"
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
echo "==> 完成：证据在 ${OUT_BASE}/（每张图另有中英两份，逐张断言见 ManualVerificationProbeTests）"
echo "    「待人工验收清单」里被本轮机器化的行：§10.6 隧道表单字段显隐 / §10.6 沙箱告知 / §10.7 R-53 SSL 收窄说明"
