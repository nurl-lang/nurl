### Fixed

- **A callee that leaves one argument viewing another's elements is
  summarised** (Agora #383; probes callee_holder_viewing_an_arena_element_*).
  `@ put ( Vec String ) arena ( Vec s ) idx String key → v { … : String e
  ( vec_at [String] arena n )  ( vec_push [s] idx ( string_data e ) ) }`
  gave its callers no tie, so clearing or truncating the arena afterwards
  left `idx` viewing freed bytes. The callee's answer now has an element
  pair (`h>^k`), and the caller's holder depends on the arena's elements:
  a push that only grows the arena leaves it valid; dropping the elements
  ends it.
