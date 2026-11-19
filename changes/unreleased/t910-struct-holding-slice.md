### Fixed

- **A change made through a slice that a struct literal holds now counts as a change of the parameter it views** (AGORA-910). Take `: SH h @ SH { ( slice_from_vec [String] v ) }`, then growing an element through `( slice_at [String] . h s 0 )`. That was in no summary, so a caller's view into `v`'s element dangled after the call. It is refused now, and reading through the held slice is still accepted.
