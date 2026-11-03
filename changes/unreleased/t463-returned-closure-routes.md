### Fixed

- **A closure returned through a join or a match arm owns its captures**
  (Agora #463; probes closure_returned_through_a_join_owns_* and
  closure_returned_as_a_match_arm_value). `^ ? c \ → … x … \ → … y …`
  and `^ ?? k { T n → \ → … x … F → … }` left the captures to the
  function, which released them at its return; calling the closure read
  freed memory. A closure literal written as an arm value of the join a
  `^` hands back is now returned there, as `^ \ …` is. A join with an arm
  that is a closure bound first is checked by what that closure holds, and
  refused when it holds a copy of a local's handle.
- **A closure handed back through an identity function is checked**
  (Agora #463; probes closure_returned_through_a_sink_identity and
  closure_returned_through_a_generic_identity). A callee that hands a
  `sink` parameter back as it is (`@ idc [A] sink A f → A { ^ f }`) gives
  its caller the closure it was handed, with the copies of the handles it
  holds; `^ ( idc \ → … x … )` over a local `x` is refused, as `^ c` of a
  closure bound first is.
- **A returned literal that captures a String and stores it gives the closure a copy**
  (Agora #463; probe closure_in_a_returned_literal_that_also_stores_its_capture).
  `^ @ H { \ → i { … x … } x }` moved `x` into the closure and into the
  field, and both released it.
- **A returned closure that hands its capture to a `sink` hands a copy**
  (Agora #463; probes closure_returned_hands_*). `^ \ → i { ^ ( eat x ) }`
  released the closure's own `x`, and the next call and the closure's drop
  released it again. The callee is now handed a copy, as `^ x` in the body
  hands one back; a capture that cannot be copied is refused there. In a
  closure that stays in its function, a payload of a capture handed to a
  `sink` takes the capture over, as the capture itself does: a second call
  is refused.
- **A returned closure that cannot copy an option it captures is refused**
  (Agora #463; probes closure_returned_captures_an_option_of_*). An option
  of a `% Drop` struct with no Clone, or an option of an option, was left
  to the function and read after its release.
- **Two programs that failed to build now build** (Agora #463; probes
  closure_captures_a_vec_get_payload and rc_of_an_option_builds). A closure
  capturing a `vec_get` payload (`use of undefined value` in the closure
  body), and an `( Rc ?String )` (`drop__w__opt.String` undefined).
