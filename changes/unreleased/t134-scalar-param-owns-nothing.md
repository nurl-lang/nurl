### Fixed

- **The impls of a `dyn` method no longer "disagree" on a scalar
  argument** (Agora #134). An `i` parameter that one impl handed on to a
  callee storing it (`( pncounter_inc . h c k 1 )`, which pushes `k` into
  a `( Vec i )`) was summarised as *kept*, so `( bump d 1 )` through a
  `%Bump` object was refused: "disagree on argument 2 … the argument would
  leak". An integer, a float, a `b` or a SIMD vector owns nothing, so a
  parameter of one of those types is now never kept, stored, consumed or
  traced as an escape, whichever callee it reaches. That is the rule raw
  pointer parameters already followed, and the one a `sink` of a scalar
  already obeyed (it is a copy). Parameters that own something (a String,
  a Vec, a handle, a closure, a struct with a drop) are compared as
  before.
