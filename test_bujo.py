#!/usr/bin/env python3
"""Run me: python3 test_bujo.py

No framework. Covers the parts that would silently corrupt notes if wrong:
the section contract, the path<->date round trip, and verify-before-write.
"""
import importlib.util
import tempfile
from importlib.machinery import SourceFileLoader
from datetime import date, timedelta
from pathlib import Path

_src = str(Path(__file__).parent / "bujo")
spec = importlib.util.spec_from_file_location("bujo", _src, loader=SourceFileLoader("bujo", _src))
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)


# vault and path ship empty, so tests that exercise notes supply their own.
TEST_PATH = "05. Journals/Daily/{{date:YYYY}}/{{date:MMMM}}/{{date:YYYY-MM-DD}}.md"


def cfg_for(root):
    c = dict(b.DEFAULTS)
    c["vault"] = Path(root)
    c["path"] = TEST_PATH
    return c


class Args:
    def __init__(self, **kw):
        self.__dict__.update(kw)


def test_date_tokens():
    d = date(2026, 9, 6)
    assert b.fmt_date("YYYY-MM-DD", d) == "2026-09-06"
    assert b.fmt_date("YYYY/MMMM", d) == "2026/September"
    assert b.fmt_date("ddd D MMM", d) == "Sun 6 Sep"
    # MM must not eat the front of MMMM
    assert b.fmt_date("MMMM MM M", d) == "September 09 9"
    assert b.render("# {{date:YYYY-MM-DD}}", d) == "# 2026-09-06"


def test_path_round_trip():
    c = cfg_for("/tmp/x")
    matcher, kinds = b.path_matcher(c)
    for d in (date(2026, 1, 1), date(2026, 9, 16), date(2026, 12, 31)):
        rel = b.render(c["path"], d)
        assert b.path_to_date(matcher, kinds, rel) == d, rel
    # the filename is the most specific source, so it wins a disagreement
    assert b.path_to_date(matcher, kinds, "05. Journals/Daily/2025/August/2026-09-16.md") == date(2026, 9, 16)
    # an unreadable month folder (another locale, a typo) falls back to the
    # numeric month rather than dropping the note off the radar entirely
    assert b.path_to_date(matcher, kinds, "05. Journals/Daily/2026/Septober/2026-09-16.md") == date(2026, 9, 16)
    # anything outside the journal tree is simply not ours
    assert b.path_to_date(matcher, kinds, "06. Archived/notes.md") is None
    assert b.path_to_date(matcher, kinds, "05. Journals/Daily/2026/September/scratch.md") is None


def test_section_contract():
    lines = ["---", "tags: [x]", "---", "# 2026-09-16", "",
             "## Journal", "- [ ] a stray checkbox that is not ours", "",
             "## Todo", "- [ ] ours", "",
             "## Log", "- a note"]
    first, last = b.section_bounds(lines, "## Todo")
    body = lines[first:last]
    assert body == ["- [ ] ours", ""], body
    # the stray checkbox under ## Journal is outside our bounds
    assert not any("stray" in l for l in body)


def test_ensure_section_appends_at_bottom():
    lines = ["# 2026-09-16", "", "# Links", "[[2026-September]]", "", ""]
    before = list(lines)
    b.ensure_section(lines, "## Todo")
    assert lines[-1] == "## Todo"
    assert lines[:len(before) - 2] == before[:-2], "existing content was rewritten"
    # idempotent
    again = list(lines)
    b.ensure_section(lines, "## Todo")
    assert lines == again


