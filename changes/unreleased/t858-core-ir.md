### Added

- **`nurlc --emit-core` prints the core IR** (AGORA-858, stage S1 of
  `docs/dev/PROPOSAL_CORE_IR.md`). The compiler builds, as it compiles,
  each function's variables and statements in evaluation order: every
  producer (a call, a literal, a join, a value block, a closure, a try)
  bound to a temporary before anything consumes it, every value read a
  place (a variable and a path). Nothing reads the IR yet: the ownership
  rules decide what they decided, and without the flag the compiler
  emits the same bytes. `docs/dev/CORE_IR.md` describes the IR and how
  the walk builds it; `compiler/tests/core_ir.sh` holds it complete (no
  construct left `opaque`, over its shapes and the compiler's own
  source); `tools/ncore --nurlc` runs the reference checker on it.
