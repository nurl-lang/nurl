# NURL — Language Gotchas

A single-page reference for the rough edges of NURL (Grammar v1.8)
that trip up code generation. If you are an LLM writing NURL, read
this first — it saves several compile-test cycles.

For deliberate *scope* limitations (no GC, no inheritance, no
exceptions) see **Known Limitations** in
[`../README.md`](../README.md). For shipped features and what they
unlock, see [`../CHANGELOG.md`](../CHANGELOG.md).

---

## Quick reference

| # | Gotcha | One-line fix |
|---|---|---|
| 1 | `&` and `|` are **binary** — `& A B C` is a parse-arity error | Chain via parens: `& A & B C` |
| 2 | Bare `@-fn` names don't auto-coerce to a `(@ R P*)` closure parameter | Wrap in `\ P* → R { ( fn args ) }` |
| 3 | Same-line shadowing: `: i z + z 7` shadows the parameter `z` from that line | Rename: `: i zz + z 7` |
| 4 | Function calls require parens — `f a b` parses as register-then-loose-tokens | Always `( f a b )` |
| 5 | Ternary arity errors cascade — diagnostic points at the *next* line | Count operands left-to-right on the previous line |
| 6 | `vec_clone` is intentionally absent | Roll your own: `vec_each` + per-element clone |
| 7 | Function-parameter struct mutation is **value-semantic** | Return the modified struct: `= c ( f c )` |
| 8 | Mutable struct captured by closure (`: ~ T`) is a **borrow**, not a copy | Don't escape the closure; if you must, use a heap-backed handle |
| 9 | Variadic FFI does not auto-promote `f32` or narrow ints | Declare the exact ABI types in `& \`libname\` @ fn ...` |
| 10 | Multi-char namespace `alias::name` is merged into a single IDENT `alias__name` | Aliases only rename `@`-functions, not types or FFI decls |

---

## 1. `&` and `|` are binary, not n-ary

```nurl
// ✗ Looks like 4 conditions but parses as `& a b`, then `c d` are stray
? & a b c d { ... }

// ✓ Explicit pairing
? & a & b & c d { ... }

// ✓ Or extract a helper (preferred when expressions are long)
@ __ok i status → b {
  ^ & >= status 200 & < status 300 != status 226
}
```

**Why:** the parser greedily binds exactly two operands per `&` / `|`
operator. There is no variadic form. Trailing operands become bare
expressions in the surrounding context — and the parse error is
reported at the *next* token, not at the operator, which is why this
hides easily.

**Real example:** `stdlib/ext/http_middleware.nu` chains range checks
via separate `?` arms instead of one big `&` expression.

---

## 2. Bare `@-fn` names don't auto-coerce to closure params

```nurl
@ eq_int i a i b → b { ^ == a b }

: ( Vec i ) v ( vec_with_cap [i] 4 )

// ✗ `eq_int` parses as a local register lookup → link-time miss
( vec_contains [i] v 42 eq_int )

// ✓ Wrap in a thin closure literal
( vec_contains [i] v 42 \ i a i b → b { ^ ( eq_int a b ) } )
```

**Why:** the parser treats bare identifiers in argument position as
local-symbol lookups, not as references to `@`-defined functions. The
`@-fn` name only resolves at the call site `( name args )`. A closure
literal makes the intent explicit and adopts the right LLVM shape
(`{ fn-ptr, env-ptr }`).

**Helper convention:** wrappers like `eq_int` / `eq_string` /
`cmp_int` / `cmp_string` / `c_int` exist, but they all still need
`\ ... { ( eq_int a b ) }` style wrapping when handed to a closure
parameter.

---

## 3. Same-line shadowing of parameters

```nurl
@ days_since_epoch i z → Time {
  // ✗ The `+ z 719468` reads parameter z, then the `:` introduces a
  //   NEW immutable z that shadows it from this line forward
  : i z + z 719468
  // any further read of `z` now sees the era-shifted value
}

// ✓ Rename
@ days_since_epoch i z → Time {
  : i zz + z 719468        // fine — original `z` still in scope
  ...
}
```

