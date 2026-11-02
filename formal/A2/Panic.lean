import A2.Leak

/-! A2 — a panic unwinds: each scope it leaves drops what it owns, so the
store it leaves has exactly the bindings outside the frames it crossed, one
owner per allocation, and nothing unowned (§7.2). -/

namespace A2

theorem HeapOK.remove_bor {m : Mem} (hh : HeapOK m) {p : Var} {w : Option Val}
    (hp : m.st p = some ⟨false, w⟩) : HeapOK (m.remove p) := by
  have := hh.remove hp DropSlot.borrowed
  exact this

/-- What a panic leaves. -/
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
