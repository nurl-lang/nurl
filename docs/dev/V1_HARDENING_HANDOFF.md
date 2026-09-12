# v1 hardening continuation

The complete scope and evidence requirements are in
[V1_HARDENING.md](V1_HARDENING.md). The external LLM-written audit supplies
hypotheses, not authority. No item below certifies the whole language or
ecosystem, and passing a narrow check does not establish a broad guarantee.

## Current implementation

The compiler's stable address graph tracks returned, stored, captured and
unverified-call origins. Dynamic return proofs survive forward/indirect calls,
bound returns and defer/cleanup; the runtime proof channel is thread-local.
Original result proofs and selected cleanup owners use separate slots, and
return-site transfers preserve cleanup on other paths.

The temporary-consumer helper whitelist is removed. Source functions use
inferred effects regardless of result type. Audited primitive effects come
from their actual LLVM declarations; unknown foreign/indirect calls retain
arguments conservatively, including addresses cast to integers. Readonly
foreign return aliases remain tracked. Same-named NURL definitions do not
inherit primitive contracts. See the contract boundary in
[compiler memory discipline](COMPILER_INTERNALS.md#4-memory-discipline).
A mutable string initialized from a proved owned local receives its own copy,
repairing the compiler's lint cursor leak while preserving borrowed-parameter
and opaque-address identity. All 20 LSP tests now enable LSan in CI.

Source arithmetic guards integer zero division/remainder, signed MIN/-1,
dynamic invalid shifts and out-of-range/NaN/infinite float-to-integer casts
before LLVM undefined behavior or poison. Scalar and aggregate-field casts
share unsignedness, bounds and bool rejection. Fractional values that truncate
into range remain valid; IEEE floating arithmetic is unchanged. The
differential fuzzer reaches those guards: half of its divisors and shift
amounts are computed sub-expressions clamped into the legal domain rather than
literals, so the guard branch is live at -O0 and the oracle catches a guard
that fires on a legal operand.

**Forty-five defects of one shape are closed: a construct the language
allows, reached by a path that skipped its own check.** Thirteen were found by
sweeping declarations and simple statements; four more by continuing the same
sweep into expression position, trait and impl bodies, match and select arms,
and the block terminators; two more by the token-deletion sweep; six more by
carrying the sweep into the surfaces that were still untouched — the
`$`-import surface, generic instantiation, `%Trait` objects, the
`inout` / `sink` conventions and the `pub` boundary; **eleven more by
giving the token-deletion sweep a second oracle**, which is the finding
this round would pass on if it could pass on only one; and **nine more from
the last five surfaces item 1 had left** — the `&`-FFI surface, `\`
try-propagation, the `?T` / `!T E` match, the `#` cast target, a select
arm's diagnostics and an aggregate bound to a pointer (see "The last five
surfaces" below).

Ten in the parser — a binding initialised by a block, a global constant with
no value, a struct or generic function with no body, an unclosed type-parameter
list, a `:` followed by junk, a function whose body is empty, two parameters
sharing a name, a match with no arms, and a foreach over something that is not
a slice. Each exited 0 and lost the declaration after it, or emitted IR only
clang rejected — or, in the foreach case, IR with empty types and nothing on
stderr at all.

Three in the type checker. A field WRITE to a name the struct does not have
stored into field 0 and printed `store  5, * %r` with no types; the read side
had rejected the same typo for years, with a comment explaining exactly this
miscompile. And the pre-registered C-runtime surface — `nurl_print` and the
117 others every program calls — was registered with a return type only, so
its call sites had no arity or argument check at all: `( nurl_print 5 )`
compiled and segfaulted dereferencing 5. Those symbols now get the FFI path's
own side-tables, filled by parsing the `declare` lines the compiler already
emits, so there is no second table to drift.

Four more from the continued sweep. `Z NoSuchType` was the one type position
with no declared-type check, and emitted a getelementptr on a type nothing
declares. An or-pattern's ALTERNATIVES were never checked against the enum,
though the first name has been for years — `Red | Nope` emitted a load of a
global nothing defines. `break` and `continue` inside a `;` defer body
branched into a loop exit the defer chain had already left and re-entered the
chain from there, so `; { break }` inside a loop compiled, exited 0 and ran
forever; `^` was already rejected for that exact reason. And an impl was never
checked against the trait it names: a missing required method, a wrong arity,
wrong non-receiver parameter types and a wrong return type all compiled. The
last is a type confusion, not a convenience — `dyn` builds its thunk from the
DECLARED signature, so a trait promising `→ i` implemented with `→ s` hands
the caller a pointer to read as an integer, with no diagnostic anywhere.

Two more came from the token-deletion sweep, and both swallowed a whole
declaration. Deleting one `}` left a trait body unterminated: the method-header
scan advanced to "the first `{`", which is then the NEXT declaration's brace,
so `: Dog { i pitch }` became the method's default body and the trait appeared
to end at some inner `}` — while the emit pass skips BALANCED braces and
therefore consumed to end of file. The two passes disagreed about where the
trait ended and `main` was inside the difference: exit 0, no `main`, nothing
on stderr. Deleting one `{` did the same to a generic template with a trait
bound (`@ ship [T: Send] T v → i`): the collector took tokens "until the next
`{` anywhere", found `@ main → i {`'s brace, and called everything after it
the template's body. Only the BOUNDED form reaches that path, which is why no
hand-written spelling had found it.

Both header scans now stop at the `→` and consume exactly the return type,
and a trait or impl body rejects any token that is neither a method nor an
associated type instead of skipping it — that skip is what made an
unterminated body dangerous, and it was also silently accepting `% Sh { 42 }`
and an impl body full of junk.

`tools/tests/test_declaration_forms.py` pins the class over **208 forms** in
eight tables, under two invariants — a clean exit must keep `main`, and the
IR it emitted must be one clang accepts; the corpus pins each fix with its
own rejection.
Six more from the import / generic / `dyn` / convention / visibility sweep,
and each is the same question answered in one spelling and not the other.

A generic STRUCT applied to the wrong number of type arguments was never
counted, though the generic FUNCTION call path has counted for years
("declares 1 type parameter(s) (T) but this call supplies 2"). Neither
direction was benign: too few left the surplus parameter unsubstituted in the
emitted type (`%P__i64 = type { i64, %V }`), too many mangled the DEFINITION
from the declared parameters and every REFERENCE from all of them
(`%Box__i64` defined, `%Box__i64__f64` referenced). Both exited 0 from every
type position — parameter, field, pointer field, slice element, `Z` — and
were rejected by clang with no NURL location.

`%Name` in a type position never checked that Name is a declared trait.
`parse_type_dyn` runs its object-safety check only when the trait is already
known, so a forward-referenced signature does not fail before its declaration
is scanned — and `check_type_known`, the shared type-position checker, skipped
`%dyn.<Trait>` outright on the claim that parse_type_dyn had validated it.
`Z %NoTrait`, a `%NoTrait` parameter, a `[ %NoTrait` slice and a struct name
written where a trait was meant all exited 0 emitting references to a type the
module never defines. This was the last type position still missing the check
that `Z NoSuchType` closed everywhere else.

A default parameter value was never checked against its parameter on the
POSITIONAL fill path — not the float↔integer law, not pointer-vs-scalar, not
the integer-width coercion. `@ show f x = 1 → v` called `( show )` emitted
`call void @show(i64 1)` against a `double` parameter: the callee read xmm0
and printed 0, a wrong answer with no diagnostic anywhere. The explicit-
argument path has enforced all of it for years and the named-argument path
since the kwargs reorder was brought under the same battery; one helper now
answers for all three spellings.

A default on an `inout` parameter compiled. An inout argument is the ADDRESS
of a mutable binding, so the literal went into the pointer slot —
`call void @bump(i64 1, i64 0)` against `define void @bump(i64, i64*)`, which
clang accepts under opaque pointers and which stores through a null pointer:
a clean compile and a segfault. The grammar names four places a default is
unavailable (generic, FFI, variadic, `inout`/`sink`); the other three already
rejected one at the declaration.

`pub` on a `$` import was read and discarded in silence. The grammar excludes
import_decl from the visibility prefix, and `simd` and `inline` in that exact
position have been diagnostics since v2.6 — but a file enters strict
visibility at its FIRST `pub`, so a file whose only `pub` sat on its import
stayed in legacy mode with every function globally callable, and said nothing
about it. (The import's ALIAS slot took a type keyword too: `$ `lib` i`
silently became an import aliased `i`. It takes a plain identifier now, which
is what `import_decl = '$' STR IDENT?` says.)

A trait method header with no return arrow was accepted at the declaration —
the item the last round found and left open. Every other function header
requires the arrow; a plain `@ f i o { … }` and an IMPL method both say
"expected a type, found '{'". The trait scan recorded a signature with no
return type instead, and nothing read it back unless the program used the
trait as a `dyn` object, which is a use it may never make. It was reported
from the `<dynsig>` re-parse when it was reported at all: a synthetic
location, decorated with the trait and method names because it had no file to
name. It anchors on the method name in the real source now, keeps the
ASCII-arrow hint (`- >` is the cause in almost every case that reaches it),
and the impl-signature check dropped the skip it carried for exactly this
case. `diag_dynsig_context.nu` keeps its subject — a synthetic buffer's error
carrying trait, method and Self — on a witness that still reaches it.

### The second oracle, and the eleven it found

`mutate_delete.py` deletes one token and asks one question: does the compiler
reject the file, or still emit the `main` the source declares? Every defect
the declaration sweep found this round is invisible to that question — they
keep `main` and emit IR only clang rejects, or IR that runs and is wrong. So
the sweep learned a second question, `--clang`: of every mutant that exits 0,
does clang accept the module? A compiler that exits 0 owes valid IR whatever
was deleted.

Twelve seeds, 168 corpus programs, **515 findings** — and eleven root
causes. Each wave was run against the compiler the previous wave's fixes had
already repaired, and each still found its own: seeds 1-4 gave three causes,
seeds 5, 6 and 8 three more, seed 7 four more again, and seed 12 one more
after that. **Seeds 9, 10 and 11 were clean** — the first wave in which most
seeds found nothing.

**A note on how that was measured, because the first two attempts were
wrong.** The recheck — recompile every saved mutant against the repaired
compiler — was run from a scratch directory the first two times, where the
mutants' `$ \`stdlib/...\`` imports did not resolve. Those mutants exited 1,
the harness read that as "rejected", and they were counted as answered. Run
from the repository root, where the imports resolve, three mutants that had
been reported clean were not. A harness that cannot tell "rejected for the
reason under test" from "rejected because it could not find a file" reports
whatever you hoped for; the count below was taken the correct way, and the
two published earlier (497 and 508) were not.

**A call whose callee names a VALUE was emitted as a direct call to it.**
`gen_ident` has carried the taxonomy for years — `__ptr` is a local binding,
`__global` a const or enum variant, `__param` a by-value parameter — and
refuses a name that is none of them rather than emit an undefined `%name` only
clang would catch. `gen_call` had no such guard: `: i a 5` then `( a )` emitted
`call i64 @a()`, a reference to a global nothing defines. The dangerous
spelling is a const: `( MAX )` emits `call i64 @MAX()` against
`@MAX = global i64 10`, which clang ACCEPTS — the global has an address — and
which jumps into the constant at run time. A clean compile, a clean link, and
a segfault. One deleted token produces this shape everywhere, because
`( print_vec a )` minus its callee name is `( a )`, which is why 300 of the
497 mutants were this. The "is this binding callable" test was also too loose
— it accepted any `{`-prefixed type, so a slice or option binding shadowed a
function of the same name; it now asks whether the struct's FIRST field is a
function pointer, at the struct's own nesting depth (a closure may return an
aggregate, and `stdlib/ext/resolver.nu` has one that does).

