module

public import A3.Reap
public import A3.LockDtorWitness

@[expose] public section

/-! `A3.TStep.last_drop_reaps` at the witnesses of a share of a destructor
value (Agora #755): `Arc D`, `Arc (Vec D)`, `Locked D`, `Locked (Vec D)`.
Apart from `A3/Reap.lean` so that a certificate, which imports the reap
lemmas, loads no witness program (AGORA-1013). -/

namespace A3
open A2

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

end A3
