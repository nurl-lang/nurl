### Fixed

- **A `??` arm that gives its own enum binding a new value can no longer
  read the old payload** (Agora #364). In `?? o { MSome s → { = o … (
  read s ) } }` over a program enum (not an option), `= o` releases the
  old value and the payload `s` with it, and the read after was of freed
  memory. That read is refused now, with the line where `o` was given its
  new value. An option keeps its old value back for the payload and stays
  accepted, as does an arm that reads the payload before the assignment,
  or one whose payload is a scalar copy.