**Field 0 of an option or result literal is the TAG, and nothing checked it.**
Every payload slot has five separate diagnostics for the ways it can disagree
with its declared type; the tag slot had none, so `@ ?i { 1 3 }` emitted
`insertvalue { i1, i64 } undef, i64 1, 0`. The spelling that reaches it is not
a wrong tag but a MISSING one — `@ ?f { 3 }` shifts every value one slot left,
which is what deleting a single `T` does. The check found a latent bug in the
metamorphic harness on its first run: `tools/metamorph/spellings.py` had a
tagless `@ ?( Rc i ) { r }` in one template.

**A binding whose initialiser TERMINATED left the block without one.**
`: i x ^ a` is legal and deliberately so — the `^`-vs-`^^` warning keeps it
compiling — and the statement's remaining instructions (the store, the drop
bookkeeping) belong in a dead block. `__handle_unreachable_stmt` parks exactly
those, but it runs BETWEEN statements: it caught this when another statement
followed and missed it when the binding was the block's last, leaving a basic
block whose final instruction is a store. clang: `expected instruction opcode`
at the closing brace, no source location. Three tree files' IR moved as a
result — two corpus fixtures that exercise the shape on purpose and
`nurlapi/main.nu` — each moving one dead store from after an `unreachable` to
inside the `dead_N:` block where it belongs, with no behaviour change.

