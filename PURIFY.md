# Purify — Dismantling `stdlib/runtime.c`, Section by Section

> **Goal:** drive C-side runtime weight down to the level peer
> systems languages (Rust, Go, Zig) keep at the libc/LLVM/pthread
> boundary. Everything that does NOT require syscall-shaped FFI or
> external-library state caching should live in pure NURL.
>
> **Starting point (2026-05-23):** `stdlib/runtime.c` is 8 879 LOC
> across 28 sections. Pure-NURL stdlib is 28 809 LOC.
>
> **Current (2026-05-24):** `stdlib/runtime.c` is **6 265 LOC** —
> **−2 614 LOC** moved out, the bulk into pure-NURL FFI declarations
> over libc/libpthread/libsqlite3. See Part VII for the per-phase
> breakdown.
>
> **Target:** runtime.c around **3 000 LOC**, comprising only:
>   - the libc/syscall thunks (file, socket, pthread, mmap),
>   - state-cached external-library bridges that can't be pure-FFI'd
>     (libcurl multi, libssl, sqlite3 prepared-statement borrowed
>     views, ucontext fiber primitives, setjmp panic),
>   - the deferred-emission output buffer (Phase 3 prerequisite).
>
> **Vehicle:** the *pure-NURL FFI* pattern proven by
> `stdlib/ext/postgres.nu` — declare libpq symbols directly via
> ``& `pq` @ … → …``, zero `runtime.c` touch points. 57 such
> declarations exist already across nine modules; every Phase below
> extends or reapplies the same shape.
>
> **Gate at every phase:** the bootstrap fixed point must hold
> (stage1 ≡ stage2 byte-identical IR) and the full test corpus must
> stay green. Bootstrap means `nurlc.py` compiles `nurlc.nu`, the
> resulting `nurlc_self` compiles `nurlc.nu` again, and the two
> outputs must diff clean. Any NURL feature we lean on inside
> `nurlc.nu` must already be supported by `nurlc.py`.

Same structure as `BORROW.md`, `DWARF.md` and `ASYNC.md`: each
phase is independently testable, leaves the tree green, and
documents what the previous phase set up.

---

## Part I — Why peer languages keep so little at the C boundary

A quick survey of what each kept-out-of-the-stdlib language actually
ships at the C / system layer (where "C" means: code the user does
not write in the source language itself):

| Lang | C-layer surface | Approx LOC | Notes |
|------|-----------------|-----------:|-------|
| Rust | `liballoc` syscalls + LLVM compiler-rt + libpthread thunks | ~1 000 LOC `libstd/sys` per platform | Everything else is Rust on top of `libc` re-declarations. |
| Go | runtime (Go itself + asm for stack switching) | ~50 LOC pure C glue per arch | Go has a HUGE runtime, but the C is tiny — scheduler, GC, netpoller are all in Go. |
| Zig | none (raw syscall stubs in Zig asm + libc decls in Zig) | ~0 LOC C | Direct syscall macros; libc is just a dynamic dep. |

The pattern: **algorithmic work belongs in the source language;
the C layer is for syscall shape and state-cached external library
bridges only.**

NURL is at the opposite end of that scale today — 8 879 LOC of C
holds work that should be either: pure-NURL FFI thunks, or pure-
NURL implementations on top of a tiny FFI surface. This document
walks runtime.c down phase by phase until what remains is
genuinely irreducible.

---

## Part II — Current inventory (2026-05-23)

