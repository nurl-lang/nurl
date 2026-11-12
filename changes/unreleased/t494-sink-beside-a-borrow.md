### Fixed

- **A container handed to a `sink` beside a borrow of its element is
  refused** (Agora #494). `( eat_then_read t e )` with `e` a `vec_at`
  borrow of `t`, or a closure over one, was accepted: the callee took `t`
  over, freed it, then read `e` (heap-use-after-free). The exclusive-call
  check now counts an argument a `sink` parameter takes over as one whose
  value the callee may end, as it counted one whose elements the callee
  drops, and says "which it takes over and may release". Read the borrow
  before the call, or pass a copy that owns its data.
