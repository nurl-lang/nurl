import A2.DynCell

/-!
  A2 — an owner's old value handed over to the binding that reads it by
  name, as the calculus has it (`A2/HANDOVER_DESIGN.md`, AGORA-885).

      : ~ String other ( mk )
      : ~ String o ( mk )
      = o other          -- o's own value is freed; o reads other's by name
      = other ( mk )     -- other's old value goes to o, which owns it now
      : i n ( string_len o )

  nurlc gives `o` a drop flag and, at `= o other`, sets it down: `o` holds a
  copy of `other`'s handle and is recorded as one of `other`'s borrowers.
  At `= other …` the old value is not freed while a borrower holds its
  buffer (an identity test on the buffer at run time): the borrower's flag
  goes up instead, and it owns the value from there on
  (`mem_udrop_hand_over`; MEMORY.md §7.6).

  The calculus needs no flag for it.  `o` is an *owner cell* `oc` (an
  option, as in `A2/DynCell.lean`) and a *borrow* `ob`, through which `o` is
  read:

  - `= o other` is `= oc none` (the old value is dropped) and
    `= ob ( borrow other )`;
  - `= other …` is `: q ( take other )  = oc ( some q )  = ob ( payload oc )`
    (the hand-over: `take`, `A2/TAKE_DESIGN.md`, moves the value out and
    leaves `other` a fresh empty one), then `= other …`;
  - a read of `o` reads `ob`, and the cell drops what it holds at its end.

  This module types the encoded program with A2's own rules and applies
  `memory_safe` and `no_leak_end` to it: the hand-over is inside what the
  theorems cover, once nurlc's lowering is read as this encoding (phase C
  / D: the borrower's flag is "is the cell `some`?").
-/

namespace A2.HandOver

open A2.DynCell (NoRootb noRootb_empty str opt Enew EnewD Ecl)

/-- No program functions: the hand-over is the caller's own code. -/
def P : Prog := []

/-! ### The program

    `z` is 0 (the integer `none` is made from), `other` 1, `o`'s own first
    value `y` 2, the cell `oc` 3, the reader `ob` 4, the taken value `q` 5
    and `n` 6. -/

/-- `= other ( mk )` with `o` reading `other`: the old value goes to the cell. -/
def handOver : Stmt :=
  .letv 5 (.take 1) (.seq (.assign 3 (.inr .int 5)) (.assign 4 (.getr 3)))

def main : Stmt :=
  .letv 0 (.expr (.lit 0)) (.letv 1 (.new .int) (.letv 2 (.new .int)
    (.letv 3 (.inr .int 2) (.letv 4 (.getr 3)
      (.seq (.assign 3 (.inl 0 str))            -- `= o other`: o's own value goes,
      (.seq (.assign 4 (.borrow 1))             -- and o reads other
      (.seq handOver                            -- `= other ( mk )`: the hand-over,
      (.seq (.assign 1 (.new .int))             -- then other's new value
        (.letv 6 (.expr (.len 4)) .skip)))))))))   -- `string_len o`

/-! ### Entries -/

/-- `ob` reading the cell's payload. -/
def Eob : Entry := ⟨str, .bor, true, [⟨3, .inner⟩], [], false, false, false, false⟩
/-- `ob` reading `other`. -/
def Eoth : Entry := ⟨str, .bor, true, [⟨1, .self⟩], [], false, false, false, false⟩
/-- The cell holding `none`. -/
def Enone : Entry := ⟨opt, .own, true, [], [], false, false, false, false⟩

/-! ### Contexts with no borrowed parameter and no destructor binding -/

theorem nrDtor {Γ : Ctx} (h : NoRootb Γ) (e : Eff) (hv : Bool) (x : Var) : DtorSafe Γ e hv x :=
  DtorSafe.of_none (fun v E hv => (h v E hv).2.1) _ _ _

theorem nrPin {Γ : Ctx} (h : NoRootb Γ) (x : Var) : NoPin Γ x := A2.DynCell.NoRootb.noPin h x

