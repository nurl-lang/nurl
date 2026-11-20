import A2.Closure

/-! AGORA-933 in A2: a callee that changes a `Vec` it reaches through a slice
its parameter holds, `( vec_reserve ( slice_at ( vec_at vv 0 ) 0 ) 4096 )`
with `vv : Vec (Slice (Vec i))`. The borrow it changes through is not fresh
(an element of a slice never is, `RhsT.sat`), so the change is an
`edit true` and the function is through-changing (`ThruFn`). Its path is
rooted at `vv`, a binding of the callee's own, so the callee's `ThruOK`
passes, yet the change lands in memory `vv`'s slices view: the caller's `w`.

nurlc accepted the call with `s2`, a view of `w`'s element, beside `vv`, and the
call with the caller reading `s2` after it. Both read freed memory (AGORA-933,
fixed in github#2100). A2 refuses both: `CallT`'s `ThruFn` premise allows no
argument that holds views of anything but a region (AGORA-937), and the
caller's `w` is none (`call_refused`, `call_alone_refused`). The second refusal is stricter than nurlc's fix,
which accepts `( f vv )` and ends the caller's views of `w` after it. Lifting it
to the same shape is AGORA-932. -/

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

/-- **AGORA-933's call is refused**: `( f vv s2 )`, `s2` viewing what `vv`'s
    slice views, has no typing. -/
theorem call_refused (E : Entry) (Γ' : Ctx) : ¬ CallT P K [] 0 [1, 2] E Γ' := fun h => by
  have hm := callR_vv_s2
  rw [CallT.thru h K_noRegion f_thru] at hm
  cases hm

/-- ... and so is `( f1 vv )` alone (AGORA-932 is to type it, ending the
    caller's views of `w` at the call, as nurlc does). -/
theorem call_alone_refused (E : Entry) (Γ' : Ctx) : ¬ CallT P K [] 1 [1] E Γ' := fun h => by
  have hm := callR_vv
  rw [CallT.thru h K_noRegion f1_thru] at hm
  cases hm

end A2.HeldViewThruWitness
