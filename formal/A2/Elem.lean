import A2.EditBV

/-! A2 — an element handed over (Agora #391): the elements of an owned `Vec`
in another order.

An owner's tree is read by membership: what a borrow, a view, a share or a
name finds in a node it finds among its elements, whatever their order, and
a view of the node's own buffer asks only for its length (`ViewAt`). So the
invariant does not see the order of an owned node's elements: permuting
them keeps `HeapOK`, `Covers` and `MInv` (`MInv.perm`). An element moved out
of the middle of a `Vec` is then a `vec_pop` of the element moved to the
end, and one put back at index `n` a `vec_push` whose element is then moved
to `n` (`withElem`, `insert`). -/

namespace A2

/-! ### An element handed over -/

/-- **An element handed over** (`withElem`): what depends on `v` ends
    (`kill .replace`: its borrows, which could reach the element, and what
    holds it by name), and element `n` moves out of `v`'s tree, as a
    `vec_pop` of it moved to the end does (`MInv.perm`, `rhs_pop`). -/
theorem elem_pres {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ) (hanch : RootbAnch Γ F)
    {v : Var} (hpin : NoPin Γ v) {E : Entry} {Γ1 : Ctx}
    (hr : RhsT (kill .replace false v Γ) F (.pop v) E Γ1)
    {t : Ty} {c d n : Nat} {es : List Val} (hn : n < es.length)
    (hT : m.st v = some ⟨true, some (.node t c d es)⟩) (hc : m.alloc c = true) (hd : m.alloc d = true) :
    RhsPost m (m.set v ⟨true, some (.node t c d (es.take n ++ es.drop (n + 1)))⟩) Γ Γ1 F ∧
    RhsOut (m.set v ⟨true, some (.node t c d (es.take n ++ es.drop (n + 1)))⟩) Γ1 E es[n] es[n].owns ∧
    (Covers m → CoversBut (m.set v ⟨true, some (.node t c d (es.take n ++ es.drop (n + 1)))⟩) es[n]
      es[n].owns) := by
  cases hr with
  | @pop _ E0 t0 hv hl hty hcan hvF hds =>
  have hmn := hpin.kills .replace false
  -- the kill: no memory changes
  have hk : RhsPost m m Γ (kill .replace false v Γ) F :=
    ⟨hi.kill_pin hanch hvF hmn, rfl, Nat.le_refl _, fun _ => rfl, fun _ _ => rfl,
      fun p Ep hp hm => by simp only [A2.kill, hp, Option.map_some]; rw [killE_rootb hanch hvF _ _ hmn hp hm],
      fun x => kill_dom .., fun x E1 h => kill_cmode h, (DKeep.refl Γ []).kill _ _ _, BlkLe.refl _⟩
  have hanch1 : RootbAnch (kill .replace false v Γ) F := hanch.kill _ _ _
  -- element `n` moved to the end
  have hp := perm_erase hn
  let m1 := m.set v ⟨true, some (.node t c d (es.take n ++ es.drop (n + 1) ++ [es[n]]))⟩
  have hT1 : m1.st v = some ⟨true, some (.node t c d (es.take n ++ es.drop (n + 1) ++ [es[n]]))⟩ := by
    simp [m1]
  have hst1 : ∀ o, o ≠ v → m1.st o = m.st o := fun o ho => by simp [m1, upd_ne _ _ ho]
  have hpm : RhsPost m m1 (kill .replace false v Γ) (kill .replace false v Γ) F :=
    ⟨hk.inv.perm hanch1 hvF hT hp, rfl, Nat.le_refl _,
      fun o => by
        by_cases ho : o = v
        · subst ho; rw [hT1, hT]; rfl
        · rw [hst1 o ho],
      fun o ho => hst1 o (fun e => hvF (e ▸ ho)), fun _ _ h _ => h, fun _ => rfl,
      fun _ E1 h => ⟨E1, h, rfl, rfl⟩, DKeep.refl _ [], BlkLe.refl _⟩
  -- the pop of it
  obtain ⟨post, out⟩ := rhs_pop hpm.inv hanch1 hv hl hty hcan hvF hT1 hds
  have hm2 : m1.set v ⟨true, some (.node t c d (es.take n ++ es.drop (n + 1)))⟩ =
      m.set v ⟨true, some (.node t c d (es.take n ++ es.drop (n + 1)))⟩ := Mem.set_set _ _ _ _
  have he : EvalR m1 (.pop v) (.ok es[n] es[n].owns
      (m1.set v ⟨true, some (.node t c d (es.take n ++ es.drop (n + 1)))⟩)) := EvalR.pop hT1 hc hd
  refine ⟨hk.trans (hpm.trans (hm2 ▸ post)), hm2 ▸ out, fun hcv => ?_⟩
  have := covers_evalR (hcv.perm hT hp) he
  rwa [hm2] at this

end A2