theorem nrEnd {Γ : Ctx} (h : NoRootb Γ) (x : Var) : EndOK Γ x := A2.DynCell.NoRootb.endOK h x

/-- `NoRootb` of a context the rules build from the empty one. -/
syntax "noroot" : tactic
macro_rules
  | `(tactic| noroot) => `(tactic| first
      | exact noRootb_empty
      | (apply A2.DynCell.NoRootb.exitScope; noroot)
      | (apply A2.DynCell.NoRootb.kill; noroot)
      | (refine A2.DynCell.NoRootb.setE ?_ (by simp [opt, str, intE, Enew, EnewD, Ecl, Eob, Eoth, Enone]); noroot))

/-- A lookup in a context the rules build. -/
syntax "look" : tactic
macro_rules
  | `(tactic| look) => `(tactic| simp [A2.setE, upd, A2.kill, killE, hits, A2.exitScope, Entry.vdeps,
      Mode.ownSlot, derive, Mode.isRoot, rootKind, projE, projDeps, str, opt, intE, Enew, EnewD, Ecl, Eob,
      Eoth, Enone, Eff.kills, comp, roots])

/-! ### Typing -/

theorem main_typed : ∃ Δ, StmtT P .none (fun _ => none) [] main Δ := by
  apply Exists.intro
  -- `: i z 0`
  refine' StmtT.letv (x := 0) rfl rfl (by simp) (RhsT.expr ExprT.lit) ?_ ?_
  rotate_left
  · -- `: ~ String other ( mk )`
    refine' StmtT.letv (x := 1) rfl (by look) (by simp) (RhsT.new (t := .int) rfl) ?_ ?_
    rotate_left
    · -- `: ~ String o ( mk )`: its first value, which goes into the cell
      refine' StmtT.letv (x := 2) rfl (by look) (by simp) (RhsT.new (t := .int) rfl) ?_ ?_
      rotate_left
      · refine' StmtT.letv (x := 3) (E := Ecl) rfl (by look) (by simp)
          (RhsT.inr (Ey := Enew) (by look) rfl
            (PushArg.move (by simp [Enew, str, Ty.owning]) rfl (by simp) (nrPin (by noroot) _)
              (nrDtor (by noroot) _ _ _)) rfl) ?_ ?_
        rotate_left
        · -- `ob`: o is read through the cell
          refine' StmtT.letv (x := 4) (E := Eob) rfl (by look) (by simp)
            (RhsT.getr (E := Ecl) (a := .int) (b := str) (by look) rfl rfl) ?_ ?_
          rotate_left
          · -- `= o other`: the cell's old value goes ...
            refine' StmtT.seq rfl ?_ ?_
            rotate_left 2
            · apply StmtT.assign (Ex := Ecl) (E := Enone)
              · look
              · simp
              · exact (Or.inl ⟨rfl, rfl⟩)
              · exact (RhsT.inl (Ey := intE) (by look) rfl PushArg.int rfl)
              all_goals first | rfl | exact nrPin (by noroot) _ | exact nrDtor (by noroot) _ _ _ | (look; done)
            · -- ... and `o` reads `other`
              refine' StmtT.seq rfl ?_ ?_
              rotate_left 2
              · apply StmtT.assign (Ex := { Eob with live := false }) (E := Eoth)
                · look
                · simp
                · exact (Or.inr (Or.inr ⟨rfl, rfl⟩))
                · exact (RhsT.borrow (E := Enew) (t := .int) (by look) rfl rfl)
                all_goals first | rfl | exact nrPin (by noroot) _ | exact nrDtor (by noroot) _ _ _ | (look; done)
              · refine' StmtT.seq rfl ?_ ?_
                rotate_left 2
                · -- the hand-over: `: q ( take other )  = oc ( some q )  = ob ( payload oc )`
                  refine' StmtT.letv (x := 5) (E := Enew) rfl (by look) (by simp)
                    (RhsT.take (E := Enew) (t := .int) (by look) rfl rfl rfl (Or.inl rfl) rfl (by simp)
                      (nrPin (by noroot) _) (nrDtor (by noroot) _ _ _)) ?_ ?_
                  rotate_left
                  · refine' StmtT.seq rfl ?_ ?_
                    rotate_left 2
                    · apply StmtT.assign (Ex := Enone) (E := Ecl)
                      · look
                      · simp
                      · exact (Or.inl ⟨rfl, rfl⟩)
                      · exact (RhsT.inr (Ey := Enew) (by look) rfl (PushArg.move (by simp [Enew, str, Ty.owning]) rfl (by simp) (nrPin (by noroot) _) (nrDtor (by noroot) _ _ _)) rfl)
                      all_goals first | rfl | exact nrPin (by noroot) _ | exact nrDtor (by noroot) _ _ _ | (look; done)
                    · apply StmtT.assign (Ex := { Eoth with live := false }) (E := Eob)
                      · look
                      · simp
                      · exact (Or.inr (Or.inr ⟨rfl, rfl⟩))
                      · exact (RhsT.getr (E := Ecl) (a := .int) (b := str) (by look) rfl rfl)
                      all_goals first | rfl | exact nrPin (by noroot) _ | exact nrDtor (by noroot) _ _ _ | (look; done)
                  · exact nrEnd (by noroot) _
                · -- `= other ( mk )`, then `string_len o`
                  refine' StmtT.seq rfl ?_ ?_
                  rotate_left 2
                  · apply StmtT.assign (Ex := Enew) (E := Enew)
                    · look
                    · simp
                    · exact (Or.inl ⟨rfl, rfl⟩)
                    · exact (RhsT.new (t := .int) rfl)
                    all_goals first | rfl | exact nrPin (by noroot) _ | exact nrDtor (by noroot) _ _ _ | (look; done)
                  · refine' StmtT.letv (x := 6) rfl (by look) (by simp)
                      (RhsT.expr (ExprT.len (E := Eob) (t := .int) (by look) rfl rfl)) StmtT.skip ?_
                    exact nrEnd (by noroot) _
          · exact nrEnd (by noroot) _
        · exact nrEnd (by noroot) _
      · exact nrEnd (by noroot) _
    · exact nrEnd (by noroot) _
  · exact nrEnd (by noroot) _


