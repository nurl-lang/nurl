### Changed

- **The reference ownership checker in tools/ncore follows a closure's stores into a captured binding as the compiler's engine does** (AGORA-887). Take a closure that leaves one captured `: ~` binding holding a view of another capture. The binding is now given that view where the closure runs, instead of the closure being refused outright. Four safe programs the engine accepts are no longer refused by the reference checker, and no faulting probe is newly accepted.
