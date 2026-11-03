import A2.Leak

/-! A2 — a panic unwinds: each scope it leaves drops what it owns, so the
store it leaves has exactly the bindings outside the frames it crossed, one
owner per allocation, and nothing unowned (§7.2). -/

namespace A2

theorem HeapOK.remove_bor {m : Mem} (hh : HeapOK m) {p : Var} {w : Option Val}
    (hp : m.st p = some ⟨false, w⟩) : HeapOK (m.remove p) := by
  have := hh.remove hp DropSlot.borrowed
  exact this

/-- A3.2: what `x`'s slot gives back to a lock owns its addresses once, and
    none of them is another slot's or a payload's: the tree `x` owns, or an
    integer. -/
theorem Giveable.ids {m : Mem} (hh : HeapOK m) {x : Var} {o : Bool} {v : Val} {t : Ty}
    (hx : m.st x = some ⟨o, some v⟩) (hg : Giveable t ⟨o, some v⟩) :
    v.ids.Nodup ∧ (∀ i ∈ v.ids, m.alloc i = true ∧ i < m.nid) ∧
    (∀ y U, y ≠ x → OwnedAt m y U → ∀ i ∈ v.ids, i ∉ U.ids) ∧ (∀ i ∈ v.ids, ¬ PayAddr m i) := by
  cases o with
  | true =>
    have hT : OwnedAt m x v := hx
    exact ⟨hh.nodup x v hT, hh.alloc x v hT, fun y U hyx hU i hi => hh.disj x y v U (Ne.symm hyx) hT hU i hi,
      fun i hi => hh.notPay hT hi⟩
  | false =>
    cases v with
    | int n => simp
    | _ => simp [Giveable] at hg

/-- A3.2: a lock's payload given back: the block owns the tree `x` gave
    (it was in no other tree and no payload), and `x`'s slot is gone. -/
theorem HeapOK.release_put {m : Mem} (hh : HeapOK m) {k : Nat} {t : Ty} {x : Var} {o : Bool} {v : Val}
    (hx : m.st x = some ⟨o, some v⟩) (hg : Giveable t ⟨o, some v⟩) (hk : m.blk k = some ⟨t, .lock, none⟩) :
    HeapOK ({ m with blk := upd m.blk k (some ⟨t, .lock, some v⟩) }.remove x) := by
  obtain ⟨hnd, hal, hdis, hnp⟩ := Giveable.ids hh hx hg
  have hown : ∀ o U, OwnedAt ({ m with blk := upd m.blk k (some ⟨t, .lock, some v⟩) }.remove x) o U →
      o ≠ x ∧ OwnedAt m o U := fun o U h => ownedAt_remove.mp h
  have hkey := hh.bkey k _ hk
  have hcases : ∀ k' bl, ({ m with blk := upd m.blk k (some ⟨t, .lock, some v⟩) }.remove x).blk k' = some bl →
      (k' = k ∧ bl = ⟨t, .lock, some v⟩) ∨ (k' ≠ k ∧ m.blk k' = some bl) := by
    intro k' bl h
    by_cases he : k' = k
    · subst he; simp [upd] at h; exact Or.inl ⟨rfl, h.symm⟩
    · exact Or.inr ⟨he, by simpa [upd, he] using h⟩
  refine ⟨fun o U h => hh.nodup o U (hown o U h).2,
    fun o1 o2 U1 U2 hne h1 h2 => hh.disj o1 o2 U1 U2 hne (hown o1 U1 h1).2 (hown o2 U2 h2).2,
    fun o U h => hh.alloc o U (hown o U h).2, fun o U h => hh.self o U (hown o U h).2, ?_, hh.views.setLock hk (hh.views.noView hk) _⟩
  intro k' bl hk'
  rcases hcases k' bl hk' with ⟨rfl, rfl⟩ | ⟨hne, h⟩
  · refine ⟨hkey, hnd, fun i hi => ⟨(hal i hi).1, (hal i hi).2,
      fun y U hU => hdis y U (hown y U hU).1 (hown y U hU).2 i hi, fun k'' bl'' hk'' h'' => ?_⟩⟩
    rcases hcases k'' bl'' h'' with ⟨rfl, _⟩ | ⟨_, h2⟩
    · exact absurd rfl hk''
    · exact fun hi' => hnp i hi ⟨k'', bl'', h2, hi'⟩
  · obtain ⟨hkey', hnd', hall⟩ := hh.blk k' bl h
    refine ⟨hkey', hnd', fun i hi => ?_⟩
    obtain ⟨ha, hlt, hsl, hoth⟩ := hall i hi
    refine ⟨ha, hlt, fun y U hU => hsl y U (hown y U hU).2, fun k'' bl'' hk'' h'' => ?_⟩
    rcases hcases k'' bl'' h'' with ⟨rfl, rfl⟩ | ⟨_, h2⟩
    · exact fun hiv => hnp i hiv ⟨k', bl, h, hi⟩
    · exact hoth k'' bl'' hk'' h2

/-- ... and every live address is still covered: what `x` owned is now the
    block's payload. -/
theorem covers_release_put {m : Mem} (hc : Covers m) {k : Nat} {t : Ty} {x : Var} {o : Bool} {v : Val}
    (hx : m.st x = some ⟨o, some v⟩) (hk : m.blk k = some ⟨t, .lock, none⟩) :
    Covers ({ m with blk := upd m.blk k (some ⟨t, .lock, some v⟩) }.remove x) := by
  intro i hi
  have hi0 : m.alloc i = true := hi
  rcases hc i hi0 with ⟨y, U, hU, hiU⟩ | ⟨k', bl, hk', hik⟩
  · by_cases hyx : y = x
    · subst hyx; unfold OwnedAt at hU; rw [hx] at hU; cases hU
      exact Or.inr ⟨k, ⟨t, .lock, some v⟩, by simp [upd], hiU⟩
    · exact Or.inl ⟨y, U, ownedAt_remove.mpr ⟨hyx, hU⟩, hiU⟩
  · have hne : k' ≠ k := fun e => by subst e; rw [hk] at hk'; cases hk'; simp [Blk.tree] at hik
    exact Or.inr ⟨k', bl, by simp [upd, hne, hk'], hik⟩

