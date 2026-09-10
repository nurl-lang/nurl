# v1.0 hardening evidence

The 2026-09-10 external audit is an investigation list, not an authority on
correctness. Each finding must be reproduced or checked against current source
before changing behavior. Passing a narrow check does not establish a broader
guarantee. This ledger retains the complete scope while changes are delivered
in reviewable groups. No item below certifies the whole language or ecosystem.

| Audit item | Evidence required before closure | Current disposition |
|---|---|---|
| A01: sanitizer coverage | Ordinary driver, bootstrap, split output and fuzz paths detect deliberate memory faults in generated code; clean controls, corpus and fuzz pass; UBSan/LLVM semantics documented | Reproduced independently at current source; codegen repair pending |
| A02: trustworthy compiler runners | Missing-main rejection fixtures run; crash/hang/worker fault controls fail closed; complete corpus verdict accounting | Verified in local normal/sanitized corpus and POSIX/PowerShell controls; native Windows execution remains CI evidence |
| A03: installed LSP | Separate installed project, unsaved edits, sibling/dependency imports, visible execution errors | Pending reproduction |
| A04: registry identity | Two local registries with equal package names; fetch, resolution, signing and lock identity preserved; errors never print success | Pending reproduction |
| A05: signed install smoke | Signed fixtures install after relocation with transitive dependencies; missing/wrong/tampered signatures reject; CI runs it | Pending reproduction |
| A06: JS dependencies | Fresh manager-native audits, reachability analysis, lockfile updates and builds/tests for all four trees; recurring checks | Pending fresh advisory evidence |
| A07: continuous package/service tests | Suite/prerequisite manifest, changed packages and reverse dependencies, scheduled coverage; registry/cloud and diagnostic gates in CI | Pending current workflow inventory |
| A08: documentation consistency | Grammar, spec, platform claims, generated facts and executable docs agree with implementation | Runner prerequisites, macOS/musl claims and stale leak comments corrected from source; remaining claims pending |
| A09: package development | Clean checkout and unpacked consumer tests, shared environment setup, explicit public import surfaces | Pending reproduction |
| A10: tree gates | Tracked formatting inventory, package-aware frontend coverage, recursive import checks with reported exclusions | Pending current scope inventory |
| A11: toolchain build integrity | Injected required-tool failures fail the build; stale binaries cannot substitute; logs and totals retained | Pending reproduction |
| A12: LSP temporary files | Secure portable per-session files, concurrent servers remain independent, all failure paths clean up | Pending reproduction; investigate with A03 |
| A13: safety contract | Default/strict/raw/FFI guarantees agree; witnesses and valid controls; opaque wrappers and container ownership audited | Pending implementation and contract review |
| A14: crypto/parser evidence | Instrumented fuzz controls and retained seeds; pinned ACVP/HTTP oracles; measured backend timing; explicit X.509 policy and independent crypto review | Pending; requires A01 and external validation for independent review |
| A15: release integrity | Mandatory target artifact gates, pinned tool downloads, installer integrity and state-preserving failure controls | Pending source review and isolated tests |
| A16: compiler architecture | Ownership/state boundaries, current global writer map, interacting-feature differential tests, diagnostic-site dispositions | Trait ordering work is merged; remaining acceptance is unverified |
| A17: ecosystem capabilities | All package public surfaces mapped to executable consumer/runtime/install evidence and prerequisites; device/platform results distinguished from CPU substitutes | Pending package inventory and execution matrix |

## A02 implementation and evidence

The current source reproduced both missing-main skips and sanitizer rejection
acceptance. Before repair, fault injection against copies of the real runners
produced 28 failed assertions across six test methods, including unbounded
compiler hangs. The same controls exercise corrected runners; they do not
replace tests of the actual compiler.

Changes share compiler flags, a compiler watchdog and verdict validation between
POSIX runners. Helpers declare `// fixture: module`; absence of `main` is never
itself a skip reason. Only compiler exit 1 is a rejection. Golden update mode
cannot bless a compiler crash or inverted acceptance. Sanitizer execution also
requires the expected runtime exit. PowerShell follows the same contract with
structured verdicts and process-tree timeouts.

Reproducible controls:

```sh
python3 tools/tests/test_compiler_runners.py
# Also exercise the PowerShell runner on a POSIX host with pwsh installed:
NURL_TEST_PWSH="$(command -v pwsh)" python3 tools/tests/test_compiler_runners.py
NURL_TEST_JOBS=8 ./build.sh
./build.sh --san --no-tests
NURL_SAN_JOBS=8 ./compiler/tests/run_san_tests.sh
```

Local results after the repair:

- Full `./build.sh`: bootstrap fixed point passed; 46 s build, 2 m 23 s tests.
- Normal corpus: 961 PASS, 19 SKIP, 0 FAIL/MISSING/ORPHAN (980 records).
- Sanitized corpus: 961 PASS, 19 SKIP; zero sanitizer, compiler, linker,
  runtime or timeout failures (980 records).
- All seven formerly skipped rejection fixtures are PASS in both corpora;
  existing goldens are unchanged.
- Fault-injection suite: 18 test methods pass, including POSIX and PowerShell
  crash/hang/acceptance controls, compiler flags, fixture intent, update-mode
  integrity, runtime exits and verdict-protocol corruption.
- Modified NURL fixtures pass the formatter check; shell syntax and diff
  whitespace checks pass.

Retained local evidence is under ignored `build/v1-hardening/`. The sanitizer
corpus at this stage validates runner behavior; A01 remains open, so a clean
result must not be represented as complete generated-code memory instrumentation.
PowerShell controls executed on Linux do not establish Windows native runtime
behavior; the Windows corpus remains a separate platform check.

## A01 independent reproduction

Using current `NURL_SAN=1 ./nurl.sh` to compile an eight-byte allocation with a
write at offset 16, then running the resulting binary with
`ASAN_OPTIONS=detect_leaks=0:symbolize=0`, prints `42` and exits 0. The emitted
IR contains two definitions without `sanitize_address`. Adding that attribute
only to those definitions and linking at the same optimization level against
the same sanitized runtime produces exit 1 and `heap-buffer-overflow`.
This contrast establishes the coverage defect on this host; the temporary IR
edit is a diagnostic control, not the production fix. Logs and both IR variants
are retained under `build/v1-hardening/asan-*` and `sanitizer_probe*`.
