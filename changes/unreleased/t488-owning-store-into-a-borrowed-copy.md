### Changed

- **An owning value stored into a field of a borrowed copy is refused**
  (Agora #488, #643). A by-value (`in`) struct parameter, a `~` loop's
  element and a closure's by-value capture are each a copy of a value
  the code only borrows: `= . a name ( string_from … )` landed in that
  copy, the owner never saw it, and nothing released the new value (a
  leak on every call or round). Each is refused, naming the fix: take
  the parameter `inout` (the caller sees the store) or `sink` (the
  function owns the value and may hand it back); replace a loop element
  in its container (an index loop and `vec_put` / `vec_set`); declare a
  captured binding `: ~`, so the closure captures it by pointer.
- **A store that owns nothing into a loop element or a by-value capture
  is warned as lost**, as one into a by-value parameter already was: the
  container, or the binding outside the closure, keeps its old value.
