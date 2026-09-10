# v1.0 hardening evidence

The 2026-09-10 external audit is an investigation list, not an authority on
correctness. Each finding must be reproduced or checked against current source
before changing behavior. Passing a narrow check does not establish a broader
guarantee. This ledger retains the complete scope while changes are delivered
in reviewable groups. No item below certifies the whole language or ecosystem.

| Audit item | Evidence required before closure | Current disposition |
|---|---|---|
| A01: sanitizer coverage | Ordinary driver, bootstrap, split output and fuzz paths detect deliberate memory faults in generated code; clean controls, corpus and fuzz pass; UBSan/LLVM semantics documented | ASan emission implemented and calibrated; revealed HTTP/3 UAF and compiler leaks repaired; lexical stack-lifetime and arithmetic work remains open |
| A02: trustworthy compiler runners | Missing-main rejection fixtures run; crash/hang/worker fault controls fail closed; complete corpus verdict accounting | Verified in local normal/sanitized corpus and POSIX/PowerShell controls; native Windows execution remains CI evidence |
| A03: installed LSP | Separate installed project, unsaved edits, sibling/dependency imports, visible execution errors | Pending reproduction |
| A04: registry identity | Two local registries with equal package names; fetch, resolution, signing and lock identity preserved; errors never print success | Pending reproduction |
| A05: signed install smoke | Signed fixtures install after relocation with transitive dependencies; missing/wrong/tampered signatures reject; CI runs it | Pending reproduction |
| A06: JS dependencies | Fresh manager-native audits, reachability analysis, lockfile updates and builds/tests for all four trees; recurring checks | Pending fresh advisory evidence |
| A07: continuous package/service tests | Suite/prerequisite manifest, changed packages and reverse dependencies, scheduled coverage; registry/cloud and diagnostic gates in CI | Pending current workflow inventory |
| A08: documentation consistency | Grammar, spec, platform claims, generated facts and executable docs agree with implementation | Runner prerequisites, macOS/musl claims and stale leak comments corrected from source; remaining claims pending |
| A09: package development | Clean checkout and unpacked consumer tests, shared environment setup, explicit public import surfaces | Pending reproduction |
| A10: tree gates | Tracked formatting inventory, package-aware frontend coverage, recursive import checks with reported exclusions | Pending current scope inventory |
| A11: toolchain build integrity | Injected required-tool failures fail the build; stale binaries cannot substitute; logs and totals retained | Required tools now fail the build, use the canonical driver and remove stale outputs; isolated full-build controls pass locally and are wired into CI |
| A12: LSP temporary files | Secure portable per-session files, concurrent servers remain independent, all failure paths clean up | Pending reproduction; investigate with A03 |
| A13: safety contract | Default/strict/raw/FFI guarantees agree; witnesses and valid controls; opaque wrappers and container ownership audited | Pending implementation and contract review |
| A14: crypto/parser evidence | Instrumented fuzz controls and retained seeds; pinned ACVP/HTTP oracles; measured backend timing; explicit X.509 policy and independent crypto review | Pending; requires A01 and external validation for independent review |
| A15: release integrity | Mandatory target artifact gates, pinned tool downloads, installer integrity and state-preserving failure controls | Pending source review and isolated tests |
| A16: compiler architecture | Ownership/state boundaries, current global writer map, interacting-feature differential tests, diagnostic-site dispositions | Trait ordering work is merged; remaining acceptance is unverified |
| A17: ecosystem capabilities | All package public surfaces mapped to executable consumer/runtime/install evidence and prerequisites; device/platform results distinguished from CPU substitutes | Pending package inventory and execution matrix |

These statuses are independent: A01/A11 progress does not close the installed
LSP, registry, dependency, package, release or independent cryptographic review
work. A proposed audit remedy is not automatically the right language design.

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

## A01 implementation and findings

`--sanitize-address` marks definitions at the compiler's final indexed write
boundary. Ordinary and split emission share the boundary, including replicated
inline definitions, closure bodies and generated drop/dyn/SIMD functions.
It does not build another module-sized string. The driver, bootstrap stages,
sanitizer corpus and fuzz harnesses request the option; the metamorphic runner
no longer repairs LLVM text itself. The refreshed seed carries the attribute
so the first bootstrap binary can be instrumented too. Ordinary emitted IR
does not carry the attribute.

