### Fixed

- **A payload of an enum with a `% Drop` of its own is copied out
  whichever way it is handed back** (Agora #641). `^ s` by name and a
  join's value were copied out of an enum the function drops; a `:`
  binding of the payload (`: String t s  ^ t`), a literal or an option
  holding it (`^ @ W { s 3 }`, `^ @ ?String { T s }`), a value block
  (`^ { s }`) and a call that lends its argument back (`^ ( id s )`)
  handed the caller the very `String` the enum's drop glue then freed: a
  heap-use-after-free in safe code. Each is a copy now where the function
  drops the enum (a local, a matched temporary, a `sink` parameter), a
  lend where the enum is a parameter the caller keeps, and refused where
  the payload cannot be copied.

### Changed

- **A `??` arm's payload ends when its enum is handed over whole** (Agora
  #641). `?? e { Three x s y → { ( eat e ) ( use s ) } }`, `eat` taking
  its argument (`sink`, or by what it does with it, whichever is compiled
  first), read `s` out of an enum `eat` had dropped: a heap-use-after-free
  for every enum that owns its payloads. The read after the call is
  refused now, as it already was after `= e …` and for an option's
  payload; a payload read before the call, and an integer payload, are
  untouched.
- **A function that lends a payload of an enum parameter with a `% Drop`
  of its own and also takes that parameter over is refused** (Agora #641).
  `@ g E e → String { ?? e { A s → { ^ s } B → { ( eat e ) … } } }` lends
  `s` to its caller on one path and hands `e` to a `sink` on another, so
  it drops `e` on every way out, the lent payload with it (a
  heap-use-after-free in the caller). Declare the parameter `sink`: a
  payload handed back is then copied.
