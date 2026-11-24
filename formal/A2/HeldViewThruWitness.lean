import A2.Closure
import A2.ThruPre

/-! AGORA-933 in A2: a callee that changes a `Vec` it reaches through a slice
its parameter holds, `( vec_reserve ( slice_at ( vec_at vv 0 ) 0 ) 4096 )`
with `vv : Vec (Slice (Vec i))`. The borrow it changes through is not fresh
(an element of a slice never is, `RhsT.sat`), so the change is an
`edit true` and the function is through-changing (`ThruFn`). Its path is
rooted at `vv`, a binding of the callee's own, so the callee's `ThruOK`
passes, yet the change lands in memory `vv`'s slices view: the caller's `w`.

nurlc accepted the call with `s2`, a view of `w`'s element, beside `vv`, and the
call with the caller reading `s2` after it. Both read freed memory (AGORA-933,
fixed in github#2100). A2 refuses `( f vv s2 )` (`call_refused`): `s2`
reaches `w` inside its elements, which route U's `CallThruOK` does not
allow. A2 also refuses `( f1 vv )` while `s2` is live (`call_alone_refused`):
the callee's change inside `w`'s elements would end `s2`.

nurlc's fix accepts the one-argument call and ends the caller's views of `w`
at the call. In A2, `s2` must be dead before the call: with `s2` ended,
`( f1 vv )` types by route U (AGORA-937 B4, `call_ok` in `K2`). `thruPre`
below shows that weakening, which ends `s2` and keeps `vv` and `w`. The
accepted call does not end `s2` itself: it leaves the context as it found it
(`post_K2`). -/

namespace A2.HeldViewThruWitness

def vvi : Ty := .vec .int
def svv : Ty := .slice vvi
def vsv : Ty := .vec svv

/-- The callee's body: a change of elements through a borrow that is not
    fresh, `edit true` (what `( vec_reserve ( slice_at ( vec_at vv 0 ) 0 ) … )`
    becomes). Only its being through-changing matters to the call. -/
def fBody : Stmt := .edit true 2 (.push 3)

/-- `f vv s2`: the AGORA-933 callee, with a view argument beside `vv`. -/
def f : Fn where
  params   := [(.inp, vsv), (.inp, .slice .int)]
  resTy    := .int
  resOwn   := false
  lends    := []
  rholds   := []
  outHolds := []
  body     := fBody
  nvars    := 4

/-- `f1 vv`: the same callee with `vv` alone. -/
def f1 : Fn where
  params   := [(.inp, vsv)]
  resTy    := .int
  resOwn   := false
  lends    := []
  rholds   := []
  outHolds := []
  body     := fBody
  nvars    := 3

def P : Prog := [f, f1]

theorem f_thru : ThruFn P 0 := ThruFn.here rfl rfl
theorem f1_thru : ThruFn P 1 := ThruFn.here rfl rfl

/-- The caller: `w` (0) owns a `Vec (Vec i)`; `vv` (1) owns a `Vec` of slices
    holding a view of `w`; `s2` (2) is a view of `w`'s element. -/
def Ew : Entry := ⟨.vec vvi, .own, true, [], [], false, false, false, false⟩
def Evv : Entry := ⟨vsv, .own, true, [], [⟨0, .view⟩], false, false, false, false⟩
def Es2 : Entry := ⟨.slice .int, .bor, true, [⟨0, .inner⟩], [], false, false, false, false⟩

def K : Ctx := fun v =>
  if v = 0 then some Ew else if v = 1 then some Evv else if v = 2 then some Es2 else none

/-- No binding of the caller is a region. -/
theorem K_noRegion : ∀ v E, K v = some E → E.mode ≠ .region := by
  intro v E h
  unfold K at h
  repeat' split at h
  all_goals (cases h <;> simp [Ew, Evv, Es2])

/-- `vv` holds a view of `w`: the memory a change through it may land in. -/
theorem callR_vv : 0 ∈ callR K [1] := by
  simp [callR, argE, K, Evv, roots, memDeps, Kind.isName, vsv, svv, vvi]

theorem callR_vv_s2 : 0 ∈ callR K [1, 2] := by
  simp [callR, argE, K, Evv, Es2, roots, memDeps, Kind.isName, vsv, svv, vvi]

/-- `s2` reaches `w` inside its elements, at `.inner`. -/
theorem s2_inner : (⟨0, .inner⟩ : Dep) ∈ (argE K 2).vdeps := by
  simp [argE, K, Es2, Entry.vdeps, Mode.ownSlot]

/-- **AGORA-933's call is refused**: `( f vv s2 )`, `s2` viewing what `vv`'s
    slice views, has no typing. `w` is no region, and route U
    (`CallThruOK`) asks every argument to reach `w` at a view, its handle or
    by name, which `s2`, a view inside `w`'s elements, does not. -/
theorem call_refused (E : Entry) (Γ' : Ctx) : ¬ CallT P K [] 0 [1, 2] E Γ' := fun h => by
  rcases CallT.thru h K_noRegion rfl f_thru with hm | hc
  · have := callR_vv_s2; rw [hm] at this; cases this
  · have := (hc.2.2.2.2.2 0 callR_vv_s2).2.1 2 (by simp) _ s2_inner rfl
    simp [Kind.isName] at this

/-- `s2` is live after `( f1 vv )` and ends where `w`'s elements change. -/
theorem s2_hit : callPost K f1 [1] 2 = some Es2 ∧ Es2.live = true ∧ hits .dropIn false 0 Es2 = true := by
  refine ⟨?_, rfl, ?_⟩
  · simp [callPost, callPostAux, f1, killNames, mutNames, argNames, nameDeps, argE, K, Evv,
      Entry.vdeps, Mode.ownSlot, Kind.isName]
  · decide

/-- ... and so is `( f1 vv )` alone while `s2` is live: the callee's change
    inside `w`'s elements ends `s2` (AGORA-937, route U). Typing it, as
    nurlc does, takes `s2` ended first (weakening), as the call's typing
    with `s2` dead shows below. -/
theorem call_alone_refused (E : Entry) (Γ' : Ctx) : ¬ CallT P K [] 1 [1] E Γ' := fun h => by
  rcases CallT.thru h K_noRegion rfl f1_thru with hm | hc
  · have := callR_vv; rw [hm] at this; cases this
  · obtain ⟨-, hl, hh⟩ := s2_hit
    have := (hc.2.2.2.2.2 0 callR_vv).2.2.2.2.1 2 Es2 (by simp [K]) hl
    rw [hh] at this; cases this

/-! ### AGORA-937 stage 3a: the call's entry kill

Typing `( f1 vv )` (stage 3d) ends, before the body runs, the frame's
bindings that reach `w` (`thruPre`, `A2/THRU_STAGE3_DESIGN.md`). Here: `s2`, a
view of `w`'s element, is ended, while `vv`, the argument, and `w`, the owner,
are kept. -/

/-! `thruPre` is a step of its own, taken before the call, and not an effect
of `CallT`: `call_alone_refused` refuses the call in `K`, and the call
accepted in `K2`, `call_ok`, leaves `K2` as it is, `post_K2`. -/

theorem pre_s2_dead : ∃ E', thruPre K [1] 2 = some E' ∧ E'.live = false :=
  thruPre_dead (r := 0) rfl (by decide) callR_vv rfl

theorem pre_vv_kept : thruPre K [1] 1 = some Evv := thruPre_arg (by simp)

theorem pre_w_kept : thruPre K [1] 0 = some Ew := thruPre_named rfl rfl rfl

/-! ### AGORA-937 B4: the through-call types (route U)

With `s2` ended, `( f1 vv )` types: it passes a view of `w`, a real memory
root, which the callee changes only inside its elements (`CallThruOK`). -/

def Es2d : Entry := { Es2 with live := false }

def K2 : Ctx := fun v =>
  if v = 0 then some Ew else if v = 1 then some Evv else if v = 2 then some Es2d else none

theorem callR_K2 : callR K2 [1] = [0] := by
  simp [callR, argE, K2, Evv, roots, memDeps, Kind.isName, vsv, svv, vvi]

theorem post_K2 : callPost K2 f1 [1] = K2 := by
  funext v
  simp [callPost, callPostAux, f1, killNames, mutNames, argNames, nameDeps, argE, K2, Evv,
    Entry.vdeps, Mode.ownSlot, Kind.isName]

theorem thru_ok : CallThruOK P K2 [] f1 [1] := by
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_⟩
  · intro g hg; simp [f1, fBody, Stmt.calls] at hg
  · intro a ha ms q; simp at ha; subst ha; simp [argE, K2, Evv, vsv, Ty.undtor]
  · intro i hi hhv
    simp [f1] at hi; subst hi; simp [f1, vsv, svv, vvi, Ty.holdsView] at hhv
  · intro i hi _ _ e he
    simp [f1] at hi; subst hi
    simp [argE, K2, Evv, memDeps, Kind.isName] at he; subst he
    refine ⟨Or.inl rfl, fun j hj hji => ?_⟩
    simp [f1] at hj; omega
  · intro i b t h; simp [f1] at h
    rcases i with _ | i <;> simp at h
  · intro w hw
    rw [callR_K2] at hw; simp at hw; subst hw
    refine ⟨by simp, ?_, ?_, ?_, ?_, ?_, by simp, ?_⟩
    · intro a ha d hd hr; simp at ha; subst ha
      simp [argE, K2, Evv, Entry.vdeps, Mode.ownSlot] at hd; subst hd; exact Or.inl rfl
    · intro a ha d hd; simp at ha; subst ha; simp [argE, K2, Evv] at hd
    · intro i hi _ _; simp [f1] at hi; subst hi; exact ⟨svv, rfl⟩
    · intro y E hy hl
      unfold K2 at hy; repeat' split at hy
      all_goals first | (cases hy; simp [Es2d, Es2] at hl) | (cases hy; decide) | cases hy
    · intro y E hy hd _
      unfold K2 at hy; repeat' split at hy
      all_goals first | (cases hy; simp [Ew, Evv, Es2d, Es2] at hd) | cases hy
    · exact ⟨Ew, vvi, by rw [post_K2]; rfl, rfl, rfl, rfl, rfl⟩


theorem mutNames_K2 : mutNames K2 [1] = [] := by
  simp [mutNames, argNames, nameDeps, argE, K2, Evv, Entry.vdeps, Mode.ownSlot, Kind.isName]

/-- **`( f1 vv )` types with `s2` ended** (AGORA-937 B4, route U): a call that
    passes a view of a real memory root to a callee that changes it only
    inside its elements. -/
theorem call_ok : CallT P K2 [] 1 [1] (callRes K2 f1 [1]) (callPost K2 f1 [1]) := by
  refine ⟨f1, rfl, rfl, fun i hi => ?_, ?_, ?_, rfl, rfl, fun _ => Or.inr thru_ok⟩
  · simp [f1] at hi; subst hi
    refine ⟨Evv, rfl, rfl, rfl, fun h => by simp [f1, PMode.moves] at h, fun h => by simp [f1] at h⟩
  · intro d hd; rw [mutNames_K2] at hd; cases hd
  · refine ⟨fun i hi => ?_, fun d hd => (by rw [mutNames_K2] at hd; cases hd), fun i hi b hb => ?_⟩
    · simp [f1] at hi; subst hi; exact ⟨fun h => by simp [f1] at h, fun b h => by simp [f1] at h⟩
    · simp [f1] at hi; subst hi; simp [f1] at hb

end A2.HeldViewThruWitness
