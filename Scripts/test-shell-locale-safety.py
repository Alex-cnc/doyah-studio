#!/usr/bin/env python3
"""`check-shell-locale-safety.py` 的负例验证（开发循环 L-05）。

两件事：
1. **证前提**：在本机 bash 上真跑一遍，证明「裸写 `$X` 紧跟 CJK」真的会丢值（bash ≥ 4 时跳过并说明）；
2. **证门禁**：造几种写法，断言门禁该红的红、该绿的绿。

**第 42 轮（合册 `T-20261013-027` · 原单 `T-20261010-055`）**：门禁判定物升到「代码面」——
行内注释 / 单引号字面量 / 转义美元 / 引号定界 heredoc **四形不再假红**，另补空跑下限
（扫到的 `.sh` 少于 `MIN_SOURCE_FILES` ⇒ rc=2）。负例随之下移：四形各断言判绿、空根断言判红、
真仓库那条从「输出里含『扫描』与 `.sh`」改成「扫到的份数 **≥ 下限**」（旧写法在「扫描 0 个」时也通过）。
**例数 9 → 13**（已登记 `Scripts/self-test-counts.json`）。

夹具仓库要**铺到下限**（`pad`）：不铺的话，测到的是下限本身，不是判定物。
下限那条另用一个**不铺**的空根来测。

故意不进闭环（`verify-all.sh` 里跑的是门禁本身，不是它的负例）。

用法：`python3 Scripts/test-shell-locale-safety.py`
"""

import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHECKER = os.path.join("Scripts", "check-shell-locale-safety.py")

_spec = importlib.util.spec_from_file_location("gate_shell_locale", os.path.join(ROOT, CHECKER))
_gate = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_gate)
MIN_FILES = _gate.MIN_SOURCE_FILES  # 下限只有一处定义（门禁里），负例这边读出来用
PAD = "#!/bin/bash\necho ok\n"

passed = 0
failed = 0


def check(what, condition, detail=""):
    global passed, failed
    if condition:
        passed += 1
        print(f"  ✅ {what}")
    else:
        failed += 1
        print(f"  ❌ {what}{('  —— ' + detail) if detail else ''}")


def bash_major(executable="/bin/bash"):
    try:
        out = subprocess.run([executable, "--version"], stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, text=True, errors="replace").stdout
    except OSError:
        return None
    match = re.search(r"version (\d+)\.", out)
    return int(match.group(1)) if match else None


def run_checker(paths, workdir, tag, pad=True):
    """把待检脚本放进一个临时仓库根里跑门禁（门禁按自身位置的上级当仓库根）。

    `pad=True` 时把夹具仓库铺到 `MIN_FILES` 份 `.sh`（门禁有空跑下限，不铺就测不到判定物）。
    """
    shim_root = os.path.join(workdir, "repo-" + tag)
    shutil.rmtree(shim_root, ignore_errors=True)  # 每次全新，免得上一轮的坏文件留在里面
    scripts = os.path.join(shim_root, "Scripts")
    os.makedirs(scripts, exist_ok=True)
    checker = os.path.join(scripts, "check-shell-locale-safety.py")
    shutil.copy2(os.path.join(ROOT, CHECKER), checker)
    if pad:
        for index in range(MIN_FILES):
            with open(os.path.join(scripts, "pad_%03d.sh" % index), "w", encoding="utf-8") as handle:
                handle.write(PAD)
    for name, content in paths.items():
        with open(os.path.join(scripts, name), "w", encoding="utf-8") as handle:
            handle.write(content)
    proc = subprocess.run([sys.executable, checker], stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, text=True, errors="replace")
    return proc.returncode, proc.stdout


