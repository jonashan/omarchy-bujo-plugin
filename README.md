# bujo

Bullet-journal todos that live in Obsidian daily notes, driven from the Omarchy
command palette and bar. Markdown is the database; this is the only thing that
writes it.

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
ln -s ~/Work/bujo/bujo ~/.local/bin/bujo
```

First run writes `~/.config/bujo/config.toml`. The two settings that matter:

- `path` — where daily notes live, as a pattern. One string covers core Daily
  notes, Periodic Notes and journals users alike, so nothing has to know which
  plugin you run. Month names render from a fixed English table, never the
  system locale.
- `template` (or `template_file`) — rendered **once**, when a note has to be
  created for a future day, and never read again. Entirely yours. Templater
  `<% %>` syntax is refused rather than half-rendered, since only Obsidian can
  run it.

## Use

```
bujo add "call the accountant" friday    # tomorrow, next monday, +3 days, 2026-09-22
bujo list                                # today plus everything dangling
bujo list --dangling --json
bujo done <ref>                          # [x] + ✅ today
bujo drop <ref>                          # [-]
bujo move <ref> tomorrow                 # [>] here, a fresh [ ] there
bujo bar                                 # waybar-style JSON for the bar
```

A `ref` is `path:line:hash`. The hash is checked before every write, so a task
that Obsidian edited under a live panel is refused rather than acted on at the
wrong line.

## Omarchy

Palette entry — `~/.config/omarchy/extensions/omarchy-menu.jsonc`:

```jsonc
"todo": {"icon":"","label":"Todo","aliases":["task","t"],"action":"bujo add-interactive"}
```

Bar counts — `~/.config/omarchy/shell.json`, under `bar.layout.<section>`:

```json
{ "id": "bujo", "type": "command", "exec": "bujo bar", "interval": 30, "tooltip": "Todos" }
```

## Built / not built

- **P0 · CLI** — done. Section contract, path patterns, verify-before-write.
- **P1 · bar counts** — done, `bujo bar`.
- **P2 · panel** — not started. Quickshell plugin, `j/k` + `m/c/d`, reads on
  open and polls while visible.
- **P3 · quick notes** — `- ` bullets into `## Log`, same plumbing.

## Tests

```bash
python3 test_bujo.py
```

No framework. Covers what would silently corrupt notes: the section contract,
the path↔date round trip, and verify-before-write.
