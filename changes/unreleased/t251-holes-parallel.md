### Changed

- **The hole-probe gate checks probes in parallel** (Agora #251, part 1).
  `tools/fuzz/holes/check.sh` compiled the ~960 probes one at a time,
  each twice (plain and under ASan): 6.6 minutes of CI's critical path.
  It now fans them out over the CPUs (`HOLES_JOBS`, default all of them).
  Each probe's verdict goes to its own file, and the report prints them in
  the order the probes were given, so the output is the same at any
  parallelism. #232's verdict rules are unchanged: REJECTED needs a
  located compile error, and UNCHECKED counts as a failure. A probe whose
  check printed nothing is UNCHECKED too.