def test_add_done_drop_move_round_trip():
    with tempfile.TemporaryDirectory() as root:
        c = cfg_for(root)
        today = date.today()
        tomorrow = today + timedelta(days=1)

        b.cmd_add(c, Args(text="call the accountant", when=""))
        b.cmd_add(c, Args(text="book the dentist", when=""))
        rows = b.today_tasks(c, today)
        assert [r["clean"] for r in rows] == ["call the accountant", "book the dentist"]
        assert all(r["status"] == b.OPEN for r in rows)

        b.cmd_done(c, Args(ref=rows[0]["ref"]))
        rows = b.today_tasks(c, today)
        assert rows[0]["status"] == b.DONE
        assert rows[0]["text"].endswith("✅ %s" % today.isoformat())
        assert rows[0]["clean"] == "call the accountant"

        b.cmd_move(c, Args(ref=rows[1]["ref"], when=tomorrow.isoformat()))
        rows = b.today_tasks(c, today)
        # the origin day keeps the record
        assert rows[1]["status"] == b.MIGRATED
        assert rows[1]["text"].endswith("→ [[%s]]" % tomorrow.isoformat())
        # and the target got a fresh open copy
        moved = b.tasks_in(c, b.note_path(c, tomorrow), tomorrow)
        assert [m["clean"] for m in moved] == ["book the dentist"]
        assert moved[0]["status"] == b.OPEN

        b.cmd_drop(c, Args(ref=moved[0]["ref"]))
        assert b.tasks_in(c, b.note_path(c, tomorrow), tomorrow)[0]["status"] == b.DROPPED


def test_every_action_toggles_back():
    with tempfile.TemporaryDirectory() as root:
        c = cfg_for(root)
        b.cmd_add(c, Args(text="a task", when=""))

        ref = lambda: b.today_tasks(c)[0]["ref"]
        b.cmd_done(c, Args(ref=ref()))
        assert b.today_tasks(c)[0]["status"] == b.DONE
        b.cmd_done(c, Args(ref=ref()))
        row = b.today_tasks(c)[0]
        # back to open, and the done stamp went with it
        assert row["status"] == b.OPEN and row["text"] == "a task"

        b.cmd_drop(c, Args(ref=ref()))
        assert b.today_tasks(c)[0]["status"] == b.DROPPED
        b.cmd_drop(c, Args(ref=ref()))
        assert b.today_tasks(c)[0]["status"] == b.OPEN


def test_undoing_a_migration_takes_the_copy_back():
    with tempfile.TemporaryDirectory() as root:
        c = cfg_for(root)
        today = date.today()
        friday = today + timedelta(days=3)
        b.cmd_add(c, Args(text="a task", when=""))

        b.cmd_move(c, Args(ref=b.today_tasks(c)[0]["ref"], when=friday.isoformat()))
        assert b.today_tasks(c)[0]["status"] == b.MIGRATED
        assert len(b.tasks_in(c, b.note_path(c, friday), friday)) == 1

        # m again, with no day, takes it back
        b.cmd_move(c, Args(ref=b.today_tasks(c)[0]["ref"], when=""))
        row = b.today_tasks(c)[0]
        assert row["status"] == b.OPEN and row["text"] == "a task"
        assert b.tasks_in(c, b.note_path(c, friday), friday) == []


def test_undo_never_discards_work_done_at_the_target():
    with tempfile.TemporaryDirectory() as root:
        c = cfg_for(root)
        today = date.today()
        friday = today + timedelta(days=3)
        b.cmd_add(c, Args(text="a task", when=""))
        b.cmd_move(c, Args(ref=b.today_tasks(c)[0]["ref"], when=friday.isoformat()))

        # the copy gets completed at the target before we change our mind
        b.cmd_done(c, Args(ref=b.tasks_in(c, b.note_path(c, friday), friday)[0]["ref"]))
        b.cmd_move(c, Args(ref=b.today_tasks(c)[0]["ref"], when=""))

        assert b.today_tasks(c)[0]["status"] == b.OPEN
        survivor = b.tasks_in(c, b.note_path(c, friday), friday)
        assert len(survivor) == 1 and survivor[0]["status"] == b.DONE


def test_settling_a_migrated_task_clears_the_copy_at_the_target():
    for verb, status in ((b.cmd_done, b.DONE), (b.cmd_drop, b.DROPPED)):
        with tempfile.TemporaryDirectory() as root:
            c = cfg_for(root)
            tomorrow = date.today() + timedelta(days=1)
            b.cmd_add(c, Args(text="call the bank", when=""))
            b.cmd_move(c, Args(ref=b.today_tasks(c)[0]["ref"], when=tomorrow.isoformat()))
            assert len(b.tasks_in(c, b.note_path(c, tomorrow), tomorrow)) == 1

            # settled at the origin, so there is nothing left waiting tomorrow
            verb(c, Args(ref=b.today_tasks(c)[0]["ref"]))
            assert b.today_tasks(c)[0]["status"] == status
            assert b.tasks_in(c, b.note_path(c, tomorrow), tomorrow) == [], verb.__name__


