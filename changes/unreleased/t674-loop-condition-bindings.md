### Fixed

- **What a loop's condition binds is released every round** (Agora #674,
  #628, `compiler/nurlc.nu`). A value block in a loop's condition —
  `~ < { : String s ( mk k ) ( string_len s ) } n { … }` — binds in the
  scope around it, which for a loop's condition is the function's: its
  String, Vec, struct with a destructor or closure environment was
  released once, at the function's exit, and every round's value but the
  last was never released (a destructor ran once instead of once per
  evaluation). They are released now where the round's condition has its
  value, before the branch on it. A condition that binds no owner compiles
  to the IR it did before.
