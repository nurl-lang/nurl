### Added

- **Conditional certificates for threaded programs (A3, AGORA-1035, part of AGORA-1015).**
  - `formal/C/Complete.lean`: added `C.certOK3BA`, `C.AssumedOK3`, `C.SpawnOK.complete`, `C.certOK3BA_claim`, `C.cert3_safe_cond`, `C.cert3_race_cond`, and `C.cert3_leak_cond`, proving A3 memory safety, race freedom, and leak freedom over every completion `P'` of a threaded program with assumed functions (standard axioms only, with a worked witness `C.cond3_witness_race`).
  - `packages/nurl-cert`: threaded programs with assumed functions whose signatures, callees, and `hasThru` can be derived from the core IR now emit both `def spawns` and `def assumed`, prove `C.certOK3BA P spawns assumed entry 1` in `Claims.lean`, record `assumed-fn:*` ledger rows covering `M.safe`, `M.leak`, and `M.race` with status `assumed`, and verify (including tamper checks).
