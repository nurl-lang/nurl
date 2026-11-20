import A2.Semantics

/-! A2 — AGORA-937: a parameter's region, as the call snapshots it.

A view-holding parameter `p` has a region `π p`: what the views its value
holds point into, the caller's memory. Where the call places the body, the
region's slot holds a snapshot of those views: the views and handle
references the argument's value holds, copied, in a value that owns
nothing (`viewsOf_noown`). A move of the parameter, or a release of its
own buffer, does not touch the snapshot: what it points into is the
caller's. -/

namespace A2

mutual
/-- The views and handle references a value holds, through its elements,
    fields, payloads and a package's environment: what it points into
    without owning. -/
def Val.viewsOf : Val → List Val
  | .view d o l => [.view d o l]
  | .href c => [.href c]
  | .node _ _ _ es => viewsOfL es
  | .pair v w => v.viewsOf ++ w.viewsOf
  | .inl v => v.viewsOf
  | .inr v => v.viewsOf
  | .pkg _ _ _ env _ => env.viewsOf
  | _ => []
def viewsOfL : List Val → List Val
  | [] => []
  | e :: es => e.viewsOf ++ viewsOfL es
end

/-- A list of values, inline: nested pairs, ended by `0`. -/
def packVals : List Val → Val
  | [] => .int 0
  | v :: vs => .pair v (packVals vs)

/-- A region's snapshot of a value: the views and handle references it holds. -/
def Val.regionSnap (v : Val) : Val := packVals v.viewsOf

/-- Everything `viewsOf` collects is a view or a handle reference. -/
theorem mem_viewsOf : ∀ {v x : Val}, x ∈ v.viewsOf → (∃ d o l, x = .view d o l) ∨ ∃ c, x = .href c
  | .view d o l, x, h => by simp [Val.viewsOf] at h; exact Or.inl ⟨d, o, l, h⟩
  | .href c, x, h => by simp [Val.viewsOf] at h; exact Or.inr ⟨c, h⟩
  | .node _ _ _ es, x, h => by simp only [Val.viewsOf] at h; exact mem_viewsOfL h
  | .pair v w, x, h => by
      simp only [Val.viewsOf, List.mem_append] at h
      rcases h with h | h
      · exact mem_viewsOf h
      · exact mem_viewsOf h
  | .inl v, x, h => by simp only [Val.viewsOf] at h; exact mem_viewsOf h
  | .inr v, x, h => by simp only [Val.viewsOf] at h; exact mem_viewsOf h
  | .pkg _ _ _ env _, x, h => by simp only [Val.viewsOf] at h; exact mem_viewsOf h
  | .int _, x, h => by simp [Val.viewsOf] at h
  | .arc _ _, x, h => by simp [Val.viewsOf] at h
  | .lk _, x, h => by simp [Val.viewsOf] at h
  | .cell _, x, h => by simp [Val.viewsOf] at h
where
  mem_viewsOfL : ∀ {es : List Val} {x : Val}, x ∈ viewsOfL es →
      (∃ d o l, x = .view d o l) ∨ ∃ c, x = .href c
    | [], x, h => by simp [viewsOfL] at h
    | e :: es, x, h => by
        simp only [viewsOfL, List.mem_append] at h
        rcases h with h | h
        · exact mem_viewsOf h
        · exact mem_viewsOfL h

/-- Packed values own what they hold, and nothing else. -/
theorem packVals_ids : ∀ (vs : List Val), (packVals vs).ids = vs.flatMap Val.ids
  | [] => by simp [packVals, Val.ids]
  | v :: vs => by simp [packVals, Val.ids, packVals_ids vs]

/-- **A region's snapshot owns nothing**: no address of it is a block's
    control or buffer, so releasing it, or the frame it lives in, frees
    nothing (AGORA-937, `viewsOf_noown`). -/
theorem viewsOf_noown (v : Val) : v.regionSnap.ids = [] := by
  unfold Val.regionSnap
  rw [packVals_ids]
  refine List.eq_nil_of_subset_nil fun a ha => ?_
  obtain ⟨x, hx, ha⟩ := List.mem_flatMap.mp ha
  rcases mem_viewsOf hx with ⟨d, o, l, rfl⟩ | ⟨c, rfl⟩ <;> simp [Val.ids] at ha

end A2
