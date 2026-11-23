### Added

- **Formal A2: a static literal's text block** (AGORA-980). The memory
  model gains `BKind.static`, the kind of the block that holds a literal's
  text, and `Rhs.slit n`, which makes one at fresh addresses and hands back
  a view of it. The block's payload is its own tree, so the no-leak
  invariant covers it, and the sweep frees it once no view refers to it.
  The A3 race-freedom proof now allows a fresh address in a payload:
  `Step.payAt` gains the case of a new block that the step's own slots
  reach. No theorem statement is weakened and no axiom is added. Typing a
  literal handed back as a view (`ValOK.sview`, C6 `inferRhs2`) follows in
  the next phases.
