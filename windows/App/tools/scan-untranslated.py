# 漏译扫描（判据工具）：找界面里"没走语言表的中文用户可见文案"
#
# 口径（为什么这么切）：
# 1. **注释里的中文不算**（那是给读代码的人看的，不是给用户看的）—— 先剥注释；
# 2. **模板里的中文**基本就是用户可见文案（模板里很少有注释）；
# 3. **脚本里的中文**要区分：出现在 `title=` / `placeholder=` / `window.confirm(` / 反引号提示串
#    这一类"会进界面"的位置才算；普通变量名与逻辑不算。
# 4. **语言表自己**（`i18n/`）里的中文是**应该有的**（那是译文），跳过。
import os, re, sys

root = r'D:\AIProjects\DoyahStudio\windows\App\src'
CJK = re.compile(r'[\u4e00-\u9fff]')

def strip_block_comments(text):
    return re.sub(r'/\*.*?\*/', '', text, flags=re.S)

def strip_line_comments(text):
    out = []
    for line in text.split('\n'):
        # 简单的行注释剥离：// 之后的内容（不处理字符串里的 //，够用）
        idx = line.find('//')
        out.append(line[:idx] if idx >= 0 else line)
    return '\n'.join(out)

def strip_html_comments(text):
    return re.sub(r'<!--.*?-->', '', text, flags=re.S)

# 会进界面的位置（脚本里）
UI_PATTERNS = [
    re.compile(r'title="([^"]*)"'),
    re.compile(r"title=\"([^\"]*)\""),
    re.compile(r'placeholder="([^"]*)"'),
    re.compile(r'window\.confirm\(\s*[\'"]([^\'"]*)[\'"]'),
    re.compile(r'window\.alert\(\s*[\'"]([^\'"]*)[\'"]'),
]

hits = []
files = []
for base, _, names in os.walk(root):
    if 'node_modules' in base:
        continue
    for name in names:
        if name.endswith(('.ts', '.vue')):
            files.append(os.path.join(base, name))

for path in files:
    rel = path.replace(root + os.sep, '').replace('\\', '/')
    if rel.startswith('i18n/'):
        continue          # 语言表里的中文是译文，应当在
    if rel.endswith('.test.ts'):
        continue          # 测试里的中文是判据文字
    raw = open(path, encoding='utf-8').read()
    text = strip_html_comments(strip_line_comments(strip_block_comments(raw)))

    if path.endswith('.vue'):
        # 模板部分：把 <template>…</template> 里的中文算进来
        m = re.search(r'<template>(.*?)</template>', text, re.S)
        if m:
            for line_no, line in enumerate(m.group(1).split('\n'), 0):
                if CJK.search(line):
                    # 模板里已有 t('…') 的不算
                    if "t('" in line or 't("' in line:
                        # 同一行可能还有别处中文；这里保守起见：只要没有"裸中文在标签之间"就跳过
                        stripped = re.sub(r"\{\{[^}]*\}\}", '', line)
                        stripped = re.sub(r'<!--.*?-->', '', stripped)
                        if not CJK.search(stripped):
                            continue
                    hits.append((rel, 'template', line.strip()[:100]))
    else:
        for pattern in UI_PATTERNS:
            for mm in pattern.finditer(text):
                val = mm.group(1)
                if CJK.search(val):
                    hits.append((rel, 'attr/confirm', val[:80]))

print(f'扫描文件数：{len(files)}（跳过语言表与测试）')
print(f'疑似漏译：{len(hits)} 处')
print()
by_file = {}
for rel, kind, snippet in hits:
    by_file.setdefault(rel, []).append((kind, snippet))
for rel in sorted(by_file):
    print(f'{rel}  ({len(by_file[rel])} 处)')
    for kind, snippet in by_file[rel][:4]:
        print(f'    [{kind}] {snippet}')
