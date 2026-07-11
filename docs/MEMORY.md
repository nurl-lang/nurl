# NURL Memory Model

This document is the single reference for how NURL manages memory: who
owns a heap allocation, when it is freed, and what the compiler checks
statically. It covers the model as implemented in `nurlc.nu` (grammar
v2.3).

## TL;DR

- **Single owner, deterministic drop.** Every heap allocation has
  exactly one owning binding. The compiler inserts the matching free
  at the end of that binding's scope. No garbage collector, no
  reference counting. A small, explicit set of **manually-managed
  handles** sits outside auto-drop — `Vec`, `String`, a `sink`
  argument, and a closure that *escapes* its creating frame — and is
  freed by you, exactly like C's `malloc`/`free` (§7.4).
- **No known compiler-owned leaks.** The compiler never leaks an
  allocation it owns — not on the normal path, and not across a
  `panic`/`recover` unwind (a thread-local journal reclaims the
  scope-exit drops the `longjmp` skips, §7.2). Owned strings, slices,
  struct fields, `% Drop` values, and the heap env of a *non-escaping*
  capturing closure are all reclaimed automatically. The **only**
  memory you must free yourself is the manual-handle set above; used
  per that contract, NURL programs are leak-free. There is no
  "by-design leak" — see §7.
- **A borrow checker runs by default.** A diagnostic analysis pass
  catches use-after-move, alias double-free, and closures that escape
  the stack frame they point into. It is on unless you pass
  `--no-borrowck`. It is a *diagnostic* layered on the auto-drop base,
  not a Rust-style borrow system — see the contract in §6.
- **It is a diagnostic pass and its diagnostics are hard errors.**
  The borrow checker emits `error:` lines and the compiler exits
  non-zero with a count of violations after walking the whole
  program (so every error surfaces in one run). It *never* changes
  generated code — a borrow-clean program compiles to byte-identical
  IR with or without the checker. `--no-borrowck` remains the
  escape hatch for a false positive.

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
parameter **`inout`**:

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
defined before it is called. Generic functions may take `inout`
parameters too (`@ store [A] inout ( Box A ) b → v`); the
define-before-call rule applies to them as well.

An `inout` argument may also be a *field target* — `. obj field`
passes the address of that single struct field, so the callee
mutates exactly that field of the caller's struct in place
(`( add100 . g turns )`). `obj` must be a mutable (`: ~`) struct
binding; the field may itself be a struct.

A **`sink`** parameter consumes (takes ownership of) its argument —
the callee owns the value, and the caller may not use the argument
binding afterwards (the borrow checker reports a later use as a
use-after-move):

```
@ give_away sink ( Vec i ) g → v { ( vec_free [i] g ) }
...
: ( Vec i ) xs ( vec_new [i] )
( give_away xs )                 // xs is consumed; using it now is a move error
```

`sink` lowers to an ordinary by-value parameter (no IR change), and the
callee is responsible for releasing the value (the `vec_free` above) — a
`sink` parameter is **not** auto-dropped. It therefore applies to `Vec`
and other manually-managed handles. `sink` works on ordinary functions
and on trait **impl methods** (`% Bumpable (Counter) { @ take sink … }`).

Passing a *compiler-auto-dropped* value — an owned string (from an
allocating call), an owned slice, a `Drop`-trait value, or a struct with
owned fields — to a `sink` parameter is **rejected by design**, not a
missing feature. The auto-drop obligation for such values is tracked in
per-scope owned-sets that are snapshotted and restored across `?` / `??`
/ loop boundaries; transferring the obligation to the callee by
un-tracking the value would be silently undone by an enclosing arm's
restore, reintroducing the very double-free the checker exists to
prevent. The conservative rejection keeps the model sound. **Workaround:**
wrap the value in a manually-managed handle (a one-field `{ s data }`
struct, or a `Vec`), or pass it as an ordinary by-value parameter and let
the caller's scope drop it. `compiler/tests/should_fail_sink_autodrop.nu`
pins the diagnostic. Generic functions may take `sink` parameters
(`@ consume [A] sink ( Box A ) b → v`).

## 2. The borrow checker

The borrow checker is a **diagnostic-only** static analysis. It is
**on by default**; `--no-borrowck` disables it. Because it only emits
diagnostics and never lowers anything, a borrow-clean program produces
the exact same IR either way — the bootstrap fixed point is
unaffected.

