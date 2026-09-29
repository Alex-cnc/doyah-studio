#!/bin/bash
set -euo pipefail

# 界面快照：把**真视图树**离屏渲染成 PNG，供助理逐张判定（队列 L-01）。
#
#   ./Scripts/make-ui-snapshots.sh              # 渲染全部，产物在 .build/ui-snapshots/
#   DOYAH_SNAPSHOT_DIR=/tmp/x ./Scripts/make-ui-snapshots.sh
#   ./Scripts/make-ui-snapshots.sh --filter testActivityBarAcrossEditions   # 只渲染一组
#   ↑ 筛选跑的产物落在 `.build/ui-snapshots/filtered/<筛子>/`，**不动**全量那一份
#     （第 97 轮起：同一台机器上人工点验与循环交错跑时，全量那份不许被筛选跑顶掉）
#
# **全量跑凭证**（第 98 轮）：全量跑（不给窄筛子）在最后把张数 / 组数 + 清单 sha256 写进
# `.build/ui-snapshots/full-run/`（`manifest.json` + `record.json`）—— `Scripts/check-doc-numbers.py`
# 的「快照张数」只读这一份。理由：测量源的写者只能有一个；`.build/ui-snapshots/manifest.json`
# 是共享产物，谁都可能覆盖它（第 97 轮实测：判据因此绿红反复）。筛选跑不写凭证。
#
# 为什么不进 `verify-all.sh`：快照是**取证工具**，不是回归门禁 —— 塞进每轮门禁只会拖慢门禁。
# 它证明的是"界面长这样"，用例本身另有断言（档位生效 / 非空白）。
#
# **队列 L-13（2026-09-27）起：每张图都出中英两份**（`-zh` / `-en`），语言是**宿主参数**
# （`UISnapshot.writeBothLanguages` → `LocalizationManager.beginHostLanguage`：只覆盖、不落盘，
# 不动用户偏好）。脚本末尾会跑 `Scripts/check-ui-snapshot-languages.py` 把两件事判住：
# 成对齐全 + **语言确实到了像素上**（未注册为语言无关的图，中英两张必须逐字节不同）。
#
# 前置：`TestsUISnapshot/` 是独立 test target，依赖 `DoyahStudioApp`（SwiftPM 允许测试目标依赖可执行目标），
# 所以这里不碰生产代码、也不给 App 开任何测试后门。

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SWIFT="${DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
SCRATCH="${ROOT}/.build"
CACHE="${ROOT}/.build-cache"
OUT="${DOYAH_SNAPSHOT_DIR:-${SCRATCH}/ui-snapshots}"

export DEVELOPER_DIR
export CLANG_MODULE_CACHE_PATH="${SCRATCH}/clang-module-cache"
export SWIFT_MODULE_CACHE_PATH="${SCRATCH}/swift-module-cache"
export DOYAH_UI_SNAPSHOT=1
mkdir -p "${SCRATCH}" "${CACHE}" "${CLANG_MODULE_CACHE_PATH}" "${SWIFT_MODULE_CACHE_PATH}" "${OUT}"

# **快照与用户真实数据解耦**（队列 L-16 第 5 批）：笔记与统一外发日志各有一条
# **产品自带的**数据家覆盖口子（不是测试后门），这里把两者指到一个**每轮清空**的临时目录 ——
# 于是「一条都没有」是**每次都能复现的态**，而不是「本机这次凑巧没有」。
# 实测动机：本机真实数据里笔记有 1 条、外发日志 60 KB，不隔离就**永远**拍不到这两张空态。
# 两个一次性迁移在覆盖生效时都**主动让路**（`NoteStoreMigration` / `NoteLibraryMigration`），
# 所以整轮渲染不写、也不读用户的真实笔记与本机外发日志。
SNAPSHOT_DATA="${SCRATCH}/ui-snapshot-data"
rm -rf "${SNAPSHOT_DATA}"
mkdir -p "${SNAPSHOT_DATA}/notes" "${SNAPSHOT_DATA}/egress"
export DOYAH_NOTES_DIR="${SNAPSHOT_DATA}/notes"
export DOYAH_EGRESS_LOG_DIR="${SNAPSHOT_DATA}/egress"

cd "${ROOT}"

