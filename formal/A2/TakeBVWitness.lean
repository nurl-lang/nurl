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
  StmtT.takeBV hsrc hy (by simp) hb rfl rfl rfl rfl (by simp) hie (by simp [Eb, memDeps, Kind.isName])
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

/-! ### A closure that holds a view, moved out (AGORA-898)

        : String s …
        : [i v ( string_data s )
        : f \ [v] …                      -- a closure whose environment is `v`
        : ( Vec f ) w …                  -- w holds it
        : ( Vec ( Vec f ) ) vv …         -- vv holds w
        : ( Vec f ) b ( vec_at vv 0 )
        : f y ( vec_pop b )              -- the closure moves out, kept
        : i n ( vec_len b )

    An element type that holds views and a closure: what the closure
    captures, `y` holds as `b` does (`HrefAt`'s `NamesIn`), and its view of
    `s`'s buffer stays valid (`takeB_viewsOK`).  `s` is 0, `v` 1, the
    closure 2, `w` 3, `vv` 4, `b` 5, `y` 6, the length 7. -/

/-- A closure with no methods whose environment may hold views. -/
def FT : Ty := .fn [] .any
def vF : Ty := .vec FT
def vvF : Ty := .vec vF

def body2 : Stmt :=
  .letv 5 (.at 4 (.lit 0))
    (.takeB 5 (.dec (.len 5)) 6 (.letv 7 (.expr (.len 5)) .skip))

def main2 : Stmt :=
  .letv 0 (.new .int) (.letv 1 (.view 0) (.letv 2 (.pack [] sl [] 1 []) (.letv 3 (.new FT)
    (.letv 4 (.new vF) (.seq (.push 3 2) (.seq (.push 4 3) body2))))))

def Ef : Entry := ⟨FT, .own, true, [], D0, false, false⟩
def EwF0 : Entry := ⟨vF, .own, true, [], [], false, false⟩
def EwF1 : Entry := ⟨vF, .own, true, [], D0, false, false⟩
def EvvF0 : Entry := ⟨vvF, .own, true, [], [], false, false⟩
def EvvF1 : Entry := ⟨vvF, .own, true, [], D0, false, false⟩
def EbF : Entry := ⟨vF, .bor, true, [⟨4, .inner⟩], D0, false, false⟩

syntax "lookF" : tactic
macro_rules
  | `(tactic| lookF) => `(tactic| simp [A2.setE, upd, A2.kill, killE, hits, A2.exitScope, Entry.vdeps,
      Mode.ownSlot, derive, Mode.isRoot, rootKind, comp, str, sl, FT, vF, vvF, intE, Es, Ev, Ef, EwF0,
      EwF1, EvvF0, EvvF1, EbF, D0, Eff.kills, roots, A2.killThruV, A2.killHv, thruKills, argE, memDeps,
      Kind.isName, Kind.bound, Edit.effAt, elemE, compE, ownHeld, Ty.holdsView, Ty.elem, capDeps,
      List.foldr_cons, List.foldr_nil, List.map_cons, List.map_nil, List.filter_cons, List.filter_nil])

syntax "norootF" : tactic
macro_rules
  | `(tactic| norootF) => `(tactic| first
      | exact noRootb_empty
      | (apply A2.DynCell.NoRootb.exitScope; norootF)
      | (apply A2.DynCell.NoRootb.kill; norootF)
      | (apply NoRootb.killThruV; norootF)
      | (refine A2.DynCell.NoRootb.setE ?_ (by simp [str, sl, FT, vF, vvF, intE, Es, Ev, Ef, EwF0, EwF1,
          EvvF0, EvvF1, EbF, D0, compE, ownHeld, Ty.holdsView, elemE, derive, Mode.isRoot, rootKind, comp,
          capDeps]); norootF))

syntax "finF" : tactic
macro_rules
  | `(tactic| finF) => `(tactic| first
      | rfl
      | decide
      | exact Or.inl rfl
      | exact nrPin (by norootF) _
      | exact nrDtor (by norootF) _ _ _
      | (lookF; done)
      | (simp [str, sl, FT, vF, vvF, intE, Es, Ev, Ef, EwF0, EwF1, EvvF0, EvvF1, EbF, D0, roots, memDeps,
          Kind.isName, Edit.stored, ownHeld, derive, Mode.isRoot, comp]; done))

theorem thru_okF {Γ : Ctx} (hn : NoRootb Γ) {i : Expr} (h4 : Γ 4 = some EvvF1) :
    ThruOK Γ [] (.trunc i) vF [⟨4, .inner⟩] := by
  intro d hd
  simp only [memDeps, Kind.isName, Bool.not_false, List.filter_cons_of_pos, List.filter_nil,
    List.mem_singleton] at hd
  subst hd
  refine ⟨by simp, fun y hy => ?_, _, h4, rfl, Or.inl rfl, nrDtor hn _ _ _, by simp⟩
  simp [Edit.stored] at hy

theorem thru_vF {Γ : Ctx} (hn : NoRootb Γ) {i : Expr} (h4 : Γ 4 = some EvvF1) :
    ThruV Γ (.trunc i) vF [⟨4, .inner⟩] [] := by
  intro d hd
  simp only [memDeps, Kind.isName, Bool.not_false, List.filter_cons_of_pos, List.filter_nil,
    List.mem_singleton] at hd
  subst hd
  exact ⟨nrDtor hn _ _ _, by simp [argE, h4, EvvF1], by simp [roots]⟩

theorem main2_typed : ∃ Δ, StmtT P .none (fun _ => none) [] main2 Δ := by
  apply Exists.intro
  refine' StmtT.letv (x := 0) rfl rfl (by simp) (RhsT.new (t := .int) rfl) ?_ ?_
  rotate_left
  · refine' StmtT.letv (x := 1) (E := Ev) rfl (by lookF) (by simp)
      (RhsT.view (E := Es) (t := .int) (by lookF) rfl rfl rfl) ?_ ?_
    rotate_left
    · -- the closure, its environment the view `v`
      refine' StmtT.letv (x := 2) (E := Ef) rfl (by lookF) (by simp)
        (RhsT.pack (q := .any) (Ey := Ev) (by lookF) rfl rfl (PushArg.slice (Or.inl rfl))
          ⟨List.nodup_nil, fun c h => by cases h⟩ (by simp [Cross.Fits, Ev, sl, Ty.holdsDtor])) ?_ ?_
      rotate_left
      · refine' StmtT.letv (x := 3) rfl (by lookF) (by simp) (RhsT.new (t := FT) rfl) ?_ ?_
        rotate_left
        · refine' StmtT.letv (x := 4) rfl (by lookF) (by simp) (RhsT.new (t := vF) rfl) ?_ ?_
          rotate_left
          · -- the closure into `w`
            refine' StmtT.seq rfl ?_ ?_
            rotate_left 2
            · apply StmtT.push (Ex := EwF0) (Ey := Ef) (Ex1 := EwF0) (t := FT)
              · lookF
              · rfl
              · rfl
              · exact Or.inl rfl
              · simp
              · lookF
              · rfl
              · rfl
              · decide
              · exact PushArg.move (by simp [FT, Ty.owning]) rfl (by simp) (nrPin (by norootF) _)
                  (nrDtor (by norootF) _ _ _)
              all_goals finF
            -- `w` into `vv`
            refine' StmtT.seq rfl ?_ ?_
            rotate_left 2
            · apply StmtT.push (Ex := EvvF0) (Ey := EwF1) (Ex1 := EvvF0) (t := vF)
              · lookF
              · rfl
              · rfl
              · exact Or.inl rfl
              · simp
              · lookF
              · rfl
              · rfl
              · decide
              · exact PushArg.move (by simp [vF, Ty.owning]) rfl (by simp) (nrPin (by norootF) _)
                  (nrDtor (by norootF) _ _ _)
              all_goals finF
            refine' StmtT.letv (x := 5) (E := EbF) rfl (by lookF) (by simp)
              (RhsT.at (E := EvvF1) (t := vF) (by lookF) rfl rfl ExprT.lit) ?_ ?_
            rotate_left
            · -- `: f y ( vec_pop b )`: the closure moves out through `b`
              refine' StmtT.takeBV (x := 5) (y := 6) (Ex := EbF) (t := FT) rfl (by lookF) (by simp)
                (by lookF) rfl rfl rfl rfl (by simp)
                (ExprT.dec (ExprT.len (E := EbF) (t := FT) (by lookF) rfl rfl))
                (by simp [EbF, memDeps, Kind.isName]) (thru_okF (by norootF) (by lookF))
                (thru_vF (by norootF) (by lookF)) rfl ?_ ?_
              rotate_left
              · refine' StmtT.letv (x := 7) (E := intE) rfl (by lookF) (by simp)
                  (RhsT.expr (ExprT.len (E := EbF) (t := FT) (by lookF) rfl rfl)) ?_ ?_
                rotate_left
                · exact StmtT.skip
                · exact nrEnd (by norootF) _
              · exact nrEnd (by norootF) _
            · exact nrEnd (by norootF) _
          · exact nrEnd (by norootF) _
        · exact nrEnd (by norootF) _
      · exact nrEnd (by norootF) _
    · exact nrEnd (by norootF) _
  · exact nrEnd (by norootF) _

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

/-- A run of the second program never touches memory it may not: the
    closure moved out keeps its view of `s` valid ... -/
theorem main2_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 8) main2 (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main2_typed
  exact memory_safe prog_ok prog_codes ht rfl
    (by simp [main2, body2, Stmt.codesOK, Rhs.codeOK, CodeOK]) (by decide) hr

/-- ... and leak-free: the closure is released with `y`, the rest with `vv`
    and `s`. -/
theorem main2_no_leak {m' : Mem} (hr : Steps P (emptyMem 8) main2 (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main2_typed
  exact no_leak_end prog_ok prog_codes ht rfl
    (by simp [main2, body2, Stmt.codesOK, Rhs.codeOK, CodeOK]) (by decide) hr

end A2.TakeBVWitness
