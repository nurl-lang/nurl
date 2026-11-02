### Fixed

- **A closure is not called with a binding it replaces** (Agora #339;
  probes closure_called_with_*). `: ( @ v String ) c \ String p → v { = o
  ( same p ) }` then `( c o )` freed `o`'s old value, which the parameter
  `p` still was: a heap-use-after-free. The call is now refused, as `(
  put x x )` with an `inout` parameter is: pass a copy, or let the
  closure take the value as an `inout` parameter instead of capturing
  it. A closure that only reads its capture may still be called with it.
