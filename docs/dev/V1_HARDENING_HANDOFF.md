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

Source arithmetic now guards integer zero division/remainder, signed MIN/-1,
dynamic invalid shifts and out-of-range/NaN/infinite float-to-integer casts
before LLVM undefined behavior or poison. Scalar and aggregate-field casts
share unsignedness, bounds and bool rejection. Fractional values that truncate
into range remain valid; IEEE floating arithmetic is unchanged.

Published checkpoints are `8d34f800` (JS audits), `b3975cdb` (return ownership),
`5e673886` (driver split paths) and `5b2a9b3a` (inferred consumer effects).
Local commit `3cf6974b` separates PowerShell startup from the compiler watchdog;
all 20 real POSIX/PowerShell controls pass. See the ledger for the exact bounds
and the limitation of the old remote failure log.

## Latest compiler verification

Both refreshed arithmetic bootstraps pass. Normal build: 75 seconds; corpus
2 m 48 s. Sanitized bootstrap: 85 seconds. Both 993-input corpora report
**974 PASS / 19 SKIP**, with zero compiler/link/runtime/timeout/sanitizer failures.
All seven arithmetic methods pass with both normal and instrumented compilers:
596 runtime cases across three modes, **1,788 executions plus two rejections**.
These use independent C inputs, O0/O2, ordinary and sanitized programs, split
output, `--no-borrowck`, all integer widths/signs, f32/f64, aggregate casts and
panic cleanup. All 31 ownership, seven compiler-cleanup and 20 LSP methods pass
on the final shared instrumented toolchain. All six compiler leak-gate sources
pass ordinary and split emission; sanitizer detection calibration also passes.
RSS is 36 MB (600 MB budget); DCE is 180 emitted / 12 reachable with identical
behavior. Source and bootstrap `.nu` are identical; generated facts are current.

Retained evidence is under ignored `build/v1-hardening/`: `arithmetic-before/`
records the old undefined/poison outcomes; `arithmetic-final-*` records final
builds, focused gates and separately copied normal/sanitized verdicts.
The ledger retains earlier ownership counterexamples and their failed candidates.

## Remote state and next work

1. PR #1107 at `5b2a9b3a` passes macOS ARM64 (including driver path controls),
   Windows, FreeBSD, sanitizer, required-tool fault injection, webdocs and all
   four JavaScript audit/build jobs. The runner watchdog change and arithmetic
   change still need publication and remote results. Keep the PR a draft.
2. The unikernel job fails because shared `packages/wasmbuilder/src/wasi_ir.nu`
   includes `nocapture nofree` attributes in parameter value types. A local
   regression reproduces the exact LLVM assembly failure. The working-tree
   fix parses balanced type/parameter syntax and strips attributes; complete
   focused leak/LLVM checks and real wasm compiler/swarm guest gates before
   publishing it. `nurlapi` imports this shared file.
3. The main Linux job is cancelled while apt installs MinGW after the other
   compiler gates. Fix the prerequisite/CI setup while retaining the cross-link
   gate; cancellation is not success. The pinned CI image lacks MinGW.
4. Continue A01's lexical alloca/defer lifetime policy and broader fuzz controls.
   Continue A13/A16 indirect/generic/embedded-origin and cleanup counterexamples;
   borrowed-initial mutable bindings and raw/FFI boundaries need broader review.
5. Retain every A01–A17 requirement. Package/release inventories, transactional
   installation, actual distribution checks and independent crypto review remain
   open. Current platform jobs do not certify their complete requirements.

## Reproduction

- `NURL_TEST_JOBS=8 ./build.sh --refresh-bootstrap`
- `python3 tools/tests/test_arithmetic_safety.py` — seven methods / three modes.
- `python3 tools/tests/test_string_argument_ownership.py` — 31 methods.
- `python3 tools/tests/test_compiler_cleanup.py` — seven methods / 366 rejection goldens.
- `./tools/memgate.sh` and `./tools/dcegate.sh` — normal build.
- `./build.sh --san --no-tests`, then `NURL_SAN=1 ./tools/nurl-lsp/build.sh`.
- `ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 LSAN_OPTIONS=use_stacks=0 python3 tools/tests/test_lsp_toolchain.py`
- `./tools/leakgate.sh` and `NURL_SAN_JOBS=8 ./compiler/tests/run_san_tests.sh`.
- `python3 tools/tests/test_driver_paths.py` — two real split/path controls.
- `NURL_TEST_PWSH=/absolute/path/to/pwsh python3 tools/tests/test_compiler_runners.py`
- Never rebuild shared compiler/runtime outputs while tests consume them; never
  overlap corpus runners using the same verdict directory.
- `python3 tools/gen_globals_map.py` after compiler edits; keep both bootstrap
  snapshots together. Preserve `vec_push_temp_owned`'s golden: `item3`, exit 0.
- Set `DEBUGINFOD_URLS=''` for isolated sanitizer probes to avoid symbol-server
  waits. Use bounded process execution and retain sanitizer errors.
