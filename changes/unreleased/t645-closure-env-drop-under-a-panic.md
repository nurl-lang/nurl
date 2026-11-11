### Fixed

- **A closure's captures, its environment and what stands beside it are
  released when a captured value's destructor panics** (Agora #645, #650).
  Under `recover`, a panic in the destructor of a value a closure had
  captured left the captures after it and the environment's block to no
  one, and — because the release of an environment was taken for a call
  no panic can start in — the struct fields after a closure field and any
  binding alive only across that release too: they leaked. A trait
  object's box leaked the same way when the boxed value's destructor
  panicked. The environment's drop method now records what is still to
  go, as a struct's drop glue does, and releasing an environment counts
  as a call that may panic exactly when one of the program's environments
  can. A program whose closures capture nothing with a destructor of its
  own compiles to the code it did.
