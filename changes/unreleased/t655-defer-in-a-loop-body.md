### Fixed

- **A `;` defer inside a loop body finds what it reads, and every round's
  value is released** (Agora #655, `compiler/nurlc.nu`). A defer runs
  once, at the function's exit, if its `;` was reached in any round of
  the loop, and a binding it reads lives until it runs. The compiler is
  one pass, so what stood above the `;` in the loop body was compiled
  before the defer was known, though from the second round on it runs
  with the defer armed:
  - a `break`, a `^` or a `\` above the `;` released the round's
    bindings itself, and the defer then read one of them
    (heap-use-after-free; with a `^`, the cleanup freed it again);
  - a round's end left a kept binding in its slot for the defer and the
    next round's `:` wrote over it: every round's String, Vec, struct or
    closure environment but the last was never released.

  A loop whose body holds a `;` is now looked at before its body is
  compiled. Inside the outermost such loop, the owners in sight at its
  head are kept from there on, and a `:` binding with a `;` further down
  its own block is kept from its binding on. Before a round stores its
  value, the value the slot holds from an earlier round is parked on a
  list that the function's cleanup releases after the defer chain,
  newest first. It is not released where it is replaced: a view of it
  that a defer still reads (a closure over it, a `string_data`, a
  payload) stays good. A closure returned on one path and kept by a
  defer on another is released on the other (it was kept back on every
  path). A function with no `;` inside a loop compiles to the IR it did
  before; nothing is scanned in a function whose body holds no `;` byte.

### Known issues

- A `^` or a `\` above a loop body's `;` still does not run the defer an
  earlier round armed (Agora #670). A loop whose defer keeps a value per
  round holds every round's value until the function returns: register
  the defer outside the loop where the loop is long.
