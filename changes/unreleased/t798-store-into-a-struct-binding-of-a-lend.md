### Changed

- **A field store into a struct binding of a lend is warned as lost**
  (AGORA-798). `: App e ( vec_at [App] ps 0 )` binds a copy of the element
  the call lends; `= . e name …` or `= . e n 7` changed only that copy, and
  `ps` kept its old value without a word. The same holds for any call that
  lends a struct (`( vec_at [App] . w apps 0 )`, `( rc_get [App] r )`, an
  `inout` parameter's element). The warning names the fix: replace the value
  where it lives (`vec_put` / `vec_set`), or bind an owned copy with
  `( mem_dup … )`. A binding given a value of its own first (`mem_dup`, a
  fresh result, `=` of a new value) is not warned. Nothing leaked here: the
  binding owns what it is given by its run-time flag.
