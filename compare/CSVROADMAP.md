# CSV stdlib roadmap — `stdlib/ext/csv.nu`

Make NURL CSV the fastest, smartest, leanest stdlib CSV handler in
existence at this scale: faster than Polars on the workloads where
NURL has structural advantages (single-binary AOT, value-moved Vecs,
NUL-tolerant `Vec[u]`-backed strings, lazy `iter_chain`, no GC), and
*production-ready* — RFC-4180 correct, schema-typed, predictable
errors, bounded memory, reproducible benchmarks.

## Baseline (v1 MVP — 1 M rows × 8 cols, `compare/nurl_analysis.nu`)

```bash
wau@wau:~/dev/nurl/compare$ ./nurl_analysis
Loaded 1000000 rows x 8 cols in 1091ms
Filtered to 149644 rows in 387ms
Sorted (val_int desc) in 901ms
Top-10 written to nurl_top10.csv in 0ms
Total: 2380ms
```

| Stage  | NURL v1 | Polars | py-csv  | NURL/Polars |
|--------|---------|--------|---------|-------------|
| Load   | 1077 ms | 67 ms  | 2319 ms | 16.1×       |
| Filter | 371 ms  | 19 ms  |   —     | 19.5×       |
| Sort   | 950 ms  | 13 ms  | 3711 ms | 73.1×       |
| Write  | 0 ms    | 5 ms   | 803 ms  |   —         |
| Total  | 2399 ms | 104 ms | 10532 ms| 23.1×       |

### Where the v1 time actually goes (hypothesis, to be confirmed in P0)

| Stage  | Suspected hotspot                                      | Lever                                |
|--------|--------------------------------------------------------|--------------------------------------|
| Load   | 8 M `string_from_bytes` heap allocs (1 M rows × 8)     | arena / slice-borrow                 |
| Load   | per-byte loop in `__csv_scan_row` (`csv.nu:346`)       | SIMD `memchr` + unroll               |
| Filter | per-cell `string_to_float` inside predicate            | typed columns parsed once at load    |
| Sort   | `string_to_int` on every comparator call (~20 N) (`csv.nu:550`) | parse keys once into `Vec[i]`        |
| Write  | already optimal — buffered FILE\* write                | leave alone                          |

The v1 contract is preserved: every public API stays available; new
APIs ship beside the old ones, with the old ones routing to the new
implementations once equivalence is proven.

## Targets

| Phase | Total goal | Headline win                                  | Status |
|-------|------------|-----------------------------------------------|--------|
| P0    | (no change)| Profile + bench harness — make P1+ measurable | ✓ shipped |
| P1    | ≤ 1100 ms  | Indexed sort: ≤ 120 ms (8× win in one phase)  | ✓ shipped (sort 73 ms med, total 731 ms before P2a stack) |
| P2a   | ≤ 750 ms   | Arena loader: kill 8 M cell-mallocs           | ✓ shipped — total 731 ms med, load 445 ms med |
| P2b   | ≤ 600 ms   | Drop FFI from per-cell hot path               | ✓ shipped — total 610 ms med, load 333 ms med |
| P3a   | ≤ 600 ms   | RFC 4180 quoting (read + write)               | ✓ shipped — total 505 ms med (Linux i7-5930K, 2c51f7c), load 285 ms; auto-quote on write; no regression vs P2b |
| API consolidation | (no perf) | Arena is the only CSVTable; `csv_table_a_*` deleted | ✓ shipped 2026-05-16 — v1 `CSVTable` / `CSVRow` removed; `csv_table_*` now reaches the arena directly; RFC 4180 quoting is the default for every CSVTable load/write |
| P2c   | ≤ 400 ms   | Hoist 3 vec_reserve + 3 vec_data out of per-row loop | candidate next — see Phase 2c below; ~6 M FFI ≈ 90–180 ms savings projected |
| P3b   | ≤ 350 ms   | Schema-typed parse                            | next-after-P2c — build atop quoted-cell support |
| P4    | ≤ 180 ms   | Columnar layout + vectorized aggregates       |        |
| P5    | win        | Streaming + predicate pushdown — beat Polars  |        |
|       |            | on selective filters (>10× row reduction)     |        |
| P6    | n/a        | Production polish — errors, sniff, bounds     |        |
| P7    | n/a        | Innovations — mmap, binary cache, Parquet     |        |

After every phase, re-run `compare/nurl_analysis.nu` *and*
`compare/polars_analysis.py` on the same machine, append timings to
`compare/HISTORY.md`, and put the numbers in the commit message.

---

## Phase 0 — Profile, benchmark harness, baseline lock-in

We are guessing where the time goes. P0 makes future phases targetable.
None of P1+ should land without P0 in place — we cannot claim a
speedup without a regression-resistant measurement.

- [ ] **Add `compare/HISTORY.md`** — append-only log: date, commit SHA,
      stage timings, machine info (`uname -a`, CPU model from
      `/proc/cpuinfo`), build flags. One line per run.
- [ ] **Add `compare/run_bench.sh`** — runs `nurl_analysis` and
      `polars_analysis.py` 5× each, reports min/median, writes to
      `HISTORY.md`. Single command for reproducibility.
- [ ] **Add `compare/README.md`** — `python compare/generate_data.py`
      to regenerate `test_data.csv` (current is 106 MB, gitignore it),
      then `./run_bench.sh`. Document seed for determinism.