All eight rules below (§2.1–§2.8) emit `error:`. Use `--no-borrowck`
for the escape hatch if a corner case slips through, and
`--strict-borrowck` (off by default) to add three opt-in checks on top —
see §2.9.

### 2.1 Move checking — use-after-move

Ownership *moves* out of a binding when it is consumed:

- passed as the argument of a typed destructor (`vec_free`,
  `string_free`, ... — any `*_free`; raw `nurl_free` of `*T`/`i8*`
  FFI memory is excluded), or
- copied into another binding (see 2.2).

After a move the binding holds freed-or-about-to-be-freed memory.
Reading it again is reported:

```
error: use of moved value 'v' - it was consumed at line N
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
not a move) and is left alone — distinguishing a borrow from a move
in the general case is the job of the parameter-convention surface
(`in` / `inout` / `sink`).

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
error: returning a value that references a stack binding by pointer
         - it dangles after this function returns
         (move the captured data to a heap-backed handle)
```

Closures that capture by *value* (the snapshot case — an immutable
`:` capture, or a single-handle struct) never escape and are not
flagged.

### 2.4 Exclusive access for `inout` arguments

An `inout` argument (section 1) is an *exclusive* mutable borrow for
the duration of its call. A binding passed `inout` must therefore be
the only argument path to its value at that call site: passing the
same binding again — as a second `inout`, or as a plain by-value
argument — is reported.

```
( swap_counters c c )    // error: 'c' is both mutably borrowed
                         //          and aliased by another argument
```

This is the "N readers XOR 1 writer" rule, scoped to a single call
(an `inout` borrow does not outlive its call, so there is no
cross-statement aliasing to track). A binding read through a *nested*
argument expression — `( f inout c (g c) )`, `( f inout c . c n )` —
is a known gap, not yet flagged.

### 2.5 Iterator invalidation

A `~ x xs { ... }` foreach loop borrows the container `xs` for the
body's duration — the loop snapshots `xs`'s buffer pointer and length
once, up front. Mutating `xs` inside the body would leave the loop
cursor pointing at a stale or freed buffer (`vec_push` may
reallocate; `vec_free` releases the buffer outright), so it is
reported:

```
~ x xs { ( vec_push xs x ) }   // error: cannot mutate 'xs'
                               //          while iterating over it
```

The check fires for a stdlib container mutator applied to the
iterated container (`vec_push` / `vec_insert` / `vec_remove` /
`vec_pop` / `vec_clear` / `vec_set` / `vec_set_len` / `vec_reserve` /
`vec_shrink_to_fit` / `vec_extend` / `vec_free` / `vec_free_with` /
`vec_swap` / `vec_reverse`) and for any `inout` argument naming it.
A counter loop (`~ k 0 ...`, a while-loop) borrows nothing, so
`( vec_set xs k v )` in an index loop stays legal — only the
element-borrowing `~ x xs` foreach form is guarded.

### 2.6 Loop-carried moves

A `~` loop body runs more than once, so a binding consumed inside it
is moved on entry to the *next* iteration. If that binding was live
**before** the loop and the body never re-binds it, re-reading it on
the second pass is a guaranteed use-after-move — the classic "free
inside a loop" double-free:

```
: ( Vec i ) xs ( vec_new [i] )
~ < k 3 { ( vec_free [i] xs ) = k + k 1 }   // error: use of moved value 'xs'
```

After the analysis walk reaches the loop's fixpoint, it re-walks the
body once more, seeded with the loop's *back-edge* state: every outer
binding the body leaves moved is seeded `Moved`, and the controlling
`~ cond` is re-checked too (it is re-evaluated each turn). A read of
such a definitely-moved binding is then reported. The same applies to
a foreach whose body frees an outer binding (`~ y ys { ( vec_free xs ) }`).

Three shapes are deliberately **not** flagged, because each is freshly
owned on every iteration:

- freeing the **loop element** — `~ x xs { ( string_free x ) }` (the
  element is a fresh load each pass);
- freeing a binding **declared inside** the loop body;
- freeing an outer binding the body **re-binds** before the next read
  (`( vec_free buf ) = buf ( vec_new [i] )`).

Only bindings that already existed at loop entry are carried, so none
of these three false-positive. This rests on the lattice join being
exact at the back-edge: a binding moved on only the body path joins to
`MaybeMoved`, never `Moved` — every merge routes through the same
`Uninit ⊔ Moved = MaybeMoved` rule.

