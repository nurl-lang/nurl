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
  recursive, a `dyn` impl, given a temporary, or one of your own marked
  `unsafe`). The same held for an `inout` parameter given a new value in a
  loop that may not run: after the loop it still holds what its argument
  held. A closure handing back `mem_dup` of its own parameter, which was
  refused as if it handed back a capture, is accepted.
- **A copy of a part of a value outlives that value** (probes
  vec_clone_of_an_element_*, mem_dup_of_an_element_*,
  slice_to_vec_of_a_slice_*, *_payload_*_runs_clean,
  callee_handing_back_a_dup_*, dup_helper_given_a_lent_element_*). A copy
  of a part was refused once the value it was part of ended, though the
  strings its views point into lived on. That covered:
  - `( vec_clone [s] ( vec_at [( Vec s )] vv 0 ) )`, `mem_dup` of it or a
    binding of it, refused once `vv` ended;
  - a payload matched out of `( vec_at … )` or `( map_get … )`;
  - `( slice_to_vec [s] ( slice_from_vec [s] t ) )`, refused once `t`
    ended;
  - `mem_dup` of a token a function of your own reads out of its
    `( Vec Tok )` or is handed as `( vec_at … )`.

  It holds what the part holds.
- **A generic instance's type read as an owner holding no views** when it
  was asked again after its layout became known (a `( Slice s )` handed
  back by `slice_from_vec`, among others): the type memos' "ask again"
  (`-1`) read as an answer, 0, since #1545.

### Changed

- `vec_map` with a closure that hands back fresh values is refused where
  its result outlives the views of the Vec it maps: a closure parameter's
  result is taken to hold what its argument holds (MEMORY.md §7.5).
  Copy the strings (`( Vec String )`) to keep a result past them.
