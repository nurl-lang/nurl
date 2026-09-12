# v1 hardening continuation

The complete scope and evidence requirements are in
[V1_HARDENING.md](V1_HARDENING.md). The external LLM-written audit supplies
hypotheses, not authority. No item below certifies the whole language or
ecosystem, and passing a narrow check does not establish a broad guarantee.

## Current implementation

The compiler's stable address graph tracks returned, stored, captured and
unverified-call origins. Dynamic return proofs survive forward/indirect calls,
bound returns and defer/cleanup; the runtime proof channel is thread-local.
Original result proofs and selected cleanup owners use separate slots, and
return-site transfers preserve cleanup on other paths.

The temporary-consumer helper whitelist is removed. Source functions use
inferred effects regardless of result type. Audited primitive effects come
from their actual LLVM declarations; unknown foreign/indirect calls retain
arguments conservatively, including addresses cast to integers. Readonly
foreign return aliases remain tracked. Same-named NURL definitions do not
inherit primitive contracts. See the contract boundary in
[compiler memory discipline](COMPILER_INTERNALS.md#4-memory-discipline).
A mutable string initialized from a proved owned local receives its own copy,
repairing the compiler's lint cursor leak while preserving borrowed-parameter
and opaque-address identity. All 20 LSP tests now enable LSan in CI.

Source arithmetic guards integer zero division/remainder, signed MIN/-1,
dynamic invalid shifts and out-of-range/NaN/infinite float-to-integer casts
before LLVM undefined behavior or poison. Scalar and aggregate-field casts
share unsignedness, bounds and bool rejection. Fractional values that truncate
into range remain valid; IEEE floating arithmetic is unchanged. The
differential fuzzer reaches those guards: half of its divisors and shift
amounts are computed sub-expressions clamped into the legal domain rather than
literals, so the guard branch is live at -O0 and the oracle catches a guard
that fires on a legal operand.

**Nineteen defects of one shape are closed: a construct the language allows,
reached by a path that skipped its own check.** Thirteen were found by
sweeping declarations and simple statements; four more by continuing the same
sweep into expression position, trait and impl bodies, match and select arms,
and the block terminators; two more by the token-deletion sweep.

Ten in the parser — a binding initialised by a block, a global constant with
no value, a struct or generic function with no body, an unclosed type-parameter
list, a `:` followed by junk, a function whose body is empty, two parameters
sharing a name, a match with no arms, and a foreach over something that is not
a slice. Each exited 0 and lost the declaration after it, or emitted IR only
clang rejected — or, in the foreach case, IR with empty types and nothing on
stderr at all.

Three in the type checker. A field WRITE to a name the struct does not have
stored into field 0 and printed `store  5, * %r` with no types; the read side
had rejected the same typo for years, with a comment explaining exactly this
miscompile. And the pre-registered C-runtime surface — `nurl_print` and the
117 others every program calls — was registered with a return type only, so
its call sites had no arity or argument check at all: `( nurl_print 5 )`
compiled and segfaulted dereferencing 5. Those symbols now get the FFI path's
own side-tables, filled by parsing the `declare` lines the compiler already
emits, so there is no second table to drift.

Four more from the continued sweep. `Z NoSuchType` was the one type position
with no declared-type check, and emitted a getelementptr on a type nothing
declares. An or-pattern's ALTERNATIVES were never checked against the enum,
though the first name has been for years — `Red | Nope` emitted a load of a
global nothing defines. `break` and `continue` inside a `;` defer body
branched into a loop exit the defer chain had already left and re-entered the
chain from there, so `; { break }` inside a loop compiled, exited 0 and ran
forever; `^` was already rejected for that exact reason. And an impl was never
checked against the trait it names: a missing required method, a wrong arity,
wrong non-receiver parameter types and a wrong return type all compiled. The
last is a type confusion, not a convenience — `dyn` builds its thunk from the
DECLARED signature, so a trait promising `→ i` implemented with `→ s` hands
the caller a pointer to read as an integer, with no diagnostic anywhere.

Two more came from the token-deletion sweep, and both swallowed a whole
declaration. Deleting one `}` left a trait body unterminated: the method-header
scan advanced to "the first `{`", which is then the NEXT declaration's brace,
so `: Dog { i pitch }` became the method's default body and the trait appeared
to end at some inner `}` — while the emit pass skips BALANCED braces and
therefore consumed to end of file. The two passes disagreed about where the
trait ended and `main` was inside the difference: exit 0, no `main`, nothing
on stderr. Deleting one `{` did the same to a generic template with a trait
bound (`@ ship [T: Send] T v → i`): the collector took tokens "until the next
`{` anywhere", found `@ main → i {`'s brace, and called everything after it
the template's body. Only the BOUNDED form reaches that path, which is why no
hand-written spelling had found it.

Both header scans now stop at the `→` and consume exactly the return type,
and a trait or impl body rejects any token that is neither a method nor an
associated type instead of skipping it — that skip is what made an
unterminated body dangerous, and it was also silently accepting `% Sh { 42 }`
and an impl body full of junk.

`tools/tests/test_declaration_forms.py` pins the class with one invariant over
**95 forms** in three tables; the corpus pins each fix with its own rejection.
Opening the block-initialiser path also exposed a borrow-checker hole:
`bck_esc_let` recorded a referent depth without comparing it, so a closure over
a block-local `: ~` struct could be bound outside that block.

Two tree gates were checking less than they claimed. The canonical-form gate
named five directories and left 464 first-party files ungated (18 had
drifted); the strict-arity gate named six and left `unikernel/` and
`pttvoice/` out. Both now take the tracked inventory from git. Both were
serial, one process per file, which is what pushed the compiler job past its
15-minute budget into a cancelled run; both now run under `xargs -P`, and the
job finishes in about eleven minutes.

The release workflow attached whatever the build jobs produced, by glob, with
only the Linux matrix as a hard gate — a failed Windows leg published a
release with no `.zip`, and the PowerShell one-liner then 404s.
`tools/check_release_artifacts.sh` runs before publication and requires the
documented set, its checksums, and its signatures when signing ran; eleven
controls cover it. The installer now stages its unpack, so a failed extraction
leaves the existing install intact, and every tool a workflow downloads is
pinned by sha256 — including the zig that ships inside the published archive.

## Latest compiler verification

Corpus **992 PASS / 19 SKIP** over 1,011 inputs, zero
FAIL/MISSING/ORPHAN. Normal build 59 s; tests 2 m 56 s. The sanitized
corpus reports **992 PASS / 19 SKIP with zero AddressSanitizer, UBSan or
LSan findings**, zero timeouts and zero compile/link/run failures.
All seven arithmetic methods, all 31 ownership methods, seven
compiler-cleanup methods, two driver-path controls, the WASI IR control,
eleven release-artifact controls and six installer-unpack controls pass.
`nurlfmt --check` is canonical over 1,790 files; strict-arity, memgate,
dcegate and leakgate pass, the last on both emission modes.

The check that matters most for a change that ADDS diagnostics is the tree
sweep: every tracked first-party `.nu` file — **816 of them** — compiled with
the parent commit's compiler and with this one produces **byte-identical**
output and exit codes. The corpus cannot see code it does not contain; the
tree can.

**Sixteen** of the new `test_declaration_forms.py` rows FAIL against a
compiler built from the parent commit and pass against this one, and two of
the six installer controls FAIL against the previous installer. That is what
makes them controls rather than descriptions. The strongest single piece of
evidence is a mutant the sweep found BEFORE the fix existed
(`showcase.nu` with one `}` deleted): it is rejected by the repaired
compiler, so the repair answers a witness it was not written against.

## Next work

1. **Continue the same sweep.** Take a construct the grammar allows, write it
   in a spelling nothing in the tree uses, and check the implementation
   against `spec/grammar.ebnf`. Declarations, simple statements, expression
   position, trait/impl bodies, match and select arms and the block
   terminators are done. Not done: the `$`-import surface (aliased imports,
   nested aliases, the duplicate-include guard), generic instantiation at
   call sites, `dyn` construction and object safety, `inout` / `sink`
   conventions, and the `pub` visibility boundary. Extend
   `test_declaration_forms.py`'s tables rather than writing a second harness.
   The two questions that found the most: what does this construct do in a
   spelling nothing in the tree uses, and does the WRITE side of a check
   exist as well as the read side.

2. **One hole from the sweep is found and NOT closed.** A trait method header
   with no return arrow (`% Sh { @ area i o }`) is accepted at the
   declaration. Nothing consumes the recorded signature unless the trait is
   used dynamically, and the dyn re-parse is where it is reported today —
   `compiler/tests/diag_dynsig_context.nu` exists to pin that message and its
   context. Rejecting it at the declaration is the right place and would
   retire that fixture's witness, so it needs a decision about the fixture,
   not just an edit. The impl-signature check skips a header with no arrow
   for the same reason.

3. **Keep running the token-deletion sweep** (`tools/fuzz/mutate_delete.py`):
   delete one token; the compiler must either reject the file or still emit
   `main`. It found the eighteenth defect this round, in a construct no
   hand-written spelling had reached. It is single-threaded per invocation
   and a large corpus program is thousands of compiles, so run several
   `--seed`s in parallel rather than one long `--files` — one 12 KB corpus
   program is several thousand compiles, and two of the four seeds took about
   an hour each. **Seeds 1-4 are clean** against the repaired compiler; seed 5
   onwards is where the next one is.

4. **A01's remaining item is a recorded decision, not pending work.** Lexical
   stack lifetimes: every NURL alloca is entry-hoisted and lives for the whole
   function, so a use-after-scope inside one frame is not a memory error
   today, and the escape that IS a dangling pointer is rejected in every
   spelling tried. Lifetime markers buy detection and stack reuse, not
   correctness, and owe an account of deferred cleanup reaching a slot after
   its lexical block. Reopen it with that trade in hand, or leave it.

   What remains genuinely open in A01 is the leak inventory: 86 of 992 corpus
   programs leak under `LSAN_DETECT_LEAKS=1`, and the ledger attributes them
   to two root causes and one test-side habit rather than 86 defects.
   - **The closure-env class.** A closure RETURNED by a function has no
     owner: the binding path registers an env only for a closure LITERAL
     initialiser. The env pointer is knowable at the binding; what is missing
     is the fresh-vs-alias answer the string path gets from
     `__last_call_ret_owned__`. Registering without it is a double free, so
     this needs a summary bit, not a patch.
   - **The escape-classification class.** A parameter stored into a container
     that dies inside the same callee is classified as escaping, so the
     caller's fresh temporary is never freed by anyone. The whole `fmt` family
     does this, which makes it the idiomatic-printing leak. Fixing it needs
     either a dataflow refinement (a store into a container that provably dies
     before return is not an escape) or a parameter marker asserting
     non-escape the way `sink` asserts consumption — the second is a language
     decision.
   The criterion that separates a compiler defect from a test that simply
   never frees is "can the program free it?", not where the allocation was
   made. Apply it with a control, by writing the same call with the free
   present.

5. **A13's remaining scope.** The fourth strict check (a READ of a maybe-moved
   binding) is a recorded decision not to build: strict mode already reports
   1,070 sites across 553 first-party files, so its own acceptance bar cannot
   be applied, and the walk has no read events at all — it is a new record
   stream out of `gen_ident`, not an `if`. `docs/MEMORY.md` §2.9 now states
   that gap explicitly. Still open: opaque wrappers beyond `Channel`, whether
   the default, strict and raw guarantees agree on everything else, and A16's
   indirect/generic/embedded-origin cleanup counterexamples. Borrowed-initial
   mutable bindings are untouched.

