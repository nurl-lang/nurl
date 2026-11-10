### Fixed

- **A `??` arm no longer drops the second and later `% Drop` payloads of an
  enum that someone keeps** (Agora #641). `?? e { Three x s y → { … } }`
  over a variant `Bomb String Bomb` dropped `y` at the end of the arm and
  again when the enum was dropped: a heap-use-after-free with no panic
  involved, for a matched temporary and for a bound enum alike. The later
  payloads are lent to the arm now, as the first payload always was; the
  enum drops each payload once. Handing such a payload to a `sink`
  parameter from the arm, which had it dropped twice, is refused with the
  message a borrowed value that cannot be copied gets.
