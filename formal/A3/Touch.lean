import A3.Thread

/-! A3.0 — what a thread's next step touches is its own.

Every address `Touch` names is in a tree one of the thread's owned slots
holds, or (A3.1) in a live block's payload that one of its values reaches:
the rules read it off `VecOf`, `NodeAt`, `DataAt`, owned slots and shares,
which search the thread's own trees and the payloads its handles and shares
point into.  A `sat` through a view finds its buffer only through the view's
address; there the typing says the view is live, and a live view is into
one of the thread's own buffers or a payload (`ViewAt`).  Every write is to
an owned tree.  So two threads touch one address only if it is in both
their trees, which the configuration invariant rules out, or if it is a
payload address, which both only read. -/

namespace A3
open A2

theorem OwnedId.st_eq {m m' : Mem} {i : Nat} (h : OwnedId m i) (hst : m'.st = m.st) : OwnedId m' i := by
  obtain ⟨x, t, hx, hi⟩ := h
  exact ⟨x, t, by unfold OwnedAt at *; rw [hst]; exact hx, hi⟩

/-- A3.1: a payload address the store's slots reach: it lies in the payload
    of a block one of the thread's values refers to, through the blocks. -/
def PaySeen (m : Mem) (i : Nat) : Prop :=
  ∃ k bl, m.blk k = some bl ∧ i ∈ bl.rd.ids ∧ Reached m.vals m.blk k

/-- What a thread may read: an address of its own trees, or one of a payload
    its values reach. -/
def Seen (m : Mem) (i : Nat) : Prop := OwnedId m i ∨ PaySeen m i

/-- A node found through a handle that a slot holds: in an owned tree, or in a
    payload the handle reaches into. -/
theorem nodeAt_seen {m : Mem} {y : Var} {o : Bool} {c : Nat} (hy : m.st y = some ⟨o, some (.href c)⟩)
    {n : Val} (h : NodeAt m c n) : ∀ i ∈ n.ids, Seen m i := by
  rcases h with ⟨x, t, hx, hs, _⟩ | ⟨k, bl, hk, hs, ty, d, es, rfl⟩
  · exact fun i hi => .inl ⟨x, t, hx, Sub.ids hs i hi⟩
  · exact fun i hi => .inr ⟨k, bl, hk, Sub.ids hs i hi,
      .root ⟨y, o, hy⟩ (Or.inr ⟨bl, hk, Or.inl ⟨c, Sub.refl _, Sub.ids hs c (by simp)⟩⟩)⟩

theorem vecOf_seen {m : Mem} {x : Var} {t : Ty} {c d : Nat} {es : List Val}
    (h : VecOf m x t c d es) : Seen m c ∧ Seen m d := by
  obtain ⟨_, _, h | ⟨hx, hn⟩⟩ := h
  · exact ⟨.inl ⟨x, _, h, by simp [Val.ids]⟩, .inl ⟨x, _, h, by simp [Val.ids]⟩⟩
  · exact ⟨nodeAt_seen hx hn c (by simp [Val.ids]), nodeAt_seen hx hn d (by simp [Val.ids])⟩

theorem eReads_seen {m : Mem} {e : Expr} {i : Nat} (h : EReads m e i) : Seen m i := by
  induction h with
  | len hv => exact (vecOf_seen hv).1
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
  | scopeLP _ _ _ ih =>
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

theorem TypedAt.scopeL {P : Prog} {m : Mem} {k : Nat} {t : Ty} {x : Var} {s : Stmt}
    (h : TypedAt P m (.scopeL k t x s)) : TypedAt P m s := by
  obtain ⟨Γ, F, Δ, ht, hi⟩ := h
  generalize hs : Stmt.scopeL k t x s = s0 at ht
  induction ht with
  | scopeL _ _ hb _ _ => cases hs; exact ⟨_, _, _, hb, hi⟩
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

/-- A live slice binding's view is into a buffer of the thread's own trees,
    or (A3.1) into a payload, which the view itself reaches. -/
theorem sat_seen {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} {t : Ty}
    (hy : Γ y = some E) (hl : E.live = true) (ht : E.ty = .slice t) {d o l : Nat}
    (hv : m.st y = some ⟨false, some (.view d o l)⟩) : Seen m d := by
  obtain ⟨sl, hsl, _, hok⟩ := hi.slot y E hy
  rw [hv] at hsl
  cases hsl
  obtain ⟨hown, _, hbor⟩ := hok
  obtain ⟨v, hv', hval⟩ := hbor hown.symm hl
  cases hv'
  rw [ht] at hval
  obtain ⟨d', o', l', he, dep, _, hva⟩ := valOK_slice.mp hval
  cases he
  rcases hva.owned_rd with ⟨x, T, hT, hd⟩ | ⟨k, bl, hk, hd⟩
  · exact .inl ⟨x, T, hT, hd⟩
  · exact .inr ⟨k, bl, hk, hd, .root ⟨y, false, hv⟩ (Or.inr ⟨bl, hk, Or.inr ⟨d, o, l, Sub.refl _, hd⟩⟩)⟩

