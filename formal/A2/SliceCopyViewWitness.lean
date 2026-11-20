import A2.Closure

/-! AGORA-935 in A2: a copy of a slice of views holds copies of its loans.

    : SBag { [s t  i n }
    @ wraps [s t → SBag { ^ @ SBag { t 2 } }       -- the literal copies `t`
    : String a ( string_from `xy` )
    : SBag b ( wraps [s | ( string_data a )] )      -- a temporary `[s` of views of `a`

The temporary owns a buffer of views of `a`. A2 has no clone rule of its own:
a copy is a call whose summary says what its result holds (`CallT`, `callRes`),
here the summary nurlc gives the copy, `__nurl_slice_copy_v`: an owned result,
no lends. So the copy's entry is not chosen but typed: the call types
(`copy_call`, the copy being no `ThruFn`), `copy_typed` derives the entry from
any `CallT` of the copy, and `copy_holds_a` / `copy_free_of_temp` read off
what A2 gives it — every kind of dependency on the roots of what its argument
holds (`heldOfArgs`), that is on `a`, and nothing rooted at the temporary
itself. A2 and nurlc's answer since AGORA-935 (`^0`: what the elements view)
agree.

A value's memory dependencies are its `vdeps`, and a binding is ended by an
effect on a root among them (`kill`, `hits`). So, of the typed copy:

* releasing the temporary (`.drop` on it) leaves the copy live
  (`copy_survives_temp_release`), while a value that depended on the temporary
  itself — nurlc's answer before AGORA-935 (`rviews` `0`: "views argument 0") —
  is ended by that release (`dep_on_temp_dies`). That is why nurlc kept the
  temporary, and leaked it;
* replacing `a` ends the copy (`copy_dead_after_replace`), and then no read of
  it types (`read_copy_refused`): the guards
  `copied_view_slice_parameter_kept_past_its_string_is_refused` and
  `copied_view_slice_of_a_lending_call_kept_past_its_string_is_refused`. -/

namespace A2.SliceCopyViewWitness

/-- A slice of views: `[s` (a slice stands for A2's view type). -/
def sv : Ty := .slice .int
/-- An owned buffer of them: the temporary, and the copy. -/
def vsv : Ty := .vec sv

/-- The copy, `__nurl_slice_copy_v`'s summary: it takes the slice in, hands back
    an owner of its own, and lends nothing of its argument. Only the summary
    matters to the call. Its body fills a buffer of its own (`.edit false`): it
    changes nothing through a borrow, so it is no `ThruFn`, and a call of it may
    pass an argument that holds views (`CallT`'s last clause). -/
def dupFn : Fn where
  params   := [(.inp, vsv)]
  resTy    := vsv
  resOwn   := true
  lends    := []
  rholds   := []
  outHolds := []
  body     := .edit false 2 (.push 3)
  nvars    := 3

def P : Prog := [dupFn]

/-- `a` (0): the String, owning its buffer. -/
def Ea : Entry := ⟨.vec .int, .own, true, [], [], false, false, false, false⟩
/-- `t` (1): the temporary `[s`, owning a buffer of views of `a`. -/
def Et : Entry := ⟨vsv, .own, true, [], [⟨0, .view⟩], false, false, false, false⟩

/-- The caller before the copy. -/
def Kt : Ctx := fun v => if v = 0 then some Ea else if v = 1 then some Et else none

/-- The copy's entry, as A2 types the call: `callRes`, not a chosen entry. -/
def Eb : Entry := callRes Kt dupFn [1]

/-- The copy changes nothing through a borrow, nor calls what does. -/
theorem dupFn_not_thru : ¬ ThruFn P 0 := by
  intro h
  cases h with
  | here hf hb =>
    simp only [P, List.getElem?_cons_zero, Option.some.injEq] at hf
    subst hf
    simp [dupFn, Stmt.hasThru] at hb
  | call hf hg _ =>
    simp only [P, List.getElem?_cons_zero, Option.some.injEq] at hf
    subst hf
    simp [dupFn, Stmt.calls] at hg

/-- **The copy is a call A2 types**: of the temporary `t`, which holds views
    of `a`, with nothing frozen. -/
theorem copy_call : CallT P Kt [] 0 [1] Eb (callPost Kt dupFn [1]) := by
  refine ⟨dupFn, rfl, rfl, ?_, ?_, ?_, rfl, rfl, fun h => absurd h dupFn_not_thru⟩
  · intro i hi
    obtain rfl : i = 0 := by simp [dupFn] at hi; omega
    refine ⟨Et, rfl, rfl, rfl, fun h => by simp [dupFn, PMode.moves] at h, fun h => ?_⟩
    rcases h with h | h <;> simp [dupFn] at h
  · intro d hd
    simp [mutNames, argNames, argE, Kt, Et, nameDeps, Kind.isName, Entry.vdeps, Mode.ownSlot, vsv, sv] at hd
  · refine CallDtorSafe.of_none (fun v E hE => ?_) _ _
    simp only [Kt] at hE
    split at hE
    · simp only [Option.some.injEq] at hE; subst hE; simp [Ea]
    · split at hE
      · simp only [Option.some.injEq] at hE; subst hE; simp [Et]
      · cases hE

/-- **The copy is typed so**: any `CallT` of it gives `Eb`. -/
theorem copy_typed {F : List Var} {E : Entry} {Γ' : Ctx} (h : CallT P Kt F 0 [1] E Γ') : E = Eb := by
  obtain ⟨fn, hf, _, _, _, _, hE, _, _⟩ := h
  simp only [P, List.getElem?_cons_zero, Option.some.injEq] at hf
  subst hf
  exact hE

/-- It holds a view of `a`: what its argument held. -/
theorem copy_holds_a : (⟨0, .view⟩ : Dep) ∈ Eb.vdeps := by
  simp [Eb, callRes, heldOfArgs, allKinds, roots, memDeps, argE, argNames, ownHeld, Entry.vdeps,
    Mode.ownSlot, resMode, Kt, Et, dupFn, vsv, sv, Ty.holdsView, Kind.isName]

/-- ... and nothing rooted at the temporary. -/
theorem copy_free_of_temp : ∀ d ∈ Eb.vdeps, d.root ≠ 1 := by
  simp [Eb, callRes, heldOfArgs, allKinds, roots, memDeps, argE, argNames, nameDeps, ownHeld, Entry.vdeps,
    Mode.ownSlot, resMode, Kt, Et, dupFn, vsv, sv, Ty.holdsView, Kind.isName]

/-- `b` as nurlc read it before AGORA-935: a value depending on the temporary. -/
def Eb0 : Entry := ⟨vsv, .own, true, [], [⟨0, .view⟩, ⟨1, .view⟩], false, false, false, false⟩

/-- The caller after the copy is bound to `b` (2). -/
def K : Ctx := fun v => if v = 2 then some Eb else Kt v

def K0 : Ctx := fun v => if v = 2 then some Eb0 else Kt v

/-- **Releasing the temporary leaves the copy as it was**: nothing of `b` is
    rooted at `t`. -/
theorem copy_survives_temp_release : kill .drop false 1 K 2 = some Eb := by
  have hfree := copy_free_of_temp
  have hh : hits .drop false 1 Eb = false := by
    simp only [hits, Bool.and_eq_false_iff, List.any_eq_false, beq_iff_eq, Bool.and_eq_true, not_and]
    exact Or.inr (fun d hd hr => absurd hr (hfree d hd))
  simp [kill, K, killE, hh]

/-- ... whereas a value depending on the temporary is ended by its release. -/
theorem dep_on_temp_dies : kill .drop false 1 K0 2 = some { Eb0 with live := false } := by
  simp [kill, killE, hits, K0, Eb0, Entry.vdeps, Mode.ownSlot, Eff.kills, vsv, sv]

/-- **Replacing `a` ends the copy**: it holds a view of `a`. -/
theorem copy_dead_after_replace : kill .replace false 0 K 2 = some { Eb with live := false } := by
  have hh : hits .replace false 0 Eb = true := by
    simp [hits, Eb, callRes, heldOfArgs, allKinds, roots, memDeps, argE, argNames, nameDeps, ownHeld,
      Entry.vdeps, Mode.ownSlot, resMode, Kt, Et, dupFn, vsv, sv, Ty.holdsView, Kind.isName, Eff.kills]
  simp [kill, K, killE, hh]

/-- ... and then no read of it types: every rule reading a variable asks
    that its binding be live. -/
theorem read_copy_refused (F : List Var) (E : Entry) (Γ' : Ctx) :
    ¬ RhsT (kill .replace false 0 K) F (.var 2) E Γ' := by
  intro h
  have hk := copy_dead_after_replace
  cases h <;> simp_all

/-! ### The literal's field: `@ SBag { t 2 }` as A2's `pair`

The copy is the literal's first field: `pair` of the copy's binding (2) and the
number (3). A2's `pair` holds what its fields' pushes hand it (`PushArg`):
the copy, an owner, is moved in and hands its `held` over (`PushArg.move`), a
number hands nothing (`PushArg.int`). So the literal holds what the typed copy
holds, and nothing of the temporary. -/

/-- The caller with the copy bound (2) and the number (3). -/
def KL : Ctx := fun v => if v = 3 then some intE else K v

/-- **The literal holds what the copy holds**: any typing of `pair 2 3`. -/
theorem lit_held {F : List Var} {E : Entry} {Γ' : Ctx} (h : RhsT KL F (.pair 2 3) E Γ') :
    E.held = Eb.held := by
  cases h with
  | pair hy _ hpy hz _ hpz _ =>
    simp only [KL, K, show (2 : Nat) ≠ 3 from by decide, ↓reduceIte, Option.some.injEq] at hy
    subst hy
    cases hpy with
    | move _ _ _ _ _ =>
      have hz' := hz
      simp only [setE, upd, kill, KL, show (3 : Nat) ≠ 2 from by decide, ↓reduceIte,
        Option.map_some, killE, hits, intE] at hz'
      simp only [Option.some.injEq] at hz'
      subst hz'
      cases hpz with
      | int => simp
      | move ho _ _ _ _ => simp [Ty.owning] at ho

/-- ... so it is free of the temporary too. -/
theorem lit_free_of_temp {F : List Var} {E : Entry} {Γ' : Ctx} (h : RhsT KL F (.pair 2 3) E Γ') :
    ∀ d ∈ E.held, d.root ≠ 1 := by
  rw [lit_held h]
  intro d hd
  exact copy_free_of_temp d (by
    simp only [Entry.vdeps, List.mem_append]
    exact Or.inr hd)

end A2.SliceCopyViewWitness
