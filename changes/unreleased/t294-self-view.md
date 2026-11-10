### Fixed

- **A value that would view its own field is refused** (Agora #294).
  `: S o @ S { sv b }`, with sv a slice of b, made `o.v` view `o.buf`'s
  bytes. Growing or replacing that field (`vec_reserve`, a push, a new
  value) left the view dangling (heap use after free). The error names
  the field and suggests keeping the view and its owner in different
  values. A view of another binding's buffer next to an owner of its own
  still compiles.
