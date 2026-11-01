# formal/rules — the change rows of formal/RULES.md, one file per change

`formal/RULES.md`'s table "Changes to MEMORY.md and what they do to the
proof" says, for every change to an ownership rule, whether it touches a
proven rule and what it does to the proof: an **extension** (it rejects
more, and every proof still holds) or a **break** (it accepts more, and
the lemmas it reopens are named). Every ownership PR used to add its row
at the end of that table, so any two of them conflicted there (Agora
#299). Now each change's row is a file in this directory:

- **`t<N>.md`**, `N` = the change's Agora task: its row or rows, exactly
  as the table shows them, one line each,
  `| Change | MEMORY.md | Touches a proven rule? | Effect |`. A second
  file for the same task is `t<N>-<slug>.md`.
- **`t0.md`**: the rows of changes that had no task, the history from
  before the board.
- A PR that changes an ownership rule (THE LINE 6) **adds** its file; a
  PR that revises a row (a proof that lands later and marks it done, a
  wording fix) **edits** that row's file. Nobody edits the table in
  `RULES.md`.

`tools/formal_rules.py --write` writes the table, between its BEGIN/END
markers, from these files in task order. The release runs it
(RELEASING.md step 2, beside `open_list.py`), and release.yml's
`verify-ci` runs `--check` on the tag, so a released `RULES.md` holds
every row. CI's shared-files job runs `--lint` on every PR: each file is
named `t<N>.md` or `t<N>-<slug>.md` and holds only table rows of four
cells, and no row is in two files. Between releases the table lags
`main`: a change since the last release is in its file only.
