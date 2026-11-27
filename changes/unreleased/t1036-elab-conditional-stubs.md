### Added

- **Kernel elaboration of conditional certificate stubs (`Cert.elab`, AGORA-1036, step 3 of `docs/dev/CONDITIONAL_CERTIFICATES.md`, part of AGORA-1015).**
  - `formal/C/Elab.lean`: added `C.Elab.fnStubElab`, `C.Elab.elabIRCond`, `C.Elab.elabIR3Cond`, `C.Elab.elabIsCond`, `C.Elab.elabIs3Cond`, and soundness theorems `elabIsCond_sound` / `elabIs3Cond_sound` (with witness `elab_cond`) on the standard axioms only. For each assumed function index in `A`, the kernel builds the stub from `fn`/`v`/`sum` lines and syntactic call/`hasThru` classification without elaborating its body.
  - `packages/nurl-cert`: conditional certificates (both single-threaded and threaded) whose non-assumed functions lie in `C.Elab`'s subset now emit `Elab.lean` (`Cert.elab` proved by the kernel), replacing the `translation` ledger row with `core-ir-words` and encoding rows while keeping every `assumed-fn:*` row.
