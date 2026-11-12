### Fixed

- **A returned join of a `( mem_dup a )` copy and a fresh value lends
  nothing of `a`** (Agora #767). `^ ? c ( mem_dup a ) ( mks … )` (either
  order, a block arm, a nested join, `??` arms) was summarised as lending
  `a`, so the caller's result was taken for a borrow of its argument and
  refused once the argument was handed on. A copy of a type that holds no
  view owns all it holds; a copy of a view holder still lends what it
  views.
