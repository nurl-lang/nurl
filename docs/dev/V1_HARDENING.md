# v1.0 hardening evidence

The 2026-09-10 external audit is an investigation list, not an authority on
correctness. Each finding must be reproduced or checked against current source
before changing behavior. Passing a narrow check does not establish a broader
guarantee. This ledger retains the complete scope while changes are delivered
in reviewable groups. No item below certifies the whole language or ecosystem.

| Audit item | Evidence required before closure | Current disposition |
|---|---|---|
| A01: sanitizer coverage | Ordinary driver, bootstrap, split output and fuzz paths detect deliberate memory faults in generated code; clean controls, corpus and fuzz pass; UBSan/LLVM semantics documented | ASan emission implemented and calibrated; revealed HTTP/3 UAF and compiler leaks repaired; lexical stack-lifetime, rejected-compilation cleanup and arithmetic work remains open |
| A02: trustworthy compiler runners | Missing-main rejection fixtures run; crash/hang/worker fault controls fail closed; complete corpus verdict accounting | Verified in local normal/sanitized corpus and POSIX/PowerShell controls; native Windows execution remains CI evidence |
| A03: installed LSP | Separate installed project, unsaved edits, sibling/dependency imports, visible execution errors | Independently reproduced; repaired and verified with relocated binaries and 20 normal/ASan protocol/compiler controls on Linux; native Windows and actual distribution installation remain unverified |
| A04: registry identity | Two local registries with equal package names; fetch, resolution, signing and lock identity preserved; errors never print success | Origin/key/index/archive/lock binding repaired and locally tested; flat-layout coexistence, backtracking and transactional/frozen installation remain open |
| A05: signed install smoke | Signed fixtures install after relocation with transitive dependencies; missing/wrong/tampered signatures reject; CI runs it | Unsigned/stale smoke independently reproduced; signed five-program relocation smoke and CLI negative controls pass locally, wired into CI; remote run pending |
| A06: JS dependencies | Fresh manager-native audits, reachability analysis, lockfile updates and builds/tests for all four trees; recurring checks | Pending fresh advisory evidence |
| A07: continuous package/service tests | Suite/prerequisite manifest, changed packages and reverse dependencies, scheduled coverage; registry/cloud and diagnostic gates in CI | Pending current workflow inventory |
| A08: documentation consistency | Grammar, spec, platform claims, generated facts and executable docs agree with implementation | Runner prerequisites, macOS/musl claims and stale leak comments corrected from source; remaining claims pending |
| A09: package development | Clean checkout and unpacked consumer tests, shared environment setup, explicit public import surfaces | Pending reproduction |
| A10: tree gates | Tracked formatting inventory, package-aware frontend coverage, recursive import checks with reported exclusions | Pending current scope inventory |
| A11: toolchain build integrity | Injected required-tool failures fail the build; stale binaries cannot substitute; logs and totals retained | Required tools now fail the build, use the canonical driver and remove stale outputs; isolated full-build controls pass locally and are wired into CI |
| A12: LSP temporary files | Concurrent servers remain independent and no shared source files can be overwritten or leaked on errors | Source temporary files eliminated through compiler stdin snapshots; concurrent-server and missing-tool controls pass |
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

## A03 / A12: document snapshots and installed tool discovery

The old server was rebuilt and driven with identical JSON-RPC messages from
both the checkout and a separate project. An undefined identifier produced an
error in the checkout and an empty diagnostic array outside it. Its hardcoded
`build/nurlc` and `build/nurlfmt` paths, shared `/tmp/nurl-lsp-<counter>.nu`
files and early error return independently confirmed the audit's report.
The audit's suggested secure temporary directory was not adopted: the compiler
now accepts stdin plus an explicit logical source path, eliminating those
source files and retaining the document's import identity.

