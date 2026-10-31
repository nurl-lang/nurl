### Added

- **Deterministic simulation: `unikernel/build_nolibc.sh --sim`** (Agora
  #260, DST 2/4). A program built with `--sim` runs on the cooperative
  runtime the unikernel uses — threads and fibers as coroutines,
  cooperative mutexes and condition variables, a report instead of a
  hang — with the three doors to the outside world closed by a seed:
  time is virtual (it moves when the program sleeps and jumps to the
  earliest timer when nothing is runnable), `getrandom` is a seeded
  stream, and the next runnable coroutine is picked by the seed
  (`NURL_SIM=0` keeps FIFO). One seed replays a run byte for byte; a sweep
  of seeds tries interleavings FIFO never would. `NURL_SIM_TRACE=1`
  prints the schedule's hash and the virtual time at exit, and
  `NURL_SIM_LIMIT_MS` stops a run that never finishes.
  `compiler/tests/net_sim_http.nu` — a server thread and a client over
  the simulated network, through a partition and a heal — simulates
  660 ms in about 2 ms. `unikernel/run_sim_tests.sh` gates it in CI:
  the hosted golden under five seeds, byte-identical runs under one,
  different schedules across seeds where there is a choice to make, and
  more time simulated than taken. The real runtime is untouched (a
  simulation is a different link).

### Fixed

- **An HTTP server links on the freestanding runtime**: `runtime_bare.c`
  answers `nurl_signal_pending` (no signal is ever pending) and
  `nurl_signal_install_shutdown` (there is nothing to arm) — the two
  symbols `net_sim_http` was missing under `run_nolibc_tests.sh`.
- **`runtime_run` may be called from a thread on the freestanding
  runtime** (Agora #273). Called from a coroutine — a thread that runs a
  fiber server, `http_app_async` inside `thread_spawn` — it drove the
  scheduler as the main context does, nested inside the coroutine and
  waiting for a count that included the caller itself, so the server
  never finished (`net_sim_http_async` hung under
  `run_nolibc_tests.sh`). From a coroutine it now waits for the spawned
  fibers — what the hosted runtime's `runtime_run` waits for — parked
  until the last one ends; from the main context it still runs every
  coroutine, detached threads included, to the end.
