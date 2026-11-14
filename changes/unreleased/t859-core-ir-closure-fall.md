### Fixed

- `nurlc --emit-core`: a closure body that falls off with the value of a tail `?` / `??` (no `^`) has its `ret` in the core IR, as a function's body has. The IR said `ret c`, a constant, and the reference checker lost what such a closure hands back. `compiler/tests/core_ir.sh` checks both shapes. (AGORA-859)
