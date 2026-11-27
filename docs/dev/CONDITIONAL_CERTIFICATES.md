# Conditional certificates

Status: **step 1 proved** (AGORA-1015, M2 part 2; spec.program-cert §4,
spec.program-cert.2 §6 M2): `formal/C/Complete.lean` (phase C15) proves
the transfer, the decided verdict `certOK2BA` and the three conditional
claims on the standard axioms, with a witness that their hypotheses hold
for a real program. Steps 2–4 (the translator, `elabIR`, the bundle) are
next. Part 1 gives every function its own coverage
status. This note decides the form of the theorem for a program that has
functions the translation does not cover. Today such a program has no
proved claim at all.

## The problem

`certOK2B P s nv` decides `ProgOK P ∧ ProgCodes P` and the entry
statement, and `cert_safe` / `cert_leak_end` / `cert_leak_panic` turn it
into the claims about `Steps P`. `P` must be the whole program: every
function's body is in it, and the claims are about runs of exactly those
bodies. A function the translation does not cover has no body in `P`.

The spec asks for `theorem m_safe (h : ∀ f ∈ assumedFns, FnOK P f) : …`.
The question is what `P` is in that statement. It cannot hold the real
body of an assumed function, because that body is not translated. And a
placeholder body would make the theorem about another program.

## What a function's typing reads of the others

`FnOK P fn` (A2/Invariant.lean) checks `fn.body` with `StmtT P`. Of the
other functions of `P`, the typing reads:

1. **Signatures**: `params`, `resTy`, `resOwn`, `lends`, `rholds`,
   `outHolds` and `recvMode`, through `P[g]?` (`CallT`, `Implements`,
   `DtorOK`, `StmtT.letrec`, `StmtT.callc`).
2. **`ThruFn P g`**: g changes a `Vec`'s elements through a borrow, by
   itself or through a callee. This is defined over bodies
   (`Stmt.hasThru`, `Stmt.calls`). The typing reads it with both
   polarities: `¬ ThruFn P σ` is a premise (`StmtT.callc`, `CallThruOK`),
   `ThruFn P f → t.holdsView = false` is a constraint (`DtorOK`, the glue
   predicates), and `Implements` asks `ThruFn P f → ThruFn P σ`.
   `CallThruOK` also reads a callee's **call list** directly
   (`∀ g ∈ fn.body.calls, ¬ ThruFn P g`).
3. **Glue bodies**: `GlueOK`, `EnumGlueOK`, `ImplGlueOK` and
   `ClosureGlueOK` pin the exact body of the drop glue `f` (nurlc's
   generated functions), and `DtorParamsOK` reads `EnumGlueOK P f u` for
   the function itself.
4. **Its own body only**: `ProgCodes` (`fn.body.codesOK P`), whose
   `rhsCodeB` reads `Implements` (1 and 2 again).

Nothing else of another function's body is read. Per function, a program
is checked against the *summaries* of the others. Such a summary is the
signature, the functions the body calls (`Stmt.calls`, as a set), and
whether it changes elements through a borrow itself (`Stmt.hasThru`). All
of these are syntactic: the core IR gives them without translating the
body. Glues are the exception: there the body is the summary.

## The theorem: over every completion

Let `A` be the indices of the assumed functions. `P` holds, at each
index in `A`, a **stub**: that function's signature, with a body of the
shape `.seq s .panic`, where `s` calls exactly the real body's callees and
changes through a borrow exactly when the real body does. The stub is
never typed: only its `calls` and `hasThru` are read. A program `P'`
**completes** `P` at `A` (`Completes A P P'`) when:

- `P'.length = P.length`;
- `P'[i] = P[i]` for every `i ∉ A`;
- for every `i ∈ A`: `(P'[i]).sig = (P[i]).sig` (everything but `body`
  and `nvars`), the two bodies call the same functions
  (`∀ g, g ∈ calls ↔ g ∈ calls'`), and `hasThru` agrees.

Then `∀ g, ThruFn P' g ↔ ThruFn P g` is a **lemma**, by induction over
`ThruFn`: the only body facts it reads are the ones `Completes` keeps.
It is not a hypothesis.

The certificate's claims become:

```lean
theorem m_safe :
    ∀ P', Completes A P P' → AssumedOK A P' →
      ∀ m' s', Steps P' (emptyMem nv) entry (.ok m' s') → ¬ Stuck P' m' s'
```

with `AssumedOK A P' := ∀ i ∈ A, ∃ fn, P'[i]? = some fn ∧ FnOK P' fn ∧
fn.body.codesOK P'`. `m_leak` takes the same form. In words: *whatever the
assumed functions' bodies are, if each one calls the functions the core
IR says it calls, changes elements through a borrow exactly when the core
IR says so, and is well-typed against its signature, then the whole
program is memory-safe and frees everything it allocates.* The real program is one such `P'`. The hypotheses are exactly
the ledger rows "f follows its summary", one per assumed function.

