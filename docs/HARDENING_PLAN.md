# Pre-production hardening: views, sealed representations, exclusive calls

Goal (owner, 2026-10-08), branch `pre-production-hardening`: close the
`Slice` hole (h32), the one known exception to the 0.71.0 guarantee
([`MEMORY.md` §6.2](MEMORY.md)), with the best design rather than a patch;
fix every hole found on the way at its root; keep or improve performance.
This is the v1.0 hardening pass of [`improvements_for_v1.md`](improvements_for_v1.md)
§2 ("close the remaining safe-looking ownership holes", "check all
allocation and capacity arithmetic").

> Exit criterion: `tools/fuzz/holes/check.sh` reports `holes: 0` over every
> probe, held by CI; MEMORY.md §6.2 states the guarantee with **no**
> exception; every gate below is green; compile and run time are at or
> below the baseline.

## Status (2026-10-08): done

Every class below is closed at its root, with the probes it found:

| class | closed by | probes |
|---|---|---|
| V — views are values | the borrow walk tracks a view through structs, Options, containers, closures, globals and results (source expressions evaluated after the module) | h32–h50, h80, h81, h89–h95 |
| R — sealed representations | literals, raw-field reads/writes and casts of raw representations are `unsafe`; caller-trusting stdlib functions are `unsafe` to call | h51–h62 |
| A — exclusive calls | a container a call may change cannot also reach it as another argument (`callx` rows) | h63–h68 |
| C — closure effects | a closure's run applies its body's effects to its captures (`pendeff` rows) | h69–h71 |
| K — accessors by summary | raw provenance decides what a raw function lends, writes, reallocates | h72–h76 |
| P — field paths | a field argument lends and loses its field; nested fields are their binding's storage | h82–h88 |
| G — allocation arithmetic | `alloc_size` / `alloc_count_add` / `alloc_grow_cap` / `alloc_grow_pow2` | h77–h79 |
| temporaries | a part of a temporary is copied; one that cannot be is an error; an instance of a generic callee is asked whether its result is its own | h96, h105 |
| F — the foreign surface | `"nurl.raw"` builtins, raw-result calls and `*u` buffer types are `unsafe` to call; safe forms beside each; generic stdlib internals stay internal | h97–h101, h103, h104 |
| N — null strings | runtime prints and `"nurl.cstr"` parameters read null as `""` | h102 |
| M — method calls | a statically dispatched call asks its impl what a call of any function asks; a `dyn` call asks every impl at once (`m__dyn__T`, the union of their summaries; handle results owned per call), and impls that disagree on keeping an argument, or keep the receiver, are rejected; a raw method signature is raw to call | h106, h107, h110–h112 |
| O — ownership summaries | a `sink` parameter handed back is the caller's own value, not a second name of its argument; a raw-pointer parameter hands nothing over | h108, h109 |
| S — owning strings | a string binding that owns its buffer (tracked, or guarded) is an owner: a copy of it is a view of the buffer, ending when the binding changes or ends; one handed back by name goes to the caller; a binding that copies what it is given holds a fresh value (no false borrow); a mutable string born from a call or a field that hands nothing over gets an owner slot (no leak); an owned string field, and an owning binding given a field, copy what is not fresh and free what they replace | h113–h127 |
| L — raw strings in values | in safe code a raw string held by a struct, an option, an enum, a slice or a container is a view (MEMORY.md §2.13): a fresh one stored there, or handed to a parameter that keeps it, is rejected (a call answering per call: at module end); a closure or literal handed back as written is checked for what its views point into | h128–h141 |

Gates (pre-production-hardening tip): `tools/fuzz/holes/check.sh` 129
probes, 113 rejected, 16 clean, **holes: 0** (in CI's build-test job);
`./build.sh` fixed point and 1226 tests pass; ASan/UBSan/LSan corpus 0
failures; `tools/leakgate.sh` zero leaks. Every tracked `.nu` file outside
the stdlib and the compiler (1884), compiled by each side's own toolchain:
1397 compile on main and the same 1397 here — after two package sites the
view checks rejected were fixed (anomaly's issuer template, a read of freed
memory; nurl-mcp's `--token`, a global view of `main`'s String; CHANGELOG).
Performance, against main back to back in one environment
(instructions:u): self-compile 0.73 % fewer on the same input (12.59 G
against 12.68 G); every runtime kernel of the bench set the same or fewer —
blake2b −0.18 %, x25519 −0.03 %, chacha20 / poly1305 / sha512 −0.01 %, the
rest within ±0.01 % — except json_parse, +0.22 % (+331 of 154 K
instructions: the null-safe string length and the checked growth of
classes N and G).

## Baseline (main 92a83993, 2026-10-08, clean `build/`)

| measure | value |
|---|---|
| `./build.sh` | build 1m05s, tests 2m35s (1225 tests), wall 3:40 |
| self-compile `nurlc compiler/nurlc.nu` | 11.21 G instructions:u, 8.67 G cycles, 2.22 s, max RSS 74 MB |
| compile set (46 package mains + 10 tests/stdlib) | 34.31 G instructions:u |
| `bench/perfstat.sh` micro set | saved TSV (15 kernels; e.g. hash_join 321.6 M instr) |
| `tools/vec_parity.sh` | safe = raw on sum / put / get |
| sanitized corpus (`run_san_tests.sh`) | 1205 pass, 20 skip, 0 SAN_FAIL (315 s) |
| `tools/leakgate.sh` | zero leaks |
| reject fuzz (`FUZZ_GEN=reject fuzz.sh 1 400`) | 400/400 caught |
| hole probes | **48 holes** (h32 + 47 found while preparing this plan) |

## The holes, by root cause

Probing the shapes around h32 found it is one instance of seven classes.
Every probe below compiles today without `unsafe` and faults under
ASan/LSan.

| class | probes | root cause |
|---|---|---|
| **V — views not tracked as values** | h32–h50 | A view (a pointer into another value's buffer) is tracked only while it is a `*T` / `s` *binding*. Held in a struct (`Slice`, `ProtoReader`, a user struct, h37/h46), an Option (h49), a container (h40), a closure (h39), a global (h47), returned through a function (h35/h48), assigned to a longer-lived binding (h50) or sent to a thread (h44), it is an untracked copy. Handle borrows escape the same ways (h50). |
| **R — representations can be forged** | h51–h62 | Safe code can build a struct literal of a raw-representation type (`Slice`, `Vec`, `Box`), write its fields, read its raw fields, or cast an integer to it (h58/h59: the cast check covers only `*T` targets). Stdlib functions whose safety depends on the caller (`slice_from_raw`, `vec_borrow_raw`, `vec_set_len`) are callable from safe code. |
| **A — aliased call arguments** | h63–h68 | A call may pass a container to a parameter that mutates it together with a borrow or view of it (or the same container twice); inside the callee the two names are unrelated, so the mutation leaves the other dangling. |
| **C — closure effects** | h69–h71 | A closure that mutates a captured container ends views/borrows of it only when the closure is *built* and only for `*T`/`s` views; running it later (directly or through a callee) is not a mutation of the capture. |
| **K — container accessors by name** | h72–h76 | `vec_get` is a borrow by name (`__last_value_borrow__`); `map_get`, `box_get`, `deque_get`, `btree_get` results are not, so `map_set` / `box_set` / `deque_pop_*` / `btree_set` replacing the value leave them dangling. |
| **G — allocation arithmetic** | h77–h79 | `n * size` / `n + 1` wrap in `vec_with_cap`, `vec_zeroed`, `string_with_cap`: a tiny buffer with a huge capacity or length. |
| **F — the trusted foreign surface** | (t72: `memmem`) | Foreign functions declared in the standard library are callable from safe code, and some take a buffer as `s` with a caller-given length (`memmem`, `strnlen`, `fwrite`, `nurl_fast_atof`, …), as do 57 NURL-level stdlib functions: a short buffer with a long length reads or writes past it. |
| **N — null strings** | (t74) | `# s 0` is legal in safe code (174 sites outside the stdlib) and `getenv` returns null, but `nurl_println` / `nurl_str_len` / `nurl_str_cat` of a null `s` crash. |

## Design

### V. Views are values (closes h32)

A **view** is a value that points into a buffer another binding owns:
`string_data` / `vec_data` / `slice_data` results, a `Slice`, and anything
that holds one — a struct with a view field, an Option or Result of one, a
container of them, a closure that captured one. Every view carries its
**sources**: the owners whose buffers it points into (borrows flatten to
owners, as today).

- **Sources are computed where a view is produced**: the producer
  built-ins; a call whose result type can hold a view (sources = the
  arguments its summary says the result views — a new `retview` summary
  derived from the return statements — and every owning/view argument for
  a callee not yet summarised); a struct/Option/Result literal (union of
  its view fields); a field read or payload of a view (same sources); a
  copy (same sources); a keeping container (the container now depends on
  the sources, as h27 does today for `s`).
- **A view ends** when a source is released, moved, reassigned, has a
  field replaced, goes out of scope, or is **mutated in a way that may
  reallocate** — inline (`vec_push`, `string_push_*`, …), through a callee
  whose mutation summary covers that parameter, or by running a closure
  whose body does (class C). Reading an ended view is an error naming the
  line where it ended. Dropping it is not a read.
- **A view may not outlive its sources**: returning one whose sources are
  locals, storing one into a global, or capturing one in a closure that
  crosses a thread is rejected. Raw pointers are not `Send`.
- **One mechanism.** This runs in the module-end walk (`bck_walk_seq`),
  where every summary is final, as a `view` dependency beside the existing
  handle borrows (`bs_` / `bb_`) and closure dependencies (`dd_`). The
  codegen-time pointer table (`__ptr_src__` / `__ptr_dead__`) it
  generalises is retired once the walk reproduces its verdicts
  (`diag_stale_borrow*` goldens, h07, h25–h29).
- The code that *reads* a view is unchanged: no runtime cost.

### R. Sealed representations

A struct type is **sealed** when it declares a raw-pointer (`*T`) field,
or it is a library handle (a `T_drop` hook) whose representation is raw —
every standard-library handle, and a program's own handle whose hooks are
`unsafe`. Outside `unsafe` functions (and the trusted standard library):

- a sealed type cannot be built with a literal, its fields cannot be
  written, and its raw (`s`, `*T`) fields cannot be read — the safe API
  (`slice_len`, `slice_empty`, `vec_len`, …) is the interface;
- a cast to a type that is or contains a pointer (raw pointer, `s`, a
  handle, a closure, an aggregate of them) is rejected — the null
  `# *T 0` stays legal;
- a call to a function with a raw-pointer parameter is rejected (the
  caller vouches for what the pointer covers: `slice_from_raw`,
  `vec_borrow_raw`, `vec_borrow_into`), and `vec_set_len` joins the
  raw-memory primitives (it declares raw writes initialised).
- Trusted code relies only on invariants the types enforce: a field safe
  code may write (`ProtoReader.pos`) is validated before it reaches raw
  arithmetic.

### F. `s` is a string, `*T` is raw memory

A parameter that a function reads or writes for a caller-given length is
raw memory and is typed `*T` — in a foreign declaration and in a NURL
function alike — and a function with a raw-pointer parameter is unsafe to
call (R). The stdlib's foreign declarations and its `s`-plus-length
functions are audited and retyped accordingly (`memmem`, `strnlen`,
`fwrite` / `fread`, `nurl_fast_atof`, `nurl_print_bytes`, …); the safe API
takes a `String`, a `Vec u8` or a `Slice`, whose length cannot lie. An `s`
parameter means a NUL-terminated string the callee reads to its NUL.

### N. Null strings

The null `s` is a real value (C APIs return it), so the string primitives
treat it as the empty string instead of crashing; the stdlib's own raw
readers guard it the same way. (To confirm with the owner: the
alternative — no null `s` outside `unsafe` — breaks 174 sites and every
`getenv`-style result.)

### A. Exclusive calls

At a call, an argument whose parameter the callee may mutate (its
mutation summary; `inout`; a container mutator) must not also reach the
callee through another argument: the same owner twice, or a borrow or
view of it. A handle borrow conflicts with a mutation that may drop or
replace elements; a view conflicts with any mutation. The message names
both arguments and the fix (take a copy, or split the call).

### C. Closure effects

A closure's body is summarised like a function's: which captures it
mutates, reallocates or drops elements of. Running it — a direct call, or
handing it to a callee that may invoke it — applies that effect to the
captures at that point, ending the views and borrows of them exactly as
the inline statements would.

### K. Accessor results are borrows by summary

Whether a call result is lent from an argument is a summary, never a
name: a value read out of a parameter's storage (directly, or through a
raw load in trusted code) is lent from that parameter. `vec_get`'s name
special case goes; `map_get`, `box_get`, `deque_get`, `btree_get`, … get
the same answer from their bodies. Which calls drop or hand out elements
(`bck_is_elem_dropper`) is likewise derived from the summaries of the
trusted bodies, not a list.

### G. Checked allocation arithmetic

One checked `size × count + extra` helper in the runtime and the stdlib
growth paths (`Vec`, `String`, `HashMap`, `Set`, `Deque`, `BTree`,
`vec_zeroed`, `vec_resize_zeroed`, `string_repeat`, …): a negative or
unrepresentable size panics with a message before anything is allocated.
The check sits on growth (cold) paths only.

## Order of work

1. Probes (done: h33–h79) and this plan.
2. **R** — sealed types, pointer casts, raw-parameter calls (small, closes
   12 probes, and V relies on safe code being unable to forge a view).
3. **K** — lend summaries for accessors; derived element droppers.
4. **V** — views in the walk; retire the pointer table.
5. **A** and **C** — exclusive calls, closure effects (both read the
   mutation summaries V needs).
6. **G** — checked allocation arithmetic; **F** and **N** — the stdlib
   surface audit.
7. Corpus migration (report mode first: every rejection in the tree is
   triaged as a real bug or a rule to refine), docs (MEMORY.md §6, spec,
   LIMITATIONS, CHANGELOG, ROADMAP, improvements_for_v1), the hole check
   in CI, genreject cores for views and aliasing.

Each step keeps every gate green: `./build.sh`, `tools/tree_sweep.sh`
(every changed verdict read and justified), `run_san_tests.sh`,
`tools/leakgate.sh`, the hole check, reject fuzz, `bench/perfstat.sh`,
`tools/vec_parity.sh`, self-compile and compile-set instructions.

## Out of scope here (tracked in improvements_for_v1.md)

Lock-held-by-path proofs for shared `Arc` mutation, fiber handle
lifetime, unsupported-async platforms — concurrency and runtime items, not
the single-threaded memory holes this branch closes.
