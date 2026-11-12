### Fixed

- **A closure run through a copy ends the views of what it changes**
  (Agora #686). `: ( @ v ) c \ → v { ( vec_reserve [u] xs 4096 ) }` run as
  `( c )` ends a Slice of `xs`, but run as `: ( @ v ) d c  ( d )` it did
  not, and the Slice read freed memory. The same held for an alias of an
  alias, `= d c`, a ternary or match or block value, a literal chosen by an
  arm or assigned in one, a literal assigned below the run in a loop (the
  next round runs it), and the copy handed to a function that runs it. A
  closure's effects now follow the closure, not the name its literal was
  bound to. A closure that only reads what it captured is accepted through
  every route.