**Why:** `:` introduces a new binding immediately after the right-hand
side is evaluated. The new name is in scope for the rest of the
function, including any subsequent reads — which silently rebind to
the new value. No warning.

---

## 4. Function calls require parens

```nurl
// ✗ `__i_mod a b` parses as: register `__i_mod` plus stray tokens
: i d __i_mod a b

// ✓ Always
: i d ( __i_mod a b )
```

**Why:** there is no implicit-call form. `( fn args )` is the only
call syntax. A bare identifier is always a name lookup — and the
following tokens are then parsed in the surrounding context (often
as operator operands), so the error surfaces several tokens later as
"unexpected token".

---

## 5. Ternary / prefix-arity is strict and silently cascading

```nurl
// ✗ Missing one operand from a nested ternary
: i x ? cond1 a ? cond2 b           // missing else for the inner ?

// → "unexpected token" at the *next* statement, not at the missing
//    operand. The outer parser ate `b` as the inner ternary's value
//    and then can't find an else for the outer.
```

**Why:** prefix notation has no closing token. Parsers count operands
left-to-right and a missing operand silently consumes the next token
that should have started a new statement. The diagnostic always
points at the wrong line.

**Debugging tip:** when you see "unexpected token" on a line that
*looks* fine, count operands on every `?`, `&`, `|`, `!`, `=`, `+`
etc. on the **previous** line.

---

## 6. `vec_clone` is intentionally absent

```nurl
// ✗ No such function — would alias owned heap buffers
: ( Vec String ) copy ( vec_clone [String] src )

// ✓ Shallow clone via vec_each + per-element clone closure
: ( Vec String ) copy ( vec_with_cap [String] ( vec_len [String] src ) )
( vec_each [String] src \ String s → v {
  ( vec_push [String] copy ( string_clone s ) )
} )
```

**Why:** `vec_clone` would do a bitwise copy of the underlying
buffer, duplicating owned-pointer fields without telling the
auto-drop machinery. The result would double-free every owned element
at scope exit. Per-element clone is explicit and respects ownership.

---

## 7. Function-parameter struct mutation is value-semantic

```nurl
: Counter { i n  i max }

@ inc Counter c → v {
  = . c n + . c n 1   // mutates a LOCAL copy
}

@ main → i {
  : Counter c @ Counter { 0 10 }
  ( inc c )
  ( inc c )
  // . c n is STILL 0 from the caller's view.
  ^ 0
}
```

```nurl
// ✓ Canonical share-mutation pattern: return the modified struct
@ inc_returning Counter c → Counter {
  = . c n + . c n 1
  ^ c
}
= c ( inc_returning c )
= c ( inc_returning c )
// . c n is now 2.
```

**Why:** NURL passes struct parameters by value, like C, Go, Zig, and
Rust-without-`&mut`. The compiler emits an `alloca + store` for each
struct-typed parameter at function entry, so `= . p field val` writes
to a fresh local backing — the caller's binding is untouched. NURL
has no `&local` address-of operator, so the only ways to share
mutation across a call boundary are:

* **Return the modified struct** (idiomatic — copy is cheap for
  small structs).
* **Use `*T` parameters** explicitly — the function gets a pointer,
  the caller passes the alloca address. Field writes through the
  pointer reach the caller's memory.
* **Wrap the state in a single-handle struct** (e.g.
  `{ ( Vec i ) counters }`) — the handle is copied but the heap
  buffer is shared. See `stdlib/ext/http_middleware.nu` `Metrics`.

---

## 8. Mutable struct captured by closure is a *borrow*

```nurl
: Counter { i n  i max }

: ~ Counter c @ Counter { 0 10 }
: (@ v) bump \ → v {
  = . c n + . c n 1     // reaches the CALLER's alloca
}
( bump ) ( bump ) ( bump )
// . c n is now 3.
```

When a `: ~`-bound multi-field struct is captured by a closure, the
closure's environment stores the caller's alloca **pointer** rather
than a value snapshot. Writes through the closure reach the caller's
memory; the caller's writes are visible on the next closure call.

