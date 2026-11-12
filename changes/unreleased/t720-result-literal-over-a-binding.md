### Fixed

- **A result literal made of the function's own bindings is kept when a
  local's destructor panics at the function's exit** (Agora #720).
  `: String s …  ^ @ ?String { T s }` — the shape of every "take the value
  out, drop something else, hand back `Some(value)`" function — lost the
  value under `recover` when an earlier local's destructor panicked: the
  binding had handed it to the literal, and the literal was in no journal
  entry. It is journaled for the locals' drops now, as a literal of fresh
  parts already was: an option, a result, a struct over two bindings, a
  literal nested in one, a `sink` parameter. A literal that reads a value
  the function does not own — a parameter it borrows, the element a `~`
  loop is at in the caller's `Vec` — is left as it was.
