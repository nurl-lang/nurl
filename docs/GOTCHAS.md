# NURL — Language Gotchas

A single-page reference for the rough edges of the current self-hosted
compiler (Grammar v1.7). Each entry is a real footgun that recurs often
enough to be worth memorising — most have an inline workaround that is
already used throughout `stdlib/`. If you are an LLM writing NURL, read
this first: it will save you several compile-test cycles.

This page covers **active quirks** of the current compiler. For deliberate
*scope* limitations (no GC, no sized types, etc.) see the **Known
Limitations** table in [`../README.md`](../README.md).

---

## Quick reference

| # | Gotcha | One-line fix |
|---|---|---|
| 1 | `&` and `|` are **binary** — `& A B C` is a parse-arity error | Chain via parens: `& A & B C`, or extract a `__cond` helper |
| 2 | ~~Mutating a multi-field struct's `i` field via `=` does not propagate through closures~~ **Fixed 2026-05-14** — `: ~ T name init` for a multi-field T is now captured by pointer, so closure body writes reach the caller's alloca | — |
| 3 | ~~`: ~ MyEnum x …` (mutable enum binding) miscompiles — i64 stored without `insertvalue`~~ **Fixed 2026-05-14** — `coerce_store_val` now wraps `i64 → %Enum` with an `insertvalue` before store; bare-variant-name reassignment (`= last_err NetTimeout`) works for narrow + wide enums | — |
| 4 | ~~`vec_get [MultiFieldStruct]` returns a wrong default when index is out of bounds~~ **Fixed 2026-05-14** — the `# T 0` cast at the heart of the None synthesis now emits `zeroinitializer` when T's f0 is a non-pointer named type (e.g. `%String`); `vec_get`, `hashmap_get`, and the iter combinators all return a valid None for multi-field T | — |
| 5 | Bare `@-fn` names don't auto-coerce to a `(@ R P*)` closure parameter | Wrap in `\ P* → R { ( fn args ) }` (same as `eq_int` / `c_int`) |
| 6 | ~~Multi-field structs can't ride the `T` arm of `! T E` (Result)~~ **Fixed 2026-05-14** — multi-field T is heap-boxed transparently on construct + `??` destructure + `\` propagate | — |
| 7 | Direct shadowing in the same `:` line: `: i z + z 719468` shadows the parameter `z` from that line forward | Rename to `zz` (or any new name) |
| 8 | Function calls require parens — `__i_mod a b` parses as register-then-loose-tokens | Always: `( __i_mod a b )` |
| 9 | Ternary nesting is arity-strict — a missing/extra operand cascades into "unexpected token" at the next statement | Count operands left-to-right; one wrong arity poisons the line + a few after |
| 10 | `vec_clone` is deliberately absent — bitwise clone would alias owned heap buffers | Roll your own: `vec_each` + `vec_push` + per-element clone closure |

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
expressions in the surrounding context — and the parse error is reported
at the *next* token, not at the operator, which is why this hides easily.

**Real example:** `stdlib/ext/http_middleware.nu:54` chains four range
checks via four separate `?` arms instead of one big `&` expression.

---

## 2. Multi-field struct mutation through closures — fixed

**Fixed 2026-05-14.** Opting a binding into mutability with `: ~` is now
also an opt-in to **capture-by-pointer** for multi-field structs.
Previously the closure machinery heap-malloc'd an env block, copied the
struct value into it, then reconstructed a fresh alloca on every
invocation — so `= . c field val` wrote to a dead local copy and the
caller never saw the mutation.

The new path: when a captured binding has `__mutable = 1` (set by `: ~`)
AND its LLVM type is a named multi-field struct (named type with
`__idx_1__type` registered, not an enum, not a single-pointer-handle),
the env field type becomes `T*`, the value stored is the caller's
alloca pointer, and the body uses that pointer directly as the
binding's `__ptr`. Every read/write reaches the caller's alloca.

```nurl
: Counter { i n  i max }

// Works directly now:
: ~ Counter c @ Counter { 0 10 }
: (@ v) bump \ → v {
  = . c n + . c n 1
}
( bump ) ( bump ) ( bump )
// . c n is now 3 — the closure's writes reached the caller's c.
```

**Backward compatibility:**
* Immutable bindings (`: Counter c …`) keep the value-snapshot
  behaviour — closures see the value at capture time and any internal
  mutations are local. Use this when you want a snapshot, e.g. to
  freeze state before async work.
* Single-pointer-handle structs (`%String`, `%Vec__T`) are unaffected:
  they already share through the inner pointer; capturing by value
  preserves mutation visibility.
* Enums (`%NetErr`, `%Color`) are out of scope for this fix — bare
  `__variants`-registered types stay captured by value, which is
  consistent with their tag-only semantics.

**Lifetime caveat:** capturing by pointer means the closure holds a
borrow of the caller's stack alloca. If the closure escapes the
binding's scope (stored in a `Vec[Closure]`, returned from a function,
detached onto a worker thread that outlives the caller), the pointer
dangles. NURL does not have escape analysis to prevent this; the
user opts in by writing `: ~`. For escaping closures, fall back to a
heap-backed handle pattern (e.g. `( Vec i ) counters` like the
`Metrics` example below).