### 2.7 Interprocedural escape

§2.3 catches a stack reference that escapes through a sink *in the
current function*. A reference can also escape through a **helper**:
hand it to a function that stores it in a heap container or detaches it
onto a thread, and it outlives the call just the same — but a
per-function pass cannot see what the callee does with it.

The checker closes this with a per-function **escape summary**,
computed in codegen order exactly like the auto-`sink` summary (§1). A
parameter is recorded as *escaping* when the body passes it to an
escaping argument position: a built-in heap/thread sink (the element of
`vec_push` / `vec_insert` / `vec_set`, or the `thread_spawn` closure),
or — transitively — an already-known escaping parameter of another
function. At a call site, passing a **stack reference** to an escaping
parameter is then reported:

```
@ detach ( @ v ) cb → v { ( thread_spawn cb ) ... }   // param 0 escapes
...
: ( @ v ) f \ → v { = . c n + . c n 1 }   // captures a `: ~` Counter by pointer
( detach f )   // error: passing a value that references a stack binding
               //        by pointer to 'detach' - it escapes …
```

The summary is built as each function compiles, so a **forward call** —
or a call to a **generic** not yet instantiated — has no summary to
consult inline. Rather than miss it, the call site **parks** the check
(a stack-reference argument to a not-yet-known user callee is rare, so
the parked list stays tiny) and `resolve_pending_escapes()` replays it
once the whole module — including the generic instantiation flush — has
compiled and the summary is final. So `( detach f )` is flagged whether
`detach` is defined above or below the call, and a generic escaping
helper is caught once its instantiation has populated the summary. The
one residual is a *pure forward chain*: a forward helper that escapes
its parameter only by handing it to *another* forward-defined helper —
the first helper's own summary is then still incomplete when parked, so
nothing resolves (define such chains bottom-up to get the check). A
parameter that the callee only *reads* or *invokes* (not stores) is not
escaping, so passing a stack reference to it stays legal — the
distinction the §2.7 summary turns on. (A reference handed back *out*
of a helper, rather than stored by it, is the separate return-escape
case — see §2.8.)

### 2.8 Return escape (a reference passed back out)

§2.7 propagates a stack reference *into* a callee. The mirror image is
a reference flowing *out* of a call: a helper that **returns one of its
parameters** hands the reference straight back, so the result of
`( id ref )` is the reference itself. A per-function pass sees only a
call result of the right type — not that it aliases an argument.

The checker records a second summary, again in codegen order: a
parameter is *returned* when the body has `^ p` (a bare-parameter
return). At a call site, the result's **referent depth** becomes the
max depth among the arguments at those returned positions. The result
then carries the reference, so the existing §2.3 / §2.7 sinks fire on
it uniformly:

```
@ id ( @ v ) cb → ( @ v ) { ^ cb }   // returns param 0
...
: ( @ v ) f \ → v { = . c n + . c n 1 }   // stack ref into this frame
^ ( id f )                  // error: returning a value that references a
                            //        stack binding by pointer …
( thread_spawn ( id f ) )   // error: … escapes … to 'thread_spawn'
```

A helper that takes the reference but returns a **fresh** value
(`@ runit ( @ v ) cb → i { ( cb ) ^ 0 }`) is not a passthrough, so
`( runit f )` is not a reference and may be returned freely: the call
result's referent depth is *authoritative* (an explicit `0` when it is
not a reference).

The summary also covers a parameter returned **inside an aggregate** —
`@ wrap ( @ v ) cb → Slot { ^ @ Slot { cb } }` records `cb`, because the
returned struct carries the reference exactly as a bare `^ cb` would, so
`( wrap f )` propagates `f`'s depth out. An ordinary constructor
returning a struct of *value* parameters (`@ mk i a i b → Point { @ Point
{ a b } }`) records them too but never false-positives: an `int` argument
has depth 0. Boundaries that remain: a parameter returned through a
closure *capture* (`^ \ → … cb …`) rather than a struct field, and
forward / generic calls, are not yet summarised.

### 2.9 `--strict-borrowck` — three opt-in checks

The eight rules above run by default. `--strict-borrowck` (off by
default) adds three further checks, all diagnostic-only and all emitting
`error:` like the rest:

1. **Aliased mutation through a field argument.** §2.4 flags an `inout`
   binding aliased by another *bare-identifier* argument of the same
   call. Strict mode generalises this to a `. obj field` argument — a
   nested field read of the same object passed alongside its `inout`
   borrow is reported too.
2. **`# *T` raw-pointer escape.** A raw pointer taken (`# *T …`) from an
   owned binding whose pointer may outlive that binding's drop is
   reported — a narrow check on the otherwise-untracked `*T` surface
   (§3).
3. **Conditional double-free (the maybe-moved hole, §6.2/§6.5).**
   Consuming a binding that is *maybe*-moved — freed on one arm of a
   `?`, still owned on the other — is reported: it is a real
   double-free on the path where the first free ran. Off by default
   because it also flags the legitimate mutually-exclusive-frees
   pattern (free under `cond` here, free under `! cond` later), which
   the default no-false-positive contract protects.

It is **off by default** because the extensions have a meaningful
false-positive rate against existing stdlib code; it is a tightening
knob for auditing a specific module, not part of the standard contract.
The default-on eight rules remain the guarantee everything else in this
document refers to.

## 3. What is NOT checked

The borrow checker targets the bug classes that ordinary NURL code
hits in practice. It deliberately does **not** cover:

- **`*T` raw pointers.** `*T` is the FFI ABI escape hatch — NURL's
  `unsafe`. A `*T` taken of a local, stored, returned, or captured
  is *not* checked by default. Treat `*T` lifetimes as your
  responsibility. (`--strict-borrowck` adds one narrow exception — a
  `# *T` escape from an owned binding, §2.9.)
- **Aliased mutation beyond a single call.** The exclusive-access
  check (§2.4) covers a binding aliased among one call's arguments.
  A binding read through a *nested* sub-expression argument, and
  any longer-range aliased-mutation analysis, is not done.
- **Escape across a forward / generic call — mostly closed.** The
  *interprocedural escape* check (§2.7) now handles a forward or
  generic call by parking it and replaying it after the whole module
  compiles (`resolve_pending_escapes`), so definition order no longer
  matters for it. Two residuals remain: a *pure forward chain* (a
  forward helper that escapes only via another forward-defined helper —
  §2.7), and the *return-escape* summary (§2.8), which is still consulted
  inline and so still misses a forward / generic passthrough. Both
  degrade the *diagnostic* only — never a miscompile.
- **Escape through a closure capture or a deeply nested aggregate.**
  §2.8 records a parameter returned directly or as a direct struct
  field; a parameter returned by being *captured into a closure*
  (`^ \ → … cb …`), or embedded one aggregate level deeper
  (`^ @ Outer { @ Inner { cb } }`), is not yet summarised.
- **`recover` / panic unwind — reclaimed, not modelled.** A panic is a
  `setjmp`/`longjmp` jump to the nearest `recover` frame (no exception
  tables, no unwinding destructors). The owned allocations the `longjmp`
  skips no longer leak: a thread-local **allocation journal** (§7.2)
  records every owned auto-drop allocation made inside a recover extent —
  raw buffers *and* `% Drop` / autodrop-enum values (whose typed
  destructor it replays) — and reclaims the still-live ones *before* the
  jump. A value that escapes
  the extent (assigned into a by-ref-captured caller binding) is
  forgotten from the journal first, so the unwind frees only genuinely
  abandoned scratch — never what the caller now owns. The reclamation is
  therefore a *leak* fix, never a use-after-free. The checker still
  treats `recover` as an ordinary call and does not model the panic
  edge — it does not need to, since the journal runs at the panic itself.

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

| Bug class | Checked? |
|---|---|
| Use-after-move | yes (`error:`) |
| Alias double-free | yes (`error:`) |
| Closure / stack-reference escape | yes (`error:`) |
| `inout` exclusive access (call-site aliasing) | yes (`error:`) |
| Iterator invalidation (mutate container in `~`-foreach) | yes (`error:`) |
| Loop-carried move (free an outer binding inside a `~` loop) | yes (`error:`) |
| Interprocedural escape (stack ref stored by a helper) | yes (`error:`) |
| Return escape (helper returns a passed-in stack ref) | yes (`error:`) |
| Aliased mutation via nested-argument reads | no |
| Returned borrows / lifetime inference | partial (§2.8) |
| `*T` raw pointers | no (by design) |

