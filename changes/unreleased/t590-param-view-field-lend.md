### Fixed

- **A function that returns a value lent out of a Slice field of its
  parameter lends that parameter** (Agora #590). With
  `@ firstq Q q → S { ^ ( slice_at [S] . q z 0 ) }`, the caller's
  `: S e ( firstq . h q )` was tied to nothing, so clearing the Vec that
  `. q z` views and then reading `e` read freed memory (heap use after
  free). `e` now depends on what the argument's field views.
