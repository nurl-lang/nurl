### Fixed

- **A module whose functions take or return closures can be imported under
  an alias** (found by Agora #659). The alias rewrite collects the names a
  module declares at its top level, and it took the `@` of a closure TYPE
  in a signature — `@ run_it ( @ v ) body → v`, `→ ( @ i K )` — for the
  start of a function declaration: "a function named `v`". Every such word
  in the module was then renamed, and compiling it failed far from the
  cause ("the function body ends without a return value (expected
  `m__v`)", "operator applied to an aggregate operand: left is `m__i`").
  Parentheses nest for the collector now, as braces do: an `@` inside them
  is part of a type.
