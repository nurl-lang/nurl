### Added

- **Formal A2: a string literal handed back as a view is typed**
  (AGORA-980). The memory model gains a static literal's text block,
  `BKind.static`, which `Rhs.slit n` makes at fresh addresses before handing
  back a view of it. The view needs no dependency (`ValOK.sview`,
  `SViewAt`), and `RhsT.slit` types it. Preservation (`rhs_slit`) and
  progress cover the new step. The no-leak invariant covers the block's
  text, and the sweep frees the block once no view refers to it. Static
  text is no memory that a dependency tracks: `RootNode`'s view case now
  asks for a node of memory (`DataAtM`). A3's race-freedom proof allows a
  fresh address in a payload: `Step.payAt` gains the case of a new block
  that the step's own slots reach. No theorem statement is weakened and no
  axiom is added. The C checker and `tools/ncore/tolean.py` emit the rule
  in the next phase.
