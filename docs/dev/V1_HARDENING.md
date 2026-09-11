# v1.0 hardening evidence

The 2026-09-10 external audit is an investigation list, not an authority on
correctness. Each finding must be reproduced or checked against current source
before changing behavior. Passing a narrow check does not establish a broader
guarantee. This ledger retains the complete scope while changes are delivered
in reviewable groups. No item below certifies the whole language or ecosystem.

| Audit item | Evidence required before closure | Current disposition |
|---|---|---|
| A01: sanitizer coverage | Ordinary driver, bootstrap, split output and fuzz paths detect deliberate memory faults in generated code; clean controls, corpus and fuzz pass; UBSan/LLVM semantics documented | ASan emission implemented and calibrated; revealed HTTP/3 UAF and compiler leaks repaired; integer division/remainder, shifts and float casts now guard invalid domains, and the differential fuzzer now reaches those guards with computed operands; lexical stack-lifetime coverage remains open |
| A02: trustworthy compiler runners | Missing-main rejection fixtures run; crash/hang/worker fault controls fail closed; complete corpus verdict accounting | Verified in local normal/sanitized corpus and POSIX/PowerShell controls; native Windows execution remains CI evidence |
| A03: installed LSP | Separate installed project, unsaved edits, sibling/dependency imports, visible execution errors | Independently reproduced; repaired and verified with relocated binaries and 20 normal/ASan/LSan protocol/compiler controls on Linux; native Windows and actual distribution installation remain unverified |
| A04: registry identity | Two local registries with equal package names; fetch, resolution, signing and lock identity preserved; errors never print success | Origin/key/index/archive/lock binding repaired; conflict-directed resolver checked against an exhaustive oracle; flat-layout coexistence and transactional/frozen installation remain open |
| A05: signed install smoke | Signed fixtures install after relocation with transitive dependencies; missing/wrong/tampered signatures reject; CI runs it | Unsigned/stale smoke independently reproduced; signed five-program relocation smoke and CLI negative controls pass locally, wired into CI; remote run pending |
| A06: JS dependencies | Fresh manager-native audits, reachability analysis, lockfile updates and builds/tests for all four trees; recurring checks | Fresh audits repaired; all four clean installs, builds/checks and zero-finding re-audits pass locally; weekly/PR checks added; all four remote audit/build jobs pass at `5b2a9b3a` |
| A07: continuous package/service tests | Suite/prerequisite manifest, changed packages and reverse dependencies, scheduled coverage; registry/cloud and diagnostic gates in CI | Pending current workflow inventory |
| A08: documentation consistency | Grammar, spec, platform claims, generated facts and executable docs agree with implementation | Runner prerequisites, macOS/musl claims and stale leak comments corrected from source; the binding path now accepts the block-expression initialiser its own grammar specifies; remaining claims pending |
| A09: package development | Clean checkout and unpacked consumer tests, shared environment setup, explicit public import surfaces | Pending reproduction |
| A10: tree gates | Tracked formatting inventory, package-aware frontend coverage, recursive import checks with reported exclusions | The canonical-form gate now covers the tracked inventory (1,779 files) instead of five hand-listed directories, and the 18 files that had drifted are reformatted; package-aware frontend coverage and recursive import checks remain open |
| A11: toolchain build integrity | Injected required-tool failures fail the build; stale binaries cannot substitute; logs and totals retained | Required tools now fail the build, use the canonical driver and remove stale outputs; isolated full-build controls pass locally and are wired into CI |
| A12: LSP temporary files | Concurrent servers remain independent and no shared source files can be overwritten or leaked on errors | Source temporary files eliminated through compiler stdin snapshots; concurrent-server and missing-tool controls pass |
| A13: safety contract | Default/strict/raw/FFI guarantees agree; witnesses and valid controls; opaque wrappers and container ownership audited | The pre-registered C-runtime surface is now checked at call sites exactly as an '&'-declared FFI symbol is — it had no argument or arity check at all; opaque wrappers, container ownership and the rest of the contract review remain open |
| A14: crypto/parser evidence | Instrumented fuzz controls and retained seeds; pinned ACVP/HTTP oracles; measured backend timing; explicit X.509 policy and independent crypto review | Pending; requires A01 and external validation for independent review |
| A15: release integrity | Mandatory target artifact gates, pinned tool downloads, installer integrity and state-preserving failure controls | The artifact set is now gated before publication, with eleven controls in CI; installer checksum/signature verification reviewed and found fail-closed; pinned tool downloads and state-preserving unpack remain open |
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
not A04 closure. At this checkpoint, greedy resolution still lacked backtracking;
the subsequent resolver section below replaces it and removes the convergence bound. Lock
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

## A04 dependency search: independent reproduction and replacement

The audit's resolver criticism was checked against the implementation at
`9e272375`. Four offline positive controls failed: a diamond requiring an older
parent, a version-dependent cycle with a valid older version, an unavailable
dependency that an older parent avoids, and a 600-package chain exceeding the
256-round bound. A separate signed HTTP/CLI fixture reproduced `ResolveUnstable`
when `foo@2` required `bar@1`, `bar@1` required `foo@1`, and the root allowed
either version of `foo`. The compatible installation is just `foo@1`.

Resolution now uses explicit decision frames and a reversible constraint trail.
Every package identity has one assignment; edges to assigned packages check
that assignment directly. Candidate failure removes the candidate's edges and
tries another version. Indexes are fetched once per identity, semantic versions
are parsed once, and identical requirements share one parsed representation.
An indexed minimum heap orders only required, unassigned packages; a constraint
change refreshes its target's candidate domain instead of rescanning every node.
All state is owned by the resolution call and released on success and failure.

Plain chronological backtracking was insufficient: 28 unrelated binary-version
roots made a two-package contradiction enumerate irrelevant combinations. The
replacement records the earlier decisions responsible for a failed candidate
and jumps over choices that cannot change the contradiction. Domain filtering
retains a condition as a cause only when it removes a still-possible candidate;
package presence needs one cause unless a root already requires it. This also
prevents redundant wildcard edges from reconnecting unrelated decisions to the
same contradiction. Both intermediate implementations exceeded a three-second
probe on their respective controls; the final regression requires termination
within the suite's per-process watchdog. General dependency solving can still
require exponential search; these controls do not establish a polynomial bound.

`tools/tests/test_resolver.py` supplies an independent exhaustive oracle, using
a deliberately small integer-major version/range grammar. It enumerates all
assignments for 400 seeded graphs, verifies both satisfiable and unsatisfiable
results, then reverses roots, index versions and dependency edges and requires
the same selection: 800 resolver executions across those graph pairs. Separate
controls cover the four original failures, valid and invalid cycles, yanked
versions, equal-precedence build metadata, duplicate versions, malformed unused
metadata, lazy dependency fetching and the unrelated-choice cases. Every fetch
is recorded and duplicate fetching per identity fails the test. The adapter and
solver run with ASan/UBSan and LSan enabled, with stack roots disabled so stale
pointers in the returned main frame cannot conceal leaked owners. The real signed CLI control requires
the selected `foo@1` archive and lock entry, and rejects any download or installed
directory from the abandoned `foo@2`/`bar@1` branch.

Selection remains one version per `(registry, name)`: fewest candidates first,
then name and normalized URL, with descending SemVer candidates and descending
lexical build metadata for equal precedence. The policy is deterministic; it
does not claim to maximize all versions simultaneously. Invalid root names or
ranges have dedicated errors; invalid dependency names/ranges, malformed versions
and duplicate version identities invalidate an index, including unused versions.
`ResolveUnstable` and its arbitrary convergence limit are removed.

This repairs dependency search, not the remaining source-layout and installation
architecture. Equal-name registry coexistence, package-scoped imports, frozen
locks, typed HTTP failures, mixed local/registry graphs, filesystem symlinks and
atomic tree publication remain open. In particular, the current fetch callback
still represents transport failures and missing indexes with the same empty
string; successful backtracking cannot turn that API into a reliable transport
diagnostic. The ownership analysis limitation for captured callbacks also remains
separate A01/A13 work.

Local performance comparison (Linux x86_64, clang 18, normal optimized binaries)
used the same stdin JSON adapter against the old and final resolver, alternating
seven runs of each. The measurements include process startup, fixture JSON
parsing, fetch logging and lock serialization, with no network traffic. Median
elapsed time for 1,000 independent roots with two versions each fell from
60.3 ms to 25.7 ms; median process peak RSS fell from 6,740 KiB to 6,376 KiB.
A 200-package single-version chain fell from 78.0 ms to 4.90 ms, with peak RSS
2,420 KiB versus 2,312 KiB. The unrelated-choice and redundant-wildcard
contradictions completed in 1.86 ms and 1.46 ms in single final-binary probes.
These are local workload measurements, not universal throughput or memory bounds.
Inputs, the measurement script and raw samples are retained under
`build/v1-hardening/benchmark_resolver.py` and
`build/v1-hardening/resolver-backjump-benchmark.json`.

