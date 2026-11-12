### Fixed

- **A second reader of a field is refused once the first takes the field
  over** (Agora #271). `: R a . col res  : R b . col res  ( eat b )`, then a
  read of `. a v`, was accepted and read freed memory: consuming `b` takes
  the field over, and `a` kept a copy of its handle. Every borrow of that
  field, or of a field nested in it, now ends there.
- **A field reader bound again by name keeps its permissions** (Agora #271).
  `: R b a` over `: R a . col res` reads the same field, so `( eat b )` is
  accepted and takes the field over, as `( eat a )` does. It was refused
  with "'b' is a borrow…".
