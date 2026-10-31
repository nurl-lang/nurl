import A3.Thread

/-! A3.0 — what a thread's next step touches is its own.

Every address `Touch` names is in a tree one of the thread's owned slots
holds: the rules read it off `VecOf`, `NodeAt`, `DataAt` and owned slots,
which search the thread's own trees.  The one exception is a `sat` through
a view, whose buffer the step finds only through the view's address; there
the typing says the view is live, and a live view is into one of the
thread's own buffers (`ViewAt`).  So two threads touch one address only if
it is in both their trees, which the configuration invariant rules out. -/

namespace A3
open A2

theorem OwnedId.st_eq {m m' : Mem} {i : Nat} (h : OwnedId m i) (hst : m'.st = m.st) : OwnedId m' i := by
  obtain ⟨x, t, hx, hi⟩ := h
  exact ⟨x, t, by unfold OwnedAt at *; rw [hst]; exact hx, hi⟩

theorem nodeAt_owned {m : Mem} {c : Nat} {n : Val} (h : NodeAt m c n) : ∀ i ∈ n.ids, OwnedId m i := by
  obtain ⟨x, t, hx, hs, _⟩ := h
  exact fun i hi => ⟨x, t, hx, Sub.ids hs i hi⟩

theorem dataAt_owned {m : Mem} {d : Nat} {n : Val} (h : DataAt m d n) : ∀ i ∈ n.ids, OwnedId m i := by
  obtain ⟨x, t, hx, hs, _⟩ := h
  exact fun i hi => ⟨x, t, hx, Sub.ids hs i hi⟩

theorem rootNode_owned {m : Mem} {r : Var} {n : Val} (h : RootNode m r n) :
    ∀ i ∈ n.ids, OwnedId m i := by
  rcases h with ⟨T, hT, htop⟩ | ⟨v, c, _, _, hn⟩ | ⟨v, d, o, l, _, _, hn⟩
  · exact fun i hi => ⟨r, T, hT, Sub.ids (Top.sub htop) i hi⟩
  · exact nodeAt_owned hn
  · exact dataAt_owned hn

/-- A valid view is into a buffer of one of the thread's own trees. -/
theorem viewAt_owned {m : Mem} {dep : Dep} {d o l : Nat} {t : Ty} (h : ViewAt m dep d o l t) :
    OwnedId m d := by
  obtain ⟨n0, c, es, hr, hk, _, _⟩ := h
  have hd : d ∈ (Val.node t c d es).ids := by simp [Val.ids]
  rcases hk with ⟨_, he⟩ | ⟨_, hb⟩
  · rw [he] at hd; exact rootNode_owned hr d hd
  · exact rootNode_owned hr d (Sub.ids (Below.sub hb) d hd)

theorem vecOf_owned {m : Mem} {x : Var} {t : Ty} {c d : Nat} {es : List Val} (h : VecOf m x t c d es) :
    OwnedId m c ∧ OwnedId m d := by
  obtain ⟨_, _, h | ⟨_, hn⟩⟩ := h
  · exact ⟨⟨x, _, h, by simp [Val.ids]⟩, ⟨x, _, h, by simp [Val.ids]⟩⟩
  · exact ⟨nodeAt_owned hn c (by simp [Val.ids]), nodeAt_owned hn d (by simp [Val.ids])⟩

theorem eReads_owned {m : Mem} {e : Expr} {i : Nat} (h : EReads m e i) : OwnedId m i := by
  induction h with
  | len hv => exact (vecOf_owned hv).1
  | addL _ ih => exact ih
  | addR _ ih => exact ih
  | ltL _ ih => exact ih
  | ltR _ ih => exact ih

/-- A panicking step only unbinds: every slot it leaves was there before. -/
theorem Step.panic_st {P : Prog} {m m1 : Mem} {s : Stmt} (h : Step P m s (.panic m1)) :
    ∀ v sl, m1.st v = some sl → m.st v = some sl := by
  generalize hr : Res.panic m1 = r at h
  induction h generalizing m1 with
  | seqP _ ih => cases hr; exact ih rfl
  | letvP _ => cases hr; exact fun _ _ h => h
  | scopeP _ _ _ ih =>
    cases hr
    intro v sl hv
    simp only [Mem.remove, upd] at hv
    split at hv
    · cases hv
    · exact ih rfl v sl hv
  | rbindP _ _ ih =>
    cases hr
    intro v sl hv
    simp only [Mem.remove, upd] at hv
    split at hv
    · cases hv
    · exact ih rfl v sl hv
  | frozenP _ ih => cases hr; exact ih rfl
  | assignP _ => cases hr; exact fun _ _ h => h
  | panic => cases hr; exact fun _ _ h => h
  | letdP _ => cases hr; exact fun _ _ h => h
  | scopeDPMoved _ _ ih =>
    cases hr
    intro v sl hv
    simp only [Mem.remove, upd] at hv
    split at hv
    · cases hv
    · exact ih rfl v sl hv
  | _ => cases hr

