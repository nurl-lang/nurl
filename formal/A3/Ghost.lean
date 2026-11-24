import A3.Rel

/-! A3.0 — the store a `recover` frame remembers is a ghost.

`Step.letrec` puts the stepping store into the statement
(`catchR x m0 _`).  No step reads it (`catchP` continues from the unwound
store), and the typing reads only its bindings, its `nv`, and that its
owned trees are live and below its `nid`.  So a statement whose remembered
stores have more addresses live is typed, and keeps A2's invariant,
whenever the original is: `GhostRel` transports every per-thread fact. -/

namespace A3
open A2

theorem GhostRel.spine {s s' : Stmt} (h : GhostRel s s') : s'.spine = s.spine := by
  induction h with
  | refl => rfl
  | seq _ _ ih => simpa only [Stmt.spine] using ih
  | scope _ _ ih => simp only [Stmt.spine, ih]
  | scopeD _ _ _ ih => simp only [Stmt.spine, ih]
  | rbind _ _ ih => simp only [Stmt.spine, ih]
  | frozen _ _ ih => simpa only [Stmt.spine] using ih
  | block _ ih => simpa only [Stmt.spine] using ih
  | catchR _ _ _ _ _ _ _ ih => simpa only [Stmt.spine] using ih
  | scopeL _ _ _ _ ih => simp only [Stmt.spine, ih]

theorem GhostRel.vars {s s' : Stmt} (h : GhostRel s s') : s'.vars = s.vars := by
  induction h with
  | refl => rfl
  | seq _ _ ih => simp only [Stmt.vars, ih]
  | scope _ _ ih => simp only [Stmt.vars, ih]
  | scopeD _ _ _ ih => simp only [Stmt.vars, ih]
  | rbind _ _ ih => simp only [Stmt.vars, ih]
  | frozen _ _ ih => simp only [Stmt.vars, ih]
  | block _ ih => simp only [Stmt.vars, ih]
  | catchR _ _ _ _ _ _ _ ih => simp only [Stmt.vars, ih]
  | scopeL _ _ _ _ ih => simp only [Stmt.vars, ih]

theorem GhostRel.killVars {s s' : Stmt} (h : GhostRel s s') : s'.killVars = s.killVars := by
  induction h with
  | refl => rfl
  | seq _ _ ih => simp only [Stmt.killVars, ih]
  | scope _ _ ih => simp only [Stmt.killVars, ih]
  | scopeD _ _ _ ih => simp only [Stmt.killVars, ih]
  | rbind _ _ ih => simp only [Stmt.killVars, ih]
  | frozen _ _ ih => simp only [Stmt.killVars, ih]
  | block _ ih => simp only [Stmt.killVars, ih]
  | catchR _ _ _ _ _ _ _ ih => simp only [Stmt.killVars, ih]
  | scopeL _ _ _ _ ih => simp only [Stmt.killVars, ih]

theorem GhostRel.codesOK {P : Prog} {s s' : Stmt} (h : GhostRel s s') (hc : s.codesOK P) :
    s'.codesOK P := by
  induction h with
  | refl => exact hc
  | seq _ _ ih => exact ⟨ih hc.1, hc.2⟩
  | scope _ _ ih => exact ih hc
  | scopeD _ _ _ ih => exact ih hc
  | rbind _ _ ih => exact ih hc
  | frozen _ _ ih => exact ih hc
  | block _ ih => exact ih hc
  | catchR _ _ _ _ _ _ _ ih => exact ih hc
  | scopeL _ _ _ _ ih => exact ih hc

theorem GhostRel.catchOK {m : Mem} {s s' : Stmt} (h : GhostRel s s') (hc : CatchOK m s) :
    CatchOK m s' := by
  induction h with
  | refl => exact hc
  | seq _ _ ih => exact ih hc
  | scope _ _ ih => exact ih hc
  | scopeD _ _ _ ih => exact ih hc
  | rbind _ _ ih => exact ih hc
  | frozen _ _ ih => exact ih hc
  | block _ ih => exact ih hc
  | scopeL _ _ _ _ ih => exact ih hc
  | @catchR x m0 m0' s s' hst hnv _ hblk _ hg ih =>
    obtain ⟨h1, h2, h3, h4, h5⟩ := hc
    have hsp := hg.spine
    have hov : OutVals m0' x s'.spine = OutVals m0 x s.spine := by
      funext v; simp only [OutVals, hst, hsp]
    refine ⟨fun v hv hx => ?_, by rw [hsp]; exact h2, by rw [hnv]; exact h3, by rw [hblk, hov]; exact h4,
      ih h5⟩
    rw [hst]; exact h1 v (by rw [← hsp]; exact hv) hx

