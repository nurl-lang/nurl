### Fixed

- **`( mem_dup @ S { … } )` no longer leaks the literal** (Agora #814). A
  literal written as mem_dup's operand is a fresh value that owns all it
  holds (as a call's argument it copies what it borrows), so it is the
  copy; copied again, the literal itself was released by no one. One copy
  fewer, too. A literal holding a view is copied as before.