# 渲染前清一遍旧图：留着上一轮的文件，`ls` 会把"这次没渲染出来的"也列成绿。
rm -f "${OUT}"/*.png "${OUT}/manifest.json"

FILTER="UISnapshotTests"
if [ "${1:-}" = "--filter" ] && [ -n "${2:-}" ]; then
    FILTER="$2"
fi

# **筛选跑不许覆盖全量跑的那一份**（第 97 轮实测的真现场）：`--filter` 只渲染一部分，
# 但默认输出目录与全量跑是同一个 ⇒ 谁后跑谁的 `manifest.json` 留在那儿，而
# `Scripts/check-doc-numbers.py` 的「快照张数」正是读这一份 ⇒ **同一台机器上两个会话交错跑**
# （人工点验跑一组 + 循环跑全量）会让它一会儿 218 张、一会儿 194 张，判据红得没道理
# （实测：全量两次都是 218 张 / 109 组，筛选跑留下 194 张 / 97 组）。
# 于是：给了 `--filter` 且**没**显式给 `DOYAH_SNAPSHOT_DIR` 时，落到
# `.build/ui-snapshots/filtered/<筛子>/` —— 全量那一份只有全量跑会动。
# `DOYAH_SNAPSHOT_DIR` 仍然优先（显式指定就照指定的来）。
if [ -z "${DOYAH_SNAPSHOT_DIR:-}" ] && [ "${FILTER}" != "UISnapshotTests" ]; then
    OUT="${SCRATCH}/ui-snapshots/filtered/$(printf '%s' "${FILTER}" | tr -c 'A-Za-z0-9._-' '-')"
    mkdir -p "${OUT}"
    rm -f "${OUT}"/*.png "${OUT}/manifest.json"
    echo "ℹ️ 这是筛选跑（--filter ${FILTER}）⇒ 产物落在 ${OUT}（不动全量那一份 ${SCRATCH}/ui-snapshots/）"
fi

echo "==> 渲染界面快照 → ${OUT}"
"${SWIFT}" test \
    --disable-sandbox \
    --package-path . \
    --cache-path "${CACHE}" \
    --scratch-path "${SCRATCH}" \
    --manifest-cache local \
    -Xswiftc -disable-sandbox \
    --filter "${FILTER}"

echo
echo "==> 产物清单"
python3 - "${OUT}" <<'PY'
import json
import os
import sys

out = sys.argv[1]
manifest = os.path.join(out, "manifest.json")
if os.path.exists(manifest):
    with open(manifest, encoding="utf-8") as handle:
        payload = json.load(handle)
    print(f"生成时间：{payload.get('generatedAt')}")
    for item in payload.get("snapshots", []):
        print(f"  · {item['name']:<28} {item['width']}×{item['height']}px "
              f"{item['bytes']:>7} B  内容占比 {item['contentRatio']:.3f}  {item['scheme']}")
    print(f"共 {len(payload.get('snapshots', []))} 张")
else:
    print("⚠️ 没有 manifest.json —— 用例可能全被跳过（检查 DOYAH_UI_SNAPSHOT）")

files = sorted(f for f in os.listdir(out) if f.endswith(".png"))
print("PNG：" + "、".join(files) if files else "⚠️ 一张 PNG 都没有")
PY

# 语言覆盖（队列 L-13）：每张图都有中英两份，且**语言真的到了像素上**。
# 为什么放在这里而不是 verify-all.sh：快照是取证工具、不进每轮门禁 ——
# 但**取证那一刻**必须把这件事判住（两份都生成了 ≠ 语言进了像素；第 10/11 轮两次
# 「判据太松」就是这么漏过去的）。判据与理由见 Scripts/check-ui-snapshot-languages.py。
echo
echo "==> 语言覆盖（中英成对 + 语言到像素）"
python3 Scripts/check-ui-snapshot-languages.py --manifest "${OUT}/manifest.json"

# ── 全量跑凭证（第 98 轮）：**判据的输入必须只有一个写者** ──
# 真现场：`.build/ui-snapshots/manifest.json` 是**共享产物** —— 本机人工点验会话跑筛选子集时也往那儿写，
# 于是它一会儿 218 张 / 109 组、一会儿 194 张 / 97 组（第 97 轮实测：16:04:34 / 16:08:19 / 16:12:04 /
# 16:15:30 四次被顶掉），而 `Scripts/check-doc-numbers.py` 的「快照张数」正是读那一份 ⇒
# 门禁第 4 项绿红反复、**两边都没做错事**。筛选跑的目录隔离只是止痛（对方不走这个脚本就白搭）。
# 根治 = 换测量源：**只有全量跑**（`--filter` 不给窄筛子）会写 `.build/ui-snapshots/full-run/`
# （`manifest.json` + `record.json`：张数 / 组数 / 清单 sha256 / 写明这是一次全量跑），
# 判据只读这一份并与记录逐项对账；此后谁再往那一份共享清单里写什么都不影响判据。
# 判据那一侧认的是同一个目录串（改名会让它当场点名「脱钩」，不许静默跳过）。
if [ "${FILTER}" = "UISnapshotTests" ]; then
    echo
    echo "==> 全量跑凭证 → ${SCRATCH}/ui-snapshots/full-run/（判据的「快照张数」只读这一份）"
    python3 - "${OUT}" "${SCRATCH}/ui-snapshots/full-run" "${FILTER}" <<'PY'
import hashlib
import json
import os
import pathlib
import shutil
import sys

out = pathlib.Path(sys.argv[1])
full = pathlib.Path(sys.argv[2])
flt = sys.argv[3]
source = out / "manifest.json"
if not source.exists():
    print("✗ 全量跑没有 manifest.json（用例可能全被跳过 —— 检查 DOYAH_UI_SNAPSHOT）⇒ 不写凭证")
    sys.exit(1)
payload = json.loads(source.read_text(encoding="utf-8"))
snapshots = payload.get("snapshots") or []
if not snapshots:
    print("✗ 全量跑的清单里一条快照都没有（零命中不许当凭证）⇒ 不写")
    sys.exit(1)
bases = set()
for item in snapshots:
    name = item.get("name") or ""
    for suffix in ("-zh", "-en"):
        if name.endswith(suffix):
            name = name[: -len(suffix)]
            break
    bases.add(name)
full.mkdir(parents=True, exist_ok=True)
target = full / "manifest.json"
shutil.copyfile(source, target)
record = {
    "writtenBy": "Scripts/make-ui-snapshots.sh（全量跑：filter=%s）" % flt,
    "filter": flt,
    "generatedAt": payload.get("generatedAt"),
    "snapshotCount": len(snapshots),
    "groupCount": len(bases),
    "pngCount": len([f for f in os.listdir(out) if f.endswith(".png")]),
    "pngDir": str(out),
    "manifestSha256": hashlib.sha256(target.read_bytes()).hexdigest(),
}
(full / "record.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"  · {record['snapshotCount']} 张 / {record['groupCount']} 组 ⇒ {full}")
PY
fi