`compiler_read_source` serves the same owned snapshot to source replays and
borrow diagnostics. `--check` runs semantic analysis and skips the final IR
copy/index/emission. The checked runtime reader preserves source newlines,
handles nonseekable input and read errors, and uses only opened regular-file
sizes as allocation hints. A sanitized directory-read control caught a bogus
LONG_MAX size from directory SEEK_END; switching the hint to `fstat` repaired
that cause instead of imposing an arbitrary file-size cap.

The LSP discovers configured, environment, sibling or PATH tools before changing
to the workspace root. Compiler capability/execution failures and formatting
failures are visible. The VS Code launcher retains the resolved executable path
and passes tool settings. Open-buffer indexing, importer-relative/dependency/
stdlib lookup, percent-escaped definition URIs, diagnostic UTF-16 ranges,
columnless borrow errors and imported related locations were also exercised.

Local controls (build fresh binaries first):

```sh
./tools/nurl-lsp/build.sh
python3 tools/tests/test_lsp_toolchain.py
python3 tools/tests/test_source_io.py
node tools/tests/test_vscode_launcher.cjs
bash compiler/tests/lsp_rename_smoke.sh
./build.sh --san --no-tests
NURL_SAN=1 ./tools/nurl-lsp/build.sh
ASAN_OPTIONS=detect_leaks=0:halt_on_error=1 python3 tools/tests/test_lsp_toolchain.py
ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 python3 tools/tests/test_lsp_toolchain.py ToolchainTest.test_check_self_compile_from_stdin
```

The protocol suite has 20 cases, using copied binaries and standard-library
sources in a relocated prefix, a separate project, and a restricted PATH.
It exercises unsaved/nonexistent sources, source-vs-disk IR identity, no-output
checking, invalid CLI arguments, CRLF and capacity boundaries, sibling and
project imports, tool selection/failure, imported error/definition locations,
UTF-16 ranges, PATH launch, concurrent servers and stdin self-compilation.
Four C reader tests run under ASan/UBSan with leak detection. The editor launcher
has separate Node controls, including simulated Windows paths; these do not
establish native Windows runtime behavior. The tests are wired into CI, whose
remote result is not asserted by local evidence.

The normal full bootstrap/corpus passed locally (41 s build, 2 m 09 s corpus),
and the final instrumented bootstrap passed (71 s). All 20 protocol/compiler
controls passed with ASan, and stdin `--check` self-compilation separately passed
LSan with zero leaks. The ordinary self-compile/drop/nested-store leak gate
also passed both output modes. C read failures, exact capacities, named pipes
and procfs reads passed their sanitizer controls.

**New open evidence:** compiling an undefined identifier with the instrumented
compiler and `ASAN_OPTIONS=symbolize=0:detect_leaks=1` reports 249 bytes in 26
allocations before process exit. A same-file comparison with the saved pre-change sanitized compiler also
reproduced rejection leaks (366 bytes/28 allocations before, 332/27 after,
298/26 through stdin for that longer path). This predates the stdin change.
Normal error exits and panic recovery need ownership cleanup; the general protocol suite therefore measures memory
accesses, while the successful stdin self-compile is a separate zero-leak gate.
This is not a claim that compiler rejection paths or the long-lived LSP are
leak-free. The declaration index's invalidation/name resolution and the
synchronous subprocess API's missing timeout also remain separate follow-up
work. A03/A12 progress does not certify all editor features or all platforms.

An instrumented `nurlfmt --check tools/nurl-lsp/main.nu` additionally reported
721,951 bytes in 13,324 allocations at exit. Formatter ownership cleanup was
open at this point; the follow-up below addresses it. Compiler rejection cleanup
remains open. The initial report appeared to hang
because llvm-symbolizer attempted remote debuginfod lookups; resolving the same
local address with `DEBUGINFOD_URLS=` returned immediately. The new tests disable
optional remote debug downloads while retaining local symbolization; they do
not suppress sanitizer findings.

