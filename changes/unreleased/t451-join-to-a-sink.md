### Fixed

- **A join of two owners handed to a consuming parameter is copied**
  (Agora #451; probes join_of_two_owners_handed_to_*,
  match_of_two_owners_handed_to_a_sink). `( eat ? c u t )`, with `u` and
  `t` owned Strings and `eat` taking a `sink String`, gave `eat` the buffer
  of whichever owner the join picked, and that owner released it again at
  the end of its block (heap-use-after-free). The same happened with a
  `??` and with a callee that keeps its parameter without declaring
  `sink`. Such a join lends on every path, so it is now copied for the
  callee, as a join that lends on some paths already was.