def test_settling_a_migration_leaves_work_already_done_at_the_target():
    with tempfile.TemporaryDirectory() as root:
        c = cfg_for(root)
        tomorrow = date.today() + timedelta(days=1)
        b.cmd_add(c, Args(text="call the bank", when=""))
        b.cmd_move(c, Args(ref=b.today_tasks(c)[0]["ref"], when=tomorrow.isoformat()))

        # it got done at the target before we settled the origin
        b.cmd_done(c, Args(ref=b.tasks_in(c, b.note_path(c, tomorrow), tomorrow)[0]["ref"]))
        b.cmd_done(c, Args(ref=b.today_tasks(c)[0]["ref"]))

        survivor = b.tasks_in(c, b.note_path(c, tomorrow), tomorrow)
        assert len(survivor) == 1 and survivor[0]["status"] == b.DONE


def test_settling_a_migration_into_the_same_note_keeps_its_own_line():
    # moving to today writes the copy into the note the [>] line lives in, so
    # removing it shifts the line the caller is about to rewrite
    with tempfile.TemporaryDirectory() as root:
        c = cfg_for(root)
        today = date.today()
        b.cmd_add(c, Args(text="one", when=""))
        b.cmd_add(c, Args(text="two", when=""))
        two = b.today_tasks(c)[1]["ref"]
        b.cmd_move(c, Args(ref=two, when=today.isoformat()))
        assert [t["clean"] for t in b.today_tasks(c)] == ["one", "two", "two"]

        b.cmd_done(c, Args(ref=b.today_tasks(c)[1]["ref"]))
        rows = b.today_tasks(c)
        assert [(t["clean"], t["status"]) for t in rows] == [("one", b.OPEN), ("two", b.DONE)]


def test_stale_ref_is_refused():
    with tempfile.TemporaryDirectory() as root:
        c = cfg_for(root)
        b.cmd_add(c, Args(text="one", when=""))
        ref = b.today_tasks(c)[0]["ref"]
        # Obsidian edits the line under a live panel
        p = b.note_path(c, date.today())
        p.write_text(p.read_text().replace("- [ ] one", "- [ ] one, edited"), encoding="utf-8")
        try:
            b.resolve_ref(c, ref)
        except SystemExit as e:
            assert "changed under us" in str(e)
        else:
            assert False, "a stale ref must not be actionable"


def test_dangling_is_unbounded():
    with tempfile.TemporaryDirectory() as root:
        c = cfg_for(root)
        old = date.today() - timedelta(days=400)
        b.cmd_add(c, Args(text="ancient debt", when=old.isoformat()))
        b.cmd_add(c, Args(text="today's work", when=""))
        late = b.dangling(c)
        assert [t["clean"] for t in late] == ["ancient debt"], late


def test_trailing_date_split():
    text, d = b.split_trailing_date("call the accountant friday")
    assert text == "call the accountant"
    assert d.weekday() == 4 and d >= date.today()
    # a month word that resolves to the past is a word, not a date
    text, d = b.split_trailing_date("pay the january invoice")
    assert text == "pay the january invoice"
    assert d == date.today()
    # no date at all
    text, d = b.split_trailing_date("book the dentist")
    assert text == "book the dentist" and d == date.today()


def test_notes_land_in_the_log_and_stay_out_of_the_list():
    with tempfile.TemporaryDirectory() as root:
        c = cfg_for(root)
        b.cmd_add(c, Args(text="a real todo", when=""))
        b.cmd_note(c, Args(text="shipped the invoice"))
        b.cmd_note(c, Args(text="- [ ] a checkbox typed into the log by hand"))

        body = b.note_path(c, date.today()).read_text()
        assert "## Todo" in body and "## Log" in body
        assert "- shipped the invoice" in body

        # the log is not ours to read: nothing under ## Log reaches the list,
        # not even something shaped exactly like a task
        rows = b.today_tasks(c)
        assert [r["clean"] for r in rows] == ["a real todo"], rows


