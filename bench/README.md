# NURL benchmarks

Twenty-five benchmarks. Fifteen of them in five languages — **NURL**,
**C**, **Rust**, **Node** and **Python** — and ten in NURL, C and Rust:
five language-feature rows (`safe_record_array`, `payload_state_machine`,
`captured_closure_queue`, `dynamic_method_mix`, `csv_table_pipeline`) and
five cryptographic kernels (`chacha20`, `poly1305`, `blake2b`, `sha512`,
`x25519`); one algorithm per benchmark, one runner, one report. A row is timed
only when all of its implementations print the same line, so no cell can
be fast by computing something else.

Two runners read the same roster: `bench.sh` compares languages on the
native target, and [`wasmbench.sh`](#the-wasm-suite--wasmbenchsh) compares
native against `wasm32-wasi` on two runtimes.

```sh
./build.sh                 # build/nurlc + stdlib/runtime.o must exist first
./bench/bench.sh           # the whole suite (~10 min; Python is the long pole)
./bench/bench.sh --quick   # one run per cell, for a smoke test
./bench/bench.sh --bench lcg --bench sieve
./bench/bench.sh --stdout  # print the report, write nothing
./bench/bench.sh --scale 100   # every benchmark does 100x the work (NURL/C/Rust)
BENCH_SCALE=100 ./bench/bench.sh   # the same, from the environment
```

`--scale N` (default `$BENCH_SCALE`, else 1) is the workload multiplier
[described under the wasm suite](#the-wasm-suite--wasmbenchsh): x1 is the
published contract, and a xN run is NURL / C / Rust only — the Node and
Python peers have no multiplier — written to `RESULTS-xN.md` and
`results/xN.json` beside the x1 report, never over it. `bench.yml` takes
the same `scale` input on a manual run; push and tag runs are always x1.

It writes two files:

| File | For | Contents |
|---|---|---|
| [`results/latest.json`](https://github.com/nurl-lang/nurl/blob/bench-data/bench/results/latest.json) | machines | Run times, compile times, checksums, host and toolchain versions. The landing page's benchmark table is generated from this file at publish time by `tools/gen-bench-table.mjs`. |
| [`RESULTS.md`](https://github.com/nurl-lang/nurl/blob/bench-data/bench/RESULTS.md) | humans | The same run rendered: run times, compile times, the correctness gate, and the process-start-up floor. |

Both are refreshed by [`.github/workflows/bench.yml`](../.github/workflows/bench.yml)
on a fixed `ubuntu-latest` runner — weekly, and on demand from the Actions
tab. Those runs commit the refreshed files, which is how nurl-lang.org's
numbers stay honest without anyone typing a figure into HTML.

## On Windows — `bench.ps1`

[`bench.ps1`](bench.ps1) is the same suite, same manifest, same protocol,
for a Windows box. It needs `build.bat` to have run, plus clang, rustc,
node and a Python the `py` launcher can find.

```powershell
build.bat --no-tests               # build\nurlc.exe + stdlib\runtime.o
pwsh bench\bench.ps1               # the whole suite
pwsh bench\bench.ps1 -Quick        # one run per cell, for a smoke test
pwsh bench\bench.ps1 -Bench lcg,sieve
pwsh bench\bench.ps1 -Stdout       # print the report, write nothing
pwsh bench\bench.ps1 -Scale 100    # x100, NURL/C/Rust (or set BENCH_SCALE)
pwsh bench\wasmbench.ps1 -Quick    # the wasm suite, see below
```

It writes [`results/latest-windows.json`](results/latest-windows.json) and
`RESULTS-WINDOWS.md`, deliberately **not** the two files above: those are
the Linux CI numbers the landing page publishes, and a local Windows run
must not be able to end up in that table by accident.

[`wasmbench.ps1`](wasmbench.ps1) is the matching port of `wasmbench.sh`
(below): same ten cells per row, same gate, `-Scale`, `-NwasmAllLangs`,
writing `results/wasm-latest-windows.json` and `WASMRESULTS-WINDOWS.md`. It
builds `wasmbuilder` and `nwasm` through `nurl.bat` and additionally needs
zig, `rustup target add wasm32-wasip1` and `wasmtime`. It has been run
under pwsh on Linux, not yet on a Windows host — treat its first Windows
run as the test of the Windows-only branches (the `nurl.bat` package build
and the `-lwinhttp` native link).

## The contract

Every implementation of a benchmark:

1. takes no arguments and reads no input except `data.json` where the
   benchmark says so;
2. computes a checksum and **prints exactly one line** — that value in
   decimal, masked to 63 bits so the languages without an unsigned
   64-bit type can print it too;
3. prints nothing else.

`bench.sh` runs all of a row's implementations, compares their lines,
and only then times them. A mismatch fails the run rather than producing a table with a
plausible-looking wrong cell in it.

The `// benchmark-contract:` line at the top of each source file is the
algorithm's parameters in one line — seed, iteration count, constants —
so the files can be checked against each other by reading, not just by
running.

## The roster

Defined in [`manifest.tsv`](manifest.tsv), which is what both `bench.sh`
and `perfstat.sh` read.

| Benchmark | Shape |
|---|---|
| `lcg` | Loop-carried mul/add/shift/xor dependency the unroller cannot compose |
| `packet_classifier` | A data-dependent 50/50 branch the predictor cannot learn |
| `ring_write` | Dependent store per iteration plus address computation |
| `histogram_bins` | Read-modify-write at a data-dependent index |
| `prefix_scan` | Store-bound fill, then a serial load/add dependency chain |
| `binary_search` | Pointer-chasing: each load address depends on the last compare |
| `sort_window` | Branchless compare/exchange mill over a 64-byte window |
| `bloom_filter` | Four unpredictable loads per query over a 2 KB working set |
| `hash_join` | Cheap Bloom early-out plus a rare, branchy join path |
| `sieve` | Irregular-stride byte writes, then one linear scan |
| `fib` | The call/return path: ~15M calls after LLVM turns one recursion into a loop |
| `collatz` | Control-flow-heavy inner loop with no array at all |
| `matmul` | Triple-nested loop, flat indexing, column-strided reads |
| `json_parse` | Allocator pressure, string handling, recursive descent |
| `nbody` | IEEE-754 doubles: sqrt and divide throughput, the FPU rather than the ALU |
| `safe_record_array` | By-value records in and out of a bounds-checked Vec: aggregate layout, pass/return, moves |
| `payload_state_machine` | Payload-bearing enum, option and result matches; an owned String on the error exit |
| `captured_closure_queue` | Indirect calls through closures of five capture shapes, the queue refilled as it runs |
| `dynamic_method_mix` | Trait-object dispatch: a vtable load and two indirect calls per step |
| `csv_table_pipeline` | The stdlib CSVTable hot path: quote-aware parse, cell index, zero-copy views |
| `chacha20` | 32-bit add/rotate/xor rounds; NURL calls stdlib `chacha20_xor` (v128 / v256 lanes) |
| `poly1305` | Serial 64x64→128 multiply/carry chain through the accumulator, radix 2^64 |
| `blake2b` | 64-bit add/xor/rotate G mixes with SIGMA-permuted message gathers |
| `sha512` | 80-round 64-bit serial compression chain plus the message schedule |
| `x25519` | Montgomery ladder over GF(2^255−19): radix-2^51 128-bit field multiplies |

No two rows measure the same shape. That is a deliberate property, and
the reason the previous `stream_lcg` kernel is gone: it was `lcg` with
32-bit constants, so it made the table longer without making it say more.

### The language-feature rows

The fifteen five-language rows are kernels over integers and doubles;
none of them holds a record, matches a sum type, calls through a pointer
or parses text into a structure. The five rows after `nbody` each measure
one of those mechanisms, in **safe** NURL — no `unsafe`, no raw pointer,
where the kernels above use raw blocks — because that is the code a NURL
program is mostly made of:

| Row | Dimension it adds | Nearest existing row |
|---|---|---|
| `safe_record_array` | A `Vec` of 4096 four-field records: two records read **by value**, passed to a function that returns a two-field record by value, a record returned by value and stored back, half the steps an exchange of two whole records — all through the bounds-checked `vec_at` / `vec_put` | `nbody` (records, but an `unsafe` struct-of-arrays) |
| `payload_state_machine` | Events decoded into a payload-bearing enum, matched by a step that returns `!St Fault` (an option lookup inside); on the error exit (1 event in 68) the fault carries an **owned String** the handler reads and drops | `collatz` (branchy control flow, but no data in the branches) |
| `captured_closure_queue` | A queue of 16 `( @ u64 u64 )` closures made by five constructors whose environments differ (one, two or three u64s, a captured `Vec`, a record); an input-chosen one called per step, every 256th step a fresh closure replacing one | `fib` (a direct call; nothing else calls through a pointer) |
| `dynamic_method_mix` | 64 `%Op` trait objects of four struct types (one owns a `Vec`), types and call order both input-chosen; a vtable load and two indirect calls (`apply`, `weight`) per step | `captured_closure_queue` (one pointer beside its environment, not a table of them) |
| `csv_table_pipeline` | The stdlib's own `CSVTable` (stdlib/ext/csv.nu) end to end: a 100k-row, 4.29 MB RFC 4180 document with quoted fields, `""` escapes and an embedded line break, copied and parsed four times, then five columns read per row through zero-copy `csv_table_view`s and aggregated per city | `json_parse` (the other stdlib parser, and the other allocating row) |

All five draw their input from the MMIX LCG `lcg` uses (`x >> 33` as the
draw), so every index, callee and branch is data-dependent, and fold
their state into a 64-bit FNV-style checksum. `BENCH_SCALE` multiplies
the step count (the pass count for `csv_table_pipeline`). At x1 each
runs 40–190 ms native, 30–150 times the process floor.

C and Rust carry the same algorithm, sizes and semantics; where a
language has no such construct, the peer spells out what the others
lower to, and the header says so:

* **C has no closures, sum types or trait objects.** Its closures are
  `{ function pointer, malloc'd environment }` pairs, its trait objects
  `{ data pointer, vtable pointer }` pairs over a static table of
  function pointers, its enum, option and result tagged structs, and its
  fault message a malloc'd buffer. Rust uses `Box<dyn Fn(u64) -> u64>`,
  `Box<dyn Op>`, enums, `Option`, `Result` and `String`.
* **C does not bounds-check.** `safe_record_array` is the row where that
  shows: its C column is the unchecked floor the two checked languages
  are measured against (Rust's checked indexing lands on it).
* **Inlining is allowed everywhere.** No language is told not to inline
  `mix` / `bump` or the step function, so after optimisation those rows
  measure the record and payload traffic, not a call sequence. The
  indirect calls in the closure and trait-object rows cannot be inlined
  — that is their point.
* **CSV: neither C nor Rust has a CSV reader in its standard library**
  (and this suite builds with bare `rustc`, no crates), so both carry the
  CSVTable layout by hand: one content buffer, an (offset, length) pair
  per cell with a negative offset into a separate buffer for cells with
  `""` escapes, a row-start / row-length index, the header row kept
  apart, the same quote, separator and end-of-row rules as
  `__csv_parse_content`, and a view accessor that bounds-checks
  (row, column). The one difference of method: they scan an unquoted
  cell byte by byte, the stdlib 16 bytes at a time (`nurl_scan_byte3`,
  SSE2).

What the rows showed when they landed (WSL2 on an i7-11850H, best of 7):

| ms | NURL | C | Rust |
|---|---:|---:|---:|
| `safe_record_array` | 51.7 | 42.6 | 42.9 |
| `payload_state_machine` | 66.1 | 53.0 | 54.5 |
| `captured_closure_queue` | 179.0 | 60.4 | 72.9 |
| `dynamic_method_mix` | 79.9 | 77.4 | 76.1 |
| `csv_table_pipeline` | 71.7 | 59.7 | 62.0 |

* `captured_closure_queue` is 3x C because NURL **copies the closure's
  environment on every call**: `vec_at` of a closure element returns
  `nurl_closure_clone` of the stored env (its body's `. data idx` is
  returned as an owned copy), and the binding drops it after the call —
  14.05M runtime allocations for 10M calls (one per call, three for the
  closure that captured a Vec), `nurl_alloc` + `nurl_free` 32 % of the
  profile, `__cenv_clone` of the Vec-capturing closure another 6 %. C and
  Rust allocate only on the 39k refills. A trait object read the same
  way is lent, not copied, which is why `dynamic_method_mix` is at par.
* `payload_state_machine` makes two runtime allocations per fault (the
  String and its buffer) where C and Rust make one.

#### `csv_table_pipeline` — throughput, memory and the hot path

Phases are separated by running the same binary with the row scan
removed and with no passes at all (`perf stat -r 5`, user-mode cycles):

| | NURL | C | Rust |
|---|---:|---:|---:|
| whole run, wall | 70.8 ms | 58.2 ms | 63.5 ms |
| generate the document only | 6.8 ms | 6.2 ms | 5.5 ms |
| copy + parse, per pass (wall) | 10.5 ms · 408 MB/s | 9.1 ms · 473 MB/s | 10.4 ms · 415 MB/s |
| copy + parse + scan, per pass (wall) | 16.0 ms · 268 MB/s | 13.0 ms · 330 MB/s | 14.5 ms · 296 MB/s |
| copy + parse, user cycles (4 passes) | 139.5M | 141.3M | 149.2M |
| view + aggregate, user cycles (4 passes) | 95.6M | 71.0M | 85.1M |
| kernel cycles (whole run) | 80.4M | 39.1M | 41.5M |
| page faults | 25,516 | 11,136 | 11,549 |
| peak RSS | 26.6 MB | 30.3 MB | 32.3 MB |
| allocations | 128 (runtime count) | 42 malloc + 120 realloc | 56 malloc + 163 realloc |
| bytes requested from libc | 331 MB | 177 MB | 181 MB |

The parser itself is not the gap: in user mode NURL parses at C's cost
and faster than Rust (the SSE2 cell scan pays for itself even on
six-byte cells), with ten allocations a table as csv.nu documents. The
gap is in two places. **The kernel**: twice C's page faults and kernel
time, 56 % of the faults taken inside `realloc`'s copy as the cell index
grows (22 % in C) — growth moves NURL's buffers to fresh pages where C's
grow in place — and the cell index's `vec_reserve` is passed
`len + 512` where the API takes the *additional* count, so it reserves
twice what it needs and grows to 32 MB where 16 MB holds it (134 MB of
the extra 154 MB requested; corrected alone, it changes neither the
faults nor the wall time). **The accessor**: `csv_table_view` re-validates
(row, column) in both `__csv_cell_off` and `__csv_view_len` and reads
the table through the handle twice per call, 1.35x C's cycles over the
same five views a row. The NURL profile: `_nurl_main` 53 % (LTO inlines
the whole CSVTable path into it; its hottest instructions are the
separator loop's `cmp $0xa` and the `nurl_scan_byte3` SSE2 compare),
page-fault entry 8 %, `memmove` 6 % (the copy and realloc growth),
other kernel memory management ~10 %, `memcmp` 3 % (the city match).

### The crypto rows

The last five rows test **the standard library**, not a hand-written
kernel: each `.nu` file is a short driver around the stdlib's own
implementation — `chacha20_xor` and `poly1305_mac`
(stdlib/std/chacha20poly1305.nu), `blake2b512_pure`
(stdlib/std/hash_blake2b.nu), `sha512_pure` (stdlib/std/hash_sha512.nu)
and `x25519` (stdlib/std/x25519.nu) — because that code is what a NURL
program doing TLS, Noise or age actually runs. C and Rust have none of the
five in their standard libraries, so their files carry the algorithm
written out by hand, line for line the same in both, and in the
formulation the stdlib uses for Poly1305 — radix 2^64, four 64x64→128
products a block, as OpenSSL's and BoringSSL's scalar code has it. For
X25519 they carry the TweetNaCl ladder over the donna-c64 field (radix
2^51) and the ref10 inversion chain, with native 128-bit products; the
stdlib has since moved to four 64-bit words (ADX blocks where present)
and a divstep inverse. ChaCha20
is the one deliberate difference: the stdlib runs it on `v128` lanes
(`v256` lanes in its x86-64-v3 clone), C and Rust carry the scalar RFC
rounds (the stdlib's own big-endian fallback), and that gap is what the
row shows.

Every workload is chained — a digest feeds the next message, a tag the
next key, an X25519 result the next scalar — so nothing can be hoisted,
and every source names its RFC/FIPS test vector. `x25519` is RFC 7748
§5.2's iteration test, so its x1 output is the RFC's own 1000-iteration
value. Node and Python are `n/a` on these rows (manifest column 4): a JS
or Python port of a 64-bit cipher would measure BigInt, not the language.

`nbody` is the one row not defined over integers, and it is here for two
reasons. It is the only one whose critical path runs through the FPU's
long-latency, non-pipelined sqrt and divide units rather than the integer
ALU — nothing else in the roster exercises that hardware, or NURL's `f`
codegen, at all. And it is the only row where JavaScript competes on even
terms: see below.

### How the languages are held to the same algorithm

Nine of the fifteen five-language rows are defined over 64-bit unsigned
integers, which two of the five languages do not have:

* **Python** has arbitrary-precision integers, so every step masks
  explicitly. Always exact, and slow — that is the measurement.
* **JavaScript** has no 64-bit integer at all. Where the algorithm
  genuinely needs 64 bits (`lcg`, `bloom_filter`, `hash_join`) the port
  uses `BigInt`; where 32 bits suffice it uses
  Numbers with `Math.imul`, which is exactly defined as the wrapping
  32-bit multiply. Each file states which and why in its header.

The rule is *each language at its fastest exact representation*, and the
checksum gate is what keeps "fastest" from drifting into "different".

`nbody` is the counterweight to those two bullets. It is defined over
IEEE-754 doubles, which is precisely the type JavaScript *does* have —
its single numeric type is the double, and `Math.sqrt` is the same
correctly-rounded hardware instruction the compiled backends emit. So
Node runs the identical arithmetic there with no representation tax, and
lands around 2× C rather than the 30–50× the BigInt rows cost it. That
matters for reading the whole table: a suite in which one language loses
every row by two orders of magnitude invites the suspicion that the
corpus was chosen to make it lose, and the cheapest way to answer that is
to include the row where it doesn't.

Bit-exactness across five languages is not free, and `nbody` holds three
lines to get it:

* **No `-ffast-math`, and no multiply-add contraction.** Fusing
  `dx*dx + dy*dy` into an fma is *more* accurate than the unfused form,
  which is exactly the problem: JS and Python cannot fuse and would
  disagree in the last bits. This is moot as the suite is built today —
  the baseline `x86-64` target has no FMA instruction and `bench.sh`
  sets no `-march` — so if a `-march=` flag is ever added, that row needs
  an explicit `-ffp-contract=off`. Its header says so.
* **The same operation order in all five files.** IEEE addition is not
  associative, so a reordered sum is a different number.
* **The same data layout in all five files** — struct-of-arrays. An
  array-of-structs C port is ~6% faster (274.0M retired instructions
  against SoA's 290.1M), but mixing the two layouts would have had the
  row reporting a 6% spread that has nothing to do with floating point.
  Pinned to one layout, the three compiled backends land within 3.5% of
  each other on instruction count. SoA is the layout that is natural in
  all five at once: an AoS Python port would be a list of objects and
  would measure the interpreter's object model instead of its float path.

What is left is IEEE-754 exact by specification — `+`, `-`, `*`, `/` and
`sqrt` are all correctly rounded — so five conforming implementations
evaluating the same expressions in the same order must agree to the bit.
The row prints the bit pattern of the final energy, so the gate asserts
exactly that.

## What is **not** in the timing suite

* `brackets`, `csv_sum`, `histogram`, `quicksort`, `rot13` and `words`
  are the held-out corpus for the generation-accuracy study in
  [`genacc/`](genacc/) and the token study in
  [`TOKEN_EFFICIENCY.md`](TOKEN_EFFICIENCY.md). Their workloads are a
  single short string: they measure process start-up, not a language.
  [`verify.sh`](verify.sh) is their cross-language correctness gate.

  `genacc/` is self-contained: each task's prompt *and* its expected
  output are pinned in [`genacc/tasks.json`](genacc/tasks.json), and the
  scorer never reads the files here. So a benchmark that appears in both
  places can hold a different workload in each — `matmul` is 256×256 in
  the timing suite (128×128 was too small to measure) and stays 128×128
  in the frozen genacc task, whose recorded model scores would otherwise
  stop describing the task they were measured against.
* `http_server.{nu,js}` + `rust_http_server/` are the HTTP-server peer
  benchmark, driven by [`run_http.sh`](run_http.sh) with `oha` as the
  load generator; results in [`HTTP_RESULTS.md`](https://github.com/nurl-lang/nurl/blob/bench-data/bench/HTTP_RESULTS.md). It
  measures requests per second, not wall clock, so it has its own runner.
  `run_http.sh --suite db` runs the same two servers' database endpoints
  — TechEmpower's `/json` `/db` `/queries` `/fortunes` `/updates` and
  HttpArena's `/async-db`, over [`http_db_schema.sql`](http_db_schema.sql)
  — NURL (packages/psql) against Rust (tokio-postgres), with a throwaway
  PostgreSQL pinned to cores of its own unless `DATABASE_URL` names one;
  results in [`HTTP_DB_RESULTS.md`](https://github.com/nurl-lang/nurl/blob/bench-data/bench/HTTP_DB_RESULTS.md). Both write their
  JSON bodies value by value with no tree in between (json.nu's streaming
  writer; serde's derive) and take text columns from the row without a
  copy; `/async-db`'s jsonb `tags` go through a parsed value on both
  sides (`Json`; `serde_json::Value`).
* `pq_compare.nu` + `rust_pq/` are the post-quantum crypto peer
  benchmark (ML-KEM, ML-DSA, SLH-DSA, SHAKE128 — pure-NURL stdlib vs
  pure-Rust RustCrypto), driven by [`run_pq.sh`](run_pq.sh); results in
  [`PQ_RESULTS.md`](https://github.com/nurl-lang/nurl/blob/bench-data/bench/PQ_RESULTS.md). `pq.nu` is the NURL-only variant of
  the same measurements with the scheme authors' reference-C and AVX2
  numbers recorded in its header.
* `tls_bench/` is the TLS peer benchmark — handshakes (full, resumed,
  per group and certificate, with server CPU split into crypto and the
  rest), the record layer, bulk throughput and the client side, NURL
  against rustls / aws-lc-rs, hyper and reqwest — driven by
  [`tls_bench/run_tls.sh`](tls_bench/run_tls.sh); results in
  [`tls_bench/TLS_RESULTS.md`](https://github.com/nurl-lang/nurl/blob/bench-data/bench/tls_bench/TLS_RESULTS.md) — an index of
  one report per CPU family of the runner pool, each led by a worst-first
  focus list. See [`tls_bench/README.md`](tls_bench/README.md).
* `stdlib_hotpath.nu` is a NURL-only profiling probe with no peers.

## The wasm suite — `wasmbench.sh`

[`wasmbench.sh`](wasmbench.sh) is the same corpus with one axis rotated.
`bench.sh` asks how fast NURL is against four other languages;
`wasmbench.sh` asks what **targeting wasm** costs, and what running that
wasm on **NURL's own runtime** costs:

```sh
./bench/wasmbench.sh                 # the whole suite (~15 min)
./bench/wasmbench.sh --nwasm-all-langs  # + C/Rust on the interpreter (~45 min)
./bench/wasmbench.sh --quick --bench lcg
./bench/wasmbench.sh --scale 100     # every benchmark does 100x the work
```

`--scale N` (default `$BENCH_SCALE`, else 1) multiplies every
benchmark's workload before it is compiled.
Each NURL, C and Rust source defines its multiplier once — `: u64
BENCH_SCALE 1`, `#define BENCH_SCALE 1ULL`, `const BENCH_SCALE: u64 = 1;`
— and multiplies its iteration count by it (`lcg` 20M → 2G steps at x100),
or repeats its kernel that many times where a bigger problem would change
the program's memory behaviour: `fib` sums N calls of `fib(35)`, `sieve`
re-sieves the same 10 MB, `matmul` multiplies N differently-seeded pairs.
The script rewrites that one number in a copy of each source, so a xN
program is the same program with a bigger constant, and it refuses to run
if any source has no such line. x1 compiles the sources as they stand —
the published contract, instruction for instruction what it was before
the multiplier existed. A large N amortises process start-up and the
runtimes' module compilation, which at x1 are a large share of a 40 ms
cell, and leaves the generated code; a xN run writes `WASMRESULTS-xN.md`
and `results/wasm-xN.json` beside the x1 report rather than replacing it.
`bench.sh` takes the same `--scale` (and `BENCH_SCALE`); the Python and
JavaScript peers have no multiplier, so a scaled `bench.sh` run is NURL /
C / Rust only.

Everything but the interpreter column costs about what `bench.sh` does;
the interpreter is ~500× native, so it is the whole budget. Running the C
and Rust modules on it too — the cross-frontend control — triples that, so
it is opt-in.

Each benchmark's NURL, C and Rust sources are compiled **twice** — native
and `wasm32-wasi` — and each module is run on **two** runtimes: the
external reference `wasmtime` (Cranelift JIT) and
[`packages/nwasm`](../packages/nwasm), a WebAssembly runtime written in
pure NURL. Ten timed cells per row, all gated on printing the
same line as the native NURL binary — the interpreter is *inside* the
gate, because a runtime that gets the wrong answer quickly is not a fast
runtime. Results: [`WASMRESULTS.md`](https://github.com/nurl-lang/nurl/blob/bench-data/bench/WASMRESULTS.md) and
[`results/wasm-latest.json`](https://github.com/nurl-lang/nurl/blob/bench-data/bench/results/wasm-latest.json).

The tenth cell is the NURL module relinked with `--no-gc-sections` —
`wasmbuilder`'s pre-0.1.4 default, kept measured so the price of its
escape hatch stays a number (section 5 of the report). See
[`packages/wasmbuilder`](../packages/wasmbuilder/README.md#--gc-sections-is-the-default-and---no-gc-sections-the-escape-hatch)
for why the default flipped and what would justify flipping it back.

C and Rust are there as the control. Without them a wasm-vs-native ratio
cannot distinguish "wasm is slower here" from "NURL's wasm pipeline is
slower here", and modules from two other LLVM frontends are the only
honest test of a runtime written against NURL's own output.

The pieces are all built from this repo rather than from an installed
toolchain — `nurlc`, `stdlib/runtime.o`,
[`packages/wasmbuilder`](../packages/wasmbuilder) (NURL → wasm) and
`packages/nwasm` (the runtime) — so the numbers describe this working
tree. What it additionally needs on the host is `zig` (wasi-libc +
`wasm-ld`, and the NURL toolchain bundles one), `rustup target add
wasm32-wasip1`, and the external reference `wasmtime`, which is
deliberately *not* vendored here: its whole job is to be the outside
opinion.

`$WASMTIME` points at that reference binary; left unset, the script takes
whatever `wasmtime` resolves to on `PATH`. That lookup used to be a real
hazard — the pure-NURL runtime installed itself as `$NURL_HOME/bin/wasmtime`
and would quietly fill the reference-JIT column with the runtime the column
exists to compare against. It is now installed as `nwasm`, so the two names
cannot collide. The report's environment table still names both runtimes,
so check it if a run looks odd.

[`.github/workflows/wasm-bench.yml`](../.github/workflows/wasm-bench.yml)
runs all of the above on a fixed `ubuntu-latest` runner and publishes the
refreshed report to the `bench-data` branch, the same way `bench.yml` does
for `RESULTS.md`. It is
manual-only — trigger it from the Actions tab, as with `http-bench` and
`pq-bench` — because the interpreter column makes a full run hours long.
Its `quick` input smoke-tests the harness at one repetition per cell and
publishes nothing; its `scale` input runs the suite at xN and publishes
`WASMRESULTS-xN.md` beside the x1 report.

## Beyond wall clock

[`perfstat.sh`](perfstat.sh) builds the NURL binaries and reports
**retired instructions and core cycles** from the CPU's own counters:

```sh
./bench/perfstat.sh --save ref.tsv     # record a baseline
./bench/perfstat.sh --against ref.tsv  # compare after a compiler change
```

Wall clock has several per cent of run-to-run drift, so anything under
~10 % there is noise. Instructions are essentially deterministic for
these single-threaded kernels and cycles do not move with the frequency
governor, which makes a 1 % regression visible. Use `bench.sh` to compare
languages, `perfstat.sh` to compare two versions of NURL.

## Physical floors — `chaincheck.sh`

A serial-chain row must not run faster than its dependency chain's
hardware minimum: `lcg`'s step is `imul(3)+add(1)+shr(1)+xor(1)` = 6
cycles, so 20M iterations cannot legitimately finish under 120M cycles.
`./bench/chaincheck.sh` builds the NURL, C and Rust binaries the way
`bench.sh` does and verifies every chain row against its documented
floor — with exact PMU cycle counts where `perf` works (a healthy row
sits within ~10 % of its floor; the current table measures 6.02–6.03
cyc/iter on `lcg` for all three languages), and as a wall-clock lower
bound at 6 GHz on PMU-less CI runners. The bench workflow runs it after
every suite run: a table with an impossible number in it fails the run
instead of getting published.

This gate exists because the pre-xorshift `lcg` was exactly such a
number — LLVM composed k affine steps into one (`x·aᵏ + cₖ`), the NURL
binary ran 100M "iterations" in 3.7 ms (a 162 GHz clock, had the chain
been real), and the row was silently measuring the compiler's
composition factor. The xorshift mix in `lcg`, `ring_write` and
`histogram_bins` breaks the affinity that transform needs;
`chaincheck.sh` keeps it broken.

## Reading the numbers

* Compare a cell against the **floor row** in `RESULTS.md` (an empty
  program in the same language). A cell near the floor is process
  start-up, not the benchmark.
* All three compiled back ends are LLVM-based and all three are allowed
  to be clever — LLVM will fold an affine recurrence or pick a different
  unroll factor per language. A cell measures optimised throughput of the
  same algorithm, not the source-level iteration count.
* Absolute numbers are machine-specific. Compare deltas between runs on
  the same machine or the same CI runner spec; the committed results
  file always records which host produced it.
