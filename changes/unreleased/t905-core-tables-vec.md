### Changed

- **The compiler's core IR builder keeps its tables in Vecs, and 88 of its 93 `unsafe` functions are safe code now** (AGORA-905). The ownership engine reads the core IR the walk builds under `--emit-core` / `--engine`. The builder's ten word tables were raw arrays, allocated, grown and freed by hand and reached by pointer, so every builder function had to be `unsafe`:
  - per function: statements, variables, places, the operand stack, temporaries;
  - per module: virtual callees, callees, pending arguments, types, functions.

  Each table is now a `( Vec i )` global. Only a handful of small inline accessors reach them: the tables, the stack of enclosing builders, and the strings behind interned ids. Each accessor says in a comment why it is sound: the walk's single-threaded state, never handed to another thread, every index bounds-checked, and interned strings that live for the whole compile. Two scratch buffers became local Vecs, and type-string bytes are read with the checked reader. Nothing in the builder is freed by hand any more. `compiler/nurlc.nu` now includes `stdlib/core/vec.nu`.
  - **Unsafe functions in the compiler:** 840 → 765.
  - **Output:** the printed core IR and the engine's verdicts are byte-identical on all 6,299 probes and tests. Ordinary compiles do not run this code.
  - **Cost:** `--engine` runs in the same wall time (the bounds checks cost 0.7 % more instructions on `gpu.nu`). Building the compiler itself also parses `vec.nu`.
