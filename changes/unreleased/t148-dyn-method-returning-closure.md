### Fixed

- **A `dyn` method that returns a closure can be called** (Agora #148).
  `( make d t )` through a trait object was refused as "passes 1
  argument(s) but the declared closure/function type takes 0". The
  vtable slot's function type starts with the returned closure's `{`
  (`{ void (i8*)*, i8* } (i8*, %String*)*`), and the arity check read the
  parameter list from inside the return type. The parameter list is now
  the last paren at the type's outer level: top level for a function
  pointer, inside the braces for a closure. The call type-checks, and the
  closure it hands back is a view of what it captured, as for a direct
  call: releasing `t` before the closure runs is refused.
