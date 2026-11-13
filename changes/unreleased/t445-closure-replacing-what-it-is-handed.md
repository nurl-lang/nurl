### Fixed

- **A closure is never handed what it replaces, by any route** (Agora
  #445). `( c o )` with `c` giving its capture `o` a new value was refused
  (#339). These compiled, and the closure read freed memory:
  - `c` and `o` handed to a function that calls one with the other;
  - the closure written inline as an argument beside `o`;
  - the assignment made by a nested closure `c` runs;
  - the argument an element (`( vec_at vs 0 )`), a view (`( string_data o )`)
    or a `??` payload of the binding.

  Each is refused now, naming the binding and the route. A closure that
  only reads what it is handed still compiles by every route.