def main():
    workdir = tempfile.mkdtemp(prefix="doyah-shell-locale-")
    try:
        print("== 1) 前提实证：本机 bash 上，裸写变量紧跟 CJK 到底会不会丢值")
        major = bash_major()
        print(f"    /bin/bash 主版本：{major}")
        sample = os.path.join(workdir, "sample.sh")
        with open(sample, "w", encoding="utf-8") as handle:
            handle.write('#!/bin/bash\nX=VALUE\necho "中文：$X）"\necho "中文：${X}）"\n')
        out = subprocess.run(["/bin/bash", sample], stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, text=True, errors="replace").stdout
        first, second = out.splitlines()[0], out.splitlines()[1]
        check("花括号写法保住值（`${X}）`）", "VALUE" in second, second)
        if major == 3:
            check("裸写写法**丢了值**（bash 3 上真的丢）", "VALUE" not in first, first)
        else:
            print(f"    （bash {major} 不丢值 —— 门禁的前提只对 bash 3.x 成立，这里如实说明而不是假装通过）")

        print()
        print("== 2) 门禁：坏写法必须报红")
        code, out = run_checker({
            "bad_paren.sh": '#!/bin/bash\nX=1\necho "拿到了（$X）"\n',
            "bad_chinese.sh": '#!/bin/bash\nCOUNT=1\necho "共 $COUNT 条" | sed "s/共/$COUNT项/"\n',
        }, workdir, "bad")
        check("裸写 + 全角括号 → exit 1", code == 1, f"exit {code}")
        check("指名了文件与行号", "bad_paren.sh:3" in out, out.strip()[:300])
        check("给了修法提示", "${" in out, out.strip()[:300])

        print()
        print("== 3) 门禁：好写法必须放行")
        code, out = run_checker({
            "good_brace.sh": '#!/bin/bash\nX=1\necho "拿到了（${X}）"\n',
            "good_ascii.sh": '#!/bin/bash\nX=1\necho "拿到了（$X)"\necho "共 $X 条"\n',
            "good_comment.sh": '#!/bin/bash\n# 说明：以前写成（$X）会丢值，别改回去\nX=1\necho $X\n',
        }, workdir, "good")
        check("花括号 / ASCII 结尾 / 整行注释 → exit 0", code == 0, f"exit {code}")
        check("打印了通过语", "✅" in out, out.strip()[:200])

        code, out = run_checker({
            "inline_comment.sh": '#!/bin/bash\nX=1\necho hi  # 中：$X）这条注释里不会展开\n',
        }, workdir, "inline-comment")
        check("② 行内注释里的裸写 → 判绿（旧码 rc=1 假红）", code == 0, out.strip()[:300])

        code, out = run_checker({
            "single_quote.sh": "#!/bin/bash\nX=1\necho '中：$X）单引号里不展开'\n",
            "escaped_dollar.sh": '#!/bin/bash\nX=1\necho "中：\\$X）反斜杠转义后是字面美元"\n',
        }, workdir, "quotes")
        check("③④ 单引号字面量 / 转义美元 → 判绿（旧码都是 rc=1 假红）", code == 0, out.strip()[:300])

        code, out = run_checker({
            "quoted_heredoc.sh": "#!/bin/bash\nX=1\ncat <<'EOF'\n中：$X）引号定界的 heredoc 体是字面文本\nEOF\n",
        }, workdir, "quoted-heredoc")
        check("⑤ 引号定界 heredoc 体里的裸写 → 判绿（旧码 rc=1 假红）", code == 0, out.strip()[:300])

        print()
        print("== 4) 门禁：真仓库 / 空跑下限")
        real = subprocess.run([sys.executable, os.path.join(ROOT, CHECKER)],
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              text=True, errors="replace")
        check("本仓库 exit 0", real.returncode == 0, real.stdout.strip()[:400])
        scanned = re.search(r"扫描 (\d+) 个 \.sh", real.stdout)
        check(f"扫到的份数 ≥ 下限（{MIN_FILES} 份）",
              bool(scanned) and int(scanned.group(1)) >= MIN_FILES, real.stdout.strip()[:200])

        code, out = run_checker({}, workdir, "empty", pad=False)
        check("⑥ 0 个 .sh 的仓库根 → rc≠0（旧码 rc=0 假绿）", code != 0, out.strip()[:200])
    finally:
        shutil.rmtree(workdir, ignore_errors=True)

    print()
    print(f"结果：{passed} 项通过 / {failed} 项失败")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
