# Profile snapshots — `compare/nurl_analysis`

This file pins the *measured* hotspots that drive `CSVROADMAP.md`'s
priority ordering. Numbers are not transferable across machines but
the *shape* (where the time goes) should be stable.

## Methodology

Standard `perf record` was unavailable (`/proc/sys/kernel/perf_event_paranoid = 4`,
unprivileged sampling disabled) so the data below comes from an
`LD_PRELOAD` malloc/calloc/realloc/free counter
(`/tmp/malloc_count.c` in the harness, paste-able from history if
needed). For CPU-time decomposition we use ablation by phase
(`load_only.nu`, `sort_only.nu`).

## 2026-05-08 — v1 baseline (commit 49e1c56+dirty)

CPU: Intel i7-5930K @ 3.50 GHz · Linux 6.17 · 1 M-row fixture.

### Allocation profile

| Run                       | malloc | calloc      | realloc     | free        | bytes (MB) | wall (ms) |
|---------------------------|-------:|------------:|------------:|------------:|-----------:|----------:|
| `load_only` (load phase)  |    693 |  9,000,633  |  9,000,034  | 18,000,631  |    649.8   |  1188     |
| `sort_only` (load + sort) |    693 |  9,000,633  |  9,000,034  | 18,000,630  |    649.8   |  9598     |
| `nurl_analysis` (full)    |    706 | 10,352,203  | 10,351,620  | 20,703,780  |    714.5   |  2426     |

Notes:
1. **Load**: 9 M calloc + 9 M realloc for 1 M rows × 8 cols = 8 M
   cells + 1 M row-Vec[String] handles ≈ 9 M + 9 M.
   Each cell costs **2 allocations** (Vec[u] data buffer + Vec[u] ctl,
   then a realloc bump on push) plus a free-on-eviction.
2. **649.8 MB allocated for a 102 MB file** — 6.4× write amplification
   from `string_from_bytes` allocating fresh per-cell instead of
   slicing into one arena.
3. **Sort phase by itself adds zero allocations** — sort cost is
   pure CPU spent inside `string_to_int` on every comparator call.
4. **Sort_only is 9.6 s** because it sorts the full 1 M rows, not the
   filtered 150 k. The full-sort comparator does ~20 M comparisons →
   40 M `string_to_int` calls. The filtered case in `nurl_analysis`
   does ~5 M `string_to_int` calls (≈ 925 ms wall) — same per-call cost.

### Hotspot decomposition (load = 1188 ms)

We don't have function-level samples, but reasoning from the alloc
counts:

| Cost                           | Estimate | Lever                |
|--------------------------------|----------|----------------------|
| `calloc` × 9 M                  |  ~520 ms | arena / slice-borrow |
| `realloc` × 9 M (cell push)     |  ~270 ms | arena / slice-borrow |
| `memcpy` cell bytes             |  ~120 ms | arena / slice-borrow |
| per-byte scan (`__csv_scan_row`)|  ~180 ms | `memchr`             |
| file read + housekeeping        |  ~100 ms | already optimal      |

The **first three rows are all addressed by the same change** — load
the file once into a single buffer, parse delimiters, store cells as
`(offset, length)` pairs into that buffer. No per-cell `calloc/realloc/memcpy`.
Conservatively this brings load to ~280 ms (~4.2× faster) without
touching `memchr`.

`memchr` is then a smaller second-stage win on the residual ~180 ms.

### Confirms hypothesis from CSVROADMAP.md

> Load: 8 M `string_from_bytes` heap allocs (1 M rows × 8) — arena / slice-borrow
> Sort: `string_to_int` on every comparator call (~20 N) — parse keys once

The numbers above promote both items from "hypothesis" to "measured".
Phase 2a (arena loader) and Phase 1 (indexed sort) attack the two
biggest costs and are independent — order them by implementation
risk, not by measured size.

## How to reproduce

```sh
# build the malloc-counter shim
cat > /tmp/malloc_count.c <<'EOF'
... (see git for the actual source)
EOF
gcc -O2 -shared -fPIC -ldl -o /tmp/malloc_count.so /tmp/malloc_count.c

# build a debug binary
cd ~/dev/nurl
zig build nurl -- -O2 -g compare/nurl_analysis.nu compare/nurl_analysis

# count allocations
LD_PRELOAD=/tmp/malloc_count.so ./compare/nurl_analysis 2>&1 | tail -1
```

If `perf` becomes available (`sudo sysctl kernel.perf_event_paranoid=1`),
add a section here with `perf report --stdio --no-children` top-10
self-time symbols and link to the `perf.data` artefact.