/-! ### The hand-over decided at run time

    nurlc's `=` asks at run time whether a borrower still holds the old
    value's buffer: `o` may read `other` on some runs only.

        : ~ String other ( mk )  : ~ String o ( mk )
        ? c { = o other } {}
        = other ( mk )           -- handed over on the runs `o` reads `other`
        : i n ( string_len o )

    In the encoding the run-time answer is a flag `a` (7 is `c`, 8 is `a`):
    the first `ite` sets it where `o` is given `other`, and the second runs
    the hand-over where it is set.  Where it is not, `o`'s value is the
    cell's already, and `ob` is pointed at it again.  After the first `ite`
    `ob` may read `other` or the cell (`EobJ`, the join); after the second,
    the cell. -/

/-- `= o other` on the runs `c` is set, which sets `a`. -/
def byName : Stmt :=
  .seq (.assign 3 (.inl 0 str)) (.seq (.assign 4 (.borrow 1)) (.assign 8 (.expr (.lit 1))))

/-- The two decisions. -/
def decide1 : Stmt := .ite (.var 7) byName (.assign 8 (.expr (.lit 0)))
def decide2 : Stmt := .ite (.var 8) handOver (.assign 4 (.getr 3))

/-- The program, for every value `c` of the condition: `c ≠ 0` runs the
    by-name `=` and the hand-over, `c = 0` neither. -/
def mainJ (c : Nat) : Stmt :=
  .letv 0 (.expr (.lit 0)) (.letv 1 (.new .int) (.letv 2 (.new .int)
    (.letv 3 (.inr .int 2) (.letv 4 (.getr 3) (.letv 7 (.expr (.lit c)) (.letv 8 (.expr (.lit 0))
      (.seq decide1 (.seq decide2
      (.seq (.assign 1 (.new .int))
        (.letv 6 (.expr (.len 4)) .skip))))))))))

