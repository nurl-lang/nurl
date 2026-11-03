import A3.Cell

/-! A3.0 — the claim, from the configuration invariant.

Every reachable configuration keeps the invariant: the start has it
(`CInv.init`), a thread's step and the sweep that ends it keep it
(`CInv.thread_of`), and so does a spawn.  From it, no thread is stuck (A2's progress on the thread's part,
lifted to the shared address space), no two threads race (`CInv.raceFree`)
and nothing is left allocated once every thread has finished
(`CInv.noLeak`).  The frame lemmas and the spawn case are hypotheses here,
discharged where they are proved. -/

namespace A3
open A2

/-- The upward frame lemma's statement (proved in `A3.Lift`). -/
def LiftLemma (P : Prog) : Prop :=
  ∀ {m : Mem} {s : Stmt} {r : Res}, Step P m s r → ∀ {a2 : Nat → Bool},
    (∀ i, m.alloc i = true → a2 i = false) → FreshFrom a2 m.nid →
    ∃ r', Step P { m with alloc := union m.alloc a2 } s r'

/-- **No thread is stuck.** -/
theorem CInv.memSafe_of {P : Prog} (hP : ProgOK P) (hL : LiftLemma P) {C : Cfg} (h : CInv P C) :
    ∀ (i : Nat) (t : Thread), C.ths[i]? = some t → ¬ Stuck P (C.view t) t.s := by
  intro i t hi ⟨hne, hnb, hno⟩
  obtain ⟨ps, hc, _⟩ := h
  have hlt := hc.lt_nid hi
  obtain ⟨a, ha⟩ := part_of hc.len hi
  obtain ⟨hto, _⟩ := hc.ok i t a hi ha
  rcases ThreadOK.progress hP hto with hs | hb | ⟨r, hr⟩
  · exact hne hs
  · -- A3.2: waiting for a lock is not stuck
    exact hnb (Blocked.of_eq (m := ownView C t a) (m' := C.view t) rfl rfl hb)
  · have hd : ∀ k, (ownView C t a).alloc k = true → minus C.alloc (union a (payPart C.blk)) k = false :=
      fun k hk => minus_disj k hk
    have hf : FreshFrom (minus C.alloc (union a (payPart C.blk))) (ownView C t a).nid := fun k hk => by
      cases hk' : minus C.alloc (union a (payPart C.blk)) k with
      | false => rfl
      | true => exact absurd (hlt k (minus_le k hk')) (Nat.not_lt.mpr hk)
    obtain ⟨r', hr'⟩ := hL hr hd hf
    have heq : { ownView C t a with
        alloc := union (ownView C t a).alloc (minus C.alloc (union a (payPart C.blk))) } = C.view t := by
      simp only [ownView, Cfg.view, union_minus (hc.view_sub ha)]
    rw [heq] at hr'
    exact hno r' hr'

/-- **Every reachable configuration keeps the invariant** (A3.5: and the
    cells' homes, `CellInv`). -/
theorem reach_cinv {P : Prog} {spawn : Nat → Bool} (hP : ProgOK P) (hPc : ProgCodes P)
    (hR : RestrictLemma P)
    (hS : ∀ {C : Cfg} {i : Nat} {t : Thread} {K : Stmt → Stmt} {x f : Nat} {args : List Var}
      {k : Stmt} {fn : Fn} {vs : List Val} {st' : Var → Option Slot},
      CInv P C → C.ths[i]? = some t → Redex t.s K (.letcall x f args k) → spawn f = true →
      P[f]? = some fn → t.st x = none → MoveArgs t.st args vs st' →
      CInv P { C with ths := C.ths.set i ⟨upd st' x (some ⟨false, some (.int 0)⟩), t.nv, K (.scope x k)⟩ ++
                        [⟨spawnSt fn vs, fn.nvars,
                          wrapParams fn.params 0 0 (.scope fn.params.length fn.body)⟩] })
    (hF : ∀ {C : Cfg} {i : Nat} {t : Thread} {K : Stmt → Stmt} {x f : Nat} {args : List Var} {k : Stmt},
      CInv P C → C.ths[i]? = some t → Redex t.s K (.letcall x f args k) →
      CInv P { C with ths := C.ths.set i ⟨t.st, t.nv, K (.seq .panic (.letcall x f args k))⟩ })
    {C C' : Cfg} (h : CInv P C) (hc : CellInv C) (hr : Reach P spawn C C') : CInv P C' ∧ CellInv C' := by
  induction hr with
  | refl => exact ⟨h, hc⟩
  | step hst _ ih =>
    cases hst with
    | thread hi _ hs => exact ih (CInv.thread_of hP hPc hR h hi hs) (hc.thread_of hi hs)
    | spawn hi hK hsp hf hx hmv hsc => exact ih (hS h hi hK hsp hf hx hmv) (hc.spawn_of hi hmv hsc)
    | spawnFail hi hK _ _ _ _ _ => exact ih (hF h hi hK) (hc.setStmt hi _)

/-- **A3.0**, given the frame lemmas and the spawn case. -/
theorem claim_of
    (hR : ∀ P, RestrictLemma P) (hL : ∀ P, LiftLemma P)
    (hS : ∀ (P : Prog) (spawn : Nat → Bool), ProgOK P → ProgCodes P → SpawnOK P spawn →
      ∀ {C : Cfg} {i : Nat} {t : Thread} {K : Stmt → Stmt} {x f : Nat} {args : List Var}
      {k : Stmt} {fn : Fn} {vs : List Val} {st' : Var → Option Slot},
      CInv P C → C.ths[i]? = some t → Redex t.s K (.letcall x f args k) → spawn f = true →
      P[f]? = some fn → t.st x = none → MoveArgs t.st args vs st' →
      CInv P { C with ths := C.ths.set i ⟨upd st' x (some ⟨false, some (.int 0)⟩), t.nv, K (.scope x k)⟩ ++
                        [⟨spawnSt fn vs, fn.nvars,
                          wrapParams fn.params 0 0 (.scope fn.params.length fn.body)⟩] })
    (hF : ∀ (P : Prog), ∀ {C : Cfg} {i : Nat} {t : Thread} {K : Stmt → Stmt} {x f : Nat} {args : List Var}
      {k : Stmt}, CInv P C → C.ths[i]? = some t → Redex t.s K (.letcall x f args k) →
      CInv P { C with ths := C.ths.set i ⟨t.st, t.nv, K (.seq .panic (.letcall x f args k))⟩ }) :
    Claim := by
  intro P spawn G s Δ nv hP hPc hSp hG ht hs hsc hv
  have h0 := CInv.start ht hs hsc hv hG
  have hreach : ∀ C, Reach P spawn (Cfg.start G s nv) C → CInv P C ∧ CellInv C :=
    fun C hr => reach_cinv hP hPc (hR P) (hS P spawn hP hPc hSp) (hF P) h0 (CellInv.start hG s nv) hr
  refine ⟨fun C hr => CInv.memSafe_of hP (hL P) (hreach C hr).1,
    fun C hr hrace => hrace.elim (CInv.raceFree (hreach C hr).1) (CellInv.cellRaceFree (hreach C hr).2),
    fun C hr hend i hi => ?_⟩
  -- A3.6: what is left is what the start's globals reach: no step wrote them
  obtain ⟨k, bl, hk, hik, hgr⟩ := CInv.noLeak (hreach C hr).1 hend i hi
  exact ⟨k, bl, hk, hik, hgr.roots (fun v ⟨g, hg⟩ => ⟨g, by rw [← Reach.gl hr]; exact hg⟩)⟩

end A3
