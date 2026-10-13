# Known Limitations

Limitations of the **language and the compiler** (`compiler/nurlc.nu`) — the
fixed rules a program must work within. The authoritative grammar is
[`spec/grammar.ebnf`](../spec/grammar.ebnf); the normative language reference
is [`docs/spec.md`](spec.md).

This page is deliberately scoped to language + compiler. Standard-library
feature coverage and gaps (databases, TLS, MQTT, …) are *not* language
limitations — they live with each module (the `stdlib/**` file headers and
[`docs/NETWORKING.md`](NETWORKING.md)) and on the [`ROADMAP.md`](../ROADMAP.md).

**No open soundness holes.** Every safe program the 0.72.0 release review
found accepted and faulting is closed, and held by a probe in
[`tools/fuzz/holes/`](../tools/fuzz/holes/) ([`MEMORY.md` §6.2](MEMORY.md)).

The fixed grammar quirks (binary `&` / `|` arity, ternary cascading, `^`
vs `^^`) are documented in the [Grammar](#grammar) section below; the
closure-capture and `: ~` closure-borrow-escape rules live in
[`docs/MEMORY.md`](MEMORY.md). All of these are compiler-diagnosed —
"the error message is the API".

## Type system

| Limitation | Workaround |
|---|---|
| Single-letter type keywords (`i u f b s v`) cannot be used as variable names with type inference | Use an explicit type annotation: `: i n expr` |

## Traits

| Limitation | Workaround |
|---|---|
| Bare-name method calls are **statically** dispatched — resolved to `method__<mangled-first-arg-type>` at monomorphisation, with no per-call vtable. Dynamic dispatch **is** supported but must be opted into via the `%Trait` object type + `( dyn Trait value )` construction: a `%dyn.<Trait> = { i8*, i8* }` box-plus-vtable fat pointer (spec §4.9). A trait must be **object-safe** to be used as `%Trait` (see `compiler/tests/should_fail_dyn_not_object_safe.nu`) | Keep the concrete type at the call site for static hot paths; for a heterogeneous collection, box values as `%Trait` with `( dyn Trait v )`, or use an enum of the variants and match |
| Associated types have **no projection**: an associated type cannot be named as `A::Elem` at a generic call site — it is usable only inside the declaring trait's own method bodies/signatures | Make the element an explicit type parameter of the function (`[A E]`) when a caller needs to name it |
| An associated-type binding (`type Elem Concrete`) must be a **single simple type name** (IDENT / type keyword); compound types (`* T`, `Vec T`, `?T`) are not accepted — the same restriction trait-default substitution carries | Bind to a named struct/alias type that wraps the compound type |
| Two type aliases that share an LLVM lowering (`i`/`i64`, `u`/`u8`, `f`/`f64`) cannot both implement the same trait method — they collide on one dispatch key and are reported as a duplicate impl | Pick one spelling per impl; the alias is the same runtime type |

## Concurrency / thread safety

Safe code is held to the ownership rules, data races included
([`MEMORY.md` §6.2](MEMORY.md)). What is trusted rather than checked —
marker assertions — is listed in
[`MEMORY.md` §3 and §6.4](MEMORY.md); read those before relying on a
thread-safety expectation the rules do not state.

| Limitation | Workaround |
|---|---|
| `Send` / `Sync` are **derived from a type's structure, not proved**. The compiler knows two unsafe leaves — `Rc` (non-atomic refcount) and `Cell` (raw unsynchronised byte buffer) — and propagates them through struct fields, enum payloads, generic arguments, aggregates and closure captures. It knows nothing about an FFI handle: no C pointer is a leaf, however it is spelled — `*u` (as the sqlite declarations take a `sqlite3*`), `s` (as the stdio pass-throughs still carry a `FILE*`) or an integer — so a struct holding a `sqlite3*` or a `FILE*` derives as Send and crosses without a word. Binding a C library takes `unsafe` functions, and marking its handle types is part of what their author vouches for | Mark the type: `% NotSend Db { }` (or `% NotSync`) from `stdlib/core/marker.nu`. It propagates exactly like a built-in leaf — a struct holding it, a `( Vec Db )`, a closure capturing one are all rejected at the boundary. `stdlib/ext/sqlite` marks its own `Database` and `Statement` this way, so that one is handled; every other binding that wraps a C handle still has to say so itself |
| The derivation is also **conservative in the other direction**: a type that is thread-safe by construction but structurally suspect is rejected. `Mutex` is literally `{ Cell c }` | Assert it: `% Send T { }` / `% Sync T { }`. An explicit marker stops the walk at that type — nothing inside is examined, because you have taken responsibility for it. This is NURL's spelling of Rust's `unsafe impl`, and a negative marker outranks a positive one on the same type |
| `Send` answers "may this value **move** to another thread", never "is this program race-free". `( Vec i )` and `s` are Send **and** Sync — correctly, because sharing one read-only is ordinary code — so two threads *mutating* one is not caught by this check | It is caught by the move rule: a thread closure moves its captures, so only share handles (`Channel`, `Mutex`, `Arc`, `Locked`) are used on both sides ([`MEMORY.md` §6.5](MEMORY.md)); a mutation through a shared `Arc` is the next row |
| Changing the **contents** of an `Arc` is rejected in safe code — on every thread, the one that made it included, and whatever lock is held. `Arc` makes the refcount atomic, not the payload: every clone reads it without a lock, and `arc_get` over a `Vec`/`String` hands back a handle aliasing the one buffer. A call that hands an `arc_get` result (or a field of one) to anything that changes it — a container mutator, a `String`'s or a map's, a helper, at any depth — is a compile error, and `arc_set` is for `unsafe` code only | Build the value first and `arc_new` it whole; put state threads share and change in a `Locked [T]` (`stdlib/std/thread.nu`: `locked_with` / `locked_set` hold its own lock, so the lock that guards the data is the one its type names); keep state one thread changes in an `Rc`; or give each thread its own copy and merge after `thread_join` |
| `thread_spawn` / `spawn` take a `( @ v )` closure; the worker runs on its own copy of the captured environment, dropped when the body returns ([`docs/MEMORY.md` §7.5](MEMORY.md)). Send covers what the copy *reaches*. The closure moves its owned captures and takes its own share of a `Channel` / `Mutex` / `Arc` (`docs/MEMORY.md` §6.2); a `: ~` by-reference capture may not reach it (§2.3), and a raw `*T` exists only in `unsafe` code | Move shared state to a heap-backed, thread-safe handle before spawning: a `Locked` or a `Channel` for state that changes, an `Arc` for a value nobody changes |

## Functions and calls

| Limitation | Workaround |
|---|---|
| Calls require explicit parens — `( f a b )` is the only call form; a bare identifier is always a name lookup, never a call | Wrap every callsite: `( puts s )` |
| Struct parameters are passed by **value** by default (C/Go/Zig semantics) — `= . p field val` inside the callee writes a local copy; the caller's struct is unchanged | Mark the parameter `inout` (`@ bump inout Counter c → v`) — an exclusive mutable borrow, the callee mutates the caller's binding in place (see [`docs/MEMORY.md`](MEMORY.md)). Or return the modified struct (`= c ( inc_returning c )`); or use a `*T` parameter inside an `unsafe` function; or wrap state in a single-handle struct (`{ ( Vec i ) slots }`) |
| A closure hands its result to its caller as the caller's own, so it cannot hand back a value it does not own that cannot be copied (a `% Drop` value with no clone — its parameter, its capture, a field of either, what a lending call lent), nor a view (a Slice, a struct of views) of what it captured; a raw string it lent comes back a copy (docs/MEMORY.md, h219/h220) | Hand back a value the body makes, or take what the view points into as an argument — a view of an argument is followed at the call. A plain function may lend its parameter or a field of one |
| A function cannot hand back a field that cannot be copied out of a struct it drops, a module global or a capture (h221) | Keep the value in a binding of its own and hand that back, or hand back the whole struct |
| A closure that moves out a capture it cannot copy (a `% Drop` value with no clone) runs at most once; one returned or handed to a thread and never run leaks that value (h222, h236) | Pass the value as an argument, or move it in a closure that is run |
| A closure that reads a capture it cannot copy cannot leave the capture's frame — returned, or inside a value returned (h224) | Move the value into the closure's result, or keep the closure in the frame that owns the value |
| A function cannot hand back a view of a `sink` parameter it drops (h225) | Take the parameter by lend (no `sink`), or hand back the value itself |
| A value that cannot be copied which a call only lends (`vec_at` of a `( Vec Res )`) cannot be stored, pushed or handed to a `sink`; nor can such a field be moved out of a struct that still drops it (h229, h230) | Take it out of its owner first (`vec_pop`, `vec_remove`, replacing the field), or lend it |
| A generic that copies its `T` (`box_clone`, anything built on `mem_dup`) cannot be instantiated with a value that cannot be copied; the error points at the copy inside the generic, not at the call (h235) | Move the value instead, or give the type a clone |
| A match arm cannot hand an enum's payload that cannot be copied to a `sink` or an owner: the enum keeps it (h231) | Match on the enum to read the payload; to take it out, give the enum a variant constructor that hands it back from a function that takes the enum as `sink` |
| A match cannot hand a payload it only borrows that cannot be copied — of an option a struct field keeps — to the binding it initialises (h227) | Read the payload in the arm, or take the option out of the struct first |
| Closures capture by value (snapshot at construction) by default. The `: ~` mutable-struct byref capture path (`stdlib/std/panic.nu` recover-with-typed-result) shares the caller's alloca — see [`docs/MEMORY.md` §2.3](MEMORY.md) for the lifetime rule | Use `: ~ MultiFieldStruct` for shared-mutation closures; for value semantics keep the binding immutable |
| A parameter may not be named `r` followed only by digits (`r0`, `r12`, …) — a by-value parameter keeps its source name as its LLVM SSA register, and nurlc's temporaries are `%r0`, `%r1`, … in the same namespace | Rename it (`r0` → `r_0`, or something that says what it holds). Locals are unaffected — the code generator names those |
| A `sink` parameter owns and drops what it is given — a `String`, `Vec`, owning struct, handle enum, library handle, `Drop` value or a raw `s` (docs/MEMORY.md §1, §7.6). An **owned slice**, or a struct whose literal gave it one, is still **rejected at the call site**: its auto-drop obligation is not transferred | Pass an owned slice as an ordinary parameter and let the caller's scope drop it, or use a `Vec` |

## Ownership

| Limitation | Workaround |
|---|---|
| Freeing a field of a match payload (`?? o { T t → ( string_free . t name ) }`) hands the rest of the payload to the arm: it is dropped at the arm's end, and `o` must not be read after that match | Take the payload whole (`: Tagged x t`), or free the field after the last use of `o` |
| Storing a *borrowed* `String` / `Vec` into an owner (a struct literal, a field of a value, an element via `vec_push`) stores a **copy**; mutations through the new owner are not seen through the old binding | Store the owned value (move it in), or keep the shared buffer behind a pointer-reached struct, whose fields are stored as is |
| An element borrowed out of a temporary container (`( vec_get [T] ( mk ) 0 )`) is copied before the temporary is dropped; when `T` cannot be copied (a `% Drop` struct with no clone) that is an error, since nothing would own the temporary | Bind the container to a name first (`: ( Vec T ) v ( mk )`): it lives to the end of its scope, and the element borrows from it |

## Imports

| Limitation | Workaround |
|---|---|
| `import_decl` is a static inline-include (like `#include`) — the imported file is compiled into the same LLVM module | Avoid importing files that define `main`; avoid circular imports |
| Import alias (`` $ `path` alias ``) rewrites top-level `@`-functions, struct/enum types, enum variants, and global `:` constants to `alias__name`. FFI decls (`& "lib" @ name`) and trait/impl methods are intentionally NOT renamed — FFI symbols resolve at the linker by literal C-ABI name, and trait methods are mangled by the impl-target type | Use `pub` to scope FFI declarations to the importing file if collision is a risk |
| `pub` visibility covers `@`-functions, struct/enum types, enum variants (inheriting their enum's flag), and global `:` constants. Files with no `pub` decl stay in legacy mode (everything public, backwards-compat). FFI and trait/impl decls accept `pub` forward-compat but do not enforce | Mark each cross-file API entry with `pub`; the diagnostic `private X 'Y' is not visible across files` points at the leaked-private use site |
| `$`-import dedup keys on the `realpath(3)`-canonical file, so the same file reached through different symlink chains compiles exactly once; only when `realpath` itself fails (exotic filesystems) does dedup fall back to the normalised path string | None needed in practice; prefer the project-root-relative form (`stdlib/foo.nu`) for readability |

## Grammar

| Limitation | Workaround |
|---|---|
| Import is inline-include only: no namespaces. Alias rewriting covers `@`-functions, struct/enum types, enum variants, and global `:` constants; FFI decls and trait/impl methods are deliberately not renamed | Stick to a single canonical import path per file; prefix FFI names manually when collisions matter |
| **Every operator has fixed arity** (prefix notation has no closing token — a **locked 1.0 design decision**, see [`docs/spec.md` §6](spec.md); not a deferred gap). `&` / `\|` / `^^` / `+` / `-` / `*` / `/` / `==` / `!=` / `<` / `>` / `<=` / `>=` / `<<` / `>>` are all **binary** (`OP A B`); `?` ternary is `? cond then else`; `^` / `!` / `~` are unary. A missing or extra operand silently consumes the next token, so the diagnostic can land on the following line | Count operands left-to-right when "unexpected token" fires on a line that looks fine. For n-ary `&`/`\|` chains write `& A & B C` or `& & & A B C D` (n−1 operators for n atoms), or factor a predicate helper (`is_alpha`-style); the compiler rejects the common `? & A B C D { … } { … }` shape as a hard error by default (`nurlc --no-strict-arity` demotes it to a warning; this repo additionally runs `tools/check_strict_arity.sh` over its whole tree in CI) |
| **`^` is the `return` keyword, not XOR** — but `^^` (two adjacent carets) **is** the native XOR operator. `^ a b` parses as `return (a b …)` | Use `^^` for XOR. The lexer pairs `^^` only when the carets are adjacent, so a stray space (`^ ^`) still means two returns |