def test_sections_do_not_bleed_into_each_other():
    with tempfile.TemporaryDirectory() as root:
        c = cfg_for(root)
        b.cmd_note(c, Args(text="first note"))
        b.cmd_add(c, Args(text="first todo", when=""))
        b.cmd_note(c, Args(text="second note"))

        lines = b.read_lines(b.note_path(c, date.today()))
        todo_first, todo_last = b.section_bounds(lines, "## Todo")
        log_first, log_last = b.section_bounds(lines, "## Log")
        assert [l for l in lines[todo_first:todo_last] if l.strip()] == ["- [ ] first todo"]
        assert [l for l in lines[log_first:log_last] if l.strip()] == ["- first note", "- second note"]


def test_the_log_reads_back_as_notes():
    with tempfile.TemporaryDirectory() as root:
        c = cfg_for(root)
        b.cmd_add(c, Args(text="a real todo", when=""))
        b.cmd_note(c, Args(text="shipped the invoice"))
        b.cmd_note(c, Args(text="accountant wants Q3 numbers"))

        notes = b.notes_in(c, b.note_path(c, date.today()), date.today())
        assert [n["text"] for n in notes] == ["shipped the invoice", "accountant wants Q3 numbers"]
        # the todo stays out of the log, the same way the log stays out of the list
        assert not any("a real todo" in n["text"] for n in notes)
        # notes carry no ref: there is nothing about one to decide
        assert all("ref" not in n for n in notes)

        # a day with no note at all reads as no notes, not as a crash
        assert b.notes_in(c, b.note_path(c, date.today() + timedelta(days=5)), date.today()) == []


def test_a_month_is_counted_in_one_walk():
    with tempfile.TemporaryDirectory() as root:
        c = cfg_for(root)
        today = date.today()
        first, last = b.month_range(b.fmt_date("YYYY-MM", today))

        b.cmd_add(c, Args(text="still open", when=today.isoformat()))
        b.cmd_add(c, Args(text="finished", when=today.isoformat()))
        b.cmd_done(c, Args(ref=b.today_tasks(c)[1]["ref"]))
        b.cmd_note(c, Args(text="a note"))
        # a day inside the month that only ever got a note
        other = first if first != today else first + timedelta(days=1)
        b.append_to_section(c, other, c["log_section"], "- noted, nothing to do")

        rows = {r["day"]: r for r in b.walk_days(c, first, last)}
        assert rows[today.isoformat()]["open"] == 1
        assert rows[today.isoformat()]["done"] == 1
        assert rows[today.isoformat()]["notes"] == 1
        # a note-only day still shows up — the calendar has to know it exists
        assert rows[other.isoformat()] == {"day": other.isoformat(), "todos": 0,
                                           "open": 0, "done": 0, "notes": 1}
        # and days outside the range are not in the walk at all
        assert all(first.isoformat() <= d <= last.isoformat() for d in rows)


def test_month_range_rolls_the_year():
    assert b.month_range("2026-12") == (date(2026, 12, 1), date(2026, 12, 31))
    assert b.month_range("2026-02") == (date(2026, 2, 1), date(2026, 2, 28))
    assert b.month_range("2024-02") == (date(2024, 2, 1), date(2024, 2, 29))
    assert b.month_range("not-a-month") == (None, None)


def test_clean_text_strips_our_own_marks():
    assert b.clean_text("ship it ✅ 2026-09-16") == "ship it"
    assert b.clean_text("ship it → [[2026-09-18]]") == "ship it"
    assert b.clean_text("ship it") == "ship it"


# ------------------------------------------------------------------- settings
#
# The panel reads these three commands and never touches config.toml, so
# every rule it renders has to hold here first.


def with_config(root):
    """Point the module's config at a temp file and hand back its path."""
    b.CONFIG_PATH = Path(root) / "bujo" / "config.toml"
    return b.CONFIG_PATH


