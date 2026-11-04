### Fixed

- **A closure returned as a join's arm owns its captures** (Agora #463;
  probe closure_returned_from_an_arm_over_a_payload). A closure literal
  written as an arm value of the `?` or `??` a `^` hands back now owns its
  captures as `^ \ …` does, where they were left to the function and read
  after its return. What the borrow checker accepts is unchanged: a join
  it refuses (h310) is still refused.
- **A closure handed back through an identity function is checked**
  (Agora #463; probes closure_returned_through_a_sink_identity and
  closure_returned_through_a_generic_identity). A callee that hands a
  `sink` parameter back as it is (`@ idc [A] sink A f → A { ^ f }`) gives
  its caller the closure it was handed, with the copies of the handles it
  holds; `^ ( idc \ → … x … )` over a local `x` is refused, as `^ c` of a
  closure bound first is.
- **A returned literal that captures a String and stores it gives the closure a copy**
  (Agora #463; probes closure_in_a_returned_literal_that_also_stores_its_capture
  and closure_literal_with_two_closures_and_a_stored_capture).
  `^ @ H { \ → i { … x … } x }` moved `x` into the closure and into the
  field, and both released it.
- **A returned closure that hands its capture to a `sink` hands a copy**
  (Agora #463; probes closure_returned_hands_*). `^ \ → i { ^ ( eat x ) }`
  released the closure's own `x`, and the next call and the closure's drop
  released it again. The callee is now handed a copy, as `^ x` in the body
  hands one back; a capture that cannot be copied is refused there.
- **A closure that hands a captured option's payload to a `sink` owns the
  option** (Agora #463; probes closure_local_hands_* and
  closure_local_releases_*_never_run). `: c \ → i { ?? x { T s → ( eat s
  ) } }` left `x` to the function, which released it again; the closure
  now takes it over and marks it taken when it hands it on: a copy of the
  closure made after it ran no longer copies what was given away, a later
  run that uses the capture again stops with a clean panic where it uses
  it, and a closure that never runs releases what it took over (a
  String's leaked too).
- **A returned closure that cannot copy an option it captures is refused**
  (Agora #463; probes closure_returned_captures_an_option_of_*). An option
  of a `% Drop` struct with no Clone, or an option of an option, was left
  to the function and read after its release.
- **A borrow handed to a `sink` in a return is refused**
  (Agora #463; probes rc_get_payload_handed_to_a_sink_in_*).
  `?? ( rc_get r ) { T s → { ^ ( eat s ) } }` released what the Rc still
  held; the same hand-over in a statement was already refused.
- **Two programs that failed to build now build** (Agora #463; probes
  closure_captures_a_vec_get_payload and rc_of_an_option_builds). A closure
  capturing a `vec_get` payload (`use of undefined value` in the closure
  body), and an `( Rc ?String )` (`drop__w__opt.String` undefined).