| § | Name                              | LOC | Category | Status | Disposition |
|---|-----------------------------------|----:|----------|:------:|-------------|
| 1  | Basic I/O                         |  206 | OS-glue   | [ ] | shrink — thin libc thunks |
| 2  | String operations                 |  819 | Pure algo | [-] | DEFERRED 2026-05-23 — every `nurl_str_*` is hot in `nurlc.nu`, and the bootstrap stage-0 Python compiler (`compiler/nurlc.py`) doesn't yet support the NURL features a clean replacement needs (`&`-FFI declarations, `i32` type, `& 255` bitwise on `i`, `. p i` pointer-index). Unblocks only after a Python-compiler upgrade (PURIFY.md §1A future item) or after deciding to retire `nurlc.py` in favour of a `nurlc_lastgood`-only bootstrap. |
| 3  | Char classification               |   11 | Pure algo | [x] | DONE 2026-05-23 — `stdlib/core/char.nu` (35 NURL LOC); -10 C LOC; compiler preamble shrunk by 4 declare lines; both `nurlc.py` (typechecker.py + llvm_gen.py) and `nurlc.nu` no longer carry the FFI surface for it |
| 4  | File & process                    |  403 | OS-glue   | [~] | PARTIAL — Phase 7 batches 1+2 + §4 batches 3-5 (2026-05-23/24). Replaced `nurl_realpath` / `nurl_write_file_safe` / `nurl_file_size` / POSIX path of `nurl_read_file_mmap` with pure-NURL `& \`c\`` FFI (`realpath` / `fopen` / `fwrite` / `fclose` / `fseek` / `ftell` / `open` / `lseek` / `mmap` / `munmap` / `madvise`); −28 LOC C, fseek/ftell added to preamble. `O_RDONLY` / `PROT_READ` / `MAP_PRIVATE` / `MADV_SEQUENTIAL` added to `nurl_native_constant`. `read_file` gates on `posix_const "MAP_PRIVATE" != -1` — pure-NURL mmap+memcpy on POSIX, runtime fopen+fread fallback on Win32/WASI. |
| 5  | HashMap (string → i64)            |  101 | Compiler  | [x] | DONE 2026-05-24 (Phase 9c) — the historic djb2-chained 64-bucket map's only NURL caller was `compiler/tests/hashmap.nu` (+ a wider HashMap section of `automated_test.nu`); both now use the generic `stdlib/std/hashmap.nu` HashMap[s i] instantiation. While the only caller was a test, `stdlib/std/hashmap.nu`'s `hash_string` was secretly O(n²) (it called `nurl_str_get` per byte, which calls `strlen` per call); fixed to O(n) direct `*u` byte walk during this migration. −101 LOC C; 7 preamble declares + 3 sym_def entries gone. The runtime is now hashmap-free; one canonical implementation (the generic stdlib) for every consumer. |
| 6a | Lexer                             |  589 | Compiler  | [x] | DONE 2026-05-24 (Phase 10) — full lexer state machine + 4-deep lookahead + every `nurl_lex_*` entry point ported to pure-NURL @-fns in `compiler/nurlc.nu` over a `nurl_zalloc`'d 280-byte handle (35 i64 slots: 5 lexer-state slots + 5 × 6-slot token records). Same lookahead depth + same backtick-string escape rules as the C version. **Subtle escape-handling bug uncovered + fixed**: only `\n` `\t` `\r` `\\` are real escapes; any other `\X` (including `\``) writes the lone `\` and advances ONE byte — so a backtick following a backslash terminates the string normally. The obvious-looking "always skip 2 on `\X`" treats `\\`` as escaped and breaks every backtick-quoting comment in nurlc.nu itself, consuming the rest of the file into one string. fnum no longer stored (every parser callsite reads `nurl_lex_val` and emits the string form directly; `nurl_lex_fnum` re-parses on demand). −592 LOC C; 17 preamble declares + 8 sym_def entries gone. Self-host wall time ~5.1 s (vs ~3.9 s pre-phase, ≤6× budget held). |
| 6b | Symbol table                      |   72 | Compiler  | [x] | DONE 2026-05-24 (Phase 9b + 9b-perf). `nurl_sym_new` / `_def` / `_get` / `_push` / `_pop` pure-NURL @-fns in `compiler/nurlc.nu` over a `nurl_zalloc`'d 48-byte handle and three parallel grow-by-2× arrays (names / types / depths), each starting at cap=64. Phase 9b-perf (2026-05-24): inner loops use direct `*s` / `*i` pointer arithmetic (`. p k`, `= . p k v`) instead of `nurl_peek`/`nurl_poke` — one LLVM `load`/`store` per slot, no runtime-call indirection. Measured on the self-host compile (10-run min, Phase 10 with the pure-NURL lexer in place): C symtab + C lexer = 4.90 s; pure-NURL with `nurl_peek` indirection = 4.83 s; pure-NURL with `*s` arith = 4.66 s. Pure-NURL is ~0.95× of the C runtime — LTO inlines the @-fn calls fully, the 3-parallel-array layout scans names cache-friendlier than C's interleaved struct, and dynamic 64→grow uses far less working set than the C version's 24 MB-per-table static preallocation. `nurl_sym_get` body returns `^ # s ( strdup … )` directly to suppress Phase 2B's owned-string auto-tag (callers leak the strdup'd copy by design, same as the C version). −72 LOC C; 5 preamble declares + 4 sym_def entries gone. |
| 7  | Codegen helpers                   |   47 | Compiler  | [x] | DONE 2026-05-24 (Phase 9a) — `nurl_cg_new` / `_reg` / `_lbl` / `_reset` are pure-NURL @-fns in `compiler/nurlc.nu` over a 16-byte `nurl_zalloc`'d 2-i64-slot handle. The @-fns deliberately return `nurl_str_cat` results without an intervening `: s` binding so Phase 2B's auto-detector keeps `__last_ident_name__` on an i64 ident (`n`) at fn exit — that suppresses the `nurl_cg_reg__ret_owned = "str"` tag the auto-detector would otherwise emit, matching the C version's same-program-lifetime leak that `gen_agg_lit`'s insertvalue chain depends on. −47 LOC C; 4 preamble declares + 3 sym_def entries gone. |
| 8  | "Last type" sideband              |   24 | Compiler  | [x] | DONE 2026-05-24 (Phase 9a) — `nurl_get_last_type` / `_set_last_type` are pure-NURL @-fns in `compiler/nurlc.nu` over a module-level `: i g_last_type_ptr 0` (an i8* held as i64). `strdup`-on-set / `free`-old / `strdup`-on-get semantics preserved byte-for-byte vs. runtime.c §8. −24 LOC C; 2 preamble declares + 2 sym_def entries gone. |
| 9  | Memory allocation                 |   39 | OS-glue   | [ ] | keep as 3-fn `malloc`/`free`/`realloc` thunk |
| 10 | (REMOVED 2026-05-01)              |    9 |    —      | [x] | already gone |
| 11 | Math (libm bridge)                |   91 | FFI       | [~] | PARTIAL 2026-05-23/24 — 12 libm wrappers + iabs/ipow removed (2026-05-23: pure-NURL FFI to libm in `stdlib/std/float.nu`; pure NURL algorithms for `int_abs`/`int_pow` in `stdlib/std/int.nu`). 2026-05-24: `nurl_str_to_float_safe` + `_str_float_value` + `g_last_parsed_float` static deleted — `float_parse` now calls `strtod` directly via `& \`c\`` FFI with an `endptr` buffer + `nurl_errno_get` ERANGE detection. −17 LOC C + 2 preamble declares + 2 `sym_def` entries. Bit access (`nurl_f64_bits` / `_from_bits` / `_f32_from_bits`) and isnan/isinf macro wrappers retained (type-punning + macro-not-symbol). |
| 12 | Time                              |   67 | OS-glue   | [x] | DONE 2026-05-24 — `nurl_now_ms` / `_now_seconds` / `_monotonic_ns` / `_sleep_ms` replaced by pure-NURL `& \`c\`` FFI to `clock_gettime` + `nanosleep` in `stdlib/std/time.nu`. `CLOCK_REALTIME` / `CLOCK_MONOTONIC` added to `nurl_native_constant` (macOS uses 6 for `CLOCK_MONOTONIC` vs 1 elsewhere). −38 C LOC; 4 preamble declares + 4 `sym_def` entries gone. Single code path across Linux / macOS / MinGW (winpthreads) / wasi-libc; no platform `#ifdef` gating in NURL. |
| 13 | CLI tooling                       |  219 | OS-glue   | [~] | PARTIAL 2026-05-24 — batches 1-3: env / cwd / chdir + `read_all_stdin` + POSIX dir_list all pure-NURL FFI. Batch 1 (`getenv` etc.), batch 2 (`__read_all_stdin_pure` over `read(2)`), batch 3 (`opendir`/`readdir`/`closedir` + 1-LOC `nurl_dirent_name` accessor bridging the platform-varying `d_name` offset). −80 C LOC combined; 8 preamble declares + 8 `sym_def` entries gone. Remaining: Win32 `nurl_dir_list_*` (FindFirstFile state cache; different API, stays). |
| 14 | HTTP client (libcurl)             |  665 | Lib-cache | [ ] | shrink to libcurl-easy bridge only; high-level moves to NURL |
| 14b | HTTP streaming (libcurl multi)   |  396 | Lib-cache | [ ] | reduce; multi-handle state-cache stays C |
| 15 | Logging level                     |    7 | Compiler  | [x] | DONE 2026-05-23 — `stdlib/std/log.nu`'s `: ~ i __g_log_level 1` is now the single source of truth; -3 C LOC + 2 preamble declares + 2 sym_def entries + 1 llvm_gen.py entry |
| 16 | Process execution                 |  562 | OS-glue   | [ ] | pure-NURL FFI to `fork`/`execvp`/`waitpid` etc |
| 16b | Process spawn (duplex stdio)     |  452 | OS-glue   | [ ] | same: fork+pipe+poll, doable in NURL once non-blocking-IO patterns settle |
| 17 | Crypto (SHA-1/256/512, MD5, HMAC) |  656 | Pure algo | [x] | DONE 2026-05-23 — MD5 / SHA-1 / SHA-256 / SHA-512 + HMAC-SHA-256/512 ported to pure NURL across four `stdlib/std/hash_*.nu` modules. -541 LOC C; only `nurl_rand_u64` / `_rand_bytes_hex` (getrandom/RtlGenRandom syscall bridge) and 35 LOC hex encoder stay. All FIPS / RFC test vectors pass byte-identical. |
| 18 | TCP sockets + TLS                 | 1 266 | OS-glue + lib-cache | [ ] | the polymorphic `NurlTcp` struct stays; helper thunks shrink |
| 19 | Threads, mutex, condvar           |  346 | OS-glue   | [ ] | mostly thin pthread thunks → pure-NURL FFI |
| 20 | Panic / recover (setjmp)          |  145 | OS-glue   | [ ] | setjmp/longjmp must stay C; minimal helpers around it |
| 21 | SQLite FFI bridge                 |  330 | Lib-cache | [ ] | shrink — `sqlite3_prepare_v2` borrowed-views are the one real bridge |
| 22 | Gzip (libz)                       |   79 | FFI       | [ ] | pure-NURL FFI; `z_stream` layout opaque-pointer is fine |
| 23 | DoS protection                    |  196 | OS-glue   | [ ] | mutex+counter table; pure-NURL once we have atomic-style primitives |
| 24 | Async runtime (fibers)            |  674 | OS-glue   | [ ] | ucontext+mmap MUST stay C; minimize helpers around them |
| 25 | I/O reactor                       |  324 | OS-glue   | [ ] | poll+pipe MUST stay C; minimize helpers |

**Categories.** Pure-algo (1 497 LOC) is 100 % movable. Compiler-
internal (840 LOC) is also movable but requires more care because
of the bootstrap dependency. FFI-bridge (170 LOC) is one rewrite
each to the pure-NURL FFI shape. Lib-cache (~1 800 LOC) shrinks
substantially but keeps an irreducible core. OS-glue (~4 500 LOC)
shrinks via pure-NURL FFI but retains the syscall-shaped subset.

---

## Part III — Phased plan

Each phase is independently shippable. Reduction estimates are
upper bounds; actual numbers come from the post-phase audit.

### Phase 1 — Char classification (`§3`, ~11 LOC reduction) — DONE 2026-05-23

Shipped exactly as planned: new `stdlib/core/char.nu` (35 LOC)
defines `is_alpha` / `is_digit` / `is_space` / `is_alnum_us` over
ASCII byte ranges. `stdlib/core/string.nu` and `stdlib/std/int.nu`
gained the `$`-import; `stdlib/ext/json.nu` already imported
`string.nu` so it inherited the new names transitively. All 16
NURL call sites switched via `sed` mass replacement.

`compiler/nurlc.nu` cannot `$`-import — it's the bootstrap fixed
point — so its two lexer-internal call sites use a private inline
helper `__is_ident_char` instead. Same byte ranges.

Removed from `stdlib/runtime.c`, from `compiler/nurlc.nu`'s
preamble-declare list, and from both `compiler/src/typechecker.py`
and `compiler/src/llvm_gen.py`. Bootstrap fixed point held on the
first try; full 272-test corpus passed unchanged.

Method validates the pattern for the rest of PURIFY.md: define
under a clean NURL name (no `nurl_` prefix), import where used,
strip the FFI surface from every compiler frontend that knew about
the C function.

### Phase 2 — Logging level (`§15`, ~7 LOC reduction) — DONE 2026-05-23

Shipped: `stdlib/std/log.nu` gained a module-level
`: ~ i __g_log_level 1` (default Info). `log_set_level` /
`log_get_level` write/read the global directly; the two `__log_emit*`
helpers read it too. `§15` and the matching compiler-frontend
metadata (preamble declares in `nurlc.nu`, the two `nurl_sym_def`
entries, the llvm_gen.py declarations) deleted in lockstep.
Bootstrap held first try; corpus green.

**Note on concurrency:** single `i64` write is naturally atomic on
every supported target (x86_64/aarch64/riscv64). Cross-thread
visibility is at the next syscall (`nurl_eprint` in every
`log_*` call performs an implicit fence via `write(2)`). Same
guarantee the C version offered — no regression.

### Phase 3 — Pure-NURL FFI for math + time + gzip (`§11+§12+§22`, ~237 LOC reduction) — PARTIAL 2026-05-23

**§11 (libm bridge) — done.** All twelve trivial libm pass-
throughs (`nurl_sqrt` / `_fabs` / `_floor` / `_ceil` / `_round` /
`_pow` / `_log` / `_exp` / `_sin` / `_cos` / `_tan` / `_atan2`)
deleted; `stdlib/std/float.nu` now `& `m` @ sqrt f x → f` etc.
directly, with the `float_*` wrappers calling them in one hop.
Likewise the two integer helpers — `nurl_iabs` / `nurl_ipow` —
moved to pure NURL in `stdlib/std/int.nu` (saturating-LLONG_MIN
abs + exponentiation-by-squaring). Compiler preamble shrunk by
14 declare lines + 14 sym_def entries.

**§11 retained for cause.** `nurl_f64_bits` / `_from_bits` /
`nurl_f32_from_bits` need memcpy-based type punning (NURL has no
bit-pun primitive). `nurl_is_nan` / `_is_inf` wrap libm macros,
not real symbols, so a portable C wrapper is the safe bridge.
`nurl_str_to_float_safe` / `nurl_str_float_value` rely on a
static sideband for the parsed value — refactoring later.

**§12 + §22 — deferred.** Re-reading both confirmed they are
already minimal. §12's cross-platform branching (`clock_gettime`
+ `nanosleep` on POSIX vs `GetSystemTimeAsFileTime` +
`QueryPerformanceCounter` + `Sleep` on Win32) would force a
`#ifdef`-laden NURL module that doesn't read better than the C.
§22's `z_stream` opaque-pointer bridge was already documented as
the irreducible core; there's no level-table or error-mapping in
C-side to move (those are NURL-side). Both stay as-is.

