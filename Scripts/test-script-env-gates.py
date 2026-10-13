#!/usr/bin/env python3
"""负例 + 行为验证：`Scripts/check-script-env-parameterization.py` 与 `Scripts/lib/test-env.sh`。

两件事，一件都不能少：

**A. 门禁的负例**（写坏 → 门禁必须报红 → 还原）：门禁绿着不代表它看得见问题 ——
本工程的规矩是「红要能红出来」（L-04 查出的"失败只记进没人读的变量"就是反面例子）。

**B. lib 的行为**（不需要数据库）：`test-env.sh` 是**唯一**决定「这轮连哪台库」的地方，
它的分支必须是机械可验的 —— 尤其是「只给一半连接信息时不许猜」，那是过渡期最容易出事的地方。

用法：`python3 Scripts/test-script-env-gates.py`
"""

import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "Scripts"
GATE = SCRIPTS / "check-script-env-parameterization.py"
LIB = SCRIPTS / "lib" / "test-env.sh"
MANIFEST = SCRIPTS / "real-db-scripts.txt"
BYPASS = SCRIPTS / "remote-bypass-scripts.json"
SUBDIR = SCRIPTS / "shell-face-subdirs.json"
BASELINE = SCRIPTS / "real-db-evidence-baseline.json"

SAMPLE = SCRIPTS / "test-er-diagram.sh"
passed = []
failed = []


def record(ok, label, detail=""):
    (passed if ok else failed).append(label)
    print(f"  {'✅' if ok else '❌'} {label}" + (f"  —— {detail}" if detail and not ok else ""))


def run_gate():
    proc = subprocess.run([sys.executable, str(GATE), "--json"], capture_output=True, text=True)
    try:
        return proc.returncode, json.loads(proc.stdout)
    except json.JSONDecodeError:
        return proc.returncode, {"problems": [proc.stdout + proc.stderr]}


def expect_gate_red(label, needle=""):
    code, data = run_gate()
    problems = "；".join(data.get("problems", []))
    if code == 0:
        record(False, label, "门禁没报红")
        return
    if needle and needle not in problems:
        record(False, label, f"报红了但没提到「{needle}」：{problems[:200]}")
        return
    record(True, label)


def expect_gate_green(label):
    code, data = run_gate()
    if code != 0:
        record(False, label, "；".join(data.get("problems", []))[:300])
        return
    record(True, label)


# ---------------------------------------------------------------- A. 门禁负例

