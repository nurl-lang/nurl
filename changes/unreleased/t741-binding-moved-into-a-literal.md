### Fixed

- **Under `recover`, a binding moved into a struct literal is dropped when
  a later field's expression panics** (Agora #741). The binding gave its
  value up at its field, before the literal was complete, so the panic
  left the value to nobody: `: Bomb b … @ Two { b ( made ) ( panics ) }`
  never ran `b`'s destructor. The binding now hands its value over at the
  literal's `}`. This holds for a nested literal, a literal handed to a
  reader, and an option's payload.
