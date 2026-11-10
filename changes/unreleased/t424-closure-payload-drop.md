### Fixed

- **A closure that clears a payload of its own parameter ends the borrows
  of it** (Agora #424). `: … clr \ ?( Vec String ) b → v { ?? b { T xs → {
  ( vec_clear [String] xs ) } F → {} } }`, called as `( clr o )` while a
  `vec_at` borrow of the matched payload lived, cleared the Vec under the
  borrow: a heap-use-after-free. The named-function form was refused. A
  closure's drop summary did not follow a payload matched out of its own
  parameter: __drop_note_via returned early in a closure body of a function
  with no parameters of its own, and its derivation search stopped only at
  the function's parameters. Both now count the closure literal's own.