/-- `ob` reading `other` or the cell's payload. -/
def EobJ : Entry := ⟨str, .bor, true, [⟨1, .self⟩, ⟨3, .inner⟩], [], false, false, false, false⟩

/-- The contexts around the decisions, with `ob`'s entry `E4`. -/
def ctxJ (E4 : Entry) : Ctx := fun v =>
  if v = 0 then some intE else if v = 1 then some Enew else if v = 2 then some EnewD
  else if v = 3 then some Ecl else if v = 4 then some E4 else if v = 7 then some intE
  else if v = 8 then some intE else none

theorem ctxJ_noRootb {E4 : Entry} (h : E4.mode ≠ .rootb ∧ E4.dtor = false ∧ E4.dbind = false) :
    NoRootb (ctxJ E4) := by
  intro v E hv
  rcases v with _ | _ | _ | _ | _ | _ | _ | _ | _ | v <;> simp [ctxJ] at hv <;> subst hv <;>
    first | exact h | simp [intE, Enew, EnewD, Ecl]

/-- What `ob` may read is bound, and owns its slot. -/
theorem ctxJ_wf {E4 : Entry} (h : E4.mode ≠ .rootb ∧ E4.dtor = false ∧ E4.dbind = false)
    (hr : ∀ r ∈ roots E4.vdeps, r = 1 ∨ r = 3) : CtxWF (ctxJ E4) := by
  have hN := ctxJ_noRootb h
  refine ⟨fun v E hv _ _ r hrv => ?_, fun v E hv hd => absurd hd (by rw [(hN v E hv).2.2]; simp),
    fun v E hv hd => absurd hd (by rw [(hN v E hv).2.1]; simp),
    fun v E hv hd => absurd hd (by rw [(hN v E hv).2.2]; simp)⟩
  by_cases h4 : v = 4
  · subst h4; simp [ctxJ] at hv; subst hv
    rcases hr r hrv with rfl | rfl
    · exact ⟨Enew, by simp [ctxJ], rfl⟩
    · exact ⟨Ecl, by simp [ctxJ], rfl⟩
  · rcases v with _ | _ | _ | _ | _ | _ | _ | _ | _ | v <;> simp [ctxJ] at hv <;> try subst hv
    all_goals first | exact absurd rfl h4 | simp [intE, Enew, EnewD, Ecl, roots, Entry.vdeps, Mode.ownSlot] at hrv

theorem ctxJ_names {E4 : Entry} (h : ∀ d ∈ E4.vdeps, d.kind.isName = false) : NameWF (ctxJ E4) := by
  intro v E hv _ _ d hd b t hk
  by_cases h4 : v = 4
  · subst h4; simp [ctxJ] at hv; subst hv
    have := h d hd; rw [hk] at this; cases this
  · rcases v with _ | _ | _ | _ | _ | _ | _ | _ | _ | v <;> simp [ctxJ] at hv <;> try subst hv
    all_goals first | exact absurd rfl h4 | simp [intE, Enew, EnewD, Ecl, Entry.vdeps, Mode.ownSlot] at hd

theorem flags_Eob : Eob.mode ≠ .rootb ∧ Eob.dtor = false ∧ Eob.dbind = false := by simp [Eob]
theorem flags_EobJ : EobJ.mode ≠ .rootb ∧ EobJ.dtor = false ∧ EobJ.dbind = false := by simp [EobJ]

theorem wf_Eob : CtxWF (ctxJ Eob) :=
  ctxJ_wf flags_Eob (by intro r hr; simp [Eob, roots, Entry.vdeps, Mode.ownSlot] at hr; simp [hr])
theorem wf_EobJ : CtxWF (ctxJ EobJ) :=
  ctxJ_wf flags_EobJ (by intro r hr; simp [EobJ, roots, Entry.vdeps, Mode.ownSlot] at hr; omega)
