# Visual Blueprint of the Lean 4 Soundness Proof (`formal/`)

> **Interactive Explorer:** You can also explore this proof interactively (with a step-by-step memory & borrow-checker simulator, clickable theorem dependency graph, and searchable soundness-hole corpus) on **[nurl-lang.org/docs/formal-verification](https://nurl-lang.org/docs/formal-verification)**.

* **Toolchain:** `leanprover/lean4:v4.35.0` (zero external dependencies; standard axioms `propext`, `Classical.choice`, `Quot.sound` only; `0` `sorry`s)
* **Phase A3 (Threads & Data-Race Freedom):** **33 modules**, **19,028 lines of Lean 4**, **928 theorems**, **1106 total declarations**
* **Phase A2 (Full Single-Threaded Calculus + Leak Freedom, destructors):** **56 modules**, **63,425 lines of Lean 4**, **2721 theorems**, **3470 total declarations**
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
## 4. Phase A2 Module Dependency DAG (56 Modules)

```mermaid
flowchart BT
  ArcDtorWitness["ArcDtorWitness<br/>(304L, 13 thms)"]
  ArcPanicWitness["ArcPanicWitness<br/>(795L, 52 thms)"]
  Basic["Basic<br/>(520L, 45 thms)"]
  Bind["Bind<br/>(188L, 4 thms)"]
  Call["Call<br/>(3791L, 173 thms)"]
  CallInv["CallInv<br/>(652L, 21 thms)"]
  CallMem["CallMem<br/>(1433L, 54 thms)"]
  Closure["Closure<br/>(3171L, 112 thms)"]
  ClosureDropWitness["ClosureDropWitness<br/>(869L, 51 thms)"]
  Codes["Codes<br/>(870L, 43 thms)"]
  Ctx["Ctx<br/>(327L, 31 thms)"]
  DropCode["DropCode<br/>(694L, 15 thms)"]
  DtorWitness["DtorWitness<br/>(3591L, 165 thms)"]
  DynCell["DynCell<br/>(480L, 33 thms)"]
  EditB["EditB<br/>(2444L, 67 thms)"]
  EditBV["EditBV<br/>(1324L, 40 thms)"]
  EditBVFnWitness["EditBVFnWitness<br/>(263L, 12 thms)"]
  Elem["Elem<br/>(67L, 1 thms)"]
  EnvHand["EnvHand<br/>(2077L, 57 thms)"]
  ExitWitness["ExitWitness<br/>(380L, 47 thms)"]
  Frame["Frame<br/>(1208L, 66 thms)"]
  HandOver["HandOver<br/>(495L, 30 thms)"]
  Heap["Heap<br/>(211L, 14 thms)"]
  Invariant["Invariant<br/>(2506L, 152 thms)"]
  Layout["Layout<br/>(182L, 12 thms)"]
  Leak["Leak<br/>(665L, 26 thms)"]
  NameWf["NameWf<br/>(1027L, 48 thms)"]
  Panic["Panic<br/>(387L, 23 thms)"]
  PopWitness["PopWitness<br/>(262L, 13 thms)"]
  Preservation["Preservation<br/>(4366L, 94 thms)"]
  Progress["Progress<br/>(926L, 14 thms)"]
  RemoveLoopWitness["RemoveLoopWitness<br/>(252L, 10 thms)"]
  Rename["Rename<br/>(4536L, 189 thms)"]
  Repl["Repl<br/>(387L, 21 thms)"]
  Rhs["Rhs<br/>(3335L, 159 thms)"]
  Semantics["Semantics<br/>(1757L, 13 thms)"]
  Settle["Settle<br/>(213L, 12 thms)"]
  Soundness["Soundness<br/>(277L, 17 thms)"]
  SrcKeep["SrcKeep<br/>(387L, 14 thms)"]
  Stability["Stability<br/>(1083L, 78 thms)"]
  StepFrame["StepFrame<br/>(417L, 17 thms)"]
  Steps["Steps<br/>(3901L, 122 thms)"]
  Sweep["Sweep<br/>(602L, 65 thms)"]
  SweepD["SweepD<br/>(475L, 39 thms)"]
  Syntax["Syntax<br/>(1428L, 64 thms)"]
  TakeB["TakeB<br/>(342L, 17 thms)"]
  TakeBDWitness["TakeBDWitness<br/>(206L, 4 thms)"]
  TakeBVWitness["TakeBVWitness<br/>(435L, 15 thms)"]
  TakeBWitness["TakeBWitness<br/>(239L, 7 thms)"]
  TakeWitness["TakeWitness<br/>(263L, 21 thms)"]
  ThruClosureWitness["ThruClosureWitness<br/>(421L, 34 thms)"]
  ThruDtorWitness["ThruDtorWitness<br/>(163L, 12 thms)"]
  Typing["Typing<br/>(1945L, 91 thms)"]
  TypingFacts["TypingFacts<br/>(1112L, 64 thms)"]
  Values["Values<br/>(1176L, 67 thms)"]
  Wf["Wf<br/>(1598L, 41 thms)"]
  DtorWitness --> ArcDtorWitness
  Settle --> ArcDtorWitness
  ArcDtorWitness --> ArcPanicWitness
  Invariant --> Basic
  Call --> Bind
  Rename --> Call
  Preservation --> Call
  CallMem --> CallInv
  SrcKeep --> CallInv
  Bind --> CallMem
  CallInv --> Closure
  DtorWitness --> ClosureDropWitness
  EnvHand --> ClosureDropWitness
  Closure --> Codes
  Repl --> Codes
  Basic --> Ctx
  DtorWitness --> DropCode
  DynCell --> DtorWitness
  Soundness --> DynCell
  TypingFacts --> EditB
  EditB --> EditBV
  TakeBVWitness --> EditBVFnWitness
  EditBV --> Elem
  Codes --> EnvHand
  SrcKeep --> EnvHand
  Soundness --> ExitWitness
  Values --> Frame
  DynCell --> HandOver
  Stability --> Heap
  Typing --> Invariant
  Basic --> Layout
  Steps --> Leak
  Wf --> NameWf
  Leak --> Panic
  DynCell --> PopWitness
  TakeB --> Preservation
  Preservation --> Progress
  PopWitness --> RemoveLoopWitness
  NameWf --> Rename
  Stability --> Repl
  Frame --> Rhs
  Syntax --> Semantics
  Soundness --> Settle
  Codes --> Soundness
  SrcKeep --> Soundness
  EnvHand --> Soundness
  Call --> SrcKeep
  Ctx --> Stability
  Panic --> StepFrame
  Rhs --> Steps
  SweepD --> Steps
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
  Semantics --> Typing
  StepFrame --> TypingFacts
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
| 0. Syntax & Store | [`A2/Semantics.lean`](A2/Semantics.lean) | 1757 | 13 | 95 | Small-step operational semantics (Step, Steps), tree deallocation (Frees, DropSlot), call expansion, and Stuck. |
| 0. Syntax & Store | [`A2/Syntax.lean`](A2/Syntax.lean) | 1428 | 64 | 78 | Types, effect & kill lattice (Eff.kills), expressions, statements, and store values (Mem, Slot, Val). |
| 1. Flow-Sensitive Typing | [`A2/Basic.lean`](A2/Basic.lean) | 520 | 45 | 1 | Foundational lemmas for store updates (upd), value subtrees, and contexts. |
| 1. Flow-Sensitive Typing | [`A2/Ctx.lean`](A2/Ctx.lean) | 327 | 31 | 0 | Algebraic properties and monotonicity of context operations (kill, exitScope, derive). |
| 1. Flow-Sensitive Typing | [`A2/Typing.lean`](A2/Typing.lean) | 1945 | 91 | 110 | Flow-sensitive context Γ, kill operation, and typing rules for RHS, statements, calls, and functions (RhsT, StmtT, CallT, FnOK). |
| 1. Flow-Sensitive Typing | [`A2/TypingFacts.lean`](A2/TypingFacts.lean) | 1112 | 64 | 1 | Inversion lemmas and structural properties of well-typed statements (StmtT). |
| 2. Memory Invariant | [`A2/Heap.lean`](A2/Heap.lean) | 211 | 14 | 0 | Preservation of heap disjointness and allocation validity (HeapOK) across store operations. |
| 2. Memory Invariant | [`A2/Invariant.lean`](A2/Invariant.lean) | 2506 | 152 | 82 | Configuration invariant (Inv, HeapOK, Covers, ValOK, ViewsOK): single ownership and valid borrows/views. |
| 2. Memory Invariant | [`A2/NameWf.lean`](A2/NameWf.lean) | 1027 | 48 | 3 | Well-formedness and invariants for by-name closure captures (Kind.name). |
| 2. Memory Invariant | [`A2/SrcKeep.lean`](A2/SrcKeep.lean) | 387 | 14 | 0 | Source typing keeps a borrowed parameter's entry (StmtT.ctxRel), so a destructor's frame gets KeepOut, CtxWF and NameWF of its body without premises on letd (srcCase). |
| 2. Memory Invariant | [`A2/Stability.lean`](A2/Stability.lean) | 1083 | 78 | 5 | Stability of borrows and views under store and context updates. |
| 2. Memory Invariant | [`A2/Values.lean`](A2/Values.lean) | 1176 | 67 | 2 | Well-formedness lemmas for values, structs (pair), enums (inl/inr), and views. |
| 2. Memory Invariant | [`A2/Wf.lean`](A2/Wf.lean) | 1598 | 41 | 1 | Preservation of context well-formedness (WfCtx) across typing transitions. |
| 3. Proof Infrastructure | [`A2/ArcDtorWitness.lean`](A2/ArcDtorWitness.lean) | 304 | 13 | 4 |  |
| 3. Proof Infrastructure | [`A2/ArcPanicWitness.lean`](A2/ArcPanicWitness.lean) | 795 | 52 | 15 |  |
| 3. Proof Infrastructure | [`A2/ClosureDropWitness.lean`](A2/ClosureDropWitness.lean) | 869 | 51 | 21 |  |
| 3. Proof Infrastructure | [`A2/DropCode.lean`](A2/DropCode.lean) | 694 | 15 | 9 |  |
| 3. Proof Infrastructure | [`A2/DtorWitness.lean`](A2/DtorWitness.lean) | 3591 | 165 | 67 |  |
| 3. Proof Infrastructure | [`A2/EditB.lean`](A2/EditB.lean) | 2444 | 67 | 0 | Element edits through borrows (StmtT.editB): push, truncate, and element set through borrowed paths. |
| 3. Proof Infrastructure | [`A2/EditBV.lean`](A2/EditBV.lean) | 1324 | 40 | 1 | A view stored through a borrow (StmtT.editBV): every view-holding root of the borrow's path holds what the stored value depends on. |
| 3. Proof Infrastructure | [`A2/EditBVFnWitness.lean`](A2/EditBVFnWitness.lean) | 263 | 12 | 17 |  |
| 3. Proof Infrastructure | [`A2/Elem.lean`](A2/Elem.lean) | 67 | 1 | 0 | An element handed over (withElem, insert): the invariant does not see the order of an owned Vec's elements (MInv.perm). |
| 3. Proof Infrastructure | [`A2/EnvHand.lean`](A2/EnvHand.lean) | 2077 | 57 | 5 | Closure and trait-object environment hand-over (StmtT.callcE) for inout receivers. |
| 3. Proof Infrastructure | [`A2/Repl.lean`](A2/Repl.lean) | 387 | 21 | 0 | One-hole replacement (Repl): a change through a borrowed handle rewrites one node of its owner's tree and leaves the rest. |
| 3. Proof Infrastructure | [`A2/Settle.lean`](A2/Settle.lean) | 213 | 12 | 3 |  |
| 3. Proof Infrastructure | [`A2/Sweep.lean`](A2/Sweep.lean) | 602 | 65 | 3 | The sweep (Mem.sweep): shared blocks (Arc, lock blocks) that nothing reaches are removed and their payloads freed, from every thread's roots. |
| 3. Proof Infrastructure | [`A2/SweepD.lean`](A2/SweepD.lean) | 475 | 39 | 3 |  |
| 3. Proof Infrastructure | [`A2/TakeB.lean`](A2/TakeB.lean) | 342 | 17 | 0 | AGORA-889: an element that owns memory moved out through a borrow (Stmt.takeB, editSet's reverse): the owner's tree loses it in place (HeapOK.editTake, MInv.editB_take, typed as editB's truncation), and the new owner takes it (takeB_outOwn, covers_takeB; takeB_pres in Preservation). AGORA-897: the same for an element type that holds views (StmtT.takeBV: MInv.editBV_take; its views stay valid, takeB_viewsOK, takeBV_out; takeBV_pres). |
| 3. Proof Infrastructure | [`A2/ThruClosureWitness.lean`](A2/ThruClosureWitness.lean) | 421 | 34 | 13 |  |
| 3. Proof Infrastructure | [`A2/ThruDtorWitness.lean`](A2/ThruDtorWitness.lean) | 163 | 12 | 6 |  |
| 3. Step & Unwinding Lemmas | [`A2/Frame.lean`](A2/Frame.lean) | 1208 | 66 | 3 | How runtime frames (scope, rbind, frozen) interact with the memory invariant. |
| 3. Step & Unwinding Lemmas | [`A2/Leak.lean`](A2/Leak.lean) | 665 | 26 | 1 | Leak-freedom invariant (Covers): every allocated address is owned by a live binding. |
| 3. Step & Unwinding Lemmas | [`A2/Panic.lean`](A2/Panic.lean) | 387 | 23 | 1 | Panic unwinding (panic_unwind): every exited scope drops its owned trees via the drop journal. |
| 3. Step & Unwinding Lemmas | [`A2/Rhs.lean`](A2/Rhs.lean) | 3335 | 159 | 3 | Stepping and invariant preservation for right-hand side evaluations (Rhs). |
| 3. Step & Unwinding Lemmas | [`A2/StepFrame.lean`](A2/StepFrame.lean) | 417 | 17 | 1 | Invariant preservation across frame steps and panic unwinding frames. |
| 3. Step & Unwinding Lemmas | [`A2/Steps.lean`](A2/Steps.lean) | 3901 | 122 | 6 | Preservation lemmas for individual statement steps (letv, assign, push, free, unpair). |
| 4. Calls & Closures | [`A2/Bind.lean`](A2/Bind.lean) | 188 | 4 | 1 | Binding call arguments (in, inout, sink) from caller context into callee frame. |
| 4. Calls & Closures | [`A2/Call.lean`](A2/Call.lean) | 3791 | 173 | 20 | Typing of expanded function calls (callStmt) from function summaries (FnOK + CallT). |
| 4. Calls & Closures | [`A2/CallInv.lean`](A2/CallInv.lean) | 652 | 21 | 0 | Full invariant preservation (callCase, recCase) across function call and recover expansion. |
| 4. Calls & Closures | [`A2/CallMem.lean`](A2/CallMem.lean) | 1433 | 54 | 2 | Store state and owned trees immediately after binding parameters in a call. |
| 4. Calls & Closures | [`A2/Closure.lean`](A2/Closure.lean) | 3171 | 112 | 7 | Closure and trait-object package calls (callc, cloCase, cloProgress) and by-name capture soundness. |
| 4. Calls & Closures | [`A2/Codes.lean`](A2/Codes.lean) | 870 | 43 | 6 | Package code-pointer integrity (ProgCodes, MemCodes, codes_step) across execution steps. |
| 4. Calls & Closures | [`A2/Rename.lean`](A2/Rename.lean) | 4536 | 189 | 14 | Alpha-renaming of function body variables to fresh variables at a call site. |
| 4. Memory Invariant | [`A2/Layout.lean`](A2/Layout.lean) | 182 | 12 | 5 | Agora #879: a tree's addresses split into its nodes' control blocks and buffers (ctls_datas_perm); no control block of any owned tree, a slot's or a block payload, is a buffer of any owned tree (ctl_ne_data, from HeapOK and BlkOwn), the fact the lowering's Vec TBAA tags assert. |
| 5. Soundness Theorems | [`A2/Preservation.lean`](A2/Preservation.lean) | 4366 | 94 | 15 | Preservation theorem (preserve): every execution step preserves typing StmtT and memory invariant Inv. |
| 5. Soundness Theorems | [`A2/Progress.lean`](A2/Progress.lean) | 926 | 14 | 0 | Progress theorem (progress): a well-typed statement is either .skip or can step (never Stuck). |
| 5. Soundness Theorems | [`A2/Soundness.lean`](A2/Soundness.lean) | 277 | 17 | 2 | Main theorems: soundness, memory_safe, no_leak_end, and no_leak_panic. |
| 5. Worked Examples | [`A2/DynCell.lean`](A2/DynCell.lean) | 480 | 33 | 21 | Per-call ownership through an owner cell: the pick example typed with A2's rules, and memory_safe and no_leak_end applied to it (pick_ok, main_safe, main_no_leak). |
| 5. Worked Examples | [`A2/ExitWitness.lean`](A2/ExitWitness.lean) | 380 | 47 | 18 | Agora #871: early exits. A break out of while T that drops a live owned Vec on the way (mainB_typed, breakB_steps), a continue-shaped exit of a loop body, and an early ^ across a scope in a callee checked against its summary (gR_ok) with its caller, each run safe and leak-free (mainB_safe, mainC_no_leak, mainR_safe, mainR_no_leak). |
| 5. Worked Examples | [`A2/HandOver.lean`](A2/HandOver.lean) | 495 | 30 | 12 | AGORA-885: the by-name owner hand-over as an encoding: the owner is a cell and a borrow, the hand-over a take into the cell. Straight-line and decided at run time (an ite on the flag nurlc reads off the buffer), each run safe and leak-free (main_safe, main_no_leak, mainJ_safe, mainJ_no_leak). |
| 5. Worked Examples | [`A2/PopWitness.lean`](A2/PopWitness.lean) | 262 | 13 | 11 | AGORA-888: a pop and a remove through a borrow, read as a truncation to the last index (Expr.dec), the number read before it, and element sets one place down; through a vec_at borrow of a Vec of Vecs and through a cursor, with memory_safe and no_leak_end applied (main_safe, main_no_leak). |
| 5. Worked Examples | [`A2/RemoveLoopWitness.lean`](A2/RemoveLoopWitness.lean) | 252 | 10 | 4 | AGORA-889: vec_remove of a number at a general index through a vec_at borrow, as a while loop of element sets one place down and the truncation, typed for every index (step_typed: the loop body keeps its context), with memory_safe and no_leak_end applied (main_safe, main_no_leak). |
| 5. Worked Examples | [`A2/TakeBDWitness.lean`](A2/TakeBDWitness.lean) | 206 | 4 | 2 | AGORA-900: a destructor value popped through a vec_at borrow of a letd Vec of Vecs of them, handed to its own letd first thing (StmtT.takeB; the guarantee A2.Dtor.takeB_typed), with memory_safe and no_leak_end applied (main12_typed, main12_safe, main12_no_leak). |
| 5. Worked Examples | [`A2/TakeBVWitness.lean`](A2/TakeBVWitness.lean) | 435 | 15 | 27 | AGORA-897: two views of a String's buffer, one popped and one removed through a vec_at borrow of a Vec of Vecs of views, both kept and read (StmtT.takeBV), with memory_safe and no_leak_end applied (main_typed, main_safe, main_no_leak); AGORA-898: a closure whose environment is a view moved out the same way (main2_*). |
| 5. Worked Examples | [`A2/TakeBWitness.lean`](A2/TakeBWitness.lean) | 239 | 7 | 10 | AGORA-889: a String popped and one removed through a vec_at borrow of a Vec of Vecs of Strings, both kept and read (Stmt.takeB), with memory_safe and no_leak_end applied (main_typed, main_safe, main_no_leak). |
| 5. Worked Examples | [`A2/TakeWitness.lean`](A2/TakeWitness.lean) | 263 | 21 | 12 | Agora #826: a take out of an inout .replace place (RhsT.take): a callee that hands its inout String on, checked against its summary, and a caller that reads its argument after the call, with memory_safe and no_leak_end applied (g_ok, main_safe, main_no_leak). |
<!-- END generated: A2 module index -->

---

<!-- BEGIN generated: A2 crown theorems (webdocs/scripts/gen-formal-data.mjs) -->
## 6. Crown Theorem Statements in Lean 4

### `A2.memory_safe` ([`A2/Soundness.lean#L212-L217`](A2/Soundness.lean#L212-L217))
```lean
/-- The memory model of stage A2 is sound: a well-typed program, run from
    the empty store, never gets stuck — it finishes, panics, or runs on. -/
theorem memory_safe {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) {s : Stmt} {Δ : Ctx}
    (ht : StmtT P .none (fun _ => none) [] s Δ) (hs : s.src = true) (hsc : s.codesOK P) {nv : Nat}
    (hv : ∀ v ∈ s.vars, v < nv)
    {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem nv) s (.ok m' s')) : ¬ Stuck P m' s'
```

### `A2.no_leak_end` ([`A2/Soundness.lean#L230-L235`](A2/Soundness.lean#L230-L235))
```lean
/-- Nothing leaks: when a well-typed program finishes, every allocation it
    made has been freed. -/
theorem no_leak_end {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) {s : Stmt} {Δ : Ctx}
    (ht : StmtT P .none (fun _ => none) [] s Δ) (hs : s.src = true) (hsc : s.codesOK P) {nv : Nat}
    (hv : ∀ v ∈ s.vars, v < nv)
    {m' : Mem} (hr : Steps P (emptyMem nv) s (.ok m' .skip)) : ∀ i, m'.alloc i = false
```

### `A2.no_leak_panic` ([`A2/Soundness.lean#L259-L264`](A2/Soundness.lean#L259-L264))
```lean
/-- ... and when a panic no `recover` frame catches ends it, the unwinding
    has freed every allocation too. -/
theorem no_leak_panic {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) {s : Stmt} {Δ : Ctx}
    (ht : StmtT P .none (fun _ => none) [] s Δ) (hs : s.src = true) (hsc : s.codesOK P) {nv : Nat}
    (hv : ∀ v ∈ s.vars, v < nv)
    {m' : Mem} (hr : Steps P (emptyMem nv) s (.panic m')) : ∀ i, m'.alloc i = false
```
<!-- END generated: A2 crown theorems -->
