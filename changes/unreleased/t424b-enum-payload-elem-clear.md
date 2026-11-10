### Fixed

- **A call that clears a program enum's payload in place ends the borrows
  of the payload's elements** (Agora #424, #569). `?? o { Fullbag inner →
  { : String s0 ( vec_at [String] inner 0 ) ( clr o ) … s0 } }`, where
  `clr` vec_clears the payload, read the dropped element: a
  heap-use-after-free. #565 keeps an arm's in-place payload across a call
  that empties it rather than replacing it, and rightly so. The borrows
  taken from that payload now end there, with their own message. The
  payload itself stays usable.
