# Changelog

## [0.4.0] — unreleased

### Added

- **N.cap: what a program can do outside its memory** (AGORA-1013, formal C16). An accepted bundle whose N.cap check succeeds states which of the program's functions a run can enter, as a list in `Caps.lean` (`Cert.runs`), and proves it; when the check does not succeed (no capability table, or Lean does not prove the list), N.cap is `open`, the manifest gives the reason, and the bundle has no `Caps.lean` and no `capabilities`: the kernel checks that the list is closed under the program's names (`C.capsOKB`), and `Cert.n_cap` gives that any program with the same functions at those indices, whatever it has elsewhere, has exactly the same runs (A2), or the same interleavings (A3, a threaded program). What those functions do outside the program's memory is read off their calls in the core IR, through the library's bodies and `dyn` impls, down to the runtime's functions, each classed by the new capability table `stdlib/caps.tsv` (copied into the bundle as `caps.tsv`). The manifest's `capabilities` gives the list, each function's classes and one chain of calls per class; N.cap's sentence says what the program can do and what it never does, from fixed phrases (a program that reaches a runtime function the table does not class gets no "never": its effects outside its memory are not bounded). Three new ledger rows say what the classes rest on (`caps-table`, `caps-attribution`, `caps-binary`), and every `unsafe-<n>` row backs N.cap too. `verify` makes the list, the classes and the chains again from the bundle's own files, compares `Caps.lean` with the template byte for byte, and has Lean prove `Cert.n_cap` again. An unaccepted program's N.cap is `open`.
  - A conditional bundle (AGORA-1033) gets N.cap too, `assumed` on its assumed functions' rows when the check succeeds (`Cert.n_cap` is about the program with its stubs, which name the functions each real one calls); an assumed function's classes are read off its real calls, so a call the translation does not cover still shows (a `nurl_print`: `stdio.out`).
  - Of the 62 certify programs, the 36 the checker accepts prove N.cap; seeded programs get exactly their reachable calls' classes (a print in `main`, behind a closure, in a destructor and in a spawned thread is claimed; one in a function nothing calls is not).
  - Certify takes 64.56 s over the 62 certify programs against 65.10 s before (−0.8 %, best of 3 alternated runs against main 011e9589d; −1.7 % in a second run), and the sum of the peak RSS is the same within the runs' noise (−0.04 % and +0.02 %; threaded −0.66 % and −0.50 %). Lean's check of Caps.lean (about 20 ms a program) and the 5 MB its proof loads are paid back by nurlc's second compile on a thread beside Lean, Lean on two worker threads (`--threads=2`), one scan of the core IR, `formal/`'s commit read from git's files, and certificates' imports carrying no witness programs.
  - Schema: the manifest gains the optional `capabilities` and `hashes.caps_lean` / `hashes.caps_tsv`, and the claims list ends with `N.cap`: a bundle of this version does not verify with an older verify, and an older bundle (no N.cap) does not verify with this one. Certify it again.

- More bundles get `Elab.lean` (AGORA-1029 step 6): `C.Elab.elabIR` now covers closures over numbers and buffers of numbers. That is a closure's code, its literals (the captures by value packed into the environment, the others by name), calls through a closure value (`.callc` of its type's interface), closures handed to and back from functions, and `nurl_println_int`. Of the 62 certify programs, 45 are in the subset (32 before), all 13 closure programs among them, and the 26 the checker accepts get `Cert.elab` (18 before).
  - The skip before Lean (`ELAB_CTORS`) takes the new constructors (`.callc .pack .pair .fst .snd .prod .fn`). A term that holds one of `ELAB_CLO_CTORS` (`callc pack pair fst snd prod`) but no `.fn` is skipped too: `elabIR` never builds one (step 7 narrows the list to `callc pack`, below).
  - Certify takes 77.1 s over the 62 certify programs against 77.8 s before (−0.9 %; −4.6 % in an earlier run). The 13 closure programs new to the subset take +0.19 to +0.63 s each for their Elab.lean part (5 of them the checker refuses, and spend it too); the other 49 are 5.6 s faster in all, the 18 with Elab.lean among them 3.3 s, since the words are numbers now. The largest peak memory is about the same (2586 MiB against 2581 MiB); a new program's peak is +15 to +71 MiB, and the sum of the peaks is −1.1 %.