6. **Retain every A01-A17 requirement.** A07 (continuous package/service
   tests) is still only an inventory question, and it sits against the
   standing decision not to wire package tests into compiler CI — that needs
   a direction before work, not after. A09, A14 and A17 are untouched; A14
   additionally requires external validation for the independent cryptographic
   review, which cannot be closed from inside this repo. A15 is closed.

7. **Remote results.** Confirm the remote runs for these commits. Previous
   remote state: every job passed at `070ff0a8` — the Linux compiler job,
   FreeBSD, macOS ARM64, Windows, the sanitizer job, the runner
   fault-injection controls, the unikernel job, the MinGW msvcrt cross-link
   job, required-tool fault injection, webdocs and all four JavaScript
   audit/build jobs. That validates those revisions and those workflow scopes,
   not every distribution target. The workflow edits in this round change how
   zig, wasmtime, cloud-hypervisor and rustup are fetched in the release,
   fuzz, CI and seven bench workflows; those legs have not run remotely since.

## Reproduction

- `NURL_TEST_JOBS=8 ./build.sh --refresh-bootstrap`
- `python3 tools/tests/test_arithmetic_safety.py` — seven methods / three modes.
- `python3 tools/tests/test_string_argument_ownership.py` — 31 methods.
- `python3 tools/tests/test_compiler_cleanup.py` — seven methods / 366 rejection goldens.
- `./tools/memgate.sh` and `./tools/dcegate.sh` — normal build.
- `./build.sh --san --no-tests`, then `NURL_SAN=1 ./tools/nurl-lsp/build.sh`.
- `ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 LSAN_OPTIONS=use_stacks=0 python3 tools/tests/test_lsp_toolchain.py`
- `./tools/leakgate.sh` and `NURL_SAN_JOBS=8 ./compiler/tests/run_san_tests.sh`.
- `python3 tools/tests/test_wasi_ir.py` — isolated shared-rewriter LLVM/leak control.
- `./packages/wasmbuilder/tests/build_test.sh` — require actual Wasmtime execution.
- `python3 tools/tests/test_driver_paths.py` — two real split/path controls.
- `python3 tools/tests/test_declaration_forms.py` — 95 declaration, statement
  and match-arm forms against one invariant; needs only `build/nurlc`, under 0.3 s.
