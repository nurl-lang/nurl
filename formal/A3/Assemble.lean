import A3.Pres

/-! A3.0 — the claim, from the configuration invariant.

Every reachable configuration keeps the invariant: the start has it
(`CInv.init`), a thread's step keeps it (`CInv.thread_of`), and so does a
spawn.  From it, no thread is stuck (A2's progress on the thread's part,
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
  intro i t hi ⟨hne, hno⟩
  have hlt := CInv.lt_nid h
  obtain ⟨ps, hlen, hall, _, hok⟩ := h
  obtain ⟨a, ha⟩ := part_of hlen hi
  obtain ⟨hto, _⟩ := hok i t a hi ha
  rcases ThreadOK.progress hP hto with hs | ⟨r, hr⟩
  · exact hne hs
  · have hd : ∀ k, (ownView C t a).alloc k = true → minus C.alloc a k = false :=
      fun k hk => minus_disj k hk
    have hf : FreshFrom (minus C.alloc a) (ownView C t a).nid := fun k hk => by
      cases hk' : minus C.alloc a k with
      | false => rfl
      | true => exact absurd (hlt k (minus_le k hk')) (Nat.not_lt.mpr hk)
    obtain ⟨r', hr'⟩ := hL hr hd hf
    have heq : { ownView C t a with alloc := union (ownView C t a).alloc (minus C.alloc a) } = C.view t := by
      simp only [ownView, Cfg.view, union_minus (part_sub hall ha)]
    rw [heq] at hr'
    exact hno r' hr'

/-- **Every reachable configuration keeps the invariant.** -/
theorem reach_cinv {P : Prog} {spawn : Nat → Bool} (hP : ProgOK P) (hPc : ProgCodes P)
    (hR : RestrictLemma P)
    (hS : ∀ {C : Cfg} {i : Nat} {t : Thread} {K : Stmt → Stmt} {x f : Nat} {args : List Var}
      {k : Stmt} {fn : Fn} {vs : List Val} {st' : Var → Option Slot},
      CInv P C → C.ths[i]? = some t → Redex t.s K (.letcall x f args k) → spawn f = true →
      P[f]? = some fn → t.st x = none → MoveArgs t.st args vs st' →
      CInv P { C with ths := C.ths.set i ⟨upd st' x (some ⟨false, some (.int 0)⟩), t.nv, K (.scope x k)⟩ ++
                        [⟨spawnSt fn vs, fn.nvars,
                          wrapParams fn.params 0 0 (.scope fn.params.length fn.body)⟩] })
    {C C' : Cfg} (h : CInv P C) (hr : Reach P spawn C C') : CInv P C' := by
  induction hr with
  | refl => exact h
  | step hst _ ih =>
    apply ih
    cases hst with
    | thread hi _ hs => exact CInv.thread_of hP hPc hR h hi hs
    | spawn hi hK hsp hf hx hmv => exact hS h hi hK hsp hf hx hmv

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
                          wrapParams fn.params 0 0 (.scope fn.params.length fn.body)⟩] }) :
    Claim := by
  intro P spawn s Δ nv hP hPc hSp ht hs hsc hv
  have h0 := CInv.init ht hs hsc hv
  have hreach : ∀ C, Reach P spawn (Cfg.init s nv) C → CInv P C :=
    fun C hr => reach_cinv hP hPc (hR P) (hS P spawn hP hPc hSp) h0 hr
  exact ⟨fun C hr => CInv.memSafe_of hP (hL P) (hreach C hr),
    fun C hr => CInv.raceFree (hreach C hr),
    fun C hr hend => CInv.noLeak (hreach C hr) hend⟩

end A3
