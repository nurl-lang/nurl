### Fixed

- **A parameter a returned literal copies is no longer counted as handed
  back** (Agora #288; probe
  parameter_copied_into_a_returned_join_literal_keeps_the_callers_temporary).
  `@ wrap H h → !H i { … ^ ?? r { T _ → @ !H i { T h } … } }` copies `h`
  into the literal, since `h` is not `sink` and the literal is an arm's.
  The §2.8 carrier rule still recorded `h` as returned. wrap's summary
  then said its result might be its argument, so a caller that passed a
  temporary (`( wrap ( mk ) )`) never dropped that temporary. That leaked
  one `H` per call, and in std/tls_server.nu a whole simulated network
  per accepted connection. A field the literal copies into a value that
  holds no views is now no carrier. A copy of a type that holds views
  still carries them.
