### Fixed

- **A value given a new one whose old value's destructor panics is
  dropped once, and the new value is kept** (Agora #621). Under
  `recover`, `= b ( new )` dropped `b`'s old value in place and stored the
  new one after; a panic in the old value's destructor had the unwind drop
  the old value a second time (a heap-use-after-free: its fields were the
  destructor's own by then) and lost the new one. The old value now leaves
  its slot before its destructor runs, as a value at the end of its scope
  does: the binding holds the new value from the store on, and the unwind
  drops that one, once. The same for a `Vec` or an option binding, an
  `inout` parameter (`= slot ( new )`), a binding owned outside the
  `recover` (usable afterwards, holding the new value), and a field
  (`= . h f ( new )`, a nested field, a `Vec`, option or closure field).
  A drop that runs no code of the program's own — a `String`, a `Vec` of
  numbers — goes where it always did.
