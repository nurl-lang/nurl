### Fixed

- **A value that would view its own field is refused where it is built** (Agora #294). `: S o @ S { sv b }`, with `sv` a slice of `b` (or of a String's bytes), made a value whose view pointed into its own field. Growing or replacing that field (`vec_reserve`, `string_push_str`, `= . o buf …`) left the view reading freed memory. The message says how to build it instead: take the view from the field once the value exists, or store a copy of the bytes. A value holding a view of another binding beside an owner of its own is unaffected.
