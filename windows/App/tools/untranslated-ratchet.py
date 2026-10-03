# 漏译棘轮：把"没走语言表的中文文案"数出来，**只许减不许增**
#
# 为什么要棘轮而不是一次修完：81 处散在 20 多个文件里，一次全改风险大（改坏模板的例子
# 本会话已有先例）。棘轮的作用是**先把水位钉住**：新写的界面文案必须走语言表，
# 老的那批按段推进、每改一批就把基线往下调。**基线只许减。**
#
# 口径与实现**只有一处**：扫描在 `scan-untranslated.py`，本文件只做"数 + 比基线 + 退出码"
# （原来这里也抄了一份，结果我补了一面只补到其中一处 ⇒ 两个脚本当场不一致，已改）。
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)                     # windows/App
SRC = os.path.join(ROOT, 'src')
BASELINE_FILE = os.path.join(HERE, 'untranslated-baseline.txt')

sys.path.insert(0, HERE)
from importlib import import_module
scan = import_module('scan-untranslated'.replace('-', '_')) if False else None

# **判据只有一处实现**：本文件不再自己写一份扫描（原来两处各一份 ⇒ 我补了一面只补到其中一处，
# 两个脚本当场不一致）。这里用 importlib 直接载入 `scan-untranslated.py` 的 `collect()`。
import importlib.util

_scanner_path = os.path.join(HERE, 'scan-untranslated.py')
_spec = importlib.util.spec_from_file_location('doyah_untranslated_scan', _scanner_path)
_scanner = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_scanner)
collect = _scanner.collect

hits = collect()
count = len(hits)

# `--write-baseline`：把当前水位写成基线（**只该在"这一批已经改完、水位确实降了"时用**）
if '--write-baseline' in sys.argv:
    with open(BASELINE_FILE, 'w', encoding='utf-8', newline='\n') as handle:
        handle.write(str(count) + '\n')
    print(f'已写下基线：{count} 处')
    sys.exit(0)

baseline = None
if os.path.exists(BASELINE_FILE):
    baseline = int(open(BASELINE_FILE, encoding='utf-8').read().strip() or '0')

print(f'漏译扫描：{count} 处（扫 {len(set(h for h, _ in hits))} 个文件；含模板 / 属性 / .ts 数据型文案三面）')
if baseline is None:
    print('（还没有基线；用 --write-baseline 记下当前水位）')
    sys.exit(0)

print(f'基线：{baseline} 处')
if count > baseline:
    over = count - baseline
    by_file = {}
    for rel, _ in hits:
        by_file[rel] = by_file.get(rel, 0) + 1
    print(f'❌ 比基线多了 {over} 处 —— 新写的界面文案要走语言表（`t(...)`）')
    for rel in sorted(by_file, key=lambda r: -by_file[r])[:8]:
        print(f'    {rel}: {by_file[rel]}')
    sys.exit(1)

if count < baseline:
    print(f'✅ 比基线少了 {baseline - count} 处（**请把基线调到 {count}** —— 基线只许减）')
    sys.exit(0)

print('✅ 与基线持平')
sys.exit(0)
