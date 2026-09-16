#!/usr/bin/env python3
"""Assemble the .dc.html artboards from one shared kit + per-board bodies."""
from pathlib import Path

HEAD = Path("_head.part").read_text()
TAIL = "</x-dc>\n</body>\n</html>\n"

FG, DIM, ACC, URG = "#4c4f69", "rgba(76,79,105,0.38)", "#1e66f5", "#d20f39"

def mark(status, color=FG):
    inner = '<rect x="2.5" y="2.5" width="11" height="11"/>'
    if status == "x":
        inner += '<path d="M5.2 8.2L7.2 10.2L10.8 6.3"/>'
    elif status == ">":
        inner += '<path d="M6.6 5.4L9.4 8L6.6 10.6"/>'
    elif status == "-":
        inner += '<path d="M4.8 11.2L11.2 4.8"/>'
    return ('<svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="%s" '
            'stroke-width="1.4" stroke-linecap="square" stroke-linejoin="miter">%s</svg>'
            % (color, inner))

def row(status, text, age="", cursor=False, urgent=False):
    receded = status != " "
    stroke = ACC if cursor else (ACC if status == ">" else (DIM if not receded else DIM))
    if not cursor and not receded:
        stroke = DIM
    cls = "lbl" + (" on" if cursor else (" dim" if receded else "")) + (" cut" if status == "-" else "")
    agecls = "age" + (" on" if cursor else (" urg" if urgent else ""))
    agestyle = ' style="color:%s"' % URG if (urgent and not cursor) else (' style="color:%s"' % ACC if cursor else "")
    return ('    <div class="row%s">%s<div class="%s">%s</div>'
            '<div class="age"%s>%s</div></div>'
            % (" cur" if cursor else "", mark(status, stroke), cls, text, agestyle, age))

def note(text):
    return ('    <div class="row"><div class="dot">·</div>'
            '<div class="note">%s</div></div>' % text)

def legend(pairs):
    out = ['  <div class="legend">']
    for k, w in pairs:
        out.append('    <div><span class="k">%s</span> %s</div>' % (k, w))
    out.append("  </div>")
    return "\n".join(out)

COG = ('<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="%s" stroke-width="1.8" '
       'stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/>'
       '<path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 '
       '1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 '
       '0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 '
       '0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 '
       '1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 '
       '2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 '
       '0-1.51 1z"/></svg>') % FG

def chev(d, color=FG):
    path = "M15 4L7.5 12L15 20" if d == "l" else "M9 4L16.5 12L9 20"
    return ('<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="%s" stroke-width="2" '
            'stroke-linecap="square" stroke-linejoin="miter"><path d="%s"/></svg>' % (color, path))

def write(name, body):
    Path(name).write_text(HEAD + body + "\n" + TAIL)
    print("wrote", name)