theorem names_Eob : NameWF (ctxJ Eob) := ctxJ_names (by simp [Eob, Entry.vdeps, Mode.ownSlot, Kind.isName])
theorem names_EobJ : NameWF (ctxJ EobJ) :=
  ctxJ_names (by simp [EobJ, Entry.vdeps, Mode.ownSlot, Kind.isName])

/-- `ob` reading `other`, or the cell, is weaker than reading either. -/
theorem ew_J {E : Entry} (hE : E = Eoth ∨ E = Eob) : EntryWeaker E EobJ := by
  rcases hE with rfl | rfl <;>
  exact ⟨rfl, rfl, fun h => by simp [Eoth, Eob] at h, fun _ => ⟨rfl, fun _ => by simp [Eoth, Eob, EobJ], by simp [Eoth, Eob]⟩,
    fun h => by simp [Eoth, Eob] at h, rfl, fun h => by simp [EobJ] at h, fun h => by simp [Eoth, Eob] at h,
      fun _ _ _ hfr => by fresh_ew,
      fun _ _ hhf => by heldfresh_ew⟩

/-- A context that agrees with `ctxJ E4` but at `ob`, whose entry is weaker. -/
theorem weakerJ {Γ : Ctx} {E4 E4' : Entry} (h : ∀ v, v ≠ 4 → Γ v = ctxJ E4 v) (h4 : Γ 4 = some E4')
    (hw : EntryWeaker E4' E4) (hwf : CtxWF (ctxJ E4)) (hn : NameWF (ctxJ E4)) : Weaker Γ (ctxJ E4) := by
  refine ⟨fun v => ?_, hwf, hn⟩
  by_cases hv : v = 4
  · subst hv; rw [h4]
    refine ⟨by simp [ctxJ], fun E E' h1 h2 => ?_⟩
    simp [ctxJ] at h2; simp at h1; subst h1; subst h2; exact hw
  · rw [h v hv]; exact ⟨Iff.rfl, fun E E' h1 h2 => by rw [h1] at h2; cases h2; exact EntryWeaker.refl _⟩

/-- A lookup in a context built from `ctxJ`. -/
syntax "lookJ" : tactic
macro_rules
  | `(tactic| lookJ) => `(tactic| simp [ctxJ, A2.setE, upd, A2.kill, killE, hits, A2.exitScope, Entry.vdeps,
      Mode.ownSlot, derive, Mode.isRoot, rootKind, projE, projDeps, str, opt, intE, Enew, EnewD, Ecl, Eob,
      Eoth, Enone, EobJ, Eff.kills, comp, roots])

/-- `ctxJ`, and the contexts the rules build from it, have no borrowed
    parameter and no destructor binding. -/
syntax "norootJ" : tactic
macro_rules
  | `(tactic| norootJ) => `(tactic| first
      | exact ctxJ_noRootb flags_Eob
      | exact ctxJ_noRootb flags_EobJ
      | (apply A2.DynCell.NoRootb.exitScope; norootJ)
      | (apply A2.DynCell.NoRootb.kill; norootJ)
      | (refine A2.DynCell.NoRootb.setE ?_ (by simp [opt, str, intE, Enew, EnewD, Ecl, Eob, Eoth, Enone, EobJ]); norootJ))

/-- The rest of an `=`'s premises, once its right side is typed. -/
syntax "assignRest" : tactic
macro_rules
  | `(tactic| assignRest) => `(tactic|
      all_goals first | rfl | exact nrPin (by norootJ) _ | exact nrDtor (by norootJ) _ _ _ | (lookJ; done))

/-- `= o other`, on the runs `c` is set. -/
theorem byName_typed : ∃ Δ, StmtT P ξ (ctxJ Eob) [] byName Δ ∧ Δ 4 = some Eoth ∧
    ∀ v, v ≠ 4 → Δ v = ctxJ EobJ v := by
  refine' ⟨_, StmtT.seq rfl ?a1 (StmtT.seq rfl ?a2 ?a3), ?h4, ?hv⟩
  case a1 =>
    apply StmtT.assign (Ex := Ecl) (E := Enone)
    · lookJ
    · simp
    · exact Or.inl ⟨rfl, rfl⟩
    · exact RhsT.inl (Ey := intE) (by lookJ) rfl PushArg.int rfl
    assignRest
  case a2 =>
    apply StmtT.assign (Ex := { Eob with live := false }) (E := Eoth)
    · lookJ
    · simp
    · exact Or.inr (Or.inr ⟨rfl, rfl⟩)
    · exact RhsT.borrow (E := Enew) (t := .int) (by lookJ) rfl rfl
    assignRest
  case a3 =>
    apply StmtT.assign (Ex := intE) (E := intE)
    · lookJ
    · simp
    · exact Or.inr (Or.inr ⟨rfl, rfl⟩)
    · exact RhsT.expr ExprT.lit
    assignRest
  case h4 => lookJ
  case hv =>
    intro v hv
    rcases v with _ | _ | _ | _ | _ | _ | _ | _ | _ | v <;> first | exact absurd rfl hv | lookJ

/-- `a` cleared, on the runs `c` is not set: `o` keeps reading the cell. -/
theorem keep_typed : ∃ Δ, StmtT P ξ (ctxJ Eob) [] (.assign 8 (.expr (.lit 0))) Δ ∧ Δ 4 = some Eob ∧
    ∀ v, v ≠ 4 → Δ v = ctxJ EobJ v := by
  refine' ⟨_, StmtT.assign (Ex := intE) (E := intE) ?g1 ?g2 (Or.inr (Or.inr ⟨rfl, rfl⟩)) (RhsT.expr ExprT.lit)
    ?g5 ?g6 ?g7 ?g8 ?g9 ?g10, ?h4, ?hv⟩
  case g2 => simp
  all_goals try (first | rfl | exact nrPin (by norootJ) _ | exact nrDtor (by norootJ) _ _ _ | (lookJ; done))
  case hv =>
    intro v hv
    rcases v with _ | _ | _ | _ | _ | _ | _ | _ | _ | v <;> first | exact absurd rfl hv | lookJ

/-- The first decision: after it `o` reads `other` or the cell. -/
theorem decide1_typed : StmtT P ξ (ctxJ Eob) [] decide1 (ctxJ EobJ) := by
  obtain ⟨Δ, hb, h4, hv⟩ := byName_typed (ξ := ξ)
  obtain ⟨Δ', hk, h4', hv'⟩ := keep_typed (ξ := ξ)
  exact StmtT.ite rfl rfl (ExprT.var (E := intE) (by lookJ) rfl rfl)
    (StmtT.sub (Weaker.refl wf_Eob names_Eob) hb (Or.inr (weakerJ hv h4 (ew_J (Or.inl rfl)) wf_EobJ names_EobJ)))
    (StmtT.sub (Weaker.refl wf_Eob names_Eob) hk (Or.inr (weakerJ hv' h4' (ew_J (Or.inr rfl)) wf_EobJ names_EobJ)))

/-- The hand-over, on the runs `a` is set. -/
theorem handOver_typed : ∃ Δ, StmtT P ξ (ctxJ EobJ) [] handOver Δ ∧ Δ 4 = some Eob ∧
    ∀ v, v ≠ 4 → Δ v = ctxJ Eob v := by
  refine' ⟨_, StmtT.letv (x := 5) (E := Enew) rfl (by lookJ) (by simp)
    (RhsT.take (E := Enew) (t := .int) (by lookJ) rfl rfl rfl (Or.inl rfl) rfl (by simp)
      (nrPin (by norootJ) _) (nrDtor (by norootJ) _ _ _)) (StmtT.seq rfl ?c1 ?c2) ?e, ?h4, ?hv⟩
  case c1 =>
    apply StmtT.assign (Ex := Ecl) (E := Ecl)
    · lookJ
    · simp
    · exact Or.inl ⟨rfl, rfl⟩
    · exact RhsT.inr (Ey := Enew) (by lookJ) rfl
        (PushArg.move (by simp [Enew, str, Ty.owning]) rfl (by simp) (nrPin (by norootJ) _)
          (nrDtor (by norootJ) _ _ _)) rfl
    assignRest
  case c2 =>
    apply StmtT.assign (Ex := { EobJ with live := false }) (E := Eob)
    · lookJ
    · simp
    · exact Or.inr (Or.inr ⟨rfl, rfl⟩)
    · exact RhsT.getr (E := Ecl) (a := .int) (b := str) (by lookJ) rfl rfl
    assignRest
  case e => exact nrEnd (by norootJ) _
  case h4 => lookJ
  case hv =>
    intro v hv
    rcases v with _ | _ | _ | _ | _ | _ | _ | _ | _ | v <;> first | exact absurd rfl hv | lookJ

/-- `o` pointed at the cell again, on the runs `a` is not set. -/
theorem repoint_typed : ∃ Δ, StmtT P ξ (ctxJ EobJ) [] (.assign 4 (.getr 3)) Δ ∧ Δ 4 = some Eob ∧
    ∀ v, v ≠ 4 → Δ v = ctxJ Eob v := by
  refine' ⟨_, StmtT.assign (Ex := EobJ) (E := Eob) ?g1 ?g2 (Or.inr (Or.inr ⟨rfl, rfl⟩))
    (RhsT.getr (E := Ecl) (a := .int) (b := str) (by lookJ) rfl rfl) ?g5 ?g6 ?g7 ?g8 ?g9 ?g10, ?h4, ?hv⟩
  case g2 => simp
  all_goals try (first | rfl | exact nrPin (by norootJ) _ | exact nrDtor (by norootJ) _ _ _ | (lookJ; done))
  case hv =>
    intro v hv
    rcases v with _ | _ | _ | _ | _ | _ | _ | _ | _ | v <;> first | exact absurd rfl hv | lookJ

/-- The second decision: after it `o` reads the cell, which owns the old
    value on the runs it was handed over. -/
theorem decide2_typed : StmtT P ξ (ctxJ EobJ) [] decide2 (ctxJ Eob) := by
  obtain ⟨Δ, hb, h4, hv⟩ := handOver_typed (ξ := ξ)
  obtain ⟨Δ', hk, h4', hv'⟩ := repoint_typed (ξ := ξ)
  exact StmtT.ite rfl rfl (ExprT.var (E := intE) (by lookJ) rfl rfl)
    (StmtT.sub (Weaker.refl wf_EobJ names_EobJ) hb
      (Or.inr (weakerJ hv h4 (EntryWeaker.refl _) wf_Eob names_Eob)))
    (StmtT.sub (Weaker.refl wf_EobJ names_EobJ) hk
      (Or.inr (weakerJ hv' h4' (EntryWeaker.refl _) wf_Eob names_Eob)))

theorem mainJ_typed (c : Nat) : ∃ Δ, StmtT P .none (fun _ => none) [] (mainJ c) Δ := by
  apply Exists.intro
  refine' StmtT.letv (x := 0) rfl rfl (by simp) (RhsT.expr ExprT.lit) ?_ ?_
  rotate_left
  · refine' StmtT.letv (x := 1) rfl (by look) (by simp) (RhsT.new (t := .int) rfl) ?_ ?_
    rotate_left
    · refine' StmtT.letv (x := 2) rfl (by look) (by simp) (RhsT.new (t := .int) rfl) ?_ ?_
      rotate_left
      · refine' StmtT.letv (x := 3) (E := Ecl) rfl (by look) (by simp)
          (RhsT.inr (Ey := Enew) (by look) rfl
            (PushArg.move (by simp [Enew, str, Ty.owning]) rfl (by simp) (nrPin (by noroot) _)
              (nrDtor (by noroot) _ _ _)) rfl) ?_ ?_
        rotate_left
        · refine' StmtT.letv (x := 4) (E := Eob) rfl (by look) (by simp)
            (RhsT.getr (E := Ecl) (a := .int) (b := str) (by look) rfl rfl) ?_ ?_
          rotate_left
          · refine' StmtT.letv (x := 7) rfl (by look) (by simp) (RhsT.expr ExprT.lit) ?_ ?_
            rotate_left
            · refine' StmtT.letv (x := 8) rfl (by look) (by simp) (RhsT.expr ExprT.lit) ?_ ?_
              rotate_left
              · -- the context is `ctxJ Eob`, as the decisions are typed
                refine' StmtT.sub (weakerJ (E4 := Eob) (E4' := Eob) ?hv ?h4 (EntryWeaker.refl _) wf_Eob names_Eob)
                  (StmtT.seq rfl decide1_typed (StmtT.seq rfl decide2_typed (StmtT.seq rfl ?r1 ?r2))) (Or.inl rfl)
                case hv =>
                  intro v hv
                  rcases v with _ | _ | _ | _ | _ | _ | _ | _ | _ | v <;> first | exact absurd rfl hv | lookJ
                case h4 => lookJ
                case r1 =>
                  apply StmtT.assign (Ex := Enew) (E := Enew)
                  · lookJ
                  · simp
                  · exact Or.inl ⟨rfl, rfl⟩
                  · exact RhsT.new (t := .int) rfl
                  assignRest
                case r2 =>
                  refine' StmtT.letv (x := 6) rfl (by lookJ) (by simp)
                    (RhsT.expr (ExprT.len (E := Eob) (t := .int) (by lookJ) rfl rfl)) StmtT.skip ?_
                  exact nrEnd (by norootJ) _
              · exact nrEnd (by norootJ) _
            · exact nrEnd (by norootJ) _
          · exact nrEnd (by norootJ) _
        · exact nrEnd (by norootJ) _
      · exact nrEnd (by norootJ) _
    · exact nrEnd (by norootJ) _
  · exact nrEnd (by norootJ) _