The `no` / `partial` rows are not bugs; they are the boundary of a
*diagnostic* pass, spelled out in §3 and contracted in §6.

## 6. The soundness contract

This section states precisely what the model guarantees, what it does
not, and what those guarantees are conditional on. It is the part to
read before relying on the checker — or before assuming it is Rust.

### 6.1 Two layers, two different jobs

Memory safety in NURL rests on **two** mechanisms, and it is worth
keeping them apart:

1. **Auto-drop (§1) is what makes the base safe.** It is conservative
   by construction: it registers a free *only* for a resource it saw
   allocated directly, and a copy into another binding registers no
   second free. So the compiler **never emits a double-free of its own
   accord**, for any program, checked or not. This is a structural
   property, not an analysis result.

2. **The borrow checker (§2) catches the mistakes a *programmer* can
   still write** on top of that base — consuming a value and reading it
   again, aliasing two owners onto one buffer, letting a stack
   reference outlive its frame. It is a flow-sensitive **diagnostic**
   pass: it emits `error:` and exits non-zero, and it lowers nothing.

### 6.2 Sound, not complete

The precise claim is a one-directional one: **every diagnostic is a
real bug** (the checker is *sound* — no false positives, §6.3), but a
clean compile is **not** a proof of memory safety (it is *not
complete*). It reliably catches the **definite, common** forms of each
class:

- **Use-after-free / double-free** — use-after-move, alias double-free,
  loop-carried double-free, indirect (auto-`sink`) use-after-free
  (§2.1, §2.2, §2.6).
- **Dangling stack references** reaching a return, a heap container, a
  thread, a longer-lived binding, or — interprocedurally — a helper
  that stores or returns one (§2.3, §2.7, §2.8).
- **Iterator-invalidating mutation** of a container under a `~ x xs`
  foreach (§2.5), and an **aliased `inout` writer** sharing a call with
  another reader of the same binding (§2.4).

It deliberately **does not** flag the *conditional* forms, to keep the
no-false-positive property exact. The sharp edge is the **maybe-moved**
case: a value freed on only one arm of a `?` and then freed again is a
real double-free on the path where the first free ran, yet it is *not*
reported —

```
? cond { ( vec_free [i] xs ) } {}
( vec_free [i] xs )    // double-free when cond was true — NOT flagged
```

— because flagging it would also reject the many programs where the
two frees are mutually exclusive. Definite double-frees (both arms, or
straight-line, or loop-carried) *are* caught; only the genuinely
conditional one slips. Together with the unchecked classes (§3) and the
trusted surface (§6.4), this is why "compiles clean" means "free of the
bug classes the checker *reports*," not "verified memory-safe."

### 6.3 The no-false-positive property

Every rule is tuned to flag only a **definite** fault, never a
*maybe*: a value moved on one arm of a `?` is `MaybeMoved` and left
alone (§2.1); only the back-edge-carried, definitely-moved binding is
flagged in a loop (§2.6); a summary records a parameter broadly but
only fires when a *real* stack reference is passed (§2.7, §2.8). The
consequence is a working contract: **if the checker flags your code, it
has found a real bug** — quote the message and fix it. The whole
in-tree corpus (compiler + stdlib + tests) is verified borrow-clean and
passes the sanitizer gate (§6.6), so a false positive is a compiler bug
worth reporting, and `--no-borrowck` is the escape hatch meanwhile.

Because the pass lowers nothing, an accepted program compiles to
**byte-identical IR** with or without it — which is why turning it on
left the self-hosting bootstrap fixed point untouched.

### 6.4 Trusted computing base

The guarantees in §6.2 hold *modulo* a small surface you are trusted to
get right:

- **`*T` raw pointers and FFI.** `*T` is NURL's `unsafe`. A `*T` into a
  local, or any pointer crossing an `& \`lib\`` boundary, is outside the
  model; its lifetime is yours.
- **Manually-managed handles.** `Vec`, `String`, a `sink` argument, and
  the env of an *escaping* closure are freed by *you*, not by auto-drop
  (§7.4). The checker tracks their *moves* (so a `vec_free`d handle can't
  be reused) but not their *freeing* — forget the `vec_free` and it leaks.
