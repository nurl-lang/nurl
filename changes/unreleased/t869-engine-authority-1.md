### Fixed

- **Six open soundness holes closed** (AGORA-689, AGORA-696, AGORA-762, AGORA-841, AGORA-848, AGORA-868). Every faulting shape of these holes now compiles to code that runs clean, or is refused or stopped at run time:
  - A function whose closure keeps a captured by-value parameter now takes the parameter over (AGORA-868).
  - A struct whose owning field is a slice is now released and moved with its holder (AGORA-848, AGORA-841).
  - A lend handed back through a `??` payload, a `vec_at` binding or a slice cursor is now copied (AGORA-762).
  - `thread_spawn`'s crossing check now counts a sealed handle's direct `Arc` field (AGORA-689).
  - A loop's handle local is now judged by what it points at by the round's end (AGORA-696).

  Their open probes graduate into `tools/fuzz/holes`.
- **A new hole found and closed.** A `% Drop` value that cannot be copied, handed back as a whole lend through a binding by a function that takes the parameter over on another path, was let through and freed the caller's binding under the result. It is refused now, as the direct `^ ( g0 p )` form already was.
- arima, nwasm and `bytes_from_str` no longer free a field by hand before a call that may panic. The field's `=` releases the old value once the new one is made.

### Changed

- **Breaking (pre-1.0):** a struct whose only owning field is a slice is now an owning value. It moves on `=` and is released wherever it is kept. `= out tmp`, refused before (`diag_owned_fields_alias`), now compiles and runs clean. No in-repo code relied on the refusal.
- **The ownership engine (`nurlc --engine-decides`, opt-in)** now refuses most of what the borrow walk refuses, in every spelling. That covers 63 of the 89 shapes only the walk caught, and most of the open holes' faulting shapes. The ordinary compile is unchanged; the walk stays the authority. Its diagnostics carry a `note:` and a `help:` for each group.

### Known open

- Five holes found by this change's adversarial pass and filed with their probes: AGORA-872, AGORA-873, AGORA-874, AGORA-875, AGORA-876.
