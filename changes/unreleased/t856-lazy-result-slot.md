### Performance

- **A function makes its result slot only when a return needs it** (AGORA-856). Every function with a result used to open with an `alloca` for it. Only two kinds of return use that slot: one under a `;` defer, which leaves its value there while the defers run, and the returns of an aggregate, which merge through it. Most functions have neither, so the slot was a dead line of IR in most functions. Now the first return that needs it makes it, as a closure body's return already did.
  - **`compiler/nurlc.nu`:** 1,744 fewer allocas, 2,819 fewer IR lines (−0.30 %).
  - **`compiler/tests/dst_flagship.nu`:** 2,544 fewer allocas, 2,591 fewer lines (−0.74 %).

  Programs run exactly as before: LLVM removed the unused slot anyway, so what shrinks is the IR nurlc prints and clang reads.