def test_config_survives_a_round_trip_through_toml():
    # A template carrying the things that break naive TOML quoting: a
    # backslash, embedded quotes, a triple quote, and a closing quote right
    # against the delimiter.
    nasty = '---\naliases: ["a \\"b\\""]\npath: C:\\Users\n---\n\nsaid: """hi"""\nends: "'
    with tempfile.TemporaryDirectory() as root:
        with_config(root)
        cfg = dict(b.DEFAULTS)
        cfg["template"] = nasty
        cfg["urgent_days"] = 3
        b.write_config(cfg)
        assert b.read_config() == cfg, b.CONFIG_PATH.read_text()

        # and the default file is writable at all — it is what a fresh
        # machine gets before anything else runs
        b.CONFIG_PATH.unlink()
        assert b.read_config() == dict(b.DEFAULTS)

        # the template stays readable in the file rather than folded onto
        # one line with \n in it
        assert '"""' in b.CONFIG_PATH.read_text()


def test_config_set_writes_one_key_and_refuses_a_typo():
    with tempfile.TemporaryDirectory() as root:
        with_config(root)
        b.cmd_config_set(b.read_config(), Args(key="section", value="## Tasks"))
        assert b.read_config()["section"] == "## Tasks"
        # everything else survived the rewrite
        assert b.read_config()["template"] == b.DEFAULTS["template"]

        b.cmd_config_set(b.read_config(), Args(key="urgent_days", value="14"))
        assert b.read_config()["urgent_days"] == 14, "ints must not land as strings"

        for key, value in (("secton", "## Tasks"), ("urgent_days", "soon")):
            try:
                b.cmd_config_set(b.read_config(), Args(key=key, value=value))
            except SystemExit:
                pass
            else:
                assert False, "%s=%s should not be settable" % (key, value)


def test_check_flags_a_path_no_date_reads_back_out_of():
    c = cfg_for("/tmp/x")
    ok = b.check_config(dict(c))
    assert ok["fields"]["path"]["ok"]
    assert ok["fields"]["path"]["preview"] == b.render(c["path"], date.today())

    # a pattern with no date in it at all: every note would look undated, and
    # nothing would ever show up as dangling
    c["path"] = "05. Journals/Daily/notes.md"
    bad = b.check_config(dict(c))
    assert not bad["ok"] and not bad["fields"]["path"]["ok"]

    # a year and a month but no day never yields a date either
    c["path"] = "{{date:YYYY}}/{{date:MMMM}}.md"
    assert not b.check_config(dict(c))["fields"]["path"]["ok"]


def test_check_surfaces_templater_before_it_is_saved():
    with tempfile.TemporaryDirectory() as root:
        c = cfg_for(root)
        c["template"] = "# <% tp.date.now() %>\n"
        out = b.check_config(dict(c))
        assert not out["ok"] and "Templater" in out["fields"]["template"]["note"]

        # and the same template arriving via a file is refused the same way,
        # because ensure_note asks the one helper both paths share
        c["template"] = b.DEFAULTS["template"]
        Path(root, "tpl.md").write_text("# <% tp.date.now() %>\n", encoding="utf-8")
        c["template_file"] = "tpl.md"
        out = b.check_config(dict(c))
        assert not out["ok"] and "Templater" in out["fields"]["template_file"]["note"]
        try:
            b.ensure_note(c, date.today())
        except SystemExit as e:
            assert "Templater" in str(e)
        else:
            assert False, "a Templater template must not create a note"


def test_check_makes_the_template_precedence_visible():
    with tempfile.TemporaryDirectory() as root:
        c = cfg_for(root)
        assert b.check_config(dict(c))["source"] == "inline"

        Path(root, "tpl.md").write_text("# {{date:YYYY-MM-DD}}\n", encoding="utf-8")
        c["template_file"] = "tpl.md"
        out = b.check_config(dict(c))
        # both fields say which one wins — two fields silently shadowing each
        # other is the whole failure mode here
        assert out["ok"] and out["source"] == "file"
        assert "overrides" in out["fields"]["template_file"]["note"]
        assert "overridden" in out["fields"]["template"]["note"]

        # and the file is what actually lands in a new note
        b.ensure_note(c, date.today())
        assert b.note_path(c, date.today()).read_text().startswith("# %s" % date.today().isoformat())

        c["template_file"] = "gone.md"
        assert not b.check_config(dict(c))["fields"]["template_file"]["ok"]


