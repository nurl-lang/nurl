import A2.CapsLive
import A2.CapClause

namespace A2

/-! AGORA-937 B4: the frame-relative closure-capture clause, threaded beside
`Inv` (`THRU_STAGE3_DESIGN.md`, "`HeldZ`, settled"). `Z p` is the frozen list
of borrowed parameter `p`'s frame, set when the call makes `p`. -/

/-- A running statement's call through a package reads its receiver: a
    killable name. -/
theorem Stmt.headCallc_killVars : ∀ (s : Stmt), ∀ c ∈ s.headCallc, c ∈ s.killVars
  | .seq a _, c, h => by simp only [Stmt.headCallc] at h; simp [Stmt.killVars, Stmt.headCallc_killVars a c h]
  | .scope _ s, c, h => by simp only [Stmt.headCallc] at h; simp [Stmt.killVars, Stmt.headCallc_killVars s c h]
  | .rbind _ s, c, h => by simp only [Stmt.headCallc] at h; simp [Stmt.killVars, Stmt.headCallc_killVars s c h]
  | .scopeD _ _ s, c, h => by simp only [Stmt.headCallc] at h; simp [Stmt.killVars, Stmt.headCallc_killVars s c h]
  | .scopeL _ _ _ s, c, h => by simp only [Stmt.headCallc] at h; simp [Stmt.killVars, Stmt.headCallc_killVars s c h]
  | .catchR _ _ s, c, h => by simp only [Stmt.headCallc] at h; simp [Stmt.killVars, Stmt.headCallc_killVars s c h]
  | .frozen _ s, c, h => by simp only [Stmt.headCallc] at h; simp [Stmt.killVars, Stmt.headCallc_killVars s c h]
  | .block s, c, h => by simp only [Stmt.headCallc] at h; simp [Stmt.killVars, Stmt.headCallc_killVars s c h]
  | .callc _ c' _ _ _ _, c, h => by simp [Stmt.headCallc] at h; simp [Stmt.killVars, h]
  | .callcE _ c' _ _ _, c, h => by simp [Stmt.headCallc] at h; simp [Stmt.killVars, h]
  | .skip, c, h | .letv .., c, h | .letcall .., c, h | .assign .., c, h | .ite .., c, h | .while .., c, h
  | .push .., c, h | .free _, c, h | .panic, c, h | .letrec .., c, h | .unpair .., c, h | .letd .., c, h
  | .edit .., c, h | .withLock .., c, h | .insert .., c, h | .withElem .., c, h | .exit _, c, h
  | .loop _, c, h | .takeB .., c, h => by simp [Stmt.headCallc] at h


/-- The running `catchR` frames on a statement's spine: each one's binding and
    remembered store. -/
def Stmt.catchFrames : Stmt → List (Var × Mem)
  | .seq a _ => a.catchFrames
  | .scope _ s => s.catchFrames
  | .rbind _ s => s.catchFrames
  | .scopeD _ _ s => s.catchFrames
  | .scopeL _ _ _ s => s.catchFrames
  | .catchR x m0 s => (x, m0) :: s.catchFrames
  | .frozen _ s => s.catchFrames
  | .block s => s.catchFrames
  | _ => []

/-- **The frame-relative closure-capture clause** (AGORA-937 B4):
    1. at each borrowed parameter's held anchor, the frame clause at the
       parameter's frame list `Z p`;
    2. off the spine, the running statement names nothing in that list;
    3. each running catch frame's remembered store meets the clause, for the
       parameters older than it. -/
structure HeldZ (m : Mem) (Γ : Ctx) (Z : Var → List Var) (s : Stmt) : Prop where
  caps  : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ d ∈ E.vdeps, d.kind.bound = .none → HeldAnch E d →
            FrameCaps m (Z p) d.root
  reach : ∀ p E, Γ p = some E → E.mode = .rootb → p ∉ s.spine → ∀ v ∈ s.killVars, v ∉ Z p
  frames : ∀ x m0, (x, m0) ∈ s.catchFrames → ∀ p E, Γ p = some E → E.mode = .rootb → p < m0.nv →
            ∀ d ∈ E.vdeps, d.kind.bound = .none → HeldAnch E d → FrameCaps (m0.set x ⟨false, some (.int 1)⟩) (Z p) d.root

/-- **No call through a package hands a held anchor's root to an `inout`
    parameter**: the receiver is a running name, inside the anchor's frame,
    so its package captures the root read-only (the frame clause). -/
theorem CapInoutH.not_heldZ {P : Prog} {m : Mem} {Γ : Ctx} {Z : Var → List Var} {s : Stmt}
    (hz : HeldZ m Γ Z s) (hcodes : MemCodes P m)
    {p : Var} {E : Entry} {d : Dep} (hp : Γ p = some E) (hm : E.mode = .rootb) (hps : p ∉ s.spine)
    (hd : d ∈ E.vdeps) (hb : d.kind.bound = .none) (hh : HeldAnch E d) :
    ¬ CapInoutH P m s d.root := by
  rintro ⟨c, hcs, o, fs, te, ms, env, cs, j, f, fn, zs, i, b, t, hc, hj, hf, hl, hi, hai, hpi⟩
  have hcZ : c ∉ Z p := hz.reach p E hp hm hps c (Stmt.headCallc_killVars s c hcs)
  have hcode := hcodes.1 c o _ fs te ms env cs hc (Sub.refl _)
  obtain ⟨hlen, himpl⟩ := hcode
  have hjl : j < ms.length := by
    rw [← hlen]
    rcases Nat.lt_or_ge j fs.length with h | h
    · exact h
    · rw [List.getElem?_eq_none h] at hj; cases hj
  obtain ⟨fn', sig, hf', hsig, hpar, -⟩ := himpl j f ms[j] hj (List.getElem?_eq_getElem hjl)
  rw [hf] at hf'; cases hf'
  rw [hpar] at hpi hl
  have hlen' : sig.params.tail.length = zs.length := by
    simp only [List.length_cons, List.length_append, List.length_map] at hl; omega
  obtain ⟨q, hq, hq1, hq2⟩ := capPos hlen' hi hai hpi
  have := (hz.caps p E hp hm d hd hb hh c o _ hcZ hc).1 fs te ms env cs (Sub.refl _) q hq hq1
  rw [hq2] at this; cases this

theorem Step.held_not_killVarsZ {P : Prog} {m m' : Mem} {Γ : Ctx} {Z : Var → List Var} {s s' : Stmt}
    (hstep : Step P m s (.ok m' s')) (hz : HeldZ m Γ Z s) (hcodes : MemCodes P m)
    {p : Var} {E : Entry} {d : Dep} (hp : Γ p = some E) (hm : E.mode = .rootb) (hps : p ∉ s.spine)
    (hd : d ∈ E.vdeps) (hb : d.kind.bound = .none) (hh : HeldAnch E d)
    (hkv : d.root ∉ s.killVars) (hlt : d.root < m.nv) : d.root ∉ s'.killVars := by
  intro hin
  rcases hstep.killVars_subH m' s' rfl d.root hin with h | h | h
  · exact hkv h
  · exact absurd h (Nat.not_le.mpr hlt)
  · exact CapInoutH.not_heldZ hz hcodes hp hm hps hd hb hh h

end A2
