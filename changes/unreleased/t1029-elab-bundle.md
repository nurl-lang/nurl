### Added

- **A certificate's term checked by the kernel, for scalar programs** (AGORA-1029 step 3). For a program in `C.Elab.elabIR`'s subset, the bundle no longer trusts nurl-cert's translator (`packages/nurl-cert/src/tolean.nu`).
  - One more file, `Elab.lean`: the core IR as Lean data and the theorem `Cert.elab : C.Elab.elabIR ir = some (P, entry)`, by `decide +kernel`.
  - `nurl --certify` keeps it only when Lean proves `Cert.elab` on the standard axioms, checked beside the claims. Lean decides which programs are in the subset: 3 of the 62 certify programs (`while_loop_summing`, `int_recursion_early_return`, `loop_with_continue_and_break`). A term with a constructor `elabIR` never builds cannot be in it, and Lean is not asked.
  - What the `translation` ledger row still trusts is then `nurlc --emit-core` and the split of the core IR into words. `nurl verify` makes `Elab.lean` again from `Program.core`, compares it byte for byte, and has Lean prove `Cert.elab` again. Another program's term swapped in, with its hash updated, now fails a plain `verify`; before, only `verify --rebuild` caught it.
  - The manifest records the case with `hashes.elab_lean`. The schema stays `nurl-cert/1`. A bundle without it verifies as before, with the translator's ledger row, and so does one downgraded honestly (the file removed, the row the translator's again).
  - `nurl-cert` 0.2.0. `nurl-cert words` refuses a core IR that is not well-formed UTF-8.
