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

/-! ### The code's call, typed from the interface's -/

theorem compE_owning (E : Entry) {t : Ty} (h : t.owning = true) :
    compE E t = ⟨t, .own, true, [], ownHeld true t E.held, false, false⟩ := by
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

/-- **The code's call, typed from the interface's** (A2-envhand): where the
    interface's call on the package `c` (its only parameter, `inout b`) is
    typed after every dependency on `c` ended, the code's call on the
    environment's binding `y` (the code's only parameter, `inout b` at the
    environment's type) is typed in the context the hand-over leaves. `y`
    holds what `c` held, and is fresh. -/
theorem callT_hand {P : Prog} {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ) (hFlt : ∀ v ∈ F, v < m.nv)
    {c x : Var} {Ec E : Entry} {Γ1 : Ctx} {σ f : Nat} {sig fn : Fn} {b : Eff} {ms : List Nat} {q : Cross}
    {te : Ty} (hc : Γ c = some Ec) (htc : Ec.ty = .fn ms q) (hx : Γ x = none) (hxn : x < m.nv)
    (hcT : CallT P (kill .replace false c Γ) F σ [c] E Γ1) (hσ : P[σ]? = some sig)
    (hsp : sig.params = [(.inout b, .fn ms q)])
    (hf : P[f]? = some fn) (hps : fn.params = [(.inout b, te)]) (hto : te.owning = true) (hnt : ¬ ThruFn P f)
    {E0 : Entry} (hE0d : E0.dtor = false) (hE0m : E0.mode ≠ .rootb) :
    CallT P (handCtx Γ c x Ec te m.nv E0) F f [m.nv]
      (callRes (handCtx Γ c x Ec te m.nv E0) fn [m.nv]) (callPost (handCtx Γ c x Ec te m.nv E0) fn [m.nv]) := by
  obtain ⟨sig', hσ', _, hargs, hnf, hds, _, _, _⟩ := hcT
  rw [hσ] at hσ'; cases hσ'
  have hτ : Ec.ty ≠ .int := by rw [htc]; simp
  -- the package, where the interface's call takes it
  obtain ⟨Ea, hEa, hla, hok, _, _⟩ := hargs 0 (by simp [hsp])
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
  -- where things are
  have hcn : c < m.nv := hi.nvSt c (by rw [← hi.dom, hc]; rfl)
  have hxy : x ≠ m.nv := fun e => by rw [e] at hxn; exact Nat.lt_irrefl _ hxn
  have hxc : x ≠ c := fun e => by rw [e, hc] at hx; cases hx
  have hyc : m.nv ≠ c := fun e => by rw [← e] at hcn; exact Nat.lt_irrefl _ hcn
  have hEy : compE Ec te = ⟨te, .own, true, [], ownHeld true te Ec.held, false, false⟩ := compE_owning Ec hto
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
  -- the other bindings are the interface's call's
  have hother : ∀ v, v ≠ x → v ≠ m.nv → v ≠ c →
      handCtx Γ c x Ec te m.nv E0 v = kill .replace false c Γ v :=
    fun v h1 h2 h3 => handCtx_other h1 h2 h3
  have hmut : ∀ d ∈ mutNames (handCtx Γ c x Ec te m.nv E0) [m.nv],
      d ∈ mutNames (kill .replace false c Γ) [c] ∧ d ∈ Ec.vdeps := by
    intro d hd
    simp only [mutNames, argNames, List.flatMap_cons, List.flatMap_nil, List.append_nil, hyE,
      List.mem_filter, hEyt, ↓reduceIte] at hd
    simp only [mutNames, argNames, List.flatMap_cons, List.flatMap_nil, List.append_nil, hck,
      List.mem_filter, killE_ty, hτ, ↓reduceIte, killE_vdeps]
    obtain ⟨hd1, hd2⟩ := hd
    have h1 := hEyv (List.mem_filter.mp hd1).1
    exact ⟨⟨List.mem_filter.mpr ⟨h1, (List.mem_filter.mp hd1).2⟩, hd2⟩, h1⟩
  have hdtor : ∀ v E', handCtx Γ c x Ec te m.nv E0 v = some E' → E'.dtor = true →
      v ≠ x ∧ v ≠ m.nv ∧ v ≠ c := by
    intro v E' hv hd
    refine ⟨fun e => ?_, fun e => ?_, fun e => ?_⟩
    · rw [e, handCtx_x] at hv; cases hv; rw [hE0d] at hd; cases hd
    · rw [e, hy] at hv; cases hv; rw [hEy] at hd; cases hd
    · rw [e, handCtx_c hxc hyc] at hv; cases hv; cases hd
  refine ⟨fn, hf, by simp [hps], fun i hi' => ?_, fun d hd => ?_, ?_, rfl, rfl, fun h => absurd h hnt⟩
  · -- the receiver: the environment's binding, handed over
    have hi0 : i = 0 := by rw [hps] at hi'; simpa using hi'
    subst hi0
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
      · intro j hj hj0; exact absurd (by simpa [hps] using hj) hj0
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
  · -- what the code's closures may change, the interface's may
    obtain ⟨hdm, hdv⟩ := hmut d hd
    obtain ⟨hcan', hvec, hnF, _, huniq⟩ := hnf d hdm
    have hdc : d.root ≠ c := hnc d hdv
    have hdlt : d.root < m.nv := hi.root_lt hc hlc (Or.inl hτ) (List.mem_map_of_mem (f := Dep.root) hdv)
    have hdx : d.root ≠ x := fun e => by
      obtain ⟨_, h', _⟩ := hi.wf c Ec hc hlc (Or.inl hτ) d.root (List.mem_map_of_mem (f := Dep.root) hdv)
      rw [e, hx] at h'; cases h'
    have hdy : d.root ≠ m.nv := fun e => by rw [e] at hdlt; exact Nat.lt_irrefl _ hdlt
    have harg : argE (handCtx Γ c x Ec te m.nv E0) d.root = argE (kill .replace false c Γ) d.root := by
      simp only [argE]; rw [hother _ hdx hdy hdc]
    rw [harg]
    refine ⟨hcan', hvec, hnF, Or.inl (by simp [hdy]), fun a ha _ d' hd' hdr => ?_⟩
    simp only [List.mem_singleton] at ha; subst ha
    rw [hyE] at hd'
    exact huniq c (by simp) (by rw [hck, killE_ty]; exact Or.inl hτ) d' (by rw [hck, killE_vdeps]; exact hEyv hd')
      hdr
  · -- no destructor views the environment's binding, nor more than before
    refine ⟨fun i hi' => ⟨fun hs => ?_, fun b' _ => ?_⟩, fun d hd => ?_, fun i hi' b' _ Ea hEa => ?_⟩
    · have hi0 : i = 0 := by rw [hps] at hi'; simpa using hi'
      subst hi0; simp [hps] at hs
    · have hi0 : i = 0 := by rw [hps] at hi'; simpa using hi'
      subst hi0
      intro v E' hv hd' hos'
      obtain ⟨hvx, hvy, hvc⟩ := hdtor v E' hv hd'
      rw [hother v hvx hvy hvc] at hv
      simp only [kill] at hv
      obtain ⟨E1, h1, rfl⟩ := Option.map_eq_some_iff.mp hv
      have := hi.dtorSafe_fresh (y := m.nv) (Nat.le_refl _) b' (fn.params[0]'hi').2.elem.holdsView v E1 h1
        (by rw [killE_dtor] at hd'; exact hd') (by rw [killE_mode] at hos'; exact hos')
      unfold hitsMem at this ⊢; rw [killE_ty, killE_mode, killE_vdeps]; exact this
    · intro v E' hv hd' hos'
      obtain ⟨hvx, hvy, hvc⟩ := hdtor v E' hv hd'
      rw [hother v hvx hvy hvc] at hv
      exact hds.2.1 d (hmut d hd).1 v E' hv hd' hos'
    · have hi0 : i = 0 := by rw [hps] at hi'; simpa using hi'
      subst hi0
      simp only [List.getD_cons_zero, hy, Option.some.injEq] at hEa
      subst hEa; rw [hEy]

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
  obtain ⟨ht, hm, hr, hlv, hd, hdb, ha, hk⟩ := hw
  refine ⟨by rw [killE_ty, ht], by rw [killE_mode, hm], fun h => by rw [hfix h, hr h], fun h => ?_,
    fun h => by rw [killE_dtor, killE_held]; exact hd h, by rw [killE_dbind, hdb],
    fun h => by rw [killE_dtor] at h; exact ha h, fun h hos hn d hnm => by rw [killE_held]; exact hk h hos hn d hnm⟩
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