**Regression test:** `compiler/tests/multifield_struct_mut.nu` covers
the closure-shared-mutation case, the immutable-snapshot baseline, and
whole-struct reassignment through a captured pointer.

**Real example (unchanged):** `stdlib/ext/http_middleware.nu:86–125` —
`Metrics` is still a single-field `{ ( Vec i ) counters }` heap-backed
struct. It predates this fix and ships through Prometheus exposition,
so we kept the working shape; new code that wants metric-style
mutation can use a plain `{ i requests, i in_flight, … }` struct with
`: ~`-bound closures.

---

## 3. Mutable enum bindings — fixed

**Fixed 2026-05-14.** A bare variant name (`Red`, `NetOther`, `NetTimeout`)
resolves through `gen_ident`'s `__global` path to a loaded `i64` tag. The
let-statement / assignment path needed to wrap that `i64` into the enum's
`{ i64, ptr* }` aggregate before storing — previously it didn't, so
`store %NetErr %r0, %NetErr* %slot` triggered a type mismatch in LLVM IR.
`coerce_store_val` now detects when the destination is a registered enum
(via the `<name>__variants` side-table written by `gen_enum_decl`) and
emits `insertvalue %Enum undef, i64 val, 0` before the store.

The symmetric immutable case (`: NetErr e NetOther`) was equally broken
but went undocumented because the canonical idiom built through
`@ NetErr { NetOther }` instead. Both shapes now work.

```nurl
: | NetErr { NetClosed NetAccept NetOther }

// Works directly now:
: ~ NetErr last_err NetOther
= last_err NetAccept              // bare-variant reassignment
?? last_err {
  NetClosed → ...
  NetAccept → ...
  NetOther  → ...
}

// And wide enums (variants with payloads) still go through @ Foo {…}
// for the payload-carrying case — bare names cover tag-only variants:
: ~ Status s Idle                 // tag-only variant via bare name
= s @ Status { Err 7 }            // payload variant via aggregate
```

**Regression test:** `compiler/tests/mutable_enum_binding.nu` covers
narrow / wide enums, immutable / mutable bindings, bare-variant
reassignment, and the http_server.nu pattern `: ~ NetishErr last_err
NetOk` + `= last_err NetTimeout`.

**Follow-up done:** `stdlib/ext/http_server.nu` `server_run` no longer
needs the cheap-re-issue trick — `: ~ NetErr last_err NetClosed`
sentinel + `= last_err e` direct assignment carry the failing variant
all the way past the loop in a single accept call.

---

## 4. `vec_get [MultiFieldStruct]` default — fixed

**Fixed 2026-05-14.** `vec_get [T]`, `hashmap_get [K V]`, and the
`stdlib/std/iter.nu` combinators all build their None case via the
`@ ? T { F # T 0 }` idiom — a cast of `i64 0` into a fresh `T`. When
T's first field was a non-pointer named type (`%String` inside
`Header`, `%Vec__u` inside `MultipartPart`), the cast emitted
`insertvalue %Header undef, i64 0, 0` which LLVM rejected as a type
mismatch on field 0.

The fix lives in `gen_cast`'s `i64 → struct/enum` branch: when f0 is
neither a pointer (existing `inttoptr` + `insertvalue` path) nor `i64`
(existing legacy `insertvalue undef, i64 val, 0` path), the cast now
returns `zeroinitializer` directly. The standard None-payload idiom
unblocks across stdlib without per-caller workarounds.

```nurl
: Header { String name, String value }

// Works directly now:
?? ( vec_get [Header] hs 99 ) {
  T h → { ... never reached for out-of-bounds ... }
  F   → { ... None path observed ... }
}
```

