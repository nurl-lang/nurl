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

**Thirty-six defects of one shape are closed: a construct the language
allows, reached by a path that skipped its own check.** Thirteen were found by
sweeping declarations and simple statements; four more by continuing the same
sweep into expression position, trait and impl bodies, match and select arms,
and the block terminators; two more by the token-deletion sweep; six more by
carrying the sweep into the surfaces that were still untouched — the
`$`-import surface, generic instantiation, `%Trait` objects, the
`inout` / `sink` conventions and the `pub` boundary; and **eleven more by
giving the token-deletion sweep a second oracle**, which is the finding
this round would pass on if it could pass on only one.

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

`tools/tests/test_declaration_forms.py` pins the class with one invariant over
**95 forms** in three tables; the corpus pins each fix with its own rejection.
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
after that. (Seed 9 was clean; 10 and 11 had not finished.)

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

## Latest compiler verification

Corpus **1,025 PASS / 19 SKIP** over 1,044 inputs, zero
FAIL/MISSING/ORPHAN. Normal build 58 s; tests 2 m 33 s. The sanitized
corpus reports the same **1,025 PASS / 19 SKIP with zero AddressSanitizer,
UBSan or LSan findings**, zero timeouts and zero compile/link/run failures.
All seven arithmetic methods, all 31 ownership methods, seven
compiler-cleanup methods, two driver-path controls, the WASI IR control,
eleven release-artifact controls and the 20 sanitized LSP tests pass.
`nurlfmt --check` is canonical over 1,810 files; strict-arity (1,408 files),
memgate, dcegate, leakgate (both emission modes), the metamorphic spelling
and trait-order gates, the pinned-download and installer-sync gates, and both
diagnostic gates pass.

The check that matters most for a change that ADDS diagnostics is the tree
sweep, and it is `tools/tree_sweep.sh` now rather than a paragraph: every
tracked first-party `.nu` file — **1,790 of them**, the whole tracked
inventory minus `bench/` — compiled with the branch-point compiler and with
this one produces identical output and exit codes, and identical IR in all
but the three files named below. The corpus
cannot see code it does not contain; the tree can. (The earlier rounds
reported 816; that was a hand-assembled subset, not a smaller tree.)

**Twenty-one** of the new `test_declaration_forms.py` rows FAIL against a
compiler built from the branch point and pass against this one. Of the 33 new
corpus fixtures, **20 are controls**: the branch-point compiler does not
reject them. Eight it accepts outright and emits IR clang is happy with — the
check was simply missing — and twelve it exits 0 on while emitting IR clang
refuses. The remaining 13 are rejected by both, because they pin the WORDING
of diagnostics that already existed and that no test made the compiler print.

Three of the fifteen are wrong at RUN time, not just in the IR:
`diag_default_on_inout.nu` compiles cleanly on the branch-point compiler,
links cleanly and segfaults; `diag_call_names_a_value.nu` does the same,
calling a data global; `diag_default_arg_type.nu` compiles cleanly and prints
`x = 0` for a parameter whose declared default is 1. A fourth,
`foreach_exit_live.nu`, is ordinary code that the branch-point compiler
cannot compile at all.

The tree sweep reports **three** intended differences against the branch
point, all of them IR-only with identical exit codes and stderr:
`compiler/tests/dead_store_both_arms_ret.nu`,
`compiler/tests/should_warn_caret_xor.nu` and `nurlapi/main.nu` each move one
dead store out of a block that had already terminated and into the `dead_N:`
block that follows it. The other **1,787** files are byte-identical.

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
   conventions and the `pub` boundary are done — **126 forms** across four
   tables in `test_declaration_forms.py`. Extend those tables rather than
   writing a second harness.

   Not done: the `&`-FFI surface (variadic `...`, a parameter with no name,
   a library name that is not a library, the same symbol declared twice with
   different signatures), the `!T E` result and `?T` option surfaces
   (try-propagation across a type the callee does not declare), the `#` cast
   surface, `select` / channel typing, and `Send`/`Sync` marker derivation.

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
   **Seeds 1-8 are clean** against the repaired compiler; seed 9 onwards is
   where the next one is. Four seeds in parallel is comfortable on eight
   cores and finishes inside two hours.

   **`--clang` is a second oracle over the same mutants, and it is where the
   yield is.** "Exit 0 and `main` is there" is a weak invariant: most of what
   this round found KEEPS main. `--clang` asks, of every mutant that exits 0,
   whether clang accepts the module. Seeds 1-8 under the weak invariant alone
   were clean; under `--clang`, twelve seeds produced **515 findings and
   eleven root causes** (see "The second oracle" above). Every wave was run
   against the compiler the previous wave's fixes had already repaired and
   every wave but one still found its own. The yield may be falling off —
   seed 9 was clean and seed 12 gave one — but seeds 10 and 11 had not
   finished when this was written, so that is a hint, not a measurement.
   **Finish 10 and 11, then seed 13 onwards.**

   Recheck from the REPOSITORY ROOT. A mutant that cannot resolve its
   `$`-imports exits 1, and a harness that reads exit 1 as "rejected" counts
   it as answered; that mistake hid three live findings twice in this round
   before the third attempt caught them.

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

   The previous round's remote results, unchanged: every check passed at
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
- `python3 tools/tests/test_declaration_forms.py` — 126 declaration,
  statement, match-arm and import forms against one invariant; needs only
  `build/nurlc`, under 0.4 s.
- `python3 tools/tests/test_release_artifacts.py` — eleven controls over the
  release artifact-set gate; needs no toolchain at all.
- `python3 tools/tests/test_installer_unpack.py` — six controls over the
  staged unpack; serves a release over `file://`, no network, no toolchain.
- `python3 tools/check_pinned_downloads.py` and `./tools/check_installer_sync.sh`
  — the workflow and served-installer gates; both need no toolchain.
- `./compiler/tests/nurlfmt_check.sh` and `./tools/check_strict_arity.sh`.
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
