### Fixed

- **A borrow that views a Vec's own buffer on one path is not taken for
  an element view past the join** (Agora #399; probes
  slice_of_a_vec_*). `: ~ W a @ W { … ( string_data e ) }` (e an element
  of `vv`), then `? c { = a @ W { ( slice_from_vec [String] vv ) … } }
  {}`: past the join `a` counted as viewing only `vv`'s element, so a
  push that moved `vv`'s buffer left its slice dangling. The same held
  when a loop that ran zero times re-gave it the element view. A source
  borrowed directly on either path is now borrowed directly past the
  join; one borrowed only through an element on every path stays so.