- **Definition order, for the residual checks.** Summaries are built in
  codegen order. The *interprocedural escape* check (§2.7) no longer
  depends on order — it is parked and replayed after the module compiles
  — but the *return-escape* (§2.8) and *sink* checks still consult the
  summary inline, so a forward / generic call to such a callee misses the
  diagnostic (§3). Never miscompiled — only unchecked.

### 6.5 This is not Rust

The model borrows vocabulary — *move*, *borrow*, “N readers XOR 1
writer” — for ideas that are genuinely analogous, but the machinery is
deliberately simpler and the equivalence does **not** hold:

- Ownership is **single-owner with deterministic scope-bound drop**
  (RAII-shaped), not an affine type system. There are **no lifetimes in
  types**, no lifetime parameters, and no generic borrow inference.
- `in` / `inout` / `sink` are **call conventions** (by-value copy /
  by-address exclusive mutation / by-value consume), not
  lifetime-polymorphic reference types. They are resolved per call, not
  threaded through signatures as `&'a`.
- The checker is a **flow-sensitive diagnostic lint** layered on the
  auto-drop base, not a total borrow system that *proves* a program
  safe. Its boundary (§3) is real and intentional, not a TODO list of
  Rust features pending.

Concretely — and this is the comparison that matters — code that
compiles clean, uses no `*T`, and calls no FFI can still do things
safe Rust cannot:

1. **Conditionally double-free.** A value freed on one arm of a `?`
   and then freed again unconditionally is a real double-free on one
   path, and it is *not* flagged by default — the price of the
   no-false-positive property (§6.2, §6.3). `--strict-borrowck` closes
   exactly this hole (§2.9, check 3) at the cost of also flagging the
   legitimate mutually-exclusive-frees pattern.
2. **Data-race on shared heap state.** There is **no `Send`/`Sync`
   system**. The one concrete footgun the compiler does reject is an
   `Rc` captured into `thread_spawn`; but two threads sharing an
   `Arc[Vec]` and both mutating the *contents* are entirely
   unchecked, and a user type that is internally non-thread-safe is
   not flagged when it crosses a thread boundary
   ([`LIMITATIONS.md`](LIMITATIONS.md), *Concurrency / thread
   safety*). `Arc` makes the *refcount* atomic, not your data.

Integer division and remainder by zero panic with a clear message —
they are not UB.

So the accurate one-line claim is: **memory-safer than C by
construction, with the common bug classes machine-checked — not
memory-safe by proof, and not data-race-free.** Anyone needing the
latter two guarantees today should reach for Rust; anyone reading a
"NURL is memory-safe like Rust" claim should be pointed here.

### 6.6 The gates — how the guarantees are checked

Everything above is enforced by two CI jobs
(`.github/workflows/ci.yml`) plus a targeted leak tool. This subsection
is the single source of truth for *what is actually run*; other
sections point here rather than re-describe it.

**One fact resolves the usual confusion:** on Linux x86-64,
`-fsanitize=address` **is** the leak detector — ASan integrates LSan and
runs it at process exit, and `detect_leaks` merely toggles it. So "ASan"
and "LSan" name the *same* instrumented run with the leak check off or
on; they are not two separate tools or two separate builds.

1. **Functional gate** — `./build.sh`. The bootstrap fixed point
   (stage1 ≡ stage2, byte-identical IR) plus the golden-output test
   corpus (`run_tests.sh`, **no** sanitizers) plus
   `tools/check_examples.sh` (frontend-compiles every `examples/` /
   `bench/` / `duo/` program). Catches miscompiles, output regressions,
   and a broken self-host.

2. **Sanitizer gate** — `./build.sh --san` (runtime + every stage built
   with `-fsanitize=address,undefined`) then
   `compiler/tests/run_san_tests.sh`, which links each corpus test with
   `-fsanitize=address,undefined` and runs it under **ASan + UBSan with
   `detect_leaks=0`**. This is the gate that catches the dangerous
   classes — use-after-free, double-free, out-of-bounds,
   undefined behaviour — across the **whole** corpus; a clean branch is
   `SAN_FAIL: 0`. It is the gate every claim of "no use-after-free /
   double-free" in this document refers to.

   **It deliberately does not gate leaks** (`detect_leaks=0`). A
   corpus-wide leak run would flag two non-defects: the compiler's own
   process-lifetime structures (symbol tables and interned strings),
   never freed by design; and the many tests that allocate a manual handle
   (`Vec` / `String`) and exit without freeing it — test brevity
   exercising the §7.4 contract. So the corpus-wide gate proves
   *memory-safety*, not leak-freedom.

