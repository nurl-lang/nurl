### Added

- **A first translation validator for the drops nurlc's code generation
  inserts** (formal phase D0, Agora #981). `tools/ncore/tv.sh prog.nu`
  checks the LLVM nurlc emits for `prog.nu`, one function at a time. On every
  path, each value a slot of the function's own frame comes to own is
  released or moved exactly once, through its drop flag: never overwritten
  or left at a return while owned, never released twice. A drop decided at
  run time (a per-call ownership answer) is reported unsupported rather than
  guessed. `tools/ncore/tv/selftest.sh` shows that it catches a missing
  release, a double release, an overwrite of an owned value and a move that
  leaves its flag set. Over `tools/ncore/certify` and the runs-clean hole
  probes it finds no mismatch.
