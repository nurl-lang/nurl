### Fixed

- **A callee that leaves one argument viewing another's elements ties the
  caller's holder to those elements** (Agora #383). `put arena idx key`
  pushing `key` into `arena`, binding `: String e ( vec_at arena n )` and
  pushing `string_data e` into `idx` left the caller's `idx` tied to
  nothing: `vec_clear`, `vec_pop`, `vec_truncate` or `vec_put` on
  `arena`, or the viewed element growing, left `idx` reading freed
  memory. The callee's answer now has an element pair, `h>^k`: the
  holder depends on argument k's elements, as a local view of an element
  does. Pushing more into the arena, which moves only its own buffer,
  stays accepted.
