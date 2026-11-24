### Added

- **The drop validation also checks the LLVM against the core IR** (formal
  phase D0b, Agora #985). `tools/ncore/tv.sh prog.nu --ir` asks that a named
  binding the core IR never moves keeps its value to its scope end in the
  emitted LLVM: its flag is never cleared while it owns a value. Bindings are
  matched to slots by name through the `--g` build's debug declarations.
  `tools/ncore/tv/selftest.sh` shows that it catches a binding the LLVM hands
  on although the IR keeps it, which the conservation check alone accepts.
  It found that the core IR leaves out the operand `mem_forget` consumes.