theorem GhostRel.pinOK {Γ : Ctx} {s s' : Stmt} (h : GhostRel s s') (hp : PinOK Γ s) : PinOK Γ s' := by
  induction h with
  | refl => exact hp
  | seq _ _ ih => exact ih hp
  | scope _ _ ih => exact ih hp
  | scopeD _ _ _ ih => exact ih hp
  | rbind _ hg ih => exact ⟨fun E hE hm r hr => by rw [hg.spine]; exact hp.1 E hE hm r hr, ih hp.2⟩
  | frozen _ _ ih => exact ih hp
  | block _ ih => exact ih hp
  | catchR _ _ _ _ _ _ _ ih => exact ih hp
  | scopeL _ _ _ _ ih => exact ih hp

theorem GhostRel.dtorPinOK {Γ : Ctx} {s s' : Stmt} (h : GhostRel s s') (hp : DtorPinOK Γ s) :
    DtorPinOK Γ s' := by
  have hin : ∀ {x : Var} {k k' : Stmt}, GhostRel k k' → DtorIn Γ x k → DtorIn Γ x k' :=
    fun hg hx E hE hd hos hn d hdd hnm => by rw [hg.spine]; exact hx E hE hd hos hn d hdd hnm
  induction h with
  | refl => exact hp
  | seq _ _ ih => exact ih hp
  | scope _ hg ih => exact ⟨hin hg hp.1, ih hp.2⟩
  | scopeD _ _ hg ih => exact ⟨hin hg hp.1, ih hp.2⟩
  | rbind _ hg ih => exact ⟨hin hg hp.1, ih hp.2⟩
  | frozen _ _ ih => exact ih hp
  | block _ ih => exact ih hp
  | catchR _ _ _ _ _ _ _ ih => exact ih hp
  | scopeL _ _ _ hg ih => exact ⟨hin hg hp.1, ih hp.2⟩

theorem GhostRel.closed {Γ : Ctx} {s s' : Stmt} (h : GhostRel s s') (hc : Closed Γ s) : Closed Γ s' :=
  fun v hv => by rw [h.spine]; exact hc v hv

theorem inv_ghost {m : Mem} {Γ : Ctx} {F : List Var} {s s' : Stmt} (hi : Inv m Γ F s)
    (hg : GhostRel s s') : Inv m Γ F s' :=
  hi.respine hg.spine (fun v hv => by rw [hg.vars] at hv; exact hv) (hg.catchOK hi.catchOK)
    (hg.pinOK hi.pinIn) (hg.dtorPinOK hi.dtorIn) (fun v hv => by rw [hg.killVars] at hv; exact hv)

/-! ### Typing, frame by frame

Each frame types its body in the frame's own contexts; `StmtT.sub` may wrap
it.  So a body that is typed wherever the old one was gives the frame. -/

theorem StmtT.seq_repl {P : Prog} {Γ : Ctx} {F : List Var} {a b : Stmt} {Δ : Ctx}
    (ht : StmtT P ξ Γ F (.seq a b) Δ) {a' : Stmt}
    (hrep : ∀ {ξ' Γ' F' Δ'}, StmtT P ξ' Γ' F' a Δ' → StmtT P ξ' Γ' F' a' Δ') : StmtT P ξ Γ F (.seq a' b) Δ := by
  generalize hs : Stmt.seq a b = s at ht
  induction ht with
  | seq hb ha hbt _ _ => cases hs; exact .seq hb (hrep ha) hbt
  | sub hw _ hd ih => exact .sub hw (ih hs) hd
  | _ => cases hs

theorem StmtT.scope_repl {P : Prog} {Γ : Ctx} {F : List Var} {x : Var} {s : Stmt} {Δ : Ctx}
    (ht : StmtT P ξ Γ F (.scope x s) Δ) {s' : Stmt}
    (hrep : ∀ {ξ' Γ' F' Δ'}, StmtT P ξ' Γ' F' s Δ' → StmtT P ξ' Γ' F' s' Δ') : StmtT P ξ Γ F (.scope x s') Δ := by
  generalize hs : Stmt.scope x s = s0 at ht
  induction ht with
  | scope hE hx hb hp _ => cases hs; exact .scope hE hx (hrep hb) hp
  | sub hw _ hd ih => exact .sub hw (ih hs) hd
  | _ => cases hs

theorem StmtT.rbind_repl {P : Prog} {Γ : Ctx} {F : List Var} {p : Var} {s : Stmt} {Δ : Ctx}
    (ht : StmtT P ξ Γ F (.rbind p s) Δ) {s' : Stmt}
    (hkv : s'.killVars = s.killVars)
    (hrep : ∀ {ξ' Γ' F' Δ'}, StmtT P ξ' Γ' F' s Δ' → StmtT P ξ' Γ' F' s' Δ') : StmtT P ξ Γ F (.rbind p s') Δ := by
  generalize hs : Stmt.rbind p s = s0 at ht
  induction ht with
  | rbind hE hm hl ha hp hb hd _ => cases hs; exact .rbind hE hm hl (by rw [hkv]; exact ha) hp (hrep hb) hd
  | sub hw _ hd ih => exact .sub hw (ih hs) hd
  | _ => cases hs

theorem StmtT.frozen_repl {P : Prog} {Γ : Ctx} {F : List Var} {z : List Var} {s : Stmt} {Δ : Ctx}
    (ht : StmtT P ξ Γ F (.frozen z s) Δ) {s' : Stmt}
    (hrep : ∀ {ξ' Γ' F' Δ'}, StmtT P ξ' Γ' F' s Δ' → StmtT P ξ' Γ' F' s' Δ') : StmtT P ξ Γ F (.frozen z s') Δ := by
  generalize hs : Stmt.frozen z s = s0 at ht
  induction ht with
  | frozen hb hz _ => cases hs; exact .frozen (hrep hb) hz
  | sub hw _ hd ih => exact .sub hw (ih hs) hd
  | _ => cases hs

theorem StmtT.scopeD_repl {P : Prog} {Γ : Ctx} {F : List Var} {x : Var} {f : Nat} {s : Stmt} {Δ : Ctx}
    (ht : StmtT P ξ Γ F (.scopeD x f s) Δ) {s' : Stmt} (hsp : s'.spine = s.spine)
    (hrep : ∀ {ξ' Γ' F' Δ'}, StmtT P ξ' Γ' F' s Δ' → StmtT P ξ' Γ' F' s' Δ') :
    StmtT P ξ Γ F (.scopeD x f s') Δ := by
  generalize hs : Stmt.scopeD x f s = s0 at ht
  induction ht with
  | scopeD hE hx hb hp hk hw hn hΔ hsf hfd _ =>
    cases hs; exact .scopeD hE hx (hrep hb) hp (by rw [hsp]; exact hk) hw hn hΔ hsf hfd
  | sub hw _ hd ih => exact .sub hw (ih hs) hd
  | _ => cases hs

theorem StmtT.scopeL_repl {P : Prog} {Γ : Ctx} {F : List Var} {k : Nat} {t : Ty} {x : Var} {s : Stmt}
    {Δ : Ctx} (ht : StmtT P ξ Γ F (.scopeL k t x s) Δ) {s' : Stmt} (hsp : s'.spine = s.spine)
    (hrep : ∀ {ξ' Γ' F' Δ'}, StmtT P ξ' Γ' F' s Δ' → StmtT P ξ' Γ' F' s' Δ') : StmtT P ξ Γ F (.scopeL k t x s') Δ := by
  generalize hs : Stmt.scopeL k t x s = s0 at ht
  induction ht with
  | scopeL hE hx hb hp hk hw hn hfd _ => cases hs; exact .scopeL hE hx (hrep hb) hp (by rw [hsp]; exact hk) hw hn hfd
  | sub hw _ hd ih => exact .sub hw (ih hs) hd
  | _ => cases hs

theorem StmtT.block_repl {P : Prog} {Γ : Ctx} {F : List Var} {s : Stmt} {Δ : Ctx}
    (ht : StmtT P ξ Γ F (.block s) Δ) {s' : Stmt}
    (hrep : ∀ {ξ' Γ' F' Δ'}, StmtT P ξ' Γ' F' s Δ' → StmtT P ξ' Γ' F' s' Δ') : StmtT P ξ Γ F (.block s') Δ := by
  generalize hs : Stmt.block s = s0 at ht
  induction ht with
  | block hb _ => cases hs; exact .block (hrep hb)
  | sub hw _ hd ih => exact .sub hw (ih hs) hd
  | _ => cases hs

/-- A `recover` frame whose body is retyped and whose remembered store has
    more addresses live, with the same bindings, `nv` and `nid`. -/
theorem StmtT.catchR_repl {P : Prog} {Γ : Ctx} {F : List Var} {x : Var} {m0 : Mem} {s : Stmt}
    {Δ : Ctx} (ht : StmtT P ξ Γ F (.catchR x m0 s) Δ) {m0' : Mem} {s' : Stmt}
    (hst : m0'.st = m0.st) (hnv : m0'.nv = m0.nv) (hnid : m0'.nid = m0.nid) (hblk : m0'.blk = m0.blk)
    (hal : ∀ i, m0.alloc i = true → m0'.alloc i = true) (hsp : s'.spine = s.spine)
    (hrep : ∀ {ξ' Γ' F' Δ'}, StmtT P ξ' Γ' F' s Δ' → StmtT P ξ' Γ' F' s' Δ') :
    StmtT P ξ Γ F (.catchR x m0' s') Δ := by
  generalize hs : Stmt.catchR x m0 s = s0 at ht
  induction ht with
  | catchR hx hb hmi hra hk hds _ =>
    cases hs
    have hst' : (m0'.set x ⟨false, some (.int 1)⟩).st = (m0.set x ⟨false, some (.int 1)⟩).st := by
      simp only [Mem.set, hst]
    have hmi' : MInv (m0'.set x ⟨false, some (.int 1)⟩) _ :=
      hmi.of_st hst' (heapOK_grow hmi.heap hst' hal (by simp only [Mem.set, hnid]; exact Nat.le_refl _) hblk)
        (by simp only [Mem.set, hnv]; exact Nat.le_refl _) hblk
    refine .catchR hx ?_ hmi' hra (by rw [hsp]; exact hk) (by rw [hsp]; exact hds)
    rw [hnv]; exact hrep hb
  | sub hw _ hd ih => exact .sub hw (ih hs) hd
  | _ => cases hs

/-- **A statement whose remembered stores grew is typed like the original.** -/
theorem StmtT.ghost {P : Prog} {s s' : Stmt} (hg : GhostRel s s') :
    ∀ {ξ' : Exits} {Γ F Δ}, StmtT P ξ' Γ F s Δ → StmtT P ξ' Γ F s' Δ := by
  induction hg with
  | refl => exact fun ht => ht
  | seq _ _ ih => exact fun ht => StmtT.seq_repl ht ih
  | scope _ _ ih => exact fun ht => StmtT.scope_repl ht ih
  | scopeD _ _ hg ih => exact fun ht => StmtT.scopeD_repl ht hg.spine ih
  | rbind _ hg ih => exact fun ht => StmtT.rbind_repl ht hg.killVars ih
  | frozen _ _ ih => exact fun ht => StmtT.frozen_repl ht ih
  | scopeL _ _ _ hg ih => exact fun ht => StmtT.scopeL_repl ht hg.spine ih
  | catchR _ hst hnv hnid hblk hal hg ih =>
    exact fun ht => StmtT.catchR_repl ht hst hnv hnid hblk hal hg.spine ih
  | block _ ih => exact fun ht => StmtT.block_repl ht ih

theorem GhostRel.under_kv {s s' : Stmt} (h : GhostRel s s') (p : Var) :
    (s'.under p).killVars = (s.under p).killVars := by
  induction h with
  | refl => rfl
  | seq _ hg ih =>
    simp only [Stmt.under, hg.spine]
    split
    · exact ih
    · simp only [Stmt.killVars, hg.killVars]
  | scope _ hg ih =>
    simp only [Stmt.under, hg.spine]
    split
    · exact ih
    · simp only [Stmt.killVars, hg.killVars]
  | scopeD _ _ hg ih =>
    simp only [Stmt.under, hg.spine]
    split
    · exact ih
    · simp only [Stmt.killVars, hg.killVars]
  | rbind _ hg ih =>
    simp only [Stmt.under, hg.spine]
    split
    · exact hg.killVars
    · split
      · exact ih
      · simp only [Stmt.killVars, hg.killVars]
  | frozen _ hg ih =>
    simp only [Stmt.under, hg.spine]
    split
    · exact ih
    · simp only [Stmt.killVars, hg.killVars]
  | block hg ih =>
    simp only [Stmt.under, hg.spine]
    split
    · exact ih
    · simp only [Stmt.killVars, hg.killVars]
  | catchR _ _ _ _ _ _ hg ih =>
    simp only [Stmt.under, hg.spine]
    split
    · exact ih
    · simp only [Stmt.killVars, hg.killVars]
  | scopeL _ _ _ hg ih =>
    simp only [Stmt.under, hg.spine]
    split
    · exact ih
    · simp only [Stmt.killVars, hg.killVars]

/-- A catch frame of the grown statement is one of the original's, with a
    remembered store of the same slots. -/
theorem GhostRel.catchFrames_back {s s' : Stmt} (h : GhostRel s s') :
    ∀ x m0' b', (x, m0', b') ∈ s'.catchFrames →
      ∃ m0 b, (x, m0, b) ∈ s.catchFrames ∧ m0'.st = m0.st ∧ m0'.nv = m0.nv ∧ b'.spine = b.spine := by
  induction h with
  | refl => exact fun x m0' b' h => ⟨m0', b', h, rfl, rfl, rfl⟩
  | seq _ _ ih => exact fun x m0' b' h => by simpa [Stmt.catchFrames] using ih x m0' b' (by simpa [Stmt.catchFrames] using h)
  | scope _ _ ih => exact fun x m0' b' h => by simpa [Stmt.catchFrames] using ih x m0' b' (by simpa [Stmt.catchFrames] using h)
  | scopeD _ _ _ ih => exact fun x m0' b' h => by simpa [Stmt.catchFrames] using ih x m0' b' (by simpa [Stmt.catchFrames] using h)
  | rbind _ _ ih => exact fun x m0' b' h => by simpa [Stmt.catchFrames] using ih x m0' b' (by simpa [Stmt.catchFrames] using h)
  | frozen _ _ ih => exact fun x m0' b' h => by simpa [Stmt.catchFrames] using ih x m0' b' (by simpa [Stmt.catchFrames] using h)
  | block _ ih => exact fun x m0' b' h => by simpa [Stmt.catchFrames] using ih x m0' b' (by simpa [Stmt.catchFrames] using h)
  | scopeL _ _ _ _ ih => exact fun x m0' b' h => by simpa [Stmt.catchFrames] using ih x m0' b' (by simpa [Stmt.catchFrames] using h)
  | @catchR x0 m0 m0' s s' hst hnv _ _ _ hg ih =>
    intro x m1 b1 h
    simp only [Stmt.catchFrames, List.mem_cons, Prod.mk.injEq] at h
    rcases h with ⟨rfl, rfl, rfl⟩ | h
    · exact ⟨m0, s, by simp [Stmt.catchFrames], hst, hnv, hg.spine⟩
    · obtain ⟨m2, b2, h2, h3⟩ := ih x m1 b1 h
      exact ⟨m2, b2, by simp [Stmt.catchFrames, h2], h3⟩

/-- AGORA-937 B4: **the frame clause survives remembered stores that grew**:
    the spines, the killable names and the remembered slots are the same. -/
theorem _root_.A2.HeldZ.ghost {m : Mem} {Γ : Ctx} {Z : Var → List Var} {s s' : Stmt} (hz : HeldZ m Γ Z s)
    (hg : GhostRel s s') : HeldZ m Γ Z s' where
  caps := hz.caps
  reach p E hp hm v hv := hz.reach p E hp hm v (by rw [← hg.under_kv p]; exact hv)
  bound := hz.bound
  frames x m0' b' hx p E hp hm hpb hlt w hW := by
    obtain ⟨m0, b, h0, hst, hnv, hsp⟩ := hg.catchFrames_back x m0' b' hx
    rw [hsp] at hpb; rw [hnv] at hlt
    exact (hz.frames x m0 b h0 p E hp hm hpb hlt w hW).of_st (by simp [Mem.set, hst])

/-- **Every per-thread fact survives remembered stores that grew.** -/
theorem ThreadOK.ghost {P : Prog} {m : Mem} {s s' : Stmt} (h : ThreadOK P m s) (hg : GhostRel s s') :
    ThreadOK P m s' := by
  obtain ⟨Γ, F, Δ, ht, hi, hcd, hsc, hc, Z, hz⟩ := h
  exact ⟨Γ, F, Δ, StmtT.ghost hg ht, inv_ghost hi hg, hcd, hg.codesOK hsc, hg.closed hc, Z, hz.ghost hg⟩

end A3
