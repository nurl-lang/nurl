### Fixed

- **The hole-probe gate no longer counts "could not tell" as a pass**
  (Agora #232). `tools/fuzz/holes/check.sh` counted a probe whose build
  failed for any reason as REJECTED, and a probe whose sanitizer build
  produced no binary, or whose run hit the time limit, as "ran clean". So
  a machine without the ASan runtime (`libclang_rt.asan`), or a tree
  without `stdlib/runtime.o`, reported `holes: 0` with real holes in the
  corpus: in a fresh worktree all 935 probes "passed" in 7 s. Those cases
  are now UNCHECKED, and the exit status counts them with the holes
  (capped at 255). REJECTED now requires one of nurlc's diagnostics, an
  error located in a source file (`f.nu:LINE:COL: error:`); a missing
  runtime object or a linker failure is not one.
  `HOLES_TIMEOUT` sets the run limit (default 60 s).
  `tools/tests/test_holes_check.py` stands in for the toolchain and runs
  in CI.
