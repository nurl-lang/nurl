### Fixed

- **A closure picked by a join, or a closure literal's own closure
  parameter, is called as the closures it may be** (Agora #420; probes
  closure_picked_by_a_join_of_*, closure_join_handed_to_a_function_*,
  closure_given_a_join_by_assignment_*,
  closure_literals_closure_parameter_*). `: f ? c clr nop` followed by
  `( f inner )`, with `clr` clearing its parameter, kept a borrow of
  `inner`'s element alive past the clear. So did a closure literal that
  calls its closure parameter (`\ y g → v { ( g y ) }`) given a clearing
  closure. Both were read as an unknown closure. Both are refused now, as
  binding `clr` by name was. A join of readers stays accepted.