**An operand of a binary operator that produces no value was emitted as an
empty one.** There are three spellings of "no value" and the binary battery
knew two: the literal `v` type, and the `undef` a void-returning call yields
(both learned from earlier arity-cascade hunts). A block that TERMINATES —
`{ ( string_free t ) break }` — hands back no register at all, the empty
string. So `? == 3 { … break } {}`, an `==` one operand short that swallowed
the then-block, emitted `%r8 = icmp eq i64 3,` with nothing after the comma.
Same arity trap, same cure, third spelling.

**An element INDEX was never required to be an integer on the store side.**
The read side has always said so — `. xs 1.5` is "expected a field name or an
index after '.'" — and the five index-store paths never asked, so
`= . xs 1.5 7` emitted `getelementptr i64, i64* %p, double 1.5`. The spelling
that reaches it is a MISSING index: `= . xs 0 1.5` with the `0` deleted
leaves the value standing where the position belongs. The write side of a
check the read side has had for years — this round's signature question,
answered once more.

**A foreach's exit path was not marked live, so an EMPTY basic block was
emitted.** `gen_loop` says the rule at its own exit label — "a loop that CAN
exit resets did_ret: its exit path is live even when the body returned
somewhere" — and a foreach always can, since the check block branches to the
exit the moment the index reaches the length. It did not reset the flag, so a
foreach whose body ends in `break` left `g_did_ret` set and the ENCLOSING
loop believed its own body had terminated and emitted its exit label with no
branch before it. Two labels back to back is an empty basic block, which LLVM
rejects. Same rule, the other loop — and unlike the rest of this section it
needs no mutation to reach: `~ x xs { = s += x break }` as the last statement
of a `~` body is ordinary code, and `compiler/tests/foreach_exit_live.nu`
writes it that way.

Seed 7 added four more, each the same shape one spelling over:

  * **An ENUM literal's field 0 is the variant TAG**, and nothing checked it
    — the exact twin of the option/result tag above, one type constructor
    over. `@ Node { NText ( string_from t ) }` minus the variant name emitted
    `insertvalue %Node zeroinitializer, %String %r1, 0`.
  * **A binary operand that RETURNS** hands back the register the `^`
    returned while the recorded type stays the operator's, so
    `? != ( f x ) { ^ ( string_from … ) }` emitted `icmp ne i64 %r2, %r4`
    with `%r4` a `%String`. The empty-operand rule above catches the `break`
    spelling; this is the `^` one.
  * **A cast's TARGET type** was the last type position with no declared-type
    check. `# * g 1` — a function name where a type belongs, one deleted `u`
    from `# *u g 1` — emitted `inttoptr i64 1 to %g*`.
  * **`~` complementing a void operand.** `~` is a loop and a bitwise
    complement; with the condition deleted the BODY becomes the operand, and
    `~ { }` emitted `xor void undef, -1`. The loop form checks its condition;
    the complement form did not.

Seed 12 added one more, and it is the plainest statement of the round's
question yet. **`String` initialising a raw C-string binding.** `String` is a
managed handle (a by-value `{ ptr }` struct); `s` is a bare `i8*`; nothing
converts between them implicitly. The ARGUMENT path has said so for years
("String vs raw C-string mismatch") and so has the ASSIGNMENT path — whose
own comment calls itself "the store dual of the let-binding / call-arg
checks". The let-binding did not have it: every clause of its never-legal-mix
test wanted one side not to be a pointer, and here both are. `: s raw t`
emitted `store i8* %r4` with `%r4` a `%String`. It calls the same shared
helper now, which is what that comment already claimed.

All 515 findings are answered by the eleven: recompiled against the repaired
compiler from the repository root, **every one of them either fails to
compile or emits IR clang accepts**.

Opening the block-initialiser path also exposed a borrow-checker hole:
`bck_esc_let` recorded a referent depth without comparing it, so a closure over
a block-local `: ~` struct could be bound outside that block.

Two tree gates were checking less than they claimed. The canonical-form gate
named five directories and left 464 first-party files ungated (18 had
drifted); the strict-arity gate named six and left `unikernel/` and
`pttvoice/` out. Both now take the tracked inventory from git. Both were
serial, one process per file, which is what pushed the compiler job past its
15-minute budget into a cancelled run; both now run under `xargs -P`, and the
job finishes in about eleven minutes.

Two more gates were running less than they claimed, and one of them was not
running at all. `tools/check_diag_coverage.sh` asks which of the compiler's
311 `die`/`warn` sites some test actually makes it print — a message nothing
prints is a message nobody has read, and the wording of a diagnostic is most
of its value. It was a by-hand tool, and that is exactly how **fourteen**
diagnostics added in one hardening round reached main with nothing printing
any of them. Sixteen `diag_*` fixtures now pin their wording (coverage 80% →
84%, never-fired 32 → 18); the one gap that remains is unreachable behind its
own lookahead and is baselined as such. The gate was three and a half minutes of
one-process-per-file — the reason it was affordable only by hand — and is
thirty-four seconds under `xargs -P`, which is what lets it and the anchor
gate join CI.

The tree sweep is a script now, `tools/tree_sweep.sh`. It was carried in prose
across three rounds and retyped each time, which is the same failure mode the
canonical-form gate had when it named directories by hand. It takes its
inventory from the BASELINE commit (a file the change ADDS has no baseline
behaviour to preserve) and builds the baseline compiler into a temp directory,
never into `build/` — replacing `build/nurlc` under a running test is one of
the two rules this tree learned the hard way.

The release workflow attached whatever the build jobs produced, by glob, with
only the Linux matrix as a hard gate — a failed Windows leg published a
release with no `.zip`, and the PowerShell one-liner then 404s.
`tools/check_release_artifacts.sh` runs before publication and requires the
documented set, its checksums, and its signatures when signing ran; eleven
controls cover it. The installer now stages its unpack, so a failed extraction
leaves the existing install intact, and every tool a workflow downloads is
pinned by sha256 — including the zig that ships inside the published archive.

### The last five surfaces, and the nine they held

Item 1 named five surfaces the sweep had not reached: the `&`-FFI surface,
`!T E` / `?T` try-propagation, the `#` cast surface, `select` / channel
typing, and `Send`/`Sync` derivation. Working them gave seven of the same
shape, and two more turned up afterwards (below), and it is worth saying
which two surfaces gave nothing: **`select` /
channel typing held up** — a wrong element type, a non-channel scrutinee, an
undeclared channel, a `_`-only select and a mistyped `chan_send` are each
already rejected — and **`Send`/`Sync` derivation held up as derivation**;
what failed there was the marker's SUBJECT, which is a type position, not
the derivation.

