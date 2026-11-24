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
    3. each frame list names only bindings made already;
    4. each running catch frame's remembered store meets the clause, for the
       parameters older than it. -/
structure HeldZ (m : Mem) (Γ : Ctx) (Z : Var → List Var) (s : Stmt) : Prop where
  caps  : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ d ∈ E.vdeps, d.kind.bound = .none → HeldAnch E d →
            FrameCaps m (Z p) d.root
  reach : ∀ p E, Γ p = some E → E.mode = .rootb → p ∉ s.spine → ∀ v ∈ s.killVars, v ∉ Z p
  bound : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ v ∈ Z p, v < m.nv
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


/-! ### The frame clause across slot changes -/

/-- **The frame clause across slot changes**: a changed slot in the domain
    holds a clean value; a node a changed owned slot holds is clean, or is
    what an old node at the same handle became, clean if that one was. -/
theorem FrameCaps.of_changeR {m m' : Mem} {D : List Var} {w : Var} (h : FrameCaps m D w)
    (hval : ∀ x o V', x ∉ D → m'.st x = some ⟨o, some V'⟩ → m'.st x ≠ m.st x →
      ValCapsInp V' w ∧ ∀ c, Sub (.href c) V' → False)
    (hnode : ∀ x t' n', m'.st x = some ⟨true, some t'⟩ → m'.st x ≠ m.st x → Sub n' t' →
      ∀ ty c d es, n' = .node ty c d es → ValCapsInp n' w ∨
        ∃ x0 t n, m.st x0 = some ⟨true, some t⟩ ∧ Sub n t ∧ (∃ ty d es, n = .node ty c d es) ∧
          (ValCapsInp n w → ValCapsInp n' w)) :
    FrameCaps m' D w := by
  intro v o V hvD hs
  by_cases heq : m'.st v = m.st v
  · rw [heq] at hs
    obtain ⟨h1, h2⟩ := h v o V hvD hs
    refine ⟨h1, fun c hc x t n hx hsn hnd => ?_⟩
    by_cases hxe : m'.st x = m.st x
    · rw [hxe] at hx; exact h2 c hc x t n hx hsn hnd
    · obtain ⟨ty, d, es, rfl⟩ := hnd
      rcases hnode x t _ hx hxe hsn ty c d es rfl with hn | ⟨x0, t0, n0, hx0, hs0, hnd0, himp⟩
      · exact hn
      · exact himp (h2 c hc x0 t0 n0 hx0 hs0 hnd0)
  · obtain ⟨hcl, hnh⟩ := hval v o V hvD hs heq
    exact ⟨hcl, fun c hc => (hnh c hc).elim⟩

/-- **A change through a borrow keeps the frame clause**: the owner `r`'s
    tree `T` becomes `T'`, one node `n` in it replaced by `n'`. Where the
    owner is in the domain its tree was clean, and stays so; a node of the new
    tree is at an old node's address, clean if that one was. -/
theorem FrameCaps.repl {m m' : Mem} {D : List Var} {w r : Var} {T T' n n' : Val}
    (h : FrameCaps m D w) (hT : m.st r = some ⟨true, some T⟩)
    (hrp : Repl n n' T T') (hr' : m'.st r = some ⟨true, some T'⟩) (hne : ∀ x, x ≠ r → m'.st x = m.st x)
    (hcl : ValCapsInp n w → ValCapsInp n' w) (hn' : ∀ x, Sub x n' → NodeBack w n x)
    (hnoh : ∀ c, Sub (.href c) T' → False) :
    FrameCaps m' D w := by
  have hnb := hrp.nodesBack hcl hn'
  refine h.of_changeR (fun x o V' hxD hs hch => ?_) (fun x t' n2 hx hch hs ty c d es hn2 => ?_)
  · have hxr : x = r := by
      by_cases e : x = r
      · exact e
      · exact absurd (hne x e) hch
    subst hxr
    rw [hr'] at hs; cases hs
    have hTc := (h x true T hxD hT).1
    exact ⟨hrp.capsInp hTc (hcl (hTc.sub hrp.old_sub)), hnoh⟩
  · have hxr : x = r := by
      by_cases e : x = r
      · exact e
      · exact absurd (hne x e) hch
    subst hxr
    rw [hr'] at hx; cases hx
    rcases hnb n2 hs ty c d es hn2 with hc | ⟨y, hy, hnd, himp⟩
    · exact Or.inl hc
    · exact Or.inr ⟨x, T, y, hT, hy, hnd, himp⟩

/-- **An edit of a `Vec` node through its owner keeps the frame clause.** -/
theorem FrameCaps.editNode {m1 m' : Mem} {D : List Var} {w x o : Var} {T T' : Val} {t : Ty}
    {c d d' : Nat} {es es' : List Val}
    (h : FrameCaps m1 D w) (hno : NodeOf m1 x o T t c d es)
    (hrp : Repl (.node t c d es) (.node t c d' es') T T')
    (hr' : m'.st o = some ⟨true, some T'⟩) (hne : ∀ z, z ≠ o → m'.st z = m1.st z)
    (hcl : ValCapsInp (.node t c d es) w → ValCapsInp (.node t c d' es') w)
    (hel : ∀ e ∈ es', e ∈ es ∨ ∀ z, Sub z e → ValCapsInp z w) (hnoh : ∀ c, Sub (.href c) T' → False) :
    FrameCaps m' D w := by
  obtain ⟨_, _, ho, _⟩ := hno
  refine h.repl ho hrp hr' hne hcl (fun z hz => ?_) hnoh
  cases hz with
  | refl =>
    intro ty c2 d2 es2 heq
    cases heq
    exact Or.inr ⟨_, Sub.refl _, ⟨t, d, es, rfl⟩, hcl⟩
  | child hm hs =>
    rcases hel _ hm with he | hc
    · exact NodeBack.of_sub (Sub.child he hs)
    · exact fun _ _ _ _ _ => Or.inl (hc _ hs)

/-- **A step that only ends slots keeps the frame clause.** -/
theorem FrameCaps.of_shrink {m m' : Mem} {D : List Var} {w : Var} (h : FrameCaps m D w)
    (hp : ∀ y sl, m'.st y = some sl → m.st y = some sl) : FrameCaps m' D w := by
  intro v o V hv hs
  obtain ⟨h1, h2⟩ := h v o V hv (hp v _ hs)
  exact ⟨h1, fun c hc x' t n hx' hsn hnd => h2 c hc x' t n (hp x' _ hx') hsn hnd⟩

/-- **Splitting a pair into two fresh slots keeps the frame clause**, where
    the pair's slot is in the domain. -/
theorem FrameCaps.unpair {m : Mem} {D : List Var} {w y x z : Var} {o oa ob : Bool} {a b : Val}
    (h : FrameCaps m D w) (hyD : y ∉ D)
    (hvy : m.st y = some ⟨o, some (.pair a b)⟩) (hxy : x ≠ y) (hzy : z ≠ y) (hxz : x ≠ z) :
    FrameCaps (((m.set y ⟨true, none⟩).set x ⟨oa, some a⟩).set z ⟨ob, some b⟩) D w := by
  obtain ⟨hP, hPt⟩ := h y o _ hyD hvy
  have hgood : ∀ u, Sub u (.pair a b) → ∀ m1 : Mem, (∀ x' t, m1.st x' = some ⟨true, some t⟩ →
      m.st x' = some ⟨true, some t⟩ ∨ Sub t (.pair a b)) → LiveGood m1 w u := by
    intro u hu m1 hob
    refine ⟨hP.sub hu, fun c hc x' t n hx' hsn hnd => ?_⟩
    rcases hob x' t hx' with hx'' | hst
    · exact hPt c (Sub.trans hc hu) x' t n hx'' hsn hnd
    · exact hP.sub (Sub.trans hsn hst)
  have hob : ∀ x' t, (((m.set y ⟨true, none⟩).set x ⟨oa, some a⟩).set z ⟨ob, some b⟩).st x' =
      some ⟨true, some t⟩ → m.st x' = some ⟨true, some t⟩ ∨ Sub t (.pair a b) := by
    intro x' t hx'
    by_cases e1 : x' = z
    · subst e1; simp [Mem.set, upd] at hx'; obtain ⟨-, rfl⟩ := hx'; exact Or.inr (Sub.snd (Sub.refl _))
    by_cases e2 : x' = x
    · subst e2; simp [Mem.set, upd, e1] at hx'; obtain ⟨-, rfl⟩ := hx'; exact Or.inr (Sub.fst (Sub.refl _))
    by_cases e3 : x' = y
    · subst e3; simp [Mem.set, upd, e1, e2] at hx'
    · simp [Mem.set, upd, e1, e2, e3] at hx'; exact Or.inl hx'
  intro v o1 V hvD hs
  by_cases e1 : v = z
  · subst e1; simp [Mem.set, upd] at hs; obtain ⟨-, rfl⟩ := hs
    exact hgood _ (Sub.snd (Sub.refl _)) _ hob
  by_cases e2 : v = x
  · subst e2; simp [Mem.set, upd, e1] at hs; obtain ⟨-, rfl⟩ := hs
    exact hgood _ (Sub.fst (Sub.refl _)) _ hob
  by_cases e3 : v = y
  · subst e3; simp [Mem.set, upd, e1, e2] at hs
  simp [Mem.set, upd, e1, e2, e3] at hs
  obtain ⟨h1, h2⟩ := h v o1 V hvD hs
  refine ⟨h1, fun c hc x' t n hx' hsn hnd => ?_⟩
  rcases hob x' t hx' with hx'' | hst
  · exact h2 c hc x' t n hx'' hsn hnd
  · exact hP.sub (Sub.trans hsn hst)


/-- **A leaf step keeps `HeldZ`**: its borrowed parameters are old ones, its
    killable names are among the old statement's, it opens no catch frame,
    and the store keeps the frame clause wherever the statement names nothing
    of the domain. -/
theorem HeldZ.leaf {m m' : Mem} {Γ Γ' : Ctx} {Z : Var → List Var} {s s' : Stmt}
    (hz : HeldZ m Γ Z s) (hsp : s.spine = []) (hcf : s'.catchFrames = [])
    (hnv : m.nv ≤ m'.nv)
    (hrb : ∀ p E, Γ' p = some E → E.mode = .rootb → Γ p = some E)
    (hkv : ∀ v ∈ s'.killVars, v ∈ s.killVars ∨ m.nv ≤ v)
    (hc : ∀ D w, (∀ v ∈ s.killVars, v ∉ D) → FrameCaps m D w → FrameCaps m' D w) :
    HeldZ m' Γ' Z s' where
  caps p E hp hm d hd hb hh := by
    have h0 := hrb p E hp hm
    exact hc _ _ (hz.reach p E h0 hm (by simp [hsp])) (hz.caps p E h0 hm d hd hb hh)
  reach p E hp hm _ v hv hvZ := by
    rcases hkv v hv with h | h
    · exact hz.reach p E (hrb p E hp hm) hm (by simp [hsp]) v h hvZ
    · exact Nat.lt_irrefl _ (Nat.lt_of_le_of_lt h (hz.bound p E (hrb p E hp hm) hm v hvZ))
  bound p E hp hm v hv := Nat.lt_of_lt_of_le (hz.bound p E (hrb p E hp hm) hm v hv) hnv
  frames x m0 h := by rw [hcf] at h; cases h


/-- The frame lists a step keeps: every old borrowed parameter's. -/
def ZKeep (Γ : Ctx) (Z Z' : Var → List Var) : Prop :=
  ∀ p E, Γ p = some E → E.mode = .rootb → Z' p = Z p

theorem ZKeep.refl (Γ : Ctx) (Z : Var → List Var) : ZKeep Γ Z Z := fun _ _ _ _ => rfl


/-- `HeldZ` in a context whose borrowed parameters are old ones (a weaker
    context, a cleaned one). -/
theorem HeldZ.of_rootb {m : Mem} {Γ Γ' : Ctx} {Z : Var → List Var} {s : Stmt} (hz : HeldZ m Γ Z s)
    (hrb : ∀ p E, Γ' p = some E → E.mode = .rootb → Γ p = some E) : HeldZ m Γ' Z s where
  caps p E hp hm := hz.caps p E (hrb p E hp hm) hm
  reach p E hp hm := hz.reach p E (hrb p E hp hm) hm
  bound p E hp hm := hz.bound p E (hrb p E hp hm) hm
  frames x m0 hx p E hp hm := hz.frames x m0 hx p E (hrb p E hp hm) hm

/-- ... and the frame lists kept, read back. -/
theorem ZKeep.back {Γ Γ0 : Ctx} {Z Z' : Var → List Var} (h : ZKeep Γ0 Z Z')
    (hrb : ∀ p E, Γ p = some E → E.mode = .rootb → ∃ E', Γ0 p = some E' ∧ E'.mode = .rootb) :
    ZKeep Γ Z Z' := fun p E hp hm => by
  obtain ⟨E', h', hm'⟩ := hrb p E hp hm
  exact h p E' h' hm'

/-- `HeldZ` at a statement with the same killable names, spine and catch
    frames (or fewer). -/
theorem HeldZ.restmt {m : Mem} {Γ : Ctx} {Z : Var → List Var} {s s' : Stmt} (hz : HeldZ m Γ Z s)
    (hspo : ∀ p, p ∉ s'.spine → p ∉ s.spine) (hkv : ∀ v ∈ s'.killVars, v ∈ s.killVars)
    (hcf : ∀ c ∈ s'.catchFrames, c ∈ s.catchFrames) : HeldZ m Γ Z s' where
  caps := hz.caps
  reach p E hp hm hps v hv := hz.reach p E hp hm (hspo p hps) v (hkv v hv)
  bound := hz.bound
  frames x m0 hx := hz.frames x m0 (hcf _ hx)


/-- A source statement runs no catch frame. -/
theorem Stmt.catchFrames_src {s : Stmt} (hs : s.src = true) : s.catchFrames = [] := by
  induction s <;> simp_all [Stmt.src, Stmt.catchFrames]

end A2