/-- A slot removed and its tree not freed: the heap stays one owner per
    address (its tree has none for now). -/
theorem HeapOK.remove_keep {m : Mem} (hh : HeapOK m) (x : Var) : HeapOK (m.remove x) := by
  have hown : ∀ o U, OwnedAt (m.remove x) o U → o ≠ x ∧ OwnedAt m o U := fun o U h => ownedAt_remove.mp h
  exact ⟨fun o U h => hh.nodup o U (hown o U h).2,
    fun o1 o2 U1 U2 hne h1 h2 => hh.disj o1 o2 U1 U2 hne (hown o1 U1 h1).2 (hown o2 U2 h2).2,
    fun o U h => hh.alloc o U (hown o U h).2, fun o U h => hh.self o U (hown o U h).2,
    hh.blk.frame rfl (Nat.le_refl _) (fun _ _ => rfl) (fun o U h i hi => hh.notPay (hown o U h).2 hi),
    hh.views⟩

/-- **A3.2: the end of a lock scope that gives the payload back.** `x`'s slot
    is gone and what borrows from it ends, as at a scope's end; its tree,
    not freed, becomes the lock block's payload: well-formed at the block's
    type, its shares naming blocks. -/
theorem step_release {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ) (hanch : RootbAnch Γ F)
    {x : Var} {E : Entry} (hx : Γ x = some E) (hnrb : E.mode ≠ .rootb) (hxF : x ∉ F) (hpin : EndOK Γ x)
    {k : Nat} {t : Ty} (hty : E.ty = t) {o : Bool} {v : Val} (hsl : m.st x = some ⟨o, some v⟩)
    (hg : Giveable t ⟨o, some v⟩) (hk : m.blk k = some ⟨t, .lock, none⟩) :
    MInv ({ m with blk := upd m.blk k (some ⟨t, .lock, some v⟩) }.remove x) (exitScope x Γ) := by
  have h0 : MInv (m.remove x) (exitScope x Γ) :=
    hi.change hanch hx hxF (hpin.1.kills _ _) hnrb (fun o ho => by simp [upd_ne _ _ ho])
      (hi.heap.remove_keep x) rfl
      (fun k hk => by cases k <;> simp [Eff.kills] at hk) (show _ = none by simp) hpin.2.1 (fun _ => hpin.2.2)
      (fun _ => rfl) (fun _ _ h => by cases h)
  obtain ⟨sl, hsl', _, hslot⟩ := hi.slot x E hx
  rw [hsl] at hsl'; cases hsl'
  have hwv : WFv t v ∧ SharesOK m t v := by
    cases o with
    | true =>
      obtain ⟨hown0, hown, _⟩ := hslot
      have hos : E.mode.ownSlot = true := by rw [← hown0]
      obtain ⟨_, hwf, _⟩ := hown hos
      have hsh := hi.shares x E _ v hx hsl rfl rfl
      rw [hty] at hwf hsh
      exact ⟨hwf v rfl, hsh⟩
    | false =>
      cases v with
      | int n => simp [Giveable] at hg; subst hg; exact ⟨.int, SharesOK.of_noArc rfl⟩
      | _ => simp [Giveable] at hg
  obtain ⟨htok, hvf, _, hna⟩ := hi.blocks k _ hk
  have hb : BlkLe m.blk (upd m.blk k (some ⟨t, .lock, some v⟩)) := BlkLe.setLock hk _
  refine h0.grow rfl (hi.heap.release_put hsl hg hk) (Nat.le_refl _) hb ?_
  intro k' bl hk'
  by_cases he : k' = k
  · subst he; simp [upd] at hk'; subst hk'
    exact ⟨htok, hvf, fun p hp => by cases hp; exact ⟨hwv.1, hwv.2.grow hb⟩, fun _ => hna rfl⟩
  · have h' : m.blk k' = some bl := by simpa [upd, he] using hk'
    obtain ⟨h1, h2, h3, h4⟩ := hi.blocks k' bl h'
    exact ⟨h1, h2, fun p hp => ⟨(h3 p hp).1, (h3 p hp).2.grow hb⟩, h4⟩

