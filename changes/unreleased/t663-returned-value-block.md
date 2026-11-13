### Fixed

- **A value block handed back by `^` is checked as its tail binding is**
  (Agora #663). `^ { : String t ( … )  : s d ( string_data t )  d }`, a
  struct or Vec of views, a closure over a block local, and a view of a
  parameter the caller then changes, were accepted where the unblocked
  `^ d` is refused, and read freed memory. They are refused now with
  `^ d`'s message. `^ { { p } }`, a block whose tail is itself a block,
  hands its value back by the same rules (a parameter or a lend is
  copied) instead of releasing it twice.
