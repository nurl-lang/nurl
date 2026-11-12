### Fixed

- **A user enum field read out of a call's result and matched in place is
  dropped** (Agora #764). `?? . ( mkapp ) ev { Got p → … }` leaked the
  enum's payload box and the Vec under it on every match: 7 KB in a loop
  of 100. It is now dropped after the match where the call handed its
  result over, and left with its owner where the call lent it
  (`vec_at`, `arc_get`).
