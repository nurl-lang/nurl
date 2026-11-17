### Fixed

- **A closure that gives one captured binding a lend of another no longer leaves a dangling borrow** (AGORA-904, AGORA-882). Inside a closure, `= o ( id other )` (or `= o { ( id other ) }`, or `: x ( id other )  = o x`) made the caller's `o` borrow `other`, but the caller never learned that. Replacing or consuming `other` after running the closure, then reading `o`, read freed memory.

### Changed

- **Breaking: such a binding now holds its own copy.** In the case above, `o` receives a copy of what the call lent, made only on the runs where the call lent it, the same way a lend of a closure-local value is already copied. A program that changed `other` after the closure ran and expected `o` to see the change now sees the value as it was when the closure ran. For a type with no copy (a `% Drop` struct), the store is refused, with a hint to give `o` a value of its own or keep the value outside the closure. Migration: no in-repo code needed a change. nurldb, nurllama and nurlapi get a guarded copy in a few closures, and their tests pass.