/-! ### Typing at the touched statement -/

/-- The statement is typed in a context the store agrees with. -/
def TypedAt (P : Prog) (m : Mem) (s : Stmt) : Prop := ∃ Γ F Δ, StmtT P Γ F s Δ ∧ MInv m Γ

theorem TypedAt.of_threadOK {P : Prog} {m : Mem} {s : Stmt} (h : ThreadOK P m s) : TypedAt P m s := by
  obtain ⟨Γ, F, Δ, ht, hi, _⟩ := h
  exact ⟨Γ, F, Δ, ht, hi.toMInv⟩

theorem TypedAt.seq {P : Prog} {m : Mem} {a b : Stmt} (h : TypedAt P m (.seq a b)) : TypedAt P m a := by
  obtain ⟨Γ, F, Δ, ht, hi⟩ := h
  generalize hs : Stmt.seq a b = s at ht
  induction ht with
  | seq _ ha _ _ _ => cases hs; exact ⟨_, _, _, ha, hi⟩
  | sub hw _ _ ih => exact ih (hi.weaker hw) hs
  | _ => cases hs

theorem TypedAt.scope {P : Prog} {m : Mem} {x : Var} {s : Stmt} (h : TypedAt P m (.scope x s)) :
    TypedAt P m s := by
  obtain ⟨Γ, F, Δ, ht, hi⟩ := h
  generalize hs : Stmt.scope x s = s0 at ht
  induction ht with
  | scope _ _ hb _ _ => cases hs; exact ⟨_, _, _, hb, hi⟩
  | sub hw _ _ ih => exact ih (hi.weaker hw) hs
  | _ => cases hs

theorem TypedAt.rbind {P : Prog} {m : Mem} {p : Var} {s : Stmt} (h : TypedAt P m (.rbind p s)) :
    TypedAt P m s := by
  obtain ⟨Γ, F, Δ, ht, hi⟩ := h
  generalize hs : Stmt.rbind p s = s0 at ht
  induction ht with
  | rbind _ _ _ _ _ hb _ _ => cases hs; exact ⟨_, _, _, hb, hi⟩
  | sub hw _ _ ih => exact ih (hi.weaker hw) hs
  | _ => cases hs

theorem TypedAt.frozen {P : Prog} {m : Mem} {z : List Var} {s : Stmt} (h : TypedAt P m (.frozen z s)) :
    TypedAt P m s := by
  obtain ⟨Γ, F, Δ, ht, hi⟩ := h
  generalize hs : Stmt.frozen z s = s0 at ht
  induction ht with
  | frozen hb _ _ => cases hs; exact ⟨_, _, _, hb, hi⟩
  | sub hw _ _ ih => exact ih (hi.weaker hw) hs
  | _ => cases hs

theorem TypedAt.catchR {P : Prog} {m : Mem} {x : Var} {m0 : Mem} {s : Stmt}
    (h : TypedAt P m (.catchR x m0 s)) : TypedAt P m s := by
  obtain ⟨Γ, F, Δ, ht, hi⟩ := h
  generalize hs : Stmt.catchR x m0 s = s0 at ht
  induction ht with
  | catchR _ hb _ _ _ _ => cases hs; exact ⟨_, _, _, hb, hi⟩
  | sub hw _ _ ih => exact ih (hi.weaker hw) hs
  | _ => cases hs

theorem TypedAt.scopeD {P : Prog} {m : Mem} {x : Var} {f : Nat} {s : Stmt}
    (h : TypedAt P m (.scopeD x f s)) : TypedAt P m s := by
  obtain ⟨Γ, F, Δ, ht, hi⟩ := h
  generalize hs : Stmt.scopeD x f s = s0 at ht
  induction ht with
  | scopeD _ _ hb _ _ _ _ _ => cases hs; exact ⟨_, _, _, hb, hi⟩
  | sub hw _ _ ih => exact ih (hi.weaker hw) hs
  | _ => cases hs

/-- What a typed right-hand side's `sat` reads: a live slice binding. -/
def SatLive (m : Mem) (r : Rhs) : Prop :=
  ∀ y i, r = .sat y i → ∃ Γ E t, MInv m Γ ∧ Γ y = some E ∧ E.live = true ∧ E.ty = .slice t

