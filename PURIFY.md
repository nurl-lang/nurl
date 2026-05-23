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

### Phase 5 — String operations (`§2`, ~700 LOC reduction) — DEFERRED 2026-05-23

Attempted; rolled back. Root blocker: every `nurl_str_*` is hot
in `compiler/nurlc.nu`, and the bootstrap stage-0 Python compiler
(`compiler/nurlc.py`) doesn't yet understand the NURL features
that a clean pure-NURL replacement would lean on. Concretely the
Python parser/typechecker stops on:

  - `&`-FFI declarations (`& \`c\` @ memcmp …` — no rule for `&`
    as a top-level decl-starter)
  - `i32` type (Python has only `i` / `u` / `f` / `b` / `s` / `v`
    base types — no sized-integer variants)
  - `& 255` bitwise on `i` operands (Python requires `b` operands
    for `&`)
  - `. p i` pointer-index syntax with a variable index (Python's
    `.` expects a struct field name identifier, not an expression)

Each of these is a non-trivial extension to a 2k-LOC Python
compiler that exists to bootstrap the self-host. The right unblock
is one of:

  - **Upgrade `nurlc.py`** to a broader subset (probably 200-300
    LOC of Python: add `&`-FFI, sized ints, byte-loop primitives).
  - **Retire `nurlc.py`** in favour of a `nurlc_lastgood`-only
    bootstrap. Removes the Python dependency entirely; pure-NURL
    rewrites of compiler-side helpers become unblocked because
    every NURL feature `nurlc_lastgood` supports is available.

Both are out of Phase 5 scope. Moving on; revisit when the bootstrap
chain is reconsidered.

### Phase 6 — Threads / mutex / cond (`§19`, ~290 LOC reduction)

The wrappers are thin pthread thunks. Re-declare directly via
`& \`pthread\` @ pthread_mutex_init …` etc. NURL's existing
`Mutex`/`Cond`/`Thread` opaque handles wrap a pointer; the
allocation + init pattern stays in NURL.

`pthread_create` needs a small C trampoline (1 fn ~10 LOC) because
NURL's closure ABI is `(fn_ptr, env_ptr)` while pthread expects
`void *(*)(void *)` — the trampoline calls the closure shape
correctly. The trampoline is the only residual C from §19.

**Acceptance:** every channel/thread test passes; async-runtime
spawn-via-pthread still works.

### Phase 7 — File & process syscalls (`§4 + §13`, ~500 LOC reduction)

`open`/`read`/`write`/`close`/`mmap`/`stat`/`lstat`/`unlink`/
`mkdir`/`getcwd`/`getenv`/`opendir`/`readdir` — all pure libc
syscalls. Re-declare via pure-NURL FFI in `stdlib/std/fs.nu` (which
already imports several). Path-string massaging logic (relative-
path resolution, `..`-rejection, etc.) moves into NURL.

**Residual C:** only the per-file-error-kind mapping table
(~30 LOC).

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

### Phase 11 — DoS protection (`§23`, ~180 LOC reduction)

Mutex + counter table + per-IP entry growth. The mutex + counter
become NURL HashMap. The mutex is pthread (already FFI'd from
Phase 6). Resulting code is ~80 LOC NURL in
`stdlib/ext/http_dos.nu`.

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

### Phase 13 — Basic I/O thinning (`§1`, ~150 LOC reduction)

`fputs`/`fflush`/`fgets`/`fread`/`fwrite` are pure libc. Wrap
directly via NURL FFI. The deferred-emission output buffer (used
by `gen_closure_expr` in `nurlc.nu`) is the one piece that stays
in C — it's the platform-specific malloc + state machine we
already keep simple.

**Acceptance:** all I/O tests pass; output buffer (the post-
commit 7cf5d5d stack model) is the only retained `§1` code.

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
