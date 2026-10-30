# NURL Language Reference

**Status:** language specification, grammar v2.11. This document is the
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

```text
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
| `TT_TYPE_KW` | `i8 i16 i32 i64` | signed fixed-width integers |
| `TT_TYPE_KW` | `u16 u32 u64` | unsigned fixed-width integers (v1.8) |
| `TT_TYPE_KW` | `f32` | 32-bit float (v1.8) |
| `TT_TYPE_KW` | `v128` | 128-bit SIMD vector (v2.5, §4.1b) |
| `TT_TYPE_KW` | `v256` | 256-bit SIMD vector (v2.6, §4.1c) |
| `TT_TYPE_KW` | `v512` | 512-bit SIMD vector (v2.11, §4.1d) |
| `TT_SIMD` | `simd` | CPU-dispatch prefix on a function (v2.6, §3.3b) |
| `TT_INLINE` | `inline` | always-inline prefix on a function (v2.7, §3.3c) |
| `TT_UNSAFE` | `unsafe` | raw-memory prefix on a function (v2.8, §3.3d) |
| — | `raw` | caller-vouched prefix on a function or struct (v2.9, §3.3e) — an `IDENT` everywhere but right before a top-level `@` or `:` |
| `TT_BOOL` | `T` `F` | boolean literals |
| `TT_SIZEOF` | `Z` | sizeof operator |
| `TT_PUB` | `pub` | visibility prefix (v2.0) |
| `TT_BREAK` | `break` | leave the innermost loop (v2.4) |
| `TT_CONTINUE` | `continue` | next iteration of the innermost loop (v2.4) |

Additionally, the contextual keyword `entry` is rejected as a parameter
name (it collides with LLVM's reserved `%entry` basic-block label).

#### 2.4.2 Contextual keywords

The following words are recognised only in specific syntactic positions
and remain valid identifier characters elsewhere:

- `in` `inout` `sink` — at the start of a function parameter; control
  the parameter passing convention (§7.2). `inout` is additionally
  banned as a parameter name.
- `in` `sync` `nocapture` — at the start of a foreign (`&`) function's
  pointer or string parameter; say what the C function does with the
  argument (§7.2).

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
| `TT_OROR` / `TT_ANDAND` | `\|\|` `&&` | strict-binary logical (v1.8) |

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
| `('pub')? ('unsafe')? & "lib" @ name params → ('sink')? type` | FFI (`unsafe` = only `unsafe` code may call it, §3.3d) |
| `('pub')? (prefix)* @ name [T]? params → type { body }` | function (prefixes `simd`, `inline`, `unsafe`, `raw`; §3.3b–§3.3e) |
| `('pub')? ('raw')? : Name [T]? { fields }` | struct (`raw` seals it, §3.3e) |
| `('pub')? : \| Name { variants }` | enum |
| `('pub')? : type IDENT value` | const / global |
| `('pub')? % Name [T]? (: Super+)? { ... }` | trait (`: Super` = supertraits; body may hold `type Item` assoc-type decls) |
| `('pub')? % Trait [T]? type { methods }` | impl (body may hold `type Item Concrete` assoc-type bindings) |

There is exactly one entry point, `main`. It returns either `i` — the
value becomes the process exit code, truncated to 32 bits — or `v`, in
which case the process exits `0`. (The reference compiler's own `main`
returns `v`.)

### 3.2 `$`-imports

A `$ "path"` declaration inline-compiles the `.nu` file at `path` into
the current module. The path is tried relative to the **importing
file's** directory first, then the compiler's current working directory,
then `$NURL_STDLIB`; a path without the `.nu` suffix is retried with it
after all three miss. A package's source therefore imports a sibling as
`name.nu` — which resolves whether the package is built from its own
root or installed under a consumer's `deps/<pkg>/` — never as
`src/name.nu`, which only the package root's working directory finds
(`tools/check_package_imports.sh` refuses it).

A compilation may be **confined** to a set of directories — `nurlc
--import-root=DIR` (repeatable) or `NURL_IMPORT_ROOTS` (`:`-separated;
the flag wins). An import whose canonical path (every symlink and `..`
resolved) lies outside every root is reported exactly as a missing file,
so the diagnostic does not reveal which paths exist. Without either, any
readable file may be imported. A server that compiles untrusted source
sets the roots to its toolchain tree and the build's own directory.

The same path is imported **at most once** per compilation. Dedup keys on
the `realpath(3)`-canonical file path (falling back to the normalised path
string when `realpath` fails), so the same file reached through different
symlink chains compiles only once.

Without an alias, all top-level names from the imported file land in the
global namespace unchanged:

```nurl
$ `stdlib/core/string.nu`
```

With an alias, every top-level `@`-function, struct/enum type, enum
variant, and global `:` constant defined in the imported file is renamed
to `alias__name` by a pre-tokenisation source rewrite; internal
cross-calls inside the imported file are rewritten to match. The
renamed names are reached from the importer via `alias::name`, which
the lexer fuses into the same single identifier:

```nurl
$ `stdlib/core/mem.nu` m

