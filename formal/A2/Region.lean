import A2.Typing

/-! A2 — AGORA-937: a parameter's region.

A view-holding parameter `p` has a region `π p`: what the views its value
holds point into, the caller's memory. It is a root of the callee's own
typing only: where the call places the body, the lift substitutes what the
argument depends on for it (`RSetup.subD`), so no context the memory
invariant is stated of holds a region (`MInv.noRegion`). -/

namespace A2

/-- **After a `.replace` on a root, nothing depending on it is live**: every
    binding that reaches `r` (and holds memory, or is a borrowed parameter)
    is ended. Applied to a region `π j`, which no statement of the body
    names (its index is not below `fn.nvars`), it says nothing reads the
    region after a change through it (AGORA-937, condition 3). -/
theorem kill_replace_pi_dead {hv : Bool} {r : Var} {Γ : Ctx} {v : Var} {E : Entry}
    (h : kill .replace hv r Γ v = some E) (hn : E.ty ≠ .int ∨ E.mode = .rootb)
    (hr : r ∈ roots E.vdeps) : E.live = false := by
  unfold kill at h
  obtain ⟨E0, h0, rfl⟩ := Option.map_eq_some_iff.mp h
  have hhit : hits .replace hv r E0 = true := by
    by_cases hh : hits .replace hv r E0 = true
    · exact hh
    · have hk : killE .replace hv r E0 = E0 := by simp [killE, hh]
      rw [hk] at hn hr
      obtain ⟨d, hd, hdr⟩ := List.mem_map.mp hr
      unfold hits
      simp only [Bool.and_eq_true, Bool.or_eq_true, bne_iff_ne, ne_eq, beq_iff_eq, List.any_eq_true]
      exact ⟨by rcases hn with hn | hn <;> simp [hn], d, hd, hdr, by cases d.kind <;> rfl⟩
  simp [killE, hhit]

end A2