**Regression tests:** `compiler/tests/option_multifield.nu` (construct
+ `??` destructure, including `vec_get [Tagged]` for in-range and
out-of-bounds), `compiler/tests/option_multifield_try.nu` (`\`
propagate through multi-field T).

**Note:** Option `? T` keeps its natural `{ i1, %T }` layout (T stored
directly in the payload slot) — unlike `! T E` which lowers to
`{ i1, i64 }` and heap-boxes multi-field T. The two encodings target
the same use cases but differ at the IR layer because Option already
has room for an inline T while Result's i64 slot has to encode every
T uniformly. The shared abstraction is the `# T 0` cast for the
dummy-zero payload, which both now handle correctly.

---

## 5. Bare `@-fn` names don't auto-coerce to closure params

```nurl
@ eq_int i a i b → b { ^ == a b }

: ( Vec i ) v ( vec_with_cap [i] 4 )

// ✗ `eq_int` parses as a local register lookup → link-time miss
( vec_contains [i] v 42 eq_int )

// ✓ Wrap in a thin closure
( vec_contains [i] v 42 \ i a i b → b { ^ ( eq_int a b ) } )
```

**Why:** the parser treats bare identifiers in argument position as
local-symbol lookups, not as references to `@`-defined functions. The
`@-fn` name only resolves at the call site `( name args )`. A closure
literal makes the intent explicit and adopts the right LLVM shape
(`{ fn-ptr, env-ptr }`).

**Helper convention:** a few ergonomic wrappers exist already —
`eq_int`, `eq_string`, `cmp_int`, `cmp_string`, `c_int` (sort
comparator) — but they all still need `\ ... { ( eq_int a b ) }` style
wrapping when handed to a closure parameter.

**Real example:** any `sort_by` / `vec_contains` / `binary_search`
call site in `stdlib/`.

---

## 6. Multi-field structs ride `! T E` Ok arms (heap-boxed)

**Fixed 2026-05-14.** Multi-field T is now transparently heap-boxed
through the full Result lifecycle: construction, `??` match
destructure, and `\` try-propagate all alloc/store/load/free the
payload behind the scenes.

```nurl
// Works directly now:
: ParsedHead {
  HttpRequest head
  i consumed
}
@ parse_request_head ( Vec u ) buf → ! ParsedHead HttpReqErr { ... }

// Caller threads `\` through chained Results without touching the
// box explicitly:
@ next_step ( Vec u ) buf → ! ParsedHead HttpReqErr {
  : ParsedHead ph \ ( parse_request_head buf )
  // ... use ph.head / ph.consumed directly ...
  ^ @ ! ParsedHead HttpReqErr { T ph }
}
```

**How it works:** `! T E` still lowers to `{ i1, i64 }`. When T is a
multi-field struct (f0 is NOT a pointer) or a wide enum
(`max_payloads > 0`), the i64 payload slot holds a heap-box `%T*`
allocated by `nurl_alloc(sizeof T)` at construction. The receiving
side (`??` arm or `\` propagate) issues `inttoptr → load → nurl_free`
to recover the value and release the box. Single-pointer-handle
structs (Vec, String, opaque-handle `{ s ctl }`) keep the cheaper
ptrtoint path — no allocation, no free.

**Opaque-handle pattern is still useful** for types whose identity
should not be copyable (sockets, mutexes, channels): `Regex`,
`Channel`, `Mutex`, `TcpListener`, `McpClient` continue to wrap a
heap impl struct because their semantics demand shared ownership
through a single handle. The heap-box payload is the right choice
for value-typed multi-field structs (parser outputs, geometry,
metric snapshots) where copy-on-construct is fine.

**Regression cases:** `compiler/tests/result_multifield.nu`
(construct + `??` destructure), `compiler/tests/result_multifield_try.nu`
(`\` propagate through chained Results).

---

## 7. Same-line shadowing of parameters

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

**Real example:** caught during `time_from_unix` development — see
`stdlib/std/time.nu`.

---

## 8. Function calls require parens

```nurl
// ✗ `__i_mod a b` parses as: register `__i_mod` plus stray tokens
: i d __i_mod a b

// ✓ Always
: i d ( __i_mod a b )
```

**Why:** there is no implicit-call form. `( fn args )` is the only
call syntax. A bare identifier is always a name lookup — and the
following tokens are then parsed in the surrounding context (often as
operator operands), so the error surfaces several tokens later as
"unexpected token".

---

## 9. Ternary / prefix-arity is strict and silently cascading

```nurl
// ✗ Missing one operand from a nested ternary
: i x ? cond1 a ? cond2 b           // missing else for the inner ?

// → "unexpected token" at the *next* statement, not at the missing
//    operand. The outer parser ate `b` as the inner ternary's value
//    and then can't find an else for the outer.
```

**Why:** prefix notation has no closing token. Parsers count operands
left-to-right and a missing operand silently consumes the next token
that should have started a new statement. The diagnostic always points
at the wrong line.

**Debugging tip:** when you see "unexpected token" on a line that
*looks* fine, count operands on every `?`, `&`, `|`, `!`, `=`, `+` etc.
on the **previous** line.

---

## 10. `vec_clone` is intentionally absent

```nurl
// ✗ No such function — would alias owned heap buffers
: ( Vec String ) copy ( vec_clone [String] src )

// ✓ Shallow clone via vec_each + per-element clone closure
: ( Vec String ) copy ( vec_with_cap [String] ( vec_len [String] src ) )
( vec_each [String] src \ String s → v {
  ( vec_push [String] copy ( string_clone s ) )
} )
```

**Why:** `vec_clone` would do a bitwise copy of the underlying buffer,
duplicating owned-pointer fields without telling the auto-drop
machinery. The result would double-free every owned element at scope
exit. Per-element clone is explicit and respects ownership.

---

## Cross-references

- Source-level workarounds are commented in
  `stdlib/ext/http_request.nu`, `http_response.nu`, `http_router.nu`,
  `http_server.nu`, `http_middleware.nu`, `regex.nu`, `mcp_client.nu`.
- Tracked compiler-side fixes live in [`../ROADMAP.md`](../ROADMAP.md)
  §1 (multi-field Option Some-arm, generic propagation through
  closures, multi-field struct mutability, mutable enum bindings).
- The README's **Known Limitations** table covers *deliberate* scope
  decisions (no GC, no sized types, …); this page covers *bugs and
  quirks* you can stub your toe on today.
