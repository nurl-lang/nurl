### Fixed

- **A view through one share of a program's Rc handle ends at a change
  through another share** (Agora #345). With `X { ( Rc Impl ) ctl }` and
  an `X_share` hook that `rc_clone`s it, a view of the state taken through
  one X outlived an `rc_set` made through another X, and the read after it
  was a heap use after free. Such a handle now counts as its Rc for the
  rule that already covered two bindings of one `( Rc T )` type.
