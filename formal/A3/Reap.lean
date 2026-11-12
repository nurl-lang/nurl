import A3.Make
import A3.LockDtorWitness

/-! A3 — Agora #755 item 1: on A3's threads, the thread whose step drops an
orphan's last share runs its destructor.

`TStep.thread` ends a thread's step with the configuration's marking sweep
(`Cfg.sweepD`, from every thread's slots and the module globals) and the
same thread's reaps (`CSettle`), as A2's `Steps` ends a step with
`Mem.sweepD` and `Settle`.  This file draws the two facts that make that
honest on every run the claim covers:

- **no thread is held up by it** (`reach_thread_total`): in every
  configuration a typed start reaches, every A2 step of a thread (but a
  spawn's) is the start of a configuration step: the reaps after it can be
  taken and end (`CSettle.total`);
- **the destructor runs on the thread that drops the last share**
  (`TStep.last_drop_reaps`, and its instances at the three witnesses of a
  share of a destructor value: `arcDtor_reaps`, `arcVecDtor_reaps`,
  `lockDtor_reaps`): when thread `i`'s step leaves such a block that no
  thread's slot, no global and no payload refers to, the marking sweep marks
  it, and a step of thread `i`, before any other thread's, moves its payload
  to a fresh slot of thread `i`, in a destructor frame (`Step.reap`). -/

namespace A3
open A2

/-- The downward frame lemma, proved (`A3.Restrict`). -/
theorem restrictLemma (P : Prog) : RestrictLemma P :=
  fun h => fun hav hb hp hf => Step.restrict h hav hb hp hf

/-- **Every A2 step of a thread is one of the configuration's**, in every
    configuration a typed start reaches (a spawn's but its own rule's): the
    eager reaping of `TStep.thread` holds up no thread, so `MemorySafe`'s
    progress (an A2 step of every thread that is not finished or waiting) is
    progress of the configuration. -/
theorem reach_thread_total {P : Prog} {spawn : Nat → Bool} {G : Globs} {s : Stmt} {Δ : Ctx} {nv : Nat}
    (hP : ProgOK P) (hPc : ProgCodes P) (hSp : SpawnOK P spawn) (hG : GlobsOK P G)
    (ht : StmtT P (fun _ => none) [] s Δ) (hs : s.src = true) (hsc : s.codesOK P)
    (hv : ∀ v ∈ s.vars, v < nv) {C : Cfg} (hr : Reach P spawn (Cfg.start G s nv) C)
    {i : Nat} {t : Thread} {m' : Mem} {s' : Stmt} (hi : C.ths[i]? = some t) (hsp : ¬ SpawnRedex spawn t.s)
    (hst : Step P (C.view t) t.s (.ok m' s')) : ∃ C', TStep P spawn C C' :=
  TStep.thread_total hP hPc (restrictLemma P) (reach_inv hP hPc hSp hG ht hs hsc hv hr).1 hi hsp hst

/-- Agora #755 item 1, at `A3.arcDtor_claim`'s witness's program: **an `Arc`
    of a destructor value whose last share thread `i`'s step drops is reaped
    by thread `i`**: the marking sweep marks its block, and a step of thread
    `i` (before any other thread's) moves the payload to a fresh slot of its
    own, in a frame `scopeD _ 0 skip` whose end calls the destructor `dfn`
    (`A2.Dtor.scopeD_end_runs_dtor`). -/
theorem arcDtor_reaps {C : Cfg} {i : Nat} {m' : Mem} {s' : Stmt} {C' : Cfg}
    (hse : CSettle A2.DtorWitness.P i (C.put i m' s').sweepD C') {k : Nat} {p : Val}
    (hk : m'.blk k = some ⟨A2.DtorWitness.DT, .arc, some p⟩)
    (hv : ∀ v, (C.put i m' s').roots v → ¬ Refers m'.blk v k)
    (hb : ∀ k' bl', m'.blk k' = some bl' → ¬ Refers m'.blk bl'.keeps k) :
    (C.put i m' s').sweepD.blk k = some ⟨A2.DtorWitness.DT, .dead, some p⟩ ∧
      ∃ (Y : Cfg) (t1 : Thread) (m1 : Mem) (s1 : Stmt), Y.ths[i]? = some t1 ∧
        Step A2.DtorWitness.P (Y.view t1) t1.s (.ok m1 s1) ∧
        m1.blk k = some ⟨A2.DtorWitness.DT, .dead, none⟩ ∧ m1.st t1.nv = some ⟨true, some p⟩ :=
  TStep.last_drop_reaps (n := 0) (f := 0) (u := A2.DtorWitness.T) hse (Or.inl rfl) hk hv hb

/-- ... and (`A3.arcVecDtor_claim`'s witness) an `Arc` of a `Vec` of them:
    thread `i` reaps it, binding the `Vec` at its own type in a destructor
    frame whose end drains it (`A2.ArcDtorWitness.reapV_drains`). -/
theorem arcVecDtor_reaps {C : Cfg} {i : Nat} {m' : Mem} {s' : Stmt} {C' : Cfg}
    (hse : CSettle A2.DtorWitness.P i (C.put i m' s').sweepD C') {k : Nat} {p : Val}
    (hk : m'.blk k = some ⟨.vec A2.DtorWitness.DT, .arc, some p⟩)
    (hv : ∀ v, (C.put i m' s').roots v → ¬ Refers m'.blk v k)
    (hb : ∀ k' bl', m'.blk k' = some bl' → ¬ Refers m'.blk bl'.keeps k) :
    (C.put i m' s').sweepD.blk k = some ⟨.vec A2.DtorWitness.DT, .dead, some p⟩ ∧
      ∃ (Y : Cfg) (t1 : Thread) (m1 : Mem) (s1 : Stmt), Y.ths[i]? = some t1 ∧
        Step A2.DtorWitness.P (Y.view t1) t1.s (.ok m1 s1) ∧
        m1.blk k = some ⟨.vec A2.DtorWitness.DT, .dead, none⟩ ∧ m1.st t1.nv = some ⟨true, some p⟩ :=
  TStep.last_drop_reaps (n := 1) (f := 0) (u := A2.DtorWitness.T) hse (Or.inl rfl) hk hv hb

/-- ... and (`A3.lockDtor_claim`'s witness, `Locked D`) a lock of a destructor
    value whose last share thread `i`'s step drops, its payload in it: thread
    `i` reaps it, as nurlc's last `Locked_drop` drops the value on the
    thread that runs it. -/
theorem lockDtor_reaps {C : Cfg} {i : Nat} {m' : Mem} {s' : Stmt} {C' : Cfg}
    (hse : CSettle A3.LockDtorWitness.P i (C.put i m' s').sweepD C') {k : Nat} {p : Val}
    (hk : m'.blk k = some ⟨A2.DtorWitness.DT, .lock, some p⟩)
    (hv : ∀ v, (C.put i m' s').roots v → ¬ Refers m'.blk v k)
    (hb : ∀ k' bl', m'.blk k' = some bl' → ¬ Refers m'.blk bl'.keeps k) :
    (C.put i m' s').sweepD.blk k = some ⟨A2.DtorWitness.DT, .dead, some p⟩ ∧
      ∃ (Y : Cfg) (t1 : Thread) (m1 : Mem) (s1 : Stmt), Y.ths[i]? = some t1 ∧
        Step A3.LockDtorWitness.P (Y.view t1) t1.s (.ok m1 s1) ∧
        m1.blk k = some ⟨A2.DtorWitness.DT, .dead, none⟩ ∧ m1.st t1.nv = some ⟨true, some p⟩ :=
  TStep.last_drop_reaps (n := 0) (f := 0) (u := A2.DtorWitness.T) hse (Or.inr rfl) hk hv hb

/-- **A global `Locked D` is never reaped**: the marking sweep roots the
    module globals, so a block a global's share names is kept as it was, at
    every thread's step (#755's review: `A2.Mem.sweepD` roots the slots only;
    A3's must root the globals too). -/
theorem glob_not_marked {C : Cfg} {g : Nat} {k : Nat} {bl : Blk} (hg : C.gl g = some (.lk k))
    (hk : C.blk k = some bl) : C.sweepD.blk k = some bl :=
  Cfg.sweepD_glob hg hk (.inl (.inl ⟨none, Sub.refl _⟩))

end A3
