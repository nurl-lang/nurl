### Changed

- **A certificate's term is made by a translator written in NURL** (AGORA-1020). `nurl-cert` turns the core IR (`nurlc --emit-core`) into the Lean term itself (`packages/nurl-cert/src/tolean.nu`, on the one core IR reader `coreir.nu`): no Python runs between `Program.core` and the theorem, and `python3` is no longer needed to certify. `nurl-cert translate prog.core` prints the term.
  - It is the port of `tools/ncore/tolean.py`, which stays its reference. `tools/ncore/tolean_parity.sh` runs both over the 58 certify programs and every hole probe (4300 core IRs): 0 differences in stdout, exit class or `unsupported` message. Over those 4300 core IRs the NURL translator takes 15.1 s where tolean.py takes 182 s, one at a time (3.8 s against 27.4 s on 12 jobs).
  - The trust ledger's `translation` and `library-summaries` rows name the new translator. A bundle written before this change no longer verifies (its ledger rows are the old text): certify it again.
