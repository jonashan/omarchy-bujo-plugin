#!/usr/bin/env python3
from build import *

# ------------------------------------------------------- Alternative: the day rail
def railrow(day, todo, notes, cursor=False, today=False):
    left = '<div class="lbl%s" style="flex:0 0 96px">%s</div>' % (" on" if cursor else "", day)
    dots = []
    if todo:
        dots.append('<span style="color:%s">%s open</span>' % (ACC if cursor else FG, todo))
    if notes:
        dots.append('<span class="dim">%s noted</span>' % notes)
    if not dots:
        dots.append('<span class="dim">—</span>')
    tail = '<div style="flex:1;font-size:10px;display:flex;gap:9px">%s</div>' % "".join(dots)
    badge = '<div class="age"%s>today</div>' % (' style="color:%s"' % ACC if today else "")
    return '    <div class="row%s">%s%s%s</div>' % (" cur" if cursor else "", left, tail,
                                                    badge if today else '<div class="age"></div>')

write("DayRail.dc.html", """<div class="ground">
  <div class="card">
  <div class="col">
  <div class="hdr"><div class="ttl">Days</div>
    <div style="flex:1"></div>
    <div class="age" style="padding-right:8px">September</div>
    """ + COG + """</div>
  <div class="sep"></div>
  <div class="rows">
""" + railrow("Wed 16 Sep", 1, 0, today=True) + "\n"
   + railrow("Tue 15 Sep", 1, 1) + "\n"
   + railrow("Mon 14 Sep", 0, 2, cursor=True) + "\n"
   + railrow("Sun 13 Sep", 0, 0) + "\n"
   + railrow("Sat 12 Sep", 2, 1) + "\n"
   + railrow("Fri 11 Sep", 0, 3) + """
  </div>
  <div class="sep"></div>
  <div class="sect"><span>MON 14 SEP</span><span></span></div>
  <div class="rows">
""" + row("x", "ship the invoice") + "\n"
   + row(">", "rewrite onboarding copy", age="→ 18 Sep") + "\n"
   + note("accountant wants the Q3 numbers") + """
  </div>
  <div class="sep"></div>
""" + legend([("j/k", "day"), ("⏎", "open"), ("esc", "back")]) + """
  </div>
  </div>
</div>""")

# ------------------------------------------------------- Alternative: one timeline
def dayhead(label, right=""):
    return ('  <div class="sect" style="padding-top:6px"><span>%s</span><span>%s</span></div>'
            % (label, right))

write("Timeline.dc.html", """<div class="ground">
  <div class="card">
  <div class="col">
  <div class="hdr"><div class="ttl">Todo</div>
    <div style="flex:1"></div>
    <div class="age" style="padding-right:8px">Wed 16 Sep</div>
    """ + COG + """</div>
  <div class="sep"></div>
""" + dayhead("TODAY", "1") + """
  <div class="rows">
""" + row(" ", "call the accountant", cursor=True) + "\n"
   + row("x", "ship the invoice") + "\n"
   + note("shipped it, invoice #2043") + "\n"
+ dayhead("YESTERDAY") + """
  <div class="rows">
""" + row("x", "book the dentist") + "\n"
   + note("dentist: 24 Sep, 09:30") + "\n"
+ dayhead("MON 14 SEP") + """
  <div class="rows">
""" + row(">", "rewrite onboarding copy", age="→ 18 Sep") + "\n"
   + row("-", "look into the Vite 6 upgrade") + "\n"
   + note("accountant wants the Q3 numbers by Friday") + """
  </div>
  <div style="font-size:10px;color:rgba(76,79,105,0.38);padding-top:2px">↓ keep scrolling for older days</div>
  <div class="sep"></div>
""" + legend([("j/k", "move"), ("x/⏎", "done"), ("d", "drop"), ("m", "migrate"),
              ("a", "add"), ("n", "note")]) + """
  </div>
  </div>
</div>""")