Final local validation for the resolver replacement: the normal bootstrap
passed in 43 s and its complete corpus in 2 m 11 s; the instrumented bootstrap
passed in 70 s. Both corpora account for 982 inputs: 963 PASS, 19 SKIP, with no
failures or timeouts. All 10 oracle/regression methods pass in normal and
instrumented builds (including LSan with stack roots disabled); all 20 signed
CLI controls pass in both builds. The five installed ecosystem programs pass
with normal tools. The separate registry trust/index controls and two-origin
resolver also pass with leak detection enabled. Explicit formatter idempotence
and IR-equivalence checks cover all four selected files without skips: the
resolver module, diamond fixture, new oracle adapter and package CLI.
Logs are retained under `build/v1-hardening/resolver-complete-*`. Normal
development tools were restored successfully after the instrumented checks.

### In progress: registry failures and compiler ownership prerequisites

The backtracking fetch callback's empty-string convention had a reproducible
failure beyond dependency search. With `foo@2` depending on `bar`, failures
fetching `bar` (HTTP 503, HTTP 401, malformed JSON, an empty HTTP 200 body, or a
disconnected socket) all caused the old CLI to install `foo@1`, report success
and replace the lock. An honest HTTP 404 remains a separate, valid missing-
package branch. Other controls reproduced a misleading not-found diagnostic
from `info`/tool installation, a successful `update --all` on HTTP 503, and a
successful publish dry-run despite the failed dependency-index gate. The publish
control supplies a real relocated compiler/stdlib, so the unrelated missing-
compiler bypass does not account for that result.

The current, uncommitted API returns `!RegIndex RegistryFetchErr`, preserving
HTTP status and transport cause and decoding the index once. Only genuine
absence is a retryable missing package; invalid responses and transport errors
abort resolution and preserve the old lock. `ResolveFetch` owns the failing
origin/name and its cause. The CLI propagates these distinctions through install,
info, update and the publish dependency gate. The targeted signed CLI suite has
24 methods and the resolver/oracle suite has 11. These are implementation work
in progress, not a completed release gate.

Owning the new resolver error exposed compiler defects independently of the
registry fixture. A tag-only enum used as a nested payload was boxed for some
expressions but stored inline for literals, while matching always dereferenced
it. A multi-field struct with a pointer first field was also mistaken for a
single-pointer handle. Named payload construction, decoding and drop
classification now share one representation decision. Anonymous aggregate
payload storage is a separate unresolved question; this does not establish its
safety.

A later-declared payload then exposed premature drop generation: the full
normal corpus reported a link failure in `forward_enum_payload` while the
other 965 runnable/compile/reject cases passed (19 skipped). The current code
captures declared layouts before ownership decisions and schedules recursive
drop graphs after type definitions and generic instances. The original forward
payload test, the nested-payload regression and the owned-enum sink regression
all pass as generated-code ASan probes with LSan and stack roots disabled.
These probes link the normal native runtime object, so they do not replace the
pending complete instrumented bootstrap/runtime gates.

Forward calls required a second ownership repair. Moving an inferred consuming
helper below its caller reproduced an ASan heap-use-after-free in the caller's
automatic drop. Sink implications now propagate to a finite fixed point across
all named bodies and instantiated generics. Static LLVM constants connect these
final facts to caller neutralization and the callee's ownership slot. The
non-consuming path of an inferred conditional sink also releases the received
owner. Borrowed enum parameters retain their readable value separately from
the inactive owner slot; conditional journal and cleanup gates disappear when
the final summary is borrowed. The optimized `inspect` control contains no
ownership/journal work. Explicit and implicit return transfer and `inout`
borrowing are covered by the expanded `sink_enum_owned` control.

Two integration errors found during this work were also corrected: branch-local
sink evidence must accumulate in its own function frame, and a nested closure's
parameter indices must not escape into the surrounding function's summary.
Forward generic calls need their actual template before argument substitution;
the signature pass now stores that template. Type-layout discovery must skip
trait supertrait headers rather than reading their colon as a struct declaration.

**Not ready to bootstrap or commit yet.** The broader inference also exposes an
existing invalid assumption in the borrow checker: a `_free`/`_free_with` name
plus a void return is treated as proof that parameter zero is consumed. The
independent `sink-name-contract-probe.nu` is rejected by the pre-change compiler
although its `report_free` function only prints a vector length. In the compiler
itself, `mem_emit_slice_free` only emits IR and borrows its symbol table; treating
it as a destructor causes 634 transitive false diagnostics in the new self-
compile. Renaming that helper, adding an exception for it, disabling borrow
checking, or suppressing the new propagation would not repair this contract.
The consuming API contract and its inference need to be made explicit and
sound before accepting this work. The complete normal/sanitized bootstraps,
all relevant corpora, leak gates, installed tools, documentation and snapshots
must then be refreshed and verified. A01/A13 and the wider audit remain open.

Reproduction and iteration artifacts are under `build/v1-hardening/`:
`registry-transport-before.log`, `registry-transport-commands-before.log`,
`sink-enum-forward-before.log`, `sink-name-contract-before.log`,
`nurlc-layout-sink-self.log`, `layout-sink-full-corpus*.log`, and the
`*-layout` probes/IR/logs. Intermediate corpus failures are retained rather than
rebaselined as successes. No native Windows validation has been performed.

Follow-up validation of this iteration: the 11 resolver methods pass using the
new generated-code ASan probe (with leak checking), and the 24 signed CLI
methods pass using a newly compiled normal CLI. The second full corpus reduced
the 101 intermediate failures to four: two diagnostic-text changes, the newly
supported forward generic `inout` call, and `ptr_borrow_arms` passing the same
value onward after a potentially consuming call. The last fixture now expresses
its consuming helper as `sink`, releases it on both paths and gives it a separate
input; the sibling-arm and early-return pointer-borrow controls remain intact.
The generic test is now `inout_generic_forward` and checks the mutated value.
All four targeted checks pass. The two malformed-program fixtures still fail
at the intended source sites; the earlier generic-template validation and
available enum metadata explain the changed diagnostic counts. Windows golden
twins were synchronized without claiming a native Windows run. The self-compile
contract failure remains open and prevents refreshing bootstrap snapshots.

The third complete corpus run passes: 985 inputs, 966 PASS and 19 SKIP, no
failures, missing records or orphans (`layout-sink-full-corpus-3.log`). The
owned-enum regression also passes at `-O0` with generated-code ASan/LSan when
borrow diagnostics are disabled; ownership inference must remain active in that
mode and does. The development compiler was restored after the isolated runs.
This corpus result does not resolve the separately failing compiler self-compile.

A read-only inventory of release-named declarations and their body calls is
retained in `destructor-contract-inventory.json` with its generating Python
script. Call spellings are investigation aids, not evidence of ownership.
Inspection also identified `packages/nwasm/src/interp.nu::__cu_mem_free`: it
pops a device pointer and calls `cuMemFree`, then continues using its interpreter
argument. Like the compiler's IR emitter, it does not consume argument zero.
Conversely, the CUDA/Opus destructors call foreign destroy functions, and
`iter_free` calls a closure with its release selector. A correct replacement
cannot equate either a suffix or the presence/absence of a release-named body
call with a consuming parameter contract.


### Consumption contracts and integration follow-up

The suffix heuristic is now removed. Release APIs declare the parameters they
consume with `sink`; the migration covers 445 additional release declarations,
plus CUDA release calls that return status. Inspection left the compiler's IR
emitter, the REPL's pop-and-free-element helper and the interpreter's CUDA
instruction handler borrowed. GPU timer disposal consumes its event argument,
not its GPU context; the eight-string cleanup helper consumes all eight inputs.
These are signature contracts, not a replacement list of compiler name rules.
The actual generic instances now feed the fixed point; the earlier lexical
first-argument template scan is removed.

An independent callback control reproduced a second false ownership transfer:
a local callback named like a global sink inherited the global's contract.
Call resolution now establishes local-callable shadowing before consulting
parameter summaries and trait dispatch. The control owns a nested enum, reads
it through the callback twice and reads it again afterwards; ASan/LSan passes.

The wider package check exposed a statement-order defect: consuming an old
value on the RHS of `= x (replace x)` was recorded after binding the result,
so the new value looked moved. A separate Vec control reproduced three false
diagnostics. Binding records now apply RHS reads and call effects before
installing the result. Repeated Vec and enum replacement/identity paths pass
ASan/LSan. ARIMA's existing stepwise search then compiles without changing its
algorithm. The CLI cache notice now captures its freshness bit before releasing
the cache record, respecting the record's explicit consumption contract.

Normal bootstrap reached its byte-identical fixed point. The complete normal
corpus passed 971 cases with 19 skips (990 selected); the 11 resolver methods,
24 signed CLI methods and all five installed ecosystem programs passed.
The memory gate measured 27 MB peak RSS, and the DCE gate passed. Checked and
`--no-borrowck` IR is identical for five ownership regressions. A package-root
frontend check covered 199 entries/tests: 161 passed, 35 lacked imports, and
three produced diagnostics also reproduced by the old compiler. No remaining
new compiler regression appeared in that check; it is not a claim that those
38 sources or all package runtime tests passed.

