### Changed

- **A literal of `in` parameters bound only to be handed back lends them**
  (AGORA-1008, the last spelling of D4c, docs/MEMORY.md §7.6). In
  `@ wrap String p → K { : K k @ K { p }  ^ k }`, `k` used to be a copy
  of `p`; now `^ k` hands back the literal as written, exactly as
  `^ @ K { p }` does. No copy is made, and the caller's result borrows its
  argument. This applies when the literal's fields are `in` parameters
  named whole or numbers, every later use of `k` in the block is `^ k`,
  those parameters are not named again after the binding (not read, not
  rebound, not a match arm's payload), no closure follows in the block,
  and `K` has no `% Drop` of the program's own. Otherwise the binding
  copies as before.

  **Break:** a caller that reads such a result after giving its argument a
  new value, or after the argument is released, is now refused, as it is
  for the direct spelling. **Migration:** copy where it is meant
  (`( wrap ( string_clone a ) )`), or read the result first. No in-repo code
  needed it: `tools/tree_sweep.sh` finds no file whose verdict changed.
  A copy that had a `% Drop` of its own is no longer made, so on a path
  that hands back something else its destructor no longer runs for it.
  New tests `bound_literal_lends_in_param`,
  `diag_bound_literal_result_read_after_its_argument_changed`; hole probes
  `in_param_*_bound_literal_*`.
