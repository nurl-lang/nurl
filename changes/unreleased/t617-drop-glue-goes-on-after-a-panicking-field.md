### Fixed

- **A struct's later fields and an enum's later payloads are no longer
  lost when an earlier one's destructor panics** (Agora #617). Under
  `recover`, the compiler-written drop glue released a value's parts in
  order with nothing standing for the parts still to go: `: Three { Bomb x
  Bomb y Bomb z }` with a panic in `y`'s destructor never ran `drop z`,
  and a plain `String` or `Vec` field after a panicking one leaked. The
  glue journals its own continuation now, as the release of a `Vec`'s
  elements does (#608): the fields or payloads after the one being dropped
  are dropped by the panic's drain, in order and once each, and the box a
  payload lives in is freed. Only a type one of whose parts may run code
  of the program's own when dropped gets the extra registration; every
  other type's drop is the straight-line function it was.
