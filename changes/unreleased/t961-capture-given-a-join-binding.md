### Fixed

- **A binding a closure captures, given a `:` binding of a join, gets a copy of its own wherever the join lends** (AGORA-961, AGORA-964). Inside a closure that captures `o`, `: e ? c ( id o ) ( id a )` then `= o e` left `o` holding memory the assignment had just released. So did `: e ? k ?? x { T s → s F → ( id a ) } ( id a )` then `= o e` when `x` was a fresh option, a closure-local option, or a `vec_get` of a closure-local Vec. `o` is now given a copy wherever the join lends, as `= o ? …` written directly already was. Nothing to change in your code.
