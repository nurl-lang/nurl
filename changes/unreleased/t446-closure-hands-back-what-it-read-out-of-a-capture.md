### Fixed

- **A closure cannot hand back a non-copyable value it read out of a
  capture or its parameter, by any route** (Agora #446; probes
  closure_hands_back_*). #372 refused a binding of an element of the
  closure's own Vec. The same element of a captured Vec, reached through
  a join, a rebind, a generic identity or a `??` payload, and a captured
  struct's field, a captured enum's payload or the capture itself bound
  first, were handed to the caller as its own and released twice. These
  are refused now, with a message that suggests taking the value out
  (`vec_pop`) or building a fresh one. Both of those stay accepted. The
  function forms are #462.
