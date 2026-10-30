# Known Limitations

Limitations of the **language and the compiler** (`compiler/nurlc.nu`) — the
fixed rules a program must work within. The authoritative grammar is
[`spec/grammar.ebnf`](../spec/grammar.ebnf); the normative language reference
is [`docs/spec.md`](spec.md).

This page is deliberately scoped to language + compiler. Standard-library
feature coverage and gaps (databases, TLS, MQTT, …) are *not* language
limitations — they live with each module (the `stdlib/**` file headers and
[`docs/NETWORKING.md`](NETWORKING.md)) and on the [`ROADMAP.md`](../ROADMAP.md).

**No soundness hole is known open** ([`MEMORY.md` §6.2](MEMORY.md)).
Every safe program found accepted and faulting is closed, and held by
a probe in [`tools/fuzz/holes/`](../tools/fuzz/holes/) (`h01–h871`). One
of them is closed at run time rather than at compile time: a handle
whose copies are one state (a `PNCounter`, a `TcpConn`, a `Cell`)
crossing to another thread while a copy of it stays behind panics at the
crossing (`thread_spawn`, `spawn`, `chan_send`, a `Locked`), naming the
handle ([`MEMORY.md` §6.5](MEMORY.md));
the ownership rules of the single-threaded language (`A2.memory_safe`,
`A2.no_leak_end`, phases A1–A2) are mechanically proven sound in Lean 4
([`formal/`](../formal/)).

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
[`MEMORY.md` §3, §6.4, and §6.5](MEMORY.md); read those before relying on a
thread-safety expectation the rules do not state.