- [ ] **Profile load with `perf record` / `perf report`** on
      `nurl_analysis` (Linux):
      ```
      perf record -g --call-graph=dwarf ./nurl_analysis
      perf report --stdio | head -60
      ```
      Capture top-10 self-time symbols into `compare/PROFILE.md`.
- [ ] **Confirm or refute the hotspot table above**, especially:
      whether `malloc` (string allocs) outranks per-byte parsing.
      The chosen P2 path depends on this.
- [ ] **Add a microbench harness** `compare/microbench.nu` covering
      `__csv_scan_row` and `string_from_bytes` in isolation, so we can
      iterate without the 1 GB-touched-pages overhead of the full
      pipeline.
- [ ] **Pin the test fixture**: regenerate `test_data.csv` with a fixed
      seed. Add a row count / SHA-256 sentinel to `compare/README.md`
      so anyone re-running can verify.
- [ ] **gitignore** the giant CSVs (`compare/test_data.csv`,
      `compare/python_sorted_data.csv` if generated). Keep
      `compare/{nurl,polars}_top10.csv` as round-trip fixtures.

Exit criterion: re-running `./run_bench.sh` between two no-op commits
produces variance < 3 % on each stage.

---

## Phase 1 — Indexed sort (cheap win, biggest single gain)

Goal: drop sort from 950 ms → ≤ 120 ms by parsing keys *once* instead
of `O(N log N)` times inside the comparator (~40 M `string_to_int`
calls today, vs. 1 M after).

The shape we want:

```
@ csv_table_sort_by_int_indexed *CSVTable t i col b asc → v {
    : i n ( csv_table_n_rows t )
    : ( Vec i ) keys ( vec_with_cap [i] n )
    // 1 parse per row
    : *CSVRow rp ( vec_data [CSVRow] . t rows )
    : ~ i ri 0
    ~ < ri n {
        : CSVRow r . rp ri
        : ? String s ( vec_get [String] . r cells col )
        : ~ i v 0
        ?? s { T x → {
            : ! i ParseErr p ( string_to_int x )
            ?? p { T pv → { = v pv } F → {} }
        } F → {} }
        ( vec_push [i] keys v )
        = ri + ri 1
    }
    // sort an index permutation
    : ( Vec i ) order ( vec_iota 0 n )
    : *i kp ( vec_data [i] keys )
    ( sort_by [i] order \ i a i b → i {
        : i ka . kp a
        : i kb . kp b
        : i c ( cmp_int ka kb )
        ? asc { ^ c } { ^ - 0 c }
    } )
    // permute rows in-place via temporary Vec[CSVRow]
    // (CSVRow is a single-pointer move — see csv.nu:255 comment)
    ...
}
```