def gate_negatives():
    print("\n== A) 门禁负例（写坏 → 报红 → 还原）")

    with tempfile.TemporaryDirectory() as tmp:
        text = SAMPLE.read_text(encoding="utf-8")

        # N-01 端口又写死回脚本
        SAMPLE.write_text(text.replace('PORT="${DOYAH_TEST_PGPORT}"', "PORT=55433"), encoding="utf-8")
        expect_gate_red("N-01 脚本里又写死本机端口 55433 → 门禁报红", "55433")
        SAMPLE.write_text(text, encoding="utf-8")

        # N-02 去掉 source 行
        SAMPLE.write_text(text.replace('source "$(cd "$(dirname "$0")" && pwd)/lib/test-env.sh"', ""),
                          encoding="utf-8")
        expect_gate_red("N-02 去掉 source lib 那一行 → 门禁报红", "source")
        SAMPLE.write_text(text, encoding="utf-8")

        # N-03 不再打印目标摘要
        SAMPLE.write_text(text.replace("doyah_test_env_summary", "# 不打印了"), encoding="utf-8")
        expect_gate_red("N-03 不再打印「连的是谁」→ 门禁报红", "目标摘要")
        SAMPLE.write_text(text, encoding="utf-8")

        # N-04 账号 / 维护库又写死
        SAMPLE.write_text(text.replace("doyah_test_env_export_connection",
                                       'export PGUSER=postgres PGDATABASE=postgres'), encoding="utf-8")
        expect_gate_red("N-04 又写死 PGUSER=postgres / PGDATABASE=postgres → 门禁报红", "写死的账号")
        SAMPLE.write_text(text, encoding="utf-8")

        # N-05 新脚本（不在清单里）里写死 217
        rogue = SCRIPTS / "test-env-gate-rogue.sh"
        rogue.write_text('#!/bin/bash\nexport PGHOST=192.168.5.217 PGUSER=zxvmax\n',
                         encoding="utf-8")
        expect_gate_red("N-05 未登记的新脚本里写死 217 → 门禁报红", "不在 Scripts/real-db-scripts.txt")
        rogue.unlink()

        # N-06 把字面量从 lib 里搬走（"删干净"式作弊）
        lib_text = LIB.read_text(encoding="utf-8")
        LIB.write_text(lib_text.replace("_doyah_test_profile_port=55434", "_doyah_test_profile_port=0"),
                       encoding="utf-8")
        expect_gate_red("N-06 lib 里的档位端口被改掉 → 门禁报红（正面判据挡住了「删干净」）", "slowquery")
        LIB.write_text(lib_text, encoding="utf-8")

        # N-07 清单里加一条不存在的脚本
        MANIFEST.write_text(MANIFEST.read_text(encoding="utf-8") + "test-no-such-script\n",
                            encoding="utf-8")
        expect_gate_red("N-07 清单登记了不存在的脚本 → 门禁报红", "不存在")
        MANIFEST.write_text(MANIFEST.read_text(encoding="utf-8").replace("test-no-such-script\n", ""),
                            encoding="utf-8")

        # ---- 判据 ⑤（旁路 217 必须登记）：四条都要能红出来 ----
        # N-08 新写一处旁路、却没进旁路台账（「悄悄扩散」那条路）
        SAMPLE.write_text(text.replace('PORT="${DOYAH_TEST_PGPORT}"',
                                       'PORT="${DOYAH_TEST_PGPORT}"\n'
                                       'export PGHOST="${DOYAH_TEST_REMOTE_HOST}"'),
                          encoding="utf-8")
        expect_gate_red("N-08 脚本里新写一处 217 旁路（未登记）→ 门禁报红", "旁路")
        SAMPLE.write_text(text, encoding="utf-8")

        registry_text = BYPASS.read_text(encoding="utf-8")

        # N-09 台账里登记一个**已经不再旁路**的脚本（陈旧登记 ⇒ 现状会被误判）
        registry = json.loads(registry_text)
        registry["entries"][0]["script"] = "test-er-diagram.sh"
        BYPASS.write_text(json.dumps(registry, ensure_ascii=False, indent=2), encoding="utf-8")
        expect_gate_red("N-09 旁路台账登记了已不再旁路的脚本 → 门禁报红（陈旧）", "销账")
        BYPASS.write_text(registry_text, encoding="utf-8")

        # N-10 台账里的理由写空（「登记了但没说为什么」= 没登记）
        registry = json.loads(registry_text)
        registry["entries"][0]["reason"] = "   "
        BYPASS.write_text(json.dumps(registry, ensure_ascii=False, indent=2), encoding="utf-8")
        expect_gate_red("N-10 旁路台账里理由写空 → 门禁报红", "没写理由")
        BYPASS.write_text(registry_text, encoding="utf-8")

        # N-11 台账本身写坏（不是合法 JSON）—— 不许静默通过
        BYPASS.write_text("{ 这不是 JSON", encoding="utf-8")
        expect_gate_red("N-11 旁路台账不是合法 JSON → 门禁报红（解析失败不静默）", "不是合法 JSON")
        BYPASS.write_text(registry_text, encoding="utf-8")

        # ---- N-12~N-22：合册 T-20261013-027 第 19 轮（原单 T-20261010-057 ㈠~㈦）----
        probe = SCRIPTS / "zzprobe-comment.sh"
        sub = SCRIPTS / "zzprobe-subdir"

        # N-12 ㈠ 注释里提旧端口（顶层非清单脚本）⇒ 判绿（旧版 rc=1，与真写死同一条话术）
        probe.write_text('#!/bin/bash\n# 迁移说明：旧端口 55433 已废弃，勿再使用\n', encoding="utf-8")
        expect_gate_green("N-12 注释里提过旧端口 55433 → 判绿（提及不算写死）")

        # N-13 ㈠ 字符串字面量里提旧端口 ⇒ 判绿（旧版 rc=1）
        probe.write_text('#!/bin/bash\necho "端口 55433 见文档"\n', encoding="utf-8")
        expect_gate_green("N-13 字符串里提过旧端口 55433 → 判绿")

        # N-14 ㈠对照 不许削软：同一脚本真在代码行写死 ⇒ 仍判红并点名
        probe.write_text('#!/bin/bash\nPORT=55433\n', encoding="utf-8")
        expect_gate_red("N-14 对照：真在代码行写死 PORT=55433 → 仍判红（剥注释/字符串没削软判据）", "55433")

        # N-15 ㈡ 假绿：清单脚本的真 source / 摘要调用被**注释掉**（字面量留在注释里）⇒ 判红
        SAMPLE.write_text(text.replace('source "$(cd "$(dirname "$0")" && pwd)/lib/test-env.sh"',
                                       '# source "$(cd "$(dirname "$0")" && pwd)/lib/test-env.sh"')
                              .replace("doyah_test_env_summary", "# doyah_test_env_summary"),
                          encoding="utf-8")
        expect_gate_red("N-15 source 与摘要调用被注释掉（字面量留在注释里）→ 判红（旧版 rc=0 假绿）", "source")
        SAMPLE.write_text(text, encoding="utf-8")

        # N-16 ㈢ 面·子目录：未登记的子目录里写死端口 ⇒ 判红（旧版 rc=0、连计数都不动）
        sub.mkdir(exist_ok=True)
        (sub / "zzprobe_face.sh").write_text('#!/bin/bash\nPORT=55433\n', encoding="utf-8")
        expect_gate_red("N-16 未登记子目录里写死 55433 → 判红（旧版面外，rc=0）", "55433")
        (sub / "zzprobe_face.sh").unlink()
        sub.rmdir()

        # N-17 ㈣ 面·账号：清单外脚本写死账号 / 库名 ⇒ 判红（旧版 rc=0）
        probe.write_text('#!/bin/bash\nexport PGUSER=postgres PGDATABASE=postgres\n', encoding="utf-8")
        expect_gate_red("N-17 清单外脚本写死 PGUSER=postgres / PGDATABASE=postgres → 判红", "写死的账号")
        probe.unlink()

        # N-18 ㈤ 判据④ 缺件：挪走证据基线 ⇒ 判红（旧版 rc=0 静默跳过）
        stash = BASELINE.with_name(BASELINE.name + ".zzprobe")
        BASELINE.rename(stash)
        try:
            expect_gate_red("N-18 证据基线缺件 → 判红（旧版无 else、静默跳过）", BASELINE.name)
        finally:
            stash.rename(BASELINE)

        # N-19 ㈥ 假阳·行尾注释：行尾注释里提旁路 token ⇒ 判绿（旧版 rc=1）
        probe.write_text('#!/bin/bash\necho ok  # 参考 DOYAH_TEST_REMOTE_HOST\n', encoding="utf-8")
        expect_gate_green("N-19 行尾注释里提 DOYAH_TEST_REMOTE_* → 判绿")
        probe.unlink()

        # N-20 ㈦ 假绿·lib 行尾注释：档位端口只留在行尾注释里 ⇒ 判红（旧版 rc=0 假绿）
        LIB.write_text(lib_text.replace("_doyah_test_profile_port=55434",
                                        "_doyah_test_profile_port=0  # 旧值 _doyah_test_profile_port=55434"),
                       encoding="utf-8")
        expect_gate_red("N-20 lib 档位端口只在行尾注释里 → 判红（旧版 rc=0 假绿）", "slowquery")
        LIB.write_text(lib_text, encoding="utf-8")

        # N-21 反向臂：在册且 exempt 的子目录同样内容 ⇒ 判绿（证明登记表真的在生效，不是摆设）
        registry_text = SUBDIR.read_text(encoding="utf-8")
        registry = json.loads(registry_text)
        sub.mkdir()
        (sub / "zzprobe_face.sh").write_text('#!/bin/bash\nPORT=55433\n', encoding="utf-8")
        registry["entries"].append({"dir": "zzprobe-subdir", "exempt": True, "reason": "反向臂：临时豁免"})
        SUBDIR.write_text(json.dumps(registry, ensure_ascii=False, indent=2), encoding="utf-8")
        expect_gate_green("N-21 在册豁免的子目录里同样写死 55433 → 判绿（登记表生效）")
        SUBDIR.write_text(registry_text, encoding="utf-8")
        (sub / "zzprobe_face.sh").unlink()
        sub.rmdir()

        # N-22 反向臂：子目录在册却没有 .sh ⇒ 死登记判红（陈旧登记与漏登记一样要命）
        registry = json.loads(registry_text)
        registry["entries"].append({"dir": "zzprobe-ghost", "exempt": True, "reason": "反向臂：死的"})
        SUBDIR.write_text(json.dumps(registry, ensure_ascii=False, indent=2), encoding="utf-8")
        expect_gate_red("N-22 面登记表登记了没有 .sh 的子目录 → 判红（死登记）", "死登记")
        SUBDIR.write_text(registry_text, encoding="utf-8")

    expect_gate_green("还原后门禁全绿")