Final confirmation for this change set: normal bootstrap/corpus passed again
(42 s build, 2 m 08 s corpus); both normal and sanitized corpora report 980
records, 961 PASS and 19 SKIP with no failures. The final server passed all 20
controls in both normal and ASan builds, plus the rename smoke. Self-compile
peak RSS was 26 MB and the DCE gate passed. The remaining items above stay open.

## Formatter ownership and shared stream reads

The formatter's leak comment was an incorrect diagnosis, not a design
constraint. A private control that re-enabled the old `tokens_free` crashed
under ASan even on empty input: its EOF token points at a static empty literal.
Skipping that sentinel released all real token slices without a double free.
Remaining leaks came from the input String and manually owned argument copies;
the CLI now adopts path buffers, frees flag buffers and releases every String
and path vector. The reusable `format.nu` entry point frees its token vector
on each invocation. No compiler-wide ownership exception was added.

Independent controls also found that `--check --stdin` emitted source and
ignored the check, a directory read could appear to be valid empty input, and
an embedded NUL could discard the source suffix. These now fail or validate
according to the documented CLI contract, before any in-place write.

Rather than special-case those inputs in the formatter, library text and byte
reads share `read_to_end`: the opened regular-file size is only a hint, short
positive reads remain data, zero means EOF and negative results mean failure.
The runtime stdio bridge retries EINTR without losing an already-read prefix;
other errors cannot become successful partial reads. Text adopts the Vec's
terminated buffer without copying and retains its byte length. The previous
mmap/seek/reopen fallbacks were removed. Stdin uses the same FILE buffer as
`read_line`, preventing loss of prefetched body bytes; convenience readers
panic on I/O failure and `read_stdin` exposes a recoverable Result. Chunk reads
release their allocation on error. The nolibc twin supplies `clearerr` too.

Focused controls:

```sh
python3 tools/tests/test_formatter.py
NURL_SAN=1 NURLFMT="$PWD/build/v1-hardening/nurlfmt-cleanup-san" python3 tools/tests/test_formatter.py
python3 tools/tests/test_source_io.py
python3 tools/tests/test_stream_io.py
```

The formatter suite covers every CLI mode, unchanged-file writes, multiple
files, read/write errors, invalid options, NUL input, large sources and 1,000
calls in one process. Runtime fault injection makes `fread` return a prefix
then EINTR or EIO, including the source reader's capacity lookahead. Library
controls cover short reads, invalid reader counts, all capacity boundaries,
embedded NULs, line-header/body mixing, named pipes, procfs and errors. They
assert clean sanitizer output even for expected nonzero exits; no leak
suppression is used. These are local Linux results, not native Windows proof.
Run the compiler-dependent suites after bootstrap finishes: building at the
same time removes `build/nurlc`, allowing the driver to find an older installed
compiler. The probe's instrumentation assertion correctly rejected that run.

A local five-sample, alternating-order comparison against the previous text
reader measured 10,000 reads of 4 KiB at median 95 ms before / 56 ms after.
Twenty reads of 32 MiB measured 427 ms / 345 ms, with peak process RSS 66,896 /
34,264 KiB. Data was page-cache resident; this is evidence on this host, not a
cross-platform throughput claim. Inputs, benchmark programs and samples are
retained in `build/v1-hardening/read-benchmark/`.

**Separate open evidence:** `( read_file_bytes ( nurl_argv 1 ) )` leaks the
anonymous owned argument even when the returned Vec is released. The compiler
conservatively retains argument temporaries for aggregate-returning consumers
without a proven ownership summary. A minimized ASan witness is retained in
`build/v1-hardening/aggregate-argument-leak/`. Named bindings in the stream
probe make its own ownership explicit; they do not close this compiler gap.
General temporary/sink/return ownership remains part of A01/A13, alongside
rejected-compilation cleanup. Formatter success is not whole-toolchain closure.

