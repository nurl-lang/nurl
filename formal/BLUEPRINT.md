# Visual Blueprint of the Lean 4 Soundness Proof (`formal/`)

> **Interactive Explorer:** You can also explore this proof interactively (with a step-by-step memory & borrow-checker simulator, clickable theorem dependency graph, and searchable soundness-hole corpus) on **[nurl-lang.org/docs/formal-verification](https://nurl-lang.org/docs/formal-verification)**.

* **Toolchain:** `leanprover/lean4:v4.35.0` (zero external dependencies; standard axioms `propext`, `Classical.choice`, `Quot.sound` only; `0` `sorry`s)
* **Phase A2 (Full Single-Threaded Calculus + Leak Freedom, destructors):** **31 modules**, **26,863 lines of Lean 4**, **1172 theorems**, **1459 total declarations**
* **Phase A1 (Core Calculus):** **22 modules**, **9,571 lines of Lean 4**, **449 theorems**, **613 total declarations**
* **Soundness Corpus (`corpus/map.tsv`):** every hole probe in [`tools/fuzz/holes/`](../tools/fuzz/holes/), with the rule and the proof phase (A1, A2, A3, B) that covers it. The table is generated from the probes' `// map:` lines by `tools/fuzz/holes/map.sh` (build.sh writes it; it is not committed); `tools/fuzz/holes/map.py --counts` gives the totals

---

## 1. For Everyone: What Does the Proof Actually Prove?

In one sentence: **If a safe NURL program passes the ownership and borrow checker (`StmtT`), running it can never read freed memory, free the same memory twice, read through a view whose buffer reallocated, or leak a single heap allocation — whether the program finishes normally or unwinds from a panic.**

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
## 4. Phase A2 Module Dependency DAG (31 Modules)

```mermaid
flowchart BT
  Basic["Basic<br/>(268L, 22 thms)"]
  Bind["Bind<br/>(188L, 4 thms)"]
  Call["Call<br/>(3392L, 160 thms)"]
  CallInv["CallInv<br/>(648L, 25 thms)"]
  CallMem["CallMem<br/>(1028L, 46 thms)"]
  Closure["Closure<br/>(2793L, 99 thms)"]
  Codes["Codes<br/>(413L, 27 thms)"]
  Ctx["Ctx<br/>(261L, 26 thms)"]
  DynCell["DynCell<br/>(479L, 33 thms)"]
  Frame["Frame<br/>(612L, 40 thms)"]
  Heap["Heap<br/>(173L, 13 thms)"]
  Invariant["Invariant<br/>(626L, 16 thms)"]
  Leak["Leak<br/>(300L, 18 thms)"]
  NameWf["NameWf<br/>(809L, 41 thms)"]
  Panic["Panic<br/>(70L, 2 thms)"]
  Preservation["Preservation<br/>(2124L, 50 thms)"]
  Progress["Progress<br/>(382L, 8 thms)"]
  Rename["Rename<br/>(3334L, 161 thms)"]
  Repl["Repl<br/>(236L, 14 thms)"]
  Rhs["Rhs<br/>(1410L, 77 thms)"]
  Semantics["Semantics<br/>(523L, 0 thms)"]
  Soundness["Soundness<br/>(176L, 12 thms)"]
  SrcKeep["SrcKeep<br/>(270L, 14 thms)"]
  Stability["Stability<br/>(656L, 48 thms)"]
  StepFrame["StepFrame<br/>(312L, 16 thms)"]
  Steps["Steps<br/>(1748L, 51 thms)"]
  Syntax["Syntax<br/>(283L, 0 thms)"]
  Typing["Typing<br/>(1172L, 53 thms)"]
  TypingFacts["TypingFacts<br/>(855L, 53 thms)"]
  Values["Values<br/>(146L, 10 thms)"]
  Wf["Wf<br/>(1176L, 33 thms)"]
  Invariant --> Basic
  Call --> Bind
  Rename --> Call
  Preservation --> Call
  CallMem --> CallInv
  Bind --> CallMem
  CallInv --> Closure
  Closure --> Codes
  Repl --> Codes
  Basic --> Ctx
  Soundness --> DynCell
  Values --> Frame
  Stability --> Heap
  Typing --> Invariant
  Steps --> Leak
  Wf --> NameWf
  Leak --> Panic
  TypingFacts --> Preservation
  Preservation --> Progress
  NameWf --> Rename
  Stability --> Repl
  Frame --> Rhs
  Syntax --> Semantics
  Codes --> Soundness
  SrcKeep --> Soundness
  Call --> SrcKeep
  Ctx --> Stability
  Panic --> StepFrame
  Rhs --> Steps
  Semantics --> Typing
  StepFrame --> TypingFacts
  Heap --> Values
  Progress --> Wf
```
<!-- END generated: A2 module DAG -->

---

## 5. Module Index & Key Theorems (Phase A2)

<!-- BEGIN generated: A2 module index (webdocs/scripts/gen-formal-data.mjs) -->
| Layer | Module | Lines | Theorems | Defs / Types | Summary |
|---|---|---:|---:|---:|---|
| 0. Syntax & Store | [`A2/Semantics.lean`](A2/Semantics.lean) | 523 | 0 | 36 | Small-step operational semantics (Step, Steps), tree deallocation (Frees, DropSlot), call expansion, and Stuck. |
| 0. Syntax & Store | [`A2/Syntax.lean`](A2/Syntax.lean) | 283 | 0 | 27 | Types, effect & kill lattice (Eff.kills), expressions, statements, and store values (Mem, Slot, Val). |
| 1. Flow-Sensitive Typing | [`A2/Basic.lean`](A2/Basic.lean) | 268 | 22 | 1 | Foundational lemmas for store updates (upd), value subtrees, and contexts. |
| 1. Flow-Sensitive Typing | [`A2/Ctx.lean`](A2/Ctx.lean) | 261 | 26 | 0 | Algebraic properties and monotonicity of context operations (kill, exitScope, derive). |
| 1. Flow-Sensitive Typing | [`A2/Typing.lean`](A2/Typing.lean) | 1172 | 53 | 91 | Flow-sensitive context Γ, kill operation, and typing rules for RHS, statements, calls, and functions (RhsT, StmtT, CallT, FnOK). |
| 1. Flow-Sensitive Typing | [`A2/TypingFacts.lean`](A2/TypingFacts.lean) | 855 | 53 | 1 | Inversion lemmas and structural properties of well-typed statements (StmtT). |
| 2. Memory Invariant | [`A2/Heap.lean`](A2/Heap.lean) | 173 | 13 | 0 | Preservation of heap disjointness and allocation validity (HeapOK) across store operations. |
| 2. Memory Invariant | [`A2/Invariant.lean`](A2/Invariant.lean) | 626 | 16 | 41 | Configuration invariant (Inv, HeapOK, Covers, ValOK, ViewsOK): single ownership and valid borrows/views. |
| 2. Memory Invariant | [`A2/NameWf.lean`](A2/NameWf.lean) | 809 | 41 | 3 | Well-formedness and invariants for by-name closure captures (Kind.name). |
| 2. Memory Invariant | [`A2/SrcKeep.lean`](A2/SrcKeep.lean) | 270 | 14 | 0 | Source typing keeps a borrowed parameter's entry (StmtT.ctxRel), so a destructor's frame gets KeepOut, CtxWF and NameWF of its body without premises on letd (srcCase). |
| 2. Memory Invariant | [`A2/Stability.lean`](A2/Stability.lean) | 656 | 48 | 4 | Stability of borrows and views under store and context updates. |
| 2. Memory Invariant | [`A2/Values.lean`](A2/Values.lean) | 146 | 10 | 0 | Well-formedness lemmas for values, structs (pair), enums (inl/inr), and views. |
| 2. Memory Invariant | [`A2/Wf.lean`](A2/Wf.lean) | 1176 | 33 | 1 | Preservation of context well-formedness (WfCtx) across typing transitions. |
| 3. Proof Infrastructure | [`A2/Repl.lean`](A2/Repl.lean) | 236 | 14 | 0 |  |
| 3. Step & Unwinding Lemmas | [`A2/Frame.lean`](A2/Frame.lean) | 612 | 40 | 1 | How runtime frames (scope, rbind, frozen) interact with the memory invariant. |
| 3. Step & Unwinding Lemmas | [`A2/Leak.lean`](A2/Leak.lean) | 300 | 18 | 1 | Leak-freedom invariant (Covers): every allocated address is owned by a live binding. |
| 3. Step & Unwinding Lemmas | [`A2/Panic.lean`](A2/Panic.lean) | 70 | 2 | 0 | Panic unwinding (panic_unwind): every exited scope drops its owned trees via the drop journal. |
| 3. Step & Unwinding Lemmas | [`A2/Rhs.lean`](A2/Rhs.lean) | 1410 | 77 | 2 | Stepping and invariant preservation for right-hand side evaluations (Rhs). |
| 3. Step & Unwinding Lemmas | [`A2/StepFrame.lean`](A2/StepFrame.lean) | 312 | 16 | 1 | Invariant preservation across frame steps and panic unwinding frames. |
| 3. Step & Unwinding Lemmas | [`A2/Steps.lean`](A2/Steps.lean) | 1748 | 51 | 1 | Preservation lemmas for individual statement steps (letv, assign, push, free, unpair). |
| 4. Calls & Closures | [`A2/Bind.lean`](A2/Bind.lean) | 188 | 4 | 1 | Binding call arguments (in, inout, sink) from caller context into callee frame. |
| 4. Calls & Closures | [`A2/Call.lean`](A2/Call.lean) | 3392 | 160 | 20 | Typing of expanded function calls (callStmt) from function summaries (FnOK + CallT). |
| 4. Calls & Closures | [`A2/CallInv.lean`](A2/CallInv.lean) | 648 | 25 | 0 | Full invariant preservation (callCase, recCase) across function call and recover expansion. |
| 4. Calls & Closures | [`A2/CallMem.lean`](A2/CallMem.lean) | 1028 | 46 | 2 | Store state and owned trees immediately after binding parameters in a call. |
| 4. Calls & Closures | [`A2/Closure.lean`](A2/Closure.lean) | 2793 | 99 | 5 | Closure and trait-object package calls (callc, cloCase, cloProgress) and by-name capture soundness. |
| 4. Calls & Closures | [`A2/Codes.lean`](A2/Codes.lean) | 413 | 27 | 1 | Package code-pointer integrity (ProgCodes, MemCodes, codes_step) across execution steps. |
| 4. Calls & Closures | [`A2/Rename.lean`](A2/Rename.lean) | 3334 | 161 | 13 | Alpha-renaming of function body variables to fresh variables at a call site. |
| 5. Soundness Theorems | [`A2/Preservation.lean`](A2/Preservation.lean) | 2124 | 50 | 11 | Preservation theorem (preserve): every execution step preserves typing StmtT and memory invariant Inv. |
| 5. Soundness Theorems | [`A2/Progress.lean`](A2/Progress.lean) | 382 | 8 | 0 | Progress theorem (progress): a well-typed statement is either .skip or can step (never Stuck). |
| 5. Soundness Theorems | [`A2/Soundness.lean`](A2/Soundness.lean) | 176 | 12 | 2 | Main theorems: soundness, memory_safe, no_leak_end, and no_leak_panic. |
| 5. Worked Examples | [`A2/DynCell.lean`](A2/DynCell.lean) | 479 | 33 | 21 | Per-call ownership through an owner cell: the pick example typed with A2's rules, and memory_safe and no_leak_end applied to it (pick_ok, main_safe, main_no_leak). |
<!-- END generated: A2 module index -->

---

<!-- BEGIN generated: A2 crown theorems (webdocs/scripts/gen-formal-data.mjs) -->
## 6. Crown Theorem Statements in Lean 4

### `A2.memory_safe` ([`A2/Soundness.lean#L133-L138`](A2/Soundness.lean#L133-L138))
```lean
/-- The memory model of stage A2 is sound: a well-typed program, run from
    the empty store, never gets stuck — it finishes, panics, or runs on. -/
theorem memory_safe {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) {s : Stmt} {Δ : Ctx}
    (ht : StmtT P (fun _ => none) [] s Δ) (hs : s.src = true) (hsc : s.codesOK P) {nv : Nat}
    (hv : ∀ v ∈ s.vars, v < nv)
    {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem nv) s (.ok m' s')) : ¬ Stuck P m' s'
```

### `A2.no_leak_end` ([`A2/Soundness.lean#L141-L146`](A2/Soundness.lean#L141-L146))
```lean
/-- Nothing leaks: when a well-typed program finishes, every allocation it
    made has been freed. -/
theorem no_leak_end {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) {s : Stmt} {Δ : Ctx}
    (ht : StmtT P (fun _ => none) [] s Δ) (hs : s.src = true) (hsc : s.codesOK P) {nv : Nat}
    (hv : ∀ v ∈ s.vars, v < nv)
    {m' : Mem} (hr : Steps P (emptyMem nv) s (.ok m' .skip)) : ∀ i, m'.alloc i = false
```

### `A2.no_leak_panic` ([`A2/Soundness.lean#L159-L164`](A2/Soundness.lean#L159-L164))
```lean
/-- ... and when a panic no `recover` frame catches ends it, the unwinding
    has freed every allocation too. -/
theorem no_leak_panic {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) {s : Stmt} {Δ : Ctx}
    (ht : StmtT P (fun _ => none) [] s Δ) (hs : s.src = true) (hsc : s.codesOK P) {nv : Nat}
    (hv : ∀ v ∈ s.vars, v < nv)
    {m' : Mem} (hr : Steps P (emptyMem nv) s (.panic m')) : ∀ i, m'.alloc i = false
```
<!-- END generated: A2 crown theorems -->
