### Fixed

- **A copy of a value that holds views holds them too** (Agora #362,
  #368, #377, #347; probes mem_dup_of_*, token_popped_*, clone_of_*,
  wrapper_around_vec_extend_* and others). A copy of a value holding views
  carried none of them, so it was kept, and read, after the String the
  views pointed into was freed. That covered `mem_dup` of a token or a
  struct of views; an element taken out with `vec_pop`, or matched out of
  `?? ( vec_pop … )`; `opt_unwrap_or`; a clone made by `vec_filter`,
  `vec_clone_with`, `vec_fold`, `Deque_clone` or `map_clone`, or by a clone
  of a clone; a function of your own that hands back `vec_clone` of its
  parameter, `slice_to_vec` of a Slice parameter, or a local it extended
  with one; and a wrapper of `vec_extend` (inout or not, generic,
  recursive, a `dyn` impl, given a temporary). A closure handing back
  `mem_dup` of its own parameter, which was refused as if it handed back a
  capture, is accepted.

### Changed

- `vec_map` with a closure that hands back fresh values is refused where
  its result outlives the views of the Vec it maps: a closure parameter's
  result is taken to hold what its argument holds (MEMORY.md §7.5).
  Copy the strings (`( Vec String )`) to keep a result past them.
