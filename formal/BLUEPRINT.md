# Visual Blueprint of the Lean 4 Soundness Proof (`formal/`)

> **Interactive Explorer:** You can also explore this proof interactively (with a step-by-step memory & borrow-checker simulator, clickable theorem dependency graph, and searchable soundness-hole corpus) on **[nurl-lang.org/docs/formal-verification](https://nurl-lang.org/docs/formal-verification)**.

* **Toolchain:** `leanprover/lean4:v4.35.0` (zero external dependencies; standard axioms `propext`, `Classical.choice`, `Quot.sound` only; `0` `sorry`s)
* **Phase A3 (Threads & Data-Race Freedom):** **37 modules**, **19,671 lines of Lean 4**, **954 theorems**, **1133 total declarations**
* **Phase A2 (Full Single-Threaded Calculus + Leak Freedom, destructors):** **95 modules**, **89,428 lines of Lean 4**, **3989 theorems**, **5069 total declarations**
* **Phase A1 (Core Calculus):** **22 modules**, **9,571 lines of Lean 4**, **449 theorems**, **613 total declarations**
* **Soundness Corpus (`corpus/map.tsv`):** every hole probe in [`tools/fuzz/holes/`](../tools/fuzz/holes/), with the rule and the proof phase (A1, A2, A3, B) that covers it. The table is generated from the probes' `// map:` lines by `tools/fuzz/holes/map.sh` (build.sh writes it; it is not committed); `tools/fuzz/holes/map.py --counts` gives the totals

---

## 1. For Everyone: What Does the Proof Actually Prove?

In one sentence: **If a safe NURL program passes the ownership and borrow checker (`StmtT`), running it can never read freed memory, free the same memory twice, read through a view whose buffer reallocated, race on shared memory across threads, or leak a single heap allocation — whether the program finishes normally or unwinds from a panic (`A2.memory_safe`, `A2.no_leak_end`, `A2.no_leak_panic`, `A3.claim_full`, `A3.claim_made_full`).**

```mermaid
flowchart TD
  subgraph CompileTime["1. Compile-Time Check (Typing.lean)"]
    Prog["Well-Typed Program<br/>ProgOK P ∧ StmtT P ∅ [] s Δ"]
    Summary["Function Summaries & Borrow Rules<br/>kill, Eff.kills, CallT, CapsOK"]
    Prog --- Summary
  end

  subgraph Runtime["2. Execution from Empty Store (Semantics.lean)"]
    Init["Initial Store: emptyMem nv<br/>inv_empty : Inv (emptyMem nv) ∅ [] s"]
    StepOk["Normal Execution Step<br/>Steps P (emptyMem nv) s (.ok m' s')"]
    StepPanic["Uncaught Panic Path<br/>Steps P (emptyMem nv) s (.panic m')"]
    Init --> StepOk
    Init --> StepPanic
  end

  subgraph CoreEngine["3. Inductive Invariant Engine (Invariant.lean, Preservation.lean, Progress.lean)"]
    Pres["Preservation (A2.preservation)<br/>Every step preserves StmtT + Inv"]
    ProgThm["Progress (A2.progress')<br/>Well-typed + Inv ⇒ s' = .skip ∨ can step"]
    Cover["Ownership Coverage (Covers m')<br/>Every live heap address has 1 owner in spine"]
    Unwind["Panic Unwinding (A2.panic_unwind)<br/>Exiting scopes drops all owned trees"]
  end

  subgraph Crown["4. Crown Theorems (A2/Soundness.lean)"]
    Safe["✓ A2.memory_safe<br/>¬ Stuck P m' s'<br/>(No UAF, double-free, or dangling view)"]
    NoLeakEnd["✓ A2.no_leak_end<br/>s' = .skip ⇒ ∀ i, m'.alloc i = false<br/>(Zero memory leaks on normal exit)"]
    NoLeakPanic["✓ A2.no_leak_panic<br/>∀ i, m'.alloc i = false<br/>(Zero memory leaks on panic)"]
  end

  CompileTime --> Init
  StepOk --> Pres
  Pres --> ProgThm
  Pres --> Cover
  StepPanic --> Unwind
  ProgThm --> Safe
  Cover --> NoLeakEnd
  Unwind --> NoLeakPanic
```

### How the Calculus Models Memory Bugs as `Stuck`
Rather than axiomatizing memory safety after the fact, [`A2/Semantics.lean`](A2/Semantics.lean) requires every memory operation to check validity before stepping:
1. **No Use-After-Free:** Reading or mutating a `Vec` node at address `c` or view buffer `d` requires `m.alloc c = true` / `m.alloc d = true`. If `c` was freed, no `Step` rule applies — the state is `Stuck`.
2. **No Double-Free:** `Frees` requires every freed address to have `alloc c = true` before setting it to `false`, and `HeapOK` proves all owned trees are pairwise disjoint.
3. **No Dangling Views on Reallocation:** `vec_push` allocates a **fresh** buffer address `m.nid` and marks the old buffer `d` as `alloc d = false`. Any surviving `Val.view d off len` pointing to the old buffer `d` would immediately become `Stuck` on read — so `StmtT.push` must prove via `kill .realloc` that no such view is still `live`!
4. **No Memory Leaks:** `Covers m` asserts that every address `i` with `m.alloc i = true` lies inside the tree of some active owner binding in `s.spine`. When the program reaches `.skip` (or unwinds via `panic_unwind`), `s.spine` is empty, forcing `m'.alloc i = false` for every `i`.

---

## 2. The Effect & Invalidation Lattice (`Eff.kills`)

Every mutating operation on a root binding `r` has an effect `e : Eff` ordered by `none < realloc < drop < replace`. The function [`Eff.kills`](A2/Syntax.lean#L125-L135) determines which dependent bindings in context `Γ` are invalidated (`live := false`):

| Operation on `r` | Effect `e : Eff` | Kills `.view` (`Slice` / `s`)? | Kills `.inner` (`vec_at` borrow)? | Kills `.self` (handle borrow)? | Kills `.name b t` (closure capture)? |
|---|---|---|---|---|---|
| Read (`vec_len`, `in` param) | `.none` (rank 0) | No | No | No | No |
| Grow (`vec_push r x`) | `.realloc` (rank 1) | **Yes** (buffer moves) | No (elements stay intact) | Only if `r` holds views (`hv`) | No |
| Pop (`vec_pop r`) | `.drop` (rank 2) | **Yes** | **Yes** (element may drop) | Only if `r` holds views (`hv`) | No |
| Move / `=` / `vec_free` / scope end | `.replace` (rank 3) | **Yes** | **Yes** | **Yes** | **Yes** (at `exitScope`) |

AGORA-374 adds `Kind.innerAt i` (strictly inside element `i`) and `Eff.dropInAt i`
(a change strictly inside element `i`): `.dropInAt i` ends what `.dropIn` ends but
`.innerAt j` for `j ≠ i`; `.realloc` ends `.innerAt` (a push may be an insert's first
step); a reorder asks `NoIdx`. A call's boundary forgets indices (`Kind.coarse`).
`vec_at y n` of an owned `Vec` of `Vec`s may be lent at `.innerAt n` (`RhsT.atIdx`),
and a change through such a borrow is `.dropInAt n` (`Edit.inEff`;
`A2/ElemIdxWitness.lean`).

---

## 3. Theorem Blueprint Graph (Landmark Definitions & Theorems)

```mermaid
flowchart BT
  Ty["Ty, Eff, Kind<br/>(A2/Syntax.lean)"]
  Kills["Eff.kills<br/>(A2/Syntax.lean)"]
  Mem["Mem, Slot, Val<br/>(A2/Syntax.lean)"]
  DropSlot["Frees & DropSlot<br/>(A2/Semantics.lean)"]
  Step["Step, Steps, Stuck<br/>(A2/Semantics.lean)"]
  Kill["kill, exitScope, derive<br/>(A2/Typing.lean)"]
  CallT["CallT & FnOK<br/>(A2/Typing.lean)"]
  StmtT["RhsT & StmtT<br/>(A2/Typing.lean)"]
  HeapOK["HeapOK<br/>(A2/Invariant.lean)"]
  Covers["Covers<br/>(A2/Invariant.lean)"]
  Inv["Inv m Γ F s<br/>(A2/Invariant.lean)"]
  PanicUnwind["panic_unwind<br/>(A2/Panic.lean)"]
  CallCase["callCase & recCase<br/>(A2/CallInv.lean)"]
  CloCase["cloCase & cloProgress<br/>(A2/Closure.lean)"]
  CodesStep["codes_step<br/>(A2/Codes.lean)"]
  Preserve["preserve<br/>(A2/Preservation.lean)"]
  Progress["progress<br/>(A2/Progress.lean)"]
  ReachOk["reach_ok & reach_panic<br/>(A2/Soundness.lean)"]
  MemSafe["★ A2.memory_safe<br/>(A2/Soundness.lean)"]
  NoLeakEnd["★ A2.no_leak_end<br/>(A2/Soundness.lean)"]
  NoLeakPanic["★ A2.no_leak_panic<br/>(A2/Soundness.lean)"]

  Ty --> Kills
  Ty --> Mem
  Mem --> DropSlot
  DropSlot --> Step
  Kills --> Kill
  Kill --> CallT
  CallT --> StmtT
  Mem --> HeapOK
  HeapOK --> Covers
  HeapOK --> Inv
  Covers --> Inv
  StmtT --> Inv
  Covers --> PanicUnwind
  DropSlot --> PanicUnwind
  Inv --> CallCase
  Inv --> CloCase
  CallCase --> Preserve
  CloCase --> Preserve
  Step --> Preserve
  Inv --> Progress
  CloCase --> Progress
  Preserve --> ReachOk
  CodesStep --> ReachOk
  PanicUnwind --> ReachOk
  ReachOk --> MemSafe
  Progress --> MemSafe
  ReachOk --> NoLeakEnd
  Covers --> NoLeakEnd
  ReachOk --> NoLeakPanic
```

---

<!-- BEGIN generated: A2 module DAG (webdocs/scripts/gen-formal-data.mjs) -->
## 4. Phase A2 Module Dependency DAG (95 Modules)

```mermaid
flowchart BT
  ArcDtorWitness["ArcDtorWitness<br/>(304L, 13 thms)"]
  ArcPanicWitness["ArcPanicWitness<br/>(796L, 52 thms)"]
  Basic["Basic<br/>(637L, 48 thms)"]
  Bind["Bind<br/>(188L, 4 thms)"]
  Call["Call<br/>(4760L, 194 thms)"]
  CallInv["CallInv<br/>(994L, 28 thms)"]
  CallMem["CallMem<br/>(1647L, 60 thms)"]
  CapClause["CapClause<br/>(80L, 4 thms)"]
  CapsEval["CapsEval<br/>(278L, 20 thms)"]
  CapsLive["CapsLive<br/>(2015L, 82 thms)"]
  CapsStore["CapsStore<br/>(187L, 18 thms)"]
  Closure["Closure<br/>(3611L, 116 thms)"]
  ClosureDropWitness["ClosureDropWitness<br/>(869L, 51 thms)"]
  ClosureParamViewWitness["ClosureParamViewWitness<br/>(357L, 18 thms)"]
  Codes["Codes<br/>(876L, 43 thms)"]
  Ctx["Ctx<br/>(432L, 42 thms)"]
  DomTy["DomTy<br/>(152L, 14 thms)"]
  DropCode["DropCode<br/>(706L, 15 thms)"]
  DropInWitness["DropInWitness<br/>(69L, 5 thms)"]
  Dtor["Dtor<br/>(1050L, 48 thms)"]
  DtorWitness["DtorWitness<br/>(2674L, 124 thms)"]
  DynCell["DynCell<br/>(444L, 27 thms)"]
  EditB["EditB<br/>(3145L, 85 thms)"]
  EditBV["EditBV<br/>(1404L, 51 thms)"]
  EditBVFnWitness["EditBVFnWitness<br/>(264L, 12 thms)"]
  Elem["Elem<br/>(69L, 1 thms)"]
  ElemIdxWitness["ElemIdxWitness<br/>(78L, 5 thms)"]
  EnvHand["EnvHand<br/>(2975L, 74 thms)"]
  ExitWitness["ExitWitness<br/>(380L, 47 thms)"]
  Frame["Frame<br/>(1980L, 97 thms)"]
  FrameCall["FrameCall<br/>(160L, 10 thms)"]
  FrameClause["FrameClause<br/>(772L, 46 thms)"]
  Fresh["Fresh<br/>(153L, 3 thms)"]
  FreshBase["FreshBase<br/>(447L, 34 thms)"]
  FreshClosureWitness["FreshClosureWitness<br/>(256L, 18 thms)"]
  FreshNestWitness["FreshNestWitness<br/>(399L, 32 thms)"]
  FreshProjWitness["FreshProjWitness<br/>(467L, 36 thms)"]
  FreshSatWitness["FreshSatWitness<br/>(417L, 34 thms)"]
  FreshWitness["FreshWitness<br/>(311L, 19 thms)"]
  HandOver["HandOver<br/>(497L, 30 thms)"]
  Heap["Heap<br/>(211L, 14 thms)"]
  HeldViewThruWitness["HeldViewThruWitness<br/>(200L, 17 thms)"]
  InoutViewArgWitness["InoutViewArgWitness<br/>(409L, 34 thms)"]
  Invariant["Invariant<br/>(3146L, 206 thms)"]
  KillVarsStep["KillVarsStep<br/>(281L, 11 thms)"]
  Layout["Layout<br/>(182L, 12 thms)"]
  Leak["Leak<br/>(677L, 26 thms)"]
  NameWf["NameWf<br/>(1056L, 50 thms)"]
  NoRootb["NoRootb<br/>(53L, 6 thms)"]
  Panic["Panic<br/>(387L, 23 thms)"]
  ParamViewWitness["ParamViewWitness<br/>(457L, 21 thms)"]
  PopWitness["PopWitness<br/>(262L, 13 thms)"]
  Preservation["Preservation<br/>(5439L, 124 thms)"]
  Progress["Progress<br/>(953L, 14 thms)"]
  Reach["Reach<br/>(955L, 53 thms)"]
  Region["Region<br/>(35L, 1 thms)"]
  RegionChangeWitness["RegionChangeWitness<br/>(86L, 5 thms)"]
  RegionMem["RegionMem<br/>(420L, 22 thms)"]
  RegionResWitness["RegionResWitness<br/>(442L, 30 thms)"]
  RegionThruWitness["RegionThruWitness<br/>(113L, 8 thms)"]
  RemoveLoopWitness["RemoveLoopWitness<br/>(252L, 10 thms)"]
  Rename["Rename<br/>(9234L, 371 thms)"]
  Repl["Repl<br/>(387L, 21 thms)"]
  Rhs["Rhs<br/>(3493L, 165 thms)"]
  SelfViewCall["SelfViewCall<br/>(60L, 2 thms)"]
  Semantics["Semantics<br/>(1778L, 13 thms)"]
  Settle["Settle<br/>(213L, 12 thms)"]
  SliceCopyViewWitness["SliceCopyViewWitness<br/>(192L, 11 thms)"]
  Soundness["Soundness<br/>(282L, 17 thms)"]
  SrcKeep["SrcKeep<br/>(564L, 25 thms)"]
  Stability["Stability<br/>(1471L, 99 thms)"]
  StepCaps["StepCaps<br/>(230L, 4 thms)"]
  StepFrame["StepFrame<br/>(417L, 17 thms)"]
  Steps["Steps<br/>(4181L, 125 thms)"]
  StoreViewWitness["StoreViewWitness<br/>(346L, 17 thms)"]
  SubDcKill["SubDcKill<br/>(183L, 9 thms)"]
  Sweep["Sweep<br/>(622L, 67 thms)"]
  SweepD["SweepD<br/>(475L, 39 thms)"]
  Syntax["Syntax<br/>(1508L, 70 thms)"]
  TakeB["TakeB<br/>(350L, 17 thms)"]
  TakeBDWitness["TakeBDWitness<br/>(207L, 4 thms)"]
  TakeBVWitness["TakeBVWitness<br/>(437L, 15 thms)"]
  TakeBWitness["TakeBWitness<br/>(240L, 7 thms)"]
  TakeWitness["TakeWitness<br/>(263L, 21 thms)"]
  ThruClosureWitness["ThruClosureWitness<br/>(443L, 34 thms)"]
  ThruDtorWitness["ThruDtorWitness<br/>(164L, 12 thms)"]
  ThruGlueWitness["ThruGlueWitness<br/>(446L, 26 thms)"]
  ThruLiftKinds["ThruLiftKinds<br/>(96L, 8 thms)"]
  ThruPre["ThruPre<br/>(247L, 25 thms)"]
  Typing["Typing<br/>(2809L, 159 thms)"]
  TypingFacts["TypingFacts<br/>(1156L, 66 thms)"]
  Unfresh["Unfresh<br/>(169L, 15 thms)"]
  UnheldFresh["UnheldFresh<br/>(198L, 16 thms)"]
  Values["Values<br/>(1424L, 77 thms)"]
  Wf["Wf<br/>(1827L, 43 thms)"]
  DtorWitness --> ArcDtorWitness
  Settle --> ArcDtorWitness
  ArcDtorWitness --> ArcPanicWitness
  Invariant --> Basic
  Call --> Bind
  Rename --> Call
  Preservation --> Call
  CallMem --> CallInv
  FrameCall --> CallInv
  KillVarsStep --> CallInv
  SrcKeep --> CallInv
  CapsLive --> CallInv
  Bind --> CallMem
  KillVarsStep --> CapClause
  TakeB --> CapsEval
  CapsStore --> CapsEval
  CapsEval --> CapsLive
  CapClause --> CapsStore
  Basic --> CapsStore
  Steps --> CapsStore
  CallInv --> Closure
  DtorWitness --> ClosureDropWitness
  EnvHand --> ClosureDropWitness
  ParamViewWitness --> ClosureParamViewWitness
  FreshClosureWitness --> ClosureParamViewWitness
  Closure --> Codes
  Repl --> Codes
  Basic --> Ctx
  FreshBase --> Ctx
  Fresh --> DomTy
  DtorWitness --> DropCode
  PopWitness --> DropInWitness
  NoRootb --> Dtor
  Dtor --> DtorWitness
  NoRootb --> DynCell
  TypingFacts --> EditB
  EditB --> EditBV
  TakeBVWitness --> EditBVFnWitness
  EditBV --> Elem
  DropInWitness --> ElemIdxWitness
  Codes --> EnvHand
  SrcKeep --> EnvHand
  Soundness --> ExitWitness
  Values --> Frame
  FrameClause --> FrameCall
  CallMem --> FrameCall
  CapsLive --> FrameClause
  CapClause --> FrameClause
  NameWf --> Fresh
  Basic --> FreshBase
  FreshWitness --> FreshClosureWitness
  FreshProjWitness --> FreshNestWitness
  InoutViewArgWitness --> FreshProjWitness
  FreshNestWitness --> FreshSatWitness
  UnheldFresh --> FreshSatWitness
  ThruDtorWitness --> FreshWitness
  DynCell --> HandOver
  Stability --> Heap
  Closure --> HeldViewThruWitness
  ThruPre --> HeldViewThruWitness
  FreshWitness --> InoutViewArgWitness
  TakeWitness --> InoutViewArgWitness
  Typing --> Invariant
  Invariant --> KillVarsStep
  Basic --> Layout
  Steps --> Leak
  Wf --> NameWf
  Soundness --> NoRootb
  Leak --> Panic
  StoreViewWitness --> ParamViewWitness
  DynCell --> PopWitness
  TakeB --> Preservation
  StepCaps --> Preservation
  CapsLive --> Preservation
  FrameClause --> Preservation
  Preservation --> Progress
  Codes --> Reach
  SweepD --> Reach
  Typing --> Region
  HeldViewThruWitness --> RegionChangeWitness
  ThruPre --> RegionMem
  Closure --> RegionResWitness
  Closure --> RegionThruWitness
  PopWitness --> RemoveLoopWitness
  NameWf --> Rename
  Fresh --> Rename
  DomTy --> Rename
  Stability --> Repl
  Frame --> Rhs
  Typing --> SelfViewCall
  Syntax --> Semantics
  Soundness --> Settle
  Closure --> SliceCopyViewWitness
  Codes --> Soundness
  SrcKeep --> Soundness
  EnvHand --> Soundness
  Call --> SrcKeep
  Fresh --> SrcKeep
  Ctx --> Stability
  CapsEval --> StepCaps
  Panic --> StepFrame
  Rhs --> Steps
  SweepD --> Steps
  FreshWitness --> StoreViewWitness
  EditBVFnWitness --> StoreViewWitness
  RegionMem --> SubDcKill
  Heap --> Sweep
  Rhs --> SweepD
  Elem --> TakeB
  DtorWitness --> TakeBDWitness
  TakeBWitness --> TakeBDWitness
  TakeBWitness --> TakeBVWitness
  PopWitness --> TakeBWitness
  Soundness --> TakeWitness
  ClosureDropWitness --> ThruClosureWitness
  DtorWitness --> ThruDtorWitness
  ThruClosureWitness --> ThruDtorWitness
  DtorWitness --> ThruGlueWitness
  ThruClosureWitness --> ThruGlueWitness
  Typing --> ThruLiftKinds
  Closure --> ThruPre
  ThruLiftKinds --> ThruPre
  Semantics --> Typing
  StepFrame --> TypingFacts
  TypingFacts --> Unfresh
  NameWf --> Unfresh
  Wf --> Unfresh
  Unfresh --> UnheldFresh
  Heap --> Values
  Repl --> Values
  Sweep --> Values
  Progress --> Wf
```
<!-- END generated: A2 module DAG -->

---

## 5. Module Index & Key Theorems (Phase A2)

<!-- BEGIN generated: A2 module index (webdocs/scripts/gen-formal-data.mjs) -->
| Layer | Module | Lines | Theorems | Defs / Types | Summary |
|---|---|---:|---:|---:|---|
| 0. Syntax & Store | [`A2/Semantics.lean`](A2/Semantics.lean) | 1778 | 13 | 96 | Small-step operational semantics (Step, Steps), tree deallocation (Frees, DropSlot), call expansion, and Stuck. |
| 0. Syntax & Store | [`A2/Syntax.lean`](A2/Syntax.lean) | 1508 | 70 | 80 | Types, effect & kill lattice (Eff.kills), expressions, statements, and store values (Mem, Slot, Val). |
| 1. Flow-Sensitive Typing | [`A2/Basic.lean`](A2/Basic.lean) | 637 | 48 | 1 | Foundational lemmas for store updates (upd), value subtrees, and contexts. |
| 1. Flow-Sensitive Typing | [`A2/Ctx.lean`](A2/Ctx.lean) | 432 | 42 | 0 | Algebraic properties and monotonicity of context operations (kill, exitScope, derive). |
| 1. Flow-Sensitive Typing | [`A2/Typing.lean`](A2/Typing.lean) | 2809 | 159 | 136 | Flow-sensitive context Γ, kill operation, and typing rules for RHS, statements, calls, and functions (RhsT, StmtT, CallT, FnOK). |
| 1. Flow-Sensitive Typing | [`A2/TypingFacts.lean`](A2/TypingFacts.lean) | 1156 | 66 | 1 | Inversion lemmas and structural properties of well-typed statements (StmtT). |
| 2. Memory Invariant | [`A2/Heap.lean`](A2/Heap.lean) | 211 | 14 | 0 | Preservation of heap disjointness and allocation validity (HeapOK) across store operations. |
| 2. Memory Invariant | [`A2/Invariant.lean`](A2/Invariant.lean) | 3146 | 206 | 101 | Configuration invariant (Inv, HeapOK, Covers, ValOK, ViewsOK): single ownership and valid borrows/views. |
| 2. Memory Invariant | [`A2/NameWf.lean`](A2/NameWf.lean) | 1056 | 50 | 3 | Well-formedness and invariants for by-name closure captures (Kind.name). |
| 2. Memory Invariant | [`A2/SrcKeep.lean`](A2/SrcKeep.lean) | 564 | 25 | 0 | Source typing keeps a borrowed parameter's entry (StmtT.ctxRel), so a destructor's frame gets KeepOut, CtxWF and NameWF of its body without premises on letd (srcCase). |
| 2. Memory Invariant | [`A2/Stability.lean`](A2/Stability.lean) | 1471 | 99 | 5 | Stability of borrows and views under store and context updates. |
| 2. Memory Invariant | [`A2/Values.lean`](A2/Values.lean) | 1424 | 77 | 2 | Well-formedness lemmas for values, structs (pair), enums (inl/inr), and views. |
| 2. Memory Invariant | [`A2/Wf.lean`](A2/Wf.lean) | 1827 | 43 | 1 | Preservation of context well-formedness (WfCtx) across typing transitions. |
| 3. Proof Infrastructure | [`A2/ArcDtorWitness.lean`](A2/ArcDtorWitness.lean) | 304 | 13 | 4 |  |
| 3. Proof Infrastructure | [`A2/ArcPanicWitness.lean`](A2/ArcPanicWitness.lean) | 796 | 52 | 15 |  |
| 3. Proof Infrastructure | [`A2/CapClause.lean`](A2/CapClause.lean) | 80 | 4 | 0 |  |
| 3. Proof Infrastructure | [`A2/CapsEval.lean`](A2/CapsEval.lean) | 278 | 20 | 0 |  |
| 3. Proof Infrastructure | [`A2/CapsLive.lean`](A2/CapsLive.lean) | 2015 | 82 | 4 |  |
| 3. Proof Infrastructure | [`A2/CapsStore.lean`](A2/CapsStore.lean) | 187 | 18 | 1 |  |
| 3. Proof Infrastructure | [`A2/ClosureDropWitness.lean`](A2/ClosureDropWitness.lean) | 869 | 51 | 21 |  |
| 3. Proof Infrastructure | [`A2/ClosureParamViewWitness.lean`](A2/ClosureParamViewWitness.lean) | 357 | 18 | 6 |  |
| 3. Proof Infrastructure | [`A2/DomTy.lean`](A2/DomTy.lean) | 152 | 14 | 1 |  |
| 3. Proof Infrastructure | [`A2/DropCode.lean`](A2/DropCode.lean) | 706 | 15 | 9 |  |
| 3. Proof Infrastructure | [`A2/DropInWitness.lean`](A2/DropInWitness.lean) | 69 | 5 | 3 |  |
| 3. Proof Infrastructure | [`A2/Dtor.lean`](A2/Dtor.lean) | 1050 | 48 | 4 |  |
| 3. Proof Infrastructure | [`A2/DtorWitness.lean`](A2/DtorWitness.lean) | 2674 | 124 | 64 |  |
| 3. Proof Infrastructure | [`A2/EditB.lean`](A2/EditB.lean) | 3145 | 85 | 0 | Element edits through borrows (StmtT.editB): push, truncate, and element set through borrowed paths. |
| 3. Proof Infrastructure | [`A2/EditBV.lean`](A2/EditBV.lean) | 1404 | 51 | 1 | A view stored through a borrow (StmtT.editBV): every view-holding root of the borrow's path holds what the stored value depends on. |
| 3. Proof Infrastructure | [`A2/EditBVFnWitness.lean`](A2/EditBVFnWitness.lean) | 264 | 12 | 17 |  |
| 3. Proof Infrastructure | [`A2/Elem.lean`](A2/Elem.lean) | 69 | 1 | 0 | An element handed over (withElem, insert): the invariant does not see the order of an owned Vec's elements (MInv.perm). |
| 3. Proof Infrastructure | [`A2/ElemIdxWitness.lean`](A2/ElemIdxWitness.lean) | 78 | 5 | 4 |  |
| 3. Proof Infrastructure | [`A2/EnvHand.lean`](A2/EnvHand.lean) | 2975 | 74 | 5 | Closure and trait-object environment hand-over (StmtT.callcE) for inout receivers. |
| 3. Proof Infrastructure | [`A2/FrameCall.lean`](A2/FrameCall.lean) | 160 | 10 | 1 |  |
| 3. Proof Infrastructure | [`A2/FrameClause.lean`](A2/FrameClause.lean) | 772 | 46 | 6 |  |
| 3. Proof Infrastructure | [`A2/Fresh.lean`](A2/Fresh.lean) | 153 | 3 | 0 |  |
| 3. Proof Infrastructure | [`A2/FreshBase.lean`](A2/FreshBase.lean) | 447 | 34 | 2 |  |
| 3. Proof Infrastructure | [`A2/FreshClosureWitness.lean`](A2/FreshClosureWitness.lean) | 256 | 18 | 7 |  |
| 3. Proof Infrastructure | [`A2/FreshNestWitness.lean`](A2/FreshNestWitness.lean) | 399 | 32 | 30 |  |
| 3. Proof Infrastructure | [`A2/FreshProjWitness.lean`](A2/FreshProjWitness.lean) | 467 | 36 | 26 |  |
| 3. Proof Infrastructure | [`A2/FreshSatWitness.lean`](A2/FreshSatWitness.lean) | 417 | 34 | 24 |  |
| 3. Proof Infrastructure | [`A2/FreshWitness.lean`](A2/FreshWitness.lean) | 311 | 19 | 7 |  |
| 3. Proof Infrastructure | [`A2/HeldViewThruWitness.lean`](A2/HeldViewThruWitness.lean) | 200 | 17 | 13 |  |
| 3. Proof Infrastructure | [`A2/InoutViewArgWitness.lean`](A2/InoutViewArgWitness.lean) | 409 | 34 | 25 |  |
| 3. Proof Infrastructure | [`A2/KillVarsStep.lean`](A2/KillVarsStep.lean) | 281 | 11 | 4 |  |
| 3. Proof Infrastructure | [`A2/NoRootb.lean`](A2/NoRootb.lean) | 53 | 6 | 1 |  |
| 3. Proof Infrastructure | [`A2/ParamViewWitness.lean`](A2/ParamViewWitness.lean) | 457 | 21 | 6 |  |
| 3. Proof Infrastructure | [`A2/Reach.lean`](A2/Reach.lean) | 955 | 53 | 9 |  |
| 3. Proof Infrastructure | [`A2/Region.lean`](A2/Region.lean) | 35 | 1 | 0 |  |
| 3. Proof Infrastructure | [`A2/RegionChangeWitness.lean`](A2/RegionChangeWitness.lean) | 86 | 5 | 3 |  |
| 3. Proof Infrastructure | [`A2/RegionMem.lean`](A2/RegionMem.lean) | 420 | 22 | 6 |  |
| 3. Proof Infrastructure | [`A2/RegionResWitness.lean`](A2/RegionResWitness.lean) | 442 | 30 | 19 |  |
| 3. Proof Infrastructure | [`A2/RegionThruWitness.lean`](A2/RegionThruWitness.lean) | 113 | 8 | 7 |  |
| 3. Proof Infrastructure | [`A2/Repl.lean`](A2/Repl.lean) | 387 | 21 | 0 | One-hole replacement (Repl): a change through a borrowed handle rewrites one node of its owner's tree and leaves the rest. |
| 3. Proof Infrastructure | [`A2/SelfViewCall.lean`](A2/SelfViewCall.lean) | 60 | 2 | 0 |  |
| 3. Proof Infrastructure | [`A2/Settle.lean`](A2/Settle.lean) | 213 | 12 | 3 |  |
| 3. Proof Infrastructure | [`A2/SliceCopyViewWitness.lean`](A2/SliceCopyViewWitness.lean) | 192 | 11 | 12 |  |
| 3. Proof Infrastructure | [`A2/StepCaps.lean`](A2/StepCaps.lean) | 230 | 4 | 0 |  |
| 3. Proof Infrastructure | [`A2/StoreViewWitness.lean`](A2/StoreViewWitness.lean) | 346 | 17 | 13 |  |
| 3. Proof Infrastructure | [`A2/SubDcKill.lean`](A2/SubDcKill.lean) | 183 | 9 | 0 |  |
| 3. Proof Infrastructure | [`A2/Sweep.lean`](A2/Sweep.lean) | 622 | 67 | 3 | The sweep (Mem.sweep): shared blocks (Arc, lock blocks) that nothing reaches are removed and their payloads freed, from every thread's roots. |
| 3. Proof Infrastructure | [`A2/SweepD.lean`](A2/SweepD.lean) | 475 | 39 | 3 |  |
| 3. Proof Infrastructure | [`A2/TakeB.lean`](A2/TakeB.lean) | 350 | 17 | 0 | AGORA-889: an element that owns memory moved out through a borrow (Stmt.takeB, editSet's reverse): the owner's tree loses it in place (HeapOK.editTake, MInv.editB_take, typed as editB's truncation), and the new owner takes it (takeB_outOwn, covers_takeB; takeB_pres in Preservation). AGORA-897: the same for an element type that holds views (StmtT.takeBV: MInv.editBV_take; its views stay valid, takeB_viewsOK, takeBV_out; takeBV_pres). |
| 3. Proof Infrastructure | [`A2/ThruClosureWitness.lean`](A2/ThruClosureWitness.lean) | 443 | 34 | 13 |  |
| 3. Proof Infrastructure | [`A2/ThruDtorWitness.lean`](A2/ThruDtorWitness.lean) | 164 | 12 | 6 |  |
| 3. Proof Infrastructure | [`A2/ThruGlueWitness.lean`](A2/ThruGlueWitness.lean) | 446 | 26 | 14 |  |
| 3. Proof Infrastructure | [`A2/ThruLiftKinds.lean`](A2/ThruLiftKinds.lean) | 96 | 8 | 0 |  |
| 3. Proof Infrastructure | [`A2/ThruPre.lean`](A2/ThruPre.lean) | 247 | 25 | 3 |  |
| 3. Proof Infrastructure | [`A2/Unfresh.lean`](A2/Unfresh.lean) | 169 | 15 | 2 |  |
| 3. Proof Infrastructure | [`A2/UnheldFresh.lean`](A2/UnheldFresh.lean) | 198 | 16 | 2 |  |
| 3. Step & Unwinding Lemmas | [`A2/Frame.lean`](A2/Frame.lean) | 1980 | 97 | 9 | How runtime frames (scope, rbind, frozen) interact with the memory invariant. |
| 3. Step & Unwinding Lemmas | [`A2/Leak.lean`](A2/Leak.lean) | 677 | 26 | 1 | Leak-freedom invariant (Covers): every allocated address is owned by a live binding. |
| 3. Step & Unwinding Lemmas | [`A2/Panic.lean`](A2/Panic.lean) | 387 | 23 | 1 | Panic unwinding (panic_unwind): every exited scope drops its owned trees via the drop journal. |
| 3. Step & Unwinding Lemmas | [`A2/Rhs.lean`](A2/Rhs.lean) | 3493 | 165 | 3 | Stepping and invariant preservation for right-hand side evaluations (Rhs). |
| 3. Step & Unwinding Lemmas | [`A2/StepFrame.lean`](A2/StepFrame.lean) | 417 | 17 | 1 | Invariant preservation across frame steps and panic unwinding frames. |
| 3. Step & Unwinding Lemmas | [`A2/Steps.lean`](A2/Steps.lean) | 4181 | 125 | 7 | Preservation lemmas for individual statement steps (letv, assign, push, free, unpair). |
| 4. Calls & Closures | [`A2/Bind.lean`](A2/Bind.lean) | 188 | 4 | 1 | Binding call arguments (in, inout, sink) from caller context into callee frame. |
| 4. Calls & Closures | [`A2/Call.lean`](A2/Call.lean) | 4760 | 194 | 22 | Typing of expanded function calls (callStmt) from function summaries (FnOK + CallT). |
| 4. Calls & Closures | [`A2/CallInv.lean`](A2/CallInv.lean) | 994 | 28 | 0 | Full invariant preservation (callCase, recCase) across function call and recover expansion. |
| 4. Calls & Closures | [`A2/CallMem.lean`](A2/CallMem.lean) | 1647 | 60 | 2 | Store state and owned trees immediately after binding parameters in a call. |
| 4. Calls & Closures | [`A2/Closure.lean`](A2/Closure.lean) | 3611 | 116 | 7 | Closure and trait-object package calls (callc, cloCase, cloProgress) and by-name capture soundness. |
| 4. Calls & Closures | [`A2/Codes.lean`](A2/Codes.lean) | 876 | 43 | 6 | Package code-pointer integrity (ProgCodes, MemCodes, codes_step) across execution steps. |
| 4. Calls & Closures | [`A2/Rename.lean`](A2/Rename.lean) | 9234 | 371 | 27 | Alpha-renaming of function body variables to fresh variables at a call site. |
| 4. Memory Invariant | [`A2/Layout.lean`](A2/Layout.lean) | 182 | 12 | 5 | Agora #879: a tree's addresses split into its nodes' control blocks and buffers (ctls_datas_perm); no control block of any owned tree, a slot's or a block payload, is a buffer of any owned tree (ctl_ne_data, from HeapOK and BlkOwn), the fact the lowering's Vec TBAA tags assert. |
| 5. Soundness Theorems | [`A2/Preservation.lean`](A2/Preservation.lean) | 5439 | 124 | 15 | Preservation theorem (preserve): every execution step preserves typing StmtT and memory invariant Inv. |
| 5. Soundness Theorems | [`A2/Progress.lean`](A2/Progress.lean) | 953 | 14 | 0 | Progress theorem (progress): a well-typed statement is either .skip or can step (never Stuck). |
| 5. Soundness Theorems | [`A2/Soundness.lean`](A2/Soundness.lean) | 282 | 17 | 2 | Main theorems: soundness, memory_safe, no_leak_end, and no_leak_panic. |
| 5. Worked Examples | [`A2/DynCell.lean`](A2/DynCell.lean) | 444 | 27 | 20 | Per-call ownership through an owner cell: the pick example typed with A2's rules, and memory_safe and no_leak_end applied to it (pick_ok, main_safe, main_no_leak). |
| 5. Worked Examples | [`A2/ExitWitness.lean`](A2/ExitWitness.lean) | 380 | 47 | 18 | Agora #871: early exits. A break out of while T that drops a live owned Vec on the way (mainB_typed, breakB_steps), a continue-shaped exit of a loop body, and an early ^ across a scope in a callee checked against its summary (gR_ok) with its caller, each run safe and leak-free (mainB_safe, mainC_no_leak, mainR_safe, mainR_no_leak). |
| 5. Worked Examples | [`A2/HandOver.lean`](A2/HandOver.lean) | 497 | 30 | 12 | AGORA-885: the by-name owner hand-over as an encoding: the owner is a cell and a borrow, the hand-over a take into the cell. Straight-line and decided at run time (an ite on the flag nurlc reads off the buffer), each run safe and leak-free (main_safe, main_no_leak, mainJ_safe, mainJ_no_leak). |
| 5. Worked Examples | [`A2/PopWitness.lean`](A2/PopWitness.lean) | 262 | 13 | 11 | AGORA-888: a pop and a remove through a borrow, read as a truncation to the last index (Expr.dec), the number read before it, and element sets one place down; through a vec_at borrow of a Vec of Vecs and through a cursor, with memory_safe and no_leak_end applied (main_safe, main_no_leak). |
| 5. Worked Examples | [`A2/RemoveLoopWitness.lean`](A2/RemoveLoopWitness.lean) | 252 | 10 | 4 | AGORA-889: vec_remove of a number at a general index through a vec_at borrow, as a while loop of element sets one place down and the truncation, typed for every index (step_typed: the loop body keeps its context), with memory_safe and no_leak_end applied (main_safe, main_no_leak). |
| 5. Worked Examples | [`A2/TakeBDWitness.lean`](A2/TakeBDWitness.lean) | 207 | 4 | 2 | AGORA-900: a destructor value popped through a vec_at borrow of a letd Vec of Vecs of them, handed to its own letd first thing (StmtT.takeB; the guarantee A2.Dtor.takeB_typed), with memory_safe and no_leak_end applied (main12_typed, main12_safe, main12_no_leak). |
| 5. Worked Examples | [`A2/TakeBVWitness.lean`](A2/TakeBVWitness.lean) | 437 | 15 | 27 | AGORA-897: two views of a String's buffer, one popped and one removed through a vec_at borrow of a Vec of Vecs of views, both kept and read (StmtT.takeBV), with memory_safe and no_leak_end applied (main_typed, main_safe, main_no_leak); AGORA-898: a closure whose environment is a view moved out the same way (main2_*). |
| 5. Worked Examples | [`A2/TakeBWitness.lean`](A2/TakeBWitness.lean) | 240 | 7 | 10 | AGORA-889: a String popped and one removed through a vec_at borrow of a Vec of Vecs of Strings, both kept and read (Stmt.takeB), with memory_safe and no_leak_end applied (main_typed, main_safe, main_no_leak). |
| 5. Worked Examples | [`A2/TakeWitness.lean`](A2/TakeWitness.lean) | 263 | 21 | 12 | Agora #826: a take out of an inout .replace place (RhsT.take): a callee that hands its inout String on, checked against its summary, and a caller that reads its argument after the call, with memory_safe and no_leak_end applied (g_ok, main_safe, main_no_leak). |
<!-- END generated: A2 module index -->

---

<!-- BEGIN generated: A2 crown theorems (webdocs/scripts/gen-formal-data.mjs) -->
## 6. Crown Theorem Statements in Lean 4

### `A2.memory_safe` ([`A2/Soundness.lean#L217-L222`](A2/Soundness.lean#L217-L222))
```lean
/-- The memory model of stage A2 is sound: a well-typed program, run from
    the empty store, never gets stuck — it finishes, panics, or runs on. -/
theorem memory_safe {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) {s : Stmt} {Δ : Ctx}
    (ht : StmtT P .none (fun _ => none) [] s Δ) (hs : s.src = true) (hsc : s.codesOK P) {nv : Nat}
    (hv : ∀ v ∈ s.vars, v < nv)
    {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem nv) s (.ok m' s')) : ¬ Stuck P m' s'
```

### `A2.no_leak_end` ([`A2/Soundness.lean#L235-L240`](A2/Soundness.lean#L235-L240))
```lean
/-- Nothing leaks: when a well-typed program finishes, every allocation it
    made has been freed. -/
theorem no_leak_end {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) {s : Stmt} {Δ : Ctx}
    (ht : StmtT P .none (fun _ => none) [] s Δ) (hs : s.src = true) (hsc : s.codesOK P) {nv : Nat}
    (hv : ∀ v ∈ s.vars, v < nv)
    {m' : Mem} (hr : Steps P (emptyMem nv) s (.ok m' .skip)) : ∀ i, m'.alloc i = false
```

### `A2.no_leak_panic` ([`A2/Soundness.lean#L264-L269`](A2/Soundness.lean#L264-L269))
```lean
/-- ... and when a panic no `recover` frame catches ends it, the unwinding
    has freed every allocation too. -/
theorem no_leak_panic {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) {s : Stmt} {Δ : Ctx}
    (ht : StmtT P .none (fun _ => none) [] s Δ) (hs : s.src = true) (hsc : s.codesOK P) {nv : Nat}
    (hv : ∀ v ∈ s.vars, v < nv)
    {m' : Mem} (hr : Steps P (emptyMem nv) s (.panic m')) : ∀ i, m'.alloc i = false
```
<!-- END generated: A2 crown theorems -->
