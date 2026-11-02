### Fixed

- **A view of a match payload's field ends with its arm again** (Agora
  #409, claude-formal's review of #336; probes
  cursor_field_view_kept_past_*, cursor_element_view_kept_past_*). 0.85.0
  let such a view outlive its arm while the option still owned the
  payload, but nothing then ended it when the payload was changed in place
  through a second match (`?? oh { T q → ( string_push_str . q name … ) }`,
  `vec_clear`, an `inout` callee): heap-use-after-free. The transfer is
  withdrawn, so the 0.84.0 refusal of a cursor payload's field view kept
  past its arm is back. It comes back accepted once a change through a
  second match ends it (#411).
