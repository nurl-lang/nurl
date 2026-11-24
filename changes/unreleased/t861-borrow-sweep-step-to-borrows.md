### Changed

- **The borrow checker's sweep of a row is linear in the bindings.** For each
  row, the sweep for bindings a call consumed visited every binding of the
  function's state, and measured the state up to each one: quadratic in the
  bindings. It now steps from one borrowed binding to the next
  (`bck_st_next_borrow`). Hoisted-body emission copies a marker's span
  without measuring the whole function each time. A self-compile runs 2.2 %
  fewer instructions (25.93G to 25.35G), with byte-identical output.
- `__vis_check_template` (Agora #861) is an ordinary function, not
  `unsafe`. Three helpers that only set a scalar global (`__rpg_tmp_next`,
  `amv_close`, `__rp_rhs_set`) are no longer `unsafe` either, so nurlc has two
  fewer `unsafe` functions than before #861.
