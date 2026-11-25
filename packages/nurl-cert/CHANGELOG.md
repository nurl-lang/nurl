# Changelog

## [Unreleased]

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

## [0.1.0] — 2026-11-25

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
