### Fixed

- **`term_read_line` edits UTF-8 text and counts terminal display columns**
  (Agora #506, `stdlib/std/term.nu`). `__term_edit` filtered input through
  `>= 32 && < 127`, so `nurllama chat`, `nurl repl` and the database/CLI
  prompts silently dropped every non-ASCII byte (`ä`, `ö`, `€`, CJK, emoji),
  stepped Left/Right and Backspace one byte at a time, walked the cursor back
  by byte length instead of column width on repaint, and spun on stdin EOF.
  The line editor now decodes 2–4-byte UTF-8 sequences (rejecting overlongs,
  surrogates, C1 controls and out-of-range scalars while recovering cleanly
  when a sequence is cut short), moves and deletes across UTF-8 character and
  combining-mark boundaries, counts 0/1/2-column widths when positioning the
  cursor, handles `Home`/`End`/`Delete` CSI/SS3 sequences without leaking
  `~`, repaints once per completed key or character, and returns `None` on
  stdin EOF.