Final validation for the formatter/stream change: normal bootstrap and corpus
passed (42 s build, 2 m 21 s corpus); the sanitized bootstrap passed in 68 s.
Both corpora have 980 records, 961 PASS and 19 SKIP, with zero failures or
timeouts. All 11 formatter controls pass in normal and fully instrumented
builds with leak detection enabled. Five runtime source-reader controls and
six NURL stream controls pass under ASan/UBSan/LSan. All 20 LSP controls pass
in both builds; successful stdin self-compilation and all six compiler leak
gate cases pass with zero leaks. Modified formatter/library sources pass
idempotence and IR-equivalence checks (the tokenizer helper retains the gate's
existing standalone-IR exclusion). The nolibc symbol gate covers all 69
required symbols, and the builtin documentation gate covers all 119 entries.
The results do not close the separately listed ownership, platform or registry
issues. Per-suite logs and complete corpus verdicts are under
`build/v1-hardening/formatter-*` and `build/v1-hardening/stream-*`.

## A04 independent reproduction

A new loopback HTTP fixture gives the project default registry `/a/` and its
`foo` dependency an explicit `/b/` registry. The current CLI requests only
`/a/index/foo.json`, exits 1 with `ResolveNotFound`, and still prints
`identity-probe 0.1.0: dependencies installed`. This reproduces both claims
without relying on the audit's output. The fixture serves a package index at
`/b/index/foo.json`; no archive is installed. Source inspection also confirms
that the resolver's fetch callback accepts only a name, while constraint and
index-cache lookup keys omit the registry. The complete identity/signing/lock
repair remains open. Script and captured requests/output are retained as
`build/v1-hardening/registry-identity-probe.py` and
`build/v1-hardening/registry-identity-independent.json`.


## A04/A05 registry identity and signed installation

The initial 12-method signed CLI fixture produced 16 assertion failures against
`e08f622b` and passed after repair. It serves two independent registries under
one ephemeral localhost listener, uses independent deterministic test keys,
records every requested path, and uses OpenSSL to sign archives independently
of NURL's verifier. The expanded suite also checks existing package/lock
preservation, malformed locks, installed-version drift and missing checksums.
The initial 17-method suite passes in ordinary and instrumented CLI builds;
final coverage below includes additional malformed-input controls. These
controls do not validate the cryptographic primitive itself (A14 remains open).

The resolver now keys constraints, selected versions and its index cache by
normalized registry URL plus name. Its fetch callback receives both fields;
transitive index dependencies inherit the parent origin. An index must identify
the requested package. Locks carry that origin through downloads and key lookup.
The standalone serializer sorts borrowed record pointers by complete identity,
leaving callers' records intact with one word of sorting storage per package;
shared TOML quoting replaces the incorrect assumption that paths cannot contain
quotes or backslashes. `lock` retains prior registry pins and refuses missing/renamed registry
packages or version drift, while allowing local development versions to change.
Both CLI and library now use the same typed lock serializer. Failed resolution/authentication does not replace the prior lock or print
project installation success.

`registry_trust` loads one user-owned URL→key map per resolved installation
batch. No registry response or downloaded manifest can establish a key. The
legacy single-key environment override is bound only to the selected default
registry. Unknown origins, malformed config and conflicting normalized pins
fail before archive downloads. SHA-256, signature, root manifest name/version,
duplicate manifests and archive member safety are checked before extraction.
The parsed archive is reused for validation and extraction instead of parsed
and copied twice.

The previous ecosystem smoke independently failed: it supplied no signatures,
looked for obsolete `Installed <name>` text, ignored installer exit codes and
hardcoded md2html 0.1.1 despite the actual manifest being 0.1.2. It now derives
versions/dependencies from manifests, signs every fixture archive, configures
the relocated toolchain's own trust file, uses a private ephemeral port with a
readiness check, and fails on command exits. Its five installed programs (`nq`,
`md2html`, `chart`, `iforest`, and synthetic `mdcat`) must execute correctly;
`mdcat` exercises transitive registry resolution and compilation. It passes
locally and both suites are wired into CI. No remote CI result is claimed.

