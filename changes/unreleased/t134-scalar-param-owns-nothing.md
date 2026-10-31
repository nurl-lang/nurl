### Fixed

- **The impls of a `dyn` method no longer "disagree" on a scalar
  argument** (Agora #134). An `i` parameter that one impl handed on to a
  callee storing it (`( pncounter_inc . h c k 1 )`, which pushes `k` into
  a `( Vec i )`) was summarised as *kept*, so `( bump d 1 )` through a
  `%Bump` object was refused: "disagree on argument 2 … the argument would
  leak". In safe code an integer, a float, a `b` or a SIMD vector cannot
  hold a pointer, and a scalar slot drops nothing, so a parameter of one of
  those types is no longer recorded as kept or stored there, whatever
  callee it reaches. That is the rule raw pointer parameters already
  followed, and the one a `sink` of a scalar already obeyed (it is a copy).
  Consumption is still followed: `unsafe` code that carries a pointer in an
  `i` and frees it consumes what it was handed. Parameters that own
  something (a String, a Vec, a handle, a closure, a struct with a drop)
  are compared as before.
