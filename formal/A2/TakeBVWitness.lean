import A2.TakeBWitness

/-!
  A2 — an element that holds views moved out through a borrow (AGORA-897).

      : String s …                     -- s owns a buffer
      : [i v ( string_data s )         -- v views it
      : ( Vec [i ) w …                 -- w holds two copies of v
      : ( Vec ( Vec [i ) ) vv …        -- vv holds w
      : ( Vec [i ) b ( vec_at vv 0 )
      : [i y ( vec_pop b )             -- the last view moves out, kept
      : [i z ( vec_remove b 0 )        -- the first one moves out, kept
      : i ly ( slice_len y )           -- both are read after
      : i lz ( slice_len z )

  `Stmt.takeB` takes an element out through a borrow (`Step.takeB`).  For an
  element type that holds views it is typed by `StmtT.takeBV`.  On every
  owner `b` may reach, the step is typed as `editBV`'s truncation
  (`killThruV`: the views among `vv`'s elements and the borrows of them end
  there).  What moves out holds what `b` holds: views of `s`'s buffer,
  which stay valid (`takeB_viewsOK`).

  This module types the program with A2's own rules and applies
  `memory_safe` and `no_leak_end`: the views own nothing, and `s`'s buffer
  and `vv` are released at their scopes' ends.
-/

namespace A2.TakeBVWitness

open A2.DynCell (NoRootb noRootb_empty)
open A2.PopWitness (nrDtor nrPin nrEnd NoRootb.killThru)

def P : Prog := []

/-- A String's buffer, a view of one, a `Vec` of views, and a `Vec` of those. -/
def str : Ty := .vec .int
def sl : Ty := .slice .int
def vs : Ty := .vec sl
def vvs : Ty := .vec vs

/-! ### The program

    `s` is 0, the view `v` 1, the views' `Vec` `w` 2, `vv` 3, the borrow
    `b` 4, the popped view `y` 5, the removed one `z` 6, and the lengths read
    7 and 8. -/

def body : Stmt :=
  .letv 4 (.at 3 (.lit 0))                                 -- `b`
    (.takeB 4 (.dec (.len 4)) 5                            -- `: [i y ( vec_pop b )`
      (.takeB 4 (.lit 0) 6                                 -- `: [i z ( vec_remove b 0 )`
        (.letv 7 (.expr (.slen 5)) (.letv 8 (.expr (.slen 6)) .skip))))

def main : Stmt :=
  .letv 0 (.new .int) (.letv 1 (.view 0) (.letv 2 (.new sl) (.letv 3 (.new vs)
    (.seq (.push 2 1) (.seq (.push 2 1) (.seq (.push 3 2) body))))))

/-! ### Entries -/

/-- What the views depend on: `s`'s buffer. -/
def D0 : List Dep := [⟨0, .view⟩]

def Es : Entry := ⟨str, .own, true, [], [], false, false⟩
def Ev : Entry := ⟨sl, .bor, true, D0, [], false, false⟩
def Ew0 : Entry := ⟨vs, .own, true, [], [], false, false⟩
def Ew1 : Entry := ⟨vs, .own, true, [], D0, false, false⟩
def Ew2 : Entry := ⟨vs, .own, true, [], D0 ++ D0, false, false⟩
def Evv0 : Entry := ⟨vvs, .own, true, [], [], false, false⟩
def Evv1 : Entry := ⟨vvs, .own, true, [], D0 ++ D0, false, false⟩
def Eb : Entry := ⟨vs, .bor, true, [⟨3, .inner⟩], D0 ++ D0, false, false⟩

theorem NoRootb.killHv {Γ : Ctx} (h : NoRootb Γ) : ∀ ks, NoRootb (A2.killHv ks Γ)
  | [] => h
  | (e, b, r) :: ks => A2.DynCell.NoRootb.kill (NoRootb.killHv h ks) e b r

theorem NoRootb.killThruV {Γ : Ctx} (h : NoRootb Γ) (op : Edit) (tx : Ty) (P : List Dep) :
    NoRootb (A2.killThruV op tx P Γ) := NoRootb.killHv h _

syntax "norootV" : tactic
macro_rules
  | `(tactic| norootV) => `(tactic| first
      | exact noRootb_empty
      | (apply A2.DynCell.NoRootb.exitScope; norootV)
      | (apply A2.DynCell.NoRootb.kill; norootV)
      | (apply NoRootb.killThruV; norootV)
      | (refine A2.DynCell.NoRootb.setE ?_ (by simp [str, sl, vs, vvs, intE, Es, Ev, Ew0, Ew1, Ew2,
          Evv0, Evv1, Eb, D0, compE, ownHeld, Ty.holdsView, elemE, derive, Mode.isRoot, rootKind, comp]);
          norootV))

syntax "lookV" : tactic
macro_rules
  | `(tactic| lookV) => `(tactic| simp [A2.setE, upd, A2.kill, killE, hits, A2.exitScope, Entry.vdeps,
      Mode.ownSlot, derive, Mode.isRoot, rootKind, comp, projE, projDeps, str, sl, vs, vvs, intE, Es, Ev,
      Ew0, Ew1, Ew2, Evv0, Evv1, Eb, D0, Eff.kills, roots, A2.killThruV, A2.killHv, thruKills, argE,
      memDeps, Kind.isName, Kind.bound, Edit.effAt, elemE, compE, ownHeld, Ty.holdsView, Ty.elem,
      List.foldr_cons, List.foldr_nil, List.map_cons, List.map_nil, List.filter_cons, List.filter_nil])

syntax "finV" : tactic
macro_rules
  | `(tactic| finV) => `(tactic| first
      | rfl
      | decide
      | exact Or.inl rfl
      | exact nrPin (by norootV) _
      | exact nrDtor (by norootV) _ _ _
      | (lookV; done)
      | (simp [str, sl, vs, vvs, intE, Es, Ev, Ew0, Ew1, Ew2, Evv0, Evv1, Eb, D0, roots, memDeps,
          Kind.isName, Edit.stored, ownHeld, derive, Mode.isRoot, comp]; done))

/-! ### Typing -/

/-- The truncation's effect through `b`, whose path is `vv`'s elements, may
    drop them: `vv` is a live owner. -/
theorem thru_ok {Γ : Ctx} (hn : NoRootb Γ) {i : Expr} (h3 : Γ 3 = some Evv1) :
    ThruOK Γ [] (.trunc i) vs [⟨3, .inner⟩] := by
  intro d hd
  simp only [memDeps, Kind.isName, Bool.not_false, List.filter_cons_of_pos, List.filter_nil,
    List.mem_singleton] at hd
  subst hd
  refine ⟨by simp, fun y hy => ?_, _, h3, rfl, Or.inl rfl, nrDtor hn _ _ _, by simp⟩
  simp [Edit.stored] at hy

/-- ... ends no view a destructor reads, `vv` is no `letd`'s, and nothing is
    stored. -/
theorem thru_v {Γ : Ctx} (hn : NoRootb Γ) {i : Expr} (h3 : Γ 3 = some Evv1) :
    ThruV Γ (.trunc i) vs [⟨3, .inner⟩] [] := by
  intro d hd
  simp only [memDeps, Kind.isName, Bool.not_false, List.filter_cons_of_pos, List.filter_nil,
    List.mem_singleton] at hd
  subst hd
  exact ⟨nrDtor hn _ _ _, by simp [argE, h3, Evv1], by simp [roots]⟩

/-- `: [i y ( vec_remove b i )` through the borrow `b`. -/
theorem take_typed {ξ : Exits} {Γ Δ : Ctx} (hn : NoRootb Γ) {y : Var} {i : Expr} {s : Stmt}
    (hb : Γ 4 = some Eb) (h3 : Γ 3 = some Evv1) (hy : Γ y = none) (hie : ExprT Γ i)
    (hsrc : s.src = true)
    (hs : StmtT P (ξ.under y) (A2.setE (A2.setE (A2.killThruV (.trunc i) vs [⟨3, .inner⟩] Γ) 4 Eb) y
      (compE Eb sl)) [] s Δ) (hend : EndOK Δ y) :
    StmtT P ξ Γ [] (.takeB 4 i y s) (A2.exitScope y Δ) :=
  StmtT.takeBV hsrc hy (by simp) hb rfl rfl rfl rfl rfl (by simp) hie (by simp [Eb, memDeps, Kind.isName])
    (thru_ok hn h3) (thru_v hn h3) rfl hs hend

theorem main_typed : ∃ Δ, StmtT P .none (fun _ => none) [] main Δ := by
  apply Exists.intro
  -- `: String s`
  refine' StmtT.letv (x := 0) rfl rfl (by simp) (RhsT.new (t := .int) rfl) ?_ ?_
  rotate_left
  · -- `: [i v ( string_data s )`
    refine' StmtT.letv (x := 1) (E := Ev) rfl (by lookV) (by simp)
      (RhsT.view (E := Es) (t := .int) (by lookV) rfl rfl rfl) ?_ ?_
    rotate_left
    · -- `: ( Vec [i ) w`
      refine' StmtT.letv (x := 2) rfl (by lookV) (by simp) (RhsT.new (t := sl) rfl) ?_ ?_
      rotate_left
      · -- `: ( Vec ( Vec [i ) ) vv`
        refine' StmtT.letv (x := 3) rfl (by lookV) (by simp) (RhsT.new (t := vs) rfl) ?_ ?_
        rotate_left
        · -- the view into `w`, twice
          refine' StmtT.seq rfl ?_ ?_
          rotate_left 2
          · apply StmtT.push (Ex := Ew0) (Ey := Ev) (Ex1 := Ew0) (t := sl)
            · lookV
            · rfl
            · rfl
            · exact Or.inl rfl
            · simp
            · lookV
            · rfl
            · rfl
            · decide
            · exact PushArg.slice (Or.inl rfl)
            all_goals finV
          refine' StmtT.seq rfl ?_ ?_
          rotate_left 2
          · apply StmtT.push (Ex := Ew1) (Ey := Ev) (Ex1 := Ew1) (t := sl)
            · lookV
            · rfl
            · rfl
            · exact Or.inl rfl
            · simp
            · lookV
            · rfl
            · rfl
            · decide
            · exact PushArg.slice (Or.inl rfl)
            all_goals finV
          -- `w` into `vv`
          refine' StmtT.seq rfl ?_ ?_
          rotate_left 2
          · apply StmtT.push (Ex := Evv0) (Ey := Ew2) (Ex1 := Evv0) (t := vs)
            · lookV
            · rfl
            · rfl
            · exact Or.inl rfl
            · simp
            · lookV
            · rfl
            · rfl
            · decide
            · exact PushArg.move (by simp [vs, Ty.owning]) rfl (by simp) (nrPin (by norootV) _)
                (nrDtor (by norootV) _ _ _)
            all_goals finV
          -- `: ( Vec [i ) b ( vec_at vv 0 )`
          refine' StmtT.letv (x := 4) (E := Eb) rfl (by lookV) (by simp)
            (RhsT.at (E := Evv1) (t := vs) (by lookV) rfl rfl ExprT.lit) ?_ ?_
          rotate_left
          · -- `: [i y ( vec_pop b )`: the last view moves out through `b`
            refine' take_typed (y := 5) ?_ ?_ ?_ ?_
              (ExprT.dec (ExprT.len (E := Eb) (t := sl) ?_ rfl rfl)) rfl ?_ ?_
            rotate_left
            · norootV
            · lookV
            · lookV
            · lookV
            · lookV
            · -- `: [i z ( vec_remove b 0 )`: the first one moves out
              refine' take_typed (y := 6) ?_ ?_ ?_ ?_ ExprT.lit rfl ?_ ?_
              rotate_left
              · norootV
              · lookV
              · lookV
              · lookV
              · -- both read after, through their views of `s`
                refine' StmtT.letv (x := 7) (E := intE) rfl (by lookV) (by simp)
                  (RhsT.expr (ExprT.slen (E := compE Eb sl) (t := .int) (by lookV) rfl rfl)) ?_ ?_
                rotate_left
                · refine' StmtT.letv (x := 8) (E := intE) rfl (by lookV) (by simp)
                    (RhsT.expr (ExprT.slen (E := compE Eb sl) (t := .int) (by lookV) rfl rfl)) ?_ ?_
                  rotate_left
                  · exact StmtT.skip
                  · exact nrEnd (by norootV) _
                · exact nrEnd (by norootV) _
              · exact nrEnd (by norootV) _
            · exact nrEnd (by norootV) _
          · exact nrEnd (by norootV) _
        · exact nrEnd (by norootV) _
      · exact nrEnd (by norootV) _
    · exact nrEnd (by norootV) _
  · exact nrEnd (by norootV) _

theorem prog_ok : ProgOK P := by
  intro fn hfn; simp [P] at hfn

theorem prog_codes : ProgCodes P := by
  intro fn hfn; simp [P] at hfn

/-- A run of the program, from the empty store, never touches memory it may
    not: each view moved out is its new binding's, valid through `s`, and
    `b` sees `vv`'s element shortened. -/
theorem main_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 9) main (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact memory_safe prog_ok prog_codes ht rfl
    (by simp [main, body, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-- ... and when it ends, everything it allocated is freed: `s`'s buffer
    and `vv` with their scopes (the views own nothing). -/
theorem main_no_leak {m' : Mem} (hr : Steps P (emptyMem 9) main (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact no_leak_end prog_ok prog_codes ht rfl
    (by simp [main, body, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

end A2.TakeBVWitness
