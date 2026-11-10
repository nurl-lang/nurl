### Fixed

- **A lent value handed back through a binding stays a lend** (Agora
  #462). `: Conn c ( vec_at [Conn] cs 0 ) ^ c`, with `Conn` a `% Drop` type
  (a value that cannot be copied), its rebinding `: Conn d c ^ d`, and an
  enum parameter's payload `?? e { Has c → { ^ c } … }` handed the
  caller's own element over as the function's: both the caller's binding
  and the container dropped it (heap-use-after-free). `^ ( vec_at … )`
  itself ran clean. The binding's drop flag was already the answer, but
  the function answered "owned" statically. It now answers per call, as
  `^ ( g x )` does. A rebinding carries the lend, and a `??` payload of a
  parameter the function does not take is lent back as part of it. The
  caller then holds such a result as a lend of its argument.
