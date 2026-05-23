# Purify — Dismantling `stdlib/runtime.c`, Section by Section

> **Goal:** drive C-side runtime weight down to the level peer
> systems languages (Rust, Go, Zig) keep at the libc/LLVM/pthread
> boundary. Everything that does NOT require syscall-shaped FFI or
> external-library state caching should live in pure NURL.
>
> **Starting point (2026-05-23):** `stdlib/runtime.c` is 8 879 LOC
> across 28 sections. Pure-NURL stdlib is 28 809 LOC.
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
| 4  | File & process                    |  403 | OS-glue   | [ ] | shrink — most logic is path massaging, do in NURL |
| 5  | HashMap (string → i64)            |  101 | Compiler  | [ ] | replace with `stdlib/core/hashmap.nu` (already exists) |
| 6a | Lexer                             |  589 | Compiler  | [ ] | rewrite in NURL — biggest single move |
| 6b | Symbol table                      |   72 | Compiler  | [ ] | thin wrapper over §5; goes away with §5 |
| 7  | Codegen helpers                   |   47 | Compiler  | [ ] | counters + label stack → NURL globals |
| 8  | "Last type" sideband              |   24 | Compiler  | [ ] | NURL globals |
| 9  | Memory allocation                 |   39 | OS-glue   | [ ] | keep as 3-fn `malloc`/`free`/`realloc` thunk |
| 10 | (REMOVED 2026-05-01)              |    9 |    —      | [x] | already gone |
| 11 | Math (libm bridge)                |   91 | FFI       | [~] | PARTIAL 2026-05-23 — 12 libm wrappers + iabs/ipow removed (pure-NURL FFI to libm in `stdlib/std/float.nu`; pure NURL algorithms for `int_abs`/`int_pow` in `stdlib/std/int.nu`); -17 C LOC + 14 preamble declares + 14 sym_def entries. Bit access, isnan/isinf, strtod parser retained (type-punning + static state). |
| 12 | Time                              |   67 | OS-glue   | [ ] | pure-NURL FFI to `clock_gettime` + `nanosleep` |
| 13 | CLI tooling                       |  219 | OS-glue   | [ ] | shrink — env/cwd/dir-list are simple wrappers |
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

### Phase 6 — Threads / mutex / cond (`§19`, ~290 LOC) — DEFERRED 2026-05-23

Original plan called for `& \`pthread\` @ pthread_mutex_init …`
direct FFI plus a small `pthread_create` trampoline. Blocked on
two infrastructure gaps the plan didn't anticipate:

  1. **`pthread_mutex_t` / `pthread_cond_t` struct sizes vary by
     platform** — 40 B on glibc x86_64, 64 B on macOS,
     `CRITICAL_SECTION` is a different shape entirely on Windows.
     NURL has no `sizeof` primitive. Either a C-side helper
     exposing the constant (≈5 LOC, defeats the purpose) or a
     dedicated `box[T]` infrastructure with platform-specific
     instantiations is required first.
  2. **The Win32 branch is genuinely different.** `_beginthreadex`
     + `CRITICAL_SECTION` + `CONDITION_VARIABLE` don't share the
     pthread ABI. A pure-NURL replacement either drops Win32 (the
     async runtime depends on it) or adds an OS-dispatch layer
     NURL also lacks today.

Net realistic shrink for §19 without that infra: maybe 80 LOC
(the per-platform wrappers compress, the cross-platform abstraction
stays). Punt until at least one of the two gaps closes.

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

### Phase 8 — Process spawn (`§16 + §16b`, ~700 LOC reduction)

`fork`/`execvp`/`pipe`/`poll`/`dup2`/`close`/`waitpid` are all libc
syscalls. Pure-NURL FFI replaces every direct call. The duplex-
stdio loop (`nurl_proc_read_line` line-buffer accumulator) becomes
NURL code over the FFI primitives.

**Residual C:** the CLOEXEC sideband for exec-error reporting needs
~25 LOC of pipe + dup2 sequencing.

### Phase 9 — Compiler-internal helpers (`§5 + §6sym + §7 + §8`, ~244 LOC reduction)

**The performance-sensitive cut.** Replace the C hashmap +
symbol-table wrapper + codegen counter + sideband with NURL
implementations using `stdlib/core/hashmap.nu` (pure NURL, already
exists). The compiler becomes more self-contained — closer to
"truly self-hosted" — at a runtime cost.

Bootstrap: `nurlc.py` must compile the new `nurlc.nu` correctly.
`hashmap.nu` is pure NURL and uses features `nurlc.py` already
supports (it's part of stdlib).

**Risk:** compiler self-host slows ~2–4× on hashmap-heavy paths
(symbol lookup). Mitigation: profile post-phase; if symbol lookup
dominates, add a small open-addressing fast-path keyed on the
common short identifiers.

**Acceptance:** bootstrap fixed point holds. Self-host wall time
≤ 5× baseline (acceptable for a compiler whose target audience is
LLMs, not iteration speed).

### Phase 10 — Lexer (`§6a`, ~589 LOC reduction)

**The largest single move.** The lexer is a state machine over
bytes: peek/advance/lex_type/lex_val/lex_line. Rewrite in NURL
under `compiler/lex.nu`. Every `nurl_lex_*` call site in
`nurlc.nu` switches to the NURL surface.

The pure-NURL FFI for `read_file_bytes` (Phase 7) gives us the
input. Token table moves to a NURL `Vec[Token]` or similar.

**Risk:** the lexer is THE hottest path in compilation. Pure-NURL
scalar bytes is slow vs. tight C. Mitigation: keep the lexer's
core scan loop in NURL but FFI to `memchr(3)` for whitespace-skip
runs (5 LOC C).

**Acceptance:** every test compiles to byte-identical IR. Self-host
wall time ≤ 6× pre-Phase-9 baseline.

### Phase 11 — DoS protection (`§23`, ~180 LOC) — DEFERRED 2026-05-23

The plan assumed Phase 6's pure-NURL mutex; with Phase 6 deferred,
the lock part still works via the existing `nurl_mutex_*` (which
sit on top of C-side pthread). The genuine blocker is `DosState`
itself: a heap-stable struct with 5 fields including a HashMap
and a Mutex handle. NURL has no `Box[T]` / heap-allocation primitive
for struct values — every `@ Foo { … }` is by-value.

A workable path needs either (a) Phase 6's struct-size infra, or
(b) the same `box[T]` primitive Phase 6 wants. Both are bigger
than this phase's payoff, so park §23 with a clear note in the
runtime.

### Phase 12 — Lib-cache thinning (`§14 + §14b + §21`, ~700 LOC reduction)

`§14` HTTP client: keep the libcurl-easy handle bridge (~150 LOC)
for the request/response state cache; move the request-building +
response-parsing wrappers (currently in C) to NURL. The
URL-encoding helpers move to a NURL module.

`§14b` HTTP streaming: shrink `NurlHttpStream` to the multi-handle
+ pump-callback state (~80 LOC) and move framing into NURL.

`§21` SQLite: the `sqlite3_column_text` borrowed-pointer view is
the one real cache (~50 LOC). The rest is pure-NURL FFI over
`sqlite3_*` symbols.

**Acceptance:** every HTTP / SQLite test passes. Per-request
overhead within 10 % of pre-phase baseline.

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

*Last updated: 2026-05-23 — initial draft. Phase 0 (this
document) ships before any code moves.*
