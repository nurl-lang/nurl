### Fixed

- **A `^` or a `\` above a loop body's `;` runs the defer an earlier
  round armed** (Agora #670, `compiler/nurlc.nu`). A defer runs once, at
  the function's exit, if its `;` was reached in any round. A way out
  written above the `;` in the loop body entered the defer chain as it
  was when that exit was compiled, below this defer, so the defer did not
  run: `~ < k 3 { ? == k n { ^ + 100 k } {}  ; { … } … }` printed no
  defer line for `n` = 1. Every way out of a defer loop now enters the
  chain through one label at the loop's end, which branches to the
  chain's top as it is there; the armed flags decide at run time what
  runs.

  So such a defer runs at that way out with what the earlier round left,
  and the borrow checker reads it so: the bindings a defer of the loop
  keeps cross the back-edge and the loop's exit with what they borrow
  (before, every binding of the body was dropped there, and the defer's
  replay read names it no longer tracked), and a defer further down a
  loop around a way out is replayed there. Newly refused, each with a
  diagnostic that names the defer, the way out and the line whose
  earlier round's value the defer reads:
  - a view (or an element) the body binds below the way out, of a
    binding made before the loop that the round gives a new value or
    clears above it — `= x ( new )  ? d { ^ 1 } {}  : s v ( string_data
    x )  ; { … v … }` read the old `x` (heap-use-after-free once the
    defer runs there);
  - a defer that frees what a `^` above it hands back;
  - a change after the loop to what the last round's view, read by the
    defer at the function's exit, borrows from (heap-use-after-free
    before this change too).

  Newly accepted: a `^` that hands back an arm's own binding while a
  defer frees an outer binding of the same name (`? d { : String g …  ^
  g } {}`): the return's owner was looked up by its bare name, the outer
  one. A function with no `;` inside a loop compiles to the IR it did
  before.
