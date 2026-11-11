### Fixed

- **A `;` defer inside a loop body is run, and finds what it reads, on
  every way out of the function** (Agora #655, `compiler/nurlc.nu`). A
  defer runs once, at the function's exit, if its `;` was reached in any
  round of the loop. The compiler is one pass, so what stood above the
  `;` in the loop body was compiled before the defer was known, though
  from the second round on it runs with the defer armed:
  - a `^` or a `\` try above the `;` entered the defer chain below this
    defer, which did not run (`~ < k 3 { ? == k n { ^ + 100 k } {}
    ; { … } … }` printed no defer line for `n` = 1);
  - a `break`, a `^` or a `\` above the `;` released the round's
    bindings itself, and the defer then read one of them
    (heap-use-after-free; with a `^`, the cleanup freed it again); a
    binding made before the loop went the same way;
  - a round's end left a kept binding in its slot for the defer and the
    next round's `:` wrote over it: every round's String, Vec, struct or
    closure environment but the last leaked.

  A loop whose body holds a `;` is now looked at before its body is
  compiled. Inside the outermost such loop, the owners in sight at its
  head are kept from there on; a `:` binding with a `;` further down its
  own block is kept from its binding on, and first releases what its
  slot holds from an earlier round (the slot holds the last value
  bound); and a way out of the function enters the chain at its top as
  it is when the loop closes. The borrow checker reads a defer further
  down a loop body at a `^` above it as it reads one above the `^`: a
  defer that releases what that `^` hands back is refused (it ran clean
  before only because the defer was skipped). A function with no `;`
  inside a loop compiles to the IR it did before; nothing is scanned in
  a function whose body holds no `;` byte.