This is exactly the right thing for in-place mutation patterns
(metric accumulators, parser state, fold-builder closures). It is
**not safe** when the closure outlives the binding's scope:

```nurl
// ✗ DON'T — the closure's pointer dangles after this function returns
@ make_counter → (@ v) {
  : ~ Counter c @ Counter { 0 10 }
  ^ \ → v { = . c n + . c n 1 }
}
```

NURL does not check for escaping captures. If the closure is stored
in a `Vec[Closure]`, returned from a function, or detached onto a
worker thread that outlives the caller, fall back to a heap-backed
handle:

```nurl
// ✓ Heap-backed handle survives capture by escaping closures
: Counter { ( Vec i ) slots }       // slot 0 = n, slot 1 = max
```

**Rule of thumb:** the closure must finish executing before the
scope holding the captured `: ~` binding exits. Same lifetime
discipline as a C function holding a pointer to a stack local.

**Immutable captures snapshot** (backward-compatible): `: Counter c …`
without `~` is captured by value. Mutations inside the closure are
local. Single-pointer-handle structs (`%String`, `%Vec`) are also
captured by value but share through their inner pointer.

---

## 9. Variadic FFI does not auto-promote

C's variadic ABI promotes `float` to `double` and narrow integer
types to `int` (or `unsigned int`) before the call. NURL's FFI
emits the exact LLVM types declared in the signature.

```nurl
// ✗ Will mis-pass: f32 is sent as `float`, but C's printf reads `double`
& `libc` @ printf i s fmt f32 x → i

// ✓ Widen at the call site
& `libc` @ printf i s fmt f val → i
: f32 narrow # f32 0.5
( printf `%g\n` # f narrow )
```

The same applies to `i8` / `i16` / `i32` passed through `...`:
declare the parameter as `i` and widen the value before calling.

**This is a known gap.** A future grammar revision (v1.9 candidate)
may add automatic variadic promotion. Until then, treat the FFI
boundary as exact.

---

## 10. Namespace syntax merges `alias::name` into one IDENT

```nurl
$ `stdlib/ext/json.nu` json
// At source level you can write:
: Json v ( json::parse `{"k":1}` )
// The lexer merges `json::parse` into the single IDENT `json__parse`.
```

**Caveat:** the `$ path alias` import form only rewrites top-level
`@`-function names. It does **not** rename struct types, enum
variants, FFI decls, traits, or impls. Use plain `$ path` (no alias)
when importing a module whose surface is mostly types — the alias
mechanism doesn't reach them.

---

## Memory-model notes that catch newcomers

NURL is single-owner with compiler-inserted auto-drop. No GC, no
borrow checker. A few specifics worth pinning down:

* **Owned strings and slices** (`( nurl_str_cat a b )`, `[ i | 1 2 3 ]`,
  allocating calls) free at scope exit. Reassignment frees the
  previous value first. Closures capturing owned bindings use RC.
* **Struct-field auto-drop is conservative.** Only fields populated
  from a fresh allocation directly inside the named-struct literal
  get a drop. Copying an already-owned binding into a struct does
  not double-free.
* **`foreach` borrows.** Iterating with `~ x : T xs { ... }` borrows
  each element from the slice — no transfer of ownership, no
  per-element drop.
* **Returning a fresh allocation transfers ownership** to the caller.
* **The `Drop` trait** is recognised by convention. Any `impl Drop`
  with `@ drop T self → v` runs at scope exit, before owned-field
  cleanup.

---

## Cross-references

* Source-level workarounds for any remaining ergonomic gaps are
  commented in `stdlib/ext/http_request.nu`, `http_response.nu`,
  `http_router.nu`, `http_server.nu`, `http_middleware.nu`,
  `regex.nu`, `mcp_client.nu`.
* Roadmap (compiler-side improvements still in flight):
  [`../ROADMAP.md`](../ROADMAP.md) §1.
* Per-release shipped features and breaking changes:
  [`../CHANGELOG.md`](../CHANGELOG.md).
* README's **Known Limitations** table covers deliberate scope
  decisions (no GC, no exceptions, no inheritance); this page
  covers bugs and quirks you can stub your toe on today.