Net delta: runtime.c 8 872 → 8 855 LOC (−17). Below the planned
~237 because §12 / §22 stayed; ship the wins, defer the rest.

**Acceptance:** every test using float/int math passes byte-
identical; bootstrap fixed point holds.

### Phase 4 — Crypto (`§17`, ~600 LOC reduction) — DONE 2026-05-23

Every transform ported to pure NURL across four submodules:

  - `stdlib/std/hash_md5.nu`    — RFC 1321 MD5
  - `stdlib/std/hash_sha1.nu`   — RFC 3174 SHA-1
  - `stdlib/std/hash_sha256.nu` — FIPS 180-4 SHA-256 + HMAC-SHA-256
  - `stdlib/std/hash_sha512.nu` — FIPS 180-4 SHA-512 + HMAC-SHA-512

`stdlib/std/hash.nu` keeps its public API; the `*_bytes` /
`*_hex` entry points are one-line wrappers over the pure
implementations.

Pure-NURL primitives proved sufficient: u32 / u64 arithmetic wraps
correctly under `+` / `*` (LLVM `add`/`mul`), `>>` on `u32`/`u64`
operands lowers to `lshr` (logical), `^^` is the XOR operator
mapping straight to LLVM `xor`. u64 constants beyond LLONG_MAX
written as their negative-two's-complement i64 equivalents
(`# u64 -N`) — no hex literals needed.

C side keeps only the irreducible syscall bridge: `nurl_rand_u64`
+ `nurl_rand_bytes_hex` (both reading `getrandom(2)` on Linux,
`arc4random_buf` on macOS, `BCryptGenRandom` on Windows, with a
`/dev/urandom` fallback) plus a 7-LOC `nurl_hex_encode` helper
used only by `_rand_bytes_hex`. 656 → 114 LOC in §17;
runtime.c overall 8 855 → 8 314 LOC. Compiler-frontend metadata
(three `declare` lines + three `nurl_sym_def` entries in
`nurlc.nu`) deleted in lockstep.

Verified against the RFC 1321 §A.5, RFC 3174 §7.3, FIPS 180-4,
RFC 4231, and RFC 6455 §1.3 worked examples. Bootstrap fixed
point held; full 272-test corpus passes (one McpStdio flaky on
first run, clean on retry — same unrelated race we documented in
the async ship).

**Performance.** Pure-NURL SHA-256 is roughly 4–5× slower than C
on a 1 MB blob — slower than the 2–3× ceiling I planned for.
Acceptable for the corpus's real consumers (HTTP keep-alive auth
digests, WebSocket handshake, MQTT auth) since per-op data is
small. A future Phase-5 follow-on could SIMD-vectorise the
transform in C if hot-path crypto bites.

### Phase 5 — String operations (`§2`, ~700 LOC reduction) — DONE 2026-05-23