unsafe @ scratch → v {
    : *u p ( m::alloc [u] 16 )    // resolves to alias-rewritten `m__alloc`
    ( nurl_free # s p )
}
```

FFI declarations (`& "lib" @ name …`) and trait/impl methods are
intentionally **not** renamed — FFI symbols resolve at the linker by
literal C-ABI name, and trait dispatch is mangled by impl-target type.

For an executable, NURL source functions have LLVM linkage names in the
reserved `__nurl_fn.` namespace. This prevents a source function such as
`open` from replacing libc's `open`; source lookup, visibility and debug
names still use the NURL name. Calls, trait methods, generated destructors
and split compilation use the same lowering rule. `pub` controls NURL
visibility and does not by itself expose a C symbol.

An explicit FFI declaration preserves its literal symbol even when a NURL
function supplies the implementation. `--keep=name` also preserves that
literal name and retains the function for callers in C. A compilation with
no `main` retains its external function names for separately linked callers;
the executable's generated C `main` entry is unchanged.

### 3.2b `__` file-private functions

A top-level function whose name begins with `__` is **file-scoped**, in
every file, with no opt-in: its definition is mangled with its source
file's id, so two files may each define `__helper` and neither collides
with — nor can shadow — the other. Resolution at a call site, in order:

1. a **local closure binding** of that name (unchanged from before);
2. the **current file's own definition** — always, even when other files
   define the same name;
3. a definition in exactly **one other file** — resolves, with an
   **obsolete** warning (once per name): cross-file use of a `__` function
   is the flat-namespace era's idiom, and the migration is to rename the
   shared helper with ONE underscore (`_name`, the shared-internal
   convention — collision-diagnosed but not scoped). This path will stop
   resolving in a future release. Nothing in the stdlib or the first-party
   tree reaches it any more; it survives only because package versions
   already published were compiled under it. A standard-library `__`
   function still resolves this way, but a call to it from a function
   that is not `unsafe` is then rejected (§3.3d): the library's internals
   take control blocks and buffers as plain values and trust them;
4. definitions in **several other files** — a compile error naming every
   owner, because there is no right answer.

The convention this encodes: `__name` is file-private (compiler-enforced),
`_name` is internal-but-shared (duplicate definitions are diagnosed with
both locations), a bare name is the public surface (gate it with `pub`
below). Pinned by `priv_file_scope.nu`, `should_warn_priv_cross_file.nu`
and `diag_priv_ambiguous.nu`.

### 3.3 `pub` visibility (grammar v2.0)

Any top-level declaration except an import may carry a leading `pub`
prefix to mark it public. Visibility is per-file and **strict-mode is
opt-in**: a source file enters strict mode the first time any of its
top-level decls carries `pub`. Files containing no `pub` decl remain in
legacy mode where every top-level name is globally callable.

In strict mode, every unmarked `@`-function is private to its source
file; a cross-file call is rejected with:

```text
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

### 3.3b `simd` CPU dispatch (grammar v2.6)

A **function** declaration may carry a leading `simd` prefix. It asks the
compiler to emit that function twice — once for the baseline ISA and once
for a wider one — and to pick between them at run time. `pub` and `simd`
may appear in either order; `simd` is accepted on `@` declarations only.

```nurl
$ `stdlib/core/vec.nu`

unsafe simd @ poly_add * i32 r * i32 a * i32 b i n → v {
    : ~ i k 0
    ~ < k n { = . r k + . a k . b k = k + k 1 }
}
pub simd @ mldsa_sign_mu i level ( Vec u ) mu → ( Vec u ) {
    ^ ( vec_clone [u] mu )    // body elided
}
```

What nurlc emits for `simd @ f`:

| symbol | what it is |
| --- | --- |
| `@f.base` | the body, baseline ISA |
| `@f.x86v3` | the same body, `"target-cpu"="x86-64-v3"` (AVX2 + BMI2 + FMA) |
| `@f` | a dispatcher: one call to `nurl_cpu_x86_v3()`, one branch |

Callers keep calling `f`. The answer is resolved once from a constructor
and cached, so the dispatcher costs a load, a test and a branch the
predictor gets right every time — which is why the binary stays runnable
on a machine without AVX2 instead of dying on an illegal instruction, the
outcome `-march=native` would produce.

**The prefix belongs on FEW, LARGE functions.** Applying it to every
function in a module measures *slower than not applying it at all* —
2× slower on the ML-DSA signing path. A dispatcher is an opaque call in
the middle of the call graph, so every small helper it fronts stops being
inlinable into its caller, and the vectorisation it buys does not come
close to paying for that. The subtree needs no marking: LLVM permits
inlining a baseline callee into a feature-richer caller (the reverse is
what it refuses), so an unmarked helper inlined into `@f.x86v3` is
compiled with the wide feature set and vectorises there. Mark the coarse
entry point; leave its callees alone.

Three consequences worth knowing:

- **A marked function is kept whole in one part.** `--split` must not
  separate the wide clone from the callees it needs inlined, which is
  most of what the prefix buys (measured: ML-DSA-65 sign 352 µs unsplit,
  509 µs with the module cut like any other). So the partition keeps the
  marked functions — each one's dispatcher, both clones and every
  function they reach — together in one part, whole, and splits the rest
  of the module as usual: that part holds the code a one-module build
  has in view when it compiles a clone, and a program that does TLS or
  post-quantum crypto builds on every core like any other. A group
  larger than an even share becomes a part of its own; one that is
  nearly the whole module leaves the module unsplit.
- **`--g` suppresses cloning.** A `!DISubprogram` may be attached to
  exactly one function, so the clones would produce invalid metadata.
  A debug build gets one copy (and is never split: `--split` cannot be
  combined with `--g`).
- **`--no-cpu-dispatch` turns the prefix off**, emitting each marked
  function once. nurlc emits no `target triple`, so it cannot tell that a
  module is bound for AArch64 or wasm; anything building for a non-x86-64
  target must say so — `--target=aarch64` (the prefix off, the crypto
  tier on the ARMv8 Cryptographic Extension, §4.1b) or this flag — and
  `nurl.sh`, the unikernel scripts and the build API all do. The prefix
  also starts off when nurlc runs natively on a non-x86-64 host (its IR
  is compiled for the host clang runs on; an AArch64 host is
  `--target=aarch64`), and `--cpu-dispatch` turns it back on for an
  x86-64 target built there; a wasm nurlc keeps the native default.
- **A marked function that uses the hardware crypto tier** (§4.1b,
  the `nurl_v128_aes*` / `nurl_v128_clmul_*`
  primitives) — or calls a function that does — cannot have a baseline
  clone: the instructions do not exist there. Its `.base` is compiled
  for the tier (x86-64-v2 + AES-NI + PCLMULQDQ) and gated on it, and its
  `.x86v3` gains `+aes,+pclmul`; the dispatcher picks the wide clone only
  when the CPU has both v3 and the tier. Which clones a marked function
  gets therefore depends on its callees, and a library function is
  compiled only once something refers to it — after its caller — so
  nurlc emits every marked function at the end of the module, when the
  set of tier functions is complete. The test is one call deep on
  purpose: a marked function that only reaches the tier through some
  ordinary function keeps its baseline clone. One that reaches a VAES
  tier (`nurl_v256_*` / `nurl_v512_*` crypto primitives) is emitted
  once, for that tier and gated on it: the tier contains x86-64-v3, so
  there is no second clone to choose. One that reaches the SHA tier
  (`nurl_v128_sha256*`) is cloned the same way for x86-64-v2 + SHA, and
  one that reaches both the AES and the SHA tier for their union, gated
  and dispatched on both.
- **A marked function with a `v256` or `v512` in its signature** takes
  it by pointer in its clones, and its dispatcher — which keeps the
  signature, spills the vectors and is `alwaysinline` — never becomes a
  call the vector crosses by value: a wide vector is one register under
  AVX and two or four without, and the two sides of a call between
  feature sets would disagree on which (§4.1b).

**Both clones are tested, not just the one this CPU picks.** A
behavioural test can only ever run the clone the dispatcher selects, so
on an AVX2 host the baseline lowering of every marked function is
compiled and never executed — and every function the prefix marks today
is cryptography (post-quantum, and ChaCha20's wide passes), where a
divergence between the two is a wrong key or a wrong ciphertext on the
machines that were never tested rather than a slow path.
`compiler/tests/simd_baseline_agree.sh` builds the vector corpus a
second time with `--no-cpu-dispatch` and requires the baseline lowering
to produce the same goldens, and it reads the marked set out of
`stdlib/` so a newly marked function with no driver fails by name.

Generic functions may not be marked: a generic is monomorphised after the
whole program is parsed, so the prefix would not survive to its
instantiations. nurlc rejects `simd` there rather than accept a prefix
that does nothing.

### 3.3c `inline` always-inline (grammar v2.7)

A **function** declaration may carry a leading `inline` prefix. nurlc puts
LLVM's `alwaysinline` on the definition, which makes the inliner skip its
cost model for that callee. `pub`, `simd` and `inline` are order-
independent, and `inline` is accepted on `@` declarations only.

<!-- doctest-prelude
: Interp { *u mem i size }
@ __lshr64 i a i n → i { ^ ? == n 0 a & >> a n - << 1 - 64 n 1 }
-->
```nurl
inline @ mem_load * Interp it i ea i n i signed → i { ^ 0 }    // body elided
pub inline @ lane i v i k → i { ^ & ( __lshr64 v * k 8 ) 255 }
```

The cost model is usually right, and a small callee gets inlined without
being asked. Ask when it is not: a helper whose arguments are *constants
at every call site* collapses to a handful of instructions once inlined,
but is scored on its whole body — and a very large caller (an interpreter
dispatch loop is the shape) pushes the decision the wrong way. In
`packages/nwasm`, `inline` on the two linear-memory accessors was 9.5 %
off the whole benchmark corpus and 24 % off its float benchmark.

It is a request the backend cannot refuse, so it is also a way to make a
program slower: an inlined body is duplicated at every call site, which
costs instruction cache, and it changes the caller's register pressure.
Measure both ways. Two rules nurlc enforces rather than leaving to LLVM:

- **not on a generic** — a generic is monomorphised after the whole
  program is parsed, and the prefix does not survive to its instantiations
  (the same reason `simd` is rejected there);
- **not together with `simd`** — `simd` replaces the function with a
  CPU-dispatching stub, which is exactly the opaque call `inline` asks to
  remove.

A directly recursive `inline` function is accepted and compiles: LLVM
inlines the non-recursive call sites and leaves the self-call alone.

### 3.3d `unsafe` — the raw-memory boundary (grammar v2.8)

A function or method declaration may carry a leading `unsafe` prefix
(order-independent with `pub`, `simd` and `inline`; in an `impl` block,
`unsafe @ name …`). Only an `unsafe` function may

- read or write through a raw pointer `*T` (`. p field`, `= . p field x`,
  `. p k`);
- cast to a pointer type (`# *T x`, `# i8* x`) — the null pointer
  `# *T 0` stays safe;
- call a function that takes or hands back a raw pointer (`*T` in a
  parameter or in the result, outside a closure type: `vec_data`,
  `slice_data`, `nurl_str_at`, a program's own `→ *T`);
- build a sealed representation field by field, write any of its fields
  or read its raw fields — a struct that declares a raw-pointer field, a
  library handle (`Slice`, `Vec`, `Box`, …), or a standard-library struct
  with its own `% Drop` (the state behind a handle — `TcpConnImpl`,
  `FileImpl`, `RawBlock`, … — whose destructor hands its fields to raw
  code). Handing a handle field of one (`. key d`, at any depth of a
  field chain, or a binding read out of such a field) to a callee that
  may change it in place — a container mutator, or a function whose
  summary changes or takes that argument (for one defined later, its
  final summary) — is a write to that field;
- call a raw-memory primitive (`nurl_alloc`, `nurl_free`, `nurl_realloc`,
  `nurl_peek*` / `nurl_poke*`, `nurl_memcpy`, …), an ownership primitive
  that gives a value up or claims it by hand (`mem_forget`, `mem_take`,
  `mem_put_back`, `vec_put_back`), an `rcbox` primitive (`rcbox_new`, `rcbox_zero`,
  `rcbox_share`, `rcbox_release`, `rcbox_ptr`), an `Arc` held as a
  plain word (`arc_into_word`, `arc_from_word`, `arc_word_share`), an
  `Arc`'s payload replaced in place (`arc_set`: the payload is frozen
  once made, docs/MEMORY.md §6.5) or a C
  primitive that reads or writes as far as its caller says, takes a
  `FILE*` or a format string (`memmem`, `fwrite`, `fopen`, `printf`, …:
  the builtins marked raw in `stdlib/core/builtins.nu`);
- call a standard-library function whose name begins with `__` (the
  library's own machinery, which trusts the control blocks and buffers
  it is handed), or one declared `raw` (§3.3e). Every other library
  function is safe for every argument a program can pass — a short or
  empty buffer, a negative or huge offset, a count whose sum with an
  offset wraps — so a helper shared between library files that needs
  its operands sized or its offsets checked by the caller (x25519.nu's
  field limbs, the recycling stash) is `raw`, and a struct whose fields
  carry such an invariant is a `raw` struct;
- call a foreign (`&`) function declared outside the standard library;
- pass a runtime handle as a plain integer: a standard-library function
  or foreign function that takes the address of the runtime's own record
  for a socket, a process or a stream as an `i` (`tcp_conn_view`,
  `tcp_conn_adopt`, `tls_attach*`, `tls_accept*`, the `nurl_tcp_*`,
  `nurl_udp_*`, `nurl_proc_*` builtins, the library's raw symbol table
  `nurl_sym_*`) — a number that is not a live handle is memory the program
  does not own. The library declares such a
  foreign function `unsafe & …`; a program reaches the same operations
  through the handle types (`TcpConn`, `UdpSocket`, `ProcChild`, and
  `tcp_starttls`, `tls_accept_conn` for a TLS upgrade);
- pass a C stream as a string: `file_raw` hands a `File`'s `FILE*` out as
  an `s`, and `file_from_raw` takes any `s` as one and closes it when the
  `File` goes (a program opens a `File` and asks `file_is_open`);
- touch a device by physical address: the unikernel HAL's `mmio_*` and
  `virtio_*` / `virtq_*` functions take a device or ring address as an
  `i`, and any number reaches any memory through them; a driver marks the
  functions that do it `unsafe`;
- read or write a mutable global that owns something, or one of a struct
  or an option, which no atomic covers (§3.4); hand a mutable `s` global a
  string to own (in safe code it holds literals, and text that changes at
  run time lives in a `( Locked String )` set at start); or take a
  global's address with `mem_addr`.

A string (`s`) in safe code is therefore NUL-terminated or null: nothing
safe can turn a raw pointer into one. A null string reads as the empty
string at every string primitive (`nurl_println`, `strlen`,
`string_from`, …). A raw string held by a struct, an option, an enum, a
slice or a container is a view: a fresh one is stored as a `String`, or
bound first and stored as a view of the binding (docs/MEMORY.md §2.13).

```nurl
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

// The rest of the program sees a safe function: it takes a String and
// returns an owned Vec, and nothing raw escapes.
unsafe @ bytes_of String s → ( Vec u8 ) {
    : ( Vec u8 ) out ( vec_with_cap [u8] ( string_len s ) )
    : *u8 p # *u8 ( string_data s )
    : ~ i k 0
    ~ < k ( string_len s ) { ( vec_push [u8] out . p k ) = k + k 1 }
    ^ out
}
```

`unsafe` is a promise the compiler cannot check: the function's author
vouches that its body is memory-safe and leak-free for every caller, the
way the standard library vouches for its own raw code. Calling an
`unsafe` function needs no marking. The rest of the program is held to
the ownership rules (docs/MEMORY.md §6), and **every program accepted
without an `unsafe` function of its own is memory-safe and leak-free**
(docs/MEMORY.md §6.2 — the ownership rules of the single-threaded
language, `A2.memory_safe` and `A2.no_leak_end`, are mechanically proven
sound in Lean 4 under `formal/`, and every hole found so far,
`h01–h940`, is closed and held by a probe in `tools/fuzz/holes/`).

The same word marks the one assertion about a type the compiler takes on
trust (grammar v2.11). `% Send T { }` and `% Sync T { }` stop the
thread-safety derivation at `T` — nothing inside it is examined — so
outside the standard library they are written `unsafe % Send T { }` /
`unsafe % Sync T { }`; without the prefix they are an error. The markers
that only add checks (`% NotSend`, `% NotSync`, `% Frozen`) and
`% Resource` are ordinary safe code (docs/MEMORY.md §3).

`nurlc --unsafe-report` lists what a program asks to be trusted outside
the standard library — its `unsafe` functions, its `unsafe % Send` /
`unsafe % Sync` assertions and the `in` / `sync` / `nocapture` claims of
its foreign declarations (§7.2), one `file:line` each — the whole
surface a reviewer has to trust.

Ordinary code never needs it: `String`, `Vec`, `HashMap`, `Box` / `Rc` /
`Arc`, channels and structs of them release themselves. `unsafe` is for
the exceptional case — a binding to a C library, a hand-laid-out buffer
handed to a GPU, a data structure whose invariant the rules cannot see.

### 3.3e `raw` — a contract the caller keeps (grammar v2.9)

An `unsafe` function promises that it is safe for every caller. Some
functions cannot promise that: what makes the call sound is something
only the caller knows — that an address is live device memory, that a
count fits the buffer behind a pointer, that kernel source it compiles
and runs is sound. Such a function is declared `raw`:

```nurl
$ `stdlib/core/vec.nu`

// requires: n <= vec_len v
raw @ sum_first ( Vec i ) v i n → i {
    : *i p ( vec_data [i] v )
    : ~ i s 0
    : ~ i k 0
    ~ < k n { = s + s . p k = k + k 1 }
    ^ s
}
```

Its body may use raw memory, as an `unsafe` one's may, and only an
`unsafe` (or `raw`) function may call it — the caller is the one that
vouches. That is the rule a foreign function already follows when the
standard library declares it `unsafe & …`; `raw @` gives it to a NURL
function. The place a contract is established — the function that
allocated the buffer, checked the sizes, wrote the kernel — is then the
`unsafe` one, and everything above it stays safe.

`raw` before a struct seals it: `raw : DevBuf { i addr i n }` says that
the fields carry an invariant the code managing them relies on (here,
that `addr` holds `n` elements), so a literal of it and a write to one of
its fields are raw memory, as they are for a struct with a raw-pointer
field. Reading a plain field is not.

`raw` is not a reserved word: it is the prefix only right before a
top-level `@` or `:`, and anywhere else it is an ordinary identifier (a
field, a binding, a constant). An import's alias is never a `raw` that
an `@` or a `:` follows. It is refused on an `impl` method — a trait method can be
called through a `dyn` value, where no caller can be checked — and on a
const, an enum and a generic struct.

### 3.4 Constants and globals

A `: type IDENT value` declaration at top level binds a constant (or, with
`: ~`, a mutable global). The `value` is normally a single literal.

An **integer-typed** const (`i` / `u` / a sized integer, not `b`) may
instead take a **compile-time-foldable prefix expression** over integer
literals, using the operators `+ - * / << >> & | ^^` (not `%`, which
collides with the trait/impl sigil). The expression is folded to a single
value at compile time (`const_eval_int`):

```nurl
: i SECS_PER_DAY * * 60 60 24            // 86400
: i PAGE        << 1 12                  // 4096
: i INT_MIN     - -9223372036854775807 1 // two's-complement min
```

A mutable global (`: ~ type Name value`) may be reassigned at runtime
with `= Name expr` (§5.2). Every thread can reach it, so how it is read
and written depends on its type:

- A **scalar** global — an integer, a bool, a float, a `s` or another
  pointer — is read and written with relaxed (monotonic) atomic
  accesses. Threads that race on it see whole values, never torn ones;
  nothing else is ordered by it (use a `Mutex`, a `Channel` or a
  `( Locked T )` for that). On x86-64 and AArch64 these are the same load
  and store instructions as plain ones.
- A `s` global holds **literals** in safe code: an assignment that would
  hand it a string to own (`= g ( nurl_str_cat a b )`) is rejected,
  because the next assignment frees what it owns while another thread may
  be reading it. Text that changes at run time belongs in a
  `( Locked String )` global set at start (below).
- A global of a **struct or an option** of plain values is more than one
  word, which no atomic covers: only an `unsafe` function (§3.3d) reads or
  writes it, as for a global that owns something.

A mutable global may also have a type that owns something — a `String`, a
`Vec`, a struct of them, an option `?T`, a closure, a library handle — with
the initialiser `0`. It starts as that type's zero value (which drops as
nothing) and owns what it holds: an assignment to it or to one of its
fields drops what it replaces, and a read borrows (docs/MEMORY.md §1,
Module globals). Every thread can reach it, so only an `unsafe` function
(§3.3d) reads or writes it.

<!-- doctest-prelude
: Model { ( Vec f ) weights }
-->
```nurl
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: ~ ( Vec String ) g_names 0
: ~ ?Model g_model 0          // F until a model is loaded
unsafe @ model_drop → v { = g_model @ ?Model { F } }
```

A global **set at start** holds program-wide state that safe code reads
from any thread. Its initialiser is a function of no arguments in
parentheses, run once before `main` (and before any thread exists); its
type must synchronise itself — `( Locked T )`, `( Arc T )`,
`( Channel T )`, `Mutex`, `Cond` or `Semaphore` — and nothing assigns it
afterwards. A read borrows the handle; binding it, storing it or returning
it clones the handle, so the global itself is never moved or dropped.

<!-- doctest-prelude
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
: Registry { ( Vec String ) names }
@ registry_new → Registry { ^ @ Registry { ( vec_new [String] ) } }
@ registry_add inout Registry r s name → v { ( vec_push [String] . r names ( string_from name ) ) }
-->
```nurl
$ `stdlib/std/thread.nu`

@ make_registry → ( Locked Registry ) { ^ ( locked_new [Registry] ( registry_new ) ) }
: ( Locked Registry ) g_registry ( make_registry )

@ register s name → v {            // safe: the Locked holds the lock
    : ~ Registry r ( locked_take [Registry] g_registry )
    ( registry_add r name )
    ( locked_restore [Registry] g_registry r )
}
```

`( mem_addr g )` (`unsafe`) is a `*T` to the mutable global `g` of type
`T` — a struct global's fields reached through a pointer, or an address a
foreign function or an atomic operation writes through. Given an `inout`
parameter it is the caller's place, valid for the call.

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
| `i8` `i16` `i32` `i64` | `i8` `i16` `i32` `i64` | signed sized integers |
| `u16` `u32` `u64` | `i16` `i32` `i64` | unsigned sized integers (v1.8) |
| `f32` | `float` | 32-bit float (v1.8) |
| `v128` | `<4 x i32>` | 128-bit SIMD vector (v2.5) — see §4.1b |
| `v256` | `<4 x i64>` | 256-bit SIMD vector (v2.6) — see §4.1c |
| `v512` | `<8 x i64>` | 512-bit SIMD vector (v2.11) — see §4.1d |

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

More generally, the call-site argument check rejects the silent-coercion
classes for calls to non-generic functions: a pointer-vs-value mismatch
(`*T` where a `T` value is declared, or vice versa), the `String`/`s`
confusion above, **passing one named struct value where a different
named struct is declared** (`%A` vs `%B` by value — clang would otherwise
coerce the call and reinterpret the foreign struct's leading fields),
and **a closure whose signature differs from the declared `(@ …)`
parameter type** (the callee invokes it with the declared signature, so
every argument would be a reinterpreted bit pattern).

**Scalar arguments follow the binding law at every call boundary** —
positional, named (`name:` kwargs, including spliced default values),
FFI, and generic instantiations (checked after tparam substitution):

- integer **widths coerce** (a bare literal is `i64`, so a `u8`
  parameter accepts `( f 3 )`; `trunc`/`sext`/`zext` are emitted so the
  call signature matches the callee — an `i1` always zero-extends,
  `T` is `1`, never `-1`);
- **float widths coerce** (`f32` ↔ `f` via `fpext`/`fptrunc`);
- **float ↔ integer never coerces** — rejected in both directions.
  Emitting the call anyway would be textually valid IR under opaque
  pointers (a call carries its own function type), so clang assembles
  it and the callee reads an unrelated register: garbage, not a crash;
- a **bool widens** into an integer parameter (lossless), but a wider
  integer into a `b` parameter is **rejected** — the truncation would
  keep only the low bit (`2` becomes `F`), and a parameter is a
  contract, like a return type;
- an **`inout` argument must match the declared parameter type
  exactly** — it is passed by address, so no register coercion is
  possible and a width/float clash would make the callee write its own
  type's bytes into the caller's differently-typed slot.

The same never-legal clashes are rejected at the other type boundaries:
returning the wrong type from a function (`^ b` of type `B` from a `→ A`
function — the float/pointer/struct dual of the argument check; float
*widths* must also match exactly at a return, like integer widths),
**struct-literal fields** — `@ A { 3.5 }` into an `i` field, a pointer
value into a scalar field, or more field values than the struct declares
— and **slice-literal elements** (`[ i | 1 2.5 ]` is rejected; widths
coerce, float↔int and pointer↔scalar never do). Omitting trailing
struct-literal fields stays legal (they zero-initialise) when zero is a
value of the field's type — a number, a flag, an option (`F`), a raw
string or pointer (null), or a struct, array or enum of those. A
`String`, a `Vec`, a library handle (`Rc`, `Arc`, `HashMap`, a module's
own handle) or a closure has no zero value — it needs its control
block, its shared block or its code — so outside `unsafe` such a field
(or a struct holding one) must be given. The same holds for an enum
literal's payloads, for the value an option or result literal's tag
names (`@ ?( Vec i ) { T }` gives none), for a bare variant used as a
value (its payloads must be plain numbers or flags), for the
zero-filling constructors (`vec_zeroed`, `vec_resize_zeroed`,
`box_zero`, `rc_zero`, `arc_zero`), and for a number used where a
`String`, a `Vec` or a library handle is expected (`: ( Vec i ) v 0`, a
`0` argument): none of them makes one outside `unsafe`. Integer
width / signedness narrowing into sized or unsigned fields is a legal
coercion. An integer never converts into a pointer type implicitly —
not into a field, a binding, an assignment, or a return value; the
explicit cast `# *T expr` converts intentionally, and `# *T 0` is the
null pointer.

Those classes are the *named* ones, not the boundary's definition. Since
0.58.0 every value boundary — return, and every argument path — ends
with a **total-agreement backstop**: after the sanctioned coercions
above (integer and float widths, the enum wrap, the FFI NULL/handle
`inttoptr` bridge), the value's lowered LLVM type must **equal** the
declared one, pointer-beside-pointer excepted, since opaque pointers
are one LLVM type. A pair that matches no branch is a diagnostic, not a
hole. This matters because the bad instruction *assembles*:
`ret { i1, i64 } %o` out of an `i64` function, or
`call i64 @f({ i1, i64 } %v)` against `declare i64 @f(i64)`, are both
accepted by clang — a call carries its own signature — and the callee
reads whichever bytes the ABI left in the register. Garbage, not a
crash. The backstop covers the aggregate-shaped types the pairwise
list never named (option, result, slice and closure values beside
scalars, pointers and named structs), a `void` expression used as an
argument, and an FFI pointer passed where an integer parameter is
declared (a silent `ptrtoint` of the string's *address*; write `# i x`
to mean it, while `( free 0 )` and handle-to-pointer stay legal). It
runs on **every** call path, not only direct calls to non-generic
functions: generic instantiations, trait-method dispatch, closure and
fn-pointer invocations, and `%Trait` dynamic dispatch each check their
assembled arguments against the callee's declared roster. A closure
returned where its own *result* type is declared is the `^ f( r )`
C-style-call typo, and the diagnostic names the parenthesised prefix
form to write instead.

A **condition** (`?` / `~`) must be `b` or an integer (tested non-zero).
A float, pointer/string, enum, or aggregate condition is rejected with
the comparison to write instead — none of them has a truth value.
Likewise `# b` of a float is rejected (an `i1` holds
only 0 or 1, so the conversion is poison for any other value — write
the comparison).

### 4.1b `v128` — the SIMD lane type (v2.5)

`v128` is one 128-bit vector register. It behaves like any other
by-value scalar type — a `:` binding holds one, a parameter passes one
in a vector register, `^` returns one, and it owns nothing, so auto-drop
never touches it — but it has no operators. Every operation on it is a
`nurl_v128_*` primitive, because `+` on a vector must say *which lane
width* it adds and an operator cannot; the primitive names do.

128 bits, and not 256, because that width is **baseline** on every
64-bit target NURL supports: SSE2 is part of the x86-64 ABI and NEON
part of AArch64. A `v128` kernel therefore needs no CPUID probe, no
target-feature attribute and no scalar fallback path — it is correct
everywhere, and fast wherever it lands in vector registers. On wasm
that takes a module built with `simd128` (`-msimd128`), which the
toolchain's wasm pipeline (wasmbuilder, `/build_wasm`) does not enable
by default; a wasm32 module without it, like a target with no vector
unit at all, runs the kernel as a scalarised loop.

A kernel that only pays off in registers asks first.
`nurl_simd128_native()`, a C runtime function (declared with `&` where
it is used), returns 0 on a wasm32 build without `simd128`, where the
`v128` is scalarised, and 1 everywhere else; the wasm pipeline's IR
rewrite folds the call to 0, so the kernel it guards drops out of the
module. ChaCha20's four-blocks-a-lane kernel is that case: sixteen
vectors live, sixty-four scalars once scalarised.

One type carries every lane width. A register does not have a lane
width, an *instruction* does; `<4 x i32>` is only the carrier, and each
primitive bitcasts to the lanes it operates on (a bitcast between
same-width vector types is a relabelling and generates no code).

The primitives, all defined in the compiler's preamble as
`linkonce_odr alwaysinline` so each is one machine instruction at the
call site:

| Group | Primitives |
|---|---|
| load / store | `nurl_v128_ld(*u) → v128`, `nurl_v128_st(*u, v128)` — unaligned |
| partial load / store | `nurl_v128_ldn(*u, n) → v128` — the first `n` bytes (0–16), zero-padded; `nurl_v128_stn(*u, n, v128)` — the first `n` bytes of the vector. Neither touches a byte past `n` (two overlapping 8-, 4- or 1-byte accesses, no loop, no `memcpy` call) — a message's short last block |
| construct | `nurl_v128_zero`, `_set32(a b c d)`, `_set64(a b)`, `_bcast32(x)`, `_bcast8(x)` |
| extract | `nurl_v128_get32(v, i) → u64`, `_get64(v, i) → u64` |
| bitwise | `nurl_v128_xor`, `_and`, `_or`, `_andnot` |
| lane arithmetic | `nurl_v128_add8`, `_add32`, `_sub32`, `_add64`, `_mul32u` |
| shift / rotate | `nurl_v128_rotl32(v, n)`, `_shl64(v, n)`, `_shr64(v, n)` |
| lane permute | `nurl_v128_rotlanes1/2/3(v)`; `nurl_v128_alignr4(hi, lo)` = (lo₁, lo₂, lo₃, hi₀) — the pair shifted down one lane (`palignr` by 4) |
| lane interleave | `nurl_v128_unpacklo32(a, b)`, `_unpackhi32`, `_unpacklo64`, `_unpackhi64` — zip the low or high halves of two vectors at 32- or 64-bit granularity; four of them transpose a 4×4 block of 32-bit words |
| byte compare | `nurl_v128_eqmask8(a, b) → u64`, `_ltmask8(a, b) → u64` — 16-bit bitmask |
| case folding | `nurl_v128_lower8(v)` — ASCII `A`–`Z` only |
| byte order | `nurl_v128_bswap128(v)` — reverse the sixteen bytes (GHASH's and every big-endian counter's block order); `nurl_v128_bswap32(v)` — reverse each lane's four (SHA-2's big-endian words) |

Lane indices are masked into range and shift counts are masked to the
lane width, so no primitive has undefined behaviour on an input the
language cannot reject at compile time.

`_eqmask8` is the primitive that makes a vector byte scan possible:
sixteen comparisons in one instruction, read out as a 16-bit integer
whose bit *k* answers for byte *k*. Paired with `nurl_ctz` it finds the
first match with one branch per sixteen bytes. `stdlib/std/simd.nu`
builds the scanners the rest of the stdlib uses on exactly that pattern
(`simd_index_byte`, `simd_index_crlf`, `simd_index_head_end`,
`simd_index_ows_end`, `simd_bytes_eq`, `simd_bytes_eq_ci`,
`simd_xor_into`).

**The hardware crypto tier** — AES rounds and carry-less
multiplication, the instructions every fast AES-GCM is built from and
the ones no shift tree stands in for:

| Primitive | Value (Intel's semantics) |
|---|---|
| `nurl_v128_aesenc(a, k)` | one AES round: MixColumns(SubBytes(ShiftRows(a))) ^ k |
| `nurl_v128_aesenclast(a, k)` | the last round, without MixColumns |
| `nurl_v128_aesdec(a, k)`, `_aesdeclast(a, k)` | the equivalent inverse rounds |
| `nurl_v128_aesimc(a)` | InvMixColumns — encryption round keys into decryption ones |
| `nurl_v128_clmul_ll/_hl/_lh/_hh(a, b)` | 128-bit carry-less product of a's low or high 64 bits and b's (PCLMULQDQ's immediate, spelled as four primitives because an instruction immediate must be a literal) |
| `nurl_cpu_has_aes() → b` | does this CPU have the tier |

Unlike the rest of the `v128` layer these are not baseline anywhere:
an x86-64 CPU without AES-NI is still a legal target. So they come
with a contract nurlc enforces rather than one the program has to keep:

- A function whose body uses one is compiled for the **crypto tier** —
  x86-64-v2 plus AES-NI and PCLMULQDQ — and its entry is **gated** on
  the runtime's CPUID answer: on a CPU without the tier the call panics
  (recoverably, like any panic) before the first AES instruction could
  raise SIGILL. The gate is a `readnone` call and a branch; in a helper
  inlined into a loop the optimiser merges every copy and hoists it.
- A tier function is never `alwaysinline` — LLVM would inline it into a
  caller compiled without the tier. A v128 signature or `inline @`
  becomes `inlinehint`, and such a function also gets an ungated
  `alwaysinline` copy (`@f.tier`, `linkonce_odr`) that every tier
  function's own calls are pointed at: inside the tier helpers inline
  unconditionally, outside it a call stays a gated call.
- A `simd @` function that uses a tier primitive, or calls a function
  that does, has its clones built for the tier (§3.3b).
- A program chooses its path **before** calling into the tier:
  `nurl_cpu_has_aes()` is the question, and a function that uses a
  primitive requires the tier however it is reached. A function that
  only *calls* a tier function stays baseline (the tier does not
  propagate up the call graph), so `? ( nurl_cpu_has_aes ) { hw } { sw }`
  in ordinary code is the shape a software fallback takes.
- **On AArch64** (`--target=aarch64`, and the default of a nurlc running
  on an AArch64 host) the same primitives lower to the ARMv8
  Cryptographic Extension: the tier is `+aes` (AESE / AESD / AESMC /
  AESIMC and PMULL / PMULL2), asked of the OS (`getauxval` HWCAP_AES and
  HWCAP_PMULL on Linux, `hw.optional.arm.FEAT_AES` on macOS — every
  Apple Silicon and Graviton CPU has it) or of `ID_AA64ISAR0_EL1` on a
  freestanding target. ARM splits a round differently from Intel — AESE
  is the key XOR then SubBytes and ShiftRows, AESMC the MixColumns — so
  `aesenc a k` is `AESMC(AESE(a, 0)) ^ k`, `aesenclast` drops the AESMC,
  and the inverse rounds are AESD / AESIMC the same way; inlined into a
  chain of rounds each `^ k` folds into the next AESE's key, which is
  the native ARM sequence. There are no `simd` clones on AArch64; a
  `simd @` function that reaches the tier is emitted once, for it. The
  wide tiers are x86-only: their primitives are stubs there and
  `nurl_cpu_has_vaes` is false.
- Under `--no-cpu-dispatch` (any other target: RISC-V, wasm, a
  freestanding build that names none) there is no tier:
  `nurl_cpu_has_aes` is a constant false and each primitive is a stub
  that panics if reached anyway.

**Two wider tiers** hold the same operations on the wider lane types,
every 128-bit lane an independent block — VAES and VPCLMULQDQ, which
Ice Lake / Zen 3 and later CPUs have:

| Tier | Primitives | Feature set | Question |
|---|---|---|---|
| AES (1) | `nurl_v128_aes*`, `nurl_v128_clmul_*` | x86-64-v2 + AES-NI + PCLMULQDQ | `nurl_cpu_has_aes()` |
| VAES (2) | `nurl_v256_aesenc`, `_aesenclast`, `_aesdec`, `_aesdeclast`, `nurl_v256_clmul_ll/_hl/_lh/_hh` | x86-64-v3 + AES + PCLMUL + VAES + VPCLMULQDQ | `nurl_cpu_has_vaes()` |
| AVX-512 VAES (3) | the same as `nurl_v512_*` (§4.1d) | x86-64-v4 + the VAES tier's | `nurl_cpu_has_vaes512()` |
| SHA | `nurl_v128_sha256rnds2(cdgh, abef, wk)`, `_sha256msg1(a, b)`, `_sha256msg2(a, b)` | x86-64-v2 + SHA | `nurl_cpu_has_sha()` |
| IFMA | `nurl_v256_madd52lo(acc, a, b)`, `_madd52hi(acc, a, b)` | x86-64-v4 + AVX-512 IFMA | `nurl_cpu_has_ifma()` |

`clmul_XY` picks the halves within each lane, as the `v128` form does
within its one; there is no wide `aesimc` (the instruction has none —
run the key schedule's InvMixColumns on `v128`). Each tier contains the
ones before it, and the contract above holds tier by tier: a function
is compiled for the highest tier whose primitive it uses and gated on
it; a tier helper's `.tier` copy is what code of that tier or a higher
one calls (never a lower one, which would put the instruction in a
function compiled without it); a `simd @` function that reaches a VAES
tier is emitted once, for that tier — it contains x86-64-v3, so there
is no clone left to choose between. `NURL_CPU_VAES=0` and
`NURL_CPU_VAES512=0` take a tier away at run time, as `NURL_CPU_AES=0`
does.

**The SHA tier** is the x86 SHA extensions, with Intel's semantics:
`sha256rnds2(cdgh, abef, wk)` runs two SHA-256 rounds on the state
halves (A, B, E, F) and (C, D, G, H) — each vector's lanes 3…0 in that
order — with the two rounds' W + K in lanes 0 and 1 of `wk`, and returns
the new (A, B, E, F), the old one becoming the next call's (C, D, G, H);
`sha256msg1` and `sha256msg2` are the σ0 and σ1 halves of the message
schedule for four words. It is **not** on the AES chain — Haswell to
Cascade Lake have AES-NI without SHA, Goldmont SHA without AVX2 — so
nurlc keeps a tier as the set of extensions it needs: a function is
compiled for the union of the tiers whose primitives it uses, its
inline helpers' `.tier` copies are called only where their set is
contained, and a `simd @` function that reaches both AES and SHA is
cloned, gated and dispatched on both. `NURL_CPU_SHA=0` takes the tier
away. On AArch64 and under `--no-cpu-dispatch` `nurl_cpu_has_sha` is a
constant false and the primitives are stubs (ARMv8's SHA2 instructions
divide the rounds differently and are not lowered yet).
`stdlib/std/hash_sha256.nu` runs SHA-224/256 on it where the CPU has it
(Goldmont, Ice Lake and later Intel, every Zen): about 7× the portable
rounds.

**The IFMA tier** is AVX-512 IFMA on a ymm register (with AVX-512VL):
`nurl_v256_madd52lo(acc, a, b)` adds to each 64-bit lane of `acc` the
low 52 bits of the 104-bit product of the low 52 bits of `a`'s and
`b`'s lanes, `madd52hi` the 52 bits above them (VPMADD52LUQ /
VPMADD52HUQ). A number held as 52-bit limbs in 64-bit lanes takes four
limb products per instruction and keeps every carry in its lane's top
12 bits until one normalising pass — a multi-precision multiply with no
carry chain. Like SHA it is on no chain with the AES tiers (Cannon Lake
has IFMA without VAES); it needs x86-64-v4, so a `simd @` function that
reaches it is emitted once, for it, as for the VAES tiers.
`NURL_CPU_IFMA=0` takes it away; on AArch64 and under
`--no-cpu-dispatch` `nurl_cpu_has_ifma` is a constant false and the
primitives are stubs. `stdlib/std/rsa_mont.nu` runs the two
exponentiations of an RSA-2048 CRT signature on it at once, 20 limbs
each in five registers (an almost Montgomery multiply, radix 2^52):
0.65 → ~0.27 ms a signature on an i7-11850H, within 1.2× of aws-lc's
AVX-512 kernel (~0.23 ms). The decision is `docs/adr/0002-ifma-rsa.md`.

A `simd @` function reaches a tier through what it calls ONE call deep:
a function whose body uses the tier's primitives. An `inline` function
is not a call in that sense — it becomes part of the body — so one that
reaches a tier through other inline functions (a kernel written as
helpers of helpers) counts as the body's own: the whole chain is
compiled into the one tier body, its helpers' `.tier` copies inlined
ungated. An ordinary function between them still ends the reach, so a
software path that asks `nurl_cpu_has_*` before calling the hardware
one keeps its baseline clone.

**A wide vector crosses a call by pointer when the two sides' features
differ.** A `v256` travels in one ymm register where a function is
compiled with AVX and in two xmm registers where it is not (a `v512`:
one zmm, two ymm or four xmm), and LLVM does not reconcile a caller and
a callee that disagree — the callee reads half a vector. An ordinary
function with a vector signature is `alwaysinline`, so no call is left
to disagree; the functions that must stay out of line under features of
their own — a `simd` function's clones, a tier function called from
outside its tier — take their wide vectors through memory instead: the
body is emitted under `f.vabi` with each wide parameter as a pointer
(and a wide result written through a leading one), and `f` itself
keeps the language signature, has no features and is `alwaysinline`,
so it inlines into every caller and spills the vectors to the caller's
frame. A `simd` dispatcher with a wide signature does the same. A
struct holding a wide vector counts as one (an aggregate is passed
element by element), and so does an ordinary function taking one, which
is `alwaysinline` like any vector signature. An *indirect* call — a
closure, a trait-object method — cannot be given a pointer form both
sides know, so one carrying a wide vector is made from a featureless
`noinline` thunk per signature (`__nurl_vcall.N`) that takes the wide
arguments by pointer: every function whose address is taken is compiled
without features, and the thunk calls it under the same ones. The cost
is a store and a load per vector per call, on calls that are
coarse-grained by construction. (A `v128` needs none of this: it is one
xmm register under every x86-64 feature set.)

`stdlib/std/aes_gcm.nu` is written on them: AES-128/256-GCM at ~3 GB/s
on a 2014 Haswell (eight-block CTR stitched with the previous batch's
GHASH, reflected-domain Montgomery reduction), against ~113 MB/s for
the bitsliced software cipher it keeps for CPUs without the tier — and
on par with the same algorithm written in C intrinsics and compiled by
the same clang. Where the CPU has a VAES tier a message of 256 bytes or
more runs a sixteen-block kernel on ymm (two blocks a register) or zmm
(four): ~0.25 and ~0.19 reference cycles a byte on a Sapphire Rapids,
against ~0.42 for the eight-block kernel there and ~0.16 for OpenSSL's
AVX-512 assembly.

**Scalar bit primitives** ship alongside, for the operations every ISA
has an instruction for and the language previously had to spell as a
loop or a shift tree: `nurl_ctz`, `nurl_clz`, `nurl_popcnt`,
`nurl_bswap32`, `nurl_bswap64`, `nurl_rotl32`, `nurl_rotr32`,
`nurl_rotl64`, `nurl_rotr64`. `ctz`/`clz` are defined at zero (they
return 64) rather than poison.

**Wide arithmetic** completes the same story for integers wider than
the language can spell. `nurl_umulhi(a, b)` gives the high half of a
product, and `nurl_smulhi(a, b)` the high half of the signed product
(one `imul`; with `*` it is a signed 128-bit result); these give the
high half of a sum and of a multiply-accumulate:

| Primitive | Value |
|---|---|
| `nurl_addc_lo/_hi(a, b, c)` | `a + b + c`, low 64 bits / carry-out |
| `nurl_subb_lo/_hi(a, b, c)` | `a − b − c`, low 64 bits / borrow-out |
| `nurl_mac_lo/_hi(a, b, c, d)` | `a·b + c + d`, low / high 64 bits |

`c` and `d` are the previous step's `_hi` (0 or 1 for addc/subb).
`nurl_mac` cannot overflow 128 bits for any 64-bit inputs, which is why
it is one primitive and not three: it is exactly one limb step of a
schoolbook or Montgomery multiply.

The language can already *spell* a carry — the unsigned wrap of `x+y`
is `x+y < x` — so these exist for the shape the **backend** recognises,
not for expressiveness. A hand-written wrap test lowers to a compare, a
zero-extend and a separate add; chained across four limbs that is an
add/cmp/setb/add tree, serialised through the ALU, and the multiplies
feeding it cannot become a flag-free widening multiply because the tree
is reading the flags. Written through these primitives the same four
limbs legalise to `add; adc; adc; adc; setb`. (`nurl_subb` goes through
`llvm.x86.subborrow.64` on x86-64: LLVM rewrites the generic borrow test
into a shape it no longer chains, and a four-word subtract came out as
setcc logic — the intrinsic is the `sub; sbb` chain itself.)

Two functions rather than one returning a pair, because a NURL function
returns one value and a pointer out-param would put the sum in memory —
the one place a carry chain must not go. Both halves are `alwaysinline`
over identical operands, so the shared computation is CSEd and the pair
costs one instruction. **That CSE is a contract on the caller**: load
limbs into bindings *first* and chain over those. Called on `. p k`
operands straight out of memory, the two halves reload through a
possibly-aliasing pointer, the CSE cannot happen, and the chain
collapses back to the tree it was meant to replace.

**A row with two carry chains.** x86 has one carry flag, so a chain of
`nurl_mac` steps is one serial chain however it is written — and LLVM,
given `mulx` and the `adcx` intrinsic, still emits plain `adc`; it never
selects `adox`. ADX (Broadwell, Zen) has two add-with-carry instructions
that carry through flags of their own, ADCX through CF and ADOX through
OF, which with BMI2's flag-free MULX run a multiply's low and high
halves as two chains at once. Flags do not survive between two pieces of
code the compiler may separate, so the unit is a whole row:

| Primitive | Value |
|---|---|
| `nurl_mac_row(rp, ap, n, b)` | `rp[0..n) += ap[0..n)·b`; returns the word above them |
| `nurl_p256_mulm(r, a, b)` / `nurl_p256_sqrm(r, a)` | P-256 Montgomery multiply / square of four-word operands; T when a kernel ran (ADX or mulq on x86-64), F elsewhere — the caller runs its portable form |
| `nurl_x25519_mulm(r, a, b)` / `nurl_x25519_sqrm(r, a)` | GF(2^255 − 19) multiply / square, lazily reduced; T on the ADX tier, F elsewhere |
| `nurl_cpu_has_adx()` | the ADX tier: BMI2 + ADX |

`rp` and `ap` are `*i` limb pointers, so only `unsafe` code may call
it. The result always fits n + 1 words, so the top word is returned
rather than added anywhere. On x86-64 the row asks `nurl_cpu_has_adx`
and runs inline asm (mulx / adcx / adox, loop control by `lea` and
`jrcxz`, which write no flag); elsewhere — a CPU without ADX, AArch64
(one carry flag, no ADOX equivalent), `--no-cpu-dispatch` — it is a
loop of `nurl_mac` steps. Every branch depends on `n` alone. There is no
gate: unlike the crypto tiers the row runs everywhere, and
`NURL_CPU_ADX=0` takes the asm away. `stdlib/std/rsa_mont.nu`'s
Montgomery multiply and square run on rows on the ADX tier (1.2–1.65×
over its FIPS kernels) and stay FIPS without it. The decision is
`docs/adr/0001-two-carry-chains.md`.

### 4.1c `v256` — the wide SIMD lane type (v2.6)

`v256` is the same idea one register wider, and follows every rule
§4.1b states: by-value, opaque to the operators, every operation a
`nurl_v256_*` primitive.

It is carried as `<4 x i64>` rather than `<16 x i16>` because the
kernels that need 256 bits at all need 64-bit lanes — four independent
Keccak states advanced in lockstep, which is how every production
ML-KEM / ML-DSA / SLH-DSA implementation generates its matrix, its
noise and its WOTS+ chains. As with `v128`, the carrier is not the lane
width: each primitive bitcasts to the lanes it operates on.

**Unlike `v128`, 256 bits is baseline nowhere**, and that is the point
rather than a problem. A `v256` kernel is *correct* on any target,
because LLVM legalises `<4 x i64>` into whatever the machine has — two
SSE2 registers on baseline x86-64, two NEON ones on AArch64. It is only
*fast* where AVX2 exists. Put the kernel behind the `simd` prefix
(§3.3b) and the wide clone gets real `vpxor` / `vpsllq` while the
baseline clone keeps working, with the choice made once per process on
a CPUID probe.

| Group | Primitives |
|---|---|
| load / store | `nurl_v256_ld(*u) → v256`, `nurl_v256_st(*u, v256)` — unaligned |
| construct | `nurl_v256_zero`, `_set64(a b c d)`, `_bcast64(x)`, `_bcast16(x)` |
| extract / insert | `nurl_v256_get64(v, i) → u64`, `_put64(v, i, x) → v256` |
| bitwise | `nurl_v256_xor`, `_and`, `_or`, `_andnot`, `_not` |
| 64-bit lanes | `nurl_v256_add64`, `_mul32u` (each lane's low 32 bits × the other's, a full 64-bit product: `vpmuludq`), `_shl64(v, n)`, `_shr64(v, n)`, `_rotl64(v, n)` |
| 32-bit lanes | `nurl_v256_add32`, `_rotl32(v, n)`, `_bcast32(x)` |
| 16-bit lanes | `nurl_v256_add16`, `_sub16`, `_mullo16`, `_mulhi16`, `_sra16` |
| interleave | `nurl_v256_unpacklo32(a, b)`, `_unpackhi32`, `_unpacklo64`, `_unpackhi64` — within each 128-bit half, as `vpunpck*` |
| half permute | `nurl_v256_permlo128(a, b)` → low halves of a and b, `_permhi128` → high halves (`vperm2i128`) |
| lane shift | `nurl_v256_shrlane64(lo, hi)` → lo's lanes 1, 2, 3 and hi's lane 0: the pair hi:lo one 64-bit lane down (`valignq` with AVX-512VL) |

The 64-bit group is what four-way Keccak needs (rotate and xor) and what
four-way Poly1305 needs (radix-2^26 limbs, one `vpmuludq` a product); the
16-bit group is what an ML-KEM / ML-DSA NTT butterfly needs; the 32-bit
group, the interleaves and the half permutes are what eight-way ChaCha20
needs — eight blocks a lane, and the transposes that hand each block's
words back in order. `_rotl32` by 8, 16 or 24 bits is a byte permutation
(one `vpshufb` on AVX2), and the compiler spells it as one.

`_mulhi16` is spelled as the widen-multiply-narrow sequence LLVM
pattern-matches back into a single `vpmulhw`, rather than as an
intrinsic — so the same source is one instruction on AVX2 and a correct
scalarised sequence everywhere else.

Between the widths, for code that works on two 128-bit blocks a
register (the VAES tier, §4.1b): `nurl_v256_join128(lo, hi) → v256`,
`nurl_v256_lo128(v) → v128`, `_hi128(v) → v128`, and
`nurl_v256_bswap128(v)` — `nurl_v128_bswap128` within each half.

### 4.1d `v512` — four 128-bit lanes (v2.11)

`v512` is `<8 x i64>`: what an AVX-512 zmm register holds, and two ymm
or four xmm registers anywhere else. It exists for the AVX-512 VAES
tier (§4.1b) — four AES blocks per instruction — and has only what a
block cipher in that shape needs; like `v256` it is correct on any
target and fast only where the hardware is that wide.

| Group | Primitives |
|---|---|
| load / store | `nurl_v512_ld(*u) → v512`, `nurl_v512_st(*u, v512)` — unaligned |
| construct | `nurl_v512_zero`, `_bcast128(v128)` (a `v128` in every lane), `_join256(lo, hi)` |
| extract | `nurl_v512_lo256(v) → v256`, `_hi256(v) → v256` |
| bitwise | `nurl_v512_xor`, `_and`, `_or` |
| lane arithmetic | `nurl_v512_add32`, `_add64` |
| byte order | `nurl_v512_bswap128(v)` — the sixteen bytes of each lane reversed |
| crypto (AVX-512 VAES tier) | `nurl_v512_aesenc`, `_aesenclast`, `_aesdec`, `_aesdeclast`, `nurl_v512_clmul_ll/_hl/_lh/_hh` |

A function using a `v512` crypto primitive is compiled for x86-64-v4
with 512-bit vectors kept legal (`"min-legal-vector-width"="512"`;
x86-64-v4 otherwise prefers 256-bit ones and splits each operation in
two).

### 4.2 Pointer types

`*T` is a raw pointer to T. `*void` is rewritten to `i8*` in the IR
(LLVM forbids `void*`).

Reading or writing through a `*T`, casting to a pointer type (except
the null `# *T 0`), and calling a function that takes or hands back a
`*T` (`vec_data`, `slice_data`, `slice_from_raw`, a program's own
`→ *T`, …) are allowed only inside an `unsafe` function (§3.3d), whose
author vouches for those lifetimes. Safe code reaches a container's
buffer through a view instead — `string_data`, or a `Slice` of a `Vec`
or a string (`slice_from_vec`, `slice_of_str`) — and a view, like a
`vec_data` pointer in `unsafe` code, is tracked against its container
(docs/MEMORY.md §2.10).

### 4.3 Optional `?T`

`?T` lowers to `{ i1, T }`. The first field is the *Some* tag (1) or
*None* tag (0); the second field is the payload (well-defined only when
the tag is 1).

Construction: `@ ?T { T payload }` for Some, `@ ?T { F # T 0 }` (or any
zero-shaped expression of T) for None.

Destructure with `??` match (§6.1) or `\` propagate (§6.4).

### 4.4 Slice `[T`

`[T` lowers to `{ T*, i64 }` — a borrowed view of a contiguous run of T
elements. The first field is the data pointer; the second is the
length.

A slice may own its backing buffer (a slice literal `[ T | ... ]`, or
the return value of an allocating call). Owned slices are subject to
auto-drop (§8).

### 4.5 Result `!T E`

`!T E` lowers to `{ i1, T, E }`: the tag (1 = Ok, 0 = Err) in field 0,
the Ok payload **by value** in field 1 (type T), and the Err payload
**by value** in field 2 (type E). The tag selects which slot is live;
the other is left zero. There is no heap-box or `i64` squeeze — a
multi-field struct Ok payload rides field 1 directly, mirroring the
`?T` → `{ i1, T }` symmetry. A `void` payload (`!v E`) lowers its slot
to a one-byte `i1` placeholder that is never read. Direct field access
is `. r 0` (tag, via `??`), `. r 1` (Ok payload), `. r 2` (Err
payload). The source-level NURL types of T and E are also preserved
separately for compile-time `\` try-propagation checking.

### 4.6 Function / closure types `(@ R P*)`

A function-typed *value* in NURL is a *closure* — a 16-byte struct
`{ R(i8*, P...)*, i8* }` holding a function pointer and an environment
pointer. The function pointer takes an implicit leading `i8*` env
argument.

A bare `@`-fn name is **not** a value. Using one in expression position
(e.g. `: c x my_fn`) is a compile error; wrap it in a closure literal:

<!-- doctest-prelude
@ my_fn i x → i { ^ * x x }
-->
```nurl
: (@ i i) sq \ i x → i { ( my_fn x ) }
```

### 4.7 Structs and enums

A struct is `:` `Name` `{` field* `}`; a field is `type IDENT?` (the
name is optional when only the type matters). Fields are accessed via
`. obj field` (§6.6).

An enum is `:` `|` `Name` `{` variant* `}`; a variant is
`IDENT type*` — the variant name followed by zero or more payload types.
Each variant compiles to an `i64` tag global named by the variant. The
enum value is `{ i64, i64, i64, ... }` sized to fit the variant with
the most payloads. Payload slots are uniformly `i64` — bit-complete for
every payload kind on every target (floats bitcast in and out, narrow
ints widen and truncate, pointers `ptrtoint`/`inttoptr`); a
pointer-typed slot would truncate f64 / >2³² payloads on wasm32, where
pointers are 32 bits wide.

A variant whose payload is a struct or enum declared *later* in the file
parses correctly via a name pre-pass. Pattern matching binds one variable
per payload slot, with no fixed cap on the number of slots (§6.1).

### 4.8 Generics

Generic functions and structs are parameterised by a type-parameter
list `[T]`, `[K V]`, etc. Each distinct type-argument list used at a
call or type-instantiation site materialises one mangled monomorphic
copy:

```nurl
@ id [T] T x → T { ^ x }
( id [i] 42 )       // → @id__i64
( id [s] `hi` )     // → @id__i8ptr
```

**Do not name a type parameter `T` or `F` if its body uses that boolean
literal.** Monomorphisation substitutes the parameter through the body by
whole word, before the body is parsed, and the lexer is context-free: a bare
`T` is the boolean literal `true` wherever it appears. So in a template
written `[T]`, a value-position `T` is rewritten along with the type
positions — `? T { … }` becomes `? i { … }`, and the instantiation fails
against source that was never written. The stdlib names its type variables
`A`, `K`/`V`, `E` for this reason (see `stdlib/core/vec.nu`); `[T]` is fine
in a body that never spells a boolean. The compiler names the collision in
the diagnostic when an instantiation of a `[T]` / `[F]` template fails.

Type arguments at call sites and in type applications may be *compound
types*, not just base identifiers: a base IDENT (type keyword or named
type), a pointer / option (`*T`, `?T`, `??T`), a nested generic or closure
type (`( Pair K V )`, `( @ R P* )`), or a trait object (`%Trait`). For
example `( id [*Point] p )`, `( box [( Pair i s )] x )`,
`( vec_new [( @ i i )] )`, `( Vec %Show )` and `( Rc ?( @ v ) )` are all
accepted; each argument's lowered type is mangled into the call name. A
type with no one-word spelling of its own is mangled — and substituted
into the template — as its *slug*: a closure as `fn<N>` followed by
`_<len>_<slug>` for its return type and each parameter in turn
(`( @ i i )` → `fn1_3_i64_3_i64`, `( @ v )` → `fn0_4_void`), a trait
object as `dyn_<Trait>`. The lengths make the slug a prefix code, so it
reads back to exactly the type it was made from. The one shape not
accepted as a type argument is a bare anonymous slice (`[T`) — wrap it in
a named struct.

A type parameter may carry one or more **trait bounds** via `: Trait`,
written `[A: Ord]`, `[K: Hash V]`, or `[A: Ord: Show]`. A bound is
checked at every instantiation: the concrete type substituted for the
variable MUST have an `impl` of the named trait, or the compiler rejects
the call naming the unsatisfied bound. Method dispatch inside the body
already resolves to the concrete impl through monomorphisation, so the
bound is an up-front guarantee and documentation rather than a dispatch
mechanism. The bound disambiguates from a slice parameter by the colon —
a slice type never contains one.

```nurl
@ my_max [A: Ord] A x A y → A { ? > ( ord_cmp x y ) 0 x y }   // A must impl Ord
```

`should_fail_trait_bound.nu` pins the rejection; `trait_bounds.nu` pins
the accepted path.

The `Send` / `Sync` markers (§4.9) are the one exception to "MUST have an
`impl`": those two bounds are answered by the compiler's structural derivation,
so `[T: Send]` accepts `i`, `s` and `( Vec i )` with no impl block anywhere and
rejects `( Rc i )` with a message saying so. `diag_send_generic_bound.nu` pins
the rejection.

Monomorphisation is deferred — instantiations are queued and emitted
after the main parse pass. Diagnostics emitted while re-parsing a
substituted body use the synthetic filename
`<generic Name__T1[__T2...] from caller.nu:line>` so an error points at
the user's call site (v2.1, 2026-05-25).

### 4.9 Traits

A **trait** names a set of methods a type can implement; an **impl** supplies
them for one type. Both use the `%` sigil:

<!-- doctest-prelude
$ `stdlib/core/string.nu`
: Point { i x i y }
-->
```nurl
% Show [T] {                       // trait declaration; [T] is the Self type
    @ fmt T self → String          // required method (header only)
    @ println T self → v {         // default method (has a body)
        ( puts ( string_data ( fmt self ) ) )
    }
}
% Show Point {                     // impl of Show for Point
    @ fmt Point self → String { ^ ( string_from ( nurl_str_int . self x ) ) }
    // println is inherited from the default, specialised to Point
}
```

**Dispatch model — static, monomorphised, no runtime identity.** A bare-name
method call `( fmt p )` dispatches on the *first argument's type*: at emission
each `(method, type)` pair is a distinct function `method__<mangled-type>`
(`fmt__Point`), and the call is rewritten to it. There is **no vtable, no type
tag, no `Self` pointer** — a trait/impl has no runtime representation, and a
value carries no trait identity. This is a locked 1.0 decision (§3.3): trait
dispatch is resolved by the type-mangled method name, not the trait's name.

**Default methods.** A method with a body in the trait is a default. An impl
that omits it gets a specialised copy with the trait's Self parameter `T`
substituted to the implementing type. An impl that provides the method
overrides the default.

**Coherence.** Each `(method, first-arg type)` pair may be registered by exactly
one impl. The compiler rejects, as a clear diagnostic rather than an LLVM
redefinition:

- a duplicate impl of the same trait for the same type;
- two type aliases that share an LLVM lowering (`i` and `i64`) implementing
  the same method — they collide on one dispatch key;
- two *different* traits each providing a same-named method for one type —
  bare-name dispatch cannot disambiguate, and the error names both traits.

**Bounds** (§4.8): a generic type parameter constrains its argument to impl a
trait via `[A: Ord]`; the bound is checked at each instantiation. Because
dispatch is by concrete type after monomorphisation, the bound is an up-front
guarantee, not a dispatch mechanism.

**Supertraits.** A trait may require other traits with a `:` clause:

```nurl
% Ord [T] : Eq { @ cmp T a T b → i }
```

`Ord : Eq` means *every type implementing `Ord` must also implement `Eq`* for
that same type. The obligation is enforced across the whole program (all
`$`-imports, any order) after signatures are collected; a missing supertrait
impl is a compile error naming it. `: Send` and `: Sync` are the exception:
they are derived, never implemented, so the derivation answers them where
each impl is (*Marker traits*, below). It composes transitively (`C : B`, `B : A`).
Because the supertrait impl is guaranteed to exist, a function bounded `[A:
Ord]` may freely call any supertrait method on `A` — dispatch resolves through
the supertrait impl the check proves present.

**Associated types.** A trait may declare per-impl type members; each impl binds
them, and the trait's methods may name them:

<!-- doctest-prelude
: IntBox { i v }
-->
```nurl
% Boxed [T] {
    type Elem                       // associated type
    @ unwrap T self → Elem
    @ first  T self Elem d → Elem { ^ ( unwrap self ) }   // default names Elem
}
% Boxed IntBox { type Elem i  @ unwrap IntBox self → i { ^ . self v } }   // Elem = i
```

In a default method the associated type is substituted to the impl's binding
(so `first`'s specialised copy for `IntBox` returns `i`). An impl must bind
exactly the trait's declared associated types — an unbound one, or a `type`
line naming an associated type the trait does not declare, is a compile error
at the impl. A binding is a single simple type name (the same restriction
trait-default substitution carries). There is **no projection** yet: an
associated type cannot be named as `A::Elem` at a generic call site; it is only
usable inside the trait's own method bodies/signatures.

**Ordering.** Trait declarations and their impls may appear in either order,
including across later or nested `$`-imports. The compiler collects the whole
program's explicit signatures and trait declarations before checking impl
associated-type bindings and registering omitted defaults. Supertrait checks
and dynamic vtables use that completed information. Import replay registers
each source impl once; distinct definitions remain distinct even on one line.

Explicit and default methods share signature registration: argument types,
arity, `inout` borrows and `sink` transfers are known before any caller is
emitted. Defaults therefore preserve the same calling and ownership
conventions as methods written in the impl.

**Marker traits — `Send` / `Sync`.** A trait with no methods carries no
behaviour; an impl of one is a pure *assertion about the type*. Five such
markers are declared in `stdlib/core/marker.nu` and given meaning by the
compiler:

```nurl
% Send [T] { }      // a value of T may MOVE to another thread
% Sync [T] { }      // two threads may reach ONE T at the same time
% NotSend [T] { }   // T must never cross a thread boundary
% NotSync [T] { }   // two threads must never reach one T at once
% Frozen [T] { }    // what a T lends is read-only (an RwLocked read guard)
```

Unlike every other trait, `Send` and `Sync` are **derived, not implemented**.
The compiler answers both questions by walking a type's whole graph — struct
fields, enum variant payloads, generic arguments, aggregate members, closure
captures — from four built-in cases: `Rc` is neither Send nor Sync (its
refcount is not atomic); `Cell` is Send but not Sync (a raw byte buffer
with unsynchronised writes); a library handle is Send, and Sync only where
asserted (its copies are one state, changed in place); and a trait object
`%Trait` is Send only when its trait declares `: Send`, and Sync only with
`: Send Sync` (its box holds any type implementing the trait).
Everything else inherits from what it contains.

The derivation is enforced where a value crosses a thread boundary —
`thread_spawn`, `spawn`, `chan_send`, and `Arc T` (whose payload must be Send
**and** Sync, because an Arc exists to be shared) — and it answers `[T: Send]`
and `[T: Sync]` bounds, which therefore need no impl block for `i`, `s`, or any
struct of them.

Writing a marker impl **overrides** the derivation for that type and stops the
walk there. `% Send T { }` / `% Sync T { }` assert safety the compiler cannot
see (`Mutex` is a handle over raw pthread memory and is nonetheless what makes
contents shareable — `stdlib/std/thread.nu` marks it); `% NotSend T { }` / `% NotSync T { }` assert
danger it cannot see (an FFI handle is an `s`, and `s` is Send). A negative
marker outranks a positive one on the same type. A positive impl is NURL's
spelling of Rust's `unsafe impl` — an assertion, not a proof — and outside
the standard library it is written so: `unsafe % Send T { }` (§3.3d). A
negative one only adds checks and needs no prefix. See
[`MEMORY.md` §6.5](MEMORY.md) for exactly what they do and do not guarantee.

**Dynamic dispatch — `%Trait` trait objects (grammar v2.3).** Alongside the static path a trait
may be used as a **dynamic object** so that values of *different* concrete types
can be handled uniformly (e.g. a heterogeneous collection). This is layered
*beside* static dispatch without changing it: a static `( fmt p )` on a concrete
`Point` still lowers to `fmt__Point`, and a trait/impl still has no runtime
identity for concrete values — the runtime representation exists only for the
`%Trait` object type.

<!-- doctest-prelude
: Dog { i woof }
: Robot { i beep }
-->
```nurl
% Speaker [T] { @ speak T self i vol → i }
% Speaker Dog   { @ speak Dog d   i vol → i { ^ * . d woof vol } }
% Speaker Robot { @ speak Robot r i vol → i { ^ + . r beep vol } }

@ announce %Speaker s i vol → i { ^ ( speak s vol ) }   // dispatches via vtable

: Dog d @ Dog { 2 }
: %Speaker sd ( dyn Speaker d )     // construct: box a Dog as a Speaker object
( announce sd 5 )                    // reaches Dog.speak with no static type known
```

- **Type `%Trait`** (type position) is a **fat pointer** lowered to
  `%dyn.<Trait> = type { i8*, i8* }`: a heap-boxed copy of the concrete value
  (field 0) paired with a per-impl **vtable** pointer (field 1). The vtable is a
  `[K x i8*]` constant whose slot 0 is the concrete destructor and slots 1..K are
  one thunk per method; each thunk adapts the uniform ABI `<ret>(i8* self, …)` to
  the concrete static method.
- **Construction `( dyn Trait value )`** boxes `value` (which must implement
  `Trait`) and pairs it with that impl's vtable.
- **Dispatch** is a bare-name call `( method obj )` whose first argument is a
  `%Trait`: the method's vtable slot is loaded and called indirectly. `Self`
  appears only as the erased `i8*` receiver; the other arguments are concrete.
- **Diamond upcasting.** A sub-trait object dispatches its supertraits' methods
  too: the vtable flattens the transitive supertrait method set (an override on
  the sub keeps the first slot), so a `%Pet` object can call the `Animal` methods
  `Pet : Animal` requires, including inherited **default** methods (which
  themselves call back through the object's dynamic dispatch).
- **Object safety.** A trait is usable as `%Trait` only if every method — and
  every supertrait's method — can be dispatched from an `i8*` self plus the
  signature: the trait has a `[T]` Self parameter, and no method (a) lacks a Self
  receiver, (b) names Self beyond the receiver, (c) consumes self by value
  (`sink`), or (d) mentions an associated type. Otherwise it is a compile error
  naming the offending method and reason (so an associated-type trait like
  `Boxed` is rejected as an object, not miscompiled).
- **Memory safety.** A `%Trait` binding is an owned value: it participates in the
  ordinary auto-drop / panic-unwind machinery via a synthesized `Drop` for
  `%dyn.<Trait>`, which runs the vtable's slot-0 destructor on the boxed value
  (freeing *its* owned resources transitively) and then frees the box. No leak
  and no double-free — verified under AddressSanitizer.
- **Ownership through dyn.** A call through a `%Trait` object reaches whichever
  impl the object holds, and is checked as a call of all of them at once: what
  it may keep, consume or lend back of its arguments is the union of the
  impls' summaries, and the impl that ran answers per call whether its result
  is the caller's to drop (a fresh `String` or raw `s`) or lent (a field of
  `self`, a literal). Impls that disagree on keeping an argument, and an impl that keeps
  its receiver (the object only lends it), are rejected at the call
  (docs/MEMORY.md §1, "Methods"). `sink` and `inout` parameters other than the
  receiver dispatch as declared.
- **Threads.** A `%Trait` object's box holds whichever type implements the
  trait, and the object's type does not say which, so the object is neither
  `Send` nor `Sync` unless its trait promises it: `% Job [T] : Send { … }`
  lets a `%Job` move to another thread (a thread's or fiber's capture,
  `chan_send`, a `[T: Send]` bound), and `: Send Sync` lets one object be
  reached from several at once (an `Arc`'s payload, a `[T: Sync]` bound). The
  promise is kept where each impl is: a type implementing `Job` is held to
  `Send` by the derivation (§4.9's markers), and an impl for one that reaches
  an `Rc`, a `Cell` or a thread-bound handle is rejected there. It reaches
  through supertraits: `% Step [T] : Job` objects may move as well.

The static surface is pinned by tests: `trait_bounds` / `should_fail_trait_
bound` (bounds), `test_09_trait_defaults` (defaults), `should_fail_duplicate_
impl` / `should_fail_ambiguous_method` (coherence), `trait_supertraits` /
`should_fail_missing_supertrait` (supertraits), and `trait_assoc` / `trait_
assoc_import` / `should_fail_missing_assoc` (associated types). The dynamic
surface is pinned by `dyn_dispatch` (object construction + vtable dispatch with a
value parameter), `dyn_diamond` (supertrait upcast + inherited default +
override), `dyn_call_ownership` (arguments and results across impls),
`diag_dyn_impls_disagree` / `diag_dyn_keeps_receiver` (the ownership checks),
`thread_dyn_send_trait` / `diag_send_dyn_object` /
`diag_send_dyn_impl_breaks_promise` / `diag_sync_dyn_impl_breaks_promise` /
`diag_sync_dyn_object_in_arc` (threads),
and `should_fail_dyn_not_object_safe` (object-safety rejection).

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

```text
: ~? type? IDENT expr
```

Binds `IDENT` to the value of `expr`. The optional `~` prefix marks the
binding mutable (default immutable). The type annotation is optional
when inferable from the right-hand side; an identifier that names a
registered type is taken as the type annotation, otherwise the
plain-IDENT form is type-inferred. A name already bound as a *value* is
not a type, so the inferred form rebinds it.

<!-- doctest-prelude
$ `stdlib/core/string.nu`
@ add i a i b → i { ^ + a b }
-->
```nurl
: i n 0                          // explicit type
: ~ i x 0                        // mutable
: String s ( string_new )        // named type
: n ( add 1 2 )                  // inferred (rebinds n)
```

A binding whose RHS is a fresh heap allocation becomes the *owner* of
that allocation (§8).

### 5.2 Set `=`

```text
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
| struct pointer `%T*` | IDENT | field lookup (inside `unsafe` only) |
| raw pointer `T*` | INT literal | array slot, constant index (inside `unsafe` only) |
| raw pointer `T*` | expression | array slot, computed index (inside `unsafe` only) |
| slice `{ T*, i64 }` | INT or expr | slice element via data ptr |

The object may itself be a **field path**, so a struct inside a struct is
written in place — `= . . o inner x 7` — one GEP per navigation hop down to
the last container, which then takes the ordinary store (same width
coercion, same diagnostics). The chain is walked by **type**, not by
counting dots: a hop that is not an aggregate *is* the object and is loaded
as a value, which is how `= . . d op + . d olen k # u byte` — a `*u` field
indexed by an expression — keeps its meaning. Writing through a nested path
requires a base binding that owns its storage: a `:`-bound struct, or an
`inout` parameter (whose `__ptr` is the caller's address). A by-value
parameter has nothing to write through and is rejected, as it is for a
single-hop store.

### 5.3 Defer `;`

```text
; { body }
```

Executes *body* when the enclosing function returns (LIFO order across
multiple defers). Useful for guaranteed cleanup.

Semantics (v2.3, 2026-08-03):

- **Reachability-armed** — the body runs at function exit iff its `;`
  statement was actually executed. A defer inside an untaken branch
  does not run; a defer inside a loop body runs **once**, not once per
  iteration.
- **Nested registration** — a defer body can register further cleanup.
  After that body completes, its reached nested defers run in LIFO order
  before older cleanup. An unreached parent does not run its nested defers.
- **Ownership interaction** — a defer body may reference any owned
  value (string, slice, `% Drop` value, closure) whose binding was
  registered *before* the `;` statement; those values stay alive
  through the defer chain and are auto-dropped after it runs. Values
  bound *after* the last defer drop at their normal scope exit.
  Returning an owned value transfers it to the caller as usual. With
  several return paths, a pre-defer owned value is transferred on the
  paths that return it and dropped after the chain on the others. A
  defer that may run at such a return may read the value that `^`, or a
  returned or fall-off block, hands back, but releasing it, giving it or a
  field of it a new value, or handing it on is a compile error
  (h426–h434, h872–h874).
- `^` (return) and `\` (failure propagation) inside a defer body are
  compile errors — the chain runs during return; handle cleanup failures
  locally with `??`. A closure defined there has its own return context.
  `;` inside a closure body is a compile error (a
  closure is its own function; defer there would chain into the
  enclosing function).

### 5.4 Loop, foreach, complement-as-statement

The `~` token at statement position is *speculatively* parsed in this
order:

1. `~ IDENT IDENT …` or `~ IDENT . …` — foreach
2. `~ expr {` — while loop
3. otherwise — complement expression used for its side effects

```text
~ cond { body }              // while
~ x xs { ( puts x ) }        // foreach (xs must have slice type)
~ x . bag items { … }        // foreach over a field
```

In a foreach, the element binding is a *borrow* from the iterated
slice. It is not owned and is not dropped at iteration end. Mutating
the iterated container from inside the loop body is rejected by the
borrow checker (§9.5).

### 5.4.1 `break` and `continue` (v2.4)

Loop control for the **innermost enclosing** `~` loop body:

<!-- doctest-prelude
@ skip i k → b { ^ == % k 2 1 }
@ done i k → b { ^ > k 7 }
: i n 10
-->
```nurl
: ~ i i 0
~ < i n {
    ? ( skip i ) { = i + i 1 continue } {}   // re-evaluate the loop condition
    ? ( done i ) { break    } {}   // leave the loop
    = i + i 1
}
```

Both **terminate the block they appear in**, exactly as `^` does —
anything after one in the same block is unreachable. Both are reserved
identifiers (§2.4.1), not symbols: every two-character prefix spelling
collides with an existing program, and `~>` in particular would swallow
every loop written `~ > cond { … }`.

Using either outside a `~` body is a compile error naming the reason,
not a silent no-op.

Both spellings of a `~` body qualify — the while loop and the foreach. A
foreach owns a hidden index, so its `continue` lands on the index bump
rather than on the loop check: the iteration advances exactly as a
fall-through does, and the two paths share one landing pad.

Note the interaction with §7 (ownership): a jump leaves the block
*without* running the code the normal path would, so the compiler emits
the loop body's whole drop sequence at the jump before branching. A
`continue` past a closure that captured by value therefore releases that
closure's environment exactly once, on every path.

### 5.5 Expression statements

A statement may be any expression. The value is discarded.

A bare identifier that names a known callable (an `@`-function, an FFI
function, or a runtime builtin) is rejected at statement position with:

```text
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
> no balancing parentheses — which is the entire point of the notation.
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

```text
+ - * / %       arithmetic (integer + float)
< > <= >= == != comparison (yields b)
<< >>           integer shift
& |             logical (b) OR bitwise (integer); dispatched by LHS type
^^              XOR (integer or b; float is an error)
&& ||           strict logical (b only) — alternate spelling of & / |
```

`<<` lowers to LLVM `shl`; `>>` uses `ashr` for signed operands and `lshr`
for unsigned operands. Counts must be nonnegative and smaller than the
operand's bit width. The compiler rejects an out-of-range constant count;
dynamic counts outside that range panic with `shift amount out of range`.
Counts are not implicitly masked to their low bits.

Integer `+`, `-` and `*` wrap at the operand width. Integer division and
remainder by zero panic with `division by zero` / `remainder by zero`.
Signed `MIN / -1` and `MIN % -1` panic with `division overflow` /
`remainder overflow`. These checks apply in ordinary and instrumented builds,
even under the deprecated `--no-borrowck`. Floating division/remainder retain
their IEEE infinity/NaN behavior.

Comparison operators yield `b` (`i1`). All other binary operators
require operand types to match: mixing float/non-float,
pointer/non-pointer (outside equality-against-`0` null checks), two
registers of different integer or float widths, or a bool register with
an integer register is a compile error naming the cast to write. An
integer **literal** combined with a typed operand evaluates at the typed
operand's width and must fit it (`+ 300 u8val` is rejected, not
wrapped); a bool operand combined with an integer literal **widens**
(`+ 10 flag` is 10 or 11 — `zext`, the binding law); an `f32` operand
combined with a float literal widens to `f` (`fpext`, lossless).

For an n-ary chain write n-1 operators:

<!-- doctest-prelude
: b a T
: b b T
: b c F
: b d T
-->
```nurl
: b all & a & b & c d        // a && b && c && d
: b any | | | a b c d        // a || b || c || d
```

The compiler rejects the canonical foot-gun
`? & a b c d { ... } { ... }` (where the bare `c`/`d` would otherwise be
consumed as the ternary's then/else and the `{ ... }` blocks become
statements) as a hard error by default; `--no-strict-arity` demotes it to
a warning.

#### Unary (1 operand)

```text
! expr     logical NOT
^ expr     return
~ expr     bitwise complement (xor -1) for integers; fneg for f
\ expr     try-propagate (disambiguated from closure by lookahead, §6.4)
```

There are no unary arithmetic operators. To negate a value, use binary
minus against a literal zero or bitwise complement of zero:

<!-- doctest-prelude
: i x 5
-->
```nurl
: i neg - 0 x        // unary negate: 0 - x
: i ones ~ 0         // -1, useful for bit-twiddling
```

Negative *literals* are directly supported at the lexer level: a `-`
immediately followed by a digit (no whitespace) lexes as the start of a
negative INT or FLOAT token.

#### Ternary

```text
? cond then else
```

Both `then` and `else` are full expressions. A block expression `{ ... }`
is a common form. Branch types must match; mismatched branches degrade
to `void`, which the enclosing return/let then flags.

#### Match

```text
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

<!-- doctest-prelude
: | Val { JNull  JNum i  KeyPress i i  Ok i  Other }
@ key_event i c i m → s { ^ `key` }
: Val val @ Val { KeyPress 65 0 }
-->
```nurl
: s text ?? val {
    JNull        → `null`
    JNum n       → ( nurl_str_int n )
    KeyPress c m → ( key_event c m )    // 2-payload binding
    Ok 200       → `ok`                 // literal-constrained
    _            → `other`
}
```

A pattern arm binds one variable per payload slot (no fixed cap).

An arm may carry a **guard** — `? cond` after the payload, before the
`→` — evaluated *after* the payload bindings are in scope. A false guard
falls through to the next arm, so a guarded arm does **not** satisfy
exhaustiveness for its variant: a later catch-all (another arm for the
variant, or `_`) is still required. Guards are not allowed on a `_`
wildcard or an or-pattern.

<!-- doctest-prelude
: | Msg { Move i  Stop }
: Msg msg @ Msg { Move 3 }
-->
```nurl
: s dir ?? msg {
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

```text
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
| `inout` | closure, `inout` first param |
| `TYPE_KW` / `*` / `?` / `[` / `!` / a type name | closure, leading param type |
| `(` then `@`, `TYPE_KW`, `*`, `?`, `??`, `[`, `!`, `\|` or a type name | closure, parenthesised param type |
| `IDENT IDENT →` | closure, single named param |
| anything else | try-propagate |

A type name is a declared struct or enum, a generic instance, `Vec`, or a
generic struct's own name (`\ ( Slice u ) s → …`). None of them can be
called, so none of them starts a `\ ( call )` try-expression.

```nurl
$ `stdlib/std/int.nu`

@ squared s src → !i ParseErr {
    : (@ i i) sq \ i x → i { * x x }    // closure
    : n \ ( int_parse src )             // try-propagate Result
    ^ @ !i ParseErr { T ( sq n ) }
}
```

`\` propagation requires the **enclosing function** to return a
compatible `?` / `!` shape (same error type for results). At a site
that cannot propagate — a `→ i` `main`, a callback with a fixed
signature — use the leaf-site combinators from the stdlib instead of
nesting `??`: `res_expect` / `opt_expect` (payload or panic with your
message), `res_unwrap_or` / `res_unwrap_or_else` (payload or fallback),
and the `res_ok` / `res_err` / `opt_ok_or` bridges
(`stdlib/core/result.nu`, `stdlib/core/option.nu`).

A closure compiles to a 16-byte `{ fn_ptr, env_ptr }` value. Captures
are stored in a heap-allocated environment struct. A closure owns
its environment wherever it is kept, and nothing frees one by hand: a
temporary closure passed to a call is dropped right after it, a
`:`-bound closure at scope exit, a returned closure by the caller that
receives it, and one stored into a struct field, a container or another
closure's captures with its holder; `spawn` / `thread_spawn` keep their
own copy — or, for a closure written in the call itself, the closure,
handed over. The env records how to drop and copy what it captured, so
dropping it releases the whole tree. A hand-written free of an env is a
compile error. It is **not** reference-counted — copying a closure
copies its env. See [`docs/MEMORY.md` §7.5](MEMORY.md) for the full
rule.

### 6.5 Function calls

```text
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

```nurl
@ box s label i width = 10 s fill = `-` → v {
    // …
}
```

A call may then **omit** defaulted trailing arguments, and may pass any
argument **by name** with an `IDENT:` label. Named arguments may appear
in any order and follow any leading positional ones; omitted parameters
fall back to their defaults:

```nurl continue
( box `a` )                    // width=10  fill=`-`
( box `b` 3 )                  // width=3   fill=`-`
( box label: `d` fill: `=` )   // named, reordered; width defaults
( box `e` fill: `#` width: 5 ) // positional + named, reordered
```

Defaults are filled **at the call site** — the callee receives a full,
fixed-length argument list, so a defaulted function is an ordinary
fixed-arity function with no runtime cost. A positional argument after a
named one is rejected. A positional call fills from the end and stops at
the first omitted parameter with no default, so a default is usable
positionally only when every parameter after it also has one; a named
call can omit any defaulted parameter wherever it sits.

A default is an **argument**, and is type-checked as one at every call
that omits it — the same battery a written argument goes through, in
both the positional and the named spelling. (It was not, on the
positional path: `@ show f x = 1 → v` called `( show )` passed an
integer register where the callee reads a float one, and printed 0.)

Defaults and named arguments are **not** available on generic functions,
FFI / variadic declarations, or parameters carrying the `inout` / `sink`
convention; all four are rejected at the declaration. An `inout`
argument is the ADDRESS of a mutable binding, and a default is a value
with no address — the literal went into the pointer slot and the callee
stored through it. A `sink` parameter consumes its argument, which one
value spliced into every call cannot give more than once. `kwargs.nu`
pins the feature.

#### Parameter conventions

A function parameter may carry a leading convention marker (§7.2):

- *(none)* / `in` — immutable borrow by value (the default).
- `inout` — exclusive mutable borrow. The argument MUST be a mutable
  (`: ~`) binding, a field target `. obj field`, or an element of a mutable
  typed-pointer binding `. pointer index`; it is passed by
  address. The callee mutates the caller's storage in place. Ordinary
  and generic declarations may follow their callers.
  Pointer indices must be integers and are evaluated once. Named fields through
  struct pointers are addressable as well, through an immutable pointer
  binding or a pointer parameter too: the pointer stays, the memory it
  points to is written. The pointee must match the declared
  parameter type exactly; raw-pointer bounds remain the caller's responsibility.
- `sink` — consume / move. The callee takes ownership; the caller may
  not use the argument binding afterwards. Compiler-managed enum owners
  and user Drop-trait values transfer their drop obligation, and so do
  raw owned strings: `sink s` is how a function that takes a string over
  declares it, as `string_adopt` does. In safe code a declared `sink s`
  is the callee's own string, released on every way out unless it moves
  on (returned, handed to another `sink`, adopted as a `String`), and its
  caller hands over its own string or a copy (§7.2); `unsafe` code and
  the standard library manage a raw `sink s` by hand. Transfer for owned
  slices and tracked struct fields remains unsupported.

#### Auto-inferred `sink` (v2.1, 2026-05-25)

A function whose body passes one of its own parameters — or a field or
the payload of one — to another function's `sink` slot, or hands it
back, has that parameter
**auto-inferred** as `sink` (a function that takes a field of its
parameter owns the rest of it, and drops it). Call sites of such a
wrapper see the same ownership contract: the argument is moved, and a
subsequent read is a use-after-move error. Explicit signatures seed a fixed point of call effects
across ordinary bodies and generic instances, including forward calls and
all argument positions. Names and return types never imply consumption.

```nurl expect-error="use of moved value 's'"
$ `stdlib/core/string.nu`

@ take String s → v { ( string_free s ) }   // s auto-inferred sink

@ main → i {
    : String s ( string_from `hi` )
    ( take s )                              // s is consumed
    ( nurl_print ( string_data s ) )         // error: use of moved value
    ^ 0
}
```

#### The package's version `( pkg_version )`

`( pkg_version )` is the `version` of the package the source file belongs
to — the one in the `[package]` table of the nearest `nurl.toml` above the
file — as a string literal (`s`). The compiler reads it when it reads the
file, so the program carries the version its manifest names and the number
is written in one place:

```nurl
$ `deps/cli/src/cli.nu`

: Cli c ( cli_new `tool` `what it does` ( pkg_version ) )
: s TOOL_VERSION ( pkg_version )             // a top-level constant too
```

Each file answers for its own package: a dependency's source reads the
dependency's manifest. A file with no `nurl.toml` above it, or one whose
`[package]` names no `version`, is a compile error. Only the exact form
`( pkg_version )` is read this way, so a function of that name that takes
arguments is an ordinary call.

### 6.6 Member access `.`

```text
. obj index
```

The compilation rule is chosen by the LLVM type of `obj`:

| Object type | Index | Effect |
|---|---|---|
| struct pointer `%T*` | IDENT | GEP field lookup + load (inside `unsafe` only) |
| raw pointer `T*` | INT | array slot, constant index (inside `unsafe` only) |
| raw pointer `T*` | expr | array slot, computed index (inside `unsafe` only) |
| `{ i1, T }` (opt `?T`) | 0 / 1 | tag / payload |
| `{ i1, T, E }` (res `!T E`) | 0 / 1 / 2 | tag / Ok payload / Err payload |
| slice `{ T*, i64 }` | 0 / 1 | data ptr / length |
| named struct `%T` | IDENT | extractvalue by registered field idx |
| enum value `%T` | 0 | whole value (for `??` match input) |

### 6.7 Cast `#`

```text
# target_type expr
```

Explicit type coercion. Used for width changes, signed↔unsigned
reinterpretation, pointer casts, and the canonical closure-field-extract
pattern:

<!-- doctest-prelude
: Point { i x i y }
@ some_fn → i32 { ^ # i32 7 }
-->
```nurl
unsafe @ casts ( @ v ) closure → v {
    : i n # i ( some_fn )                   // i64-truncate / widen
    : *Point p # *Point ( nurl_alloc 16 )   // cast i8* to *Point
    : *u fp # *u closure 0                  // extract fn ptr from closure
    : *u env # *u closure 1                 // extract env ptr from closure
    ( nurl_free # s p )
}
```

Pointer casts (except the null `# *T 0`), closure fn / env extraction and
`nurl_alloc` compile only inside an `unsafe` function (§3.3d).

The trailing INT (0 or 1) is consumed only when the source expression
is a closure-shaped struct and the destination type is a pointer — the
common shape for feeding C-runtime callback APIs (`thread_spawn`,
signal handlers) the raw fn-ptr / env-ptr pair.

A struct converts to an integer or a pointer through its first field, and
a pointer converts back to a struct whose first field is a pointer (a
handle: `# ( Vec u ) p`). Where that first field is itself a struct
wrapping one pointer (`{ s ctl }`, as a library handle's
`( Shared T )` is), the cast follows it to that pointer: `# i h` and
`# Regex # s 0` work on such a handle as on a one-pointer one. Any other
aggregate first field has no scalar to take and is an error.

Float-to-integer casts truncate toward zero and use the target's signedness.
The truncated value must fit the target: `-128.9` converts to `i8(-128)` and
`-0.9` to `u8(0)`, but `128.0` does not fit `i8`. Out-of-range values, NaN and
infinities panic with `float-to-integer conversion out of range`. The same
rules apply when an integer cast extracts a floating first field from a
structure. A float-to-`b` cast is a compile error in both forms; write an
explicit comparison to produce a truth value.

### 6.8 Sizeof `Z`

```text
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

```text
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

<!-- doctest-prelude
$ `stdlib/core/string.nu`
$ `stdlib/std/channel.nu`
@ work i n → v {}
@ handle String s → v {}
@ quit → v {}
: ( Channel i ) jobs ( chan_new [i] )
: ( Channel String ) control ( chan_new [String] )
-->
```nurl
?? {
    [i]      jobs    → o { ?? o { T n → ( work n )  F → ( quit ) } }
    [String] control → o { ?? o { T s → ( handle s ) F → ( quit ) } }
    _                → {}    // nothing ready
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

```text
@ name [T]? param* → ret { body }
```

Function declarations are top-level only (the `@` token in expression
position is the aggregate-literal start). A function MUST have at
least the return-type arrow `→` and a body block.

A parameter may carry a **default value** `= atom`
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
  binding is marked moved. The ABI is by value. Ownership transfers before
  the call; the callee drops a `String`, `Vec`, owning struct, handle
  enum, library handle or `Drop` value on exit unless it returns or
  transfers it onward. A raw `s` is handed over too: in safe code the
  callee releases it on exit unless it moves it on, and the caller hands
  over its own string — which leaves the binding — or a copy of anything
  else ([`docs/MEMORY.md`](MEMORY.md) §1); in `unsafe` code and the
  standard library a raw `sink s` is managed by hand. (An owned slice
  cannot be passed to a `sink` yet.)

`in` / `inout` / `sink` are contextual keywords — recognised only as a
parameter's leading token. `inout` is additionally banned as a
parameter name.

A closure may take a parameter `inout` as well: its type spells it
`( @ R inout T )` and the literal `\ inout T x → R { … }`. The argument
is the caller's mutable binding (or a field of one), passed by address
exactly as to a function, so the closure changes the caller's value in
place. Three rules keep it exclusive: the argument must be a mutable
`: ~` binding; a closure value carries no summary of what it does, so
every view into an `inout` argument ends at the call (the closure may
move or free what it holds); and a closure may not be handed `inout` a
binding it also captures — nor may a call pass a binding (or a field of
one, `. c fds`) `inout` beside a closure argument, named or written inline,
that captures it — because inside, the parameter and the capture would be
two names for one value. `locked_update` and `locked_apply`
(stdlib/std/thread.nu) are built on it: they run a closure on a `Locked`
value where it lives, without moving it out and back. So are `vec_update`
and `vec_apply` (stdlib/core/vec.nu): they run one on a Vec's element in
place, the Vec passed `inout` so that a closure able to grow or shrink it
under that element is rejected. A closure captures a binding it only reads
by value; a `: ~` binding it assigns or hands to an `inout` parameter, by
pointer (§8.4), so a callback
can count, set a flag or hand a result out into its caller's binding —
and, holding a pointer into that frame, cannot outlive it (§9.3). A result can also come back as
the closure's return value (`vec_apply`, `locked_apply`) or through an
`inout` parameter.

A foreign (`&`) declaration may mark a parameter `inout` too: the C
function takes a pointer to a `T` it writes a result through, and the
argument is a mutable binding whose address is passed — nothing is
allocated for the result.

```nurl
& `libcuda` @ cuMemGetInfo_v2 inout i avail inout i total → i32

unsafe @ gpu_free_bytes → i {
    : ~ i avail 0
    : ~ i total 0
    : i32 rc ( cuMemGetInfo_v2 avail total )
    ^ avail
}
```

The parameter may be a struct too (`inout Timespec ts`): the C function
fills the caller's local in place.

A pointer or string parameter may say what the C function does with it
(grammar v2.10): `in` — it only reads, during the call (it keeps and frees
nothing: a temporary handed there is released after the call, and a frozen
view may be passed); `sync` — it changes what is there only atomically or
under a lock of its own; `nocapture` — its result holds nothing of it.
Unmarked, a `*T` is taken to be written through, and either kind may be
kept or freed.

<!-- doctest-prelude
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
: s dir `/tmp/app`
-->
```nurl
& `c` @ remove in s path → i32
: !v IoErr r ( file_delete ( nurl_str_cat dir `/data` ) )   // the path is released
```

A foreign function that returns a string it allocated, for the caller to
release, declares its result `sink s`: the binding the result lands in
owns it — it is released at scope exit, or handed on (`string_adopt`,
another `sink` parameter), like any owned string — so nothing frees it by
hand. Only a raw string `s` can be a `sink` result.

```nurl
$ `stdlib/core/string.nu`

& `c` @ strdup s src → sink s

unsafe @ copies → String {
    : s copy ( strdup `text` )      // released at scope exit
    : String owned ( string_adopt ( strdup `more` ) )
    ^ owned
}
```

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

```nurl
@ id [T] T x → T { ^ x }
```

Type arguments at call sites may be compound types — a base identifier
(type keyword or named type), a pointer / option (`*T`, `?T`, `??T`), a
nested generic / closure application (`( Pair K V )`, `( @ R P* )`), or a
trait object (`%Trait`, §4.8); only a bare anonymous slice (`[T`) is
excluded. Each distinct argument list
materialises one mangled monomorphic copy. The body is stored as source
text at the declaration and re-parsed per instantiation.

Generic functions support `inout` and `sink` parameter conventions —
explicit conventions are collected from each template before its callers
are compiled. Inferred consumption also uses the compiled instances and the
whole-module fixed point.

## 8. Memory model

NURL has no tracing GC (`Rc` cycles are collected, docs/MEMORY.md §7.7).
Heap allocations are managed by **single-owner auto-drop**: the compiler tracks which binding owns each heap resource
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
  fresh allocations (each is tracked individually; a fresh raw string
  field only in `unsafe` code — in safe code a raw string in a value is
  a view, §9.12),
- a value of a type with a user `Drop` trait impl,
- a string literal or an owned string bound by a mutable string binding
  (`: ~ s`): the binding takes its own copy, and every value assigned to
  it after is fresh or its own copy,
- a `String`, a `Vec T`, or a struct whose fields own one (§8.5).

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

A closure's heap environment is **not** reference-counted. It is owned
wherever the closure is kept — a binding, a struct field, a slice, a
container's element, an option or a result, another closure's captures,
a spawned thread — and dropped by that owner; a returned closure's env
belongs to the caller, and a borrowed one stored into an owner is copied.
A closure read out of a field, an option's payload or a container's
element borrows that owner: calling it after the owner died, was given a
new value or had the field replaced or its elements dropped is a compile
error. Freeing an env by hand is a compile
error. See [`docs/MEMORY.md` §7.5](MEMORY.md).

A closure *captures by pointer* a mutable (`: ~`) multi-field struct
binding, and any other mutable binding its body assigns or hands to an
`inout` parameter (see
[`docs/MEMORY.md` §2.3](MEMORY.md) for the lifetime rule): the env block
stores the caller's alloca pointer rather than a value snapshot, so writes
through the closure reach the caller's binding — `( vec_each v \ i x → v
{ = n + n 1 } )` counts into `n`, and `recover \ → v { = out ( f ) }`
hands `f`'s result out. A value assigned that way replaces the binding's,
which is dropped. One that only reads a binding takes a snapshot of it, as
immutable as the binding (an immutable one cannot reach an `inout`
parameter through it either). A
by-pointer capture borrows the caller's stack frame and MUST NOT
out-live it. The borrow checker rejects an escaping by-ref capture
(returning the closure, pushing it into a longer-lived container,
spawning a thread or a fiber, or installing a signal handler, that holds
it).

### 8.5 `String`, `Vec` and owning structs

`String`, `Vec T`, every enum and plain struct whose fields own one, and
the library handles (a generic struct whose module defines `S_drop`:
`HashMap`, `Set`, `Deque`, `BTree`, `Box`, `Rc`, `Arc` — docs/MEMORY.md
§7.6) are dropped like any other owned value; no program needs
`string_free` / `vec_free` / `map_free`, which remain as an explicit early
release. Each owning
binding carries a drop flag, so a value is released exactly once
whichever way it leaves:

- storing it into a struct or enum literal, a field, or a container
  element moves it; a parameter stored that way is taken over from the
  caller;
- `: ~ cur root` makes a cursor that borrows `root`'s value (an
  immutable `: cur root` moves it);
- a borrowed value stored into an owner is copied;
- a `?` / `??` join hands over what its chosen arm owned, and a fresh
  `? T` / `! T E` returned by a call owns its payload in the arm that
  binds it;
- `( mem_forget x )` (only inside an `unsafe` function, §3.3d) gives up
  `x`'s value for good — for a hand-written disposer;
- `( mem_take x )` (only inside an `unsafe` function) claims `x`'s value
  — for a container operation that hands an element out (`vec_pop`), so
  the element is owned, not lent.
- `( mem_put_back x )` (only inside an `unsafe` function) stores `x` back
  into the slot it was read from without copying it or taking it over —
  for an element setter.
- `( mem_replace [T] place x )` (stdlib/core/mem.nu, `unsafe`) puts `x`
  into the `inout` place and returns what the place held, owned — for
  taking a value out of a field (through a pointer too) and leaving
  another in its place.

See [`docs/MEMORY.md` §7.6](MEMORY.md) for the complete rules and
[`docs/LIMITATIONS.md`](LIMITATIONS.md) for the shapes that still
borrow.

## 9. Borrow checker

The borrow checker is a static analysis pass over the parsed program.
It is **always on** (`--no-borrowck` is deprecated and warns: without the
checker nothing guarantees memory safety). The rules are conservative,
and each diagnostic names a fix (docs/MEMORY.md §6.3).
`--strict-borrowck` (off by default) adds three opt-in checks on top
(see [`docs/MEMORY.md` §2.9](MEMORY.md)). Diagnostics are **hard
errors**; the compiler exits non-zero
with a count of violations after walking the whole program. The checker
is **diagnostic-only** — emitted IR is byte-identical whether it runs or
not.

Thirteen rules are enforced. The semantic level is summarised here; for
exact phrasing and the soundness contract see
[`docs/MEMORY.md` §2 and §6](MEMORY.md).

### 9.1 Move (use-after-move)

A binding is *moved* when consumed: stored into an aggregate, an Option
or a container, sent on a channel, returned, passed to an explicit or
inferred `sink` parameter, captured by a closure another thread or fiber
runs, or bound to another immutable name (see §9.2). After a move —
including a move on *some* path — reading the binding is rejected. A
value with nothing to release is copied instead.

### 9.2 Alias / double-free

An immutable `: T b a` copy of an owned-heap binding `a` is treated as
a *move* — ownership passes to `b`. A `: ~` mutable copy is treated as
a borrow / cursor, not a move (this is the conventional disambiguation
between "owning copy" and "working alias"). `: T b a` / `= b a` move an
owner and copy a borrow; `: ~ T b a` borrows. A string binding (`s`)
that owns its buffer is the exception: `: s b a` makes `b` a view of
`a`'s buffer, which ends when `a` is given a new value or ends, while
`: ~ s b a` and `= b a` give `b` its own copy
([`docs/MEMORY.md` §1 and §2.10](MEMORY.md)).

### 9.3 Escape analysis

A closure capturing a binding by pointer (a `: ~` multi-field struct, or
a `: ~` binding it assigns or hands to an `inout` parameter — see §8.4) is a *stack reference*. Returning it, pushing it
into a longer-lived container, spawning a thread or a fiber (or
installing a signal handler) that holds it, or
assigning it into a longer-lived binding is rejected. The escape rule
also covers an aggregate (struct) literal that holds such a closure,
a `= . obj field` store into one (the struct inherits the reference),
and the phi of a `?` / `??` — a join carries the deepest referent depth
any live arm carries, so `^ ? c f f` is rejected exactly as `^ f` is.

### 9.4 Exclusive access at a call site

A binding passed `inout` to a call MUST NOT be aliased by another
*bare-identifier* argument of the same call (whether that other one is
`inout` or a plain by-value read). This is the "N readers XOR 1
writer" rule scoped to a single call.

<!-- doctest-prelude
: Counter { i n i max }
@ swap_counters inout Counter a inout Counter b → v { : i t . a n = . a n . b n = . b n t }
: ~ Counter c @ Counter { 3 10 }
-->
```nurl expect-error="'c' is both mutably borrowed"
( swap_counters c c )   // error: 'c' is both mutably borrowed and
                         //         aliased by another argument
```

A read of the same binding through a *nested sub-expression* argument
(`( f inout c (g c) )`, `( f inout c . c n )`) is **not** flagged by
default — by
the language's left-to-right evaluation order and Option B's
call-scoped borrow lifetime, that read completes before the `inout`
borrow goes live (§6.2).

That holds for a read that yields a plain value. A view or a borrow of
the container does not end with the read: it lives on into the call. So an
argument the callee may change — `inout` or by value, one whose buffer
its summaries say it may move or free, or whose elements they say it
may drop or replace (raw code: anything it mutates) — cannot also reach
the call through another argument the callee does not keep: not as the
same owner passed twice (`( f xs xs )`), and not as a view or borrow of
it, whether bound before the call or built in a nested sub-expression.
Inside the callee the two are unrelated names, and the change through
one leaves the other dangling:
`( grow_then_read v ( slice_from_vec [i] v ) )`, whose callee grows `v`
and then reads the slice, is rejected naming both arguments
([`docs/MEMORY.md` §2.4](MEMORY.md)).

### 9.5 Iterator invalidation

In a `~ x xs { ... }` foreach loop, the iterated container `xs` is
borrowed for the body's duration. Mutating `xs` inside the body — via a
stdlib container mutator on its receiver arg 0
(`vec_push` / `vec_insert` / `vec_remove` / `vec_pop` / `vec_clear` /
`vec_set` / `vec_set_len` / `vec_reserve` / `vec_shrink_to_fit` /
`vec_extend` / `vec_free` / `vec_free_with` / `vec_swap` /
`vec_reverse`) or as an `inout` argument — is rejected. A loop over a
field (`~ x . obj items`) borrows that field: mutating `obj.items`, or
handing `obj` on whole that way, is rejected in the body; another field
of `obj` is not.

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
whole module compiles, so definition order does not matter — including a
*pure forward chain* of helpers, whose summaries are propagated as
implications and run to a fixed point before any parked check replays.

### 9.8 Return escape

A helper that **returns one of its parameters** — directly, inside a
returned struct at any nesting depth, inside a closure that captured it,
or after binding it to a local first — hands the reference back out. The checker records a
second summary of returned-parameter positions; the result of such a call
carries the max referent depth of the arguments at those positions, so
the existing escape sinks (§9.3 / §9.7) fire on it. A helper that returns
a *fresh* value is not a passthrough and stays legal.

### 9.9 Closure captures

A closure literal copies each captured binding's handle into its heap
environment, so the closure *holds* those handles for as long as it can
be called. **Invoking a closure is a read of everything it captured**:
freeing a captured handle and then calling the closure is rejected as
the use-after-move of §9.1, and so is capturing a binding that is
already moved. The invocation may be direct (`( f )`) or one call deep,
through a parameter the callee only ever invokes; a closure captured by
another closure carries its handles outward at any depth. Running a
closure is also what its body does to its captures: one that changes,
reallocates or drops elements of a capture ends the views and borrows of
that capture (§9.11) at the call — made directly, or by handing the
closure to a function that may run it
([`docs/MEMORY.md` §2.11](MEMORY.md)).

A closure that changes a capture this way is a second route to it, under
the exclusive-call rule of §9.4: handed to a call, or called itself, it
MUST NOT meet another argument that reaches that capture — the binding,
a borrow or a view of it, or another closure that captured it. A closure
that runs a closure it captured does what that one does, and a closure
whose body changes a capture MUST NOT also hold a view or a borrow of it.
Inside a closure body, running a closure the caller chose — a closure
parameter, or a closure a parameter holds in a field or an element — ends
the views of every binding the enclosing closure captured by reference,
since that closure may re-enter it and grow what it captured.

Merely *loading* a closure value is not a use of its captures — that is
how a closure's heap environment is reclaimed once it is dead, which
legitimately happens after the captured handles are freed. A closure kept
by a struct or by a callee ties that owner to its captures in the same
way.

### 9.10 Consume after store

A value stored into an owner — a bound or returned aggregate literal, a
container (`vec_push`), a callee that keeps it — belongs to that owner.
Releasing it again through the original name is an error (a double free
when the owner drops it), and so is reading it: the value moved. To keep
one and hand one on, store a copy (`( string_clone x )`), or read it
through its owner (`. w s`).

### 9.11 Borrows and views

A read that does not take ownership — `vec_get`, a field read, a match
payload of a borrowed value, a call result the callee lends — is a
*borrow* of its source. It may be read and passed on, never released,
stored as an owner or sent, and it ends when the source is moved,
released, reassigned or has the field replaced; reading it after that is
rejected. A view — from `string_data`, a `Slice` of a `Vec` or a string
(`slice_from_vec`, `slice_sub`, `slice_of_str`), or, in `unsafe` code,
`vec_data` — also ends at any mutation that may reallocate the buffer,
and stays a view of its source wherever it goes: held in a struct, an
Option or a container, captured by a closure, stored in a global or
returned from a function
([`docs/MEMORY.md` §6.2 and §2.10](MEMORY.md)).

### 9.12 A raw string in a value is a view

A raw string (`s`) held by a struct, an option, an enum, a slice or a
container owns nothing (§3.3d). In safe code a *fresh* string — the
result of a call that hands its string over (`nurl_str_cat`,
`nurl_str_int`, …) — cannot be stored there, nor handed to a parameter
that keeps it (`vec_push [s]`, `map_set`): hold a `String`, or bind the
string first and store the binding, a view the checker keeps from
outliving it (§9.11). A struct or a closure handed back holding a string
binding that owns its buffer holds a view of it, and is rejected like
any view that outlives its source. A parameter that takes a string over
is declared `sink` ([`docs/MEMORY.md` §2.13](MEMORY.md)).

### 9.13 Frozen `Arc` payloads and thread sharing

An `Arc` freezes its payload once constructed: `arc_get` returns a read-only
borrow, any call that could mutate the payload or a field of it is rejected in
safe code, and `arc_set` is `raw` (`unsafe`-only). The same holds for whatever
a type marked `% Frozen` lends — an `RwLocked` read guard's value
(`rguard_get`), so many readers may hold it at once — and for a struct that
holds an `Arc` or a frozen value. Mutable state shared across threads lives in
a `Locked [T]` (`locked_new`, `locked_update`, `locked_await`), an
`RwLocked [T]` taken for writing (`rw_write`, `wguard_get`), or an `Atomic`
(std/atomic.nu); thread/fiber spawns enforce structural `Send` / `NotSend`
bounds on captures ([`docs/MEMORY.md` §6.5](MEMORY.md)). A thread (or a
fiber) may take a second read guard of an `RwLocked` it already reads; one
that asks for a lock it already holds for writing, or to write one it reads,
panics instead of waiting for itself.

### 9.14 What is NOT checked

The body of an `unsafe` (§3.3d) or `raw` (§3.3e) function: raw pointers,
pointer casts, the raw-memory primitives and foreign calls are its author's
(or, for `raw`, its `unsafe` caller's) to get right. Everything else is held
to the rules above — every program accepted without an `unsafe` function of
its own is memory-safe and leak-free ([`docs/MEMORY.md` §6.2](MEMORY.md)):
the ownership rules of the single-threaded language (`A2.memory_safe`,
`A2.no_leak_end`) are mechanically proven sound in Lean 4
([`formal/`](../formal/)), and every hole found so far (`h01–h940`) is
closed and held by a probe in `tools/fuzz/holes/`; a handle whose copies
are one state is checked where it crosses to another thread
(docs/MEMORY.md §6.5).
The pre-production hardening closed the exception 0.71.0 named: a `Slice`
built from a `Vec` (`slice_from_vec`, `slice_sub`, `slice_window`, protobuf's
`ProtoReader`) is now tracked as a view of it and ends when the `Vec` is
freed or may reallocate ([`docs/MEMORY.md` §2.10](MEMORY.md)).

## 10. Diagnostics

### 10.1 Errors as the API

NURL treats compiler errors and warnings as the primary user interface,
not the spec. The historical "gotchas list" is empty by policy: every
previously-required-memorisation foot-gun is surfaced as a compiler
`error:` or `warning:` with a pointing caret and the concrete cure
inline. The compiler MUST emit ASCII-only diagnostic text (may be
relaxed in a future revision).

### 10.2 Diagnostic shape

Every diagnostic carries:

- A location prefix `file:line:col:`.
- A severity tag — `error:`, `warning:`, or `note:`.
- A message naming the offending construct and pointing at a cure.
- The source line text.
- A caret line pointing at the column.

A check that runs once the whole program has been read — a missing
supertrait impl, a closure that would cross to another thread — has the
same shape: the position was recorded when the construct was scanned, and
the line is re-read from the source being compiled.

Example:

```text
foo.nu:6:3: error: bare identifier 'nurl_print' as a statement has no
                    effect — calls in NURL are written '( name args )',
                    not 'name args'. Did you forget the parens?
  nurl_print `oops`
  ^
```

**Re-parsed contexts.** A diagnostic raised inside a generic
instantiation's body is anchored at the **template's own** `file:line:col`
(the re-lex buffer preserves the template's line structure), and the
message carries a bracketed context suffix naming the instantiation and
its first call site — `[while instantiating 'f__i64' — the error may
depend on the concrete type arguments; first call site: main.nu:12]`.
Trait-method signature and default-body re-parses carry the analogous
suffix naming the method, the trait, and the Self/impl type.

**Multi-error reporting.** One `nurlc` run reports the errors of *every*
failing top-level declaration, not just the first: a diagnostic aborts
only the declaration it fired in, the compiler resynchronises to the
next top-level declaration, and the run ends with an
`error: aborting due to N previous error(s)` summary and a non-zero
exit. Reporting is capped at 20 errors per run (`too many errors`).
Two scopes stay fail-fast (first error exits immediately): the
structural pre-scan passes that run before the main walk, and the
deferred stages after it (generic-instantiation flush). On wasm32-wasi
the resynchronisation mechanism is unavailable (no unwinding), so the
compiler degrades to fail-fast there. Any IR emitted after the first
error is garbage; the non-zero exit makes every caller discard it.

**Internal compiler errors.** If the compiler *itself* panics while
processing a declaration — as opposed to reporting a diagnostic about
the program — it prints an `internal compiler error:` report naming the
panic message, the file and approximate line being processed, and the
compiler version, asks for a bug report, and exits with status 3
(distinct from status 1, a rejected program).

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

This document corresponds to **grammar v2.11** (`unsafe % Send` /
`unsafe % Sync`, §3.3d, and the `v512` lane type, §4.1d; v2.10 foreign-parameter markers
`in` / `sync` / `nocapture`, §7.2, and a foreach over a field, §5.4; v2.9
the `raw` caller-vouched prefix, §3.3e; v2.8 the `unsafe` raw-memory prefix, §3.3d; v2.7 added the `inline` always-inline prefix, §3.3c; v2.6 added the `simd` CPU-dispatch prefix, §3.3b, and the
`v256` lane type; v2.5 the `v128` SIMD lane type, §4.1b; v2.4
`break` / `continue`; v2.3 dynamic trait objects). The authoritative grammar lives in
[`spec/grammar.ebnf`](../spec/grammar.ebnf); changes since v1.x are
tracked in that file's prelude.

A compiler is "v2.11 conformant" if it accepts every program the EBNF
generates and rejects every program the EBNF does not generate, with
the semantics defined here. A program is "v2.11 portable" if it relies
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
- `i` `u` `f` `b` `s` `v` `i8` `i16` `i32` `i64` `u16` `u32` `u64` `f32` —
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
- [`docs/FORMAT.md`](FORMAT.md) — `nurlfmt` rules.
- [`docs/ASYNC.md`](ASYNC.md) — async runtime design.
- [`README.md`](../README.md) — project overview and tutorials.
- [`CHANGELOG.md`](../CHANGELOG.md) — release notes.
