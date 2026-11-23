### Performance

- **The borrow checker's statement rows are no longer interned for the whole compile** (Agora #974). Each function's captured row list, which the borrow walk splits into rows, was copied into the intern arena, and that arena is never freed. The list was interned again when a deferred function was parked, when it was walked, and when a closure literal saved its enclosing function's rows. Now:
  - the walk reads the list in place;
  - a parked function's rows sit in a buffer of their own, read in place by each of its walks and released after the last one;
  - a closure saves a copy of its own.
  
  No new unsafe code. Self-compile of `nurlc.nu`: heap at peak 230.8 → 225.1 MB (massif, −2.5 %), instructions −0.011 % (callgrind), peak RSS flat, byte-identical output.
