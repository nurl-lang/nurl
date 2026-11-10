### Fixed

- **A bare `s` view handed back through a join, or from a `??` payload
  inside an `if`, lends what it views** (Agora #487).
  `^ ? c ( string_data ( vec_at [String] p 0 ) ) ``` was lent by no
  parameter, so a caller that cleared `p` while holding the result read
  freed memory. The join's arms read `p` on its edge rows, and the return
  was read through nothing. A value join now hands its arms' reads to the
  return's raw provenance, as `^ ( string_data … )` hands its own.
  `?? ( vec_get [String] p 0 ) { T e → { ^ ( string_data e ) } … }`
  inside an `if` or a loop lends what the payload's match lends of `p`, as
  it did when the `??` directly preceded the last `^`. A `??` value join's
  payload view is still open (tools/fuzz/holes/open/t487.md). The answer
  is per parameter, as the direct form's is: a join's view of
  `. r items` is now ended by clearing `. r name` too (refused, safe;
  path-precise answers are Agora #572).
