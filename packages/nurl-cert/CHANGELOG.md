# Changelog

## [0.2.0] — unreleased

### Added

- The term checked by the kernel, for the programs `C.Elab.elabIR` covers (the scalar subset; AGORA-1029 step 3). A bundle can hold one more file, `Elab.lean`: Program.core's words (`nurl-cert words`) and the theorem `Cert.elab : C.Elab.elabIR ir = some (P, entry)`, by `decide +kernel`.
  - `certify` writes it for a program the checker accepts and keeps it only when Lean proves `Cert.elab` on the standard axioms. Lean runs on it beside the claims' check. A program whose translated term holds a constructor `elabIR` never builds cannot be in the subset, and gets no attempt. Of the 62 certify programs, 3 are in the subset.
  - With it, the `translation` ledger row says what is left: `nurlc --emit-core` and the split into words. `verify` makes Elab.lean again from Program.core and compares it byte for byte, then has Lean prove `Cert.elab` again. A swapped Program.lean, with its hash updated, now fails a plain `verify`.
  - The manifest records the case with `hashes.elab_lean`. The schema stays `nurl-cert/1`: bundles without it verify as before, with the translator's row.

### Changed

- `nurl-cert words` refuses a core IR that is not well-formed UTF-8 (exit 1): Lean would read such a byte as U+FFFD, another word.
- The bundle's format changed (one optional file and hash), hence 0.2.0. An older `verify` refuses a bundle that has it.

## [0.1.1] — 2026-11-26

### Fixed

- A certificate's claims cover every run, whatever the program's numbers (AGORA-1030): an untracked number is A2's `Expr.any`, not `.lit 0`, which made the model take every if's else arm. Certify 0.1.0 bundles again.

## [0.1.0] — 2026-11-25

### Changed

- The translation from the core IR to the Lean term is written in NURL
  (`src/tolean.nu`, on the core IR reader `src/coreir.nu`), and no Python
  runs between `Program.core` and the theorem: `python3` is no longer
  needed, and the `--tolean` option is gone. The translator prints exactly
  what the Python prototype `tools/ncore/tolean.py` prints, which stays its
  reference: `tools/ncore/tolean_parity.sh` compares the two over every
  certify program and every hole probe (AGORA-1020).
- The `translation` and `library-summaries` ledger rows name
  `packages/nurl-cert/src/tolean.nu`.

### Added

- `nurl-cert translate prog.core`: the Lean term of a core IR on stdout,
  or `unsupported: <why>` on stderr and exit 2 (exit 1 for a core IR it
  cannot read).
- `tests/translate_test.sh`: core IR edits the translator must refuse,
  and the translator against `tools/ncore/tolean.py` on every certify
  program.

### Added

- `nurl-cert certify prog.nu`: a certificate bundle (`prog.cert/`) whose
  `Claims.lean` proves `M.safe` and `M.leak` about the program's own term
  in `formal/A2`, the checker's verdict decided by the Lean kernel
  (profile `kernel`) or by compiled code (profile `fast`, claims
  `validated`); `manifest.json` with statuses, coverage, hashes, versions
  and the trust ledger (docs/dev/CERTIFICATE.md, schema `nurl-cert/1`).
- `nurl-cert verify prog.cert [--binary prog]`: the bundle checked again
  without nurlc; every disagreement printed and named.
- `tests/nurl-cert_test.sh`: the 58 certify programs, five tamper cases,
  the fast profile, and every manifest against the JSON Schema (AGORA-1019).
