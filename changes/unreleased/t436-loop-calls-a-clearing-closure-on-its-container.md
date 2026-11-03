### Fixed

- **A `~` loop calling a closure that clears the loop's container is
  refused** (Agora #436; probes loop_calls_a_*). `~ x xs { ( f xs ) … x … }`
  with `f` a closure binding, or a function's closure parameter, that
  clears its Vec compiled, and read freed memory. The check asked the
  closure's summary before it was final. It is now decided at module end,
  as for a function compiled later. A loop calling a reader stays accepted.
