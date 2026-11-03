### Fixed

- **A closure clearing a local it read out of its capture through a join,
  a `??` payload or a generic identity ends the caller's borrows of the
  capture's elements** (Agora #449; probes closure_clears_a_*_capture,
  closure_clears_a_local_passed_through_a_generic_identity). #353 covered
  `: e ( vec_at vv 0 ) ( vec_clear e )`. The same element reached through
  `? c ( vec_at vv 0 ) ( vec_at vv 0 )`, `?? ( vec_get vv 0 ) { T e → … }`
  or `( idv ( vec_at vv 0 ) )` was not seen as the capture, and the caller
  read freed memory. These are refused now. A reader stays accepted. The
  enum-payload form is #460.