Reproduction commands:

```sh
python3 tools/tests/test_registry_identity.py
./tools/nurlpkg/test-install-tool.sh
./compiler/tests/run_tests.sh resolver_registry registry_trust
NURL_SAN=1 ./nurl.sh compiler/tests/registry_trust.nu build/registry-trust-leaks
ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 ./build/registry-trust-leaks
```

The pure resolver and trust/lock controls run with leak detection enabled and
pass. CLI controls disable leak detection because existing package-manager
ownership paths are not yet leak-clean; ASan/UBSan errors still fail each test.
A capturing comparator passed through `sort_by` also exposed the compiler's
conservative callback-escape analysis: the environment leaks because forwarding
through recursive generic helpers is not proved to borrow it. The serializer
needs no captured context when sorting record pointers, but that independent
compiler limitation remains A01/A13 work, not a claimed compiler fix.

**Remaining scope:** the resolver can represent equal names from different
registries, but the compiler's global imports and the CLI's flat `deps/<name>`
layout do not yet support their coexistence. The CLI detects and refuses this
collision before downloading either archive; this is an explicit limitation,
not A04 closure. Greedy resolution still lacks backtracking; exceeding the
convergence bound now errors rather than returning an unchecked lock. Lock
shape/version validation, typed transport failures, frozen installation, package-scoped import/symbol
identity, mixed local/registry graphs, exclusive staging, existing symlink
protection and atomic publication of the dependency tree remain open A04/A09/A15
work. Archive preflight does not make filesystem I/O failure transactional.
The NURL registry service's own publish/install test still has separate unsigned
fixtures and requires its own signing-path investigation under A07/A17.


Additional boundary controls reproduced seven accepted invalid inputs: decoded
NUL in the index name, version, checksum, dependency name or requirement, plus
raw NUL after an otherwise valid HTTP index or trust-config file. The original
`__ridx_str` projected JSON through a C string and silently discarded the suffix.
Index parsing now validates field types and complete strings before projection;
HTTP fetches preserve the actual body length, and resolver/config readers reject
embedded NUL before handing a source to a C-string parser. Unknown JSON fields
remain allowed. The negative fixture also covers incorrectly typed version,
checksum, yanked and dependency fields. Missing checksums now fail as a bad
index before an archive download. All 19 CLI controls pass in the updated
instrumented build; the seven pre-fix failures are retained in
`build/v1-hardening/registry-nul-before.log`.

The registry service's existing socket-free wire suite was also compiled and
executed with ASan/UBSan: all 55 checks passed, covering publish/read/yank/auth
operations with the shared name validator. This does not establish that its
separate unsigned network install fixture works, nor that a live deployment is
configured correctly. Native Windows archive-path semantics and existing
filesystem symlinks still require dedicated A15 validation.


Final validation for this change on Linux x86_64 (clang 18): the normal
bootstrap passed in 41 s and its corpus in 2 m 21 s; the sanitized bootstrap
passed in 69 s. Both complete corpora account for 982 inputs: 963 PASS,
19 SKIP, no failures or timeouts. All 19 signed CLI controls pass in the final
normal and ASan/UBSan builds, and all five installed ecosystem programs pass
with the final normal toolchain. The pure registry trust/index error controls
and the two-origin resolver run with LSan enabled and report zero leaks.
Formatter idempotence/IR checks pass, including an explicit two-file run for
nurlpkg and the registry store (neither skipped). Normal tools are restored.
Final logs are retained under `build/v1-hardening/registry-complete-*`,
`registry-final-san-corpus.log`, `registry-nul-san-controls.log`,
`registry-trust-complete-*` and `resolver-registry-complete-*`. The goal remains
open for the separate architectural, transactional and platform items above.
