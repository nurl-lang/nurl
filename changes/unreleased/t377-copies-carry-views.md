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
- **A copy of a part of a value that views its own storage** (probes
  *_viewing_its_sibling_*). A token Vec whose second token views the first
  token's String, a struct element viewing a sibling's field, or a struct
  whose field views another field, moved into a Vec: a copy of a part of
  it (`mem_dup`, a foreach element, a match payload, a helper's copy) was
  kept past the value and read the freed String. It is refused now.
- **A copy of a parameter's views given to a global or another thread**
  (probes global_given_a_*_copy_of_*, thread_given_a_view_popped_off_*).
  A string global given the word of `mem_dup` of a token parameter kept a
  view into the caller's string past its release. That shape, and a view
  popped off a copy of a `( Vec s )` parameter stored in a global or
  captured by a thread, are refused in the function, as a view parameter
  itself is.
- **A copier given a literal** (probes token_copier_given_a_literal_*,
  copy_function_given_a_token_literal_*). A callee pushing `mem_dup` of its
  token into an `inout` Vec, given a token literal viewing a local line,
  left the Vec viewing the line after it was freed.
- **A function handing back a view popped off a copy of its parameter**
  (probe bare_view_popped_off_a_copy_of_a_param_runs_clean) was refused as
  if the view pointed into the copy. It points into what the caller passed;
  the caller now checks what it keeps.
- **A generic instance's type read as an owner holding no views** when it
  was asked again after its layout became known (a `( Slice s )` handed
  back by `slice_from_vec`, among others): the type memos' "ask again"
  (`-1`) read as an answer, 0, since #1545.

### Changed

- `vec_map` with a closure that hands back fresh values is refused where
  its result outlives the views of the Vec it maps: a closure parameter's
  result is taken to hold what its argument holds (MEMORY.md §7.5).
  Copy the strings (`( Vec String )`) to keep a result past them.
- The element `vec_replace` hands back is taken to hold what every
  argument holds, the replacing value's views too (A2's `heldOfArgs`):
  kept past the string the new value views, it is refused. Keep that
  string alive as long as the old element, or copy the strings.