- More bundles get `Elab.lean` (AGORA-1029 step 7): `C.Elab.elabIR` now covers structs and options of the subset's types. That is a struct's literal (its fields nested in pairs), a field read through the pairs where an operand or a library call's argument names it, a number field's value, an option's literal (`.inl`/`.inr`), its match (`.isl`) and its payload (`.getr`), and a closure that takes a struct. No struct with a destructor. Of the 62 certify programs, 51 are in the subset (45 before), all 6 struct and option programs among them, and the 30 the checker accepts get `Cert.elab` (26 before). Outside stay the destructor, channel and thread programs.
  - The skip before Lean (`ELAB_CTORS`) takes the new constructors (`.inl .inr .getr .isl .sum`). `ELAB_CLO_CTORS` is `callc pack` now: `.pair .fst .snd .prod` are a struct's too, which `elabIR` builds. It is still exact.
  - `elabIR` costs the kernel less, most in a long function. A drop's check reads the lines after it as bits of one number (`maskAfter`), `retSplit` runs once a list rather than once a statement, the literals' temporaries are set aside and given back rather than counted and cut, and a variable's `v` line is found from the end: `joins_each_freeing_a_different_vec`'s certify takes 18.7 s against 19.9 s.
  - Certify takes 80.0 s over the 62 certify programs against 80.2 s before (−0.2 %; the sums of the per-program bests 77.7 s against 77.7 s). The 6 programs new to the subset take +0.11 to +0.39 s each for their Elab.lean part (2 of them the checker refuses, and spend it too); the other 56 are 1.55 s faster in all, most of it `joins…`. The largest peak memory is the same (2585 MiB); a new program's peak is +22 to +36 MiB, and the sum of the peaks is +0.2 %.

- More bundles get `Elab.lean` (AGORA-1029 step 8): `C.Elab.elabIR` now covers destructor frames, a struct with a `% Drop` of the program's own (A2's `.dtor f u`) whose fields are of the subset's types, a closure excepted. Its values are bound by `.letd` (a struct of one field padded with a number, raw text in a field a view), its destructor `drop__X` is a function of the program that reads its fields through the pairs, and a destructor value may be moved into another binding or lent to a read-only parameter. Not in the subset: a destructor value handed back, assigned, returned by a call, given to a `sink` or `inout` parameter, or held in another value. Of the 62 certify programs, 55 are in the subset (51 before), all 4 destructor programs among them, and the 32 the checker accepts get `Cert.elab` (30 before). Outside stay the channel and thread programs.
  - The skip before Lean (`ELAB_CTORS`) takes the new constructors (`.letd .dtor`). It is still exact.
  - The selftest's program outside the subset, and its tamper bundle, is `chan_int_sent_and_received` now (it was `destructor_frame_left_by_an_early_return`).
  - Certify takes 77.2 s over the 62 certify programs against 76.7 s before (+0.7 %, best of 3 alternated runs against step 7). The 4 destructor programs new to the subset take +0.20 to +0.45 s each for their Elab.lean part (2 of them the checker refuses, and spend it too); the other 58 are 0.8 s faster in all. A word's bytes are now read lazily (`wordGo` puts each byte at the head of a cons whose tail is not yet read), so a prefix test reads only the bytes it needs. The largest peak memory is the same (2588 MiB against 2587 MiB); a new program's peak is +23 to +47 MiB, and the sum of the peaks is +0.03 % (−0.3 % over the other 58).