The first complete generated-code sanitizer corpus also passed all 971 cases
with 19 skips. A separate formatter-library control then exposed a compiler
leak in construction of a pending sink implication (6186 bytes in 191 records
for that fixture). The minimal `sink_summary_storage` reproduces one leaked
18-byte record. The summary table copies the record, so `gen_call` now owns
and releases its temporary record after that copy. The minimal source and a
complete compiler self-compile pass with the repaired instrumented compiler,
leak detection enabled and stack roots disabled. The compiler leak gate now
includes this regression. This is source-level ownership of the compiler's
record buffer; it does not claim to finish general owned-string temporary
transfer across arbitrary forward/escaping calls.

Leak-test stack-root options are now passed through `LSAN_OPTIONS`, including
the compiler leak gate, rather than placing that LSan-specific option in
`ASAN_OPTIONS`. The first focused leak run failed in compiler compilation
before it could execute its seven programs; those failures are retained as
failures. Final sanitizer bootstrap, focused leak checks and full validation
are pending at this point. The broad v1 goal and the remaining ownership,
callback, package-layout and platform limitations remain open.


The next focused compiler leak checks exposed an additional lifetime mismatch
in newly returned flag/register name buffers. Sink flags now return their
numeric identity; their textual names are formed in their owning caller.
Load/select emitters borrow explicit result-register names instead of allocating
and returning them. This also removes an unnecessary cached-name copy. The five
previously failing source controls compile with zero leaks and emit byte-
identical instrumented LLVM IR before and after this change. Self-compilation
is leak-clean too. All eight focused compilation/runtime leak controls pass with
the refreshed sanitized bootstrap. The earlier failing reports are retained in
`contracts-owned-leaks-registers-before.log`; they were not reclassified as passes.
A token comparison verified that 250 existing NURL files outside the substantive
implementation and fixtures changed only in `sink` markers, comments or layout.


Review of the final commit path found another false-success gate: the pre-commit
hook discarded `nurlfmt --write` failures and could stage partial formatter
output anyway. Two isolated Git-index controls fail against the previous hook.
The hook now blocks on formatter failure and leaves the staged source intact;
all four controls (including successful formatting and partially staged input)
pass. CI runs these checks. This correction does not change the configured
policy of skipping the hook's formatter check when no formatter is installed.

Final validation of this unit is complete. Both the normal bootstrap/corpus
and the generated-code sanitizer corpus selected 991 tests: 972 passed and 19
were skipped, with no failures or timeouts. The eight focused compilation and
runtime leak controls passed, as did all twelve compiler leak checks (six
sources in single-module and partitioned emission). Formatter tests passed all
11 methods, resolver tests all 11 methods, signed registry CLI tests all 24
methods, and all five installed ecosystem programs passed. Final normal build
artifacts are restored; self-compilation reached its byte-identical fixed point,
peak RSS was 27 MB, and the DCE gate passed.

Three ownership fixtures also compiled, linked and ran successfully as four
separate modules with generated-code ASan/UBSan and leak detection enabled.
The normal CI job now builds and executes `sink_enum_owned` through the public
split-build driver; that exact command passed locally too. Final logs are in
`build/v1-hardening/contracts-final-normal-build.log`,
`contracts-full-san-final.log`, `contracts-owned-leaks-final.log` and
`contracts-compiler-leaks-final.log`, with the corresponding formatter, resolver,
registry and installed-program logs alongside them. These checks complete this
unit, not the broader v1 goal or the remaining limitations recorded above.

### Publication compiler gate: verified failures and literal process arguments

Six isolated CLI controls independently checked the existing executable's
compiler gate. Five failed: a missing compiler and an unavailable target root
reported success, an unlaunchable compiler and a source diagnostic were
mislabelled as missing stdlib APIs, and shell substitution inside the toolchain
path executed a command. The valid default-prefix control passed. The baseline
is retained in `build/v1-hardening/publish-compiler-before.log`.

The gate now requires an available target root and compiler, pins that root
in the command's child environment, and invokes `process_run2` with literal
arguments and `--check`. Launch errors retain their typed process cause;
compiler errors retain their diagnostics without inferring a different cause.
Negative controls run both dry-run and authenticated publication against an
isolated local server and require no network request, unchanged manifest/lock
bytes and a nonzero exit status. Positive controls cover shell metacharacters
in the prefix and a module available only in the default installed target.

LSan then exposed 112 leaked bytes in four allocations on each tested gate
failure: registry and token owners were bypassed by early returns. All five
validation checks now run in a borrowing helper, leaving the owning command
to release these resources at its common cleanup point. The failing log remains
`publish-compiler-leaks.log`. All seven focused controls pass after that fix
with an instrumented CLI and normal compiler (`publish-compiler-leaks-final.log`).
The six CI controls that do not reject compiler input also pass with both the
CLI and compiler instrumented (`publish-compiler-ci-leaks.log`).

The separate rejected-input compiler limitation remains independently
reproducible: instrumented `nurlc --check` on one undefined identifier reports
61460 leaked bytes in 942 allocations with stack roots disabled
(`publish-rejected-compiler-leaks.log`). This is not suppressed or counted as a
passing leak check. The full registry CLI suite exercises compiler diagnostics
with ASan/UBSan; the focused CI leak gate covers the six controls above until
compiler error-path ownership is repaired. Library packages without
`src/main.nu` still skip the compile gate, and path-dependency archive fetch
failures and complete source-tree comparison remain open work. This change
does not establish full release completeness or native Windows behavior.

Final normal and instrumented CLI suites each passed all 30 methods; the
instrumented suite also used the instrumented compiler for its target-toolchain
fixtures. Logs are `publish-compiler-final-normal.log` and
`publish-compiler-final-san.log`. The normal `build/nurlpkg` is restored, and
the changed NURL source passes the formatter check. No compiler semantics or
bootstrap snapshot changed in this unit, so the complete compiler corpus was
not repeated for this CLI-only change.

### Compiler diagnostic cleanup — work in progress

The next continuation reproduced the compiler leak and traced it to two
separate causes: frontend failures bypassed main's cleanup, and per-declaration
recovery deliberately disabled the allocation journal to avoid its linear
search on every free. The journal's array-index marks also failed when an inner
extent removed an outer owner and reused its slot. Two public runtime controls
failed against the previous implementation: an inner panic missed its new owner,
and an outer panic incorrectly dropped an owner from a completed inner extent.

The candidate runtime indexes registrations by pointer and uses monotonic
sequence marks across deletion and compaction. Seven ASan/LSan test methods pass,
including 40 generated nested-scope programs compared with an independent owner
model. The FIFO registration benchmark (three runs, median, clang -O2) changed
from 0.1201 s to 0.00384 s for 10000 live owners and from 2.0165 s to 0.00691 s
for 40000; logs are `panic-journal-before.log`, `panic-journal-oracle.log` and
`panic-journal-benchmark.log` under `build/v1-hardening`.

The candidate compiler uses journalled recovery and a common frontend boundary.
Its compilation context owns all lexer and symbol-table instances through
intrusive lists, with constant-time early release and final cleanup of objects
abandoned by diagnostics. Error recovery retains buffered IR instead of exposing
partial definitions. Argument temporaries and reassigned owned string/slice
bindings now register their unwind obligations. `recover_reassign_temps` leaked
69 bytes in four allocations before the codegen correction and passes LSan
after it. Five compiler cleanup methods cover body/prepass/deferred/import
failures, stdin, CLI failures, the error limit and output modes; they pass with
the instrumented candidate (`compiler-cleanup-controls.log`).

This unit is not complete. A broader --check sweep of 363 existing diagnostic
fixtures found 44 remaining small leaks, largely involving ownership guards for
forward string-returning calls and their argument temporaries. The complete
results are in `diagnostic-memory/results.json` and the individual stderr logs;
the 44 failures have not been suppressed or relabelled. Return/consumer ownership
must be repaired at its general source rather than adding compiler-helper names
to ownership whitelists or reordering their declarations. The instrumented
candidate's self-compile already reaches byte-identical IR at stage 3 with no
leaks: 10.41 s / 1354552 KB peak RSS versus 9.87 s / 1355512 KB for the previous
instrumented compiler on the same current source. These are ASan measurements,
not the normal-build memory gate. Full normal validation is in progress in
`error-cleanup-normal-build.log`; bootstrap snapshots have been refreshed for
the candidate and remain uncommitted with this work.

The normal bootstrap completed in 50 s; its corpus passed all 972 previous
cases with 19 skips. The new recovery fixture initially failed only because
its handwritten golden lacked the runner's compile/link/exit header. The
runner regenerated that golden from the verified output. The normal memory
gate remains 27 MB and the DCE gate passes (180 emitted, 12 reachable; equal
behavior). Four representative failures from the wider sweep have now been
added to the compiler cleanup test itself, so that suite deliberately remains
red under LSan until the forward-return/consumer ownership defect is fixed.
There has been no commit or publication of this unfinished unit.

