### Fixed

- **A clearing callee handed an element a call lends ends the borrows of
  that element's contents** (Agora #421, #443; probes
  closure_called_with_an_element_*, function_hands_its_parameters_element_*).
  `( f ( vec_at outer 0 ) )`, with `f` a closure that clears its
  parameter, kept a borrow of the element's element alive past the clear:
  a named callee there was refused. A function handing `( vec_at vv 0 )`
  of its parameter to a clearing callee, or to its closure parameter,
  had no drop in its own summary, so its caller's borrows survived too.
  Both are refused now. A reader stays accepted.
