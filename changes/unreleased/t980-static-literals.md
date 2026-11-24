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
  axiom is added. The verified checker infers the rule (C `inferRhs2`).
  `tools/ncore/tolean.py` translates a literal handed back as a view, and a
  borrowed-result function that hands back only literals, which it used to
  report as unsupported: seven more hole probes now translate, and the six
  that must be rejected are.
- **The verified checker accepts a return from inside a loop beside a
  fall-off result.** Its block rule asked every exit of a block to leave
  from exactly the block's end. It now joins the end with the exits'
  contexts when they differ, as it already joins an `if`'s arms, which A2's
  `Exits.blk` and `sub` allow. `bare_view_of_a_loop_element_over_a_param_handed_back_runs_clean`
  is accepted. Over the 154 translated sweep programs no other verdict
  changes, and all 99 that must be rejected still are.