3. **Leak verification** — pinned, not corpus-wide. Because gate 2 runs
   with leaks off, the no-leak guarantees are pinned two ways, both with
   `detect_leaks=1`:
   - `LSAN_DETECT_LEAKS=1 run_san_tests.sh` flips the *same* ASan run's
     leak check on, turning any leak into a `SAN_FAIL`. Used as an audit
     and on the leak-pinned tests, which run clean:
     `struct_nested_field_drop`, `arm_local_drop`,
     `arm_local_trailing_drop` (normal-path drop, §7.1),
     `recover_unwind` (panic-unwind, §7.2), `loop_drop_reclaim`
     (loop-body `% Drop` reclamation), and `closure_env_reclaim`,
     `closure_env_binding` (closure-env reclamation, §7.4).
     (`loop_drop_reclaim` + `recover_unwind` pin the fix for a real
     loop-body leak: a `% Drop` value bound inside a `~` loop was not
     dropped at iteration end — the while-loop scope exit freed owned
     strings/vecs but skipped user destructors.)
   - `tools/leakcheck/run.sh` — an end-to-end gate that builds the HTTP
     server with ASan+LSan (`detect_leaks=1`), serves 21 requests, and
     fails on *any* leak; it locks the per-request leak class
     (None-placeholder allocations, the keepalive-500 response, and
     router/handler closure envs).

   Both pinned checks are now wired into `ci.yml`: the leak-pinned
   subset runs under `LSAN_DETECT_LEAKS=1` in the sanitizers job, and
   `tools/leakcheck/run.sh` runs in the build-test job. So a leak
   regression in the pinned surface fails CI, not just a manual audit.

## 7. Leaks versus memory safety

A leak is **not** a memory-safety violation: no use-after-free, no
double-free, no undefined behaviour — just memory the process never
returns. The checked classes (§5) are all memory-*safety*; leaks are a
separate axis.

The contract is sharp: **the compiler never leaks an allocation it
owns.** Everything auto-drop owns is freed at scope exit on the normal
path (§7.1) and reclaimed across a `panic` unwind too (§7.2) — so there
are *no known compiler-owned leaks*. What is left to you is a small,
explicit set of **manually-managed handles** (§7.4): memory the model
deliberately does not own, freed by you exactly as C requires `free`
for `malloc`. Used per that contract, programs are leak-free. There is
no "leaks by design" tier here — only "the compiler's job" and "your
job", with the boundary drawn precisely below.

### 7.1 Ordinary code does not leak

In straight-line code, across `?` / `??` branches, and through loop
bodies, auto-drop is exhaustive: owned strings, owned slices, `Drop`
values, and **owned struct fields — including fields nested inside
inner struct literals** — are all freed at scope exit, and a binding
declared in a `?` / match / loop arm that *falls through* (no `^`) is
dropped at arm end, not leaked. These behaviours are pinned leak-clean
by the leak-verification tests `struct_nested_field_drop`, `arm_local_drop`,
`arm_local_trailing_drop` (§6.6). Do **not** treat them as open
limitations.

### 7.2 The panic-unwind allocation journal

A panic `longjmp`s straight to the recover frame, skipping every
scope-exit drop the compiler queued between (§3). Historically that
leaked any owned allocation made inside the extent. A thread-local
**allocation journal** closes that gap without exception tables:

- While a `recover` frame is active, the compiler records every owned
  auto-drop allocation it registers, in one of two forms:
  - a **raw buffer** (`nurl_journal_push`) for an owned string
    (`nurl_str_cat` / `nurl_read_file` / …), an owned slice
    (`[ T | … ]`), or each owned **struct-field buffer** (a fresh
    string/slice field of a `@ T { … }` literal). The journal holds the
    raw pointer; `nurl_free` — the single choke point every auto-drop
    release flows through — removes it again, so a value freed normally
    before the panic leaves no entry (no stale-slot hazard) and an
    aliased buffer is freed once.
  - a **typed destructor** (`nurl_journal_push_drop`) for a value with a
    `% Drop` impl or a heap-boxing autodrop enum. The journal holds the
    value's *alloca* and a generated `__jdrop_<T>` thunk that loads and
    runs the destructor; the compiler `forget`s the entry wherever that
    destructor runs on the normal path (scope exit, branch/loop arm,
    move-out), so a value dropped before the panic is never re-dropped.
