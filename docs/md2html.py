# -*- coding: utf-8 -*-
"""Lightweight Markdown -> HTML converter for the deployment manual.
Handles: headings, fenced code blocks, tables, ul/ol lists, blockquotes,
horizontal rules, inline code, bold, and paragraphs. No external deps.
"""
import html
import re
import sys

def inline(text):
    # escape first, then restore inline code and bold via placeholders
    code_spans = []
    def _code(m):
        code_spans.append('<code>' + html.escape(m.group(1)) + '</code>')
        return '\x00CODE%d\x00' % (len(code_spans) - 1)
    text = re.sub(r'`([^`]+)`', _code, text)
    text = html.escape(text)
    text = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', text)
    for i, c in enumerate(code_spans):
        text = text.replace('\x00CODE%d\x00' % i, c)
    return text

def is_table_sep(line):
    s = line.strip().strip('|')
    cells = [c.strip() for c in s.split('|')]
    return bool(cells) and all(re.fullmatch(r':?-{3,}:?', c) for c in cells)

def convert(md):
    lines = md.split('\n')
    out = []
    i = 0
    n = len(lines)
    in_code = False
    code_buf = []
    while i < n:
        line = lines[i]
        stripped = line.strip()

        # fenced code
        if stripped.startswith('```'):
            if in_code:
                out.append('<pre><code>' + html.escape('\n'.join(code_buf)) + '</code></pre>')
                code_buf = []
                in_code = False
            else:
                in_code = True
            i += 1
            continue
        if in_code:
            code_buf.append(line)
            i += 1
            continue

        # blank
        if stripped == '':
            i += 1
            continue

        # horizontal rule
        if re.fullmatch(r'-{3,}', stripped) or re.fullmatch(r'\*{3,}', stripped):
            out.append('<hr>')
            i += 1
            continue

        # heading
        m = re.match(r'^(#{1,6})\s+(.*)$', stripped)
        if m:
            lvl = len(m.group(1))
            out.append('<h%d>%s</h%d>' % (lvl, inline(m.group(2)), lvl))
            i += 1
            continue

        # table
        if stripped.startswith('|') and i + 1 < n and is_table_sep(lines[i + 1]):
            header = [c.strip() for c in stripped.strip('|').split('|')]
            i += 2
            rows = []
            while i < n and lines[i].strip().startswith('|'):
                rows.append([c.strip() for c in lines[i].strip().strip('|').split('|')])
                i += 1
            thead = '<tr>' + ''.join('<th>' + inline(c) + '</th>' for c in header) + '</tr>'
            tbody = ''.join('<tr>' + ''.join('<td>' + inline(c) + '</td>' for c in r) + '</tr>' for r in rows)
            out.append('<table><thead>' + thead + '</thead><tbody>' + tbody + '</tbody></table>')
            continue

        # blockquote
        if stripped.startswith('>'):
            q = []
            while i < n and lines[i].strip().startswith('>'):
                q.append(lines[i].strip().lstrip('>').strip())
                i += 1
            out.append('<blockquote>' + inline(' '.join(q)) + '</blockquote>')
            continue

        # unordered list
        if re.match(r'^[-+]\s+', stripped):
            items = []
            while i < n and re.match(r'^[-+]\s+', lines[i].strip()):
                items.append(re.sub(r'^[-+]\s+', '', lines[i].strip()))
                i += 1
            out.append('<ul>' + ''.join('<li>' + inline(x) + '</li>' for x in items) + '</ul>')
            continue

        # ordered list
        if re.match(r'^\d+\.\s+', stripped):
            items = []
            while i < n and re.match(r'^\d+\.\s+', lines[i].strip()):
                items.append(re.sub(r'^\d+\.\s+', '', lines[i].strip()))
                i += 1
            out.append('<ol>' + ''.join('<li>' + inline(x) + '</li>' for x in items) + '</ol>')
            continue

        # paragraph: merge consecutive non-special lines
        para = [stripped]
        i += 1
        while i < n:
            s = lines[i].strip()
            if (s == '' or s.startswith('#') or s.startswith('|') or s.startswith('>')
                    or s.startswith('```') or re.fullmatch(r'-{3,}|\*{3,}', s)
                    or re.match(r'^[-+]\s+', s) or re.match(r'^\d+\.\s+', s)):
                break
            para.append(s)
            i += 1
        out.append('<p>' + inline(' '.join(para)) + '</p>')

    if in_code:
        out.append('<pre><code>' + html.escape('\n'.join(code_buf)) + '</code></pre>')
    return '\n'.join(out)

CSS = """
:root{--bg:#ffffff;--fg:#1f2328;--muted:#57606a;--border:#d0d7de;--code-bg:#f6f8fa;
--th:#f6f8fa;--accent:#0969da;--quote-bg:#f6f8fa;--quote-bar:#0969da;}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);
font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Microsoft YaHei",sans-serif;
font-size:15px;line-height:1.7;padding:0}
.wrap{max-width:900px;margin:0 auto;padding:48px 40px 80px}
h1{font-size:30px;font-weight:600;border-bottom:2px solid var(--border);padding-bottom:14px;margin:0 0 26px}
h2{font-size:22px;font-weight:600;margin:36px 0 14px;padding-bottom:8px;border-bottom:1px solid var(--border)}
h3{font-size:18px;font-weight:600;margin:26px 0 10px}
h4{font-size:16px;font-weight:600;margin:20px 0 8px}
p{margin:10px 0}
ul,ol{margin:10px 0;padding-left:26px}
li{margin:5px 0}
code{background:var(--code-bg);border:1px solid var(--border);border-radius:5px;
padding:1px 6px;font-family:"SFMono-Regular",Consolas,"Liberation Mono",monospace;font-size:13px;color:#cf222e}
pre{background:var(--code-bg);border:1px solid var(--border);border-radius:8px;
padding:16px 18px;overflow-x:auto;margin:14px 0;line-height:1.5}
pre code{background:none;border:none;padding:0;color:var(--fg);font-size:13.5px}
table{border-collapse:collapse;width:100%;margin:16px 0;font-size:14px;display:block;overflow-x:auto}
th,td{border:1px solid var(--border);padding:9px 12px;text-align:left;vertical-align:top}
th{background:var(--th);font-weight:600;white-space:nowrap}
blockquote{margin:16px 0;padding:10px 16px;background:var(--quote-bg);
border-left:4px solid var(--quote-bar);color:var(--muted);border-radius:0 6px 6px 0}
hr{border:none;border-top:1px solid var(--border);margin:28px 0}
strong{font-weight:600}
@media(max-width:640px){.wrap{padding:24px 18px 60px}h1{font-size:24px}}
@media print{body{font-size:12px}.wrap{padding:0}h2{page-break-after:avoid}pre,table{page-break-inside:avoid}}
"""

def main():
    src, dst = sys.argv[1], sys.argv[2]
    with open(src, 'r', encoding='utf-8') as f:
        md = f.read()
    body = convert(md)
    title = 'asterCC 迁移测试环境部署手册'
    doc = ('<!DOCTYPE html>\n<html lang="zh-CN">\n<head>\n'
           '<meta charset="utf-8">\n'
           '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
           '<title>' + title + '</title>\n<style>' + CSS + '</style>\n</head>\n'
           '<body><div class="wrap">\n' + body + '\n</div></body>\n</html>\n')
    with open(dst, 'w', encoding='utf-8') as f:
        f.write(doc)
    print('written:', dst, len(doc), 'bytes')

if __name__ == '__main__':
    main()