- `python3 tools/tests/test_release_artifacts.py` — eleven controls over the
  release artifact-set gate; needs no toolchain at all.
- `python3 tools/tests/test_installer_unpack.py` — six controls over the
  staged unpack; serves a release over `file://`, no network, no toolchain.
- `python3 tools/check_pinned_downloads.py` and `./tools/check_installer_sync.sh`
  — the workflow and served-installer gates; both need no toolchain.
- `./compiler/tests/nurlfmt_check.sh` and `./tools/check_strict_arity.sh`.
- `python3 tools/fuzz/mutate_delete.py --files 40` — the token-deletion sweep.
  Tens of thousands of compiles; a hunting tool, not a gate.
- `LSAN_DETECT_LEAKS=1 ./compiler/tests/run_san_tests.sh` — the whole corpus
  with leak detection on, which the default run leaves off.
- `NURL_TEST_PWSH=/absolute/path/to/pwsh python3 tools/tests/test_compiler_runners.py`
- **The tree sweep, for any change that adds a diagnostic.** Compile every
  tracked first-party `.nu` file with the parent commit's compiler and with
  the new one, and diff the two transcripts. A corpus fixture cannot see code
  it does not contain; 816 real files can, and byte-identical output is the
  only evidence that a new rejection rejects nothing that was valid. Build the
  baseline by compiling `git show HEAD:compiler/nurlc.nu` with
  `build/nurlc_lastgood.bin` and linking against `stdlib/runtime.o`.
- Never rebuild shared compiler/runtime outputs while tests consume them; never
  overlap corpus runners using the same verdict directory. Both rules were
  broken in one session: a sweep died when `./build.sh` replaced `build/nurlc`
  underneath it, and a corpus run flaked with "Text file busy" when a second
  build started while the first was alive.
- `python3 tools/gen_globals_map.py` after compiler edits; keep both bootstrap
  snapshots together. Preserve `vec_push_temp_owned`'s golden: `item3`, exit 0.
- Set `DEBUGINFOD_URLS=''` for isolated sanitizer probes to avoid symbol-server
  waits. Use bounded process execution and retain sanitizer errors.
