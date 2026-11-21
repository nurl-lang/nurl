### Changed

- **The formal proof builds with no warnings** (was 225, all from Lean's linters). It drops 183 `simp` lemmas a call did not use, renames 26 uses of core lemmas Lean has renamed (`if_pos`/`if_neg`/`if_true` → `ite_eq_left`/`ite_eq_right`/`ite_true`), and marks 16 unused hypothesis names `_`. No definition, rule or theorem statement changes, and no proof is weakened. A new warning in `formal/check.sh`'s output is now visible at once. Compiler, runtime and NURL source are unchanged.
