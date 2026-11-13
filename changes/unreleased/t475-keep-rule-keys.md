### Fixed

- **`= o ( f o k )` for a `!i String` or a `? ?String`** (Agora #475).
  When `f` may hand back its argument, the assignment asks whether the
  new value is the old one by its key. A result whose error owns a String
  beside a number, and an option of an option, had no key. On the run that
  handed back o's own value, o's value was released and then read. They
  are now keyed by their active side, by nesting. A function returning an
  option of an option now answers per call whether it hands over its own
  value.