`tools/sanitizer_controls.py` runs deliberate heap OOB/UAF cases at O0/O2,
stack-use-after-return at O0, and valid counterparts. Failure means both a
nonzero exit and the expected ASan class, rather than any crash. It checks
debug/no-DCE/library/thunk output and executes linked split modules. Both fuzz
wrappers run its quick calibration before a campaign.

The first fully instrumented corpus reported a real HTTP/3 use-after-free:
`__h3_on_stream` freed a completed request stream, then read its kind in a
second cleanup condition. Both terminal predicates now precede one drop.
The existing `http3_client_server` regression detects the old code and passes
with the repair.

Structural seed 1 also exposed compiler leaks. The original compiler leaked
143 bytes in 22 allocations compiling `enum_tree_drop.nu`, and 6 bytes in
three allocations compiling `nested_field_store.nu`. The drop generator's
register counters are now typed `inout i` locals instead of allocated cells;
drop-name branches and lexer lookahead have uniform owned-string results.
The lexer uses the owned string API rather than the manually managed raw
`nurl_strdup` API, removing a name-specific ownership registration. Both
existing fixtures now run in the default compiler leak gate, alongside the
self-compile, through ordinary and instrumented split emission.

Local evidence on Linux x86_64, clang 18.1.3:

- Fully instrumented bootstrap reaches its byte-identical fixed point and
  builds both required tools (68 s).
- Final normal `./build.sh` passes its fixed point and corpus (40 s build,
  140 s tests). Normal and instrumented corpora each account for 980 inputs:
  961 PASS, 19 SKIP, no missing verdicts or failures.
- All detection controls pass; valid ordinary/split controls remain clean.
- Expanded compiler leak gate: zero leaks for all three inputs, both modes.
- Normal IR is byte-identical before/after for six controls covering traits,
  user drops, SIMD dispatch, recursive enum drops, nested stores and closures.
- Self-compile peak RSS remains 26 MB; DCE retains 12 of 180 functions and
  preserves behavior. The normal package-manager binary still depends only
  on libc on this host.
- Structural seeds 1–50: O0/O2/oracle agree; 50 ASan/LSan runs, zero findings.
- Parser seed 1: 2,000 mutations across JSON/YAML/XML/TOML/X.509/CBOR/MessagePack,
  zero findings; the temporary harness directory is removed after completion.

Remaining A01 work is explicit. NURL allocas are currently hoisted to function
entry and deferred cleanup may use them after their lexical block; there are
no `llvm.lifetime` boundaries. A correct use-after-scope policy must account
for those real lifetimes and deferred accesses, rather than append blanket
lifetime ends. An independent O0 probe assigns a closure over a mutable block
local to an outer binding, then invokes it after that block: it prints 42 and
exits 0 without an ASan report (`build/v1-hardening/stack-scope*`). This is not
counted as a passing detection control. NURL also emits no source-level UBSan checks. Dynamic shift
counts and float-to-integer ranges retain LLVM poison cases; division guards
zero but not signed overflow. The spec's contradictory low-six-bit masking
claim is corrected from the actual shift emitter. See
[coverage boundaries](../BUILDING.md#sanitizer-coverage).

## A11 implementation and evidence

Both required tool builders now use `nurl.sh`, which keeps their runtime,
sanitizer and link configuration consistent with other programs. Before this
repair a sanitized bootstrap could silently fail both tool links while
printing overall success. The full build now requires both tools and the
formatter round-trip check. A failed tool rebuild removes its old executable;
the complete build retains its log, commands and clang version.

`python3 tools/tests/test_build_failures.py` copies actual working sources into
an isolated checkout without ignored binaries, injects an invalid formatter
or package-manager source, plants a stale executable and runs the complete
build. Both cases return failure attributed to the required tool, remove the
stale binary and retain a versioned build log. The CI job runs these controls
and uploads their logs. Local evidence is in
`build/v1-hardening/required-tool-faults-final2.log` and
`build/build-failure-controls/`; CI execution remains separate evidence.
