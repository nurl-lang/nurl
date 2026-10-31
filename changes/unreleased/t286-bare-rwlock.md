### Added

- **`RwLocked` (std/rwlock.nu) in the no-libc runtime and under
  `--sim`, so nurldb links there** (Agora #286, for DST 4/4 #262).
  `unikernel/runtime_bare.c` now has the hosted `nurl_rwlock_*` with the
  hosted semantics. A holder that re-reads a lock it already reads is
  counted. Asking for a lock its holder already has panics with the same
  message instead of waiting for itself. The try forms take a lock only
  when that needs no waiting. On the cooperative scheduler, waiters queue
  in arrival order and an unlock hands the lock straight to the head of
  the queue: one writer, or every reader up to the next writer. A reader
  that arrives while a writer waits queues behind it, so readers cannot
  starve a writer. The main context waits in the same queue. sched_gate
  asserts these schedules as traces, plus a deadlock scenario and a
  three panic-not-deadlock scenarios. Five corpus tests move from
  NEEDS-BARE to PASS in the no-libc run: `rwlock_basic`,
  `rwlock_relock_panics`, `block_after_cond`, `block_value_scope` and
  `drop_guard_field_only`. nurldb's own suites pass on the no-libc
  runtime: bufpool, conc, wal and db. `conc_test` also passes under
  `--sim` for every seed tried, each seed with its own schedule and the
  same seed replaying it byte for byte.
