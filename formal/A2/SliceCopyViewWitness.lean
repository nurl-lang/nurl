import A2.Closure

/-! AGORA-935 in A2: a copy of a slice of views holds copies of its loans.

    : SBag { [s t  i n }
    @ wraps [s t → SBag { ^ @ SBag { t 2 } }       -- the literal copies `t`
    : String a ( string_from `xy` )
    : SBag b ( wraps [s | ( string_data a )] )      -- a temporary `[s` of views of `a`

The temporary owns a buffer of views of `a`; the copy the literal makes owns a
buffer of its own, holding copies of those views. In A2 a value's memory
dependencies are its `vdeps` (its path, unless it owns its slot, and what it
holds), and a binding is ended by an effect on a root among them (`kill`,
`hits`). So:

* the copy holds a view of `a`, not of the temporary: releasing the temporary
  (`.drop` on it) leaves the copy live (`copy_survives_temp_release`), while a
  value that depended on the temporary itself, which is what nurlc answered
  before AGORA-935 (`rviews` `0`: "views argument 0"), is ended by that release
  (`dep_on_temp_dies`). That is why nurlc kept the temporary, and leaked it;
* replacing `a` ends the copy (`copy_dead_after_replace`), and then no read of
  it types (`read_copy_refused`): the guards
  `copied_view_slice_parameter_kept_past_its_string_is_refused` and
  `copied_view_slice_of_a_lending_call_kept_past_its_string_is_refused`.

nurlc's answer since AGORA-935 is the copy's (`^0`: what the elements view;
`__rv_views_arg` releases a temporary whose elements own no storage). -/

namespace A2.SliceCopyViewWitness

/-- A slice of views: `[s` (a slice stands for A2's view type). -/
def sv : Ty := .slice .int
/-- An owned buffer of them: the temporary, and the copy. -/
def vsv : Ty := .vec sv

/-- `a` (0): the String, owning its buffer. -/
def Ea : Entry := ⟨.vec .int, .own, true, [], [], false, false, false, false⟩
/-- `t` (1): the temporary `[s`, owning a buffer of views of `a`. -/
def Et : Entry := ⟨vsv, .own, true, [], [⟨0, .view⟩], false, false, false, false⟩
/-- `b` (2): the copy, owning a buffer of its own that holds copies of the views:
    it holds a view of `a`, nothing of `t`. -/
def Eb : Entry := ⟨vsv, .own, true, [], [⟨0, .view⟩], false, false, false, false⟩
/-- `b` as nurlc read it before AGORA-935: a value depending on the temporary. -/
def Eb0 : Entry := ⟨vsv, .own, true, [], [⟨0, .view⟩, ⟨1, .view⟩], false, false, false, false⟩

def K : Ctx := fun v =>
  if v = 0 then some Ea else if v = 1 then some Et else if v = 2 then some Eb else none

def K0 : Ctx := fun v =>
  if v = 0 then some Ea else if v = 1 then some Et else if v = 2 then some Eb0 else none

/-- **Releasing the temporary leaves the copy as it was**: nothing of `b` is
    rooted at `t`. -/
theorem copy_survives_temp_release : kill .drop false 1 K 2 = some Eb := by
  simp [kill, killE, hits, K, Eb, Entry.vdeps, Mode.ownSlot, vsv, sv]

/-- ... whereas a value depending on the temporary is ended by its release. -/
theorem dep_on_temp_dies : kill .drop false 1 K0 2 = some { Eb0 with live := false } := by
  simp [kill, killE, hits, K0, Eb0, Entry.vdeps, Mode.ownSlot, Eff.kills, vsv, sv]

/-- **Replacing `a` ends the copy**: it holds a view of `a`. -/
theorem copy_dead_after_replace : kill .replace false 0 K 2 = some { Eb with live := false } := by
  simp [kill, killE, hits, K, Eb, Entry.vdeps, Mode.ownSlot, Eff.kills, vsv, sv]

/-- ... and then no read of it types: every rule reading a variable asks
    that its binding be live. -/
theorem read_copy_refused (F : List Var) (E : Entry) (Γ' : Ctx) :
    ¬ RhsT (kill .replace false 0 K) F (.var 2) E Γ' := by
  intro h
  have hk := copy_dead_after_replace
  cases h <;> simp_all

end A2.SliceCopyViewWitness
