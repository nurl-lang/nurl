# NURL Memory Model

This document is the single reference for how NURL manages memory: who
owns a heap allocation, when it is freed, and what the compiler checks
statically. It covers the model as actually implemented in `nurlc.nu`
(grammar v2.1). The phased roadmap for the static analysis lives in
[`../BORROW.md`](../BORROW.md).

## TL;DR

- **Single owner, deterministic drop.** Every heap allocation has
  exactly one owning binding. The compiler inserts the matching free
  at the end of that binding's scope. No garbage collector, no
  reference counting for ordinary values (closure environments are
  the one exception — they are RC'd).
- **A borrow checker runs by default.** A diagnostic analysis pass
  (BORROW.md Phases 1-3) catches use-after-move, alias double-free,
  and closures that escape the stack frame they point into. It is on
  unless you pass `--no-borrowck`.
- **It is a diagnostic pass.** The borrow checker emits `warning:`
  lines and *never* changes generated code. A borrow-clean program
  compiles to byte-identical IR with or without the checker.

## 1. Ownership and auto-drop

NURL has no GC. Values live on the stack by default; heap memory is
obtained through the C runtime (`malloc`/`free` via FFI). The compiler
tracks which bindings own a heap resource and emits the free for you.

### What gets owned

A `:` binding becomes the **owner** of a heap resource when its
initialiser is a *fresh allocation produced on the spot*:

- a slice literal `[ T | ... ]`,
- a slice-returning call,
- an allocating string call (`nurl_str_cat`, `_cat3/4`, `_int`,
  `_float`, `_slice`, `nurl_read_file`),
- a named-struct literal `@ T { ... }` whose fields are themselves
  fresh allocations (each such field is tracked individually),
- a value of a type with a user `Drop` trait impl.

At the end of the owning binding's scope the compiler emits the
matching `nurl_free` / `drop`. Reassigning an owned binding frees the
previous value first. Returning a fresh allocation **transfers
ownership** to the caller and suppresses the local drop.

### Conservative by construction

The compiler only registers a drop for a resource it saw allocated
*directly*. Copying an already-owned binding into a struct field does
**not** register a second drop — so the compiler never emits a
double-free of its own accord. This conservatism is why the auto-drop
layer is safe on its own; the borrow checker (below) is what catches
the mistakes a *programmer* can still write.

### Parameter passing conventions

A parameter is an **immutable borrow by default** (the `in`
convention — it may be written explicitly but is normally omitted): a
struct-typed parameter is copied into a fresh `alloca` at function
entry (C/Go/Zig semantics), and `= . p field val` inside the callee
writes that local copy, leaving the caller's struct unchanged.

To let a callee mutate the caller's value in place, mark the
parameter **`inout`** (BORROW.md Phase 4, Option B — mutable value
semantics):

```
@ bump inout Counter c → v { = . c n + . c n 1 }
...
: ~ Counter c @ Counter { 0 10 }
( bump c )                       // c.n is now 1, in the caller
```

`inout` lowers to a by-address (`<T>*`) parameter. The argument must
be a mutable (`: ~`) binding; it is passed by address, so the
callee's writes land on the caller's storage. `inout` is the
preferred replacement for the three older mutation idioms — returning
the modified struct, a `*T` parameter, or a single-handle struct
wrapper — though all three still work. An `inout` function must be
defined before it is called. The `sink` (consume / move) convention
is reserved but not yet implemented.

## 2. The borrow checker

The borrow checker is a **diagnostic-only** static analysis. It is
**on by default**; `--no-borrowck` disables it. Because it only emits
diagnostics and never lowers anything, a program with no borrow
warnings produces the exact same IR either way — the bootstrap fixed
point is unaffected.

All three rules currently emit `warning:`, not `error:`. This is
deliberate (BORROW.md watch #3): a new rule ships as a warning and is
promoted to a hard error only once it has been proven
false-positive-free across the whole compiler + stdlib + test +
example corpus. All three are clean today.

### 2.1 Move checking — use-after-move

Ownership *moves* out of a binding when it is consumed:

- passed as the argument of a typed destructor (`vec_free`,
  `string_free`, ... — any `*_free`; raw `nurl_free` of `*T`/`i8*`
  FFI memory is excluded), or
- copied into another binding (see 2.2).

After a move the binding holds freed-or-about-to-be-freed memory.
Reading it again is reported:

```
warning: use of moved value 'v' - it was consumed at line N
         (pass a fresh value or rebind it before reuse)
```

Re-binding the name (`: ...` or `= ...`) revives it. A binding moved
on only one arm of a `?` is *maybe-moved* and deliberately not
flagged, to keep the rule false-positive-free.

### 2.2 Alias and double-free detection

An immutable binding-to-binding copy of an owned heap aggregate ---
`: (Vec i) b a` --- makes `b` the new owner and **moves** `a`. Any
later use of `a` (including a second `vec_free a`) is then the
use-after-move warning above. This closes the silent-alias
double-free: two live bindings can no longer own the same buffer
unnoticed.

A *mutable* copy `: ~ T b a` is treated as a working cursor (a borrow,
not a move) and is left alone — distinguishing a borrow from a move in
the general case is the job of the reference surface in BORROW.md
Phase 4.

### 2.3 Escape analysis

A closure that captures a `: ~`-mutable multi-field struct captures it
**by pointer** into the enclosing function's stack frame. Such a
closure is a *stack reference*: it must not outlive the frame it
points into. The checker assigns every binding a **region** (its
block-nesting depth — the function body is depth 1, each nested
`?`/`~`/`??`/`{ }` one deeper, the caller depth 0) and tags a stack
reference with the deepest region it points into. Reference-ness
propagates through closure and aggregate literals, `let` copies, and
`=` assignments. An escape is reported when a stack reference reaches:

- `^`-return (it would dangle the moment the function returns),
- `vec_push` / `vec_insert` / `vec_set` / `thread_spawn` (it outlives
  the current scope inside a container or on a worker thread),
- an `=` into a binding declared in a longer-lived (shallower) region.

```
warning: returning a value that references a stack binding by pointer
         - it dangles after this function returns
         (move the captured data to a heap-backed handle)
```

Closures that capture by *value* (the snapshot case — an immutable
`:` capture, or a single-handle struct) never escape and are not
flagged.

## 3. What is NOT checked

The borrow checker targets the bug classes that ordinary NURL code
hits in practice. It deliberately does **not** yet cover:

- **Exclusive access / aliased mutation.** Two mutable paths to the
  same data, where a write through one breaks an invariant the other
  relies on, is not yet detected. The `inout` convention (Phase 4)
  gives the language the exclusive mutable borrow this check needs;
  enforcing "N readers XOR 1 writer" on top of it is BORROW.md
  Phase 5.
- **Full iterator invalidation.** Mutating a container while a
  `~`-foreach borrows its elements is a planned check (Phase 6), not
  yet implemented.
- **`*T` raw pointers.** `*T` is the FFI ABI escape hatch — NURL's
  `unsafe`. A `*T` taken of a local, stored, returned, or captured is
  *not* checked. Treat `*T` lifetimes as your responsibility.
- **Interprocedural escape.** A stack reference passed *through a
  helper function* that retains it cannot be caught by a
  per-function pass; that needs function summaries (BORROW.md
  Phase 7).
- **`recover` / panic edges.** Owned values in a `recover` scope leak
  on panic; the checker treats `recover` as an ordinary call and does
  not model panic control flow.

## 4. Practical guidance

- Trust the diagnostic. If the compiler reports a use-after-move or an
  escape, it has found a real bug — quote the message and fix it
  rather than reaching for `--no-borrowck`.
- To share a closure beyond the scope of the data it mutates, move
  that data to a heap-backed handle (a single-handle struct over a
  `Vec` or a heap allocation) and capture the handle by value.
- To hand an owned container to a consumer and keep using it, you
  cannot — that is the move. Take a fresh copy, or restructure so the
  consumer borrows.
- `--no-borrowck` exists for bisecting a suspected false positive or
  for builds that must match pre-checker behaviour exactly. If you hit
  a genuine false positive, it is a compiler bug worth reporting — the
  corpus is verified clean.

## 5. Status

| Bug class | Checked? | BORROW.md phase |
|---|---|---|
| Use-after-move | yes (`warning:`) | Phase 1 |
| Alias double-free | yes (`warning:`) | Phase 2 |
| Closure / stack-reference escape | yes (`warning:`) | Phase 3 |
| Aliased mutation (exclusive access) | no | Phases 4-5 |
| Iterator invalidation | no | Phase 6 |
| Returned borrows / lifetime inference | no | Phase 7 |
| `*T` raw pointers | no (by design) | n/a |

See [`../BORROW.md`](../BORROW.md) for the full design rationale,
the per-phase implementation notes, and the open roadmap.
