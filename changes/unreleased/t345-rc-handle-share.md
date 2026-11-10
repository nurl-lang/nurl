### Fixed

- **A program's own handle over an Rc is shared by type** (Agora #345).
  With `: X { ( Rc Impl ) ctl }` and `X_share` cloning the Rc, a view of
  the state taken through one share (`x_view y`, an accessor's `rc_get`)
  outlived `x_reset a` (an accessor's `rc_set`) through another share and
  read freed memory. The same-Rc rule (two values of one `( Rc T )` type
  may be the same Rc value) now also covers a struct type that holds an
  `( Rc T )` field. A call that may drop or move what such a value holds
  ends the views taken through any other value of that type. Coarse by
  type, as for the Rc itself: shares are not tracked one by one.
