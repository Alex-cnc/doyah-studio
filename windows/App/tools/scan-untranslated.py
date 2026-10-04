# 漏译扫描（**判据的唯一实现**）：找界面里"没走语言表的中文用户可见文案"
#
# 三面都扫（**缺一面就是假绿**）：
#   ① **模板**：`.vue` 的 `<template>` 里的中文基本就是用户可见文案；
#   ② **属性/确认框**：`title` / `placeholder` / `window.confirm` / `window.alert` 里的中文；
#   ③ **`.ts` 里的数据型文案**：`label: '科技蓝'` 这种 —— 界面直接拿它显示。
#      **这一面是后补的**：头一版只看模板，于是 `appearance.ts` 的配色名、`commands.ts` 的命令名、
#      `activityBar.ts` 的视图名、`ipc.ts` 的旁路提示**全都没被算进去**（判据不完整就是假绿）。
#
# 不算的：注释里的中文（给读代码的人看）、语言表自己（那是译文）、测试文件（那是判据文字）。
#
# 用法：`python tools/scan-untranslated.py` 直接看当前水位；
#       棘轮（`untranslated-ratchet.py`）**复用本文件的 `collect()`** —— 不许再抄一份。
import os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # windows/App
SRC = os.path.join(ROOT, 'src')

CJK = re.compile(r'[\u4e00-\u9fff]')

UI_PATTERNS = [
    re.compile(r'title="([^"]*)"'),
    re.compile(r'placeholder="([^"]*)"'),
    re.compile(r'window\.confirm\(\s*[\'"]([^\'"]*)[\'"]'),
    re.compile(r'window\.alert\(\s*[\'"]([^\'"]*)[\'"]'),
    # `.ts` 里的数据型文案（`label: '科技蓝'` / `text: '…'` / `hint: '…'`）
    re.compile(r'\b(?:label|title|text|hint|note|placeholder|message|reason)\s*:\s*[\'"]([^\'"]*)[\'"]'),
    # 兜底：`value: '带中文的…'`
    re.compile(r'\bvalue\s*:\s*[\'"]([^\'"]*[\u4e00-\u9fff][^\'"]*)[\'"]'),
]


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


def collect():
    """返回 [(相对路径, 命中面)] —— **判据的唯一实现**。"""
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
        # **白名单**（逐条给理由，不许默默放过）：
        # `shell/activityBar.ts` 有一套**自己的双语表**（`'zh-Hans': { title: '工作区' },
        # en: { title: 'Workspace' }` 成对写在一个表里，`Record<UiLanguage, …>`）。
        # 那是"另一种合规做法"，不是漏译 —— 头一版判据把它误判成 4 处漏译（假红）。
        if rel == 'shell/activityBar.ts':
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
                        hits.append((rel, 'ts-data'))

    return hits


def report(hits):
    by_file = {}
    for rel, kind in hits:
        by_file.setdefault(rel, []).append(kind)
    for rel in sorted(by_file, key=lambda r: (-len(by_file[r]), r)):
        print(f'{rel}  ({len(by_file[rel])} 处)')
    return by_file


if __name__ == '__main__':
    hits = collect()
    print(f'扫描文件数：{len(set(h for h, _ in hits))} 个文件有命中（跳过语言表与测试）')
    print(f'疑似漏译：{len(hits)} 处（三面：模板 / 属性 / .ts 数据型文案）')
    print()
    report(hits)
