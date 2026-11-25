### Changed

- **A certificate's term is made by a translator written in NURL** (AGORA-1020). `nurl-cert` turns the core IR (`nurlc --emit-core`) into the Lean term itself (`packages/nurl-cert/src/tolean.nu`, on the one core IR reader `coreir.nu`): no Python runs between `Program.core` and the theorem, and `python3` is no longer needed to certify. `nurl-cert translate prog.core` prints the term.
  - It is the port of `tools/ncore/tolean.py`, which stays its reference. `tools/ncore/tolean_parity.sh` runs both over the 58 certify programs and every hole probe (4300 core IRs): 0 differences in stdout, exit class or `unsupported` message. Over those 4300 core IRs the NURL translator takes 15.1 s where tolean.py takes 182 s, one at a time (3.8 s against 27.4 s on 12 jobs).
  - The trust ledger's `translation` and `library-summaries` rows name the new translator. A bundle written before this change no longer verifies (its ledger rows are the old text): certify it again.
  - A core IR that is not one nurlc prints is refused, never read as something else (`nurl-cert translate` exit 1, `internal: …`): a needed column that is not an integer, a `ty` line with fewer fields than it counts, an `endfn` with no function open, a statement missing a word. Variable ids are indexed sparsely, so an IR with an id of 10^9 costs no more than one with 10.
  - Intentional deviations from `tolean.py` (fail closed on malformed IR): a statement whose operand count exceeds its operand words, and a block with no `end` before its function's end (or an `end`, `else`, `arm` or `loopcond` out of place), are refused, where `tolean.py` reads them. nurlc prints neither shape.
  - Deliberately stricter as well: a core IR record malformed in shape is refused (`internal: line N of the core IR: malformed: …`): a count below 0 (parameters, fields, type arguments, variants, payloads, a statement's operands), a type's counts past its line, a variable id below 0 or a kind outside 0–3, an `fn` line while a function is open, the input ending inside a function.

### Added

- **`nurl-cert translate` translates a program that spawns threads for A3** (AGORA-1020). A program with `thread_spawn_owned` becomes a term for A3's checker (`C.certOK3B P spawns entry 1`, `formal/C/Cert3.lean`): the spawned closure at class `send`, its captures by value (numbers, Vecs of numbers, channel shares), one spawn wrapper per closure code (`def spawns`), `!Thread ThreadErr` as a sum, `thread_join` as a read of the handle. A spawned closure that captures a binding by name is unsupported. A program that spawns nothing is translated as before, byte for byte.

### Added

- **Certificates of threaded programs: `M.race`** (AGORA-1020). A program that spawns with `thread_spawn_owned` is translated for A3: the spawn becomes A3's spawn-only call of a wrapper that takes the closure over (class `send`), the join a read, a thread handle an integer, and `!Thread ThreadErr` a sum. Its Claims.lean then proves `M.safe`, `M.leak` and `M.race` over every interleaving of its threads, from `C.certOK3B` (`formal/C/Cert3.lean`, C14). `M.race` rests on the new `drf-sc` ledger row.
  - The verified checker's closure literal takes the class its interface declares where it fits (`C.packClass`, `C.fitsB`); every other closure keeps `any`. All 4505 hole and certify probes keep their verdicts.
  - New certify programs: two threaded programs certified and two refused. One of the refused pair is a channel alias moved and then read, which guards the encoding.
  - What the threaded claims cover: the translation takes every `thread_spawn_owned` to succeed, so a run in which `pthread_create` fails is outside the claims. The threaded `M.leak` covers runs in which every thread finishes. The sentences say both.
  - A spawned closure gets the `send` class only when the spawn is its single use. One reused after the spawn, or passed to a function that takes the ordinary closure type, is `unsupported`, not refused: `thread_spawn_owned` copies the environment, and the copy is not translated yet.
  - The translator also refuses surplus type-argument columns and operand words past a statement's count (`internal: … malformed`).
