### Fixed

- **A view stored into one share of an Rc is held by every share**
  (Agora #392). `: ( Rc W ) r2 ( rc_clone [W] r )`, then `rc_set` of a
  `W { ( string_data s ) }` through r2 (directly, or inside a callee),
  then a read through `r` after `s` ended: a heap-use-after-free. An Rc's
  state is one for all its clones. The walk now records a binding bound
  to `rc_clone` of another as one Rc family, and a dependency stored into
  one share is added to every share of the family. rc_set of a
  literal-only value is accepted as before.
