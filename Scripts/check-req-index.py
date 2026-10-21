#!/usr/bin/env python3
"""机器视图漂移检查：`Docs/requirement-index.jsonl` 必须与正文表格逐字对应。

单独成脚本（而不是并进 gen 的 --check），是为了能挂进闭环当一道独立判据：
正文改了、jsonl 没重生成 ⇒ 这里报红。
"""
import subprocess
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.exit(subprocess.run([sys.executable, str(ROOT / "Scripts/gen-req-index.py"), "--check"]).returncode)