The next independent consumer test, `recover_forward_consumer`, leaks 31 bytes
in two allocations with the current candidate: an inline owned argument to a
forward reader and another to a forward function that panics. A trial deferred
consumer predicate removed those leaks, but a counterexample invalidated its
proof: `@ address_of s value → i { ^ # i value }` returns the argument's address,
so a scalar result is insufficient evidence for releasing that argument. The
same use-after-free already occurs in the existing compiler when this helper
is defined before its caller, including when the cast is first bound to a
local. `tools/tests/test_string_argument_ownership.py` reproduces both orders
under ASan/LSan; it currently reports three failures (the forward reader/panic
case and the two backward address-return cases). The experimental predicate
was removed from the source; its diff and results remain in
`build/v1-hardening/forward-consumer-rejected.patch`,
`recover-forward-{before,after}.log`, `backward-address.log` and
`string-argument-ownership-before.log`. The required fix must preserve address
provenance through casts, bindings and calls before extending consumer drops.

The now-unused `nurl_recover_nojournal` implementation and its WASI stub have
been removed; neither compiler source nor refreshed bootstrap IR references
it. All seven standalone journal methods still pass, and a normal bootstrap
with `--no-tests` completes in 27 seconds after removal. The journal owner-model
suite is now wired into the sanitizer CI job. This does not turn the outstanding
compiler ownership tests green, and the unit remains uncommitted.

The following continuation extends returned-parameter provenance through casts,
integer arithmetic/bitwise operations, named locals, assignments, conditionals,
match arms and value blocks, including implicit returns. These ownership facts
remain active with `--no-borrowck`. Positional and named argument temporaries
now share `mem_consumer_arg_drop_safe`; a returned-parameter fact vetoes a drop
even for an integer return type. A forward helper whose body frees its argument
previously caused a named call to free that same argument again. The new helper
removes that double free (`string-named-sink-before.log` / `-after.log`). Explicit
`sink` parameters are currently excluded from named-call dispatch; that syntax
was not the accepted input reproducing this bug.

The expanded address test covers 15 source spellings in both declaration orders,
with and without borrow checking. The normal candidate passes those 60 ASan/LSan
program runs, along with named arguments and a scalar-conversion control. A
proposed copy control was corrected after inspecting emitted IR: an untracked
mutable `s` alias need not copy its parameter. The actual copy control now uses
`nurl_str_cat value` with an empty suffix; a separate alias control transfers
the same pointer back for explicit release. Both controls pass.

This is still an incomplete dataflow implementation. Two additional independent
controls fail with heap use-after-free: a forward call nested inside a cast, and
an address carried through a loop backedge. Eagerly expanding binding names to
their currently known parameters loses both dependencies. The next change must
retain stable origin identities and symbolic dependency edges across scopes,
assignments and calls, then solve the finite graph before emitting ownership
decisions. Extending the old scalar predicate to forward consumers remains
unsound until this is fixed. `string-address-dataflow-frontier.log` contains
both counterexamples; they are permanent methods in the ownership test.

The instrumented compiler's own self-check currently reports 603 bytes in 135
allocations from `nurl_sym_get` (`nurlc-address-stage2-check.log`). This regression
is not accepted: new analysis calls exercise the still-unfixed forward argument
temporary path. The four diagnostic cleanup representatives also remain red
(`compiler-cleanup-address-provenance.log`). Instrumented program tests are run
separately with a normal compiler to distinguish generated-program lifetime
failures from the compiler's own leak gate; neither result replaces the other.
Normal full bootstrap/corpus validation is in
`address-provenance-normal-build.log`. No changes in this unit have been committed.


### Address graph continuation (draft checkpoint, 2026-09-11)

The eager-name analysis has been supplemented by a compilation-owned root
address graph. Binding nodes survive scope exit and retain assignment and
loop-backedge dependencies. Conditional call edges read the completed callee
return/consumption facts; a worklist propagates inline parameter bits with
sparse overflow words. Legacy diagnostic implications participate in the same
finite convergence, with the 64-round cap removed. Named and positional string
argument temporaries use shared deferred LLVM constants for their final drop
proof. A forward string result passed directly as an argument captures its
existing dynamic ownership guard instead of abandoning the returned buffer.

The first graph candidate fixed the two address use-after-free witnesses and
the 31-byte forward-consumer leak, but exposed missing raw-free consumption
facts. Adding those facts exposed a second distinction: a new closure's root
environment is not any of the objects it captures. Root-address facts are now
separate from embedded-reference facts. A full toolchain build additionally
found that lifted closures inherited the enclosing function's summary nodes.
Closure summaries now have their own parameter domain, including hidden capture
inputs. The corrected candidate passes the nurlpkg source check; the failed
intermediate build remains recorded in `origin-normal-build.log` and must not
be mistaken for the final result.

Verified focused results for the corrected candidate:

- `tools/tests/test_string_argument_ownership.py`: 15 methods pass, including
  the original 60 spelling/order/borrowck combinations, 70-parameter functions,
  an 81-function return chain, named arguments, cast/alias consumption, closure
  environment ownership and closure parameter isolation.
- `tools/tests/test_panic_journal.py`: all 7 methods pass.
- An independently linked ASan/UBSan compiler candidate successfully checks its
  own current source with `ASAN_OPTIONS=detect_leaks=1:halt_on_error=1` and
  `LSAN_OPTIONS=use_stacks=0`. The earlier 603-byte self-check regression is gone.
- `tools/tests/test_compiler_cleanup.py` still fails two representative inputs:
  `diag_bad_type_token` leaks 4 bytes in one allocation;
  `diag_closure_arity_few` leaks 2 bytes in two allocations. The other two prior
  diagnostic regressions (`diag_send_chan_send`, `should_fail_unterminated_trait`)
  and the ordinary/error/CLI test methods pass. These remaining failures are
  deliberately unsuppressed.

Local evidence is in `build/v1-hardening/string-origin-scopes.log`,
`panic-journal-origin.log`, `nurlc-origin-scopes-selfcheck.log` and
`compiler-cleanup-origin-scopes.log`. `nurlc-origin-scopes-san` is the isolated
instrumented compiler used for the last two checks; its runtime was separately
compiled with ASan/UBSan. This focused candidate check does not replace the
repository's full sanitized bootstrap, corpus or multi-mode leak gate.
The final normal bootstrap/corpus run is `origin-scopes-normal-build.log`.

Remaining work before merge: fix the two diagnostic lifetimes at their general
source (forward return-proof propagation and guarded owners across panic),
rerun the wider diagnostic sweep, and complete the full sanitized bootstrap,
corpus and multi-mode leak gates. Audit indirect calls, aggregate-contained
origins, generic dispatch and all forward-result exit paths against independent
counterexamples; passing the focused address suite alone is not proof that
all lifetime cases are covered. Do not add helper whitelists, reorder helper
definitions, or suppress leak detection to pass a gate. The v1 hardening goal
remains open; the audit document is a hypothesis source, not an oracle.


The next full normal run found `vec_push_temp_owned` returning 1 with empty
output (973 passes, one failure). This was a real premature drop, not a golden
mismatch: the new generic-call decision lacked the address-retention fact for
`= . data len x`. Pointer/slice writes now contribute their RHS's root origins
to the function's escape summary, and the `nurl_poke` ABI declares its stored
value position as retained. The unchanged fixture again prints `item3` and
exits zero. Additional ASan/LSan controls cover typed pointer stores, raw-word
stores, forward/backward definitions, `--no-borrowck`, and freeing a vector's
stored string exactly once. The expanded suite passes all 17 methods with the
normal isolated candidate (`string-origin-stores.log`).

The final isolated candidate is `nurlc-origin-stores-san`; it emits its own
current source successfully under ASan/UBSan/LSan with no findings, including
full IR emission (`origin-stores-self-emit.log`). The diagnostic cleanup suite
still reports exactly the same two failures (4 bytes and 2 bytes), recorded in
`compiler-cleanup-origin-stores.log`. The latest complete normal run is
`origin-stores-normal-build.log`; earlier logs above describe intermediate
candidates and must not be used to claim the latest build passed.


Final normal validation for this checkpoint is green: full refreshed bootstrap
and corpus **974 PASS, 19 SKIP, no failures** (`origin-stores-normal-build.log`,
`build/logs/build.pDABto`), including the unchanged `vec_push_temp_owned` golden.
Build time was 1m01s and corpus time 2m53s. Source and bootstrap source are
byte-identical. The normal memory gate reports **34 MB** peak RSS (budget
600 MB), and DCE reports **180 emitted / 12 reachable**, with identical
behavior. The previous pre-graph candidate measured 28 MB on its then-current
source; these are separate source revisions, not a controlled performance
comparison. The final address suite also passes all **17 methods with an
instrumented compiler**, in 98.931s (`string-origin-stores-instrumented-compiler.log`).
No full sanitized bootstrap/corpus or complete multi-mode leak-gate result is
claimed for this checkpoint. Continue from
[V1_HARDENING_HANDOFF.md](V1_HARDENING_HANDOFF.md); the PR remains a draft.

## A06: dependency audits and clean installs (2026-09-11)

Fresh npm audits reported six vulnerable dependency packages in each Worker
project (five high, one low), and one high-severity `brace-expansion` finding
in the VS Code extension. The pnpm audit reported 33 advisory findings for
webdocs, including two critical Next.js advisories. These are manager-reported
findings, not independently demonstrated exploits against the deployed sites.