# ---------------------------------------------------------------- B. lib 行为

PROBE = """{extra}source "{lib}"
echo "MODE=${{DOYAH_TEST_MODE}}"
echo "HOST=${{DOYAH_TEST_PGHOST}} PORT=${{DOYAH_TEST_PGPORT}} USER=${{DOYAH_TEST_PGUSER}} DB=${{DOYAH_TEST_PGDATABASE}}"
echo "BIN=${{DOYAH_TEST_PG_BIN}} DATADIR=${{DOYAH_TEST_LOCAL_DATADIR}} ADMIN=${{DOYAH_TEST_ADMIN_DB}}"
"""


def probe(env=None, extra="", after=""):
    """extra 在 source **之前**（脚本「报到」与档位声明就是那个位置），after 在之后。"""
    with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False, encoding="utf-8") as handle:
        handle.write(PROBE.format(lib=LIB, extra=extra) + after)
        path = handle.name
    base = {k: v for k, v in os.environ.items()
            if not k.startswith(("DOYAH_TEST_", "PG", "TEST_PGPORT", "PGSERVER_"))}
    base["PATH"] = os.environ.get("PATH", "/usr/bin:/bin")
    if env:
        base.update(env)
    proc = subprocess.run(["/bin/bash", path], capture_output=True, text=True, env=base, cwd=str(ROOT))
    os.unlink(path)
    return proc.returncode, proc.stdout + proc.stderr


