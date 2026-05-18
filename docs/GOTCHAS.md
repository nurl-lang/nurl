# NURL — Language Gotchas

A single-page reference for the rough edges of NURL (Grammar v2.1)
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
| 3 | Same-line shadowing: `: i z + z 7` shadows the parameter `z` from that line (compiler emits a non-fatal `warning:`) | Rename: `: i zz + z 7` |
| 4 | Ternary arity errors cascade — diagnostic points at the *next* line | Count operands left-to-right on the previous line |
| 5 | Mutable struct captured by closure (`: ~ T`) is a **borrow**, not a copy (compiler warns for `^`-return AND `vec_push` / `vec_insert` / `vec_set` / `thread_spawn` escapes; struct-wrapped indirection slips past) | Don't escape the closure; if you must, use a heap-backed handle |

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
the new value.

**Compiler help:** a `:` binding that matches one of the enclosing
function's (or closure's) parameter names emits a non-fatal `warning:`
line at the binding site. The check is scoped to parameter shadowing
only — block-local `:`-to-`:` shadowing (occasionally intentional in
loop accumulators) is silent.

---

## 4. Ternary / prefix-arity is strict and silently cascading

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

## 5. Mutable struct captured by closure is a *borrow*

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

If the closure is stored in a `Vec[Closure]`, returned from a
function, or detached onto a worker thread that outlives the caller,
fall back to a heap-backed handle:

```nurl
// ✓ Heap-backed handle survives capture by escaping closures
: Counter { ( Vec i ) slots }       // slot 0 = n, slot 1 = max
```

**Rule of thumb:** the closure must finish executing before the
scope holding the captured `: ~` binding exits. Same lifetime
discipline as a C function holding a pointer to a stack local.

**Compiler help:** `^`-returning a closure that captures a
`: ~`-mutable multi-field struct by pointer emits a non-fatal
`warning:` line. Both shapes trip the check — a named closure binding
(`^ bump`) and a closure literal (`^ \ → v { ... c ... }`). Closures
captured by-value (no `: ~`) and closures used locally stay silent.
The check ALSO catches escapes via `vec_push` / `vec_insert` /
`vec_set` / `thread_spawn` (shipped 2026-05-18) — passing a
byref-capturing closure binding to any of these four ownership-taking
helpers emits the same `warning:` line. The check is by-name only:
wrapping the closure in a struct (`@ Slot { cb }` then push the slot)
silently passes through, so the warning catches the obvious one-line
foot-gun rather than every conceivable indirection.

**Immutable captures snapshot** (backward-compatible): `: Counter c …`
without `~` is captured by value. Mutations inside the closure are
local. Single-pointer-handle structs (`%String`, `%Vec`) are also
captured by value but share through their inner pointer.

**Recover-with-typed-result idiom:** the byref-capture path is what
makes `recover` usable for typed returns. The closure must return
void, so the canonical shape is:

```nurl
: ~ HttpResponse out ( response_text 500 `default\n` )
: !v PanicInfo r ( recover \ → v { = out ( risky_handler req ) } )
?? r {
  T _ → { /* `out` carries risky_handler's actual return */ }
  F p → { /* `out` keeps its default; `p.msg` has the reason */ }
}
```

The multi-field-struct + `: ~` combination triggers the byref path so
the assignment inside the closure reaches the caller's alloca. For
scalars or single-handle structs, writes inside the closure stay
local — use a wrapper struct if you need recover-with-result on a
scalar payload.

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

For the wider memory-model story (default-immutable bindings,
value-semantic struct parameters, single-owner auto-drop phases),
see README's **Memory model** section.

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
