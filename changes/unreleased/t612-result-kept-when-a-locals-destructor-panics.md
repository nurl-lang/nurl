### Fixed

- **A function's result is no longer lost when one of its locals'
  destructors panics at its exit** (Agora #612). Under `recover`, `@ mk →
  Bomb { : Bomb loc … ^ @ Bomb { … } }` evaluated its result, then dropped
  `loc`; a panic in `loc`'s destructor unwound past the result, which was
  in no journal entry: its destructor never ran and what it owned leaked.
  The same held for a call's value, a `?` join, the body's last
  expression, a `String`, a `Vec`, an option, a result, an enum or a
  struct handed back, and for a binding handed back (`^ res`) that was
  declared after the local whose destructor panics. The result is the
  function's own until the `ret` now: for that window it is in the panic
  journal, with the ownership that return answers, so a panic in a local's
  destructor runs the result's destructor, once, and frees it. Nothing is
  registered in a function none of whose locals runs code of the program's
  own when it is dropped, so every other function's code is unchanged.
