### Fixed

- **A `% NotSync` part of a type marked `% Sync` is heard** (Agora #719).
  `unsafe % Sync App {}` over a `( W i )` field with `% NotSync ( W i ) {}`
  let a closure kept in an `Arc` grow that field's plain `Vec` from every
  thread (a double free): the rule asked App's mark alone. The same held
  for an Arc's App payload handed to a helper that grows that field. The negative
  mark now outranks the positive for the part, as it already did for one
  instance (#693). The error names both marks. A change the part orders
  itself, such as a send on its `Channel`, still compiles.