REMOTE_ENV = {
    "DOYAH_TEST_PGHOST": "192.168.5.217",
    "DOYAH_TEST_PGPORT": "5432",
    "DOYAH_TEST_PGUSER": "doyah",
    "DOYAH_TEST_PGDATABASE": "doyah_test",
}


def lib_behavior():
    print("\n== B) lib 行为（不需要数据库）")

    code, out = probe()
    record(code == 0 and "MODE=local" in out and "PORT=55433" in out
           and "DB=doyah_manual_test" in out and "ADMIN=postgres" in out,
           "B-01 什么都不给 → 本机过渡模式（55433 / doyah_manual_test）", out.strip()[:160])

    code, out = probe({"DOYAH_TEST_LOCAL_PROFILE": "slowquery"})
    record(code == 0 and "PORT=55434" in out and "pgdata-slowquery" in out,
           "B-02 slowquery 档 → 55434 + 自己的数据目录", out.strip()[:160])

    code, out = probe({"DOYAH_TEST_LOCAL_PROFILE": "querytest"})
    record(code == 0 and "PORT=55432" in out and "pgdata-querytest" in out,
           "B-03 querytest 档 → 55432 + 外部数据目录", out.strip()[:160])

    code, out = probe({"DOYAH_TEST_LOCAL_PROFILE": "no-such-profile"})
    record(code == 78, "B-04 未知档位 → 拒绝开工（exit 78）", out.strip()[:160])

    code, out = probe(REMOTE_ENV)
    record(code == 78 and "报到" in out,
           "B-05 给齐四项但脚本没报到 → 拒绝开工（不制造假红）", out.strip()[:160])

    code, out = probe(REMOTE_ENV, "DOYAH_TEST_SCRIPT_READY_FOR_REMOTE=1\n")
    record(code == 0 and "MODE=remote" in out and "BIN=" in out and "192.168.5.217" in out,
           "B-06 报到的脚本 + 四项齐全 → 远程模式，且本机二进制为空", out.strip()[:200])

    code, out = probe({"DOYAH_TEST_PGHOST": "192.168.5.217"})
    record(code == 78 and "还缺" in out and "DOYAH_TEST_PGUSER" in out and "DOYAH_TEST_PGDATABASE" in out,
           "B-07 只给一半 → 拒绝并**点名**缺哪几项（不猜、不回落本机）", out.strip()[:200])

    business = dict(REMOTE_ENV, DOYAH_TEST_PGDATABASE="zxvmax")
    code, out = probe(business, "DOYAH_TEST_SCRIPT_READY_FOR_REMOTE=1\n")
    record(code == 77 and "业务库" in out,
           "B-08 远程模式下指向业务库 zxvmax → 安全拒绝（exit 77，SRS §0.9 E3）", out.strip()[:200])

    maintenance = dict(REMOTE_ENV, DOYAH_TEST_PGDATABASE="postgres")
    code, out = probe(maintenance, "DOYAH_TEST_SCRIPT_READY_FOR_REMOTE=1\n")
    record(code == 77, "B-09 远程模式下指向维护库 postgres → 同样拒绝", out.strip()[:160])

    code, out = probe(REMOTE_ENV, "DOYAH_TEST_SCRIPT_READY_FOR_REMOTE=1\n",
                      after="doyah_test_env_scratch_db whatever\n")
    record(code == 77 and "自建库" in out,
           "B-10 报到的脚本想自建库 → 拒绝并指路（迁移第 2 步未做）", out.strip()[:200])

    code, out = probe(after='doyah_test_env_export_connection\necho "PG=$PGHOST/$PGPORT/$PGUSER/${PGDATABASE:-未导出}"\n')
    record(code == 0 and "PG=127.0.0.1/55433/postgres/未导出" in out,
           "B-11 导出的标准变量正确，且**不**替脚本定库名（库名各脚本自定）", out.strip()[:200])

    code, out = probe({"DOYAH_TEST_LOCAL_PORT": "55999"})
    record(code == 0 and "PORT=55999" in out, "B-12 端口可被 DOYAH_TEST_LOCAL_PORT 覆盖", out.strip()[:160])

    code, out = probe({"TEST_PGPORT": "55888"})
    record(code == 0 and "PORT=55888" in out, "B-13 旧名 TEST_PGPORT 仍认（对外承诺过）", out.strip()[:160])

    code, out = probe(REMOTE_ENV, "DOYAH_TEST_SCRIPT_READY_FOR_REMOTE=1\n",
                      after='echo "R=$DOYAH_TEST_REMOTE_HOST/$DOYAH_TEST_REMOTE_PORT/$DOYAH_TEST_REMOTE_USER"\n')
    record(code == 0 and "R=192.168.5.217/5432/zxvmax" in out,
           "B-14 217 只读段的连接信息也来自 lib", out.strip()[:160])

    port_occupancy_cases()


