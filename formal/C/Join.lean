module

public import C.Check
public import C.Dedup

@[expose] public section

/-!
# C1: joins (`ite`, `while`) over finite contexts (AGORA-970)

`StmtT`'s `ite` asks for one context after both arms, and `while` for a
context its body gives back. With contexts as functions, C0 could not
compare them. Here the checker keeps every context inside a finite domain
`D`: the program's variables, which it gets from the program (`Stmt.vars`).
`Supported Γ D` says `Γ` names nothing outside `D`. Every step keeps that,
so two contexts are equal exactly when they agree on `D`, which a loop over
`D` decides. The checker `checkS` covers all of C0 plus `ite` and `while`,
and is proven sound (`checkS_sound`, `checkedS_memory_safe`).
-/

namespace C

open A1

/-- `Γ` names nothing outside `D`. -/
def Supported (Γ : Ctx) (D : List Var) : Prop := ∀ v, v ∉ D → Γ v = none

theorem supported_kill {Γ : Ctx} {D : List Var} (h : Supported Γ D) (e : Eff) (hv : Bool) (x : Var) :
    Supported (kill e hv x Γ) D := fun v hv' => by simp [kill, h v hv']

theorem supported_setE {Γ : Ctx} {D : List Var} (h : Supported Γ D) {x : Var} (hx : x ∈ D) (E : Entry) :
    Supported (setE Γ x E) D := fun v hv => by
  have : v ≠ x := fun e => hv (e ▸ hx)
  simp [setE, upd, this, h v hv]

theorem supported_exitScope {Γ : Ctx} {D : List Var} (h : Supported Γ D) (x : Var) :
    Supported (exitScope x Γ) D := fun v hv => by
  unfold exitScope; simp only [upd]; split
  · rfl
  · exact supported_kill h .replace false x v hv

/-- Two supported contexts that agree on `D` are equal. -/
theorem eq_of_agree {Γ Δ : Ctx} {D : List Var} (h1 : Supported Γ D) (h2 : Supported Δ D)
    (h : D.all (fun v => Γ v == Δ v) = true) : Γ = Δ := by
  funext v
  by_cases hv : v ∈ D
  · have := List.all_eq_true.mp h v hv; simpa using this
  · rw [h1 v hv, h2 v hv]

/-! ### `Weaker` decided over the domain (used by C1's dedup and C2's certificates) -/

def subB (a b : List Dep) : Bool := a.all (fun d => decide (d ∈ b))

theorem subB_sound {a b : List Dep} (h : subB a b = true) : a ⊆ b := fun d hd =>
  of_decide_eq_true (List.all_eq_true.mp h d hd)