/-- A borrowed parameter is reached by no change a call's closures make by
    name: what it borrows from is lent out, which such a binding is not, and
    what it holds by name changes no more than the name says. -/
theorem rootb_names {Γ : Ctx} {F : List Var} (hanch : RootbAnch Γ F) {ds : List Dep}
    (hds : ∀ d ∈ ds, d.root ∉ F ∧ d.kind.bound ≠ .replace) :
    ∀ p E, Γ p = some E → E.mode = .rootb → ∀ d ∈ ds, hits d.kind.bound false d.root E = false := by
  intro p E hp hm d hd
  obtain ⟨hF, hbr⟩ := hds d hd
  refine RSetup.hits_false_of fun d' hd' hr' => ?_
  by_cases hb0 : d'.kind.bound = .none
  · exact absurd (hr' ▸ hanch p E hp hm d' hd' hb0) hF
  · exact RSetup.kills_isName hbr _ (RSetup.isName_of_bound hb0)

/-- **The receiver is not ended by its own closures**: an `inout` argument
    reached by no other way than by names of their bound (`NamesFree`), each
    no `replace` (a closure changes a binding by name at most by dropping
    elements), holds after the call what it held and what it was handed, and
    none of the call's changes by name ends it. -/
theorem recv_keep {Ea : Entry} {H : List Dep} {ds : List Dep}
    (hH : ∀ d' ∈ H, d' ∈ Ea.vdeps ∨ (∃ d0 ∈ memDeps Ea.vdeps, d'.root = d0.root) ∨
      d' ∈ nameDeps Ea.vdeps)
    (huniq : ∀ d ∈ ds, ∀ d' ∈ Ea.vdeps, d'.root = d.root → d'.kind.bound = d.kind.bound)
    (hds : ∀ d ∈ ds, d.kind.bound ≠ .none ∧ d.kind.bound ≠ .replace) (hos : Ea.mode.ownSlot = true) :
    RSetup.killAll ds { Ea with held := H } = { Ea with held := H } := by
  refine killAll_id fun d hd => RSetup.hits_false_of fun d' hd' hr' => ?_
  obtain ⟨hbn, hbr⟩ := hds d hd
  have hv' : ({ Ea with held := H } : Entry).vdeps = H := by simp [Entry.vdeps, hos]
  rw [hv'] at hd'
  have hname : ∀ d'' ∈ Ea.vdeps, d''.root = d.root → d''.kind.isName = true := fun d'' h1 h2 =>
    RSetup.isName_of_bound (by rw [huniq d hd d'' h1 h2]; exact hbn)
  rcases hH d' hd' with h1 | ⟨d0, h0, h2⟩ | h1
  · exact RSetup.kills_isName hbr _ (hname d' h1 hr')
  · obtain ⟨h0v, h0n⟩ := List.mem_filter.mp h0
    rw [hname d0 h0v (h2 ▸ hr')] at h0n; cases h0n
  · exact RSetup.kills_isName hbr _ (hname d' (List.mem_filter.mp h1).1 hr')

end A2
