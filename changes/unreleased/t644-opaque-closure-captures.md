### Fixed

- **A closure lent out of a captured Arc can be run more than once inside a
  closure body** (Agora #644). `: ( @ v i ) run ( arc_get … mine )` then
  `( run 1 ) ( run 1 )`, or a loop over it, was refused after the first
  call as "'mine' ended". An immutable Arc capture is left be: nothing run
  there can replace it, and its payload is frozen.
- **An unknown closure run inside a closure body ends what was read out of
  a `: ~` capture** (found fixing Agora #644). It may be one that gives the
  capture a new value: an element read out of a captured Vec, or a value
  read out of a captured Arc's payload, was used after the reassignment
  released it.
