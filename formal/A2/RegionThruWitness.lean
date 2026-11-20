import A2.Closure

/-! AGORA-937 (turn-on 2) in A2: a through-changing call that passes a
view-holding parameter's own region.

`g sink (Vec [s) vv` hands `vv` to `f`, which changes elements through a
borrow (`ThruFn`). In `g`'s own typing `vv` holds views of its region
`π vv` (`sigCtx`), the caller's memory, and of nothing else. `CallT`'s
`ThruFn` premise asks only that what the arguments hold views of is a
region (`call_region_ok`), so the call types, though the arguments hold
views (`callR_region`: the premise before regions refused it). That is
sound: `g`'s own call was made where no binding is a region, so by the same
premise it was handed no views, and `π vv` stands for nothing in that
frame (`CallH.σ_nil_of_thru`); the lift of the inner call passes none
(`RSetup.callR_canon`).

A real memory root is still refused: in `g`'s body a binding `vv2` holding a
view of a local `w` is not handed to `f` (`call_root_refused`), as before
(`HeldViewThruWitness`). -/

namespace A2.RegionThruWitness

def vsi : Ty := .vec (.slice .int)

/-- `f vv`: changes elements through a borrow (what `( vec_reserve … )`
    through a non-fresh borrow becomes). -/
def f : Fn where
  params   := [(.inp, vsi)]
  resTy    := .int
  resOwn   := false
  lends    := []
  rholds   := []
  outHolds := []
  body     := .edit true 2 (.push 3)
  nvars    := 4

/-- `g sink (Vec [s) vv`: its parameter `vv` (0) is regioned; its region
    is `π 0 = 4`. Only its signature matters to the call. -/
def g : Fn where
  params   := [(.sink, vsi)]
  resTy    := .int
  resOwn   := false
  lends    := []
  rholds   := []
  outHolds := []
  body     := .letcall 2 0 [0] .skip
  nvars    := 4

def P : Prog := [f, g]

theorem f_thru : ThruFn P 0 := ThruFn.here rfl rfl

/-- The callee `g`'s view of `vv`: it holds views of its region. -/
theorem sig_vv : sigCtx g 0 = some ⟨vsi, .own, true, [], [⟨4, .view⟩], false, false, false, false⟩ := by
  simp [sigCtx, regionP, regioned, paramE, g, vsi, Ty.holdsView, Ty.hasFn]

theorem sig_region : sigCtx g 4 = some regionE := by
  simp [sigCtx, isRegionIdx, regioned, g, vsi, Ty.holdsView]

/-- `vv` holds views of the region: the old premise (`callR = []`) refused
    the call. -/
theorem callR_region : callR (sigCtx g) [0] = [4] := by
  simp [callR, argE, sig_vv, roots, memDeps, Kind.isName, vsi]

theorem mutNames_vv : mutNames (sigCtx g) [0] = [] := by
  simp [mutNames, argNames, argE, sig_vv, nameDeps, Entry.vdeps, Mode.ownSlot, Kind.isName, vsi]

/-- **The through-changing call of a regioned parameter types**: `( f vv )`
    in `g`'s body, `vv` holding views of its own region only. -/
theorem call_region_ok :
    CallT P (sigCtx g) [] 0 [0] (callRes (sigCtx g) f [0]) (callPost (sigCtx g) f [0]) := by
  refine ⟨f, rfl, rfl, fun i hi => ?_, fun d hd => ?_,
    CallDtorSafe.of_inp (by simp [f]) mutNames_vv, rfl, rfl, fun _ r hr => ?_⟩
  · have hi' : i = 0 := by simpa [f] using hi
    subst hi'
    refine ⟨_, sig_vv, rfl, rfl, fun h => ?_, fun h => ?_⟩
    · simp [f, PMode.moves] at h
    · simp [f] at h
  · rw [mutNames_vv] at hd; cases hd
  · rw [callR_region] at hr
    simp only [List.mem_singleton] at hr
    subst hr
    exact ⟨_, sig_region, rfl⟩

/-! ### A real memory root is still refused -/

def Ew : Entry := ⟨.vec .int, .own, true, [], [], false, false, false, false⟩
def Evv2 : Entry := ⟨vsi, .own, true, [], [⟨2, .view⟩], false, false, false, false⟩

/-- `g`'s body with a local `w` (2), a `Vec`, and `vv2` (3) holding a view
    of it, beside the region. -/
def K : Ctx := setE (setE (sigCtx g) 2 Ew) 3 Evv2

theorem callR_root : 2 ∈ callR K [3] := by
  simp [callR, argE, K, setE, upd, Evv2, roots, memDeps, Kind.isName, vsi]

/-- **A view of memory is not handed to through-changing code**: `( f vv2 )`
    has no typing, `w` being no region. -/
theorem call_root_refused (E : Entry) (Γ' : Ctx) : ¬ CallT P K [] 0 [3] E Γ' := fun h => by
  obtain ⟨_, _, _, _, _, _, _, _, hthr⟩ := h
  obtain ⟨E', hE', hm⟩ := hthr f_thru 2 callR_root
  simp [K, setE, upd] at hE'
  subst hE'
  simp [Ew] at hm

end A2.RegionThruWitness