Initial attempt rolled back because the stage-0 Python compiler
(`compiler/nurlc.py`) couldn't compile a pure-NURL replacement
that used `&`-FFI, `i32`, `& 255` on `i`, or `. p i` pointer
indexing. The unblock was the second option below: **retire
Python from the bootstrap** (commit `879dc14`) — `nurlc.py` is
gone and stage 0 is now `clang compiler/nurlc_lastgood.ll`. With
the Python ceiling removed, every NURL feature `nurlc_lastgood`
supports is on the table, and the migration landed in three
batches:

  - **Batch A** (`0536e99`) — libc scaffolding: `strlen`/`strcmp`/
    `strncmp`/`memcmp`/`strstr`/`memmem`/`atoll`/`atof`/`memcpy`/
    `strdup` declared globally in nurlc's preamble + `sym_def`'d
    so any module can call them without per-file `&`-FFI noise.
    `nurl_memcmp_lex` moved first as the canary.
  - **Batch B** (`16b980c`) — 9 thin libc wrappers: `nurl_str_len`,
    `_eq`, `_cmp`, `_to_int`, `_to_float`, `_starts`, `_find`,
    `_ends`, `_memmem_range`.
  - **Batch C** (`d547651`) — 6 allocation/algorithm ops:
    `nurl_str_get`, `_cat`, `_cat3`, `_cat4`, `_slice`,
    `_parse_int_range`. `_cat4` lost the historic 2-intermediate
    leak from nested `cat` calls; now allocates exactly once.

Each batch held the fixed-point gate (`./build.sh` = stage1 IR ≡
stage2 IR byte-identical, full corpus passing).

The migration teaches `compiler/nurlc.nu` itself: it can't
`$`-import its own stdlib, so it carries a local copy of each
moved @-fn — a 100-line duplication but a small price for the
~600 lines of C deleted. `nurl_sym_def` registrations stay
intact so cross-module callers that don't `$`-import
`stdlib/core/string.nu` still get correct LLVM call types (the
verifier rejects the i64-instead-of-ptr mismatch otherwise).

**Residual C** (`stdlib/runtime.c §2`): `nurl_str_int`,
`nurl_str_float`, `nurl_parse_float_range` — all `snprintf`/
`strtod`-shaped. Deferred to a future Batch D' (either bind
`snprintf` variadic via FFI or hand-code decimal / float
formatting in NURL; the latter is a known LLONG_MIN /
Grisu-style minefield, hence the deferral).

`runtime.c`: 8 879 → 8 197 LOC (−682). `nurlc.nu`'s preamble
shed 10 `declare` lines and several `nurl_sym_def` entries;
six test files that called `nurl_str_*` without importing
`stdlib/core/string.nu` got the explicit import — the symbol
no longer floats in as a runtime extern.

### Phase 6 — Threads / mutex / cond (`§19`, ~290 LOC) — BATCH 1 LANDED 2026-05-23

