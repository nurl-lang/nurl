### Fixed

- **A closure stored in an `Rc` payload is now tracked as something the `Rc` holds** (AGORA-960). A helper handed an `( Rc H )` that runs `H`'s closure through `rc_get` ends the views of what the closure changes, as it already did for a struct, an option, a `Vec` or a `Box`. Before, a slice of another `Rc`'s payload, held across such a call, was read after the closure had replaced that payload (a heap-use-after-free).
- **A function that hands back a `box_new` or `rc_new` of a value holding a closure now says what that closure does.** A caller that runs it therefore ends the same views. Before, a maker's result counted as holding closures nobody here built.