The Worker findings are in Wrangler's development/deployment dependency tree
(`miniflare`, `undici`, `ws`, `sharp`, `esbuild`); both manifests classify
Wrangler as a development dependency. The extension finding is in its packaging
tooling. Webdocs exports static files (`next.config.mjs`: `output: 'export'`),
so the deployed site does not run the Next.js server, Server Actions or its
image-optimization endpoint. The affected packages still execute during local
and CI development/build work; static export is not used to dismiss the audit.
No advisory exclusions or forced incompatible npm resolutions were added.

The lockfiles now resolve Wrangler 4.131.0, `brace-expansion` 2.1.4 for the
extension, and Next.js / eslint-config-next 16.3.3. Both Worker projects use
Workers types 5.20260911.1 to satisfy the updated Wrangler peer requirement.
Webdocs' compatible dependency updates were resolved by pnpm 10.34.5. Fresh
manager-native audits after clean installs report zero findings in all four
trees, including development dependencies.

Clean-install verification on Node 24.15.0 / npm 11.12.1:

- Registry: TypeScript and 73 README-rendering assertions pass.
- Cloudflare: generated Worker types and TypeScript pass; recovery and all eight
  artifact controls pass. Typechecking now regenerates ignored bindings first,
  and `src/env.d.ts` declares the optional deploy-workflow `NURL_DEPLOY_ID`.
- VS Code: launcher controls and `npm pack --dry-run` pass.
- Webdocs: frozen pnpm install, MDX/Next/TypeScript checks and the complete
  production static export pass.

`.github/workflows/dependency-audit.yml` adds changed-tree PR checks, main-branch
lockfile checks, a weekly audit and manual dispatch. Each job retains the audit
JSON, checks all severities and runs the corresponding project checks without
service credentials or deployments. Remote workflow execution remains pending;
zero findings describe this dated local audit, not future advisory databases.
Evidence is retained in `build/v1-hardening/audit-*.json`, `audit-fix*.log`,
`audit-webdocs-after.json` and `js-*.log`.

### Return ownership and diagnostic cleanup (2026-09-11)

This checkpoint supersedes the two open diagnostic leaks above. Independent
controls reproduced forward return-proof loss, proof clobbering by `defer`,
indirect closure-return leaks, and a bound dynamic return that tried to copy an
opaque `s` value (`# s 42`). A further control stored a guarded string address
inside a nested conditional; scope-local read counters lost that use and freed
the buffer at function exit. The original sources fail their sanitizer controls;
the unchanged vector golden remains `item3`, exit 0.

Result ownership is saved per activation before cleanup, published at the final
LLVM return, and captured immediately after direct/indirect calls. The runtime
channel is thread-local (plain storage on single-threaded WASI), with a
deterministic two-thread isolation control. Bound returns preserve the original
owner pointer, including null for borrowed or opaque results. Successful owner
transfer removes the callee's panic-journal registration only after cleanup.

Guarded bindings now use the stable address graph to select the owner eligible
for cleanup and panic registration. The selected drop slot is distinct from
the original result-proof slot. Reachability survives scope exit, aliases and
forward calls; storage, captures and unknown dispatch conservatively retain
owners. A direct guarded return transfers at that return site while other
paths still reclaim the binding. Local owners add no fabricated parameter bits,
and guard analysis does not modify summary solver state. The existing temporary
consumer whitelist was not expanded; the guarded-binding read counters were
removed.

The first graph-lifetime candidate fixed the nested-store use-after-free but
leaked empty recursive `__thr_check` results on 24 rejected-source controls.
Treating all possible returns as lifetime escapes had also disabled cleanup on
paths that did not return that binding. Return-site transfer edges fixed this
cause; no helper reordering, name exceptions or leak suppressions were used.
The wider diagnostic sweep also found `__diag_lit`'s raw result allocation; it
now uses the existing owned string API and preserves the diagnostic text.

Focused verification:

- All 25 address/return ownership methods pass with both the normal candidate
  and the ASan/UBSan candidate; emitted programs also run with ASan/UBSan/LSan.
- All six compiler-cleanup methods pass, including a sweep derived from all
  366 current rejection goldens and their actual runner flags. Output-mode,
  stdin, error-limit and invalid-CLI controls remain included.
- The instrumented compiler emits its complete source with leak detection
  enabled and `LSAN_OPTIONS=use_stacks=0`, with no sanitizer findings.

Failed and passing stages are retained under `build/v1-hardening/`: the
`*-before.log` witnesses, `guard-graph-cleanup.log` (failed),
`guard2-{ownership,san-ownership,cleanup,self}.log` (passed). The final shared
bootstrap/corpus results are recorded separately below. These results close the
listed rejection regressions, not A01's lexical lifetime/arithmetic work or the
entire safety, architecture and package audits.

Final shared verification for this checkpoint: refreshed normal bootstrap and
993-input corpus pass (974 PASS / 19 SKIP, 59 s build and 2 m 47 s tests).
Sanitized bootstrap passes (85 s); its complete corpus also reports 974 PASS /
19 SKIP with zero sanitizer/compiler/link/runtime/timeout failures. All six
compiler leak-gate inputs pass both ordinary and instrumented split emission
(12 modes), and the shared compiler passes all six diagnostic-cleanup methods.
RSS is 35 MB against the unchanged 600 MB budget; DCE is 180 emitted / 12
reachable with matching behavior; all seven runtime-journal controls pass.
Logs are `guard-final-*.log`; the normal verdicts are also retained separately.

Enabling LSan for the complete installed LSP suite yields five failures out of
20 controls: message-building argument temporaries leak in compiler-failure and
formatter-failure paths. This is separate from the now-clean rejected compiler
processes. The failed `guard-final-lsp.log` is retained. The remaining aggregate
consumer restriction and unknown-call handling need investigation before this
service suite can truthfully become a zero-leak CI gate.

### Primitive effects and aggregate consumers (2026-09-11)

The complete LSP leak experiment above exposed two compiler defects. A Json
copy consumer leaked its owned argument because temporary cleanup required a
fresh string or scalar result. Conversely, a source wrapper around an unknown
foreign pointer-retaining call freed its argument too soon. Independent C
translation units retain and later read both pointer arguments and addresses
cast to integers, so these controls do not depend on NURL's own inference.
Simply allowing all analyzed result types fixed the leak but not the
use-after-free, and that intermediate candidate was rejected.

