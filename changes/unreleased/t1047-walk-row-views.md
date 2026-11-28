### Performance

- **The borrow walk reads its rows in place** (AGORA-1047). Every visit
  to a row of a function's walk, every round, copied the row
  (`bck_rec`, a `strdup` and a `free`). The row table is written once and
  released whole at the end of the function's analysis, so the walk now
  takes a view of the row (`bck_row`). Output is byte-identical. Compiling
  the compiler takes 0.24 % fewer instructions, `packages/nwasm/src/rjit.nu`
  0.21 % and `stdlib/std/tls.nu` 0.19 %. An AddressSanitizer build of the
  compiler self-compiles clean.
