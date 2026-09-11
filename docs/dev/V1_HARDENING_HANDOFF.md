# v1 hardening continuation

Work on branch `codex/v1-validation-hardening`. The pull request is a draft;
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

The temporary-consumer helper whitelist is now removed. Source functions use
inferred effects regardless of result type. Audited primitive effects come
from their actual LLVM declarations; unknown foreign/indirect calls retain
arguments conservatively, including addresses cast to integers. Readonly
foreign return aliases remain tracked. Same-named NURL definitions do not
inherit primitive contracts. See the contract boundary in
[compiler memory discipline](COMPILER_INTERNALS.md#4-memory-discipline).

A mutable string initialized from a proved owned local now receives its own
copy. This repairs replacement/join leaks in the compiler's lint import walk
while preserving borrowed-parameter and opaque-address identity. These two
general changes fix the five LSP service leak failures and the preexisting
compiler lint leak they had masked. The full 20-test LSP CI step now enables
LSan with stack roots disabled.

The previous commits `8d34f800` (JavaScript audits) and `b3975cdb` (return/guard
ownership) remain the earlier verified checkpoint. All four JavaScript trees
have refreshed locks, clean installs, zero-finding manager audits and passing
builds/checks. Weekly/PR checks are wired; remote execution remains separate
from local evidence.

## Verification of the current change

The isolated no-whitelist candidate passes all 31 ownership methods, all seven
compiler-cleanup methods (including all 366 rejection goldens and positive
lint), instrumented self-compilation, and all 20 installed LSP controls with
ASan/UBSan/LSan and `use_stacks=0`. The refreshed shared normal compiler also
passes all 31 ownership methods. RSS is 36 MB (600 MB budget); DCE is 180 emitted
/ 12 reachable with identical behavior.

Both final shared bootstraps pass. The normal build takes 60 seconds and its
corpus 2 m 52 s; the sanitized build takes 86 seconds. Both 993-input corpora
report **974 PASS / 19 SKIP**, with zero sanitizer/compiler/link/runtime/timeout
failures in the sanitized run. All 31 ownership, seven compiler-cleanup and
20 LSP methods pass on the final shared instrumented toolchain. All six compiler
leak-gate sources pass ordinary and split emission (12 modes); the generated-code
sanitizer detection controls also pass. Source and bootstrap `.nu` are identical,
and the global-state appendix and site line count have been regenerated.

Commit `5e673886` additionally fixes the existing PR's macOS ARM64 driver failure:
a split-output prefix containing spaces was split into separate arguments. Both
local regressions fail before repair and pass after it, including forced split
linking and cleanup through names with spaces and glob characters. The driver
now carries those paths as individual arguments. Linux/macOS CI runs the controls;
new remote results remain pending.

## Failed controls retained as evidence

- `consumer-regressions-before.log`: Json copying leaks a temporary; an unknown
  foreign retaining wrapper instead frees its argument too early.
- `consumer-uncertain-*.log`: unknown-call propagation without primitive
  contracts leaks 1,028,315,679 bytes during self-compilation. Rejected.
- Intermediate ABI effects omit scalar length/index roles and leak 1,224 bytes
  on the SIMD rejection path. Explicit primitive value-only contracts fix this;
  arbitrary integer arguments remain possible address carriers.
- `guard2-lint-before.log`: the previous compiler leaks 2,706 bytes in a positive
  lint/import walk. `mutable-cursor-before.log` independently pins the 33-byte
  mutable replacement/join leak.
- `guard-final-lsp.log`: the previous full LSP run fails five controls. The new
  passing run is `lsp-nohelpers-tests.log`; no service leak suppression remains.

## Next work and boundaries

1. Publish the verified checkpoints to the existing draft PR #1107 and inspect
   its new checks, including the previously failed macOS driver step. Keep the
   PR a draft; do not merge it.
2. Continue A01's source-level arithmetic/LLVM poison work. Seven independent
   C-input probes at O0/O2 are retained in `arithmetic-before/` and
   `arithmetic-before.log`: signed division/remainder overflow traps as native
   FPE at O0 but passes silently at O2; invalid dynamic shifts, NaN/infinity
   casts and negative-to-unsigned casts pass silently at both levels. No source
   panic occurs. These are failed safety controls, not sanitizer successes.
   Pin expected failures and valid boundary cases before changing semantics.
   Hoisted allocas and defer accesses also still need a lexical lifetime policy.
3. Continue indirect/generic/embedded-origin and cleanup counterexamples under
   A13/A16. Borrowed-initial mutable bindings and raw/FFI boundaries still need
   broader review. These controls do not prove every package consumer safe.
4. Retain all A01–A17 requirements. Native platform/distribution checks, remote
   workflows, package/release inventory and independent crypto review remain
   open. Linux tests do not certify those requirements.

## Reproduction

- `NURL_TEST_JOBS=8 ./build.sh --refresh-bootstrap`
- `python3 tools/tests/test_string_argument_ownership.py` — 31 methods;
  emitted programs are instrumented, including independent C retention controls.
- `python3 tools/tests/test_compiler_cleanup.py` — seven methods.
- `./tools/memgate.sh` and `./tools/dcegate.sh` — normal build.
- `./build.sh --san --no-tests`, then `NURL_SAN=1 ./tools/nurl-lsp/build.sh`.
- `ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 LSAN_OPTIONS=use_stacks=0 python3 tools/tests/test_lsp_toolchain.py`
- `./tools/leakgate.sh` and `NURL_SAN_JOBS=8 ./compiler/tests/run_san_tests.sh`.
- `python3 tools/tests/test_panic_journal.py` — seven runtime controls.
- `python3 tools/tests/test_driver_paths.py` — two real split/path controls.
- Never rebuild shared compiler/runtime outputs while tests consume them; never
  overlap corpus runners using the same verdict directory.
- `python3 tools/gen_globals_map.py` after compiler edits; keep both bootstrap
  snapshots together. Preserve `vec_push_temp_owned`'s golden: `item3`, exit 0.

Ignored local evidence is under `build/v1-hardening/`. `consumer-nohelpers-*`
records the isolated candidate. `consumer-final-*` records the refreshed shared
build and gates. `NURL_TEST_TOOLCHAIN_DIR` selects an isolated binary directory
for the LSP tests; its default is the shared `build/` directory. Artifact names
alone do not prove correspondence to the current source.
