### Security

- **A view of an element of a `Vec` whose elements hold views ends when
  that element grows** (AGORA-1041, docs/MEMORY.md §2.10). In
  `: ( Slice s ) e1 ( slice_from_vec [s] ( vec_at [( Vec s )] vv 0 ) )`,
  the element handed to `slice_from_vec` was read as `vv`'s own buffer
  whenever its elements hold views, not as element 0's. A push into that
  element (`( vec_push [s] ( vec_at [( Vec s )] vv 0 ) … )`) then left
  `e1` live, and reading it read freed memory. Now such an element is
  reached through `vv`'s element, as an element that holds no views always
  was, and what it holds stays a dependency of its own. The same program
  with pushes into `vv` itself, which move the elements' handles but not
  their buffers, compiles now; it was refused before, as it never was for a
  `( Vec ( Vec i ) )`. Hole probes `slice_of_an_element_of_a_vec_of_view_vecs_*`
  and `slice_of_an_element_holding_a_view_of_a_string_kept_past_its_growth`.