When `A = []`, `Completes [] P P'` forces `P' = P` and `AssumedOK` is
trivial, so the theorem is today's. This is the strongest form: no claim
gets weaker for a fully covered program.

### What the checker decides

`certOK2BA P A s nv` is `certOK2B`, with `fnOK2B`/`stmtCodesB` skipped at
the indices in `A`. It also adds these checks:

- every `i ∈ A` holds a stub: its body is `.seq _ .panic`.

No glue predicate can name a function in `A`. Each glue predicate pins its
function's body to one shape (`.unpair`, `.ite (.isl 0)`, `.letd`,
`.callcE`), and a stub is a `.seq`, so a glue predicate that holds over
`P` names a function outside `A`, whose body `P'` keeps. The proof reads
this off the shapes and needs no extra check.

### The proof obligation: transfer

The one new lemma family is **transfer**: typing over `P` is typing over
any completion.

```lean
theorem StmtT.complete (hc : Completes A P P') :
    StmtT P ξ Γ F s Δ → StmtT P' ξ Γ F s Δ
```

The proof goes by induction over `StmtT`. Each rule's premises reach
other functions only through items 1–3 above:

- signatures are equal by `Completes`;
- `ThruFn` is equal by the lemma above, and a callee's call list by
  `Completes`;
- a glue predicate on `P` names a function outside `A` (its shape is not
  a stub's), whose body is unchanged.

Then `FnOK P fn → FnOK P' fn` and `codesOK P → codesOK P'` hold for
`fn ∉ A`. With `AssumedOK` for `A`, this gives `ProgOK P' ∧ ProgCodes P'`.
A2's theorems apply to `P'` as they do to `P`. `StmtT` has 32 rules. 25 of them take no premise about `P` beyond
`CallT`, `TakeOK`, `LetdFn` and `DropFnOK`, each with its own transfer
lemma, and one tactic line per rule closes them. That line names the rule:
`constructor` would pick `StmtT.sub`, which matches every statement. The
other seven bind the callee itself (`letcall`'s destructor clause,
`letrec`, `callc`, `callcE`) or a glue predicate under an existential
(`unpair`, `letd`, `scopeD`), and are written out. No premise quantifies
over `P` itself.

A3 (threads) takes the same form over `certOK3B`: `spawns` are indices
too, and a spawned function in `A` is assumed like any other.

### The term, and the kernel's view of it

`Cert.elab` proves `elabIR ir = some (P, entry)`. With stubs, `elabIR`
takes `A` as input (a list of names, in the words). For a function named
in `A` it builds the stub from the function's `fn`, `v` and `sum` lines
and reads none of its statements. `A` itself comes from the untrusted
translator, which is sound: a larger `A` only adds hypotheses, and every
name in it is in the manifest and the ledger. A name in `A` that is not a
function fails the elaboration. The kernel never takes an unsupported
function's statements on trust, because it never reads them.

## The certificate

- Each assumed function gets a ledger row `assumed-fn:<name>`. The row
  says what is assumed (it is well-typed against its signature, and its
  `ThruFn` bit is the summary's), why (the reason from part 1), and where
  (`file:line`). The claims rest on it, and their premises list it.
- `M.safe` and `M.leak` are `assumed`: kernel-proved, under the named
  hypotheses. `coverage.functions` keeps `unsupported` for the functions
  in `A`. A function outside `A` gets the claims' status, `proved` per
  function once the hypotheses are only about others. The table of
  part 1 counts them so.
- The review document's first screen says: "proved, assuming N functions
  follow their summaries", with the N listed.

## Alternatives considered

- **A placeholder body in `P`, claims about `P`**: rejected. That
  theorem is about another program.
- **An opaque call construct in A2** (a statement that does anything a
  summary allows): it would need a new step rule and its cases in every
  A2 proof (Preservation, Progress, Leak, Panic, A3). The completion form
  needs no change to the calculus, only the transfer lemma about typing.
- **Hypothesis `FnOK P f` on the stub**: vacuous. The stub is never the
  real body, so this says nothing about the real function.
- **`ThruFn` equality as a hypothesis**: it would hold, but it is a fact
  about the whole program that nobody can check by looking at one
  function. Calls and `hasThru` per function are syntactic, and the core
  IR gives them.

## Order of work

1. `Completes`, `AssumedOK`, `certOK2BA` and its soundness, with
   `StmtT.complete` and its corollaries (formal/C/CertA.lean). No change
   to A2's statements or proofs. `formal/check.sh` must stay at rc 0 with
   no new axiom.
2. The translator emits stubs for the functions in `A` (the
   `Program.lean` grammar takes `def assumed : List Nat`), and
   Claims.lean's template for `A ≠ []`.
3. `elabIR` builds stubs for the names in `A`, so `Cert.elab` covers
   conditional bundles too.
4. Manifest, ledger, coverage statuses, verify, and the selftest. The
   tamper cases are: a name dropped from `A`, a stub body changed, and a
   `ThruFn` bit flipped.
