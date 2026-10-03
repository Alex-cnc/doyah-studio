# 漏译棘轮：把"没走语言表的中文文案"数出来，**只许减不许增**
#
# 为什么要棘轮而不是一次修完：81 处散在 20 多个文件里，一次全改风险大（改坏模板的例子
# 本会话已有先例）。棘轮的作用是**先把水位钉住**：新写的界面文案必须走语言表，
# 老的那批按段推进、每改一批就把基线往下调。**基线只许减。**
#
# 口径见 `scan-untranslated.py`。本文件只做"数 + 比基线 + 退出码"。
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)                     # windows/App
SRC = os.path.join(ROOT, 'src')
BASELINE_FILE = os.path.join(HERE, 'untranslated-baseline.txt')

sys.path.insert(0, HERE)
from importlib import import_module
scan = import_module('scan-untranslated'.replace('-', '_')) if False else None

CJK = re.compile(r'[\u4e00-\u9fff]')

def strip_block_comments(text):
    return re.sub(r'/\*.*?\*/', '', text, flags=re.S)

def strip_line_comments(text):
    out = []
    for line in text.split('\n'):
        idx = line.find('//')
        out.append(line[:idx] if idx >= 0 else line)
    return '\n'.join(out)

def strip_html_comments(text):
    return re.sub(r'<!--.*?-->', '', text, flags=re.S)

UI_PATTERNS = [
    re.compile(r'title="([^"]*)"'),
    re.compile(r'placeholder="([^"]*)"'),
    re.compile(r'window\.confirm\(\s*[\'"]([^\'"]*)[\'"]'),
    re.compile(r'window\.alert\(\s*[\'"]([^\'"]*)[\'"]'),
]

def collect():
    hits = []
    files = []
    for base, _, names in os.walk(SRC):
        if 'node_modules' in base:
            continue
        for name in names:
            if name.endswith(('.ts', '.vue')):
                files.append(os.path.join(base, name))
    for path in files:
        rel = path.replace(SRC + os.sep, '').replace('\\', '/')
        if rel.startswith('i18n/') or rel.endswith('.test.ts'):
            continue
        raw = open(path, encoding='utf-8').read()
        text = strip_html_comments(strip_line_comments(strip_block_comments(raw)))
        if path.endswith('.vue'):
            m = re.search(r'<template>(.*?)</template>', text, re.S)
            if m:
                for line in m.group(1).split('\n'):
                    if not CJK.search(line):
                        continue
                    if "t('" in line or 't("' in line:
                        stripped = re.sub(r"\{\{[^}]*\}\}", '', line)
                        stripped = re.sub(r'<!--.*?-->', '', stripped)
                        if not CJK.search(stripped):
                            continue
                    hits.append((rel, 'template'))
        else:
            for pattern in UI_PATTERNS:
                for mm in pattern.finditer(text):
                    if CJK.search(mm.group(1)):
                        hits.append((rel, 'attr'))
    return hits

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

print(f'漏译扫描：{count} 处（扫 {len(set(h for h, _ in hits))} 个文件）')
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
