### Fixed

- **A type named like a library type is judged by what it is at a
  thread's edge** (Agora #714). A program's own struct named `Weak` (or a
  generic of that name) holding a PNCounter share crossed to other threads
  uncounted, because the run-time crossing check skipped any type named
  `Weak` or `Rc`. Eight threads then changed one counter (a double free).
  The crossing now panics, as for the same struct under another name.
  Under the same rule, a program's own `Rc` of numbers captured by a
  thread, and its own generic `Arc` holding a `Cell` moved into one, now
  compile: they were refused by name.
