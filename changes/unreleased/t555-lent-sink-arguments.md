### Fixed

- **A join or a value block that only lends is copied for a `sink` parameter** (Agora #555). `( eat { . h a } )`, `( eat ? c . h a . h b )`, `( eat { w } )` and `( eat { { . h a } } )`, with `@ eat sink ( Vec S ) v`, handed the callee the value `h` or `w` still owned: the callee released it, and the owner released it again or read it (a double free or a heap-use-after-free). The callee now gets a copy, as it already did for a join of names. A block's own binding as its tail still goes to the callee itself.
