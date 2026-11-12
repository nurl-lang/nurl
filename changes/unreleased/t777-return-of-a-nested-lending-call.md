### Fixed

- **A return of a call's lend whose argument is itself a call lending a
  parameter is a lend of that parameter** (Agora #777). `^ ( id0 ( id0 p ) )`
  — and the same chain through a struct field, a generic lender, a lender
  defined further down, or three calls deep — was in no lend summary: the
  borrow checker tied the result to the argument, but the caller's code
  took the result for its own and released the argument under it (a
  use after free). Each link of the chain is now checked against its
  callee's lent parameters, and the parameter at the bottom is recorded as
  lent, as a single `^ ( id0 p )` already was.
