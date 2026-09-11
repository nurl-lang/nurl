# v1 hardening continuation

Work on branch `codex/v1-validation-hardening`. The pull request is a draft;
do not merge it or declare v1 hardening complete from the focused results.
The scope and evidence requirements remain in [V1_HARDENING.md](V1_HARDENING.md).
The external LLM-written audit is a source of hypotheses, not an authority.

## What changed in this checkpoint

Compiler ownership uses stable binding nodes, conditional call dependencies,
separate root-address and embedded-reference summaries, and a finite worklist.
It preserves origins through casts, arithmetic, locals, assignments, loop
backedges and forward calls. Lifted closures have separate parameter domains.
Pointer/slice stores and raw-word stores retain their input address origins.
Named and positional string argument temporaries share the final drop decision;
forward result arguments capture their dynamic ownership proof. The runtime
panic journal has indexed removal and stable sequence marks, and the compiler
uses normal recovery plus compilation-owned cleanup for lexers and symbol tables.

The branch also includes nine earlier commits covering sanitizer/test-runner
integrity, installed LSP context, formatter/stream cleanup, trusted registry
identity, conflict-directed dependency resolution and verified publication.

## Verified at this checkpoint

- Full refreshed normal bootstrap and corpus: **974 pass, 19 skip, zero fail**.
  `vec_push_temp_owned` uses its unchanged golden (`item3`, exit 0).
- All **17** ownership test methods pass both with a normal compiler and with
  the isolated ASan/UBSan compiler; the emitted programs use ASan/UBSan/LSan.
- The **7** standalone runtime journal methods pass.
- The instrumented compiler emits its complete current source with no sanitizer
  findings or leaks (`detect_leaks=1`, `use_stacks=0`).
- Normal RSS gate: **34 MB** (600 MB budget); DCE: **180 emitted / 12 reachable**,
  identical behavior. These do not certify the full v1 performance objective.
- Compiler and bootstrap `.nu` sources are byte-identical.

## Known unfinished work

1. Fix two diagnostic leaks without helper reordering, new whitelists, temporary
   binding workarounds or sanitizer suppression. With an instrumented compiler,
   `python3 tools/tests/test_compiler_cleanup.py` still finds 4 bytes in
   `diag_bad_type_token` and 2 bytes in `diag_closure_arity_few`. Other methods
   pass. Inspect direct forward-return proof propagation (`tok_here` to
   `__tok_label`) and guarded forward-result bindings abandoned by panic.
2. Rerun the wider rejected-source leak sweep. The historic 44 failures are not
   a fresh count; two of the four formerly pinned failures have been fixed.
3. Complete the full sanitized bootstrap, corpus and multi-mode leak gate.
   The focused ASan/UBSan compiler successfully emits its own source without
   leaks, but that does not replace all modes of `tools/leakgate.sh`.
4. Audit indirect/generic dispatch, embedded origins and all dynamic return
   proof exits. The old helper whitelist in `mem_consumer_copy_safe` and the
   conservative guarded-binding protocol remain; do not expand the whitelist.
   A dynamic proof must be captured before another generated call can clobber
   `@__nurl_ret_owned`, and an escaping owner must not be journalled for an
   extent that may end before the owner does.
5. Continue the remaining v1 audit requirements in the evidence ledger.

## Reproduction and working discipline

- Normal build: `./build.sh` (refresh snapshots explicitly after compiler edits).
- Address/lifetime controls: `python3 tools/tests/test_string_argument_ownership.py`.
  The final focused suite has 17 methods and includes the vector temporary
  regression, large parameter indices, long return chains and closure isolation.
- Runtime controls: `python3 tools/tests/test_panic_journal.py` (7 methods).
- Instrumented build: `./build.sh --san --no-tests`, then the cleanup/address
  controls, `./tools/leakgate.sh` and `compiler/tests/run_san_tests.sh`.
- Normal memory and DCE gates: `./tools/memgate.sh`, `./tools/dcegate.sh`.
- Never rebuild shared compiler/runtime artifacts while test runners consume
  them; never overlap corpus runners sharing `build/tests/.verdicts`.
- Always record failing controls as failures. Preserve existing golden output
  for `vec_push_temp_owned`: `item3`, exit 0.
- Keep compiler source and both bootstrap snapshots together and update the
  generated global-state map with `python3 tools/gen_globals_map.py`.

Local isolated artifacts and logs live under `build/v1-hardening/` (ignored by
Git). `nurlc-origin-stores` is the normal candidate and
`nurlc-origin-stores-san` is the instrumented candidate. Rebuild them if source
has changed; these names alone do not prove they match the checkout.
