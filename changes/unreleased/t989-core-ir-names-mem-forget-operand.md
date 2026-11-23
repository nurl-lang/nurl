### Fixed

- **The core IR names the binding `mem_forget` gives up** (Agora #989).
  - `nurlc --emit-core` printed `( mem_forget x )` as `call mem_forget 0`,
    with no operand. So the IR said `x` lived to its scope end, while the
    generated code correctly cleared `x`'s drop flag there.
  - It now prints `call mem_forget 1 vK`, as every call names the operands
    it consumes.
  - The ownership engine's verdicts are unchanged. The emitted LLVM is
    byte-identical across the tree.
  - The drop validator (`tools/ncore/tv.sh --ir`) no longer reports
    `__dq_drop_elems` in `stdlib/std/deque.nu`.
