### Fixed

- **A binding a closure captures, given a `:` binding of a join by name, gets a copy of its own** (AGORA-961). Inside a closure, `: e ? c ( id a ) ( id b )` then `= o e`, with `a` and `b` locals of the closure and `o` captured, leaked the local the join did not select. When the join could hand back `o`'s own value (`( id o )`), `o` was left holding freed memory. `o` is now given a copy wherever the join lends, as `= o ? c ( id a ) ( id b )` written directly already was. Nothing to change in your code.