**The `...` variadic marker was not required to be last, or to be one.**
The grammar is `ffi_param* ( '...' )? '→' type`. The parameter loop took a
`...` wherever it landed and carried on, and the two consumers of the
parameter list then disagreed about what the declaration said. A parameter
AFTER the marker emitted `declare i64 @xpf(i8*, ..., i64)` and a second
marker emitted `(i8*, ..., ...)`; llvm-as rejects both. A LEADING marker is
worse than either: the first parameter's `pct == 0` branch OVERWRITES the
accumulated string, destroying the marker in the `declare` while
`__variadic_sig` keeps it — so the module declared `@xpf(i8*)` and emitted
`call i64 (...) @xpf(i8* %r1)`, a variadic call against a non-variadic
callee. That one exits 0 and clang accepts it; it is a real ABI difference
on every target that passes variadic arguments differently from fixed ones,
reported by nothing at all.

**A variadic call's FIXED prefix was never counted.** `...` makes the TAIL
optional, never the parameters ahead of it. `gen_ffi_decl` registers no
`__arity` for a variadic symbol — there is no single right count — and the
call-site check was conditioned on `! is_variadic`, so it skipped the
minimum as well. `( xpf )` against `xpf s fmt ... → i` emitted
`call i64 (i8*, ...) @xpf()`: "not enough parameters specified for call".
The count was already recorded, as `__variadic_fixed`, for the
argument-promotion path; nothing had ever asked it this question. The
comment on the non-variadic registration says why that check exists — "a
missing argument read an unset ABI register, silently" — and this is the
same hazard one spelling over.

**An empty FFI library name skipped its gate rather than failing it.** The
library is what turns a missing dev package into a compile error instead of
a link error, through the `stdlib/runtime.<lib>` sentinel; the check ran
under `? > llen 0`, so `& `` @ f …` silently disabled it. The `$` import
surface has rejected an empty path for the same reason.

