# v1 hardening continuation

Work on branch `codex/v1-validation-hardening`. PR #1107 is a draft;
do not merge it or declare v1 hardening complete from focused results.
The complete scope and evidence requirements remain in
[V1_HARDENING.md](V1_HARDENING.md). The external LLM-written audit supplies
hypotheses, not authority.

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
differential fuzzer now reaches those guards: half of its divisors and shift
amounts are computed sub-expressions clamped into the legal domain rather than
literals, so the guard branch is live at -O0 and the oracle catches a guard
that fires on a legal operand.

Thirteen defects of one shape are closed: a construct the language allows,
reached by a path that skipped its own check. Ten in the parser — a binding
initialised by a block, a global constant with no value, a struct or generic
function with no body, an unclosed type-parameter list, a `:` followed by
junk, a function whose body is empty, two parameters sharing a name, a match
with no arms, and a foreach over something that is not a slice. Each exited 0
and lost the declaration after it, or emitted IR only clang rejected — or, in
the foreach case, IR with empty types and nothing on stderr at all.

Three more in the type checker. A field WRITE to a name the struct does not
have stored into field 0 and printed `store  5, * %r` with no types; the read
side had rejected the same typo for years, with a comment explaining exactly
this miscompile. And the pre-registered C-runtime surface — `nurl_print` and
the 117 others every program calls — was registered with a return type only,
so its call sites had no arity or argument check at all: `( nurl_print 5 )`
compiled and segfaulted dereferencing 5. Those symbols now get the FFI path's
own side-tables, filled by parsing the `declare` lines the compiler already
emits, so there is no second table to drift.

`tools/tests/test_declaration_forms.py` pins the class with one invariant
over 44 forms; the corpus pins each fix with its own rejection. Opening the
block-initialiser path also exposed a borrow-checker hole: `bck_esc_let`
recorded a referent depth without comparing it, so a closure over a
block-local `: ~` struct could be bound outside that block.

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
controls cover it.

## Latest compiler verification

Both refreshed bootstraps pass. Normal build: 55-57 s; corpus 2 m 30 s. The
corpus reports **985 PASS / 19 SKIP** over 1,004 inputs, with zero
compiler/link/runtime/timeout failures. All seven arithmetic methods pass
with both normal and instrumented compilers: 596 runtime cases across three
modes, **1,788 executions plus two rejections**. All 31 ownership, seven
compiler-cleanup and 20 LSP methods pass on the final shared instrumented
toolchain. All six compiler leak-gate sources pass ordinary and split
emission; sanitizer detection calibration also passes.

After the parser changes, the 303 diagnostics the stdlib, packages and
examples produce are byte-identical to those the pre-change compiler produced
over the same 719 files. That is the check that matters most for a parser
edit: the corpus cannot see code it does not contain.

Fuzz campaigns on the changed compiler: 600 integer seeds, 150 structural
seeds with 37 sanitizer runs, and 200 inverse-oracle seeds — all clean.

Ownership traffic through the newly reachable block-expression path was
checked separately under ASan+LSan with leak detection on: an owned tail
value, one bound inside the block and handed out, a second owned local
dropped at block exit, nested block initialisers, and allocation inside a
loop. Correct values, zero findings.

## Remote state and next work

1. Every remote job passed on this branch at `070ff0a8`: the Linux compiler
   job, FreeBSD, macOS ARM64, Windows, the sanitizer job, the runner
   fault-injection controls, the unikernel job, the MinGW msvcrt cross-link
   job, required-tool fault injection, webdocs and all four JavaScript
   audit/build jobs. That validates those revisions and those workflow
   scopes, not every distribution target. Keep PR #1107 a draft. The commits
   after `070ff0a8` are pushed; confirm their remote results.
2. Continue the sweep that found those thirteen defects. Take a construct
   the grammar allows, write it in a spelling nothing in the tree uses, and
   check the implementation against `spec/grammar.ebnf`. Declarations and
   simple statements are done; expression position, trait/impl bodies,
   select arms, foreach and the `!`/`?` operator forms are not. The
   permanent control is `tools/tests/test_declaration_forms.py` — extend its
   table rather than writing a second harness. The two questions that found
   the most: what does this construct do in a spelling nothing in the tree
   uses, and does the WRITE side of a check exist as well as the read side.
3. A token-deletion sweep over corpus programs (delete one token; the
   compiler must either reject the file or still emit `main`) is written but
   has not completed a clean run — twice interrupted by rebuilding or
   cleaning the tree underneath it. Run it against a PRIVATE copy of
   `build/nurlc` and keep its mutants out of `compiler/tests/`; one was
   committed by accident and had to be removed.
4. A01's stack-lifetime item is narrower than the ledger recorded, and its
   cited probe has been resolved. Written with a `: ~` struct the capture is
   by pointer and the assignment is rejected at compile time; written with a
   scalar — which is how a probe that PRINTS 42 must have been written — the
   capture is by VALUE, so there is no dangling reference to detect and the
   clean exit was the right answer. Running that probe under LeakSanitizer
   instead found two real leaks in the closure-env machinery, both fixed and
   pinned by `closure_env_assign.nu`.

   What remains: every NURL alloca is hoisted to the entry block and lives
   for the whole function, so a use-after-scope inside one frame is not a
   memory error today — at worst a slot reused across loop iterations. The
   escape that IS a dangling pointer, a stack reference outliving its
   function, is rejected in every spelling tried (assignment, struct field
   store, conditional arm, closure of closure, nested blocks, loop body,
   interprocedural, and block-expression initialisers). A lifetime-marker
   policy therefore buys detection and stack reuse, not correctness, and
   must still account for deferred cleanup reaching a slot after its lexical
   block. Decide whether that trade is worth making before writing it.

   The technique that paid here is worth repeating on its own: run existing
   probes under LSan, not only ASan. The leak was invisible to every ASan
   run and to the default sanitized corpus, which sets `detect_leaks=0`.
5. Continue A13/A16 indirect/generic/embedded-origin and cleanup
   counterexamples; borrowed-initial mutable bindings and raw/FFI boundaries
   need broader review.
6. Retain every A01-A17 requirement. A07 (continuous package/service tests)
   is still only an inventory question, and it sits against the standing
   decision not to wire package tests into compiler CI — that needs a
   direction before work, not after. A09, A14 and A17 are untouched. A15's
   remaining halves are pinned tool downloads and a staged unpack: the
   installer removes the old toolchain before extracting, so an extraction
   interrupted after verification leaves a broken prefix that only a re-run
   repairs.

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
- `NURL_TEST_PWSH=/absolute/path/to/pwsh python3 tools/tests/test_compiler_runners.py`
- Never rebuild shared compiler/runtime outputs while tests consume them; never
  overlap corpus runners using the same verdict directory.
- `python3 tools/gen_globals_map.py` after compiler edits; keep both bootstrap
  snapshots together. Preserve `vec_push_temp_owned`'s golden: `item3`, exit 0.
- Set `DEBUGINFOD_URLS=''` for isolated sanitizer probes to avoid symbol-server
  waits. Use bounded process execution and retain sanitizer errors.