- More bundles get `Elab.lean` (AGORA-1029 step 9): `C.Elab.elabIR` now covers channels of numbers, Strings and Vecs of numbers (A2's `.lk (.prod (.vec T) .int)`), in a program that spawns no thread. That is `chan_new` (`.lockNew` of a fresh queue and a 0 flag), `Channel_share` (`.lockClone`), `chan_send` (`.chanSend`, the value moves into the queue), `chan_recv` and `chan_try_recv` (`.chanRecv`, an owned option), and `chan_close` (`.chanClose`). A library type with a destructor (`%MutexImpl`, which `stdlib/std/channel.nu` brings) no longer keeps a program out; a value of one still does. Of the 62 certify programs, 58 are in the subset (55 before), all 3 channel programs among them, and the 34 the checker accepts get `Cert.elab` (32 before). Outside stay the 4 thread programs.
  - The skip before Lean (`ELAB_CTORS`) takes the new constructors (`.lockNew .lockClone .chanSend .chanRecv .chanClose .lk`). It is still exact.
  - The selftest's program outside the subset, and its tamper bundle, is `thread_spawned_with_a_number_capture` now.
  - Certify takes 76.5 s over the 62 certify programs against 76.8 s before (−0.3 %, best of 3 alternated runs against step 8, both formal/ trees built from scratch). The 3 channel programs new to the subset take +0.47 to +0.75 s each for their Elab.lean part (1 of them the checker refuses, and spends it too); the other 59 are 35 ms faster each, since Lean starts without `lake env` (below). `dOnlyOf` reads the `ty` lines in one pass. The largest peak memory is 2513 MiB against 2618 MiB, and the sum of the peaks is −12.8 %: `lake` no longer waits in every certify's process tree while Lean runs.

- More bundles get `Elab.lean` (AGORA-1029 step 10): programs that spawn threads. Their `Elab.lean` states `C.Elab.elabIR3 ir = some (P, spawns, entry)`: the kernel builds the program, its spawn wrappers and its entry from the core IR's words, A3's term. That is the spawn scan (each spawned closure followed back to its literal), a spawned closure of class `send` with an interface of its own, a spawn as a call of its code's wrapper whose result is the ok variant around a handle, a join, a result `{ i1, T, E }` as `.sum E T` with its error read by `.getl`, and a thread's handle and its error as numbers. Of the 62 certify programs, all 62 are in the subset (58 before), and the 36 the checker accepts get `Cert.elab` (34 before).
  - The skip before Lean (`ELAB_CTORS`) takes `.getl .send`. It is still exact.
  - Certify takes 80.9 s over the 62 certify programs against 76.5 s before (+5.7 %, best of 3 alternated runs against step 9): the 4 thread programs new to the subset take +0.85 to +1.41 s each for their Elab.lean part (2 of them the checker refuses, and spend it too), the other 58 the same (+0.34 s in all, within noise). The largest peak memory is 2487 MiB against 2513 MiB; a thread program's peak is +18 to +70 MiB. This is the price of the kernel building the 4 programs' terms: every certify bundle is out of the translator's trust now.

- **Coverage per function** (AGORA-1015, M2 part 1). The translation goes on past a function it does not cover, and `coverage.functions` gives each of the program's own functions its own status and reason (`unsupported`, `error`, or `open` for one that translates in a program that does not). The verdict and the claims are unchanged: the program is refused with the first unsupported function's reason. `nurl-cert coverage DIR` prints the Markdown table of the bundles `DIR/*.cert`; `tests/coverage.sh` runs it over the certify corpus, the hole sweep, `examples/`, the compiler tests and `packages/` (formal/README.md's table, and the nightly certify-coverage workflow). Of nurlc's own 3772 functions, 1268 translate.

### Performance

- The core IR reader splits a statement line only into its words, and keeps no second copy of the line: nurlc's core IR translates in 0.63 s against 0.94 s (peak 446 MB against 569 MB), and certifying nurlc, now through all its functions, takes as long as before with a peak of 512 MB against 629 MB.

### Fixed

- **A deep term, and a refusal Lean cannot explain** (AGORA-1034). Program.lean gives a deep term the elaborator bound it needs (`set_option maxRecDepth`, `cert_rec_depth`: 2 × the deepest nesting + 128, only past the default 512; the grammar check takes exactly that value). Where Lean's explanation of a failed `decide +kernel` fails too, certify proves the refusal (`certOK2B … = false`) in a run of its own, or the verdict stays `error`. `loop_nest_deep` is now accepted, and `option_payload_chain_forty_deep_compiles_fast` is refused with a proof.

- **Windows** (AGORA-1031): certify and verify run there. A path like `C:/…` or `\\host\share` is absolute (it was joined to the working directory), and a `--nurlc` or `--lean` path with a backslash is a path, not a command to look up. nurlc writes its records and core IR untranslated, so the bytes it lists are the file's bytes.

### Changed

- **The translator has no Python twin any more** (AGORA-1048). `tolean.nu` is the translation. The Python prototype it was held to byte for byte is retired, so translate_test drops its reference section, and the term is checked against formal/C's elabIR in the kernel. The `translation` ledger row names that check, not the parity script. The manifest changes only in that row's text, and that is a break: `verify` rebuilds the ledger and compares it exactly, so a bundle certified before this change no longer verifies. Certify it again; 0.4.0 already asks that for N.cap's schema, and no released bundle is affected.
- **Breaking: a bundle with `Elab.lean` has no `translation` ledger row** (AGORA-1029 step 11). In its place are `core-ir-words` (nurlc's core IR and its words) and one row per encoding of `C.Elab.elabIR`'s the term uses (`enc-numbers`, `enc-raw-text`, `enc-shapes`, `enc-destructors`, `enc-closures`, `enc-threads`, `enc-channels`, `enc-summaries`), each with its design note (docs/dev/TRANSLATION_TRUST.md, "The encodings"); each claim's premises name the same rows. Certify and verify read which rows off Program.lean's constructors. A bundle without `Elab.lean` keeps the `translation` row. Migration: a 0.4.0 bundle with `Elab.lean` made before this change does not verify (its ledger and premises are the old ones); certify the program again.
- **Breaking: `--lake PATH` / `$LAKE` is `--lean PATH` / `$LEAN`** (AGORA-1029 step 9). Certify and verify run `lean --json` inside `formal/` with `LEAN_PATH` set to `formal/`'s build (`env LEAN_PATH=<formal>/.lake/build/lib/lean lean …`), not `lake env lean`, which set the same path and cost ≈ 45 ms a run before Lean started. Run inside `formal/`, elan's `lean` picks `formal/`'s toolchain, as its `lake` did; an inherited `LEAN_PATH` is replaced, not used. Migration: pass `--lean` (a `lean` binary or a wrapper of one) where you passed `--lake`; with neither, nothing changes but the speed. In-repo, only the selftest passed `--lake` (its wrapper that kills Lean is a `lean` wrapper now).
- **`nurl-cert words` prints each word as a number**, not a string literal: `nat_lit 0x1`, then the word's bytes from the last to the first, two hex digits each. `C.Elab.wordOf` reads it back into the bytes (`wordOf_encB` proves it inverts the encoding), and `elabIR` compares the words with its keywords as numbers. In Lean 4.35 the kernel builds a string literal's bytes one `push` at a time, which is quadratic in the word's length: the file paths of the `fn` lines cost ≈ 130 ms each. The file is ASCII and needs no escaping, so a core IR that is not well-formed UTF-8 now has words too; one with a NUL byte still has none.
- **`nurl-cert words` leaves out a `sum` line outside every function whose name no other word holds.** `elabIR` looks a summary up only by a function's name, a callee's name, or the function a `let … call f` calls. A `sum` line inside a function is a statement of its body, which `elabIR` refuses, so it is kept. `tools/ncore/elab_parity.sh` checks that `elabIR` answers the same on the full words, selftest 2e checks both kinds of line, and translate_test 1c checks the rule against a Python reading of it.
- **Breaking:** Elab.lean's words are another text, so a 0.3.0 bundle with `Elab.lean` does not verify with 0.4.0 (`verify` makes Elab.lean again from `Program.core` and compares it byte for byte). Migration: certify the program again. A bundle without `Elab.lean` verifies as before.

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