**`\` in a function whose return type cannot carry the failure.** This is
the round's segfault. The grammar says `\` "immediately returns the same
shape from the enclosing function, propagating the error value unchanged",
and the error-type check beside it (T8) has compared the two error types for
years — but only when the enclosing function returns a Result. When it
returned anything else there was nothing to compare against and nothing said
so, and the fail path fell to the `zeroinitializer` default. That is not
propagation: it discards what the callee reported and hands the caller a
zero of the declared type. For `→ i` that is 0, indistinguishable from a
real answer. For `→ s` it is `ret i8* zeroinitializer`, and printing the
result is a null dereference — a clean compile, a clean link and a
segfault. `stdlib/core/result.nu` already named the alternative in so many
words: at "a site that cannot `\`-propagate (a `→ i` main, a callback with
a fixed signature)", `res_expect` / `res_unwrap` take the payload or PANIC.
The compiler had never enforced the sentence its own stdlib wrote.

Two corpus fixtures were written that way and are now the other spelling —
`routertrap.nu` and `test_06_torture_chamber.nu` (and its copy under
`examples/`), each keeping the `\` it exists to exercise, in a helper whose
return type can carry the failure, with both goldens byte-identical.

**An option and a result are not interchangeable across `\`.** Both shapes
start `{ i1, `, so the check above accepts either; what it cannot see is
that the fail path then zeroes the OTHER shape. An option tried inside a
`!T E` function returns Err with an error payload of 0 that no callee ever
produced — an invented error, which is worse than a dropped one — and a
result tried inside a `?T` function returns None with the Err payload gone.
Both conversions are real and the stdlib spells them (`res_ok`,
`opt_ok_or`); requiring one is what keeps `\` a propagation.

**A non-exhaustive match on `?T` / `!T E` yielded `undef`.** The grammar
states one rule for all three scrutinee kinds, and the enum spelling has
been rejected for years. `check_exhaustive` looks the variants up by enum
NAME in a `__variants` entry only a user enum has, so an option or result
scrutinee fell straight through the loop. The uncovered path reaches the
join as `phi i64 [ %r8, %arm_2 ], [ undef, %next_3 ]`: `?? o { T v → v }`
over a None yields whatever was in the register, not a zero and not the same
value twice.

**`#` between two named struct types was a reinterpret.** Nothing above the
final fallthrough in `gen_cast` converts an aggregate, so that path handed
the operand register back wearing the TARGET's type. For two integer
spellings of one width that is right — the bits are the value. For a named
struct it is not a conversion at all: `ret %Q %r1` with `%r1` a `%Pt`, two
structs of different field counts, and clang answering about generated IR
with no NURL location. The anonymous-aggregate source is diagnosed a few
lines above with the same reasoning and almost the same words; the named one
reached the fallthrough because `%Struct` sources are handled far above ONLY
when the destination is an integer.

**An impl's SUBJECT was the last type position with no declared-type
check** — the hole `Z NoSuchType`, the `#` cast target and `%Trait` each
closed in their own spelling. The marker traits are what make it matter.
`% NotSend Db { }` asserts a danger the structural derivation cannot see (a
`sqlite3*` is an `s`, and `s` is Send); on a MISSPELLED subject it asserted
it about a type that does not exist. Nothing said so, the real `Db` stayed
Send, and it crossed the thread boundary the marker was written to forbid.
A safety assertion that silently does nothing is worse than none, because
the author reads it and stops looking. `check_type_known` is not the
instrument here — it rejects a bare generic TEMPLATE name, and an impl
subject is allowed to be one (`% NotSend Rc { }` covers every `Rc`
monomorph, which is one of `__thr_marked`'s three spellings), so the check
accepts what an impl may name and rejects only a name that is none of them.

Three things were found and deliberately NOT changed, and they share one
cause: **the built-in protocol traits have no declaration.** `% Drop Database
{ }` in `stdlib/ext/sqlite.nu` names a trait that no `% Drop [T] { … }`
declares anywhere, and `Ord` and `Show` are the same. So:

  * **An impl of a trait that is not declared compiles.**
    `check_impl_contract` says why in its own comment — there is no contract
    to check. Closing it means enumerating the built-in set, which is a
    language decision, not a check; and a typo'd trait name is still caught
    downstream when the method is called ("call to unknown function").
  * **A BOUND naming an undeclared trait reports against the type**, not the
    name: `[T: NoSuchMarker]` says "type 'i' does not implement trait
    'NoSuchMarker'", which blames the author's typo on the argument. It is
    rejected, so this is message quality, not a miscompile — but the better
    message needs the same closed set the item above does.
  * **`% Send` / `% Sync` / `% NotSend` / `% NotSync` as BOUNDS** are
    answered by the structural derivation rather than by an impl lookup, so
    they are undeclared traits by design. Any rule about undeclared trait
    names has to exempt them explicitly.

All three are recorded rather than forced, on the same standard as the
unreachable type-parameter diagnostic above. Whoever closes the first closes
all three, and the deliverable is the list of built-in protocol names.

One probe result that is NOT a finding, recorded so it is not re-probed:
declaring the same FFI symbol from two different libraries compiles and the
second library name is dropped. That is correct. The library name's only job
is the build-time sentinel check, `__ffi_lib_check` runs for EVERY `&`
declaration before anything is dropped, and the linker resolves by symbol
name — so both libraries are still checked and the attribution has no effect
on the emitted module. The signature disagreement, which does matter, has
been a diagnostic since the round before.

**Two more, found after the five surfaces were closed.**

**A select arm's diagnostics pointed at generated text.** A select lowers
to a whole program — a poll loop, a shared waiter, one `chan_try_recv` per
arm — which is then re-lexed through a sub-lexer, so every check inside it
reports against THAT text. A mistyped arm element printed
`<select>:4:127` with a caret into a line the author never wrote, naming no
file, no line of real source, and no `??`: which arm of which select was
left entirely to the reader. `<dynsig>`, the compiler's other synthetic
buffer, had the same problem and already had the cure — `g_diag_ctx`, a
suffix appended to every diagnostic raised while the re-parse runs — and
nothing had applied it here. It carries the `??`'s own position, which
`gen_match` has always captured for the borrow checker's structural markers
and now hands to `gen_select`. The synthetic location stays: the caret does
point at the lowered call, and moving it would mean threading a position
through every token of generated text. What was missing was the sentence
telling the reader where to look instead.

`tools/check_diag_anchor.sh` did not see this, and its report says "every
baselined diagnostic points at real code". It asks one question — does the
caret land on a closing delimiter — and a synthetic BUFFER is a different
way to point at nothing. No corpus golden anchored in one before
`diag_select_arm_context.nu`, which is why it had never come up. Extending
the gate to ask about synthetic buffers is the obvious next step and is
left for the next round, with the `<dynsig>` case as its known-good
baseline.

**An aggregate value bound to a pointer binding**, which is the
token-deletion sweep paying out again: seed 14, `mut_pointer.nu`, one
deleted `*`. `# *Node x` minus its star is `# Node x`, a legal cast
producing a `%Node` VALUE, while the binding still says `*Node` — so the
store was `store %Node* %r1, %Node** %r2` with `%r1` a `%Node`. Exit 0,
and clang's "'%r1' defined with type '%Node' but expected 'ptr'" the only
report. The binding's never-legal-mix battery has six clauses and this fell
through all six: the integer clause knows only INTEGERS into a pointer, the
nominal clause requires NEITHER side to be a pointer, the pointer clause
runs the other direction, and the aggregate clauses all want a scalar or
aggregate TARGET. It is the exact mirror of the String-vs-raw-C-string
clause added the round before — that one existed because every other clause
wanted one side not to be a pointer; this one because they wanted the
other side not to be. All three aggregate shapes reached it (a named
struct or enum, an anonymous option or result, and a slice), so the clause
asks about the shape rather than the name. The two mutants that found it
are rejected by the repaired compiler.

**A methodology finding, which is the one to carry forward.** The first
version of this round's probe asked clang the question with
`clang -fsyntax-only -x ir`. **That does not parse the IR.** It exits 0 on a
module `llvm-as` rejects outright, and it reported every form in this
section clean. `tools/fuzz/mutate_delete.py` uses `clang -c`, which does
parse, so the published seed results are unaffected — but a hand-written
probe is written fresh each time, and this is the second round in a row
whose first measurement was wrong in the same direction: a harness that
cannot fail reports whatever you hoped for. `test_declaration_forms.py` now
asks the clang question itself, with `clang -c` and a comment saying why,
so the table sees the class of defect that keeps `main`. None of this
round's seven is visible to the old invariant.


## Latest compiler verification

Corpus **1,035 PASS / 19 SKIP** over 1,054 inputs, zero
FAIL/MISSING/ORPHAN. Normal build 1 m 06 s (with `--refresh-bootstrap`);
tests 3 m 15 s. The sanitized corpus reports the same **1,035 PASS / 19 SKIP
with zero AddressSanitizer, UBSan or LSan findings**, zero timeouts and zero
compile/link/run failures.
All seven arithmetic methods, all 31 ownership methods, seven
compiler-cleanup methods, two driver-path controls, the WASI IR control,
eleven release-artifact controls, six installer-unpack controls and the 20
sanitized LSP tests pass.
`nurlfmt --check` is canonical over 1,823 files; strict-arity (1,409 files),
memgate, dcegate, leakgate (both emission modes), the metamorphic spelling
(0 gaps) and trait-order (200/200) gates, the pinned-download and
installer-sync gates, and both diagnostic gates pass. Diagnostic coverage is
84% of **327** sites with **18** never-fired — unchanged from the previous
round's 18, so every diagnostic this round added is printed by a test.

The check that matters most for a change that ADDS diagnostics is the tree
sweep, and it is `tools/tree_sweep.sh` now rather than a paragraph: every
tracked first-party `.nu` file — **1,823 of them**, the whole tracked
inventory minus `bench/` — compiled with the branch-point compiler and with
this one produces **byte-identical output, exit codes and IR, with zero
differences**. Nine new rejections, and nothing in the tree was written in
any of the nine ways. The corpus cannot see code it does not contain; the
tree can. (The earlier rounds reported 816; that was a hand-assembled
subset, not a smaller tree.)

**Twenty** of the new `test_declaration_forms.py` rows FAIL against a
compiler built from the branch point and pass against this one, and every one
of the 188 rows the previous rounds left still passes on both — the new clang
invariant did not retroactively condemn anything.

Of the **ten** new corpus fixtures, **nine are controls**: the branch-point
compiler rejects none of them. Four it exits 0 on while emitting IR clang
refuses (`diag_ffi_ellipsis_not_last`, `diag_ffi_variadic_missing_fixed`,
`diag_cast_between_structs`, `diag_aggregate_into_pointer`); the other five
it accepts outright, emitting IR clang is happy with — the check was simply
missing. The tenth, `diag_select_arm_context.nu`, is rejected by both,
because what changed there is the WORDING: the branch-point compiler says
the same thing about `<select>:4:127` and names no file, no line of real
source and no `??`.

Four of the five it accepts are wrong at RUN time, not just in principle.
Built with the branch-point compiler: `diag_try_in_plain_return.nu` compiles
cleanly, links cleanly and **segfaults** — `\` in a `→ s` function returned
`ret i8* zeroinitializer` and printing it dereferenced null.
`diag_try_option_in_result_fn.nu` exits 0 carrying an Err payload of 0 that
no callee produced. `diag_match_option_nonexhaustive.nu` prints whatever the
`undef` in the join phi happened to be. And
`diag_marker_impl_unknown_type.nu` ships a `% NotSend` type across the Send
bound that marker was written to forbid, silently, because the marker named
a type that does not exist.

**How that baseline was built, because the first attempt was wrong again.**
`tools/tree_sweep.sh` links its baseline compiler against the working tree's
`stdlib/runtime.o`, and a `./build.sh --san` run replaces that file with an
AddressSanitizer-instrumented one. A baseline built while the sanitized
corpus was running did not link at all, and the harness read the missing
binary's exit 127 as "the baseline rejects this" — the same failure as the
`$`-import trap of the previous round, in a third spelling. Two stale sweep
workdirs then disagreed with each other, which is what surfaced it. The
numbers above were taken against a baseline built from
`git show <branch point>:compiler/nurlc.nu`, with `stdlib/runtime.o` in its
normal state, and cross-checked against a clean `./build.sh` of the branch
point in a separate worktree; both agree. The scare it caused was worth one
check: main's `nurlc.nu` compiled by the branch-point bootstrap and by this
branch's bootstrap is **byte-identical IR**, so nothing here changed how the
compiler compiles itself.

The tree sweep reports **zero** differences against the branch point:
all **1,823** tracked first-party `.nu` files produce identical output, exit
codes and IR under both compilers. Nine new rejections, and nothing in the
tree was written in any of the nine ways. (Three files did differ on the
first run, and all three were the same fixture: `routertrap.nu` and
`test_06_torture_chamber.nu` used `\` inside `@ main → i`, and the second
has a byte-identical copy under `examples/`. Each keeps the `\` it exists
to exercise, moved into a helper whose return type can carry the failure;
both goldens are unchanged.)

The token-deletion sweep is clean through **seed 8**: seeds 5, 6, 7 and 8 —
160 corpus programs, tens of thousands of mutants — produced no finding
against the repaired compiler.

## Next work

1. **Continue the same sweep.** Take a construct the grammar allows, write it
   in a spelling nothing in the tree uses, and check the implementation
   against `spec/grammar.ebnf`. Declarations, simple statements, expression
   position, trait/impl bodies, match and select arms, the block terminators,
   the `$`-import surface, generic instantiation (call site AND type
   position), `dyn` construction and object safety, the `inout` / `sink`
   conventions, the `pub` boundary, the `&`-FFI surface (declaration AND
   call site), `\` try-propagation, the `?T` / `!T E` literal and match
   surfaces, the `#` cast target, `select` / channel typing and the
   `Send`/`Sync` marker subjects are done — **208 forms** across eight
   tables in `test_declaration_forms.py`, which now asks the clang question
   of everything that compiles. Extend those tables rather than writing a
   second harness.

   **Every surface the last round listed as not done is now done**, and two
   of the five gave nothing: `select` / channel typing and the `Send`/`Sync`
   derivation itself both held up (what failed in the second was the
   marker's SUBJECT, a type position). The remaining unswept surfaces are
   smaller and were never on a list: `%`-trait DECLARATION bodies
   (supertraits, associated types, defaults), the `simd` / `inline`
   prefixes, `Z`-sizeof over compound types, string and char literal
   escapes, and the `--strict-borrowck` / `--raw` mode boundaries. None has
   the shape of the ones above — they are not "one spelling of a check that
   exists elsewhere" — so expect a lower yield and say so if it is lower.

   The three questions that found the most, in order of yield:
   *what does this construct do in a spelling nothing in the tree uses*;
   *does the WRITE side of a check exist as well as the read side*; and the
   one this round added — *this value reaches the same place a written
   argument does, so does it go through the same checks?* A default value, a
   substituted type argument and a synthesised signature are all values that
   arrive by a side door, and every one of them had a door with no guard.

2. **The trait-method-header hole is closed** (it was this list's item 2).
   The decision the fixture needed: `diag_dynsig_context.nu` keeps its
   subject — an error from a synthetic buffer carrying trait, method and Self
   — on a witness that still reaches it (a literal where a parameter type
   belongs), and the ASCII-arrow spelling moved to
   `diag_trait_method_no_arrow.nu` at the declaration, where it anchors on
   the method name in a real file. The impl-signature check dropped its
   matching skip.

   One diagnostic in the compiler is now known-unreachable and baselined as
   such: "the type parameters of `@ [ … ]` are never closed". Reaching that
   branch requires the signature pre-pass to have recognised a template, and
   it recognises one by looking ahead for the very `]` the message says is
   missing. Making it reachable means broadening that lookahead, which
   collides with slice-typed parameters (`[ i xs`) — a real behaviour change
   for a message, so it is recorded rather than forced. The `:` side of the
   same rule has no lookahead and does fire
   (`diag_generic_struct_tparams_unclosed.nu`).

3. **Keep running the token-deletion sweep** (`tools/fuzz/mutate_delete.py`):
   delete one token; the compiler must either reject the file or still emit
   `main`. It found two defects two rounds ago, in constructs no hand-written
   spelling had reached. It is single-threaded per invocation and a large
   corpus program is thousands of compiles, so run several `--seed`s in
   parallel rather than one long `--files` — one 12 KB corpus program is
   several thousand compiles, and a 40-file seed is one to two hours.
   **Seeds 1-12 are clean** against the repaired compiler; **seed 14 found
   one more** (an aggregate value bound to a `*T` binding, from one deleted
   `*` in `mut_pointer.nu` — see "The last five surfaces" above), which is
   now closed, and seeds 13, 15 and 16 were still running when this was
   written. Seed 17 onwards is where the next one is. Four seeds in parallel
   is comfortable on eight cores; do not start a build while they run, but
   note the harness copies `build/nurlc` privately at startup, so a rebuild
   cannot corrupt a seed already in flight — only the seeds you start
   afterwards see the new compiler.

   **`--clang` is a second oracle over the same mutants, and it is where the
   yield is.** "Exit 0 and `main` is there" is a weak invariant: most of what
   this round found KEEPS main. `--clang` asks, of every mutant that exits 0,
   whether clang accepts the module. Seeds 1-8 under the weak invariant alone
   were clean; under `--clang`, twelve seeds produced **515 findings and
   eleven root causes** (see "The second oracle" above). Every wave was run
   against the compiler the previous wave's fixes had already repaired.

   **The yield is falling off but has not stopped, and that is the
   measurement.** Seeds 1-4 gave three causes, 5-8 gave four, 9-12 gave one
   — with 9, 10 and 11 each finding nothing at all across 36 corpus
   programs — and **seed 14 gave one more** after four surfaces of
   hand-written sweeping had already been closed. One root cause per four
   seeds is a low rate and still not zero, and the one it found needed no
   cleverness: a deleted `*`. Keep running it in the background of whatever
   else is being swept; it is no longer the highest-value thing to run, and
   it is the cheapest thing to leave running.

   What "falling off" does NOT mean is that the language is clean. It means
   this oracle, with this mutation, over this corpus, is close to exhausted.
   Deleting one token reaches the shapes a deletion can reach. The surfaces
   named in item 1 (`&`-FFI, `!T E` / `?T` try-propagation, `#` casts,
   `select` / channel typing, `Send`/`Sync` derivation) each got that probe
   in the 2026-09-12 round and gave nine more root causes, so this paragraph
   is now a finished prediction rather than a plan. What made those probes
   work is exactly what the clang oracle taught: **ask a stronger question of
   the programs that already compile.** "Exit 0" was the weak invariant; "clang accepts it" was the
   strong one, and it paid eleven root causes. The next rung is "the program
   RUNS and answers correctly" — a differential or metamorphic oracle over
   mutants that survive both questions. Two of this round's defects
   (`( MAX )` segfaulting, a default of 1 arriving as 0) would have been
   caught only there.

   Recheck from the REPOSITORY ROOT. A mutant that cannot resolve its
   `$`-imports exits 1, and a harness that reads exit 1 as "rejected" counts
   it as answered; that mistake hid three live findings twice in one round
   before the third attempt caught them.

   **That trap has now appeared three rounds running, in three spellings,
   and it is the same trap every time: a harness that cannot distinguish
   "rejected for the reason under test" from "did not run".** The three so
   far are an unresolved `$` import (exit 1), `clang -fsyntax-only -x ir`
   (which exits 0 without parsing the IR at all, so nothing is ever
   rejected), and a baseline compiler that failed to LINK because
   `./build.sh --san` had replaced `stdlib/runtime.o` underneath it (exit
   127, read as a rejection). Before trusting any probe you write, make it
   fail on purpose once and check that it says so — and prefer a harness
   that reports a distinct verdict for "could not run" over one that folds
   it into "rejected". The probe used this round does; see the HARNESS
   verdict in its source.

   One of the six needed no mutation at all: a foreach ending in `break`, as
   the last statement of a `~` body, emits an empty basic block. Ordinary
   code, and nothing in 1,815 tracked files happened to be written that way.
   A mutation oracle is worth running against a tree that passes every gate
   precisely because the tree is a sample, not the language.

   It costs one clang invocation per surviving mutant, so a 40-file seed is
   too big: use `--files 15` and run four seeds in parallel. Triage by root
   cause before reading individual mutants — 300 of the 497 were one defect,
   and the fastest way to see that is to group the clang error lines:
   `grep -o "error: [^(]*" seed.log | sed "s/'[^']*'/'X'/g" | sort | uniq -c`.
   Then, after a fix, recompile every saved mutant against the repaired
   compiler; the count that still emits IR clang rejects is the honest
   measure of what is left.

4. **A01's remaining item is a recorded decision, not pending work.** Lexical
   stack lifetimes: every NURL alloca is entry-hoisted and lives for the whole
   function, so a use-after-scope inside one frame is not a memory error
   today, and the escape that IS a dangling pointer is rejected in every
   spelling tried. Lifetime markers buy detection and stack reuse, not
   correctness, and owe an account of deferred cleanup reaching a slot after
   its lexical block. Reopen it with that trade in hand, or leave it.

   What remains genuinely open in A01 is the leak inventory: 86 of 992 corpus
   programs leak under `LSAN_DETECT_LEAKS=1`, and the ledger attributes them
   to two root causes and one test-side habit rather than 86 defects.
   - **The closure-env class.** A closure RETURNED by a function has no
     owner: the binding path registers an env only for a closure LITERAL
     initialiser. The env pointer is knowable at the binding; what is missing
     is the fresh-vs-alias answer the string path gets from
     `__last_call_ret_owned__`. Registering without it is a double free, so
     this needs a summary bit, not a patch.
   - **The escape-classification class.** A parameter stored into a container
     that dies inside the same callee is classified as escaping, so the
     caller's fresh temporary is never freed by anyone. The whole `fmt` family
     does this, which makes it the idiomatic-printing leak. Fixing it needs
     either a dataflow refinement (a store into a container that provably dies
     before return is not an escape) or a parameter marker asserting
     non-escape the way `sink` asserts consumption — the second is a language
     decision.
   The criterion that separates a compiler defect from a test that simply
   never frees is "can the program free it?", not where the allocation was
   made. Apply it with a control, by writing the same call with the free
   present.

5. **A13's remaining scope.** The fourth strict check (a READ of a maybe-moved
   binding) is a recorded decision not to build: strict mode already reports
   1,070 sites across 553 first-party files, so its own acceptance bar cannot
   be applied, and the walk has no read events at all — it is a new record
   stream out of `gen_ident`, not an `if`. `docs/MEMORY.md` §2.9 now states
   that gap explicitly. Still open: opaque wrappers beyond `Channel`, whether
   the default, strict and raw guarantees agree on everything else, and A16's
   indirect/generic/embedded-origin cleanup counterexamples. Borrowed-initial
   mutable bindings are untouched.

6. **Retain every A01-A17 requirement.** A07 (continuous package/service
   tests) is still only an inventory question, and it sits against the
   standing decision not to wire package tests into compiler CI — that needs
   a direction before work, not after. A09, A14 and A17 are untouched; A14
   additionally requires external validation for the independent cryptographic
   review, which cannot be closed from inside this repo. A15 is closed.

7. **Remote results, and the workflows CI cannot reach.** Two steps were
   added to `ci.yml`'s compiler job this round — the diagnostic-coverage gate
   (~34 s) and the anchor gate (instant). The job was finishing in about
   eleven minutes of a fifteen-minute budget before them, so the margin is
   still there, but it is the number to watch: the last time that budget was
   exceeded, the run was cancelled rather than failed, which reads as
   infrastructure rather than as a gate.

   **This round's remote results: every check passed on PR #1111** — twelve
   pass, one skipping. The Linux compiler job with the bootstrap fixed point
   and corpus, the same on arm64, FreeBSD in a VM, Windows, the
   AddressSanitizer + UBSan job, the unikernel job, the MinGW msvcrt
   cross-link job, required-tool fault injection, the runner fault-injection
   controls, and the three path-classifier jobs. The webdocs job skipped
   (no `webdocs/` change), and the four JavaScript audit/build jobs did not
   run for the same reason — a compiler-only change does not reach them, so
   this round says nothing about those five. The compiler job's fifteen-
   minute budget was not exceeded with the two gates the previous round
   added.

   The round before's remote results, unchanged: every check passed at
   `359ac597` — all seventeen: the Linux compiler job
   with the bootstrap fixed point and corpus (13m28s), the same on arm64,
   FreeBSD in a VM, Windows, the AddressSanitizer + UBSan job (20m22s), the
   unikernel job, the MinGW msvcrt cross-link job, required-tool fault
   injection, the runner fault-injection controls, webdocs and all four
   JavaScript audit/build jobs. `check_pinned_downloads.py` ran there too, and
   the unikernel job's `cloud-hypervisor` fetch printed `/tmp/cloud-hypervisor:
   OK` — one of the new checksums verified on a real runner.

   The honest gap: **only `ci.yml` runs on a pull request.** `release.yml` runs
   on push/dispatch, `fuzz.yml` on a schedule, and all seven bench workflows on
   dispatch only. So the zig, wasmtime and rustup pinning in those nine files
   is verified by inspection and by the gate, not by having run — including
   the release job's zig, which is the one whose bytes ship inside the
   published archive. Dispatch `fuzz.yml` and one bench workflow before
   trusting them, and watch the next release's "Fetch bundled zig backend"
   step for its `OK` line.

## Reproduction

- `NURL_TEST_JOBS=8 ./build.sh --refresh-bootstrap`
- `python3 tools/tests/test_arithmetic_safety.py` — seven methods / three modes.
- `python3 tools/tests/test_string_argument_ownership.py` — 31 methods.
- `python3 tools/tests/test_compiler_cleanup.py` — seven methods / 366 rejection goldens.
- `./tools/memgate.sh` and `./tools/dcegate.sh` — normal build.
- `./build.sh --san --no-tests`, then `NURL_SAN=1 ./tools/nurl-lsp/build.sh`.
- `ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 LSAN_OPTIONS=use_stacks=0 python3 tools/tests/test_lsp_toolchain.py`
- `./tools/leakgate.sh` and `NURL_SAN_JOBS=8 ./compiler/tests/run_san_tests.sh`.
- `python3 tools/tests/test_wasi_ir.py` — isolated shared-rewriter LLVM/leak control.
- `./packages/wasmbuilder/tests/build_test.sh` — require actual Wasmtime execution.
- `python3 tools/tests/test_driver_paths.py` — two real split/path controls.
- `python3 tools/tests/test_declaration_forms.py` — 208 declaration,
  statement, match-arm, import, FFI (declaration and call site), try /
  option / result / cast and impl-subject forms against two invariants:
  a clean exit must keep `main`, AND the IR it emitted must be one clang
  accepts. Needs `build/nurlc` and, for the second question, `clang` —
  which is skipped, not failed, when missing. Under 3 s.
  The clang call is `clang -c`. NOT `clang -fsyntax-only -x ir`, which
  does not parse the IR at all and exits 0 on a module `llvm-as` rejects;
  a probe written that way reported every defect of the 2026-09-12 FFI /
  try / cast round clean.
- `python3 tools/tests/test_release_artifacts.py` — eleven controls over the
  release artifact-set gate; needs no toolchain at all.
- `python3 tools/tests/test_installer_unpack.py` — six controls over the
  staged unpack; serves a release over `file://`, no network, no toolchain.
- `python3 tools/check_pinned_downloads.py` and `./tools/check_installer_sync.sh`
  — the workflow and served-installer gates; both need no toolchain.
- `./compiler/tests/nurlfmt_check.sh` and `./tools/check_strict_arity.sh`.
- `python3 tools/fuzz/probe_forms.py FORMS.py` — the exploratory probe the
  2026-09-12 surface sweep was written with: a list of hand-written source
  forms, each asked both questions (does nurlc reject it; if not, does clang
  accept the IR). Not a gate — it prints verdicts and nothing fails. Once a
  form has an answer worth keeping, move it into
  `tools/tests/test_declaration_forms.py`, which asserts the same two.
  Its HARNESS verdict is the part to keep: a run that could not run (an
  unresolved `$` import, a missing clang) is never reported as a rejection.
- `python3 tools/fuzz/mutate_delete.py --files 40` — the token-deletion sweep.
  Tens of thousands of compiles; a hunting tool, not a gate. Add `--clang` for
  the second oracle (does clang accept what a surviving mutant emitted?) —
  slower per mutant, and the question that sees the defects which keep `main`.
- `./tools/check_diag_coverage.sh` and `./tools/check_diag_anchor.sh` — does
  any test make the compiler print this message, and does it point at real
  code. Both run in CI now; the first is ~34 s with `NURL_CHECK_JOBS`.
- `LSAN_DETECT_LEAKS=1 ./compiler/tests/run_san_tests.sh` — the whole corpus
  with leak detection on, which the default run leaves off.
- `NURL_TEST_PWSH=/absolute/path/to/pwsh python3 tools/tests/test_compiler_runners.py`
- **`./tools/tree_sweep.sh`, for any change that adds a diagnostic.** It
  compiles every tracked first-party `.nu` file with the baseline commit's
  compiler and with `build/nurlc` and diffs the two transcripts. A corpus
  fixture cannot see code it does not contain; 1,790 real files can, and
  byte-identical output is the only evidence that a new rejection rejects
  nothing that was valid. It builds the baseline itself (the baseline
  commit's `compiler/nurlc.nu` through `build/nurlc_lastgood.bin`, linked
  against `stdlib/runtime.o` — which is LLVM bitcode, so the link needs
  `-flto=thin`) into a temp directory, never into `build/`. `--base REF` to
  compare against something other than HEAD, `NURL_SWEEP_JOBS` for
  parallelism, `NURL_SWEEP_OUT` to keep the transcripts.
- Never rebuild shared compiler/runtime outputs while tests consume them; never
  overlap corpus runners using the same verdict directory. Both rules were
  broken in one session: a sweep died when `./build.sh` replaced `build/nurlc`
  underneath it, and a corpus run flaked with "Text file busy" when a second
  build started while the first was alive.
- `python3 tools/gen_globals_map.py` after compiler edits; keep both bootstrap
  snapshots together. Preserve `vec_push_temp_owned`'s golden: `item3`, exit 0.
- Set `DEBUGINFOD_URLS=''` for isolated sanitizer probes to avoid symbol-server
  waits. Use bounded process execution and retain sanitizer errors.