- [ ] **Implement `vec_iota i lo i hi → ( Vec i )`** in
      `stdlib/core/vec.nu` if it does not exist (probably doesn't).
      Pre-fill with `lo, lo+1, …, hi-1`. Used everywhere indexed
      operations land.
- [ ] **Implement `csv_table_sort_by_int_indexed`** in
      `stdlib/ext/csv.nu`. Permutation step: build new `Vec[CSVRow]`
      with `vec_with_cap`, push each old `rp[order[k]]` (this *moves*
      the 8-byte `ctl` pointer, no clone). Free the *old*
      `Vec[CSVRow]` with `vec_free [CSVRow]` — **NOT**
      `vec_free_with` — because ownership of every `CSVRow` was moved
      into the new vec. (The `vec_free [CSVRow]` vs `vec_free_with`
      distinction is the same trap that bit `Vec[String]` per
      [project_nurl_vec_drop](memory).)
- [ ] **Implement `csv_table_sort_by_float_indexed`** — same shape,
      `Vec[f]` keys, `cmp_float`, `string_to_float`. Note: NURL's `!=`
      is `fcmp one`, NaN-trap territory — coerce NaN to a sentinel
      (e.g., `-INFINITY` for ascending so they sink to the bottom).
- [ ] **Wire the public APIs** `csv_table_sort_by_int` /
      `csv_table_sort_by_float` (`csv.nu:550`, `csv.nu:574`) to the
      `_indexed` variants. Old name stays, behavior identical, new
      cost.
- [ ] **Add `csv_table_sort_by_string_indexed`** — keys are borrowed
      `s` pointers (no copy), comparator calls `nurl_str_cmp`. The
      generic `csv_table_sort_by` (`csv.nu:511`) re-fetches the cell
      every comparison; with borrowed pointers we cut the option-
      unwrap and branch tax.
- [ ] **Multi-key sort**: `csv_table_sort_by_keys *CSVTable t ( Vec i ) cols ( Vec b ) asc → v`
      precomputes a `Vec[i]` (or `Vec[String]`) per key, then runs a
      stable comparator. This is what `compare/sort_data.py` does (8
      keys); without it we are not feature-parity with `csv.DictReader`.
- [ ] **Tests** in `compiler/tests/csv_sort_indexed.nu`:
      - 100 k random ints, asc + desc, verify monotone after sort
      - round-trip: sort → write → reload → re-sort → no diff
      - all-equal keys (no destabilization, no segfault)
      - empty table, single row
      - unparseable cells: must not crash, must compare as 0 (or
        as documented sentinel)
      - multi-key sort matching `compare/sort_data.py`'s 8-key result
- [ ] **Re-run** `./run_bench.sh`. Sort must drop below 150 ms; ideally
      below 100 ms (parse cost alone is what's left).
- [ ] **Update baseline table** above + `compare/HISTORY.md`.

---

## Phase 2 — Arena loader (kill the 8 M mallocs) + `memchr` scan

P0 will tell us which dominates. Most likely both matter, and the
arena win is bigger.

### 2a. Arena-allocated string slices

Today every cell is a `string_from_bytes(src, n)` (`csv.nu:355,361,367`)
which `malloc`s a fresh `{ s ctl }`. For a 1 M-row × 8-col file that is
8 M `malloc`+`memcpy` pairs. The file content is already in one
contiguous buffer (`read_file`). We don't need a second copy.

- [ ] **Define `CSVArena`**: owns the file content buffer plus a
      `Vec[u]` of NUL bytes injected at delimiters. Cells are
      `(offset, len)` pairs into the buffer; `cell_view(arena, off, len)`
      hands back a borrowed `s` (pointer-into-arena) without
      allocation.
- [ ] **Define `CSVTableA`** — arena-backed table:
      ```
      : CSVTableA {
          *CSVArena arena
          ( Vec String ) headers     // owned (copies; small)
          ( Vec ( Vec i ) ) rows     // each row is Vec[i] of (off,len) pairs packed 2-i64-per-cell, OR a Vec[CellRef]
      }
      ```
      Two sub-options to evaluate: **(a)** parallel `Vec[i]` per row
      (offset, length, alternating), super cache-tight; **(b)**
      `Vec[CellRef] { i off, i len }` — slightly fatter, easier to
      read. Pick (a) only if it benches faster.
- [ ] **Implement `csv_table_load_arena s path → *CSVTableA`** —
      reads file once, parses with the v2 scanner, never copies cell
      bytes. Allocations: file buffer + one `Vec[i]` per row + headers.
      That's ~1 M small allocs instead of 8 M. Use
      `vec_with_cap [i]` sized at `2 * n_cols_estimated` so the
      hot loop never reallocs.
- [ ] **Add `csv_table_a_get_view *CSVTableA t i row i col → ? s`** —
      borrowed pointer into arena buffer. **Caller must not free.**
      Document: views are valid until `csv_table_a_free`.
- [ ] **Add `csv_table_a_to_table *CSVTableA t → *CSVTable`** —
      promotion to the v1 owned-string layout for callers that need
      independent lifetimes. The view → owned copy is the only place
      we pay malloc.
- [ ] **Wire `csv_table_load`** to delegate to the arena loader and
      promote — keeps the existing API, gets the parse speedup, but
      pays the malloc on conversion. The conversion *can* be cheaper
      than the v1 path because we already know lengths.

### 2b. Drop FFI from the per-cell hot path  ✓ shipped 2026-05-08

The original Phase 2b plan was "use `memchr` for the byte loop", on
the hypothesis that the byte scan was the bottleneck. Empirically it
**wasn't**. NURL compiles to LLVM-IR + -O2, so the byte loop already
runs as native code. Profiling pointed at a different hotspot:
`vec_push` issues two FFI calls per push (`nurl_peek` ctl read +
`nurl_poke` len bump), and `runtime.o` is built without LTO so those
calls don't inline. With 1 M rows × 8 cells × 2 i64 pairs =
~32 M FFI calls × ~15 ns per call = ~480 ms.

What shipped instead:
- [x] **Pre-reserve + raw pointer writes** in `__csv_a_parse_content`.
      Per row: one `vec_reserve` to ensure ≥256 cells of headroom, one
      `vec_data` to pin the data pointer, then cell `(off, len)` pairs
      written via `. fcp i` direct stores. `row_starts`/`row_lens` use
      the same trick (`vec_reserve` + raw stores via `rsp_w`/`rlp_w`,
      `vec_set_len` once at the end).
- [x] **FFI count cut** from ~32 M to ~5 M. Load: 445 → 333 ms median
      (25 % faster). Total pipeline: 731 → 610 ms median.
- [x] **Two failed experiments documented** in `csv.nu`'s
      `__csv_a_parse_content` header comment + retained as Phase 3
      infrastructure in `runtime.c`:
      - `nurl_csv_parse_arena` (whole-file C parser): 510 ms — large
        contiguous reservation page-faulted.
      - `nurl_csv_scan_row_pairs` (per-row C scanner): 700 ms — 1 M
        FFI calls + transfer copy from C buffer to flat_cells via
        `vec_push` reintroduced the cell-FFI cost.
- [x] **Byte-identical Top-10** vs Polars confirmed (`diff
      nurl_top10.csv polars_top10.csv` = 0 bytes).

Quoting (Phase 3a) is shipped — see below.

#### Future: try memchr / SSE2 for the byte loop
The original `memchr` idea is still valid, but the upper bound it
saves is ~150 ms (the residual byte-scan cost after Phase 2b). Lower
priority than Phase 3 typed parse, which collapses load + filter into
one pass on typed columns.

### 2c. Hoist row-level FFI (vec_reserve / vec_data) out of the inner loop

After Phase 3a landed, profiling on Linux i7-5930K (`2c51f7c`) puts
the arena pipeline at 285 ms load. Of that, the inner row-loop in
`__csv_a_parse_content` calls **6 FFI functions per row**:

```nu
( vec_reserve [i] . t flat_cells + row_first_i64 max_row_i64 )
( vec_reserve [i] . t row_starts + row_w 1 )
( vec_reserve [i] . t row_lens   + row_w 1 )
: *i fcp   ( vec_data [i] . t flat_cells )
: *i rsp_w ( vec_data [i] . t row_starts )
: *i rlp_w ( vec_data [i] . t row_lens )
```

`vec_reserve` is itself NURL (one `nurl_peek` cap-read + branch when
already big enough), `vec_data` is one `nurl_peek` — both are cross-
TU calls without LTO, so each pays ~30 ns. **6 M FFI per million rows
≈ 90–180 ms** (depending on prefetcher state) — somewhere between a
quarter and a half of the current load budget.

The plan:

- [ ] **Pre-count rows** with one tight pass over `cd` looking for
      `\n`. NURL byte-loop runs at native speed (LLVM-O2); 100 MB ≈
      80–120 ms. Net cost is *less* than the FFI we eliminate.
      Alternatively add `nurl_count_byte` (libc `memchr` in a loop) —
      one FFI call, < 10 ms via SIMD.
- [ ] **Pre-reserve once** at function entry: `flat_cells` →
      `n_rows × est_cells × 2` (e.g. 32 cells/row), `row_starts` /
      `row_lens` → exact `n_rows`. Memory is fine — 100 MB CSV with
      32 cells/row × 16 B = 50 MB of flat_cells.
- [ ] **Hoist `fcp`, `rsp_w`, `rlp_w` outside** the row loop. With
      one-shot reserve they remain valid for the whole parse.
- [ ] **Hoist `wi` outside** too — replaces the per-row
      `vec_len . t flat_cells` re-read; we can track it as a single
      mutable counter that survives across rows. `vec_set_len` only
      runs once at the end.
- [ ] **Safety check** for the rare case our cell estimate is too
      low (e.g. some row has > est_cells columns): re-grow + re-fetch
      pointers inline. Predicted-not-taken; near-zero cost on typical
      data.
- [ ] **`escape_buf` stays unchanged** — it's only touched on quoted
      `""` escapes (cold path on test_data.csv).
- [ ] **Bench** — target load ≤ 200 ms, total ≤ 400 ms on Linux
      i7-5930K. Update `compare/HISTORY.md`.

Risk: if the hoisted-pointer path is a regression on shapes we don't
test (very wide rows, very narrow rows), we revert and ship the
optimization gated on cell-count estimate sanity. Tests in
`compiler/tests/repro_csv_*` already cover quoting, escapes, and
narrow-row CSVs — keep them green.

---

## Phase 3 — RFC 4180 quoting + schema-driven typed parse

Once load is fast and pre-parsed, sort becomes trivial and filter
becomes "tight loop over typed cells". This is also where we earn
"production-ready" — real-world CSVs (Excel exports, pandas dumps,
financial extracts) need quoting.

### 3a. RFC 4180 quoting in `csv_table_a` — ✓ shipped 2026-05-08

- [x] **Add `quote_char` to `CSVDialect` (`csv.nu:30`)** — default
      `34` (`"`). `csv_dialect_unquoted` (`quote_char = 0`) bypasses
      the quote branch entirely.
- [x] **Reader state machine** in `__csv_a_parse_content` — at each
      cell start, peek `cd[p]`. If `quote_char != 0` and the byte
      matches, run the quoted-cell sub-loop: bytes go to a zero-copy
      span into `content` UNLESS we hit `""` (escape), in which case
      we materialize the unescaped run into the new `escape_buf`
      `Vec[u]` field on `CSVTableA`. Cells are addressed by either a
      positive offset into `content` (zero-copy fast path) or a
      negative offset `-(esc_off+1)` into `escape_buf`.
      `csv_table_a_view` dispatches on the sign.
- [x] **Update writer** (`csv_table_a_write`) — per-cell prescan for
      delim/quote/`\n`/`\r`. If any present, emit `"..."` with
      embedded `"` doubled. Bypasses entirely when
      `dia.quote_char = 0` to keep Phase 2b's raw-write speed.
      Cells from `escape_buf` (off < 0) ALWAYS quote-emit since they
      came from quoted input by definition.
- [x] **Tests** in `compare/test_quoting.nu` — simple quoted,
      embedded comma, embedded newline, doubled-quote escape, lone
      escape `""""`, empty quoted `""`, CRLF terminators, full
      round-trip via `csv_table_a_write` + reload.
- [x] **No regression on unquoted hot path** — `nurl_analysis_arena`
      load median 326 ms (Phase 2b: 327 ms), total ~560 ms unchanged
      within noise. Per-cell `& != quote 0 < p clen ==` check is a
      single predicted-not-taken branch on quote-free data.
- [ ] **Real-data validation** — Excel/pandas sample TBD by user.

### 3b. Schema, types, nullability

NURL already has the building blocks: tagged unions via `! T E`
(beware multi-field-struct-in-Result is broken — prefer single-field
unions or two-field max — see [project_nurl_http_proxy](memory)),
`?` for option, `Pair[K V]` for kv mapping.

- [ ] **`ColType`** — sum type with:
      `I64`, `F64`, `Str`, `Bool`, `DateIso` (yyyy-mm-dd → days since
      1970-01-01 as i64), `TimestampIso` (RFC 3339 → ns since epoch),
      `Null`. NURL idiom: tagged-union via discriminant byte +
      sentinel (text-level generics make true ADTs awkward — see
      [feedback_nurl_compiler_quirks](memory)).
- [ ] **`Schema`** — `Vec[ColType]` plus optional column names. A
      mismatch between schema-named columns and CSV headers is a
      `LoadErr::SchemaMismatch`.
- [ ] **`TypedCell`** — packed cell: 1-byte discriminant + 8-byte
      union. Total 16 B aligned. Bool is 0/1, Null is its own variant.
- [ ] **`TypedRow { Vec[TypedCell] cells }`**.
- [ ] **`TypedTable { Vec[String] headers, Vec[TypedRow] rows, Schema schema, i n_parse_errors, ( Vec ParseErr ) errors }`**
      — error list is *capped* (e.g. first 100) to avoid unbounded
      growth on garbage input. Counter is exact.
- [ ] **`csv_load_typed s path Schema → ! *TypedTable LoadErr`** —
      single-pass typed parse. On per-cell parse failure, emit a
      `Null` cell, increment counter, push first 100 errors with
      (row, col, raw bytes, expected type).
- [ ] **`csv_load_typed_strict`** — same, but first parse error
      aborts with a populated `LoadErr`.
- [ ] **`csv_infer_schema s path i sample_rows → Schema`** — peek at
      first N rows, infer per-column type by trying I64, then F64,
      then Bool, then DateIso, then Str. Uses the typed parser
      internally with `Str` schema, then re-asserts.
- [ ] **Typed accessors** — `typed_get_i64`, `typed_get_f64`,
      `typed_get_str`, `typed_get_bool`, `typed_is_null`. Return
      `?T`; missing or wrong-type both → `None`.
- [ ] **Typed sort** — `typed_sort_by(t, col, asc)` dispatches on
      `schema[col]` once at entry; comparator does no parsing.
      ≤ 80 ms for 1 M rows on val_int — straight `cmp_int`.
- [ ] **Typed filter** — `typed_filter(t, predicate)` — predicate
      receives `*TypedRow`, calls cheap accessors. **Critical for
      P3 win**: this kills the per-row `string_to_float` cost in
      `nurl_analysis.nu:38`, which is the bulk of the 387 ms filter.
- [ ] **Convenience predicates** — `typed_filter_i64_gt`,
      `typed_filter_f64_gt`, `typed_filter_f64_lt`,
      `typed_filter_str_contains`, `typed_filter_str_eq`. These are
      the "you don't need to write a closure for the common cases"
      escape hatch — and they are easier for the compiler to inline
      than user-supplied closures.
- [ ] **Re-stringifying writer** — `typed_table_write` honors the
      original cell formatting (e.g., `97.3819` not `97.38190000`).
      Float printer must match v1's `nurl_str_float` output by
      default; expose a precision dial for users who want it.
- [ ] **Port `nurl_analysis.nu` to typed APIs** as
      `compare/nurl_analysis_typed.nu`, *keep the old one* for
      A/B benchmarking. Both must produce the same `nurl_top10.csv`
      byte-for-byte.
- [ ] **Re-bench**. P3 target: total ≤ 350 ms — load 250, filter 30,
      sort 50, write 20.

---

## Phase 4 — Columnar layout + vectorized aggregates

Now we are competing with Polars on its home turf: aggregation and
column scans. NURL's compile-to-LLVM means our tight loops should
auto-vectorize as well as Rust's; the question is whether we can keep
the syntactic ceremony low enough.

### 4a. Columnar storage

- [ ] **`Column`** — tagged union of `Vec[i]` (i64), `Vec[f]`,
      `Vec[String]`, `Vec[u]` (bool packed 1 bit/row, OR 1 byte/row
      for simplicity in v1), `Vec[i]` (date-as-days-since-epoch).
      Discriminant + `*v` payload.
- [ ] **`ColumnarTable { Vec[String] headers, Vec[Column] cols, i n_rows, Schema schema }`**.
- [ ] **`csv_load_columnar s path Schema → ! *ColumnarTable LoadErr`** —
      pre-allocate columns at file_size / avg_row_length estimate,
      grow with `vec_with_cap`-doubling. Parse row, distribute fields
      per-column. Layout transform happens once at load.
- [ ] **`columnar_to_typed`** + `typed_to_columnar`** — bidirectional
      so users can mix-and-match the two table flavors. Cheap
      pointer-shuffle for arena-backed columns; expensive for owned.

### 4b. Borrow accessors (zero-copy column views)

- [ ] **`col_i64_data *ColumnarTable t i col → *i`** (returns NULL +
      pushes error if `schema[col] != I64`).
- [ ] **`col_f64_data`, `col_str_data`, `col_bool_data`** —
      analogous. **Document** that the pointer is invalidated on any
      mutation that grows or shrinks the column.

### 4c. Vectorized aggregates

- [ ] **`col_sum_i64`, `col_sum_f64`** — tight loop over the raw
      pointer; LLVM auto-vectorizes given the right `--march`. Add a
      build flag to `compiler/build.sh` to bump LLVM to `-O3 -march=native`
      *for the runtime only* (we don't want native flags in user
      binaries by default). Verify the output `.ll` shows `<4 x i64>`
      or wider.
- [ ] **`col_min`, `col_max`, `col_mean`, `col_count`,
      `col_count_nulls`, `col_stddev`** — i64 + f64 versions.
- [ ] **`col_filter_i64 *ColumnarTable t i col CmpOp op i val → ( Vec i )`** —
      returns row indices passing the predicate, using a single tight
      loop. CmpOp = `Eq Ne Lt Le Gt Ge`. NURL idiom: `i op` discriminant
      with a `match` dispatch *outside* the loop, not inside.
- [ ] **`columnar_take *ColumnarTable t ( Vec i ) idx → *ColumnarTable`** —
      materialize a filter result. Each column is a single
      `for i in idx: out.push(col[i])` loop — also vectorizable for
      the i64/f64 cases.
- [ ] **`columnar_groupby_sum_i64 *ColumnarTable t i key_col i agg_col → ( Vec ( Pair i i ) )`** —
      pandas-`.groupby(key).sum(agg)`. HashMap-backed
      ([project_nurl_hashmap](memory) — closure hash/eq passed per
      call, no struct fn-ptr fields).
- [ ] **Bench**: filter + sum + count workload vs. Polars equivalent.
      Target: parity on aggregate, win on filter+aggregate when
      selectivity is < 20 %.

---

## Phase 5 — Streaming pipelines + predicate pushdown (NURL's edge)

This is the section where NURL gets to be *better* than Polars, not
just close. Polars' `LazyFrame` is excellent but bound to its query
optimizer. NURL's `iter_chain` (constant-memory lazy iterator,
[project_nurl_iter_chain](memory)) lets users compose pipelines that
never materialize intermediates.

### 5a. Streaming reader

- [ ] **`CSVStream { *v fh, Schema schema, Vec[u] readbuf, i bufpos, i buflen, i row_no }`** —
      file handle + a fixed-size read buffer (e.g., 256 KB). State
      machine continues a row across buffer refills.
- [ ] **`csv_stream_open s path Schema → ! *CSVStream LoadErr`** —
      reads header, validates against schema (or infers in `Auto` mode).
- [ ] **`csv_stream_next *CSVStream s → ?? TypedRow`** — `?? T` here
      is "Some(T) | None at EOF | parse-error in inner counter". One
      row at a time. Critical: **the returned `TypedRow` is borrowed
      from the stream's internal buffer when the row fits in the
      current buffer**, owned otherwise. Document the ownership flip
      precisely; provide `typed_row_take` to force ownership.
- [ ] **`csv_stream_close`** — frees buffer, closes fh.

### 5b. Iterator combinators

- [ ] **Wrap `CSVStream` as `Iter TypedRow`** so `std/iter.nu`'s
      lazy chain (already shipped per
      [project_nurl_iter_chain](memory)) composes with it for free.
      Users get `iter_filter`, `iter_map`, `iter_take`, etc. with no
      extra work in `csv.nu`.
- [ ] **`stream_aggregate (@ ( Pair Acc TypedRow ) Acc TypedRow ) f Acc init → Acc`** —
      terminal fold. Drives the iterator to exhaustion, calls drop
      cascade.
- [ ] **`stream_collect *CSVStream s → ! *TypedTable LoadErr`** — a
      terminal materializer. Equivalent to `csv_load_typed`, just via
      streaming, useful when the pipeline filters first.

### 5c. Single-column predicate pushdown

This is the killer feature. Suppose the user has a 10-GB CSV and a
filter touching one column out of 50. Polars must parse all 50
columns to find row boundaries. We can:

1. Ask the predicate which column it touches (registered
   `col_predicate_typed`).
2. In the row scanner, parse *only* that column; for other columns,
   `memchr` to the next `,` and emit a `null`-deferred view.
3. If the predicate fails, skip the rest of the row to the next `\n`
   in one `memchr` call.
4. If the predicate passes, finish parsing the deferred columns.

- [ ] **`PushdownPred`** — opaque struct: column index, op, value.
      Constructed by `pushdown_i64_gt(col, val)`,
      `pushdown_f64_lt(col, val)`, `pushdown_str_eq(col, s)`,
      `pushdown_str_contains(col, s)`.
- [ ] **`csv_stream_open_pushdown s path Schema PushdownPred → ! *CSVStream LoadErr`** —
      the pushdown variant.
- [ ] **`csv_stream_next` honors pushdown** — internal scanner knows
      the target col, skips others as views, evaluates predicate
      after target col is parsed, skips rest of row on miss.
- [ ] **Streaming benchmark** in `compare/`:
      ```
      filter 10 M-row CSV with predicate `val_int > 999000`
      → expected: NURL ~ 200 ms (single-column scan)
                  Polars ~ 600-900 ms (full parse first)
      ```
      Add this benchmark and commit numbers to `HISTORY.md`.

---

## Phase 6 — Production polish (no perf, all correctness/UX)

Speed without correctness is not production-ready. This phase ships
in parallel with P3-P5; do not ship "v1 production" until these are
all checked.

- [ ] **Error model** — settle now. Every `LoadErr` case has:
      `path`, `line`, `column` (0-indexed *and* header name when
      known), `expected` (type), `got` (raw bytes truncated to 80 ch),
      `kind` (`SchemaMismatch | TypeParse | Truncated | IOError | DialectMismatch`).
      Test that error messages render readably.
- [ ] **Strict vs. permissive** — `csv_load_typed_strict` aborts on
      first error; `csv_load_typed` emits Null + counter; both
      paths share a single scanner.
- [ ] **Bounds** — refuse to load a row whose total length exceeds
      `MAX_ROW_BYTES` (default 16 MB), or a single field exceeding
      `MAX_FIELD_BYTES` (default 1 MB). Configurable per-load. Without
      this, a malicious 4 GB single-line file hangs the parser.
- [ ] **BOM stripping** — leading UTF-8 BOM (`EF BB BF`) on header
      row is silently consumed.
- [ ] **Encoding** — explicit "we are UTF-8 only; bytes outside
      ASCII pass through as opaque bytes; don't trust any cell as
      `s` (NUL-terminated) — use the `String` Vec[u] handle". Document
      this loud and clear in `csv.nu` header. Add a test that loads a
      CSV with embedded NULs in a quoted cell and round-trips it
      byte-for-byte (this exercises the
      [project_nurl_string_vec_u_migration](memory) NUL-tolerance).
- [ ] **Dialect sniffer** — `csv_sniff_dialect s path → CSVDialect` —
      reads the first ~64 KB, picks the delimiter from `, ; \t |`
      by the variance criterion (the column count is most stable when
      we picked the right one). Detects CRLF. Detects quote char.
      The Python `csv.Sniffer()` shape, but in NURL.
- [ ] **Header normalization helpers** — `csv_header_lower`,
      `csv_header_snake_case` (turn `Val Float 1` into `val_float_1`),
      `csv_header_dedup` (suffix `_2, _3` on duplicates). Standard
      pandas-equivalent ergonomics.
- [ ] **`csv_table_describe *CSVTable t → String`** — pandas-style
      summary: row count, col count, per-column inferred type, sample
      values, null count. Renders with `string_concat` to a single
      printable buffer. This is the "feels good in REPL" hook that
      makes the library *land*.
- [ ] **Strict-typed Result for `! T E`** — single-field-struct only
      (per [project_nurl_http_proxy](memory) gotcha — multi-field
      structs in Result are broken). Wrap multi-field errors in a
      `*LoadErrBox` payload.
- [ ] **Public docs** — bump `stdlib/STDLIB.md` and add a `csv.nu`
      doc block at the top with: contract, ownership rules, error
      handling, performance characteristics, mini-tutorial.
- [ ] **Doctests via `compare/csv_demo.nu`** — every public function
      called once with a one-liner asserting expected output. CI gate.

---

## Phase 7 — Innovations (post-v1; pick by motivation)

Standalone wins after P0-P6 ship. Each is a credible stdlib feature
that sets NURL apart.

### Likely-fast, high-impact

- [ ] **`csv_to_columnar_cache *ColumnarTable t s path → ! v IoErr`** —
      flat NURL-native binary file: fixed header (magic + n_rows +
      n_cols + schema), then column blobs concatenated. Two-format:
      raw (mmap-friendly, native endian) and zstd-compressed. Cache
      file is ~3-5× smaller than the source CSV and reloads in
      essentially file-read time.
- [ ] **`csv_load_columnar_cache s path → *ColumnarTable`** with
      mmap on Linux/macOS. Add `nurl_mmap`, `nurl_munmap` to
      `runtime.c` (POSIX `mmap` exists; need to add to NURL FFI).
      Zero-copy reload — the column data pointers are mmap views.
- [ ] **mmap-backed string columns for read-only loads** — CSV file
      is `mmap`'d; cells are `(off, len)` slices. Same
      single-allocation arena pattern as P2a, but file-backed, so
      paging behavior is the OS's problem and reload is instant on
      hot caches.

### Wider ecosystem

- [ ] **Parquet writer** (`csv_to_parquet`) — emit columnar tables
      as Parquet for interop with the wider data ecosystem. Use
      `parquet-tools` or write Parquet directly via libparquet (FFI).
      Decide based on whether libparquet pulls Arrow as a transitive.
- [ ] **JSON-Lines bridge** — `csv_load_jsonl`,
      `typed_table_to_jsonl`. The two interchange formats users
      need 90 % of the time.

### NURL-native curiosities

- [ ] **Compile-time schema specialization** — NURL's generic struct
      instantiation is text-level
      ([feedback_nurl_compiler_quirks](memory)). Exploit this: a
      `TypedTable[Schema=...]` macro-style expansion that emits a
      type-specialized parser per call site, eliminating the discriminant
      branch on every cell. Needs compiler work (codegen-time
      schema parameter); land only if P3-P4 microbench shows
      discriminant tax > 10 %.
- [ ] **`#csv` literal** — compile-time CSV literal embedded in source
      code becomes a `*TypedTable` constant. `dataset := #csv "compare/test_data.csv"`.
      Works by compile-time include + parse + emit `.rodata` blob.
- [ ] **Async pipeline with channels** — pair the streaming reader
      with `std/channel.nu` so a producer thread parses while a
      consumer thread aggregates. Realistic 1.5-2× speedup on big
      files; needs careful ownership across the channel boundary.

### Speculative

- [ ] **GPU aggregate via CUDA FFI** — beat Polars decisively on
      numeric aggregates. Probably more "demo" than "stdlib" — keep
      it in `stdlib/ext/csv_gpu.nu` so the dependency is opt-in.
- [ ] **WASM target benchmark** — confirm reasonable performance under
      `wasmtime`; document for browser/edge use cases.
- [ ] **Deterministic memory mode** — `csv_aggregate_bounded` that
      streams when memory budget would be exceeded. Defensive against
      OOM in production daemons.

---

## Cross-cutting checklist

- [ ] **Quoting contract** explicit at top of `stdlib/ext/csv.nu`
      (currently buried in a comment around `csv.nu:18`).
- [ ] **Ownership contract** explicit per public function: who owns
      the returned value? Inline in the doc comment, not just at the
      file level.
- [ ] **`compare/HISTORY.md`** kept current — every commit that
      touches `csv.nu` or the runtime parser must include a bench run
      in the message body.
- [ ] **CI bench gate** — a regression > 5 % on any stage fails CI.
      Implemented as a script consuming `HISTORY.md`'s last two
      entries, run on the same hardware.
- [ ] **Compiler-quirk awareness in csv.nu**, ground rules:
      - never use `[T]` (single-letter `T` collides with the `T`
        bool literal — use `[A]` / `[E]` /
        [feedback_nurl_compiler_quirks](memory))
      - prefer single-field structs in `! T E` Result
        ([project_nurl_http_proxy](memory))
      - struct-as-field default value: avoid the `# Struct 0` cycle
        ([project_nurl_string_vec_u_migration](memory))
      - closures capture by value — no out-params via closure
      - text-level generics — instantiate once per concrete type at
        the call site

---

## Done log

Append entries here as items complete, with date and benchmark numbers.

- 2026-05-08 — v1 MVP baseline established. Total 2399 ms vs. Polars
  104 ms (23.1×).
- 2026-05-08 — Roadmap rewritten: phases reordered around hotspot
  hypothesis (mallocs > byte-loop in load); P0 added to lock the
  measurement; P5 streaming-pushdown promoted as the strategic win
  vs. Polars; P6 production-polish pulled out; NURL-specific
  innovations consolidated in P7.
- 2026-05-08 — Phase 3a (RFC 4180 quoting) confirmed on Linux. Arena
  pipeline at 2c51f7c: load 285 ms / filter 153 ms / sort 58 ms /
  total 505 ms (vs. db5e53a 327 / 157 / 75 / 562 — 13 % load and 23 %
  sort improvement, no regression). Required fixing
  `compare/run_bench.sh` to default to `nurl_analysis_arena` (matching
  Windows `run_bench.ps1`); the prior 2c51f7c HISTORY entry showing
  load 1016 ms was running the legacy `nurl_analysis` v1 binary by
  accident — see retroactive note in HISTORY.md. Phase 2c (hoist 6
  FFI/row from arena loader) added as the next perf candidate.
- 2026-05-16 — **API consolidation**: `csv_table_a_*` deleted; arena
  is the only CSVTable. The v1 per-cell-malloc `CSVTable` / `CSVRow`
  layout is gone — `csv_table_*` calls now reach the arena parser
  directly and RFC 4180 quoting is the default for every load/write.
  New surface: `csv_table_view` / `csv_table_view_len` /
  `csv_table_view_by_name` (zero-copy borrowed `s`) +
  `csv_table_get` / `csv_table_get_by_name` (owned `?String`).
  Sort/filter/truncate/find/select_cols all wired through the arena.
  `compare/nurl_analysis_arena.nu` + `compiler/tests/csv_sort_indexed.nu`
  + `stdlib/ext/csv_hoist_test.nu` removed (now redundant). Bootstrap
  fixed point holds at 1 185 386 B (stage1 ≡ stage2 byte-identical).
  `csv_arena`, `repro_csv_quotes`, `repro_csv_table_quotes`, and
  `test_csv_full` all green.
- 2026-05-16 — **Runtime LTO** (`-flto` on `stdlib/runtime.o` compile
  + every clang invocation that consumes it: `build.sh`, `nurl.sh`,
  `compiler/tests/run_tests.sh`, `tools/{nurlfmt,nurl-lsp,nurlpkg}/build.sh`).
  Vec / string / io FFI now inlines into user code at link time. On
  the 1 M-row × 8-col `test_data.csv` bench (Linux i7-5930K, 5 runs):

  | Stage  | no LTO median | LTO median | Δ      | Δ %    |
  |--------|--------------:|-----------:|-------:|-------:|
  | load   | 315 ms        | 272 ms     | -43 ms | -14 %  |
  | filter | 146 ms        | 139 ms     |  -7 ms |  -5 %  |
  | sort   |  65 ms        |  40 ms     | -25 ms | -38 %  |
  | total  | 529 ms        | 451 ms     | -78 ms | -15 %  |

  Sort wins the most because the sort_by inner comparator was
  dominated by un-inlinable `nurl_parse_int_range` / `cmp_int` /
  `vec_data` calls. Load wins from `vec_push` / `vec_data` /
  `vec_reserve` inlining in `__csv_parse_content`. Filter was already
  cached-pointer-optimised so the residual FFI was small. Bootstrap
  fixed point preserved (IR generation runs at compile time, LTO is
  link-only). Native binary size for `compare/nurl_analysis` dropped
  172 888 → 25 408 B (-85 %) as LTO drops unused runtime symbols.
  Phase 2c (FFI hoist in the row loop) remains an open candidate —
  with LTO that 90–180 ms ceiling is smaller since the residual FFI
  cost is mostly absorbed.
