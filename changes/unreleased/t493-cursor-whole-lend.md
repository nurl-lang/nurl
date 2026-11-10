### Fixed

- **A `~` loop's container grown through a cursor a helper hands back is
  refused again** (Agora #493). `~ x t { ( grow ( pickv cur other ) ) }`,
  with `cur` a cursor of `t` and `pickv` handing its first argument back,
  moved `t`'s buffer under the loop. The rule that lets the loop go on
  after an *element's* buffer moved through `( vec_at cur 0 )` took any
  value a call lends out of the cursor for a part of it; a value handed
  back whole is the cursor itself. Never in a release.
