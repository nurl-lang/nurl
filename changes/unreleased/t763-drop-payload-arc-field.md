### Fixed

- **A `??` payload of a `% Drop` element read out of an Arc's payload is
  a view of that payload** (Agora #763).
  `?? ( vec_get [R] . ( arc_get [App] mine ) rs 0 ) { T e → { ( rg e k ) } F → {} }`,
  with `R` a struct with its own `% Drop` and `rg` growing a Vec field of
  it, passed the frozen-Arc rule, so eight threads doing it grew one Vec
  at once. The payload was lent from the bindings the scrutinee reads,
  and a field of a call's result is none of them. It now borrows what the
  call lends from, and the change is refused, in place or in a closure, as
  it already was without the `% Drop`.
