import A2.Codes

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
leaves, as weak as what the interface's does (`hand_weaker`). -/

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
    obtain ⟨h1, h2, h3⟩ := hi.blocks k bl hk
    exact ⟨h1, h2, fun p hp => ⟨(h3 p hp).1, (h3 p hp).2.of_blk rfl⟩⟩

/-- A tree of an owning type is owned. -/
theorem WFv.owns_owning {t : Ty} {v : Val} (hw : WFv t v) (ho : t.owning = true) : v.owns = true := by
  cases hw <;> simp_all [Val.owns, Ty.owning]

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
theorem hand_minv {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ) (hanch : RootbAnch Γ F)
    {c x : Var} {Ec : Entry} (hc : Γ c = some Ec) (hl : Ec.live = true) (hos : Ec.mode.ownSlot = true)
    (hcF : c ∉ F) (hny : NoPin Γ c) (hdc : DtorSafe Γ .replace false c)
    {fs : List Nat} {te : Ty} {ms : List Nat} {q : Cross} {env : Val} (htc : Ec.ty = .fn ms q)
    (hslot : m.st c = some ⟨true, some (.pkg fs te ms env [])⟩) (hown : te.owning = true)
    (htok : te.ok = true) (hx : Γ x = none) (hxn : x < m.nv) {E0 : Entry} (hl0 : E0.live = false)
    (hp0 : E0.path = []) (hh0 : E0.held = []) (htok0 : E0.ty.ok = true) (hm0 : E0.mode = .own ∨ E0.mode = .bor)
    (hown0 : E0.mode = .own → E0.ty.owning = true) (hdt0 : E0.dtor = false) (hdb0 : E0.dbind = false) :
    MInv (handMem m c x env E0.mode.ownSlot) (handCtx Γ c x Ec te m.nv E0) ∧
    RhsPost { m with nv := m.nv + 2 } ({ m with nv := m.nv + 2 }.set c ⟨true, none⟩) Γ
      (setE (kill .replace false c Γ) c { Ec with live := false, dtor := false }) F := by
  let m' : Mem := { m with nv := m.nv + 2 }
  have hi' : MInv m' Γ :=
    hi.of_st rfl ⟨hi.heap.nodup, hi.heap.disj, hi.heap.alloc, hi.heap.self, hi.heap.blk, hi.heap.views⟩
      (by show m.nv ≤ m.nv + 2; omega)
  obtain ⟨post, out⟩ := rhs_move' hi' hanch hc hl hos hcF hny hslot hdc
  have hτ : Ec.ty ≠ .int := by rw [htc]; simp
  have hwP : WFv Ec.ty (.pkg fs te ms env []) := (out.valOwn rfl).2.1
  rw [htc] at hwP
  obtain ⟨hwe, hq⟩ : WFv te env ∧ q.Fits te [] := by cases hwP with | pkg h1 h2 => exact ⟨h1, h2⟩
  have hvin : ∀ s v, ViewIn te env s v → ViewIn Ec.ty (.pkg fs te ms env []) s v := by
    intro s v hv
    rw [htc]
    cases q with
    | any => exact ViewIn.pkg hv
    | _ => exact absurd hv.holdsView (by rw [(hq.1 rfl).1]; simp)
  have hain : ∀ u k p, ArcIn te env u k p → ArcIn Ec.ty (.pkg fs te ms env []) u k p := by
    intro u k p ha
    rw [htc]
    cases hqs : q.shares with
    | true => exact ArcIn.pkg ha hqs
    | false => exact absurd ha.hasArc (by rw [hq.2.2 hqs]; simp)
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

end A2
