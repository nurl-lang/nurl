### Changed

- **formal: a `% Drop` destructor runs as code inside the calculus (A2,
  Agora #221).** A2's drops ran no program code, so `formal/CLAIM.md`
  listed every user destructor as outside the proof. A binding with a
  destructor (`letd`, scoped by `scopeD`) now runs it at the scope's end,
  on the binding lent, before the drop glue frees the tree. A panic that
  reaches the frame runs it once, frees the binding and raises again, so a
  destructor that panics during an unwind is covered too. Proving the
  panic path took a new invariant: no borrowed parameter depends on a
  scope opened inside its call (`Inv.pinOut`). `A2.memory_safe`,
  `A2.soundness`, `A2.no_leak_end` and `A2.no_leak_panic` are re-proven
  over the new statements (`formal/check.sh`, Lean 4.35.0, standard axioms
  only). This covers destructors of types that hold no views. Those that
  hold one need the `DtorSafe` rule (Agora #224) and are still listed in
  CLAIM.md.
