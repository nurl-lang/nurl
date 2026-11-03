### Fixed

- **A closure cannot give its captures or its Vec parameter a view
  through a local, or a view of a capture** (Agora #332; probes
  closure_local_bound_from_*, closure_pushes_a_view_of_its_capture_*,
  closure_handed_to_a_function_pushes_its_captures_view). Inside a closure
  body, `: s t p` followed by `= w @ V { t }` stored a view of the
  closure's parameter into a capture, as `= w @ V { p }` would, but only
  the direct form was refused. And `\ ( Vec s ) out → v { ( vec_push [s]
  out ( string_data cap ) ) }` left the caller's Vec viewing a String the
  closure captured. Both read freed memory once the source ended. Both are
  refused now. A view of the closure's own other parameter stored into its
  Vec parameter is tied to that argument at the call (Agora #403).
