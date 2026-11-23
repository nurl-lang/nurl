import A2.Codes
import A2.SrcKeep

/-! A2 — the environment handed over (A2-envhand): a call through an owned
package of a method whose interface takes the receiver `inout`
(`Stmt.callcE`, `StmtT.callcE`).

A call through a package lends its code a copy of the environment
(`envMem`), so a change would land in the copy. A method that changes the
environment (an accumulator's moved-in count, a trait object's `inout`
method) is called with the environment handed over instead, as `withElem`
hands over an element: the environment moves out of the package into a
fresh binding `y`, the code is called on `y` as an ordinary call with `y`
its `inout` receiver, and `y`'s value goes back into the package, at the
same place (`handStmt`). Every form the step leaves is one A2 already
types (`scope`, `letcall`, `assign` of a `pack`), so preservation is the
step's own case: the store the hand-over leaves (this section), the code's
call typed from the interface's (`callT_hand`), and what the code's call
leaves, as weak as what the interface's does (`hand_typed`).

AGORA-927: the interface may take parameters beside the receiver, `zs`; the
code's call passes them as they are, beside `y`. That part of the comparison
is the identity: each extra argument has the same entry in both contexts,
and the two calls move and change them alike (`handRel_tail`), the run-time
form handing an `inout` one no more than the source (`y` depends on no more
than the package). What is new is that they and `y` are apart
(`hand_args_apart`), and that what the call hands the receiver from them
ends `y` no more than it ends the package. The owned (drop) interface takes
no such parameter. -/

namespace A2

/-! ### The store the hand-over leaves -/

/-- A slot set to hold nothing owns nothing. -/
theorem HeapOK.set_none {m : Mem} (hh : HeapOK m) (x : Var) (o : Bool) :
    HeapOK (m.set x ⟨o, none⟩) := by
  have hown : ∀ o' U, OwnedAt (m.set x ⟨o, none⟩) o' U → OwnedAt m o' U := fun o' U h => by
    rcases ownedAt_set.mp h with ⟨_, h⟩ | ⟨_, h⟩
    · cases h
    · exact h
  exact ⟨fun o' U h => hh.nodup o' U (hown o' U h),
    fun o1 o2 U1 U2 hne h1 h2 => hh.disj o1 o2 U1 U2 hne (hown o1 U1 h1) (hown o2 U2 h2),
    fun o' U h => hh.alloc o' U (hown o' U h), fun o' U h => hh.self o' U (hown o' U h),
    hh.blk.frame rfl (Nat.le_refl _) (fun _ _ => rfl) (fun o' U h i hi => hh.notPay (hown o' U h) hi),
    hh.views⟩

/-- **Binding a fresh variable, unset**: a dead entry that depends on
    nothing, over a slot that holds no value (a call's result binding before
    the call returns, `callX`). -/
