#!/usr/bin/env python3
from build import *

# ---------------------------------------------------------------- Today (anchor)
write("Today.dc.html", """<div class="ground">
  <div class="card">
  <div class="col">
  <div class="hdr"><div class="ttl">Todo</div>
    <div style="flex:1"></div>
    <div class="age" style="padding-right:8px">Wed 16 Sep</div>
    """ + COG + """</div>
  <div class="sep"></div>
  <div class="sect"><span>TODAY</span><span>1</span></div>
  <div class="rows">
""" + row(" ", "call the accountant", cursor=True) + "\n"
   + row("x", "ship the invoice") + "\n"
   + row("-", "look into the Vite 6 upgrade") + """
  </div>
  <div class="sect"><span>DANGLING</span><span>1</span></div>
  <div class="rows">
""" + row(" ", "rewrite onboarding copy", age="9d", urgent=True) + """
  </div>
  <div class="sep"></div>
""" + legend([("j/k", "move"), ("m", "migrate"), ("x/⏎", "done"), ("d", "drop"),
              ("a", "add"), ("n", "note"), ("s", "settings")]) + """
  </div>
  </div>
</div>""")

# ------------------------------------------------------------- Main: the day view
write("Main.dc.html", """<div class="ground">
  <div class="card">
  <div class="col">
  <div class="hdr">
    <div style="display:flex;align-items:center;gap:7px">
      """ + chev("l") + """<div class="ttl">Mon 14 Sep</div>""" + chev("r", DIM) + """
    </div>
    <div style="flex:1"></div>
    <div class="age" style="padding-right:8px">2 days ago</div>
    """ + COG + """</div>
  <div class="sep"></div>
  <div class="sect"><span>TODO</span><span>4</span></div>
  <div class="rows">
""" + row("x", "ship the invoice", cursor=True) + "\n"
   + row("x", "call the accountant") + "\n"
   + row(">", "rewrite onboarding copy", age="→ 18 Sep") + "\n"
   + row("-", "look into the Vite 6 upgrade") + """
  </div>
  <div class="sect"><span>LOG</span><span>2</span></div>
  <div class="rows">
""" + note("accountant wants the Q3 numbers by Friday") + "\n"
   + note("onboarding copy needs Sara’s sign-off first") + """
  </div>
  <div class="sep"></div>
""" + legend([("h/l", "day"), ("t", "today"), ("j/k", "move"), ("x/⏎", "done"),
              ("d", "drop"), ("m", "migrate"), ("a", "add"), ("n", "note")]) + """
  </div>
  </div>
</div>""")

# ----------------------------------------------------------------- Main: empty day
write("Empty.dc.html", """<div class="ground">
  <div class="card">
  <div class="col">
  <div class="hdr">
    <div style="display:flex;align-items:center;gap:7px">
      """ + chev("l") + """<div class="ttl">Sun 13 Sep</div>""" + chev("r") + """
    </div>
    <div style="flex:1"></div>
    <div class="age" style="padding-right:8px">3 days ago</div>
    """ + COG + """</div>
  <div class="sep"></div>
  <div style="font-size:10px;color:rgba(76,79,105,0.38);padding:4px 0">No note for this day.</div>
  <div class="sep"></div>
""" + legend([("h/l", "day"), ("t", "today"), ("a", "add"), ("n", "note")]) + """
  </div>
  </div>
</div>""")
