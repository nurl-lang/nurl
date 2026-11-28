module

public import A2.Closure

@[expose] public section

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

A real memory root is no region (`call_root_not_region`): `( f vv2 )`, with
`vv2` holding a view of a local `w`, does not meet the regions-only branch.
This witness shows only that. It does not show that `f` changes `w` (its body
uses slots 2 and 3 unbound). The positive `CallT` witness for route U is
`HeldViewThruWitness.call_ok`. -/

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
theorem sig_vv : sigCtx g 0 = some ⟨vsi, .own, true, [], [⟨4, .self⟩], false, false, false, false⟩ := by
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
    CallDtorSafe.of_inp (by simp [f]) mutNames_vv, rfl, rfl, fun _ => Or.inl fun r hr => ?_⟩
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

/-! ### A real memory root does not meet the regions-only branch

(Route U's `CallThruOK` is the other branch, `HeldViewThruWitness.call_ok`.) -/

def Ew : Entry := ⟨.vec .int, .own, true, [], [], false, false, false, false⟩
def Evv2 : Entry := ⟨vsi, .own, true, [], [⟨2, .view⟩], false, false, false, false⟩

/-- `g`'s body with a local `w` (2), a `Vec`, and `vv2` (3) holding a view
    of it, beside the region. -/
def K : Ctx := setE (setE (sigCtx g) 2 Ew) 3 Evv2

theorem callR_root : 2 ∈ callR K [3] := by
  simp [callR, argE, K, setE, upd, Evv2, roots, memDeps, Kind.isName, vsi]

/-- **A view of memory is no region**: `( f vv2 )` does not type by the
    regions-only branch of `CallT`'s `ThruFn` premise, `w` being no region.
    Before route U this was its refusal. Whether route U's `CallThruOK`
    branch types it is not shown here (see `HeldViewThruWitness.call_ok` for
    a call it types). -/
theorem call_root_not_region : ¬ ∀ r ∈ callR K [3], ∃ E, K r = some E ∧ E.mode = .region := fun h => by
  obtain ⟨E', hE', hm⟩ := h 2 callR_root
  simp [K, setE, upd] at hE'
  subst hE'
  simp [Ew] at hm

end A2.RegionThruWitness