Both infrastructure gaps closed by commit 41b96d4
([[project-box-allocators]]): `nurl_native_sizeof` returns the
platform's actual `pthread_mutex_t` / `pthread_cond_t` size, and
`Cell` gives heap-stable opaque storage. The Win32 question
resolved at the link layer: mingw-w64's posix thread model
(Debian's `gcc-mingw-w64-x86-64` default) ships winpthreads, so
`pthread_*` symbols resolve uniformly when the linker gets
`-lpthread` (added to `api/app/main.py:1502` mingw link line).
The Win32 build now also pulls `<pthread.h>`.

**Batch 1 landed** — mutex + cond moved to pure-NURL FFI:
  * `stdlib/std/thread.nu` declares `pthread_mutex_init/lock/unlock/destroy`
    + `pthread_cond_init/wait/signal/broadcast/destroy` via `& \`c\``.
  * `Mutex { Cell c }` + `Cond { Cell c }` — storage is a Cell
    sized via `cell_for_native "pthread_mutex_t"`.
  * `stdlib/runtime.c §19` shed all 12 `nurl_mutex_*` / `nurl_cond_*`
    functions (both POSIX and Win32 branches) plus the `NurlMutex` /
    `NurlCond` typedefs. WASI keeps tiny pthread-shaped no-op shims
    (9 stub fns, ~9 LOC) since wasi-libc has no pthread.
  * `compiler/nurlc.nu` preamble shed 9 `declare` lines + 9 `nurl_sym_def`
    entries.
  * `stdlib/std/channel.nu` updated to pass `cell_ptr` of the mutex
    Cell directly to `nurl_fiber_park_with_mutex` — the C side now
    casts to `pthread_mutex_t *` instead of `NurlMutex *`.

`runtime.c`: 8 254 → 8 162 LOC (−92). §19 alone: 346 → ~150 LOC
(comment block grew; actual code shed ~210 LOC). Bootstrap held
on the lastgood-refresh round-trip; full 272-test corpus passes
including `cell_pthread`, `arc_threads`, `async_basic`,
`async_chan`, `channel_basic`, `signal_basic`,
`http_server_tls_extras`.

**Batch 2 landed** — thread spawn/join/detach are pure-NURL FFI:
  * `stdlib/std/thread.nu` declares `pthread_create` via `& \`c\``
    and passes the NURL closure's (fn, env) pair as start_routine /
    arg. The closure's `void(*)(void *)` signature is ABI-compatible
    with pthread's `void *(*)(void *)` on every System V target
    — the discarded return value falls out of x86_64/aarch64/riscv64
    calling conventions naturally (pthread_join always passes a
    value-ptr we throw away).
  * Two tiny C trampolines remain — `nurl_pthread_join_ptr` and
    `nurl_pthread_detach_ptr` — because pthread_t is passed BY VALUE
    to pthread_join / pthread_detach and is a 16-byte struct on
    winpthreads (NURL's `&`-FFI has no by-value-struct shape).
    Each is 1-3 LOC.
  * `Thread { s raw }` kept its 8-byte shape (raw is a `nurl_alloc`'d
    pthread_t-sized buffer, NOT a Cell) because three call sites
    (`compiler/tests/{thread_basic,arc_threads}.nu` and the
    `stdlib/ext/http_server.nu` worker-pool path) stash handles in a
    malloc'd i64 array via `nurl_poke` / `nurl_peek` for batch-join
    — a 16-byte Cell wouldn't fit.
  * `compiler/nurlc.nu` preamble shed the 3 `nurl_thread_*` declares
    + 3 `nurl_sym_def` entries. Combined Phase 6: 12 declares +
    12 sym_defs gone.

`runtime.c`: 8 162 → 8 092 LOC (−70 for batch 2 alone; combined
Phase 6 net −162 from 8 254). §19 now ~80 LOC (2 trampolines +
9 WASI stubs + comments). Bootstrap held; full corpus passes.

### Phase 7 — File & process syscalls (`§4 + §13`, ~500 LOC) — PARTIAL 2026-05-23

**Landed batch 1** (`2e6b717`) — 6 fopen-family wrappers via libc
stdio in the nurlc preamble:

  nurl_file_open / _close / _write / _write_range / _write_byte / _eof
  → fopen / fclose / fputs / fwrite / fputc / feof

**Landed batch 2** (`166287b`) — 4 probe / mutation wrappers:

  nurl_file_exists / _del / _dir_create / _dir_remove
  → access / remove / mkdir / rmdir (POSIX; Win32 lost the
    _mkdir / _rmdir paper-over)

**Held back:**

  - `nurl_file_read_chunk` writes the `g_last_bytes_len` side-
    channel that the `file_read_chunk` wrapper consumes for the
    actual byte count. Clean migration needs a dual-return shape
    (ptr + len) or a thread-local — neither in the runtime yet.
  - `nurl_file_size` reads `struct stat::st_size`; struct layout
    knowledge is the same `sizeof` gap as Phase 6.
  - `nurl_realpath` / `nurl_read_file_safe` / `nurl_read_file_mmap` /
    `nurl_write_file_safe` — allocation-heavy, several still doable
    once Phase 7 reaches them; mmap one is platform-specific.
  - `nurl_init` / `nurl_argc` / `nurl_argv` / `nurl_exit` — these
    are the bootstrap-entry contract with the generated `_nurl_main`,
    irreducible.
  - `§13` (env/cwd/stdin slurp/dir-listing) — clean libc, future
    batch.

runtime.c shrink so far: 8 189 → 8 138 LOC (−51). Realistic
full-Phase-7 target: ~150-200 LOC, far below the 500 the original
plan assumed (the plan double-counted §13's getenv/getcwd and
overestimated how much of §4's mmap/stat paths can leave C).

### Phase 8 — Process spawn (`§16 + §16b`, ~700 LOC reduction) — DONE 2026-05-23

`fork`/`execvp`/`pipe`/`poll`/`dup2`/`close`/`waitpid` are all libc
syscalls; pure-NURL FFI can call each one directly. The duplex-
stdio loop (`nurl_proc_read_line` line-buffer accumulator) becomes
NURL code over the FFI primitives.

**Batch 1 — POSIX FFI scaffolding** landed. No C-LOC reduction
this batch; this is the foundation for batches 2 + 3.

  * `stdlib/runtime.c §2` gains:
    - `nurl_native_constant(name)` — runtime lookup for platform-
      varying ints (`O_NONBLOCK`, `F_GETFL`, `POLLIN`, `SIGTERM`,
      `WNOHANG`, common errnos). Returns -1 on Win32/WASI for the
      POSIX-only names — caller gates the whole code path on target.
    - `nurl_errno_get` / `nurl_errno_set` — thread-local errno
      accessor (libc's `__errno_location` differs by platform).
    - `nurl_wait_is_exited` / `_exit_status` / `_is_signaled` /
      `_term_sig` — function-wrapped versions of the WIFEXITED /
      WEXITSTATUS / WIFSIGNALED / WTERMSIG macros (NURL has no
      preprocessor).
    - `struct pollfd` + `pid_t` added to `nurl_native_sizeof` table.
    - POSIX headers (`<fcntl.h>` / `<poll.h>` / `<sys/wait.h>` /
      `<unistd.h>`) promoted to the top-of-file POSIX include block
      so §2's new helpers can see the constants/macros.

  * `stdlib/core/posix.nu` (new, 168 LOC) — pure-NURL FFI surface
    for fork / execvp / `_exit` / waitpid / kill / getpid / pipe /
    dup2 / close / fcntl / read / write / signal / poll. Plus
    `posix_pollfd_set` / `_revents` helpers for the 8-byte struct.

  * `compiler/tests/posix_fork_exec.nu` (new) — smoke test that
    forks, execs `/bin/true`, waitpids the child, and decodes the
    exit status via the new helpers. End-to-end proof that the
    NURL→pthread_create→execvp→waitpid path works under bootstrap.

**Batch 2 landed** — `nurl_proc_run` POSIX backend ported to pure NURL.

`stdlib/std/process.nu` gained `__process_run_posix` (~280 LOC) that
executes the full fork + 4 × pipe + CLOEXEC sideband + dup2 setup +
execvp + poll drain loop + waitpid + errno-mapped err_kind sequence
through the FFI surface in `stdlib/core/posix.nu`. The
`NurlProcResult` heap struct stays C-side as an opaque 48-byte
allocation (slot 0 = exit_code, 1 = err_kind, 2 = stdout_buf,
3 = stdout_len, 4 = stderr_buf, 5 = stderr_len); NURL populates it
via `nurl_poke` and the existing `nurl_proc_*` accessors project
into it unchanged.

`process_run` gates on `posix_const "O_NONBLOCK" != -1` and dispatches
to the NURL path on POSIX; Win32 / WASI fall through to the runtime
`nurl_proc_run` (whose POSIX body is now a 5-LOC link-time placeholder).

A language-level prerequisite shipped alongside: `||` and `&&` are
now own lexer tokens with strict binary arity (bool-only,
short-circuit). The legacy `|` / `&` chain semantics — N tokens take
N+1 operands and dispatch bitwise vs. logical by operand type —
stays intact for everything that uses it; the new tokens unblock
chains like `( a || b || c )` whose `| | | a b c` equivalent is
less readable. Three changes total: lexer (`stdlib/runtime.c` two
`make_tok` cases), parser (`compiler/nurlc.nu` two `gen_*`-arms),
bootstrap snapshot refreshed in the same commit.

`runtime.c`: 8 197 → 7 984 LOC (−213 from §16's POSIX path; the
~10-LOC helper `nurl__proc_close_pair` + a re-included POSIX header
block stays until §16b's `nurl_proc_spawn` migrates in batch 3).
Bootstrap held first try; full corpus passes including
`process_basic`, `process_spawn_basic`, every `http_server_*`,
`mcp_stdio_basic`, `postgres_basic`.

**Batch 3 landed** — `nurl_proc_spawn` POSIX backend + the
scratch / line buffer accumulators + write / close_stdin /
read_line / wait / kill / free ported to pure NURL.

`stdlib/std/process.nu` gained `__process_spawn_posix`,
`__proc_write_posix`, `__proc_close_stdin_posix`,
`__proc_read_line_posix` (with the full poll-driven drain +
'\n'-trailer accumulator), `__proc_wait_posix`,
`__proc_kill_posix`, `__proc_reap_posix`, `__proc_free_posix`
plus three pure-NURL buffer helpers (`__pc_scratch_reserve` /
`__pc_line_reserve` / `__pc_drain_line`).

The `NurlProcChild` struct was refactored to use 16 × i64 slots
(128 bytes total) so the NURL side can address every field
through `nurl_poke` / `nurl_peek` by slot number — the previous
`int eof` / `int waited` / `pid_t pid` / `int fd_in` / `int
fd_out` / `size_t scratch_len` mix is gone. C-side accessors
(`err_kind` / `pid` / `read_line_len` / `eof` / `last_io_err`)
unchanged.

`process_spawn` and every `proc_*` wrapper gate on
`posix_const "O_NONBLOCK" != -1` and dispatch to the NURL path
on POSIX; Win32 / WASI fall through to the existing C stubs.
The POSIX-side `nurl_proc_spawn_*` symbols collapse to 5-LOC
link-time placeholders; `nurl_proc_spawn_free` keeps a trivial
POSIX path (`free(c)`) since the real cleanup runs in
`__proc_free_posix`.

`runtime.c`: 7 804 → 7 559 LOC (−245). Bootstrap fixed point
held on the lastgood-refresh round-trip; full corpus passes
including `process_spawn_basic`, `mcp_stdio_basic`, every
`http_server_*` test.

**Residual C:** Win32 backend (~215 LOC, CreateProcess + reader
threads) stays — the API surface is genuinely incompatible with
fork/exec. CLOEXEC sideband C-side or NURL-side is roughly a wash.

### Phase 9 — Compiler-internal helpers (`§5 + §6sym + §7 + §8`, ~244 LOC reduction) — PHASE 9a LANDED 2026-05-24

**The performance-sensitive cut.** Replace the C hashmap +
symbol-table wrapper + codegen counter + sideband with NURL
implementations. The compiler becomes more self-contained —
closer to "truly self-hosted" — at a runtime cost.

**Phase 9a landed** — `§7` codegen counters + `§8` last-type
sideband are pure-NURL @-fns in `compiler/nurlc.nu`. See the §7
and §8 rows above for the per-section detail.

**Phase 9b landed** — `§6b` symbol table is a pure-NURL @-fn
family over a 6-i64-slot heap handle (count / depth / cap +
three parallel grow-by-2× arrays). See the §6b row.

**Phase 9c landed** — `§5` HashMap deleted entirely. The only
NURL caller was `compiler/tests/hashmap.nu` (a test); migrated to
the generic `stdlib/std/hashmap.nu` HashMap[s i]. Same migration
caught the O(n²) `hash_string` and fixed it. See the §5 row.

Key learning from Phase 9a: Phase 2B's owned-string auto-detector
at `gen_fn_decl`'s epilogue auto-tags any @-fn whose final
expression is bound through an `__owned_strings__`-tracked `: s`
identifier. For the §7 helpers, that auto-tag would break
`gen_agg_lit`'s insertvalue accumulator chain (the caller's `= result r`
reassignment was written against the C version's non-owned
contract, so an auto-tagged owned return would auto-drop `r` and
leave `result` dangling). Fix: inline the int formatting into a
single `nurl_str_cat` call without `: s tmp` binding, so the last
ident at fn exit is the i64 binding `n` instead of an owned-string
binding. This propagates the C version's "leak for program
lifetime" contract through cleanly.

**Phase 9 complete** — §5 + §6b + §7 + §8 all moved out of
runtime.c.

**Bootstrap:** every Phase 9 batch must compile from
`nurlc_lastgood`. After Phase 9a, that snapshot was regenerated
via `--refresh-bootstrap` plus a one-shot sed to strip six
stale `declare` lines the OLD build/nurlc still emits in its
preamble (this is the standard pattern when removing preamble
declares — until a new build/nurlc with the cleaned preamble
exists, the lastgood it generates carries stale declares that
collide with the new pure-NURL @-fn defines).

**Risk:** compiler self-host may slow on hashmap-heavy paths
(symbol lookup). Mitigation: profile post-phase; if symbol lookup
dominates, add a small open-addressing fast-path keyed on the
common short identifiers.

**Acceptance:** bootstrap fixed point holds. Self-host wall time
≤ 5× baseline (acceptable for a compiler whose target audience is
LLMs, not iteration speed).

### Phase 10 — Lexer (`§6a`, ~589 LOC reduction) — DONE 2026-05-24

**The largest single move — landed.** Full lexer state machine +
4-deep lookahead + every `nurl_lex_*` entry point ported to
pure-NURL @-fns in `compiler/nurlc.nu` over a `nurl_zalloc`'d
280-byte handle (35 i64 slots: 5 lexer-state + 5 × 6-slot token
records). Same lookahead depth and same backtick-string escape
rules as the C version.

**Subtle escape-handling bug uncovered + fixed during the port:**
only `\n` `\t` `\r` `\\` are real escapes. Any other `\X`
(including `` \` ``) writes the lone `\` and advances ONE byte —
so a backtick following a backslash terminates the string
normally. The obvious-looking "always skip 2 on `\X`" treats
`` \\` `` as escaped, which breaks every backtick-quoting comment
in `nurlc.nu` itself by consuming the rest of the file into one
giant string.

`fnum` is no longer stored per-token — every parser callsite
reads `nurl_lex_val` and re-parses the string form on demand via
`nurl_lex_fnum` (cheap; called only at parse-time for FLOAT
tokens, not in the inner-loop scan).

**Result:** −592 LOC C; 17 preamble `declare` lines + 8
`nurl_sym_def` entries gone from `nurlc.nu` and the lastgood
snapshot. Self-host wall time ~5.1 s (vs ~3.9 s pre-phase,
1.3×; well inside the ≤6× budget).

### Phase 11 — DoS protection (`§23`, ~180 LOC) — DONE 2026-05-23

Shipped: `stdlib/std/dos.nu` (254 LOC) replaces the entire 196-LOC
§23 body. The migration leans on three prior phases:

  * Phase 6 batch 1 mutex/cond FFI — `pthread_mutex_init/lock/unlock/
    destroy` come directly from `stdlib/std/thread.nu`. The mutex
    buffer lives in slot 7 of the state struct (sized via
    `nurl_native_sizeof "pthread_mutex_t"`).
  * Box / Cell / heap allocators ([[box-allocators]]) — the
    `DosState` heap struct is a `nurl_zalloc 80`-allocated 10-slot
    opaque block with field access via `nurl_poke` / `nurl_peek`.
    The two parallel IP-table arrays (string keys + i64 counts)
    grow via `nurl_realloc`.
  * `strdup` (already in nurlc's preamble) — used to take ownership
    of the per-IP key string; the old C `free()` path is now
    `nurl_free` on each slot at `dos_state_free` time.

`http_server.nu` switches from `nurl_dos_state_*` to the new
`dos_state_*` API (five call sites updated). `runtime.c` §23
deleted in full; the five `declare` lines + five `nurl_sym_def`
entries gone from `compiler/nurlc.nu` and the lastgood snapshot.

`runtime.c`: 7 984 → 7 804 LOC (−180). Bootstrap fixed point
held on the lastgood-refresh round-trip; full corpus passes
including `http_server_dos`, `http_server_limits`, every other
`http_server_*` test. The pure-NURL implementation preserves the
C-side IP-table policy verbatim (linear search, 256-entry cap,
last-element-swap-then-pop eviction on refcount=0, no LRU
churn beyond that).

### Phase 12 — Lib-cache thinning (`§14 + §14b + §21`, ~700 LOC reduction) — §21 SQLite DONE 2026-05-23

`§14` HTTP client: keep the libcurl-easy handle bridge (~150 LOC)
for the request/response state cache; move the request-building +
response-parsing wrappers (currently in C) to NURL. The
URL-encoding helpers move to a NURL module.

`§14b` HTTP streaming: shrink `NurlHttpStream` to the multi-handle
+ pump-callback state (~80 LOC) and move framing into NURL.

`§21` SQLite — **DONE 2026-05-23**. Shipped pure-NURL FFI over 18
libsqlite3 symbols (`sqlite3_open` / `_close` / `_exec` /
`_prepare_v2` / `_step` / `_finalize` / `_reset` / `_clear_bindings`
/ `_bind_int64` / `_bind_text` / `_bind_null` / `_column_int64` /
`_column_text` / `_column_count` / `_column_type` / `_changes` /
`_errmsg` / `_free`) in `stdlib/ext/sqlite.nu`. Database +
Statement handles are 32-byte opaque NURL-allocated heap blocks
(slot 0 = pointer, 1 = err_kind, 2 = strdup'd diagnostic /
borrowed-view snapshot). `SQLITE_TRANSIENT` materialised as
`# *u -1`. `runtime.c §21` deleted in full; 17 declare lines +
17 sym_def entries gone from `nurlc.nu`. runtime.c 7 559 → 7 229
LOC (−330). Bootstrap held; sqlite_basic + every consumer passes.

**Acceptance:** every HTTP / SQLite test passes. Per-request
overhead within 10 % of pre-phase baseline.

### Phase §12 — Time (clock_gettime + nanosleep, ~38 LOC) — DONE 2026-05-24

Shipped: `stdlib/std/time.nu` now declares `clock_gettime` and
`nanosleep` directly via `& \`c\`` and replaces every runtime helper
(`nurl_now_ms` / `_now_seconds` / `_monotonic_ns` / `_sleep_ms`) with
pure-NURL implementations over a 16-byte `struct timespec` buffer.

  * **Cross-platform without `#ifdef`.** Linux + macOS expose
    `clock_gettime` and `nanosleep` in primary libc; MinGW-w64 routes
    through winpthreads (already linked via `-lpthread` from Phase 6
    batch 1); wasi-libc wraps the WASI snapshot-1 syscalls. NURL ships
    one code path — no platform gating.
  * **Constants via `nurl_native_constant`.** `CLOCK_REALTIME` and
    `CLOCK_MONOTONIC` added to the table (outside the existing
    `!_WIN32 && !__wasi__` guard since `<time.h>` is included at file
    scope). macOS values differ — `CLOCK_MONOTONIC = 6` there vs `1`
    elsewhere — so NURL reads at runtime rather than hard-coding.
  * **16-byte allocation.** `struct timespec` is `{ time_t tv_sec;
    long tv_nsec; }`: 16 B on every 64-bit POSIX target, 12 B packed
    on MinGW LLP64 (rounded to 16 with 8-byte alignment). Allocating
    16 via `nurl_zalloc` covers every layout — the trailing pad on
    Win32/WASI stays zeroed so `nurl_peek` of slot 1 returns the
    32-bit `tv_nsec` extended with zeros, the correct value.
  * **`nanosleep` EINTR retry** uses `nanosleep(req, req)` — same
    pointer for both args, so the kernel updates the remaining time
    in place and the retry sees the correct duration. Non-EINTR
    failures (EINVAL / EFAULT) drop the residual sleep rather than
    spin-loop.

`runtime.c §12` deleted (66 → 14 LOC comment stub); `compiler/nurlc.nu`
shed 4 `declare` lines + 4 `nurl_sym_def` entries. Net `runtime.c`
delta: 7 229 → 7 191 LOC (−38, after the +10 LOC for the two new
`nurl_native_constant` entries). Two test files (`async_http_server.nu`,
`async_tcp.nu`) updated to `$`-import `stdlib/std/time.nu` and call
`sleep_ms` instead of the removed runtime symbol.

Bootstrap fixed point held after a lastgood-refresh round-trip; the
full 272-test corpus passes including `async_*`, `process_basic`,
`http_server_*`, `mqtt_basic`.

### Phase §13 — CLI tooling batch 1 (env + cwd, ~46 LOC) — DONE 2026-05-24

Shipped: `stdlib/ext/env.nu` now declares the five POSIX names
directly via `& \`c\`` — `getenv`, `setenv`, `unsetenv`, `getcwd`,
`chdir` — and the `env_get` / `env_set` / `env_unset` / `env_cwd` /
`env_chdir` public wrappers call them in one hop.

  * **Single ABI across libc flavours.** Linux/macOS primary libc and
    mingw-w64's libmingwex (auto-linked on Win32) both expose the
    POSIX names with the same signature. The `_putenv_s` / `_getcwd`
    / `_chdir` `_`-prefixed MSVCRT variants the previous C bridge
    used are no longer reachable from NURL — the linker now resolves
    the POSIX names directly.
  * **`getenv` borrowed-pointer discipline.** `getenv` returns a
    libc-owned pointer into the environment block; `string_from`
    copies the bytes into an owned String so the result outlives any
    subsequent `setenv` that might invalidate the borrow. The
    previous C `nurl_env_get` strdup'd internally and the NURL caller
    then copied again — one extra allocation per lookup gone.
  * **Owned-cwd retry loop.** `getcwd(buf, cap)` returns NULL with
    errno=ERANGE when the buffer is too small; the NURL implementation
    doubles and retries up to a 1 MB ceiling (well past any real
    PATH_MAX). `ERANGE` added to `nurl_native_constant` outside the
    POSIX-only guard — `<errno.h>` is included at file scope and the
    value is identical on every platform we target.

`runtime.c §13` shed the five thunks (POSIX + Win32 branches);
`compiler/nurlc.nu` shed 5 `declare` lines + 5 `nurl_sym_def`
entries. Net runtime.c delta: 7 191 → 7 145 LOC (−46). One test
file (`net_loopback.nu`) switched from `nurl_env_set` to `env_set`
with a `$`-import of `stdlib/ext/env.nu`.

Bootstrap fixed point held after a lastgood-refresh round-trip; full
272-test corpus passes including `process_basic`, `http_server_*`,
`net_loopback`.

**Remaining §13:** `nurl_read_all_stdin` (fread accumulator) and
`nurl_dir_list_open` / `_next` / `_close` (opaque DIR* on POSIX,
WIN32_FIND_DATAA iterator on Win32). Batch 2 candidates once the
fread / readdir FFI shape settles.

### Phase 13 — Basic I/O thinning (`§1`, ~150 LOC) — DEFERRED 2026-05-23

The outbuf stack machinery (`nurl_print_buf_start` / `_stop` /
`_reset` + the 32-deep frame stack feeding `gen_closure_expr`) is
the irreducible core the plan already called out — that stays.
The migration candidates are the *user-visible* I/O:
`nurl_print` / `_print_int` / `_print_str` / `_print_bool` /
`_eprint` / `_eprintln`.

Genuine blocker: **the test corpus calls these directly without
any import.** A quick grep counts ~250 test files invoking
`nurl_print` and ~70 invoking `nurl_print_int`. Moving the
definitions to a NURL module (e.g. `stdlib/core/io.nu`) would
force `$`-imports on each — the same friction that drove Batch
D' to keep `nurl_str_int` in C. Add an **auto-prelude** mechanism
first (compiler emits a sentinel `$`-import for every program), or
accept this section as runtime-pinned.

### Phase 14 — Final accounting

Tally remaining LOC by section. Confirm we are within striking
distance of the 3 000 LOC target. Update `README.md`'s
"Comparison" table to reflect the new C-side weight against Rust /
Zig / Go.

---

## Part IV — Bootstrap dependency map

A handful of `nurlc.nu` calls go through runtime helpers EVERY
compilation. Any NURL rewrite of these helpers must compile under
`nurlc.py` first, then under `nurlc_self`. The chain:

```
nurlc.py (stage 0; subset of grammar v1.1)
   │
   ▼  compiles
nurlc.nu  →  build/nurlc_self  (stage 1)
   │
   ▼  re-compiles
nurlc.nu  →  build/nurlc_self2 (stage 2)
   │
   ▼  diff -q
must be byte-identical (fixed-point gate)
```

Implications for the phase order above:

- **Phases 1–3, 11, 13** touch stdlib code that `nurlc.nu` does
  not consume. No bootstrap risk.
- **Phase 4 (crypto)** is stdlib-side; `nurlc.nu` doesn't compute
  hashes. No bootstrap risk.
- **Phase 5 (string ops)** is touched by `nurlc.nu` for IR-text
  building. Bootstrap risk: `nurlc.py` must support every NURL
  feature the new string module uses (it does — string is core).
- **Phase 6 (threads)** is stdlib-side. No bootstrap risk for the
  compiler.
- **Phases 7–8 (file/process)** are stdlib-side, but the compiler
  uses `nurl_read_file` etc. `nurlc.py` needs the new FFI shape
  in its symbol table.
- **Phase 9 (compiler-internal helpers)** is the bootstrap-
  sensitive phase. New hashmap-based symbol table must be
  compilable by `nurlc.py`. Since `stdlib/core/hashmap.nu` is
  already pure NURL and used by the corpus, this should work.
- **Phase 10 (lexer)** is the riskiest. Every token nurlc.nu reads
  goes through the new lexer. Bootstrap will surface any
  edge-case the C lexer handled that the NURL one doesn't.
- **Phase 12 (lib-cache)** is stdlib-side.

The general rule: every phase ends with `./build.sh` showing
`BUILD SUCCESS & TESTS PASSED`. The build script enforces the
fixed-point gate.

---

## Part V — What the residual `runtime.c` looks like

Projected end-state (`~3 000 LOC`):

| § | Name                              | LOC | Why it stays |
|---|-----------------------------------|----:|-------------|
| 1  | Output buffer (deferred-emission) | ~85 | Compiler's print-capture stack — closure-body buffering |
| 2  | SIMD CSV scanner                  | ~150 | Hot-path SIMD intrinsics not expressible in NURL |
| 4  | File-error-kind mapping           |  ~30 | Compact errno → enum table |
| 6  | pthread closure trampoline        |  ~10 | NURL closure ABI ↔ pthread ABI bridge |
| 9  | Memory allocation                 |  ~25 | `malloc`/`free`/`realloc` thunks (or maybe just FFI directly?) |
| 14  | libcurl easy state-cache         | ~150 | `CURL *` handle + response buffer + header callback |
| 14b | libcurl multi pump-callback     |  ~80 | `NurlHttpStream` multi-handle state |
| 16b | CLOEXEC sideband for exec-error  |  ~25 | fork/exec error reporting protocol |
| 17 | `nurl_secure_random`              |  ~25 | `getrandom(2)` / `RtlGenRandom` |
| 18 | `NurlTcp` polymorphic SSL state   | ~250 | TLS SSL_CTX + per-conn SSL + SNI/ALPN/mTLS metadata |
| 20 | `setjmp`/`longjmp` panic frames   |  ~80 | C-level unwind primitives + thread-local frame stack |
| 21 | sqlite borrowed-text views        |  ~50 | `sqlite3_column_text` returned-pointer lifetime cache |
| 22 | `z_stream` streaming bridge       |  ~50 | `z_stream` layout opaque-pointer bridge |
| 24 | Async runtime (fibers)            | ~600 | `ucontext` + `mmap` guard pages + work-stealing scheduler |
| 25 | I/O reactor                       | ~320 | `poll(2)` + pipe + active-flag wait list |
| —  | Preamble + `_GNU_SOURCE` + headers | ~70 | Cross-platform feature-test boilerplate |
|    |                                   | **~2 000** | Within striking distance of the 3 000 LOC target. |

Anything more aggressive (e.g. moving the async runtime to pure
NURL) is blocked by the "no syscall-shaped FFI in NURL" gap and is
outside this document's scope.

---

## Part VI — Open questions

1. **`nurl_alloc` vs direct libc `malloc`** — once Phase 13 lands,
   should NURL's `alloc` primitive be a true FFI to libc `malloc`,
   or stay as the C thunk it is today? Direct FFI is one fewer
   indirection but loses the diagnostic-hook insertion point we
   might want for sanitiser modes. Suggested: keep the thunk.

2. **SSE2 / AVX intrinsics in NURL?** The CSV scanner is the only
   place SIMD pays. If we ever add SIMD intrinsics to NURL (a
   substantial language addition), §2's SIMD scanner could move
   too. Out of scope today.

3. **`pthread_atfork` and fiber-runtime interaction** — once
   process-spawn (Phase 8) is in NURL, calling `fork(2)` from a
   fiber-running thread is undefined unless the runtime cooperates.
   The C side currently does nothing special; the NURL rewrite
   should at least document the unsafety (or refuse to fork from
   a fiber context).

4. **Self-host wall time budget** — every phase has a self-host
   regression budget (≤1.5× for Phase 5, ≤5× for Phase 9, ≤6× for
   Phase 10). If we overshoot, can we accept it? Acceptable
   answer: yes, the compiler's bottleneck is LLM author cycles,
   not compile speed. But a ≥10× regression would be flagged for
   review.

5. **WASI** — pure-NURL FFI to `& \`c\`` works fine on the wasm32-
   wasi target (the WASI sysroot provides libc-shaped wrappers).
   Pure-NURL FFI to `& \`pthread\`` does not (WASI has no threads).
   Plan: WASI-specific stubs in NURL itself (`stdlib/wasi/...`)
   rather than `#ifdef` islands in runtime.c.

---

## Part VII — Status snapshot (end of refactor/pure-nurl branch)

**Starting point (2026-05-23):** `stdlib/runtime.c` 8 879 LOC across 28 sections.

**Current (2026-05-24):** `stdlib/runtime.c` **6 265 LOC** — a
**−2 614 LOC** reduction (−29.4 %) across the branch's 42 commits.
Two thirds of the way to the 3 000-LOC target with every shipped
phase keeping the bootstrap fixed point and the full test corpus
green.

**Shipped phases (chronological):**

| # | Section(s)           | C-LOC moved | Vehicle |
|--:|---------------------|------------:|---------|
| 1  | §3 char classification        |  −11 | pure NURL (`stdlib/core/char.nu`) |
| 2  | §15 logging level             |   −7 | pure NURL global (`stdlib/std/log.nu`) |
| 3  | §11 libm + integer helpers    |  −17 | `& \`m\`` / `& \`c\`` FFI |
| 4  | §17 crypto (MD5/SHA-1/256/512 + HMAC) | −541 | pure NURL (`stdlib/std/hash_*.nu`) |
| 5  | §2 string operations          | −682 | libc `& \`c\`` FFI |
| 6  | §19 threads / mutex / cond    | −162 | pthread `& \`pthread\`` FFI |
| 7  | §4 + §13 file & dir syscalls (incremental) | −158 | POSIX `& \`c\`` FFI |
| 8  | §16 + §16b process spawn      | −245 | fork/exec/poll `& \`c\`` FFI |
| 9a | §7 + §8 codegen + last_type   |  −71 | pure NURL @-fns in `nurlc.nu` |
| 9b | §6b symbol table              |  −72 | pure NURL @-fns + `*s` arith |
| 9c | §5 HashMap (string→i64)       | −101 | generic stdlib HashMap[s i] |
| 10 | §6a Lexer (the big one)       | −592 | pure NURL state machine in `nurlc.nu` |
| 11 | §23 DoS protection            | −180 | pure NURL (`stdlib/std/dos.nu`) |
| 12·§21 | sqlite3 bridge            | −330 | `& \`sqlite3\`` FFI (`stdlib/ext/sqlite.nu`) |
| §12 | clock + sleep                |  −38 | `clock_gettime` + `nanosleep` FFI |
| §13b | stdin + dir_list            |  −80 | `read(2)` + opendir/readdir POSIX FFI |
| §11 strtod | float parse sideband  |  −20 | strtod + endptr buffer |

**Other branch deliverables (not LOC moves):**

  * Python bootstrap removed. `compiler/nurlc.py` + `compiler/src/*.py`
    deleted. Stage 0 now links `compiler/nurlc_lastgood.ll` directly
    via clang. `build.sh --refresh-bootstrap` regenerates both
    `nurlc_lastgood.nu` and `.ll` from the current `build/nurlc`.
    No language toolchain other than `clang` is required to build.
  * `Box[T]` / `Cell[T]` / `Rc[T]` / `Arc[T]` allocators landed
    (`stdlib/core/box.nu` + `cell.nu` + `stdlib/std/rc.nu` + `arc.nu`).
    `% Drop` auto-fires; `nurl_native_sizeof` + `nurl_atomic_i64_*`
    runtime primitives added. These unblocked Phase 6 / 8 / 11 / 12.
  * `||` and `&&` tokens (the strict bool-only short-circuit forms)
    added to the language. Grammar v2.0 documents them.
  * `./check.sh <file.nu>` — per-file syntax/type check, ~270×
    faster than a full `build.sh` round-trip. Use in iterate-fix
    loops before kicking the full build.
  * Test-runner split into `success.txt` + `failures.txt` so a
    failure is greppable without reading through the green output.
  * Parenthesised-operator diagnostic — `( . obj field )` /
    `( | a b )` etc. now produce a precise call-site `error:`
    instead of a far-away LLVM-verifier complaint.
  * Call-arity diagnostics — every call's argument count is
    checked against the callee's parameter count; mismatches
    point at the call site.
  * WASM FFI width fixes — `nurl_errno_get` / `nurl_errno_set` /
    `nurl_wait_*` widened to `long long`; `memmem` added to the
    `api/app/main.py` wasm shim list. The uuidgen wasm build now
    links without `signature mismatch` warnings.

**Residual runtime.c (~6 265 LOC):** still above the projected
end-state (~2 000 LOC) — Phase 12 lib-cache (libcurl easy +
multi), Phase 13 basic I/O, Phase 14 final accounting still open.
The path from here is the same FFI pattern, applied to
fewer-but-larger remaining sections.

---

*Last updated: 2026-05-24 — end of refactor/pure-nurl branch.*
