### Fixed

- **A binding a closure captures, given a `:` binding of a join that may hand back the capture's own value, gets a copy of its own** (AGORA-961). Inside a closure, `: e ? c ( id o ) ( id a )` then `= o e`, with `o` captured, left `o` holding memory the assignment had just released. `o` is now given a copy wherever the join lends, as `= o ? c ( id o ) ( id a )` written directly already was. Nothing to change in your code.
