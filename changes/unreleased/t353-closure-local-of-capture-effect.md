### Fixed

- **A closure that changes a local read out of its capture changes the
  capture** (Agora #353; probes closure_clears_a_local_read_out_*,
  closure_grows_a_local_read_out_*). `\ → v { : ( Vec String ) e (
  vec_at [( Vec String )] vv 0 ) ( vec_clear [String] e ) }`, run while
  the caller borrowed an element of `vv`'s element, freed it under the
  borrow: only the direct form `( vec_clear ( vec_at vv 0 ) )` counted as
  an effect of running the closure. A body local read out of a capture
  now reaches that capture, through copies too.
