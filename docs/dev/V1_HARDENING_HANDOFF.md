# v1 hardening continuation

Work on branch `codex/v1-validation-hardening`. The pull request is a draft;
do not merge it or declare v1 hardening complete from the focused results.
The scope and evidence requirements remain in [V1_HARDENING.md](V1_HARDENING.md).
The external LLM-written audit is a source of hypotheses, not an authority.

## What changed in this checkpoint

The compiler uses a stable address graph for guarded binding lifetimes as well
as argument retention. Return proofs survive forward/indirect calls, bound
returns and cleanup/defer calls, and the runtime proof channel is thread-local.
Original result proofs and selected cleanup owners have separate slots. Return
sites transfer ownership without disabling cleanup on other paths; transferred
owners leave the callee's panic journal after cleanup. The scoped guard-read
counters are gone, and the existing consumer whitelist was not expanded.

The two previously open diagnostic leaks are fixed. The default cleanup suite
now checks all 366 rejected-source goldens with the real fixture flags. A new
nested-store witness caught a guarded binding being freed too soon, and a
failed intermediate graph candidate exposed conditional-return leaks; both
failures are retained as evidence and repaired at their general cause.

All four JavaScript dependency trees have refreshed locks and zero-finding
manager audits after clean installs. Registry/cloud/extension checks and the
webdocs production build pass. A weekly/PR dependency workflow was added;
remote execution is separate evidence.

## Verified at this checkpoint

- Full refreshed normal bootstrap and corpus: **974 pass, 19 skip, zero fail**.
  `vec_push_temp_owned` keeps its unchanged golden (`item3`, exit 0).
- All **25** ownership test methods pass with normal and isolated ASan/UBSan
  compilers; emitted programs use ASan/UBSan/LSan.
- All **6** compiler-cleanup methods pass, including **366** rejection fixtures.
- All **7** standalone runtime journal methods pass.
- The instrumented candidate emits its complete source with no sanitizer
  findings or leaks (`detect_leaks=1`, `use_stacks=0`).
- Normal RSS gate: **35 MB** (600 MB budget). DCE: **180 emitted / 12 reachable**,
  identical behavior. These do not certify the full v1 performance objective.
- Compiler and bootstrap `.nu` sources are byte-identical.
- Final shared sanitized bootstrap and corpus: **974 pass, 19 skip**, zero
  sanitizer/compiler/link/runtime/time-out failures. All six compiler leak-gate
  sources pass ordinary and instrumented split emission (12 modes total).
- Running all 20 installed LSP controls with leak detection reveals **5 failures**
  in service message construction. These remain open and are not suppressed
  in the retained experiment (`guard-final-lsp.log`).

## Known unfinished work

1. Fix the five LSP message-construction leaks found with leak detection enabled.
   Stack traces point to `__compile_diagnostics` / `__make_error` temporary
   arguments consumed by functions returning Json. Inspect the remaining
   scalar/fresh-result restriction in `mem_consumer_arg_drop_safe`, including
   embedded ownership and unknown-call controls; do not add a helper whitelist
   or work around the compiler by introducing temporary message bindings.
2. Continue indirect/generic/embedded-origin and cleanup-path counterexamples.
   Unknown dispatch, captures and stores retain owners conservatively. The
   temporary-consumer whitelist still exists. These focused controls do not
   prove all dynamic lifetime cases or all package consumers safe.
3. Continue A01's lexical stack lifetime and source-level arithmetic/LLVM poison
   work, followed by the remaining requirements in the evidence ledger.
4. A06 has dated local audit/build evidence and recurring checks, but remote CI
   execution is pending. The other platform, release, ecosystem and independent
   crypto-review requirements remain open; do not infer closure from Linux tests.

## Reproduction and working discipline

- Normal build: `./build.sh` (refresh snapshots explicitly after compiler edits).
- Address/lifetime controls: `python3 tools/tests/test_string_argument_ownership.py`
  (25 methods; emits and runs instrumented programs).
- Diagnostic cleanup: `python3 tools/tests/test_compiler_cleanup.py`
  (6 methods, including the complete current rejection-golden sweep).
- Runtime controls: `python3 tools/tests/test_panic_journal.py` (7 methods).
- Instrumented build: `./build.sh --san --no-tests`, then the cleanup/address
  controls, `./tools/leakgate.sh` and `compiler/tests/run_san_tests.sh`.
- Normal memory and DCE gates: `./tools/memgate.sh`, `./tools/dcegate.sh`.
- Never rebuild shared compiler/runtime artifacts while test runners consume
  them; never overlap corpus runners sharing `build/tests/.verdicts`.
- Record failing controls as failures. Preserve existing golden output for
  `vec_push_temp_owned`: `item3`, exit 0.
- Keep compiler source and both bootstrap snapshots together and update the
  generated global-state map with `python3 tools/gen_globals_map.py`.

Local isolated artifacts and logs live under ignored `build/v1-hardening/`.
`nurlc-guard2` and `nurlc-guard2-san` are the focused candidates;
`guard2-*.log` records their checks. `guard-final-*.log` records the final
shared bootstrap/gates. `guard-graph-cleanup.log` is a failed intermediate
candidate, not a passing result. Rebuild candidates if source has changed;
artifact names alone do not prove they match the checkout.
