### Fixed

- **An owner's old value is handed over or released by a key that tells
  values apart** (Agora #366). Two kinds of value had no usable key:
  - a record whose first owned field is an enum that can hold a unit
    variant;
  - an enum whose variant holds a number before its buffer (`A i String`).

  Given a new value beside a cursor, or a lend out of a container, such
  an owner kept its old value back for good. A unit variant was also
  built with an undef payload slot, so both the owner and its cursor were
  left owning nothing. A record is now keyed by its first field that
  keys, an enum by its variant's first owned buffer, and a unit variant's
  slot is zero.
