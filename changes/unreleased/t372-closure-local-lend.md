### Fixed

- **A closure no longer hands back a lend of a Vec it drops** (Agora #372;
  probes closure_returns_*). `\ → Conn { : ( Vec Conn ) cs … : Conn c (
  vec_at [Conn] cs 0 ) ^ c }` handed its caller the element as owned, then
  dropped it with `cs` on the way out: a double drop. The same body as a
  function was refused. A closure's `^` of a binding that a call may lend
  (out of the body's own Vec, a capture, or through a join) is now refused
  the same way when the value cannot be copied. A String element is
  copied, and a `vec_get` payload is taken out of its slot, as before.
