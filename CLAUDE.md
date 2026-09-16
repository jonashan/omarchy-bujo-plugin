# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
python3 test_bujo.py                                           # all tests
python3 -c "import test_bujo as t; t.test_path_round_trip()"   # one test
./install                                                      # deploy + restart the shell
```

Plugin checks the Omarchy developer guide requires, both expected to exit clean:

```bash
omarchy-plugin-validate ~/.config/omarchy/plugins/io.github.jonashan.bujo
mkdir -p /tmp/qmlimports && ln -sfn /usr/share/omarchy/shell /tmp/qmlimports/qs
qmllint -I /tmp/qmlimports plugin/*.qml
```

`qmllint` ships with Qt 6 and is often not on `PATH` (look in the Qt 6 `bin`
directory). It cannot resolve `qs.Commons` / `qs.Ui` on its own — the shell
normally supplies those through its own import interception, so the symlinked
import root stands in. Remaining warnings about members "not found on type
QObject" are unavoidable: `Loader.item` is typed `QObject`, so anything reached
through it is unresolvable statically. First-party plugins produce the same.

## Architecture

**The section contract is the whole design.** `bujo` owns exactly one heading
in a daily note — `## Todo` — appending it at the bottom if absent, and reads
**only** the lines between that heading and the next `## ` or EOF. This is why
there is no YAML parser and no markdown parser: frontmatter, journal prompts
and checkboxes elsewhere in the note are invisible by construction, so vaults
full of unrelated `- [ ]` lines need no filtering. `## Log` (notes) follows the
same rule. Two tests guard this boundary, including one that hand-types a
checkbox into `## Log` and asserts it never reaches the todo list — treat them
as load-bearing.

**`bujo` (Python, stdlib only) is the only thing that writes markdown.**
Everything else is a view over it, and there are three: the bar widget, the
panel, and whatever reads the files later (Obsidian, grep, an AI). Keep it that
way — front-ends are disposable, the files are not.

**Every mutation goes through `append_to_section` or a verified in-place line
rewrite.** A `ref` is `path:line:sha1[:8]`; `resolve_ref` re-hashes the target
line and refuses on mismatch, because Obsidian may have edited the file under a
live panel and shifted the lines. Never add a write path that skips this.

**Daily-note location is one `{{date:FORMAT}}` pattern**, not a reader for each
Obsidian daily-note plugin — one setting covers core Daily notes, Periodic
Notes and journals users alike. `path_matcher` compiles that pattern into a
regex that reads a date back out of a path; resolution is last-wins, so the
filename beats a folder that disagrees, and an unreadable month-name folder
falls back to the numeric month rather than dropping notes off the dangling
radar. Month names render from a fixed English table — never `date +%B`, which
yields localised names under a non-English `LC_TIME` and silently forks the
journal tree into a parallel directory.

**Liveness is pushed, not polled.** Every mutating command calls
`notify_shell()`, which pings the plugin's IPC target so a capture from the
palette appears immediately. The bar's own timer (30s closed, 1s while the
panel is open) is only a fallback for the one case with nothing to ping: a box
ticked inside Obsidian. Polling rather than watching is deliberate — an inotify
watch on a file breaks when that file is replaced by `rename()`, which is
exactly what the atomic writes do.

**Toggles, not one-way transitions.** `done`, `drop` and `move` all reverse on
a second press. Undoing a migration also removes the copy at the target — but
only while that copy is still open, since one already completed or edited there
is somebody's work.

Date parsing is delegated to GNU `date -d`. It handles "tomorrow", "friday",
"+3 days"; it does not do recurrence, which is the line where Tasks-plugin `🔁`
syntax would have to be adopted.

## Omarchy environment

These cost real debugging time and are not discoverable from the code.

- **Plugin QML does not hot-reload.** The running shell keeps the QML it
  started with. `Local plugin changed, reloading` in the log refers to the
  plugin *registry*, not live widgets — copying files over a running shell
  changes nothing. `./install` restarts the shell for this reason; do not
  remove that.
- **Never run `omarchy-refresh-shell`.** It resets `shell.json` to Omarchy
  defaults. The reload command is `omarchy-restart-shell`.
- **`bar.run()` passes its string through `bash -lc`**, so anything containing
  a space (a ref carries the note path, which usually has one) splits into
  extra arguments. Use `Util.execArgv(argv)`. `Process.command` is already an
  argv array and safe.
- **The plugin directory must contain real files.** `omarchy-plugin-validate`
  refuses symlinks inside a plugin folder, which is why `install` copies
  instead of linking.
- **The command palette cannot host a live list.** Menu `provider` rows resolve
  from a hardcoded map in the shell's `plugins/menu/Menu.qml`; third parties
  contribute static rows only. The palette can summon the panel, not be it.
  Palette entries themselves are static JSONC in
  `~/.config/omarchy/extensions/omarchy-menu.jsonc`.
- **Hyprland keybinds are not a plugin's to register.** The plugin exposes the
  IPC target (`omarchy-shell shell toggle io.github.jonashan.bujo`); bindings
  belong in the user's `~/.config/hypr/bindings.lua`.

## UI conventions

The panel composes the shell's own kit (`Panel`, `KeyboardPanel`,
`PanelKeyCatcher`, `PanelSectionHeader`, `PanelSeparator`, `WidgetButton`), so
theming is automatic — every component binds to `Color.*`. Follow the house
rules rather than inventing: monospace only, five palette roles
(`foreground` `background` `accent` `urgent` `muted`), `cornerRadius: 0`,
state expressed as alpha on foreground rather than a new hue (the selected row
is `foreground @ 8%` with `accent` text), and `urgent` reserved for the one
thing that should bother you.

Status marks are drawn on a `Canvas` (`StatusMark.qml`) rather than set in a
Nerd Font: glyph coverage varies by font version and a missing box would be a
tofu mid-list, while a painted mark takes the palette colour.

`PanelKeyCatcher` already supplies `j/k`, arrows, Enter and Escape; only
single-letter verbs need handling in `onTextKey`. Verbs that summon their own
Quickshell prompt must `root.close()` first rather than compete for keyboard
focus.

A bar widget sizes itself from its label. A widget that draws its own content
must set `fixedWidth` / `fixedHeight`, or it reports a slot smaller than it
paints and overlaps its neighbour.
