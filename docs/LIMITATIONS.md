# Known Limitations

Limitations of the **language and the compiler** (`compiler/nurlc.nu`) — the
fixed rules a program must work within. The authoritative grammar is
[`spec/grammar.ebnf`](../spec/grammar.ebnf); the normative language reference
is [`docs/spec.md`](spec.md).

This page is deliberately scoped to language + compiler. Standard-library
feature coverage and gaps (databases, TLS, MQTT, …) are *not* language
limitations — they live with each module (the `stdlib/**` file headers and
[`docs/NETWORKING.md`](NETWORKING.md)) and on the [`ROADMAP.md`](../ROADMAP.md).

The fixed grammar quirks (binary `&` / `|` arity, ternary cascading, `^`
vs `^^`) are documented in the [Grammar](#grammar) section below; the
closure-capture and `: ~` closure-borrow-escape rules live in
[`docs/MEMORY.md`](MEMORY.md). All of these are compiler-diagnosed — see
[`docs/GOTCHAS.md`](GOTCHAS.md) for the "the error message is the API" policy.

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
| A trait must be scanned **before** its impls (defaults, supertrait names, and associated types are read from the trait when an impl is processed) | Declare the trait — or place its `$`-import — above the impl (the natural order) |
| Two type aliases that share an LLVM lowering (`i`/`i64`, `u`/`u8`, `f`/`f64`) cannot both implement the same trait method — they collide on one dispatch key and are reported as a duplicate impl | Pick one spelling per impl; the alias is the same runtime type |

## Concurrency / thread safety

The complete list of ways *safe-looking* code can still fail — this
table plus the conditional double-free — is stated together in
[`MEMORY.md` §6.5 "This is not Rust"](MEMORY.md); read that section
before relying on any thread-safety expectation.

| Limitation | Workaround |
|---|---|
| `Send` / `Sync` are **derived from a type's structure, not proved**. The compiler knows two unsafe leaves — `Rc` (non-atomic refcount) and `Cell` (raw unsynchronised byte buffer) — and propagates them through struct fields, enum payloads, generic arguments, aggregates and closure captures. It knows nothing about an FFI handle: `s` spells both `String` and every opaque C pointer, so a `sqlite3*` or a `FILE*` derives as Send and crosses without a word | Mark the type: `% NotSend Db { }` (or `% NotSync`) from `stdlib/core/marker.nu`. It propagates exactly like a built-in leaf — a struct holding it, a `( Vec Db )`, a closure capturing one are all rejected at the boundary |
| The derivation is also **conservative in the other direction**: a type that is thread-safe by construction but structurally suspect is rejected. `Mutex` is literally `{ Cell c }` | Assert it: `% Send T { }` / `% Sync T { }`. An explicit marker stops the walk at that type — nothing inside is examined, because you have taken responsibility for it. This is NURL's spelling of Rust's `unsafe impl`, and a negative marker outranks a positive one on the same type |
| `Send` answers "may this value **move** to another thread", never "is this program race-free". `( Vec i )` and `s` are Send **and** Sync — correctly, because sharing one read-only is ordinary code — so two threads *mutating* one is not caught by this check | It is caught by the next row instead, at the mutation. The two checks are complementary; neither subsumes the other |
| Mutating the **contents** of a shared `Arc` from a worker is rejected: a `thread_spawn` / `spawn` closure that calls a container mutator on an `arc_get` result — inline, or inside a helper it calls — without holding a lock is a compile error. `Arc` makes the refcount atomic, not the payload, and `arc_get` over a `Vec`/`String` hands back a handle aliasing the one buffer | Take a `Mutex` **in the worker** around the mutation (`mutex_lock` / `mutex_unlock`, or `mutex_with`), one Mutex shared by every worker; or give each thread its own copy and merge after `thread_join` |
| The lock check **counts** `mutex_lock`/`mutex_unlock` rather than proving a lock is held on every path, and it says nothing about the *parent* thread mutating shared state while a worker runs | Keep every access to shared state — parent included — inside the same lock |
| `thread_spawn` / `spawn` take a `( @ v )` closure; the captured environment is copied to the worker. Send covers what the copy *reaches*; a raw `*T` pointer into the parent stack is covered separately by the borrow checker's escape analysis (`docs/MEMORY.md` §2.3) | Move shared state to a heap-backed, thread-safe handle (`Arc`, `Channel`) before spawning |

## Functions and calls

| Limitation | Workaround |
|---|---|
| Calls require explicit parens — `( f a b )` is the only call form; a bare identifier is always a name lookup, never a call | Wrap every callsite: `( puts s )` |
| Struct parameters are passed by **value** by default (C/Go/Zig semantics) — `= . p field val` inside the callee writes a local copy; the caller's struct is unchanged | Mark the parameter `inout` (`@ bump inout Counter c → v`) — an exclusive mutable borrow, the callee mutates the caller's binding in place (see [`docs/MEMORY.md`](MEMORY.md)). Or return the modified struct (`= c ( inc_returning c )`); or use a `*T` parameter; or wrap state in a single-handle struct (`{ ( Vec i ) slots }`) |
| Closures capture by value (snapshot at construction) by default. The `: ~` mutable-struct byref capture path (`stdlib/std/panic.nu` recover-with-typed-result) shares the caller's alloca — see [`docs/MEMORY.md` §2.3](MEMORY.md) for the lifetime rule | Use `: ~ MultiFieldStruct` for shared-mutation closures; for value semantics keep the binding immutable |
| A `sink` parameter takes a manually-managed handle (`Vec`, single-pointer struct) that the callee frees explicitly. A *compiler-auto-dropped* value (an owned string, owned slice, `Drop` value, or struct with owned fields) is **rejected at the call site by design** — its auto-drop obligation can't be transferred without risking a double-free across `?`/`??`/loop scope restores (see [`docs/MEMORY.md` §1](MEMORY.md)) | Wrap it in a handle (`{ s data }` / `Vec`), or pass it by value as an ordinary parameter and let the caller's scope drop it |

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
