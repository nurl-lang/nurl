### Fixed

- **A returned closure keeps its effects through a copy, a join, an arm and a capture** (Agora #817). A closure that a call hands back now has a member of its own in the graph of what a closure binding may be. So `: d c`, `= d c`, `^ ? k ( mk x ) ( mk y )`, a block or `??` arm ending in such a call, and `= c ( mk xs )` inside an arm or a loop all carry what running it does to the caller's view (heap-use-after-free before). A literal that captures it and runs it, `: d \ → v { ( c ) }` then `( d )`, carries it as well.

  An argument written as a join, a block, a `??`, a field of an element or a nested lend is followed to the bindings it names: one written outside every call may be the value itself, and one a call in it reads is lent out of. A block whose value is a call's lends what that call lends.

### Known issues

- **Assignments are not ordered.** As for closure literals, the graph does not follow the order of assignments: a closure binding given a returned closure that changes a capture, then another one that does not, still counts as changing it.
- **Some routes still lose the effects** (Agora #838): a closure handed back through a pass-through call (`pick`, an identity, a generic), stored in a struct, Option or Vec and run from there, or handed to a helper as a join of closures. A builder declared below its caller or generic is Agora #813.