| Limitation | Workaround |
|---|---|
| `Send` / `Sync` are **derived from a type's structure, not proved**. The compiler knows four built-in cases — `Rc` (non-atomic refcount), `Cell` (raw unsynchronised byte buffer), a library handle (Sync only where asserted) and a trait object (Send only when its trait declares `: Send`) — and propagates them through struct fields, enum payloads, generic arguments, aggregates and closure captures. It knows nothing about an FFI handle: no C pointer is a leaf, however it is spelled — `*u` (as the sqlite declarations take a `sqlite3*`), `s` (as the `raw` stdio pass-throughs `file_raw` / `file_from_raw` carry a `FILE*`) or an integer — so a struct holding a `sqlite3*` or a `FILE*` derives as Send and crosses without a word. Binding a C library takes `unsafe` functions, and marking its handle types is part of what their author vouches for | Mark the type: `% NotSend Db { }` (or `% NotSync`) from `stdlib/core/marker.nu`. It propagates exactly like a built-in leaf — a struct holding it, a `( Vec Db )`, a closure capturing one are all rejected at the boundary. `stdlib/ext/sqlite` marks its own `Database` and `Statement` this way, so that one is handled; every other binding that wraps a C handle still has to say so itself |
| The derivation is also **conservative in the other direction**: a type that is thread-safe by construction but structurally suspect is rejected — one that holds a `Cell` but synchronises access to it itself | Assert it: `unsafe % Send T { }` / `unsafe % Sync T { }` (outside the standard library the `unsafe` prefix is required, [spec §3.3d](spec.md)). An explicit marker stops the walk at that type — nothing inside is examined, because you have taken responsibility for it. This is NURL's spelling of Rust's `unsafe impl`, and a negative marker outranks a positive one on the same type |
| `Send` answers "may this value **move** to another thread", never "is this program race-free". `( Vec i )` and `s` are Send **and** Sync — correctly, because sharing one read-only is ordinary code — so two threads *mutating* one is not caught by this check | It is caught by the move rule: a thread closure moves its captures, so only share handles (`Channel`, `Mutex`, `Arc`, `Locked`, `RwLocked`, `Atomic`, `PFile`) are used on both sides ([`MEMORY.md` §6.5](MEMORY.md)); a mutation through a shared `Arc` is the next row |
| Changing the **contents** of an `Arc` is rejected in safe code — on every thread, the one that made it included, and whatever lock is held. `Arc` makes the refcount atomic, not the payload: every clone reads it without a lock, and `arc_get` over a `Vec`/`String` hands back a handle aliasing the one buffer. A call that hands an `arc_get` result (or a field of one) to anything that changes it — a container mutator, a `String`'s or a map's, a helper, at any depth — is a compile error, and `arc_set` is for `unsafe` code only | Build the value first and `arc_new` it whole; put state threads share and change in a `Locked [T]` (`stdlib/std/thread.nu`: `locked_with` / `locked_set` hold its own lock, so the lock that guards the data is the one its type names), in an `RwLocked [T]` when many threads read it at once (`stdlib/std/rwlock.nu`: a read guard lends a frozen view), or in an `Atomic` for a single word; keep state one thread changes in an `Rc`; or give each thread its own copy and merge after `thread_join` |
| `thread_spawn` / `spawn` take a `( @ v )` closure; the worker runs on its own copy of the captured environment (a closure written in the call is handed over instead of copied), dropped when the body returns ([`docs/MEMORY.md` §7.5](MEMORY.md)). Send covers what the copy *reaches*. The closure moves its owned captures and takes its own share of a `Channel` / `Mutex` / `Arc` / `Locked` (`docs/MEMORY.md` §6.2); a `: ~` by-reference capture may not reach it (§2.3), and a raw `*T` exists only in `unsafe` code | Move shared state to a heap-backed, thread-safe handle before spawning: a `Locked` or a `Channel` for state that changes, an `Arc` for a value nobody changes |
| Module globals in safe code: a mutable scalar global (an integer, bool, float or `s`) is read and written atomically, but a mutable global of a struct or an option is reachable only from `unsafe` code (no atomic covers it), a mutable `s` global holds literals only (safe code may not hand it a string to own: the next assignment would free it under a reader on another thread), and a global set at start holds only a type that synchronises itself — a `Locked`, `Arc`, `Channel`, `Mutex`, `Cond` or `Semaphore`, never a bare `( Vec T )` (h263, h272, h273) | Keep state that changes at run time in a `( Locked T )` global set at start (`: ( Locked T ) g ( make )`, docs/MEMORY.md Module globals); a value nobody changes in an `Arc` |

## Functions and calls

