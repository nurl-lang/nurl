### Fixed

- **A cursor given its own value still borrows what it copies** (Agora #554). `: ~ ( Vec S ) j . h a`, then `= j j`, `= j { j }` or `= j { : i t 1 j }`, then `( vec_clear [S] j )`: the `=` was taken for a fresh value, so the clear ended no borrow of `. h a`'s elements and a String read out of one read freed memory (a heap-use-after-free). It is now refused, as the clear without the self-assignment is.