theorem Seen.of_st {m m1 : Mem} {i : Nat} (h : Seen m1 i) (hst : m1.st = m.st) (hb : m1.blk = m.blk) :
    Seen m i := by
  have hv : m1.vals = m.vals := by funext v; simp only [Mem.vals, hst]
  rcases h with h | ⟨k, bl, hk, hi, hr⟩
  · exact .inl (h.st_eq hst.symm)
  · rw [hv, hb] at hr; rw [hb] at hk; exact .inr ⟨k, bl, hk, hi, hr⟩

theorem rTouch_seen {m m1 : Mem} {r : Rhs} {i : Nat} {w : Bool} (h : RTouch m r i w)
    (hst : m1.st = m.st) (hb : m1.blk = m.blk) (hsat : SatLive m1 r) : OwnedId m i ∨ (w = false ∧ Seen m i) := by
  cases h with
  | expr he => exact .inr ⟨rfl, eReads_seen he⟩
  | atC hv => exact .inr ⟨rfl, (vecOf_seen hv).1⟩
  | atD hv => exact .inr ⟨rfl, (vecOf_seen hv).2⟩
  | atI he => exact .inr ⟨rfl, eReads_seen he⟩
  | view hv => exact .inr ⟨rfl, (vecOf_seen hv).1⟩
  | sat hv =>
    obtain ⟨Γ, E, t, hi, hy, hl, ht⟩ := hsat _ _ rfl
    exact .inr ⟨rfl, (sat_seen hi hy hl ht (by rw [hst]; exact hv)).of_st hst hb⟩
  | satI he => exact .inr ⟨rfl, eReads_seen he⟩
  | popC hy => exact .inl ⟨_, _, hy, by simp [Val.ids]⟩
  | popD hy => exact .inl ⟨_, _, hy, by simp [Val.ids]⟩
  | arcGet ha hk hi => exact .inr ⟨rfl, .inr ⟨_, _, hk, hi, .root ⟨_, _, ha⟩ (Or.inl ⟨some _, Sub.refl _⟩)⟩⟩
  | chanSend hy hi => exact .inl ⟨_, _, hy, hi⟩

/-- **What a thread's next step touches is its own**: an address in one of
    its own trees, or (A3.1) a payload address its values reach, which it
    only reads.  `m` is the store the step runs on; `m1` has its bindings
    and blocks and is where the thread's typing holds (its own part of the
    address space). -/
theorem touch_seen {P : Prog} {m m1 : Mem} {s : Stmt} {i : Nat} {w : Bool}
    (h : Touch P m s i w) (hst : m1.st = m.st) (hb : m1.blk = m.blk) (hty : TypedAt P m1 s) :
    OwnedId m i ∨ (w = false ∧ Seen m i) := by
  induction h with
  | seq _ ih => exact ih hty.seq
  | letv hr => exact rTouch_seen hr hst hb hty.letv_sat
  | letd hr => exact rTouch_seen hr hst hb hty.letd_sat
  | scopeD _ ih => exact ih hty.scopeD
  | assign hr => exact rTouch_seen hr hst hb hty.assign_sat
  | assignDrop hx hi => exact .inl ⟨_, _, hx, hi⟩
  | ite he => exact .inr ⟨rfl, eReads_seen he⟩
  | pushC hx => exact .inl ⟨_, _, hx, by simp [Val.ids]⟩
  | pushD hx => exact .inl ⟨_, _, hx, by simp [Val.ids]⟩
  | free hx hi => exact .inl ⟨_, _, hx, hi⟩
  | editC hn => exact .inl ⟨_, _, hn.2.2.1, hn.sub.ids _ (by simp [Val.ids])⟩
  | editD hn => exact .inl ⟨_, _, hn.2.2.1, hn.sub.ids _ (by simp [Val.ids])⟩
  | editFree hn _ ha => exact .inl ⟨_, _, hn.2.2.1, hn.sub.ids _ (ids_drop_sub ha)⟩
  | editI he => exact .inr ⟨rfl, eReads_seen he⟩
  | editSetFree hlt hn _ ha => exact .inl ⟨_, _, hn.2.2.1, hn.sub.ids _ (ids_get_sub hlt ha)⟩
  | editSetDrop _ _ _ hy ha => exact .inl ⟨_, _, hy, ha⟩
  | editSetI he => exact .inr ⟨rfl, eReads_seen he⟩
  | scope _ ih => exact ih hty.scope
  | scopeEnd hx hi => exact .inl ⟨_, _, hx, hi⟩
  | scopeUnwind hs hx hi => exact .inl ⟨_, _, Step.panic_st hs _ _ hx, hi⟩
  | rbind _ ih => exact ih hty.rbind
  | frozen _ ih => exact ih hty.frozen
  | catchR _ ih => exact ih hty.catchR
  | scopeL _ ih => exact ih hty.scopeL
  | scopeLEnd hx hi => exact .inl ⟨_, _, hx, hi⟩
  | scopeLUnwind hs hx hi => exact .inl ⟨_, _, Step.panic_st hs _ _ hx, hi⟩

end A3