| Limitation | Workaround |
|---|---|
| Calls require explicit parens — `( f a b )` is the only call form; a bare identifier is always a name lookup, never a call | Wrap every callsite: `( puts s )` |
| Struct parameters are passed by **value** by default (C/Go/Zig semantics) — `= . p field val` inside the callee writes a local copy; the caller's struct is unchanged | Mark the parameter `inout` (`@ bump inout Counter c → v`) — an exclusive mutable borrow, the callee mutates the caller's binding in place (see [`docs/MEMORY.md`](MEMORY.md)). Or return the modified struct (`= c ( inc_returning c )`); or use a `*T` parameter inside an `unsafe` function; or wrap state in a single-handle struct (`{ ( Vec i ) slots }`) |
| A closure hands its result to its caller as the caller's own, so it cannot hand back a value it does not own that cannot be copied (a `% Drop` value with no clone — its parameter, its capture, a field of either, what a lending call lent), nor a view (a Slice, a struct of views) of what it captured; a raw string it lent comes back a copy (docs/MEMORY.md, h219/h220) | Hand back a value the body makes, or take what the view points into as an argument — a view of an argument is followed at the call. A plain function may lend its parameter or a field of one |
| A function cannot hand back a field that cannot be copied out of a struct it drops, a module global or a capture (h221) | Keep the value in a binding of its own and hand that back, or hand back the whole struct |
| A closure that moves out a capture it cannot copy (a `% Drop` value with no clone) runs at most once — one that may leave its frame and is run again after the move, or after a copy of it (a thread's) took the value, stops with a panic (h222, h236, h239, h244) | Pass the value as an argument, or move it in a closure that is run once |
| A closure that may leave its frame (handed back, to a thread, a fiber or a callee, or bound to a name used other than as a callee) takes a capture it cannot copy from the frame when it is made, even one it only reads: the frame cannot use the value after that (h240–h243) | Make the closure after the frame's last use of the value, or call the closure only by name so it stays in the frame |
| A function cannot hand back a view of a `sink` parameter it drops (h225) | Take the parameter by lend (no `sink`), or hand back the value itself |
| A value that cannot be copied which a call only lends (`vec_at` of a `( Vec Res )`) cannot be stored, pushed or handed to a `sink`; nor can such a field be moved out of a struct that still drops it (h229, h230) | Take it out of its owner first (`vec_pop`, `vec_remove`, replacing the field), or lend it |
| A generic that copies its `T` (`box_clone`, anything built on `mem_dup`) cannot be instantiated with a value that cannot be copied; the error points at the copy inside the generic, not at the call (h235) | Move the value instead, or give the type a clone |
| A match arm cannot hand an enum's payload that cannot be copied to a `sink` or an owner: the enum keeps it (h231) | Match on the enum to read the payload; to take it out, give the enum a variant constructor that hands it back from a function that takes the enum as `sink` |
| A match cannot hand a payload it only borrows that cannot be copied — of an option a struct field keeps — to the binding it initialises (h227) | Read the payload in the arm, or take the option out of the struct first |
| A closure whose body changes a capture (grows, clears or replaces it) cannot be handed to a call, or called, beside another argument that reaches that capture — the binding, a borrow or view of it, or another closure that captured it — and cannot itself hold a view of that capture (h274–h280) | Hand the callee what it needs as a parameter instead of capturing it, as `ws_serve_messages_deflate_with_context` gives its handler the deflate context ([`MEMORY.md` §2.11](MEMORY.md)) |
| A closure captures by pointer into its caller's frame a `: ~` binding it assigns or hands to an `inout` parameter, and a `: ~` multi-field struct (a callback counts into its caller's binding; `recover \ → v { = out ( f ) }` hands a result out); such a closure cannot leave the frame — returned, stored in a container or handed to a thread ([`docs/MEMORY.md` §2.3](MEMORY.md)). Every other capture is copied when the closure is made | Keep state a closure that outlives its frame changes in a heap-backed handle: an `Atomic`, a `Locked`, an `Rc` |
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
| **Every operator has fixed arity** (prefix notation has no closing token — a **locked 1.0 design decision**, see [`docs/spec.md` §6](spec.md); not a deferred gap). `&` / `\|` / `^^` / `+` / `-` / `*` / `/` / `==` / `!=` / `<` / `>` / `<=` / `>=` / `<<` / `>>` are all **binary** (`OP A B`); `?` ternary is `? cond then else`; `^` / `!` / `~` are unary. A missing or extra operand silently consumes the next token, so the diagnostic can land on the following line (when the swallowed line uses the binding being initialised, nurlc names the cause instead: "the initialiser of 'b' is one operand short and swallowed the statement on line N") | Count operands left-to-right when "unexpected token" fires on a line that looks fine. For n-ary `&`/`\|` chains write `& A & B C` or `& & & A B C D` (n−1 operators for n atoms), or factor a predicate helper (`is_alpha`-style); the compiler rejects the common `? & A B C D { … } { … }` shape as a hard error by default (`nurlc --no-strict-arity` demotes it to a warning; this repo additionally runs `tools/check_strict_arity.sh` over its whole tree in CI) |
| **`^` is the `return` keyword, not XOR** — but `^^` (two adjacent carets) **is** the native XOR operator. `^ a b` parses as `return (a b …)` | Use `^^` for XOR. The lexer pairs `^^` only when the carets are adjacent, so a stray space (`^ ^`) still means two returns |
