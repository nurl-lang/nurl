### Added

- **The kernel builds the certificate's term for programs on Vecs and strings too** (AGORA-1029 step 4). `C.Elab.elabIR` (`formal/C/Elab.lean`) now also covers buffers of numbers: raw text (`i8*`), `String`s and `Vec`s of numbers.
  - It covers their moves, cursors (`.borrow`), `drop`s, returns, and `inout`, `sink` and read-only buffer parameters, with the mode the walk's summary gives a buffer changed through its handle.
  - It lowers the library calls `vec_new`, `vec_push`, `vec_len`, `vec_at` (a number element), `vec_free`, `string_from`, `string_len`, `string_free`, `nurl_str_cat` and `nurl_str_len`.
  - 19 of the 62 certify programs are now in the subset (3 before). The 13 the checker accepts get `Elab.lean` and `Cert.elab` (3 before), so their bundles no longer trust the translator `packages/nurl-cert/src/tolean.nu`.
  - Where the translator's checks reach past what it translates, `elabIR` makes them too. A buffer's `drop` is refused when a later line names the buffer, or an element read out of it, as the translator's `__views_of` refuses it. `elabIR` stays stricter than the translator, never laxer: it refuses a `Vec` of anything but numbers, a call whose result may be a view, and a `let` of a `vec_push`. Each check has a kernel witness for its refusal and for its well-formed neighbour.
  - `tools/ncore/elab_parity.sh` finds 0 differences and 0 programs `elabIR` takes but the translator refuses. Its fixtures move to `tools/ncore/elab/`, with 13 new programs on Vecs and strings.
  - `nurl-cert` 0.3.0: the skip before Lean (`ELAB_CTORS`) takes the new constructors, and a `true` in a term (`resOwn := true`) no longer skips it.

### Changed

- **`nurl-cert words` leaves out the statement lines of the standard library's functions** (AGORA-1029 step 4). A library function keeps its `fn`, `v` and `endfn` lines. Neither the translator nor `C.Elab.elabIR` reads those lines: both take the library's functions for A2's constructs, by the same `stdlib/` test. `tools/ncore/elab_parity.sh` checks that `elabIR` answers the same on every core IR either way. A program's `Elab.lean` shrinks (`vec_push_len`: 581 lines of words to 157), and so does its check.
  - **Breaking:** a bundle from nurl-cert 0.2.0 that holds `Elab.lean`, and whose core IR has functions of the standard library, no longer verifies, since `verify` makes `Elab.lean` again from `Program.core` and the file is different now. Certify the program again. A bundle without `Elab.lean` verifies as before.
- **certify and verify run one Lean process per program**: Program.lean's definitions, the claims and `Elab.lean`, in one generated file. The bundle's modules are unchanged and still check the module way. No `Program.olean` passes from one Lean run to the next any more. Over the 62 certify programs certify takes 82.1 s against 83.9 s before. A program's peak memory is about the same outside `C.Elab`'s subset, and +78 to +110 MiB in it.
- A refused `Cert.elab` fails in under a second: `C.Elab.elabIs` is irreducible to the elaborator, so `decide +kernel` no longer re-reduces it to explain the failure. That re-reduction had taken 111 s and 28 GB before the OOM killer stopped it.