- On a panic, `nurl_panic` drains the entries recorded since the target
  recover frame's mark — the allocations still live, neither freed nor
  escaped — *before* the `longjmp`, while the owning C frames are still
  valid: a raw entry is freed, a typed entry runs its `__jdrop` thunk.
- A value that **escapes** the extent — assigned into a by-ref-captured
  caller binding (the `= resp ( f req )` typed-return pattern) — has its
  heap leaves (and, for a moved `% Drop` value, its alloca entry)
  *forgotten* from the journal at the assignment, so the drain never
  frees what the caller now owns.

So a panic reclaims **every** kind of allocation auto-drop owns — owned
strings, owned slices, owned struct-field buffers, and user `% Drop` /
autodrop-enum values. The mechanism can never turn a leak into a
double-free or use-after-free (raw entries are pointer-keyed and removed
at `nurl_free`; typed entries are forgotten at their normal drop site and
deduped on drain); it clears the sanitizer gate, and `recover_unwind` is
one of the leak-pinned tests (§6.6) that pins the round trip leak-clean.
Single-owner scalars and slices are captured *by value* by a closure, so
they cannot
escape a recover extent by reference and need no forget; only multi-field
structs (and the `% Drop` move) can, which the escape-forget covers.

### 7.3 What a panic does **not** reclaim

Only **manually-managed handles** (§7.4) — `Vec`, `String`, a `sink`
argument, and the env of a closure that *escapes* its frame — survive a
panic unfreed, because they are never auto-dropped in the first place:
*you* free them. A panic that abandons one mid-scope leaks it exactly as
forgetting its free would — no different from the manual-handle contract
everywhere else. The mitigation is the same as any manual resource: hold
it in the *caller's* frame (the `: ~` by-ref-capture pattern
`stdlib/std/panic.nu` documents), not in the scope the panic abandons.

### 7.4 Manually-managed handles

Auto-drop only frees what it saw allocated *directly*. The handles below
sit outside that — the model deliberately does not own them, so they are
yours to release. This is the complete list; nothing else leaks.

- **`Vec`** and **`String`** — single boxed handles over a heap buffer;
  free with `vec_free` / `vec_free_with` / `string_free`. (`String` is
  `{ s ctl }`, the same single-handle shape as `Vec[u]`.)
- the heap **environment of a capturing closure** that **escapes** its
  creating frame — `\ → … x …` allocates an env block, and the compiler
  now reclaims it automatically whenever it provably does *not* escape:
  - an **inline closure literal** passed directly to a parameter the
    callee only ever *invokes* (an **invoke-only** parameter — a pure
    borrow, recorded in `g_fn_invoke_only`) has its env freed right after
    the call;
  - a closure **bound to a `:` name** has its env freed at scope exit
    (and, in a loop body, each iteration) unless it escapes — covering
    the `: f \ …` then `( hof f )` callback pattern.

  An env is left for *you* only when the closure genuinely outlives the
  frame: it is returned (`^ \ …` / `^ f`), stored into a struct field or
  container, captured into another closure, detached onto a thread
  (`thread_spawn`), or decomposed (`recover` frees its own). The signal
  is positive (escape sites untrack the binding; the default is to free
  nothing), so the reclamation is never a use-after-free — an escaped
  closure is the consumer's to release via the env pointer (`# *u f 1`),
  exactly like a returned `Vec`.
- a value passed to a **`sink`** parameter — the callee frees it.

These are deliberate seams, not defects: the conservatism that makes
auto-drop double-free-proof (§6.1) is exactly what stops it from owning
them. The checker still tracks these handles' *moves* — a `vec_free`d
`Vec`, or a `sink`-consumed value, cannot be used again (§2.1) — it just
does not free them for you.

Outside this manual-handle set, nothing leaks. The corpus-wide
sanitizer gate runs with leak detection **off** (§6.6) — deliberately,
because a leak run would flag the compiler's process-lifetime arenas and
the many tests that allocate a manual handle and exit without freeing it
(test brevity exercising this contract, not a defect). The no-leak
guarantees are instead pinned by the leak-verification tests and
`tools/leakcheck` (§6.6). A program that honours the contract leaks
nothing.
