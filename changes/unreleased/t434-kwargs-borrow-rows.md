### Fixed

- **A keyword call is borrow-checked like a positional one** (Agora #434).
  `( clr v: v )`, a clearer called with its argument by name, ended no
  borrow of `v`'s elements, because the keyword path assembled the call
  without any of the positional path's borrow rows. A call that sets its
  arguments in declared order now takes the positional path, so every
  rule applies. That covers labels from the first argument on, a
  positional prefix followed by labels, a defaulted parameter a label
  skips over (its default is spliced in) and omitted trailing defaults.
  A call that really reorders its arguments still takes the keyword
  path. An argument there that holds heap storage (a binding, or a field
  path of such a type) is refused, with the advice to name the arguments
  in declared order or pass them positionally. Literals and scalars are
  passed as before.
- **A parameter given twice is refused** (Agora #434). `( add 1 2 x: 3 )`,
  or `x:` written twice, kept the later value without a word. It now
  names the argument.
