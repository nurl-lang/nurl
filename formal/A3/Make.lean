import A3.Claim

/-! A3.6's rest — module globals made before `main`, read at their declared types.

* **The read's type tied to the declaration.**  A program declares its
  globals (`Decl`: each one's `make` and type); the declarations' types are
  the program's global type environment (`declTy`).  A typed program reads
  each global at it (`ProgGlobs`, `Stmt.globsAt`, A2/Codes.lean), every
  configuration a start reaches still does (`Reach.globsAt`), and so no
  thread's read of a global panics (`Reach.glob_typed`): `EvalR.globP` is
  never taken.
* **The make phase.**  Each global's `make`, a function of no parameter whose
  owned result's type synchronises itself, runs before `main`, one at a time
  and in order, on a thread of its own, from the store the earlier ones left
  (`Made`).  When the call has returned its result moves into the global.  A
  run of the phase that ends leaves a start `GlobsOK` holds of, with every
  global set at its declared type (`made_ok`); every run of a `make` is
  memory-safe and race-free (`made_safe`); the other way a `make` ends is a
  panic before `main` (`MakePanics`).
* **The claim from the declarations** (`claim_made`): `A3.claim`, with the
  start the make phase left in place of `GlobsOK` as a premise, and no read
  of a global panicking. -/

namespace A3
open A2

/-! ### Every configuration reads its globals at the declared types -/

theorem Redex.globs_hole {s r : Stmt} {K : Stmt → Stmt} (h : Redex s K r) {GT : GTy}
    (hs : (K r).globsAt GT) : r.globsAt GT := by
  induction h with
  | here => exact hs
  | seq _ ih => exact ih hs.1
  | scope _ ih => exact ih hs
  | rbind _ ih => exact ih hs
  | frozen _ ih => exact ih hs
  | catchR _ ih => exact ih hs
  | scopeD _ ih => exact ih hs
  | scopeL _ ih => exact ih hs

theorem Redex.globsAt {s r : Stmt} {K : Stmt → Stmt} (h : Redex s K r) {GT : GTy} {y y' : Stmt}
    (hy : y.globsAt GT) (hy' : (K y').globsAt GT) : (K y).globsAt GT := by
  induction h with
  | here => exact hy
  | seq _ ih => exact ⟨ih hy'.1, hy'.2⟩
  | scope _ ih => exact ih hy'
  | rbind _ ih => exact ih hy'
  | frozen _ ih => exact ih hy'
  | catchR _ ih => exact ih hy'
  | scopeD _ ih => exact ih hy'
  | scopeL _ ih => exact ih hy'

/-- Every thread of a configuration reads its globals at their declared types. -/
def Cfg.globsAt (C : Cfg) (GT : GTy) : Prop := ∀ t ∈ C.ths, t.s.globsAt GT

/-- **A step keeps it**: a thread's step leaves a part of its statement or a
    function's body (`globs_step`), a spawn the spawner's statement with its
    call replaced and the spawned function's body. -/
theorem TStep.globsAt {P : Prog} {spawn : Nat → Bool} {GT : GTy} (hPG : ProgGlobs P GT) {C C' : Cfg}
    (h : TStep P spawn C C') (hC : C.globsAt GT) : C'.globsAt GT := by
  cases h with
  | @thread i t m' s' hi _ hs =>
    intro t' ht'
    rcases List.mem_or_eq_of_mem_set ht' with ht' | rfl
    · exact hC t' ht'
    · exact globs_step hPG hs (hC t (List.mem_of_getElem? hi)) _ _ rfl
  | @spawn i t K x f args k fn vs st' hi hK _ hf _ _ _ =>
    have ht := hC t (List.mem_of_getElem? hi)
    rw [hK.eq] at ht
    have hk : (Stmt.letcall x f args k).globsAt GT := hK.globs_hole ht
    intro t' ht'
    rcases List.mem_append.mp ht' with ht' | ht'
    · rcases List.mem_or_eq_of_mem_set ht' with ht' | rfl
      · exact hC t' ht'
      · exact hK.globsAt (y := .scope x k) hk ht
    · simp only [List.mem_singleton] at ht'
      subst ht'
      exact wrapParams_globs (s := .scope fn.params.length fn.body) (hPG fn (List.mem_of_getElem? hf)) _ _ _
  | @spawnFail i t K x f args k fn vs st' hi hK _ _ _ _ _ =>
    have ht := hC t (List.mem_of_getElem? hi)
    rw [hK.eq] at ht
    intro t' ht'
    rcases List.mem_or_eq_of_mem_set ht' with ht' | rfl
    · exact hC t' ht'
    · exact hK.globsAt (y := .seq .panic (.letcall x f args k)) ⟨trivial, hK.globs_hole ht⟩ ht

theorem Reach.globsAt {P : Prog} {spawn : Nat → Bool} {GT : GTy} (hPG : ProgGlobs P GT) {C C' : Cfg}
    (h : Reach P spawn C C') (hC : C.globsAt GT) : C'.globsAt GT := by
  induction h with
  | refl => exact hC
  | step hst _ ih => exact ih (hst.globsAt hPG hC)

/-- A right-hand side a statement's next step evaluates: a binding's, an
    assignment's or a destructor binding's, at the redex. -/
def NextRhs (s : Stmt) (r : Rhs) : Prop :=
  ∃ K x k, Redex s K (.letv x r k) ∨ Redex s K (.assign x r) ∨ ∃ f, Redex s K (.letd x f r k)

theorem NextRhs.globAt {s : Stmt} {r : Rhs} {GT : GTy} (h : NextRhs s r) (hs : s.globsAt GT) :
    r.globAt GT := by
  obtain ⟨K, x, k, hK | hK | ⟨f, hK⟩⟩ := h
  · rw [hK.eq] at hs; exact (hK.globs_hole hs).1
  · rw [hK.eq] at hs; exact hK.globs_hole hs
  · rw [hK.eq] at hs; exact (hK.globs_hole hs).1

/-- The start holds every declared global at its declared type. -/
def GlobsAt (G : Globs) (GT : GTy) : Prop := ∀ g t, GT g = some t → ∃ v, G.gl g = some v ∧ GlobFits G.blk t v

/-- **A3.6, from typing alone: no read of a global panics.**  A program that
    reads each global at its declared type, run from a start that holds each
    declared global at that type, reaches no configuration where a thread's
    next read of a global is `EvalR.globP`. -/
theorem Reach.glob_typed {P : Prog} {spawn : Nat → Bool} {GT : GTy} {G : Globs} {s : Stmt} {nv : Nat}
    (hPG : ProgGlobs P GT) (hs : s.globsAt GT) (hG : GlobsAt G GT) {C : Cfg}
    (hr : Reach P spawn (Cfg.start G s nv) C) :
    ∀ th ∈ C.ths, ∀ g t, NextRhs th.s (.glob g t) → ¬ EvalR (C.view th) (.glob g t) .panic := by
  intro th hth g t hn
  have hC : C.globsAt GT := hr.globsAt hPG (fun t' ht' => by
    simp only [Cfg.start, List.mem_singleton] at ht'
    subst ht'; exact hs)
  have hgt : GT g = some t := hn.globAt (hC th hth)
  obtain ⟨v, hv, hf⟩ := hG g t hgt
  exact Reach.glob_noPanic hr hv hf th

/-! ### The make phase -/

/-- A3.6: a module global's declaration, `: T g ( make )`: its `make`, a
    function of the program, and its declared type. -/
structure Decl where
  make : Nat
  ty   : Ty

/-- The declarations' global type environment: global `g` is the `g`-th
    declaration. -/
def declTy (D : List Decl) : GTy := fun g => (D[g]?).map Decl.ty

/-- Each declaration's `make` takes no parameter and hands back an owned
    value of a type that synchronises itself (`Ty.sync`: a `Locked`, an
    `RwLocked`, a `Mutex`, an `Atomic`, a `Channel`, or an `Arc` of no library
    handle). -/
def DeclsOK (P : Prog) (D : List Decl) : Prop :=
  ∀ (g : Nat) (d : Decl), D[g]? = some d → d.ty.sync = true ∧
    ∃ fn, P[d.make]? = some fn ∧ fn.params = [] ∧ fn.resTy = d.ty ∧ fn.resOwn = true

/-- The thread global `g`'s `make` runs on: the call, its result into
    variable 0, then the hand-over point, which never runs: the make phase
    stops the thread there and moves the result into the global (`Made`).
    The hand-over point is an assignment to 0 of a read of the global at its
    declared type, so the thread's typing there says that 0 owns a value of
    that type (`handOver_inv`). -/
def makeStmt (g : Nat) (d : Decl) : Stmt := .letcall 0 d.make [] (.assign 0 (.glob g d.ty))

/-- **The make phase**, run so far: the first `i` globals are made.  Global
    `i`'s `make` runs on its own thread from the store the earlier ones left
    (`Cfg.start G`), the program's thread steps and sweeps, up to the
    hand-over point; its result moves into global `i`, and the next one runs
    on that store.  (A `make` that spawns a thread never reaches a
    configuration of one thread at the hand-over point: the phase models
    single-threaded `make`s.) -/
inductive Made (P : Prog) (spawn : Nat → Bool) (D : List Decl) : Nat → Globs → Prop
  | nil : Made P spawn D 0 Globs.empty
  | make {i : Nat} {d : Decl} {G : Globs} {C : Cfg} {st : Var → Option Slot} {nv : Nat} {o : Bool} {v : Val} :
      Made P spawn D i G → D[i]? = some d → Reach P spawn (Cfg.start G (makeStmt i d) 1) C →
      C.ths = [⟨st, nv, .scope 0 (.assign 0 (.glob i d.ty))⟩] → st 0 = some ⟨o, some v⟩ →
      Made P spawn D (i + 1) ⟨C.alloc, C.nid, C.blk, upd C.gl i (some v)⟩

/-- ... and the other way a `make` ends: it panics before `main`, its thread's
    next step a panic no frame catches. -/
def MakePanics (P : Prog) (spawn : Nat → Bool) (D : List Decl) : Prop :=
  ∃ i d G C th m', Made P spawn D i G ∧ D[i]? = some d ∧ Reach P spawn (Cfg.start G (makeStmt i d) 1) C ∧
    C.ths = [th] ∧ Step P (C.view th) th.s (.panic m')

/-! #### The `make`'s thread is typed -/

theorem makeStmt_vars (g : Nat) (d : Decl) : ∀ v ∈ (makeStmt g d).vars, v < 1 := by
  intro v hv
  simp [makeStmt, Stmt.vars, Rhs.vars] at hv
  rw [hv]; exact Nat.zero_lt_one

/-- A context with no borrowed parameter and no destructor binding. -/
def Plain (Γ : Ctx) : Prop := ∀ v E, Γ v = some E → E.mode ≠ .rootb ∧ E.dtor = false ∧ E.dbind = false

theorem Plain.endOK {Γ : Ctx} (h : Plain Γ) (x : Var) : EndOK Γ x :=
  ⟨fun p E hp hm => absurd hm (h p E hp).1, DtorSafe.of_none (fun v E hE => (h v E hE).2.1) _ _ _,
    DbindSafe.of_none (fun v E hE => (h v E hE).2.2) _⟩

/-- A make's result: owned, holding nothing. -/
def resE (t : Ty) : Entry := ⟨t, .own, true, [], [], false, false⟩

theorem makeStmt_typed {P : Prog} (hP : ProgOK P) {D : List Decl} (hD : DeclsOK P D) {g : Nat} {d : Decl}
    (hd : D[g]? = some d) : ∃ Δ, StmtT P (fun _ => none) [] (makeStmt g d) Δ := by
  obtain ⟨hsy, fn, hf, hps, hrt, hro⟩ := hD g d hd
  have htok : d.ty.ok = true := hrt ▸ (hP fn (List.mem_of_getElem? hf)).2.2.2.1
  have hcall : CallT P (fun _ => none) [] d.make [] (resE d.ty) (fun _ => none) := by
    refine ⟨fn, hf, by simp [hps], fun i hi => absurd hi (by simp [hps]), fun dd hdd => ?_,
      CallDtorSafe.of_inp (by simp [hps]) (by simp [mutNames, argNames]), ?_, ?_, fun _ => by simp [callR]⟩
    · simp [mutNames, argNames] at hdd
    · simp [callRes, resE, hrt, resMode, hro, heldOfArgs, argNames, allKinds, ownHeld, argDeps, argE, intE]
    · funext v
      simp [callPost, mutNames, argNames, killNames, hps, callPostAux]
  have hΓ0 : (setE (fun _ => none) 0 (resE d.ty)) 0 = some (resE d.ty) := upd_same _ _ _
  have hplain : Plain (setE (fun _ => none) 0 (resE d.ty)) := fun v E hE => by
    simp only [setE, upd] at hE
    split at hE
    · cases hE; exact ⟨by simp [resE], rfl, rfl⟩
    · cases hE
  have hasg := StmtT.assign (P := P) (F := []) hΓ0 (by simp) (.inl ⟨rfl, rfl⟩) (RhsT.glob (g := g) hsy htok) rfl
    (by simp [roots, Entry.vdeps, Mode.ownSlot]) (by rw [hΓ0]; rfl) (hplain.endOK 0).1
    (hplain.endOK 0).2.1 rfl
  have hplain' : Plain (setE (kill .replace false 0 (setE (fun _ => none) 0 (resE d.ty))) 0
      { (⟨d.ty, .own, true, [], [], false, false⟩ : Entry) with mode := (resE d.ty).mode }) := fun v E hE => by
    simp only [setE, upd] at hE
    split at hE
    · cases hE; exact ⟨by simp [resE], rfl, rfl⟩
    · simp only [kill, upd] at hE
      split at hE
      · contradiction
      · cases hE
  exact ⟨_, StmtT.letcall rfl rfl (by simp) hcall hasg (hplain'.endOK 0)
    (fun fn' hf' _ hd => by rw [hf] at hf'; cases hf'; rw [hrt, Ty.holdsDtor_of_sync hsy] at hd; cases hd)⟩

/-- At the hand-over point, variable 0 is an owner (or, in no context the
    invariant admits, an `inout` binding) of the declared type: the
    assignment there is typed only so. -/
theorem assignGlob_inv {P : Prog} {Γ : Ctx} {F : List Var} {x g : Nat} {t : Ty} {Δ : Ctx}
    (h : StmtT P Γ F (.assign x (.glob g t)) Δ) :
    ∃ E, Γ x = some E ∧ E.ty = t ∧ (E.mode = .own ∨ E.mode = .inout .replace) := by
  generalize hS : Stmt.assign x (.glob g t) = S at h
  induction h with
  | assign hx _ hm hr hty _ _ _ _ _ =>
    cases hS
    cases hr
    refine ⟨_, hx, hty.symm, ?_⟩
    rcases hm with ⟨h1, _⟩ | ⟨h1, _⟩ | ⟨_, h2⟩
    · exact .inl h1
    · exact .inr h1
    · cases h2
  | sub hw _ _ ih =>
    obtain ⟨E0, h0, hty, hm⟩ := ih hS
    obtain ⟨E, hE⟩ : ∃ E, _ := Option.ne_none_iff_exists'.mp (fun hn => by
      rw [((hw.1 x).1.mp hn)] at h0; cases h0)
    have hew := (hw.1 x).2 E E0 hE h0
    exact ⟨E, hE, hew.ty ▸ hty, hew.mode ▸ hm⟩
  | _ => cases hS

theorem handOver_inv {P : Prog} {Γ : Ctx} {F : List Var} {x g : Nat} {t : Ty} {Δ : Ctx}
    (h : StmtT P Γ F (.scope x (.assign x (.glob g t))) Δ) :
    ∃ E, Γ x = some E ∧ E.ty = t ∧ (E.mode = .own ∨ E.mode = .inout .replace) := by
  generalize hS : Stmt.scope x (.assign x (.glob g t)) = S at h
  induction h with
  | scope _ _ hb _ =>
    cases hS
    exact assignGlob_inv hb
  | sub hw _ _ ih =>
    obtain ⟨E0, h0, hty, hm⟩ := ih hS
    obtain ⟨E, hE⟩ : ∃ E, _ := Option.ne_none_iff_exists'.mp (fun hn => by
      rw [((hw.1 x).1.mp hn)] at h0; cases h0)
    have hew := (hw.1 x).2 E E0 hE h0
    exact ⟨E, hE, hew.ty ▸ hty, hew.mode ▸ hm⟩
  | _ => cases hS

/-! #### Every reachable configuration of a `make`'s run has the invariant -/

/-- A3.0's invariant in every configuration a typed start reaches, and (A3.5)
    the cells' homes, as `A3.claim` draws them. -/
theorem reach_inv {P : Prog} {spawn : Nat → Bool} {G : Globs} {s : Stmt} {Δ : Ctx} {nv : Nat}
    (hP : ProgOK P) (hPc : ProgCodes P) (hSp : SpawnOK P spawn) (hG : GlobsOK P G)
    (ht : StmtT P (fun _ => none) [] s Δ) (hs : s.src = true) (hsc : s.codesOK P)
    (hv : ∀ v ∈ s.vars, v < nv) {C : Cfg} (hr : Reach P spawn (Cfg.start G s nv) C) : CInv P C ∧ CellInv C :=
  (reach_cinv hP hPc (fun h => fun hav hb hp hf => Step.restrict h hav hb hp hf)
    (fun {_ _ _ _ _ _ _ _ _ _ _} h hi hK hsp hf hx hmv => CInv.spawn_of
      (fun hok => fun hR hsp hf hx hmv => spawner_ok hP hPc hSp hok hR hsp hf hx hmv)
      (fun hok => fun hR hsp hf hmv => spawn_args hP hSp hok hR hsp hf hmv)
      (fun hsp hf => fun hlen hwf hnd hdisj hself hpk hcd => fun hpart => fun hlt => fun hsh hB hBc hBv =>
        newThread_ok hP hPc hSp hsp hf hlen hwf hnd hdisj hself hpk hcd hpart hlt hsh hB hBc hBv)
      h hi hK hsp hf hx hmv)
    (fun {_ _ _ _ _ _ _ _} h hi hK => CInv.spawnFail_of (fun hok => fun hR => spawnFail_ok hok hR) h hi hK)
    (CInv.start ht hs hsc hv hG) (CellInv.start hG s nv) hr)

/-! #### What the hand-over leaves -/

/-- A share of a type that synchronises itself, whose share names a block of
    its type, fits a global's read at that type. -/
theorem globFits_of {B : Nat → Option Blk} {t : Ty} {v : Val} (hs : t.sync = true) (hw : WFv t v)
    (hsh : SharesIn B t v) : GlobFits B t v ∧ v.ids = [] := by
  cases t with
  | lk u =>
    cases hw
    obtain ⟨o, hk⟩ := hsh _ _ _ ArcIn.lk
    exact ⟨.inl ⟨u, _, o, rfl, rfl, hk⟩, rfl⟩
  | arc u =>
    cases hw
    exact ⟨.inr ⟨u, _, _, rfl, rfl, hsh _ _ _ ArcIn.here⟩, rfl⟩
  | _ => cases hs

/-- The store a `make` left, with no binding, once its result is the global:
    A2's invariant, over the blocks as they are. -/
theorem MInv.unbind {m : Mem} {Γ : Ctx} (hi : MInv m Γ) (a : Nat → Bool) (ha : ∀ i, a i = m.alloc i)
    (gl : Nat → Option Val) : MInv ⟨a, m.nid, 0, fun _ => none, m.blk, gl⟩ (fun _ => none) where
  dom _ := rfl
  slot _ _ h := by cases h
  heap := by
    refine ⟨fun _ _ h => (by cases h), fun _ _ _ _ _ h => (by cases h), fun _ _ h => (by cases h),
      fun _ _ h => (by cases h), fun k bl hk => ?_, hi.heap.views⟩
    obtain ⟨hkey, hnd, hall⟩ := hi.heap.blk k bl hk
    refine ⟨hkey, hnd, fun i hi' => ?_⟩
    obtain ⟨hal, hlt, _, hoth⟩ := hall i hi'
    exact ⟨show a i = true by rw [ha]; exact hal, hlt, fun _ _ h => (by cases h), hoth⟩
  nvSt _ h := by cases h
  noInout _ _ _ h := by cases h
  wf := ⟨fun _ _ h => (by cases h), fun _ _ h => (by cases h), fun _ _ h => (by cases h),
    fun _ _ h => (by cases h)⟩
  rootbLive _ _ h := by cases h
  rootbLt _ _ h := by cases h
  names _ _ h := by cases h
  held _ _ _ _ h := by cases h
  pkgs _ _ _ h := by cases h
  armed _ _ _ h := by cases h
  shares _ _ _ _ h := by cases h
  blocks := hi.blocks

/-- **One `make`, handed over**: from a start `GlobsOK` holds of, global `i`'s
    `make` run to the hand-over point leaves, once its result is global `i`,
    a start `GlobsOK` holds of again, with global `i` at its declared type. -/
theorem make_ok {P : Prog} {spawn : Nat → Bool} (hP : ProgOK P) (hPc : ProgCodes P) (hSp : SpawnOK P spawn)
    {D : List Decl} (hD : DeclsOK P D) {i : Nat} {d : Decl} (hd : D[i]? = some d) {G : Globs}
    (hG : GlobsOK P G) (hGi : G.gl i = none) {C : Cfg} (hr : Reach P spawn (Cfg.start G (makeStmt i d) 1) C)
    {st : Var → Option Slot} {nv : Nat} (hths : C.ths = [⟨st, nv, .scope 0 (.assign 0 (.glob i d.ty))⟩])
    {o : Bool} {v : Val} (hst : st 0 = some ⟨o, some v⟩) :
    GlobsOK P ⟨C.alloc, C.nid, C.blk, upd C.gl i (some v)⟩ ∧ GlobFits C.blk d.ty v ∧ C.gl = G.gl := by
  obtain ⟨hsy, _⟩ := hD i d hd
  obtain ⟨Δ0, ht0⟩ := makeStmt_typed hP hD hd
  obtain ⟨hci, hcell⟩ := reach_inv hP hPc hSp hG ht0 rfl trivial (makeStmt_vars i d) hr
  have hgl : C.gl = G.gl := Reach.gl hr
  obtain ⟨ps, hc, hreach⟩ := hci
  have hth : C.ths[0]? = some ⟨st, nv, .scope 0 (.assign 0 (.glob i d.ty))⟩ := by rw [hths]; rfl
  obtain ⟨a, ha⟩ := part_of hc.len hth
  have hps : ps = [a] := by
    have hl : ps.length = 1 := by rw [hc.len, hths]; rfl
    match ps, hl, ha with
    | [a'], _, ha' => simp at ha'; rw [ha']
  obtain ⟨hto, _⟩ := hc.ok 0 _ a hth ha
  obtain ⟨Γ, F, Δ, ht, hi, hcd, _, hcl⟩ := hto
  -- the view is the configuration's store
  have hall : ∀ j, union a (payPart C.blk) j = C.alloc j := by
    intro j
    have := hc.all j
    rw [hps] at this
    cases hj : C.alloc j with
    | true =>
      rcases this.mp hj with ⟨a', ha', h⟩ | h
      · simp only [List.mem_singleton] at ha'; subst ha'; simp [union, h]
      · simp [union, payPart_iff.mpr h]
    | false =>
      cases hu : union a (payPart C.blk) j with
      | false => rfl
      | true =>
        simp only [union, Bool.or_eq_true] at hu
        rcases hu with h | h
        · rw [this.mpr (.inl ⟨a, by simp, h⟩)] at hj; cases hj
        · rw [this.mpr (.inr (payPart_iff.mp h))] at hj; cases hj
  -- variable 0 owns the result, of the declared type
  obtain ⟨E, hE, hty, hmo⟩ := handOver_inv ht
  have hmo' : E.mode = .own := by
    rcases hmo with h | h
    · exact h
    · exact absurd h (hi.noInout 0 E .replace hE)
  obtain ⟨sl, hsl, htok, hso⟩ := hi.slot 0 E hE
  have hsl' : sl = ⟨o, some v⟩ := by
    change st 0 = some sl at hsl
    rw [hst] at hsl; cases hsl; rfl
  subst hsl'
  have hown : o = true := by have h := hso.1; rw [hmo'] at h; exact h
  subst hown
  have hwf : WFv d.ty v := hty ▸ (hso.2.1 (by rw [hmo']; rfl)).2.1 v rfl
  have hsh : SharesIn C.blk d.ty v := hty ▸ hi.shares 0 E _ v hE hsl rfl rfl
  obtain ⟨hfit, hids⟩ := globFits_of hsy hwf hsh
  -- 0 is the thread's one binding
  have honly : ∀ x, x ≠ 0 → st x = none := by
    intro x hx
    cases hgx : Γ x with
    | some Ex =>
      have := hcl x (by rw [hgx]; rfl)
      simp [Stmt.spine] at this; exact absurd this hx
    | none =>
      have := hi.dom x
      rw [hgx] at this
      change false = (st x).isSome at this
      cases h' : st x with
      | none => rfl
      | some _ => rw [h'] at this; cases this
  refine ⟨⟨fun g w hg => ?_, ?_, fun j hj => ?_, fun k bl hk => ?_, hcd.blk.1, hcd.blk.2,
    -- A3.5: each cell's shares are in one block, below `nid`: the cells' homes
    fun k k1 k2 h1 h2 => ⟨hcell.one k k1 k2 h1 h2, hcell.blkBelow k1 k h1⟩⟩, hfit, hgl⟩
  · -- each global holds a share of a block of a type that synchronises itself
    by_cases hgi : g = i
    · subst hgi; simp [upd] at hg; subst hg
      exact ⟨d.ty, hsy, hty ▸ htok, hfit⟩
    · simp only [upd, hgi, ite_false] at hg
      rw [hgl] at hg
      obtain ⟨t', hs', hok', hf'⟩ := hG.sync g w hg
      exact ⟨t', hs', hok', (hr.globFits (C := Cfg.start G (makeStmt i d) 1) hg hf').2⟩
  · exact MInv.unbind hi.toMInv C.alloc (fun j => (hall j).symm) _
  · -- every live address is a payload's: the result owns none
    rcases hi.cover j (by show union a (payPart C.blk) j = true; rw [hall]; exact hj) with
      ⟨x, T, hT, hjT⟩ | hp
    · exfalso
      by_cases hx : x = 0
      · subst hx
        have h0 : st 0 = some ⟨true, some T⟩ := hT
        rw [hst] at h0; cases h0
        rw [hids] at hjT; cases hjT
      · have h0 : st x = some ⟨true, some T⟩ := hT
        rw [honly x hx] at h0; cases h0
    · exact .inr hp
  · -- every block is reached from a global: the result's, or an earlier one
    refine (hreach k bl hk).roots fun w hw => ?_
    rcases hw with ⟨j, t, hj, x, o', hx⟩ | ⟨g, hg⟩
    · rw [hths] at hj
      cases j with
      | succ j => simp at hj
      | zero =>
        simp at hj; subst hj
        change st x = some ⟨o', some w⟩ at hx
        by_cases hx0 : x = 0
        · subst hx0; rw [hst] at hx; cases hx; exact ⟨i, by simp [upd]⟩
        · rw [honly x hx0] at hx; cases hx
    · have hgi : g ≠ i := fun e => by subst e; rw [hgl, hGi] at hg; cases hg
      exact ⟨g, by simp [upd, hgi, hg]⟩

/-- **The make phase leaves a start `GlobsOK` holds of**, with every global
    made so far set at its declared type, and none of the later ones set. -/
theorem made_ok {P : Prog} {spawn : Nat → Bool} (hP : ProgOK P) (hPc : ProgCodes P) (hSp : SpawnOK P spawn)
    {D : List Decl} (hD : DeclsOK P D) {i : Nat} {G : Globs} (h : Made P spawn D i G) :
    GlobsOK P G ∧ (∀ g d, g < i → D[g]? = some d → ∃ v, G.gl g = some v ∧ GlobFits G.blk d.ty v) ∧
      ∀ g, i ≤ g → G.gl g = none := by
  induction h with
  | nil => exact ⟨GlobsOK.empty, fun _ _ h => absurd h (Nat.not_lt_zero _), fun _ _ => rfl⟩
  | @make i d G C st nv o v _ hd hr hths hst ih =>
    obtain ⟨hG, hset, hunset⟩ := ih
    obtain ⟨hG', hfit, hgl⟩ := make_ok hP hPc hSp hD hd hG (hunset i (Nat.le_refl _)) hr hths hst
    refine ⟨hG', fun g d' hg hd' => ?_, fun g hg => ?_⟩
    · by_cases hgi : g = i
      · subst hgi; rw [hd] at hd'; cases hd'
        exact ⟨v, by simp [upd], hfit⟩
      · obtain ⟨w, hw, hf⟩ := hset g d' (by omega) hd'
        refine ⟨w, by simp [upd, hgi, hgl, hw], ?_⟩
        exact (hr.globFits (C := Cfg.start G (makeStmt i d) 1) hw hf).2
    · have hgi : g ≠ i := by omega
      simp [upd, hgi, hgl, hunset g (by omega)]

/-- ... and, once every global is made, the start holds each at its declared
    type. -/
theorem made_globsAt {P : Prog} {spawn : Nat → Bool} (hP : ProgOK P) (hPc : ProgCodes P)
    (hSp : SpawnOK P spawn) {D : List Decl} (hD : DeclsOK P D) {G : Globs} (h : Made P spawn D D.length G) :
    GlobsOK P G ∧ GlobsAt G (declTy D) := by
  obtain ⟨hG, hset, _⟩ := made_ok hP hPc hSp hD h
  refine ⟨hG, fun g t hg => ?_⟩
  simp only [declTy, Option.map_eq_some_iff] at hg
  obtain ⟨d, hd, rfl⟩ := hg
  exact hset g d (List.getElem?_eq_some_iff.mp hd).1 hd

/-- **Every `make`'s run is safe**: from the store the earlier ones left, no
    configuration it reaches is stuck or has a race. -/
theorem made_safe {P : Prog} {spawn : Nat → Bool} (hP : ProgOK P) (hPc : ProgCodes P) (hSp : SpawnOK P spawn)
    {D : List Decl} (hD : DeclsOK P D) {i : Nat} {G : Globs} (h : Made P spawn D i G) {d : Decl}
    (hd : D[i]? = some d) :
    MemorySafe P spawn (Cfg.start G (makeStmt i d) 1) ∧ RaceFree P spawn (Cfg.start G (makeStmt i d) 1) := by
  obtain ⟨Δ, ht⟩ := makeStmt_typed hP hD hd
  have hc := claim P spawn G (makeStmt i d) Δ 1 hP hPc hSp (made_ok hP hPc hSp hD h).1 ht rfl trivial
    (makeStmt_vars i d)
  exact ⟨hc.1, hc.2.1⟩

/-- **A3.6, the claim from the program's declarations**: a program A2 types,
    whose globals are declared with `make`s of no parameter and synchronising
    types (`DeclsOK`) and read at their declared types (`ProgGlobs`):
    - every `make`'s run before `main` is memory-safe and race-free;
    - once every global is made (`Made`), the program run from that start is
      memory-safe, race-free and leaves only what the globals reach
      (`A3.claim`, with `GlobsOK` derived), and no thread's read of a global
      ever panics (`EvalR.globP` is never taken). -/
theorem claim_made (P : Prog) (spawn : Nat → Bool) (D : List Decl) (s : Stmt) (Δ : Ctx) (nv : Nat)
    (hP : ProgOK P) (hPc : ProgCodes P) (hSp : SpawnOK P spawn) (hD : DeclsOK P D)
    (hPG : ProgGlobs P (declTy D))
    (ht : StmtT P (fun _ => none) [] s Δ) (hs : s.src = true) (hsc : s.codesOK P) (hsg : s.globsAt (declTy D))
    (hv : ∀ v ∈ s.vars, v < nv) :
    (∀ i G d, Made P spawn D i G → D[i]? = some d →
      MemorySafe P spawn (Cfg.start G (makeStmt i d) 1) ∧ RaceFree P spawn (Cfg.start G (makeStmt i d) 1)) ∧
    ∀ G, Made P spawn D D.length G →
      MemorySafe P spawn (Cfg.start G s nv) ∧ RaceFree P spawn (Cfg.start G s nv) ∧
      NoLeak P spawn (Cfg.start G s nv) ∧
      ∀ C, Reach P spawn (Cfg.start G s nv) C →
        ∀ th ∈ C.ths, ∀ g t, NextRhs th.s (.glob g t) → ¬ EvalR (C.view th) (.glob g t) .panic := by
  refine ⟨fun i G d h hd => made_safe hP hPc hSp hD h hd, fun G h => ?_⟩
  obtain ⟨hG, hGa⟩ := made_globsAt hP hPc hSp hD h
  obtain ⟨h1, h2, h3⟩ := claim P spawn G s Δ nv hP hPc hSp hG ht hs hsc hv
  exact ⟨h1, h2, h3, fun C hr => Reach.glob_typed hPG hsg hGa hr⟩

end A3
