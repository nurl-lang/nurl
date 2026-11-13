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
  configuration a typed start reaches, every A2 step of a thread to an
  `.ok` result, at no spawn redex, is the start of a configuration step: the
  reaps after it can be taken and end (`CSettle.total`).  (As before the
  reaps, a top-level step to `.panic` is no configuration step, and no
  lemma here shows a spawn redex always has `TStep.spawn` or `spawnFail`);
- **the destructor runs on the thread that drops the last share**
  (`TStep.last_drop_reaps`, and its instances at the witnesses of a
  share of a destructor value: `arcDtor_reaps`, `arcVecDtor_reaps`,
  `lockDtor_reaps`, `lockVecDtor_reaps`): when thread `i`'s step leaves such a block that no
  thread's slot, no global and no payload refers to, the marking sweep marks
  it, and in the result of that configuration step (whose reaps are all
  thread `i`'s, before any other thread runs) a fresh slot of thread `i`
  owns its payload and the block is emptied or gone: a reap of thread `i`
  bound it there, in a destructor frame (`Step.reap`). -/

namespace A3
open A2

/-- The downward frame lemma, proved (`A3.Restrict`). -/
theorem restrictLemma (P : Prog) : RestrictLemma P :=
  fun h => fun hav hb hp hf => Step.restrict h hav hb hp hf

/-- **Every `.ok` A2 step of a thread, at no spawn redex, is the start of one
    of the configuration's**, in every configuration a typed start reaches:
    the eager reaping of `TStep.thread` holds up no such step.  (A top-level
    step to `.panic` is no configuration step, as before the reaps; that a
    spawn redex always has `TStep.spawn` or `spawnFail` is not proved here.) -/
theorem reach_thread_total {P : Prog} {spawn : Nat → Bool} {G : Globs} {s : Stmt} {Δ : Ctx} {nv : Nat}
    (hP : ProgOK P) (hPc : ProgCodes P) (hSp : SpawnOK P spawn) (hG : GlobsOK P G)
    (ht : StmtT P (fun _ => none) [] s Δ) (hs : s.src = true) (hsc : s.codesOK P)
    (hv : ∀ v ∈ s.vars, v < nv) {C : Cfg} (hr : Reach P spawn (Cfg.start G s nv) C)
    {i : Nat} {t : Thread} {m' : Mem} {s' : Stmt} (hi : C.ths[i]? = some t) (hsp : ¬ SpawnRedex spawn t.s)
    (hst : Step P (C.view t) t.s (.ok m' s')) : ∃ C', TStep P spawn C C' :=
  TStep.thread_total hP hPc (restrictLemma P) (reach_inv hP hPc hSp hG ht hs hsc hv hr).1 hi hsp hst

/-- Agora #755 item 1, at `A3.arcDtor_claim`'s witness's program: **an `Arc`
    of a destructor value whose last share thread `i`'s step drops is reaped
    by thread `i` in that configuration step**: the marking sweep marks its
    block, and in the step's result `C'` a fresh slot of thread `i` owns the
    payload (a reap of thread `i`, before any other thread ran, bound it in a
    frame `scopeD _ 0 skip` whose end calls the destructor `dfn`,
    `A2.Dtor.scopeD_end_runs_dtor`) and the block is emptied or gone. -/
theorem arcDtor_reaps {C : Cfg} {i : Nat} {m' : Mem} {s' : Stmt} {C' : Cfg} (hlen : i < C.ths.length)
    (hse : CSettle A2.DtorWitness.P i (C.put i m' s').sweepD C') {k : Nat} {p : Val}
    (hk : m'.blk k = some ⟨A2.DtorWitness.DT, .arc, some p⟩)
    (hv : ∀ v, (C.put i m' s').roots v → ¬ Refers m'.blk v k)
    (hb : ∀ k' bl', m'.blk k' = some bl' → ¬ Refers m'.blk bl'.keeps k) :
    (C.put i m' s').sweepD.blk k = some ⟨A2.DtorWitness.DT, .dead, some p⟩ ∧
      ∃ (t' : Thread) (x : Var), C'.ths[i]? = some t' ∧ t'.st x = some ⟨true, some p⟩ ∧ m'.nv ≤ x ∧
        Emptied C'.blk k (A2.DtorWitness.DT) :=
  TStep.last_drop_reaps (n := 0) (f := 0) (u := A2.DtorWitness.T) hlen hse (Or.inl rfl) hk (CutOff.one hv hb) rfl

/-- ... and (`A3.arcVecDtor_claim`'s witness) an `Arc` of a `Vec` of them:
    thread `i` reaps it in that configuration step, binding the `Vec` at its
    own type in a destructor frame whose end drains it
    (`A2.ArcDtorWitness.reapV_drains`). -/
theorem arcVecDtor_reaps {C : Cfg} {i : Nat} {m' : Mem} {s' : Stmt} {C' : Cfg} (hlen : i < C.ths.length)
    (hse : CSettle A2.DtorWitness.P i (C.put i m' s').sweepD C') {k : Nat} {p : Val}
    (hk : m'.blk k = some ⟨.vec A2.DtorWitness.DT, .arc, some p⟩)
    (hv : ∀ v, (C.put i m' s').roots v → ¬ Refers m'.blk v k)
    (hb : ∀ k' bl', m'.blk k' = some bl' → ¬ Refers m'.blk bl'.keeps k) :
    (C.put i m' s').sweepD.blk k = some ⟨.vec A2.DtorWitness.DT, .dead, some p⟩ ∧
      ∃ (t' : Thread) (x : Var), C'.ths[i]? = some t' ∧ t'.st x = some ⟨true, some p⟩ ∧ m'.nv ≤ x ∧
        Emptied C'.blk k (.vec A2.DtorWitness.DT) :=
  TStep.last_drop_reaps (n := 1) (f := 0) (u := A2.DtorWitness.T) hlen hse (Or.inl rfl) hk (CutOff.one hv hb) rfl

/-- ... and (`A3.lockDtor_claim`'s witness, `Locked D`) a lock of a destructor
    value whose last share thread `i`'s step drops, its payload in it: thread
    `i` reaps it in that configuration step, as nurlc's last `Locked_drop`
    drops the value on the thread that runs it. -/
theorem lockDtor_reaps {C : Cfg} {i : Nat} {m' : Mem} {s' : Stmt} {C' : Cfg} (hlen : i < C.ths.length)
    (hse : CSettle A3.LockDtorWitness.P i (C.put i m' s').sweepD C') {k : Nat} {p : Val}
    (hk : m'.blk k = some ⟨A2.DtorWitness.DT, .lock, some p⟩)
    (hv : ∀ v, (C.put i m' s').roots v → ¬ Refers m'.blk v k)
    (hb : ∀ k' bl', m'.blk k' = some bl' → ¬ Refers m'.blk bl'.keeps k) :
    (C.put i m' s').sweepD.blk k = some ⟨A2.DtorWitness.DT, .dead, some p⟩ ∧
      ∃ (t' : Thread) (x : Var), C'.ths[i]? = some t' ∧ t'.st x = some ⟨true, some p⟩ ∧ m'.nv ≤ x ∧
        Emptied C'.blk k (A2.DtorWitness.DT) :=
  TStep.last_drop_reaps (n := 0) (f := 0) (u := A2.DtorWitness.T) hlen hse (Or.inr rfl) hk (CutOff.one hv hb) rfl

/-- ... and (`A3.lockVecDtor_claim`'s witness, `Locked (Vec D)`) a lock of a
    drained `Vec` of destructor values whose last share thread `i`'s step
    drops, its payload in it: thread `i` reaps it in that configuration step,
    binding the `Vec` at its own type in a destructor frame whose end drains
    it (`A3.LockDtorWitness.reapV_drains`), as nurlc's last `Locked_drop`
    drops the `Vec`'s elements on the thread that runs it. -/
theorem lockVecDtor_reaps {C : Cfg} {i : Nat} {m' : Mem} {s' : Stmt} {C' : Cfg} (hlen : i < C.ths.length)
    (hse : CSettle A3.LockDtorWitness.P i (C.put i m' s').sweepD C') {k : Nat} {p : Val}
    (hk : m'.blk k = some ⟨.vec A2.DtorWitness.DT, .lock, some p⟩)
    (hv : ∀ v, (C.put i m' s').roots v → ¬ Refers m'.blk v k)
    (hb : ∀ k' bl', m'.blk k' = some bl' → ¬ Refers m'.blk bl'.keeps k) :
    (C.put i m' s').sweepD.blk k = some ⟨.vec A2.DtorWitness.DT, .dead, some p⟩ ∧
      ∃ (t' : Thread) (x : Var), C'.ths[i]? = some t' ∧ t'.st x = some ⟨true, some p⟩ ∧ m'.nv ≤ x ∧
        Emptied C'.blk k (.vec A2.DtorWitness.DT) :=
  TStep.last_drop_reaps (n := 1) (f := 0) (u := A2.DtorWitness.T) hlen hse (Or.inr rfl) hk (CutOff.one hv hb) rfl

/-- **A global `Locked D` is never reaped**: the marking sweep roots the
    module globals, so a block a global's share names is kept as it was, at
    every thread's step (#755's review: `A2.Mem.sweepD` roots the slots only;
    A3's must root the globals too). -/
theorem glob_not_marked {C : Cfg} {g : Nat} {k : Nat} {bl : Blk} (hg : C.gl g = some (.lk k))
    (hk : C.blk k = some bl) : C.sweepD.blk k = some bl :=
  Cfg.sweepD_glob hg hk (.inl (.inl ⟨none, Sub.refl _⟩))

end A3
