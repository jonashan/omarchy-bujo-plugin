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


def cfg_for(root):
    c = dict(b.DEFAULTS)
    c["vault"] = Path(root)
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


def test_clean_text_strips_our_own_marks():
    assert b.clean_text("ship it ✅ 2026-09-16") == "ship it"
    assert b.clean_text("ship it → [[2026-09-18]]") == "ship it"
    assert b.clean_text("ship it") == "ship it"


if __name__ == "__main__":
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print("ok  %s" % t.__name__)
    print("\n%d passed" % len(tests))