/-- `EntryWeaker`, decided. -/
def entryWeakerB (E E' : Entry) : Bool :=
  decide (E'.ty = E.ty) && decide (E'.mode = E.mode) && (decide (E.mode ≠ .rootb) || decide (E' = E)) &&
    (!E'.live || (E.live && (E.mode.ownSlot || subB E.path E'.path) && subB E.held E'.held))

theorem entryWeakerB_sound {E E' : Entry} (h : entryWeakerB E E' = true) : EntryWeaker E E' := by
  simp only [entryWeakerB, Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq, Bool.not_eq_true'] at h
  obtain ⟨⟨⟨hty, hm⟩, hr⟩, hl⟩ := h
  refine ⟨hty, hm, fun e => hr.resolve_left (fun h' => h' e), fun hl' => ?_⟩
  rcases hl with h0 | ⟨⟨h1, h2⟩, h3⟩
  · rw [hl'] at h0; cases h0
  · refine ⟨h1, fun ho => ?_, subB_sound h3⟩
    rcases h2 with h2 | h2
    · rw [ho] at h2; cases h2
    · exact subB_sound h2

/-- `CtxWF` over the domain, decided. -/
def ctxWFB (D : List Var) (Γ : Ctx) : Bool :=
  D.all fun v => match Γ v with
    | some E => !E.live || !(decide (E.ty ≠ .int ∨ E.mode = .rootb)) ||
        (roots E.vdeps).all fun r => match Γ r with
          | some Er => Er.mode.isRoot
          | none => false
    | none => true

theorem ctxWFB_sound {D : List Var} {Γ : Ctx} (hs : Supported Γ D) (h : ctxWFB D Γ = true) : CtxWF Γ := by
  intro v E hv hl hk r hr
  have hvD : v ∈ D := by
    apply Classical.byContradiction; intro hn; rw [hs v hn] at hv; cases hv
  have := List.all_eq_true.mp h v hvD
  rw [hv] at this
  simp only [Bool.or_eq_true, Bool.not_eq_true', decide_eq_false_iff_not] at this
  rcases this with (h0 | h0) | h0
  · rw [hl] at h0; cases h0
  · exact absurd hk h0
  · have := List.all_eq_true.mp h0 r hr
    split at this
    · rename_i Er hEr; exact ⟨Er, hEr, this⟩
    · cases this

/-- `Weaker Γ Γ'` over the domain, decided. -/
def weakerB (D : List Var) (Γ Γ' : Ctx) : Bool :=
  (D.all fun v => match Γ v, Γ' v with
    | none, none => true
    | some E, some E' => entryWeakerB E E'
    | _, _ => false) && ctxWFB D Γ'

theorem weakerB_sound {D : List Var} {Γ Γ' : Ctx} (hs : Supported Γ D) (hs' : Supported Γ' D)
    (h : weakerB D Γ Γ' = true) : Weaker Γ Γ' := by
  simp only [weakerB, Bool.and_eq_true] at h
  obtain ⟨h1, h2⟩ := h
  refine ⟨fun v => ?_, ctxWFB_sound hs' h2⟩
  by_cases hv : v ∈ D
  · have := List.all_eq_true.mp h1 v hv
    split at this
    · rename_i ha hb; exact ⟨by simp [ha, hb], fun E E' e1 e2 => by rw [ha] at e1; cases e1⟩
    · rename_i E E' ha hb
      exact ⟨by simp [ha, hb], fun E1 E1' e1 e2 => by
        rw [ha] at e1; rw [hb] at e2; cases e1; cases e2; exact entryWeakerB_sound this⟩
    · cases this
  · rw [hs v hv, hs' v hv]; exact ⟨Iff.rfl, fun E _ e => by cases e⟩

theorem inferRhs_supported {Γ : Ctx} {F : List Var} {D : List Var} {r : Rhs} {E : Entry} {Γ1 : Ctx}
    (hs : Supported Γ D) (hD : ∀ v ∈ r.vars, v ∈ D) (h : inferRhs Γ F r = some (E, Γ1)) : Supported Γ1 D := by
  cases r with
  | expr e => simp only [inferRhs] at h; split at h <;> cases h; exact hs
  | new t => simp only [inferRhs] at h; split at h <;> cases h; exact hs
  | var y =>
    simp only [inferRhs] at h
    split at h
    · split at h
      · split at h
        · cases h
        · cases h; exact supported_setE (supported_kill hs _ _ _) (hD y (by simp [Rhs.vars])) _
      · cases h; exact hs
      · cases h; exact hs
      · cases h
    · cases h
  | borrow y => simp only [inferRhs] at h; split at h <;> (try split at h) <;> cases h; exact hs
  | «at» y i =>
    simp only [inferRhs] at h; split at h <;> (try split at h) <;> (try split at h) <;> cases h; exact hs
  | view y =>
    simp only [inferRhs] at h; split at h <;> (try split at h) <;> (try split at h) <;> cases h; exact hs
  | sat y i =>
    simp only [inferRhs] at h; split at h <;> (try split at h) <;> (try split at h) <;> cases h; exact hs
  | pop y =>
    simp only [inferRhs] at h; split at h <;> (try split at h) <;> (try split at h) <;> cases h
    exact supported_kill hs _ _ _

/-! ### Duplicate dependencies dropped (AGORA-988)

A1's push appends what the pushed value depends on to what the `Vec`
holds (`Ex1.held ++ D`), and a call appends what its arguments hold in
every kind (`callPost`, `callRes`). The checker computes those lists
exactly, so repeated pushes or calls grow them geometrically
(github#2242's review). `Entry.dedup1` drops the duplicates. A1's
`EntryWeaker` is stated by membership, so the entry is weaker than the
original (`EntryWeaker.dedup1`), and a context with some entries
deduplicated is `Weaker` once it is well formed, which the checker
decides. The drop is one `sub` step: on what a call's continuation starts
from (`settleL1`, in C2's `checkC`) or on where a push ends (`settleOutL1`,
in `checkS`). Where a check fails, the exact context is kept, so nothing
is refused for it. C0's `checkStmt` has no domain to decide well-formedness
over, so it stays exact. -/

/-- An entry with duplicates dropped from both lists. A borrowed
    parameter's entry stays as it is: `EntryWeaker` keeps it exactly. -/
def _root_.A1.Entry.dedup1 (E : Entry) : Entry :=
  if E.mode = .rootb then E else { E with path := dedupL E.path, held := dedupL E.held }

theorem EntryWeaker.dedup1 (E : Entry) : EntryWeaker E E.dedup1 := by
  unfold Entry.dedup1
  by_cases hm : E.mode = .rootb
  · simp only [hm, ite_true]; exact EntryWeaker.refl E
  · simp only [hm, ite_false]
    exact ⟨rfl, rfl, fun h => absurd h hm, fun hl => ⟨hl, fun _ => sub_dedupL, sub_dedupL⟩⟩

/-- ... and the other way: the two entries say the same. -/
theorem EntryWeaker.of_dedup1 (E : Entry) : EntryWeaker E.dedup1 E := by
  unfold Entry.dedup1
  by_cases hm : E.mode = .rootb
  · simp only [hm, ite_true]; exact EntryWeaker.refl E
  · simp only [hm, ite_false]
    exact ⟨rfl, rfl, fun h => absurd h hm, fun hl => ⟨hl, fun _ => dedupL_sub, dedupL_sub⟩⟩

/-- Does dropping duplicates change one of the entries of `vs`? -/
def dupsAt1 (vs : List Var) (Γ : Ctx) : Bool :=
  vs.any fun v => match Γ v with
    | some E => decide (E.dedup1 ≠ E)
    | none => false

theorem supported_tbl1 {D : List Var} (L : Var → Option Entry) : Supported (ctxOfTbl (tblOf D L)) D :=
  fun _ hv => ctxOfTbl_none _ hv

/-- `Γ` with the entries of `vs` deduplicated, read into a table over `D`. -/
def dedupTbl1 (D vs : List Var) (Γ : Ctx) : CtxT Entry := tblOf D (mapAt Entry.dedup1 vs Γ)

theorem weaker_dedup1 {Γ : Ctx} {D : List Var} (hs : Supported Γ D) (vs : List Var)
    (hw : CtxWF (ctxOfTbl (dedupTbl1 D vs Γ))) : Weaker Γ (ctxOfTbl (dedupTbl1 D vs Γ)) := by
  refine ⟨fun v => ?_, hw⟩
  unfold dedupTbl1
  rcases ctxOfTbl_mapAt hs Entry.dedup1 vs v with e | e <;> rw [e]
  · exact ⟨Iff.rfl, fun E E' h1 h2 => by rw [h1] at h2; cases h2; exact EntryWeaker.refl E⟩
  · refine ⟨by cases Γ v <;> simp, fun E E' h1 h2 => ?_⟩
    rw [h1] at h2; cases h2; exact EntryWeaker.dedup1 E

/-- ... and the other way, once the context it came from is well formed. -/
theorem weaker_of_dedup1 {Γ : Ctx} {D : List Var} (hs : Supported Γ D) (vs : List Var) (hw : CtxWF Γ) :
    Weaker (ctxOfTbl (dedupTbl1 D vs Γ)) Γ := by
  refine ⟨fun v => ?_, hw⟩
  unfold dedupTbl1
  rcases ctxOfTbl_mapAt hs Entry.dedup1 vs v with e | e <;> rw [e]
  · exact ⟨Iff.rfl, fun E E' h1 h2 => by rw [h1] at h2; cases h2; exact EntryWeaker.refl E⟩
  · refine ⟨by cases Γ v <;> simp, fun E E' h1 h2 => ?_⟩
    cases hv : Γ v with
    | none => rw [hv] at h1; cases h1
    | some E0 => rw [hv] at h1 h2; cases h1; cases h2; exact EntryWeaker.of_dedup1 _

/-- `Weaker Γ Γ`, where `Γ` is well formed. -/
theorem weaker_self1 {D : List Var} {Γ : Ctx} (hs : Supported Γ D) (h : ctxWFB D Γ = true) : Weaker Γ Γ :=
  ⟨fun v => ⟨Iff.rfl, fun E E' e1 e2 => by rw [e1] at e2; cases e2; exact EntryWeaker.refl _⟩,
    ctxWFB_sound hs h⟩

/-- The context a statement starts from, read into a table over `D`, its
    duplicates dropped if that changes it and keeps it well formed. As A2's
    `settleL2`, it is a `List` the checker reads through `ctxOfTbl`, so it
    is built once. -/
def settleL1 (D vs : List Var) (Γ : Ctx) : CtxT Entry :=
  if dupsAt1 vs Γ then
    let L := dedupTbl1 D vs Γ
    if ctxWFB D (ctxOfTbl L) then L else tblOf D Γ
  else tblOf D Γ

theorem settleL1_supported {Γ : Ctx} {D : List Var} (vs : List Var) :
    Supported (ctxOfTbl (settleL1 D vs Γ)) D := by
  unfold settleL1
  split
  · simp only; split
    · exact supported_tbl1 _
    · exact supported_tbl1 _
  · exact supported_tbl1 _

theorem settleL1_weaker {Γ : Ctx} {D : List Var} (hs : Supported Γ D) (vs : List Var) :
    ctxOfTbl (settleL1 D vs Γ) = Γ ∨ Weaker Γ (ctxOfTbl (settleL1 D vs Γ)) := by
  unfold settleL1
  split
  · simp only; split
    · rename_i hc
      exact Or.inr (weaker_dedup1 hs vs (ctxWFB_sound (supported_tbl1 _) hc))
    · exact Or.inl (ctxOfTbl_self hs)
  · exact Or.inl (ctxOfTbl_self hs)

theorem stmtT_settleIn1 {P : Prog} {Γ : Ctx} {F : List Var} {s : Stmt} {Δ : Ctx} {D : List Var}
    (hs : Supported Γ D) (vs : List Var) (ht : StmtT P (ctxOfTbl (settleL1 D vs Γ)) F s Δ) : StmtT P Γ F s Δ := by
  rcases settleL1_weaker hs vs with e | w
  · rw [e] at ht; exact ht
  · exact .sub w ht (Or.inl rfl)

/-- The context a statement ends in, as a table over `D`, its duplicates
    dropped where that and the context it started from are well formed. -/
def settleOutL1 (D vs : List Var) (Γ Δ : Ctx) : CtxT Entry :=
  if dupsAt1 vs Δ && ctxWFB D (ctxOfTbl (tblOf D Γ)) then settleL1 D vs Δ else tblOf D Δ

theorem settleOutL1_supported {Γ Δ : Ctx} {D : List Var} (vs : List Var) :
    Supported (ctxOfTbl (settleOutL1 D vs Γ Δ)) D := by
  unfold settleOutL1
  split
  · exact settleL1_supported vs
  · exact supported_tbl1 _

theorem stmtT_settleOut1 {P : Prog} {Γ : Ctx} {F : List Var} {s : Stmt} {Δ : Ctx} {D : List Var}
    (hs : Supported Γ D) (hsΔ : Supported Δ D) (vs : List Var) (ht : StmtT P Γ F s Δ) :
    StmtT P Γ F s (ctxOfTbl (settleOutL1 D vs Γ Δ)) := by
  unfold settleOutL1
  split
  · rename_i hc
    simp only [Bool.and_eq_true] at hc
    have hc2 := hc.2
    rw [ctxOfTbl_self hs] at hc2
    rcases settleL1_weaker hsΔ vs with e | w
    · rw [e]; exact ht
    · exact .sub (weaker_self1 hs hc2) ht (Or.inr w)
  · rw [ctxOfTbl_self hsΔ]; exact ht

/-- The checker with joins. Straight-line leaves go to C0's `checkStmt`.
    Its soundness (`checkS_sound`) needs two things of the domain `D`: every
    slot `Γ` binds (`Supported Γ D`) and every slot `s` names. A join compares
    the arms only over `D`, so a slot left out of it is not compared: from
    the empty context, `s.vars` alone is enough (`checkedS_memory_safe`);
    from any other context, `D` must also cover what `Γ` binds. -/
def checkS (D : List Var) : Ctx → List Var → Stmt → Option Ctx
  | Γ, F, .seq a b =>
    if b.src then (match checkS D Γ F a with
      | some Γ1 => checkS D Γ1 F b
      | none => none) else none
  | Γ, F, .letv x r s =>
    if s.src ∧ Γ x = none ∧ x ∉ F then
      match inferRhs Γ F r with
      | some (E, Γ1) => (checkS D (setE Γ1 x E) F s).map (exitScope x)
      | none => none
    else none
  | Γ, F, .frozen z s => checkS D Γ (F ++ z) s
  | Γ, F, .ite c a b =>
    if a.src ∧ b.src ∧ checkExpr Γ c then
      match checkS D Γ F a, checkS D Γ F b with
      | some Δa, some Δb => if D.all (fun v => Δa v == Δb v) then some Δa else none
      | _, _ => none
    else none
  | Γ, F, .while c s =>
    if s.src ∧ checkExpr Γ c then
      match checkS D Γ F s with
      | some Δ => if D.all (fun v => Δ v == Γ v) then some Γ else none
      | none => none
    else none
  | Γ, F, .push x y => (checkStmt Γ F (.push x y)).map fun Δ => ctxOfTbl (settleOutL1 D [x] Γ Δ)
  | Γ, F, s => checkStmt Γ F s

/-- C0's leaves keep the support. -/
theorem checkStmt_leaf_supported {Γ : Ctx} {F D : List Var} {s : Stmt} {Δ : Ctx} (hs : Supported Γ D)
    (hD : ∀ v ∈ s.vars, v ∈ D) (h : checkStmt Γ F s = some Δ)
    (hleaf : s = .skip ∨ (∃ x r, s = .assign x r) ∨ (∃ x y, s = .push x y) ∨ (∃ x, s = .free x)) :
    Supported Δ D := by
  rcases hleaf with rfl | ⟨x, r, rfl⟩ | ⟨x, y, rfl⟩ | ⟨x, rfl⟩
  · simp [checkStmt] at h; subst h; exact hs
  · simp only [checkStmt] at h
    split at h
    · split at h
      · cases h
      · split at h
        · rename_i E Γ1 hr
          split at h
          · cases h
            exact supported_setE (supported_kill (inferRhs_supported hs (fun v hv => hD v (by simp [Stmt.vars, hv])) hr) _ _ _)
              (hD x (by simp [Stmt.vars])) _
          · cases h
        · cases h
    · cases h
  · simp only [checkStmt] at h
    split at h
    · split at h
      · split at h
        · split at h
          · rename_i D' Γ1 hpa
            have hs1 : Supported Γ1 D := by
              unfold pushArg at hpa
              split at hpa
              · split at hpa
                · cases hpa; exact supported_setE (supported_kill hs _ _ _) (hD y (by simp [Stmt.vars])) _
                · cases hpa
              · cases hpa; exact hs
              · split at hpa
                · cases hpa; exact hs
                · cases hpa
            split at h
            · cases h
            · split at h
              · cases h; exact supported_setE (supported_kill hs1 _ _ _) (hD x (by simp [Stmt.vars])) _
              · cases h
          · cases h
        · cases h
      · cases h
    · cases h
  · simp only [checkStmt] at h
    split at h
    · split at h
      · split at h
        · cases h; exact supported_setE (supported_kill hs _ _ _) (hD x (by simp [Stmt.vars])) _
        · cases h
      · cases h
    · cases h

theorem checkS_sound {P : Prog} {D : List Var} : ∀ {s : Stmt} {Γ : Ctx} {F : List Var} {Δ : Ctx},
    Supported Γ D → (∀ v ∈ s.vars, v ∈ D) → checkS D Γ F s = some Δ → StmtT P Γ F s Δ ∧ Supported Δ D := by
  intro s
  induction s with
  | skip => intro Γ F Δ hs hD h; simp [checkS, checkStmt] at h; subst h; exact ⟨.skip, hs⟩
  | seq a b iha ihb =>
    intro Γ F Δ hs hD h
    simp only [checkS] at h
    split at h
    · rename_i hb
      split at h
      · rename_i Γ1 ha
        obtain ⟨ta, sa⟩ := iha hs (fun v hv => hD v (by simp [Stmt.vars, hv])) ha
        obtain ⟨tb, sb⟩ := ihb sa (fun v hv => hD v (by simp [Stmt.vars, hv])) h
        exact ⟨.seq hb ta tb, sb⟩
      · cases h
    · cases h
  | letv x r s ih =>
    intro Γ F Δ hs hD h
    simp only [checkS] at h
    split at h
    · rename_i hc
      obtain ⟨hsrc, hx, hF⟩ := hc
      split at h
      · rename_i E Γ1 hr
        obtain ⟨Δ0, h0, rfl⟩ := Option.map_eq_some_iff.mp h
        have hs1 := inferRhs_supported hs (fun v hv => hD v (by simp [Stmt.vars, hv])) hr
        obtain ⟨t0, s0⟩ := ih (supported_setE hs1 (hD x (by simp [Stmt.vars])) E)
          (fun v hv => hD v (by simp [Stmt.vars, hv])) h0
        exact ⟨.letv hsrc hx hF (inferRhs_sound hr) t0, supported_exitScope s0 x⟩
      · cases h
    · cases h
  | letcall x f args s ih => intro Γ F Δ hs hD h; simp [checkS, checkStmt] at h
  | assign x r =>
    intro Γ F Δ hs hD h
    simp only [checkS] at h
    exact ⟨checkStmt_sound h, checkStmt_leaf_supported hs hD h (Or.inr (Or.inl ⟨x, r, rfl⟩))⟩
  | ite c a b iha ihb =>
    intro Γ F Δ hs hD h
    simp only [checkS] at h
    split at h
    · rename_i hc
      obtain ⟨ha, hb, hce⟩ := hc
      split at h
      · rename_i Δa Δb hca hcb
        split at h
        · rename_i hag
          simp only [Option.some.injEq] at h; subst h
          obtain ⟨ta, sa⟩ := iha hs (fun v hv => hD v (by simp [Stmt.vars, hv])) hca
          obtain ⟨tb, sb⟩ := ihb hs (fun v hv => hD v (by simp [Stmt.vars, hv])) hcb
          have heq : Δa = Δb := eq_of_agree sa sb hag
          subst heq
          exact ⟨.ite ha hb (checkExpr_sound hce) ta tb, sa⟩
        · cases h
      · cases h
    · cases h
  | «while» c s ih =>
    intro Γ F Δ hs hD h
    simp only [checkS] at h
    split at h
    · rename_i hc
      obtain ⟨hsrc, hce⟩ := hc
      split at h
      · rename_i Δ0 h0
        split at h
        · rename_i hag
          simp only [Option.some.injEq] at h; subst h
          obtain ⟨t0, s0⟩ := ih hs (fun v hv => hD v (by simp [Stmt.vars, hv])) h0
          have heq : Δ0 = Γ := eq_of_agree s0 hs hag
          subst heq
          exact ⟨.while hsrc (checkExpr_sound hce) t0, hs⟩
        · cases h
      · cases h
    · cases h
  | push x y =>
    intro Γ F Δ hs hD h
    simp only [checkS] at h
    obtain ⟨Δ0, h0, rfl⟩ := Option.map_eq_some_iff.mp h
    have s0 := checkStmt_leaf_supported hs hD h0 (Or.inr (Or.inr (Or.inl ⟨x, y, rfl⟩)))
    exact ⟨stmtT_settleOut1 hs s0 [x] (checkStmt_sound h0), settleOutL1_supported [x]⟩
  | free x =>
    intro Γ F Δ hs hD h
    simp only [checkS] at h
    exact ⟨checkStmt_sound h, checkStmt_leaf_supported hs hD h (Or.inr (Or.inr (Or.inr ⟨x, rfl⟩)))⟩
  | scope x s _ => intro Γ F Δ hs hD h; simp [checkS, checkStmt] at h
  | rbind p s _ => intro Γ F Δ hs hD h; simp [checkS, checkStmt] at h
  | frozen z s ih =>
    intro Γ F Δ hs hD h
    simp only [checkS] at h
    obtain ⟨t0, s0⟩ := ih hs (fun v hv => hD v (by simp [Stmt.vars, hv])) h
    exact ⟨.frozen t0, s0⟩

/-- A program the joining checker accepts, run from the empty store, never
    gets stuck. The domain is the program's own variables. -/
theorem checkedS_memory_safe {P : Prog} (hP : ProgOK P) {s : Stmt} {Δ : Ctx}
    (hc : checkS s.vars (fun _ => none) [] s = some Δ) (hs : s.src = true) {nv : Nat}
    (hv : ∀ v ∈ s.vars, v < nv) {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem nv) s (.ok m' s')) :
    ¬ Stuck P m' s' :=
  memory_safe hP (checkS_sound (P := P) (fun _ _ => rfl) (fun _ h => h) hc).1 hs hv hr

/-- As `checkedS_memory_safe`, over the program's variables with each slot
    listed once: a join compares the arms once per slot, not once per
    mention (github#2242's review). -/
theorem checkedS_memory_safe_dedup {P : Prog} (hP : ProgOK P) {s : Stmt} {Δ : Ctx}
    (hc : checkS s.vars.eraseDups (fun _ => none) [] s = some Δ) (hs : s.src = true) {nv : Nat}
    (hv : ∀ v ∈ s.vars, v < nv) {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem nv) s (.ok m' s')) :
    ¬ Stuck P m' s' :=
  memory_safe hP (checkS_sound (P := P) (fun _ _ => rfl) (fun _ h => List.mem_eraseDups.mpr h) hc).1 hs hv hr

/-- A loop that pushes into a `Vec` it owns (once: its length reaches 1),
    then frees it: accepted. -/
def ex3 : Stmt :=
  .letv 0 (.new .int) (.letv 1 (.expr (.lit 3)) (.seq (.while (.lt (.len 0) (.lit 1)) (.push 0 1)) (.free 0)))

example : (checkS ex3.vars (fun _ => none) [] ex3).isSome = true := by decide

/-- One arm frees the `Vec`, the other does not: the arms disagree, refused. -/
def ex4 : Stmt :=
  .letv 0 (.new .int) (.ite (.lit 1) (.free 0) .skip)

example : (checkS ex4.vars (fun _ => none) [] ex4).isSome = false := by decide

end C