The stable graph now propagates unverified foreign/indirect-call effects per
argument in a lifetime-only summary. Primitive declarations carry audited LLVM
`nocapture`/`nofree` contracts; `readonly` return aliases remain in the address
graph. Explicit scalar data roles use a custom `nurl.value-only` ABI attribute,
never an assumption that integer arguments cannot retain addresses. Source
functions are inferred from their bodies, including definitions that shadow a
primitive name. This removes the temporary-consumer helper whitelist entirely.
The contracts and their LLVM 15 basis are described in
[compiler memory discipline](COMPILER_INTERNALS.md#4-memory-discipline).

The initial unverified-call candidate leaked 1,028,315,679 bytes during
self-compilation because it could not prove local use through `strcmp` and
`nurl_strdup`; a later candidate leaked 1,224 bytes on the SIMD rejection path
because length/index arguments carried false unknown-call retention. Both
failures remain in the local logs. The primitive contracts close those proof
gaps without declaring unknown C functions safe.

After the service leaks were repaired, LSP tests exposed an additional,
independently reproduced preexisting compiler leak: `--lint --check` on
`argv_test.nu` leaked 2,706 bytes while walking imported definitions. A mutable
cursor initialized from a proved owned local was untracked; owned replacements
and the mixed join that preserved the previous cursor leaked. Such initializers
now receive their own copy in both explicit and inferred binding paths. The
new standalone cursor witness leaked 33 bytes before repair. Borrowed parameter
and opaque-address controls still preserve identity.

The ownership suite now contains 31 methods, including Json copies in both
declaration orders, unknown foreign pointer/integer retention, returned
`strstr`/`memmem` aliases, source overrides of primitive names and mutable cursor
replacement. Diagnostic cleanup has seven methods: all 366 current rejection
goldens plus output modes, stdin, limits, CLI errors and the positive lint
walk. An isolated toolchain selector lets the full 20-test installed LSP suite
exercise the candidate without replacing shared build outputs. All three
focused suites and instrumented self-compilation pass with LSan enabled and
stack roots disabled in the no-whitelist candidate (`consumer-nohelpers-*.log`,
`lsp-nohelpers-tests.log`).

Final shared verification: both refreshed bootstraps reach their fixed point,
and both 993-input corpora report **974 PASS / 19 SKIP** with no failures. Normal
build/test times are 60 s / 2 m 52 s; the sanitized bootstrap is 86 s. All 31
ownership methods pass with normal and instrumented shared compilers; all seven
cleanup methods and all 20 installed LSP controls pass with the instrumented
toolchain and LSan enabled. Six compiler leak-gate inputs pass both ordinary and
split emission (12 modes), and deliberate generated-code sanitizer controls
still detect their faults. Normal RSS is 36 MB against 600 MB; DCE remains
180 emitted / 12 reachable with matching output. Logs and separate normal/san
verdict files use `consumer-final-*`. The full LSP CI step now enables leak
checking without the former exception. These results do not close the full
safety, platform, architecture or package audit.

### A11: split driver paths (2026-09-11)

The existing draft PR's macOS ARM64 build passed bootstrap/corpus but failed its
`nurl.sh` smoke step on `smoke dir/s.nu`: the unquoted split-prefix flag became
two compiler arguments. This is independently reproducible on Linux. Quoting
that prefix alone would still leave the forced-split link and cleanup splitting
the object paths. The driver now preserves both the compiler flags containing
paths and the split-object list as individual POSIX shell arguments.

Both new real-toolchain controls fail before repair and pass after it, using
relocated compiler/runtime paths, source/output names with spaces and literal
brackets, and both a small unsplit program and forced two-part lowering. They
verify execution and intermediate cleanup; Linux and macOS CI run them. Commit
`5e673886` contains the driver fix. The old remote log is `pr-arm64-before.log`,
and local evidence is `driver-paths-{before,after}.log`. New remote execution
remains pending.

### A01: arithmetic boundary reproduction (2026-09-11)

Seven additional probes take values from independent C functions so optimized
NURL compilation cannot resolve the inputs. Both O0 and O2 use generated-code
ASan and the sanitized C runtime. Signed `INT_MIN / -1` and `INT_MIN % -1` report
native FPE under ASan at O0 but return silently at O2. Dynamic negative/width-sized
shifts, NaN/infinity-to-signed casts and negative-to-unsigned casts return without
any finding at both levels. None produces a NURL panic. These outcomes do not
meet a source-level safety/detection contract; they remain open controls.
The [LLVM 15 operation contracts](https://releases.llvm.org/15.0.0/docs/LangRef.html#srem-instruction)
confirm the overflow/poison boundaries. Sources, IR, stdout/stderr and the
14-run result matrix are retained in `build/v1-hardening/arithmetic-before/`;
the generator is `arithmetic-before.py`. No arithmetic codegen change is included
in the primitive-effects checkpoint.


### A01: source arithmetic guards (2026-09-11)

The compiler now branches to a NURL panic before integer zero division or
remainder, signed `MIN / -1` or `MIN % -1`, and dynamic shift counts outside
`[0, width)`. Scalar and aggregate-first-field float casts share truncation,
signedness and ordered bounds checks. NaN, infinity and values whose truncated
result is unrepresentable panic before LLVM conversion. Fractional lower-edge
values such as `-128.9 → i8` and `-0.9 → u8` remain valid. Aggregate unsigned
casts now use `fptoui`; aggregate float-to-bool casts reject like scalar casts.
IEEE floating division/remainder behavior and integer wrapping remain unchanged.
The spec and build documentation describe the source checks separately from
C-runtime UBSan; LLVM poison is not itself a sanitizer success.

`tools/tests/test_arithmetic_safety.py` has seven methods: **596 runtime cases
in each of three modes (1,788 executions), plus two compile rejection controls**.
Independent C inputs prevent source constant folding. The modes are O0 with
ASan/UBSan/LSan, ordinary unsanitized O2, and instrumented O2 three-part output
with `--no-borrowck`. Controls cover all four integer widths/signs, f32/f64,
scalar/aggregate conversion, exact representability boundaries, short-circuit
and phi contexts, and owned-string panic cleanup. Linux sanitizer and macOS
workflows run this suite. The before matrix fails on the old implementation;
final normal and sanitized compilers pass all seven methods.

Both refreshed bootstraps pass; source and bootstrap source are identical.
Normal build: 75 s, corpus 2 m 48 s. Sanitized bootstrap: 85 s. Both corpora:
**974 PASS / 19 SKIP / 0 failures, 993 records**. The final instrumented toolchain
also passes all 31 ownership, seven compiler-cleanup and 20 LSP methods,
all six leak-gate inputs in both emission modes, and sanitizer detection
calibration. Normal RSS is 36 MB (600 MB budget); DCE is 180 emitted / 12
reachable with identical behavior. Logs are `arithmetic-final-*` under ignored
`build/v1-hardening/`; copied verdicts distinguish normal and sanitized runs.
A01 remains open for lexical stack lifetimes and broader fuzz requirements.

### Remote checkpoint and runner startup control (2026-09-11)

Draft PR #1107 at `5b2a9b3a` passes macOS ARM64, Windows, FreeBSD, the sanitizer
job, required-tool fault injection, webdocs and all four JavaScript audit/build
jobs. This validates that revision and those workflow scopes, not later edits
or every distribution target. The Linux job is cancelled at its overall budget
while installing MinGW with apt; it is not a passing whole-job result.
The unikernel job exposes LLVM parameter attributes being parsed as value types
by the shared wasmbuilder rewriter. Both need follow-up before a green PR.

The runner fault-injection job times out its initial PowerShell control.
An independent nine-second launcher delay reproduces a false failure of the
old eight-second outer watchdog. Commit `3cf6974b` separates bounded PowerShell
startup (30 seconds) from the eight-second compiler watchdog, starting the
latter at an explicit fake-compiler entry marker. Another control proves an
unbounded compiler still fails after entry. All 20 POSIX/PowerShell methods
pass locally with the real PowerShell executable; new remote execution is
pending. The original CI log alone did not identify startup as its cause.


### Shared WASI parameter parser (2026-09-11)

The first remote primitive-contract checkpoint fails the unikernel compiler
and swarm gates with `inttoptr i8* nocapture nofree %a0 to i8*`. An independent
IR fixture reproduces that exact LLVM assembly error. The shared rewriter
(imported by both wasmbuilder and nurlapi) now extracts a balanced LLVM type
prefix and splits only top-level declaration parameters. Parameter attributes,
varargs and trailing function attributes cannot enter operand types. Nested
aggregate/function-pointer types and quoted identifiers retain their syntax.
This does not establish ABI adaptation for arbitrary LLVM types/address spaces.

The focused leak control also reproduces a preexisting 1,008-byte allocation
leak per rewrite: the initialized parameter-code string was replaced without
freeing it. That replacement now releases its old value. The permanent
`tools/tests/test_wasi_ir.py` compiles the public rewriter control with
ASan/UBSan/LSan, requires clean stderr and assembles its output for wasm32.
It passes with zero leaks; the sanitizer workflow runs it.

The existing package gate passes **18 controls**: all 16 native/Wasmtime corpus
pairs match exit and output, the IR assertions pass, and the library API builds
Wasm successfully. The real `wasmc_gate.sh` builds nurlc.wasm and runs it inside
the QEMU unikernel; all **eight programs produce byte-identical IR** to the
native compiler. Evidence is `wasm-attrs-*` under ignored `build/v1-hardening/`.
The end-to-end gates use a normal shared toolchain rebuilt after all arithmetic
sanitizer checks finished; isolated IR leak tests compile their own runtime.


The swarm appliance gate also passes both execution paths: its guest joins
the host census, the expression kernel returns 332833500, and the host-compiled
Wasm kernel returns 328350 when executed in-process by the guest. Cold start
to the first expression answer is nine seconds on this TCG run; this is a local
measurement, not a performance promise. No Wasm half was skipped.

### MinGW cross-link CI scheduling (2026-09-11)

The msvcrt C-runtime cross-link gate moves to a separate Ubuntu 24.04 job;
it requires no compiler bootstrap or NURL corpus. A preinstalled distro MinGW
compiler is reused, otherwise a bounded four-minute prerequisite step installs
it with finite network retries/timeouts. An explicit executable check prevents
a missing prerequisite from becoming the script's optional local skip. The
main compiler container now performs no per-run apt installation. The full
runtime cross-compiles and links locally with `x86_64-w64-mingw32-gcc`;
workflow YAML and changed shell syntax pass validation. Remote execution of the
new job remains required. This isolates the observed package-install stall
without dropping the msvcrt check or increasing the compiler job's budget.

### Block-expression bindings and the escape they opened (2026-09-11)

`spec/grammar.ebnf` has said since v1 that a binding's initialiser is an
expression (`let_stmt = ':' '~'? type? IDENT expr`) and that a block is one
(`block_expr = '{' stmt* '}'`, "block used as expression, yields last value").
The assignment path honoured that — `= x { 7 }` stores 7 — but the binding
path did not. It skipped the initialiser token by token up to the FIRST `}`
and returned `undef` without ever defining the name. Three consequences, all
silent: the declaration vanished, so a later use reported an undefined
identifier at the USE site; an unused binding compiled clean with nothing
bound; and because the scan did not balance braces, a nested block ended it
early and the remainder of the statement was re-parsed as ordinary statements.
Nothing in the tree used the shape, so nothing failed — the corpus, the
stdlib and every package are free of it.

The initialiser now goes through the ordinary expression path, where
`gen_expr` already dispatches a leading `{` to `gen_block_expr`. An empty
block, or one whose tail statement yields nothing, is the ordinary "no value
to bind" rejection; that diagnostic's wording no longer claims a block never
yields a value.

Opening the path exposed a second hole one level down. A `:` binding normally
cannot name anything declared deeper than itself, so `bck_esc_let` recorded a
referent depth without ever comparing it — only `bck_esc_assign` compared.
A block-expression initialiser is exactly the exception: a closure that
captures a block-local `: ~` multi-field struct holds a pointer into the
block's frame (docs/MEMORY.md §2.3), and binding it outside the block dangles
precisely as assigning it there does. `bck_esc_let` now applies the same
comparison and the same wording in the `:` voice.

Evidence. `block_expr_binding.nu` binds through a tail value, through
statements plus a tail, through a nested block initialiser, through a call
tail, through an outer binding read, and — the control for the escape case —
through a closure over a FUNCTION-level `: ~` struct, which is legal and runs.
`diag_block_binding_escape.nu` is the rejection; `diag_block_binding_void.nu`
is the empty-block rejection. Ownership traffic through the new path was
checked separately under ASan+LSan with leak detection on: an owned string as
the tail value, one bound inside the block and handed out, one with a second
owned local that must still be dropped at block exit, nested block
initialisers, and a block initialiser allocating inside a loop — all correct
values, zero leaks, zero sanitizer findings. `^`, `;` defer and `break` inside
a block initialiser behave as the spec describes (return from the function,
run at function exit, leave the loop). The tree's other unbalanced token skip,
the generic parameter list in `scan_fn_sigs`, cannot swallow a body: an
unterminated `[` is rejected earlier by the type parser.

The full build passes with the bootstrap fixed point; the corpus is 981 PASS
/ 19 SKIP over 1000 inputs, and the 303 diagnostics the stdlib, packages and
examples produce are byte-identical before and after. The globals appendix is
regenerated.

### A01: computed divisors and shift amounts in the differential fuzzer (2026-09-11)

`gen.py` kept the integer fuzzer out of the undefined domain by making every
divisor and every shift amount a LITERAL. The arithmetic guards added earlier
today are emitted either way, but against a constant operand their compare is
constant too: nothing exercises the taken/not-taken decision at run time, and
`-O2` deletes the branch before the program is run. The generator now derives
half of them from an arbitrary sub-expression clamped into the legal domain —
`| 1 & x 63` is odd and in [1, 63], so it is neither 0 nor -1, and
`& x (width-1)` is in [0, width). The oracle models each clamp exactly, so a
guard that fires on a legal operand becomes a divergence rather than a silent
panic.

Verified on the emitted IR: with a computed divisor both guard branches are
live at `-O0` and compare against a loaded value; at `-O2` LLVM proves the
operand nonzero and not -1 and removes both, so the differential run also
checks that the fold preserves the answer.

### The ':' declaration parser's silent skips (2026-09-11)

A `:` at the top level introduces a struct, an enum or a global constant.
Four points in that parser advanced past a token they did not understand
instead of reporting it, and each could consume the declaration that
followed.

- A global constant with no value advanced one token and returned, defining
  nothing. The token it swallowed was the next declaration's `@`, so the
  report landed a line later as "unexpected 'main' at the top level" and
  suggested unbalanced braces. The declaration that was actually incomplete
  was never named.
- The same path skipped one token when the NAME slot held something else —
  which is exactly where a struct declaration whose `{ … }` body is missing
  arrives.
- A generic struct's `[ … ]` was followed by `skip_balanced`, which walks to
  the next `{` ANYWHERE in the file. `: S [ T ]` with no body therefore
  consumed the whole function after it, `main` included: the compiler exited
  0, emitted a module with no `main`, and the only report was the linker's
  `undefined reference to 'main'`, with no source location at all. An
  unterminated `[` was equally silent.
- A `:` followed by neither `|` nor a name skipped one token per turn.

Each now reports, names the declaration and the token found, and is anchored
at the declaration rather than at the token that revealed it — the
constant's name for a missing value, the type for the other three. This is
the same closure the top-level loop already had: it stopped silently
advancing past stray tokens precisely because an unbalanced brace could
slip a whole function past the parser.

Nothing in the tree relied on any of the four: every existing corpus input
passes unchanged beside the four new rejections
(`diag_const_missing_value`, `diag_const_missing_name`,
`diag_generic_struct_no_body`, `diag_colon_decl_junk`), and the stdlib,
packages and examples produce the same diagnostics they did before.

### A10: the formatting gate's inventory (2026-09-11)

`compiler/tests/nurlfmt_check.sh` opens by asserting that "every first-party
NURL source file is already in canonical form" and then checked five
hand-listed directories. The tracked inventory is 1,817 `.nu` files; the gate
saw 1,315 of them, `bench/` accounts for 38 deliberately excluded recorded
model outputs, and **464 first-party files were gated by nothing** —
`packages/`, `unikernel/`, `tools/` outside `tools/nurlfmt/`, `nurlapi/`,
`pttvoice/`. Eighteen of those had drifted out of canonical form.

The drift stayed small because `.githooks/pre-commit` has always used the
right rule — every staged `.nu` minus `bench/` — so anything touched since
the hook was installed was corrected on the way in. The gate and the hook
disagreed about what they were guarding; the eighteen are the files nobody
had staged since.

The gate now asks git for the inventory (`git ls-files '*.nu'` minus
`bench/`, with a filesystem fallback for an exported tree), which is the
whole point of an inventory gate: a directory added tomorrow is covered the
day it is committed, with no list to update. It reports 1,779 canonical
files.

Reformatting the eighteen was checked for meaning, not just for bytes: for
each file the formatted copy was written beside the original so its imports
still resolved, and both were compiled. Seven produce byte-identical IR; the
other eleven do not compile standalone (their vendored `deps/` are not in the
tree) and were left to the idempotence property alone. No file changed its
IR. The stronger IR-equivalence gate keeps its narrower tree on purpose — it
compiles a copy in a temporary directory, which only works for sources whose
imports resolve from the repository root.

The gate's failure message also pointed at `./tools/nurlfmt/fix.sh`, which
does not exist anywhere in the tree.

### A15: the release publishes the set it promises (2026-09-11)

`RELEASING.md` names four targets and calls exactly one of them —
FreeBSD — best-effort. The workflow enforced less than that. The publish
step attaches `artifacts/*.tar.gz`, `*.zip`, `*.sha256` and `*.minisig` by
glob, and its condition requires only `verify-ci` and the Linux matrix to
have succeeded; the comment beside it says plainly that the Windows job "is
a required-to-build job (its failure reds the run) but neither is a hard
publish gate". A failed Windows leg therefore published a release with no
`.zip`, and the one-line PowerShell installer 404s for that version — the
installers compute an archive name by rule and cannot fall back.

`tools/check_release_artifacts.sh` now runs immediately before the publish
step, with the tree checked out first so it exists (the release job had no
checkout at all, and `actions/checkout` would have deleted the downloaded
artifacts had it run after them). It requires both Linux archives and the
Windows zip, warns for the best-effort FreeBSD archive, requires each
present archive to be non-empty and to carry a `.sha256` whose first field
matches the file — read exactly the way the installers read it, so the
Windows leg's CRLF checksum file parses — and, when signing ran, a
`.minisig` beside every archive. An archive matching no known target name
fails the release: the four target names live in the RELEASING.md table,
the workflow matrix, the installers' name rule and this gate, and this is
what notices when one of them moves.

`tools/tests/test_release_artifacts.py` is eleven controls over that gate:
the complete set, a missing required target (named in the message), a
missing best-effort target (a warning, not a failure), an archive with no
checksum, a checksum that does not match, a Windows-style CRLF checksum
file, an empty archive, a signed release missing one signature, an unsigned
release not demanding any, an unknown target name, and a missing directory
as an environment error. They run in the ordinary CI job — the gate needs
no toolchain.

This closes the "mandatory target artifact gates" half of A15. Pinned tool
downloads, installer integrity beyond the archive set, and state-preserving
failure controls remain open; note that `tools/get-nurl.sh` already
verifies the checksum fail-closed, verifies the minisign signature
fail-closed when `minisign` is present, refuses to install into `/`, `$HOME`
or a non-NURL directory, and removes only the toolchain's own paths so an
upgrade cannot log the user out or delete their model cache. What it does
not do is stage the unpack: it removes the old toolchain before extracting,
so an extraction interrupted after verification leaves a broken prefix that
only a re-run repairs.

### The compiler job's budget, and two serial gates (2026-09-11)

The Linux compiler job was cancelled 15 minutes in, during the strict-arity
gate. A cancelled job is the worst shape a CI failure can take: no gate
reported anything, so the log says only that time ran out. The step timings
show it was not a regression but a budget with no room. The previous green
run of the same job totalled 843 s against a 15-minute limit — 57 seconds of
headroom — with 306 s in the strict-arity gate and 258 s in `build.sh`. The
next run drew a slower machine, both grew about a quarter, and the sum
crossed the line.

Both gates spent nearly all of that on process startup: one compiler (or
formatter) invocation per file, strictly serially, over the tracked tree.
Each file is compiled alone and only its own diagnostics are read, so the
work is embarrassingly parallel. Running it under `xargs -P` takes the
strict-arity gate from 12 min 20 s of CPU to 1 min 20 s of wall time on a
12-core machine; the formatting gate is now floored by its single largest
file (`nurlfmt --check compiler/nurlc.nu` alone is 23 s), which no amount of
parallelism can shorten.

Raising the limit was the other option and the worse one: the job would have
kept spending six minutes on startup overhead, and the next slow runner
would have found the new line instead.

The strict-arity gate also took its file list from six hand-named
directories, which left `unikernel/` and `pttvoice/` unchecked — the same
defect A10 found in the formatting gate. It now uses the tracked inventory
minus `bench/` and vendored `deps/` copies: 1,407 files, up from 1,374.
Both gates were re-verified against a deliberate offender: each still exits
1 and names the file.

### Three more declarations that vanished (2026-09-11)

The sweep that found the `:` parser's silent skips was run again over the
other declaration kinds — `@`, `&`, `%`, `$` — with one invariant: a file
that still declares `@ main` must either fail to compile or emit `main`.
Fifteen spellings, three findings, and one form that looked wrong and is not
(`$ \`path\` name` is the documented import alias, `import_decl = '$' STR
IDENT?`).

**A generic function with no body swallowed the next declaration.** The
template pre-scan walks from the return arrow to the body's `{`, and walked
straight through `@ main → i {` to land on main's body, which
`skip_balanced` then consumed as the template. The compiler exited 0,
emitted a module with no `main`, and the only report was the linker's
`undefined reference to 'main'` — no source location at all, the same shape
`: S [ T ]` produced. A closure type is always parenthesised (`( @ v )`), so
an `@` at paren depth zero cannot be part of a type; the walk stops there
and reports. The type-parameter list's own walk also had no EOF guard and
now has one.

**A value-returning function with an EMPTY body returned garbage.**
`@ f → i {}` emitted `ret i64 undef` and compiled clean — `main` included, so
an empty `main` returned an undefined exit status. The fall-off battery does
check for a body that ends without a value, but it reads
`nurl_get_last_type`, and `gen_block_ret` never typed an empty block: the
type left over from whatever ran last anywhere was still there, and it was
usually i64, which the check liked. `gen_block_expr` has typed `{}` as void
all along and says why; `gen_block_ret` now does the same, and the fall-off
message mentions an empty body among the shapes that yield nothing. The
error is anchored at the body's `{` rather than at `:0:0:`, which is what a
missing statement anchor printed.

**Two parameters could share a name.** `@ f i a i a → i` lowered to
`define i64 @f(i64 %a, i64 %a)`. LLVM requires distinct argument names, so
clang rejected the module with `redefinition of argument '%a'`, a line
number into generated IR and no NURL source location — and the body could
only ever reach one of the two. The parameter roster is the one place that
sees them all, so both the `@` path and the closure path check it there.

`diag_generic_fn_no_body.nu`, `diag_empty_body_value_fn.nu` and
`diag_duplicate_param_name.nu` are the rejections. Every existing corpus
input passes unchanged.

The same sweep at STATEMENT level — each snippet placed inside a `main` that
must still print, the program compiled, linked and run — found one more.
A `??` with an empty arm block dispatched nothing and then emitted its merge
label immediately after a non-terminator instruction: invalid IR, reported
by clang as "expected instruction opcode" at a line number in generated text
with no NURL source location. An enum scrutinee never reached it (the
non-exhaustive check fires first), nor did an option or result; an integer
or string one did. A match with no arms is now a rejection anchored at the
`??` itself (`diag_match_no_arms.nu`). The neighbouring shapes were already
covered: an empty select says so, an empty ternary in value position is the
ordinary no-value binding error, and an empty defer or closure body is
legal and harmless.

All nine defects shared one shape: a construct the grammar allows, handled
by an ad-hoc token skip rather than by the path that parses it, with the
skip running past the end of the declaration. The corpus pins each fix with
its own rejection fixture; `tools/tests/test_declaration_forms.py` pins the
CLASS. Twenty-six declaration forms and nine statement forms are checked
against the one invariant that binds them — a file that still declares
`@ main` either fails to compile, or the module it produces defines main —
so a new parser path that skips instead of reporting fails there even in a
spelling nobody thought to write a fixture for. It runs in the compiler job
and takes under a tenth of a second. Its own negative control was run: with
one expectation deliberately inverted the suite fails and names the form.

Extending that sweep into expression position found a tenth defect of the
same family. `~ e k { … }` — a foreach whose collection is neither a slice
nor a Vec — took the element type by slicing fixed offsets out of the
`{ T*, i64 }` carrier shape. On an `i64` those offsets yield an EMPTY type,
and the loop emitted `alloca `, `getelementptr , `, `load , ` and an
`extractvalue` on a non-aggregate. Invalid IR with nothing on stderr at all:
clang reported "expected type" at a line number in generated text, which is
no report at all. Iterating anything but those two carriers is now a
diagnostic that names the type it was given
(`diag_foreach_not_iterable.nu`), and both foreach shapes joined the form
table.

### A13: the pre-registered runtime surface was the unchecked one (2026-09-11)

A NURL function's call sites are type-checked. An `&`-declared FFI symbol's
call sites are type-checked — arity, float against integer, pointer against
integer, aggregate against scalar, each with its own diagnostic. The
C-runtime surface the compiler pre-registers — `nurl_print`, `nurl_str_int`
and the 117 others `stdlib/core/builtins.nu` documents, the functions in
every NURL program — was checked not at all. It was registered with a
RETURN type only, so the call path had nothing to compare against:

    ( nurl_print )              → call void @nurl_print()
    ( nurl_print `a` `b` )      → call void @nurl_print(i8*, i8*)
    ( nurl_print 1.5 )          → call void @nurl_print(double 1.5)
    ( nurl_print 5 )            → call void @nurl_print(i64 5)

All four compiled. None is valid against
`declare void @nurl_print(i8* nocapture nofree)` — and under opaque pointers
none is an IR error either: the call carries its own signature, LLVM's
verifier accepts it, clang assembles it, and the ABI mismatch arrives at run
time. `( nurl_print 5 )` segfaulted dereferencing 5. A trait impl whose
return type disagreed with its trait reached the same place by a different
road: `( nurl_print ( show 1 ) )` passed an i64 to the pointer parameter.

The signatures were never missing. `emit_header` emits a `declare` line for
every one of these symbols, and `__emit_rt_decl` sees each line. Reading the
parameter list out of it fills the same side-tables the FFI path fills —
`<name>__ffi_params` and `<name>__arity` — so a builtin call is now checked
by exactly the code that checks an `&` declaration, with no second table to
drift and nothing hand-written to keep in sync. The one variadic builtin,
`printf`, keeps its existing hand-written registration and is left without
an arity.

One gap remained after that. An integer in a pointer position is converted
with `inttoptr` rather than rejected, deliberately: a handle held as `i64`
is how NURL passes a C pointer around, and on wasm the call's signature must
match the declaration or `wasm-ld` emits a trapping stub. But a handle
arrives in a register and a literal does not, so an integer LITERAL in a
pointer position is now rejected — except `0`, which is the null pointer.
That is what closes `( nurl_print 5 )`.

Evidence: the bootstrap reaches its fixed point with the check active, which
is the compiler's own 35,000 lines of builtin calls agreeing with the
declares. The corpus passes 989 of 1,007 inputs with 19 skips. The 303
diagnostics the stdlib, packages and examples produce over 719 files are
byte-identical to before, so nothing in the tree was relying on the
looseness. `diag_builtin_arity.nu`, `diag_builtin_arg_type.nu` and
`diag_builtin_literal_pointer.nu` are the rejections, and seven builtin-call
forms joined `tools/tests/test_declaration_forms.py`.

### The write side of a field access (2026-09-11)

`gen_member` rejects a read of a field the struct does not have, and its
comment says exactly why: the index lookup returns an empty string,
`nurl_str_to_int ""` is 0, and the access silently reads field 0 — "a
miscompile". The write side kept that bug. `= . p nofield 5` stored into
field `x`, and the field's empty TYPE printed `store  5, * %r6` with no
types at all: emitted with status 0, rejected only by clang, against
generated IR with no source location.

Both halves now use the same check and the same wording. The nested-path
writer (`= . . o a b v`) already had it; only the single-dot by-value path
did not. The corpus passes 990 of 1,009 inputs, and the tree's 303
diagnostics are unchanged.

### A token deleted from every corpus program (2026-09-11)

A second sweep, mechanical rather than hand-written: take a program that
compiles, blank one token, and require the compiler to answer — reject the
file, or emit the `main` the source still declares. Deletion is the right
mutation because it produces the truncations a human actually writes (a
missing brace, a missing bracket) rather than random noise, and the
invariant needs no oracle. Two earlier attempts died on my own carelessness:
the first ran against `build/nurlc` while a build replaced it, the second had
its mutants deleted mid-run, and one mutant was committed by accident because
they were written beside the originals. Run it against a private copy of the
compiler with the corpus copied out of the tree.

Forty programs, roughly 80,000 mutants, one finding — and it is the kind
only a machine finds. Deleting the `]` from a call's generic type-argument
list (`( vec_new [i )`) HUNG the compiler: the walk that collects the type
arguments ended only on `]`, so at end of input it spun on TT_EOF forever.
That is the same shape `diag_generic_struct_unclosed.nu` exists for, in a
construct nobody had thought to truncate. EOF now ends the walk and the
existing `expect` reports it (`diag_call_targs_unclosed.nu`).

One finding in 80,000 mutants is also a result about the parser: every other
truncation of every other construct in those forty programs was already
answered.
