# Changelog

## [0.3.0] — 2026-11-26

### Added

- More bundles get `Elab.lean` (AGORA-1029 step 4): `C.Elab.elabIR` now covers buffers of numbers too, raw text (`i8*`), `String`s and `Vec`s of numbers. Their moves, cursors, `drop`s and returns are covered, and so are `inout`, `sink` and read-only buffer parameters and the library calls `vec_new`, `vec_push`, `vec_len`, `vec_at` (a number element), `vec_free`, `string_from`, `string_len`, `string_free`, `nurl_str_cat` and `nurl_str_len`. Of the 62 certify programs, 19 are in the subset (3 before), and the 13 the checker accepts get `Cert.elab` (3 before). For those programs the translator is out of the trusted path.
  - The skip before Lean (`ELAB_CTORS`) takes the new constructors (`.push .free .new .borrow .at .len .vec .drop .realloc .dropIn`) and no longer skips a term for a `true`: `resOwn := true` is a Vec handed back.
- More bundles get `Elab.lean` (AGORA-1029 step 5): `C.Elab.elabIR` now covers views too. That is slices of `Vec`s of numbers, raw text viewed by `string_data`, and `Vec`s of raw strings. It also covers `foreach` over a `Vec` of numbers, and the library calls `string_data`, `slice_from_vec`, `slice_len`, `nurl_println`, `vec_clear`, `vec_truncate`, `vec_reserve`, `vec_shrink_to_fit` and `string_push_str`. Of the 62 certify programs, 32 are in the subset (19 before), and the 18 the checker accepts get `Cert.elab` (13 before).
  - The skip before Lean (`ELAB_CTORS`) takes the new constructors (`.edit .view .sat .slen .trunc .slice`).
  - certify takes 81.3 s over the 62 certify programs against 80.8 s for step 4 (+0.6 %): +0.3 to +0.8 s for each of the 13 programs new to the subset, the other 49 7.2 s faster in all, since the words now leave the library's functions out whole (docs/dev/TRANSLATION_TRUST.md, step 5).

### Changed

- **`nurl-cert words` leaves out the standard library's functions** whole, whenever Lean's reader would accept their `fn` and `v` lines. When it would not, those lines are printed, and the reader refuses the words as it refuses the whole core IR. Neither the translator nor `C.Elab.elabIR` reads anything else of a library function. `tools/ncore/elab_parity.sh` checks that `elabIR` answers the same either way over the corpus, and the selftest checks it over 11 core IRs, 8 of which the reader refuses. `Elab.lean` shrinks, and so does its check: `vec_push_len` has 55 lines of words (581 with every line, 157 with only the statement lines left out), `vec_cleared_then_pushed` 119 (407 with only the statement lines left out).
- **Breaking:** a 0.2.0 bundle that holds `Elab.lean` and whose core IR has functions of the standard library does not verify with 0.3.0: `verify` makes `Elab.lean` again from `Program.core`, and it is another file now. Migration: certify the program again. A bundle without `Elab.lean` verifies as before.
- **One Lean process per program.** certify and verify check a bundle in one Lean file, made in the work directory: Program.lean's definitions inside a `section`, then Claims.lean's body and Elab.lean's, with only the lines checked to be their exact imports left out. The bundle's three modules are unchanged and still check the module way. The selftest compares the two ways on three bundles. An error in the Elab.lean part means only that there is no Elab.lean. A run that dies (killed, out of memory) before its end, with no error in the claims' part, is run again once without the Elab.lean part: the claims still count, and there is no `Cert.elab`. certify prints why a candidate has none (`Cert.elab not proved: …`). No `Program.olean` passes from one Lean run to the next any more, and there is no second, concurrent Lean process.
- A refused `Cert.elab` (words whose term is not Program.lean's) fails in under a second: `C.Elab.elabIs` is irreducible to the elaborator, so `decide +kernel` no longer re-reduces it to explain the failure. That re-reduction had taken 111 s and 28 GB before the OOM killer stopped it.
- certify is 2 % faster over the 62 certify programs (82.1 s against 83.9 s). Peak memory per program is about the same outside the subset, and +78 to +110 MiB in it (docs/dev/TRANSLATION_TRUST.md, step 4).

## [0.2.0] — 2026-11-26

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
