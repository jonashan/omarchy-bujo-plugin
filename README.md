# bujo

Bullet-journal todos that live in Obsidian daily notes, driven from the
[Omarchy](https://omarchy.org) command palette and bar. Markdown is the
database; this is the only thing that writes it.

Today's list and everything still dangling, with a decision for each — done,
dropped, or migrated to a day you name. No sync service, no database, no
daemon. Your notes stay plain files that Obsidian, your phone and `grep` all
read the same way.

Requires Omarchy 4, Python 3.11+, and any Obsidian vault with daily notes.

## The contract

bujo owns exactly one section of a daily note — `## Todo` — and nothing else.
It appends that heading at the bottom if absent, and it **reads only the lines
between that heading and the next `## ` or EOF**. Frontmatter, journal prompts
and stray checkboxes elsewhere in the note are invisible to it by construction.

Obsidian renders the note. bujo renders the section.

Four statuses, Tasks-plugin compatible:

```markdown
- [ ] Call the accountant
- [x] Ship the invoice ✅ 2026-09-16
- [>] Rewrite onboarding copy → [[2026-09-18]]
- [-] Look into the Vite 6 upgrade
```

Every action leaves its record in the origin day — a migrated task keeps `[>]`
where it was written, so a created note is never empty and the deferral chain
stays readable. Dangling is unbounded: an open box from 2024 still shows up
until you make a decision about it.

## Install

```bash
git clone https://github.com/jonashan/omarchy-bujo-plugin.git
cd omarchy-bujo-plugin
./install
```

Symlinks the CLI onto `PATH` and copies the plugin into
`~/.config/omarchy/plugins/io.github.jonashan.bujo`. The QML is copied rather than linked
because `omarchy-plugin-validate` refuses symlinks inside a plugin folder, so
re-run `./install` after editing the plugin.

`install` restarts the shell, because it has to: the running shell keeps the
QML it started with. The `Local plugin changed, reloading` line in the log is
the plugin registry, not the live widgets — copy new files over them and
nothing changes until a restart. (It is `omarchy-restart-shell`, never
`omarchy-refresh-shell`, which resets `shell.json` to Omarchy defaults.)

Then add the widget to `bar.layout.<section>` in `~/.config/omarchy/shell.json`:

```json
{ "id": "io.github.jonashan.bujo" }
```

First run writes `~/.config/bujo/config.toml`, and the panel's settings page
edits it (or `bujo config set`). `vault` and `path` start **empty** — they are
the two things only you can know, and a default that happens to resolve is
worse than a blank that says "not set". Nothing else needs touching.

- `vault` — your Obsidian vault. `bujo config pick vault` (or the folder button
  on the settings page) opens the desktop chooser.
- `path` — where daily notes live inside it, as a pattern. One string covers
  core Daily notes, Periodic Notes and journals users alike, so nothing has to
  know which plugin you run. Month names render from a fixed English table,
  never the system locale.
- `template` (or `template_file`) — rendered **once**, when a note has to be
  created for a future day, and never read again. Entirely yours. Templater
  `<% %>` syntax is refused rather than half-rendered, since only Obsidian can
  run it.

## Use

```
bujo add "call the accountant" friday    # tomorrow, next monday, +3 days, 2026-09-22
bujo note "shipped the invoice"          # a - bullet into today's ## Log
bujo list                                # today plus everything dangling
bujo list --dangling --json
bujo done <ref>                          # [x] + ✅ today
bujo drop <ref>                          # [-]
bujo move <ref> tomorrow                 # [>] here, a fresh [ ] there
bujo edit <ref> "call the accountant"    # rewrite the words; a note the same way
bujo log --day yesterday                 # read a day's log back; `note` writes one
bujo days 2026-09 --json                 # per-day counts for a month, one walk
bujo bar                                 # waybar-style JSON for the bar

bujo config get                          # the effective settings, --json for the panel
bujo config set path "Journal/{{date:YYYY-MM-DD}}.md"
bujo config check                        # a verdict per setting, before or after saving
bujo config check "template_file=Templates/Daily.md"   # ...on a draft you have not saved
bujo config pick vault                   # the desktop folder chooser, then save
bujo config pick template_file           # ...and stored vault-relative
```

`a` and `n` capture through Omarchy's own prompt (`omarchy-menu-input`), asked
for at 560px rather than its 300px default — a todo is a sentence, not a
filename. The menu caps that to the screen, so the number degrades rather than
overflows.

All three actions toggle: `x` on a done task reopens it (and the ✅ stamp goes
with it), `d` on a dropped one revives it, and `m` on a migrated one brings it
back.

Settling a migrated task settles it everywhere. Ticking or dropping a `[>]`
line — or taking it back with `m` — clears the copy waiting at the target,
because a task you have finished is not still owed on Thursday. A copy that has
already been completed or edited there is somebody's work: it is left alone,
and you are told.

`edit` rewrites a line's words and only its words. The status box, the ✅
stamp and the `→` migration link are what a line records about itself rather
than what it says, and they survive. Which section the line sits in is what
decides whether it is a todo or a note, so a checkbox hand-typed into `## Log`
stays the bullet the log shows it as.

A `ref` is `path:line:hash`. The hash is checked before every write, so a task
that Obsidian edited under a live panel is refused rather than acted on at the
wrong line. Notes carry a ref for the same reason, now that there is a write
that can reach one.

## Omarchy

Palette entry — `~/.config/omarchy/extensions/omarchy-menu.jsonc`:

```jsonc
"todo": {"icon":"","label":"Todo","aliases":["task","t"],"action":"bujo add-interactive"},
"note": {"icon":"","label":"Note","aliases":["log","jot"],"action":"bujo note-interactive"}
```

The bar widget shows today's open count, and the dangling count after it in
the `urgent` role — the one colour bujo introduces, and only when there is
something to decide about. Left click opens the panel, right click captures.

In the panel: `j/k` move, `x` or `Enter` done, `d` drop, `m` migrate, `e` edit,
`a` add, `n` note, `s` settings, `Esc` closes. It reads on open and polls once a
second while visible, so a box ticked in Obsidian shows up here.

Today's list shows the day's log under it — record rather than decision, so
those rows carry no status mark, and the empty mark column is what says so.
The cursor walks into them all the same, because `e` is how anything is edited
and a note is a thing you can mistype. The deciding verbs stay refused there.

`e` opens a field under the list rather than turning the row into one: every
list here is rebuilt on the one-second refresh, which would throw a half-typed
row away mid-word, and the row keeps its highlight up there so what you are
changing stays beside what you are changing it to. `Enter` saves, `Esc` throws
the edit away.

**Previous days.** `h` and `l` (or `←`/`→`) step the date; the header becomes
the day you are on and the TODAY/DANGLING split collapses into one list,
because "dangling" is a relationship to today that a past day has not got.
Every verb still works on the row under the cursor. `Esc` returns to today.

`c` opens a month. Days with a note are legible, days without are dim, and a
day still carrying open todos gets a dot — `urgent` once it is in the past, so
a month reads as a map of what is owed rather than a date picker. `h/j/k/l`
walks it (off the edge turns the page), `[` and `]` step months, `Enter` opens
the day under the cursor.

The settings page — the cog, or `s` — edits the vault, the daily-note pattern,
the two section headings and the template, with today's note resolved live
underneath the pattern so you can see it land. A field saves when you leave
it; `Esc` puts it back. Vault and template file have a folder button beside
them — that is `omarchy-file-select`, Omarchy's own portal-backed chooser, so
there is no picker here to maintain and no new dependency. The panel closes
while the dialog is up (it is another window taking focus) and reopens on the
same page afterwards. The panel does not parse or write `config.toml`: it
runs `bujo config get`, `check` and `set`, so what counts as a usable vault,
pattern or template is decided in one place and it is the CLI. That is also
why a Templater `<% %>` template turns red while you type it rather than at
the moment a note fails to be created.

Statuses are drawn, not set in a font — a shared box plus one mark inside it,
so the column reads as one family and there is no glyph roulette across Nerd
Font versions.

If you would rather not run the QML plugin, `bujo bar` still emits
Waybar-style JSON for a plain command module:

```json
{ "id": "bujo", "type": "command", "exec": "bujo bar", "interval": 30 }
```

## Keybindings

Hyprland keybinds are not a plugin's to register — the plugin exposes the IPC
route and the binding lives in your dotfiles, the same way Omarchy binds its
own surfaces (`o.bind("SUPER + CTRL + E", "Emojis", "omarchy-shell shell toggle
omarchy.emojis")`):

```lua
o.bind("SUPER + CTRL + J", "Todos", "omarchy-shell shell toggle io.github.jonashan.bujo")
o.bind("SUPER + CTRL + ALT + J", "Capture a todo", "bujo add-interactive")
o.bind("SUPER + CTRL + SHIFT + J", "Jot a note", "bujo note-interactive")
```

One letter, three surfaces: `J` opens the panel, `+ALT` captures a todo,
`+SHIFT` jots a note. `J` for journal — every other letter in the `SUPER +
CTRL` row is already taken by an Omarchy default except G, M, U and Y, while
the whole `SUPER + CTRL + SHIFT` row is free.

## Checks

```bash
python3 test_bujo.py
omarchy-plugin-validate ~/.config/omarchy/plugins/io.github.jonashan.bujo
ln -sfn /usr/share/omarchy/shell /tmp/qmlimports/qs
/usr/lib/qt6/bin/qmllint -I /tmp/qmlimports plugin/*.qml
```

`qmllint` needs `qs.Commons` / `qs.Ui` reachable, which the shell normally
resolves through its own import interception — hence the symlink. What remains
after that are warnings every first-party plugin also produces: `Loader.item`
is typed `QObject`, so the panel methods reached through it cannot be checked
statically.

## Built / not built

- **P0 · CLI** — done. Section contract, path patterns, verify-before-write.
- **P1 · bar counts** — done, `bujo bar`.
- **P2 · panel** — done. Quickshell bar widget plus keyboard-driven panel.
- **P3 · quick notes** — done. `- ` bullets into `## Log`, same plumbing.
- **P4 · settings** — done. A page in the panel over `bujo config`.
- **P5 · previous days** — done. `h`/`l` steps the day, `c` opens a month, and
  both views show the log beside the todos.
- **P6 · editing** — done. `e` on any row, todo or note, through the same
  verified-ref write as every other verb.

Known ceiling: if `omarchy-file-select` is missing — an Omarchy older than this
plugin supports — the folder button does nothing rather than saying so;
surfacing a failed helper needs an error line the panel does not have yet. Type
the path instead.

Notes still carry no status and need no decision — `x`, `d` and `m` are
refused on one. What they gained is `e`: fixing a typo in what you wrote is not
a decision about it, and going to Obsidian for that was the tax.

Editing a migrated task breaks the text tying it to the copy at its target, so
undoing that move afterwards leaves the copy alone rather than taking it back.
That is the same rule migrations already followed — a copy that no longer
matches is somebody's work — and you are told when it applies.

Navigation stops at today. Migrating a task forward puts it on a day you
cannot step to — the calendar still shows its dot, and the task comes to you
when that day arrives. Add a forward step if looking ahead turns out to be
worth a key.

Known ceiling: `m` opens a free-text prompt rather than the fixed rows
(tomorrow / next week / pick a date) the design calls for. Upgrade when the
common cases turn out to be worth a keystroke each.

## Tests

```bash
python3 test_bujo.py
```

No framework. Covers what would silently corrupt notes: the section contract,
the path↔date round trip, and verify-before-write.