theorem MInv.addUnset {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {x : Var} (hx : Γ x = none) (hxn : x < m.nv)
    {E : Entry} (hl : E.live = false) (hp : E.path = []) (hh : E.held = []) (htok : E.ty.ok = true)
    (hm : E.mode = .own ∨ E.mode = .bor) (hown : E.mode = .own → E.ty.owning = true)
    (hdt : E.dtor = false) (hdb : E.dbind = false) :
    MInv (m.set x ⟨E.mode.ownSlot, none⟩) (setE Γ x E) := by
  have hmx : m.st x = none := by
    have := hi.dom x; rw [hx] at this; cases h : m.st x <;> simp_all
  have hext : ∀ o', m.st o' ≠ none → (m.set x ⟨E.mode.ownSlot, none⟩).st o' = m.st o' := by
    intro o' ho'
    have : o' ≠ x := fun h => ho' (h ▸ hmx)
    simp [upd_ne _ _ this]
  have hroot : ∀ r Er, Γ r = some Er → r ≠ x := fun r Er h hr => by rw [hr, hx] at h; cases h
  have hrb : E.mode ≠ .rootb := by rcases hm with h | h <;> rw [h] <;> simp
  have hvd : E.vdeps = [] := by simp [Entry.vdeps, hp, hh]
  constructor
  · intro w
    by_cases hw : w = x
    · subst hw; simp [setE]
    · simp only [setE, upd_ne _ _ hw, Mem.set_st]; exact hi.dom w
  · intro w Ew hw
    by_cases hwx : w = x
    · subst hwx
      simp only [setE, upd_same, Option.some.injEq] at hw
      subst hw
      have hl' : ∀ {α : Prop}, E.live = true → α := fun h => by rw [hl] at h; cases h
      refine ⟨⟨E.mode.ownSlot, none⟩, by simp, htok, rfl, fun hos => ⟨?_, fun T hT => (by cases hT),
        fun h => hl' h⟩, fun _ h => hl' h⟩
      rcases hm with h | h
      · exact hown h
      · rw [h] at hos; cases hos
    · simp only [setE, upd_ne _ _ hwx] at hw
      obtain ⟨sl, hsl, hok, hslot⟩ := hi.slot w Ew hw
      exact ⟨sl, by simp [upd_ne _ _ hwx, hsl], hok, hslot.ext hext⟩
  · exact hi.heap.set_none x _
  · intro w hw
    by_cases hwx : w = x
    · subst hwx; exact hxn
    · simp only [Mem.set_st, upd_ne _ _ hwx] at hw; exact hi.nvSt w hw
  · intro w Ew b hw
    by_cases hwx : w = x
    · subst hwx
      simp only [setE, upd_same, Option.some.injEq] at hw
      subst hw
      rcases hm with h | h <;> rw [h] <;> simp
    · simp only [setE, upd_ne _ _ hwx] at hw; exact hi.noInout w Ew b hw
  · intro w Ew hw
    by_cases hwx : w = x
    · subst hwx
      simp only [setE, upd_same, Option.some.injEq] at hw
      subst hw
      rcases hm with h | h <;> rw [h] <;> simp
    · simp only [setE, upd_ne _ _ hwx] at hw; exact hi.noRegion w Ew hw
  · refine ⟨?live, ?dtorc, ?armc, ?viewc⟩
    case armc =>
      intro w Ew hw hd
      by_cases hwx : w = x
      · subst hwx; simp only [setE, upd_same, Option.some.injEq] at hw; subst hw; rw [hdt] at hd; cases hd
      · simp only [setE, upd_ne _ _ hwx] at hw; exact hi.wf.arm w Ew hw hd
    case viewc =>
      intro w Ew hw hd
      by_cases hwx : w = x
      · subst hwx; simp only [setE, upd_same, Option.some.injEq] at hw; subst hw; rw [hdb] at hd; cases hd
      · simp only [setE, upd_ne _ _ hwx] at hw; exact hi.wf.view w Ew hw hd
    case dtorc =>
      intro w Ew hw hd hos hn d hdd hnm
      by_cases hwx : w = x
      · subst hwx; simp only [setE, upd_same, Option.some.injEq] at hw; subst hw; rw [hdb] at hd; cases hd
      · simp only [setE, upd_ne _ _ hwx] at hw
        obtain ⟨Er, hEr, hro⟩ := hi.wf.dtor w Ew hw hd hos hn d hdd hnm
        exact ⟨Er, by simp [setE, upd_ne _ _ (hroot d.root Er hEr), hEr], hro⟩
    intro w Ew hw hlw hn r hr
    by_cases hwx : w = x
    · subst hwx; simp only [setE, upd_same, Option.some.injEq] at hw; subst hw; rw [hl] at hlw; cases hlw
    · simp only [setE, upd_ne _ _ hwx] at hw
      obtain ⟨Er, hEr, hro⟩ := hi.wf w Ew hw hlw hn r hr
      exact ⟨Er, by simp [setE, upd_ne _ _ (hroot r Er hEr), hEr], hro⟩
  · intro p Ep hp hmp
    by_cases hpx : p = x
    · subst hpx; simp only [setE, upd_same, Option.some.injEq] at hp; subst hp; exact absurd hmp hrb
    · simp only [setE, upd_ne _ _ hpx] at hp; exact hi.rootbLive p Ep hp hmp
  · intro p Ep hp hmp
    by_cases hpx : p = x
    · subst hpx; simp only [setE, upd_same, Option.some.injEq] at hp; subst hp; exact absurd hmp hrb
    · simp only [setE, upd_ne _ _ hpx] at hp; exact hi.rootbLt p Ep hp hmp
  · have hΓ : ∀ r Er, Γ r = some Er → Er.live = true → Er.held = [] → Er.mode.ownSlot = true →
        ∃ Er', setE Γ x E r = some Er' ∧ Er'.live = true ∧ Er'.held = [] ∧ Er'.ty = Er.ty ∧ Er'.mode = Er.mode :=
      fun r Er hEr hl hh _ => ⟨Er, by simp [setE, upd_ne _ _ (hroot r Er hEr), hEr], hl, hh, rfl, rfl⟩
    intro w Ew hw hlw hn
    by_cases hwx : w = x
    · subst hwx; simp only [setE, upd_same, Option.some.injEq] at hw; subst hw; rw [hl] at hlw; cases hlw
    · simp only [setE, upd_ne _ _ hwx] at hw
      exact (hi.names w Ew hw hlw hn).transport (fun r Er _ => hΓ r Er) (List.Subset.refl _)
  · exact hi.fresh.bind hx (FreshE.of_live hl)
  · intro w Ew sl T hw hlw hsl hT
    by_cases hwx : w = x
    · subst hwx; simp only [setE, upd_same, Option.some.injEq] at hw; subst hw; rw [hl] at hlw; cases hlw
    · simp only [setE, upd_ne _ _ hwx] at hw
      simp only [Mem.set_st, upd_ne _ _ hwx] at hsl
      exact hi.held w Ew sl T hw hlw hsl hT
  · intro w sl T hsl hT
    by_cases hwx : w = x
    · subst hwx; simp only [Mem.set_st, upd_same, Option.some.injEq] at hsl; subst hsl; exact (by cases hT)
    · simp only [Mem.set_st, upd_ne _ _ hwx] at hsl
      exact hi.pkgs w sl T hsl hT
  · intro w Ew sl hw hsl
    by_cases hwx : w = x
    · subst hwx
      simp only [setE, upd_same, Option.some.injEq] at hw
      subst hw
      intro hd; rw [hdb] at hd; cases hd
    · simp only [setE, upd_ne _ _ hwx] at hw
      have hsl0 : m.st w = some sl := by simpa [Mem.set_st, upd_ne _ _ hwx] using hsl
      exact (hi.armed w Ew sl hw hsl0).keep fun _ _ _ dep _ => (rootKeep_ext hext dep.root).vkeep
  · intro w Ew sl T hw hsl hown' hT
    by_cases hwx : w = x
    · subst hwx; simp only [Mem.set_st, upd_same, Option.some.injEq] at hsl; subst hsl; cases hT
    · simp only [setE, upd_ne _ _ hwx] at hw
      have hsl0 : m.st w = some sl := by simpa [Mem.set_st, upd_ne _ _ hwx] using hsl
      exact (hi.shares w Ew sl T hw hsl0 hown' hT).of_blk rfl
  · intro k bl hk
    obtain ⟨h1, h2, h3, h4⟩ := hi.blocks k bl hk
    exact ⟨h1, h2, fun p hp => ⟨(h3 p hp).1, (h3 p hp).2.of_blk rfl⟩, h4⟩
  · exact hi.pkgFree_addNone hx

/-- A tree of an owning type is owned. -/
theorem WFv.owns_owning {t : Ty} {v : Val} (hw : WFv t v) (ho : t.owning = true) : v.owns = true :=
  hw.owns ho

/-- The context a hand-over leaves: what depended on the package `c` ended
    (`kill .replace`, as a move of it ends it), `c` moved out, the
    environment's binding `y` an owner of the environment's type holding what
    the package held (`compE`, as a field taken apart), and the result
    binding `x` unset (`E0`). -/
def handCtx (Γ : Ctx) (c x : Var) (Ec : Entry) (te : Ty) (y : Var) (E0 : Entry) : Ctx :=
  setE (setE (setE (kill .replace false c Γ) c { Ec with live := false, dtor := false }) y (compE Ec te)) x E0

/-- **The store a hand-over leaves** satisfies the invariant: the package's
    tree moved from `c` to the environment's binding `y` (the first fresh
    variable), as a field of a struct taken apart (`rhs_move'`, `out_part`),
    and `x` bound unset. -/
theorem hand_minv {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ) (hanchF : RootbAnchF Γ F)
    {c x : Var} {Ec : Entry} (hc : Γ c = some Ec) (hl : Ec.live = true) (hos : Ec.mode.ownSlot = true)
    (hcF : c ∉ F) (hny : NoPin Γ c) (hdc : DtorSafe Γ .replace false c)
    {fs : List Nat} {te : Ty} {ms : List Nat} {q : Cross} {env : Val} (htc : Ec.ty.undtor = .fn ms q)
    (hslot : m.st c = some ⟨true, some (.pkg fs te ms env [])⟩) (hown : te.owning = true)
    (htok : te.ok = true) (hx : Γ x = none) (hxn : x < m.nv) {E0 : Entry} (hl0 : E0.live = false)
    (hp0 : E0.path = []) (hh0 : E0.held = []) (htok0 : E0.ty.ok = true) (hm0 : E0.mode = .own ∨ E0.mode = .bor)
    (hown0 : E0.mode = .own → E0.ty.owning = true) (hdt0 : E0.dtor = false) (hdb0 : E0.dbind = false) :
    MInv (handMem m c x env E0.mode.ownSlot) (handCtx Γ c x Ec te m.nv E0) ∧
    RhsPost { m with nv := m.nv + 2 } ({ m with nv := m.nv + 2 }.set c ⟨true, none⟩) Γ
      (setE (kill .replace false c Γ) c { Ec with live := false, dtor := false }) F := by
  have hanch : RootbAnch Γ F := hanchF.toH
  let m' : Mem := { m with nv := m.nv + 2 }
  have hi' : MInv m' Γ :=
    hi.of_st rfl ⟨hi.heap.nodup, hi.heap.disj, hi.heap.alloc, hi.heap.self, hi.heap.blk, hi.heap.views⟩
      (by show m.nv ≤ m.nv + 2; omega)
  obtain ⟨post, out⟩ := rhs_move' hi' hanch hc hl hos hcF hny (HeldSpared.of_none (NoHeld.of_anchF hanchF hcF) _ _) hslot hdc
  have hτ : Ec.ty ≠ .int := fun h => by rw [h] at htc; cases htc
  have hwP : WFv Ec.ty.undtor (.pkg fs te ms env []) := ((out.valOwn rfl).2.1).undtor
  rw [htc] at hwP
  obtain ⟨hwe, hq⟩ : WFv te env ∧ q.Fits te [] := by cases hwP with | pkg h1 h2 => exact ⟨h1, h2⟩
  have hvin : ∀ s v, ViewIn te env s v → ViewIn Ec.ty (.pkg fs te ms env []) s v := by
    intro s v hv
    rw [← ViewIn.undtor_iff, htc]
    cases q with
    | any => exact ViewIn.pkg hv
    | _ => exact absurd hv.holdsView (by rw [(hq.1 rfl).1]; simp)
  have hain : ∀ u k p, ArcIn te env u k p → ArcIn Ec.ty (.pkg fs te ms env []) u k p := by
    intro u k p ha
    rw [← ArcIn.undtor_iff, htc]
    cases hqs : q.shares with
    | true => exact ArcIn.pkg ha hqs
    | false => exact absurd ha.hasArc (by rw [hq.2.2.1 hqs]; simp)
  have outy := out_part out hτ hwe (Sub.pkg (Sub.refl _)) hvin (by simp [Val.ids]) htok hain
  have hy0 : setE (kill .replace false c Γ) c { Ec with live := false, dtor := false } m.nv = none := by
    have hcn : c ≠ m.nv := fun e => by
      have := hi.nvSt c (by rw [hslot]; rfl); rw [e] at this; exact Nat.lt_irrefl _ this
    have hΓn : Γ m.nv = none := by
      cases h : Γ m.nv with
      | none => rfl
      | some E => exact absurd (hi.nvSt m.nv (by rw [← hi.dom, h]; rfl)) (Nat.lt_irrefl _)
    simp [setE, upd_ne _ _ (Ne.symm hcn), kill, hΓn]
  have hi2 := post.inv.add hy0 (by show m.nv < m.nv + 2; omega) outy
  have hxc : x ≠ c := fun e => by rw [e, hc] at hx; cases hx
  have hxy : x ≠ m.nv := fun e => by rw [e] at hxn; exact Nat.lt_irrefl _ hxn
  have hx2 : setE (setE (kill .replace false c Γ) c { Ec with live := false, dtor := false }) m.nv (compE Ec te) x =
      none := by simp [setE, upd_ne _ _ hxy, upd_ne _ _ hxc, kill, hx]
  have hi3 := hi2.addUnset hx2 (Nat.lt_of_lt_of_le hxn (Nat.le_add_right _ 2)) hl0 hp0 hh0 htok0 hm0 hown0 hdt0 hdb0
  rw [hwe.owns_owning hown] at hi3
  exact ⟨hi3, post⟩

/-! ### The code's call, typed from the interface's -/

theorem compE_owning (E : Entry) {t : Ty} (h : t.owning = true) :
    compE E t = ⟨t, .own, true, [], ownHeld true t E.held, false, false, false, false⟩ := by
  cases t <;> simp_all [compE, Ty.owning]

/-- What a package that is live where every dependency on it has ended
    (`kill .replace`) depends on: no dependency on itself. -/
theorem kill_live_self {c : Var} {E : Entry} (hl : (killE .replace false c E).live = true) (hn : E.ty ≠ .int) :
    E.live = true ∧ ∀ d ∈ E.vdeps, d.root ≠ c := by
  obtain ⟨h1, h2⟩ := killE_live_dep hl (Or.inl hn)
  exact ⟨h1, fun d hd hr => by have := h2 d hd hr; simp [Eff.kills] at this⟩

section hand
variable {Γ : Ctx} {c x y : Var} {Ec : Entry} {te : Ty} {E0 : Entry}

theorem handCtx_x : handCtx Γ c x Ec te y E0 x = some E0 := by simp [handCtx, setE]

theorem handCtx_y (hxy : x ≠ y) : handCtx Γ c x Ec te y E0 y = some (compE Ec te) := by
  simp [handCtx, setE, upd_ne _ _ (Ne.symm hxy)]

theorem handCtx_c (hxc : x ≠ c) (hyc : y ≠ c) :
    handCtx Γ c x Ec te y E0 c = some { Ec with live := false, dtor := false } := by
  simp [handCtx, setE, upd_ne _ _ (Ne.symm hxc), upd_ne _ _ (Ne.symm hyc)]

theorem handCtx_other {v : Var} (hvx : v ≠ x) (hvy : v ≠ y) (hvc : v ≠ c) :
    handCtx Γ c x Ec te y E0 v = kill .replace false c Γ v := by
  simp [handCtx, setE, upd_ne _ _ hvx, upd_ne _ _ hvy, upd_ne _ _ hvc]

end hand

/-- The roots a live binding of a well-formed context depends on are bound,
    so below the next fresh variable. -/
theorem MInv.root_lt {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {v : Var} {E : Entry} (hv : Γ v = some E)
    (hl : E.live = true) (hn : E.ty ≠ .int ∨ E.mode = .rootb) {r : Var} (hr : r ∈ roots E.vdeps) :
    r < m.nv := by
  obtain ⟨Er, hEr, _⟩ := hi.wf v E hv hl hn r hr
  exact hi.nvSt r (by rw [← hi.dom, hEr]; rfl)

/-- ... and so do a destructor binding's memory dependencies. -/
theorem MInv.dtor_root_lt {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {v : Var} {E : Entry} (hv : Γ v = some E)
    (hd : E.dtor = true) (hos : E.mode.ownSlot = true) (hn : E.ty ≠ .int ∨ E.mode = .rootb) {d : Dep}
    (hdd : d ∈ E.vdeps) (hnm : d.kind.isName = false) : d.root < m.nv := by
  obtain ⟨Er, hEr, _⟩ := hi.wf.dtor v E hv (hi.wf.arm v E hv hd) hos hn d hdd hnm
  exact hi.nvSt d.root (by rw [← hi.dom, hEr]; rfl)

/-- A destructor binding views nothing of a fresh variable. -/
theorem MInv.dtorSafe_fresh {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} (hy : m.nv ≤ y) (e : Eff)
    (hv : Bool) : DtorSafe Γ e hv y := by
  intro v E hE hd hos
  unfold hitsMem
  cases hg : (E.ty != .int || E.mode == .rootb)
  · rfl
  · rw [Bool.true_and, List.any_eq_false]
    intro d hdd hc
    simp only [Bool.and_eq_true, beq_iff_eq, Bool.not_eq_true'] at hc
    obtain ⟨⟨hr, hnm⟩, _⟩ := hc
    have hn : E.ty ≠ .int ∨ E.mode = .rootb := by
      simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, beq_iff_eq] at hg; exact hg
    have := hi.dtor_root_lt hE hd hos hn hdd hnm
    rw [hr] at this; have := vlt this; omega

/-! ### What the code's call and the give-back leave, beside the interface's call

The run-time form's context and the source's are compared binding by
binding, outside the bindings the hand-over makes or changes (`x`, the
environment's `y`, the inner result `r`, the package `c`): there each
run-time entry says no less than the source's (`EntryWeaker`), depends only on
bindings of the store before the step (`Rooted`), and a fixed one is the
store's as it was. -/

/-- An entry that no change of a binding outside `Γ` ends: dead, a plain
    integer, or depending only on bindings of `Γ`. -/
def Rooted (Γ : Ctx) (E : Entry) : Prop :=
  E.live = false ∨ (E.ty = .int ∧ E.mode ≠ .rootb) ∨ ∀ d ∈ E.vdeps, (Γ d.root).isSome

theorem Rooted.killE_fresh {Γ : Ctx} {E : Entry} (h : Rooted Γ E) {v : Var} (hv : Γ v = none) (e : Eff)
    (hb : Bool) : killE e hb v E = E := by
  rcases h with h | ⟨ht, hm⟩ | h
  · exact killE_dead h
  · unfold killE hits; simp [ht, hm]
  · exact killE_nohit fun d hd hr => by have := h d hd; rw [hr, hv] at this; cases this

theorem Rooted.killE {Γ : Ctx} {E : Entry} (h : Rooted Γ E) (e : Eff) (hb : Bool) (v : Var) :
    Rooted Γ (killE e hb v E) := by
  rcases h with h | h | h
  · exact Or.inl (by rw [killE_dead h]; exact h)
  · exact Or.inr (Or.inl (by rw [killE_ty, killE_mode]; exact h))
  · exact Or.inr (Or.inr (by rw [killE_vdeps]; exact h))

theorem Rooted.killAll {Γ : Ctx} {E : Entry} (h : Rooted Γ E) (ds : List Dep) : Rooted Γ (RSetup.killAll ds E) := by
  unfold RSetup.killAll; split
  · rcases h with h | h | h
    · exact Or.inl rfl
    · exact Or.inl rfl
    · exact Or.inl rfl
  · exact h

/-- A store's bindings are rooted in it. -/
theorem MInv.rooted {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {v : Var} {E : Entry} (hv : Γ v = some E) : Rooted Γ E := by
  cases hl : E.live
  · exact Or.inl hl
  by_cases hn : E.ty ≠ .int ∨ E.mode = .rootb
  · refine Or.inr (Or.inr fun d hd => ?_)
    obtain ⟨Er, hEr, _⟩ := hi.wf v E hv hl hn d.root (List.mem_map_of_mem (f := Dep.root) hd)
    rw [hEr]; rfl
  · simp only [not_or, ne_eq, Decidable.not_not] at hn
    exact Or.inr (Or.inl hn)

/-- An entry not fixed is not changed by a weaker one's being taken as it is. -/
theorem EntryWeaker.killR {E E' : Entry} (hw : EntryWeaker E E') {e : Eff} {hb : Bool} {v : Var}
    (hfix : E.fixed → killE e hb v E' = E') : EntryWeaker E (killE e hb v E') := by
  obtain ⟨ht, hm, hr, hlv, hd, hdb, ha, hk, hf, hg⟩ := hw
  refine ⟨by rw [killE_ty, ht], by rw [killE_mode, hm], fun h => by rw [hfix h, hr h], fun h => ?_,
    fun h => by rw [killE_dtor, killE_held]; exact hd h, by rw [killE_dbind, hdb],
    fun h => by rw [killE_dtor] at h; exact ha h, fun h hos hn d hnm => by rw [killE_held]; exact hk h hos hn d hnm,
    fun hl hn hb h => by
      rw [killE_fresh] at h; rw [killE_path]; rw [killE_ty] at hn; rw [killE_mode] at hb
      rw [killE_live] at hl; simp only [Bool.and_eq_true] at hl
      exact hf hl.1 hn hb h,
    fun hn hb hhf => by
      rw [killE_heldFresh] at hhf; rw [killE_ty] at hn; rw [killE_mode] at hb
      exact hg hn hb hhf⟩
  rw [killE_live] at h
  simp only [Bool.and_eq_true] at h
  obtain ⟨hl, hp, hh⟩ := hlv h.1
  exact ⟨hl, fun ho => by rw [killE_path]; exact hp ho, by rw [killE_held]; exact hh⟩

/-- The run-time context `Γd` beside the source's `Γs`, outside `X`. -/
def HandRel (Γ : Ctx) (X : List Var) (Γd Γs : Ctx) : Prop :=
  ∀ v, v ∉ X → (Γd v = none ↔ Γs v = none) ∧
    ∀ Ed Es, Γd v = some Ed → Γs v = some Es → EntryWeaker Ed Es ∧ Rooted Γ Ed ∧ (Ed.fixed → Γ v = some Ed)

namespace HandRel
variable {Γ : Ctx} {X : List Var} {Γd Γs : Ctx}

/-- Only the run-time form ends what depends on a binding the store had none of. -/
theorem killD_fresh (h : HandRel Γ X Γd Γs) {w : Var} (hw : Γ w = none) (e : Eff) (hb : Bool) :
    HandRel Γ X (kill e hb w Γd) Γs := by
  intro v hv
  obtain ⟨hn, hr⟩ := h v hv
  refine ⟨by simp [kill, hn], fun Ed Es hd hs => ?_⟩
  simp only [kill] at hd
  obtain ⟨Ed0, hd0, rfl⟩ := Option.map_eq_some_iff.mp hd
  obtain ⟨h1, h2, h3⟩ := hr Ed0 Es hd0 hs
  rw [h2.killE_fresh hw]
  exact ⟨h1, h2, h3⟩

/-- Both end what depends on one binding. -/
theorem kill2 (h : HandRel Γ X Γd Γs) (e : Eff) (hb : Bool) (w : Var)
    (hfix : ∀ v E, Γ v = some E → E.fixed → killE e hb w E = E) :
    HandRel Γ X (kill e hb w Γd) (kill e hb w Γs) := by
  intro v hv
  obtain ⟨hn, hr⟩ := h v hv
  refine ⟨by simp [kill, hn], fun Ed Es hd hs => ?_⟩
  simp only [kill] at hd hs
  obtain ⟨Ed0, hd0, rfl⟩ := Option.map_eq_some_iff.mp hd
  obtain ⟨Es0, hs0, rfl⟩ := Option.map_eq_some_iff.mp hs
  obtain ⟨h1, h2, h3⟩ := hr Ed0 Es0 hd0 hs0
  refine ⟨killE_weaker h1, h2.killE e hb w, fun hf => ?_⟩
  have hf0 : Ed0.fixed := by unfold Entry.fixed at hf ⊢; rwa [killE_mode, killE_ty] at hf
  rw [hfix v Ed0 (h3 hf0) hf0]; exact h3 hf0

/-- Only the source ends what depends on one binding. -/
theorem killS (h : HandRel Γ X Γd Γs) (e : Eff) (hb : Bool) (w : Var)
    (hfix : ∀ v E, Γ v = some E → E.fixed → killE e hb w E = E) :
    HandRel Γ X Γd (kill e hb w Γs) := by
  intro v hv
  obtain ⟨hn, hr⟩ := h v hv
  refine ⟨by simp [kill, hn], fun Ed Es hd hs => ?_⟩
  simp only [kill] at hs
  obtain ⟨Es0, hs0, rfl⟩ := Option.map_eq_some_iff.mp hs
  obtain ⟨h1, h2, h3⟩ := hr Ed Es0 hd hs0
  refine ⟨h1.killR fun hf => ?_, h2, h3⟩
  rw [h1.fixed hf]; exact hfix v Ed (h3 hf) hf

/-- A binding of `X` set, on either side. -/
theorem setD (h : HandRel Γ X Γd Γs) {w : Var} (hw : w ∈ X) (E : Entry) : HandRel Γ X (setE Γd w E) Γs := by
  intro v hv
  have hvw : v ≠ w := fun e => hv (e ▸ hw)
  simp only [setE, upd_ne _ _ hvw]; exact h v hv

theorem setS (h : HandRel Γ X Γd Γs) {w : Var} (hw : w ∈ X) (E : Entry) : HandRel Γ X Γd (setE Γs w E) := by
  intro v hv
  have hvw : v ≠ w := fun e => hv (e ▸ hw)
  simp only [setE, upd_ne _ _ hvw]; exact h v hv

theorem updD (h : HandRel Γ X Γd Γs) {w : Var} (hw : w ∈ X) (o : Option Entry) : HandRel Γ X (upd Γd w o) Γs := by
  intro v hv
  have hvw : v ≠ w := fun e => hv (e ▸ hw)
  simp only [upd_ne _ _ hvw]; exact h v hv

/-- The run-time form's closures end no more than the source's, and neither
    ends a fixed binding. -/
theorem killNames (h : HandRel Γ X Γd Γs) {A B : List Dep} (hsub : ∀ d ∈ A, d ∈ B ∨ d.kind.bound = .none)
    (hfix : ∀ v E, Γ v = some E → E.fixed → ∀ d ∈ B, hits d.kind.bound false d.root E = false) :
    HandRel Γ X (A2.killNames A Γd) (A2.killNames B Γs) := by
  intro v hv
  obtain ⟨hn, hr⟩ := h v hv
  refine ⟨by simp [RSetup.killNames_eq, hn], fun Ed Es hd hs => ?_⟩
  rw [RSetup.killNames_eq] at hd hs
  obtain ⟨Ed0, hd0, rfl⟩ := Option.map_eq_some_iff.mp hd
  obtain ⟨Es0, hs0, rfl⟩ := Option.map_eq_some_iff.mp hs
  obtain ⟨h1, h2, h3⟩ := hr Ed0 Es0 hd0 hs0
  refine ⟨weaker_killAll_more h1 hsub fun hf => hfix v Ed0 (h3 hf) hf, h2.killAll A, fun hf => ?_⟩
  have hf0 := killAll_fixed.mp hf
  rw [killAll_id fun d hd => ?_]
  · exact h3 hf0
  · rcases hsub d hd with hd | hd
    · exact hfix v Ed0 (h3 hf0) hf0 d hd
    · rw [hd]; exact hits_none

end HandRel

/-! ### The bindings the rules read for pins and destructors -/

/-- `Γ'`'s borrowed parameters, destructor bindings and `letd` bindings are
    `Γ`'s, as they were (ended, perhaps): what `NoPin`, `DtorSafe` and
    `DbindSafe` read. -/
def FrameOK (Γ Γ' : Ctx) : Prop :=
  (∀ p E, Γ' p = some E → E.mode = .rootb → Γ p = some E) ∧
  (∀ v E, Γ' v = some E → E.dtor = true → ∃ E0, Γ v = some E0 ∧ E0.dtor = true ∧ E0.ty = E.ty ∧
    E0.mode = E.mode ∧ E0.vdeps = E.vdeps) ∧
  (∀ v E, Γ' v = some E → E.dbind = true → ∃ E0, Γ v = some E0 ∧ E0.dbind = true ∧ E0.ty = E.ty ∧
    E0.mode = E.mode ∧ E0.vdeps = E.vdeps)

namespace FrameOK
variable {Γ Γ' : Ctx}

theorem refl (Γ : Ctx) : FrameOK Γ Γ :=
  ⟨fun _ _ h _ => h, fun _ E h _ => ⟨E, h, by assumption, rfl, rfl, rfl⟩,
    fun _ E h _ => ⟨E, h, by assumption, rfl, rfl, rfl⟩⟩

theorem kill (h : FrameOK Γ Γ') (e : Eff) (hb : Bool) (w : Var)
    (hfix : ∀ p E, Γ' p = some E → E.mode = .rootb → killE e hb w E = E) : FrameOK Γ (A2.kill e hb w Γ') := by
  refine ⟨fun p E hp hm => ?_, fun v E hv hd => ?_, fun v E hv hd => ?_⟩
  · simp only [A2.kill] at hp
    obtain ⟨E0, h0, rfl⟩ := Option.map_eq_some_iff.mp hp
    rw [killE_mode] at hm
    rw [hfix p E0 h0 hm]; exact h.1 p E0 h0 hm
  · simp only [A2.kill] at hv
    obtain ⟨E0, h0, rfl⟩ := Option.map_eq_some_iff.mp hv
    rw [killE_dtor] at hd
    obtain ⟨E1, h1, h2, h3, h4, h5⟩ := h.2.1 v E0 h0 hd
    exact ⟨E1, h1, h2, by rw [killE_ty]; exact h3, by rw [killE_mode]; exact h4, by rw [killE_vdeps]; exact h5⟩
  · simp only [A2.kill] at hv
    obtain ⟨E0, h0, rfl⟩ := Option.map_eq_some_iff.mp hv
    rw [killE_dbind] at hd
    obtain ⟨E1, h1, h2, h3, h4, h5⟩ := h.2.2 v E0 h0 hd
    exact ⟨E1, h1, h2, by rw [killE_ty]; exact h3, by rw [killE_mode]; exact h4, by rw [killE_vdeps]; exact h5⟩

theorem setE (h : FrameOK Γ Γ') {w : Var} {E : Entry} (hm : E.mode ≠ .rootb) (hd : E.dtor = false)
    (hdb : E.dbind = false) : FrameOK Γ (A2.setE Γ' w E) := by
  refine ⟨fun p Ep hp hpm => ?_, fun v Ev hv hvd => ?_, fun v Ev hv hvd => ?_⟩
  all_goals first
    | (by_cases hpw : p = w
       · subst hpw; simp only [A2.setE, upd_same, Option.some.injEq] at hp; subst hp; exact absurd hpm hm
       · simp only [A2.setE, upd_ne _ _ hpw] at hp; exact h.1 p Ep hp hpm)
    | (by_cases hvw : v = w
       · subst hvw; simp only [A2.setE, upd_same, Option.some.injEq] at hv; subst hv; simp_all
       · simp only [A2.setE, upd_ne _ _ hvw] at hv; first | exact h.2.1 v Ev hv hvd | exact h.2.2 v Ev hv hvd)

/-- A binding `letd` made stays in the frame, as it was typed. -/
theorem setE' (h : FrameOK Γ Γ') {w : Var} {E : Entry} (hm : E.mode ≠ .rootb) (hd : E.dtor = false)
    (hdb : E.dbind = true → ∃ E0, Γ w = some E0 ∧ E0.dbind = true ∧ E0.ty = E.ty ∧ E0.mode = E.mode ∧
      E0.vdeps = E.vdeps) : FrameOK Γ (A2.setE Γ' w E) := by
  refine ⟨fun p Ep hp hpm => ?_, fun v Ev hv hvd => ?_, fun v Ev hv hvd => ?_⟩
  · by_cases hpw : p = w
    · subst hpw; simp only [A2.setE, upd_same, Option.some.injEq] at hp; subst hp; exact absurd hpm hm
    · simp only [A2.setE, upd_ne _ _ hpw] at hp; exact h.1 p Ep hp hpm
  · by_cases hvw : v = w
    · subst hvw; simp only [A2.setE, upd_same, Option.some.injEq] at hv; subst hv; simp_all
    · simp only [A2.setE, upd_ne _ _ hvw] at hv; exact h.2.1 v Ev hv hvd
  · by_cases hvw : v = w
    · subst hvw; simp only [A2.setE, upd_same, Option.some.injEq] at hv; subst hv; exact hdb hvd
    · simp only [A2.setE, upd_ne _ _ hvw] at hv; exact h.2.2 v Ev hv hvd

theorem upd_none (h : FrameOK Γ Γ') (w : Var) : FrameOK Γ (upd Γ' w none) := by
  refine ⟨fun p Ep hp hpm => ?_, fun v Ev hv hvd => ?_, fun v Ev hv hvd => ?_⟩
  all_goals first
    | (by_cases hpw : p = w
       · subst hpw; simp at hp
       · simp only [upd_ne _ _ hpw] at hp; exact h.1 p Ep hp hpm)
    | (by_cases hvw : v = w
       · subst hvw; simp at hv
       · simp only [upd_ne _ _ hvw] at hv; first | exact h.2.1 v Ev hv hvd | exact h.2.2 v Ev hv hvd)

theorem killNames (h : FrameOK Γ Γ') (ds : List Dep)
    (hfix : ∀ p E, Γ' p = some E → E.mode = .rootb → ∀ d ∈ ds, hits d.kind.bound false d.root E = false) :
    FrameOK Γ (A2.killNames ds Γ') := by
  refine ⟨fun p E hp hm => ?_, fun v E hv hd => ?_, fun v E hv hd => ?_⟩
  · rw [RSetup.killNames_eq] at hp
    obtain ⟨E0, h0, rfl⟩ := Option.map_eq_some_iff.mp hp
    have hm0 : E0.mode = .rootb := by unfold RSetup.killAll at hm; split at hm <;> exact hm
    rw [killAll_id (hfix p E0 h0 hm0)]; exact h.1 p E0 h0 hm0
  all_goals
    rw [RSetup.killNames_eq] at hv
    obtain ⟨E0, h0, rfl⟩ := Option.map_eq_some_iff.mp hv
    unfold RSetup.killAll at hd ⊢
    split <;> split at hd <;> first
      | (obtain ⟨E1, h1, h2, h3, h4, h5⟩ := h.2.1 v E0 h0 hd; exact ⟨E1, h1, h2, h3, h4, h5⟩)
      | (obtain ⟨E1, h1, h2, h3, h4, h5⟩ := h.2.2 v E0 h0 hd; exact ⟨E1, h1, h2, h3, h4, h5⟩)

/-- A binding the store has none of: no borrowed parameter changes it by name. -/
theorem noPin_fresh {m : Mem} (hi : MInv m Γ) (h : FrameOK Γ Γ') {w : Var} (hw : Γ w = none) : NoPin Γ' w := by
  intro p E hp hm d hd _ hr
  have h0 := h.1 p E hp hm
  obtain ⟨Er, hEr, _⟩ := hi.wf p E h0 (hi.rootbLive p E h0 hm) (Or.inr hm) d.root
    (List.mem_map_of_mem (f := Dep.root) hd)
  rw [hr, hw] at hEr; cases hEr

theorem noPin (h : FrameOK Γ Γ') {w : Var} (hp : NoPin Γ w) : NoPin Γ' w :=
  fun p E hp' hm => hp p E (h.1 p E hp' hm) hm

theorem dtorSafe (h : FrameOK Γ Γ') {e : Eff} {hb : Bool} {w : Var} (hd : DtorSafe Γ e hb w) :
    DtorSafe Γ' e hb w := by
  intro v E hv hvd hos
  obtain ⟨E0, h0, h1, h2, h3, h4⟩ := h.2.1 v E hv hvd
  have := hd v E0 h0 h1 (by rw [h3]; exact hos)
  unfold hitsMem at this ⊢; rw [h2, h3, h4] at this; exact this

theorem dbindSafe (h : FrameOK Γ Γ') {w : Var} (hd : DbindSafe Γ w) : DbindSafe Γ' w := by
  intro v E hv hvd hos hn dd hdd hnm
  obtain ⟨E0, h0, h1, h2, h3, h4⟩ := h.2.2 v E hv hvd
  exact hd v E0 h0 h1 (by rw [h3]; exact hos) (by rw [h2, h3]; exact hn) dd (by rw [h4]; exact hdd) hnm

theorem endOK_fresh {m : Mem} (hi : MInv m Γ) (h : FrameOK Γ Γ') {w : Var} (hw : Γ w = none) : EndOK Γ' w :=
  ⟨h.noPin_fresh hi hw, h.dtorSafe (DtorSafe.of_fresh hi.wf hw _ _), h.dbindSafe (DbindSafe.of_fresh hi.wf hw)⟩

end FrameOK

/-- The hand-over's context against the interface call's: the bindings it
    adds (`x`, the environment's `y`, the package moved out) are no borrowed
    parameter and run no destructor, so every pin and destructor the call's
    context answers for is the same (AGORA-927). -/
theorem handCtx_frameOK {Γ : Ctx} {c x y : Var} {Ec E0 : Entry} {te : Ty} (hto : te.owning = true)
    (hEc : Ec.mode ≠ .rootb) (hdbc : Ec.dbind = false) (hE0d : E0.dtor = false) (hE0m : E0.mode ≠ .rootb)
    (hE0b : E0.dbind = false) :
    FrameOK (kill .replace false c Γ) (handCtx Γ c x Ec te y E0) := by
  have hEy := compE_owning Ec hto
  refine ⟨fun p E hp hm => ?_, fun v E hv hd => ?_, fun v E hv hd => ?_⟩
  · simp only [handCtx, setE, upd] at hp
    split at hp
    · cases hp; exact absurd hm hE0m
    split at hp
    · cases hp; rw [hEy] at hm; cases hm
    split at hp
    · cases hp; exact absurd hm hEc
    exact hp
  · simp only [handCtx, setE, upd] at hv
    split at hv
    · cases hv; rw [hE0d] at hd; cases hd
    split at hv
    · cases hv; rw [hEy] at hd; cases hd
    split at hv
    · cases hv; cases hd
    exact ⟨E, hv, hd, rfl, rfl, rfl⟩
  · simp only [handCtx, setE, upd] at hv
    split at hv
    · cases hv; rw [hE0b] at hd; cases hd
    split at hv
    · cases hv; rw [hEy] at hd; cases hd
    split at hv
    · cases hv; simp [hdbc] at hd
    exact ⟨E, hv, hd, rfl, rfl, rfl⟩

/-- A borrowed parameter is reached by no change a call's closures make by
    name: what it borrows from is lent out, which such a binding is not, and
    what it holds by name changes no more than the name says. -/
theorem rootb_names {Γ : Ctx} {F : List Var} (hanch : RootbAnchF Γ F) {ds : List Dep}
    (hds : ∀ d ∈ ds, d.root ∉ F ∧ d.kind.bound ≠ .replace) :
    ∀ p E, Γ p = some E → E.mode = .rootb → ∀ d ∈ ds, hits d.kind.bound false d.root E = false := by
  intro p E hp hm d hd
  obtain ⟨hF, hbr⟩ := hds d hd
  refine RSetup.hits_false_of fun d' hd' hr' => ?_
  by_cases hb0 : d'.kind.bound = .none
  · exact absurd (hr' ▸ hanch p E hp hm d' hd' hb0) hF
  · exact RSetup.kills_isName hbr _ (RSetup.isName_of_bound hb0)

/-- Every entry of `Γ'` is rooted in `Γ`: a binding `Γ` has none of ends nothing. -/
def AllRooted (Γ Γ' : Ctx) : Prop := ∀ v E, Γ' v = some E → Rooted Γ E

namespace AllRooted
variable {Γ Γ' : Ctx}

theorem kill_fresh (h : AllRooted Γ Γ') {w : Var} (hw : Γ w = none) (e : Eff) (hb : Bool) :
    A2.kill e hb w Γ' = Γ' := by
  funext v
  simp only [A2.kill]
  cases hv : Γ' v with
  | none => rfl
  | some E => simp only [Option.map_some, (h v E hv).killE_fresh hw]

theorem kill (h : AllRooted Γ Γ') (e : Eff) (hb : Bool) (w : Var) : AllRooted Γ (A2.kill e hb w Γ') := by
  intro v E hv
  simp only [A2.kill] at hv
  obtain ⟨E0, h0, rfl⟩ := Option.map_eq_some_iff.mp hv
  exact (h v E0 h0).killE e hb w

theorem setE (h : AllRooted Γ Γ') {w : Var} {E : Entry} (hE : Rooted Γ E) : AllRooted Γ (A2.setE Γ' w E) := by
  intro v Ev hv
  by_cases hvw : v = w
  · subst hvw; simp only [A2.setE, upd_same, Option.some.injEq] at hv; subst hv; exact hE
  · simp only [A2.setE, upd_ne _ _ hvw] at hv; exact h v Ev hv

theorem upd_none (h : AllRooted Γ Γ') (w : Var) : AllRooted Γ (upd Γ' w none) := by
  intro v Ev hv
  by_cases hvw : v = w
  · subst hvw; simp at hv
  · simp only [upd_ne _ _ hvw] at hv; exact h v Ev hv

theorem killNames (h : AllRooted Γ Γ') (ds : List Dep) : AllRooted Γ (A2.killNames ds Γ') := by
  intro v E hv
  rw [RSetup.killNames_eq] at hv
  obtain ⟨E0, h0, rfl⟩ := Option.map_eq_some_iff.mp hv
  exact (h v E0 h0).killAll ds

end AllRooted

theorem Rooted.of_dead {Γ : Ctx} {E : Entry} (h : E.live = false) : Rooted Γ E := Or.inl h

theorem Rooted.of_roots {Γ : Ctx} {E : Entry} (h : ∀ d ∈ E.vdeps, (Γ d.root).isSome) : Rooted Γ E :=
  Or.inr (Or.inr h)

theorem outHeld_nil {Γ : Ctx} {fn : Fn} (h : fn.outHolds = []) (args : List Var) (i : Nat) :
    outHeld Γ fn args i = [] := by
  simp [outHeld, h]

/-- What `x := r` takes from the inner call's result: a move of an owned
    result, a copy of a lent one. -/
theorem hand_res {Γr : Ctx} {F : List Var} {r : Var} {E' : Entry} (hr : Γr r = some E') (hl : E'.live = true)
    (hrF : r ∉ F) (hpin : NoPin Γr r) (hds : DtorSafe Γr .replace false r) (hm : E'.mode = .own ∨ E'.mode = .bor) :
    ∃ Er Γ2, RhsT Γr F (.var r) Er Γ2 ∧ Er.mode = E'.mode ∧ Er.ty = E'.ty ∧ Er.live = true ∧
      Er.path ⊆ E'.path ∧ Er.held ⊆ E'.held ∧ Er.dtor = false ∧ Er.dbind = false ∧
      (Γ2 = setE (kill .replace false r Γr) r { E' with live := false, dtor := false } ∨ Γ2 = Γr) := by
  rcases hm with hm | hm
  · exact ⟨_, _, RhsT.moveOwn hr hl hm hrF hpin hds, hm.symm, rfl, rfl, List.nil_subset _,
      List.Subset.refl _, rfl, rfl, Or.inl rfl⟩
  · refine ⟨_, _, RhsT.copyBor hr hl hm, rfl, rfl, hl, List.Subset.refl _, List.Subset.refl _, rfl, rfl, Or.inr rfl⟩

/-- The post-context of a call whose first parameter is `inout` (AGORA-927:
    with parameters beside it). -/
theorem callPost_cons {Γ : Ctx} {fn : Fn} {b : Eff} {t : Ty} {ps : List (PMode × Ty)}
    (hps : fn.params = (.inout b, t) :: ps) (a : Var) (zs : List Var) :
    callPost Γ fn (a :: zs) = A2.killNames (mutNames Γ (a :: zs)) (callPostAux Γ fn (a :: zs) ps zs 1
      (setE (kill b t.elem.holdsView a Γ) a
      { argE Γ a with heldFresh := (if t.holdsView then false else (argE Γ a).heldFresh), held := if t.holdsView then
          (argE Γ a).held ++ outHeld Γ fn (a :: zs) 0 ++ heldOfArgs Γ (a :: zs) else (argE Γ a).held })) := by
  simp only [callPost, hps, callPostAux]

/-- A binding outside `X` set on both sides, the run-time form's saying no less. -/
theorem HandRel.set2 {Γ : Ctx} {X : List Var} {Γd Γs : Ctx} (h : HandRel Γ X Γd Γs) {w : Var} (hw : w ∉ X)
    {Ed Es : Entry} (hwk : EntryWeaker Ed Es) (hR : Rooted Γ Ed) (hfx : ¬ Ed.fixed) :
    HandRel Γ X (setE Γd w Ed) (setE Γs w Es) := by
  intro v hv
  by_cases hvw : v = w
  · subst hvw
    refine ⟨by simp [setE], fun E1 E2 h1 h2 => ?_⟩
    simp only [setE, upd_same, Option.some.injEq] at h1 h2
    subst h1 h2
    exact ⟨hwk, hR, fun hf => absurd hf hfx⟩
  · simp only [setE, upd_ne _ _ hvw]; exact h v hv

/-- AGORA-927: **the parameters beside the receiver, on both sides**: the
    run-time form's call and the interface's take the same arguments past the
    receiver, of the same entries; each side moves and changes them alike, the
    run-time form's handing each `inout` one no more than the source's. -/
theorem handRel_tail {Γ : Ctx} {X : List Var} {Γ0d Γ0s : Ctx} {fd fs' : Fn} {ad as' : List Var}
    (hod : fd.outHolds = []) (hos : fs'.outHolds = [])
    (hH : heldOfArgs Γ0d ad ⊆ heldOfArgs Γ0s as')
    (hHR : ∀ d ∈ heldOfArgs Γ0d ad, (Γ d.root).isSome) :
    ∀ (ps : List (PMode × Ty)) (zs : List Var) (i : Nat) (Γd Γs : Ctx),
      (∀ pa ∈ ps.zip zs, pa.1.1.moves = true → pa.2 ∉ X ∧ argE Γ0d pa.2 = argE Γ0s pa.2 ∧
        ¬ (argE Γ0d pa.2).fixed ∧ (∀ b, pa.1.1 = .inout b → (argE Γ0d pa.2).dbind = false) ∧
        (∀ d ∈ (argE Γ0d pa.2).vdeps, (Γ d.root).isSome) ∧
        ∀ b, (pa.1.1 = .sink ∧ b = .replace ∨ pa.1.1 = .inout b) → ∀ hb v E, Γ v = some E → E.fixed →
          killE b hb pa.2 E = E) →
      HandRel Γ X Γd Γs →
      HandRel Γ X (callPostAux Γ0d fd ad ps zs i Γd) (callPostAux Γ0s fs' as' ps zs i Γs) := by
  intro ps
  induction ps with
  | nil => intro zs i Γd Γs _ h; cases zs <;> exact h
  | cons p ps ih =>
    intro zs i Γd Γs hz h
    obtain ⟨pm, t⟩ := p
    cases zs with
    | nil => cases pm <;> exact h
    | cons a zs =>
      have hz' := fun pa (hpa : pa ∈ ps.zip zs) => hz pa (by simp [hpa])
      cases pm with
      | inp => exact ih zs (i + 1) Γd Γs hz' h
      | sink =>
        obtain ⟨hX, hEq, hnf, _, _, hfix⟩ := hz ((.sink, t), a) (by simp) rfl
        simp only [callPostAux]
        refine ih zs (i + 1) _ _ hz' ?_
        rw [← hEq]
        exact (h.kill2 .replace false a (hfix .replace (Or.inl ⟨rfl, rfl⟩) false)).set2 hX (EntryWeaker.refl _)
          (Rooted.of_dead rfl) (fun hf => hnf hf)
      | inout b =>
        obtain ⟨hX, hEq, hnf, hdb, hR, hfix⟩ := hz ((.inout b, t), a) (by simp) rfl
        simp only [callPostAux]
        refine ih zs (i + 1) _ _ hz' ?_
        rw [← hEq, outHeld_nil hod, outHeld_nil hos]
        have hdb0 := hdb b rfl
        refine (h.kill2 b t.elem.holdsView a (hfix b (Or.inr rfl) _)).set2 hX ?_ ?_ (fun hf => hnf hf)
        · refine RSetup.EntryWeaker.mk' rfl rfl (fun hf => hnf hf) rfl (fun _ => List.Subset.refl _) ?_
            (fun h => h) rfl (fun h => Or.inl h) (fun h => by simp_all) (fun _ _ _ h => ⟨h, List.Subset.refl _⟩)
            (fun _ _ h => h)
          intro d hd
          by_cases hv : t.holdsView = true
          · simp only [hv, ↓reduceIte, List.append_nil, List.mem_append] at hd ⊢
            rcases hd with h1 | h1
            · exact Or.inl h1
            · exact Or.inr (hH h1)
          · simp only [hv, Bool.false_eq_true, ↓reduceIte] at hd ⊢; exact hd
        · refine Rooted.of_roots fun d hd => ?_
          by_cases hv : t.holdsView = true
          · simp only [Entry.vdeps, hv, ↓reduceIte, List.append_nil, List.mem_append] at hd
            rcases hd with h1 | h1 | h1
            · exact hR d (List.mem_append_left _ h1)
            · exact hR d (List.mem_append_right _ h1)
            · exact hHR d h1
          · simp only [Entry.vdeps, hv, Bool.false_eq_true, ↓reduceIte] at hd
            exact hR d hd

/-- What no parameter the call moves or changes ends, it leaves as it was. -/
theorem callPostAux_keepAt {Γ0 : Ctx} {fn : Fn} {args : List Var} {y : Var} {o : Option Entry} :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (Γ : Ctx),
      (∀ pa ∈ ps.zip as, pa.1.1.moves = true → pa.2 ≠ y ∧
        ∀ b, (pa.1.1 = .sink ∧ b = .replace ∨ pa.1.1 = .inout b) → ∀ hb, o.map (killE b hb pa.2) = o) →
      Γ y = o → callPostAux Γ0 fn args ps as i Γ y = o := by
  intro ps
  induction ps with
  | nil => intro as i Γ _ hp; cases as <;> exact hp
  | cons q ps ih =>
    intro as i Γ hz hp
    obtain ⟨pm, t⟩ := q
    cases as with
    | nil => cases pm <;> exact hp
    | cons a as =>
      have hz' := fun pa (hpa : pa ∈ ps.zip as) => hz pa (by simp [hpa])
      cases pm with
      | inp => exact ih as (i + 1) Γ hz' hp
      | sink =>
        obtain ⟨hay, hk⟩ := hz ((.sink, t), a) (by simp) rfl
        apply ih as (i + 1) _ hz'
        simp only [setE, upd_ne _ _ hay.symm, A2.kill, hp]
        exact hk .replace (Or.inl ⟨rfl, rfl⟩) false
      | inout b =>
        obtain ⟨hay, hk⟩ := hz ((.inout b, t), a) (by simp) rfl
        apply ih as (i + 1) _ hz'
        simp only [setE, upd_ne _ _ hay.symm, A2.kill, hp]
        exact hk b (Or.inr rfl) _

/-- The source's side: a binding the call does not move or change it only
    ends, so an entry not fixed that says no less than it before says no less
    than it after. -/
theorem callPostAux_weakR {Γ0 : Ctx} {fn : Fn} {args : List Var} {y : Var} {Ed : Entry} (hnf : ¬ Ed.fixed) :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (Γ : Ctx),
      (∀ pa ∈ ps.zip as, pa.1.1.moves = true → pa.2 ≠ y) →
      ∀ E0, Γ y = some E0 → EntryWeaker Ed E0 →
      ∃ E, callPostAux Γ0 fn args ps as i Γ y = some E ∧ EntryWeaker Ed E := by
  intro ps
  induction ps with
  | nil => intro as i Γ _ E0 hp hw; cases as <;> exact ⟨E0, hp, hw⟩
  | cons q ps ih =>
    intro as i Γ hz E0 hp hw
    obtain ⟨pm, t⟩ := q
    cases as with
    | nil => cases pm <;> exact ⟨E0, hp, hw⟩
    | cons a as =>
      have hz' := fun pa (hpa : pa ∈ ps.zip as) => hz pa (by simp [hpa])
      cases pm with
      | inp => exact ih as (i + 1) Γ hz' E0 hp hw
      | sink =>
        have hay := hz ((.sink, t), a) (by simp) rfl
        exact ih as (i + 1) _ hz' (killE .replace false a E0)
          (by simp only [setE, upd_ne _ _ hay.symm, A2.kill, hp, Option.map_some])
          (hw.killR fun hf => absurd hf hnf)
      | inout b =>
        have hay := hz ((.inout b, t), a) (by simp) rfl
        exact ih as (i + 1) _ hz' (killE b t.elem.holdsView a E0)
          (by simp only [setE, upd_ne _ _ hay.symm, A2.kill, hp, Option.map_some])
          (hw.killR fun hf => absurd hf hnf)

/-- What a call's arguments hand a binding: of an argument not an integer,
    what its views reach in memory (of every kind), or the names it holds. -/
theorem mem_heldOfArgs {Γ : Ctx} {args : List Var} {d : Dep} (h : d ∈ heldOfArgs Γ args) :
    ∃ a ∈ args, (argE Γ a).ty ≠ .int ∧ ((d.kind.isName = false ∧ ∃ d0 ∈ memDeps (argE Γ a).held, d.root = d0.root) ∨
      (d.kind.isName = true ∧ d ∈ (argE Γ a).vdeps)) := by
  simp only [heldOfArgs, List.mem_append] at h
  rcases h with h | h
  · have hn := compAll_argMem_notName h
    obtain ⟨d0, hd0, k, _, rfl⟩ := mem_compAll.mp h
    obtain ⟨a, ha, hni, hm⟩ := mem_argMem.mp hd0
    exact ⟨a, ha, hni, Or.inl ⟨hn, d0, hm, rfl⟩⟩
  · simp only [argNames, List.mem_flatMap] at h
    obtain ⟨a, ha, hda⟩ := h
    split at hda
    · cases hda
    · exact ⟨a, ha, by assumption, Or.inr ⟨(List.mem_filter.mp hda).2, (List.mem_filter.mp hda).1⟩⟩

/-- The pins, destructors and `letd` bindings past the receiver: a call's
    parameters beside it move or change no borrowed parameter, and what they
    leave is no destructor binding but one the store had as it is. -/
theorem FrameOK.callPostAux_tail {Γ Γ0 : Ctx} {fn : Fn} {args : List Var} :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (Γ' : Ctx),
      (∀ pa ∈ ps.zip as, pa.1.1.moves = true → (argE Γ0 pa.2).mode ≠ .rootb ∧
        (∀ b, pa.1.1 = .inout b → (argE Γ0 pa.2).dbind = false ∧ (argE Γ0 pa.2).dtor = false) ∧
        ((argE Γ0 pa.2).dbind = true → ∃ E0, Γ pa.2 = some E0 ∧ E0.dbind = true ∧ E0.ty = (argE Γ0 pa.2).ty ∧
          E0.mode = (argE Γ0 pa.2).mode ∧ E0.vdeps = (argE Γ0 pa.2).vdeps) ∧
        ∀ b, (pa.1.1 = .sink ∧ b = .replace ∨ pa.1.1 = .inout b) → ∀ hb v E, Γ v = some E → E.fixed →
          killE b hb pa.2 E = E) →
      FrameOK Γ Γ' → FrameOK Γ (callPostAux Γ0 fn args ps as i Γ') := by
  intro ps
  induction ps with
  | nil => intro as i Γ' _ h; cases as <;> exact h
  | cons p ps ih =>
    intro as i Γ' hz h
    obtain ⟨pm, t⟩ := p
    cases as with
    | nil => cases pm <;> exact h
    | cons a as =>
      have hz' := fun pa (hpa : pa ∈ ps.zip as) => hz pa (by simp [hpa])
      cases pm with
      | inp => exact ih as (i + 1) Γ' hz' h
      | sink =>
        obtain ⟨hm, _, hdb, hfix⟩ := hz ((.sink, t), a) (by simp) rfl
        simp only [callPostAux]
        refine ih as (i + 1) _ hz' ?_
        exact (h.kill .replace false a fun p E hp hpm =>
          hfix .replace (Or.inl ⟨rfl, rfl⟩) false p E (h.1 p E hp hpm) (Or.inl hpm)).setE' hm rfl hdb
      | inout b =>
        obtain ⟨hm, hio, _, hfix⟩ := hz ((.inout b, t), a) (by simp) rfl
        obtain ⟨hdb, hdt⟩ := hio b rfl
        simp only [callPostAux]
        refine ih as (i + 1) _ hz' ?_
        exact (h.kill b t.elem.holdsView a fun p E hp hpm =>
          hfix b (Or.inr rfl) _ p E (h.1 p E hp hpm) (Or.inl hpm)).setE hm hdt hdb

/-! ### The run-time form, typed -/

/-- Roots of a sublist are roots of the list. -/
theorem roots_sub_of {A B : List Dep} (h : A ⊆ B) {r : Var} (hr : r ∈ roots A) : r ∈ roots B := by
  simp only [roots, List.mem_map] at hr ⊢; obtain ⟨d, hd, rfl⟩ := hr; exact ⟨d, h hd, rfl⟩

theorem memDeps_sub_of {A B : List Dep} (h : A ⊆ B) : memDeps A ⊆ memDeps B := fun _d hd =>
  List.mem_filter.mpr ⟨h (List.mem_filter.mp hd).1, (List.mem_filter.mp hd).2⟩

/-- **What the code's call's closures may change, the interface's may**: the
    environment's binding depends on no more than the package, and each
    argument beside it has the same entry in both contexts (`callT_hand`,
    `hand_typed`). -/
theorem mutNames_hand {Γh Γk : Ctx} {y c : Var} {zs : List Var}
    (hy : (argE Γh y).ty ≠ .int) (hc : (argE Γk c).ty ≠ .int)
    (hyv : (argE Γh y).vdeps ⊆ (argE Γk c).vdeps)
    (hz : ∀ z ∈ zs, argE Γh z = argE Γk z) :
    ∀ d ∈ mutNames Γh (y :: zs), d ∈ mutNames Γk (c :: zs) := by
  intro d hd
  simp only [mutNames, argNames, List.flatMap_cons, List.mem_filter, List.mem_append] at hd ⊢
  obtain ⟨hd1, hd2⟩ := hd
  refine ⟨?_, hd2⟩
  rcases hd1 with h | h
  · left
    simp only [hy, ↓reduceIte] at h; simp only [hc, ↓reduceIte]
    exact List.mem_filter.mpr ⟨hyv (List.mem_filter.mp h).1, (List.mem_filter.mp h).2⟩
  · right
    simp only [List.mem_flatMap] at h ⊢
    obtain ⟨z, hz', hdz⟩ := h
    exact ⟨z, hz', by rw [← hz z hz']; exact hdz⟩

/-! ### What a hand-over with parameters beside the receiver refuses (AGORA-927) -/

/-- AGORA-927, refused: **the package passed again beside itself**. The
    interface's call changes the package, and `CallT` passes a changed
    argument once. -/
theorem callcE_arg_is_pkg {P : Prog} {Γ Γ1 : Ctx} {F : List Var} {σ : Nat} {c : Var} {zs : List Var}
    {E : Entry} {sig : Fn} {b : Eff} {t : Ty} {ps : List (PMode × Ty)}
    (hσ : P[σ]? = some sig) (hsp : sig.params = (.inout b, t) :: ps) (hz : c ∈ zs) :
    ¬ CallT P (kill .replace false c Γ) F σ (c :: zs) E Γ1 := by
  rintro ⟨sig', hσ', hlen, hargs, _⟩
  rw [hσ] at hσ'; cases hσ'
  obtain ⟨k, hk, hkc⟩ := List.getElem_of_mem hz
  have hk1 : k + 1 < sig.params.length := by simp [hsp] at hlen ⊢; omega
  obtain ⟨_, _, _, _, hmv, _⟩ := hargs 0 (by simp [hsp])
  have hne := ((hmv (by simp [hsp, PMode.moves])).2.2.2.2 (k + 1) hk1 (by omega)).1
  simp [List.getD, List.getElem?_eq_getElem hk, hkc] at hne

/-- AGORA-927, refused: **an argument beside the receiver that views the
    package**, or what the package's environment holds through it (a view
    into a package is rooted at the package). The interface's call changes
    the package, and `CallT` keeps every other argument from reaching a
    changed one in memory. -/
theorem callcE_arg_views_pkg {P : Prog} {Γ Γ1 : Ctx} {F : List Var} {σ : Nat} {c z : Var} {zs : List Var}
    {E : Entry} {sig : Fn} {b : Eff} {t : Ty} {ps : List (PMode × Ty)}
    (hσ : P[σ]? = some sig) (hsp : sig.params = (.inout b, t) :: ps) (hz : z ∈ zs)
    (hv : ∃ d ∈ (argE (kill .replace false c Γ) z).vdeps, d.root = c ∧ d.kind.isName = false) :
    ¬ CallT P (kill .replace false c Γ) F σ (c :: zs) E Γ1 := by
  rintro ⟨sig', hσ', hlen, hargs, _⟩
  rw [hσ] at hσ'; cases hσ'
  obtain ⟨k, hk, rfl⟩ := List.getElem_of_mem hz
  have hk1 : k + 1 < sig.params.length := by simp [hsp] at hlen ⊢; omega
  obtain ⟨_, _, _, _, hmv, _⟩ := hargs 0 (by simp [hsp])
  have hr := ((hmv (by simp [hsp, PMode.moves])).2.2.2.2 (k + 1) hk1 (by omega)).2.1
  have hg : (c :: zs).getD (k + 1) 0 = zs[k] := by simp [List.getD, List.getElem?_eq_getElem hk]
  simp only [List.getD_cons_zero] at hr
  rw [hg] at hr
  obtain ⟨d, hd, hdr, hdn⟩ := hv
  exact hr (List.mem_map.mpr ⟨d, List.mem_filter.mpr ⟨hd, by simp [hdn]⟩, hdr⟩)

/-- AGORA-927, refused: **a package that views an argument the method moves
    or changes**: the call changes that argument, and `CallT` keeps the
    package (as every other argument) from reaching it in memory, so the
    environment the code is handed views nothing the code changes beside
    it. -/
theorem callcE_pkg_views_arg {P : Prog} {Γ Γ1 : Ctx} {F : List Var} {σ : Nat} {c : Var} {zs : List Var}
    {E : Entry} {sig : Fn} {b : Eff} {t : Ty} {ps : List (PMode × Ty)} {k : Nat}
    (hσ : P[σ]? = some sig) (hsp : sig.params = (.inout b, t) :: ps) (hk : k < ps.length)
    (hm : ps[k].1.moves = true)
    (hv : ∃ d ∈ (argE (kill .replace false c Γ) c).vdeps, d.root = zs.getD k 0 ∧ d.kind.isName = false) :
    ¬ CallT P (kill .replace false c Γ) F σ (c :: zs) E Γ1 := by
  rintro ⟨sig', hσ', hlen, hargs, _⟩
  rw [hσ] at hσ'; cases hσ'
  have hk1 : k + 1 < sig.params.length := by simp [hsp]; omega
  have hpe : sig.params[k + 1]'hk1 = ps[k] := by simp [hsp]
  obtain ⟨_, _, _, _, hmv, _⟩ := hargs (k + 1) hk1
  rw [hpe] at hmv
  have hr := ((hmv hm).2.2.2.2 0 (by simp [hsp]) (by omega)).2.1
  simp only [List.getD_cons_zero, List.getD_cons_succ] at hr
  obtain ⟨d, hd, hdr, hdn⟩ := hv
  exact hr (List.mem_map.mpr ⟨d, List.mem_filter.mpr ⟨hd, by simp [hdn]⟩, hdr⟩)

/-- AGORA-927: **no argument beside the receiver reaches the environment's
    binding**: `y` is fresh, and every dependency of such an argument is a
    binding's (`StmtT.callcE`'s premise, which holds of an integer argument
    too), so none is `y`'s. With `CallT`'s own premise that the package
    reaches a moved argument only by a name of its bound, `y` and the other
    arguments stay apart as the package and they were. -/
theorem hand_args_apart {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {c x : Var} {Ec : Entry} {te : Ty} {E0 : Entry}
    {z : Var} (hzc : z ≠ c) (hzx : z ≠ x) (hzy : z ≠ m.nv)
    (hzb : ∀ d ∈ (argE Γ z).vdeps, (Γ d.root).isSome) :
    ∀ d ∈ (argE (handCtx Γ c x Ec te m.nv E0) z).vdeps, d.root ≠ m.nv := by
  intro d hd e
  have hd' : d ∈ (argE Γ z).vdeps := by
    simp only [argE] at hd ⊢; rw [handCtx_other hzx hzy hzc] at hd
    cases h : Γ z <;> simp_all [kill, killE_vdeps]
  have := hzb d hd'
  rw [e] at this
  exact Nat.lt_irrefl _ (hi.nvSt m.nv (by rw [← hi.dom]; exact this))

/-- **The code's call, typed from the interface's** (A2-envhand): where the
    interface's call on the package `c` (its `inout b` receiver) and the
    arguments beside it, `zs` (AGORA-927), is typed after every dependency on
    `c` ended, the code's call on the environment's binding `y` (the code's
    receiver, `inout b` at the environment's type) and the same `zs` is
    typed in the context the hand-over leaves. `y` holds what `c` held, and
    is fresh; each extra argument keeps its entry (it is not `x`, `y` or the
    package), and reaches nothing of `y` (`hand_args_apart`), so every
    premise the interface's call met for the package it meets for `y`. -/
theorem callT_hand {P : Prog} {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ) (hFlt : ∀ v ∈ F, v < m.nv)
    {c x : Var} {Ec E : Entry} {Γ1 : Ctx} {σ f : Nat} {sig fn : Fn} {b : Eff} {ms : List Nat} {q : Cross}
    {te : Ty} {zs : List Var} {ps : List (PMode × Ty)} (hc : Γ c = some Ec) (htc : Ec.ty = .fn ms q)
    (hx : Γ x = none) (hxn : x < m.nv)
    (hcT : CallT P (kill .replace false c Γ) F σ (c :: zs) E Γ1) (hσ : P[σ]? = some sig)
    (hsp : sig.params = (.inout b, .fn ms q) :: ps)
    (hf : P[f]? = some fn) (hps : fn.params = (.inout b, te) :: ps) (hto : te.owning = true) (hnt : ¬ ThruFn P f)
    (hzb : ∀ z ∈ zs, ∀ d ∈ (argE Γ z).vdeps, (Γ d.root).isSome)
    {E0 : Entry} (hE0d : E0.dtor = false) (hE0m : E0.mode ≠ .rootb) (hE0b : E0.dbind = false) :
    CallT P (handCtx Γ c x Ec te m.nv E0) F f (m.nv :: zs)
      (callRes (handCtx Γ c x Ec te m.nv E0) fn (m.nv :: zs))
      (callPost (handCtx Γ c x Ec te m.nv E0) fn (m.nv :: zs)) := by
  obtain ⟨sig', hσ', hlen, hargs, hnf, hds, _, _, _⟩ := hcT
  rw [hσ] at hσ'; cases hσ'
  have hτ : Ec.ty ≠ .int := by rw [htc]; simp
  have hlenz : zs.length = ps.length := by simpa [hsp] using hlen
  obtain ⟨Ea, hEa, hla, hok, hmv0, _⟩ := hargs 0 (by simp [hsp])
  simp only [List.getD_cons_zero, kill, hc, Option.map_some, Option.some.injEq] at hEa
  subst hEa
  obtain ⟨hlc, hnc⟩ := kill_live_self hla hτ
  have hcan : canDo Ec.mode b := by
    simp only [hsp, List.getElem_cons_zero, paramOK] at hok
    obtain ⟨_, hcan, _⟩ := hok
    rwa [killE_mode] at hcan
  have hmc : Ec.mode ≠ .rootb := by rcases hcan with h | ⟨b', h, _⟩ <;> rw [h] <;> simp
  have hos : Ec.mode.ownSlot = true := hcan.ownSlot
  have hck : argE (kill .replace false c Γ) c = killE .replace false c Ec := by
    simp [argE, kill, hc]
  have hcn : c < m.nv := hi.nvSt c (by rw [← hi.dom, hc]; rfl)
  have hxy : x ≠ m.nv := fun e => by rw [e] at hxn; exact Nat.lt_irrefl _ hxn
  have hxc : x ≠ c := fun e => by rw [e, hc] at hx; cases hx
  have hyc : m.nv ≠ c := fun e => by rw [← e] at hcn; exact Nat.lt_irrefl _ hcn
  have hdbc : Ec.dbind = false := by
    have := hds.2.2 0 (by simp [hsp]) b (by simp [hsp]) (killE .replace false c Ec) (by simp [kill, hc])
    rwa [killE_dbind] at this
  have hEy : compE Ec te = ⟨te, .own, true, [], ownHeld true te Ec.held, false, false, false, false⟩ :=
    compE_owning Ec hto
  have hy : handCtx Γ c x Ec te m.nv E0 m.nv = some (compE Ec te) := handCtx_y hxy
  have hyE : argE (handCtx Γ c x Ec te m.nv E0) m.nv = compE Ec te := by
    simp only [argE, hy, Option.getD_some]
  have hEyv : (compE Ec te).vdeps ⊆ Ec.vdeps := by
    intro d hd
    rw [hEy] at hd
    simp only [Entry.vdeps, Mode.ownSlot, ↓reduceIte, List.nil_append] at hd
    simp only [Entry.vdeps, hos, ↓reduceIte, List.nil_append]
    exact ownHeld_sub _ _ _ hd
  have hyroot : ∀ d ∈ (compE Ec te).vdeps, d.root ≠ m.nv := fun d hd e => by
    have := hi.root_lt hc hlc (Or.inl hτ) (List.mem_map_of_mem (f := Dep.root) (hEyv hd))
    rw [e] at this; exact Nat.lt_irrefl _ this
  have hEyt : (compE Ec te).ty ≠ .int := by
    rw [hEy]; intro h; simp only at h; subst h; simp [Ty.owning] at hto
  have hother : ∀ v, v ≠ x → v ≠ m.nv → v ≠ c →
      handCtx Γ c x Ec te m.nv E0 v = kill .replace false c Γ v :=
    fun v h1 h2 h3 => handCtx_other h1 h2 h3
  have hFr := handCtx_frameOK (Γ := Γ) (c := c) (x := x) (y := m.nv) hto hmc hdbc hE0d hE0m hE0b
  have hmvc := hmv0 (by simp [hsp, PMode.moves])
  -- a bound binding is neither `x` nor the fresh `y`
  have hbnd : ∀ v, (Γ v).isSome → v ≠ x ∧ v ≠ m.nv := fun v hv =>
    ⟨fun e => (by rw [e, hx] at hv; cases hv),
     fun e => (by rw [e] at hv; exact Nat.lt_irrefl _ (hi.nvSt m.nv (by rw [← hi.dom]; exact hv)))⟩
  -- each extra argument: not the package, `x` or `y`; its entry is the call's
  have hzi : ∀ j, j < zs.length → zs.getD j 0 ≠ c ∧ zs.getD j 0 ≠ x ∧ zs.getD j 0 ≠ m.nv := by
    intro j hj
    have hj1 : j + 1 < sig.params.length := by simp [hsp]; omega
    obtain ⟨Ez, hEz, _⟩ := hargs (j + 1) hj1
    simp only [List.getD_cons_succ] at hEz
    have hne := (hmvc.2.2.2.2 (j + 1) hj1 (by omega)).1
    simp only [List.getD_cons_succ, List.getD_cons_zero] at hne
    have hs : (Γ (zs.getD j 0)).isSome := by
      simp only [kill] at hEz; cases h : Γ (zs.getD j 0) <;> simp_all
    exact ⟨hne, (hbnd _ hs).1, (hbnd _ hs).2⟩
  have hzE : ∀ j, j < zs.length → argE (handCtx Γ c x Ec te m.nv E0) (zs.getD j 0) =
      argE (kill .replace false c Γ) (zs.getD j 0) := by
    intro j hj; obtain ⟨h1, h2, h3⟩ := hzi j hj
    simp only [argE]; rw [hother _ h2 h3 h1]
  have hzv : ∀ j, j < zs.length → ∀ d ∈ (argE (kill .replace false c Γ) (zs.getD j 0)).vdeps, d.root ≠ m.nv := by
    intro j hj d hd
    have hmem : zs.getD j 0 ∈ zs := by simp [List.getD, List.getElem?_eq_getElem hj]
    obtain ⟨h1, h2, h3⟩ := hzi j hj
    exact hand_args_apart hi h1 h2 h3 (hzb _ hmem) d (by rw [hzE j hj]; exact hd)
  have hdtor : ∀ v E', handCtx Γ c x Ec te m.nv E0 v = some E' → E'.dtor = true →
      v ≠ x ∧ v ≠ m.nv ∧ v ≠ c := by
    intro v E' hv hd
    refine ⟨fun e => ?_, fun e => ?_, fun e => ?_⟩
    · rw [e, handCtx_x] at hv; cases hv; rw [hE0d] at hd; cases hd
    · rw [e, hy] at hv; cases hv; rw [hEy] at hd; cases hd
    · rw [e, handCtx_c hxc hyc] at hv; cases hv; cases hd
  -- the extra arguments, by membership
  have hzM : ∀ z ∈ zs, z ≠ c ∧ z ≠ x ∧ z ≠ m.nv ∧
      argE (handCtx Γ c x Ec te m.nv E0) z = argE (kill .replace false c Γ) z := by
    intro z hz
    obtain ⟨j, hj, rfl⟩ := List.getElem_of_mem hz
    have hg : zs.getD j 0 = zs[j] := by simp [List.getD, List.getElem?_eq_getElem hj]
    obtain ⟨h1, h2, h3⟩ := hzi j hj
    rw [hg] at h1 h2 h3
    refine ⟨h1, h2, h3, ?_⟩
    simp only [argE]; rw [hother _ h2 h3 h1]
  have hmutZ : ∀ d ∈ mutNames (handCtx Γ c x Ec te m.nv E0) (m.nv :: zs),
      d ∈ mutNames (kill .replace false c Γ) (c :: zs) :=
    mutNames_hand (by rw [hyE]; exact hEyt) (by rw [hck, killE_ty]; exact hτ)
      (by rw [hyE, hck, killE_vdeps]; exact hEyv) fun z hz => (hzM z hz).2.2.2
  refine ⟨fn, hf, by simp [hps, hlenz], fun i hi' => ?_, fun d hd => ?_, ?_, rfl, rfl, fun h => absurd h hnt⟩
  · rcases i with _ | j
    · -- the receiver: the environment's binding, handed over
      have hpi : fn.params[0]'hi' = (.inout b, te) := by simp [hps]
      refine ⟨compE Ec te, by simpa using hy, by rw [hEy], ?_, ?_, ?_⟩
      · rw [hpi]; exact ⟨by rw [hEy], Or.inl (by rw [hEy]), hto⟩
      · intro _
        refine ⟨fun h => Nat.lt_irrefl _ (hFlt _ h), ?_, ?_, ?_, ?_⟩
        · intro h
          simp only [List.getD_cons_zero, roots, List.mem_map] at h
          obtain ⟨d, hd, hdr⟩ := h
          exact hyroot d (List.mem_filter.mp hd).1 hdr
        · intro h; rw [hpi] at h; cases h
        · intro _ _ d hd hr; exact absurd hr (hyroot d hd)
        · -- (AGORA-927: and no extra argument reaches it: the fresh `y` roots no dependency)
          intro j hj hj0
          rcases j with _ | j
          · exact absurd rfl hj0
          have hjz : j < zs.length := by simp [hps] at hj; omega
          simp only [List.getD_cons_succ, List.getD_cons_zero]
          rw [hzE j hjz]
          refine ⟨fun e => (hzi j hjz).2.2 e, ?_, ?_, ?_⟩
          · intro h; simp only [roots, List.mem_map] at h; obtain ⟨d, hd, hdr⟩ := h
            exact hzv j hjz d (List.mem_filter.mp hd).1 hdr
          · intro h; simp [hps] at h
          · intro _ _ d hd hdr; exact absurd hdr (hzv j hjz d hd)
      · intro _ p Ep hp hpr d hd _ hdr
        simp only [List.getD_cons_zero] at hdr
        by_cases hpx : p = x
        · rw [hpx, handCtx_x] at hp; cases hp; exact hE0m hpr
        by_cases hpy : p = m.nv
        · rw [hpy, hy] at hp; cases hp; rw [hEy] at hpr; cases hpr
        by_cases hpc : p = c
        · rw [hpc, handCtx_c hxc hyc] at hp; cases hp; exact hmc hpr
        rw [hother p hpx hpy hpc] at hp
        simp only [kill] at hp
        obtain ⟨Ep0, hp0, rfl⟩ := Option.map_eq_some_iff.mp hp
        rw [killE_mode] at hpr; rw [killE_vdeps] at hd
        have := hi.root_lt hp0 (hi.rootbLive p Ep0 hp0 hpr) (Or.inr hpr) (List.mem_map_of_mem (f := Dep.root) hd)
        rw [hdr] at this; exact Nat.lt_irrefl _ this
    · -- an extra argument: its entry and parameter are the interface's call's
      have hjz : j < zs.length := by simp [hps] at hi'; omega
      have hj1 : j + 1 < sig.params.length := by simp [hsp]; omega
      obtain ⟨Ez, hEz, hlz, hokz, hmvz, hpinz⟩ := hargs (j + 1) hj1
      have hpar : fn.params[j + 1]'hi' = sig.params[j + 1]'hj1 := by simp [hps, hsp]
      obtain ⟨h1, h2, h3⟩ := hzi j hjz
      simp only [List.getD_cons_succ] at hEz hmvz hpinz ⊢
      refine ⟨Ez, by rw [hother _ h2 h3 h1]; exact hEz, hlz, by rw [hpar]; exact hokz, fun hmv => ?_,
        fun hp => hFr.noPin (hpinz (by rw [← hpar]; exact hp))⟩
      obtain ⟨hF, hown, hsk, hio, hoth⟩ := hmvz (by rw [← hpar]; exact hmv)
      refine ⟨hF, hown, fun h => hsk (by rw [← hpar]; exact h), fun b' h => hio b' (by rw [← hpar]; exact h),
        fun j' hj' hjj => ?_⟩
      have hj'' : j' < sig.params.length := by simp [hps, hsp] at hj' ⊢; omega
      obtain ⟨hne, hr, hs, hb⟩ := hoth j' hj'' hjj
      rcases j' with _ | j'
      · -- the receiver: `y` in place of the package, depending on no more
        simp only [List.getD_cons_zero] at hne hr hs hb ⊢
        rw [hyE]
        rw [hck, killE_vdeps] at hr hs hb
        rw [hpar]
        refine ⟨fun e => h3 e.symm, fun h => hr (roots_sub_of (memDeps_sub_of hEyv) h),
          fun h hh => hs h (roots_sub_of hEyv hh), fun b' h d hd e => hb b' h d (hEyv hd) e⟩
      · simp only [List.getD_cons_succ] at hne hr hs hb ⊢
        have hj'z : j' < zs.length := by simp [hps] at hj'; omega
        rw [hzE j' hj'z, hpar]
        exact ⟨hne, hr, hs, hb⟩
  · -- what the code's closures may change, the interface's may
    obtain ⟨hcan', hvec, hnF, hin, huniq, hnh⟩ := hnf d (hmutZ d hd)
    have hbd : (Γ d.root).isSome := by
      cases h : Γ d.root with
      | some _ => rfl
      | none =>
        have : argE (kill .replace false c Γ) d.root = intE := by simp [argE, kill, h]
        rw [this] at hcan'; rcases hcan' with h' | ⟨_, h', _⟩ <;> cases h'
    obtain ⟨hdx, hdy⟩ := hbnd _ hbd
    have hdc : d.root ≠ c := fun e => by
      obtain ⟨s', hs', _⟩ := hvec; rw [e, hck, killE_ty, htc] at hs'; cases hs'
    have harg : argE (handCtx Γ c x Ec te m.nv E0) d.root = argE (kill .replace false c Γ) d.root := by
      simp only [argE]; rw [hother _ hdx hdy hdc]
    rw [harg]
    refine ⟨hcan', hvec, hnF, ?_, fun a ha hcond d' hd' hdr => ?_,
      -- (AGORA-937 B3: the hand-over's new bindings are no borrowed parameters)
      fun p Ep hp hm d' hd' hdr hha => ?_⟩
    rotate_right
    · by_cases hpx : p = x
      · rw [hpx, handCtx_x] at hp; cases hp; exact absurd hm hE0m
      by_cases hpy : p = m.nv
      · rw [hpy, hy, hEy] at hp; cases hp; cases hm
      by_cases hpc : p = c
      · rw [hpc, handCtx_c hxc hyc] at hp; cases hp; simp only at hm; rw [hm] at hos; cases hos
      rw [hother p hpx hpy hpc] at hp
      exact hnh p Ep hp hm d' hd' hdr hha
    · rcases hin with hn | ⟨i, t, hi1, hi2⟩
      · left; simp only [List.mem_cons, not_or] at hn ⊢; exact ⟨hdy, hn.2⟩
      · rcases i with _ | i
        · simp at hi1; exact absurd hi1.symm hdc
        · right; exact ⟨i + 1, t, by simpa using hi1, by simpa [hps, hsp] using hi2⟩
    · rcases List.mem_cons.mp ha with rfl | haz
      · rw [hyE] at hd'
        exact huniq c (by simp) (by rw [hck, killE_ty]; exact Or.inl hτ) d' (by rw [hck, killE_vdeps]; exact hEyv hd')
          hdr
      · rw [(hzM a haz).2.2.2] at hcond hd'
        exact huniq a (by simp [haz]) hcond d' hd' hdr
  · -- no destructor views the environment's binding, nor more than before
    refine ⟨fun i hi' => ⟨fun hs => ?_, fun b' hb' => ?_⟩, fun d hd => hFr.dtorSafe (hds.2.1 d (hmutZ d hd)),
      fun i hi' b' hb' Ea hEa => ?_⟩
    · rcases i with _ | i
      · simp [hps] at hs
      · have hj1 : i + 1 < sig.params.length := by simp [hps, hsp] at hi' ⊢; omega
        have hpar : fn.params[i + 1]'hi' = sig.params[i + 1]'hj1 := by simp [hps, hsp]
        have := (hds.1 (i + 1) hj1).1 (by rw [← hpar]; exact hs)
        simp only [List.getD_cons_succ] at this ⊢
        exact hFr.dtorSafe this
    · rcases i with _ | i
      · intro v E' hv hd' hos'
        obtain ⟨hvx, hvy, hvc⟩ := hdtor v E' hv hd'
        rw [hother v hvx hvy hvc] at hv
        simp only [kill] at hv
        obtain ⟨E1, h1, rfl⟩ := Option.map_eq_some_iff.mp hv
        have := hi.dtorSafe_fresh (y := m.nv) (Nat.le_refl _) b' (fn.params[0]'hi').2.elem.holdsView v E1 h1
          (by rw [killE_dtor] at hd'; exact hd') (by rw [killE_mode] at hos'; exact hos')
        unfold hitsMem at this ⊢; rw [killE_ty, killE_mode, killE_vdeps]; exact this
      · have hj1 : i + 1 < sig.params.length := by simp [hps, hsp] at hi' ⊢; omega
        have hpar : fn.params[i + 1]'hi' = sig.params[i + 1]'hj1 := by simp [hps, hsp]
        have := (hds.1 (i + 1) hj1).2 b' (by rw [← hpar]; exact hb')
        simp only [List.getD_cons_succ] at this ⊢
        rw [hpar]; exact hFr.dtorSafe this
    · rcases i with _ | i
      · simp only [List.getD_cons_zero, hy, Option.some.injEq] at hEa
        subst hEa; rw [hEy]
      · have hj1 : i + 1 < sig.params.length := by simp [hps, hsp] at hi' ⊢; omega
        have hpar : fn.params[i + 1]'hi' = sig.params[i + 1]'hj1 := by simp [hps, hsp]
        have hjz : i < zs.length := by simp [hps] at hi'; omega
        obtain ⟨h1, h2, h3⟩ := hzi i hjz
        simp only [List.getD_cons_succ] at hEa ⊢
        rw [hother _ h2 h3 h1] at hEa
        exact hds.2.2 (i + 1) hj1 b' (by rw [← hpar]; exact hb') Ea (by simpa using hEa)

/-- **The hand-over's run-time form is typed** (A2-envhand): in the context
    the hand-over leaves, the environment's scope — the code's call on `y`
    with its result moved to `x`, then `y`'s value back into `c` as a package
    — is typed, and leaves a context that says no less than the one the
    interface's call leaves the source (with `c` ended again: the
    environment moved back in). -/
theorem hand_typed {P : Prog} (hP : ProgOK P) {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanchF : RootbAnchF Γ F) (hFlt : ∀ v ∈ F, v < m.nv)
    {c x : Var} {Ec E : Entry} {Γ1 : Ctx} {σ f : Nat} {sig fn : Fn} {b : Eff} {ms : List Nat} {q : Cross}
    {te : Ty} {fs : List Nat} {zs : List Var} {ps : List (PMode × Ty)} (hc : Γ c = some Ec)
    (htc : Ec.ty = .fn ms q) (hmo : Ec.mode = .own)
    (hx : Γ x = none) (hxn : x < m.nv) (hxF : x ∉ F) (hcF : c ∉ F) (hny : NoPin Γ c)
    (hdc : DtorSafe Γ .replace false c)
    (hcT : CallT P (kill .replace false c Γ) F σ (c :: zs) E Γ1) (hσ : P[σ]? = some sig)
    (hsp : sig.params = (.inout b, .fn ms q) :: ps) (hsl : sig.lends = []) (hsr : sig.rholds = [])
    (hso : sig.outHolds = [])
    (hf : P[f]? = some fn) (hps : fn.params = (.inout b, te) :: ps) (hto : te.owning = true) (hnt : ¬ ThruFn P f)
    (hrt : fn.resTy = sig.resTy) (hro : fn.resOwn = sig.resOwn) (hfl : fn.lends ⊆ sig.lends)
    (hfr : fn.rholds ⊆ sig.rholds) (hfo : fn.outHolds ⊆ sig.outHolds) (hq : q.Fits te [])
    (hzb : ∀ z ∈ zs, ∀ d ∈ (argE Γ z).vdeps, (Γ d.root).isSome) :
    ∃ Γe, StmtT P ξ (handCtx Γ c x Ec te m.nv (callX fn)) F
      (.scope m.nv (.seq (.letcall (m.nv + 1) f (m.nv :: zs) (.assign x (.var (m.nv + 1))))
        (.assign c (.pack fs te ms m.nv [])))) Γe ∧
      Weaker Γe (kill .replace false c (setE Γ1 x E)) := by
  have hanch : RootbAnch Γ F := hanchF.toH
  have hcT0 := hcT
  obtain ⟨sig', hσ', hlen, hargs, hnf, hds, hE, hΓ1, _⟩ := hcT
  rw [hσ] at hσ'; cases hσ'
  subst hE hΓ1
  have hlenz : zs.length = ps.length := by simpa [hsp] using hlen
  have hτ : Ec.ty ≠ .int := by rw [htc]; simp
  have hos : Ec.mode.ownSlot = true := by rw [hmo]; rfl
  -- the package, where the interface's call takes it
  obtain ⟨Ea, hEa, hla, _, hmv0, _⟩ := hargs 0 (by simp [hsp])
  simp only [List.getD_cons_zero, kill, hc, Option.map_some, Option.some.injEq] at hEa
  subst hEa
  obtain ⟨hlc, hnc⟩ := kill_live_self hla hτ
  have hkc : killE .replace false c Ec = Ec := by
    rw [killE_live] at hla
    simp only [Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at hla
    unfold killE; rw [hla.2]; rfl
  have hΓkc : kill .replace false c Γ c = some Ec := by simp [kill, hc, hkc]
  have hck : argE (kill .replace false c Γ) c = Ec := by simp [argE, hΓkc]
  have hdbc : Ec.dbind = false := hds.2.2 0 (by simp [hsp]) b (by simp [hsp]) Ec (by simpa using hΓkc)
  have hdtc : Ec.dtor = false := by
    cases h : Ec.dtor
    · rfl
    · rw [hi.wf.arm c Ec hc h] at hdbc; cases hdbc
  have hEcr : ∀ d ∈ Ec.vdeps, ∃ Er, Γ d.root = some Er := fun d hd => by
    obtain ⟨Er, hEr, _⟩ := hi.wf c Ec hc hlc (Or.inl hτ) d.root (List.mem_map_of_mem (f := Dep.root) hd)
    exact ⟨Er, hEr⟩
  have hEch : Ec.vdeps = Ec.held := by simp [Entry.vdeps, hos]
  have hmvc := hmv0 (by simp [hsp, PMode.moves])
  -- the code's summaries are the interface's, none
  have hfl0 : fn.lends = [] := List.eq_nil_of_subset_nil (hsl ▸ hfl)
  have hfr0 : fn.rholds = [] := List.eq_nil_of_subset_nil (hsr ▸ hfr)
  have hfo0 : fn.outHolds = [] := List.eq_nil_of_subset_nil (hso ▸ hfo)
  -- where things are
  have hcn : c < m.nv := hi.nvSt c (by rw [← hi.dom, hc]; rfl)
  have hxy : x ≠ m.nv := fun e => by rw [e] at hxn; exact Nat.lt_irrefl _ hxn
  have hxc : x ≠ c := fun e => by rw [e, hc] at hx; cases hx
  have hyc : m.nv ≠ c := fun e => by rw [← e] at hcn; exact Nat.lt_irrefl _ hcn
  have hrx : m.nv + 1 ≠ x := fun e => by rw [← e] at hxn; have := vlt hxn; omega
  have hry : m.nv + 1 ≠ m.nv := by omega
  have hrc : m.nv + 1 ≠ c := fun e => by rw [← e] at hcn; have := vlt hcn; omega
  have hΓfresh : ∀ v, m.nv ≤ v → Γ v = none := fun v hv => by
    cases h : Γ v with
    | none => rfl
    | some E0 =>
      have h1 := hi.nvSt v (by rw [← hi.dom, h]; rfl)
      exact absurd (Nat.lt_of_lt_of_le h1 hv) (Nat.lt_irrefl _)
  have hΓy : Γ m.nv = none := hΓfresh _ (Nat.le_refl _)
  have hΓr : Γ (m.nv + 1) = none := hΓfresh _ (Nat.le_succ _)
  have hyF : m.nv ∉ F := fun h => Nat.lt_irrefl _ (hFlt _ h)
  have hrF : m.nv + 1 ∉ F := fun h => by have := vlt (hFlt _ h); omega
  have hrootb_c : ∀ v E0, Γ v = some E0 → E0.fixed → ∀ e hb, killE e hb c E0 = E0 := by
    intro v E0 hv hf e hb
    rcases hf with hm | ⟨b', hm, _⟩
    · exact killE_rootb hanch hcF e hb (hny.kills e hb) (HeldSpared.of_none (NoHeld.of_anchF hanchF hcF) _ _) hv hm
    · exact absurd hm (hi.noInout v E0 b' hv)
  -- the environment's binding
  let Γh := handCtx Γ c x Ec te m.nv (callX fn)
  have hEy : compE Ec te = ⟨te, .own, true, [], ownHeld true te Ec.held, false, false, false, false⟩ := compE_owning Ec hto
  have hEyt : (compE Ec te).ty ≠ .int := by
    rw [hEy]; intro h; simp only at h; subst h; simp [Ty.owning] at hto
  have hEyv : (compE Ec te).vdeps ⊆ Ec.vdeps := by
    intro d hd
    rw [hEy] at hd
    simp only [Entry.vdeps, Mode.ownSlot, ↓reduceIte, List.nil_append] at hd
    rw [hEch]; exact ownHeld_sub _ _ _ hd
  have hEyh : (compE Ec te).vdeps = (compE Ec te).held := by rw [hEy]; simp [Entry.vdeps, Mode.ownSlot]
  have hhy : Γh m.nv = some (compE Ec te) := handCtx_y hxy
  have hyE : argE Γh m.nv = compE Ec te := by simp only [argE, hhy, Option.getD_some]
  have hhx : Γh x = some (callX fn) := handCtx_x
  have hhc : Γh c = some { Ec with live := false, dtor := false } := handCtx_c hxc hyc
  have hhr : Γh (m.nv + 1) = none := (handCtx_other hrx hry hrc).trans (by simp [kill, hΓr])
  have hho : ∀ v, v ≠ x → v ≠ m.nv → v ≠ c → Γh v = kill .replace false c Γ v :=
    fun v h1 h2 h3 => handCtx_other h1 h2 h3
  -- (AGORA-927) the arguments beside the receiver: the interface's call's, as they were
  have hargk : ∀ a, argE (kill .replace false c Γ) a = killE .replace false c (argE Γ a) := by
    intro a; cases h : Γ a <;> simp [argE, kill, h, killE, hits, intE]
  have hlive_k : ∀ {E0 : Entry}, (killE .replace false c E0).live = true → E0.live = true := by
    intro E0 h; unfold killE at h; split at h <;> simp_all
  have hzI : ∀ k (hk : k < ps.length), ∃ Ez0, Γ (zs.getD k 0) = some Ez0 ∧
      (killE .replace false c Ez0).live = true ∧ paramOK ps[k].1 ps[k].2 (killE .replace false c Ez0) ∧
      zs.getD k 0 ≠ c := by
    intro k hk
    have hk1 : k + 1 < sig.params.length := by simp [hsp]; omega
    have hpe : sig.params[k + 1]'hk1 = ps[k] := by simp [hsp]
    obtain ⟨Ez, hEz, hlz, hokz, _, _⟩ := hargs (k + 1) hk1
    simp only [List.getD_cons_succ, kill] at hEz
    obtain ⟨Ez0, h0, rfl⟩ := Option.map_eq_some_iff.mp hEz
    have hne := (hmvc.2.2.2.2 (k + 1) hk1 (by omega)).1
    simp only [List.getD_cons_succ, List.getD_cons_zero] at hne
    rw [hpe] at hokz
    exact ⟨Ez0, h0, hlz, hokz, hne⟩
  have hzM : ∀ z ∈ zs, z ≠ c ∧ z ≠ x ∧ z ≠ m.nv ∧ z ≠ m.nv + 1 ∧
      argE Γh z = argE (kill .replace false c Γ) z := by
    intro z hz
    obtain ⟨k, hk, rfl⟩ := List.getElem_of_mem hz
    have hg : zs.getD k 0 = zs[k] := by simp [List.getD, List.getElem?_eq_getElem hk]
    obtain ⟨Ez0, h0, _, _, hne⟩ := hzI k (by omega)
    rw [hg] at h0 hne
    have hlt : zs[k] < m.nv := hi.nvSt _ (by rw [← hi.dom, h0]; rfl)
    have h1 : zs[k] ≠ x := fun e => by rw [e, hx] at h0; cases h0
    have h2 : zs[k] ≠ m.nv := Nat.ne_of_lt hlt
    refine ⟨hne, h1, h2, Nat.ne_of_lt (Nat.lt_succ_of_lt hlt), ?_⟩
    simp only [argE]; rw [hho _ h1 h2 hne]
  have hzE : ∀ z ∈ zs, argE Γh z = argE (kill .replace false c Γ) z := fun z hz => (hzM z hz).2.2.2.2
  have hgetD : ∀ k, k < zs.length → zs.getD k 0 ∈ zs := fun k hk => by
    simp [List.getD, List.getElem?_eq_getElem hk]
  have hzX : ∀ pa ∈ ps.zip zs, pa.2 ≠ x ∧ pa.2 ≠ m.nv ∧ pa.2 ≠ m.nv + 1 ∧ pa.2 ≠ c := by
    intro pa hpa
    obtain ⟨k, hk, hkz, rfl⟩ := RSetup.mem_zip_getD hpa
    obtain ⟨h1, h2, h3, h4, _⟩ := hzM _ (hgetD k hkz)
    exact ⟨h2, h3, h4, h1⟩
  -- a moved argument is reached from no argument but by names of its bound
  have hzmv : ∀ k (hk : k < ps.length), ps[k].1.moves = true →
      zs.getD k 0 ∉ F ∧ (ps[k].1 = .sink ∨ ps[k].1 = .inout .replace → NoPin (kill .replace false c Γ) (zs.getD k 0)) ∧
      ∀ a ∈ c :: zs, zs.getD k 0 ∉ roots (memDeps (argE (kill .replace false c Γ) a).vdeps) ∧
        (ps[k].1 = .sink → zs.getD k 0 ∉ roots (argE (kill .replace false c Γ) a).vdeps) ∧
        (∀ b', ps[k].1 = .inout b' → ∀ d ∈ (argE (kill .replace false c Γ) a).vdeps, d.root = zs.getD k 0 →
          d.kind.bound = b' ∧ b' ≠ .none) := by
    intro k hk hm
    have hk1 : k + 1 < sig.params.length := by simp [hsp]; omega
    have hpe : sig.params[k + 1]'hk1 = ps[k] := by simp [hsp]
    obtain ⟨Ez, hEz, _, _, hmv, hpin⟩ := hargs (k + 1) hk1
    simp only [List.getD_cons_succ] at hEz hmv hpin
    rw [hpe] at hmv hpin
    obtain ⟨hF, hr0, hs0, hb0, hoth⟩ := hmv hm
    refine ⟨hF, hpin, fun a ha => ?_⟩
    by_cases hae : a = zs.getD k 0
    · subst hae
      have he : argE (kill .replace false c Γ) (zs.getD k 0) = Ez := by simp only [argE, hEz, Option.getD_some]
      rw [he]; exact ⟨hr0, hs0, hb0⟩
    · obtain ⟨j, hj, hja⟩ : ∃ j, j < sig.params.length ∧ (c :: zs).getD j 0 = a := by
        obtain ⟨j, hj, rfl⟩ := List.getElem_of_mem ha
        exact ⟨j, by simp [hsp] at hj ⊢; omega, by simp [List.getD, List.getElem?_eq_getElem hj]⟩
      have hjk : j ≠ k + 1 := fun e => hae (by rw [← hja, e]; simp)
      obtain ⟨_, h2, h3, h4⟩ := hoth j hj hjk
      rw [hja] at h2 h3 h4
      exact ⟨h2, h3, h4⟩
  -- ... and the package by none of the others but by names of its bound
  have hcz : ∀ z ∈ zs, c ∉ roots (memDeps (argE (kill .replace false c Γ) z).vdeps) ∧
      ∀ d ∈ (argE (kill .replace false c Γ) z).vdeps, d.root = c → d.kind.bound = b ∧ b ≠ .none := by
    intro z hz
    obtain ⟨j, hj, rfl⟩ := List.getElem_of_mem hz
    have hj1 : j + 1 < sig.params.length := by simp [hsp]; omega
    obtain ⟨_, h2, _, h4⟩ := hmvc.2.2.2.2 (j + 1) hj1 (by omega)
    have hg : (c :: zs).getD (j + 1) 0 = zs[j] := by simp [List.getD, List.getElem?_eq_getElem hj]
    simp only [List.getD_cons_zero] at h2 h4
    rw [hg] at h2 h4
    exact ⟨h2, h4 b (by simp [hsp])⟩
  -- the arguments' entries: live, bound, and rooted
  have haE : ∀ a ∈ c :: zs, ∃ Ea0, Γ a = some Ea0 ∧ Ea0.live = true ∧
      argE (kill .replace false c Γ) a = killE .replace false c Ea0 := by
    intro a ha
    rcases List.mem_cons.mp ha with rfl | hz
    · exact ⟨Ec, hc, hlc, by rw [hck, hkc]⟩
    · obtain ⟨k, hk, rfl⟩ := List.getElem_of_mem hz
      have hg : zs.getD k 0 = zs[k] := by simp [List.getD, List.getElem?_eq_getElem hk]
      obtain ⟨Ez0, h0, hl, _, _⟩ := hzI k (by omega)
      rw [hg] at h0
      exact ⟨Ez0, h0, hlive_k hl, by simp [argE, kill, h0]⟩
  have haR : ∀ a ∈ c :: zs, ∀ d ∈ (argE (kill .replace false c Γ) a).vdeps, (Γ d.root).isSome := by
    intro a ha d hd
    rcases List.mem_cons.mp ha with rfl | hz
    · rw [hck] at hd; obtain ⟨Er, hEr⟩ := hEcr d hd; rw [hEr]; rfl
    · rw [hargk, killE_vdeps] at hd; exact hzb a hz d hd
  -- a name an argument holds changes its binding at most by dropping elements
  have hbrA : ∀ a ∈ c :: zs, (argE (kill .replace false c Γ) a).ty ≠ .int →
      ∀ d ∈ (argE (kill .replace false c Γ) a).vdeps, d.kind.bound ≠ .none → d.kind.bound ≠ .replace := by
    intro a ha hty d hd hb
    obtain ⟨Ea0, h0, hl, he⟩ := haE a ha
    rw [he, killE_ty] at hty; rw [he, killE_vdeps] at hd
    have hnm := RSetup.isName_of_bound hb
    obtain ⟨rd, kd⟩ := d
    cases kd with
    | name b' t' =>
      obtain ⟨_, _, _, _, _, _, hcb, _⟩ := hi.names a Ea0 h0 hl (Or.inl hty) _ hd b' t' rfl
      rcases hcb with h | ⟨h, _⟩
      · exact absurd h hb
      · exact h
    | _ => simp [Kind.isName] at hnm
  have hmutD : ∀ d ∈ mutNames (kill .replace false c Γ) (c :: zs), d.kind.bound ≠ .none ∧
      ∃ a ∈ c :: zs, (argE (kill .replace false c Γ) a).ty ≠ .int ∧ d ∈ (argE (kill .replace false c Γ) a).vdeps := by
    intro d hd
    simp only [mutNames, argNames, List.mem_filter, List.mem_flatMap] at hd
    obtain ⟨⟨a, ha, hda⟩, hb⟩ := hd
    split at hda
    · cases hda
    · exact ⟨by simpa using hb, a, ha, by assumption, (List.mem_filter.mp hda).1⟩
  have hB : ∀ d ∈ mutNames (kill .replace false c Γ) (c :: zs), d.root ∉ F ∧ d.kind.bound ≠ .replace := by
    intro d hd
    obtain ⟨hb, a, ha, hty, hda⟩ := hmutD d hd
    exact ⟨(hnf d hd).2.2.1, hbrA a ha hty d hda hb⟩
  have hmutA : ∀ d ∈ mutNames Γh (m.nv :: zs), d ∈ mutNames (kill .replace false c Γ) (c :: zs) :=
    mutNames_hand (by rw [hyE]; exact hEyt) (by rw [hck]; exact hτ) (by rw [hyE, hck]; exact hEyv) hzE
  have hAF : ∀ d ∈ mutNames Γh (m.nv :: zs), d.root ∉ F ∧ d.kind.bound ≠ .replace := fun d hd => hB d (hmutA d hd)
  -- what the arguments hand: in terms of the interface's call's entries
  have hyh : (compE Ec te).held ⊆ Ec.vdeps := fun d hd => hEyv (by rw [hEyh]; exact hd)
  have hHk : ∀ d ∈ heldOfArgs Γh (m.nv :: zs), ∃ a ∈ c :: zs, (argE (kill .replace false c Γ) a).ty ≠ .int ∧
      ((d.kind.isName = false ∧ ∃ d0 ∈ memDeps (argE (kill .replace false c Γ) a).vdeps, d.root = d0.root) ∨
        (d.kind.isName = true ∧ d ∈ (argE (kill .replace false c Γ) a).vdeps)) := by
    intro d hd
    obtain ⟨a, ha, hty, h⟩ := mem_heldOfArgs hd
    have hhv : ∀ E0 : Entry, E0.held ⊆ E0.vdeps := fun E0 d hd => List.mem_append_right _ hd
    rcases List.mem_cons.mp ha with rfl | hz
    · rw [hyE] at h
      refine ⟨c, by simp, by rw [hck]; exact hτ, ?_⟩
      rw [hck]
      rcases h with ⟨hn, d0, hd0, hr⟩ | ⟨hn, hdv⟩
      · exact Or.inl ⟨hn, d0, memDeps_sub_of hyh hd0, hr⟩
      · exact Or.inr ⟨hn, hEyv hdv⟩
    · rw [hzE a hz] at hty h
      refine ⟨a, List.mem_cons_of_mem _ hz, hty, ?_⟩
      rcases h with ⟨hn, d0, hd0, hr⟩ | ⟨hn, hdv⟩
      · exact Or.inl ⟨hn, d0, memDeps_sub_of (hhv _) hd0, hr⟩
      · exact Or.inr ⟨hn, hdv⟩
  -- what such a dependency is: rooted, not the package's, ended by no closure's change nor the call's
  have hOK : ∀ a ∈ c :: zs, (argE (kill .replace false c Γ) a).ty ≠ .int → ∀ d',
      ((d'.kind.isName = false ∧ ∃ d0 ∈ memDeps (argE (kill .replace false c Γ) a).vdeps, d'.root = d0.root) ∨
        (d'.kind.isName = true ∧ d' ∈ (argE (kill .replace false c Γ) a).vdeps)) →
      (Γ d'.root).isSome ∧ d'.root ≠ c ∧
      (∀ dm ∈ mutNames (kill .replace false c Γ) (c :: zs), d'.root = dm.root → d'.kind.isName = true) ∧
      (∀ k (hk : k < ps.length), ps[k].1.moves = true → d'.root = zs.getD k 0 → ∀ b',
        (ps[k].1 = .sink ∧ b' = .replace ∨ ps[k].1 = .inout b') → ∀ hb, b'.kills hb d'.kind = false) := by
    intro a ha hty d' hd'
    refine ⟨?_, ?_, ?_, ?_⟩
    · rcases hd' with ⟨_, d0, hd0, hr⟩ | ⟨_, hdv⟩
      · rw [hr]; exact haR a ha d0 (List.mem_filter.mp hd0).1
      · exact haR a ha d' hdv
    · intro he
      rcases List.mem_cons.mp ha with rfl | hz
      · rw [hck] at hd'
        rcases hd' with ⟨_, d0, hd0, hr⟩ | ⟨_, hdv⟩
        · exact hnc d0 (List.mem_filter.mp hd0).1 (hr ▸ he)
        · exact hnc d' hdv he
      · rcases hd' with ⟨_, d0, hd0, hr⟩ | ⟨hn, hdv⟩
        · exact (hcz a hz).1 (List.mem_map.mpr ⟨d0, hd0, by rw [← hr, he]⟩)
        · -- a name of the package that may change it: its binding is a `Vec`, not a package
          obtain ⟨hbd, hbn⟩ := (hcz a hz).2 d' hdv he
          have hmut : d' ∈ mutNames (kill .replace false c Γ) (c :: zs) := by
            simp only [mutNames, argNames, List.mem_filter, List.mem_flatMap]
            refine ⟨⟨a, ha, ?_⟩, by rw [hbd]; simpa using hbn⟩
            rw [ite_eq_right hty]; exact List.mem_filter.mpr ⟨hdv, hn⟩
          obtain ⟨s', hs', _⟩ := (hnf d' hmut).2.1
          rw [he, hck, htc] at hs'; cases hs'
    · intro dm hdm hr
      rcases hd' with ⟨hn, d0, hd0, hr0⟩ | ⟨hn, _⟩
      · have hb0 := (hnf dm hdm).2.2.2.2.1 a ha (Or.inl hty) d0 (List.mem_filter.mp hd0).1 (by rw [← hr0, hr])
        have hn0 := RSetup.isName_of_bound (by rw [hb0]; exact (hmutD dm hdm).1)
        have := (List.mem_filter.mp hd0).2
        rw [hn0] at this; cases this
      · exact hn
    · intro k hk hm hr b' hb' hb
      obtain ⟨_, _, hza⟩ := hzmv k hk hm
      obtain ⟨hzr, hzs, hzi⟩ := hza a ha
      rcases hd' with ⟨_, d0, hd0, hr0⟩ | ⟨hn, hdv⟩
      · exact absurd (List.mem_map.mpr ⟨d0, hd0, by rw [← hr0, hr]⟩) hzr
      · rcases hb' with ⟨hs, _⟩ | hio
        · exact absurd (List.mem_map.mpr ⟨d', hdv, hr⟩) (hzs hs)
        · obtain ⟨hbd, hbn⟩ := hzi b' hio d' hdv hr
          exact RSetup.kills_isName (by rw [← hbd]; exact hbrA a ha hty d' hdv (by rw [hbd]; exact hbn)) hb hn
  have hOKv : ∀ a ∈ c :: zs, (argE (kill .replace false c Γ) a).ty ≠ .int →
      ∀ d' ∈ (argE (kill .replace false c Γ) a).vdeps,
      ((d'.kind.isName = false ∧ ∃ d0 ∈ memDeps (argE (kill .replace false c Γ) a).vdeps, d'.root = d0.root) ∨
        (d'.kind.isName = true ∧ d' ∈ (argE (kill .replace false c Γ) a).vdeps)) := by
    intro a _ _ d' hd'
    cases hn : d'.kind.isName
    · exact Or.inl ⟨rfl, d', List.mem_filter.mpr ⟨hd', by simp [hn]⟩, rfl⟩
    · exact Or.inr ⟨rfl, hd'⟩
  have hsubH : heldOfArgs Γh (m.nv :: zs) ⊆ heldOfArgs (kill .replace false c Γ) (c :: zs) := by
    intro d hd
    simp only [heldOfArgs, argNames, List.flatMap_cons, List.mem_append] at hd ⊢
    rcases hd with h | h
    · left
      refine compAll_mono (fun d0 hd0 => ?_) h
      simp only [argMem, List.flatMap_cons, List.mem_append, List.mem_flatMap] at hd0 ⊢
      rcases hd0 with hr | ⟨z, hz, hrz⟩
      · left
        rw [hyE] at hr; simp only [hEyt, ↓reduceIte] at hr; rw [hck]; simp only [hτ, ↓reduceIte]
        exact memDeps_sub_of (fun d hd => by rw [← hEch]; exact hyh hd) hr
      · right; exact ⟨z, hz, by rw [← hzE z hz]; exact hrz⟩
    · right
      simp only [List.mem_flatMap] at h ⊢
      rcases h with h | ⟨z, hz, hdz⟩
      · left
        rw [hyE] at h; simp only [hEyt, ↓reduceIte] at h; rw [hck]; simp only [hτ, ↓reduceIte]
        exact List.mem_filter.mpr ⟨hEyv (List.mem_filter.mp h).1, (List.mem_filter.mp h).2⟩
      · right; exact ⟨z, hz, by rw [← hzE z hz]; exact hdz⟩
  -- what the environment's binding is handed after the call
  let HyR : List Dep := if te.holdsView then
      (compE Ec te).held ++ outHeld Γh fn (m.nv :: zs) 0 ++ heldOfArgs Γh (m.nv :: zs)
    else (compE Ec te).held
  let Ey1 : Entry := { compE Ec te with held := HyR }
  have hHyR : ∀ d' ∈ HyR, (Γ d'.root).isSome ∧ d'.root ≠ c ∧
      (∀ dm ∈ mutNames (kill .replace false c Γ) (c :: zs), d'.root = dm.root → d'.kind.isName = true) ∧
      (∀ k (hk : k < ps.length), ps[k].1.moves = true → d'.root = zs.getD k 0 → ∀ b',
        (ps[k].1 = .sink ∧ b' = .replace ∨ ps[k].1 = .inout b') → ∀ hb, b'.kills hb d'.kind = false) := by
    have hc' : c ∈ c :: zs := by simp
    have hcty : (argE (kill .replace false c Γ) c).ty ≠ .int := by rw [hck]; exact hτ
    intro d' hd'
    simp only [HyR] at hd'
    split at hd'
    · rw [outHeld_nil hfo0, List.append_nil] at hd'
      rcases List.mem_append.mp hd' with h | h
      · exact hOK c hc' hcty d' (hOKv c hc' hcty d' (by rw [hck]; exact hyh h))
      · obtain ⟨a, ha, hty, h'⟩ := hHk d' h
        exact hOK a ha hty d' h'
    · exact hOK c hc' hcty d' (hOKv c hc' hcty d' (by rw [hck]; exact hyh hd'))
  have hEy1v : Ey1.vdeps = HyR := by simp [Ey1, Entry.vdeps, hEy, Mode.ownSlot]
  have hEy1r : Rooted Γ Ey1 := Rooted.of_roots fun d hd => (hHyR d (hEy1v ▸ hd)).1
  have hHR : ∀ d ∈ heldOfArgs Γh (m.nv :: zs), (Γ d.root).isSome := fun d hd => by
    obtain ⟨a, ha, hty, h'⟩ := hHk d hd
    exact (hOK a ha hty d h').1
  -- the hand-over's context is rooted and keeps the store's pins and destructors
  have hrootΓ : AllRooted Γ (kill .replace false c Γ) :=
    fun v E0 hv => by
      simp only [kill] at hv
      obtain ⟨E1, h1, rfl⟩ := Option.map_eq_some_iff.mp hv
      exact (hi.rooted h1).killE _ _ _
  have hrooth : AllRooted Γ Γh := by
    refine ((hrootΓ.setE (Rooted.of_dead rfl)).setE ?_).setE (Rooted.of_dead rfl)
    refine Rooted.of_roots fun d hd => ?_
    obtain ⟨Er, hEr⟩ := hEcr d (hEyv hd)
    rw [hEr]; rfl
  have hfrΓk : FrameOK Γ (kill .replace false c Γ) :=
    (FrameOK.refl Γ).kill _ _ _ fun p E0 hp hm => hrootb_c p E0 hp (Or.inl hm) _ _
  have hfrh : FrameOK Γ Γh :=
    ((hfrΓk.setE (by simp [hmo]) rfl (by simp [hdbc])).setE (by rw [hEy]; simp) (by rw [hEy]) (by rw [hEy])).setE
      (resMode_ne' fn) rfl rfl
  -- the moved arguments beside the receiver
  have hzown : ∀ k (hk : k < ps.length), ps[k].1.moves = true →
      ∃ Ez0, Γ (zs.getD k 0) = some Ez0 ∧ Ez0.mode = .own ∧
        argE Γh (zs.getD k 0) = killE .replace false c Ez0 := by
    intro k hk hm
    obtain ⟨Ez0, h0, _, hok, _⟩ := hzI k hk
    have hkz : k < zs.length := by omega
    refine ⟨Ez0, h0, ?_, by
      rw [hzE _ (hgetD k hkz)]; simp only [argE, kill, h0, Option.map_some, Option.getD_some]⟩
    have hok' := hok
    have hm' := hm
    generalize ps[k] = pt at hok' hm'
    obtain ⟨pm, t⟩ := pt
    cases pm with
    | inp => simp [PMode.moves] at hm'
    | sink => have := hok'.2.1; rwa [killE_mode] at this
    | inout b' =>
      rcases hok'.2.1 with h | ⟨b'', h, _⟩
      · rw [killE_mode] at h; exact h
      · rw [killE_mode] at h; exact absurd h (hi.noInout _ Ez0 b'' h0)
  have hzfix : ∀ k (hk : k < ps.length), ps[k].1.moves = true → ∀ b',
      (ps[k].1 = .sink ∧ b' = .replace ∨ ps[k].1 = .inout b') → ∀ hb v E0, Γ v = some E0 → E0.fixed →
      killE b' hb (zs.getD k 0) E0 = E0 := by
    intro k hk hm b' hb' hb v E0 hv hf
    obtain ⟨hzF, hpin, _⟩ := hzmv k hk hm
    rcases hf with hrb | ⟨b'', hm', _⟩
    · refine killE_rootb hanch hzF b' hb (fun p Ep hp hpm d hd hbn hk' => ?_)
          (HeldSpared.of_none (NoHeld.of_anchF hanchF hzF) _ _) hv hrb
      by_cases hbr : b' = .replace
      · have hor : ps[k].1 = .sink ∨ ps[k].1 = .inout .replace := by
          rcases hb' with ⟨hs, _⟩ | hio
          · exact Or.inl hs
          · exact Or.inr (hbr ▸ hio)
        exact hpin hor p Ep (by simp [kill, hp, hrootb_c p Ep hp (Or.inl hpm)]) hpm d hd hbn
      · rw [RSetup.kills_isName hbr hb (RSetup.isName_of_bound hbn)] at hk'; cases hk'
    · exact absurd hm' (hi.noInout v E0 b'' hv)
  have htz : ∀ pa ∈ ps.zip zs, pa.1.1.moves = true → pa.2 ∉ [x, m.nv, m.nv + 1, c] ∧
      argE Γh pa.2 = argE (kill .replace false c Γ) pa.2 ∧ ¬ (argE Γh pa.2).fixed ∧
      (∀ b', pa.1.1 = .inout b' → (argE Γh pa.2).dbind = false) ∧
      (∀ d ∈ (argE Γh pa.2).vdeps, (Γ d.root).isSome) ∧
      ∀ b', (pa.1.1 = .sink ∧ b' = .replace ∨ pa.1.1 = .inout b') → ∀ hb v E0, Γ v = some E0 → E0.fixed →
        killE b' hb pa.2 E0 = E0 := by
    intro pa hpa hm
    obtain ⟨k, hk, hkz, rfl⟩ := RSetup.mem_zip_getD hpa
    have hz := hgetD k hkz
    obtain ⟨Ez0, h0, hmo0, hEh⟩ := hzown k hk hm
    obtain ⟨h1, h2, h3, h4⟩ := hzX _ hpa
    refine ⟨by simp only [List.mem_cons, List.not_mem_nil, or_false, not_or]; exact ⟨h1, h2, h3, h4⟩,
      hzE _ hz, ?_, fun b' hb' => ?_, ?_, hzfix k hk hm⟩
    · rw [hEh]; unfold Entry.fixed; rw [killE_mode, hmo0]; simp
    · have hk1 : k + 1 < sig.params.length := by simp [hsp]; omega
      have hpe : sig.params[k + 1]'hk1 = ps[k] := by simp [hsp]
      have := hds.2.2 (k + 1) hk1 b' (by rw [hpe]; exact hb') (argE Γh (zs.getD k 0))
        (by rw [hEh]; simp only [List.getD_cons_succ, kill, h0, Option.map_some])
      exact this
    · rw [hzE _ hz]; exact haR _ (List.mem_cons_of_mem _ hz)
  have htzF : ∀ pa ∈ ps.zip zs, pa.1.1.moves = true → (argE Γh pa.2).mode ≠ .rootb ∧
      (∀ b', pa.1.1 = .inout b' → (argE Γh pa.2).dbind = false ∧ (argE Γh pa.2).dtor = false) ∧
      ((argE Γh pa.2).dbind = true → ∃ E0, Γ pa.2 = some E0 ∧ E0.dbind = true ∧ E0.ty = (argE Γh pa.2).ty ∧
        E0.mode = (argE Γh pa.2).mode ∧ E0.vdeps = (argE Γh pa.2).vdeps) ∧
      ∀ b', (pa.1.1 = .sink ∧ b' = .replace ∨ pa.1.1 = .inout b') → ∀ hb v E0, Γ v = some E0 → E0.fixed →
        killE b' hb pa.2 E0 = E0 := by
    intro pa hpa hm
    obtain ⟨_, _, _, hdb, _, hfix⟩ := htz pa hpa hm
    obtain ⟨k, hk, hkz, rfl⟩ := RSetup.mem_zip_getD hpa
    obtain ⟨Ez0, h0, hmo0, hEh⟩ := hzown k hk hm
    refine ⟨by rw [hEh, killE_mode, hmo0]; simp, fun b' hb' => ⟨hdb b' hb', ?_⟩, fun hd => ?_, hfix⟩
    · have h1 := hdb b' hb'
      rw [hEh, killE_dbind] at h1; rw [hEh, killE_dtor]
      cases h : Ez0.dtor
      · rfl
      · rw [hi.wf.arm _ Ez0 h0 h] at h1; cases h1
    · rw [hEh] at hd ⊢; rw [killE_dbind] at hd
      exact ⟨Ez0, h0, hd, by rw [killE_ty], by rw [killE_mode], by rw [killE_vdeps]⟩
  -- the code's call, and what it leaves
  have hcT' := callT_hand hi hFlt hc htc hx hxn hcT0 hσ hsp hf hps hto hnt hzb (E0 := callX fn) rfl
    (resMode_ne' fn) rfl
  have hΓ1' : callPost Γh fn (m.nv :: zs) = A2.killNames (mutNames Γh (m.nv :: zs))
      (callPostAux Γh fn (m.nv :: zs) ps zs 1 (setE Γh m.nv Ey1)) := by
    rw [callPost_cons hps, hrooth.kill_fresh hΓy, hyE]; simp only [Ey1, compE_heldFresh, ite_self]; rfl
  have hkeepy : RSetup.killAll (mutNames Γh (m.nv :: zs)) Ey1 = Ey1 := by
    refine killAll_id fun d hd => RSetup.hits_false_of fun d' hd' hr' => ?_
    rw [hEy1v] at hd'
    exact RSetup.kills_isName (hAF d hd).2 _ ((hHyR d' hd').2.2.1 d (hmutA d hd) hr')
  have hzy : ∀ pa ∈ ps.zip zs, pa.1.1.moves = true → pa.2 ≠ m.nv ∧ ∀ b',
      (pa.1.1 = .sink ∧ b' = .replace ∨ pa.1.1 = .inout b') → ∀ hb, (some Ey1).map (killE b' hb pa.2) = some Ey1 := by
    intro pa hpa hm
    refine ⟨(hzX pa hpa).2.1, fun b' hb' hb => ?_⟩
    obtain ⟨k, hk, _, rfl⟩ := RSetup.mem_zip_getD hpa
    show some (killE b' hb _ Ey1) = some Ey1
    unfold killE
    rw [RSetup.hits_false_of fun d' hd' hr' => (hHyR d' (hEy1v ▸ hd')).2.2.2 k hk hm hr' b' hb' hb]; rfl
  have h1y : callPost Γh fn (m.nv :: zs) m.nv = some Ey1 := by
    rw [hΓ1', RSetup.killNames_eq,
      callPostAux_keepAt (Γ0 := Γh) (fn := fn) (args := m.nv :: zs) (y := m.nv) (o := some Ey1) ps zs 1 _ hzy
        (by simp [setE])]
    simp [hkeepy]
  have h1x : callPost Γh fn (m.nv :: zs) x = some (callX fn) := by
    have hkx : ∀ e hb w, killE e hb w (callX fn) = callX fn := fun e hb w => by
      unfold killE; rw [RSetup.hits_false_of fun d hd _ => by rw [callX_vdeps] at hd; cases hd]; rfl
    rw [hΓ1', RSetup.killNames_eq,
      callPostAux_keepAt (Γ0 := Γh) (fn := fn) (args := m.nv :: zs) (y := x) (o := some (callX fn)) ps zs 1 _
        (fun pa hpa _ => ⟨(hzX pa hpa).1, fun b' _ hb => by show some _ = _; rw [hkx]⟩)
        (by simp only [setE, upd_ne _ _ hxy, hhx])]
    simp only [Option.map_some, Option.some.injEq]
    exact killAll_id fun d _ => by unfold hits; simp [callX_vdeps]
  have h1r : callPost Γh fn (m.nv :: zs) (m.nv + 1) = none := by
    rw [hΓ1', RSetup.killNames_eq,
      callPostAux_keepAt (Γ0 := Γh) (fn := fn) (args := m.nv :: zs) (y := m.nv + 1) (o := none) ps zs 1 _
        (fun pa hpa _ => ⟨(hzX pa hpa).2.2.1, fun _ _ _ => rfl⟩) (by simp only [setE, upd_ne _ _ hry, hhr])]
    rfl
  let Ecd1 := RSetup.killAll (mutNames Γh (m.nv :: zs)) { Ec with live := false, dtor := false }
  have h1c : callPost Γh fn (m.nv :: zs) c = some Ecd1 := by
    rw [hΓ1', RSetup.killNames_eq,
      callPostAux_keepAt (Γ0 := Γh) (fn := fn) (args := m.nv :: zs) (y := c)
        (o := some { Ec with live := false, dtor := false }) ps zs 1 _
        (fun pa hpa _ => ⟨(hzX pa hpa).2.2.2, fun _ _ _ => by show some (killE _ _ _ _) = _; rw [killE_dead rfl]⟩)
        (by simp only [setE, upd_ne _ _ hyc.symm, hhc])]
    rfl
  have hEcd1 : Ecd1.mode = Ec.mode ∧ Ecd1.ty = Ec.ty ∧ Ecd1.dbind = Ec.dbind ∧ Ecd1.live = false := by
    simp only [Ecd1]; unfold RSetup.killAll; split <;> exact ⟨rfl, rfl, rfl, rfl⟩
  -- the interface's call, in the source
  let HcS : List Dep := if (Ty.fn ms q).holdsView then
      (argE (kill .replace false c Γ) c).held ++ outHeld (kill .replace false c Γ) sig (c :: zs) 0 ++
        heldOfArgs (kill .replace false c Γ) (c :: zs)
    else (argE (kill .replace false c Γ) c).held
  let Ec1 : Entry := { argE (kill .replace false c Γ) c with
    heldFresh := (if (Ty.fn ms q).holdsView then false else (argE (kill .replace false c Γ) c).heldFresh), held := HcS }
  have hΓ1 : callPost (kill .replace false c Γ) sig (c :: zs) = A2.killNames (mutNames (kill .replace false c Γ) (c :: zs))
      (callPostAux (kill .replace false c Γ) sig (c :: zs) ps zs 1
        (setE (kill b (Ty.fn ms q).elem.holdsView c (kill .replace false c Γ)) c Ec1)) := callPost_cons hsp c zs
  -- the two contexts, binding by binding outside the hand-over's
  have hfixB : ∀ v E0, Γ v = some E0 → E0.fixed → ∀ d ∈ mutNames (kill .replace false c Γ) (c :: zs),
      hits d.kind.bound false d.root E0 = false := by
    intro v E0 hv hf d hd
    rcases hf with hm | ⟨b', hm, _⟩
    · exact rootb_names hanchF hB v E0 hv hm d hd
    · exact absurd hm (hi.noInout v E0 b' hv)
  have hfixc : ∀ v E0, Γ v = some E0 → E0.fixed → killE .replace false c E0 = E0 :=
    fun v E0 hv hf => hrootb_c v E0 hv hf _ _
  have hXn : ∀ v, v ∉ [x, m.nv, m.nv + 1, c] → v ≠ x ∧ v ≠ m.nv ∧ v ≠ m.nv + 1 ∧ v ≠ c := by
    intro v hv; simp only [List.mem_cons, List.not_mem_nil, or_false, not_or] at hv; exact hv
  have h0 : HandRel Γ [x, m.nv, m.nv + 1, c] Γh (kill .replace false c Γ) := by
    intro v hv
    obtain ⟨h1, h2, _, h4⟩ := hXn v hv
    refine ⟨by rw [hho v h1 h2 h4], fun Ed Es hd hs => ?_⟩
    rw [hho v h1 h2 h4] at hd
    rw [hd] at hs; cases hs
    refine ⟨EntryWeaker.refl _, hrootΓ v Ed hd, fun hf => ?_⟩
    simp only [kill] at hd
    obtain ⟨E0, h0', rfl⟩ := Option.map_eq_some_iff.mp hd
    have hf0 : E0.fixed := by unfold Entry.fixed at hf ⊢; rwa [killE_mode, killE_ty] at hf
    rw [hrootb_c v E0 h0' hf0]; exact h0'
  have hA : HandRel Γ [x, m.nv, m.nv + 1, c] (setE Γh m.nv Ey1)
      (setE (kill b (Ty.fn ms q).elem.holdsView c (kill .replace false c Γ)) c Ec1) :=
    ((h0.killS b (Ty.fn ms q).elem.holdsView c fun v E0 hv hf => hrootb_c v E0 hv hf _ _).setD
      (by simp) Ey1).setS (by simp) Ec1
  have hT3 := handRel_tail (X := [x, m.nv, m.nv + 1, c]) (Γ0d := Γh) (Γ0s := kill .replace false c Γ) (fd := fn)
      (fs' := sig) (ad := m.nv :: zs) (as' := c :: zs) hfo0 hso hsubH hHR ps zs 1 _ _ htz hA
  have h3 : HandRel Γ [x, m.nv, m.nv + 1, c] (callPost Γh fn (m.nv :: zs))
      (callPost (kill .replace false c Γ) sig (c :: zs)) := by
    rw [hΓ1', hΓ1]
    exact hT3.killNames (A := mutNames Γh (m.nv :: zs)) (B := mutNames (kill .replace false c Γ) (c :: zs))
      (fun d hd => Or.inl (hmutA d hd)) hfixB
  have hroot1 : AllRooted Γ (callPost Γh fn (m.nv :: zs)) := by
    intro v E0 hv
    by_cases hvX : v ∈ [x, m.nv, m.nv + 1, c]
    · simp only [List.mem_cons, List.not_mem_nil, or_false] at hvX
      rcases hvX with hv' | hv' | hv' | hv' <;> rw [hv'] at hv
      · rw [h1x] at hv; rw [← Option.some.inj hv]; exact Rooted.of_roots (by simp [callX_vdeps])
      · rw [h1y] at hv; rw [← Option.some.inj hv]; exact hEy1r
      · rw [h1r] at hv; cases hv
      · rw [h1c] at hv; rw [← Option.some.inj hv]; exact Rooted.of_dead hEcd1.2.2.2
    · obtain ⟨hn, hr⟩ := h3 v hvX
      cases hs : callPost (kill .replace false c Γ) sig (c :: zs) v with
      | none => rw [hn.mpr hs] at hv; cases hv
      | some Es => exact (hr E0 Es hv hs).2.1
  have hfr1 : FrameOK Γ (callPost Γh fn (m.nv :: zs)) := by
    rw [hΓ1']
    have hft := FrameOK.callPostAux_tail (Γ0 := Γh) (fn := fn) (args := m.nv :: zs) ps zs 1 _ htzF
      (hfrh.setE (E := Ey1) (w := m.nv) (by simp [Ey1, hEy]) (by simp [Ey1, hEy]) (by simp [Ey1, hEy]))
    refine hft.killNames _ ?_
    intro p E0 hp hm
    exact rootb_names hanchF hAF p E0 (hft.1 p E0 hp hm) hm
  -- the inner call's result
  have hE'r : ∀ d ∈ (callRes Γh fn (m.nv :: zs)).path ++ (callRes Γh fn (m.nv :: zs)).held, (Γ d.root).isSome := by
    intro d hd
    have hd' : d ∈ heldOfArgs Γh (m.nv :: zs) := by
      simp only [callRes, hfl0, hfr0, List.flatMap_nil, List.nil_append, List.mem_append] at hd
      rcases hd with hd | hd
      · exact hd
      · exact ownHeld_sub _ _ _ hd
    exact hHR d hd'
  have hE'R : Rooted Γ (callRes Γh fn (m.nv :: zs)) := Rooted.of_roots fun d hd => by
    apply hE'r
    simp only [Entry.vdeps, List.mem_append] at hd ⊢
    rcases hd with hd | hd
    · split at hd
      · cases hd
      · exact Or.inl hd
    · exact Or.inr hd
  have hE'm : (callRes Γh fn (m.nv :: zs)).mode = .own ∨ (callRes Γh fn (m.nv :: zs)).mode = .bor := by
    simp only [callRes, resMode]; split <;> simp
  let Γr := setE (callPost Γh fn (m.nv :: zs)) (m.nv + 1) (callRes Γh fn (m.nv :: zs))
  have hrootr : AllRooted Γ Γr := hroot1.setE hE'R
  have hfrr : FrameOK Γ Γr := hfr1.setE (resMode_ne' fn) rfl rfl
  obtain ⟨Er, Γ2, hRhs, hErm, hErt, hErl, hErp, hErh, hErd, hErdb, hΓ2⟩ :=
    hand_res (Γr := Γr) (F := F) (by simp [Γr, setE]) rfl hrF (hfrr.noPin_fresh hi hΓr)
      (hfrr.dtorSafe (DtorSafe.of_fresh hi.wf hΓr _ _)) hE'm
  obtain ⟨Er2, hΓ2eq, hEr2m, hEr2d, hEr2db, hEr2R⟩ : ∃ Er2, Γ2 = setE (callPost Γh fn (m.nv :: zs)) (m.nv + 1) Er2 ∧
      Er2.mode = (callRes Γh fn (m.nv :: zs)).mode ∧ Er2.dtor = false ∧ Er2.dbind = false ∧ Rooted Γ Er2 := by
    rcases hΓ2 with h | h
    · refine ⟨{ callRes Γh fn (m.nv :: zs) with live := false, dtor := false }, ?_, rfl, rfl, rfl, Rooted.of_dead rfl⟩
      rw [h, hrootr.kill_fresh hΓr]
      funext v; simp only [Γr, setE, upd]; split <;> rfl
    · exact ⟨_, h, rfl, rfl, rfl, hE'R⟩
  have hroot2 : AllRooted Γ Γ2 := by rw [hΓ2eq]; exact hroot1.setE hEr2R
  have hfr2 : FrameOK Γ Γ2 := by
    rw [hΓ2eq]; exact hfr1.setE (by rw [hEr2m]; exact resMode_ne' fn) hEr2d hEr2db
  have hErv : ∀ d ∈ Er.vdeps, (Γ d.root).isSome := by
    intro d hd
    simp only [Entry.vdeps, List.mem_append] at hd
    apply hE'r
    rcases hd with hd | hd
    · split at hd
      · cases hd
      · exact List.mem_append_left _ (hErp hd)
    · exact List.mem_append_right _ (hErh hd)
  have hxroot : x ∉ roots Er.vdeps := by
    intro h
    obtain ⟨d, hd, hdr⟩ := List.mem_map.mp h
    have := hErv d hd
    rw [hdr, hx] at this; cases this
  have hmodes : ((callX fn).mode = .own ∧ Er.mode = .own) ∨ ((callX fn).mode = .inout .replace ∧ Er.mode = .own) ∨
      ((callX fn).mode = .bor ∧ Er.mode = .bor) := by
    rw [hErm]; simp only [callX, callRes, resMode]; split <;> simp
  have hTasg : StmtT P ((ξ.under m.nv).under (m.nv + 1)) Γr F (.assign x (.var (m.nv + 1)))
      (setE (kill .replace false x Γ2) x { Er with mode := (callX fn).mode }) :=
    StmtT.assign (by simp [Γr, setE, upd_ne _ _ (Ne.symm hrx), h1x]) hxF hmodes hRhs
      (by rw [hErt]; rfl) hxroot (by rw [hΓ2eq]; simp [setE, upd_ne _ _ (Ne.symm hrx), h1x])
      (hfrr.noPin_fresh hi hx) (hfr2.dtorSafe (DtorSafe.of_fresh hi.wf hx _ _)) rfl
  let Ex1 : Entry := { Er with mode := (callX fn).mode }
  have hΔr : setE (kill .replace false x Γ2) x Ex1 = setE Γ2 x Ex1 := by rw [hroot2.kill_fresh hx]
  have hEx1 : Ex1 = Er := by
    have hmEq : (callX fn).mode = Er.mode := by rw [hErm]; rfl
    simp only [Ex1, hmEq]
  have hEx1R : Rooted Γ Ex1 := Rooted.of_roots fun d hd => by
    rw [hEx1] at hd; exact hErv d hd
  have hfrΔ : FrameOK Γ (setE (kill .replace false x Γ2) x Ex1) := by
    rw [hΔr]; exact hfr2.setE (resMode_ne' fn) hErd hErdb
  have hTcall : StmtT P (ξ.under m.nv) Γh F (.letcall (m.nv + 1) f (m.nv :: zs) (.assign x (.var (m.nv + 1))))
      (exitScope (m.nv + 1) (setE (kill .replace false x Γ2) x Ex1)) :=
    StmtT.letcall rfl hhr hrF hcT' hTasg (hfrΔ.endOK_fresh hi hΓr)
      -- (A2-drop.3a: the code's result moves into `x` at once, whose
      -- binder, the call through the package, answers for it)
      (fun _ _ _ _ => by simp [Stmt.movedFirst, Stmt.assigns]; exact hrx)
  -- the environment goes back into the package
  have hrootΔ : AllRooted Γ (setE Γ2 x Ex1) := hroot2.setE hEx1R
  have hΓ3 : exitScope (m.nv + 1) (setE (kill .replace false x Γ2) x Ex1) = upd (setE Γ2 x Ex1) (m.nv + 1) none := by
    unfold exitScope; rw [hΔr, hrootΔ.kill_fresh hΓr]
  have hroot3 : AllRooted Γ (exitScope (m.nv + 1) (setE (kill .replace false x Γ2) x Ex1)) := by
    rw [hΓ3]; exact hrootΔ.upd_none _
  have hfr3 : FrameOK Γ (exitScope (m.nv + 1) (setE (kill .replace false x Γ2) x Ex1)) := by
    rw [hΓ3]; exact (hΔr ▸ hfrΔ).upd_none _
  have h3y : exitScope (m.nv + 1) (setE (kill .replace false x Γ2) x Ex1) m.nv = some Ey1 := by
    rw [hΓ3, hΓ2eq]; simp [setE, upd_ne _ _ (Ne.symm hxy), h1y]
  have h3c : exitScope (m.nv + 1) (setE (kill .replace false x Γ2) x Ex1) c = some Ecd1 := by
    rw [hΓ3, hΓ2eq]; simp [setE, upd_ne _ _ (Ne.symm hrc), upd_ne _ _ (Ne.symm hxc), h1c]
  have h3x : exitScope (m.nv + 1) (setE (kill .replace false x Γ2) x Ex1) x = some Ex1 := by
    rw [hΓ3]; simp [setE, upd_ne _ _ (Ne.symm hrx)]
  have h3r : exitScope (m.nv + 1) (setE (kill .replace false x Γ2) x Ex1) (m.nv + 1) = none := by
    rw [hΓ3]; simp
  let Γ3 := exitScope (m.nv + 1) (setE (kill .replace false x Γ2) x Ex1)
  have hEy1o : Ey1.mode = .own := by simp [Ey1, hEy]
  have hpush : PushArg Γ3 F m.nv Ey1 te Ey1.held
      (setE (kill .replace false m.nv Γ3) m.nv { Ey1 with live := false, dtor := false }) :=
    PushArg.move hto hEy1o hyF (hfr3.noPin_fresh hi hΓy) (hfr3.dtorSafe (DtorSafe.of_fresh hi.wf hΓy _ _))
  have hpk : RhsT Γ3 F (.pack fs te ms m.nv [])
      ⟨.fn ms q, .own, true, [], Ey1.held ++ capDeps [], false, false, false, false⟩
      (setE (kill .replace false m.nv Γ3) m.nv { Ey1 with live := false, dtor := false }) :=
    RhsT.pack h3y (by simp [Ey1, hEy]) (by simp [Ey1, hEy]) hpush ⟨List.nodup_nil, fun _ h => by cases h⟩ hq
  let Γ4 := setE (kill .replace false m.nv Γ3) m.nv { Ey1 with live := false, dtor := false }
  have hroot4 : AllRooted Γ Γ4 := (hroot3.kill _ _ _).setE (Rooted.of_dead rfl)
  have hfr4 : FrameOK Γ Γ4 :=
    (hfr3.kill _ _ _ fun p E0 hp _ => (hroot3 p E0 hp).killE_fresh hΓy _ _).setE (by simp [Ey1, hEy])
      (by rfl) (by simp [Ey1, hEy])
  have h3c' : Γ3 c = some Ecd1 := h3c
  have h4c : Γ4 c = some Ecd1 := by
    simp only [Γ4, setE, upd_ne _ _ (Ne.symm hyc), kill, h3c', Option.map_some]
    rw [killE_dead hEcd1.2.2.2]
  have hEy1h : Ey1.held = HyR := rfl
  have hcroot : c ∉ roots ((⟨.fn ms q, .own, true, [], Ey1.held ++ capDeps [], false, false, false, false⟩ : Entry).vdeps) := by
    intro h
    obtain ⟨d, hd, hdr⟩ := List.mem_map.mp h
    have hd' : d ∈ HyR := by simpa [Entry.vdeps, Mode.ownSlot, capDeps, Ey1] using hd
    exact (hHyR d hd').2.1 hdr
  have hTpack : StmtT P (ξ.under m.nv) Γ3 F (.assign c (.pack fs te ms m.nv []))
      (setE (kill .replace false c Γ4) c
        { (⟨.fn ms q, .own, true, [], Ey1.held ++ capDeps [], false, false, false, false⟩ : Entry) with mode := Ecd1.mode }) :=
    StmtT.assign h3c hcF (Or.inl ⟨by rw [hEcd1.1, hmo], rfl⟩) hpk (by show Ty.fn ms q = Ecd1.ty; rw [hEcd1.2.1, htc])
      hcroot (by simp [Γ4, setE, upd_ne _ _ (Ne.symm hyc), kill, h3c']) (hfr3.noPin hny) (hfr4.dtorSafe hdc)
      (by rw [hEcd1.2.2.1, hdbc])
  let Epk : Entry := { (⟨.fn ms q, .own, true, [], Ey1.held ++ capDeps [], false, false, false, false⟩ : Entry) with mode := Ecd1.mode }
  have hEpkR : Rooted Γ Epk := Rooted.of_roots fun d hd => by
    have hd' : d ∈ HyR := by simpa [Epk, Entry.vdeps, Mode.ownSlot, capDeps, Ey1, hEcd1.1, hmo] using hd
    exact (hHyR d hd').1
  have hrootp : AllRooted Γ (setE (kill .replace false c Γ4) c Epk) := (hroot4.kill _ _ _).setE hEpkR
  have hfrp : FrameOK Γ (setE (kill .replace false c Γ4) c Epk) :=
    (hfr4.kill _ _ _ fun p E0 hp hm => hrootb_c p E0 (hfr4.1 p E0 hp hm) (Or.inl hm) _ _).setE
      (by simp [Epk, hEcd1.1, hmo]) rfl (by simp [Epk])
  refine ⟨_, StmtT.scope ⟨compE Ec te, hhy, by rw [hEy]; simp⟩ hyF (StmtT.seq rfl hTcall hTpack)
    (hfrp.endOK_fresh hi hΓy), ?_⟩
  show Weaker (exitScope m.nv (setE (kill .replace false c Γ4) c Epk)) _
  have hown_sub : ∀ (o : Bool) (t : Ty) {H H' : List Dep}, H ⊆ H' → ownHeld o t H ⊆ ownHeld o t H' := by
    intro o t H H' h; unfold ownHeld; split
    · exact List.nil_subset _
    · exact h
  -- the result binding says no less than the interface's result
  have hwx : EntryWeaker Ex1 (callRes (kill .replace false c Γ) sig (c :: zs)) := by
    have hEx1m : Ex1.mode = resMode fn := by simp [Ex1, callX]
    refine RSetup.EntryWeaker.mk' (by simp [callRes, Ex1, hErt, callRes, hrt]) (by simp [callRes, hEx1m, resMode, hro])
      (fun hf => by
        unfold Entry.fixed at hf; rw [hEx1m] at hf
        rcases hf with h | ⟨b', h, _⟩ <;> (unfold resMode at h; split at h <;> cases h))
      (by simp [callRes, Ex1, hErl]) (fun _ => ?_) ?_ (fun h => by simp [Ex1, hErd] at h) (by simp [callRes, Ex1, hErdb])
      (fun h => by simp [callRes] at h) (fun h => by simp [Ex1, hErdb] at h)
    · intro d hd
      have := hErp hd
      simp only [callRes, hfl0, hsl, List.flatMap_nil, List.nil_append] at this ⊢
      exact hsubH this
    · intro d hd
      have := hErh hd
      simp only [callRes, hfr0, hsr, List.flatMap_nil, List.nil_append, hro, hrt] at this ⊢
      exact hown_sub _ _ hsubH this
  -- the package says no less than the interface's receiver
  have hEpkF : ¬ Epk.fixed := by
    unfold Entry.fixed; simp only [Epk, hEcd1.1, hmo]; simp
  have hHyS : HyR ⊆ HcS := by
    intro d hd
    simp only [HyR, HcS, hck] at hd ⊢
    by_cases hv : te.holdsView = true
    · have hqv : q.views = true := by
        cases hqv : q.views
        · rw [(hq.1 hqv).1] at hv; cases hv
        · rfl
      simp only [hv, ↓reduceIte, outHeld_nil hfo0, List.append_nil] at hd
      simp only [Ty.holdsView, hqv, ↓reduceIte, outHeld_nil hso, List.append_nil]
      rcases List.mem_append.mp hd with h | h
      · exact List.mem_append_left _ (hEch ▸ hyh h)
      · exact List.mem_append_right _ (hsubH h)
    · simp only [hv, Bool.false_eq_true, ↓reduceIte] at hd
      have h1 : d ∈ Ec.held := hEch ▸ hyh hd
      split
      · exact List.mem_append_left _ (List.mem_append_left _ h1)
      · exact h1
  have hw0 : EntryWeaker Epk Ec1 :=
    RSetup.EntryWeaker.mk' (by simp [Ec1, Epk, hck, htc]) (by simp [Ec1, Epk, hck, hEcd1.1]) hEpkF
      (by simp [Ec1, Epk, hck, hlc]) (fun _ => by show [] ⊆ _; exact List.nil_subset _)
      (fun d hd => by simpa [Ec1, Epk, capDeps] using hHyS (by simpa [Epk, capDeps, Ey1] using hd))
      (fun h => by simp [Epk] at h) (by simp [Ec1, Epk, hck, hdbc]) (fun h => by simp [Ec1, hck, hdtc] at h)
      (fun h => by simp [Epk] at h) (fun _ _ hb _ => by simp [Ec1, hck, hmo] at hb)
      (fun _ hb _ => by simp [Ec1, hck, hmo] at hb)
  -- (AGORA-927: the parameters beside the receiver only end the source's package)
  obtain ⟨Esc, hEsc, hwEsc⟩ := callPostAux_weakR (Γ0 := kill .replace false c Γ) (fn := sig) (args := c :: zs)
    hEpkF ps zs 1 (setE (kill b (Ty.fn ms q).elem.holdsView c (kill .replace false c Γ)) c Ec1)
    (fun pa hpa _ => (hzX pa hpa).2.2.2) Ec1 (by simp [setE]) hw0
  have hwc : EntryWeaker Epk (killE .replace false c (RSetup.killAll (mutNames (kill .replace false c Γ) (c :: zs)) Esc)) := by
    have h1 := weaker_killAll_more (Mc := []) (M := mutNames (kill .replace false c Γ) (c :: zs)) hwEsc
      (fun d hd => by cases hd) (fun hf => absurd hf hEpkF)
    rw [killAll_id (fun d hd => by cases hd)] at h1
    exact h1.killR fun hf => absurd hf hEpkF
  have h4 : HandRel Γ [x, m.nv, m.nv + 1, c] (setE Γ2 x Ex1) (callPost (kill .replace false c Γ) sig (c :: zs)) := by
    rw [hΓ2eq]; exact (h3.setD (by simp) _).setD (by simp) _
  have h7 : HandRel Γ [x, m.nv, m.nv + 1, c] Γ4 (callPost (kill .replace false c Γ) sig (c :: zs)) := by
    have h6 : HandRel Γ [x, m.nv, m.nv + 1, c] Γ3 (callPost (kill .replace false c Γ) sig (c :: zs)) := by
      show HandRel Γ _ (exitScope (m.nv + 1) (setE (kill .replace false x Γ2) x Ex1)) _
      rw [hΓ3]; exact h4.updD (by simp) none
    exact (h6.killD_fresh hΓy .replace false).setD (by simp) _
  have h10 : HandRel Γ [x, m.nv, m.nv + 1, c] (setE (kill .replace false c Γ4) c Epk)
      (kill .replace false c (setE (callPost (kill .replace false c Γ) sig (c :: zs)) x
        (callRes (kill .replace false c Γ) sig (c :: zs)))) :=
    ((h7.setS (by simp) _).kill2 .replace false c hfixc).setD (by simp) Epk
  have hend : exitScope m.nv (setE (kill .replace false c Γ4) c Epk) = upd (setE (kill .replace false c Γ4) c Epk) m.nv none := by
    unfold exitScope; rw [hrootp.kill_fresh hΓy]
  -- the source's context is well formed
  have hdom1 := (CallT.domTy hcT0).1
  have hnone1 : ∀ v, Γ v = none → callPost (kill .replace false c Γ) sig (c :: zs) v = none := fun v hv => by
    have := hdom1 v; simp only [kill, hv, Option.map_none, Option.isSome_none] at this
    cases h : callPost (kill .replace false c Γ) sig (c :: zs) v with
    | none => rfl
    | some _ => rw [h] at this; simp at this
  have hwk : CtxWF (kill .replace false c Γ) := hi.wf.kill _ _ _
  obtain ⟨hw1, _, hEroots⟩ := CallT.wf hP hcT0 hwk
  have hwsrc := (hw1.add (hnone1 x hx) (fun _ _ => hEroots) (fun h => absurd h (by simp [callRes]))
    (fun h => absurd h (by simp [callRes])) (fun h => absurd h (by simp [callRes]))).kill .replace false c
  obtain ⟨hn1, hEn, _⟩ := CallT.names hP hcT0 (hi.names.kill .replace false c)
  have hnsrc := (NameWF.setE hn1 (fun Ex h => by rw [hnone1 x hx] at h; cases h)
    (fun Ex h => by rw [hnone1 x hx] at h; cases h) hEn).kill .replace false c
  rw [hend]
  refine ⟨fun v => ?_, hwsrc, hnsrc⟩
  by_cases hvX : v ∈ [x, m.nv, m.nv + 1, c]
  · simp only [List.mem_cons, List.not_mem_nil, or_false] at hvX
    rcases hvX with hv | hv | hv | hv <;> rw [hv]
    · -- the result
      have hr : upd (setE (kill .replace false c Γ4) c Epk) m.nv none x = some (killE .replace false c Ex1) := by
        have h3x' : Γ3 x = some Ex1 := h3x
        simp only [upd_ne _ _ hxy, setE, upd_ne _ _ hxc, kill, Γ4, h3x', Option.map_some]
        rw [hEx1R.killE_fresh hΓy]
      have hs : kill .replace false c (setE (callPost (kill .replace false c Γ) sig (c :: zs)) x
          (callRes (kill .replace false c Γ) sig (c :: zs))) x =
          some (killE .replace false c (callRes (kill .replace false c Γ) sig (c :: zs))) := by
        simp [kill, setE]
      rw [hr, hs]
      exact ⟨by simp, fun E1 E2 h1 h2 => by cases h1; cases h2; exact killE_weaker hwx⟩
    · -- the environment's binding, gone
      have hs : kill .replace false c (setE (callPost (kill .replace false c Γ) sig (c :: zs)) x
          (callRes (kill .replace false c Γ) sig (c :: zs))) m.nv = none := by
        simp [kill, setE, upd_ne _ _ (Ne.symm hxy), hnone1 _ hΓy]
      rw [hs]; exact ⟨by simp, fun E1 E2 h1 _ => by simp at h1⟩
    · -- the inner result, gone
      have hr : upd (setE (kill .replace false c Γ4) c Epk) m.nv none (m.nv + 1) = none := by
        have h3r' : Γ3 (m.nv + 1) = none := h3r
        simp [setE, upd_ne _ _ hrc, kill, Γ4, h3r']
      have hs : kill .replace false c (setE (callPost (kill .replace false c Γ) sig (c :: zs)) x
          (callRes (kill .replace false c Γ) sig (c :: zs))) (m.nv + 1) = none := by
        simp [kill, setE, upd_ne _ _ hrx, hnone1 _ hΓr]
      rw [hr, hs]; exact ⟨Iff.rfl, fun E1 E2 h1 _ => by cases h1⟩
    · -- the package, its environment back
      have hr : upd (setE (kill .replace false c Γ4) c Epk) m.nv none c = some Epk := by
        simp [upd_ne _ _ hyc.symm, setE]
      have hs : kill .replace false c (setE (callPost (kill .replace false c Γ) sig (c :: zs)) x
          (callRes (kill .replace false c Γ) sig (c :: zs))) c =
          some (killE .replace false c (RSetup.killAll (mutNames (kill .replace false c Γ) (c :: zs)) Esc)) := by
        have hpc : callPost (kill .replace false c Γ) sig (c :: zs) c =
            some (RSetup.killAll (mutNames (kill .replace false c Γ) (c :: zs)) Esc) := by
          rw [hΓ1, RSetup.killNames_eq, hEsc]; rfl
        simp only [kill, setE, upd_ne _ _ (Ne.symm hxc), hpc, Option.map_some]
      rw [hr, hs]
      exact ⟨by simp, fun E1 E2 h1 h2 => by cases h1; cases h2; exact hwc⟩
  · obtain ⟨h1, h2⟩ := h10.updD (by simp : m.nv ∈ [x, m.nv, m.nv + 1, c]) none v hvX
    exact ⟨h1, fun E1 E2 hE1 hE2 => (h2 E1 E2 hE1 hE2).1⟩

/-- Agora #609: **the hand-over to a drop method, typed**: in the hand-over's
    context (the package moved out, its environment in the fresh binding), the
    code's call takes the environment owned, its result goes to `x`, and the
    environment's scope ends moved out; what is left says no less than what
    the interface's call leaves.  The package holds nothing (`Ec.vdeps = []`:
    it is its glue's own parameter), so every entry made here holds nothing. -/
theorem handD_typed {P : Prog} (hP : ProgOK P) {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanchF : RootbAnchF Γ F) (hFlt : ∀ v ∈ F, v < m.nv)
    {c x : Var} {Ec E : Entry} {Γ1 : Ctx} {σ f : Nat} {sig fn : Fn} {ms : List Nat} {q : Cross}
    {te : Ty} (hc : Γ c = some Ec) (htu : Ec.ty.undtor = .fn ms q) (hmo : Ec.mode = .own)
    (hvd : Ec.vdeps = [])
    (hx : Γ x = none) (hxn : x < m.nv) (hxF : x ∉ F) (hcF : c ∉ F) (hny : NoPin Γ c)
    (hcT : CallT P (kill .replace false c Γ) F σ [c] E Γ1) (hσ : P[σ]? = some sig)
    (hsp : sig.params = [(.sink, Ec.ty)]) (hsl : sig.lends = []) (hsr : sig.rholds = [])
    (hf : P[f]? = some fn) (hps : fn.params = [(.sink, te)]) (hto : te.owning = true) (hnt : ¬ ThruFn P f)
    (hrt : fn.resTy = sig.resTy) (hro : fn.resOwn = sig.resOwn) (hfl : fn.lends ⊆ sig.lends)
    (hfr : fn.rholds ⊆ sig.rholds) :
    ∃ Γe, StmtT P ξ (handCtx Γ c x Ec te m.nv (callX fn)) F
      (.scope m.nv (.letcall (m.nv + 1) f [m.nv] (.assign x (.var (m.nv + 1))))) Γe ∧
      Weaker Γe (kill .replace false c (setE Γ1 x E)) := by
  have hanch : RootbAnch Γ F := hanchF.toH
  have hcT0 := hcT
  obtain ⟨sig', hσ', _, _, _, _, hE, hΓ1, _⟩ := hcT
  rw [hσ] at hσ'; cases hσ'
  subst hE hΓ1
  have hτ : Ec.ty ≠ .int := fun h => by rw [h] at htu; cases htu
  have hos : Ec.mode.ownSlot = true := by rw [hmo]; rfl
  have hEh : Ec.held = [] := by simpa [Entry.vdeps, hos] using hvd
  have hnohit : ∀ (E0 : Entry) (e : Eff) (hb : Bool) (w : Var), E0.vdeps = [] → killE e hb w E0 = E0 :=
    fun E0 e hb w h0 => by unfold killE; simp [hits, h0]
  have hkc : killE .replace false c Ec = Ec := hnohit _ _ _ _ hvd
  have hΓkc : kill .replace false c Γ c = some Ec := by simp [kill, hc, hkc]
  have hck : argE (kill .replace false c Γ) c = Ec := by simp [argE, hΓkc]
  have hfl0 : fn.lends = [] := List.eq_nil_of_subset_nil (hsl ▸ hfl)
  have hfr0 : fn.rholds = [] := List.eq_nil_of_subset_nil (hsr ▸ hfr)
  -- where things are
  have hcn : c < m.nv := hi.nvSt c (by rw [← hi.dom, hc]; rfl)
  have hxy : x ≠ m.nv := fun e => by rw [e] at hxn; exact Nat.lt_irrefl _ hxn
  have hxc : x ≠ c := fun e => by rw [e, hc] at hx; cases hx
  have hyc : m.nv ≠ c := fun e => by rw [← e] at hcn; exact Nat.lt_irrefl _ hcn
  have hrx : m.nv + 1 ≠ x := fun e => by rw [← e] at hxn; have := vlt hxn; omega
  have hry : m.nv + 1 ≠ m.nv := by omega
  have hrc : m.nv + 1 ≠ c := fun e => by rw [← e] at hcn; have := vlt hcn; omega
  have hΓfresh : ∀ v, m.nv ≤ v → Γ v = none := fun v hv => by
    cases h : Γ v with
    | none => rfl
    | some E0 =>
      have h1 := hi.nvSt v (by rw [← hi.dom, h]; rfl)
      exact absurd (Nat.lt_of_lt_of_le h1 hv) (Nat.lt_irrefl _)
  have hΓy : Γ m.nv = none := hΓfresh _ (Nat.le_refl _)
  have hΓr : Γ (m.nv + 1) = none := hΓfresh _ (Nat.le_succ _)
  have hyF : m.nv ∉ F := fun h => Nat.lt_irrefl _ (hFlt _ h)
  have hrF : m.nv + 1 ∉ F := fun h => by have := vlt (hFlt _ h); omega
  have hrootb_c : ∀ v E0, Γ v = some E0 → E0.fixed → ∀ e hb, killE e hb c E0 = E0 := by
    intro v E0 hv hf e hb
    rcases hf with hm | ⟨b', hm, _⟩
    · exact killE_rootb hanch hcF e hb (hny.kills e hb) (HeldSpared.of_none (NoHeld.of_anchF hanchF hcF) _ _) hv hm
    · exact absurd hm (hi.noInout v E0 b' hv)
  -- the environment's binding
  let Γh := handCtx Γ c x Ec te m.nv (callX fn)
  have hEy : compE Ec te = ⟨te, .own, true, [], [], false, false, false, false⟩ := by
    rw [compE_owning Ec hto, hEh]; simp [ownHeld]
  have hEyt : (compE Ec te).ty ≠ .int := by
    rw [hEy]; intro h; simp only at h; subst h; simp [Ty.owning] at hto
  have hEyv : (compE Ec te).vdeps = [] := by rw [hEy]; simp [Entry.vdeps, Mode.ownSlot]
  have hhy : Γh m.nv = some (compE Ec te) := handCtx_y hxy
  have hyE : argE Γh m.nv = compE Ec te := by simp only [argE, hhy, Option.getD_some]
  have hhx : Γh x = some (callX fn) := handCtx_x
  have hhc : Γh c = some { Ec with live := false, dtor := false } := handCtx_c hxc hyc
  have hhr : Γh (m.nv + 1) = none := (handCtx_other hrx hry hrc).trans (by simp [kill, hΓr])
  have hho : ∀ v, v ≠ x → v ≠ m.nv → v ≠ c → Γh v = kill .replace false c Γ v :=
    fun v h1 h2 h3 => handCtx_other h1 h2 h3
  have hrootΓ : AllRooted Γ (kill .replace false c Γ) :=
    fun v E0 hv => by
      simp only [kill] at hv
      obtain ⟨E1, h1, rfl⟩ := Option.map_eq_some_iff.mp hv
      exact (hi.rooted h1).killE _ _ _
  have hrooth : AllRooted Γ Γh :=
    ((hrootΓ.setE (Rooted.of_dead rfl)).setE (Rooted.of_roots fun d hd => by rw [hEyv] at hd; cases hd)).setE
      (Rooted.of_dead rfl)
  have hfrΓk : FrameOK Γ (kill .replace false c Γ) :=
    (FrameOK.refl Γ).kill _ _ _ fun p E0 hp hm => hrootb_c p E0 hp (Or.inl hm) _ _
  have hfrh : FrameOK Γ Γh :=
    ((hfrΓk.setE' (E := { Ec with live := false, dtor := false }) (by simp [hmo]) rfl
      (fun h => ⟨Ec, hc, h, rfl, rfl, rfl⟩)).setE (by rw [hEy]; simp) (by rw [hEy])
      (by rw [hEy])).setE
      (resMode_ne' fn) rfl rfl
  -- the code's call takes the environment owned
  have hnm : mutNames Γh [m.nv] = [] := by
    simp [mutNames, argNames, hyE, hEyv, nameDeps]
  let Eyd : Entry := { compE Ec te with live := false, dtor := false }
  have hΓ1' : callPost Γh fn [m.nv] = setE Γh m.nv Eyd := by
    have : callPost Γh fn [m.nv] = setE (kill .replace false m.nv Γh) m.nv Eyd := by
      simp [callPost, hnm, killNames, hps, callPostAux, hyE, Eyd]
    rw [this, hrooth.kill_fresh hΓy]
  have hcT' : CallT P Γh F f [m.nv] (callRes Γh fn [m.nv]) (callPost Γh fn [m.nv]) := by
    refine ⟨fn, hf, by simp [hps], fun i hlt => ?_, fun d hd => ?_, ?_, rfl, rfl, fun h => absurd h hnt⟩
    · have hi0 : i = 0 := by simp [hps] at hlt; omega
      subst hi0
      refine ⟨compE Ec te, by simpa using hhy, by rw [hEy], ?_, fun _ => ⟨by simpa using hyF,
        by simp [hEyv, memDeps, roots], fun _ => by simp [hEyv, roots], fun b hb => by simp [hps] at hb,
        fun j hj hne => ?_⟩, fun _ => by simpa using hfrh.noPin_fresh hi hΓy⟩
      · simp [hps, paramOK, hEy, hto]
      · simp [hps] at hj; omega
    · rw [hnm] at hd; cases hd
    · refine ⟨fun i hlt => ⟨fun _ => ?_, fun b hb => ?_⟩, fun d hd => ?_, fun i hlt b hb => ?_⟩
      · have hi0 : i = 0 := by simp [hps] at hlt; omega
        subst hi0; simpa using hfrh.dtorSafe (DtorSafe.of_fresh hi.wf hΓy _ _)
      · have hi0 : i = 0 := by simp [hps] at hlt; omega
        subst hi0; simp [hps] at hb
      · rw [hnm] at hd; cases hd
      · have hi0 : i = 0 := by simp [hps] at hlt; omega
        subst hi0; simp [hps] at hb
  have h1x : callPost Γh fn [m.nv] x = some (callX fn) := by
    rw [hΓ1']; simp [setE, upd_ne _ _ hxy, hhx]
  have h1r : callPost Γh fn [m.nv] (m.nv + 1) = none := by
    rw [hΓ1']; simp [setE, hhr]
  have h1c : callPost Γh fn [m.nv] c = some { Ec with live := false, dtor := false } := by
    rw [hΓ1']; simp [setE, upd_ne _ _ hyc.symm, hhc]
  have hroot1 : AllRooted Γ (callPost Γh fn [m.nv]) := by
    rw [hΓ1']; exact hrooth.setE (Rooted.of_dead rfl)
  have hfr1 : FrameOK Γ (callPost Γh fn [m.nv]) := by
    rw [hΓ1']; exact hfrh.setE (by simp [Eyd, hEy]) rfl (by simp [Eyd, hEy])
  -- the inner call's result holds nothing
  have hres : callRes Γh fn [m.nv] = ⟨fn.resTy, resMode fn, true, [], [], false, false, false, false⟩ := by
    simp [callRes, hfl0, hfr0, heldOfArgs, argNames, hyE, hEy, Entry.vdeps, nameDeps, memDeps, argMem, compAll,
      ownHeld, Mode.ownSlot]
  have hE'R : Rooted Γ (callRes Γh fn [m.nv]) := Rooted.of_roots fun d hd => by
    rw [hres] at hd; simp [Entry.vdeps] at hd
  have hE'm : (callRes Γh fn [m.nv]).mode = .own ∨ (callRes Γh fn [m.nv]).mode = .bor := by
    simp only [callRes, resMode]; split <;> simp
  let Γr := setE (callPost Γh fn [m.nv]) (m.nv + 1) (callRes Γh fn [m.nv])
  have hrootr : AllRooted Γ Γr := hroot1.setE hE'R
  have hfrr : FrameOK Γ Γr := hfr1.setE (resMode_ne' fn) rfl rfl
  obtain ⟨Er, Γ2, hRhs, hErm, hErt, hErl, hErp, hErh, hErd, hErdb, hΓ2⟩ :=
    hand_res (Γr := Γr) (F := F) (by simp [Γr, setE]) rfl hrF (hfrr.noPin_fresh hi hΓr)
      (hfrr.dtorSafe (DtorSafe.of_fresh hi.wf hΓr _ _)) hE'm
  obtain ⟨Er2, hΓ2eq, hEr2m, hEr2d, hEr2db, hEr2R⟩ : ∃ Er2, Γ2 = setE (callPost Γh fn [m.nv]) (m.nv + 1) Er2 ∧
      Er2.mode = (callRes Γh fn [m.nv]).mode ∧ Er2.dtor = false ∧ Er2.dbind = false ∧ Rooted Γ Er2 := by
    rcases hΓ2 with h | h
    · refine ⟨{ callRes Γh fn [m.nv] with live := false, dtor := false }, ?_, rfl, rfl, rfl, Rooted.of_dead rfl⟩
      rw [h, hrootr.kill_fresh hΓr]
      funext v; simp only [Γr, setE, upd]; split <;> rfl
    · exact ⟨_, h, rfl, rfl, rfl, hE'R⟩
  have hroot2 : AllRooted Γ Γ2 := by rw [hΓ2eq]; exact hroot1.setE hEr2R
  have hfr2 : FrameOK Γ Γ2 := by
    rw [hΓ2eq]; exact hfr1.setE (by rw [hEr2m]; exact resMode_ne' fn) hEr2d hEr2db
  have hErv0 : Er.vdeps = [] := by
    have h1 := hErp; have h2 := hErh
    rw [hres] at h1 h2
    simp [Entry.vdeps, List.subset_nil.mp h1, List.subset_nil.mp h2]
  have hxroot : x ∉ roots Er.vdeps := by rw [hErv0]; simp [roots]
  have hmodes : ((callX fn).mode = .own ∧ Er.mode = .own) ∨ ((callX fn).mode = .inout .replace ∧ Er.mode = .own) ∨
      ((callX fn).mode = .bor ∧ Er.mode = .bor) := by
    rw [hErm]; simp only [callX, callRes, resMode]; split <;> simp
  have hTasg : StmtT P ((ξ.under m.nv).under (m.nv + 1)) Γr F (.assign x (.var (m.nv + 1)))
      (setE (kill .replace false x Γ2) x { Er with mode := (callX fn).mode }) :=
    StmtT.assign (by simp [Γr, setE, upd_ne _ _ (Ne.symm hrx), h1x]) hxF hmodes hRhs
      (by rw [hErt]; rfl) hxroot (by rw [hΓ2eq]; simp [setE, upd_ne _ _ (Ne.symm hrx), h1x])
      (hfrr.noPin_fresh hi hx) (hfr2.dtorSafe (DtorSafe.of_fresh hi.wf hx _ _)) rfl
  let Ex1 : Entry := { Er with mode := (callX fn).mode }
  have hΔr : setE (kill .replace false x Γ2) x Ex1 = setE Γ2 x Ex1 := by rw [hroot2.kill_fresh hx]
  have hEx1 : Ex1 = Er := by
    have hmEq : (callX fn).mode = Er.mode := by rw [hErm]; rfl
    simp only [Ex1, hmEq]
  have hEx1R : Rooted Γ Ex1 := Rooted.of_roots fun d hd => by
    rw [hEx1, hErv0] at hd; cases hd
  have hfrΔ : FrameOK Γ (setE (kill .replace false x Γ2) x Ex1) := by
    rw [hΔr]; exact hfr2.setE (resMode_ne' fn) hErd hErdb
  have hTcall : StmtT P (ξ.under m.nv) Γh F (.letcall (m.nv + 1) f [m.nv] (.assign x (.var (m.nv + 1))))
      (exitScope (m.nv + 1) (setE (kill .replace false x Γ2) x Ex1)) :=
    StmtT.letcall rfl hhr hrF hcT' hTasg (hfrΔ.endOK_fresh hi hΓr)
      -- (A2-drop.3a: the code's result moves into `x` at once, whose
      -- binder, the call through the package, answers for it)
      (fun _ _ _ _ => by simp [Stmt.movedFirst, Stmt.assigns]; exact hrx)
  have hrootΔ : AllRooted Γ (setE Γ2 x Ex1) := hroot2.setE hEx1R
  have hΓ3 : exitScope (m.nv + 1) (setE (kill .replace false x Γ2) x Ex1) = upd (setE Γ2 x Ex1) (m.nv + 1) none := by
    unfold exitScope; rw [hΔr, hrootΔ.kill_fresh hΓr]
  have hroot3 : AllRooted Γ (exitScope (m.nv + 1) (setE (kill .replace false x Γ2) x Ex1)) := by
    rw [hΓ3]; exact hrootΔ.upd_none _
  have hfr3 : FrameOK Γ (exitScope (m.nv + 1) (setE (kill .replace false x Γ2) x Ex1)) := by
    rw [hΓ3]; exact (hΔr ▸ hfrΔ).upd_none _
  have h3x : exitScope (m.nv + 1) (setE (kill .replace false x Γ2) x Ex1) x = some Ex1 := by
    rw [hΓ3]; simp [setE, upd_ne _ _ (Ne.symm hrx)]
  have h3r : exitScope (m.nv + 1) (setE (kill .replace false x Γ2) x Ex1) (m.nv + 1) = none := by
    rw [hΓ3]; simp
  let Γ3 := exitScope (m.nv + 1) (setE (kill .replace false x Γ2) x Ex1)
  let Γ3 := exitScope (m.nv + 1) (setE (kill .replace false x Γ2) x Ex1)
  have h3c : Γ3 c = some { Ec with live := false, dtor := false } := by
    show exitScope (m.nv + 1) (setE (kill .replace false x Γ2) x Ex1) c = _
    rw [hΓ3, hΓ2eq]; simp [setE, upd_ne _ _ (Ne.symm hrc), upd_ne _ _ (Ne.symm hxc), h1c]
  have hend : exitScope m.nv Γ3 = upd Γ3 m.nv none := by
    unfold exitScope; rw [hroot3.kill_fresh hΓy]
  refine ⟨_, StmtT.scope ⟨compE Ec te, hhy, by rw [hEy]; simp⟩ hyF hTcall (hfr3.endOK_fresh hi hΓy), ?_⟩
  show Weaker (exitScope m.nv Γ3) _
  -- the interface's call, in the source: the package moved out, nothing else touched
  have hnmS : mutNames (kill .replace false c Γ) [c] = [] := by
    simp [mutNames, argNames, hck, hvd, nameDeps]
  have hΓ1s : callPost (kill .replace false c Γ) sig [c] =
      setE (kill .replace false c (kill .replace false c Γ)) c { Ec with live := false, dtor := false } := by
    simp [callPost, hnmS, killNames, hsp, callPostAux, hck]
  have hEs : callRes (kill .replace false c Γ) sig [c] = ⟨sig.resTy, resMode sig, true, [], [], false, false, false, false⟩ := by
    simp [callRes, hsl, hsr, heldOfArgs, argNames, hck, hEh, Entry.vdeps, nameDeps, memDeps, argMem, compAll,
      ownHeld, hos]
  have hwx : EntryWeaker Ex1 (callRes (kill .replace false c Γ) sig [c]) := by
    have hEx1m : Ex1.mode = resMode fn := by simp [Ex1, callX]
    have hEx1v : Ex1.path = [] ∧ Ex1.held = [] := by
      have h1 := hErp; have h2 := hErh
      rw [hres] at h1 h2
      exact ⟨by simpa [Ex1] using List.subset_nil.mp h1, by simpa [Ex1] using List.subset_nil.mp h2⟩
    rw [hEs]
    refine RSetup.EntryWeaker.mk' (by simp [Ex1, hErt, hres, hrt]) (by simp [hEx1m, resMode, hro])
      (fun hf => by
        unfold Entry.fixed at hf; rw [hEx1m] at hf
        rcases hf with h | ⟨b', h, _⟩ <;> (unfold resMode at h; split at h <;> cases h))
      (by simp [Ex1, hErl]) (fun _ => by rw [hEx1v.1]; exact List.nil_subset _)
      (by rw [hEx1v.2]; exact List.nil_subset _) (fun h => by simp [Ex1, hErd] at h) (by simp [Ex1, hErdb])
      (fun h => by simp at h) (fun h => by simp [Ex1, hErdb] at h)
  have hfixc : ∀ v E0, Γ v = some E0 → E0.fixed → killE .replace false c E0 = E0 :=
    fun v E0 hv hf => hrootb_c v E0 hv hf _ _
  have hXn : ∀ v, v ∉ [x, m.nv, m.nv + 1, c] → v ≠ x ∧ v ≠ m.nv ∧ v ≠ m.nv + 1 ∧ v ≠ c := by
    intro v hv; simp only [List.mem_cons, List.not_mem_nil, or_false, not_or] at hv; exact hv
  have h0 : HandRel Γ [x, m.nv, m.nv + 1, c] Γh (kill .replace false c Γ) := by
    intro v hv
    obtain ⟨h1, h2, _, h4⟩ := hXn v hv
    refine ⟨by rw [hho v h1 h2 h4], fun Ed Es hd hs => ?_⟩
    rw [hho v h1 h2 h4] at hd
    rw [hd] at hs; cases hs
    refine ⟨EntryWeaker.refl _, hrootΓ v Ed hd, fun hf => ?_⟩
    simp only [kill] at hd
    obtain ⟨E0, h0', rfl⟩ := Option.map_eq_some_iff.mp hd
    have hf0 : E0.fixed := by unfold Entry.fixed at hf ⊢; rwa [killE_mode, killE_ty] at hf
    rw [hrootb_c v E0 h0' hf0]; exact h0'
  have h3 : HandRel Γ [x, m.nv, m.nv + 1, c] (callPost Γh fn [m.nv]) (callPost (kill .replace false c Γ) sig [c]) := by
    rw [hΓ1', hΓ1s]
    exact ((h0.killS .replace false c hfixc).setD (by simp) Eyd).setS (by simp) _
  have h4 : HandRel Γ [x, m.nv, m.nv + 1, c] (setE Γ2 x Ex1) (callPost (kill .replace false c Γ) sig [c]) := by
    rw [hΓ2eq]; exact (h3.setD (by simp) _).setD (by simp) _
  have h6 : HandRel Γ [x, m.nv, m.nv + 1, c] Γ3 (callPost (kill .replace false c Γ) sig [c]) := by
    show HandRel Γ _ (exitScope (m.nv + 1) (setE (kill .replace false x Γ2) x Ex1)) _
    rw [hΓ3]; exact h4.updD (by simp) none
  have h10 : HandRel Γ [x, m.nv, m.nv + 1, c] Γ3
      (kill .replace false c (setE (callPost (kill .replace false c Γ) sig [c]) x
        (callRes (kill .replace false c Γ) sig [c]))) :=
    (h6.setS (by simp) _).killS .replace false c hfixc
  -- the source's context is well formed
  have hdom1 := (CallT.domTy hcT0).1
  have hnone1 : ∀ v, Γ v = none → callPost (kill .replace false c Γ) sig [c] v = none := fun v hv => by
    have := hdom1 v; simp only [kill, hv, Option.map_none, Option.isSome_none] at this
    cases h : callPost (kill .replace false c Γ) sig [c] v <;> simp_all
  have hwk : CtxWF (kill .replace false c Γ) := hi.wf.kill _ _ _
  obtain ⟨hw1, _, hEroots⟩ := CallT.wf hP hcT0 hwk
  have hwsrc := (hw1.add (hnone1 x hx) (fun _ _ => hEroots) (fun h => absurd h (by simp [callRes]))
    (fun h => absurd h (by simp [callRes])) (fun h => absurd h (by simp [callRes]))).kill .replace false c
  obtain ⟨hn1, hEn, _⟩ := CallT.names hP hcT0 (hi.names.kill .replace false c)
  have hnsrc := (NameWF.setE hn1 (fun Ex h => by rw [hnone1 x hx] at h; cases h)
    (fun Ex h => by rw [hnone1 x hx] at h; cases h) hEn).kill .replace false c
  rw [hend]
  refine ⟨fun v => ?_, hwsrc, hnsrc⟩
  by_cases hvX : v ∈ [x, m.nv, m.nv + 1, c]
  · simp only [List.mem_cons, List.not_mem_nil, or_false] at hvX
    rcases hvX with hv | hv | hv | hv <;> rw [hv]
    · -- the result
      have hr : upd Γ3 m.nv none x = some Ex1 := by
        rw [upd_ne _ _ hxy]; exact h3x
      have hs : kill .replace false c (setE (callPost (kill .replace false c Γ) sig [c]) x
          (callRes (kill .replace false c Γ) sig [c])) x = some (callRes (kill .replace false c Γ) sig [c]) := by
        simp only [kill, setE, upd_same, Option.map_some]
        rw [hnohit _ _ _ _ (by rw [hEs]; simp [Entry.vdeps])]
      rw [hr, hs]
      exact ⟨by simp, fun E1 E2 h1 h2 => by cases h1; cases h2; exact hwx⟩
    · -- the environment's binding, gone
      have hs : kill .replace false c (setE (callPost (kill .replace false c Γ) sig [c]) x
          (callRes (kill .replace false c Γ) sig [c])) m.nv = none := by
        simp [kill, setE, upd_ne _ _ (Ne.symm hxy), hnone1 _ hΓy]
      rw [hs]; exact ⟨by simp, fun E1 E2 h1 _ => by simp at h1⟩
    · -- the inner result, gone
      have hr : upd Γ3 m.nv none (m.nv + 1) = none := by
        rw [upd_ne _ _ hry]; exact h3r
      have hs : kill .replace false c (setE (callPost (kill .replace false c Γ) sig [c]) x
          (callRes (kill .replace false c Γ) sig [c])) (m.nv + 1) = none := by
        simp [kill, setE, upd_ne _ _ hrx, hnone1 _ hΓr]
      rw [hr, hs]; exact ⟨Iff.rfl, fun E1 E2 h1 _ => by cases h1⟩
    · -- the package, moved out on both sides
      have hr : upd Γ3 m.nv none c = some { Ec with live := false, dtor := false } := by
        rw [upd_ne _ _ hyc.symm]; exact h3c
      have hs : kill .replace false c (setE (callPost (kill .replace false c Γ) sig [c]) x
          (callRes (kill .replace false c Γ) sig [c])) c = some { Ec with live := false, dtor := false } := by
        rw [hΓ1s]
        simp only [kill, setE, upd_ne _ _ (Ne.symm hxc), upd_same, Option.map_some]
        rw [hnohit _ _ _ _ (by simpa [Entry.vdeps] using hvd)]
      rw [hr, hs]
      exact ⟨by simp, fun E1 E2 h1 h2 => by cases h1; cases h2; exact EntryWeaker.refl _⟩
  · obtain ⟨h1, h2⟩ := h10.updD (by simp : m.nv ∈ [x, m.nv, m.nv + 1, c]) none v hvX
    exact ⟨h1, fun E1 E2 hE1 hE2 => (h2 E1 E2 hE1 hE2).1⟩

/-! ### The cases of preservation and progress -/

/-- What a hand-over finds: the package `c`, live where every dependency on
    it has ended, an owner (at run time no binding is `inout`) whose slot
    owns a package of the interfaces; its code for the method takes the
    environment `inout`, and it captures nothing by name. -/
theorem hand_found {P : Prog} {m : Mem} {Γ Γ1 : Ctx} {F : List Var} (hi : MInv m Γ) (hcd : MemCodes P m)
    {c : Var} {Ec E : Entry} {ms : List Nat} {q : Cross} {j σ : Nat} {sig : Fn} {b : Eff}
    (hc : Γ c = some Ec) (htc : Ec.ty = .fn ms q) (hcan : canDo Ec.mode .replace) (hj : ms[j]? = some σ)
    {zs : List Var} {ps : List (PMode × Ty)}
    (hσ : P[σ]? = some sig) (hsp : sig.params = (.inout b, .fn ms q) :: ps)
    (hcT : CallT P (kill .replace false c Γ) F σ (c :: zs) E Γ1) :
    Ec.live = true ∧ Ec.mode = .own ∧ ∃ fs te env f fn, m.st c = some ⟨true, some (.pkg fs te ms env [])⟩ ∧
      fs[j]? = some f ∧ P[f]? = some fn ∧ fn.params = (.inout b, te) :: ps ∧ fn.resTy = sig.resTy ∧
      fn.resOwn = sig.resOwn ∧ fn.lends ⊆ sig.lends ∧ fn.rholds ⊆ sig.rholds ∧ fn.outHolds ⊆ sig.outHolds ∧
      ¬ ThruFn P f := by
  have hτ : Ec.ty ≠ .int := by rw [htc]; simp
  obtain ⟨sig', hσ', _, hargs, _⟩ := hcT
  rw [hσ] at hσ'; cases hσ'
  obtain ⟨Ea, hEa, hla, _⟩ := hargs 0 (by simp [hsp])
  simp only [List.getD_cons_zero, kill, hc, Option.map_some, Option.some.injEq] at hEa
  subst hEa
  obtain ⟨hlc, _⟩ := kill_live_self hla hτ
  have hmo : Ec.mode = .own := by
    rcases canDo_replace_cases hcan with h | h
    · exact h
    · exact absurd h (hi.noInout c Ec _ hc)
  obtain ⟨o, fs, te, env, cs, hslot⟩ := pkg_slot hi hc hlc (by rw [htc]; rfl)
  obtain ⟨sl, hsl, _, hso, _⟩ := hi.slot c Ec hc
  rw [hslot] at hsl; cases hsl
  rw [hmo] at hso; simp only [Mode.ownSlot] at hso; subst hso
  obtain ⟨f, fn, hfs, hf, hps, hcs, hrt, hro, hl, hr, ho, hnt⟩ := pkg_code_recv hcd hslot hj hσ
  have hrm : sig.recvMode = .inout b := Fn.recvMode_of_head (by rw [hsp]; rfl) (by simp)
  have hcs0 : cs = [] := hcs (by rw [hrm]; simp)
  subst hcs0
  rw [hrm, hsp] at hps
  -- (code that changes elements through a borrow takes its environment
  -- lent, `Implements`: this one is handed it)
  exact ⟨hlc, hmo, fs, te, env, f, fn, hslot, hfs, hf, by simpa using hps, hrt, hro, hl, hr, ho,
    fun ht => by have := (hnt ht).2.2; rw [hrm] at this; cases this⟩

/-- Agora #609: what the hand-over to a drop method finds: the package `c`,
    an owner whose slot owns a package of the interfaces; its code for the
    method takes the environment OWNED, and it captures nothing by name. -/
theorem hand_foundD {P : Prog} {m : Mem} {Γ : Ctx} (hi : MInv m Γ) (hcd : MemCodes P m)
    {c : Var} {Ec : Entry} {ms : List Nat} {q : Cross} {j σ : Nat} {sig : Fn}
    (hc : Γ c = some Ec) (htu : Ec.ty.undtor = .fn ms q) (hl : Ec.live = true) (hmo : Ec.mode = .own)
    (hj : ms[j]? = some σ) (hσ : P[σ]? = some sig) (hsp : sig.params = [(.sink, Ec.ty)]) :
    ∃ fs te env f fn, m.st c = some ⟨true, some (.pkg fs te ms env [])⟩ ∧
      fs[j]? = some f ∧ P[f]? = some fn ∧ fn.params = [(.sink, te)] ∧ fn.resTy = sig.resTy ∧
      fn.resOwn = sig.resOwn ∧ fn.lends ⊆ sig.lends ∧ fn.rholds ⊆ sig.rholds ∧ fn.outHolds ⊆ sig.outHolds ∧
      ¬ ThruFn P f ∧ q.Fits te [] := by
  obtain ⟨T, hT, hw, _⟩ := hi.own_val hc hl (by rw [hmo]; rfl)
  have hw' := hw.undtor
  rw [htu] at hw'
  cases hw' with
  | @pkg fs te _ _ env cs hwe hq =>
    obtain ⟨f, fn, hfs, hf, hps, hcs, hrt, hro, hl', hr, ho, hnt⟩ := pkg_code_recv hcd hT hj hσ
    have hrm : sig.recvMode = .sink := by unfold Fn.recvMode; rw [hsp]; rfl
    have hcs0 : cs = [] := hcs (by rw [hrm]; simp)
    subst hcs0
    rw [hrm, hsp] at hps
    exact ⟨fs, te, env, f, fn, hT, hfs, hf, by simpa using hps, hrt, hro, hl', hr, ho,
      (fun ht => by have := (hnt ht).2.2; rw [hrm] at this; cases this), hq⟩

/-- Agora #609: progress of the hand-over to a drop method. -/
theorem handProgressD {P : Prog} {Γ Γ1 : Ctx} {F : List Var} {x c : Var} {j : Nat} {k : Stmt} {Ec E : Entry}
    {ms : List Nat} {q : Cross} {σ : Nat} {sig : Fn} {m : Mem}
    (hx : Γ x = none) (hc : Γ c = some Ec) (htu : Ec.ty.undtor = .fn ms q)
    (hj : ms[j]? = some σ) (hσ : P[σ]? = some sig)
    (hD : sig.params = [(.sink, Ec.ty)] ∧ Ec.vdeps = [] ∧ Ec.mode = .own ∧ Ec.live = true ∧
      q.drops = true ∧ sig.resOwn = false)
    (_hcT : CallT P (kill .replace false c Γ) F σ [c] E Γ1) (hcd : MemCodes P m)
    (hi : Inv m Γ F (.callcE x c j [] k)) : ∃ r, Step P m (.callcE x c j [] k) r := by
  obtain ⟨hsp, _, hmo, hl, _, _⟩ := hD
  obtain ⟨_, _, _, _, _, hslot, hfs, hf, hps, _⟩ := hand_foundD hi.toMInv hcd hc htu hl hmo hj hσ hsp
  have hmx : m.st x = none := by
    have := hi.dom x; rw [hx] at this; cases h : m.st x <;> simp_all
  exact ⟨_, Step.callcD hslot hfs hf hmx (by rw [hps]; rfl)⟩

theorem handCaseD {P : Prog} (hP : ProgOK P) {Γ Γ1 : Ctx} {F : List Var} {x c : Var} {j : Nat} {k : Stmt}
    {Ec E : Entry} {ms : List Nat} {q : Cross} {σ : Nat} {sig : Fn} {Δ : Ctx} {m m' : Mem} {s' : Stmt}
    (hk : k.src = true) (hx : Γ x = none) (hxF : x ∉ F) (hc : Γ c = some Ec) (htu : Ec.ty.undtor = .fn ms q)
    (hj : ms[j]? = some σ) (hσ : P[σ]? = some sig)
    (hD : sig.params = [(.sink, Ec.ty)] ∧ Ec.vdeps = [] ∧ Ec.mode = .own ∧ Ec.live = true ∧
      q.drops = true ∧ sig.resOwn = false)
    (hsl : sig.lends = []) (hsr : sig.rholds = []) (_hso : sig.outHolds = [])
    (hny : NoPin Γ c) (hdc : DtorSafe Γ .replace false c)
    (hcT : CallT P (kill .replace false c Γ) F σ [c] E Γ1)
    (hkT : StmtT P (ξ.under x) (kill .replace false c (setE Γ1 x E)) F k Δ) (hpx : EndOK Δ x)
    (hcd : MemCodes P m) (hi : Inv m Γ F (.callcE x c j [] k))
    (hst : Step P m (.callcE x c j [] k) (.ok m' s')) (hnr : ¬ IsReap m (.callcE x c j [] k) m' s') :
    ∃ Γ', StmtT P ξ Γ' F s' (exitScope x Δ) ∧ Inv m' Γ' F s' ∧ m.nv ≤ m'.nv ∧
      Keep Γ Γ' (.callcE x c j [] k) s' ∧ Frz F m m':= by
  obtain ⟨hsp, hvd, hmo, hlc, _, _⟩ := hD
  obtain ⟨fs0, te0, env0, f0, fn0, hslot0, hfs0, hf0, hps, hrt, hro, hl, hr, ho, hnt, hq⟩ :=
    hand_foundD hi.toMInv hcd hc htu hlc hmo hj hσ hsp
  cases hst with
  | reap hrs hrk _ => exact absurd ⟨_, _, _, _, _, hrs, hrk, rfl, rfl⟩ hnr
  | callcE hslot hfs hf hmx hns =>
    have e1 := hslot0.symm.trans hslot
    simp only [Option.some.injEq, Slot.mk.injEq, Val.pkg.injEq, true_and] at e1
    obtain ⟨e1, e2, e3, e4, -⟩ := e1
    subst e1 e2 e3 e4
    have e5 := Option.some.inj (hfs0.symm.trans hfs)
    subst e5
    have e6 := Option.some.inj (hf0.symm.trans hf)
    subst e6
    exact absurd (by rw [hps]; rfl) (hns te0)
  | callcD hslot hfs hf hmx hsk =>
  have e1 := hslot0.symm.trans hslot
  simp only [Option.some.injEq, Slot.mk.injEq, Val.pkg.injEq, true_and] at e1
  obtain ⟨e1, e2, e3, e4, -⟩ := e1
  subst e1 e2 e3 e4
  have e5 := Option.some.inj (hfs0.symm.trans hfs)
  subst e5
  have e6 := Option.some.inj (hf0.symm.trans hf)
  subst e6
  have hanch := hi.leafAnch rfl
  have hanchF : RootbAnchF Γ F := sorry  -- WIP scaffold (AGORA-937 B2, never merged): the package-call lemmas take the relaxed anchors (AGORA-963)
  have hos : Ec.mode.ownSlot = true := by rw [hmo]; rfl
  have hcF : c ∉ F := hcT.sink0_notF hσ hsp
  have hxn : x < m.nv := hi.nvS x (by simp [Stmt.vars])
  have hcn : c < m.nv := hi.nvSt c (by rw [← hi.dom, hc]; rfl)
  have hxy : x ≠ m.nv := fun e => by rw [e] at hxn; exact Nat.lt_irrefl _ hxn
  have hxc : x ≠ c := fun e => by rw [e, hc] at hx; cases hx
  have hyc : m.nv ≠ c := fun e => by rw [← e] at hcn; exact Nat.lt_irrefl _ hcn
  have hΓy : Γ m.nv = none := by
    cases h : Γ m.nv with
    | none => rfl
    | some E0 => exact absurd (hi.nvSt m.nv (by rw [← hi.dom, h]; rfl)) (Nat.lt_irrefl _)
  -- the code
  have hfn : FnOK P fn0 := hP fn0 (List.mem_of_getElem? hf0)
  obtain ⟨_, _, _, hrok, hrown, hpar, _⟩ := hfn
  have hte := hpar (.sink, te0) (by rw [hps]; simp)
  have hto : te0.owning = true := hte.2.1 rfl
  -- the store
  obtain ⟨hm1, _⟩ := hand_minv hi.toMInv hanchF hc hlc hos hcF hny hdc htu hslot0 hto hte.1 hx hxn
    (E0 := callX fn0) rfl rfl rfl hrok (by simp only [callX, resMode]; split <;> simp)
    (fun h => hrown (by simpa [callX, resMode] using h)) rfl rfl
  have hmo' : (callX fn0).mode.ownSlot = fn0.resOwn := resMode_ownSlot fn0
  rw [hmo'] at hm1
  -- the run-time form, typed
  obtain ⟨Γe, hTh, hW⟩ := handD_typed hP hi.toMInv hanchF hi.nvF hc htu hmo hvd hx hxn hxF hcF hny hcT hσ hsp
    hsl hsr hf0 hps hto hnt hrt hro hl hr
  have hT : StmtT P ξ (handCtx Γ c x Ec te0 m.nv (callX fn0)) F (handStmtD x f0 [] m.nv k)
      (exitScope x Δ) :=
    StmtT.scope ⟨callX fn0, handCtx_x, resMode_ne' fn0⟩ hxF (StmtT.seq hk hTh (hkT.weakenIn hW)) hpx
  -- the hand-over's context: every binding the store had, ended or moved out, and the two new ones
  have hcases : ∀ v E', handCtx Γ c x Ec te0 m.nv (callX fn0) v = some E' →
      (v = x ∧ E' = callX fn0) ∨ (v = m.nv ∧ E' = compE Ec te0) ∨
      (v = c ∧ E' = { Ec with live := false, dtor := false }) ∨
      (v ≠ x ∧ v ≠ m.nv ∧ v ≠ c ∧ ∃ E1, Γ v = some E1 ∧ E' = killE .replace false c E1) := by
    intro v E' hv
    by_cases hvx : v = x
    · subst hvx; rw [handCtx_x] at hv; cases hv; exact Or.inl ⟨rfl, rfl⟩
    by_cases hvy : v = m.nv
    · subst hvy; rw [handCtx_y hxy] at hv; cases hv; exact Or.inr (Or.inl ⟨rfl, rfl⟩)
    by_cases hvc : v = c
    · subst hvc; rw [handCtx_c hxc hyc] at hv; cases hv; exact Or.inr (Or.inr (Or.inl ⟨rfl, rfl⟩))
    rw [handCtx_other hvx hvy hvc] at hv
    simp only [kill] at hv
    obtain ⟨E1, h1, rfl⟩ := Option.map_eq_some_iff.mp hv
    exact Or.inr (Or.inr (Or.inr ⟨hvx, hvy, hvc, E1, h1, rfl⟩))
  have hEyE : compE Ec te0 = ⟨te0, .own, true, [], ownHeld true te0 Ec.held, false, false, false, false⟩ := compE_owning Ec hto
  have hkrb : ∀ v E1, Γ v = some E1 → E1.mode = .rootb → killE .replace false c E1 = E1 :=
    fun v E1 hv hm => killE_rootb hanch hcF .replace false (hny.kills .replace false)
      (HeldSpared.of_none (NoHeld.of_anchF hanchF hcF) _ _) hv hm
  -- its borrowed parameters and `letd` bindings are the store's
  have hrbΓ : ∀ p E', handCtx Γ c x Ec te0 m.nv (callX fn0) p = some E' → E'.mode = .rootb → Γ p = some E' := by
    intro p E' hp hm
    rcases hcases p E' hp with ⟨_, rfl⟩ | ⟨_, rfl⟩ | ⟨_, rfl⟩ | ⟨_, _, _, E1, h1, rfl⟩
    · exact absurd hm (resMode_ne' fn0)
    · rw [hEyE] at hm; cases hm
    · simp only [hmo] at hm; cases hm
    · rw [killE_mode] at hm; rw [hkrb p E1 h1 hm]; exact h1
  have hspine : (handStmtD x f0 [] m.nv k).spine = [x, m.nv] := by
    simp [handStmtD, Stmt.spine]
  refine ⟨handCtx Γ c x Ec te0 m.nv (callX fn0), hT, ?_, by simp [handMem], ?_, ?_⟩
  · refine Inv.mk₀ (sorry /- WIP scaffold (AGORA-963 step 3, never merged): HeldCapsInp across this step -/) hm1 (fun v hv => ?_) (fun v hv => ?_) (fun p E' hp hm _ => ?_) (by rw [hspine]; simp [hxy])
      (fun v hv => ?_) (by simp [handStmtD, CatchOK]) ?_
      (pinOut_fresh hi.toMInv (fun p E' hp hm => ⟨E', hrbΓ p E' hp hm, hm, rfl⟩)
        (fun v hv => by rw [hspine] at hv; simp only [List.mem_cons, List.not_mem_nil, or_false] at hv
                        rcases hv with rfl | rfl
                        · exact hx
                        · exact hΓy))
      (by simp [handStmtD, PinOK])
      (dtorOut_fresh hi.toMInv (fun v E' hv hd hos' hn' _ => by
          rcases hcases v E' hv with ⟨_, rfl⟩ | ⟨_, rfl⟩ | ⟨rfl, rfl⟩ | ⟨_, _, _, E1, h1, rfl⟩
          · simp [callX] at hd
          · rw [hEyE] at hd; cases hd
          · exact ⟨Ec, hc, hd, hos', hn', List.Subset.refl _⟩
          · rw [killE_dbind] at hd; rw [killE_mode] at hos'; rw [killE_ty, killE_mode] at hn'
            exact ⟨E1, h1, hd, hos', hn', by rw [killE_vdeps]; exact List.Subset.refl _⟩)
        (fun v hv => by rw [hspine] at hv; simp only [List.mem_cons, List.not_mem_nil, or_false] at hv
                        rcases hv with rfl | rfl
                        · exact hx
                        · exact hΓy))
      ⟨DtorIn.of_off fun E0 h0 => by rw [handCtx_x] at h0; cases h0; rfl,
        DtorIn.of_off fun E0 h0 => by rw [handCtx_y hxy] at h0; cases h0; rw [hEyE],
        trivial⟩
    · -- the variables of the run-time form
      show v < m.nv + 2
      have hvars : (handStmtD x f0 [] m.nv k).vars =
          [x, m.nv, m.nv + 1, m.nv, x, m.nv + 1] ++ k.vars := by
        simp [handStmtD, Stmt.vars, Rhs.vars]
      rw [hvars] at hv
      simp only [List.cons_append, List.nil_append, List.mem_cons] at hv
      have h1 : x < m.nv + 2 := Nat.lt_of_lt_of_le hxn (Nat.le_add_right _ 2)
      have h2 : m.nv < m.nv + 2 := Nat.lt_add_of_pos_right (by decide)
      have h3 : m.nv + 1 < m.nv + 2 := Nat.add_lt_add_left (by decide) _
      have h4 : c < m.nv + 2 := Nat.lt_of_lt_of_le hcn (Nat.le_add_right _ 2)
      rcases hv with h | h | h | h | h | h | h <;> (try rw [h]) <;> (try assumption)
      exact Nat.lt_of_lt_of_le (hi.nvS v (by simp [Stmt.vars, h])) (Nat.le_add_right _ 2)
    · exact Nat.lt_of_lt_of_le (hi.nvF v hv) (by show m.nv ≤ m.nv + 2; omega)
    · -- AGORA-937 (B2): the new statement's killable names are the old ones,
      -- or the fresh m.nv / m.nv+1, none of them bound in Γ (asked of the new
      -- names and the old ones together, so x and c are in the set; then the new)
      have hΓr : Γ (m.nv + 1) = none := by
        have hmz : m.st (m.nv + 1) = none := by
          cases h : m.st (m.nv + 1) with
          | none => rfl
          | some sl => exact absurd (hi.nvSt (m.nv + 1) (by rw [h]; rfl)) (Nat.not_lt.mpr (Nat.le_succ _))
        have := hi.dom (m.nv + 1); rw [hmz] at this; cases h : Γ (m.nv + 1) <;> simp_all
      have h0 := hrbΓ p E' hp hm
      refine ((((hi.anch p E' h0 hm (by simp [Stmt.spine])).extend
        (V' := (handStmtD x f0 [] m.nv k).killVars ++ (Stmt.callcE x c j [] k).killVars) fun v hv => ?_).of_tyV
        fun r Er hr hrV => ?_).anti fun v hv => List.mem_append_left _ hv)
      · rcases List.mem_append.mp hv with hv | hv
        · simp only [handStmtD, Stmt.killVars, Rhs.vars, List.mem_cons, List.mem_append,
            List.not_mem_nil, or_false] at hv
          by_cases h1 : v = m.nv
          · exact Or.inr (h1 ▸ hΓy)
          by_cases h2 : v = m.nv + 1
          · exact Or.inr (h2 ▸ hΓr)
          left
          simp only [h1, h2, false_or, or_false] at hv
          simp only [Stmt.killVars]
          rcases hv with h | h <;> first | (rcases h with h' | h' <;> simp [h']) | simp [h]
        · exact Or.inl hv
      · have hrx : r ≠ x := fun e => hrV (List.mem_append_right _ (by simp [Stmt.killVars, e]))
        have hrc : r ≠ c := fun e => hrV (List.mem_append_right _ (by simp [Stmt.killVars, e]))
        have hry : r ≠ m.nv := fun e => by rw [e, hΓy] at hr; cases hr
        refine ⟨killE .replace false c Er, ?_, killE_ty ..⟩
        rw [handCtx_other hrx hry hrc]; simp [kill, hr]
    · rw [hspine] at hv
      simp only [List.mem_cons, List.not_mem_nil, or_false] at hv
      rcases hv with rfl | rfl
      · exact ⟨_, handCtx_x⟩
      · exact ⟨_, handCtx_y hxy⟩
    · -- the package's tree is the environment's binding's
      intro i hia
      rcases hi.cover i hia with ⟨o, U, hU, hiU⟩ | hp
      · by_cases hoc : o = c
        · subst hoc
          unfold OwnedAt at hU; rw [hslot0] at hU; cases hU
          refine Or.inl ⟨m.nv, env0, ?_, by simpa [Val.ids] using hiU⟩
          unfold OwnedAt; simp [handMem, Mem.set, upd_ne _ _ (Ne.symm hxy)]
        · have hox : o ≠ x := fun e => by subst e; unfold OwnedAt at hU; rw [hmx] at hU; cases hU
          have hoy : o ≠ m.nv := fun e => by
            subst e; unfold OwnedAt at hU
            have := hi.dom m.nv; rw [hΓy, hU] at this; cases this
          refine Or.inl ⟨o, U, ?_, hiU⟩
          unfold OwnedAt at hU ⊢; simp [handMem, Mem.set, upd_ne _ _ hox, upd_ne _ _ hoy, upd_ne _ _ hoc, hU]
      · exact Or.inr hp
  · -- every binding outside the new scopes stays, with its mode and type
    refine ⟨fun v E0 hv _ => ⟨?_, ?_⟩, fun v E' hv hvs => ⟨by simp [Stmt.spine], ?_⟩, ?_⟩
    · have hvx : v ≠ x := fun e => by rw [e, hx] at hv; cases hv
      have hvy : v ≠ m.nv := fun e => by rw [e, hΓy] at hv; cases hv
      rw [hspine]; simp [hvx, hvy]
    · have hvx : v ≠ x := fun e => by rw [e, hx] at hv; cases hv
      have hvy : v ≠ m.nv := fun e => by rw [e, hΓy] at hv; cases hv
      by_cases hvc : v = c
      · subst hvc; rw [hc] at hv; cases hv
        refine ⟨_, handCtx_c hxc hyc, rfl, rfl, fun hm => absurd hm (by rw [hmo]; simp)⟩
      · refine ⟨killE .replace false c E0, by rw [handCtx_other hvx hvy hvc]; simp [kill, hv], killE_mode .. ,
          killE_ty .., fun hm => hkrb v E0 hv hm⟩
    · rw [hspine] at hvs
      simp only [List.mem_cons, List.not_mem_nil, or_false, not_or] at hvs
      rcases hcases v E' hv with ⟨h, _⟩ | ⟨h, _⟩ | ⟨h, _⟩ | ⟨_, _, _, E1, h1, _⟩
      · exact absurd h hvs.1
      · exact absurd h hvs.2
      · subst h; exact ⟨_, hc⟩
      · exact ⟨_, h1⟩
    · intro v E' hv hd hos hn hvs
      rcases hcases v E' hv with ⟨_, rfl⟩ | ⟨_, rfl⟩ | ⟨rfl, rfl⟩ | ⟨_, _, _, E1, h1, rfl⟩
      · simp [callX] at hd
      · rw [hEyE] at hd; cases hd
      · exact ⟨Ec, hc, hd, hos, hn, fun d hdd _ => hdd⟩
      · rw [killE_dbind] at hd; rw [killE_mode] at hos; rw [killE_ty, killE_mode] at hn
        exact ⟨E1, h1, hd, hos, hn, fun d hdd _ => by rwa [killE_vdeps] at hdd⟩
  · -- nothing lent out is touched
    intro v hv
    have hvx : v ≠ x := fun e => hxF (e ▸ hv)
    have hvc : v ≠ c := fun e => hcF (e ▸ hv)
    have hvy : v ≠ m.nv := fun e => by have := hi.nvF v hv; rw [e] at this; exact Nat.lt_irrefl _ this
    simp [handMem, Mem.set, upd_ne _ _ hvx, upd_ne _ _ hvy, upd_ne _ _ hvc]


/-- **Progress of a hand-over**: the package's slot holds what the step needs. -/
theorem handProgress {P : Prog} {Γ Γ1 : Ctx} {F : List Var} {x c : Var} {j : Nat} {zs : List Var} {k : Stmt}
    {Ec E : Entry} {ms : List Nat} {q : Cross} {σ : Nat} {sig : Fn} {b : Eff} {m : Mem}
    (hx : Γ x = none) (hc : Γ c = some Ec) (htu : Ec.ty.undtor = .fn ms q) (hcan : canDo Ec.mode .replace)
    (hj : ms[j]? = some σ) (hσ : P[σ]? = some sig)
    (hsp0 : ((∃ ps, sig.params = (.inout b, .fn ms q) :: ps ∧ Ec.ty = .fn ms q ∧ Cross.send.Le q ∧
          ∀ z ∈ zs, ∀ d ∈ (argE Γ z).vdeps, (Γ d.root).isSome) ∨
      (sig.params = [(.sink, Ec.ty)] ∧ zs = [] ∧ Ec.vdeps = [] ∧ Ec.mode = .own ∧ Ec.live = true ∧
        q.drops = true ∧ sig.resOwn = false)))
    (hcT : CallT P (kill .replace false c Γ) F σ (c :: zs) E Γ1) (hcd : MemCodes P m)
    (hi : Inv m Γ F (.callcE x c j zs k)) : ∃ r, Step P m (.callcE x c j zs k) r := by
  rcases hsp0 with ⟨ps, hsp, htc, _⟩ | ⟨hD1, hz, hD⟩
  rotate_left
  · subst hz
    exact handProgressD hx hc htu hj hσ ⟨hD1, hD⟩ hcT hcd hi
  obtain ⟨_, _, _, _, _, _, _, hslot, hfs, hf, hps, _⟩ := hand_found hi.toMInv hcd hc htc hcan hj hσ hsp hcT
  have hmx : m.st x = none := by
    have := hi.dom x; rw [hx] at this; cases h : m.st x <;> simp_all
  exact ⟨_, Step.callcE hslot hfs hf hmx (fun pt h => by rw [hps] at h; cases h)⟩

/-- **Preservation of a hand-over** (A2-envhand): the store it leaves
    (`hand_minv`), the run-time form typed (`hand_typed`), and every binding
    outside its new scopes kept. -/
theorem handCase {P : Prog} (hP : ProgOK P) : HandCase P := by
  intro ξ Γ Γ1 F x c j zs k Ec E ms q σ sig b Δ m m' s' hk hx hxF hc htu hcan hj hσ hsp0 hsl hsr hso hny hdc hcT
    hkT hpx hcd hi hst hnr
  rcases hsp0 with ⟨ps, hsp, htc, _, hzb⟩ | ⟨hD1, hz, hD⟩
  rotate_left
  · subst hz
    exact handCaseD hP hk hx hxF hc htu hj hσ ⟨hD1, hD⟩ hsl hsr hso hny hdc hcT hkT hpx hcd hi hst hnr
  obtain ⟨hlc, hmo, fs0, te0, env0, f0, fn0, hslot0, hfs0, hf0, hps, hrt, hro, hl, hr, ho, hnt⟩ :=
    hand_found hi.toMInv hcd hc htc hcan hj hσ hsp hcT
  cases hst with
  | reap hrs hrk _ => exact absurd ⟨_, _, _, _, _, hrs, hrk, rfl, rfl⟩ hnr
  | callcD hslot hfs hf hmx hsk =>
    -- (Agora #609: the code of an `inout` interface takes the environment `inout`)
    have e1 := hslot0.symm.trans hslot
    simp only [Option.some.injEq, Slot.mk.injEq, Val.pkg.injEq, true_and] at e1
    obtain ⟨e1, e2, e3, e4, -⟩ := e1
    subst e1 e2 e3 e4
    have e5 := Option.some.inj (hfs0.symm.trans hfs)
    subst e5
    have e6 := Option.some.inj (hf0.symm.trans hf)
    subst e6
    rw [hps] at hsk; cases hsk
  | callcE hslot hfs hf hmx =>
    have e1 := hslot0.symm.trans hslot
    simp only [Option.some.injEq, Slot.mk.injEq, Val.pkg.injEq, true_and] at e1
    obtain ⟨e1, e2, e3, e4, -⟩ := e1
    subst e1 e2 e3 e4
    have e5 := Option.some.inj (hfs0.symm.trans hfs)
    subst e5
    have e6 := Option.some.inj (hf0.symm.trans hf)
    subst e6
    have hanch := hi.leafAnch rfl
    have hanchF : RootbAnchF Γ F := sorry  -- WIP scaffold (AGORA-937 B2, never merged): the package-call lemmas take the relaxed anchors (AGORA-963)
    have hos : Ec.mode.ownSlot = true := by rw [hmo]; rfl
    have hcF : c ∉ F := hcT.inout0_notF hσ hsp
    have hxn : x < m.nv := hi.nvS x (by simp [Stmt.vars])
    have hcn : c < m.nv := hi.nvSt c (by rw [← hi.dom, hc]; rfl)
    have hxy : x ≠ m.nv := fun e => by rw [e] at hxn; exact Nat.lt_irrefl _ hxn
    have hxc : x ≠ c := fun e => by rw [e, hc] at hx; cases hx
    have hyc : m.nv ≠ c := fun e => by rw [← e] at hcn; exact Nat.lt_irrefl _ hcn
    have hΓy : Γ m.nv = none := by
      cases h : Γ m.nv with
      | none => rfl
      | some E0 => exact absurd (hi.nvSt m.nv (by rw [← hi.dom, h]; rfl)) (Nat.lt_irrefl _)
    -- the code
    have hfn : FnOK P fn0 := hP fn0 (List.mem_of_getElem? hf0)
    obtain ⟨_, _, _, hrok, hrown, hpar, _⟩ := hfn
    have hte := hpar (.inout b, te0) (by rw [hps]; simp)
    have hto : te0.owning = true := hte.2.2 b rfl
    have hq : q.Fits te0 [] := pkg_fits hi.toMInv hc hlc (by rw [htc]; rfl) hslot0
    -- the store
    obtain ⟨hm1, _⟩ := hand_minv hi.toMInv hanchF hc hlc hos hcF hny hdc (by rw [htc]; rfl) hslot0 hto hte.1 hx hxn
      (E0 := callX fn0) rfl rfl rfl hrok (by simp only [callX, resMode]; split <;> simp)
      (fun h => hrown (by simpa [callX, resMode] using h)) rfl rfl
    have hmo' : (callX fn0).mode.ownSlot = fn0.resOwn := resMode_ownSlot fn0
    rw [hmo'] at hm1
    -- the run-time form, typed
    obtain ⟨Γe, hTh, hW⟩ := hand_typed hP hi.toMInv hanchF hi.nvF hc htc hmo hx hxn hxF hcF hny hdc hcT hσ hsp
      hsl hsr hso hf0 hps hto hnt hrt hro hl hr ho hq hzb (fs := fs0)
    have hT : StmtT P ξ (handCtx Γ c x Ec te0 m.nv (callX fn0)) F (handStmt x c f0 zs fs0 te0 ms m.nv k)
        (exitScope x Δ) :=
      StmtT.scope ⟨callX fn0, handCtx_x, resMode_ne' fn0⟩ hxF (StmtT.seq hk hTh (hkT.weakenIn hW)) hpx
    -- the hand-over's context: every binding the store had, ended or moved out, and the two new ones
    have hdbc : Ec.dbind = false := by
      obtain ⟨sig', hσ', _, _, _, hds, _⟩ := hcT
      rw [hσ] at hσ'; cases hσ'
      have := hds.2.2 0 (by simp [hsp]) b (by simp [hsp]) (killE .replace false c Ec) (by simp [kill, hc])
      rwa [killE_dbind] at this
    have hcases : ∀ v E', handCtx Γ c x Ec te0 m.nv (callX fn0) v = some E' →
        (v = x ∧ E' = callX fn0) ∨ (v = m.nv ∧ E' = compE Ec te0) ∨
        (v = c ∧ E' = { Ec with live := false, dtor := false }) ∨
        (v ≠ x ∧ v ≠ m.nv ∧ v ≠ c ∧ ∃ E1, Γ v = some E1 ∧ E' = killE .replace false c E1) := by
      intro v E' hv
      by_cases hvx : v = x
      · subst hvx; rw [handCtx_x] at hv; cases hv; exact Or.inl ⟨rfl, rfl⟩
      by_cases hvy : v = m.nv
      · subst hvy; rw [handCtx_y hxy] at hv; cases hv; exact Or.inr (Or.inl ⟨rfl, rfl⟩)
      by_cases hvc : v = c
      · subst hvc; rw [handCtx_c hxc hyc] at hv; cases hv; exact Or.inr (Or.inr (Or.inl ⟨rfl, rfl⟩))
      rw [handCtx_other hvx hvy hvc] at hv
      simp only [kill] at hv
      obtain ⟨E1, h1, rfl⟩ := Option.map_eq_some_iff.mp hv
      exact Or.inr (Or.inr (Or.inr ⟨hvx, hvy, hvc, E1, h1, rfl⟩))
    have hEyE : compE Ec te0 = ⟨te0, .own, true, [], ownHeld true te0 Ec.held, false, false, false, false⟩ := compE_owning Ec hto
    have hkrb : ∀ v E1, Γ v = some E1 → E1.mode = .rootb → killE .replace false c E1 = E1 :=
      fun v E1 hv hm => killE_rootb hanch hcF .replace false (hny.kills .replace false)
      (HeldSpared.of_none (NoHeld.of_anchF hanchF hcF) _ _) hv hm
    -- its borrowed parameters and `letd` bindings are the store's
    have hrbΓ : ∀ p E', handCtx Γ c x Ec te0 m.nv (callX fn0) p = some E' → E'.mode = .rootb → Γ p = some E' := by
      intro p E' hp hm
      rcases hcases p E' hp with ⟨_, rfl⟩ | ⟨_, rfl⟩ | ⟨_, rfl⟩ | ⟨_, _, _, E1, h1, rfl⟩
      · exact absurd hm (resMode_ne' fn0)
      · rw [hEyE] at hm; cases hm
      · simp only [hmo] at hm; cases hm
      · rw [killE_mode] at hm; rw [hkrb p E1 h1 hm]; exact h1
    have hspine : (handStmt x c f0 zs fs0 te0 ms m.nv k).spine = [x, m.nv] := by
      simp [handStmt, Stmt.spine]
    refine ⟨handCtx Γ c x Ec te0 m.nv (callX fn0), hT, ?_, by simp [handMem], ?_, ?_⟩
    · refine Inv.mk₀ (sorry /- WIP scaffold (AGORA-963 step 3, never merged): HeldCapsInp across this step -/) hm1 (fun v hv => ?_) (fun v hv => ?_) (fun p E' hp hm _ => ?_) (by rw [hspine]; simp [hxy])
        (fun v hv => ?_) (by simp [handStmt, CatchOK]) ?_
        (pinOut_fresh hi.toMInv (fun p E' hp hm => ⟨E', hrbΓ p E' hp hm, hm, rfl⟩)
          (fun v hv => by rw [hspine] at hv; simp only [List.mem_cons, List.not_mem_nil, or_false] at hv
                          rcases hv with rfl | rfl
                          · exact hx
                          · exact hΓy))
        (by simp [handStmt, PinOK])
        (dtorOut_fresh hi.toMInv (fun v E' hv hd hos' hn' _ => by
            rcases hcases v E' hv with ⟨_, rfl⟩ | ⟨_, rfl⟩ | ⟨_, rfl⟩ | ⟨_, _, _, E1, h1, rfl⟩
            · simp [callX] at hd
            · rw [hEyE] at hd; cases hd
            · simp [hdbc] at hd
            · rw [killE_dbind] at hd; rw [killE_mode] at hos'; rw [killE_ty, killE_mode] at hn'
              exact ⟨E1, h1, hd, hos', hn', by rw [killE_vdeps]; exact List.Subset.refl _⟩)
          (fun v hv => by rw [hspine] at hv; simp only [List.mem_cons, List.not_mem_nil, or_false] at hv
                          rcases hv with rfl | rfl
                          · exact hx
                          · exact hΓy))
        ⟨DtorIn.of_off fun E0 h0 => by rw [handCtx_x] at h0; cases h0; rfl,
          DtorIn.of_off fun E0 h0 => by rw [handCtx_y hxy] at h0; cases h0; rw [hEyE],
          trivial⟩
      · -- the variables of the run-time form
        show v < m.nv + 2
        have hvars : (handStmt x c f0 zs fs0 te0 ms m.nv k).vars =
            [x, m.nv, m.nv + 1, m.nv] ++ zs ++ [x, m.nv + 1, c, m.nv] ++ k.vars := by
          simp [handStmt, Stmt.vars, Rhs.vars]
        rw [hvars] at hv
        simp only [List.mem_append, List.mem_cons, List.not_mem_nil, or_false, or_assoc] at hv
        have h1 : x < m.nv + 2 := Nat.lt_of_lt_of_le hxn (Nat.le_add_right _ 2)
        have h2 : m.nv < m.nv + 2 := Nat.lt_add_of_pos_right (by decide)
        have h3 : m.nv + 1 < m.nv + 2 := Nat.add_lt_add_left (by decide) _
        have h4 : c < m.nv + 2 := Nat.lt_of_lt_of_le hcn (Nat.le_add_right _ 2)
        have hS : ∀ w ∈ (Stmt.callcE x c j zs k).vars, w < m.nv + 2 := fun w hw =>
          Nat.lt_of_lt_of_le (hi.nvS w hw) (Nat.le_add_right _ 2)
        rcases hv with h | h | h | h | h | h | h | h | h | h
        all_goals first
          | (rw [h]; assumption)
          | exact hS v (by simp [Stmt.vars, h])
      · exact Nat.lt_of_lt_of_le (hi.nvF v hv) (by show m.nv ≤ m.nv + 2; omega)
      · -- AGORA-937 (B2): as handStmtD's: the new killable names are the old ones,
        -- or the fresh m.nv / m.nv+1, none of them bound in Γ
        have hΓr : Γ (m.nv + 1) = none := by
          have hmz : m.st (m.nv + 1) = none := by
            cases h : m.st (m.nv + 1) with
            | none => rfl
            | some sl => exact absurd (hi.nvSt (m.nv + 1) (by rw [h]; rfl)) (Nat.not_lt.mpr (Nat.le_succ _))
          have := hi.dom (m.nv + 1); rw [hmz] at this; cases h : Γ (m.nv + 1) <;> simp_all
        have h0 := hrbΓ p E' hp hm
        refine ((((hi.anch p E' h0 hm (by simp [Stmt.spine])).extend
          (V' := (handStmt x c f0 zs fs0 te0 ms m.nv k).killVars ++ (Stmt.callcE x c j zs k).killVars)
          fun v hv => ?_).of_tyV fun r Er hr hrV => ?_).anti fun v hv => List.mem_append_left _ hv)
        · rcases List.mem_append.mp hv with hv | hv
          · by_cases h1 : v = m.nv
            · exact Or.inr (h1 ▸ hΓy)
            by_cases h2 : v = m.nv + 1
            · exact Or.inr (h2 ▸ hΓr)
            left
            simp only [handStmt, Stmt.killVars, Rhs.vars, List.mem_cons, List.mem_append,
              List.not_mem_nil] at hv ⊢
            grind
          · exact Or.inl hv
        · have hrx : r ≠ x := fun e => hrV (List.mem_append_right _ (by simp [Stmt.killVars, e]))
          have hrc : r ≠ c := fun e => hrV (List.mem_append_right _ (by simp [Stmt.killVars, e]))
          have hry : r ≠ m.nv := fun e => by rw [e, hΓy] at hr; cases hr
          refine ⟨killE .replace false c Er, ?_, killE_ty ..⟩
          rw [handCtx_other hrx hry hrc]; simp [kill, hr]
      · rw [hspine] at hv
        simp only [List.mem_cons, List.not_mem_nil, or_false] at hv
        rcases hv with rfl | rfl
        · exact ⟨_, handCtx_x⟩
        · exact ⟨_, handCtx_y hxy⟩
      · -- the package's tree is the environment's binding's
        intro i hia
        rcases hi.cover i hia with ⟨o, U, hU, hiU⟩ | hp
        · by_cases hoc : o = c
          · subst hoc
            unfold OwnedAt at hU; rw [hslot0] at hU; cases hU
            refine Or.inl ⟨m.nv, env0, ?_, by simpa [Val.ids] using hiU⟩
            unfold OwnedAt; simp [handMem, Mem.set, upd_ne _ _ (Ne.symm hxy)]
          · have hox : o ≠ x := fun e => by subst e; unfold OwnedAt at hU; rw [hmx] at hU; cases hU
            have hoy : o ≠ m.nv := fun e => by
              subst e; unfold OwnedAt at hU
              have := hi.dom m.nv; rw [hΓy, hU] at this; cases this
            refine Or.inl ⟨o, U, ?_, hiU⟩
            unfold OwnedAt at hU ⊢; simp [handMem, Mem.set, upd_ne _ _ hox, upd_ne _ _ hoy, upd_ne _ _ hoc, hU]
        · exact Or.inr hp
    · -- every binding outside the new scopes stays, with its mode and type
      refine ⟨fun v E0 hv _ => ⟨?_, ?_⟩, fun v E' hv hvs => ⟨by simp [Stmt.spine], ?_⟩, ?_⟩
      · have hvx : v ≠ x := fun e => by rw [e, hx] at hv; cases hv
        have hvy : v ≠ m.nv := fun e => by rw [e, hΓy] at hv; cases hv
        rw [hspine]; simp [hvx, hvy]
      · have hvx : v ≠ x := fun e => by rw [e, hx] at hv; cases hv
        have hvy : v ≠ m.nv := fun e => by rw [e, hΓy] at hv; cases hv
        by_cases hvc : v = c
        · subst hvc; rw [hc] at hv; cases hv
          refine ⟨_, handCtx_c hxc hyc, rfl, rfl, fun hm => absurd hm (by rw [hmo]; simp)⟩
        · refine ⟨killE .replace false c E0, by rw [handCtx_other hvx hvy hvc]; simp [kill, hv], killE_mode .. ,
            killE_ty .., fun hm => hkrb v E0 hv hm⟩
      · rw [hspine] at hvs
        simp only [List.mem_cons, List.not_mem_nil, or_false, not_or] at hvs
        rcases hcases v E' hv with ⟨h, _⟩ | ⟨h, _⟩ | ⟨h, _⟩ | ⟨_, _, _, E1, h1, _⟩
        · exact absurd h hvs.1
        · exact absurd h hvs.2
        · subst h; exact ⟨_, hc⟩
        · exact ⟨_, h1⟩
      · intro v E' hv hd hos hn hvs
        rcases hcases v E' hv with ⟨_, rfl⟩ | ⟨_, rfl⟩ | ⟨_, rfl⟩ | ⟨_, _, _, E1, h1, rfl⟩
        · simp [callX] at hd
        · rw [hEyE] at hd; cases hd
        · simp [hdbc] at hd
        · rw [killE_dbind] at hd; rw [killE_mode] at hos; rw [killE_ty, killE_mode] at hn
          exact ⟨E1, h1, hd, hos, hn, fun d hdd _ => by rwa [killE_vdeps] at hdd⟩
    · -- nothing lent out is touched
      intro v hv
      have hvx : v ≠ x := fun e => hxF (e ▸ hv)
      have hvc : v ≠ c := fun e => hcF (e ▸ hv)
      have hvy : v ≠ m.nv := fun e => by have := hi.nvF v hv; rw [e] at this; exact Nat.lt_irrefl _ this
      simp [handMem, Mem.set, upd_ne _ _ hvx, upd_ne _ _ hvy, upd_ne _ _ hvc]

end A2
