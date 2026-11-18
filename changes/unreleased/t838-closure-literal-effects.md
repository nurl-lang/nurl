### Fixed

- **A returned closure's effects are no longer lost through a closure literal** (AGORA-838). Take `: ( @ v ) c ( mk xs )`, whose closure grows `xs`. Three shapes were accepted when the closure ran while a view of `xs` lived, and the view then read a freed buffer:
  - a literal that captures a copy of `c` (`: d c`, or `= d c` in an arm) and runs it;
  - a literal's call that hands `c` back (`: g \ → ( @ v ) { ^ c }`, `( g )`), or that builds the closure from its own parameter;
  - a literal that hands back the closure it is given (`\ ( @ v ) f → ( @ v ) { ^ f }`).

  These are now refused, as running `c` directly is. A closure that only reads what it captured stays accepted. Nothing new is asked of the author.
