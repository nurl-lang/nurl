### Fixed

- **`: T s s` takes its value from the `s` it shadows** (Agora #792). The
  right-hand side was resolved after the new `s` was defined, so it named
  the new binding itself. A `: ~ String s s` or a copy of a parameter
  handed to a sink freed a value twice; they are refused now, as their
  renamed twins are. A plain handover, `? T { : String s s  ( eat s ) }
  {}`, was refused as a use of a moved value and is accepted now; so is
  `= s { : String s s  s }` in a loop (with #806), which freed the value
  twice.