theorem rhsT_satLive {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {F : List Var} {r : Rhs} {E : Entry} {Γ1 : Ctx}
    (h : RhsT Γ F r E Γ1) : SatLive m r := by
  intro y i hr
  subst hr
  cases h with
  | sat hy hl ht _ => exact ⟨Γ, _, _, hi, hy, hl, ht⟩

theorem TypedAt.letv_sat {P : Prog} {m : Mem} {x : Var} {r : Rhs} {s : Stmt}
    (h : TypedAt P m (.letv x r s)) : SatLive m r := by
  obtain ⟨Γ, F, Δ, ht, hi⟩ := h
  generalize hs : Stmt.letv x r s = s0 at ht
  induction ht with
  | letv _ _ _ hr _ _ _ => cases hs; exact rhsT_satLive hi hr
  | sub hw _ _ ih => exact ih (hi.weaker hw) hs
  | _ => cases hs

theorem TypedAt.letd_sat {P : Prog} {m : Mem} {x : Var} {f : Nat} {r : Rhs} {s : Stmt}
    (h : TypedAt P m (.letd x f r s)) : SatLive m r := by
  obtain ⟨Γ, F, Δ, ht, hi⟩ := h
  generalize hs : Stmt.letd x f r s = s0 at ht
  induction ht with
  | letd _ _ _ hr _ _ _ _ _ _ _ => cases hs; exact rhsT_satLive hi hr
  | sub hw _ _ ih => exact ih (hi.weaker hw) hs
  | _ => cases hs

theorem TypedAt.assign_sat {P : Prog} {m : Mem} {x : Var} {r : Rhs} (h : TypedAt P m (.assign x r)) :
    SatLive m r := by
  obtain ⟨Γ, F, Δ, ht, hi⟩ := h
  generalize hs : Stmt.assign x r = s0 at ht
  induction ht with
  | assign _ _ _ hr _ _ _ _ => cases hs; exact rhsT_satLive hi hr
  | sub hw _ _ ih => exact ih (hi.weaker hw) hs
  | _ => cases hs

/-- A live slice binding's view is into a buffer of the thread's own trees. -/
theorem sat_owned {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} {t : Ty}
    (hy : Γ y = some E) (hl : E.live = true) (ht : E.ty = .slice t) {d o l : Nat}
    (hv : m.st y = some ⟨false, some (.view d o l)⟩) : OwnedId m d := by
  obtain ⟨sl, hsl, _, hok⟩ := hi.slot y E hy
  rw [hv] at hsl
  cases hsl
  obtain ⟨hown, _, hbor⟩ := hok
  obtain ⟨v, hv', hval⟩ := hbor hown.symm hl
  cases hv'
  rw [ht] at hval
  obtain ⟨d', o', l', he, dep, _, hva⟩ := valOK_slice.mp hval
  cases he
  exact viewAt_owned hva

theorem rTouch_owned {m m1 : Mem} {r : Rhs} {i : Nat} {w : Bool} (h : RTouch m r i w)
    (hst : m1.st = m.st) (hsat : SatLive m1 r) : OwnedId m i := by
  cases h with
  | expr he => exact eReads_owned he
  | atC hv => exact (vecOf_owned hv).1
  | atD hv => exact (vecOf_owned hv).2
  | atI he => exact eReads_owned he
  | view hv => exact (vecOf_owned hv).1
  | sat hv =>
    obtain ⟨Γ, E, t, hi, hy, hl, ht⟩ := hsat _ _ rfl
    exact (sat_owned hi hy hl ht (by rw [hst]; exact hv)).st_eq hst.symm
  | satI he => exact eReads_owned he
  | popC hy => exact ⟨_, _, hy, by simp [Val.ids]⟩
  | popD hy => exact ⟨_, _, hy, by simp [Val.ids]⟩

/-- **Every address a thread's next step touches is in one of its own trees.**
    `m` is the store the step runs on; `m1` has its bindings and is where the
    thread's typing holds (its own part of the address space). -/
theorem touch_owned {P : Prog} {m m1 : Mem} {s : Stmt} {i : Nat} {w : Bool} (h : Touch P m s i w)
    (hst : m1.st = m.st) (hty : TypedAt P m1 s) : OwnedId m i := by
  induction h with
  | seq _ ih => exact ih hty.seq
  | letv hr => exact rTouch_owned hr hst hty.letv_sat
  | letd hr => exact rTouch_owned hr hst hty.letd_sat
  | scopeD _ ih => exact ih hty.scopeD
  | assign hr => exact rTouch_owned hr hst hty.assign_sat
  | assignDrop hx hi => exact ⟨_, _, hx, hi⟩
  | ite he => exact eReads_owned he
  | pushC hx => exact ⟨_, _, hx, by simp [Val.ids]⟩
  | pushD hx => exact ⟨_, _, hx, by simp [Val.ids]⟩
  | free hx hi => exact ⟨_, _, hx, hi⟩
  | scope _ ih => exact ih hty.scope
  | scopeEnd hx hi => exact ⟨_, _, hx, hi⟩
  | scopeUnwind hs hx hi => exact ⟨_, _, Step.panic_st hs _ _ hx, hi⟩
  | rbind _ ih => exact ih hty.rbind
  | frozen _ ih => exact ih hty.frozen
  | catchR _ ih => exact ih hty.catchR

end A3