/-! ### The claim for it -/

theorem prog_ok : ProgOK P := by
  intro fn hfn; simp [P] at hfn

theorem prog_codes : ProgCodes P := by
  intro fn hfn; simp [P] at hfn

/-- A run of the encoded program, from the empty store, never touches
    memory it may not: `o` reads `other`'s value while `other` holds it, and
    the cell's once it was handed over. -/
theorem main_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 7) main (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact memory_safe prog_ok prog_codes ht rfl
    (by simp [main, handOver, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-- ... and when it ends, `o`'s first value, the value handed over and
    `other`'s new one have all been freed: nothing leaks, and nothing is
    freed twice (the old value is freed once, by the cell). -/
theorem main_no_leak {m' : Mem} (hr : Steps P (emptyMem 7) main (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact no_leak_end prog_ok prog_codes ht rfl
    (by simp [main, handOver, Stmt.codesOK, Rhs.codeOK]) (by decide) hr


/-- The variables do not depend on the condition's value. -/
theorem mainJ_vars (c : Nat) : (mainJ c).vars = (mainJ 0).vars := rfl

theorem mainJ_vars_lt (c : Nat) : ∀ v ∈ (mainJ c).vars, v < 9 := by
  rw [mainJ_vars]; decide

/-- The hand-over decided at run time: a run, from the empty store, never
    touches memory it may not, whether or not `o` was given `other`. -/
theorem mainJ_safe (c : Nat) {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 9) (mainJ c) (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := mainJ_typed c
  exact memory_safe prog_ok prog_codes ht rfl
    (by simp [mainJ, decide1, decide2, byName, handOver, Stmt.codesOK, Rhs.codeOK]) (mainJ_vars_lt c) hr

/-- ... and nothing leaks, on either path. -/
theorem mainJ_no_leak (c : Nat) {m' : Mem} (hr : Steps P (emptyMem 9) (mainJ c) (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := mainJ_typed c
  exact no_leak_end prog_ok prog_codes ht rfl
    (by simp [mainJ, decide1, decide2, byName, handOver, Stmt.codesOK, Rhs.codeOK]) (mainJ_vars_lt c) hr

end A2.HandOver
