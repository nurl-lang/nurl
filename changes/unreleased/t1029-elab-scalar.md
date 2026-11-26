### Added

- **The certificate's term built in Lean, scalar programs first** (AGORA-1029 step 2). `C.Elab.elabIR` (`formal/C/Elab.lean`) builds the A2 term from the core IR's words, the job of the untrusted translator `packages/nurl-cert/src/tolean.nu`, for programs whose functions work only on integers: calls (`inout`/`sink` int parameters included), `if`, loops, `break`/`continue` and returns. It is written so the kernel can run it (structural recursion; numbers read from a word's bytes). It fails closed on anything else, and it is stricter than the translator where they differ.
  - `C.Elab.elabIs_sound` lets a Boolean comparison prove `elabIR ir = some (P, e)`.
  - `elab_while` checks one program's term by `decide +kernel`.
  - `tools/ncore/elab_parity.sh` compares `elabIR` with the translator over every certify program, every hole probe and 18 new scalar programs (`tools/ncore/elab_scalar/`): 21 programs in the subset, 21 identical terms, each also checked by the kernel, and `none` for the rest. CI runs it.
  - Kernel time: 0.2–0.3 s per scalar program.
  - Certificates do not state their claims about `elabIR` yet: that is step 3.