theorem Release.heap {m m' : Mem} {k : Nat} {t : Ty} {x : Var} (h : Release m k t x m') (hh : HeapOK m) :
    HeapOK m' := by
  cases h with
  | put hsl hg hk => exact hh.release_put hsl hg hk
  | drop _ hsl hd => exact hh.remove hsl hd

theorem Release.covers {m m' : Mem} {k : Nat} {t : Ty} {x : Var} (h : Release m k t x m') (hc : Covers m) :
    Covers m' := by
  cases h with
  | put hsl _ hk => exact covers_release_put hc hsl hk
  | drop _ hsl hd => exact covers_remove hc hsl hd

theorem Release.st {m m' : Mem} {k : Nat} {t : Ty} {x : Var} (h : Release m k t x m') : m'.st = upd m.st x none := by
  cases h <;> rfl

theorem Release.nv {m m' : Mem} {k : Nat} {t : Ty} {x : Var} (h : Release m k t x m') : m'.nv = m.nv := by
  cases h <;> rfl

theorem Release.nid {m m' : Mem} {k : Nat} {t : Ty} {x : Var} (h : Release m k t x m') : m'.nid = m.nid := by
  cases h <;> rfl

/-- What a panic leaves (A3.2: a lock scope it unwinds gives its payload
    back, so a lock block's payload may have come back). -/
theorem panic_unwind {P : Prog} {m m1 : Mem} {s : Stmt} (hst : Step P m s (.panic m1))
    (hh : HeapOK m) (hc : Covers m) (hnd : s.spine.Nodup) :
    (∀ v, v ∉ s.spine → m1.st v = m.st v) ∧ (∀ v ∈ s.spine, m1.st v = none) ∧
    HeapOK m1 ∧ Covers m1 ∧ m1.nv = m.nv ∧ m1.nid = m.nid ∧ m1.blk = m.blk := by
  generalize hr : Res.panic m1 = r at hst
  induction hst generalizing m1 with
  | letvP _ => cases hr; exact ⟨fun _ _ => rfl, fun v hv => by simp [Stmt.spine] at hv, hh, hc, rfl, rfl, rfl⟩
  | assignP _ => cases hr; exact ⟨fun _ _ => rfl, fun v hv => by simp [Stmt.spine] at hv, hh, hc, rfl, rfl, rfl⟩
  | panic => cases hr; exact ⟨fun _ _ => rfl, fun v hv => by simp [Stmt.spine] at hv, hh, hc, rfl, rfl, rfl⟩
  | seqP _ ih => cases hr; exact ih hnd rfl
  | scopeP _ hsl hd ih =>
    rename_i x _ _ _ _
    cases hr
    simp only [Stmt.spine, List.nodup_cons] at hnd
    obtain ⟨h1, h2, hh1, hc1, hnv, hnid, hblk⟩ := ih hnd.2 rfl
    refine ⟨fun v hv => ?_, fun v hv => ?_, hh1.remove hsl hd, covers_remove hc1 hsl hd, hnv, hnid, hblk⟩
    · simp only [Stmt.spine, List.mem_cons, not_or] at hv
      simp [Mem.remove, upd_ne _ _ hv.1, h1 v hv.2]
    · simp only [Stmt.spine, List.mem_cons] at hv
      rcases hv with rfl | hv
      · simp [Mem.remove]
      · have hvx : v ≠ x := fun e => hnd.1 (e ▸ hv)
        simp [Mem.remove, upd_ne _ _ hvx, h2 v hv]
  | rbindP _ hp ih =>
    rename_i p _ _ _
    cases hr
    simp only [Stmt.spine, List.nodup_cons] at hnd
    obtain ⟨h1, h2, hh1, hc1, hnv, hnid, hblk⟩ := ih hnd.2 rfl
    refine ⟨fun v hv => ?_, fun v hv => ?_, hh1.remove_bor hp, covers_remove_bor hc1 hp, hnv, hnid, hblk⟩
    · simp only [Stmt.spine, List.mem_cons, not_or] at hv
      simp [Mem.remove, upd_ne _ _ hv.1, h1 v hv.2]
    · simp only [Stmt.spine, List.mem_cons] at hv
      rcases hv with rfl | hv
      · simp [Mem.remove]
      · have hvp : v ≠ p := fun e => hnd.1 (e ▸ hv)
        simp [Mem.remove, upd_ne _ _ hvp, h2 v hv]
  | frozenP _ ih => cases hr; exact ih hnd rfl
  | letdP _ => cases hr; exact ⟨fun _ _ => rfl, fun v hv => by simp [Stmt.spine] at hv, hh, hc, rfl, rfl, rfl⟩
  | scopeLP _ hsl hd ih =>
    rename_i x _ _ _ _
    cases hr
    simp only [Stmt.spine, List.nodup_cons] at hnd
    obtain ⟨h1, h2, hh1, hc1, hnv, hnid, hblk⟩ := ih hnd.2 rfl
    refine ⟨fun v hv => ?_, fun v hv => ?_, hh1.remove hsl hd, covers_remove hc1 hsl hd, hnv, hnid, hblk⟩
    · simp only [Stmt.spine, List.mem_cons, not_or] at hv
      simp [Mem.remove, upd_ne _ _ hv.1, h1 v hv.2]
    · simp only [Stmt.spine, List.mem_cons] at hv
      rcases hv with rfl | hv
      · simp [Mem.remove]
      · have hvx : v ≠ x := fun e => hnd.1 (e ▸ hv)
        simp [Mem.remove, upd_ne _ _ hvx, h2 v hv]
  | scopeDPMoved _ hsl ih =>
    rename_i x _ _ _
    cases hr
    simp only [Stmt.spine, List.nodup_cons] at hnd
    obtain ⟨h1, h2, hh1, hc1, hnv, hnid, hblk⟩ := ih hnd.2 rfl
    refine ⟨fun v hv => ?_, fun v hv => ?_, hh1.remove hsl DropSlot.moved,
      covers_remove hc1 hsl DropSlot.moved, hnv, hnid, hblk⟩
    · simp only [Stmt.spine, List.mem_cons, not_or] at hv
      simp [Mem.remove, upd_ne _ _ hv.1, h1 v hv.2]
    · simp only [Stmt.spine, List.mem_cons] at hv
      rcases hv with rfl | hv
      · simp [Mem.remove]
      · have hvx : v ≠ x := fun e => hnd.1 (e ▸ hv)
        simp [Mem.remove, upd_ne _ _ hvx, h2 v hv]
  | _ => cases hr

end A2
