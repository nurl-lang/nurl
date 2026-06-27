# Known Limitations

Limitations of the **language and the compiler** (`compiler/nurlc.nu`) — the
fixed rules a program must work within. The authoritative grammar is
[`spec/grammar.ebnf`](../spec/grammar.ebnf); the normative language reference
is [`docs/spec.md`](spec.md).

This page is deliberately scoped to language + compiler. Standard-library
feature coverage and gaps (databases, TLS, MQTT, …) are *not* language
limitations — they live with each module (the `stdlib/**` file headers and
[`docs/NETWORKING.md`](NETWORKING.md)) and on the [`ROADMAP.md`](../ROADMAP.md).

For active compiler quirks (binary `&` / `|` arity, bare `@-fn` closure
coercion, same-line parameter shadowing, ternary cascading, `: ~`
closure-borrow escape) see [`docs/GOTCHAS.md`](GOTCHAS.md). The memory model
and the borrow checker's not-yet-checked list live in
[`docs/MEMORY.md`](MEMORY.md).

## Type system

| Limitation | Workaround |
|---|---|
| Single-letter type keywords (`i u f b s v`) cannot be used as variable names with type inference | Use an explicit type annotation: `: i n expr` |

## Traits

| Limitation | Workaround |
|---|---|
| Dispatch is **fully static** — a bare-name method call resolves to `method__<mangled-first-arg-type>` at monomorphisation. There is no runtime trait identity, no vtable, and **no `dyn Trait`** (dynamic dispatch / heterogeneous collections of differing impls). The model is a deliberately reserved extension point (see `docs/spec.md` §4.9) | Keep the concrete type at the call site; for a heterogeneous set, use an enum of the variants and match |
| Associated types have **no projection**: an associated type cannot be named as `A::Elem` at a generic call site — it is usable only inside the declaring trait's own method bodies/signatures | Make the element an explicit type parameter of the function (`[A E]`) when a caller needs to name it |
| An associated-type binding (`type Elem Concrete`) must be a **single simple type name** (IDENT / type keyword); compound types (`* T`, `Vec T`, `?T`) are not accepted — the same restriction trait-default substitution carries | Bind to a named struct/alias type that wraps the compound type |
| A trait must be scanned **before** its impls (defaults, supertrait names, and associated types are read from the trait when an impl is processed) | Declare the trait — or place its `$`-import — above the impl (the natural order) |
| Two type aliases that share an LLVM lowering (`i`/`i64`, `u`/`u8`, `f`/`f64`) cannot both implement the same trait method — they collide on one dispatch key and are reported as a duplicate impl | Pick one spelling per impl; the alias is the same runtime type |

## Concurrency / thread safety

| Limitation | Workaround |
|---|---|
| Sending a non-thread-safe value across a thread boundary is **partially** checked at compile time: a `thread_spawn` closure that captures an **`Rc`** (non-atomic refcount) is rejected, since two threads racing on its control-block count is UB. This is the concrete, documented footgun. There is **no general `Send`/`Sync` auto-derive** yet — a *user* type that is internally non-thread-safe is not automatically flagged when captured | Use **`Arc`** (atomic refcount) for any handle that crosses a thread boundary, exactly as `stdlib/std/arc.nu` documents; keep shared mutable state behind `Arc[Mutex]` |
| `thread_spawn` takes a `( @ v )` closure; the captured environment is copied to the worker. The check above covers `Rc`; a raw `*T` pointer into the parent stack is covered separately by the borrow checker's escape analysis (`docs/MEMORY.md` §2.3) | Move shared state to a heap-backed, thread-safe handle (`Arc`, `Channel`) before spawning |

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
| `$`-import dedup is keyed on the path string with a small normalisation (leading `./` is stripped). Symlink-equivalent paths still collide as separate imports | Stick to the project-root-relative form (`stdlib/foo.nu`, no `./` prefix) |

## Grammar

| Limitation | Workaround |
|---|---|
| Import is inline-include only: no namespaces. Alias rewriting covers `@`-functions, struct/enum types, enum variants, and global `:` constants; FFI decls and trait/impl methods are deliberately not renamed | Stick to a single canonical import path per file; prefix FFI names manually when collisions matter |
| **Every operator has fixed arity** (prefix notation has no closing token — a **locked 1.0 design decision**, see [`docs/spec.md` §6](spec.md); not a deferred gap). `&` / `\|` / `^^` / `+` / `-` / `*` / `/` / `==` / `!=` / `<` / `>` / `<=` / `>=` / `<<` / `>>` are all **binary** (`OP A B`); `?` ternary is `? cond then else`; `^` / `!` / `~` are unary. A missing or extra operand silently consumes the next token, so the diagnostic can land on the following line | Count operands left-to-right when "unexpected token" fires on a line that looks fine. For n-ary `&`/`\|` chains write `& A & B C` or `& & & A B C D` (n−1 operators for n atoms), or factor a predicate helper (`is_alpha`-style); the compiler warns on the common `? & A B C D { … } { … }` shape |
| **`^` is the `return` keyword, not XOR** — but `^^` (two adjacent carets) **is** the native XOR operator. `^ a b` parses as `return (a b …)` | Use `^^` for XOR. The lexer pairs `^^` only when the carets are adjacent, so a stray space (`^ ^`) still means two returns |
