# NURL Language Reference

**Status:** language specification, grammar v2.2. This document is the
normative reference for the NURL — Neural Unified Representation Language —
source language as implemented by `compiler/nurlc.nu`.

This is a programmer's reference. It defines what a conformant NURL
program is and what it means, at the level of detail needed to read and
write code correctly. Compiler-internal mechanism (LLVM IR shapes,
codegen tactics, bootstrap procedure) is mentioned only where it affects
observable behaviour. For deeper dives see [References](#13-references).

## 1. Conventions

- The **grammar** is given formally in
  [`spec/grammar.ebnf`](../spec/grammar.ebnf). This document does not
  reproduce the EBNF; it summarises and explains it.
- Code snippets in `monospaced` font are NURL source.
- Words in *italics* are technical terms defined elsewhere in the spec.
- "MUST", "SHOULD", "MAY" carry their RFC 2119 meaning.
- Versioned features cite the grammar version that introduced them
  (e.g. *grammar v1.6*).

## 2. Lexical structure

### 2.1 Source files

A NURL source file is a stream of UTF-8 bytes ending in EOF. The file
extension is `.nu`. The compiler accepts files with or without a final
newline.

A source file lexes to a sequence of *tokens* separated by whitespace
and/or comments, terminated by EOF. There are no statement terminators
and no commas anywhere in the language — list elements (function
arguments, struct fields, enum variants, type-parameter lists) are
separated by whitespace.

### 2.2 Whitespace and comments

Whitespace is one or more of space, tab, CR, LF. Whitespace is not
significant except as a token separator. A `-` followed *immediately*
by a digit (no whitespace in between) lexes as the start of a negative
numeric literal; `-` with surrounding whitespace lexes as the binary
minus operator (see §6.3).

Comments start with `//` and run to end of line. There are no block
comments.

### 2.3 Identifiers

A plain identifier is `[A-Za-z_][A-Za-z0-9_]*`.

Adjacent identifiers joined by `::` (no intervening whitespace) merge
into a single identifier token with `__` substituted for `::`:

```
m::alloc             →   single IDENT `m__alloc`
outer::inner::leaf   →   single IDENT `outer__inner__leaf`
```

`::` is purely a lexer glue for identifier chains and produces no token
on its own. The merge applies only to identifiers — type keywords,
boolean literals, and the `Z` sizeof keyword do not participate.

### 2.4 Keywords

#### 2.4.1 Reserved identifiers

The following identifiers are classified by the lexer and MUST NOT be
used as variable, parameter, field, or function names:

| Token | Identifiers | Use |
|---|---|---|
| `TT_TYPE_KW` | `i u f b s v` | single-char type keywords |
| `TT_TYPE_KW` | `i8 i16 i32` | signed fixed-width integers (v1.8) |
| `TT_TYPE_KW` | `u16 u32 u64` | unsigned fixed-width integers (v1.8) |
| `TT_TYPE_KW` | `f32` | 32-bit float (v1.8) |
| `TT_BOOL` | `T` `F` | boolean literals |
| `TT_SIZEOF` | `Z` | sizeof operator |
| `TT_PUB` | `pub` | visibility prefix (v2.0) |

Additionally, the contextual keyword `entry` is rejected as a parameter
name (it collides with LLVM's reserved `%entry` basic-block label).

#### 2.4.2 Contextual keywords

The following words are recognised only in specific syntactic positions
and remain valid identifier characters elsewhere:

- `in` `inout` `sink` — at the start of a function parameter; control
  the parameter passing convention (§7.2). `inout` is additionally
  banned as a parameter name.

### 2.5 Literals

**Integer literal:** `-?DIGIT+`. The leading `-` is part of the literal
only when no whitespace separates it from the first digit. There is no
underscore separator, no hex / octal / binary prefix.

**Float literal:** `-?DIGIT+ '.' DIGIT+ ([eE] [+-]? DIGIT+)?` — a decimal
point is mandatory; an exponent is optional.

**String literal:** backtick-delimited, `` `...` ``. Four escape
sequences are recognised: `\n` (LF), `\t` (HT), `\r` (CR), `\\`
(backslash). Any other `\X` pair passes through verbatim (`\d` stays as
the two bytes `\` `d`, convenient for regex source). The backtick
itself cannot be escaped — strings cannot contain a literal backtick.

**Boolean literal:** `T` for true, `F` for false. `T` also serves as the
conventional type-variable name in generics; disambiguation is
contextual (in a `[…]` type-parameter list and in parameter type
position it names a type variable; elsewhere it is the boolean true).

### 2.6 Operators and punctuation

The lexer recognises the following multi-character operator tokens
(longest match wins; the three-byte forms are matched before their
shorter prefixes):

| Token | Glyph | Notes |
|---|---|---|
| `TT_ELLIPSIS` | `...` | variadic FFI marker (v1.9) |
| `TT_ARROW` | `→` | function return arrow (multi-byte UTF-8) |
| `TT_EQEQ` / `TT_NE` | `==` `!=` | equality |
| `TT_LE` / `TT_GE` | `<=` `>=` | comparison |
| `TT_SHL` / `TT_SHR` | `<<` `>>` | shift |
| `TT_CARETCARET` | `^^` | XOR (v1.8) — two adjacent carets only |
| `TT_QUESTQUEST` | `??` | match |
| `TT_OROR` / `TT_ANDAND` | `||` `&&` | strict-binary logical (v1.8) |

Single-character operator tokens include `+ - * / % < > = ! ? & | ^ ~
\ : ; @ # . $ ( ) { } [ ]`.

**`^` vs `^^`.** A single `^` is the *return* operator. `^^` (two
adjacent carets, with no whitespace between them) is the *XOR*
operator. A stray space, `^ ^`, lexes as two return tokens; this is
almost always a bug and is reported at use-site by the compiler (see
§10.3).

## 3. Modules

### 3.1 Top-level declarations

A program is a sequence of top-level declarations followed by EOF. Each
declaration is one of:

| Form | Decl kind |
|---|---|
| `$ "path" IDENT?` | import |
| `('pub')? & "lib" @ name params → type` | FFI |
| `('pub')? @ name [T]? params → type { body }` | function |
| `('pub')? : Name [T]? { fields }` | struct |
| `('pub')? : | Name { variants }` | enum |
| `('pub')? : type IDENT value` | const / global |
| `('pub')? % Name [T]? { ... }` | trait |
| `('pub')? % Trait [T]? type { methods }` | impl |

There is exactly one entry point, `main`. It returns either `i` — the
value becomes the process exit code, truncated to 32 bits — or `v`, in
which case the process exits `0`. (The reference compiler's own `main`
returns `v`.)

### 3.2 `$`-imports

A `$ "path"` declaration inline-compiles the `.nu` file at `path` into
the current module. The path is resolved relative to the compiler's
current working directory, **not** relative to the importing file.

The same path is imported **at most once** per compilation. Dedup is
keyed on the path string after normalising a leading `./`. Symlink-
equivalent paths still collide as separate imports (path canonicalisation
is roadmap, not yet implemented).

Without an alias, all top-level names from the imported file land in the
global namespace unchanged:

```
$ `stdlib/core/string.nu`
```

With an alias, every top-level `@`-function, struct/enum type, enum
variant, and global `:` constant defined in the imported file is renamed
to `alias__name` by a pre-tokenisation source rewrite; internal
cross-calls inside the imported file are rewritten to match. The
renamed names are reached from the importer via `alias::name`, which
the lexer fuses into the same single identifier:

```
$ `stdlib/core/mem.nu` m
( m::alloc 16 )    // resolves to alias-rewritten `m__alloc`
```

FFI declarations (`& "lib" @ name …`) and trait/impl methods are
intentionally **not** renamed — FFI symbols resolve at the linker by
literal C-ABI name, and trait dispatch is mangled by impl-target type.

### 3.3 `pub` visibility (grammar v2.0)

Any top-level declaration except an import may carry a leading `pub`
prefix to mark it public. Visibility is per-file and **strict-mode is
opt-in**: a source file enters strict mode the first time any of its
top-level decls carries `pub`. Files containing no `pub` decl remain in
legacy mode where every top-level name is globally callable.

In strict mode, every unmarked `@`-function is private to its source
file; a cross-file call is rejected with:

```
file:line:col: error: private function 'X' is not visible across files;
                       defined in 'Y'
```

**Enforcement scope.** In strict mode the cross-file visibility check
covers `@`-functions, structs, enums, top-level consts, and enum
variants — referencing an unmarked one of these from another file is a
hard compile error (e.g. `private type 'X' is not visible across files`).

`pub` on **traits, impl methods, and FFI** declarations is accepted
(forward-compat) but has **no cross-file effect, by design** — this is a
deliberate, locked decision, not a missing feature:

- trait dispatch is resolved by the *type-mangled method name* produced at
  monomorphisation, not by the trait's own name, so a trait/impl has no
  name-based identity to gate; and
- FFI symbols are linker-level ABI globals with no NURL-source identity —
  the linker resolves them across the whole program regardless of which
  file declared them.

The contract is pinned by tests: `pub_trait_ffi_visibility.nu` proves the
unenforced surface (a non-`pub` trait method + FFI) stays callable across
files, and the `should_fail_pub_*` tests prove the enforced surface (a
private fn / struct / const / enum variant) is rejected.

### 3.4 Constants and globals

A `: type IDENT value` declaration at top level binds a constant (or, with
`: ~`, a mutable global). The `value` is normally a single literal.

An **integer-typed** const (`i` / `u` / a sized integer, not `b`) may
instead take a **compile-time-foldable prefix expression** over integer
literals, using the operators `+ - * / << >> & | ^^` (not `%`, which
collides with the trait/impl sigil). The expression is folded to a single
value at compile time (`const_eval_int`):

```
: i SECS_PER_DAY * * 60 60 24            // 86400
: i PAGE        << 1 12                  // 4096
: i INT_MIN     - -9223372036854775807 1 // two's-complement min
```

A mutable global (`: ~ type Name value`) may be reassigned at runtime
with `= Name expr` (§5.2).

## 4. Types

NURL is statically and strongly typed with inference at let-bindings.
There are no implicit conversions: a width or sign change requires an
explicit cast (`#`).

### 4.1 Base types

| NURL | LLVM | Meaning |
|---|---|---|
| `v` | `void` | unit (no value) |
| `i` | `i64` | signed 64-bit integer |
| `u` | `i8` | unsigned 8-bit byte (grammar v1.6) |
| `f` | `double` | 64-bit IEEE 754 float |
| `b` | `i1` | boolean |
| `s` | `i8*` | UTF-8 string (NUL-terminated C string) |
| `i8` `i16` `i32` | `i8` `i16` `i32` | signed sized integers (v1.8) |
| `u16` `u32` `u64` | `i16` `i32` `i64` | unsigned sized integers (v1.8) |
| `f32` | `float` | 32-bit float (v1.8) |

The unsigned variants share LLVM types with their signed counterparts;
the compiler tracks signedness in a side-channel and selects `udiv` /
`urem` / `lshr` / `icmp u*` op families when either operand is unsigned
(grammar v1.8 Phase 1B). Bitwise `&` / `|` / `^^` are sign-agnostic.

Variadic FFI calls auto-promote `f32 → double` via `fpext` and narrow
integers (`i1` / `i8` / `i16`, sign-aware) → `i32` via `sext` / `zext`
per ISO C §6.5.2.2 (grammar v1.9).

`s` (a raw `i8*` C-string) and the stdlib `String` (a managed,
length-headered string, LLVM `%String`) are **distinct types** despite
both being pointer-shaped. They are ABI-compatible enough that a call
passing one where the other is declared would assemble and link, but
reinterpreting one representation as the other is silent
wild-pointer UB — so the compiler **rejects it at the call site**
(in either direction). Convert explicitly: `string_data` (`String → s`)
or `string_from` (`s → String`).

More generally, the call-site argument check rejects three silent-coercion
classes for calls to non-generic functions: a pointer-vs-value mismatch
(`*T` where a `T` value is declared, or vice versa), the `String`/`s`
confusion above, and **passing one named struct value where a different
named struct is declared** (`%A` vs `%B` by value — clang would otherwise
coerce the call and reinterpret the foreign struct's leading fields).
Scalars (including enums, which are `i64`) and pointers are untouched by
the struct check.

The same never-legal clashes are rejected at the other type boundaries:
returning the wrong type from a function (`^ b` of type `B` from a `→ A`
function — the float/pointer/struct dual of the argument check), and
**struct-literal fields** — `@ A { 3.5 }` into an `i` field, or more
field values than the struct declares. Omitting trailing fields stays
legal (they zero-initialise), and integer width / signedness narrowing
into sized or unsigned fields is a legal coercion, not flagged.

### 4.2 Pointer types

`*T` is a raw pointer to T. `*void` is rewritten to `i8*` in the IR
(LLVM forbids `void*`).

`*T` is the FFI ABI escape hatch — NURL's `unsafe`. The borrow checker
does not track `*T` lifetimes; the programmer is responsible for them.

### 4.3 Optional `?T`

`?T` lowers to `{ i1, T }`. The first field is the *Some* tag (1) or
*None* tag (0); the second field is the payload (well-defined only when
the tag is 1).

Construction: `@ ?T { T payload }` for Some, `@ ?T { F # T 0 }` (or any
zero-shaped expression of T) for None.

Destructure with `??` match (§6.4) or `\` propagate (§6.5).

### 4.4 Slice `[T`

`[T` lowers to `{ T*, i64 }` — a borrowed view of a contiguous run of T
elements. The first field is the data pointer; the second is the
length.

A slice may own its backing buffer (a slice literal `[ T | ... ]`, or
the return value of an allocating call). Owned slices are subject to
auto-drop (§8).

### 4.5 Result `!T E`

`!T E` lowers to `{ i1, i64 }`: the tag (1 = Ok, 0 = Err) and a single
i64 slot holding either T or E (integers direct, pointers via
`ptrtoint`, enums via their i64 tag, multi-field T heap-boxed). The
source-level NURL types of T and E are preserved separately for
compile-time `\` try-propagation checking.

### 4.6 Function / closure types `(@ R P*)`

A function-typed *value* in NURL is a *closure* — a 16-byte struct
`{ R(i8*, P...)*, i8* }` holding a function pointer and an environment
pointer. The function pointer takes an implicit leading `i8*` env
argument.

A bare `@`-fn name is **not** a value. Using one in expression position
(e.g. `: c x my_fn`) is a compile error; wrap it in a closure literal:

```
: (@ i i) sq \ i x → i { ( my_fn x ) }
```

### 4.7 Structs and enums

A struct is `:` `Name` `{` field* `}`; a field is `type IDENT?` (the
name is optional when only the type matters). Fields are accessed via
`. obj field` (§6.7).

An enum is `:` `|` `Name` `{` variant* `}`; a variant is
`IDENT type*` — the variant name followed by zero or more payload types.
Each variant compiles to an `i64` tag global named by the variant. The
enum value is `{ i64, ptr, ptr, ... }` sized to fit the variant with
the most payloads.

A variant whose payload is a struct or enum declared *later* in the file
parses correctly via a name pre-pass (grammar v2.1, 2026-05-21). Pattern
matching binds at most 3 payload variables per arm (§6.4).

### 4.8 Generics

Generic functions and structs are parameterised by a type-parameter
list `[T]`, `[K V]`, etc. Each distinct type-argument list used at a
call or type-instantiation site materialises one mangled monomorphic
copy:

```
@ id [T] T x → T { ^ x }
( id [i] 42 )       // → @id__i64
( id [s] `hi` )     // → @id__i8ptr
```

Type arguments at call sites may be *compound types*, not just base
identifiers: a base IDENT (type keyword or named type), a pointer / option
(`*T`, `?T`, `??T`), or a nested generic / closure application
(`( Pair K V )`, `( @ R P* )`). For example `( id [*Point] p )` and
`( box [( Pair i s )] x )` are both accepted; each argument's lowered type
is mangled into the call name. The one shape not accepted as a type argument
is a bare anonymous slice (`[T`) — wrap it in a named struct.

A type parameter may carry one or more **trait bounds** via `: Trait`,
written `[A: Ord]`, `[K: Hash V]`, or `[A: Ord: Show]`. A bound is
checked at every instantiation: the concrete type substituted for the
variable MUST have an `impl` of the named trait, or the compiler rejects
the call naming the unsatisfied bound. Method dispatch inside the body
already resolves to the concrete impl through monomorphisation, so the
bound is an up-front guarantee and documentation rather than a dispatch
mechanism. The bound disambiguates from a slice parameter by the colon —
a slice type never contains one.

```
@ my_max [A: Ord] A x A y → A { ? > ( ord_cmp x y ) 0 x y }   // A must impl Ord
```

`should_fail_trait_bound.nu` pins the rejection; `trait_bounds.nu` pins
the accepted path.

Monomorphisation is deferred — instantiations are queued and emitted
after the main parse pass. Diagnostics emitted while re-parsing a
substituted body use the synthetic filename
`<generic Name__T1[__T2...] from caller.nu:line>` so an error points at
the user's call site (v2.1, 2026-05-25).

## 5. Statements

A *block* is `{ stmt* }`. Each statement is one of:

| Form | Statement kind |
|---|---|
| `:` ... | let binding (§5.1) |
| `=` ... | assignment (§5.2) |
| `;` `{` ... `}` | defer (§5.3) |
| `~` ... | loop / foreach / complement-as-statement (§5.4) |
| *expression* | expression statement (§5.5) |

### 5.1 Let `:`

```
: ~? type? IDENT expr
```

Binds `IDENT` to the value of `expr`. The optional `~` prefix marks the
binding mutable (default immutable). The type annotation is optional
when inferable from the right-hand side; an identifier that names a
registered type is taken as the type annotation, otherwise the
plain-IDENT form is type-inferred.

```
: i n 0                          // explicit type
: ~ i x 0                        // mutable
: String s ( string_new )        // named type
: n ( add 1 2 )                  // inferred
```

A binding whose RHS is a fresh heap allocation becomes the *owner* of
that allocation (§8).

### 5.2 Set `=`

```
= IDENT expr
= '.' expr ( IDENT | INT | expr ) expr
```

Reassigns an existing binding (local or global), or writes a struct
field / array slot / slice element / pointer element via GEP + store.

Reassigning an *immutable* binding, a parameter (without `inout`
convention), or an immutable global is a compile error.

The index form is chosen by the LHS LLVM type:

| Object type | Index | Effect |
|---|---|---|
| struct pointer `%T*` | IDENT | field lookup |
| raw pointer `T*` | INT literal | array slot, constant index |
| raw pointer `T*` | expression | array slot, computed index |
| slice `{ T*, i64 }` | INT or expr | slice element via data ptr |

### 5.3 Defer `;`

```
; { body }
```

Executes *body* when the enclosing function returns (LIFO order across
multiple defers). Useful for guaranteed cleanup.

### 5.4 Loop, foreach, complement-as-statement

The `~` token at statement position is *speculatively* parsed in this
order:

1. `~ IDENT IDENT …` — foreach
2. `~ expr {` — while loop
3. otherwise — complement expression used for its side effects

```
~ cond { body }              // while
~ x xs { ( puts x ) }        // foreach (xs must have slice type)
```

In a foreach, the element binding is a *borrow* from the iterated
slice. It is not owned and is not dropped at iteration end. Mutating
the iterated container from inside the loop body is rejected by the
borrow checker (§9.5).

### 5.5 Expression statements

A statement may be any expression. The value is discarded.

A bare identifier that names a known callable (an `@`-function, an FFI
function, or a runtime builtin) is rejected at statement position with:

```
error: bare identifier 'name' as a statement has no effect — calls in
       NURL are written '( name args )', not 'name args'. Did you
       forget the parens?
```

This catches the canonical "forgot the parens" foot-gun
`nurl_print "hello"` (v2.1, 2026-05-25).

## 6. Expressions

Every expression is in **prefix notation**: operator first, operands
after. Every operator has fixed, known *arity* — there are no grouping
parentheses for precedence. Parentheses appear only in function calls
`( f a b )`, function-type literals `(@ R P)`, and generic-type
instantiation `( Name A )`.

> **Design decision — no grouping/closing delimiter (locked for 1.0).**
> Fixed prefix arity with **no closing token** is the permanent surface
> form. An expression's shape is fully determined by each operator's known
> arity, so the grammar stays a regular LL(k≤4) with no precedence table and
> no balancing parentheses — which is the entire point of the notation, and
> the largest contributor to its token economy.
>
> This is the one ergonomics objection a reader raises ("how deep can the
> un-parenthesised nesting get before it's unreadable?"), so the call was
> made against data rather than taste. A sweep of the whole first-party
> corpus (~77 000 lines: the self-hosted compiler, the HTTP/1.1+2 +
> WebSocket stack, a regex engine, crypto, and the Game Boy / C64
> emulators) measured, per line, the longest run of consecutive prefix
> operators:
>
> | chain depth | lines | share of operator lines |
> |------------:|------:|:------------------------|
> | 1           | 14527 | ~78 %                   |
> | 2           |  3415 | ~18 %                   |
> | 3           |   495 | ~2.7 %                  |
> | 4           |    83 | 0.4 %                   |
> | ≥5          |    19 | 0.025 % of all lines    |
>
> ~96 % of operator-bearing lines nest only one or two deep — trivially
> readable in prefix — and just 19 lines in the entire corpus reach depth 5.
> Those few cluster in two recognisable idioms (n-ary boolean membership
> `| | == c A == c B …`, and big-endian byte assembly), both of which have
> ordinary library answers — a predicate helper (the codebase already does
> this: `is_alpha` / `is_digit` / `is_space`) or an intermediate `:`
> binding. The data shows the bare form is adequate for real, dense code;
> the foot-gun shape (an operator silently short an operand) is caught by
> the front-end's dead-value / prefix-arity-cascade diagnostics, not left to
> the reader.
>
> The decision is also **safe to revisit additively**: an *optional*
> grouping form could be introduced after 1.0 without breaking any existing
> program, should a genuine need ever emerge. What 1.0 locks is the
> negative — prefix arity is canonical and there is no required closing
> token — not a door permanently shut.

### 6.1 Operator forms and arities

#### Strictly binary (2 operands)

```
+ - * / %       arithmetic (integer + float)
< > <= >= == != comparison (yields b)
<< >>           integer shift
& |             logical (b) OR bitwise (integer); dispatched by LHS type
^^              XOR (integer or b; float is an error)
&& ||           strict logical (b only) — alternate spelling of & / |
```

`<<` and `>>` lower to LLVM `shl` / `ashr`. The shift count is `i64` by
convention; only the low 6 bits matter for `i64` operands. Out-of-range
counts behave per LLVM (poison for `>=` bitwidth).

Comparison operators yield `b` (`i1`). All other binary operators
require operand types to match.

For an n-ary chain write n-1 operators:

```
& a & b & c d        // a && b && c && d
| | | a b c d        // a || b || c || d
```

The compiler warns on the canonical foot-gun
`? & a b c d { ... } { ... }` (the bare `c`/`d` are consumed as the
ternary's then/else, the `{ ... }` blocks become statements).

#### Unary (1 operand)

```
! expr     logical NOT
^ expr     return
~ expr     bitwise complement (xor -1) for integers; fneg for f
\ expr     try-propagate (disambiguated from closure by lookahead, §6.5)
```

There are no unary arithmetic operators. To negate a value, use binary
minus against a literal zero or bitwise complement of zero:

```
- 0 x        // unary negate: 0 - x
~ 0          // -1, useful for bit-twiddling
```

Negative *literals* are directly supported at the lexer level: a `-`
immediately followed by a digit (no whitespace) lexes as the start of a
negative INT or FLOAT token.

#### Ternary

```
? cond then else
```

Both `then` and `else` are full expressions. A block expression `{ ... }`
is a common form. Branch types must match; mismatched branches degrade
to `void`, which the enclosing return/let then flags.

#### Match

```
?? expr { arm* }
```

Pattern match on enum, `?T`, or `!T E`. Each arm is
`variant_or_pattern payload* → result`. Exhaustiveness is checked at
compile time: every variant MUST be covered, or a `_` wildcard arm
MUST be present. Duplicate arms (without literal constraints) are
rejected.

A pattern is one of:

- `IDENT` — a variant name (or the boolean pattern `T`/`F` when
  matching `?T`).
- `_` — wildcard, covers all otherwise-unmatched variants.
- `IDENT | IDENT ...` — an **or-pattern**: one arm covering several
  tag-only variants (`Spring | Summer → ...`). Or-patterns take no
  payload binding, no literal constraint, and no guard.

A payload slot is one of:

- `IDENT` — binds the payload at that position.
- `INT` — compares equality with the payload value (literal constraint).

```
?? val {
    JNull        → `null`
    JNum n       → ( nurl_str_int n )
    KeyPress c m → ( key_event c m )    // 2-payload binding
    Ok 200       → `ok`                 // literal-constrained
    _            → `other`
}
```

A pattern arm binds at most 3 payload variables.

An arm may carry a **guard** — `? cond` after the payload, before the
`→` — evaluated *after* the payload bindings are in scope. A false guard
falls through to the next arm, so a guarded arm does **not** satisfy
exhaustiveness for its variant: a later catch-all (another arm for the
variant, or `_`) is still required. Guards are not allowed on a `_`
wildcard or an or-pattern.

```
?? msg {
    Move n ? > n 0 → `forward`
    Move n         → `back-or-stay`    // catch-all for Move
    _              → `other`
}
```

### 6.2 Evaluation order

NURL evaluates expressions **left-to-right**. Function call arguments
are evaluated left-to-right and fully evaluated before the callee is
invoked. There is no exception for `inout` argument binding: an
`inout c` argument takes the address of `c` at the moment that
argument-position is evaluated, but the *call* itself is only invoked
after every argument has been evaluated.

A consequence: an `inout` borrow lives exactly for the duration of the
call. Reads of the same binding through nested sub-expression arguments
(`( f inout c (g c) )`, `( f inout c . c n )`) read `c` *before* the
borrow goes live and are well-defined — no overlap with the mutation
that happens inside `f`. The borrow checker does not flag these
nested-read shapes (this is a deliberate consequence of *mutable value
semantics*, §9).

### 6.3 `^` return vs `^^` XOR

`^` is the **return** operator and is strictly unary: `^ expr` returns
`expr` from the enclosing function.

In a function declared `→ v` (returns nothing) a **bare `^`** — with no
following value expression — is a valid early return (it emits
`ret void`). The converse is rejected: giving `^` a value in a `→ v`
function (`^ 0`) is a compile error, as is a bare `^` in a
value-returning function (`^` with no expr where a return value is
required). `^ ( void_call )` is permitted — it tail-returns a `v` call.

`^^` (two adjacent carets, no whitespace) is the **XOR** operator and
is strictly binary: `^^ a b`. On integer operands it is bitwise XOR; on
`b` (i1) operands it is logical XOR (no short-circuit — `xor` cannot).
Float operands are a compile error.

`^ a b` parses as `^ a` followed by a separate `b` expression statement.
When `b` is on the same line as `^` and is value-producing, the compiler
emits the warning:

```
warning: '^' is the return operator; did you mean '^^' for XOR? (Two
         adjacent carets, no space between them)
```

(v2.1, 2026-05-25.)

### 6.4 Closures and try-propagate (the `\` disambiguation)

The `\` token serves two purposes; the parser disambiguates by looking
at the next 1–3 tokens:

| Lookahead | Form |
|---|---|
| `→` | closure, zero params |
| `TYPE_KW` / `*` / `?` / `[` / `!` | closure, leading param type |
| `(` `@` | closure, fn-type param |
| `IDENT IDENT →` | closure, single named param |
| anything else | try-propagate |

```
: (@ i i) sq \ i x → i { * x x }     // closure
: n \ ( parse_int src )              // try-propagate Result
```

A closure compiles to a 16-byte `{ fn_ptr, env_ptr }` value. Captures
are stored in a heap-allocated environment struct. A closure that
provably does **not** escape its creating frame has that env reclaimed
automatically — an inline closure passed to an invoke-only parameter is
freed right after the call, and a `:`-bound closure is freed at scope
exit. An env is left for *you* to free (via the env pointer, `# *u f 1`)
only when the closure genuinely escapes: it is returned, stored into a
container or struct field, captured into another closure, or detached
onto a thread. The escaping-closure env is therefore one of the
manually-managed handles (§8); it is **not** reference-counted. See
[`docs/MEMORY.md` §7.4](MEMORY.md) for the full reclamation rule.

### 6.5 Function calls

```
( fn [T+]? arg* )
```

The optional `[T+]` is a generic-instantiation type-argument list,
present only when `fn` is generic.

A call's first token must be an identifier. Operator tokens are not
callable: `( . obj field )` is rejected — write `. obj field` directly
without the parens.

#### Keyword arguments (grammar v2.2)

A trailing parameter may carry a **default value** — `= atom`, where
`atom` is a single token (a literal, a const name, or `T` / `F`):

```
@ box s label i width = 10 s fill = `-` → v { ... }
```

A call may then **omit** defaulted trailing arguments, and may pass any
argument **by name** with an `IDENT:` label. Named arguments may appear
in any order and follow any leading positional ones; omitted parameters
fall back to their defaults:

```
( box `a` )                    // width=10  fill=`-`
( box `b` 3 )                  // width=3   fill=`-`
( box label: `d` fill: `=` )   // named, reordered; width defaults
( box `e` fill: `#` width: 5 ) // positional + named, reordered
```

Defaults are filled **at the call site** — the callee receives a full,
fixed-length argument list, so a defaulted function is an ordinary
fixed-arity function with no runtime cost. A positional argument after a
named one is rejected. Defaults and named arguments are **not** available
on generic functions, FFI / variadic declarations, or parameters carrying
the `inout` / `sink` convention. `kwargs.nu` pins the feature.

#### Parameter conventions

A function parameter may carry a leading convention marker (§7.2):

- *(none)* / `in` — immutable borrow by value (the default).
- `inout` — exclusive mutable borrow. The argument MUST be a mutable
  (`: ~`) binding or a field target `. obj field`; it is passed by
  address. The callee mutates the caller's storage in place. An
  `inout` function MUST be defined before it is called.
- `sink` — consume / move. The callee takes ownership; the caller may
  not use the argument binding afterwards. Compiler-auto-dropped
  values (owned strings / slices / Drop-trait values) cannot yet be
  `sink`-passed.

#### Auto-inferred `sink` (v2.1, 2026-05-25)

A function whose body passes one of its own parameters to a `*_free`
destructor or to another function's `sink` slot has that parameter
**auto-inferred** as `sink`. Call sites of such a wrapper see the
sink-arg-path: the argument is move-marked, and a subsequent read is a
use-after-move error.

```
@ take String s → v { ( string_free s ) }   // s auto-inferred sink

@ main → i {
    : String s ( string_from `hi` )
    ( take s )                              // s is consumed
    ( nurl_print ( string_data s ) )         // error: use of moved value
}
```

### 6.6 Member access `.`

```
. obj index
```

The compilation rule is chosen by the LLVM type of `obj`:

| Object type | Index | Effect |
|---|---|---|
| struct pointer `%T*` | IDENT | GEP field lookup + load |
| raw pointer `T*` | INT | array slot, constant index |
| raw pointer `T*` | expr | array slot, computed index |
| `{ i1, T }` (opt / res) | 0 / 1 | tag / payload |
| slice `{ T*, i64 }` | 0 / 1 | data ptr / length |
| named struct `%T` | IDENT | extractvalue by registered field idx |
| enum value `%T` | 0 | whole value (for `??` match input) |

### 6.7 Cast `#`

```
# target_type expr
```

Explicit type coercion. Used for width changes, signed↔unsigned
reinterpretation, pointer casts, and the canonical closure-field-extract
pattern:

```
# i ( some_fn )                  // i64-truncate / widen
# *Point ( nurl_alloc 16 )       // cast i8* to *Point
# *u closure 0                   // extract fn ptr from closure
# *u closure 1                   // extract env ptr from closure
```

The trailing INT (0 or 1) is consumed only when the source expression
is a closure-shaped struct and the destination type is a pointer — the
common shape for feeding C-runtime callback APIs (`thread_spawn`,
signal handlers) the raw fn-ptr / env-ptr pair.

### 6.8 Sizeof `Z`

```
Z type
```

Byte size of *type* as an `i64`. The fold is keyed on the *LLVM* type:
a type lowering to `void` (`0`), `i64` (`8` — `i` and `u64`), `double`
(`8` — `f`), `i1` (`1` — `b`), or any pointer (`8` — `s`, `*T`) folds to
a compile-time constant. Every other type uses a `getelementptr null`
trick so LLVM computes the size at emission time, yielding the natural
width: `u` 1, `i8` 1, `i16` / `u16` 2, `i32` / `u32` 4, `f32` 4, and any
named or aggregate type. **`Z u` is therefore 1, not 8** — `u` is a
single byte.

### 6.9 Aggregate / slice literals

```
@ type { expr* }            // aggregate / enum constructor
[ type | expr* ]            // slice literal
```

`@ Name { f0 f1 ... }` builds a struct, enum value, or `?T` / `[T` /
`!T E` field by field. Enum-variant constructors prefix the payload
with the variant name: `@ Json { JNum 42 }`.

`[ T | v0 v1 v2 ]` allocates a heap array of 3 T values and returns a
slice owning the buffer. Layout: field 0 = `T*` data, field 1 = `i64`
length.

### 6.10 Channel select

A `??` whose scrutinee is *immediately* `{` has no value to match and is
parsed as a **Go-style channel select** (distinct from the `?? expr {`
match of §6.1). It proceeds with the **first ready** channel arm, in
source order (deterministic priority):

```
?? {
    [i]      jobs    → o { ?? o { T n → ( work n )  F → ( quit ) } }
    [String] control → o { ?? o { T s → ( handle s ) F → ( quit ) } }
    _                → { /* nothing ready */ }
}
```

Each channel arm is `[ type ] chan_expr → IDENT { body }`: it receives
from `chan_expr` (a bare identifier or a parenthesised call, evaluated as
a borrow), binding the result to a `?T` option — `T v` yields a value,
`F` means the channel is closed and drained. With **no** `_` default arm
the select **blocks** until some channel is ready; with a `_` arm it
never blocks — the default runs when nothing is ready. Selects lower to
the rendezvous primitives in `stdlib/std/channel.nu`; `select_basic.nu`
pins the construct.

## 7. Functions

### 7.1 Declaration

```
@ name [T]? param* → ret { body }
```

Function declarations are top-level only (the `@` token in expression
position is the aggregate-literal start). A function MUST have at
least the return-type arrow `→` and a body block.

A trailing parameter may carry a **default value** `= atom`
(`@ sum3 i a i b = 100 i c = 1000 → i { ... }`); callers may then omit it
or pass it by name. See §6.5 for the call-site rules and restrictions.

### 7.2 Parameter conventions

NURL uses **mutable value semantics**. A parameter is one of three
conventions:

- **`in`** (default) — immutable borrow by value. Struct-typed
  parameters are copied into a fresh `alloca` at function entry;
  `= . p field val` inside the callee writes that local copy.
- **`inout`** — exclusive mutable borrow. Lowers to a `<T>*` parameter;
  the argument is passed by address, so the callee's writes land on
  the caller's storage. Generic functions may take `inout` parameters
  too.
- **`sink`** — consume. The callee takes ownership; the caller's
  binding is marked moved. Lowers to an ordinary by-value parameter
  (no IR change beyond the value pass-through); the move check is
  enforced at the call site.

`in` / `inout` / `sink` are contextual keywords — recognised only as a
parameter's leading token. `inout` is additionally banned as a
parameter name.

### 7.3 Return ownership

Returning a fresh allocation **transfers ownership** to the caller. The
callee emits no drop for the returned value; the caller's binding
becomes the new owner (§8).

### 7.4 Tail-call optimisation

`^ ( fn args )` at the end of a function body emits an LLVM `tail call`
when all of:

- The flag was set by `gen_ret` at the immediately enclosing return.
- The callee's return type matches the caller's declared return type.
- The callee is not variadic.
- No pending owned-string / owned-slice / owned-struct-field / user-Drop
  / `;`-defer remains in scope.

LLVM converts a self-recursive tail call into a jump, allowing unbounded
recursion. Trait / impl / closure / fn-pointer-parameter dispatch paths
intentionally emit a plain `call` (different shapes; not deep-recursion
targets).

### 7.5 Generic functions

A generic function carries a `[T+]` type-parameter list immediately
after the function name:

```
@ id [T] T x → T { ^ x }
```

Type arguments at call sites may be compound types — a base identifier
(type keyword or named type), a pointer / option (`*T`, `?T`, `??T`), or a
nested generic / closure application (`( Pair K V )`, `( @ R P* )`); only a
bare anonymous slice (`[T`) is excluded. Each distinct argument list
materialises one mangled monomorphic copy. The body is stored as source
text at the declaration and re-parsed per instantiation.

Generic functions support `inout` and `sink` parameter conventions —
since parameter conventions depend only on parameter *position*, not
the instantiating type, the convention sets are computed once per
generic template and shared across all instantiations.

## 8. Memory model

NURL has no GC. Heap allocations are managed by **single-owner
auto-drop**: the compiler tracks which binding owns each heap resource
and inserts the matching free at the end of that binding's scope. See
[`docs/MEMORY.md`](MEMORY.md) for the implementation-level reference
and the borrow checker's per-rule semantics.

### 8.1 Single owner

A `:` binding becomes the **owner** of a heap resource when its
right-hand side is a *fresh allocation produced on the spot*:

- a slice literal `[ T | ... ]`,
- a slice-returning call,
- an allocating string call (`nurl_str_cat`, `_cat3` / `_cat4`,
  `_int`, `_float`, `_slice`, `nurl_read_file`),
- a named-struct literal `@ T { ... }` whose fields are themselves
  fresh allocations (each is tracked individually),
- a value of a type with a user `Drop` trait impl.

The compiler only registers a drop for a resource it saw allocated
*directly*. Copying an already-owned binding into another binding does
**not** register a second drop — the model is conservative by
construction.

### 8.2 Auto-drop

At the end of an owning binding's scope, the compiler emits the
matching `nurl_free` / typed-`*_free` / `drop__T`. Reassigning an owned
binding (`= x <owned-call>`) frees the previous value first. Branch-
local allocations (in a `?` / `??` / `~` arm) that the arm does not
yield are dropped when control flows out of that arm.

### 8.3 Drop trait

A `% Drop` impl `@ drop T self → v { ... }` is recognised by
convention: whenever an owned binding of type `T` reaches its
scope-exit point, the compiler inserts a call to `drop__<T-mangle>(self)`
before freeing any owned fields of `T`. User `drop` methods MUST NOT
panic and SHOULD NOT free the self pointer themselves — that
responsibility belongs to the auto-drop machinery.

### 8.4 Closure environments

A closure's heap environment is **not** reference-counted. Instead the
compiler reclaims it whenever the closure provably does not escape — an
inline closure handed to an invoke-only parameter is freed right after
the call, and a `:`-bound closure is freed at scope exit (each iteration
in a loop body). When the closure genuinely escapes — returned, stored
into a container or struct field, captured into another closure, or
detached onto a thread — the env becomes a **manually-managed handle**
(§6.4): the consumer frees it via the env pointer. See
[`docs/MEMORY.md` §7.4](MEMORY.md) for the exact escape-site list.

A closure may *capture by pointer* a mutable (`: ~`) multi-field struct
binding (see [`docs/MEMORY.md` §2.3](MEMORY.md) for the lifetime rule):
the env block stores the caller's alloca pointer rather than a value
snapshot, so writes through the closure reach the caller's binding. A
by-pointer capture borrows the caller's stack frame and MUST NOT
out-live it. The borrow checker rejects an escaping by-ref capture
(returning the closure, pushing it into a longer-lived container,
spawning a thread that holds it).

## 9. Borrow checker

The borrow checker is a static analysis pass over the parsed program.
It is **on by default**; `--no-borrowck` disables it, and
`--strict-borrowck` (off by default) adds two opt-in checks on top
(see [`docs/MEMORY.md` §2.9](MEMORY.md)). Diagnostics are **hard
errors** as of grammar v2.1 (2026-05-25); the compiler exits non-zero
with a count of violations after walking the whole program. The checker
is **diagnostic-only** — emitted IR is byte-identical whether it runs or
not.

Eight rules are enforced. The semantic level is summarised here; for
exact phrasing and the soundness contract see
[`docs/MEMORY.md` §2 and §6](MEMORY.md).

### 9.1 Move (use-after-move)

A binding is *moved* when consumed: passed to a `*_free` family
destructor, or to a `sink` parameter, or copied into another binding
(see §9.2). After a move, reading the binding is rejected.

### 9.2 Alias / double-free

An immutable `: T b a` copy of an owned-heap binding `a` is treated as
a *move* — ownership passes to `b`. A `: ~` mutable copy is treated as
a borrow / cursor, not a move (this is the conventional disambiguation
between "owning copy" and "working alias"). Distinguishing borrow from
move in the general case is the job of a later reference-surface phase.

### 9.3 Escape analysis

A closure capturing a `: ~`-mutable multi-field struct binding by
pointer (see §8.4) is a *stack reference*. Returning it, pushing it
into a longer-lived container, spawning a thread that holds it, or
assigning it into a longer-lived binding is rejected. The escape rule
also covers an aggregate (struct) literal that holds such a closure.

### 9.4 Exclusive access at a call site

A binding passed `inout` to a call MUST NOT be aliased by another
*bare-identifier* argument of the same call (whether that other one is
`inout` or a plain by-value read). This is the "N readers XOR 1
writer" rule scoped to a single call.

```
( swap_counters c c )   // error: 'c' is both mutably borrowed and
                         //         aliased by another argument
```

A read of the same binding through a *nested sub-expression* argument
(`( f inout c (g c) )`, `( f inout c . c n )`) is **not** flagged — by
the language's left-to-right evaluation order and Option B's
call-scoped borrow lifetime, that read completes before the `inout`
borrow goes live (§6.2).

### 9.5 Iterator invalidation

In a `~ x xs { ... }` foreach loop, the iterated container `xs` is
borrowed for the body's duration. Mutating `xs` inside the body — via a
stdlib container mutator on its receiver arg 0
(`vec_push` / `vec_insert` / `vec_remove` / `vec_pop` / `vec_clear` /
`vec_set` / `vec_set_len` / `vec_reserve` / `vec_shrink_to_fit` /
`vec_extend` / `vec_free` / `vec_free_with` / `vec_swap` /
`vec_reverse`) or as an `inout` argument — is rejected.

Index-based mutation loops (`~ i k 0 ...`) borrow nothing and stay
legal.

### 9.6 Loop-carried move

A binding consumed inside a `~` loop is moved on entry to the *next*
iteration. If it was live before the loop and the body never re-binds
it, re-reading it on the second pass is a guaranteed use-after-move —
the classic "free inside a loop" double-free — and is rejected. Three
shapes stay legal because each is freshly owned every iteration: freeing
the loop element, freeing a binding declared inside the body, and freeing
an outer binding the body re-binds before the next read.

### 9.7 Interprocedural escape

A stack reference can escape not only directly (§9.3) but through a
**helper**: passed to a function that stores it in a heap container or
detaches it onto a thread. The checker computes a per-function *escape
summary* (which parameters the body lets escape, transitively) and
rejects passing a stack reference to an escaping parameter. Forward and
generic calls are handled by parking the check and replaying it after the
whole module compiles, so definition order does not matter; the one
residual is a *pure forward chain* of helpers (§9.9).

### 9.8 Return escape

A helper that **returns one of its parameters** (directly, or inside a
returned struct) hands the reference back out. The checker records a
second summary of returned-parameter positions; the result of such a call
carries the max referent depth of the arguments at those positions, so
the existing escape sinks (§9.3 / §9.7) fire on it. A helper that returns
a *fresh* value is not a passthrough and stays legal.

### 9.9 What is NOT checked

- `*T` raw pointer lifetimes (the FFI escape hatch) — except the one
  narrow `# *T`-escape check `--strict-borrowck` adds (§9 intro).
- Aliased mutation beyond a single call (longer-range "exclusive
  reference" analysis is not currently implemented), and a binding read
  through a *nested* sub-expression argument (§6.2) — though
  `--strict-borrowck` does flag aliased mutation through a `. obj field`
  argument.
- A *pure forward chain* of escaping helpers (§9.7) and a parameter
  returned through a closure *capture* rather than a struct field (§9.8) —
  the residual interprocedural gaps. Both degrade the *diagnostic* only,
  never a miscompile.
- Panic / `recover` control flow: the checker treats `recover` as an
  ordinary call and does not model panic unwind. It does not need to —
  the owned allocations a panic `longjmp` would skip are reclaimed at the
  panic itself by a thread-local allocation journal, so they leak neither
  the normal nor the unwind path (see [`docs/MEMORY.md` §7.2](MEMORY.md)).
- **Conditional** (maybe-moved) double-frees: a value freed on only one
  arm of a `?` and then freed again is not flagged, to keep every
  diagnostic a *definite* bug (the no-false-positive contract,
  [`docs/MEMORY.md` §6.3](MEMORY.md)).

## 10. Diagnostics

### 10.1 Errors as the API

NURL treats compiler errors and warnings as the primary user interface,
not the spec. The historical "gotchas list" is empty by policy: every
previously-required-memorisation foot-gun is surfaced as a compiler
`error:` or `warning:` with a pointing caret and the concrete cure
inline. The compiler MUST emit ASCII-only diagnostic text (legacy
constraint inherited from a now-removed Python stage-0 lexer; may be
relaxed in a future revision).

### 10.2 Diagnostic shape

Every diagnostic carries:

- A location prefix `file:line:col:`.
- A severity tag — `error:`, `warning:`, or `note:`.
- A message naming the offending construct and pointing at a cure.
- The source line text.
- A caret line pointing at the column.

Example:

```
foo.nu:6:3: error: bare identifier 'nurl_print' as a statement has no
                    effect — calls in NURL are written '( name args )',
                    not 'name args'. Did you forget the parens?
  nurl_print `oops`
  ^
```

### 10.3 The grammar v2.1 Tier-A diagnostics

Four new diagnostics shipped 2026-05-25 closing the remaining
"grammar-legal but semantically dead" silent-compile shapes:

1. **`^ X Y` on the same line** — warning naming `^^` as the XOR
   operator (§6.3).
2. **Bare callable as statement** — error pointing at `( name args )`
   as the call form (§5.5).
3. **Use-after-`_free` via wrapper** — error via auto-inferred `sink`
   convention on parameters that the wrapper's body consumes (§6.5).
4. **Per-instantiation source line for generics** — diagnostics emitted
   while re-parsing a substituted generic body name the call site,
   not the synthetic generic filename (§4.8).

## 11. Conformance

### 11.1 Grammar version

This document corresponds to **grammar v2.2** (keyword arguments —
default parameter values + named call arguments). The authoritative
grammar lives in [`spec/grammar.ebnf`](../spec/grammar.ebnf); changes
since v1.x are tracked in that file's prelude.

A compiler is "v2.2 conformant" if it accepts every program the EBNF
generates and rejects every program the EBNF does not generate, with
the semantics defined here. A program is "v2.2 portable" if it relies
only on features documented in this spec or in
[`spec/grammar.ebnf`](../spec/grammar.ebnf) — not on
compiler-internal accidents.

### 11.2 Bootstrap

The reference compiler `compiler/nurlc.nu` is self-hosting. The
build is a three-stage fixed point:

1. **Stage 0.** `clang` links the committed
   `compiler/nurlc_lastgood.ll` (target-triple-agnostic LLVM IR text)
   plus `stdlib/runtime.o` into a `nurlc_lastgood.bin`. Only build-time
   dependency is `clang/LLVM 15+`.
2. **Stage 1.** `nurlc_lastgood.bin` compiles `compiler/nurlc.nu` →
   `build/nurlc_self.ll` → `build/nurlc_self`.
3. **Stage 2.** `nurlc_self` compiles `compiler/nurlc.nu` again →
   `build/nurlc_self2.ll` → `build/nurlc_self2`.
4. **Fixed-point check.** `diff nurlc_self.ll nurlc_self2.ll` MUST be
   empty.

Any compiler change that breaks the fixed point is a regression.

### 11.3 Reserved future syntax

The following identifiers / tokens are reserved for future use and
SHOULD NOT be used as variable names:

- `in` `inout` `sink` — parameter conventions.
- `pub` — visibility.
- `Z` — sizeof.
- `T` `F` — booleans.
- `i` `u` `f` `b` `s` `v` `i8` `i16` `i32` `u16` `u32` `u64` `f32` —
  type keywords.
- `entry` — collides with LLVM's basic-block label.

## 12. Acknowledgements

The borrow-checker design (Option B, mutable value semantics) is
inspired by Hylo / Val. The "compiler errors are the API" stance
echoes Elm and Rust; the bootstrap layout (committed target-agnostic
IR blob + deterministic compiler + fixed-point check) mirrors Zig.

## 13. References

- [`spec/grammar.ebnf`](../spec/grammar.ebnf) — authoritative grammar.
- [`docs/MEMORY.md`](MEMORY.md) — memory model and borrow checker
  programmer's guide.
- [`docs/GOTCHAS.md`](GOTCHAS.md) — source-level traps (currently none;
  the compiler diagnoses them at the point of error).
- [`docs/FORMAT.md`](FORMAT.md) — `nurlfmt` rules.
- [`docs/ASYNC.md`](ASYNC.md) — async runtime design.
- [`README.md`](../README.md) — project overview and tutorials.
- [`CHANGELOG.md`](../CHANGELOG.md) — release notes.
