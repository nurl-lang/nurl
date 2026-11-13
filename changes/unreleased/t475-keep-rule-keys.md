### Fixed

- **`= o ( f o k )` for a `!i String` or a `? ?String`** (Agora #475).
  When `f` may hand back its argument, the assignment asks whether the
  new value is the old one by its key. A result whose error owns a String
  beside a number, and an option of an option, had no key. On the run that
  handed back o's own value, o's value was released and then read. They
  are now keyed by their active side, by nesting. A function returning an
  option of an option now answers per call whether it hands over its own
  value.
- **`= o ( f o k )` for a result of an Rc share** (Agora #475). An
  `rc_clone` share has the old share's key and was kept as if it were the
  old value, so one count leaked. The old value is now kept only on runs
  where the call lent its result.
