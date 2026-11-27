### Changed

- **Certificate bundle schema bumped from `nurl-cert/1` to `nurl-cert/2` (AGORA-1033, part of AGORA-1015).**
  `nurl-cert` now emits conditional memory-safety certificates for single-threaded programs that contain functions the translator does not yet cover, whenever each such function's signature, callee set and local `hasThru` bit can be derived unambiguously from the core IR and at least one own function is translated:
  - `Program.lean` emits a stub (`body := (.seq s .panic), nvars := 0`) for each assumed function and appends `def assumed : List Nat := […]` after `def entry`.
  - `Claims.lean` imports `C.Complete`, checks `C.certOK2BA P assumed entry 1 = true`, and states `M.safe` and `M.leak` over every completion `P'` satisfying `C.Completes` and `C.AssumedOK`.
  - `manifest.json` records one trust-ledger row `assumed-fn:<name>` per assumed function (naming its completion and proof obligations, `file:line`, and reason), lists those rows in `M.safe`/`M.leak`'s `premises`, sets `M.safe`/`M.leak` status to `assumed`, keeps assumed functions `unsupported` in `coverage.functions`, and marks every translated function `proved` (under `kernel`) or `validated` (under `fast`). Exit code for conditional acceptance is `0`.
  - `nurl-cert verify` rebuilds conditional `Claims.lean` from the template, checks `def assumed` and each stub's signature/callees/`hasThru` in `Program.lean` against `Program.core` and the manifest's `assumed-fn:*` ledger rows, and re-runs Lean.
  - **Migration:** existing `nurl-cert/1` bundles must be re-certified with `nurl-cert certify` (and `formal/` built with `lake build C.Cert C.Cert3 C.Elab C.Complete`).