PG_CTL_STUB = """#!/bin/bash
# 假 pg_ctl：只够判「起实例」那一段的分支（start 落标记、status 读标记），不真起库。
datadir=""
prev=""
cmd=""
for arg in "$@"; do
  [ "${prev}" = "-D" ] && datadir="${arg}"
  prev="${arg}"
  cmd="${arg}"
done
case "${cmd}" in
  status) [ -f "${datadir}/doyah-fake-running" ] && exit 0 || exit 3 ;;
  start) mkdir -p "${datadir}" && : > "${datadir}/doyah-fake-running" && exit 0 || exit 1 ;;
  stop) rm -f "${datadir}/doyah-fake-running"; exit 0 ;;
esac
exit 1
"""

INITDB_STUB = """#!/bin/bash
# 假 initdb：只把 PG_VERSION 落进数据目录（够让 start_cluster 走完「没初始化就初始化」那一支）。
datadir=""
prev=""
for arg in "$@"; do
  [ "${prev}" = "-D" ] && datadir="${arg}"
  prev="${arg}"
done
mkdir -p "${datadir}" && printf '18\\n' > "${datadir}/PG_VERSION"
"""

def port_occupancy_cases():
    """⑦C（T-20261013-036）：本机档端口被占 ⇒ 出声 + 75；端口空闲 ⇒ 静默。成对自检。

    为什么要有它（真缺陷）：本机档三档端口是固定的，而同机常有别的克隆的测试集群常驻占着
    同一个端口（实测 55433 被别的克隆的 postmaster 占住数日）⇒ `pg_ctl start` 必败、且失败
    只写进日志 ⇒ 脚本侧看到非零退出、有时一行输出都没有，现场像「判据自己坏了」。
    这里注入一个**真监听**（占用）与一个空端口（空闲），各跑一次 `doyah_test_env_start_cluster`。
    """
    with tempfile.TemporaryDirectory() as tmp:
        fake_bin = Path(tmp) / "fake-pg-bin"
        fake_bin.mkdir()
        for name, body in (("pg_ctl", PG_CTL_STUB), ("initdb", INITDB_STUB)):
            stub = fake_bin / name
            stub.write_text(body, encoding="utf-8")
            stub.chmod(0o755)
        datadir = Path(tmp) / "pgdata"
        common = {"DOYAH_TEST_PG_BIN": str(fake_bin), "DOYAH_TEST_LOCAL_DATADIR": str(datadir)}

        with socket.socket() as server:
            server.bind(("127.0.0.1", 0))
            server.listen(1)
            busy_port = str(server.getsockname()[1])
            code, out = probe(dict(common, DOYAH_TEST_LOCAL_PORT=busy_port),
                              after="doyah_test_env_start_cluster\n")
        record(code == 75 and busy_port in out and "别的实例" in out and "pid" in out,
               "B-15 本机档端口被别的实例占着 → 点名占者 + exit 75（不静默）", out.strip()[:240])

        with socket.socket() as spare:
            spare.bind(("127.0.0.1", 0))
            free_port = str(spare.getsockname()[1])
        code, out = probe(dict(common, DOYAH_TEST_LOCAL_PORT=free_port),
                          after="doyah_test_env_start_cluster\n")
        record(code == 0 and "端口" not in out and "❌" not in out,
               "B-16 端口空闲 → 静默起群（一行都不多打；反向对照，防这条闸恒红）", out.strip()[:240])

def main():
    print("== 门禁与 lib 的自检（负例 + 行为）")
    gate_negatives()
    lib_behavior()
    print()
    print(f"通过 {len(passed)} 项，失败 {len(failed)} 项")
    if failed:
        for label in failed:
            print(f"  ❌ {label}")
        return 1
    print("✅ 门禁的每条判据都能红出来，lib 的每个分支都按说好的走。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
