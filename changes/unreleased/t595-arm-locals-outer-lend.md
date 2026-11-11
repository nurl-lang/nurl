### Fixed

- **An arm that ends in a lend of an outer binding releases its own locals** (Agora #595). `: S e ? c { : String junk … ( vec_at [S] v 0 ) } ( vec_at [S] v 1 )` never released `junk` (a leak once per run of the arm; the same in a `??` arm, and with the `?` as a call argument). An arm whose value is consumed kept its locals back in case the value was one of them; it now releases them at its exit when the value is a call's lend out of bindings made outside the arm.
