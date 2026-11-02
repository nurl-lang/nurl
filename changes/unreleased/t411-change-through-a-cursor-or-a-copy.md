### Fixed

- **A change made in place through a match payload or a copy of an
  owner's handle ends the owner's views** (Agora #411, #293; probes
  option_payload_field_view_lent_by_a_callee_*,
  option_inner_payload_view_lent_by_a_callee_*,
  struct_field_view_kept_past_a_push_through_a_cursor_copy_of_its_owner,
  vec_slice_kept_past_*, vec_field_slice_kept_past_*). Each of these
  was a heap-use-after-free:
  - A view of an option's payload field handed back by a callee from its
    own `??` arm (`: s w ( name_of oh )`) was not seen to borrow from
    `oh`. Replacing `oh`, growing the field through a second `?? oh` (or a
    nested `?? . q inner`), or growing it in an `inout` callee's own `??`
    left `w` reading freed memory.
  - A view of a struct's field, or a slice of a Vec, survived a change
    made through a copy of the owner's handle. For example, `: ~ H q hs`
    then `( string_push_str . q name … )`; or `( id vs )`, a field viewer
    `. o buf`, or `: ~ ( Vec i ) w vs`, then `vec_reserve` or `vec_push`.

  All are refused now, naming the line and the route of the change. A
  view of another field stays valid, as does a slice of a Vec whose
  element was changed through a copy of that element.
