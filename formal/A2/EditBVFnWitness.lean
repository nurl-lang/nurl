import A2.TakeBVWitness

/-!
  A2 — a store through a borrow of an element that holds views and a
  closure (AGORA-901).

      : String buf …                   -- buf owns a buffer
      : [i sl ( string_data buf )      -- sl views it
      : f \ [sl] …                     -- a closure whose environment is `sl`,
                                       -- capturing nothing by name
      : S e { sl f }                   -- an element: a view beside a closure
      : ( Vec S ) w …
      : ( Vec ( Vec S ) ) vv …         -- vv holds w
      ( vec_push vv w )
      : ( Vec S ) b ( vec_at vv 0 )    -- a borrow
      ( vec_push b e )                 -- stored through the borrow

  `Stmt.edit true` changes a `Vec`'s elements through a borrow.  For an
  element type that holds views it is typed by `StmtT.editBV`, whose
  premise on closures (AGORA-901) is now the disjunction: the element type
  holds no closure, or what the stored value captures by name the borrow and
  every owner it may land in hold already.  Here the element type
  `prod (slice int) (fn [] any)` holds both a view and a closure, so the
  right disjunct is used: the closure captures nothing by name, what is
  stored depends only on `buf`'s buffer (a view), and the premise holds
  vacuously.  `vv`, the owner the push may land in, then holds that view
  too (`holdThru`), as `b` does.

  This module types the program with A2's own rules and applies
  `memory_safe` and `no_leak_end`: the closure's environment and the view
  own nothing, the element moves into `vv`'s tree, and `vv` and `buf`'s
  buffer are released at their scopes' ends.
-/

namespace A2.EditBVFnWitness

open A2.DynCell (NoRootb noRootb_empty)
open A2.PopWitness (nrDtor nrPin nrEnd)

def P : Prog := []

/-- A String's buffer, a view of one, a closure with no methods whose
    environment may hold views, the struct of a view and such a closure, a
    `Vec` of those, and a `Vec` of such `Vec`s. -/
def str : Ty := .vec .int
def sl : Ty := .slice .int
def FT : Ty := .fn [] .any
def S : Ty := .prod sl FT
def vS : Ty := .vec S
def vvS : Ty := .vec vS

/-! ### The program

    `buf` is 0, the view `sl` 1, the closure `f` 2, the element `e` 3, the
    inner `Vec` `w` 4, `vv` 5, the borrow `b` 6. -/

def body : Stmt :=
  .seq (.push 5 4) (.letv 6 (.at 5 (.lit 0)) (.edit true 6 (.push 3)))

def main : Stmt :=
  .letv 0 (.new .int) (.letv 1 (.view 0) (.letv 2 (.pack [] sl [] 1 []) (.letv 3 (.pair 1 2)
    (.letv 4 (.new S) (.letv 5 (.new vS) body)))))

/-! ### Entries -/

/-- What the view depends on: `buf`'s buffer. -/
def D0 : List Dep := [⟨0, .view⟩]

def Es : Entry := ⟨str, .own, true, [], [], false, false, false⟩
def Ev : Entry := ⟨sl, .bor, true, D0, [], false, false, false⟩
def Ef : Entry := ⟨FT, .own, true, [], D0, false, false, false⟩
def Ee : Entry := ⟨S, .own, true, [], D0 ++ D0, false, false, false⟩
def Ew0 : Entry := ⟨vS, .own, true, [], [], false, false, false⟩
def Evv0 : Entry := ⟨vvS, .own, true, [], [], false, false, false⟩
def Eb : Entry := ⟨vS, .bor, true, [⟨5, .inner⟩], [], false, false, false⟩

theorem NoRootb.killHv {Γ : Ctx} (h : NoRootb Γ) : ∀ ks, NoRootb (A2.killHv ks Γ)
  | [] => h
  | (e, b, r) :: ks => A2.DynCell.NoRootb.kill (NoRootb.killHv h ks) e b r

theorem NoRootb.killThruV {Γ : Ctx} (h : NoRootb Γ) (op : Edit) (tx : Ty) (P : List Dep) :
    NoRootb (A2.killThruV op tx P Γ) := NoRootb.killHv h _

/-- Holding more keeps the bindings' modes and flags. -/
theorem NoRootb.holdThru {Γ : Ctx} (h : NoRootb Γ) (D Q : List Dep) :
    NoRootb (A2.holdThru D Q Γ) := by
  intro v E hv
  obtain ⟨E0, h0, rfl⟩ := holdOn_get hv
  have := h v E0 h0
  split <;> simpa [Entry.hold] using this

syntax "norootE" : tactic
macro_rules
  | `(tactic| norootE) => `(tactic| first
      | exact noRootb_empty
      | (apply A2.DynCell.NoRootb.exitScope; norootE)
      | (apply A2.DynCell.NoRootb.kill; norootE)
      | (apply NoRootb.killThruV; norootE)
      | (apply NoRootb.holdThru; norootE)
      | (refine A2.DynCell.NoRootb.setE ?_ (by simp [str, sl, FT, S, vS, vvS, intE, Es, Ev, Ef, Ee,
          Ew0, Evv0, Eb, D0, compE, ownHeld, Ty.holdsView, elemE, derive, Mode.isRoot, rootKind, comp,
          capDeps]); norootE))

syntax "lookE" : tactic
macro_rules
  | `(tactic| lookE) => `(tactic| simp [A2.setE, upd, A2.kill, killE, hits, A2.exitScope, Entry.vdeps,
      Mode.ownSlot, derive, Mode.isRoot, rootKind, comp, str, sl, FT, S, vS, vvS, intE, Es, Ev, Ef, Ee,
      Ew0, Evv0, Eb, D0, Eff.kills, roots, A2.killThruV, A2.killHv, thruKills, argE, memDeps,
      Kind.isName, Kind.bound, Edit.effAt, elemE, compE, ownHeld, Ty.holdsView, Ty.elem, capDeps,
      A2.holdThru, A2.holdOn, Entry.hold,
      List.foldr_cons, List.foldr_nil, List.map_cons, List.map_nil, List.filter_cons, List.filter_nil])

syntax "finE" : tactic
macro_rules
  | `(tactic| finE) => `(tactic| first
      | rfl
      | decide
      | exact Or.inl rfl
      | exact nrPin (by norootE) _
      | exact nrDtor (by norootE) _ _ _
      | (lookE; done)
      | (simp [str, sl, FT, S, vS, vvS, intE, Es, Ev, Ef, Ee, Ew0, Evv0, Eb, D0, roots, memDeps,
          Kind.isName, Edit.stored, ownHeld, derive, Mode.isRoot, comp]; done))

/-! ### Typing -/

/-- The push's effect through `b`, whose path is `vv`'s elements, may drop
    them: `vv` is a live owner, and not what is stored. -/
theorem thru_ok {Γ : Ctx} (hn : NoRootb Γ) (h5 : Γ 5 = some Evv0) :
    ThruOK Γ [] (.push 3) vS [⟨5, .inner⟩] := by
  intro d hd
  simp only [memDeps, Kind.isName, Bool.not_false, List.filter_cons_of_pos, List.filter_nil,
    List.mem_singleton] at hd
  subst hd
  refine ⟨by simp, fun y hy => ?_, _, h5, rfl, Or.inl rfl, nrDtor hn _ _ _, by simp⟩
  simp [Edit.stored] at hy
  subst hy
  decide

/-- ... ends no view a destructor reads, `vv` is no `letd`'s, and what is
    stored depends on `buf`, not on `vv`. -/
theorem thru_v {Γ : Ctx} (hn : NoRootb Γ) (h5 : Γ 5 = some Evv0) :
    ThruV Γ (.push 3) vS [⟨5, .inner⟩] (memDeps (D0 ++ D0)) := by
  intro d hd
  simp only [memDeps, Kind.isName, Bool.not_false, List.filter_cons_of_pos, List.filter_nil,
    List.mem_singleton] at hd
  subst hd
  exact ⟨nrDtor hn _ _ _, by simp [argE, h5, Evv0], by simp [roots, memDeps, D0, Kind.isName]⟩

/-- AGORA-901: the element type holds a closure, but what is stored captures
    nothing by name: the right disjunct of `editBV`'s premise holds. -/
theorem names_held (Ex1 : Entry) (Γ1 : Ctx) :
    ∀ d ∈ D0 ++ D0, d.kind.isName = true →
      d ∈ Ex1.held ∧ ∀ r ∈ roots (memDeps Ex1.path), (argE Γ1 r).ty.holdsView = true →
        d ∈ (argE Γ1 r).held := by
  intro d hd hn
  simp only [D0, List.cons_append, List.nil_append, List.mem_cons, List.not_mem_nil, or_false,
    or_self] at hd
  subst hd
  simp [Kind.isName] at hn

/-- `( vec_push b e )`: the element stored through the borrow `b`. -/
theorem edit_typed {ξ : Exits} {Γ : Ctx} (hn : NoRootb Γ) (hb : Γ 6 = some Eb)
    (h5 : Γ 5 = some Evv0) (h3 : Γ 3 = some Ee) :
    StmtT P ξ Γ [] (.edit true 6 (.push 3))
      (A2.setE (A2.holdThru (memDeps (D0 ++ D0)) [⟨5, .inner⟩]
        (A2.killThruV (.push 3) vS [⟨5, .inner⟩]
          (A2.setE (A2.kill .replace false 3 Γ) 3 { Ee with live := false, dtor := false }))) 6
        { Eb with held := Eb.held ++ memDeps (D0 ++ D0) }) := by
  have hn1 : NoRootb (A2.setE (A2.kill .replace false 3 Γ) 3 { Ee with live := false, dtor := false }) :=
    (A2.DynCell.NoRootb.kill hn _ _ _).setE (by simp [Ee])
  refine StmtT.editBV (Ex := Eb) (Ex1 := Eb) (t := S) (D := D0 ++ D0) hb rfl rfl rfl rfl
    (Or.inr (names_held _ _)) (by simp)
    (EditArg.push (Ey := Ee) h3 rfl rfl
      (PushArg.move (by simp [S, Ty.owning]) rfl (by simp) (nrPin hn _) (nrDtor hn _ _ _)))
    (fun y hy => by simp [Edit.stored] at hy; subst hy; decide) ?_ rfl
    (by simp [Eb, memDeps, Kind.isName]) (thru_ok hn1 ?_) (thru_v hn1 ?_) (fun h => by
      simp [Edit.drops] at h)
  · simp [A2.setE, upd, A2.kill, killE, hits, hb, Eb, Entry.vdeps, Mode.ownSlot, Eff.kills]
  all_goals simp [A2.setE, upd, A2.kill, killE, hits, h5, Evv0, Entry.vdeps, Mode.ownSlot]

theorem main_typed : ∃ Δ, StmtT P .none (fun _ => none) [] main Δ := by
  apply Exists.intro
  -- `: String buf`
  refine' StmtT.letv (x := 0) rfl rfl (by simp) (RhsT.new (t := .int) rfl) ?_ ?_
  rotate_left
  · -- `: [i sl ( string_data buf )`
    refine' StmtT.letv (x := 1) (E := Ev) rfl (by lookE) (by simp)
      (RhsT.view (E := Es) (t := .int) (by lookE) rfl rfl rfl) ?_ ?_
    rotate_left
    · -- the closure, its environment the view `sl`, capturing nothing by name
      refine' StmtT.letv (x := 2) (E := Ef) rfl (by lookE) (by simp)
        (RhsT.pack (q := .any) (Ey := Ev) (by lookE) rfl rfl (PushArg.slice (Or.inl rfl))
          ⟨List.nodup_nil, fun c h => by cases h⟩ (by simp [Cross.Fits, Ev, sl, Ty.holdsDtor])) ?_ ?_
      rotate_left
      · -- `: S e { sl f }`: the view copied, the closure moved in
        refine' StmtT.letv (x := 3) (E := Ee) rfl (by lookE) (by simp)
          (RhsT.pair (Ey := Ev) (Ez := Ef) (by lookE) rfl (PushArg.slice (Or.inl rfl)) (by lookE) rfl
            (PushArg.move (by simp [Ef, FT, Ty.owning]) rfl (by simp) (nrPin (by norootE) _)
              (nrDtor (by norootE) _ _ _))
            (by simp [roots, D0])) ?_ ?_
        rotate_left
        · -- `: ( Vec S ) w`
          refine' StmtT.letv (x := 4) rfl (by lookE) (by simp) (RhsT.new (t := S) rfl) ?_ ?_
          rotate_left
          · -- `: ( Vec ( Vec S ) ) vv`
            refine' StmtT.letv (x := 5) rfl (by lookE) (by simp) (RhsT.new (t := vS) rfl) ?_ ?_
            rotate_left
            · -- `w` into `vv`
              refine' StmtT.seq rfl ?_ ?_
              rotate_left 2
              · apply StmtT.push (Ex := Evv0) (Ey := Ew0) (Ex1 := Evv0) (t := vS)
                · lookE
                · rfl
                · rfl
                · exact Or.inl rfl
                · simp
                · lookE
                · rfl
                · rfl
                · decide
                · exact PushArg.move (by simp [vS, Ty.owning]) rfl (by simp) (nrPin (by norootE) _)
                    (nrDtor (by norootE) _ _ _)
                all_goals finE
              -- `: ( Vec S ) b ( vec_at vv 0 )`
              refine' StmtT.letv (x := 6) (E := Eb) rfl (by lookE) (by simp)
                (RhsT.at (E := Evv0) (t := vS) (by lookE) rfl rfl ExprT.lit) ?_ ?_
              rotate_left
              · -- `( vec_push b e )`: `StmtT.editBV`, its right disjunct
                exact edit_typed (by norootE) (by lookE) (by lookE) (by lookE)
              · exact nrEnd (by norootE) _
            · exact nrEnd (by norootE) _
          · exact nrEnd (by norootE) _
        · exact nrEnd (by norootE) _
      · exact nrEnd (by norootE) _
    · exact nrEnd (by norootE) _
  · exact nrEnd (by norootE) _

theorem prog_ok : ProgOK P := by
  intro fn hfn; simp [P] at hfn

theorem prog_codes : ProgCodes P := by
  intro fn hfn; simp [P] at hfn

/-- A run of the program, from the empty store, never touches memory it may
    not: the element stored through `b` lands in `vv`'s tree, which then
    holds its view of `buf`'s buffer, as `b` does. -/
theorem main_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 7) main (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact memory_safe prog_ok prog_codes ht rfl
    (by simp [main, body, Stmt.codesOK, Rhs.codeOK, CodeOK]) (by decide) hr

/-- ... and when it ends, everything it allocated is freed: `vv`, with the
    stored element and its closure, and `buf`'s buffer with their scopes. -/
theorem main_no_leak {m' : Mem} (hr : Steps P (emptyMem 7) main (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact no_leak_end prog_ok prog_codes ht rfl
    (by simp [main, body, Stmt.codesOK, Rhs.codeOK, CodeOK]) (by decide) hr

end A2.EditBVFnWitness
