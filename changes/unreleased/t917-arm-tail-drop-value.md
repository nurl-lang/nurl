### Fixed

- **A `% Drop` value that a then-only `?` arm discards is released** (AGORA-917). In `? c { ( mk ) } {}` with `mk` handing back a value of a type with a `% Drop` (or a struct or enum holding one), the value was owned by nobody: it leaked, and its destructor never ran. It is now released where the arm ends, once, as the same value discarded by a statement already was.
