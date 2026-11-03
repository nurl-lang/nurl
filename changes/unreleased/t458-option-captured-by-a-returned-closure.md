### Fixed

- **A returned closure owns a copy of the options and results it captures**
  (Agora #458; probes option_local_captured_by_a_returned_closure and its
  variants). `: ?String x ( mk … )  ^ \ → i { ?? x { … } }` left `x` to
  the function, which released it at its return; calling the closure
  then read freed memory. A captured String already moved into the
  closure. An option or result that owns a String, a Vec or another
  handle is now copied in, whether the closure is returned as it is or
  inside a struct literal or another closure; the closure releases its
  copy, and copying the closure copies it.