def test_check_guards_the_section_contract():
    c = cfg_for("/tmp/x")
    # reading stops at the next "## ", so a heading that isn't one would
    # swallow every section below it
    for heading in ("# Todo", "### Todo", "Todo", "## Todo "):
        bad = dict(c, section=heading)
        assert not b.check_config(bad)["fields"]["section"]["ok"], heading
    # one section cannot be both the todos and the log
    same = dict(c, log_section=c["section"])
    out = b.check_config(same)
    assert not out["fields"]["section"]["ok"] and not out["fields"]["log_section"]["ok"]


def test_picking_stores_the_path_the_setting_actually_wants():
    with tempfile.TemporaryDirectory() as root:
        with_config(root)
        vault = Path(root) / "vault"
        (vault / "Templates").mkdir(parents=True)
        (vault / "Templates" / "Daily.md").write_text("# {{date:YYYY-MM-DD}}\n", encoding="utf-8")

        real = b.run_or_none
        try:
            # cancelling the chooser is an answer, and it writes nothing
            b.run_or_none = lambda cmd: None
            b.cmd_config_pick(b.read_config(), Args(key="vault"))
            assert b.read_config()["vault"] == ""

            b.run_or_none = lambda cmd: str(vault)
            b.cmd_config_pick(b.read_config(), Args(key="vault"))
            assert b.read_config()["vault"] == str(vault)

            # template_file is vault-relative by definition, so an absolute
            # path out of the chooser has to be converted, not stored
            b.run_or_none = lambda cmd: str(vault / "Templates" / "Daily.md")
            b.cmd_config_pick(b.read_config(), Args(key="template_file"))
            assert b.read_config()["template_file"] == "Templates/Daily.md"

            # and one outside the vault is refused rather than stored broken
            b.run_or_none = lambda cmd: str(Path(root) / "elsewhere.md")
            try:
                b.cmd_config_pick(b.read_config(), Args(key="template_file"))
            except SystemExit as e:
                assert "outside the vault" in str(e)
            else:
                assert False, "a template outside the vault must be refused"
            assert b.read_config()["template_file"] == "Templates/Daily.md", "the refusal kept the old value"
        finally:
            b.run_or_none = real


def test_tildify_keeps_a_picked_path_readable():
    assert b.tildify(Path.home() / "Documents" / "Obsidian") == "~/Documents/Obsidian"
    assert b.tildify(Path("/mnt/vault")) == "/mnt/vault"


def test_check_says_where_it_looked_for_a_missing_vault():
    out = b.check_config(dict(b.DEFAULTS, vault="~/no-such-vault"))
    assert not out["fields"]["vault"]["ok"]
    assert str(Path.home() / "no-such-vault") in out["fields"]["vault"]["note"]


def test_a_fresh_install_is_unset_rather_than_pointed_somewhere():
    # Path("") expands to ".", a perfectly real directory. Unguarded, an empty
    # vault passes is_dir() and bujo writes todos into whatever directory it
    # happened to run in — so "not set" has to be its own answer.
    out = b.check_config(dict(b.DEFAULTS))
    assert not out["ok"]
    assert "not set" in out["fields"]["vault"]["note"]
    assert "not set" in out["fields"]["path"]["note"]
    assert out["fields"]["path"]["preview"] == ""

    with tempfile.TemporaryDirectory() as root:
        with_config(root)
        try:
            b.load_config()
        except SystemExit as e:
            assert "vault not set" in str(e)
        else:
            assert False, "every other command must refuse an unset vault"


if __name__ == "__main__":
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    real_config = b.CONFIG_PATH
    for t in tests:
        t()
        b.CONFIG_PATH = real_config   # with_config points it at a temp dir
        print("ok  %s" % t.__name__)
    print("\n%d passed" % len(tests))
