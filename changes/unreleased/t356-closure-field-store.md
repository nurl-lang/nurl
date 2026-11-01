### Fixed

- **A closure's store into a field of a captured struct reaches the
  struct** (Agora #356). The closure capture analysis counted a binding as
  assigned only when the `=` target was the name itself. A field-path
  target (`= . w f …`) was skipped, so a captured single-field `: ~` struct
  was captured by value. The store landed in the closure's own copy and was
  lost, and an owned value stored that way, such as a String or a Vec,
  leaked. The root of a field-path target now counts as assigned, so the
  struct is captured by pointer like any binding a closure assigns.
