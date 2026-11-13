### Changed

- **`tools/tree_sweep.sh` stops a compile that hangs** (Agora #794).
  Each compile runs under `NURL_SWEEP_TIMEOUT` (default 120 s). One that
  runs past it is recorded as `exit=timeout`, and the summary names every
  timed-out file first; a hang used to hold the sweep forever and report
  nothing. A file whose compile takes more than `NURL_SWEEP_SLOWER` times
  as long with the new compiler (default 5, compiles of a second or more)
  is reported too.
